-- =============================================================================
-- Migration 35: stock_count (جلسات جرد المخزون)
-- =============================================================================
-- الغرض:
--   * إنشاء جدولين لجلسات الجرد.
--   * RPCs لإنشاء/إدخال/اعتماد/إلغاء جلسة الجرد.
--   * عند الاعتماد: إدراج adjustment_in / adjustment_out في stock_movements،
--     والـ trigger apply_stock_movement يُحدّث inventory_balances تلقائيًا.
--   * RLS بنفس نمط inventory_balances.
--
-- المتطلبات المسبقة:
--   * CHECK constraint على stock_movements يدعم adjustment_in / adjustment_out.
--   * TRIGGER trg_stock_movements_apply موجود على stock_movements.
--   * الدوال المساعدة: is_company_member, has_permission.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) جدول stock_count_sessions
-- -----------------------------------------------------------------------------
create table if not exists public.stock_count_sessions (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references public.companies(id) on delete cascade,
  branch_id     uuid not null references public.branches(id) on delete restrict,
  status        text not null default 'draft'
                check (status in ('draft', 'confirmed', 'cancelled')),
  notes         text,
  started_at    timestamptz not null default now(),
  confirmed_at  timestamptz,
  cancelled_at  timestamptz,
  created_by    uuid,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists stock_count_sessions_company_idx
  on public.stock_count_sessions (company_id, status, started_at desc);

create index if not exists stock_count_sessions_branch_idx
  on public.stock_count_sessions (branch_id, started_at desc);

-- -----------------------------------------------------------------------------
-- 2) جدول stock_count_items
-- -----------------------------------------------------------------------------
create table if not exists public.stock_count_items (
  id                 uuid primary key default gen_random_uuid(),
  company_id         uuid not null references public.companies(id) on delete cascade,
  session_id         uuid not null references public.stock_count_sessions(id) on delete cascade,
  product_id         uuid not null references public.products(id) on delete restrict,
  unit_id            uuid,
  expected_quantity  numeric(15,4) not null default 0,
  actual_quantity    numeric(15,4),
  notes              text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (session_id, product_id)
);

create index if not exists stock_count_items_session_idx
  on public.stock_count_items (session_id);

create index if not exists stock_count_items_product_idx
  on public.stock_count_items (product_id);

-- -----------------------------------------------------------------------------
-- 3) RLS
-- -----------------------------------------------------------------------------
alter table public.stock_count_sessions enable row level security;
alter table public.stock_count_items    enable row level security;

drop policy if exists stock_count_sessions_select on public.stock_count_sessions;
create policy stock_count_sessions_select
  on public.stock_count_sessions
  for select
  using (public.is_company_member(company_id));

drop policy if exists stock_count_sessions_insert on public.stock_count_sessions;
create policy stock_count_sessions_insert
  on public.stock_count_sessions
  for insert
  with check (
    public.is_company_member(company_id)
    and public.has_permission(company_id, 'inventory.adjust')
  );

drop policy if exists stock_count_sessions_update on public.stock_count_sessions;
create policy stock_count_sessions_update
  on public.stock_count_sessions
  for update
  using (
    public.is_company_member(company_id)
    and public.has_permission(company_id, 'inventory.adjust')
  )
  with check (
    public.is_company_member(company_id)
    and public.has_permission(company_id, 'inventory.adjust')
  );

drop policy if exists stock_count_sessions_delete on public.stock_count_sessions;
create policy stock_count_sessions_delete
  on public.stock_count_sessions
  for delete
  using (
    public.is_company_member(company_id)
    and public.has_permission(company_id, 'inventory.adjust')
    and status = 'draft'
  );

drop policy if exists stock_count_items_select on public.stock_count_items;
create policy stock_count_items_select
  on public.stock_count_items
  for select
  using (public.is_company_member(company_id));

drop policy if exists stock_count_items_insert on public.stock_count_items;
create policy stock_count_items_insert
  on public.stock_count_items
  for insert
  with check (
    public.is_company_member(company_id)
    and public.has_permission(company_id, 'inventory.adjust')
  );

drop policy if exists stock_count_items_update on public.stock_count_items;
create policy stock_count_items_update
  on public.stock_count_items
  for update
  using (
    public.is_company_member(company_id)
    and public.has_permission(company_id, 'inventory.adjust')
  )
  with check (
    public.is_company_member(company_id)
    and public.has_permission(company_id, 'inventory.adjust')
  );

drop policy if exists stock_count_items_delete on public.stock_count_items;
create policy stock_count_items_delete
  on public.stock_count_items
  for delete
  using (
    public.is_company_member(company_id)
    and public.has_permission(company_id, 'inventory.adjust')
  );

-- -----------------------------------------------------------------------------
-- 4) RPC: create_stock_count_session
-- -----------------------------------------------------------------------------
-- ينشئ جلسة جديدة + بنودها من الأرصدة الحالية للفرع.
-- الجلسة تشمل كل منتج موجود في inventory_balances (أو الكمية = 0 لكل منتج نشط).
-- -----------------------------------------------------------------------------
create or replace function public.create_stock_count_session(
  p_company_id uuid,
  p_branch_id  uuid,
  p_notes      text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_session_id uuid;
  v_is_member  boolean;
  v_has_perm   boolean;
begin
  -- (a) فحص العضوية
  v_is_member := public.is_company_member(p_company_id);
  if v_is_member is distinct from true then
    raise exception 'Permission denied: not a member of company %', p_company_id
      using errcode = '42501';
  end if;

  -- (b) فحص الصلاحية
  v_has_perm := public.has_permission(p_company_id, 'inventory.adjust');
  if v_has_perm is distinct from true then
    raise exception 'Permission denied: inventory.adjust'
      using errcode = '42501';
  end if;

  -- (c) فحص الفرع
  if not exists (
    select 1 from public.branches b
    where b.id = p_branch_id and b.company_id = p_company_id
  ) then
    raise exception 'Validation failed: branch not in company'
      using errcode = '22023';
  end if;

  -- (d) إنشاء الجلسة
  insert into public.stock_count_sessions (
    company_id, branch_id, status, notes, created_by
  ) values (
    p_company_id, p_branch_id, 'draft',
    nullif(p_notes, ''), auth.uid()
  )
  returning id into v_session_id;

  -- (e) إنشاء البنود من inventory_balances الحالية
  --     كل منتج له رصيد > 0، أو موجود في الأرصدة (حتى لو = 0).
  --     لالتقاط المنتجات التي نفدت (quantity_on_hand = 0)، نضمّن كل الأرصدة.
  insert into public.stock_count_items (
    company_id, session_id, product_id, unit_id, expected_quantity
  )
  select
    p_company_id,
    v_session_id,
    ib.product_id,
    p.default_unit_id,
    ib.quantity_on_hand
  from public.inventory_balances ib
  join public.products p
    on p.id = ib.product_id
   and p.company_id = p_company_id
  where ib.company_id = p_company_id
    and ib.branch_id  = p_branch_id;

  -- (f) ضمّن أيضًا المنتجات النشطة التي ليس لها صف في inventory_balances
  --     (لم تُسجَّل لها أي حركة بعد).
  insert into public.stock_count_items (
    company_id, session_id, product_id, unit_id, expected_quantity
  )
  select
    p_company_id,
    v_session_id,
    p.id,
    p.default_unit_id,
    0
  from public.products p
  where p.company_id = p_company_id
    and p.is_active = true
    and not exists (
      select 1 from public.stock_count_items sci
      where sci.session_id = v_session_id
        and sci.product_id = p.id
    );

  return v_session_id;
end;
$function$;

-- -----------------------------------------------------------------------------
-- 5) RPC: set_stock_count_item_actual
-- -----------------------------------------------------------------------------
-- يُحدّث الكمية الفعلية لبند واحد.
-- -----------------------------------------------------------------------------
create or replace function public.set_stock_count_item_actual(
  p_item_id         uuid,
  p_actual_quantity numeric,
  p_notes           text default null
)
returns void
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_company_id uuid;
  v_status     text;
begin
  if p_actual_quantity is null or p_actual_quantity < 0 then
    raise exception 'Validation failed: actual_quantity must be >= 0'
      using errcode = '22023';
  end if;

  select sci.company_id, scs.status
    into v_company_id, v_status
  from public.stock_count_items sci
  join public.stock_count_sessions scs on scs.id = sci.session_id
  where sci.id = p_item_id;

  if v_company_id is null then
    raise exception 'Not found: stock_count_item %', p_item_id
      using errcode = 'P0002';
  end if;

  if public.is_company_member(v_company_id) is distinct from true then
    raise exception 'Permission denied: not a member'
      using errcode = '42501';
  end if;

  if public.has_permission(v_company_id, 'inventory.adjust') is distinct from true then
    raise exception 'Permission denied: inventory.adjust'
      using errcode = '42501';
  end if;

  if v_status <> 'draft' then
    raise exception 'Validation failed: session is %, not draft', v_status
      using errcode = '22023';
  end if;

  update public.stock_count_items
  set actual_quantity = p_actual_quantity,
      notes           = nullif(p_notes, ''),
      updated_at      = now()
  where id = p_item_id;
end;
$function$;

-- -----------------------------------------------------------------------------
-- 6) RPC: confirm_stock_count_session
-- -----------------------------------------------------------------------------
-- يمر على البنود ذات الفروق != 0، ويُدرج adjustment_in / adjustment_out.
-- الـ trigger apply_stock_movement يُحدّث inventory_balances تلقائيًا.
-- -----------------------------------------------------------------------------
create or replace function public.confirm_stock_count_session(
  p_session_id uuid
)
returns integer
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_company_id  uuid;
  v_branch_id   uuid;
  v_status      text;
  v_item        record;
  v_variance    numeric;
  v_movement    text;
  v_count       integer := 0;
  v_created_by  uuid := auth.uid();
begin
  select company_id, branch_id, status
    into v_company_id, v_branch_id, v_status
  from public.stock_count_sessions
  where id = p_session_id;

  if v_company_id is null then
    raise exception 'Not found: stock_count_session %', p_session_id
      using errcode = 'P0002';
  end if;

  if public.is_company_member(v_company_id) is distinct from true then
    raise exception 'Permission denied: not a member'
      using errcode = '42501';
  end if;

  if public.has_permission(v_company_id, 'inventory.adjust') is distinct from true then
    raise exception 'Permission denied: inventory.adjust'
      using errcode = '42501';
  end if;

  if v_status <> 'draft' then
    raise exception 'Validation failed: session is %, not draft', v_status
      using errcode = '22023';
  end if;

  -- مر على البنود ذات actual_quantity غير null
  for v_item in
    select
      sci.id,
      sci.product_id,
      sci.unit_id,
      sci.expected_quantity,
      sci.actual_quantity
    from public.stock_count_items sci
    where sci.session_id = p_session_id
      and sci.actual_quantity is not null
  loop
    v_variance := v_item.actual_quantity - v_item.expected_quantity;
    if v_variance = 0 then
      continue;
    end if;

    v_movement := case
      when v_variance > 0 then 'adjustment_in'
      else 'adjustment_out'
    end;

    insert into public.stock_movements (
      company_id, branch_id, product_id,
      movement_type, quantity, unit_id,
      reference_type, reference_id,
      notes, created_by
    ) values (
      v_company_id,
      v_branch_id,
      v_item.product_id,
      v_movement,
      v_variance,
      v_item.unit_id,
      'stock_count',
      p_session_id,
      'تسوية جرد',
      v_created_by
    );

    v_count := v_count + 1;
  end loop;

  update public.stock_count_sessions
  set status = 'confirmed',
      confirmed_at = now(),
      updated_at = now()
  where id = p_session_id;

  return v_count;
end;
$function$;

-- -----------------------------------------------------------------------------
-- 7) RPC: cancel_stock_count_session
-- -----------------------------------------------------------------------------
create or replace function public.cancel_stock_count_session(
  p_session_id uuid
)
returns void
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_company_id uuid;
  v_status     text;
begin
  select company_id, status
    into v_company_id, v_status
  from public.stock_count_sessions
  where id = p_session_id;

  if v_company_id is null then
    raise exception 'Not found: stock_count_session %', p_session_id
      using errcode = 'P0002';
  end if;

  if public.is_company_member(v_company_id) is distinct from true then
    raise exception 'Permission denied: not a member'
      using errcode = '42501';
  end if;

  if public.has_permission(v_company_id, 'inventory.adjust') is distinct from true then
    raise exception 'Permission denied: inventory.adjust'
      using errcode = '42501';
  end if;

  if v_status <> 'draft' then
    raise exception 'Validation failed: session is %, not draft', v_status
      using errcode = '22023';
  end if;

  update public.stock_count_sessions
  set status = 'cancelled',
      cancelled_at = now(),
      updated_at = now()
  where id = p_session_id;
end;
$function$;

-- -----------------------------------------------------------------------------
-- 8) الصلاحيات
-- -----------------------------------------------------------------------------
revoke all on function public.create_stock_count_session(uuid, uuid, text) from public, anon;
revoke all on function public.set_stock_count_item_actual(uuid, numeric, text) from public, anon;
revoke all on function public.confirm_stock_count_session(uuid) from public, anon;
revoke all on function public.cancel_stock_count_session(uuid) from public, anon;

grant execute on function public.create_stock_count_session(uuid, uuid, text) to authenticated;
grant execute on function public.set_stock_count_item_actual(uuid, numeric, text) to authenticated;
grant execute on function public.confirm_stock_count_session(uuid) to authenticated;
grant execute on function public.cancel_stock_count_session(uuid) to authenticated;

-- =============================================================================
-- انتهى Migration 35
-- =============================================================================

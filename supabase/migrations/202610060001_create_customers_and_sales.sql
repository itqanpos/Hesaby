-- ============================================================================
-- Migration : 202610060001_create_customers_and_sales.sql
-- Phase     : 8 — Customers & Sales Foundation
-- Purpose   : Customers, sales invoices, sale line items, RLS, and the full
--             sales lifecycle (state machine, stock movements, totals,
--             payment status).
-- Security  : RLS on all three tables. Composite FKs guarantee cross-tenant
--             integrity. Trigger functions are SECURITY DEFINER with a
--             pinned search_path.
-- ============================================================================


-- ============================================================================
-- 1) CUSTOMERS
-- ============================================================================

create table if not exists public.customers (
  id          uuid        primary key default gen_random_uuid(),
  company_id  uuid        not null
                          references public.companies (id) on delete cascade,
  name        text        not null,
  code        text,
  phone       text,
  email       text,
  address     text,
  notes       text,
  is_active   boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint customers_name_length
    check (char_length(trim(name)) between 1 and 200),
  constraint customers_code_length
    check (code is null or char_length(trim(code)) between 1 and 64),
  constraint customers_phone_length
    check (phone is null or char_length(trim(phone)) between 1 and 30),
  constraint customers_email_length
    check (email is null or char_length(trim(email)) between 1 and 255),
  constraint customers_address_length
    check (address is null or char_length(address) <= 500),
  constraint customers_notes_length
    check (notes is null or char_length(notes) <= 2000),
  constraint customers_company_name_unique
    unique (company_id, name),
  constraint customers_id_company_unique
    unique (id, company_id)
);

comment on table public.customers is
  'Customers of a company. Foundation for Phase 8 (Sales).';

create unique index if not exists uniq_customers_company_code
  on public.customers (company_id, code) where code is not null;
create unique index if not exists uniq_customers_company_phone
  on public.customers (company_id, phone) where phone is not null;
create index if not exists idx_customers_company_active
  on public.customers (company_id, is_active);
create index if not exists idx_customers_company_name
  on public.customers (company_id, name);

drop trigger if exists trg_customers_set_updated_at on public.customers;
create trigger trg_customers_set_updated_at
before update on public.customers
for each row execute function public.set_updated_at();

alter table public.customers enable row level security;

drop policy if exists "customers_select_company_member" on public.customers;
create policy "customers_select_company_member"
on public.customers for select to authenticated
using (public.is_company_member(company_id));

drop policy if exists "customers_insert_company_manager" on public.customers;
create policy "customers_insert_company_manager"
on public.customers for insert to authenticated
with check (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);

drop policy if exists "customers_update_company_manager" on public.customers;
create policy "customers_update_company_manager"
on public.customers for update to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
)
with check (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);

drop policy if exists "customers_delete_company_manager" on public.customers;
create policy "customers_delete_company_manager"
on public.customers for delete to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);


-- ============================================================================
-- 2) SALES (header)
-- ============================================================================

create table if not exists public.sales (
  id              uuid          primary key default gen_random_uuid(),
  company_id      uuid          not null
                                references public.companies (id)
                                on delete cascade,
  branch_id       uuid          not null,
  customer_id     uuid          not null,
  invoice_number  text,
  sale_date       timestamptz   not null default now(),
  status          text          not null default 'draft',
  subtotal        numeric(15,4) not null default 0,
  discount        numeric(15,4) not null default 0,
  tax_amount      numeric(15,4) not null default 0,
  total           numeric(15,4) not null default 0,
  paid_amount     numeric(15,4) not null default 0,
  payment_status  text          not null default 'unpaid',
  notes           text,
  created_by      uuid          references auth.users (id) on delete set null,
  confirmed_at    timestamptz,
  cancelled_at    timestamptz,
  created_at      timestamptz   not null default now(),
  updated_at      timestamptz   not null default now(),

  constraint sales_branch_company_fk
    foreign key (branch_id, company_id)
    references public.branches (id, company_id) on delete restrict,
  constraint sales_customer_company_fk
    foreign key (customer_id, company_id)
    references public.customers (id, company_id) on delete restrict,

  constraint sales_status_valid
    check (status in ('draft', 'confirmed', 'cancelled')),
  constraint sales_payment_status_valid
    check (payment_status in ('unpaid', 'partial', 'paid')),

  constraint sales_invoice_number_length
    check (invoice_number is null
           or char_length(trim(invoice_number)) between 1 and 64),
  constraint sales_notes_length
    check (notes is null or char_length(notes) <= 2000),

  constraint sales_subtotal_non_negative
    check (subtotal >= 0),
  constraint sales_discount_non_negative
    check (discount >= 0),
  constraint sales_tax_non_negative
    check (tax_amount >= 0),
  constraint sales_total_non_negative
    check (total >= 0),
  constraint sales_paid_amount_non_negative
    check (paid_amount >= 0),
  constraint sales_paid_amount_not_exceeding_total
    check (paid_amount <= total),

  constraint sales_id_company_unique
    unique (id, company_id)
);

comment on table public.sales is
  'Sales invoices (customer receipts). Header rows.';

create unique index if not exists uniq_sales_company_invoice_number
  on public.sales (company_id, invoice_number)
  where invoice_number is not null;
create index if not exists idx_sales_company_date
  on public.sales (company_id, sale_date desc);
create index if not exists idx_sales_company_status
  on public.sales (company_id, status);
create index if not exists idx_sales_company_customer
  on public.sales (company_id, customer_id);
create index if not exists idx_sales_company_branch
  on public.sales (company_id, branch_id);

drop trigger if exists trg_sales_set_updated_at on public.sales;
create trigger trg_sales_set_updated_at
before update on public.sales
for each row execute function public.set_updated_at();

alter table public.sales enable row level security;

drop policy if exists "sales_select_company_member" on public.sales;
create policy "sales_select_company_member"
on public.sales for select to authenticated
using (public.is_company_member(company_id));

-- Cashiers are allowed to create and update sales (they operate the till),
-- but not to delete them; deletion is a management action.
drop policy if exists "sales_insert_company_staff" on public.sales;
create policy "sales_insert_company_staff"
on public.sales for insert to authenticated
with check (
  public.has_company_role(
    company_id, array['owner', 'admin', 'manager', 'cashier']
  )
);

drop policy if exists "sales_update_company_staff" on public.sales;
create policy "sales_update_company_staff"
on public.sales for update to authenticated
using (
  public.has_company_role(
    company_id, array['owner', 'admin', 'manager', 'cashier']
  )
)
with check (
  public.has_company_role(
    company_id, array['owner', 'admin', 'manager', 'cashier']
  )
);

drop policy if exists "sales_delete_company_manager" on public.sales;
create policy "sales_delete_company_manager"
on public.sales for delete to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);


-- ============================================================================
-- 3) SALE ITEMS
-- ============================================================================

create table if not exists public.sale_items (
  id          uuid          primary key default gen_random_uuid(),
  company_id  uuid          not null
                            references public.companies (id)
                            on delete cascade,
  sale_id     uuid          not null,
  product_id  uuid          not null,
  unit_id     uuid          not null,
  quantity    numeric(15,4) not null,
  unit_price  numeric(15,4) not null,
  line_total  numeric(15,4) not null,
  notes       text,
  created_at  timestamptz   not null default now(),
  updated_at  timestamptz   not null default now(),

  constraint sale_items_sale_company_fk
    foreign key (sale_id, company_id)
    references public.sales (id, company_id) on delete cascade,
  constraint sale_items_product_company_fk
    foreign key (product_id, company_id)
    references public.products (id, company_id) on delete restrict,
  constraint sale_items_unit_company_fk
    foreign key (unit_id, company_id)
    references public.units (id, company_id) on delete restrict,

  constraint sale_items_quantity_positive
    check (quantity > 0),
  constraint sale_items_unit_price_non_negative
    check (unit_price >= 0),
  constraint sale_items_line_total_non_negative
    check (line_total >= 0),
  constraint sale_items_notes_length
    check (notes is null or char_length(notes) <= 1000)
);

comment on table public.sale_items is
  'Line items of a sales invoice.';

create index if not exists idx_sale_items_company_sale
  on public.sale_items (company_id, sale_id);
create index if not exists idx_sale_items_company_product
  on public.sale_items (company_id, product_id);

drop trigger if exists trg_sale_items_set_updated_at on public.sale_items;
create trigger trg_sale_items_set_updated_at
before update on public.sale_items
for each row execute function public.set_updated_at();

alter table public.sale_items enable row level security;

drop policy if exists "sale_items_select_company_member"
  on public.sale_items;
create policy "sale_items_select_company_member"
on public.sale_items for select to authenticated
using (public.is_company_member(company_id));

drop policy if exists "sale_items_insert_company_staff"
  on public.sale_items;
create policy "sale_items_insert_company_staff"
on public.sale_items for insert to authenticated
with check (
  public.has_company_role(
    company_id, array['owner', 'admin', 'manager', 'cashier']
  )
);

drop policy if exists "sale_items_update_company_staff"
  on public.sale_items;
create policy "sale_items_update_company_staff"
on public.sale_items for update to authenticated
using (
  public.has_company_role(
    company_id, array['owner', 'admin', 'manager', 'cashier']
  )
)
with check (
  public.has_company_role(
    company_id, array['owner', 'admin', 'manager', 'cashier']
  )
);

drop policy if exists "sale_items_delete_company_staff"
  on public.sale_items;
create policy "sale_items_delete_company_staff"
on public.sale_items for delete to authenticated
using (
  public.has_company_role(
    company_id, array['owner', 'admin', 'manager', 'cashier']
  )
);


-- ============================================================================
-- 4) TRIGGER: guard_sales_insert
-- ============================================================================
-- Sales are always created as drafts. Confirmation is an explicit UPDATE.

create or replace function public.guard_sales_insert()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status <> 'draft' then
    raise exception
      'Sales must be created with status = draft (got %)', new.status
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sales_guard_insert on public.sales;
create trigger trg_sales_guard_insert
before insert on public.sales
for each row
execute function public.guard_sales_insert();


-- ============================================================================
-- 5) TRIGGER: apply_sale_status_change
-- ============================================================================
-- Handles every UPDATE:
--   * draft -> confirmed  : insert sale_out stock movements, stamp
--                           confirmed_at, clear cancelled_at
--   * draft -> cancelled  : stamp cancelled_at, no movements
--   * confirmed -> cancel : insert return_in stock movements (may fail
--                           with insufficient stock via the Phase 5
--                           trigger), stamp cancelled_at
--   * other transitions   : rejected
--   * non-transition edits: draft rows recompute total; confirmed and
--                           cancelled rows accept only notes changes
-- Always keeps payment_status in sync with paid_amount and total.

create or replace function public.apply_sale_status_change()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_item      record;
  v_has_items boolean;
begin
  -- --------------------------------------------------------------------------
  -- Status transition branch
  -- --------------------------------------------------------------------------
  if new.status <> old.status then
    if old.status = 'draft' and new.status = 'confirmed' then
      select exists (
        select 1 from public.sale_items where sale_id = old.id
      ) into v_has_items;

      if not v_has_items then
        raise exception
          'Cannot confirm sale % without items', old.id
          using errcode = 'check_violation';
      end if;

      for v_item in
        select product_id, quantity, unit_price
          from public.sale_items
         where sale_id = old.id
      loop
        insert into public.stock_movements (
          company_id, branch_id, product_id, movement_type, quantity,
          unit_cost, reference_type, reference_id, created_by
        ) values (
          new.company_id, new.branch_id, v_item.product_id, 'sale_out',
          -v_item.quantity, v_item.unit_price,
          'sale', new.id, auth.uid()
        );
      end loop;

      new.confirmed_at := now();
      new.cancelled_at := null;
    elsif old.status = 'draft' and new.status = 'cancelled' then
      new.cancelled_at := now();
    elsif old.status = 'confirmed' and new.status = 'cancelled' then
      for v_item in
        select product_id, quantity, unit_price
          from public.sale_items
         where sale_id = old.id
      loop
        insert into public.stock_movements (
          company_id, branch_id, product_id, movement_type, quantity,
          unit_cost, reference_type, reference_id, created_by
        ) values (
          new.company_id, new.branch_id, v_item.product_id, 'return_in',
          v_item.quantity, v_item.unit_price,
          'sale', new.id, auth.uid()
        );
      end loop;

      new.cancelled_at := now();
    else
      raise exception
        'Invalid sale status transition: % -> %', old.status, new.status
        using errcode = 'check_violation';
    end if;
  else
    -- ------------------------------------------------------------------------
    -- Non-transition updates
    -- ------------------------------------------------------------------------
    if old.status = 'draft' then
      -- Draft: recompute the total from the current financial fields.
      new.total := new.subtotal - new.discount + new.tax_amount;
    elsif old.status = 'confirmed' then
      -- Confirmed: only notes may change.
      if (new.subtotal       is distinct from old.subtotal)
         or (new.discount      is distinct from old.discount)
         or (new.tax_amount    is distinct from old.tax_amount)
         or (new.total         is distinct from old.total)
         or (new.paid_amount   is distinct from old.paid_amount)
         or (new.branch_id     is distinct from old.branch_id)
         or (new.customer_id   is distinct from old.customer_id)
         or (new.sale_date     is distinct from old.sale_date)
         or (new.invoice_number is distinct from old.invoice_number)
      then
        raise exception
          'Cannot modify a % sale except notes', old.status
          using errcode = 'check_violation';
      end if;
    else
      -- Cancelled: only notes may change, nothing financial.
      if (new.subtotal       is distinct from old.subtotal)
         or (new.discount      is distinct from old.discount)
         or (new.tax_amount    is distinct from old.tax_amount)
         or (new.total         is distinct from old.total)
         or (new.paid_amount   is distinct from old.paid_amount)
         or (new.branch_id     is distinct from old.branch_id)
         or (new.customer_id   is distinct from old.customer_id)
         or (new.sale_date     is distinct from old.sale_date)
         or (new.invoice_number is distinct from old.invoice_number)
      then
        raise exception
          'Cannot modify a % sale except notes', old.status
          using errcode = 'check_violation';
      end if;
    end if;
  end if;

  -- --------------------------------------------------------------------------
  -- Payment status is always derived from paid_amount and total.
  -- --------------------------------------------------------------------------
  if new.paid_amount <= 0 then
    new.payment_status := 'unpaid';
  elsif new.paid_amount >= new.total then
    new.payment_status := 'paid';
  else
    new.payment_status := 'partial';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sales_apply_status_change on public.sales;
create trigger trg_sales_apply_status_change
before update on public.sales
for each row
execute function public.apply_sale_status_change();


-- ============================================================================
-- 6) TRIGGER: block_sale_delete
-- ============================================================================
-- Sales are never hard-deleted; cancellation is the supported path.

create or replace function public.block_sale_delete()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception
    'Sales cannot be deleted; set status = cancelled instead'
    using errcode = 'check_violation';
end;
$$;

drop trigger if exists trg_sales_block_delete on public.sales;
create trigger trg_sales_block_delete
before delete on public.sales
for each row
execute function public.block_sale_delete();


-- ============================================================================
-- 7) TRIGGER: guard_sale_items_mutation
-- ============================================================================
-- Items may be inserted / updated / deleted only while the parent sale is
-- still a draft.

create or replace function public.guard_sale_items_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_sale_id uuid;
  v_status  text;
begin
  if tg_op = 'DELETE' then
    v_sale_id := old.sale_id;
  else
    v_sale_id := new.sale_id;
  end if;

  select status into v_status from public.sales where id = v_sale_id;

  if v_status is null then
    raise exception
      'Parent sale % not found', v_sale_id
      using errcode = 'check_violation';
  end if;

  if v_status <> 'draft' then
    raise exception
      'Cannot modify items of a % sale', v_status
      using errcode = 'check_violation';
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_sale_items_guard_mutation on public.sale_items;
create trigger trg_sale_items_guard_mutation
before insert or update or delete on public.sale_items
for each row
execute function public.guard_sale_items_mutation();


-- ============================================================================
-- 8) TRIGGER: compute_sale_item_line_total
-- ============================================================================
-- Forces line_total = quantity * unit_price, overriding whatever the client
-- sent.

create or replace function public.compute_sale_item_line_total()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.line_total := new.quantity * new.unit_price;
  return new;
end;
$$;

drop trigger if exists trg_sale_items_compute_line_total
  on public.sale_items;
create trigger trg_sale_items_compute_line_total
before insert or update on public.sale_items
for each row
execute function public.compute_sale_item_line_total();


-- ============================================================================
-- 9) TRIGGER: recompute_sale_totals
-- ============================================================================
-- After any change to the line items, refresh the parent sale's subtotal.
-- The parent's BEFORE UPDATE trigger then recomputes the total and the
-- payment status.

create or replace function public.recompute_sale_totals()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale_id  uuid;
  v_subtotal numeric(15,4);
begin
  if tg_op = 'DELETE' then
    v_sale_id := old.sale_id;
  else
    v_sale_id := new.sale_id;
  end if;

  select coalesce(sum(line_total), 0) into v_subtotal
    from public.sale_items
   where sale_id = v_sale_id;

  update public.sales set subtotal = v_subtotal where id = v_sale_id;

  return null;
end;
$$;

drop trigger if exists trg_sale_items_recompute_totals on public.sale_items;
create trigger trg_sale_items_recompute_totals
after insert or update or delete on public.sale_items
for each row
execute function public.recompute_sale_totals();


-- ============================================================================
-- End of migration
-- ============================================================================

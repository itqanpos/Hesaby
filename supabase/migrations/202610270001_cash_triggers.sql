-- ============================================================================
-- Migration : 202610270001_cash_triggers.sql
-- Phase     : T-5 — Cash Register (Stage 2b)
-- Purpose   : Auto-record cash movements for the three most common flows:
--             1) sale_payments   INSERT  → cash in
--             2) customer_payments INSERT → cash in
--             3) supplier_payments INSERT → cash out
--
-- Helper functions pick the correct account (cash / card / instapay) based
-- on the payment method, falling back to the default cash account if the
-- matching type is unavailable.
--
-- At the end, existing confirmed sales with paid_amount > 0 are backfilled
-- into sale_payments (defaulted to cash) so their historical totals appear
-- in the cash register. The backfill fires the trigger above.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1) Helper: map payment method to an account type
-- ----------------------------------------------------------------------------

create or replace function public.cash_method_to_account_type(p_method text)
returns text
language sql
immutable
as $$
  select case
    when p_method in ('card', 'credit_card') then 'card'
    when p_method = 'bank_transfer' then 'bank'
    when p_method = 'instapay' then 'instapay'
    else 'cash'
  end;
$$;

comment on function public.cash_method_to_account_type(text) is
  'Maps a payment method string to a cash_accounts.type value.';


-- ----------------------------------------------------------------------------
-- 2) Helper: default account id by type (first active, oldest)
-- ----------------------------------------------------------------------------

create or replace function public.cash_default_account_id(
  p_company_id uuid,
  p_type       text
)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id
    from public.cash_accounts
   where company_id = p_company_id
     and type       = p_type
     and is_active  = true
   order by created_at
   limit 1;
$$;

comment on function public.cash_default_account_id(uuid, text) is
  'Returns the oldest active cash account of the given type, or null.';


-- ----------------------------------------------------------------------------
-- 3) Helper: category id by name
-- ----------------------------------------------------------------------------

create or replace function public.cash_category_id(
  p_company_id uuid,
  p_name       text
)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id
    from public.cash_categories
   where company_id = p_company_id
     and name       = p_name
   limit 1;
$$;

comment on function public.cash_category_id(uuid, text) is
  'Returns the id of the company category with the given name, or null.';


-- ----------------------------------------------------------------------------
-- 4) Trigger: sale_payments INSERT → cash in
-- ----------------------------------------------------------------------------

create or replace function public.trg_cash_from_sale_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type          text;
  v_account_id    uuid;
  v_category_id   uuid;
  v_category_name text;
begin
  -- Choose account type from method.
  v_type := public.cash_method_to_account_type(new.payment_method);

  v_account_id := public.cash_default_account_id(new.company_id, v_type);
  if v_account_id is null then
    -- Fallback to the cash account if the specific type is missing.
    v_account_id := public.cash_default_account_id(new.company_id, 'cash');
  end if;
  if v_account_id is null then
    -- No cash account at all — skip silently. This should never happen in
    -- production because companies are seeded with two accounts on creation.
    return new;
  end if;

  v_category_name := case
    when v_type = 'cash' then 'بيع نقدي'
    else 'بيع بطاقة'
  end;
  v_category_id := public.cash_category_id(new.company_id, v_category_name);

  insert into public.cash_transactions (
    company_id,
    account_id,
    category_id,
    direction,
    amount,
    source_type,
    source_id,
    reference,
    recorded_by
  ) values (
    new.company_id,
    v_account_id,
    v_category_id,
    'in',
    new.amount,
    'sale',
    new.sale_id,
    'دفعة من بيع',
    coalesce(new.created_by, auth.uid())
  );

  return new;
end;
$$;

comment on function public.trg_cash_from_sale_payment() is
  'Records a cash-in transaction when a sale_payment is inserted.';

drop trigger if exists trg_cash_sale_payment_insert on public.sale_payments;
create trigger trg_cash_sale_payment_insert
after insert on public.sale_payments
for each row
execute function public.trg_cash_from_sale_payment();


-- ----------------------------------------------------------------------------
-- 5) Trigger: customer_payments INSERT → cash in
-- ----------------------------------------------------------------------------

create or replace function public.trg_cash_from_customer_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type        text;
  v_account_id  uuid;
  v_category_id uuid;
begin
  v_type := public.cash_method_to_account_type(new.method);

  v_account_id := public.cash_default_account_id(new.company_id, v_type);
  if v_account_id is null then
    v_account_id := public.cash_default_account_id(new.company_id, 'cash');
  end if;
  if v_account_id is null then
    return new;
  end if;

  v_category_id := public.cash_category_id(new.company_id, 'دفعة عميل');

  insert into public.cash_transactions (
    company_id,
    account_id,
    category_id,
    direction,
    amount,
    source_type,
    source_id,
    reference,
    recorded_by
  ) values (
    new.company_id,
    v_account_id,
    v_category_id,
    'in',
    new.amount,
    'customer_payment',
    new.id,
    coalesce(new.reference, 'دفعة عميل'),
    coalesce(new.created_by, auth.uid())
  );

  return new;
end;
$$;

comment on function public.trg_cash_from_customer_payment() is
  'Records a cash-in transaction when a customer_payment is inserted.';

drop trigger if exists trg_cash_customer_payment_insert on public.customer_payments;
create trigger trg_cash_customer_payment_insert
after insert on public.customer_payments
for each row
execute function public.trg_cash_from_customer_payment();


-- ----------------------------------------------------------------------------
-- 6) Trigger: supplier_payments INSERT → cash out
-- ----------------------------------------------------------------------------

create or replace function public.trg_cash_from_supplier_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type        text;
  v_account_id  uuid;
  v_category_id uuid;
begin
  v_type := public.cash_method_to_account_type(new.payment_method);

  v_account_id := public.cash_default_account_id(new.company_id, v_type);
  if v_account_id is null then
    v_account_id := public.cash_default_account_id(new.company_id, 'cash');
  end if;
  if v_account_id is null then
    return new;
  end if;

  v_category_id := public.cash_category_id(new.company_id, 'دفعة مورد');

  insert into public.cash_transactions (
    company_id,
    account_id,
    category_id,
    direction,
    amount,
    source_type,
    source_id,
    reference,
    recorded_by
  ) values (
    new.company_id,
    v_account_id,
    v_category_id,
    'out',
    new.amount,
    'supplier_payment',
    new.id,
    coalesce(new.reference, 'دفعة مورد'),
    coalesce(new.created_by, auth.uid())
  );

  return new;
end;
$$;

comment on function public.trg_cash_from_supplier_payment() is
  'Records a cash-out transaction when a supplier_payment is inserted.';

drop trigger if exists trg_cash_supplier_payment_insert on public.supplier_payments;
create trigger trg_cash_supplier_payment_insert
after insert on public.supplier_payments
for each row
execute function public.trg_cash_from_supplier_payment();


-- ----------------------------------------------------------------------------
-- 7) Backfill: existing confirmed sales with paid_amount > 0
-- ----------------------------------------------------------------------------
-- Every historical sale that has a non-zero paid amount gets one
-- sale_payments row marked as cash (the safest default — the money is
-- somewhere in the business, and cash is the assumed default). Fires the
-- trigger above, so the cash register starts with a realistic opening
-- position.
-- ----------------------------------------------------------------------------

insert into public.sale_payments (
  company_id,
  sale_id,
  amount,
  payment_method,
  notes,
  created_at
)
select
  s.company_id,
  s.id,
  s.paid_amount,
  'cash',
  'ترحيل تلقائي من سجل بيع سابق',
  coalesce(s.confirmed_at, s.sale_date, s.created_at)
from public.sales s
where s.status = 'confirmed'
  and s.paid_amount > 0
  and not exists (
    select 1 from public.sale_payments sp where sp.sale_id = s.id
  );


-- ============================================================================
-- End of migration
-- ============================================================================

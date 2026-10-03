-- ============================================================================
-- Migration : 202610070001_pos_and_prices.sql
-- Phase     : 9 — POS Foundation + Customer Balance
-- Purpose   : Extend pricing (min/max on products and product units), add
--             customer balance tracking, create the customer_payments table,
--             and wire the triggers that keep customer balances in sync with
--             confirmed sales and standalone payments.
-- Security  : RLS is enabled on customer_payments with the same membership
--             and role model as the rest of the application. Trigger
--             functions are SECURITY DEFINER with a pinned search_path.
-- ============================================================================


-- ============================================================================
-- 1) products.max_selling_price
-- ============================================================================

alter table public.products
  add column if not exists max_selling_price numeric(15,4);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'products_max_selling_price_non_negative'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_max_selling_price_non_negative
      check (max_selling_price is null or max_selling_price >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'products_price_range_valid'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_price_range_valid
      check (
        min_selling_price is null
        or max_selling_price is null
        or min_selling_price <= max_selling_price
      );
  end if;
end $$;

comment on column public.products.max_selling_price is
  'Optional upper bound for the default unit selling price. NULL = no cap.';


-- ============================================================================
-- 2) product_units: per-unit pricing
-- ============================================================================

alter table public.product_units
  add column if not exists selling_price numeric(15,4);
alter table public.product_units
  add column if not exists min_selling_price numeric(15,4);
alter table public.product_units
  add column if not exists max_selling_price numeric(15,4);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'product_units_selling_price_non_negative'
      and conrelid = 'public.product_units'::regclass
  ) then
    alter table public.product_units
      add constraint product_units_selling_price_non_negative
      check (selling_price is null or selling_price >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'product_units_min_selling_price_non_negative'
      and conrelid = 'public.product_units'::regclass
  ) then
    alter table public.product_units
      add constraint product_units_min_selling_price_non_negative
      check (min_selling_price is null or min_selling_price >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'product_units_max_selling_price_non_negative'
      and conrelid = 'public.product_units'::regclass
  ) then
    alter table public.product_units
      add constraint product_units_max_selling_price_non_negative
      check (max_selling_price is null or max_selling_price >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'product_units_price_range_valid'
      and conrelid = 'public.product_units'::regclass
  ) then
    alter table public.product_units
      add constraint product_units_price_range_valid
      check (
        min_selling_price is null
        or max_selling_price is null
        or min_selling_price <= max_selling_price
      );
  end if;
end $$;

comment on column public.product_units.selling_price is
  'Unit-specific selling price. When NULL, the effective price falls back to products.selling_price * conversion_factor.';
comment on column public.product_units.min_selling_price is
  'Optional lower bound for this unit. NULL = inherit from products.min_selling_price * conversion_factor.';
comment on column public.product_units.max_selling_price is
  'Optional upper bound for this unit. NULL = inherit from products.max_selling_price * conversion_factor.';


-- ============================================================================
-- 3) customers.balance
-- ============================================================================

alter table public.customers
  add column if not exists balance numeric(15,4) not null default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'customers_balance_non_negative'
      and conrelid = 'public.customers'::regclass
  ) then
    alter table public.customers
      add constraint customers_balance_non_negative
      check (balance >= 0);
  end if;
end $$;

comment on column public.customers.balance is
  'Outstanding amount owed by the customer. Increased by confirmed sales and decreased by payments. Never negative.';


-- ============================================================================
-- 4) Allow sales.customer_id to be NULL (cash sales without a registered
--    customer).
-- ============================================================================

alter table public.sales
  alter column customer_id drop not null;


-- ============================================================================
-- 5) customer_payments table
-- ============================================================================

create table if not exists public.customer_payments (
  id          uuid          primary key default gen_random_uuid(),
  company_id  uuid          not null
                            references public.companies (id)
                            on delete cascade,
  customer_id uuid          not null,
  amount      numeric(15,4) not null,
  method      text          not null,
  reference   text,
  notes       text,
  created_by  uuid          references auth.users (id) on delete set null,
  created_at  timestamptz   not null default now(),

  constraint customer_payments_customer_company_fk
    foreign key (customer_id, company_id)
    references public.customers (id, company_id) on delete restrict,

  constraint customer_payments_amount_positive
    check (amount > 0),

  constraint customer_payments_method_valid
    check (method in ('cash', 'card', 'transfer')),

  constraint customer_payments_reference_length
    check (reference is null or char_length(reference) <= 100),

  constraint customer_payments_notes_length
    check (notes is null or char_length(notes) <= 1000)
);

comment on table public.customer_payments is
  'Standalone payments received from customers, independent of any sale. Each row reduces the customer balance.';

create index if not exists idx_customer_payments_company_customer
  on public.customer_payments (company_id, customer_id, created_at desc);

alter table public.customer_payments enable row level security;

drop policy if exists "customer_payments_select_company_member"
  on public.customer_payments;
create policy "customer_payments_select_company_member"
on public.customer_payments for select to authenticated
using (public.is_company_member(company_id));

drop policy if exists "customer_payments_insert_company_staff"
  on public.customer_payments;
create policy "customer_payments_insert_company_staff"
on public.customer_payments for insert to authenticated
with check (
  public.has_company_role(
    company_id, array['owner', 'admin', 'manager', 'cashier']
  )
);


-- ============================================================================
-- 6) Trigger: customer_payments → reduce customer balance
-- ============================================================================

create or replace function public.apply_customer_payment()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  update public.customers
     set balance = greatest(balance - new.amount, 0)
   where id = new.customer_id;

  return new;
end;
$$;

comment on function public.apply_customer_payment() is
  'Reduces the customer balance by the recorded payment amount.';

drop trigger if exists trg_customer_payments_apply
  on public.customer_payments;

create trigger trg_customer_payments_apply
after insert on public.customer_payments
for each row
execute function public.apply_customer_payment();


-- ============================================================================
-- 7) Trigger: sales status transition → adjust customer balance
-- ============================================================================
-- This trigger runs AFTER the Phase 8 apply_sale_status_change trigger, so
-- the sale row is already in its final state (confirmed_at, cancelled_at,
-- totals consistent).
--
-- Rules:
--   * draft -> confirmed:    balance += (total - paid_amount)
--   * confirmed -> cancelled: balance -= (total - paid_amount)
--
-- A null customer_id (cash sale) is ignored.

create or replace function public.apply_sale_balance_change()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_delta numeric(15,4);
begin
  if new.customer_id is null then
    return new;
  end if;

  if new.status = old.status then
    return new;
  end if;

  if old.status = 'draft' and new.status = 'confirmed' then
    v_delta := new.total - new.paid_amount;
    if v_delta <> 0 then
      update public.customers
         set balance = balance + v_delta
       where id = new.customer_id
         and company_id = new.company_id;
    end if;
  elsif old.status = 'confirmed' and new.status = 'cancelled' then
    v_delta := old.total - old.paid_amount;
    if v_delta <> 0 then
      update public.customers
         set balance = greatest(balance - v_delta, 0)
       where id = old.customer_id
         and company_id = old.company_id;
    end if;
  end if;

  return new;
end;
$$;

comment on function public.apply_sale_balance_change() is
  'Adjusts the customer balance when a sale is confirmed or cancelled.';

drop trigger if exists trg_sales_apply_balance_change on public.sales;

create trigger trg_sales_apply_balance_change
after update on public.sales
for each row
execute function public.apply_sale_balance_change();


-- ============================================================================
-- End of migration
-- ============================================================================

-- ============================================================================
-- Migration : 202610260001_sale_payments.sql
-- Phase     : T-5 — Cash Register (Stage 2a)
-- Purpose   : Introduce sale_payments so a single sale can be settled by
--             multiple methods (mixed cash + card). Each row is one payment
--             leg of the sale. This table is the source of truth for the
--             cash register triggers, replacing the single paid_amount
--             column on `sales` for accounting purposes.
--
-- Note: `sales.paid_amount` is kept (for now) as a denormalised total. It
-- will be reconciled against SUM(sale_payments.amount) going forward.
-- ============================================================================

create table if not exists public.sale_payments (
  id              uuid        primary key default gen_random_uuid(),
  company_id      uuid        not null references public.companies (id) on delete cascade,
  sale_id         uuid        not null references public.sales (id) on delete cascade,
  amount          numeric(14, 2) not null,
  payment_method  text        not null,
  reference       text,
  notes           text,
  created_by      uuid        references auth.users (id) on delete set null,
  created_at      timestamptz not null default now(),

  constraint sale_payments_amount_positive
    check (amount > 0),
  constraint sale_payments_method_valid
    check (payment_method in ('cash', 'card', 'instapay', 'bank_transfer', 'other')),
  constraint sale_payments_reference_length
    check (reference is null or char_length(reference) <= 200),
  constraint sale_payments_notes_length
    check (notes is null or char_length(notes) <= 500)
);

comment on table public.sale_payments is
  'Payment legs of a sale. One row per method used. Supports mixed cash + card.';

create index if not exists idx_sale_payments_company_sale
  on public.sale_payments (company_id, sale_id);

create index if not exists idx_sale_payments_company_created
  on public.sale_payments (company_id, created_at desc);

alter table public.sale_payments enable row level security;

-- SELECT: any company member
drop policy if exists "sale_payments_select" on public.sale_payments;
create policy "sale_payments_select"
on public.sale_payments for select to authenticated
using (public.is_company_member(company_id));

-- INSERT: members with sales.create
drop policy if exists "sale_payments_insert" on public.sale_payments;
create policy "sale_payments_insert"
on public.sale_payments for insert to authenticated
with check (public.has_permission(company_id, 'sales.create'));

-- UPDATE: members with sales.edit
drop policy if exists "sale_payments_update" on public.sale_payments;
create policy "sale_payments_update"
on public.sale_payments for update to authenticated
using (public.has_permission(company_id, 'sales.edit'))
with check (public.has_permission(company_id, 'sales.edit'));

-- DELETE: members with sales.edit
drop policy if exists "sale_payments_delete" on public.sale_payments;
create policy "sale_payments_delete"
on public.sale_payments for delete to authenticated
using (public.has_permission(company_id, 'sales.edit'));

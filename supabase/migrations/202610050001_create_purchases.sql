-- ============================================================================
-- Migration : 202610050001_create_purchases.sql
-- Phase     : 7 — Purchases Foundation
-- Purpose   : Purchase orders (supplier invoices). Header table only; line
--             items live in purchase_items (migration 2). A trigger in
--             migration 3 keeps stock_movements in sync when the purchase
--             transitions to `confirmed` or `cancelled`.
-- Security  : RLS enabled. Access is derived from auth.uid() and
--             company_members — never from client-supplied company_id.
--             Cross-tenant integrity enforced by composite foreign keys on
--             both the supplier and the branch.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Table: public.purchases
-- ----------------------------------------------------------------------------

create table if not exists public.purchases (
  id              uuid          primary key default gen_random_uuid(),
  company_id      uuid          not null
                                references public.companies (id)
                                on delete cascade,
  branch_id       uuid          not null,
  supplier_id     uuid          not null,
  invoice_number  text,
  purchase_date   date          not null default current_date,
  status          text          not null default 'draft',
  subtotal        numeric(15,4) not null default 0,
  discount        numeric(15,4) not null default 0,
  tax_amount      numeric(15,4) not null default 0,
  total           numeric(15,4) not null default 0,
  notes           text,
  created_by      uuid          references auth.users (id) on delete set null,
  confirmed_at    timestamptz,
  cancelled_at    timestamptz,
  created_at      timestamptz   not null default now(),
  updated_at      timestamptz   not null default now(),

  -- Cross-tenant integrity: the branch must belong to the same company.
  constraint purchases_branch_company_fk
    foreign key (branch_id, company_id)
    references public.branches (id, company_id)
    on delete restrict,

  -- Cross-tenant integrity: the supplier must belong to the same company.
  constraint purchases_supplier_company_fk
    foreign key (supplier_id, company_id)
    references public.suppliers (id, company_id)
    on delete restrict,

  constraint purchases_status_valid
    check (status in ('draft', 'confirmed', 'cancelled')),

  constraint purchases_invoice_number_length
    check (
      invoice_number is null
      or (char_length(trim(invoice_number)) between 1 and 64)
    ),

  constraint purchases_notes_length
    check (notes is null or char_length(notes) <= 2000),

  constraint purchases_subtotal_non_negative
    check (subtotal >= 0),
  constraint purchases_discount_non_negative
    check (discount >= 0),
  constraint purchases_tax_non_negative
    check (tax_amount >= 0),
  constraint purchases_total_non_negative
    check (total >= 0),

  -- Composite uniqueness enables a composite FK from purchase_items so
  -- that a line item can never reference a purchase of another company.
  constraint purchases_id_company_unique
    unique (id, company_id)
);

comment on table  public.purchases                  is
  'Purchase orders (supplier invoices). Header rows.';
comment on column public.purchases.branch_id        is
  'Receiving branch. Must belong to the same company.';
comment on column public.purchases.supplier_id      is
  'Supplier of this purchase. Must belong to the same company.';
comment on column public.purchases.invoice_number   is
  'Optional supplier invoice number. Unique per company when present.';
comment on column public.purchases.purchase_date    is
  'Business date of the purchase. Defaults to today.';
comment on column public.purchases.status           is
  'draft | confirmed | cancelled. Only the trigger may transition states.';
comment on column public.purchases.subtotal         is
  'Sum of line totals. Maintained by the trigger. NUMERIC(15,4).';
comment on column public.purchases.discount         is
  'Header-level discount. NUMERIC(15,4).';
comment on column public.purchases.tax_amount       is
  'Header-level tax amount. NUMERIC(15,4).';
comment on column public.purchases.total            is
  'Net total = subtotal - discount + tax_amount. NUMERIC(15,4).';
comment on column public.purchases.confirmed_at     is
  'When the purchase was confirmed. NULL while in draft.';
comment on column public.purchases.cancelled_at     is
  'When the purchase was cancelled. NULL otherwise.';


-- ----------------------------------------------------------------------------
-- Indexes
-- ----------------------------------------------------------------------------

-- Invoice number is unique per company only among rows that carry one.
create unique index if not exists uniq_purchases_company_invoice_number
  on public.purchases (company_id, invoice_number)
  where invoice_number is not null;

create index if not exists idx_purchases_company_date
  on public.purchases (company_id, purchase_date desc);

create index if not exists idx_purchases_company_status
  on public.purchases (company_id, status);

create index if not exists idx_purchases_company_supplier
  on public.purchases (company_id, supplier_id);

create index if not exists idx_purchases_company_branch
  on public.purchases (company_id, branch_id);


-- ----------------------------------------------------------------------------
-- Trigger: keep updated_at fresh
-- ----------------------------------------------------------------------------

drop trigger if exists trg_purchases_set_updated_at on public.purchases;

create trigger trg_purchases_set_updated_at
before update on public.purchases
for each row
execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- Row Level Security
-- ----------------------------------------------------------------------------
-- SELECT : any active member of the company.
-- WRITE  : owner / admin / manager.
-- ----------------------------------------------------------------------------

alter table public.purchases enable row level security;

drop policy if exists "purchases_select_company_member" on public.purchases;

create policy "purchases_select_company_member"
on public.purchases
for select
to authenticated
using (public.is_company_member(company_id));

drop policy if exists "purchases_insert_company_manager" on public.purchases;

create policy "purchases_insert_company_manager"
on public.purchases
for insert
to authenticated
with check (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);

drop policy if exists "purchases_update_company_manager" on public.purchases;

create policy "purchases_update_company_manager"
on public.purchases
for update
to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
)
with check (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);

drop policy if exists "purchases_delete_company_manager" on public.purchases;

create policy "purchases_delete_company_manager"
on public.purchases
for delete
to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);


-- ============================================================================
-- End of migration
-- ============================================================================

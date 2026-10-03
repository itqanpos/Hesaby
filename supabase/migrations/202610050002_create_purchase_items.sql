-- ============================================================================
-- Migration : 202610050002_create_purchase_items.sql
-- Phase     : 7 — Purchases Foundation
-- Purpose   : Line items of a purchase order. Each row references a
--             purchase, a product, and a unit, all belonging to the same
--             company (composite FKs).
-- Security  : RLS enabled. Simple role checks; the "only draft purchases
--             can be edited" rule is enforced by the trigger in migration 3
--             so that all validation lives in one place.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Table: public.purchase_items
-- ----------------------------------------------------------------------------

create table if not exists public.purchase_items (
  id          uuid          primary key default gen_random_uuid(),
  company_id  uuid          not null
                            references public.companies (id)
                            on delete cascade,
  purchase_id uuid          not null,
  product_id  uuid          not null,
  unit_id     uuid          not null,
  quantity    numeric(15,4) not null,
  unit_cost   numeric(15,4) not null,
  line_total  numeric(15,4) not null,
  notes       text,
  created_at  timestamptz   not null default now(),
  updated_at  timestamptz   not null default now(),

  -- Cross-tenant integrity: the purchase must belong to the same company.
  -- CASCADE: deleting a purchase removes its lines.
  constraint purchase_items_purchase_company_fk
    foreign key (purchase_id, company_id)
    references public.purchases (id, company_id)
    on delete cascade,

  -- Cross-tenant integrity: the product must belong to the same company.
  -- RESTRICT: a product referenced by a purchase line cannot be deleted.
  constraint purchase_items_product_company_fk
    foreign key (product_id, company_id)
    references public.products (id, company_id)
    on delete restrict,

  -- Cross-tenant integrity: the unit must belong to the same company.
  -- RESTRICT: a unit referenced by a purchase line cannot be deleted.
  constraint purchase_items_unit_company_fk
    foreign key (unit_id, company_id)
    references public.units (id, company_id)
    on delete restrict,

  constraint purchase_items_quantity_positive
    check (quantity > 0),

  constraint purchase_items_unit_cost_non_negative
    check (unit_cost >= 0),

  constraint purchase_items_line_total_non_negative
    check (line_total >= 0),

  constraint purchase_items_notes_length
    check (notes is null or char_length(notes) <= 1000)
);

comment on table  public.purchase_items              is
  'Line items of a purchase order.';
comment on column public.purchase_items.purchase_id  is
  'Parent purchase. Cascades on delete.';
comment on column public.purchase_items.product_id   is
  'Product being purchased. Must belong to the same company.';
comment on column public.purchase_items.unit_id      is
  'Unit of measure for this line. Must belong to the same company.';
comment on column public.purchase_items.quantity     is
  'Quantity purchased. Strictly positive. NUMERIC(15,4).';
comment on column public.purchase_items.unit_cost    is
  'Unit cost for this line. NUMERIC(15,4).';
comment on column public.purchase_items.line_total   is
  'Line total = quantity * unit_cost. NUMERIC(15,4).';


-- ----------------------------------------------------------------------------
-- Indexes
-- ----------------------------------------------------------------------------

create index if not exists idx_purchase_items_company_purchase
  on public.purchase_items (company_id, purchase_id);

create index if not exists idx_purchase_items_company_product
  on public.purchase_items (company_id, product_id);


-- ----------------------------------------------------------------------------
-- Trigger: keep updated_at fresh
-- ----------------------------------------------------------------------------

drop trigger if exists trg_purchase_items_set_updated_at
  on public.purchase_items;

create trigger trg_purchase_items_set_updated_at
before update on public.purchase_items
for each row
execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- Row Level Security
-- ----------------------------------------------------------------------------
-- SELECT : any active member of the company.
-- WRITE  : owner / admin / manager.
-- The "only draft purchases can be edited" rule is enforced by the trigger
-- in migration 3, so it lives in one place.
-- ----------------------------------------------------------------------------

alter table public.purchase_items enable row level security;

drop policy if exists "purchase_items_select_company_member"
  on public.purchase_items;

create policy "purchase_items_select_company_member"
on public.purchase_items
for select
to authenticated
using (public.is_company_member(company_id));

drop policy if exists "purchase_items_insert_company_manager"
  on public.purchase_items;

create policy "purchase_items_insert_company_manager"
on public.purchase_items
for insert
to authenticated
with check (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);

drop policy if exists "purchase_items_update_company_manager"
  on public.purchase_items;

create policy "purchase_items_update_company_manager"
on public.purchase_items
for update
to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
)
with check (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);

drop policy if exists "purchase_items_delete_company_manager"
  on public.purchase_items;

create policy "purchase_items_delete_company_manager"
on public.purchase_items
for delete
to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);


-- ============================================================================
-- End of migration
-- ============================================================================

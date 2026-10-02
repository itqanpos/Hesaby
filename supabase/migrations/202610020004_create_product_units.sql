-- ============================================================================
-- Migration : 202610020004_create_product_units.sql
-- Phase     : 4 — Product Catalog Foundation
-- Purpose   : Per-product unit conversions (e.g. 1 carton = 24 pieces). The
--             base unit of a product is products.default_unit_id; this table
--             stores only NON-base conversions.
-- Security  : RLS enabled. Cross-tenant integrity guaranteed by composite FKs
--             on both the product and the unit, so a product_unit row can
--             never mix company A's product with company B's unit.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Table: public.product_units
-- ----------------------------------------------------------------------------

create table if not exists public.product_units (
  id                 uuid          primary key default gen_random_uuid(),
  company_id         uuid          not null
                                   references public.companies (id)
                                   on delete cascade,
  product_id         uuid          not null,
  unit_id            uuid          not null,
  conversion_factor  numeric(15,6) not null,
  created_at         timestamptz   not null default now(),
  updated_at         timestamptz   not null default now(),

  -- Cross-tenant integrity: the product must belong to the same company as
  -- this row.
  constraint product_units_product_company_fk
    foreign key (product_id, company_id)
    references public.products (id, company_id)
    on delete cascade,

  -- Cross-tenant integrity: the unit must belong to the same company as
  -- this row.
  constraint product_units_unit_company_fk
    foreign key (unit_id, company_id)
    references public.units (id, company_id)
    on delete restrict,

  constraint product_units_conversion_factor_positive
    check (conversion_factor > 0),

  -- No duplicate (product, unit) conversions.
  constraint product_units_product_unit_unique
    unique (product_id, unit_id)
);

comment on table  public.product_units                    is
  'Non-base unit conversions per product. Base unit = products.default_unit_id.';
comment on column public.product_units.company_id         is
  'Owning company. Denormalised for RLS and composite FK enforcement.';
comment on column public.product_units.product_id         is
  'Product this conversion applies to. Cascades on delete.';
comment on column public.product_units.unit_id            is
  'Non-base unit that the product can be sold/purchased in.';
comment on column public.product_units.conversion_factor  is
  'How many base units equal one unit. Always > 0. NUMERIC(15,6).';


-- ----------------------------------------------------------------------------
-- Indexes
-- ----------------------------------------------------------------------------

create index if not exists idx_product_units_company
  on public.product_units (company_id);

create index if not exists idx_product_units_product
  on public.product_units (product_id);

create index if not exists idx_product_units_unit
  on public.product_units (unit_id);


-- ----------------------------------------------------------------------------
-- Trigger: keep updated_at fresh
-- ----------------------------------------------------------------------------

drop trigger if exists trg_product_units_set_updated_at
  on public.product_units;

create trigger trg_product_units_set_updated_at
before update on public.product_units
for each row
execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- Trigger: reject rows that would duplicate the product's base unit
-- ----------------------------------------------------------------------------
-- The base unit of a product is products.default_unit_id. Storing it here
-- with a conversion factor of 1 would be redundant and could drift out of
-- sync. The trigger rejects such rows with a clear error.
-- The function is SECURITY INVOKER (it only reads products under the caller's
-- privileges) and pins search_path for deterministic resolution.
-- ----------------------------------------------------------------------------

create or replace function public.check_product_unit_not_base()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_default_unit_id uuid;
begin
  select default_unit_id into v_default_unit_id
    from public.products
   where id = new.product_id;

  if v_default_unit_id is null then
    -- The FK will catch a missing product; nothing to check here.
    return new;
  end if;

  if v_default_unit_id = new.unit_id then
    raise exception
      'The base unit of product % cannot also appear in product_units.',
      new.product_id
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

comment on function public.check_product_unit_not_base() is
  'Rejects product_units rows whose unit is the product''s base unit.';

drop trigger if exists trg_product_units_check_not_base
  on public.product_units;

create trigger trg_product_units_check_not_base
before insert or update on public.product_units
for each row
execute function public.check_product_unit_not_base();


-- ----------------------------------------------------------------------------
-- Row Level Security
-- ----------------------------------------------------------------------------

alter table public.product_units enable row level security;

drop policy if exists "product_units_select_company_member"
  on public.product_units;

create policy "product_units_select_company_member"
on public.product_units
for select
to authenticated
using (public.is_company_member(company_id));

drop policy if exists "product_units_insert_company_manager"
  on public.product_units;

create policy "product_units_insert_company_manager"
on public.product_units
for insert
to authenticated
with check (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);

drop policy if exists "product_units_update_company_manager"
  on public.product_units;

create policy "product_units_update_company_manager"
on public.product_units
for update
to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
)
with check (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);

drop policy if exists "product_units_delete_company_manager"
  on public.product_units;

create policy "product_units_delete_company_manager"
on public.product_units
for delete
to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);


-- ----------------------------------------------------------------------------
-- End of migration
-- ----------------------------------------------------------------------------

-- ============================================================================
-- Migration : 202610020003_create_products.sql
-- Phase     : 4 — Product Catalog Foundation
-- Purpose   : Products, scoped to a company, optionally linked to a category
--             and always linked to a default unit. Cross-tenant protection is
--             enforced at the database level via composite foreign keys.
-- Security  : RLS enabled. Cross-tenant integrity guaranteed by composite FKs
--             (products.category_id, products.company_id) ->
--             (categories.id, categories.company_id)
--             and
--             (products.default_unit_id, products.company_id) ->
--             (units.id, units.company_id).
--             A product of company A can never reference a category or unit
--             belonging to company B, even if a malicious client forges the
--             company_id.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Table: public.products
-- ----------------------------------------------------------------------------

create table if not exists public.products (
  id                 uuid          primary key default gen_random_uuid(),
  company_id         uuid          not null
                                   references public.companies (id)
                                   on delete cascade,
  category_id        uuid,
  default_unit_id    uuid          not null,
  name               text          not null,
  sku                text,
  barcode            text,
  description        text,
  cost_price         numeric(15,4) not null default 0,
  selling_price      numeric(15,4) not null default 0,
  min_selling_price  numeric(15,4),
  tax_rate           numeric(5,2),
  is_active          boolean       not null default true,
  created_at         timestamptz   not null default now(),
  updated_at         timestamptz   not null default now(),

  -- Cross-tenant integrity: the category (when set) must belong to the
  -- same company as the product. MATCH SIMPLE semantics skip the check
  -- when category_id is NULL.
  constraint products_category_company_fk
    foreign key (category_id, company_id)
    references public.categories (id, company_id)
    on delete restrict,

  -- Cross-tenant integrity: the default unit must belong to the same
  -- company as the product.
  constraint products_default_unit_company_fk
    foreign key (default_unit_id, company_id)
    references public.units (id, company_id)
    on delete restrict,

  constraint products_name_length
    check (char_length(trim(name)) between 1 and 200),
  constraint products_sku_length
    check (sku is null or (char_length(trim(sku)) between 1 and 64)),
  constraint products_barcode_length
    check (barcode is null or (char_length(trim(barcode)) between 1 and 64)),
  constraint products_description_length
    check (description is null or char_length(description) <= 2000),

  constraint products_cost_price_non_negative
    check (cost_price >= 0),
  constraint products_selling_price_non_negative
    check (selling_price >= 0),
  constraint products_min_selling_price_non_negative
    check (min_selling_price is null or min_selling_price >= 0),
  constraint products_tax_rate_range
    check (tax_rate is null or (tax_rate >= 0 and tax_rate <= 100)),

  -- Composite uniqueness enables a composite FK from product_units so that
  -- a product_units row can be forced to reference a product of the same
  -- company.
  constraint products_id_company_unique
    unique (id, company_id)
);

comment on table  public.products                       is
  'Products, scoped to a company. Foundation for Phase 4 catalog.';
comment on column public.products.company_id            is
  'Owning company. Cascades on delete.';
comment on column public.products.category_id           is
  'Optional category. When set, enforced to belong to the same company.';
comment on column public.products.default_unit_id       is
  'Default selling/base unit. Must belong to the same company.';
comment on column public.products.sku                   is
  'Optional stock keeping unit. Unique per company when present.';
comment on column public.products.barcode               is
  'Optional barcode. Stored as data only in Phase 4 (no scanning).';
comment on column public.products.cost_price            is
  'Cost price. NUMERIC(15,4) — never floating point.';
comment on column public.products.selling_price         is
  'Default selling price. NUMERIC(15,4).';
comment on column public.products.min_selling_price     is
  'Optional floor price. NUMERIC(15,4).';
comment on column public.products.tax_rate              is
  'Optional tax percentage, 0–100. NUMERIC(5,2).';
comment on column public.products.is_active             is
  'Soft-disable flag. Inactive products remain in the DB but are hidden from active workflows.';


-- ----------------------------------------------------------------------------
-- Indexes
-- ----------------------------------------------------------------------------

-- Partial unique indexes: SKU and Barcode are unique per company only among
-- rows that actually carry a value.
create unique index if not exists uniq_products_company_sku
  on public.products (company_id, sku)
  where sku is not null;

create unique index if not exists uniq_products_company_barcode
  on public.products (company_id, barcode)
  where barcode is not null;

-- Common filtering / listing patterns.
create index if not exists idx_products_company_active
  on public.products (company_id, is_active);

create index if not exists idx_products_company_name
  on public.products (company_id, name);

create index if not exists idx_products_company_category
  on public.products (company_id, category_id);

create index if not exists idx_products_company_unit
  on public.products (company_id, default_unit_id);


-- ----------------------------------------------------------------------------
-- Trigger: keep updated_at fresh
-- ----------------------------------------------------------------------------

drop trigger if exists trg_products_set_updated_at on public.products;

create trigger trg_products_set_updated_at
before update on public.products
for each row
execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- Row Level Security
-- ----------------------------------------------------------------------------

alter table public.products enable row level security;

drop policy if exists "products_select_company_member" on public.products;

create policy "products_select_company_member"
on public.products
for select
to authenticated
using (public.is_company_member(company_id));

drop policy if exists "products_insert_company_manager" on public.products;

create policy "products_insert_company_manager"
on public.products
for insert
to authenticated
with check (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);

drop policy if exists "products_update_company_manager" on public.products;

create policy "products_update_company_manager"
on public.products
for update
to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
)
with check (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);

drop policy if exists "products_delete_company_manager" on public.products;

create policy "products_delete_company_manager"
on public.products
for delete
to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);


-- ----------------------------------------------------------------------------
-- End of migration
-- ----------------------------------------------------------------------------

-- ============================================================================
-- Migration : 202610020002_create_units.sql
-- Phase     : 4 — Product Catalog Foundation
-- Purpose   : Units of measurement (piece, carton, kilogram, ...). Each unit
--             belongs to exactly one company and inherits tenant isolation
--             through the membership helpers defined in Phase 2.
-- Security  : RLS enabled. Access is derived from auth.uid() and
--             company_members — never from client-supplied company_id.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Table: public.units
-- ----------------------------------------------------------------------------

create table if not exists public.units (
  id          uuid        primary key default gen_random_uuid(),
  company_id  uuid        not null
                          references public.companies (id) on delete cascade,
  name        text        not null,
  symbol      text,
  is_active   boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint units_name_length
    check (char_length(trim(name)) between 1 and 100),
  constraint units_symbol_length
    check (symbol is null or (char_length(trim(symbol)) between 1 and 20)),

  -- Name is unique per company.
  constraint units_company_name_unique
    unique (company_id, name),

  -- Composite uniqueness enables composite FKs from products and
  -- product_units so a unit reference is guaranteed to belong to the same
  -- company as the referencing row.
  constraint units_id_company_unique
    unique (id, company_id)
);

comment on table  public.units             is
  'Units of measurement, scoped to a company. Foundation for Phase 4 catalog.';
comment on column public.units.company_id  is
  'Owning company. Cascades on delete.';
comment on column public.units.name        is
  'Display name. Unique per company. Trimmed, 1–100 characters.';
comment on column public.units.symbol      is
  'Optional short symbol (e.g. "kg"). Unique per company when present.';
comment on column public.units.is_active   is
  'Soft-disable flag. Inactive units remain in the DB but are hidden from active workflows.';


-- ----------------------------------------------------------------------------
-- Indexes
-- ----------------------------------------------------------------------------

-- Partial unique index: symbol is unique per company only among rows that
-- actually carry a symbol. Units without a symbol do not collide.
create unique index if not exists uniq_units_company_symbol
  on public.units (company_id, symbol)
  where symbol is not null;

create index if not exists idx_units_company_active
  on public.units (company_id, is_active);

create index if not exists idx_units_company_name
  on public.units (company_id, name);


-- ----------------------------------------------------------------------------
-- Trigger: keep updated_at fresh
-- ----------------------------------------------------------------------------

drop trigger if exists trg_units_set_updated_at on public.units;

create trigger trg_units_set_updated_at
before update on public.units
for each row
execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- Row Level Security
-- ----------------------------------------------------------------------------

alter table public.units enable row level security;

drop policy if exists "units_select_company_member" on public.units;

create policy "units_select_company_member"
on public.units
for select
to authenticated
using (public.is_company_member(company_id));

drop policy if exists "units_insert_company_manager" on public.units;

create policy "units_insert_company_manager"
on public.units
for insert
to authenticated
with check (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);

drop policy if exists "units_update_company_manager" on public.units;

create policy "units_update_company_manager"
on public.units
for update
to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
)
with check (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);

drop policy if exists "units_delete_company_manager" on public.units;

create policy "units_delete_company_manager"
on public.units
for delete
to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);


-- ----------------------------------------------------------------------------
-- End of migration
-- ----------------------------------------------------------------------------

-- ============================================================================
-- Migration : 202610020001_create_categories.sql
-- Phase     : 4 — Product Catalog Foundation
-- Purpose   : Product categories, scoped to a company. Each category belongs
--             to exactly one company and inherits tenant isolation through
--             the membership helpers defined in Phase 2.
-- Security  : RLS enabled. Access is derived from auth.uid() and
--             company_members — never from client-supplied company_id.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Table: public.categories
-- ----------------------------------------------------------------------------

create table if not exists public.categories (
  id          uuid        primary key default gen_random_uuid(),
  company_id  uuid        not null
                          references public.companies (id) on delete cascade,
  name        text        not null,
  description text,
  sort_order  integer     not null default 0,
  is_active   boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint categories_name_length
    check (char_length(trim(name)) between 1 and 200),
  constraint categories_description_length
    check (description is null or char_length(description) <= 500),
  constraint categories_sort_order_range
    check (sort_order between -1000000 and 1000000),

  -- Name is unique per company.
  constraint categories_company_name_unique
    unique (company_id, name),

  -- Composite uniqueness enables a composite FK from products so that a
  -- product's category is guaranteed to belong to the same company.
  constraint categories_id_company_unique
    unique (id, company_id)
);

comment on table  public.categories                    is
  'Product categories, scoped to a company. Foundation for Phase 4 catalog.';
comment on column public.categories.company_id         is
  'Owning company. Cascades on delete.';
comment on column public.categories.name               is
  'Display name. Unique per company. Trimmed, 1–200 characters.';
comment on column public.categories.sort_order         is
  'UI ordering hint. Defaults to 0; ties are broken by name.';
comment on column public.categories.is_active          is
  'Soft-disable flag. Inactive categories remain in the DB but are hidden from active workflows.';


-- ----------------------------------------------------------------------------
-- Indexes
-- ----------------------------------------------------------------------------

create index if not exists idx_categories_company_active
  on public.categories (company_id, is_active);

create index if not exists idx_categories_company_sort
  on public.categories (company_id, sort_order, name);


-- ----------------------------------------------------------------------------
-- Trigger: keep updated_at fresh
-- ----------------------------------------------------------------------------

drop trigger if exists trg_categories_set_updated_at on public.categories;

create trigger trg_categories_set_updated_at
before update on public.categories
for each row
execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- Row Level Security
-- ----------------------------------------------------------------------------
-- SELECT  : any active member of the company can read its categories.
-- WRITE   : owner / admin / manager can insert, update or delete.
-- ----------------------------------------------------------------------------

alter table public.categories enable row level security;

drop policy if exists "categories_select_company_member"
  on public.categories;

create policy "categories_select_company_member"
on public.categories
for select
to authenticated
using (public.is_company_member(company_id));

drop policy if exists "categories_insert_company_manager"
  on public.categories;

create policy "categories_insert_company_manager"
on public.categories
for insert
to authenticated
with check (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);

drop policy if exists "categories_update_company_manager"
  on public.categories;

create policy "categories_update_company_manager"
on public.categories
for update
to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
)
with check (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);

drop policy if exists "categories_delete_company_manager"
  on public.categories;

create policy "categories_delete_company_manager"
on public.categories
for delete
to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);


-- ----------------------------------------------------------------------------
-- End of migration
-- ----------------------------------------------------------------------------

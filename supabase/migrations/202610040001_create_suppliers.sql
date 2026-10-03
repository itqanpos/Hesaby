-- ============================================================================
-- Migration : 202610040001_create_suppliers.sql
-- Phase     : 6 — Suppliers Foundation
-- Purpose   : Suppliers of a company (who we buy from). Foundation for
--             Phase 7 (Purchases), which will reference this table via a
--             composite FK on (supplier_id, company_id).
-- Security  : RLS enabled. Access is derived from auth.uid() and
--             company_members — never from client-supplied company_id.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Table: public.suppliers
-- ----------------------------------------------------------------------------

create table if not exists public.suppliers (
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

  constraint suppliers_name_length
    check (char_length(trim(name)) between 1 and 200),
  constraint suppliers_code_length
    check (code is null or (char_length(trim(code)) between 1 and 64)),
  constraint suppliers_phone_length
    check (phone is null or (char_length(trim(phone)) between 1 and 30)),
  constraint suppliers_email_length
    check (email is null or (char_length(trim(email)) between 1 and 255)),
  constraint suppliers_address_length
    check (address is null or char_length(address) <= 500),
  constraint suppliers_notes_length
    check (notes is null or char_length(notes) <= 2000),

  -- Name is unique per company.
  constraint suppliers_company_name_unique
    unique (company_id, name),

  -- Composite uniqueness enables a composite FK from `purchases`
  -- (Phase 7) so a purchase can never reference a supplier of another
  -- company.
  constraint suppliers_id_company_unique
    unique (id, company_id)
);

comment on table  public.suppliers              is
  'Suppliers of a company. Foundation for Phase 7 (Purchases).';
comment on column public.suppliers.company_id   is
  'Owning company. Cascades on delete.';
comment on column public.suppliers.name         is
  'Display name. Unique per company. Trimmed, 1–200 characters.';
comment on column public.suppliers.code         is
  'Optional internal code (e.g. SUP-001). Unique per company when present.';
comment on column public.suppliers.phone        is
  'Optional contact phone. Unique per company when present.';
comment on column public.suppliers.email        is
  'Optional contact email. Not unique (several suppliers may share one).';
comment on column public.suppliers.is_active    is
  'Soft-disable flag. Inactive suppliers remain in the DB but are hidden from active workflows.';


-- ----------------------------------------------------------------------------
-- Indexes
-- ----------------------------------------------------------------------------

-- Partial unique indexes: `code` and `phone` are unique per company only
-- among rows that actually carry a value. Multiple suppliers without a code
-- or phone do not collide.
create unique index if not exists uniq_suppliers_company_code
  on public.suppliers (company_id, code)
  where code is not null;

create unique index if not exists uniq_suppliers_company_phone
  on public.suppliers (company_id, phone)
  where phone is not null;

create index if not exists idx_suppliers_company_active
  on public.suppliers (company_id, is_active);

create index if not exists idx_suppliers_company_name
  on public.suppliers (company_id, name);


-- ----------------------------------------------------------------------------
-- Trigger: keep updated_at fresh
-- ----------------------------------------------------------------------------

drop trigger if exists trg_suppliers_set_updated_at on public.suppliers;

create trigger trg_suppliers_set_updated_at
before update on public.suppliers
for each row
execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- Row Level Security
-- ----------------------------------------------------------------------------
-- SELECT : any active member of the company.
-- WRITE  : owner / admin / manager.
-- ----------------------------------------------------------------------------

alter table public.suppliers enable row level security;

drop policy if exists "suppliers_select_company_member" on public.suppliers;

create policy "suppliers_select_company_member"
on public.suppliers
for select
to authenticated
using (public.is_company_member(company_id));

drop policy if exists "suppliers_insert_company_manager" on public.suppliers;

create policy "suppliers_insert_company_manager"
on public.suppliers
for insert
to authenticated
with check (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);

drop policy if exists "suppliers_update_company_manager" on public.suppliers;

create policy "suppliers_update_company_manager"
on public.suppliers
for update
to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
)
with check (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);

drop policy if exists "suppliers_delete_company_manager" on public.suppliers;

create policy "suppliers_delete_company_manager"
on public.suppliers
for delete
to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
);


-- ============================================================================
-- End of migration
-- ============================================================================

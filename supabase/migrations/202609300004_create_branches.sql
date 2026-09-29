-- ============================================================================
-- Migration : 202609300004_create_branches.sql
-- Phase     : 2 — Multi-Tenant Database Foundation
-- Purpose   : Create the `branches` table. A branch belongs to exactly one
--             company and inherits its tenant isolation through the parent
--             company's membership. Branches are the scope unit that future
--             phases (sales, inventory, POS) will attach to.
-- Security  : RLS is enabled and every policy is expressed in terms of the
--             parent company's membership helper functions. The client can
--             never widen access by supplying a branch_id or company_id of
--             its own choosing: the database derives the truth from
--             auth.uid() and `company_members`.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table: public.branches
-- ----------------------------------------------------------------------------
-- Belongs to a company. Never carries credentials or authentication data.
-- `code` is optional but, when present, must be unique per company (e.g.
-- "CAI-01", "ALX-01"). `name` must be unique per company.
-- ----------------------------------------------------------------------------

create table if not exists public.branches (
  id          uuid        primary key default gen_random_uuid(),
  company_id  uuid        not null
                          references public.companies (id) on delete cascade,
  name        text        not null,
  code        text,
  address     text,
  phone       text,
  is_active   boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint branches_name_length
    check (char_length(trim(name)) between 1 and 200),
  constraint branches_code_format
    check (code is null or (char_length(code) between 1 and 32
                            and trim(code) <> '')),
  constraint branches_address_length
    check (address is null or char_length(address) <= 500),
  constraint branches_phone_length
    check (phone is null or char_length(phone) <= 30),
  constraint branches_company_name_unique
    unique (company_id, name)
);

comment on table  public.branches             is
  'Branches belonging to a company. The scope unit for future business tables.';
comment on column public.branches.company_id  is
  'Owning company. Cascades on delete.';
comment on column public.branches.name        is
  'Display name of the branch. Unique per company.';
comment on column public.branches.code        is
  'Optional short code, unique per company when present.';
comment on column public.branches.is_active   is
  'Soft-disable flag. Inactive branches retain their data but are hidden from active workflows.';

-- Partial unique index: enforce code uniqueness only among rows that
-- actually carry a code. NULL codes (branches without a short code) do not
-- collide with each other.
create unique index if not exists uniq_branches_company_code
  on public.branches (company_id, code)
  where code is not null;

-- Index on company_id is required so that `on delete cascade` from
-- `companies` is efficient, and so the common "list branches of company X"
-- query served to RLS is backed by an index. The unique constraint on
-- (company_id, name) already provides a covering index for those two
-- columns, but a plain (company_id) index keeps the FK maintenance cheap.
create index if not exists idx_branches_company_id
  on public.branches (company_id);


-- ----------------------------------------------------------------------------
-- Trigger: keep branches.updated_at fresh
-- ----------------------------------------------------------------------------

drop trigger if exists trg_branches_set_updated_at on public.branches;

create trigger trg_branches_set_updated_at
before update on public.branches
for each row
execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- Row Level Security: public.branches
-- ----------------------------------------------------------------------------

alter table public.branches enable row level security;

-- SELECT: any active member of the parent company can read its branches.
drop policy if exists "branches_select_company_member" on public.branches;

create policy "branches_select_company_member"
on public.branches
for select
to authenticated
using (public.is_company_member(company_id));

-- INSERT: only owners and admins of the parent company can create a branch.
-- The WITH CHECK ensures the row's company_id is a company the caller
-- actually administers; a caller cannot attach a branch to a foreign company.
drop policy if exists "branches_insert_company_admin" on public.branches;

create policy "branches_insert_company_admin"
on public.branches
for insert
to authenticated
with check (
  public.has_company_role(company_id, array['owner', 'admin'])
);

-- UPDATE: only owners and admins of the parent company can modify a branch.
-- Both USING and WITH CHECK are required so a caller cannot reassign a
-- branch to a different company they do not administer.
drop policy if exists "branches_update_company_admin" on public.branches;

create policy "branches_update_company_admin"
on public.branches
for update
to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin'])
)
with check (
  public.has_company_role(company_id, array['owner', 'admin'])
);

-- DELETE: only owners and admins of the parent company can remove a branch.
drop policy if exists "branches_delete_company_admin" on public.branches;

create policy "branches_delete_company_admin"
on public.branches
for delete
to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin'])
);


-- ----------------------------------------------------------------------------
-- End of migration
-- ----------------------------------------------------------------------------

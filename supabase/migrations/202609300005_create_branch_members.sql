-- ============================================================================
-- Migration : 202609300005_create_branch_members.sql
-- Phase     : 2 — Multi-Tenant Database Foundation
-- Purpose   : Introduce branch-level membership. A company member can be
--             assigned to zero, one, or many branches. This table is the
--             foundation that later phases will use to scope business data
--             (sales, inventory, POS, reports) to specific branches.
-- Security  : RLS enforced. Two composite foreign keys guarantee, at the
--             database level, that a branch-member row can only reference
--             a (company, user) pair that is a real company membership and
--             a (company, branch) pair that belongs to the same company.
--             A malicious client cannot fabricate a cross-tenant link.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Prerequisite: composite uniqueness on public.branches
-- ----------------------------------------------------------------------------
-- The composite FK below references branches(company_id, id). PostgreSQL
-- requires a unique constraint on the referenced columns. Since `id` is
-- already the primary key, `(company_id, id)` is trivially unique; the
-- constraint is added solely to enable the FK and is idempotent.
-- ----------------------------------------------------------------------------

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname    = 'branches_company_id_id_unique'
       and conrelid   = 'public.branches'::regclass
  ) then
    alter table public.branches
      add constraint branches_company_id_id_unique
      unique (company_id, id);
  end if;
end $$;


-- ----------------------------------------------------------------------------
-- Table: public.branch_members
-- ----------------------------------------------------------------------------
-- (branch_id, user_id) is unique: a user is assigned to a branch at most
-- once. `company_id` is stored explicitly (not derived by join) so that:
--   * the composite FKs can enforce both invariants declaratively;
--   * RLS policies and future queries can filter by company without a join.
-- ----------------------------------------------------------------------------

create table if not exists public.branch_members (
  id          uuid        primary key default gen_random_uuid(),
  company_id  uuid        not null,
  branch_id   uuid        not null,
  user_id     uuid        not null,
  is_active   boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  -- The (company_id, user_id) pair must be an existing company membership.
  -- Cascades when the membership is removed.
  constraint branch_members_membership_fk
    foreign key (company_id, user_id)
    references public.company_members (company_id, user_id)
    on delete cascade,

  -- The (company_id, branch_id) pair must point to a branch of the same
  -- company. Cascades when the branch is removed.
  constraint branch_members_branch_fk
    foreign key (company_id, branch_id)
    references public.branches (company_id, id)
    on delete cascade,

  -- A user can be assigned to a given branch at most once.
  constraint branch_members_unique_assignment
    unique (branch_id, user_id)
);

comment on table  public.branch_members             is
  'Branch-level assignments. A company member may be assigned to one or more branches. The foundation for branch-scoped authorization.';
comment on column public.branch_members.company_id  is
  'Owning company. Redundant with branch_id.company_id, but stored so composite FKs and RLS can enforce tenant consistency without joins.';
comment on column public.branch_members.branch_id   is
  'Assigned branch. Must belong to the same company as (company_id).';
comment on column public.branch_members.user_id     is
  'Assigned user. Must be an active or inactive member of (company_id) via company_members.';
comment on column public.branch_members.is_active   is
  'Soft-disable flag. Inactive assignments are ignored by has_branch_access checks.';

-- Support indexes for the composite foreign keys. PostgreSQL does not
-- create indexes automatically for FK columns, and both FKs need them for
-- efficient cascade maintenance and for the access patterns below:
--   * idx_branch_members_company_user   -> "which branches can user X access
--                                            inside company Y?"
--   * idx_branch_members_company_branch -> "which users are assigned to
--                                            branch B?"  (RLS filters by
--                                            company first)
-- The unique constraint (branch_id, user_id) already indexes "members of
-- branch B" directly, but the composite index keeps FK maintenance cheap.
create index if not exists idx_branch_members_company_user
  on public.branch_members (company_id, user_id);

create index if not exists idx_branch_members_company_branch
  on public.branch_members (company_id, branch_id);


-- ----------------------------------------------------------------------------
-- Trigger: keep branch_members.updated_at fresh
-- ----------------------------------------------------------------------------

drop trigger if exists trg_branch_members_set_updated_at
  on public.branch_members;

create trigger trg_branch_members_set_updated_at
before update on public.branch_members
for each row
execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- Helper function: is_branch_member(uuid)
-- ----------------------------------------------------------------------------
-- Used by future migrations (Phase 3+) to scope business tables to branches
-- the current user is assigned to. Runs as SECURITY DEFINER with a pinned
-- search_path, exactly like the company helpers in migration 3, so that it
-- can be called from RLS policies on unrelated tables without recursion and
-- without search_path based privilege escalation.
-- ----------------------------------------------------------------------------

create or replace function public.is_branch_member(p_branch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
      from public.branch_members bm
     where bm.branch_id = p_branch_id
       and bm.user_id   = auth.uid()
       and bm.is_active = true
  );
$$;

comment on function public.is_branch_member(uuid) is
  'True when auth.uid() has an active branch assignment for the given branch.';


-- ----------------------------------------------------------------------------
-- Row Level Security: public.branch_members
-- ----------------------------------------------------------------------------

alter table public.branch_members enable row level security;

-- SELECT: any active member of the parent company can read the branch
-- assignments of that company. Phase 2 keeps this intentionally broad so
-- that team management UIs can list assignments. Phase 3+ may narrow it to
-- "own assignments only" or "assignments of branches I manage" without any
-- schema change, because every access decision goes through the same
-- membership helpers.
drop policy if exists "branch_members_select_company_member"
  on public.branch_members;

create policy "branch_members_select_company_member"
on public.branch_members
for select
to authenticated
using (public.is_company_member(company_id));

-- INSERT: only owners and admins of the parent company can assign members
-- to branches. The composite FK already guarantees the (company, user) and
-- (company, branch) invariants; this policy adds the authorization layer
-- on top.
drop policy if exists "branch_members_insert_company_admin"
  on public.branch_members;

create policy "branch_members_insert_company_admin"
on public.branch_members
for insert
to authenticated
with check (
  public.has_company_role(company_id, array['owner', 'admin'])
);

-- UPDATE: only owners and admins can modify an assignment. USING and
-- WITH CHECK are both required so an admin cannot reassign a row into a
-- company they do not administer.
drop policy if exists "branch_members_update_company_admin"
  on public.branch_members;

create policy "branch_members_update_company_admin"
on public.branch_members
for update
to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin'])
)
with check (
  public.has_company_role(company_id, array['owner', 'admin'])
);

-- DELETE: only owners and admins can remove an assignment.
drop policy if exists "branch_members_delete_company_admin"
  on public.branch_members;

create policy "branch_members_delete_company_admin"
on public.branch_members
for delete
to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin'])
);


-- ----------------------------------------------------------------------------
-- End of migration
-- ----------------------------------------------------------------------------

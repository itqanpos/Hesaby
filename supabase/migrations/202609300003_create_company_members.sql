-- ============================================================================
-- Migration : 202609300003_create_company_members.sql
-- Phase     : 2 — Multi-Tenant Database Foundation
-- Purpose   : Create `company_members` (the tenant access list), add the
--             helper functions that drive tenant isolation, install the RLS
--             policies on `company_members`, and finally install the
--             membership-based policies on `companies` that were deferred
--             from migration 2.
-- Security  : RLS on every table. Helper functions run as SECURITY DEFINER
--             with a pinned search_path to avoid recursion and privilege
--             escalation. The database — not the client — decides access.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Table: public.company_members
-- ----------------------------------------------------------------------------
-- Associates an authenticated user with a company, carrying the user's role
-- inside that company. `(company_id, user_id)` is unique: a user has at most
-- one membership row per company.
--
-- Tenant isolation lives here: this table is the authoritative answer to
-- "which companies can this user access, and with what role?".
-- ----------------------------------------------------------------------------

create table if not exists public.company_members (
  id          uuid        primary key default gen_random_uuid(),
  company_id  uuid        not null
                          references public.companies (id) on delete cascade,
  user_id     uuid        not null
                          references auth.users (id) on delete cascade,
  role        text        not null,
  is_active   boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint company_members_role_valid
    check (role in ('owner', 'admin', 'manager', 'cashier', 'inventory_clerk')),
  constraint company_members_unique_membership
    unique (company_id, user_id)
);

comment on table  public.company_members             is
  'Tenant access list. One row per (company, user) pair. Authoritative for tenant isolation.';
comment on column public.company_members.company_id  is
  'Owning company. Cascades on delete.';
comment on column public.company_members.user_id     is
  'Authenticated user (auth.users.id). Cascades on delete.';
comment on column public.company_members.role        is
  'Foundational role: owner, admin, manager, cashier, inventory_clerk.';
comment on column public.company_members.is_active   is
  'Active membership flag. Inactive members lose all access immediately.';

-- Secondary index on user_id is required so that `on delete cascade` from
-- auth.users is efficient, and so the common "which companies am I in?"
-- query is served by an index. The unique constraint already covers
-- (company_id, user_id), which also serves "members of a company" queries.
create index if not exists idx_company_members_user_id
  on public.company_members (user_id);


-- ----------------------------------------------------------------------------
-- Trigger: keep company_members.updated_at fresh
-- ----------------------------------------------------------------------------

drop trigger if exists trg_company_members_set_updated_at
  on public.company_members;

create trigger trg_company_members_set_updated_at
before update on public.company_members
for each row
execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- Trigger: protect the last active owner of a company
-- ----------------------------------------------------------------------------
-- A company whose active owners have all been removed or demoted would be
-- orphaned: no member could ever administer it again without service_role
-- intervention. This trigger forbids reaching that state.
--
-- Concurrency: the trigger takes a row lock on the company before counting,
-- so two simultaneous demotions of the company's last two owners cannot
-- both succeed.
--
-- The function is SECURITY INVOKER: it only needs to write the lock and to
-- count rows. Both are legitimate for the caller's role, and the fixed
-- search_path keeps resolution deterministic.
-- ----------------------------------------------------------------------------

create or replace function public.guard_last_active_owner()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_company_id        uuid;
  v_remaining_owners  int;
begin
  -- Only an active owner row can trigger the guard.
  if old.role <> 'owner' or old.is_active = false then
    return coalesce(new, old);
  end if;

  -- UPDATE that leaves the row as an active owner in the same company
  -- cannot orphan the company.
  if tg_op = 'UPDATE'
     and new.role = 'owner'
     and new.is_active = true
     and new.company_id = old.company_id then
    return new;
  end if;

  v_company_id := old.company_id;

  -- Serialise concurrent operations affecting this company's members.
  perform 1
    from public.companies
   where id = v_company_id
     for update;

  select count(*) into v_remaining_owners
    from public.company_members
   where company_id = v_company_id
     and role       = 'owner'
     and is_active  = true
     and id        <> old.id;

  if v_remaining_owners = 0 then
    raise exception
      'Cannot remove or demote the last active owner of company %',
      v_company_id
      using errcode = 'check_violation';
  end if;

  return coalesce(new, old);
end;
$$;

comment on function public.guard_last_active_owner() is
  'Prevents UPDATE/DELETE from leaving a company without any active owner.';

drop trigger if exists trg_company_members_guard_owner
  on public.company_members;

create trigger trg_company_members_guard_owner
before update or delete on public.company_members
for each row
execute function public.guard_last_active_owner();


-- ----------------------------------------------------------------------------
-- Helper functions used by Row Level Security policies
-- ----------------------------------------------------------------------------
-- Both functions:
--   * run as SECURITY DEFINER so RLS policies on `company_members` can call
--     them without entering infinite recursion;
--   * pin search_path to prevent search_path based privilege escalation;
--   * rely exclusively on auth.uid() (the JWT identity) and never on
--     client-supplied ids.
-- ----------------------------------------------------------------------------

-- is_company_member: is the current user an ACTIVE member of this company?
create or replace function public.is_company_member(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
      from public.company_members cm
     where cm.company_id = p_company_id
       and cm.user_id    = auth.uid()
       and cm.is_active  = true
  );
$$;

comment on function public.is_company_member(uuid) is
  'True when auth.uid() is an active member of the given company.';

-- has_company_role: does the current user hold ANY of the given roles,
-- with an active membership in this company?
create or replace function public.has_company_role(
  p_company_id uuid,
  p_roles      text[]
)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
      from public.company_members cm
     where cm.company_id = p_company_id
       and cm.user_id    = auth.uid()
       and cm.is_active  = true
       and cm.role       = any (p_roles)
  );
$$;

comment on function public.has_company_role(uuid, text[]) is
  'True when auth.uid() has an active membership in the company with one of the given roles.';


-- ----------------------------------------------------------------------------
-- Row Level Security: public.company_members
-- ----------------------------------------------------------------------------

alter table public.company_members enable row level security;

-- SELECT: an active member of a company can see the other members of the
-- same company. This is what allows an admin to list the team.
drop policy if exists "company_members_select_same_company"
  on public.company_members;

create policy "company_members_select_same_company"
on public.company_members
for select
to authenticated
using (public.is_company_member(company_id));

-- INSERT: only owners and admins of the target company can add members.
drop policy if exists "company_members_insert_admin"
  on public.company_members;

create policy "company_members_insert_admin"
on public.company_members
for insert
to authenticated
with check (
  public.has_company_role(company_id, array['owner', 'admin'])
);

-- UPDATE: only owners and admins of the target company can modify a member.
-- The WITH CHECK re-evaluates against the NEW row so a caller cannot move a
-- row into a company they do not administer.
drop policy if exists "company_members_update_admin"
  on public.company_members;

create policy "company_members_update_admin"
on public.company_members
for update
to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin'])
)
with check (
  public.has_company_role(company_id, array['owner', 'admin'])
);

-- DELETE: only owners and admins of the target company can remove a member.
drop policy if exists "company_members_delete_admin"
  on public.company_members;

create policy "company_members_delete_admin"
on public.company_members
for delete
to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin'])
);


-- ----------------------------------------------------------------------------
-- Row Level Security: public.companies  (policies deferred from migration 2)
-- ----------------------------------------------------------------------------
-- RLS was already enabled on `companies` in migration 2. Now that membership
-- exists, the read and update policies can be expressed in terms of it.
--
-- No INSERT or DELETE policy is created: companies are provisioned and
-- removed exclusively by trusted server-side flows (a future onboarding
-- Edge Function using service_role), never directly by the client SDK.
-- ----------------------------------------------------------------------------

-- SELECT: an active member of a company can read that company's row.
drop policy if exists "companies_select_member" on public.companies;

create policy "companies_select_member"
on public.companies
for select
to authenticated
using (public.is_company_member(id));

-- UPDATE: only owners and admins of the company can update it.
drop policy if exists "companies_update_admin" on public.companies;

create policy "companies_update_admin"
on public.companies
for update
to authenticated
using (public.has_company_role(id, array['owner', 'admin']))
with check (public.has_company_role(id, array['owner', 'admin']));


-- ----------------------------------------------------------------------------
-- End of migration
-- ----------------------------------------------------------------------------

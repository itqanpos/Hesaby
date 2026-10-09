-- ============================================================================
-- Migration : 202610170001_member_permissions.sql
-- Purpose   : Deny-list permissions per company member.
--
--   1. Add `denied_permissions text[]` to company_members. Empty array
--      means "all permissions granted" — the model is deny-list.
--   2. Protect owners: an owner cannot have any permission denied.
--   3. Restrict SELECT on company_members to owner/admin/manager (plus own
--      row for every member, so every user can read their own permissions).
--   4. Allow owners/admins/managers to read their team members' profiles
--      (name, phone) — needed to display a readable list.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1) Deny-list column
-- ----------------------------------------------------------------------------

alter table public.company_members
  add column if not exists denied_permissions text[] not null default '{}';

comment on column public.company_members.denied_permissions is
  'Deny-list of permission codes revoked from this member. Empty = all granted.';

-- GIN index — useful if we later need to filter by denied permission.
create index if not exists idx_company_members_denied
  on public.company_members using gin (denied_permissions);


-- ----------------------------------------------------------------------------
-- 2) Trigger: protect owners from any denial
-- ----------------------------------------------------------------------------

create or replace function public.guard_owner_permissions()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.role = 'owner'
     and cardinality(new.denied_permissions) > 0 then
    raise exception
      'Cannot revoke permissions from an owner'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

comment on function public.guard_owner_permissions() is
  'Rejects any attempt to add permissions to an owner''s deny-list.';

drop trigger if exists trg_guard_owner_permissions
  on public.company_members;

create trigger trg_guard_owner_permissions
before update on public.company_members
for each row
execute function public.guard_owner_permissions();


-- ----------------------------------------------------------------------------
-- 3) RLS: restrict SELECT on company_members
-- ----------------------------------------------------------------------------
-- Previously: any active member could list the whole team.
-- Now:      only owner/admin/manager can list the team.
--           Every member can still read their own row (needed by the UI
--           to compute the current user's permissions).
-- ----------------------------------------------------------------------------

drop policy if exists "company_members_select_same_company"
  on public.company_members;

drop policy if exists "company_members_select_managers_only"
  on public.company_members;

create policy "company_members_select_managers_only"
on public.company_members
for select
to authenticated
using (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
  or user_id = auth.uid()
);


-- ----------------------------------------------------------------------------
-- 4) RLS: allow managers to read their team's profiles
-- ----------------------------------------------------------------------------
-- Previously: profiles were readable only by their owner.
-- Now:      a manager of a company can read the profiles of every active
--           member of that company, so the members list shows real names.
--           (The original `profiles_select_own` policy remains in force;
--           PostgreSQL combines policies of the same command with OR.)
-- ----------------------------------------------------------------------------

drop policy if exists "profiles_select_company_team"
  on public.profiles;

create policy "profiles_select_company_team"
on public.profiles
for select
to authenticated
using (
  exists (
    select 1
    from public.company_members me
    join public.company_members them
      on me.company_id = them.company_id
    where me.user_id    = auth.uid()
      and me.is_active  = true
      and me.role       = any (array['owner', 'admin', 'manager'])
      and them.user_id  = profiles.user_id
      and them.is_active = true
  )
);


-- ============================================================================
-- End of migration
-- ============================================================================

-- ============================================================================
-- Migration : 202610220001_platform_admin.sql
-- Phase     : T-2 — Platform Admin
-- Purpose   : Introduce a platform-wide administrator role that can read
--             every company (regardless of membership) and update their
--             subscription fields. This powers the in-app "Owner Dashboard"
--             so Mohammed does not have to touch the Supabase SQL editor
--             every time he needs to activate a customer.
--
-- Design:
--   * A single boolean on `profiles.is_platform_admin`. There is exactly one
--     value to flip, and the flag is data-driven (no hard-coded roles).
--   * A SECURITY DEFINER helper `is_platform_admin()` that RLS policies can
--     call without triggering recursion on `profiles`.
--   * A guard trigger prevents a non-admin user from flipping their own
--     flag via the existing `profiles_update_own` policy.
--   * Permissive policies are ADDED — existing member/admin policies keep
--     working untouched.
--   * A helper function `promote_platform_admin(email)` makes it trivial to
--     promote another user later (documented at the bottom).
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1) Add the flag
-- ----------------------------------------------------------------------------

alter table public.profiles
  add column if not exists is_platform_admin boolean not null default false;

comment on column public.profiles.is_platform_admin is
  'When true, this user can read every company and edit its subscription fields. Grants no access to auth.users.';


-- ----------------------------------------------------------------------------
-- 2) Guard trigger: only an existing platform admin can flip the flag
-- ----------------------------------------------------------------------------
-- `profiles_update_own` lets any user update their own row. Without a guard,
-- a normal user could set is_platform_admin = true on themselves.
--
-- The trigger allows the change when:
--   * there is no JWT context (SQL editor, migrations, service_role), or
--   * the caller is already a platform admin.
-- Otherwise, it raises insufficient_privilege.
-- ----------------------------------------------------------------------------

create or replace function public.guard_platform_admin_flag()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if new.is_platform_admin is distinct from old.is_platform_admin then
    -- Direct DB access (migration, SQL editor, service_role): allow.
    if auth.uid() is null then
      return new;
    end if;

    -- Otherwise, only a current platform admin can change the flag.
    if not exists (
      select 1
        from public.profiles p
       where p.user_id = auth.uid()
         and p.is_platform_admin = true
    ) then
      raise exception
        'Only an existing platform admin can change is_platform_admin'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  return new;
end;
$$;

comment on function public.guard_platform_admin_flag() is
  'Blocks non-admins from flipping profiles.is_platform_admin via client UPDATE.';

drop trigger if exists trg_profiles_guard_platform_admin on public.profiles;

create trigger trg_profiles_guard_platform_admin
before update on public.profiles
for each row
execute function public.guard_platform_admin_flag();


-- ----------------------------------------------------------------------------
-- 3) Helper: is_platform_admin()
-- ----------------------------------------------------------------------------
-- SECURITY DEFINER so RLS policies on `companies` / `profiles` can call it
-- without hitting the `profiles_select_own` restriction.
-- ----------------------------------------------------------------------------

create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select coalesce(
    (
      select p.is_platform_admin
        from public.profiles p
       where p.user_id = auth.uid()
    ),
    false
  );
$$;

comment on function public.is_platform_admin() is
  'True when auth.uid() is flagged as a platform administrator.';


-- ----------------------------------------------------------------------------
-- 4) Promote the founding admin
-- ----------------------------------------------------------------------------
-- Looks up the user_id in auth.users by email, then flips the flag. Safe to
-- run before the user has signed up: the update simply affects 0 rows and a
-- notice is raised.
-- ----------------------------------------------------------------------------

create or replace function public.promote_platform_admin(p_email text)
returns int
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_count int;
begin
  with target as (
    select id
      from auth.users
     where lower(email) = lower(p_email)
     limit 1
  )
  update public.profiles p
     set is_platform_admin = true
    from target t
   where p.user_id = t.id;

  get diagnostics v_count = row_count;

  if v_count = 0 then
    raise notice
      'promote_platform_admin: no user found with email % (has the user signed up yet?)',
      p_email;
  else
    raise notice
      'promote_platform_admin: % profile(s) flagged for email %',
      v_count, p_email;
  end if;

  return v_count;
end;
$$;

comment on function public.promote_platform_admin(text) is
  'Flags the user with the given email as a platform admin. Safe to re-run.';

-- Promote the founding admin (Mohammed El-Sonbaty).
select public.promote_platform_admin('mohammedelsonbaty866@gmail.com');


-- ----------------------------------------------------------------------------
-- 5) RLS policies: platform admin sees and edits everything
-- ----------------------------------------------------------------------------
-- These are PERMISSIVE policies — they OR with the existing ones, they do
-- not replace them. A regular user's access is unchanged.
-- ----------------------------------------------------------------------------

-- companies: read every row.
drop policy if exists "companies_platform_admin_select_all"
  on public.companies;

create policy "companies_platform_admin_select_all"
on public.companies
for select
to authenticated
using (public.is_platform_admin());

-- companies: update every row (subscription fields, plan, etc.).
drop policy if exists "companies_platform_admin_update_all"
  on public.companies;

create policy "companies_platform_admin_update_all"
on public.companies
for update
to authenticated
using (public.is_platform_admin())
with check (public.is_platform_admin());

-- profiles: read every row (needed to render "owner name" in the dashboard).
drop policy if exists "profiles_platform_admin_select_all"
  on public.profiles;

create policy "profiles_platform_admin_select_all"
on public.profiles
for select
to authenticated
using (public.is_platform_admin());

-- company_members: read every row (needed to show member counts).
drop policy if exists "company_members_platform_admin_select_all"
  on public.company_members;

create policy "company_members_platform_admin_select_all"
on public.company_members
for select
to authenticated
using (public.is_platform_admin());


-- ----------------------------------------------------------------------------
-- 6) Verification query (safe to run anytime)
-- ----------------------------------------------------------------------------
-- Expect: exactly one row, is_platform_admin = true.
--
--   select p.user_id, u.email, p.full_name, p.is_platform_admin
--     from public.profiles p
--     join auth.users u on u.id = p.user_id
--    where p.is_platform_admin = true;
--
-- To promote someone else later (e.g. a co-founder), run:
--
--   select public.promote_platform_admin('their-email@example.com');
--
-- ============================================================================
-- End of migration
-- ============================================================================

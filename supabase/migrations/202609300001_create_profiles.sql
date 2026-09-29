-- ============================================================================
-- Migration : 202609300001_create_profiles.sql
-- Phase     : 2 — Multi-Tenant Database Foundation
-- Purpose   : Create the `profiles` table, link it one-to-one with
--             `auth.users`, enforce Row Level Security, and auto-provision a
--             profile row whenever a new authenticated user is created.
-- Notes     : This migration also creates the shared `set_updated_at()`
--             trigger function that every subsequent tenant table reuses.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Shared trigger function: set_updated_at()
-- ----------------------------------------------------------------------------
-- Keeps `updated_at` accurate on every UPDATE. Defined once here so later
-- migrations can attach it to their tables without redefining it.
-- ----------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function public.set_updated_at() is
  'Sets updated_at to now() on every UPDATE. Reused by all tenant tables.';


-- ----------------------------------------------------------------------------
-- Table: public.profiles
-- ----------------------------------------------------------------------------
-- One-to-one companion to auth.users. Stores only application-level identity
-- data. Credentials, emails, tokens and any authentication material remain
-- exclusively inside Supabase Auth (`auth.users`).
-- ----------------------------------------------------------------------------

create table if not exists public.profiles (
  user_id    uuid        primary key
                         references auth.users (id) on delete cascade,
  full_name  text,
  phone      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint profiles_full_name_length
    check (full_name is null or char_length(full_name) <= 200),
  constraint profiles_phone_length
    check (phone is null or char_length(phone) <= 30)
);

comment on table  public.profiles           is
  'Application-level profile data linked one-to-one with auth.users. Never stores credentials.';
comment on column public.profiles.user_id   is
  'Primary key. One-to-one with auth.users.id. Cascades on delete.';
comment on column public.profiles.full_name is
  'Display name. Nullable until the user completes their profile.';
comment on column public.profiles.phone     is
  'Optional contact phone number.';


-- ----------------------------------------------------------------------------
-- Trigger: keep profiles.updated_at fresh
-- ----------------------------------------------------------------------------

drop trigger if exists trg_profiles_set_updated_at on public.profiles;

create trigger trg_profiles_set_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- Row Level Security: public.profiles
-- ----------------------------------------------------------------------------

alter table public.profiles enable row level security;

-- SELECT: a user can read only their own profile.
drop policy if exists "profiles_select_own" on public.profiles;

create policy "profiles_select_own"
on public.profiles
for select
to authenticated
using (user_id = (select auth.uid()));

-- UPDATE: a user can update only their own profile, and cannot reassign it
-- to another user_id (WITH CHECK prevents changing the primary key).
drop policy if exists "profiles_update_own" on public.profiles;

create policy "profiles_update_own"
on public.profiles
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

-- No client INSERT or DELETE policies are intentionally created:
--   * INSERT happens exclusively through `handle_new_user()` below.
--   * DELETE happens exclusively through `on delete cascade` from auth.users.
-- This prevents an arbitrary client from creating or removing profile rows.


-- ----------------------------------------------------------------------------
-- Auto-provisioning: handle_new_user()
-- ----------------------------------------------------------------------------
-- Invoked by a trigger on auth.users AFTER INSERT. Runs as SECURITY DEFINER
-- because the Supabase Auth service does not hold INSERT privileges on
-- public.profiles. `set search_path` is pinned to prevent search_path based
-- privilege escalation, and the insert is written defensively with
-- ON CONFLICT DO NOTHING.
-- ----------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  insert into public.profiles (user_id, full_name)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), null)
  )
  on conflict (user_id) do nothing;

  return new;
end;
$$;

comment on function public.handle_new_user() is
  'Provisions a public.profiles row when a new auth.users row is created.';

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_user();

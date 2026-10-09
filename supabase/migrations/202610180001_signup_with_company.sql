-- ============================================================================
-- Migration : 202610180001_signup_with_company.sql
-- Purpose   : Extend the sign-up flow so a fresh user can bootstrap their
--             own company in one round-trip.
--
-- How it works:
--   1. The client calls Supabase Auth `signUp` with the standard email
--      and password, plus two metadata fields:
--        - full_name    — optional, becomes profiles.full_name
--        - company_name — optional, when present triggers the company
--                         + owner membership creation.
--   2. `handle_new_user()` (already existing) is replaced by an extended
--      version that keeps provisioning the profile, and additionally
--      creates a company and an owner membership when `company_name` is
--      supplied.
--
-- Backwards compatibility:
--   * Sign-ups that do not carry `company_name` behave exactly as before
--     (profile only, no company). This preserves the invitation flow, in
--     which a user joins an existing company instead of creating one.
-- ============================================================================


create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_full_name    text;
  v_company_name text;
  v_company_id   uuid;
begin
  -- ---- 1) Profile (unchanged behavior) ----
  v_full_name := nullif(trim(new.raw_user_meta_data ->> 'full_name'), '');

  insert into public.profiles (user_id, full_name)
  values (new.id, v_full_name)
  on conflict (user_id) do nothing;

  -- ---- 2) Bootstrap company + owner membership when requested ----
  v_company_name := nullif(trim(new.raw_user_meta_data ->> 'company_name'), '');

  if v_company_name is not null then
    insert into public.companies (name)
    values (v_company_name)
    returning id into v_company_id;

    insert into public.company_members (company_id, user_id, role)
    values (v_company_id, new.id, 'owner')
    on conflict (company_id, user_id) do nothing;
  end if;

  return new;
end;
$$;

comment on function public.handle_new_user() is
  'Provisions a profiles row, and optionally a companies row + owner membership, when a new auth.users row is created. company_name in user metadata is the trigger.';

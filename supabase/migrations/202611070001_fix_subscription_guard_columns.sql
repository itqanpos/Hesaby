-- ============================================================================
-- Migration : 202611070001_fix_subscription_guard_columns.sql
-- Purpose   : Restore guard_company_subscription_columns() with the correct
--             column names. The original version referenced non-existent
--             columns (subscription_start_date, subscription_end_date,
--             max_users, max_branches), causing 42703 on every UPDATE to
--             companies — including from the company profile page.
--
-- Correct column list on public.companies (per migration 16):
--   plan_id, subscription_status, subscription_started_at,
--   trial_ends_at, billing_cycle, subscribed_until
-- ============================================================================

create or replace function public.guard_company_subscription_columns()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  -- Direct DB access (migrations / service_role / SQL editor): allow.
  if auth.uid() is null then
    return new;
  end if;

  -- Platform admins may change anything on companies.
  if public.is_platform_admin() then
    return new;
  end if;

  -- Guard the *actual* subscription columns that exist on public.companies.
  if new.plan_id                 is distinct from old.plan_id
     or new.subscription_status     is distinct from old.subscription_status
     or new.subscription_started_at is distinct from old.subscription_started_at
     or new.trial_ends_at           is distinct from old.trial_ends_at
     or new.billing_cycle           is distinct from old.billing_cycle
     or new.subscribed_until        is distinct from old.subscribed_until
  then
    raise exception
      'Subscription fields can only be changed by a platform admin'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

comment on function public.guard_company_subscription_columns() is
  'Blocks client-side updates to subscription fields on companies unless caller is a platform admin.';

-- Re-affirm the trigger binding (idempotent).
drop trigger if exists trg_guard_company_subscription on public.companies;

create trigger trg_guard_company_subscription
before update on public.companies
for each row
execute function public.guard_company_subscription_columns();

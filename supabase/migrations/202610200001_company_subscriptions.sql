-- ============================================================================
-- Migration : 202610200001_company_subscriptions.sql
-- Purpose   : Add subscription fields to companies and grandfather every
--             company that already exists as an active subscriber.
--
-- Model:
--   * Trial:   subscription_status='trial' with trial_ends_at = created_at + 7d.
--   * Active:  subscription_status='active' with subscribed_until in the future.
--   * Expired: either trial_ends_at or subscribed_until lies in the past, or
--              the row was explicitly marked 'expired'/'cancelled'.
--   * The client computes the *effective* status; the database stores the
--     raw fields only. No cron job is required.
--
-- Grandfathering:
--   Every company that exists at the moment this migration runs is marked
--   'active' until year 2099 — these accounts predate the subscription
--   system and must not lose access.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1) Add subscription columns
-- ----------------------------------------------------------------------------

alter table public.companies
  add column if not exists subscription_status     text        not null default 'trial',
  add column if not exists trial_ends_at           timestamptz not null default (now() + interval '7 days'),
  add column if not exists subscription_started_at timestamptz not null default now(),
  add column if not exists plan_id                 text,
  add column if not exists billing_cycle           text,
  add column if not exists subscribed_until        timestamptz;

comment on column public.companies.subscription_status is
  'trial | active | expired | cancelled. The *effective* status is computed client-side.';
comment on column public.companies.trial_ends_at is
  'When the 7-day free trial ends. Only meaningful while subscription_status = trial.';
comment on column public.companies.subscription_started_at is
  'When the trial (or the very first paid period) began.';
comment on column public.companies.plan_id is
  'basic | pro. Null while on trial or when never upgraded.';
comment on column public.companies.billing_cycle is
  'monthly | yearly. Null while on trial.';
comment on column public.companies.subscribed_until is
  'End of the current paid period. Only meaningful while subscription_status = active.';


-- ----------------------------------------------------------------------------
-- 2) Constraints
-- ----------------------------------------------------------------------------

alter table public.companies
  add constraint companies_subscription_status_valid
    check (subscription_status in ('trial', 'active', 'expired', 'cancelled'));

alter table public.companies
  add constraint companies_plan_id_valid
    check (plan_id is null or plan_id in ('basic', 'pro'));

alter table public.companies
  add constraint companies_billing_cycle_valid
    check (billing_cycle is null or billing_cycle in ('monthly', 'yearly'));


-- ----------------------------------------------------------------------------
-- 3) Grandfather every company that exists right now
-- ----------------------------------------------------------------------------
-- These accounts existed before subscriptions. They keep full access
-- forever (until 2099) and are tagged as Pro / yearly so the UI shows a
-- sensible "current plan" everywhere.
-- ----------------------------------------------------------------------------

update public.companies
set
  subscription_status     = 'active',
  plan_id                 = coalesce(plan_id, 'pro'),
  billing_cycle           = coalesce(billing_cycle, 'yearly'),
  subscribed_until        = '2099-12-31 23:59:59+00'::timestamptz,
  subscription_started_at = created_at
where subscription_status = 'trial';


-- ----------------------------------------------------------------------------
-- 4) Index for fast lookups of expired / trial accounts
-- ----------------------------------------------------------------------------

create index if not exists idx_companies_subscription_status
  on public.companies (subscription_status);


-- ============================================================================
-- End of migration
-- ============================================================================

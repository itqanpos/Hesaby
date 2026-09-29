-- ============================================================================
-- Migration : 202609300002_create_companies.sql
-- Phase     : 2 — Multi-Tenant Database Foundation
-- Purpose   : Create the `companies` table — the root of tenant isolation.
-- Notes     : RLS is enabled immediately, but membership-based policies are
--             intentionally deferred to migration 3 (`company_members`),
--             because visibility of a company is defined in terms of
--             membership, which cannot be evaluated before that table
--             exists. Until then, RLS with no policies denies all access
--             from non-superuser roles — the safest possible default.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table: public.companies
-- ----------------------------------------------------------------------------
-- One row per tenant. Every other tenant-owned table in HESABI will reference
-- this table directly or indirectly. Contains no business data and no
-- authentication material.
-- ----------------------------------------------------------------------------

create table if not exists public.companies (
  id          uuid        primary key default gen_random_uuid(),
  name        text        not null,
  legal_name  text,
  phone       text,
  email       text,
  address     text,
  currency    text        not null default 'EGP',
  timezone    text        not null default 'Africa/Cairo',
  is_active   boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint companies_name_length
    check (char_length(trim(name)) between 1 and 200),
  constraint companies_legal_name_length
    check (legal_name is null or char_length(legal_name) <= 300),
  constraint companies_phone_length
    check (phone is null or char_length(phone) <= 30),
  constraint companies_email_format
    check (email is null or email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  constraint companies_address_length
    check (address is null or char_length(address) <= 500),
  constraint companies_currency_format
    check (currency ~ '^[A-Z]{3}$'),
  constraint companies_timezone_length
    check (char_length(timezone) between 1 and 64)
);

comment on table  public.companies             is
  'Tenant root table. One row per customer company. Never stores credentials.';
comment on column public.companies.id          is
  'Primary key. Referenced by every tenant-owned table in the system.';
comment on column public.companies.name        is
  'Display name of the company. Required, trimmed, 1–200 characters.';
comment on column public.companies.legal_name  is
  'Optional legal / registered name, e.g. for invoices.';
comment on column public.companies.currency    is
  'ISO 4217 currency code (3 uppercase letters). Defaults to EGP.';
comment on column public.companies.timezone    is
  'IANA timezone identifier. Defaults to Africa/Cairo.';
comment on column public.companies.is_active   is
  'Soft-disable flag. Inactive companies keep their data but are treated as suspended.';


-- ----------------------------------------------------------------------------
-- Trigger: keep companies.updated_at fresh
-- ----------------------------------------------------------------------------

drop trigger if exists trg_companies_set_updated_at on public.companies;

create trigger trg_companies_set_updated_at
before update on public.companies
for each row
execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- Row Level Security: public.companies
-- ----------------------------------------------------------------------------
-- Enabled immediately. No policies are declared in this migration because
-- every meaningful access rule for a company depends on membership, which is
-- introduced by `company_members` in the next migration.
--
-- With RLS enabled and no policies:
--   * `anon` and `authenticated` roles can perform no operation at all.
--   * `service_role` and the table owner (bypassing RLS) can still manage
--     rows, which is what the future onboarding Edge Function will use.
--
-- Membership-based SELECT / UPDATE / DELETE policies are added in
-- 202609300003_create_company_members.sql, once the membership table exists.
-- ----------------------------------------------------------------------------

alter table public.companies enable row level security;


-- ----------------------------------------------------------------------------
-- Indexes
-- ----------------------------------------------------------------------------
-- The primary key on `id` already covers every join and lookup that will be
-- issued against this table from `company_members` and future tenant tables.
-- No additional index is created here to avoid premature optimisation.
-- ----------------------------------------------------------------------------

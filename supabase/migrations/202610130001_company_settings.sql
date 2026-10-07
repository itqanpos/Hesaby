-- ============================================================================
-- Migration : 202610130001_company_settings.sql
-- Purpose   : Add a `company_settings` table so each company can store its
--             own business defaults (tax rate, receipt footer, sale rules).
--             One row per company, created on demand via upsert.
-- Security  : RLS — SELECT for any company member, UPDATE for owner/admin/manager.
-- ============================================================================

create table if not exists public.company_settings (
  company_id                uuid primary key
                            references public.companies (id) on delete cascade,

  -- Sales / tax
  default_tax_rate          numeric(5,2) not null default 0,
  max_discount_percent      numeric(5,2) not null default 100,
  allow_sale_without_stock  boolean      not null default false,
  allow_credit_sale         boolean      not null default true,

  -- Receipt
  receipt_footer            text         not null default 'شكرًا لتعاملكم معنا',

  -- Timestamps
  created_at                timestamptz  not null default now(),
  updated_at                timestamptz  not null default now(),

  constraint company_settings_tax_rate_valid
    check (default_tax_rate >= 0 and default_tax_rate <= 100),

  constraint company_settings_max_discount_valid
    check (max_discount_percent >= 0 and max_discount_percent <= 100),

  constraint company_settings_footer_length
    check (char_length(receipt_footer) <= 200)
);

comment on table public.company_settings is
  'Per-company business defaults: tax rate, discount limit, sale rules, receipt footer.';

-- ----------------------------------------------------------------------------
-- Auto-create a default settings row when a company is inserted.
-- ----------------------------------------------------------------------------

create or replace function public.create_default_company_settings()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  insert into public.company_settings (company_id)
  values (new.id)
  on conflict (company_id) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_companies_create_default_settings
  on public.companies;

create trigger trg_companies_create_default_settings
after insert on public.companies
for each row
execute function public.create_default_company_settings();

-- ----------------------------------------------------------------------------
-- Backfill: create settings rows for existing companies.
-- ----------------------------------------------------------------------------

insert into public.company_settings (company_id)
select id from public.companies
on conflict (company_id) do nothing;

-- ----------------------------------------------------------------------------
-- updated_at trigger (reuses the shared helper).
-- ----------------------------------------------------------------------------

drop trigger if exists trg_company_settings_set_updated_at
  on public.company_settings;

create trigger trg_company_settings_set_updated_at
before update on public.company_settings
for each row
execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- Row Level Security
-- ----------------------------------------------------------------------------

alter table public.company_settings enable row level security;

drop policy if exists "company_settings_select_company_member"
  on public.company_settings;
create policy "company_settings_select_company_member"
on public.company_settings for select to authenticated
using (public.is_company_member(company_id));

drop policy if exists "company_settings_insert_company_managers"
  on public.company_settings;
create policy "company_settings_insert_company_managers"
on public.company_settings for insert to authenticated
with check (
  public.has_company_role(
    company_id, array['owner', 'admin', 'manager']
  )
);

drop policy if exists "company_settings_update_company_managers"
  on public.company_settings;
create policy "company_settings_update_company_managers"
on public.company_settings for update to authenticated
using (
  public.has_company_role(
    company_id, array['owner', 'admin', 'manager']
  )
)
with check (
  public.has_company_role(
    company_id, array['owner', 'admin', 'manager']
  )
);

-- ----------------------------------------------------------------------------
-- End of migration
-- ----------------------------------------------------------------------------

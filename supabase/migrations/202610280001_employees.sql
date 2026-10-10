-- ============================================================================
-- Migration : 202610280001_employees.sql
-- Phase     : T-5 — Employees (Stage 4a)
-- Purpose   : Introduce the employees table. It is deliberately separate
--             from company_members: an employee may not have an app login
--             (driver, cleaner, accountant, ...), yet may still receive a
--             salary or an advance through the cash register.
--
-- RLS uses `has_permission(...)` with two new permission codes:
--   * employees.view   — see the list
--   * employees.manage — create / edit / delete
-- ============================================================================

create table if not exists public.employees (
  id           uuid        primary key default gen_random_uuid(),
  company_id   uuid        not null references public.companies (id) on delete cascade,
  full_name    text        not null,
  phone        text,
  email        text,
  national_id  text,
  position     text,
  hire_date    date,
  base_salary  numeric(14, 2) not null default 0,
  notes        text,
  is_active    boolean     not null default true,
  created_by   uuid        references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint employees_full_name_length
    check (char_length(trim(full_name)) between 1 and 200),
  constraint employees_phone_length
    check (phone is null or char_length(phone) <= 30),
  constraint employees_email_format
    check (email is null or email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  constraint employees_national_id_length
    check (national_id is null or char_length(national_id) <= 30),
  constraint employees_position_length
    check (position is null or char_length(position) <= 100),
  constraint employees_base_salary_positive
    check (base_salary >= 0),
  constraint employees_notes_length
    check (notes is null or char_length(notes) <= 1000)
);

comment on table  public.employees             is
  'Company staff list. Separate from company_members — employees may not have an app login.';
comment on column public.employees.base_salary is
  'Monthly base salary in the company currency. Used as the default when generating a salary run.';

create index if not exists idx_employees_company_active
  on public.employees (company_id, is_active, full_name);

alter table public.employees enable row level security;

-- SELECT
drop policy if exists "employees_select" on public.employees;
create policy "employees_select"
on public.employees for select to authenticated
using (public.has_permission(company_id, 'employees.view'));

-- INSERT
drop policy if exists "employees_insert" on public.employees;
create policy "employees_insert"
on public.employees for insert to authenticated
with check (public.has_permission(company_id, 'employees.manage'));

-- UPDATE
drop policy if exists "employees_update" on public.employees;
create policy "employees_update"
on public.employees for update to authenticated
using (public.has_permission(company_id, 'employees.manage'))
with check (public.has_permission(company_id, 'employees.manage'));

-- DELETE
drop policy if exists "employees_delete" on public.employees;
create policy "employees_delete"
on public.employees for delete to authenticated
using (public.has_permission(company_id, 'employees.manage'));

-- Platform admin read
drop policy if exists "employees_platform_admin_select" on public.employees;
create policy "employees_platform_admin_select"
on public.employees for select to authenticated
using (public.is_platform_admin());

-- updated_at trigger
drop trigger if exists trg_employees_set_updated_at on public.employees;
create trigger trg_employees_set_updated_at
before update on public.employees
for each row
execute function public.set_updated_at();

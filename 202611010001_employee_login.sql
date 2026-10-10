-- ============================================================================
-- Migration : 202611010001_employee_login.sql
-- Phase     : U-3 — Employee login via code
-- Purpose   : Allow company owners to provision login accounts for their
--             employees using a simple code (e.g. "ahmed01") instead of an
--             email. Users sign in with the code; the app appends
--             "@hesaby.local" and authenticates against Supabase Auth.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Columns on employees
-- ----------------------------------------------------------------------------

alter table public.employees
  add column if not exists login_code text;

create unique index if not exists idx_employees_login_code
  on public.employees (company_id, lower(login_code))
  where login_code is not null;

comment on column public.employees.login_code is
  'Login code for this employee (unique per company). Null when no account yet.';


-- ----------------------------------------------------------------------------
-- 2) RPC: create_employee_user
-- ----------------------------------------------------------------------------
-- Called by an owner/admin to provision a login account for one of their
-- employees. SECURITY DEFINER runs as the table owner (postgres), which has
-- rights on auth.users / auth.identities.
--
-- The email is always "{code}@hesaby.local" — a reserved, non-routable
-- domain. Real email is not required.
-- ----------------------------------------------------------------------------

create or replace function public.create_employee_user(
  p_employee_id uuid,
  p_login_code  text,
  p_password    text,
  p_role        text default 'cashier'
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_company_id uuid;
  v_full_name  text;
  v_email      text;
  v_user_id    uuid;
  v_member_id  uuid;
  v_code       text;
begin
  -- Validate role
  if p_role not in ('admin', 'manager', 'cashier', 'inventory_clerk') then
    raise exception 'دور غير صالح: %', p_role using errcode = '22023';
  end if;

  -- Normalize code
  v_code := lower(trim(p_login_code));

  -- Find the employee
  select company_id, full_name
    into v_company_id, v_full_name
    from public.employees
   where id = p_employee_id;

  if v_company_id is null then
    raise exception 'الموظف غير موجود' using errcode = '22023';
  end if;

  -- Authorize: caller must be owner or admin of that company
  if not public.has_company_role(
    v_company_id, array['owner', 'admin']
  ) then
    raise exception 'ليس لديك صلاحية لإنشاء حساب لهذا الموظف'
      using errcode = '42501';
  end if;

  -- Reject if the employee already has an account
  if exists (
    select 1 from public.employees
     where id = p_employee_id
       and company_member_id is not null
  ) then
    raise exception 'هذا الموظف لديه حساب بالفعل' using errcode = '23505';
  end if;

  -- Validate code format
  if v_code !~ '^[a-z0-9_-]{3,30}$' then
    raise exception 'الكود يجب أن يكون 3-30 حرف (a-z، 0-9، _، -)'
      using errcode = '22023';
  end if;

  -- Validate password
  if char_length(p_password) < 6 then
    raise exception 'كلمة السر قصيرة جدًا (6 أحرف على الأقل)'
      using errcode = '22023';
  end if;

  v_email := v_code || '@hesaby.local';

  -- Reject if the code is already taken system-wide
  if exists (select 1 from auth.users where lower(email) = v_email) then
    raise exception 'الكود "%" مستخدم بالفعل. اختر كودًا آخر.', p_login_code
      using errcode = '23505';
  end if;

  -- ---- Create auth.users ----
  v_user_id := gen_random_uuid();

  insert into auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token
  ) values (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    v_email,
    crypt(p_password, gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', v_full_name, 'login_code', v_code),
    now(),
    now(),
    '',
    '',
    '',
    ''
  );

  -- ---- Create auth.identities ----
  insert into auth.identities (
    id,
    user_id,
    provider_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_user_id,
    v_user_id::text,
    jsonb_build_object(
      'sub', v_user_id::text,
      'email', v_email,
      'email_verified', true
    ),
    'email',
    now(),
    now(),
    now()
  );

  -- ---- Add company_member ----
  insert into public.company_members (
    company_id, user_id, role, is_active
  ) values (
    v_company_id, v_user_id, p_role, true
  )
  returning id into v_member_id;

  -- ---- Link employee ----
  update public.employees
     set company_member_id = v_member_id,
         login_code        = v_code
   where id = p_employee_id;

  return jsonb_build_object(
    'success', true,
    'user_id', v_user_id,
    'member_id', v_member_id,
    'login_code', v_code
  );
end;
$$;

comment on function public.create_employee_user(uuid, text, text, text) is
  'Provisions a login account for an employee. Returns the new user / member ids.';

grant execute on function public.create_employee_user(uuid, text, text, text)
  to authenticated;

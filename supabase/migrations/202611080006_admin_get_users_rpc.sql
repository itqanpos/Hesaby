-- Migration : 202611080006_admin_get_users_rpc.sql
-- Purpose   : Securely fetch users with their emails for the platform admin.

create or replace function public.get_admin_users()
returns table (
  user_id uuid,
  full_name text,
  email text,
  is_platform_admin boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  -- Check if the caller is a platform admin
  if not public.is_platform_admin() then
    raise exception 'Access denied: platform admin only';
  end if;

  return query
  select 
    p.user_id, 
    p.full_name, 
    u.email::text, 
    p.is_platform_admin, 
    p.created_at
  from public.profiles p
  join auth.users u on u.id = p.user_id
  order by p.created_at desc;
end;
$$;

comment on function public.get_admin_users() is
  'Returns all users (with emails) for the platform admin.';

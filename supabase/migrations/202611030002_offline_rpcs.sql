create or replace function public.create_offline_customer_payment(
  p_company_id uuid,
  p_client_uuid uuid,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_existing uuid;
  v_id uuid;
begin
  -- Membership check (SECURITY DEFINER bypasses RLS).
  if not exists (
    select 1 from public.company_members
    where company_id = p_company_id
      and user_id = auth.uid()
  ) then
    raise exception 'Permission denied: not a member of company %',
      p_company_id
      using errcode = '42501';
  end if;

  -- Idempotency.
  select id into v_existing
  from public.customer_payments
  where company_id = p_company_id
    and client_uuid = p_client_uuid
  limit 1;

  if v_existing is not null then
    return v_existing;
  end if;

  insert into public.customer_payments (
    company_id, customer_id, amount, method, reference, notes,
    created_by, client_uuid
  )
  values (
    p_company_id,
    (p_payload->>'customer_id')::uuid,
    (p_payload->>'amount')::numeric,
    p_payload->>'method',
    nullif(p_payload->>'reference', ''),
    nullif(p_payload->>'notes', ''),
    auth.uid(),
    p_client_uuid
  )
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.create_offline_customer_payment(
  uuid, uuid, jsonb
) to authenticated;
create or replace function public.create_offline_supplier_payment(
  p_company_id uuid,
  p_client_uuid uuid,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_existing uuid;
  v_id uuid;
begin
  if not exists (
    select 1 from public.company_members
    where company_id = p_company_id
      and user_id = auth.uid()
  ) then
    raise exception 'Permission denied: not a member of company %',
      p_company_id
      using errcode = '42501';
  end if;

  select id into v_existing
  from public.supplier_payments
  where company_id = p_company_id
    and client_uuid = p_client_uuid
  limit 1;

  if v_existing is not null then
    return v_existing;
  end if;

  insert into public.supplier_payments (
    company_id, supplier_id, amount, method, reference, notes,
    created_by, client_uuid
  )
  values (
    p_company_id,
    (p_payload->>'supplier_id')::uuid,
    (p_payload->>'amount')::numeric,
    p_payload->>'method',
    nullif(p_payload->>'reference', ''),
    nullif(p_payload->>'notes', ''),
    auth.uid(),
    p_client_uuid
  )
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.create_offline_supplier_payment(
  uuid, uuid, jsonb
) to authenticated;
create or replace function public.create_offline_expense(
  p_company_id uuid,
  p_client_uuid uuid,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_existing uuid;
  v_id uuid;
begin
  if not exists (
    select 1 from public.company_members
    where company_id = p_company_id
      and user_id = auth.uid()
  ) then
    raise exception 'Permission denied: not a member of company %',
      p_company_id
      using errcode = '42501';
  end if;

  select id into v_existing
  from public.expenses
  where company_id = p_company_id
    and client_uuid = p_client_uuid
  limit 1;

  if v_existing is not null then
    return v_existing;
  end if;

  insert into public.expenses (
    company_id, branch_id, category_id, amount, expense_date,
    payment_method, notes, created_by, client_uuid
  )
  values (
    p_company_id,
    (p_payload->>'branch_id')::uuid,
    (p_payload->>'category_id')::uuid,
    (p_payload->>'amount')::numeric,
    coalesce((p_payload->>'expense_date')::timestamptz, now()),
    p_payload->>'payment_method',
    nullif(p_payload->>'notes', ''),
    auth.uid(),
    p_client_uuid
  )
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.create_offline_expense(
  uuid, uuid, jsonb
) to authenticated;
create or replace function public.create_offline_sale(
  p_company_id uuid,
  p_client_uuid uuid,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_existing uuid;
  v_sale_id uuid;
  v_subtotal numeric(15,4) := 0;
  v_discount numeric(15,4);
  v_tax numeric(15,4);
  v_paid numeric(15,4);
  v_total numeric(15,4);
  v_payment_status text;
  v_payment_method text;
  v_item jsonb;
  v_qty numeric(15,4);
  v_price numeric(15,4);
begin
  -- Membership check.
  if not exists (
    select 1 from public.company_members
    where company_id = p_company_id
      and user_id = auth.uid()
  ) then
    raise exception 'Permission denied: not a member of company %',
      p_company_id
      using errcode = '42501';
  end if;

  -- Idempotency.
  select id into v_existing
  from public.sales
  where company_id = p_company_id
    and client_uuid = p_client_uuid
  limit 1;

  if v_existing is not null then
    return v_existing;
  end if;

  -- Extract header values.
  v_discount := coalesce((p_payload->>'discount')::numeric, 0);
  v_tax      := coalesce((p_payload->>'tax_amount')::numeric, 0);
  v_paid     := coalesce((p_payload->>'paid_amount')::numeric, 0);
  v_payment_method := nullif(p_payload->>'payment_method', '');

  -- Compute subtotal.
  for v_item in
    select * from jsonb_array_elements(
      coalesce(p_payload->'items', '[]'::jsonb)
    )
  loop
    v_qty   := coalesce((v_item->>'quantity')::numeric, 0);
    v_price := coalesce((v_item->>'unit_price')::numeric, 0);
    v_subtotal := v_subtotal + (v_qty * v_price);
  end loop;

  v_total := v_subtotal - v_discount + v_tax;

  if v_paid <= 0 then
    v_payment_status := 'unpaid';
  elsif v_paid >= v_total then
    v_payment_status := 'paid';
  else
    v_payment_status := 'partial';
  end if;

  -- Insert sale as draft. `client_uuid` marks it as offline-origin.
  insert into public.sales (
    company_id, branch_id, customer_id, sale_date, status,
    subtotal, discount, tax_amount, total, paid_amount,
    payment_status, notes, created_by, client_uuid
  )
  values (
    p_company_id,
    (p_payload->>'branch_id')::uuid,
    nullif(p_payload->>'customer_id', '')::uuid,
    coalesce((p_payload->>'sale_date')::timestamptz, now()),
    'draft',
    v_subtotal, v_discount, v_tax, v_total, v_paid,
    v_payment_status,
    nullif(p_payload->>'notes', ''),
    auth.uid(),
    p_client_uuid
  )
  returning id into v_sale_id;

  -- Insert items.
  for v_item in
    select * from jsonb_array_elements(
      coalesce(p_payload->'items', '[]'::jsonb)
    )
  loop
    v_qty   := coalesce((v_item->>'quantity')::numeric, 0);
    v_price := coalesce((v_item->>'unit_price')::numeric, 0);

    insert into public.sale_items (
      company_id, sale_id, product_id, unit_id,
      quantity, unit_price, line_total, notes
    )
    values (
      p_company_id,
      v_sale_id,
      (v_item->>'product_id')::uuid,
      (v_item->>'unit_id')::uuid,
      v_qty, v_price, (v_qty * v_price),
      nullif(v_item->>'notes', '')
    );
  end loop;

  -- Confirm — fires stock, cash, and customer-balance triggers.
  update public.sales
  set status = 'confirmed',
      confirmed_at = now()
  where id = v_sale_id;

  -- Record sale payment (if any) — fires the cash trigger.
  if v_paid > 0 and v_payment_method is not null then
    insert into public.sale_payments (
      company_id, sale_id, amount, method, created_by
    )
    values (
      p_company_id,
      v_sale_id,
      v_paid,
      v_payment_method,
      auth.uid()
    );
  end if;

  return v_sale_id;
end;
$$;

grant execute on function public.create_offline_sale(
  uuid, uuid, jsonb
) to authenticated;

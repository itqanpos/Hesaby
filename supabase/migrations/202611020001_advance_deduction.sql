-- ============================================================================
-- Migration : 202611020001_advance_deduction.sql
-- Phase     : U-4 — Auto-deduct advances when a salary is paid
-- Purpose   : When an employee_salaries row is marked as paid (paid_at set),
--             deduct the `advances_deducted` amount from the employee's open
--             advances in FIFO order, updating `remaining_amount` and
--             `status`.
--             Also prevent deleting or un-paying a paid salary (which would
--             leave the advances already reduced).
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1) Trigger function: apply advance deduction
-- ----------------------------------------------------------------------------

create or replace function public.apply_advance_deduction()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_remaining      numeric;
  v_advance        record;
  v_new_remaining  numeric;
  v_new_status     text;
begin
  -- Only fire on the transition into "paid with a positive deduction".
  if tg_op = 'INSERT' then
    if new.paid_at is null or coalesce(new.advances_deducted, 0) <= 0 then
      return new;
    end if;
  elsif tg_op = 'UPDATE' then
    -- Row was already paid → do nothing.
    if old.paid_at is not null then
      return new;
    end if;
    if new.paid_at is null or coalesce(new.advances_deducted, 0) <= 0 then
      return new;
    end if;
  else
    return new;
  end if;

  v_remaining := new.advances_deducted;

  -- Walk the employee's open advances, oldest first (FIFO).
  for v_advance in
    select id, remaining_amount
      from public.employee_advances
     where company_id      = new.company_id
       and employee_id     = new.employee_id
       and remaining_amount > 0
     order by advance_date asc, created_at asc
     for update
  loop
    exit when v_remaining <= 0;

    if v_advance.remaining_amount <= v_remaining then
      -- Fully deduct this advance.
      v_new_remaining := 0;
      v_new_status    := 'deducted';
      v_remaining     := v_remaining - v_advance.remaining_amount;
    else
      -- Partially deduct.
      v_new_remaining := v_advance.remaining_amount - v_remaining;
      v_new_status    := 'partially_deducted';
      v_remaining     := 0;
    end if;

    update public.employee_advances
       set remaining_amount = v_new_remaining,
           status           = v_new_status
     where id = v_advance.id;
  end loop;

  -- If any amount is still left over, the caller tried to deduct more than
  -- the employee owes. Roll back the whole salary transaction.
  if v_remaining > 0 then
    raise exception
      'المبلغ المُخصوم من السلف يتجاوز المتاح (%)', v_remaining
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function public.apply_advance_deduction() is
  'On salary payment, deducts advances_deducted from the employee''s open advances (FIFO).';

drop trigger if exists trg_apply_advance_deduction on public.employee_salaries;
create trigger trg_apply_advance_deduction
after insert or update on public.employee_salaries
for each row
execute function public.apply_advance_deduction();


-- ----------------------------------------------------------------------------
-- 2) Trigger function: prevent unpay or delete of a paid salary
-- ----------------------------------------------------------------------------
-- Once a salary is paid, the advances have already been reduced. Deleting
-- or un-paying the row without reversing the deduction would corrupt the
-- advance balances. Block it at the DB level.
-- ----------------------------------------------------------------------------

create or replace function public.prevent_unpay_paid_salary()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    if old.paid_at is not null then
      raise exception 'لا يمكن حذف راتب مدفوع. أعد الراتب إلى مسودة أولًا.'
        using errcode = '23514';
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' then
    if old.paid_at is not null and new.paid_at is null then
      raise exception 'لا يمكن إلغاء دفع راتب. أنشئ سجلًا تصحيحيًا بدلًا من ذلك.'
        using errcode = '23514';
    end if;
    return new;
  end if;

  return coalesce(new, old);
end;
$$;

comment on function public.prevent_unpay_paid_salary() is
  'Blocks DELETE and paid→unpaid UPDATE on employee_salaries.';

drop trigger if exists trg_prevent_unpay_paid_salary on public.employee_salaries;
create trigger trg_prevent_unpay_paid_salary
before update or delete on public.employee_salaries
for each row
execute function public.prevent_unpay_paid_salary();


-- ----------------------------------------------------------------------------
-- 3) Verification
-- ----------------------------------------------------------------------------
--   select tgname from pg_trigger
--    where tgrelid = 'public.employee_salaries'::regclass
--      and tgname like 'trg_%pay%';
-- ============================================================================
-- End of migration
-- ============================================================================

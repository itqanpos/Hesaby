-- ============================================================================
-- Migration : 202610050003_create_purchase_triggers.sql
-- Phase     : 7 — Purchases Foundation
-- Purpose   : Complete purchase lifecycle enforcement, all in the database:
--             * only draft purchases can be created or edited
--             * confirming a purchase inserts purchase_in stock movements
--             * cancelling a confirmed purchase inserts reverse sale_out
--               movements (may fail with insufficient stock — correct)
--             * totals are recomputed automatically from line items
--             * hard deletion is forbidden; use status = 'cancelled'
-- Security  : Trigger functions are SECURITY DEFINER with pinned
--             search_path, so they can insert into stock_movements on
--             behalf of the caller without exposing elevated privileges.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1) guard_purchases_insert
-- ----------------------------------------------------------------------------
-- A purchase can only be created in `draft`. Confirmation is an explicit
-- UPDATE. This keeps the stock-movement generation path single-entry.
-- ----------------------------------------------------------------------------

create or replace function public.guard_purchases_insert()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status <> 'draft' then
    raise exception
      'Purchases must be created with status = draft (got %)', new.status
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

comment on function public.guard_purchases_insert() is
  'Rejects inserts of purchases that are not in draft status.';

drop trigger if exists trg_purchases_guard_insert on public.purchases;

create trigger trg_purchases_guard_insert
before insert on public.purchases
for each row
execute function public.guard_purchases_insert();


-- ----------------------------------------------------------------------------
-- 2) apply_purchase_status_change
-- ----------------------------------------------------------------------------
-- Handles every UPDATE of a purchases row:
--   * transitions draft -> confirmed (insert purchase_in movements)
--   * transitions draft -> cancelled  (no movements)
--   * transitions confirmed -> cancelled (insert reverse sale_out movements)
--   * any other transition is rejected
--   * non-transition updates are allowed only on draft rows, and only for
--     non-financial fields beyond `notes` once the purchase leaves draft.
-- Also keeps `total = subtotal - discount + tax_amount` consistent whenever
-- a financial field changes.
-- ----------------------------------------------------------------------------

create or replace function public.apply_purchase_status_change()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_item      record;
  v_has_items boolean;
begin
  -- --------------------------------------------------------------------------
  -- Status transition branch
  -- --------------------------------------------------------------------------
  if new.status <> old.status then
    if old.status = 'draft' and new.status = 'confirmed' then
      select exists (
        select 1 from public.purchase_items where purchase_id = old.id
      ) into v_has_items;

      if not v_has_items then
        raise exception
          'Cannot confirm purchase % without items', old.id
          using errcode = 'check_violation';
      end if;

      for v_item in
        select product_id, quantity, unit_cost
          from public.purchase_items
         where purchase_id = old.id
      loop
        insert into public.stock_movements (
          company_id,
          branch_id,
          product_id,
          movement_type,
          quantity,
          unit_cost,
          reference_type,
          reference_id,
          created_by
        ) values (
          new.company_id,
          new.branch_id,
          v_item.product_id,
          'purchase_in',
          v_item.quantity,
          v_item.unit_cost,
          'purchase',
          new.id,
          auth.uid()
        );
      end loop;

      new.confirmed_at := now();
      new.cancelled_at := null;
      return new;
    end if;

    if old.status = 'draft' and new.status = 'cancelled' then
      new.cancelled_at := now();
      return new;
    end if;

    if old.status = 'confirmed' and new.status = 'cancelled' then
      for v_item in
        select product_id, quantity, unit_cost
          from public.purchase_items
         where purchase_id = old.id
      loop
        insert into public.stock_movements (
          company_id,
          branch_id,
          product_id,
          movement_type,
          quantity,
          unit_cost,
          reference_type,
          reference_id,
          created_by
        ) values (
          new.company_id,
          new.branch_id,
          v_item.product_id,
          'sale_out',
          -v_item.quantity,
          v_item.unit_cost,
          'purchase',
          new.id,
          auth.uid()
        );
      end loop;

      new.cancelled_at := now();
      return new;
    end if;

    raise exception
      'Invalid purchase status transition: % -> %', old.status, new.status
      using errcode = 'check_violation';
  end if;

  -- --------------------------------------------------------------------------
  -- Non-transition updates
  -- --------------------------------------------------------------------------
  if old.status <> 'draft' then
    -- Only `notes` may be edited once the purchase has left draft.
    if (new.subtotal      is distinct from old.subtotal)
       or (new.discount      is distinct from old.discount)
       or (new.tax_amount    is distinct from old.tax_amount)
       or (new.total         is distinct from old.total)
       or (new.branch_id     is distinct from old.branch_id)
       or (new.supplier_id   is distinct from old.supplier_id)
       or (new.purchase_date is distinct from old.purchase_date)
       or (new.invoice_number is distinct from old.invoice_number)
    then
      raise exception
        'Cannot modify a % purchase except notes', old.status
        using errcode = 'check_violation';
    end if;
    return new;
  end if;

  -- Draft: recompute total from the current financial fields.
  new.total := new.subtotal - new.discount + new.tax_amount;
  return new;
end;
$$;

comment on function public.apply_purchase_status_change() is
  'Enforces purchase lifecycle transitions and keeps stock_movements in sync.';

drop trigger if exists trg_purchases_apply_status_change on public.purchases;

create trigger trg_purchases_apply_status_change
before update on public.purchases
for each row
execute function public.apply_purchase_status_change();


-- ----------------------------------------------------------------------------
-- 3) block_purchase_delete
-- ----------------------------------------------------------------------------
-- Purchases are never hard-deleted. Cancellation is the supported path and
-- preserves the audit trail for later phases (accounting, reports).
-- ----------------------------------------------------------------------------

create or replace function public.block_purchase_delete()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception
    'Purchases cannot be deleted; set status = cancelled instead'
    using errcode = 'check_violation';
end;
$$;

comment on function public.block_purchase_delete() is
  'Rejects hard deletion of purchases; use status = cancelled.';

drop trigger if exists trg_purchases_block_delete on public.purchases;

create trigger trg_purchases_block_delete
before delete on public.purchases
for each row
execute function public.block_purchase_delete();


-- ----------------------------------------------------------------------------
-- 4) guard_purchase_items_mutation
-- ----------------------------------------------------------------------------
-- Line items can be inserted, updated or deleted only while the parent
-- purchase is in `draft`. Once confirmed or cancelled, the lines are frozen.
-- ----------------------------------------------------------------------------

create or replace function public.guard_purchase_items_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_purchase_id uuid;
  v_status      text;
begin
  if tg_op = 'DELETE' then
    v_purchase_id := old.purchase_id;
  else
    v_purchase_id := new.purchase_id;
  end if;

  select status into v_status
    from public.purchases
   where id = v_purchase_id;

  if v_status is null then
    raise exception
      'Parent purchase % not found', v_purchase_id
      using errcode = 'check_violation';
  end if;

  if v_status <> 'draft' then
    raise exception
      'Cannot modify items of a % purchase', v_status
      using errcode = 'check_violation';
  end if;

  return coalesce(new, old);
end;
$$;

comment on function public.guard_purchase_items_mutation() is
  'Blocks insert/update/delete of purchase_items when the parent is not draft.';

drop trigger if exists trg_purchase_items_guard_mutation
  on public.purchase_items;

create trigger trg_purchase_items_guard_mutation
before insert or update or delete on public.purchase_items
for each row
execute function public.guard_purchase_items_mutation();


-- ----------------------------------------------------------------------------
-- 5) compute_purchase_item_line_total
-- ----------------------------------------------------------------------------
-- Keeps line_total = quantity * unit_cost, overriding whatever the client
-- sent. Runs BEFORE INSERT/UPDATE so `recompute_purchase_totals` (AFTER)
-- reads a consistent value.
-- ----------------------------------------------------------------------------

create or replace function public.compute_purchase_item_line_total()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.line_total := new.quantity * new.unit_cost;
  return new;
end;
$$;

comment on function public.compute_purchase_item_line_total() is
  'Forces line_total to equal quantity * unit_cost on each item.';

drop trigger if exists trg_purchase_items_compute_line_total
  on public.purchase_items;

create trigger trg_purchase_items_compute_line_total
before insert or update on public.purchase_items
for each row
execute function public.compute_purchase_item_line_total();


-- ----------------------------------------------------------------------------
-- 6) recompute_purchase_totals
-- ----------------------------------------------------------------------------
-- After any change to the line items, refresh the parent purchase's subtotal.
-- The parent trigger (apply_purchase_status_change) then recomputes total.
-- ----------------------------------------------------------------------------

create or replace function public.recompute_purchase_totals()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_purchase_id uuid;
  v_subtotal    numeric(15,4);
begin
  if tg_op = 'DELETE' then
    v_purchase_id := old.purchase_id;
  else
    v_purchase_id := new.purchase_id;
  end if;

  select coalesce(sum(line_total), 0)
    into v_subtotal
    from public.purchase_items
   where purchase_id = v_purchase_id;

  update public.purchases
     set subtotal = v_subtotal
   where id = v_purchase_id;

  return null;
end;
$$;

comment on function public.recompute_purchase_totals() is
  'Recomputes purchases.subtotal from its line items after any change.';

drop trigger if exists trg_purchase_items_recompute_totals
  on public.purchase_items;

create trigger trg_purchase_items_recompute_totals
after insert or update or delete on public.purchase_items
for each row
execute function public.recompute_purchase_totals();


-- ============================================================================
-- End of migration
-- ============================================================================

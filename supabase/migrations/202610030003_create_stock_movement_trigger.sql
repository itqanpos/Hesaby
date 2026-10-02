-- ============================================================================
-- Migration : 202610030003_create_stock_movement_trigger.sql
-- Phase     : 5 — Inventory Foundation
-- Purpose   : Keep `inventory_balances` in sync with `stock_movements`.
--             Every INSERT on the ledger triggers a derived update of the
--             balance table, inside the same transaction.
-- Security  : SECURITY DEFINER with pinned search_path. Required because
--             clients have no INSERT/UPDATE policy on `inventory_balances`;
--             only this function may write to it, and it does so on behalf
--             of the caller's already-authorised INSERT on the ledger.
-- Costing   : Moving Average Weighted (MAW). IN movements recompute the
--             average; OUT movements leave the average unchanged and only
--             reduce the quantity on hand.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Function: apply_stock_movement()
-- ----------------------------------------------------------------------------
-- Concurrency:
--   * The balance row is created with `ON CONFLICT DO NOTHING`, which is
--     safe under concurrent inserts of the same (branch, product).
--   * The row is then locked with `FOR UPDATE`, serialising any other
--     movement that targets the same (branch, product).
--   * The CHECK on `quantity_on_hand >= 0` is the final safety net in case
--     a future migration weakens the guard below.
--
-- Numeric care:
--   All arithmetic uses `numeric(15,4)`. PostgreSQL numeric division keeps
--   the caller's precision, so the moving average does not lose digits
--   beyond the storage scale.
--
-- Failure modes (all raise `check_violation`):
--   * An OUT movement that would drive the balance negative.
--   * An OUT movement against a (branch, product) with no existing balance.
-- ----------------------------------------------------------------------------

create or replace function public.apply_stock_movement()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_qty      numeric(15,4);
  v_avg      numeric(15,4);
  v_new_qty  numeric(15,4);
  v_new_avg  numeric(15,4);
  v_in_cost  numeric(15,4);
begin
  -- 1) Guarantee the balance row exists. Safe under concurrency: a second
  --    transaction inserting the same (branch, product) will conflict and
  --    do nothing, then proceed to the SELECT ... FOR UPDATE below.
  insert into public.inventory_balances (
    company_id,
    branch_id,
    product_id,
    quantity_on_hand,
    average_cost
  )
  values (
    new.company_id,
    new.branch_id,
    new.product_id,
    0,
    0
  )
  on conflict (branch_id, product_id) do nothing;

  -- 2) Lock the balance row for the remainder of this transaction. Any
  --    concurrent movement on the same (branch, product) will wait here.
  select quantity_on_hand, average_cost
    into v_qty, v_avg
    from public.inventory_balances
   where branch_id = new.branch_id
     and product_id = new.product_id
     for update;

  -- 3) Compute the new balance.
  if new.quantity < 0 then
    -- OUT movement: reduce quantity, keep average cost unchanged.
    v_new_qty := v_qty + new.quantity;
    if v_new_qty < 0 then
      raise exception
        'Insufficient stock for branch %, product %: current %, attempted %',
        new.branch_id, new.product_id, v_qty, new.quantity
        using errcode = 'check_violation';
    end if;
    v_new_avg := v_avg;
  else
    -- IN movement: recompute the moving average. When unit_cost is NULL
    -- (for example, an adjustment), we fall back to the current average
    -- so the average is not distorted.
    v_in_cost  := coalesce(new.unit_cost, v_avg);
    v_new_qty  := v_qty + new.quantity;
    if v_new_qty = 0 then
      v_new_avg := 0;
    else
      v_new_avg :=
        (v_qty * v_avg + new.quantity * v_in_cost) / v_new_qty;
    end if;
  end if;

  -- 4) Persist the new balance. `set_updated_at` trigger from migration 1
  --    refreshes `updated_at` automatically.
  update public.inventory_balances
     set quantity_on_hand = v_new_qty,
         average_cost     = v_new_avg,
         last_movement_at = now()
   where branch_id = new.branch_id
     and product_id = new.product_id;

  return new;
end;
$$;

comment on function public.apply_stock_movement() is
  'Applies a stock movement to inventory_balances. SECURITY DEFINER.';


-- ----------------------------------------------------------------------------
-- Trigger: fire after every stock movement insert
-- ----------------------------------------------------------------------------

drop trigger if exists trg_stock_movements_apply
  on public.stock_movements;

create trigger trg_stock_movements_apply
after insert on public.stock_movements
for each row
execute function public.apply_stock_movement();


-- ============================================================================
-- End of migration
-- ============================================================================

-- ============================================================================
-- Notes for later phases (informational only, not executed)
-- ----------------------------------------------------------------------------
-- * Purchase flows will INSERT a stock_movements row with movement_type
--   'purchase_in' and reference_type 'purchase'.
-- * Sale flows will INSERT a stock_movements row with movement_type
--   'sale_out' and reference_type 'sale'.
-- * Branch transfers will INSERT two rows in the same transaction
--   ('transfer_out' + 'transfer_in'); their atomicity is guaranteed by
--   the surrounding transaction, not by this trigger.
-- * Because the ledger is append-only and the trigger holds a row lock,
--   two concurrent sales of the same product in the same branch are safely
--   serialised: the second one will observe the quantity after the first.
-- ============================================================================

-- ============================================================================
-- Migration : 202610030001_create_inventory_balances.sql
-- Phase     : 5 — Inventory Foundation
-- Purpose   : Current stock level per (company, branch, product).
-- Security  : RLS enabled. Only SELECT is granted to clients; all writes go
--             through the SECURITY DEFINER trigger in migration 3 that
--             applies stock movements. This keeps the balance table strictly
--             derived from the movement ledger.
-- ============================================================================

create table if not exists public.inventory_balances (
  id               uuid          primary key default gen_random_uuid(),
  company_id       uuid          not null
                                 references public.companies (id)
                                 on delete cascade,
  branch_id        uuid          not null,
  product_id       uuid          not null,
  quantity_on_hand numeric(15,4) not null default 0,
  average_cost     numeric(15,4) not null default 0,
  last_movement_at timestamptz,
  created_at       timestamptz   not null default now(),
  updated_at       timestamptz   not null default now(),

  -- Composite FKs guarantee tenant consistency: a balance row can never mix
  -- a product of company A with a branch of company B.
  constraint inventory_balances_branch_company_fk
    foreign key (branch_id, company_id)
    references public.branches (id, company_id)
    on delete cascade,
  constraint inventory_balances_product_company_fk
    foreign key (product_id, company_id)
    references public.products (id, company_id)
    on delete cascade,

  -- One balance row per (branch, product).
  constraint inventory_balances_branch_product_unique
    unique (branch_id, product_id),

  constraint inventory_balances_quantity_not_negative
    check (quantity_on_hand >= 0),
  constraint inventory_balances_average_cost_not_negative
    check (average_cost >= 0)
);

comment on table  public.inventory_balances                       is
  'Derived stock level per (company, branch, product). Written only by the stock movement trigger.';
comment on column public.inventory_balances.quantity_on_hand      is
  'Current quantity in the branch. Never negative. NUMERIC(15,4).';
comment on column public.inventory_balances.average_cost          is
  'Moving Average Weighted cost per unit. NUMERIC(15,4).';
comment on column public.inventory_balances.last_movement_at      is
  'Timestamp of the most recent stock movement affecting this row.';

create index if not exists idx_inventory_balances_company_branch
  on public.inventory_balances (company_id, branch_id);

create index if not exists idx_inventory_balances_company_product
  on public.inventory_balances (company_id, product_id);

create index if not exists idx_inventory_balances_low_stock
  on public.inventory_balances (company_id, branch_id, quantity_on_hand)
  where quantity_on_hand > 0;

drop trigger if exists trg_inventory_balances_set_updated_at
  on public.inventory_balances;

create trigger trg_inventory_balances_set_updated_at
before update on public.inventory_balances
for each row
execute function public.set_updated_at();

alter table public.inventory_balances enable row level security;

-- ----------------------------------------------------------------------------
-- RLS: read-only for clients.
-- ----------------------------------------------------------------------------
-- SELECT is allowed for any active member of the company. Writes are
-- intentionally absent: they are performed exclusively by the SECURITY
-- DEFINER trigger in migration 3. A malicious client cannot forge a balance
-- by writing directly; it must insert a movement, which passes through the
-- validation logic of the trigger.
-- ----------------------------------------------------------------------------

drop policy if exists "inventory_balances_select_company_member"
  on public.inventory_balances;

create policy "inventory_balances_select_company_member"
on public.inventory_balances
for select
to authenticated
using (public.is_company_member(company_id));

-- ============================================================================
-- End of migration
-- ============================================================================

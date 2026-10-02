-- ============================================================================
-- Migration : 202610030002_create_stock_movements.sql
-- Phase     : 5 — Inventory Foundation
-- Purpose   : Append-only ledger of stock movements. Every change to the
--             on-hand quantity is recorded here; the derived balance table
--             (migration 1) is updated exclusively by the trigger in
--             migration 3.
-- Security  : RLS enabled. Clients may INSERT and SELECT only; UPDATE and
--             DELETE are impossible by design (no policies are granted).
--             The trigger in migration 3 runs with elevated privileges to
--             keep the balance in sync within the same transaction.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Enum: stock movement types
-- ----------------------------------------------------------------------------
-- Kept as text with a CHECK constraint rather than a PostgreSQL ENUM so that
-- future phases can extend the set with a simple ALTER of the constraint
-- without a data migration.
-- ----------------------------------------------------------------------------

create table if not exists public.stock_movements (
  id               uuid          primary key default gen_random_uuid(),
  company_id       uuid          not null
                                 references public.companies (id)
                                 on delete cascade,
  branch_id        uuid          not null,
  product_id       uuid          not null,
  movement_type    text          not null,
  quantity         numeric(15,4) not null,
  unit_cost        numeric(15,4),
  reference_type   text,
  reference_id     uuid,
  notes            text,
  created_by       uuid          references auth.users (id) on delete set null,
  created_at       timestamptz   not null default now(),

  -- Composite FKs enforce tenant consistency: a movement can never mix a
  -- product of company A with a branch of company B.
  constraint stock_movements_branch_company_fk
    foreign key (branch_id, company_id)
    references public.branches (id, company_id)
    on delete restrict,
  constraint stock_movements_product_company_fk
    foreign key (product_id, company_id)
    references public.products (id, company_id)
    on delete restrict,

  -- Allowed movement types. Every future addition requires a migration that
  -- replaces this constraint, forcing an intentional decision.
  constraint stock_movements_type_valid
    check (movement_type in (
      'adjustment_in',
      'adjustment_out',
      'purchase_in',
      'sale_out',
      'transfer_in',
      'transfer_out',
      'return_in',
      'return_out',
      'opening_balance'
    )),

  -- Signed quantity: positive increases stock, negative decreases it.
  constraint stock_movements_quantity_not_zero
    check (quantity <> 0),

  -- unit_cost, when present, must be non-negative.
  constraint stock_movements_unit_cost_not_negative
    check (unit_cost is null or unit_cost >= 0),

  -- Reference integrity: both fields are either null, or both are set.
  constraint stock_movements_reference_pair
    check (
      (reference_type is null and reference_id is null)
      or (reference_type is not null and reference_id is not null)
    ),

  constraint stock_movements_notes_length
    check (notes is null or char_length(notes) <= 1000),

  constraint stock_movements_reference_type_length
    check (reference_type is null or char_length(reference_type) between 1 and 64)
);

comment on table  public.stock_movements                  is
  'Append-only ledger of stock movements. Never updated, never deleted.';
comment on column public.stock_movements.movement_type    is
  'Kind of movement: adjustment_in/out, purchase_in, sale_out, transfer_in/out, return_in/out, opening_balance.';
comment on column public.stock_movements.quantity         is
  'Signed quantity. Positive = increase, negative = decrease. NUMERIC(15,4).';
comment on column public.stock_movements.unit_cost        is
  'Optional cost per unit for this movement. Used for moving-average computation.';
comment on column public.stock_movements.reference_type   is
  'Optional external reference (e.g. "purchase", "sale"). Set together with reference_id.';
comment on column public.stock_movements.reference_id     is
  'Optional external reference id. Set together with reference_type.';
comment on column public.stock_movements.created_by       is
  'auth.users.id of the user who recorded the movement. Nullable if user deleted.';

-- ----------------------------------------------------------------------------
-- Indexes
-- ----------------------------------------------------------------------------

create index if not exists idx_stock_movements_company_created
  on public.stock_movements (company_id, created_at desc);

create index if not exists idx_stock_movements_branch_product
  on public.stock_movements (company_id, branch_id, product_id, created_at desc);

create index if not exists idx_stock_movements_product
  on public.stock_movements (company_id, product_id);

create index if not exists idx_stock_movements_reference
  on public.stock_movements (reference_type, reference_id)
  where reference_id is not null;

-- ----------------------------------------------------------------------------
-- Row Level Security
-- ----------------------------------------------------------------------------
-- SELECT : any active member of the company.
-- INSERT : owner / admin / manager, and only for their own company.
-- UPDATE / DELETE: intentionally no policy — the ledger is immutable.
-- ----------------------------------------------------------------------------

alter table public.stock_movements enable row level security;

drop policy if exists "stock_movements_select_company_member"
  on public.stock_movements;

create policy "stock_movements_select_company_member"
on public.stock_movements
for select
to authenticated
using (public.is_company_member(company_id));

drop policy if exists "stock_movements_insert_company_manager"
  on public.stock_movements;

create policy "stock_movements_insert_company_manager"
on public.stock_movements
for insert
to authenticated
with check (
  public.has_company_role(company_id, array['owner', 'admin', 'manager'])
  and (created_by is null or created_by = auth.uid())
);

-- No UPDATE or DELETE policies: the ledger is append-only.

-- ============================================================================
-- End of migration
-- ============================================================================

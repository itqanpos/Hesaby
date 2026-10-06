-- ============================================================================
-- Migration : 202610120001_products_min_stock.sql
-- Purpose   : Add a `min_stock` column to `products` so the low-stock report
--             can identify products that need reordering. The column is
--             optional: a NULL or zero value means "no minimum configured".
-- ============================================================================

alter table public.products
  add column if not exists min_stock numeric(15,4);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'products_min_stock_non_negative'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_min_stock_non_negative
      check (min_stock is null or min_stock >= 0);
  end if;
end $$;

comment on column public.products.min_stock is
  'Optional reorder threshold. When quantity_on_hand <= min_stock, the product appears in the low-stock report. NULL or 0 means "no minimum configured".';

create index if not exists idx_products_min_stock
  on public.products (company_id)
  where min_stock is not null and min_stock > 0;

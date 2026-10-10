// lib/core/invalidation/data_invalidation.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/reports/presentation/providers/reports_providers.dart';
import '../../features/sales/presentation/providers/sales_providers.dart';

/// Central invalidation helpers.
///
/// Every write operation that changes data visible on another screen must
/// call the matching helper below *after* the write succeeds. Riverpod then
/// rebuilds every affected provider on the next frame, so no screen shows
/// stale data after a sale, purchase, product edit, etc.
///
/// Why this exists:
///   The app does not use realtime subscriptions. Providers cache their
///   result until invalidated. When a mutation happens — usually inside a
///   dialog that belongs to a feature the user is not currently looking at
///   — the screens that read the mutated data must be told to refetch.
///   Doing this centrally avoids the "forgot to invalidate X" class of bugs.
///
/// Family providers are invalidated wholesale via `ref.invalidate(family)`:
/// Riverpod 2.x clears every instance, which is exactly what we want after
/// a write (all period variations are now stale).
abstract final class DataInvalidation {
  // ---------------------------------------------------------------------------
  // Sale
  // ---------------------------------------------------------------------------

  /// After a sale is created, confirmed, cancelled, or a sale return is
  /// confirmed/cancelled.
  ///
  /// Affected screens:
  /// * Sales list (`salesProvider`).
  /// * Customer list + statement + payments (balance moved).
  /// * Dashboard: low stock, receivables.
  /// * Reports: sales summary, top products, top customers, cashier,
  ///   profit & loss, customer aging, stock valuation, dead stock.
  static void afterSale(WidgetRef ref) {
    // ---- Sales feature ----
    ref.invalidate(salesProvider);
    ref.invalidate(customersProvider);
    ref.invalidate(customerStatementProvider);
    ref.invalidate(customerPaymentsProvider);
    ref.invalidate(returnsProvider);

    // ---- Reports feature ----
    ref.invalidate(lowStockProvider);
    ref.invalidate(receivablesProvider);
    ref.invalidate(customerAgingProvider);
    ref.invalidate(salesSummaryProvider);
    ref.invalidate(topProductsProvider);
    ref.invalidate(topCustomersProvider);
    ref.invalidate(salesByCashierProvider);
    ref.invalidate(profitLossProvider);
    ref.invalidate(stockValuationProvider);
    ref.invalidate(deadStockProvider);
  }

  // ---------------------------------------------------------------------------
  // Product
  // ---------------------------------------------------------------------------

  /// After a product is created, updated, deleted, or its units change.
  static void afterProductChange(WidgetRef ref) {
    ref.invalidate(lowStockProvider);
    ref.invalidate(stockValuationProvider);
    ref.invalidate(deadStockProvider);
    ref.invalidate(topProductsProvider);
    ref.invalidate(profitLossProvider);
    // Sales list shows product names on each row — refresh so renames are
    // reflected without a full page reload.
    ref.invalidate(salesProvider);
  }

  // ---------------------------------------------------------------------------
  // Customer
  // ---------------------------------------------------------------------------

  /// After a customer is created, updated, deleted, or a standalone payment
  /// or adjustment is recorded.
  static void afterCustomerChange(WidgetRef ref) {
    ref.invalidate(customersProvider);
    ref.invalidate(customerStatementProvider);
    ref.invalidate(customerPaymentsProvider);
    ref.invalidate(receivablesProvider);
    ref.invalidate(customerAgingProvider);
    ref.invalidate(topCustomersProvider);
    ref.invalidate(salesProvider);
  }

  // ---------------------------------------------------------------------------
  // Purchase / supplier
  // ---------------------------------------------------------------------------

  /// After a purchase is created, updated, deleted, or a supplier payment
  /// is recorded.
  static void afterPurchase(WidgetRef ref) {
    ref.invalidate(lowStockProvider);
    ref.invalidate(stockValuationProvider);
    ref.invalidate(deadStockProvider);
    ref.invalidate(payablesProvider);
    ref.invalidate(supplierAgingProvider);
    ref.invalidate(profitLossProvider);
  }
}

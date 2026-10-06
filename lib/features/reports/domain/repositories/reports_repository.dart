// lib/features/reports/domain/repositories/reports_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/inventory_reports.dart';
import '../entities/report_period.dart';
import '../entities/sales_reports.dart';

// ============================================================================
// Failure types
// ============================================================================

/// Categories of failures raised by [ReportsRepository] operations.
enum ReportFailureType {
  network,
  unauthorized,
  notFound,
  invalidResponse,
  unknown,
}

/// Domain-level exception raised by [ReportsRepository] operations.
@immutable
class ReportException extends Equatable implements Exception {
  const ReportException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  final ReportFailureType type;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'ReportException(type: ${type.name})';
}

// ============================================================================
// Repository contract
// ============================================================================

/// Contract for every read-only aggregation the reports feature needs.
///
/// Implementations are expected to push most of the work down to the
/// database (aggregations, grouping, ordering) rather than fetch full
/// tables and reduce them client-side.
///
/// Every sales method takes a [ReportPeriod] describing the window to
/// aggregate over. `null` bounds inside the period mean "open-ended"
/// (all-time). Inventory reports operate on the *current* state, so they
/// do not take a period — except the dead-stock report, which takes a
/// lookback window.
abstract interface class ReportsRepository {
  // ---------------------------------------------------------------------------
  // Sales
  // ---------------------------------------------------------------------------

  /// Returns the aggregated sales figures for the company over [period].
  Future<SalesSummary> getSalesSummary({
    required String companyId,
    required ReportPeriod period,
  });

  /// Returns the top [limit] products by revenue over [period].
  Future<List<TopProduct>> getTopProducts({
    required String companyId,
    required ReportPeriod period,
    int limit = 20,
    required Map<String, String> productNames,
  });

  /// Returns the top [limit] customers by spending over [period].
  Future<List<TopCustomer>> getTopCustomers({
    required String companyId,
    required ReportPeriod period,
    int limit = 20,
    required Map<String, String> customerNames,
  });

  /// Returns sales grouped by cashier (`created_by`) over [period].
  Future<List<CashierSales>> getSalesByCashier({
    required String companyId,
    required ReportPeriod period,
    required Map<String, String> cashierNames,
  });

  // ---------------------------------------------------------------------------
  // Inventory
  // ---------------------------------------------------------------------------

  /// Returns the current inventory valuation for [companyId].
  ///
  /// The report is derived from `inventory_balances` (per branch and
  /// product) and aggregated per product. When [branchId] is `null` the
  /// report covers every branch the user can see.
  ///
  /// `productNames` and `unitNames` are passed from the UI to resolve ids
  /// to display strings; missing entries fall back to placeholder text.
  Future<StockValuationReport> getStockValuation({
    required String companyId,
    String? branchId,
    required Map<String, String> productNames,
    required Map<String, String> unitNames,
  });

  /// Returns every product whose current on-hand quantity is at or below
  /// its configured `min_stock` level.
  ///
  /// Products without a `min_stock` value are ignored.
  Future<List<LowStockItem>> getLowStockItems({
    required String companyId,
    String? branchId,
    required Map<String, String> productNames,
    required Map<String, String> unitNames,
  });

  /// Returns every product that still has stock on hand but has not been
  /// sold within the last [window] days.
  ///
  /// Products that have *never* been sold are also included and flagged
  /// via [DeadStockItem.neverSold].
  Future<List<DeadStockItem>> getDeadStockItems({
    required String companyId,
    String? branchId,
    required DeadStockWindow window,
    required Map<String, String> productNames,
    required Map<String, String> unitNames,
  });
}

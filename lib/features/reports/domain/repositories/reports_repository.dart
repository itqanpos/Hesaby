// lib/features/reports/domain/repositories/reports_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/aging_reports.dart';
import '../entities/financial_reports.dart';
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
/// Sales and financial reports take a [ReportPeriod]. Inventory reports
/// operate on the *current* state, so they do not take a period — except
/// the dead-stock report, which takes a lookback window.
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
  Future<StockValuationReport> getStockValuation({
    required String companyId,
    String? branchId,
    required Map<String, String> productNames,
    required Map<String, String> unitNames,
  });

  /// Returns every product whose current on-hand quantity is at or below
  /// its configured `min_stock` level.
  Future<List<LowStockItem>> getLowStockItems({
    required String companyId,
    String? branchId,
    required Map<String, String> productNames,
    required Map<String, String> unitNames,
  });

  /// Returns every product that still has stock on hand but has not been
  /// sold within the last [window] days.
  Future<List<DeadStockItem>> getDeadStockItems({
    required String companyId,
    String? branchId,
    required DeadStockWindow window,
    required Map<String, String> productNames,
    required Map<String, String> unitNames,
  });

  // ---------------------------------------------------------------------------
  // Financial
  // ---------------------------------------------------------------------------

  /// Returns the profit & loss summary for [period].
  ///
  /// The cost of goods sold is derived from the `sale_out` stock movements
  /// whose parent sale was confirmed within [period]: their historical
  /// `unit_cost` is preserved even if the product's cost changed since.
  Future<ProfitLossSummary> getProfitLoss({
    required String companyId,
    required ReportPeriod period,
  });

  /// Returns the current accounts receivable: customers with a positive
  /// balance, ordered by descending balance.
  Future<ReceivablesReport> getReceivables({
    required String companyId,
  });

  /// Returns the accounts payable summary for confirmed purchases over
  /// [period], grouped by supplier.
  Future<PayablesReport> getPayables({
    required String companyId,
    required ReportPeriod period,
    required Map<String, String> supplierNames,
  });

  // ---------------------------------------------------------------------------
  // Aging
  // ---------------------------------------------------------------------------

  /// Returns the current customer aging report.
  ///
  /// Each customer's outstanding balance is distributed across their
  /// confirmed invoices using a simplified FIFO rule, then classified into
  /// four buckets (0–30 / 31–60 / 61–90 / 90+ days).
  Future<AgingReport> getCustomerAging({
    required String companyId,
  });
}

// lib/features/reports/domain/repositories/reports_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

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
/// Every method takes a [ReportPeriod] describing the window to aggregate
/// over. `null` bounds inside the period mean "open-ended" (all-time).
abstract interface class ReportsRepository {
  // ---------------------------------------------------------------------------
  // Sales
  // ---------------------------------------------------------------------------

  /// Returns the aggregated sales figures for the company over [period].
  ///
  /// The result combines `sales` (confirmed / draft / cancelled counts and
  /// totals) with `sale_returns` (confirmed return count and amount).
  Future<SalesSummary> getSalesSummary({
    required String companyId,
    required ReportPeriod period,
  });

  /// Returns the top [limit] products by revenue over [period].
  ///
  /// Only confirmed sales are counted; cancelled sales and draft sales are
  /// ignored. The result is ordered by `total_revenue DESC`.
  ///
  /// `productNames` is a map from product id to display name, used to
  /// resolve the [TopProduct.productName] field. Missing ids fall back to
  /// "منتج محذوف".
  Future<List<TopProduct>> getTopProducts({
    required String companyId,
    required ReportPeriod period,
    int limit = 20,
    required Map<String, String> productNames,
  });

  /// Returns the top [limit] customers by spending over [period].
  ///
  /// Only confirmed sales with a non-null customer are considered.
  /// `customerNames` maps a customer id to its display name; missing ids
  /// fall back to "عميل محذوف".
  Future<List<TopCustomer>> getTopCustomers({
    required String companyId,
    required ReportPeriod period,
    int limit = 20,
    required Map<String, String> customerNames,
  });

  /// Returns sales grouped by cashier (`created_by`) over [period].
  ///
  /// `cashierNames` maps a Supabase user id to a display name. When the
  /// caller cannot resolve a name, the implementation should fall back to
  /// a short suffix of the id.
  Future<List<CashierSales>> getSalesByCashier({
    required String companyId,
    required ReportPeriod period,
    required Map<String, String> cashierNames,
  });
}

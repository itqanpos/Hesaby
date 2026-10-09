// lib/features/reports/domain/repositories/reports_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/aging_reports.dart';
import '../entities/financial_reports.dart';
import '../entities/inventory_reports.dart';
import '../entities/report_period.dart';
import '../entities/sales_reports.dart';

enum ReportFailureType {
  network,
  unauthorized,
  notFound,
  invalidResponse,
  unknown,
}

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

abstract interface class ReportsRepository {
  Future<SalesSummary> getSalesSummary({
    required String companyId,
    required ReportPeriod period,
  });

  Future<List<TopProduct>> getTopProducts({
    required String companyId,
    required ReportPeriod period,
    int limit = 20,
    required Map<String, String> productNames,
  });

  Future<List<TopCustomer>> getTopCustomers({
    required String companyId,
    required ReportPeriod period,
    int limit = 20,
    required Map<String, String> customerNames,
  });

  Future<List<CashierSales>> getSalesByCashier({
    required String companyId,
    required ReportPeriod period,
    required Map<String, String> cashierNames,
  });

  Future<StockValuationReport> getStockValuation({
    required String companyId,
    String? branchId,
    required Map<String, String> productNames,
    required Map<String, String> unitNames,
  });

  Future<List<LowStockItem>> getLowStockItems({
    required String companyId,
    String? branchId,
    required Map<String, String> productNames,
    required Map<String, String> unitNames,
  });

  Future<List<DeadStockItem>> getDeadStockItems({
    required String companyId,
    String? branchId,
    required DeadStockWindow window,
    required Map<String, String> productNames,
    required Map<String, String> unitNames,
  });

  Future<ProfitLossSummary> getProfitLoss({
    required String companyId,
    required ReportPeriod period,
  });

  Future<ReceivablesReport> getReceivables({
    required String companyId,
  });

  Future<PayablesReport> getPayables({
    required String companyId,
    required ReportPeriod period,
    required Map<String, String> supplierNames,
  });

  Future<AgingReport> getCustomerAging({
    required String companyId,
  });

  Future<SupplierAgingReport> getSupplierAging({
    required String companyId,
  });
}

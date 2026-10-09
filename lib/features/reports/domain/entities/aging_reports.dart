// lib/features/reports/domain/entities/aging_reports.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Four time-based buckets used by every aging report (customer and
/// supplier).
@immutable
class AgingBuckets extends Equatable {
  const AgingBuckets({
    this.days0to30 = 0,
    this.days31to60 = 0,
    this.days61to90 = 0,
    this.days90plus = 0,
  });

  const AgingBuckets.zero()
      : days0to30 = 0,
        days31to60 = 0,
        days61to90 = 0,
        days90plus = 0;

  final double days0to30;
  final double days31to60;
  final double days61to90;
  final double days90plus;

  double get total => days0to30 + days31to60 + days61to90 + days90plus;
  double get current => days0to30 + days31to60;
  double get overdue => days61to90 + days90plus;

  @override
  List<Object?> get props =>
      <Object?>[days0to30, days31to60, days61to90, days90plus];
}

// ============================================================================
// Customer aging
// ============================================================================

@immutable
class CustomerAgingRow extends Equatable {
  const CustomerAgingRow({
    required this.customerId,
    required this.customerName,
    required this.balance,
    required this.buckets,
    this.phone,
  });

  final String customerId;
  final String customerName;
  final String? phone;
  final double balance;
  final AgingBuckets buckets;

  @override
  List<Object?> get props =>
      <Object?>[customerId, customerName, phone, balance, buckets];
}

@immutable
class AgingReport extends Equatable {
  const AgingReport({
    required this.rows,
    required this.totals,
    required this.customerCount,
  });

  factory AgingReport.empty() => const AgingReport(
        rows: <CustomerAgingRow>[],
        totals: AgingBuckets.zero(),
        customerCount: 0,
      );

  final List<CustomerAgingRow> rows;
  final AgingBuckets totals;
  final int customerCount;

  bool get isEmpty => rows.isEmpty;
  bool get isNotEmpty => rows.isNotEmpty;

  double get averageBalance {
    if (customerCount == 0) return 0;
    return totals.total / customerCount;
  }

  @override
  List<Object?> get props => <Object?>[rows, totals, customerCount];
}

// ============================================================================
// Supplier aging
// ============================================================================

@immutable
class SupplierAgingRow extends Equatable {
  const SupplierAgingRow({
    required this.supplierId,
    required this.supplierName,
    required this.balance,
    required this.buckets,
    this.phone,
  });

  final String supplierId;
  final String supplierName;
  final String? phone;
  final double balance;
  final AgingBuckets buckets;

  @override
  List<Object?> get props =>
      <Object?>[supplierId, supplierName, phone, balance, buckets];
}

@immutable
class SupplierAgingReport extends Equatable {
  const SupplierAgingReport({
    required this.rows,
    required this.totals,
    required this.supplierCount,
  });

  factory SupplierAgingReport.empty() => const SupplierAgingReport(
        rows: <SupplierAgingRow>[],
        totals: AgingBuckets.zero(),
        supplierCount: 0,
      );

  final List<SupplierAgingRow> rows;
  final AgingBuckets totals;
  final int supplierCount;

  bool get isEmpty => rows.isEmpty;
  bool get isNotEmpty => rows.isNotEmpty;

  double get averageBalance {
    if (supplierCount == 0) return 0;
    return totals.total / supplierCount;
  }

  @override
  List<Object?> get props => <Object?>[rows, totals, supplierCount];
}

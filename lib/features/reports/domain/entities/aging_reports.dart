// lib/features/reports/domain/entities/aging_reports.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Four time-based buckets used by every aging report (customer and, in a
/// follow-up, supplier).
///
/// All values are non-negative. The buckets are computed from the customer's
/// current `balance`, distributed across their confirmed invoices using a
/// simplified FIFO rule: the balance is "consumed" from the oldest invoice
/// first. Whatever remains on an invoice is classified by its age.
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

  /// Amount attributed to invoices aged 0–30 days.
  final double days0to30;

  /// Amount attributed to invoices aged 31–60 days.
  final double days31to60;

  /// Amount attributed to invoices aged 61–90 days.
  final double days61to90;

  /// Amount attributed to invoices aged more than 90 days.
  final double days90plus;

  /// Sum of all four buckets.
  double get total => days0to30 + days31to60 + days61to90 + days90plus;

  /// Amount that is considered "current" (0–60 days).
  double get current => days0to30 + days31to60;

  /// Amount that is considered "overdue" (60+ days).
  double get overdue => days61to90 + days90plus;

  @override
  List<Object?> get props =>
      <Object?>[days0to30, days31to60, days61to90, days90plus];
}

/// Aging breakdown for a single customer.
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

  /// Current outstanding balance from `customers.balance`.
  final double balance;

  /// Distribution of [balance] across the four time buckets.
  final AgingBuckets buckets;

  @override
  List<Object?> get props =>
      <Object?>[customerId, customerName, phone, balance, buckets];
}

/// Complete customer aging report.
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

  /// Average balance per customer (0 when empty).
  double get averageBalance {
    if (customerCount == 0) return 0;
    return totals.total / customerCount;
  }

  @override
  List<Object?> get props => <Object?>[rows, totals, customerCount];
}

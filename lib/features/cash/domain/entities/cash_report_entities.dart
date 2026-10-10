// lib/features/cash/domain/entities/cash_report_entities.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';


/// Preset periods for cash reports.
enum CashReportPeriodType {
  today,
  thisMonth,
  thisYear,
  all,
}

/// A concrete period with optional [from]/[to] bounds.
@immutable
class CashReportPeriod extends Equatable {
  const CashReportPeriod({required this.type, this.from, this.to});

  final CashReportPeriodType type;
  final DateTime? from;
  final DateTime? to;

  /// Builds a period anchored to today.
  factory CashReportPeriod.preset(CashReportPeriodType type) {
    final DateTime now = DateTime.now();
    switch (type) {
      case CashReportPeriodType.today:
        final DateTime start = DateTime(now.year, now.month, now.day);
        return CashReportPeriod(
          type: type,
          from: start,
          to: start.add(const Duration(days: 1)).subtract(
                const Duration(microseconds: 1),
              ),
        );
      case CashReportPeriodType.thisMonth:
        final DateTime start = DateTime(now.year, now.month, 1);
        final DateTime end = DateTime(now.year, now.month + 1, 1).subtract(
          const Duration(microseconds: 1),
        );
        return CashReportPeriod(type: type, from: start, to: end);
      case CashReportPeriodType.thisYear:
        final DateTime start = DateTime(now.year, 1, 1);
        final DateTime end = DateTime(now.year + 1, 1, 1).subtract(
          const Duration(microseconds: 1),
        );
        return CashReportPeriod(type: type, from: start, to: end);
      case CashReportPeriodType.all:
        return const CashReportPeriod(type: CashReportPeriodType.all);
    }
  }

  bool get isAll => type == CashReportPeriodType.all;

  String get label => switch (type) {
        CashReportPeriodType.today => 'اليوم',
        CashReportPeriodType.thisMonth => 'هذا الشهر',
        CashReportPeriodType.thisYear => 'هذا العام',
        CashReportPeriodType.all => 'كل الفترات',
      };

  @override
  List<Object?> get props => <Object?>[type, from, to];
}

/// Summary of the period's movement.
@immutable
class CashFlowSummary extends Equatable {
  const CashFlowSummary({
    required this.openingBalance,
    required this.totalIn,
    required this.totalOut,
    required this.transactionCount,
  });

  const CashFlowSummary.empty()
      : openingBalance = 0,
        totalIn = 0,
        totalOut = 0,
        transactionCount = 0;

  final double openingBalance;
  final double totalIn;
  final double totalOut;
  final int transactionCount;

  double get netChange => totalIn - totalOut;
  double get closingBalance => openingBalance + netChange;

  @override
  List<Object?> get props =>
      <Object?>[openingBalance, totalIn, totalOut, transactionCount];
}

/// One row in the "by category" breakdown.
@immutable
class CashCategoryBreakdown extends Equatable {
  const CashCategoryBreakdown({
    required this.categoryName,
    required this.totalIn,
    required this.totalOut,
    required this.count,
  });

  final String categoryName;
  final double totalIn;
  final double totalOut;
  final int count;

  double get netChange => totalIn - totalOut;
  double get total => totalIn + totalOut;

  @override
  List<Object?> get props =>
      <Object?>[categoryName, totalIn, totalOut, count];
}

/// One row in the "by account" breakdown.
@immutable
class CashAccountBreakdown extends Equatable {
  const CashAccountBreakdown({
    required this.accountId,
    required this.accountName,
    required this.totalIn,
    required this.totalOut,
    required this.count,
  });

  final String accountId;
  final String accountName;
  final double totalIn;
  final double totalOut;
  final int count;

  double get netChange => totalIn - totalOut;

  @override
  List<Object?> get props =>
      <Object?>[accountId, accountName, totalIn, totalOut, count];
}

/// Everything the report page needs in one object.
@immutable
class CashReportBundle extends Equatable {
  const CashReportBundle({
    required this.period,
    required this.summary,
    required this.byCategory,
    required this.byAccount,
  });

  factory CashReportBundle.empty(CashReportPeriod period) => CashReportBundle(
        period: period,
        summary: const CashFlowSummary.empty(),
        byCategory: const <CashCategoryBreakdown>[],
        byAccount: const <CashAccountBreakdown>[],
      );

  final CashReportPeriod period;
  final CashFlowSummary summary;
  final List<CashCategoryBreakdown> byCategory;
  final List<CashAccountBreakdown> byAccount;

  @override
  List<Object?> get props =>
      <Object?>[period, summary, byCategory, byAccount];
}

// lib/features/reports/domain/entities/financial_reports.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'report_period.dart';

// ============================================================================
// Profit & Loss
// ============================================================================

/// Gross-profit summary for a company over a period.
///
/// The report has two halves:
/// * **Revenue side** — net sales after returns.
/// * **Cost side** — cost of goods sold (COGS), computed from the
///   `sale_out` stock movements that back the confirmed sales in the
///   period. This is an *historical* figure: each movement stores the
///   MAW cost that applied at the time of the sale, so the report is
///   accurate even if product costs changed afterwards.
///
/// Operating expenses and other income are not tracked in the schema yet,
/// so [netProfit] currently equals [grossProfit].
@immutable
class ProfitLossSummary extends Equatable {
  const ProfitLossSummary({
    required this.period,
    required this.grossRevenue,
    required this.returnTotal,
    required this.netRevenue,
    required this.costOfGoodsSold,
    required this.grossProfit,
    required this.operatingExpenses,
  });

  factory ProfitLossSummary.empty(ReportPeriod period) => ProfitLossSummary(
        period: period,
        grossRevenue: 0,
        returnTotal: 0,
        netRevenue: 0,
        costOfGoodsSold: 0,
        grossProfit: 0,
        operatingExpenses: 0,
      );

  final ReportPeriod period;

  /// Sum of `total` for confirmed sales in the period.
  final double grossRevenue;

  /// Sum of `total` for confirmed returns in the period.
  final double returnTotal;

  /// `grossRevenue − returnTotal` (never below zero).
  final double netRevenue;

  /// Historical cost of the goods that were sold in the period.
  final double costOfGoodsSold;

  /// `netRevenue − costOfGoodsSold`.
  final double grossProfit;

  /// Reserved for future expense tracking; currently always zero.
  final double operatingExpenses;

  // ---------------------------------------------------------------------------
  // Derived
  // ---------------------------------------------------------------------------

  /// `grossProfit − operatingExpenses`.
  double get netProfit => grossProfit - operatingExpenses;

  /// Gross margin as a fraction of [netRevenue] (`0`..`1`). Zero when the
  /// revenue is zero.
  double get grossMargin {
    if (netRevenue <= 0) return 0;
    return grossProfit / netRevenue;
  }

  /// Net margin as a fraction of [netRevenue]. Zero when the revenue is
  /// zero.
  double get netMargin {
    if (netRevenue <= 0) return 0;
    return netProfit / netRevenue;
  }

  /// Whether the period closed with a profit.
  bool get isProfitable => netProfit > 0;

  @override
  List<Object?> get props => <Object?>[
        period,
        grossRevenue,
        returnTotal,
        netRevenue,
        costOfGoodsSold,
        grossProfit,
        operatingExpenses,
      ];
}

// ============================================================================
// Receivables
// ============================================================================

/// A customer with an outstanding balance at the current moment.
///
/// The list is derived from `customers` where `balance > 0`, sorted by
/// descending balance. `lastSaleAt` is the most recent confirmed sale date
/// for the customer within the last 180 days, when available.
@immutable
class ReceivableItem extends Equatable {
  const ReceivableItem({
    required this.customerId,
    required this.customerName,
    required this.balance,
    this.phone,
    this.lastSaleAt,
  });

  final String customerId;
  final String customerName;
  final double balance;
  final String? phone;
  final DateTime? lastSaleAt;

  /// Days since the customer's last sale, or `null` when no sale is
  /// recorded in the lookback window.
  int? get daysSinceLastSale {
    if (lastSaleAt == null) return null;
    return DateTime.now().toUtc().difference(lastSaleAt!).inDays;
  }

  @override
  List<Object?> get props => <Object?>[
        customerId,
        customerName,
        balance,
        phone,
        lastSaleAt,
      ];
}

/// Aggregate view of the accounts receivable.
@immutable
class ReceivablesReport extends Equatable {
  const ReceivablesReport({
    required this.items,
    required this.totalBalance,
    required this.customerCount,
  });

  factory ReceivablesReport.empty() => const ReceivablesReport(
        items: <ReceivableItem>[],
        totalBalance: 0,
        customerCount: 0,
      );

  final List<ReceivableItem> items;
  final double totalBalance;
  final int customerCount;

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;

  /// Average outstanding balance per customer (`0` when the list is empty).
  double get averageBalance {
    if (customerCount == 0) return 0;
    return totalBalance / customerCount;
  }

  @override
  List<Object?> get props => <Object?>[items, totalBalance, customerCount];
}

// ============================================================================
// Payables
// ============================================================================

/// Aggregated purchases for a single supplier over a period.
///
/// Derived from `purchases` where `status = 'confirmed'` (draft and
/// cancelled invoices are excluded). "Paid" reflects the `paid_amount`
/// column on the purchase headers.
@immutable
class PayableItem extends Equatable {
  const PayableItem({
    required this.supplierId,
    required this.supplierName,
    required this.invoiceCount,
    required this.totalPurchases,
    required this.totalPaid,
    required this.totalDue,
  });

  final String supplierId;
  final String supplierName;
  final int invoiceCount;
  final double totalPurchases;
  final double totalPaid;
  final double totalDue;

  @override
  List<Object?> get props => <Object?>[
        supplierId,
        supplierName,
        invoiceCount,
        totalPurchases,
        totalPaid,
        totalDue,
      ];
}

/// Aggregate view of the accounts payable.
@immutable
class PayablesReport extends Equatable {
  const PayablesReport({
    required this.period,
    required this.items,
    required this.totalPurchases,
    required this.totalPaid,
    required this.totalDue,
  });

  factory PayablesReport.empty(ReportPeriod period) => PayablesReport(
        period: period,
        items: const <PayableItem>[],
        totalPurchases: 0,
        totalPaid: 0,
        totalDue: 0,
      );

  final ReportPeriod period;
  final List<PayableItem> items;
  final double totalPurchases;
  final double totalPaid;
  final double totalDue;

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
  int get supplierCount => items.length;

  @override
  List<Object?> get props => <Object?>[
        period,
        items,
        totalPurchases,
        totalPaid,
        totalDue,
      ];
}

// lib/features/reports/domain/entities/financial_reports.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'report_period.dart';

// ============================================================================
// Profit & Loss
// ============================================================================

/// Gross-profit summary for a company over a period.
///
/// The report has three components:
/// * **Revenue side** — net sales after returns.
/// * **Cost of goods sold (COGS)** — computed from `sale_out` and
///   `sale_return_in` stock movements that back the confirmed sales
///   and returns in the period. Each movement stores the MAW cost that
///   applied at the time of the transaction, so the figure is accurate
///   even if product costs changed afterwards.
/// * **Operating expenses** — sum of the `expenses` rows within the
///   period (rent, salaries, utilities, etc.).
///
/// [netProfit] = [grossProfit] − [operatingExpenses].
/// [netRevenue] may be negative when returns exceed gross sales in the
/// period.
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

  /// `grossRevenue − returnTotal`. May be negative if returns exceed
  /// sales in a given window.
  final double netRevenue;

  /// Historical cost of the goods that were sold (net of returns) in the
  /// period. Always non-negative.
  final double costOfGoodsSold;

  /// `netRevenue − costOfGoodsSold`.
  final double grossProfit;

  /// Sum of all expense rows recorded in the period.
  final double operatingExpenses;

  // ---------------------------------------------------------------------------
  // Derived
  // ---------------------------------------------------------------------------

  /// `grossProfit − operatingExpenses`.
  double get netProfit => grossProfit - operatingExpenses;

  /// Gross margin as a fraction of [netRevenue]. Zero when revenue is
  /// non-positive.
  double get grossMargin {
    if (netRevenue <= 0) return 0;
    return grossProfit / netRevenue;
  }

  /// Net margin as a fraction of [netRevenue]. Zero when revenue is
  /// non-positive.
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
/// descending balance.
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

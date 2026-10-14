// lib/features/reports/domain/entities/sales_reports.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'report_period.dart';

// ============================================================================
// Sales summary
// ============================================================================

/// Aggregated sales figures for a single company over a period.
///
/// All amounts are in the company's currency and computed from `sales`,
/// `sale_returns`, and `sale_items`. Draft sales are counted separately and
/// never contribute to totals.
@immutable
class SalesSummary extends Equatable {
  const SalesSummary({
    required this.period,
    required this.confirmedCount,
    required this.draftCount,
    required this.cancelledCount,
    required this.totalSales,
    required this.totalPaid,
    required this.totalDue,
    required this.totalDiscount,
    required this.totalTax,
    required this.returnCount,
    required this.returnTotal,
  });

  factory SalesSummary.empty(ReportPeriod period) => SalesSummary(
        period: period,
        confirmedCount: 0,
        draftCount: 0,
        cancelledCount: 0,
        totalSales: 0,
        totalPaid: 0,
        totalDue: 0,
        totalDiscount: 0,
        totalTax: 0,
        returnCount: 0,
        returnTotal: 0,
      );

  final ReportPeriod period;

  final int confirmedCount;
  final int draftCount;
  final int cancelledCount;

  /// Sum of `total` for all confirmed sales.
  final double totalSales;

  /// Sum of `paid_amount` for all confirmed sales.
  final double totalPaid;

  /// Sum of `(total - paid_amount)` for all confirmed sales.
  final double totalDue;

  /// Sum of `discount` for all confirmed sales.
  final double totalDiscount;

  /// Sum of `tax_amount` for all confirmed sales.
  final double totalTax;

  /// Count of confirmed returns within the period.
  final int returnCount;

  /// Sum of `total` for all confirmed returns.
  final double returnTotal;

  // ---------------------------------------------------------------------------
  // Derived
  // ---------------------------------------------------------------------------

  /// Gross sales minus confirmed returns.
  double get netSales {
    final double net = totalSales - returnTotal;
    return net < 0 ? 0 : net;
  }

  /// Average invoice value (gross sales / confirmed count). Zero when no
  /// confirmed invoices exist.
  double get averageInvoice {
    if (confirmedCount == 0) return 0;
    return totalSales / confirmedCount;
  }

  /// Portion of the gross sales that has not been collected yet, as a
  /// percentage of [totalSales]. Zero when there are no sales.
  double get uncollectedRatio {
    if (totalSales <= 0) return 0;
    return totalDue / totalSales;
  }

  @override
  List<Object?> get props => <Object?>[
        period,
        confirmedCount,
        draftCount,
        cancelledCount,
        totalSales,
        totalPaid,
        totalDue,
        totalDiscount,
        totalTax,
        returnCount,
        returnTotal,
      ];
}

// ============================================================================
// Top product
// ============================================================================

/// Aggregated sales of a single product over a period.
@immutable
class TopProduct extends Equatable {
  const TopProduct({
    required this.productId,
    required this.productName,
    required this.totalQuantity,
    required this.totalRevenue,
    required this.invoiceCount,
  });

  final String productId;

  /// Resolved from the loaded `products` list at query time. Falls back to
  /// "منتج محذوف" when the product no longer exists.
  final String productName;

  /// Sum of `quantity` across all matched `sale_items`.
  final double totalQuantity;

  /// Sum of `line_total` across all matched `sale_items`.
  final double totalRevenue;

  /// Number of distinct confirmed sales that included this product.
  final int invoiceCount;

  @override
  List<Object?> get props => <Object?>[
        productId,
        productName,
        totalQuantity,
        totalRevenue,
        invoiceCount,
      ];
}

// ============================================================================
// Top customer
// ============================================================================

/// Aggregated sales attributed to a single customer over a period.
///
/// Cash sales (with `customer_id = null`) are excluded — those are counted
/// only in the [SalesSummary].
@immutable
class TopCustomer extends Equatable {
  const TopCustomer({
    required this.customerId,
    required this.customerName,
    required this.invoiceCount,
    required this.totalSpent,
    required this.totalPaid,
    required this.totalDue,
  });

  final String customerId;
  final String customerName;
  final int invoiceCount;
  final double totalSpent;
  final double totalPaid;
  final double totalDue;

  @override
  List<Object?> get props => <Object?>[
        customerId,
        customerName,
        invoiceCount,
        totalSpent,
        totalPaid,
        totalDue,
      ];
}

// ============================================================================
// Cashier sales
// ============================================================================

/// Aggregated sales attributed to a single cashier over a period.
///
/// The company may not have a dedicated cashiers table; `created_by` is the
/// Supabase user id. When a display name is not available the caller should
/// fall back to a short id or "كاشير".
@immutable
class CashierSales extends Equatable {
  const CashierSales({
    required this.cashierId,
    required this.cashierName,
    required this.invoiceCount,
    required this.totalSales,
    required this.totalPaid,
    required this.totalDue,
  });

  final String cashierId;
  final String cashierName;
  final int invoiceCount;
  final double totalSales;
  final double totalPaid;
  final double totalDue;

  @override
  List<Object?> get props => <Object?>[
        cashierId,
        cashierName,
        invoiceCount,
        totalSales,
        totalPaid,
        totalDue,
      ];
}

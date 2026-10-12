// lib/features/reports/domain/entities/profit_reports.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Aggregated profit figures for a single product over a period.
///
/// Revenue is computed from confirmed `sale_items.line_total` (via the
/// parent sale's confirmation). Cost is computed from
/// `stock_movements` of type `sale_out` in the same window, using the
/// movement's `unit_cost` — this is the **historical average cost** at
/// the moment of the sale, giving an accurate gross profit.
@immutable
class ProductProfit extends Equatable {
  const ProductProfit({
    required this.productId,
    required this.productName,
    required this.quantitySold,
    required this.revenue,
    required this.cost,
    required this.invoiceCount,
  });

  final String productId;

  /// Resolved from the loaded products list at query time. Falls back to
  /// "منتج محذوف" when the product no longer exists.
  final String productName;

  /// Sum of `quantity` across all matched `sale_items`.
  final double quantitySold;

  /// Sum of `line_total` across all matched `sale_items`.
  final double revenue;

  /// Sum of `|quantity| × unit_cost` from `sale_out` stock movements.
  final double cost;

  /// Number of distinct confirmed sales that included this product.
  final int invoiceCount;

  // ---------------------------------------------------------------------------
  // Derived
  // ---------------------------------------------------------------------------

  /// Gross profit = revenue − cost. May be negative when a product is
  /// sold below its average cost.
  double get profit => revenue - cost;

  /// Profit as a percentage of revenue. Returns `null` when there is no
  /// revenue to divide by.
  double? get marginPercent {
    if (revenue <= 0) return null;
    return (profit / revenue) * 100;
  }

  /// Whether this product contributed a profit in the period.
  bool get isProfitable => profit > 0;

  /// Whether this product was sold at a loss.
  bool get isLoss => profit < 0;

  @override
  List<Object?> get props => <Object?>[
        productId,
        productName,
        quantitySold,
        revenue,
        cost,
        invoiceCount,
      ];
}

/// Aggregate view of the whole "profit by product" report.
@immutable
class ProductProfitReport extends Equatable {
  const ProductProfitReport({
    required this.items,
    required this.totalRevenue,
    required this.totalCost,
    required this.productsWithLoss,
  });

  factory ProductProfitReport.empty() => const ProductProfitReport(
        items: <ProductProfit>[],
        totalRevenue: 0,
        totalCost: 0,
        productsWithLoss: 0,
      );

  final List<ProductProfit> items;

  /// Sum of `ProductProfit.revenue` across all items.
  final double totalRevenue;

  /// Sum of `ProductProfit.cost` across all items.
  final double totalCost;

  /// Count of items where `profit < 0`.
  final int productsWithLoss;

  // ---------------------------------------------------------------------------
  // Derived
  // ---------------------------------------------------------------------------

  int get productCount => items.length;

  double get totalProfit => totalRevenue - totalCost;

  double? get overallMarginPercent {
    if (totalRevenue <= 0) return null;
    return (totalProfit / totalRevenue) * 100;
  }

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;

  @override
  List<Object?> get props => <Object?>[
        items,
        totalRevenue,
        totalCost,
        productsWithLoss,
      ];
}

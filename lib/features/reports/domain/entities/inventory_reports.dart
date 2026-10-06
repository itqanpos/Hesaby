// lib/features/reports/domain/entities/inventory_reports.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

// ============================================================================
// Stock valuation
// ============================================================================

/// A single product's inventory valuation at the current moment.
///
/// Derived from `inventory_balances`: `quantity_on_hand × average_cost`
/// per (product, branch). The report aggregates per product across the
/// selected branch (or the whole company).
@immutable
class StockValuationItem extends Equatable {
  const StockValuationItem({
    required this.productId,
    required this.productName,
    required this.quantityOnHand,
    required this.averageCost,
    required this.totalValue,
    this.unitName,
  });

  final String productId;
  final String productName;
  final double quantityOnHand;
  final double averageCost;

  /// `quantityOnHand × averageCost`.
  final double totalValue;

  /// Display name of the default unit, when available.
  final String? unitName;

  @override
  List<Object?> get props => <Object?>[
        productId,
        productName,
        quantityOnHand,
        averageCost,
        totalValue,
        unitName,
      ];
}

/// Aggregate view of the entire stock valuation.
@immutable
class StockValuationReport extends Equatable {
  const StockValuationReport({
    required this.items,
    required this.totalValue,
    required this.totalQuantity,
  });

  factory StockValuationReport.empty() => const StockValuationReport(
        items: <StockValuationItem>[],
        totalValue: 0,
        totalQuantity: 0,
      );

  final List<StockValuationItem> items;
  final double totalValue;
  final double totalQuantity;

  int get itemCount => items.length;
  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;

  @override
  List<Object?> get props => <Object?>[items, totalValue, totalQuantity];
}

// ============================================================================
// Low stock
// ============================================================================

/// A product whose on-hand quantity has dropped to (or below) its
/// configured minimum stock level.
///
/// `minStock` is read from `products.min_stock`; when that column is
/// null the row is not considered part of the report.
@immutable
class LowStockItem extends Equatable {
  const LowStockItem({
    required this.productId,
    required this.productName,
    required this.quantityOnHand,
    required this.minStock,
    this.unitName,
  });

  final String productId;
  final String productName;
  final double quantityOnHand;
  final double minStock;
  final String? unitName;

  /// Positive when the product is below its minimum; zero when exactly at
  /// the minimum.
  double get deficit {
    final double d = minStock - quantityOnHand;
    return d < 0 ? 0 : d;
  }

  /// Whether the stock is completely out.
  bool get isOutOfStock => quantityOnHand <= 0;

  @override
  List<Object?> get props => <Object?>[
        productId,
        productName,
        quantityOnHand,
        minStock,
        unitName,
      ];
}

// ============================================================================
// Dead stock
// ============================================================================

/// A product that has not been sold within the lookback window but still
/// has stock on hand.
@immutable
class DeadStockItem extends Equatable {
  const DeadStockItem({
    required this.productId,
    required this.productName,
    required this.quantityOnHand,
    required this.stockValue,
    this.lastSoldAt,
    this.unitName,
  });

  final String productId;
  final String productName;
  final double quantityOnHand;
  final double stockValue;

  /// Most recent confirmed `sale_date` for this product within the entire
  /// dataset (not just the report window). `null` when the product has
  /// never been sold.
  final DateTime? lastSoldAt;

  final String? unitName;

  /// Days since the product was last sold, or `null` when it has never
  /// been sold.
  int? get daysSinceLastSale {
    if (lastSoldAt == null) return null;
    return DateTime.now().toUtc().difference(lastSoldAt!).inDays;
  }

  /// Whether the product has never been sold.
  bool get neverSold => lastSoldAt == null;

  @override
  List<Object?> get props => <Object?>[
        productId,
        productName,
        quantityOnHand,
        stockValue,
        lastSoldAt,
        unitName,
      ];
}

// ============================================================================
// Helper: dead stock lookback
// ============================================================================

/// Preset lookback windows for the dead stock report.
enum DeadStockWindow {
  days30(30, '30 يومًا'),
  days60(60, '60 يومًا'),
  days90(90, '90 يومًا'),
  days180(180, '6 أشهر'),
  year(365, 'سنة');

  const DeadStockWindow(this.days, this.label);

  final int days;
  final String label;

  /// Cutoff instant: `now - days`.
  DateTime get cutoff =>
      DateTime.now().toUtc().subtract(Duration(days: days));
}

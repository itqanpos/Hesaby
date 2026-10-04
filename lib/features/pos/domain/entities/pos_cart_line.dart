// lib/features/pos/domain/entities/pos_cart_line.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// A single line in the POS cart.
///
/// This is a pure value object. It knows nothing about Supabase, Flutter
/// widgets, or persistence. It carries just enough information for the
/// cart UI and the future `sale_items` payload:
///
/// * product identity (`productId`, `productName`),
/// * the chosen unit (`unitId`, `unitName`, `conversionFactor`),
/// * the effective quantity and unit price (after any cashier edit),
/// * the selling-price bounds, used for validation,
/// * the currently available stock, used for display.
///
/// A line is uniquely identified within a cart by the pair
/// `(productId, unitId)`. Adding the same product with the same unit merges
/// quantities into a single line; adding it with a different unit creates a
/// second line.
@immutable
class PosCartLine extends Equatable {
  const PosCartLine({
    required this.productId,
    required this.productName,
    required this.unitId,
    required this.unitName,
    required this.conversionFactor,
    required this.quantity,
    required this.unitPrice,
    this.minSellingPrice,
    this.maxSellingPrice,
    this.availableStock,
    this.notes,
  });

  /// Unique identifier of the product.
  final String productId;

  /// Display name of the product. Cached to avoid re-resolving on rebuild.
  final String productName;

  /// Identifier of the unit chosen for this line.
  final String unitId;

  /// Display name of the unit. Cached for the same reason as [productName].
  final String unitName;

  /// How many base units equal one of [unitId]. Provided for display and
  /// future receipt printing; not used for pricing.
  final double conversionFactor;

  /// Quantity in [unitId]. Always strictly positive.
  final double quantity;

  /// Selling price per [unitId]. Chosen by the cashier within the bounds
  /// [minSellingPrice] and [maxSellingPrice] when those are set.
  final double unitPrice;

  /// Optional lower bound for [unitPrice]. When `null`, unbounded below.
  final double? minSellingPrice;

  /// Optional upper bound for [unitPrice]. When `null`, unbounded above.
  final double? maxSellingPrice;

  /// Snapshot of the branch stock at the moment the line was created or
  /// last refreshed. Advisory only: the authoritative check happens on the
  /// server when the sale is confirmed.
  final double? availableStock;

  /// Optional free-form note for this line.
  final String? notes;

  // ---------------------------------------------------------------------------
  // Derived
  // ---------------------------------------------------------------------------

  /// Line total = [quantity] * [unitPrice].
  double get lineTotal => quantity * unitPrice;

  /// Stable key for merging / replacing operations inside the cart.
  String get key => '$productId::$unitId';

  /// Whether a note is present.
  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;

  /// Whether an explicit price range is enforced.
  bool get hasPriceRange =>
      minSellingPrice != null || maxSellingPrice != null;

  /// Whether the current [unitPrice] is within the allowed range.
  bool get isPriceValid {
    if (minSellingPrice != null && unitPrice < minSellingPrice!) {
      return false;
    }
    if (maxSellingPrice != null && unitPrice > maxSellingPrice!) {
      return false;
    }
    return true;
  }

  /// Whether the line quantity can still be increased without exceeding
  /// the known available stock. When [availableStock] is `null`, the
  /// quantity is assumed to be unbounded (the authoritative check happens
  /// on the server).
  bool get canIncrease {
    final double? available = availableStock;
    if (available == null) {
      return true;
    }
    return quantity < available;
  }

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  PosCartLine copyWith({
    String? productName,
    String? unitName,
    double? conversionFactor,
    double? quantity,
    double? unitPrice,
    double? minSellingPrice,
    bool clearMinSellingPrice = false,
    double? maxSellingPrice,
    bool clearMaxSellingPrice = false,
    double? availableStock,
    bool clearAvailableStock = false,
    String? notes,
    bool clearNotes = false,
  }) {
    return PosCartLine(
      productId: productId,
      productName: productName ?? this.productName,
      unitId: unitId,
      unitName: unitName ?? this.unitName,
      conversionFactor: conversionFactor ?? this.conversionFactor,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      minSellingPrice: clearMinSellingPrice
          ? null
          : (minSellingPrice ?? this.minSellingPrice),
      maxSellingPrice: clearMaxSellingPrice
          ? null
          : (maxSellingPrice ?? this.maxSellingPrice),
      availableStock : clearAvailableStock
          ? null
          : (availableStock ?? this.availableStock),
      notes: clearNotes ? null : (notes ?? this.notes),
    );
  }

  @override
  List<Object?> get props => <Object?>[
        productId,
        productName,
        unitId,
        unitName,
        conversionFactor,
        quantity,
        unitPrice,
        minSellingPrice,
        maxSellingPrice,
        availableStock,
        notes,
      ];

  @override
  String toString() =>
      'PosCartLine(productId: $productId, unitId: $unitId, '
      'quantity: $quantity, unitPrice: $unitPrice)';
}

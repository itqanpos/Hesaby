// lib/features/purchases/domain/entities/purchase_cart_line.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// A single line in the purchase cart (what we're buying from a supplier).
///
/// This is a pure value object — no Supabase, no Flutter widgets.
///
/// A line is uniquely identified within a cart by the pair
/// `(productId, unitId)`; adding the same product with the same unit merges
/// quantities into a single line.
///
/// Unlike `PosCartLine`, this carries `unitCost` (what we pay the supplier)
/// instead of a selling price, and no price-range bounds (they don't apply
/// to purchases).
@immutable
class PurchaseCartLine extends Equatable {
  const PurchaseCartLine({
    required this.productId,
    required this.productName,
    required this.unitId,
    required this.unitName,
    required this.conversionFactor,
    required this.quantity,
    required this.unitCost,
    this.notes,
  });

  /// Identifier of the product being purchased.
  final String productId;

  /// Display name of the product. Cached for display.
  final String productName;

  /// Identifier of the chosen unit.
  final String unitId;

  /// Display name of the unit.
  final String unitName;

  /// How many base units equal one of [unitId]. Currently `1` (single-unit
  /// purchases); kept for future multi-unit support.
  final double conversionFactor;

  /// Quantity in [unitId]. Always strictly positive.
  final double quantity;

  /// Unit cost — what we pay the supplier for one [unitId]. Never negative.
  final double unitCost;

  /// Optional free-form note for this line.
  final String? notes;

  // ---------------------------------------------------------------------------
  // Derived
  // ---------------------------------------------------------------------------

  /// Line total = [quantity] × [unitCost].
  double get lineTotal => quantity * unitCost;

  /// Stable key for merging / replacing operations inside the cart.
  String get key => '$productId::$unitId';

  /// Whether a note is present.
  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  PurchaseCartLine copyWith({
    String? productName,
    String? unitName,
    double? conversionFactor,
    double? quantity,
    double? unitCost,
    String? notes,
    bool clearNotes = false,
  }) {
    return PurchaseCartLine(
      productId: productId,
      productName: productName ?? this.productName,
      unitId: unitId,
      unitName: unitName ?? this.unitName,
      conversionFactor: conversionFactor ?? this.conversionFactor,
      quantity: quantity ?? this.quantity,
      unitCost: unitCost ?? this.unitCost,
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
        unitCost,
        notes,
      ];

  @override
  String toString() =>
      'PurchaseCartLine(productId: $productId, unitId: $unitId, '
      'quantity: $quantity, unitCost: $unitCost)';
}

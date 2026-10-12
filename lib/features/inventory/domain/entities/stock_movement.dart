// lib/features/inventory/domain/entities/stock_movement.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Canonical movement type identifiers used by `stock_movements.movement_type`.
abstract final class StockMovementType {
  static const String adjustmentIn = 'adjustment_in';
  static const String adjustmentOut = 'adjustment_out';
  static const String purchaseIn = 'purchase_in';
  static const String saleOut = 'sale_out';
  static const String transferIn = 'transfer_in';
  static const String transferOut = 'transfer_out';
  static const String returnIn = 'return_in';
  static const String returnOut = 'return_out';
  static const String openingBalance = 'opening_balance';

  static const List<String> all = <String>[
    adjustmentIn,
    adjustmentOut,
    purchaseIn,
    saleOut,
    transferIn,
    transferOut,
    returnIn,
    returnOut,
    openingBalance,
  ];
}

/// Represents a single, immutable stock movement.
///
/// `quantity` is **always** expressed in the product's base unit — the
/// application multiplies any user-entered quantity by
/// `product_units.conversion_factor` before the insert. [unitId], when
/// present, records the unit the operator actually picked for the UI and
/// for later reporting; it does not affect the stored quantity.
@immutable
class StockMovement extends Equatable {
  const StockMovement({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.productId,
    required this.movementType,
    required this.quantity,
    required this.createdAt,
    this.unitId,
    this.unitCost,
    this.referenceType,
    this.referenceId,
    this.notes,
    this.createdBy,
  });

  final String id;
  final String companyId;
  final String branchId;
  final String productId;
  final String movementType;

  /// Signed **base-unit** quantity. Positive increases stock, negative
  /// decreases it. Never zero.
  final double quantity;

  /// Optional unit the operator picked when recording the movement.
  /// Informational only — see class doc.
  final String? unitId;

  final double? unitCost;
  final String? referenceType;
  final String? referenceId;
  final String? notes;
  final String? createdBy;
  final DateTime createdAt;

  // ---------------------------------------------------------------------------
  // Convenience getters (UI only)
  // ---------------------------------------------------------------------------

  bool get isIncrease => quantity > 0;
  bool get isDecrease => quantity < 0;
  double get absoluteQuantity => quantity < 0 ? -quantity : quantity;
  bool get hasUnit => unitId != null;
  bool get hasReference => referenceType != null && referenceId != null;
  bool get hasUnitCost => unitCost != null;
  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;
  bool get hasCreatedBy => createdBy != null;

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        branchId,
        productId,
        movementType,
        quantity,
        unitId,
        unitCost,
        referenceType,
        referenceId,
        notes,
        createdBy,
        createdAt,
      ];

  @override
  String toString() =>
      'StockMovement(id: $id, type: $movementType, quantity: $quantity, '
      'unitId: $unitId, branchId: $branchId, productId: $productId)';
}

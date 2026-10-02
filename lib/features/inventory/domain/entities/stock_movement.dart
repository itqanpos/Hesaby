// lib/features/inventory/domain/entities/stock_movement.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Canonical movement type identifiers used by `stock_movements.movement_type`.
///
/// Declared as constants rather than a Dart `enum` because the database
/// stores the value as `text` with a CHECK constraint; adding a new type in a
/// future migration should not require changing existing entity instances.
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

  /// Every type currently accepted by the database CHECK constraint.
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
/// This is a pure Domain entity. It knows nothing about Supabase,
/// PostgreSQL, or Flutter widgets.
///
/// Money and quantity representation:
/// `quantity`, `unitCost` are exposed as `double`, matching `numeric(15,4)`
/// in the database. The same rationale documented on `Product` applies.
///
/// A movement is append-only: it is never updated and never deleted.
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
    this.unitCost,
    this.referenceType,
    this.referenceId,
    this.notes,
    this.createdBy,
  });

  /// Unique identifier of the movement (uuid).
  final String id;

  /// Identifier of the owning company.
  final String companyId;

  /// Identifier of the branch this movement affects.
  final String branchId;

  /// Identifier of the product this movement affects.
  final String productId;

  /// One of [StockMovementType.all].
  final String movementType;

  /// Signed quantity. Positive increases stock, negative decreases it.
  /// Never zero.
  final double quantity;

  /// Optional cost per unit for this movement. Used for moving-average cost
  /// computation when positive. Never negative when present.
  final double? unitCost;

  /// Optional external reference type, e.g. `purchase`, `sale`.
  /// Always set together with [referenceId].
  final String? referenceType;

  /// Optional external reference id.
  /// Always set together with [referenceType].
  final String? referenceId;

  /// Optional free-form note.
  final String? notes;

  /// Optional `auth.users.id` of the user who recorded the movement.
  final String? createdBy;

  /// Creation timestamp (UTC).
  final DateTime createdAt;

  // ---------------------------------------------------------------------------
  // Convenience getters (UI only — no business rules)
  // ---------------------------------------------------------------------------

  /// Whether this movement increases stock.
  bool get isIncrease => quantity > 0;

  /// Whether this movement decreases stock.
  bool get isDecrease => quantity < 0;

  /// Absolute magnitude of the movement, always non-negative.
  double get absoluteQuantity => quantity < 0 ? -quantity : quantity;

  /// Whether the movement has an external reference.
  bool get hasReference => referenceType != null && referenceId != null;

  /// Whether a unit cost was provided with the movement.
  bool get hasUnitCost => unitCost != null;

  /// Whether a note was attached to the movement.
  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;

  /// Whether the movement was attributed to an authenticated user.
  bool get hasCreatedBy => createdBy != null;

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        branchId,
        productId,
        movementType,
        quantity,
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
      'branchId: $branchId, productId: $productId)';
}

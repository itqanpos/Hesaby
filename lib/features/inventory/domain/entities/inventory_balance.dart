// lib/features/inventory/domain/entities/inventory_balance.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Represents the current stock level of a single product in a single branch.
///
/// This is a pure Domain entity. It knows nothing about Supabase,
/// PostgreSQL, or Flutter widgets.
///
/// The entity is derived state: it is maintained exclusively by the
/// database trigger on `stock_movements` (Phase 5, migration 3) and must
/// never be written directly by client code. Its Domain role is to expose
/// the authoritative quantity and moving-average cost to the presentation
/// layer.
///
/// Money and quantity representation:
/// `quantityOnHand` and `averageCost` are exposed as `double`, matching
/// `numeric(15,4)` in the database, following the same rationale documented
/// on `Product`.
@immutable
class InventoryBalance extends Equatable {
  const InventoryBalance({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.productId,
    required this.quantityOnHand,
    required this.averageCost,
    required this.createdAt,
    required this.updatedAt,
    this.lastMovementAt,
  });

  /// Unique identifier of the balance row (uuid).
  final String id;

  /// Identifier of the owning company.
  final String companyId;

  /// Identifier of the branch this balance belongs to.
  final String branchId;

  /// Identifier of the product this balance belongs to.
  final String productId;

  /// Current quantity on hand. Always >= 0.
  final double quantityOnHand;

  /// Moving-average weighted cost per unit. Always >= 0.
  final double averageCost;

  /// Timestamp of the most recent movement affecting this balance.
  ///
  /// `null` until the first movement is applied. Rows are created with a
  /// zero quantity, so a freshly-created row that has not yet seen a
  /// movement will have a null value here.
  final DateTime? lastMovementAt;

  /// Creation timestamp (UTC).
  final DateTime createdAt;

  /// Last modification timestamp (UTC).
  final DateTime updatedAt;

  // ---------------------------------------------------------------------------
  // Convenience getters (UI only — no business rules)
  // ---------------------------------------------------------------------------

  /// Whether the balance has no stock at all.
  bool get isOutOfStock => quantityOnHand <= 0;

  /// Total value of the stock on hand at the current average cost.
  double get totalValue => quantityOnHand * averageCost;

  /// Whether this balance has never been touched by a movement.
  bool get hasNoMovementYet => lastMovementAt == null;

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        branchId,
        productId,
        quantityOnHand,
        averageCost,
        lastMovementAt,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'InventoryBalance(id: $id, branchId: $branchId, productId: $productId, '
      'quantityOnHand: $quantityOnHand, averageCost: $averageCost)';
}

// lib/features/purchases/domain/entities/purchase_item.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Represents a single line item of a purchase order.
///
/// This is a pure Domain entity. It knows nothing about Supabase,
/// PostgreSQL, or Flutter widgets.
///
/// `lineTotal` is maintained by the database
/// (`compute_purchase_item_line_total`): it always equals
/// `quantity * unitCost`. The client reads it but never sets it.
@immutable
class PurchaseItem extends Equatable {
  const PurchaseItem({
    required this.id,
    required this.companyId,
    required this.purchaseId,
    required this.productId,
    required this.unitId,
    required this.quantity,
    required this.unitCost,
    required this.lineTotal,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
  });

  /// Unique identifier of the line item (uuid).
  final String id;

  /// Identifier of the owning company.
  final String companyId;

  /// Identifier of the parent purchase.
  final String purchaseId;

  /// Identifier of the product being purchased.
  final String productId;

  /// Identifier of the unit of measure for this line.
  final String unitId;

  /// Quantity purchased. Strictly positive.
  final double quantity;

  /// Unit cost for this line. Never negative.
  final double unitCost;

  /// Line total = quantity × unitCost. Maintained by the database.
  final double lineTotal;

  /// Optional free-form notes for this line.
  final String? notes;

  /// Creation timestamp (UTC).
  final DateTime createdAt;

  /// Last modification timestamp (UTC).
  final DateTime updatedAt;

  // ---------------------------------------------------------------------------
  // Convenience getters (UI only — no business rules)
  // ---------------------------------------------------------------------------

  /// True when a meaningful note is present.
  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;

  /// Alias for [lineTotal] to make it explicit at call sites that this is
  /// the value of the line, independent of how it was computed.
  double get value => lineTotal;

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        purchaseId,
        productId,
        unitId,
        quantity,
        unitCost,
        lineTotal,
        notes,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'PurchaseItem(id: $id, purchaseId: $purchaseId, productId: $productId, '
      'quantity: $quantity, unitCost: $unitCost, lineTotal: $lineTotal)';
}

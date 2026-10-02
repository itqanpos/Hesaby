// lib/features/products/domain/entities/product_unit.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Represents a non-base unit conversion for a product.
///
/// Example: a product whose base unit is "piece" can also be sold in
/// "carton", where one carton equals 24 pieces. That relationship is a
/// [ProductUnit] with [conversionFactor] == 24.
///
/// The base unit of a product is stored on the product itself
/// (`Product.defaultUnitId`), not here. This table holds only additional,
/// non-base units. A database trigger rejects rows that would duplicate
/// the product's base unit.
///
/// This is a pure Domain entity. It knows nothing about Supabase,
/// PostgreSQL, or Flutter widgets.
@immutable
class ProductUnit extends Equatable {
  const ProductUnit({
    required this.id,
    required this.companyId,
    required this.productId,
    required this.unitId,
    required this.conversionFactor,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Unique identifier of the conversion row (uuid).
  final String id;

  /// Identifier of the owning company (denormalised for RLS).
  final String companyId;

  /// Identifier of the product this conversion belongs to.
  final String productId;

  /// Identifier of the non-base unit referenced by this conversion.
  final String unitId;

  /// How many base units equal one [unitId]. Always strictly positive.
  ///
  /// Stored as `numeric(15,6)` in the database. Exposed as `double` here,
  /// following the same rationale documented on [Product].
  final double conversionFactor;

  /// Creation timestamp (UTC).
  final DateTime createdAt;

  /// Last modification timestamp (UTC).
  final DateTime updatedAt;

  /// Whether the conversion represents a meaningful quantity
  /// (factor > 0). UI helper only; the database enforces this with a
  /// CHECK constraint.
  bool get isMeaningfulConversion => conversionFactor > 0;

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        productId,
        unitId,
        conversionFactor,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'ProductUnit(id: $id, productId: $productId, unitId: $unitId, '
      'conversionFactor: $conversionFactor)';
}

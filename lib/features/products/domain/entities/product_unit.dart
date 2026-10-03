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
/// Pricing:
/// A unit may define its own [sellingPrice]. When it does not, the
/// effective selling price falls back to
/// `product.sellingPrice * conversionFactor`. The same fallback applies to
/// [minSellingPrice] and [maxSellingPrice].
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
    this.sellingPrice,
    this.minSellingPrice,
    this.maxSellingPrice,
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

  /// Optional unit-specific selling price.
  ///
  /// When `null`, the effective price is
  /// `product.sellingPrice * conversionFactor`.
  final double? sellingPrice;

  /// Optional lower bound for this unit's price.
  ///
  /// When `null`, the effective lower bound is
  /// `product.minSellingPrice * conversionFactor` (which may itself be
  /// `null`).
  final double? minSellingPrice;

  /// Optional upper bound for this unit's price.
  ///
  /// When `null`, the effective upper bound is
  /// `product.maxSellingPrice * conversionFactor` (which may itself be
  /// `null`).
  final double? maxSellingPrice;

  /// Creation timestamp (UTC).
  final DateTime createdAt;

  /// Last modification timestamp (UTC).
  final DateTime updatedAt;

  /// Whether the conversion represents a meaningful quantity
  /// (factor > 0). UI helper only; the database enforces this with a
  /// CHECK constraint.
  bool get isMeaningfulConversion => conversionFactor > 0;

  /// Whether this unit defines its own selling price.
  bool get hasSellingPrice => sellingPrice != null;

  /// Whether this unit defines its own lower bound.
  bool get hasMinSellingPrice => minSellingPrice != null;

  /// Whether this unit defines its own upper bound.
  bool get hasMaxSellingPrice => maxSellingPrice != null;

  /// Whether this unit defines an explicit selling-price range.
  bool get hasPriceRange => hasMinSellingPrice || hasMaxSellingPrice;

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        productId,
        unitId,
        conversionFactor,
        sellingPrice,
        minSellingPrice,
        maxSellingPrice,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'ProductUnit(id: $id, productId: $productId, unitId: $unitId, '
      'conversionFactor: $conversionFactor, sellingPrice: $sellingPrice)';
}

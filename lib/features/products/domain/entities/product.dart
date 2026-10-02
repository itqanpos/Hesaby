// lib/features/products/domain/entities/product.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Represents a product inside HESABI.
///
/// This is a pure Domain entity. It knows nothing about Supabase,
/// PostgreSQL, or Flutter widgets.
///
/// Money representation:
/// The database stores all monetary values as `numeric(15,4)` — exact,
/// never floating point. In Dart, they are exposed as `double`. `double`
/// represents values with two decimals exactly up to 2^53 / 100 (about
/// 9 × 10^13), which is far beyond any realistic POS price.
///
/// A product always belongs to exactly one company; [companyId] is part of
/// the entity so that the presentation layer can verify tenant coherence
/// without an extra query.
@immutable
class Product extends Equatable {
  const Product({
    required this.id,
    required this.companyId,
    required this.defaultUnitId,
    required this.name,
    required this.costPrice,
    required this.sellingPrice,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.categoryId,
    this.sku,
    this.barcode,
    this.description,
    this.minSellingPrice,
    this.taxRate,
  });

  /// Unique identifier of the product (uuid).
  final String id;

  /// Identifier of the owning company.
  final String companyId;

  /// Optional identifier of the category this product belongs to.
  final String? categoryId;

  /// Identifier of the default (base) unit of this product.
  final String defaultUnitId;

  /// Display name of the product.
  final String name;

  /// Optional stock keeping unit. Unique per company when present.
  final String? sku;

  /// Optional barcode. Stored as data only in Phase 4 (no scanning).
  final String? barcode;

  /// Optional description.
  final String? description;

  /// Cost price. Never negative.
  final double costPrice;

  /// Default selling price. Never negative.
  final double sellingPrice;

  /// Optional floor selling price. Never negative when present.
  final double? minSellingPrice;

  /// Optional tax percentage, 0–100.
  final double? taxRate;

  /// Whether the product is currently active.
  final bool isActive;

  /// Creation timestamp (UTC).
  final DateTime createdAt;

  /// Last modification timestamp (UTC).
  final DateTime updatedAt;

  // ---------------------------------------------------------------------------
  // Convenience getters (UI only — no business rules)
  // ---------------------------------------------------------------------------

  bool get hasCategory => categoryId != null;

  /// True when a meaningful SKU is present: non-null and not whitespace-only.
  bool get hasSku => sku != null && sku!.trim().isNotEmpty;

  /// True when a meaningful barcode is present: non-null and not
  /// whitespace-only.
  bool get hasBarcode => barcode != null && barcode!.trim().isNotEmpty;

  /// True when a meaningful description is present: non-null and not
  /// whitespace-only.
  bool get hasDescription =>
      description != null && description!.trim().isNotEmpty;

  bool get hasMinSellingPrice => minSellingPrice != null;

  bool get hasTaxRate => taxRate != null;

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        categoryId,
        defaultUnitId,
        name,
        sku,
        barcode,
        description,
        costPrice,
        sellingPrice,
        minSellingPrice,
        taxRate,
        isActive,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'Product(id: $id, companyId: $companyId, name: $name, '
      'sku: $sku, sellingPrice: $sellingPrice, isActive: $isActive)';
}

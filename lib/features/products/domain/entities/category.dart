// lib/features/products/domain/entities/category.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Represents a product category inside HESABI.
///
/// Named `ProductCategory` rather than `Category` to avoid a name clash
/// with Flutter's `Category` annotation, which is exported by
/// `package:flutter/foundation.dart` (used here for `@immutable`). Any
/// file that imports both `foundation.dart` and this file would otherwise
/// produce an `ambiguous_import` error.
///
/// This is a pure Domain entity. It knows nothing about Supabase,
/// PostgreSQL, or Flutter widgets: the data layer is responsible for
/// mapping database rows into this entity.
///
/// A category always belongs to exactly one company; [companyId] is part
/// of the entity so that the presentation layer can verify that a selected
/// category is coherent with the current company without an extra query.
@immutable
class ProductCategory extends Equatable {
  const ProductCategory({
    required this.id,
    required this.companyId,
    required this.name,
    required this.sortOrder,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.description,
  });

  /// Unique identifier of the category (uuid).
  final String id;

  /// Identifier of the owning company.
  final String companyId;

  /// Display name of the category. Unique per company.
  final String name;

  /// Optional description.
  final String? description;

  /// UI ordering hint. Lower values are shown first.
  final int sortOrder;

  /// Whether the category is currently active.
  final bool isActive;

  /// Creation timestamp (UTC).
  final DateTime createdAt;

  /// Last modification timestamp (UTC).
  final DateTime updatedAt;

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        name,
        description,
        sortOrder,
        isActive,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'ProductCategory(id: $id, companyId: $companyId, name: $name, '
      'isActive: $isActive)';
}

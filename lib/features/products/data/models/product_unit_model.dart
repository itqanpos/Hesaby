// lib/features/products/data/models/product_unit_model.dart

import 'package:equatable/equatable.dart';

import '../../domain/entities/product_unit.dart';

/// Data-layer representation of a row in `public.product_units`.
///
/// Maps the PostgreSQL snake_case columns into a pure [ProductUnit] entity
/// via [toEntity]. This is the only place in the products feature that is
/// allowed to know the physical column names for product-unit conversions.
///
/// Precision:
/// `conversion_factor`, `selling_price`, `min_selling_price` and
/// `max_selling_price` are `numeric(...)` in the database. PostgREST
/// returns `numeric` values as JSON *strings* to preserve precision, so the
/// helpers below accept `String`, `int` and `double` inputs and convert
/// safely to `double`. `conversion_factor` is NOT NULL so it uses a strict
/// helper; the three price columns are optional and default to `null`.
class ProductUnitModel extends Equatable {
  const ProductUnitModel({
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

  /// Builds a model from a row returned by Supabase / PostgreSQL.
  ///
  /// Throws [FormatException] when a required column is missing or has an
  /// unexpected type.
  factory ProductUnitModel.fromMap(Map<String, dynamic> map) {
    return ProductUnitModel(
      id: _requireString(map, 'id'),
      companyId: _requireString(map, 'company_id'),
      productId: _requireString(map, 'product_id'),
      unitId: _requireString(map, 'unit_id'),
      conversionFactor: _requireDouble(map, 'conversion_factor'),
      sellingPrice: _optionalDouble(map, 'selling_price'),
      minSellingPrice: _optionalDouble(map, 'min_selling_price'),
      maxSellingPrice: _optionalDouble(map, 'max_selling_price'),
      createdAt: _requireTimestamp(map, 'created_at'),
      updatedAt: _requireTimestamp(map, 'updated_at'),
    );
  }

  final String id;
  final String companyId;
  final String productId;
  final String unitId;
  final double conversionFactor;
  final double? sellingPrice;
  final double? minSellingPrice;
  final double? maxSellingPrice;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Maps this data-layer model into the pure Domain entity.
  ProductUnit toEntity() => ProductUnit(
        id: id,
        companyId: companyId,
        productId: productId,
        unitId: unitId,
        conversionFactor: conversionFactor,
        sellingPrice: sellingPrice,
        minSellingPrice: minSellingPrice,
        maxSellingPrice: maxSellingPrice,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  // ---------------------------------------------------------------------------
  // Column helpers
  // ---------------------------------------------------------------------------

  static String _requireString(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException(
      'ProductUnitModel: missing or invalid required column "$key".',
    );
  }

  /// Parses a mandatory numeric column that may arrive as a JSON string
  /// (PostgREST returns `numeric` as string), an `int`, or a `double`.
  /// Throws [FormatException] on absence or unparseable input.
  static double _requireDouble(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final String trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        final double? parsed = double.tryParse(trimmed);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    throw FormatException(
      'ProductUnitModel: missing or invalid required column "$key".',
    );
  }

  /// Parses an optional numeric column. Returns `null` when the value is
  /// absent or unparseable.
  static double? _optionalDouble(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) {
      return null;
    }
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final String trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      return double.tryParse(trimmed);
    }
    return null;
  }

  static DateTime _requireTimestamp(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is String && value.isNotEmpty) {
      final DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed.toUtc();
      }
    }
    throw FormatException(
      'ProductUnitModel: missing or invalid timestamp column "$key".',
    );
  }

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
      'ProductUnitModel(id: $id, productId: $productId, unitId: $unitId, '
      'conversionFactor: $conversionFactor, sellingPrice: $sellingPrice)';
}

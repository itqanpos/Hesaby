// lib/features/products/data/models/product_model.dart

import 'package:equatable/equatable.dart';

import '../../domain/entities/product.dart';

/// Data-layer representation of a row in `public.products`.
///
/// Maps the PostgreSQL snake_case columns into a pure [Product] entity via
/// [toEntity]. This is the only place in the products feature that is
/// allowed to know the physical column names for products.
///
/// Money / tax precision:
/// PostgreSQL stores these columns as `numeric(...)`. PostgREST (Supabase)
/// returns `numeric` values as JSON *strings* to preserve precision, so the
/// helpers below accept `String`, `int` and `double` inputs and convert
/// safely to `double`. Missing or unparseable values fall back to `null`,
/// and the caller applies the same defaults the database uses (0 for
/// prices, null for optional fields).
class ProductModel extends Equatable {
  const ProductModel({
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
    this.maxSellingPrice,
    this.taxRate,
  });

  /// Builds a model from a row returned by Supabase / PostgreSQL.
  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      id: _requireString(map, 'id'),
      companyId: _requireString(map, 'company_id'),
      categoryId: _optionalString(map, 'category_id'),
      defaultUnitId: _requireString(map, 'default_unit_id'),
      name: _requireString(map, 'name'),
      sku: _optionalString(map, 'sku'),
      barcode: _optionalString(map, 'barcode'),
      description: _optionalString(map, 'description'),
      costPrice: _optionalDouble(map, 'cost_price') ?? 0,
      sellingPrice: _optionalDouble(map, 'selling_price') ?? 0,
      minSellingPrice: _optionalDouble(map, 'min_selling_price'),
      maxSellingPrice: _optionalDouble(map, 'max_selling_price'),
      taxRate: _optionalDouble(map, 'tax_rate'),
      isActive: _optionalBool(map, 'is_active') ?? true,
      createdAt: _requireTimestamp(map, 'created_at'),
      updatedAt: _requireTimestamp(map, 'updated_at'),
    );
  }

  final String id;
  final String companyId;
  final String? categoryId;
  final String defaultUnitId;
  final String name;
  final String? sku;
  final String? barcode;
  final String? description;
  final double costPrice;
  final double sellingPrice;
  final double? minSellingPrice;
  final double? maxSellingPrice;
  final double? taxRate;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Maps this data-layer model into the pure Domain entity.
  Product toEntity() => Product(
        id: id,
        companyId: companyId,
        categoryId: categoryId,
        defaultUnitId: defaultUnitId,
        name: name,
        sku: sku,
        barcode: barcode,
        description: description,
        costPrice: costPrice,
        sellingPrice: sellingPrice,
        minSellingPrice: minSellingPrice,
        maxSellingPrice: maxSellingPrice,
        taxRate: taxRate,
        isActive: isActive,
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
      'ProductModel: missing or invalid required column "$key".',
    );
  }

  static String? _optionalString(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) {
      return null;
    }
    if (value is String) {
      final String trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return value.toString();
  }

  /// Parses a numeric column that may arrive as a JSON string (PostgREST
  /// returns `numeric` as string to preserve precision), an `int`, or a
  /// `double`. Returns `null` on absence or unparseable input.
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

  static bool? _optionalBool(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) {
      return null;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final String lower = value.toLowerCase();
      if (lower == 'true' || lower == 't' || lower == '1') {
        return true;
      }
      if (lower == 'false' || lower == 'f' || lower == '0') {
        return false;
      }
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
      'ProductModel: missing or invalid timestamp column "$key".',
    );
  }

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
        maxSellingPrice,
        taxRate,
        isActive,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'ProductModel(id: $id, companyId: $companyId, name: $name, '
      'sku: $sku, sellingPrice: $sellingPrice)';
}

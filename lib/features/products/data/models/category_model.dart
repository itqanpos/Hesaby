// lib/features/products/data/models/category_model.dart

import 'package:equatable/equatable.dart';

import '../../domain/entities/category.dart';

/// Data-layer representation of a row in `public.categories`.
///
/// Maps the PostgreSQL snake_case columns into a pure [ProductCategory]
/// entity via [toEntity]. This is the only place in the products feature
/// that is allowed to know the physical column names for categories.
///
/// The model deliberately does not extend [ProductCategory]. Extending
/// would make `Equatable` compare `runtimeType`, so a model and its
/// corresponding entity would never be considered equal despite holding
/// the same values.
class CategoryModel extends Equatable {
  const CategoryModel({
    required this.id,
    required this.companyId,
    required this.name,
    required this.sortOrder,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.description,
  });

  /// Builds a model from a row returned by Supabase / PostgreSQL.
  ///
  /// Throws [FormatException] when a required column is missing or has an
  /// unexpected type. Optional columns default to `null`.
  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: _requireString(map, 'id'),
      companyId: _requireString(map, 'company_id'),
      name: _requireString(map, 'name'),
      description: _optionalString(map, 'description'),
      sortOrder: _optionalInt(map, 'sort_order') ?? 0,
      isActive: _optionalBool(map, 'is_active') ?? true,
      createdAt: _requireTimestamp(map, 'created_at'),
      updatedAt: _requireTimestamp(map, 'updated_at'),
    );
  }

  final String id;
  final String companyId;
  final String name;
  final String? description;
  final int sortOrder;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Maps this data-layer model into the pure Domain entity.
  ProductCategory toEntity() => ProductCategory(
        id: id,
        companyId: companyId,
        name: name,
        description: description,
        sortOrder: sortOrder,
        isActive: isActive,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  static String _requireString(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException(
      'CategoryModel: missing or invalid required column "$key".',
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

  static int? _optionalInt(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
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
      'CategoryModel: missing or invalid timestamp column "$key".',
    );
  }

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
      'CategoryModel(id: $id, companyId: $companyId, name: $name)';
}

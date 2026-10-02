// lib/features/products/data/models/unit_model.dart

import 'package:equatable/equatable.dart';

import '../../domain/entities/unit.dart';

/// Data-layer representation of a row in `public.units`.
///
/// Maps the PostgreSQL snake_case columns into a pure [Unit] entity via
/// [toEntity]. This is the only place in the products feature that is
/// allowed to know the physical column names for units.
///
/// The model deliberately does not extend [Unit], for the same reason
/// [CategoryModel] does not extend `ProductCategory`: it keeps `Equatable`
/// semantics predictable across the layer boundary.
class UnitModel extends Equatable {
  const UnitModel({
    required this.id,
    required this.companyId,
    required this.name,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.symbol,
  });

  /// Builds a model from a row returned by Supabase / PostgreSQL.
  ///
  /// Throws [FormatException] when a required column is missing or has an
  /// unexpected type. Optional columns default to `null`.
  factory UnitModel.fromMap(Map<String, dynamic> map) {
    return UnitModel(
      id: _requireString(map, 'id'),
      companyId: _requireString(map, 'company_id'),
      name: _requireString(map, 'name'),
      symbol: _optionalString(map, 'symbol'),
      isActive: _optionalBool(map, 'is_active') ?? true,
      createdAt: _requireTimestamp(map, 'created_at'),
      updatedAt: _requireTimestamp(map, 'updated_at'),
    );
  }

  final String id;
  final String companyId;
  final String name;
  final String? symbol;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Maps this data-layer model into the pure Domain entity.
  Unit toEntity() => Unit(
        id: id,
        companyId: companyId,
        name: name,
        symbol: symbol,
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
      'UnitModel: missing or invalid required column "$key".',
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
      'UnitModel: missing or invalid timestamp column "$key".',
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        name,
        symbol,
        isActive,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'UnitModel(id: $id, companyId: $companyId, name: $name, symbol: $symbol)';
}

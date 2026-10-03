// lib/features/suppliers/data/models/supplier_model.dart

import 'package:equatable/equatable.dart';

import '../../domain/entities/supplier.dart';

/// Data-layer representation of a row in `public.suppliers`.
///
/// Maps the PostgreSQL snake_case columns into a pure [Supplier] entity via
/// [toEntity]. This is the only place in the suppliers feature that is
/// allowed to know the physical column names for suppliers.
///
/// The model deliberately does not extend [Supplier]. Extending would make
/// `Equatable` compare `runtimeType`, so a model and its corresponding
/// entity would never be considered equal despite holding the same values.
class SupplierModel extends Equatable {
  const SupplierModel({
    required this.id,
    required this.companyId,
    required this.name,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.code,
    this.phone,
    this.email,
    this.address,
    this.notes,
  });

  /// Builds a model from a row returned by Supabase / PostgreSQL.
  ///
  /// Throws [FormatException] when a required column is missing or has an
  /// unexpected type. Optional columns default to `null`.
  factory SupplierModel.fromMap(Map<String, dynamic> map) {
    return SupplierModel(
      id: _requireString(map, 'id'),
      companyId: _requireString(map, 'company_id'),
      name: _requireString(map, 'name'),
      code: _optionalString(map, 'code'),
      phone: _optionalString(map, 'phone'),
      email: _optionalString(map, 'email'),
      address: _optionalString(map, 'address'),
      notes: _optionalString(map, 'notes'),
      isActive: _optionalBool(map, 'is_active') ?? true,
      createdAt: _requireTimestamp(map, 'created_at'),
      updatedAt: _requireTimestamp(map, 'updated_at'),
    );
  }

  final String id;
  final String companyId;
  final String name;
  final String? code;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Maps this data-layer model into the pure Domain entity.
  Supplier toEntity() => Supplier(
        id: id,
        companyId: companyId,
        name: name,
        code: code,
        phone: phone,
        email: email,
        address: address,
        notes: notes,
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
      'SupplierModel: missing or invalid required column "$key".',
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
      'SupplierModel: missing or invalid timestamp column "$key".',
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        name,
        code,
        phone,
        email,
        address,
        notes,
        isActive,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'SupplierModel(id: $id, companyId: $companyId, name: $name, '
      'code: $code)';
}

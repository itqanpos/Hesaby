// lib/features/companies/data/models/company_model.dart

import 'package:equatable/equatable.dart';

import '../../domain/entities/company.dart';

/// Data-layer representation of a row in `public.companies`.
///
/// Maps the PostgreSQL snake_case columns into a pure [Company] entity via
/// [toEntity]. This is the only place in the companies feature that is
/// allowed to know the physical column names.
///
/// The model deliberately does not extend [Company]. Extending would make
/// `Equatable` compare `runtimeType`, so a model and its corresponding
/// entity would never be considered equal despite holding the same values.
class CompanyModel extends Equatable {
  const CompanyModel({
    required this.id,
    required this.name,
    required this.currency,
    required this.timezone,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.legalName,
    this.phone,
    this.email,
    this.address,
  });

  /// Builds a model from a row returned by Supabase / PostgreSQL.
  ///
  /// Throws [FormatException] when a required column is missing or has an
  /// unexpected type. Optional columns default to `null`.
  factory CompanyModel.fromMap(Map<String, dynamic> map) {
    return CompanyModel(
      id: _requireString(map, 'id'),
      name: _requireString(map, 'name'),
      legalName: _optionalString(map, 'legal_name'),
      phone: _optionalString(map, 'phone'),
      email: _optionalString(map, 'email'),
      address: _optionalString(map, 'address'),
      currency: _optionalString(map, 'currency') ?? 'EGP',
      timezone: _optionalString(map, 'timezone') ?? 'Africa/Cairo',
      isActive: _optionalBool(map, 'is_active') ?? true,
      createdAt: _requireTimestamp(map, 'created_at'),
      updatedAt: _requireTimestamp(map, 'updated_at'),
    );
  }

  final String id;
  final String name;
  final String? legalName;
  final String? phone;
  final String? email;
  final String? address;
  final String currency;
  final String timezone;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Maps this data-layer model into the pure Domain entity.
  Company toEntity() => Company(
        id: id,
        name: name,
        legalName: legalName,
        phone: phone,
        email: email,
        address: address,
        currency: currency,
        timezone: timezone,
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
      'CompanyModel: missing or invalid required column "$key".',
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
      'CompanyModel: missing or invalid timestamp column "$key".',
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        name,
        legalName,
        phone,
        email,
        address,
        currency,
        timezone,
        isActive,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() => 'CompanyModel(id: $id, name: $name)';
}

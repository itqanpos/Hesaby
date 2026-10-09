// lib/features/companies/data/models/company_member_model.dart

import 'package:equatable/equatable.dart';

import '../../domain/entities/company_member.dart';

/// Data-layer representation of a row in `public.company_members`,
/// optionally enriched with the member's `profiles` row.
///
/// The model is deliberately not extended by the entity; conversion goes
/// through [toEntity], keeping the entity free of physical column names.
class CompanyMemberModel extends Equatable {
  const CompanyMemberModel({
    required this.id,
    required this.companyId,
    required this.userId,
    required this.role,
    required this.isActive,
    required this.deniedPermissions,
    required this.createdAt,
    required this.updatedAt,
    this.displayName,
    this.phone,
    this.email,
  });

  /// Builds a model from a `company_members` row, optionally merging a
  /// `profiles` row with the same `user_id`.
  ///
  /// [profile] is the raw row from `profiles` (keys: `user_id`, `full_name`,
  /// `phone`), or `null` when the profile could not be read.
  factory CompanyMemberModel.fromMap(
    Map<String, dynamic> map, {
    Map<String, dynamic>? profile,
    String? email,
  }) {
    return CompanyMemberModel(
      id: _requireString(map, 'id'),
      companyId: _requireString(map, 'company_id'),
      userId: _requireString(map, 'user_id'),
      role: _requireString(map, 'role'),
      isActive: _requireBool(map, 'is_active'),
      deniedPermissions: _optionalStringList(map, 'denied_permissions'),
      createdAt: _requireTimestamp(map, 'created_at'),
      updatedAt: _requireTimestamp(map, 'updated_at'),
      displayName: profile == null
          ? null
          : _optionalString(profile, 'full_name'),
      phone: profile == null ? null : _optionalString(profile, 'phone'),
      email: email,
    );
  }

  final String id;
  final String companyId;
  final String userId;
  final String role;
  final bool isActive;
  final List<String> deniedPermissions;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? displayName;
  final String? phone;
  final String? email;

  CompanyMember toEntity() => CompanyMember(
        id: id,
        companyId: companyId,
        userId: userId,
        role: role,
        isActive: isActive,
        deniedPermissions: deniedPermissions,
        displayName: displayName,
        phone: phone,
        email: email,
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
      'CompanyMemberModel: missing or invalid required column "$key".',
    );
  }

  static String? _optionalString(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) return null;
    if (value is String) {
      final String trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return value.toString();
  }

  static bool _requireBool(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final String lower = value.toLowerCase();
      if (lower == 'true' || lower == 't' || lower == '1') return true;
      if (lower == 'false' || lower == 'f' || lower == '0') return false;
    }
    throw FormatException(
      'CompanyMemberModel: "$key" is not boolean.',
    );
  }

  static List<String> _optionalStringList(
    Map<String, dynamic> map,
    String key,
  ) {
    final Object? value = map[key];
    if (value == null) {
      return const <String>[];
    }
    if (value is List) {
      return value
          .whereType<String>()
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  static DateTime _requireTimestamp(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is DateTime) return value.toUtc();
    if (value is String && value.isNotEmpty) {
      final DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    throw FormatException(
      'CompanyMemberModel: missing or invalid timestamp "$key".',
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        userId,
        role,
        isActive,
        deniedPermissions,
        createdAt,
        updatedAt,
        displayName,
        phone,
        email,
      ];

  @override
  String toString() =>
      'CompanyMemberModel(id: $id, userId: $userId, role: $role)';
}

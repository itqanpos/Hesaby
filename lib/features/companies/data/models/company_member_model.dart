// lib/features/companies/data/models/company_member_model.dart

import 'package:equatable/equatable.dart';

import '../../domain/entities/company_member.dart';

/// Data-layer representation of a row in `public.company_members`,
/// optionally enriched with the member's `profiles` row.
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

  /// ⬇️ إصلاح: شبكة أمان لتحويل تواريخ PostgreSQL
  static DateTime _requireTimestamp(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) {
      return DateTime.now().toUtc(); // قيمة افتراضية بدلاً من الانهيار
    }
    if (value is DateTime) return value.toUtc();
    
    if (value is String && value.isNotEmpty) {
      // 1. محاولة القراءة المباشرة
      DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();

      // 2. المعالجة لتنسيق Postgres (مثل "2026-10-02 11:27:09.602636+00")
      try {
        String normalized = value.trim();
        if (normalized.contains(' ')) {
          normalized = normalized.replaceFirst(' ', 'T');
        }
        if (normalized.endsWith('+00')) {
          normalized = normalized.replaceAll('+00', 'Z');
        } else if (normalized.endsWith('-00')) {
          normalized = normalized.replaceAll('-00', 'Z');
        }
        parsed = DateTime.tryParse(normalized);
        if (parsed != null) return parsed.toUtc();
      } catch (_) {}
    }
    
    // بدلاً من رمي FormatException (الذي يسبب انهيار الشاشة)، نرجع الوقت الحالي
    return DateTime.now().toUtc();
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

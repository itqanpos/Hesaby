// lib/features/companies/data/models/branch_model.dart

import 'package:equatable/equatable.dart';

import '../../domain/entities/branch.dart';

/// Data-layer representation of a row in `public.branches`.
class BranchModel extends Equatable {
  const BranchModel({
    required this.id,
    required this.companyId,
    required this.name,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.code,
    this.address,
    this.phone,
  });

  factory BranchModel.fromMap(Map<String, dynamic> map) {
    return BranchModel(
      id: _requireString(map, 'id'),
      companyId: _requireString(map, 'company_id'),
      name: _requireString(map, 'name'),
      code: _optionalString(map, 'code'),
      address: _optionalString(map, 'address'),
      phone: _optionalString(map, 'phone'),
      isActive: _optionalBool(map, 'is_active') ?? true,
      createdAt: _requireTimestamp(map, 'created_at'),
      updatedAt: _requireTimestamp(map, 'updated_at'),
    );
  }

  final String id;
  final String companyId;
  final String name;
  final String? code;
  final String? address;
  final String? phone;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Branch toEntity() => Branch(
        id: id,
        companyId: companyId,
        name: name,
        code: code,
        address: address,
        phone: phone,
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
      'BranchModel: missing or invalid required column "$key".',
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

  static bool? _optionalBool(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final String lower = value.toLowerCase();
      if (lower == 'true' || lower == 't' || lower == '1') return true;
      if (lower == 'false' || lower == 'f' || lower == '0') return false;
    }
    return null;
  }

  static DateTime _requireTimestamp(Map<String, dynamic> map, String key) {
    final DateTime? parsed = _optionalTimestamp(map, key);
    if (parsed != null) return parsed;
    throw FormatException(
      'BranchModel: missing or invalid timestamp column "$key".',
    );
  }

  /// 🔥 الإصلاح هنا: دالة تقوم بتنظيف النص القادم من Supabase لتفهمه Dart
  static DateTime? _optionalTimestamp(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is String && value.isNotEmpty) {
      // المحاولة الأولى: التنسيق القياسي
      DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();

      // المحاولة الثانية: تنسيق Postgres (مثل "2026-10-02 11:27:09.602636+00")
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
    return null;
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        name,
        code,
        address,
        phone,
        isActive,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() => 'BranchModel(id: $id, companyId: $companyId, name: $name)';
}

// lib/features/companies/data/models/company_model.dart

import 'package:equatable/equatable.dart';

import '../../domain/entities/company.dart';

/// Data-layer representation of a row in `public.companies`.
class CompanyModel extends Equatable {
  const CompanyModel({
    required this.id,
    required this.name,
    required this.currency,
    required this.timezone,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.subscriptionStatus,
    required this.maxUsers,
    required this.maxBranches,
    this.legalName,
    this.phone,
    this.email,
    this.address,
    this.taxNumber,
    this.commercialRegister,
    this.trialEndsAt,
    this.subscriptionStartedAt,
    this.planId,
    this.billingCycle,
    this.subscribedUntil,
    this.isSuspended = false,
    this.suspensionReason,
  });

  factory CompanyModel.fromMap(Map<String, dynamic> map) {
    return CompanyModel(
      id: _requireString(map, 'id'),
      name: _requireString(map, 'name'),
      legalName: _optionalString(map, 'legal_name'),
      phone: _optionalString(map, 'phone'),
      email: _optionalString(map, 'email'),
      address: _optionalString(map, 'address'),
      taxNumber: _optionalString(map, 'tax_number'),
      commercialRegister: _optionalString(map, 'commercial_register'),
      currency: _optionalString(map, 'currency') ?? 'EGP',
      timezone: _optionalString(map, 'timezone') ?? 'Africa/Cairo',
      isActive: _optionalBool(map, 'is_active') ?? true,
      createdAt: _requireTimestamp(map, 'created_at'),
      updatedAt: _requireTimestamp(map, 'updated_at'),
      subscriptionStatus:
          _optionalString(map, 'subscription_status') ?? 'trial',
      trialEndsAt: _optionalTimestamp(map, 'trial_ends_at'),
      subscriptionStartedAt:
          _optionalTimestamp(map, 'subscription_started_at'),
      planId: _optionalString(map, 'plan_id'),
      billingCycle: _optionalString(map, 'billing_cycle'),
      subscribedUntil: _optionalTimestamp(map, 'subscribed_until'),
      // ---- New fields ----
      isSuspended: _optionalBool(map, 'is_suspended') ?? false,
      suspensionReason: _optionalString(map, 'suspension_reason'),
      maxUsers: _optionalInt(map, 'max_users') ?? 5,
      maxBranches: _optionalInt(map, 'max_branches') ?? 1,
    );
  }

  final String id;
  final String name;
  final String? legalName;
  final String? phone;
  final String? email;
  final String? address;
  final String? taxNumber;
  final String? commercialRegister;
  final String currency;
  final String timezone;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  final String subscriptionStatus;
  final DateTime? trialEndsAt;
  final DateTime? subscriptionStartedAt;
  final String? planId;
  final String? billingCycle;
  final DateTime? subscribedUntil;

  // ---- Suspension & Limits ----
  final bool isSuspended;
  final String? suspensionReason;
  final int maxUsers;
  final int maxBranches;

  Company toEntity() => Company(
        id: id,
        name: name,
        legalName: legalName,
        phone: phone,
        email: email,
        address: address,
        taxNumber: taxNumber,
        commercialRegister: commercialRegister,
        currency: currency,
        timezone: timezone,
        isActive: isActive,
        createdAt: createdAt,
        updatedAt: updatedAt,
        subscriptionStatus: subscriptionStatus,
        trialEndsAt: trialEndsAt,
        subscriptionStartedAt: subscriptionStartedAt,
        planId: planId,
        billingCycle: billingCycle,
        subscribedUntil: subscribedUntil,
        isSuspended: isSuspended,
        suspensionReason: suspensionReason,
        maxUsers: maxUsers,
        maxBranches: maxBranches,
      );

  static String _requireString(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException(
      'CompanyModel: missing or invalid required column "$key".',
    );
  }

  static String? _optionalString(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) return null;
    if (value is String) {
      final String t = value.trim();
      return t.isEmpty ? null : t;
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

  static int? _optionalInt(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime _requireTimestamp(Map<String, dynamic> map, String key) {
    final DateTime? parsed = _optionalTimestamp(map, key);
    if (parsed != null) return parsed;
    throw FormatException(
      'CompanyModel: missing or invalid timestamp column "$key".',
    );
  }

  static DateTime? _optionalTimestamp(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is String && value.isNotEmpty) {
      final DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    return null;
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        name,
        legalName,
        phone,
        email,
        address,
        taxNumber,
        commercialRegister,
        currency,
        timezone,
        isActive,
        createdAt,
        updatedAt,
        subscriptionStatus,
        trialEndsAt,
        subscriptionStartedAt,
        planId,
        billingCycle,
        subscribedUntil,
        isSuspended,
        suspensionReason,
        maxUsers,
        maxBranches,
      ];

  @override
  String toString() =>
      'CompanyModel(id: $id, name: $name, status: $subscriptionStatus, '
      'isSuspended: $isSuspended)';
}

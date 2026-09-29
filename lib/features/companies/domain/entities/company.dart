// lib/features/companies/domain/entities/company.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Represents a tenant company inside HESABI.
///
/// This is a pure Domain entity. It knows nothing about Supabase, PostgreSQL,
/// or Flutter widgets. The data layer is responsible for mapping database
/// rows into this entity.
///
/// Phase 3 scope only: it carries the fields required to display and select
/// a company. Business relationships (owner, members, subscription plan,
/// billing) are intentionally out of scope.
@immutable
class Company extends Equatable {
  const Company({
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

  /// Unique identifier of the company (uuid).
  final String id;

  /// Display name of the company. Always present.
  final String name;

  /// Optional registered / legal name used on invoices.
  final String? legalName;

  /// Optional contact phone number.
  final String? phone;

  /// Optional contact email address.
  final String? email;

  /// Optional postal / physical address.
  final String? address;

  /// ISO 4217 currency code (3 uppercase letters), e.g. `EGP`.
  final String currency;

  /// IANA timezone identifier, e.g. `Africa/Cairo`.
  final String timezone;

  /// Whether the company is currently active.
  final bool isActive;

  final DateTime createdAt;
  final DateTime updatedAt;

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
  String toString() => 'Company(id: $id, name: $name, isActive: $isActive)';
}

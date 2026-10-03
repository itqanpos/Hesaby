// lib/features/suppliers/domain/entities/supplier.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Represents a supplier of a company inside HESABI.
///
/// This is a pure Domain entity. It knows nothing about Supabase,
/// PostgreSQL, or Flutter widgets.
///
/// A supplier always belongs to exactly one company; [companyId] is part of
/// the entity so that the presentation layer can verify tenant coherence
/// without an extra query.
///
/// Phase 6 scope only: it carries contact and identification data.
/// Financial concepts (opening balance, credit limit, aging) are out of
/// scope and belong to later phases.
@immutable
class Supplier extends Equatable {
  const Supplier({
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

  /// Unique identifier of the supplier (uuid).
  final String id;

  /// Identifier of the owning company.
  final String companyId;

  /// Display name of the supplier. Unique per company.
  final String name;

  /// Optional internal code (e.g. `SUP-001`). Unique per company when
  /// present.
  final String? code;

  /// Optional contact phone. Unique per company when present.
  final String? phone;

  /// Optional contact email. Not unique (several suppliers may share one).
  final String? email;

  /// Optional postal / physical address.
  final String? address;

  /// Optional free-form notes.
  final String? notes;

  /// Whether the supplier is currently active.
  final bool isActive;

  /// Creation timestamp (UTC).
  final DateTime createdAt;

  /// Last modification timestamp (UTC).
  final DateTime updatedAt;

  // ---------------------------------------------------------------------------
  // Convenience getters (UI only — no business rules)
  // ---------------------------------------------------------------------------

  /// True when a meaningful code is present: non-null and not
  /// whitespace-only.
  bool get hasCode => code != null && code!.trim().isNotEmpty;

  /// True when a meaningful phone number is present.
  bool get hasPhone => phone != null && phone!.trim().isNotEmpty;

  /// True when a meaningful email is present.
  bool get hasEmail => email != null && email!.trim().isNotEmpty;

  /// True when a meaningful address is present.
  bool get hasAddress => address != null && address!.trim().isNotEmpty;

  /// True when a meaningful note is present.
  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;

  /// True when at least one contact channel (phone or email) is available.
  bool get hasContactInfo => hasPhone || hasEmail;

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
      'Supplier(id: $id, companyId: $companyId, name: $name, '
      'code: $code, isActive: $isActive)';
}

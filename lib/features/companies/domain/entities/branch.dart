// lib/features/companies/domain/entities/branch.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Represents a branch belonging to a tenant company.
///
/// This is a pure Domain entity. It knows nothing about Supabase, PostgreSQL,
/// or Flutter widgets.
///
/// A branch always belongs to exactly one company; [companyId] is part of the
/// entity so that the presentation layer can verify that a selected branch is
/// coherent with the currently selected company without an extra query.
@immutable
class Branch extends Equatable {
  const Branch({
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

  /// Unique identifier of the branch (uuid).
  final String id;

  /// Identifier of the owning company.
  final String companyId;

  /// Display name of the branch. Unique per company.
  final String name;

  /// Optional short code, unique per company when present.
  final String? code;

  /// Optional postal / physical address.
  final String? address;

  /// Optional contact phone number.
  final String? phone;

  /// Whether the branch is currently active.
  final bool isActive;

  /// Creation timestamp (UTC).
  final DateTime createdAt;

  /// Last modification timestamp (UTC).
  final DateTime updatedAt;

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
  String toString() => 'Branch(id: $id, companyId: $companyId, name: $name)';
}

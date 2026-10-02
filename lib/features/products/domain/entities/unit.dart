// lib/features/products/domain/entities/unit.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Represents a unit of measurement inside HESABI (piece, carton, kilogram,
/// litre, metre, …).
///
/// This is a pure Domain entity. It knows nothing about Supabase,
/// PostgreSQL, or Flutter widgets.
///
/// A unit always belongs to exactly one company; [companyId] is part of the
/// entity so that the presentation layer can verify that a selected unit is
/// coherent with the current company without an extra query.
@immutable
class Unit extends Equatable {
  const Unit({
    required this.id,
    required this.companyId,
    required this.name,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.symbol,
  });

  /// Unique identifier of the unit (uuid).
  final String id;

  /// Identifier of the owning company.
  final String companyId;

  /// Display name of the unit. Unique per company.
  final String name;

  /// Optional short symbol, e.g. `kg`, `L`, `pcs`.
  final String? symbol;

  /// Whether the unit is currently active.
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
        symbol,
        isActive,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'Unit(id: $id, companyId: $companyId, name: $name, symbol: $symbol)';
}

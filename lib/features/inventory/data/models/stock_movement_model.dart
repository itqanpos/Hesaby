// lib/features/inventory/data/models/stock_movement_model.dart

import 'package:equatable/equatable.dart';

import '../../domain/entities/stock_movement.dart';

/// Data-layer representation of a row in `public.stock_movements`.
///
/// Maps the PostgreSQL snake_case columns into a pure [StockMovement] entity
/// via [toEntity]. This is the only place in the inventory feature that is
/// allowed to know the physical column names for stock movements.
///
/// Precision:
/// `quantity` and `unit_cost` are `numeric(15,4)` in the database.
/// PostgREST returns `numeric` values as JSON *strings* to preserve
/// precision, so the helpers below accept `String`, `int` and `double`
/// inputs and convert safely to `double`. `quantity` is NOT NULL and never
/// zero, so it is parsed with a strict helper that raises [FormatException]
/// on absence or unparseable input; `unit_cost` is optional and falls back
/// to `null`.
class StockMovementModel extends Equatable {
  const StockMovementModel({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.productId,
    required this.movementType,
    required this.quantity,
    required this.createdAt,
    this.unitCost,
    this.referenceType,
    this.referenceId,
    this.notes,
    this.createdBy,
  });

  /// Builds a model from a row returned by Supabase / PostgreSQL.
  factory StockMovementModel.fromMap(Map<String, dynamic> map) {
    return StockMovementModel(
      id: _requireString(map, 'id'),
      companyId: _requireString(map, 'company_id'),
      branchId: _requireString(map, 'branch_id'),
      productId: _requireString(map, 'product_id'),
      movementType: _requireString(map, 'movement_type'),
      quantity: _requireDouble(map, 'quantity'),
      unitCost: _optionalDouble(map, 'unit_cost'),
      referenceType: _optionalString(map, 'reference_type'),
      referenceId: _optionalString(map, 'reference_id'),
      notes: _optionalString(map, 'notes'),
      createdBy: _optionalString(map, 'created_by'),
      createdAt: _requireTimestamp(map, 'created_at'),
    );
  }

  final String id;
  final String companyId;
  final String branchId;
  final String productId;
  final String movementType;
  final double quantity;
  final double? unitCost;
  final String? referenceType;
  final String? referenceId;
  final String? notes;
  final String? createdBy;
  final DateTime createdAt;

  /// Maps this data-layer model into the pure Domain entity.
  StockMovement toEntity() => StockMovement(
        id: id,
        companyId: companyId,
        branchId: branchId,
        productId: productId,
        movementType: movementType,
        quantity: quantity,
        unitCost: unitCost,
        referenceType: referenceType,
        referenceId: referenceId,
        notes: notes,
        createdBy: createdBy,
        createdAt: createdAt,
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
      'StockMovementModel: missing or invalid required column "$key".',
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

  /// Parses a mandatory numeric column that may arrive as a JSON string
  /// (PostgREST returns `numeric` as string), an `int`, or a `double`.
  /// Throws [FormatException] on absence or unparseable input.
  static double _requireDouble(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final String trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        final double? parsed = double.tryParse(trimmed);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    throw FormatException(
      'StockMovementModel: missing or invalid required column "$key".',
    );
  }

  /// Parses an optional numeric column. Returns `null` when the value is
  /// absent or unparseable.
  static double? _optionalDouble(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) {
      return null;
    }
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final String trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      return double.tryParse(trimmed);
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
      'StockMovementModel: missing or invalid timestamp column "$key".',
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        branchId,
        productId,
        movementType,
        quantity,
        unitCost,
        referenceType,
        referenceId,
        notes,
        createdBy,
        createdAt,
      ];

  @override
  String toString() =>
      'StockMovementModel(id: $id, type: $movementType, quantity: $quantity)';
}

// lib/features/inventory/data/models/inventory_balance_model.dart

import 'package:equatable/equatable.dart';

import '../../domain/entities/inventory_balance.dart';

/// Data-layer representation of a row in `public.inventory_balances`.
///
/// Maps the PostgreSQL snake_case columns into a pure [InventoryBalance]
/// entity via [toEntity]. This is the only place in the inventory feature
/// that is allowed to know the physical column names for inventory
/// balances.
///
/// Precision:
/// `quantity_on_hand` and `average_cost` are `numeric(15,4)` in the
/// database. PostgREST returns `numeric` values as JSON *strings* to
/// preserve precision, so the helpers below accept `String`, `int` and
/// `double` inputs and convert safely to `double`. Both columns are
/// NOT NULL with a default of 0, so they are parsed with a strict helper
/// that raises [FormatException] on absence or unparseable input.
///
/// `last_movement_at` is optional: rows are created with zero quantity and
/// a null timestamp until the first movement is applied.
class InventoryBalanceModel extends Equatable {
  const InventoryBalanceModel({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.productId,
    required this.quantityOnHand,
    required this.averageCost,
    required this.createdAt,
    required this.updatedAt,
    this.lastMovementAt,
  });

  /// Builds a model from a row returned by Supabase / PostgreSQL.
  factory InventoryBalanceModel.fromMap(Map<String, dynamic> map) {
    return InventoryBalanceModel(
      id: _requireString(map, 'id'),
      companyId: _requireString(map, 'company_id'),
      branchId: _requireString(map, 'branch_id'),
      productId: _requireString(map, 'product_id'),
      quantityOnHand: _requireDouble(map, 'quantity_on_hand'),
      averageCost: _requireDouble(map, 'average_cost'),
      lastMovementAt: _optionalTimestamp(map, 'last_movement_at'),
      createdAt: _requireTimestamp(map, 'created_at'),
      updatedAt: _requireTimestamp(map, 'updated_at'),
    );
  }

  final String id;
  final String companyId;
  final String branchId;
  final String productId;
  final double quantityOnHand;
  final double averageCost;
  final DateTime? lastMovementAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Maps this data-layer model into the pure Domain entity.
  InventoryBalance toEntity() => InventoryBalance(
        id: id,
        companyId: companyId,
        branchId: branchId,
        productId: productId,
        quantityOnHand: quantityOnHand,
        averageCost: averageCost,
        lastMovementAt: lastMovementAt,
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
      'InventoryBalanceModel: missing or invalid required column "$key".',
    );
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
      'InventoryBalanceModel: missing or invalid required column "$key".',
    );
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
      'InventoryBalanceModel: missing or invalid timestamp column "$key".',
    );
  }

  /// Parses an optional timestamp column. Returns `null` when the value is
  /// absent or unparseable.
  static DateTime? _optionalTimestamp(
    Map<String, dynamic> map,
    String key,
  ) {
    final Object? value = map[key];
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is String && value.isNotEmpty) {
      final DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed.toUtc();
      }
    }
    return null;
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        branchId,
        productId,
        quantityOnHand,
        averageCost,
        lastMovementAt,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'InventoryBalanceModel(id: $id, branchId: $branchId, '
      'productId: $productId, quantityOnHand: $quantityOnHand)';
}

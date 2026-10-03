// lib/features/purchases/data/models/purchase_item_model.dart

import 'package:equatable/equatable.dart';

import '../../domain/entities/purchase_item.dart';

/// Data-layer representation of a row in `public.purchase_items`.
///
/// Maps the PostgreSQL snake_case columns into a pure [PurchaseItem] entity
/// via [toEntity]. This is the only place in the purchases feature that is
/// allowed to know the physical column names for purchase line items.
///
/// Precision:
/// `quantity`, `unit_cost` and `line_total` are `numeric(15,4)` in the
/// database. PostgREST returns `numeric` values as JSON *strings* to
/// preserve precision, so the helpers below accept `String`, `int` and
/// `double` inputs and convert safely to `double`.
///
/// `line_total` is maintained by the database trigger and is read-only from
/// the client's perspective; the model simply carries it forward.
class PurchaseItemModel extends Equatable {
  const PurchaseItemModel({
    required this.id,
    required this.companyId,
    required this.purchaseId,
    required this.productId,
    required this.unitId,
    required this.quantity,
    required this.unitCost,
    required this.lineTotal,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
  });

  /// Builds a model from a row returned by Supabase / PostgreSQL.
  factory PurchaseItemModel.fromMap(Map<String, dynamic> map) {
    return PurchaseItemModel(
      id: _requireString(map, 'id'),
      companyId: _requireString(map, 'company_id'),
      purchaseId: _requireString(map, 'purchase_id'),
      productId: _requireString(map, 'product_id'),
      unitId: _requireString(map, 'unit_id'),
      quantity: _requireDouble(map, 'quantity'),
      unitCost: _requireDouble(map, 'unit_cost'),
      lineTotal: _requireDouble(map, 'line_total'),
      notes: _optionalString(map, 'notes'),
      createdAt: _requireTimestamp(map, 'created_at'),
      updatedAt: _requireTimestamp(map, 'updated_at'),
    );
  }

  final String id;
  final String companyId;
  final String purchaseId;
  final String productId;
  final String unitId;
  final double quantity;
  final double unitCost;
  final double lineTotal;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Maps this data-layer model into the pure Domain entity.
  PurchaseItem toEntity() => PurchaseItem(
        id: id,
        companyId: companyId,
        purchaseId: purchaseId,
        productId: productId,
        unitId: unitId,
        quantity: quantity,
        unitCost: unitCost,
        lineTotal: lineTotal,
        notes: notes,
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
      'PurchaseItemModel: missing or invalid required column "$key".',
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
      'PurchaseItemModel: missing or invalid required column "$key".',
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
      'PurchaseItemModel: missing or invalid timestamp column "$key".',
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        purchaseId,
        productId,
        unitId,
        quantity,
        unitCost,
        lineTotal,
        notes,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'PurchaseItemModel(id: $id, purchaseId: $purchaseId, '
      'productId: $productId, lineTotal: $lineTotal)';
}

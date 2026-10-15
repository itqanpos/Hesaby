// lib/features/inventory/data/models/stock_count_model.dart

import '../../domain/entities/stock_count.dart';

// ============================================================================
// StockCountSessionModel
// ============================================================================

/// Data-layer representation of a row in `stock_count_sessions`.
///
/// Parses raw PostgREST JSON into a strongly typed object and exposes
/// [toEntity] for the domain layer.
///
/// Numeric columns are delivered as strings by PostgREST in some
/// configurations and as numbers in others; both are handled here.
class StockCountSessionModel {
  const StockCountSessionModel({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.status,
    required this.startedAt,
    this.notes,
    this.confirmedAt,
    this.cancelledAt,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory StockCountSessionModel.fromMap(Map<String, dynamic> map) {
    return StockCountSessionModel(
      id: _requireString(map['id'], 'id'),
      companyId: _requireString(map['company_id'], 'company_id'),
      branchId: _requireString(map['branch_id'], 'branch_id'),
      status: _requireString(map['status'], 'status'),
      startedAt: _requireDate(map['started_at'], 'started_at'),
      notes: _optionalString(map['notes']),
      confirmedAt: _optionalDate(map['confirmed_at']),
      cancelledAt: _optionalDate(map['cancelled_at']),
      createdBy: _optionalString(map['created_by']),
      createdAt: _optionalDate(map['created_at']),
      updatedAt: _optionalDate(map['updated_at']),
    );
  }

  final String id;
  final String companyId;
  final String branchId;
  final String status;
  final DateTime startedAt;
  final String? notes;
  final DateTime? confirmedAt;
  final DateTime? cancelledAt;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  StockCountSession toEntity({
    int itemCount = 0,
    int countedItemCount = 0,
    int varianceItemCount = 0,
  }) {
    return StockCountSession(
      id: id,
      companyId: companyId,
      branchId: branchId,
      status: status,
      startedAt: startedAt,
      notes: notes,
      confirmedAt: confirmedAt,
      cancelledAt: cancelledAt,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt,
      itemCount: itemCount,
      countedItemCount: countedItemCount,
      varianceItemCount: varianceItemCount,
    );
  }
}

// ============================================================================
// StockCountItemModel
// ============================================================================

/// Data-layer representation of a row in `stock_count_items`.
class StockCountItemModel {
  const StockCountItemModel({
    required this.id,
    required this.companyId,
    required this.sessionId,
    required this.productId,
    required this.expectedQuantity,
    this.unitId,
    this.actualQuantity,
    this.notes,
  });

  factory StockCountItemModel.fromMap(Map<String, dynamic> map) {
    return StockCountItemModel(
      id: _requireString(map['id'], 'id'),
      companyId: _requireString(map['company_id'], 'company_id'),
      sessionId: _requireString(map['session_id'], 'session_id'),
      productId: _requireString(map['product_id'], 'product_id'),
      expectedQuantity:
          _requireDouble(map['expected_quantity'], 'expected_quantity'),
      unitId: _optionalString(map['unit_id']),
      actualQuantity: _optionalDouble(map['actual_quantity']),
      notes: _optionalString(map['notes']),
    );
  }

  final String id;
  final String companyId;
  final String sessionId;
  final String productId;
  final double expectedQuantity;
  final String? unitId;
  final double? actualQuantity;
  final String? notes;

  StockCountItem toEntity({
    String? productName,
    String? unitName,
  }) {
    return StockCountItem(
      id: id,
      companyId: companyId,
      sessionId: sessionId,
      productId: productId,
      expectedQuantity: expectedQuantity,
      unitId: unitId,
      actualQuantity: actualQuantity,
      notes: notes,
      productName: productName,
      unitName: unitName,
    );
  }
}

// ============================================================================
// Parsing helpers
// ============================================================================

String _requireString(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Missing or empty required string: $field');
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is String) {
    final String t = value.trim();
    return t.isEmpty ? null : t;
  }
  final String t = value.toString().trim();
  return t.isEmpty ? null : t;
}

double _requireDouble(Object? value, String field) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  if (value is String) {
    final double? parsed = double.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('Missing or non-numeric value for: $field');
}

double? _optionalDouble(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  if (value is String) {
    final double? parsed = double.tryParse(value);
    return parsed;
  }
  return null;
}

DateTime _requireDate(Object? value, String field) {
  if (value is DateTime) return value.toUtc();
  if (value is String) {
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toUtc();
  }
  throw FormatException('Missing or invalid timestamp: $field');
}

DateTime? _optionalDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  if (value is String) {
    final DateTime? parsed = DateTime.tryParse(value);
    return parsed?.toUtc();
  }
  return null;
}

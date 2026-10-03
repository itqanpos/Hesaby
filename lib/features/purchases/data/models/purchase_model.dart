// lib/features/purchases/data/models/purchase_model.dart

import 'package:equatable/equatable.dart';

import '../../domain/entities/purchase.dart';

/// Data-layer representation of a row in `public.purchases`.
///
/// Maps the PostgreSQL snake_case columns into a pure [Purchase] entity via
/// [toEntity]. This is the only place in the purchases feature that is
/// allowed to know the physical column names for purchases.
///
/// Precision:
/// `subtotal`, `discount`, `tax_amount` and `total` are `numeric(15,4)` in
/// the database. PostgREST returns `numeric` values as JSON *strings* to
/// preserve precision, so the helpers below accept `String`, `int` and
/// `double` inputs and convert safely to `double`.
///
/// Date handling:
/// `purchase_date` is a PostgreSQL `date` (no time component). PostgREST
/// returns it as `"YYYY-MM-DD"`, which [DateTime.tryParse] interprets as
/// midnight UTC. `confirmed_at` and `cancelled_at` are `timestamptz` and
/// are handled by the timestamp helper.
class PurchaseModel extends Equatable {
  const PurchaseModel({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.supplierId,
    required this.purchaseDate,
    required this.status,
    required this.subtotal,
    required this.discount,
    required this.taxAmount,
    required this.total,
    required this.createdAt,
    required this.updatedAt,
    this.invoiceNumber,
    this.notes,
    this.createdBy,
    this.confirmedAt,
    this.cancelledAt,
  });

  /// Builds a model from a row returned by Supabase / PostgreSQL.
  factory PurchaseModel.fromMap(Map<String, dynamic> map) {
    return PurchaseModel(
      id: _requireString(map, 'id'),
      companyId: _requireString(map, 'company_id'),
      branchId: _requireString(map, 'branch_id'),
      supplierId: _requireString(map, 'supplier_id'),
      invoiceNumber: _optionalString(map, 'invoice_number'),
      purchaseDate: _requireDate(map, 'purchase_date'),
      status: _requireString(map, 'status'),
      subtotal: _requireDouble(map, 'subtotal'),
      discount: _requireDouble(map, 'discount'),
      taxAmount: _requireDouble(map, 'tax_amount'),
      total: _requireDouble(map, 'total'),
      notes: _optionalString(map, 'notes'),
      createdBy: _optionalString(map, 'created_by'),
      confirmedAt: _optionalTimestamp(map, 'confirmed_at'),
      cancelledAt: _optionalTimestamp(map, 'cancelled_at'),
      createdAt: _requireTimestamp(map, 'created_at'),
      updatedAt: _requireTimestamp(map, 'updated_at'),
    );
  }

  final String id;
  final String companyId;
  final String branchId;
  final String supplierId;
  final String? invoiceNumber;
  final DateTime purchaseDate;
  final String status;
  final double subtotal;
  final double discount;
  final double taxAmount;
  final double total;
  final String? notes;
  final String? createdBy;
  final DateTime? confirmedAt;
  final DateTime? cancelledAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Maps this data-layer model into the pure Domain entity.
  Purchase toEntity() => Purchase(
        id: id,
        companyId: companyId,
        branchId: branchId,
        supplierId: supplierId,
        invoiceNumber: invoiceNumber,
        purchaseDate: purchaseDate,
        status: status,
        subtotal: subtotal,
        discount: discount,
        taxAmount: taxAmount,
        total: total,
        notes: notes,
        createdBy: createdBy,
        confirmedAt: confirmedAt,
        cancelledAt: cancelledAt,
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
      'PurchaseModel: missing or invalid required column "$key".',
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
      'PurchaseModel: missing or invalid required column "$key".',
    );
  }

  /// Parses a mandatory PostgreSQL `date` column.
  ///
  /// PostgREST returns `date` as `"YYYY-MM-DD"`. [DateTime.tryParse]
  /// interprets this as midnight UTC, which is the expected semantics for
  /// a date-only value.
  static DateTime _requireDate(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is DateTime) {
      return DateTime.utc(value.year, value.month, value.day);
    }
    if (value is String && value.isNotEmpty) {
      final DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return DateTime.utc(parsed.year, parsed.month, parsed.day);
      }
    }
    throw FormatException(
      'PurchaseModel: missing or invalid date column "$key".',
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
      'PurchaseModel: missing or invalid timestamp column "$key".',
    );
  }

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
        supplierId,
        invoiceNumber,
        purchaseDate,
        status,
        subtotal,
        discount,
        taxAmount,
        total,
        notes,
        createdBy,
        confirmedAt,
        cancelledAt,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'PurchaseModel(id: $id, supplierId: $supplierId, status: $status, '
      'total: $total)';
}

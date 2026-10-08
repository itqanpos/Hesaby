// lib/features/purchases/data/models/supplier_payment_model.dart

import 'package:equatable/equatable.dart';

import '../../domain/entities/supplier_payment.dart';

/// Data-layer representation of a row in `public.supplier_payments`.
///
/// Maps the PostgreSQL snake_case columns into a pure [SupplierPayment]
/// entity via [toEntity]. This is the only place in the purchases feature
/// that is allowed to know the physical column names for supplier payments.
///
/// `numeric(15,4)` columns arrive from PostgREST as strings (to preserve
/// precision), so the helpers below accept `String`, `int` and `double`.
class SupplierPaymentModel extends Equatable {
  const SupplierPaymentModel({
    required this.id,
    required this.companyId,
    required this.supplierId,
    required this.amount,
    required this.paymentMethod,
    required this.paymentDate,
    required this.createdAt,
    required this.updatedAt,
    this.purchaseId,
    this.reference,
    this.notes,
    this.createdBy,
  });

  /// Builds a model from a row returned by Supabase / PostgreSQL.
  factory SupplierPaymentModel.fromMap(Map<String, dynamic> map) {
    return SupplierPaymentModel(
      id: _requireString(map, 'id'),
      companyId: _requireString(map, 'company_id'),
      supplierId: _requireString(map, 'supplier_id'),
      purchaseId: _optionalString(map, 'purchase_id'),
      amount: _requireDouble(map, 'amount'),
      paymentMethod:
          _optionalString(map, 'payment_method') ?? SupplierPaymentMethod.cash,
      paymentDate: _requireTimestamp(map, 'payment_date'),
      reference: _optionalString(map, 'reference'),
      notes: _optionalString(map, 'notes'),
      createdBy: _optionalString(map, 'created_by'),
      createdAt: _requireTimestamp(map, 'created_at'),
      updatedAt: _requireTimestamp(map, 'updated_at'),
    );
  }

  final String id;
  final String companyId;
  final String supplierId;
  final String? purchaseId;
  final double amount;
  final String paymentMethod;
  final DateTime paymentDate;
  final String? reference;
  final String? notes;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Maps this data-layer model into the pure Domain entity.
  SupplierPayment toEntity() => SupplierPayment(
        id: id,
        companyId: companyId,
        supplierId: supplierId,
        purchaseId: purchaseId,
        amount: amount,
        paymentMethod: paymentMethod,
        paymentDate: paymentDate,
        reference: reference,
        notes: notes,
        createdBy: createdBy,
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
      'SupplierPaymentModel: missing or invalid required column "$key".',
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

  static double _requireDouble(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) {
      final double? parsed = double.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
    throw FormatException(
      'SupplierPaymentModel: "$key" is not numeric.',
    );
  }

  static DateTime _requireTimestamp(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is DateTime) return value.toUtc();
    if (value is String && value.isNotEmpty) {
      final DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    throw FormatException(
      'SupplierPaymentModel: "$key" is not a valid timestamp.',
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        supplierId,
        purchaseId,
        amount,
        paymentMethod,
        paymentDate,
        reference,
        notes,
        createdBy,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'SupplierPaymentModel(id: $id, supplierId: $supplierId, '
      'amount: $amount)';
}

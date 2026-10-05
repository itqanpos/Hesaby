// lib/features/sales/data/models/customer_payment_model.dart

import '../../domain/entities/customer_payment.dart';

/// Data-layer representation of a `customer_payments` row.
///
/// PostgREST delivers `numeric` columns as `String`, and `timestamptz` as
/// ISO-8601 strings. Both are normalised here so the domain layer only
/// ever sees `double` and `DateTime`.
///
/// Parsing failures raise [FormatException] — the repository implementation
/// maps them to `CustomerException(invalidResponse)`.
class CustomerPaymentModel {
  const CustomerPaymentModel({
    required this.id,
    required this.companyId,
    required this.customerId,
    required this.amount,
    required this.method,
    required this.createdAt,
    this.reference,
    this.notes,
    this.createdBy,
  });

  final String id;
  final String companyId;
  final String customerId;
  final double amount;
  final String method;
  final String? reference;
  final String? notes;
  final String? createdBy;
  final DateTime createdAt;

  // ---------------------------------------------------------------------------
  // Mapping
  // ---------------------------------------------------------------------------

  factory CustomerPaymentModel.fromMap(Map<String, dynamic> map) {
    return CustomerPaymentModel(
      id: _requireString(map, 'id'),
      companyId: _requireString(map, 'company_id'),
      customerId: _requireString(map, 'customer_id'),
      amount: _requireDouble(map, 'amount'),
      method: _requireString(map, 'method'),
      reference: _optionalString(map, 'reference'),
      notes: _optionalString(map, 'notes'),
      createdBy: _optionalString(map, 'created_by'),
      createdAt: _requireDateTime(map, 'created_at'),
    );
  }

  CustomerPayment toEntity() => CustomerPayment(
        id: id,
        companyId: companyId,
        customerId: customerId,
        amount: amount,
        method: method,
        reference: reference,
        notes: notes,
        createdBy: createdBy,
        createdAt: createdAt,
      );

  // ---------------------------------------------------------------------------
  // Field parsers
  // ---------------------------------------------------------------------------

  static String _requireString(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is! String || value.isEmpty) {
      throw FormatException(
        'CustomerPaymentModel: "$key" is missing or not a non-empty string.',
        map,
      );
    }
    return value;
  }

  static String? _optionalString(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw FormatException(
        'CustomerPaymentModel: "$key" must be a string when present.',
        map,
      );
    }
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static double _requireDouble(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final double? parsed = double.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
    throw FormatException(
      'CustomerPaymentModel: "$key" is missing or not numeric.',
      map,
    );
  }

  static DateTime _requireDateTime(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is! String) {
      throw FormatException(
        'CustomerPaymentModel: "$key" is missing or not a string.',
        map,
      );
    }
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException(
        'CustomerPaymentModel: "$key" is not a valid ISO-8601 timestamp.',
        map,
      );
    }
    return parsed.toUtc();
  }
}

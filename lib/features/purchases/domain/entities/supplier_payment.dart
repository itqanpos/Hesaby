// lib/features/purchases/domain/entities/supplier_payment.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Canonical payment-method identifiers accepted by the database CHECK
/// constraint on `supplier_payments.payment_method`.
abstract final class SupplierPaymentMethod {
  static const String cash = 'cash';
  static const String card = 'card';
  static const String transfer = 'transfer';
  static const String cheque = 'cheque';
  static const String other = 'other';

  static const List<String> all = <String>[
    cash,
    card,
    transfer,
    cheque,
    other,
  ];

  /// Arabic display label for a stored method value.
  static String label(String method) {
    switch (method) {
      case cash:
        return 'نقدي';
      case card:
        return 'بطاقة';
      case transfer:
        return 'تحويل بنكي';
      case cheque:
        return 'شيك';
      case other:
        return 'أخرى';
      default:
        return method;
    }
  }
}

/// A single payment made to a supplier.
///
/// This is a pure Domain entity. It knows nothing about Supabase,
/// PostgreSQL, or Flutter widgets.
///
/// A payment may optionally be tied to a specific [purchaseId] (settling
/// that invoice). When [purchaseId] is `null`, the payment is an on-account
/// advance that reduces the supplier's running balance.
@immutable
class SupplierPayment extends Equatable {
  const SupplierPayment({
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

  final String id;
  final String companyId;
  final String supplierId;

  /// Optional purchase this payment settles. `null` for on-account payments.
  final String? purchaseId;

  /// Always strictly positive. Enforced by the database.
  final double amount;

  /// One of [SupplierPaymentMethod.all].
  final String paymentMethod;

  /// Business date of the payment.
  final DateTime paymentDate;

  /// Optional reference (cheque number, transfer reference, etc.).
  final String? reference;

  /// Optional free-form notes.
  final String? notes;

  /// `auth.users.id` of the user who recorded the payment.
  final String? createdBy;

  final DateTime createdAt;
  final DateTime updatedAt;

  // ---------------------------------------------------------------------------
  // Convenience getters (UI only)
  // ---------------------------------------------------------------------------

  bool get isLinkedToPurchase => purchaseId != null && purchaseId!.isNotEmpty;

  bool get hasReference =>
      reference != null && reference!.trim().isNotEmpty;

  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;

  /// Arabic label for [paymentMethod].
  String get methodLabel => SupplierPaymentMethod.label(paymentMethod);

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
      'SupplierPayment(id: $id, supplierId: $supplierId, '
      'purchaseId: $purchaseId, amount: $amount, '
      'method: $paymentMethod)';
}

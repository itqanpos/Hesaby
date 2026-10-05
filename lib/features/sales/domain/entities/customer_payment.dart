// lib/features/sales/domain/entities/customer_payment.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

// ============================================================================
// Payment method constants
// ============================================================================

/// Canonical payment-method identifiers used by
/// `customer_payments.method`.
///
/// The three values match the `customer_payments_method_valid` CHECK
/// constraint declared in migration `202610070001_pos_and_prices.sql`.
abstract final class PaymentMethod {
  static const String cash = 'cash';
  static const String card = 'card';
  static const String transfer = 'transfer';

  static const List<String> all = <String>[cash, card, transfer];
}

// ============================================================================
// Customer payment
// ============================================================================

/// Represents a standalone payment received from a customer.
///
/// A payment is **not** attached to a specific sale: the database trigger
/// `apply_customer_payment` simply reduces `customers.balance` by
/// [amount] after each insert. Reconciliation against individual invoices
/// is a future concern.
///
/// Money values are exposed as `double`, matching `numeric(15,4)` in the
/// database; the same rationale documented on `Product` and `Sale` applies.
@immutable
class CustomerPayment extends Equatable {
  const CustomerPayment({
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

  /// Amount actually received. Always > 0 (enforced by the DB).
  final double amount;

  /// One of [PaymentMethod.all]. Stored as text in the database.
  final String method;

  /// Optional external reference — receipt number, transaction id, etc.
  /// Length is capped at 100 characters in the database.
  final String? reference;

  /// Optional free-form notes. Length is capped at 1000 characters in the
  /// database.
  final String? notes;

  /// User id of the cashier who recorded the payment. `null` when the row
  /// was inserted by a migration or service role.
  final String? createdBy;

  final DateTime createdAt;

  // ---------------------------------------------------------------------------
  // Convenience getters (UI only — no business rules)
  // ---------------------------------------------------------------------------

  bool get hasReference =>
      reference != null && reference!.trim().isNotEmpty;

  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;

  bool get hasCreatedBy => createdBy != null;

  bool get isCash => method == PaymentMethod.cash;
  bool get isCard => method == PaymentMethod.card;
  bool get isTransfer => method == PaymentMethod.transfer;

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        customerId,
        amount,
        method,
        reference,
        notes,
        createdBy,
        createdAt,
      ];

  @override
  String toString() =>
      'CustomerPayment(id: $id, customerId: $customerId, '
      'amount: $amount, method: $method)';
}

// ============================================================================
// Customer payment draft (input value object)
// ============================================================================

/// Input value object used when recording a new customer payment.
///
/// The `company_id` is intentionally **not** part of the draft: it is
/// resolved by the notifier from the active company context, matching the
/// convention used by `SaleItemDraft` and the existing repository
/// signatures.
///
/// Amount validation (positive, not exceeding the current balance) is
/// performed by the caller before a draft is submitted — this class is a
/// plain data carrier.
@immutable
class CustomerPaymentDraft extends Equatable {
  const CustomerPaymentDraft({
    required this.customerId,
    required this.amount,
    required this.method,
    this.reference,
    this.notes,
  });

  final String customerId;
  final double amount;
  final String method;
  final String? reference;
  final String? notes;

  @override
  List<Object?> get props =>
      <Object?>[customerId, amount, method, reference, notes];

  @override
  String toString() =>
      'CustomerPaymentDraft(customerId: $customerId, amount: $amount, '
      'method: $method)';
}

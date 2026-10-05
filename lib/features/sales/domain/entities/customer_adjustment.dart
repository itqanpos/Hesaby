// lib/features/sales/domain/entities/customer_adjustment.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

// ============================================================================
// Adjustment reason constants
// ============================================================================

/// Canonical reason identifiers used by
/// `customer_balance_adjustments.reason`.
///
/// The five values match the `customer_balance_adjustments_reason_valid`
/// CHECK constraint declared in migration
/// `202610080001_customer_balance_adjustments.sql`.
abstract final class AdjustmentReason {
  /// Initial outstanding amount carried over when the customer is first
  /// registered (e.g. migrating from a paper ledger).
  static const String openingBalance = 'opening_balance';

  /// Fixing a data-entry mistake on a previous entry.
  static const String correction = 'correction';

  /// A goodwill discount granted to the customer.
  static const String discount = 'discount';

  /// A late-payment fee or other penalty added to the balance.
  static const String penalty = 'penalty';

  /// Anything else — the free-form [CustomerAdjustment.notes] carries the
  /// explanation.
  static const String other = 'other';

  static const List<String> all = <String>[
    openingBalance,
    correction,
    discount,
    penalty,
    other,
  ];
}

// ============================================================================
// Customer adjustment
// ============================================================================

/// Represents a manual adjustment to a customer's balance.
///
/// Unlike [CustomerPayment] (which is always positive and reduces the
/// balance), an adjustment may be **positive** (increases what the
/// customer owes) or **negative** (decreases it). The database trigger
/// `apply_customer_balance_adjustment` applies the delta and rejects any
/// value that would make the balance negative.
///
/// Money values are exposed as `double`, matching `numeric(15,4)` in the
/// database; the same rationale documented on `Product` and `Sale` applies.
@immutable
class CustomerAdjustment extends Equatable {
  const CustomerAdjustment({
    required this.id,
    required this.companyId,
    required this.customerId,
    required this.amount,
    required this.reason,
    required this.createdAt,
    this.notes,
    this.createdBy,
  });

  final String id;
  final String companyId;
  final String customerId;

  /// Signed delta. Positive means "customer owes more"; negative means
  /// "customer owes less". Never zero (enforced by the database).
  final double amount;

  /// One of [AdjustmentReason.all]. Stored as text in the database.
  final String reason;

  /// Optional free-form notes. Length is capped at 1000 characters in the
  /// database.
  final String? notes;

  /// User id of the manager who recorded the adjustment. `null` when the
  /// row was inserted by a migration or service role.
  final String? createdBy;

  final DateTime createdAt;

  // ---------------------------------------------------------------------------
  // Convenience getters (UI only — no business rules)
  // ---------------------------------------------------------------------------

  bool get isIncrease => amount > 0;
  bool get isDecrease => amount < 0;

  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;
  bool get hasCreatedBy => createdBy != null;

  bool get isOpeningBalance => reason == AdjustmentReason.openingBalance;
  bool get isCorrection => reason == AdjustmentReason.correction;
  bool get isDiscount => reason == AdjustmentReason.discount;
  bool get isPenalty => reason == AdjustmentReason.penalty;
  bool get isOther => reason == AdjustmentReason.other;

  /// Absolute amount — useful for the "دائن/مدين" columns without sign
  /// juggling at call sites.
  double get absoluteAmount => amount < 0 ? -amount : amount;

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        customerId,
        amount,
        reason,
        notes,
        createdBy,
        createdAt,
      ];

  @override
  String toString() =>
      'CustomerAdjustment(id: $id, customerId: $customerId, '
      'amount: $amount, reason: $reason)';
}

// ============================================================================
// Customer adjustment draft (input value object)
// ============================================================================

/// Input value object used when creating a new customer adjustment.
///
/// The `company_id` is intentionally **not** part of the draft: it is
/// resolved by the notifier from the active company context, matching the
/// convention used by `SaleItemDraft` and `CustomerPaymentDraft`.
///
/// [amount] must be non-zero; [reason] must be one of [AdjustmentReason.all].
/// Both are enforced by the database; callers are expected to validate
/// before submitting.
@immutable
class CustomerAdjustmentDraft extends Equatable {
  const CustomerAdjustmentDraft({
    required this.customerId,
    required this.amount,
    required this.reason,
    this.notes,
  });

  final String customerId;
  final double amount;
  final String reason;
  final String? notes;

  @override
  List<Object?> get props => <Object?>[customerId, amount, reason, notes];

  @override
  String toString() =>
      'CustomerAdjustmentDraft(customerId: $customerId, amount: $amount, '
      'reason: $reason)';
}

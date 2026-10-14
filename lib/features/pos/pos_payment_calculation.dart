// lib/features/pos/pos_payment_calculation.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'pos_cart.dart';

// ============================================================================
// Payment methods
// ============================================================================

/// Payment methods offered at the POS.
///
/// These string values must stay in sync with the SQL whitelist in
/// Migration 31 (`create_offline_sale` and `sale_payments`):
/// `('cash','card','wallet','credit','mixed')`.
///
/// `mixed` is accepted by the database but not yet exposed in the UI: it
/// would require splitting the amount across multiple methods, which is a
/// separate feature.
abstract final class PosPaymentMethod {
  static const String cash = 'cash';
  static const String card = 'card';
  static const String wallet = 'wallet';
  static const String credit = 'credit';
}

// ============================================================================
// Validation errors
// ============================================================================

/// Reasons a POS payment input can be rejected locally — before any
/// network round-trip.
enum PosPaymentError {
  emptyCart,
  creditRequiresCustomer,
  cardMustCoverTotal,
  cardNoChange,
  partialRequiresCustomer,
}

extension PosPaymentErrorArabic on PosPaymentError {
  /// Arabic message shown to the cashier.
  String get arabicMessage => switch (this) {
        PosPaymentError.emptyCart =>
          'السلة فارغة. أضف منتجاً قبل الدفع.',
        PosPaymentError.creditRequiresCustomer =>
          'البيع الآجل يتطلب اختيار عميل مسجل.',
        PosPaymentError.cardMustCoverTotal =>
          'الدفع بالبطاقة أو المحفظة يجب أن يغطي كامل قيمة الفاتورة.',
        PosPaymentError.cardNoChange =>
          'الدفع بالبطاقة أو المحفظة لا يُعيد باقياً.',
        PosPaymentError.partialRequiresCustomer =>
          'الدفع الجزئي يتطلب اختيار عميل مسجل.',
      };
}

// ============================================================================
// Calculation
// ============================================================================

/// Pure, testable computation of a POS payment.
///
/// Given the cart total, the customer's existing balance, whether a
/// customer is attached, the chosen method and the amount entered by the
/// cashier, [PosPaymentCalculation] produces every derived value the UI
/// needs:
///
/// * how much to apply to the invoice ([appliedToSale]);
/// * how much change to return ([changeToCustomer]);
/// * how much to add to the customer balance ([addedToBalance]);
/// * the resulting balance ([resultingBalance]);
/// * whether the input is valid ([error], [isValid]).
///
/// It has no dependency on Flutter, Riverpod, or Supabase, so it can be
/// unit-tested in isolation.
@immutable
class PosPaymentCalculation extends Equatable {
  const PosPaymentCalculation({
    required this.method,
    required this.inputAmount,
    required this.cartTotal,
    required this.customerBalance,
    required this.hasCustomer,
    required this.cartIsEmpty,
  });

  /// Builds a calculation from a live cart.
  factory PosPaymentCalculation.fromCart({
    required PosCartState cart,
    required String method,
    required double inputAmount,
  }) {
    return PosPaymentCalculation(
      method: method,
      inputAmount: inputAmount,
      cartTotal: cart.total,
      customerBalance: cart.customerBalance,
      hasCustomer: cart.hasCustomer,
      cartIsEmpty: cart.isEmpty,
    );
  }

  final String method;
  final double inputAmount;
  final double cartTotal;
  final double customerBalance;
  final bool hasCustomer;
  final bool cartIsEmpty;

  // ---------------------------------------------------------------------------
  // Derived values
  // ---------------------------------------------------------------------------

  /// Amount applied to the current invoice.
  ///
  /// Capped at [cartTotal] because of the SQL CHECK
  /// `paid_amount <= total`. Credit sales apply nothing.
  double get appliedToSale {
    if (method == PosPaymentMethod.credit) return 0;
    if (inputAmount <= 0) return 0;
    return inputAmount >= cartTotal ? cartTotal : inputAmount;
  }

  /// Cash refunded to the customer when the input exceeds the invoice
  /// total. Only meaningful for cash payments.
  double get changeToCustomer {
    if (method != PosPaymentMethod.cash) return 0;
    final double excess = inputAmount - cartTotal;
    return excess > 0 ? excess : 0;
  }

  /// Amount added to the customer balance after this sale.
  double get addedToBalance => cartTotal - appliedToSale;

  /// Resulting customer balance after this sale.
  double get resultingBalance => customerBalance + addedToBalance;

  /// Whether the sale is fully settled with no change and no new balance.
  bool get isFullyPaid => changeToCustomer == 0 && addedToBalance == 0;

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  /// The first validation error, or `null` when the input is acceptable.
  PosPaymentError? get error {
    if (cartIsEmpty) return PosPaymentError.emptyCart;

    if (method == PosPaymentMethod.credit) {
      if (!hasCustomer) return PosPaymentError.creditRequiresCustomer;
      return null;
    }

    if (method == PosPaymentMethod.card ||
        method == PosPaymentMethod.wallet) {
      if (inputAmount < cartTotal) return PosPaymentError.cardMustCoverTotal;
      if (inputAmount > cartTotal) return PosPaymentError.cardNoChange;
      return null;
    }

    // Cash: partial payment requires a registered customer.
    if (addedToBalance > 0 && !hasCustomer) {
      return PosPaymentError.partialRequiresCustomer;
    }

    return null;
  }

  bool get isValid => error == null;

  /// Arabic message for the current [error], or `null` when valid.
  String? get errorMessage => error?.arabicMessage;

  @override
  List<Object?> get props => <Object?>[
        method,
        inputAmount,
        cartTotal,
        customerBalance,
        hasCustomer,
        cartIsEmpty,
      ];
}

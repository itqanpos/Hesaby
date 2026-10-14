// test/pos_payment_calculation_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:hesabi/features/pos/pos_cart.dart';
import 'package:hesabi/features/pos/pos_payment_calculation.dart';

/// Unit tests for [PosPaymentCalculation].
///
/// These tests exercise the *pure* payment logic without any Flutter or
/// Riverpod involvement. They are the safety net for the most critical
/// financial computation in the POS: how much money actually hits the
/// invoice, how much change goes back to the customer, and how much lands
/// on the customer's balance.
///
/// Every test uses the direct constructor unless it is explicitly marked
/// as testing the [PosPaymentCalculation.fromCart] factory — that way the
/// logic is verified in isolation from `PosCartState`.
void main() {
  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Builds a calculation directly — skips `PosCartState`.
  PosPaymentCalculation calc({
    required String method,
    required double inputAmount,
    double cartTotal = 100,
    double customerBalance = 0,
    bool hasCustomer = false,
    bool cartIsEmpty = false,
  }) {
    return PosPaymentCalculation(
      method: method,
      inputAmount: inputAmount,
      cartTotal: cartTotal,
      customerBalance: customerBalance,
      hasCustomer: hasCustomer,
      cartIsEmpty: cartIsEmpty,
    );
  }

  /// Builds a cart with exactly one line whose total equals [subtotal].
  /// Pass [subtotal] = 0 to produce an empty cart.
  PosCartState cartWith({
    double subtotal = 100,
    String? customerId,
    double customerBalance = 0,
    double discount = 0,
    double taxAmount = 0,
  }) {
    final List<PosCartLine> lines = subtotal > 0
        ? <PosCartLine>[
            PosCartLine(
              productId: 'p1',
              productName: 'Product 1',
              unitId: 'u1',
              unitName: 'قطعة',
              conversionFactor: 1,
              quantity: 1,
              unitPrice: subtotal,
            ),
          ]
        : const <PosCartLine>[];
    return PosCartState(
      lines: lines,
      customerId: customerId,
      customerBalance: customerBalance,
      discount: discount,
      taxAmount: taxAmount,
    );
  }

  // ===========================================================================
  // Empty cart
  // ===========================================================================

  group('empty cart', () {
    test('reports emptyCart error regardless of method', () {
      for (final String method in <String>[
        PosPaymentMethod.cash,
        PosPaymentMethod.card,
        PosPaymentMethod.wallet,
        PosPaymentMethod.credit,
      ]) {
        final PosPaymentCalculation c = calc(
          method: method,
          inputAmount: 100,
          cartTotal: 100,
          cartIsEmpty: true,
        );
        expect(
          c.error,
          PosPaymentError.emptyCart,
          reason: 'method=$method',
        );
        expect(c.isValid, isFalse);
      }
    });

    test('errorMessage is not null when there is an error', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.cash,
        inputAmount: 0,
        cartIsEmpty: true,
      );
      expect(c.errorMessage, isNotNull);
    });

    test('no error message when there is no error', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.cash,
        inputAmount: 100,
        cartTotal: 100,
      );
      expect(c.errorMessage, isNull);
    });
  });

  // ===========================================================================
  // Cash
  // ===========================================================================

  group('cash — exact payment', () {
    test('applies the full total, no change, no balance', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.cash,
        inputAmount: 100,
        cartTotal: 100,
      );
      expect(c.appliedToSale, closeTo(100, 0.001));
      expect(c.changeToCustomer, closeTo(0, 0.001));
      expect(c.addedToBalance, closeTo(0, 0.001));
      expect(c.resultingBalance, closeTo(0, 0.001));
      expect(c.isFullyPaid, isTrue);
      expect(c.isValid, isTrue);
    });
  });

  group('cash — overpayment', () {
    test('refunds the excess as change', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.cash,
        inputAmount: 150,
        cartTotal: 100,
      );
      expect(c.appliedToSale, closeTo(100, 0.001));
      expect(c.changeToCustomer, closeTo(50, 0.001));
      expect(c.addedToBalance, closeTo(0, 0.001));
      expect(c.isFullyPaid, isFalse);
      expect(c.isValid, isTrue);
    });

    test('with previous balance, only the invoice is settled', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.cash,
        inputAmount: 150,
        cartTotal: 100,
        customerBalance: 200,
        hasCustomer: true,
      );
      expect(c.changeToCustomer, closeTo(50, 0.001));
      expect(c.addedToBalance, closeTo(0, 0.001));
      expect(c.resultingBalance, closeTo(200, 0.001));
      expect(c.isValid, isTrue);
    });
  });

  group('cash — partial payment', () {
    test('with customer: remainder goes to balance', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.cash,
        inputAmount: 40,
        cartTotal: 100,
        customerBalance: 200,
        hasCustomer: true,
      );
      expect(c.appliedToSale, closeTo(40, 0.001));
      expect(c.changeToCustomer, closeTo(0, 0.001));
      expect(c.addedToBalance, closeTo(60, 0.001));
      expect(c.resultingBalance, closeTo(260, 0.001));
      expect(c.isValid, isTrue);
    });

    test('without customer: rejected', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.cash,
        inputAmount: 40,
        cartTotal: 100,
        hasCustomer: false,
      );
      expect(c.error, PosPaymentError.partialRequiresCustomer);
      expect(c.isValid, isFalse);
    });

    test('zero payment without customer: rejected', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.cash,
        inputAmount: 0,
        cartTotal: 100,
        hasCustomer: false,
      );
      expect(c.error, PosPaymentError.partialRequiresCustomer);
    });

    test('zero payment with customer: valid, full total to balance', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.cash,
        inputAmount: 0,
        cartTotal: 100,
        customerBalance: 50,
        hasCustomer: true,
      );
      expect(c.appliedToSale, closeTo(0, 0.001));
      expect(c.addedToBalance, closeTo(100, 0.001));
      expect(c.resultingBalance, closeTo(150, 0.001));
      expect(c.isValid, isTrue);
    });
  });

  // ===========================================================================
  // Card
  // ===========================================================================

  group('card', () {
    test('exact match: valid', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.card,
        inputAmount: 100,
        cartTotal: 100,
      );
      expect(c.appliedToSale, closeTo(100, 0.001));
      expect(c.changeToCustomer, closeTo(0, 0.001));
      expect(c.addedToBalance, closeTo(0, 0.001));
      expect(c.isValid, isTrue);
    });

    test('less than total: rejected', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.card,
        inputAmount: 80,
        cartTotal: 100,
      );
      expect(c.error, PosPaymentError.cardMustCoverTotal);
      expect(c.isValid, isFalse);
    });

    test('more than total: rejected (no change allowed)', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.card,
        inputAmount: 120,
        cartTotal: 100,
      );
      expect(c.error, PosPaymentError.cardNoChange);
      expect(c.isValid, isFalse);
    });

    test('never produces change, even on overpayment', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.card,
        inputAmount: 500,
        cartTotal: 100,
      );
      expect(c.changeToCustomer, 0);
    });
  });

  // ===========================================================================
  // Wallet — must behave exactly like card
  // ===========================================================================

  group('wallet', () {
    test('exact match: valid', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.wallet,
        inputAmount: 100,
        cartTotal: 100,
      );
      expect(c.isValid, isTrue);
    });

    test('less than total: rejected with card error', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.wallet,
        inputAmount: 50,
        cartTotal: 100,
      );
      expect(c.error, PosPaymentError.cardMustCoverTotal);
    });

    test('more than total: rejected with card error', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.wallet,
        inputAmount: 150,
        cartTotal: 100,
      );
      expect(c.error, PosPaymentError.cardNoChange);
    });

    test('never produces change', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.wallet,
        inputAmount: 200,
        cartTotal: 100,
      );
      expect(c.changeToCustomer, 0);
    });
  });

  // ===========================================================================
  // Credit (آجل)
  // ===========================================================================

  group('credit', () {
    test('with customer: nothing applied, full total to balance', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.credit,
        inputAmount: 999,
        cartTotal: 100,
        customerBalance: 50,
        hasCustomer: true,
      );
      expect(c.appliedToSale, 0);
      expect(c.addedToBalance, closeTo(100, 0.001));
      expect(c.resultingBalance, closeTo(150, 0.001));
      expect(c.isValid, isTrue);
    });

    test('without customer: rejected', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.credit,
        inputAmount: 0,
        cartTotal: 100,
        hasCustomer: false,
      );
      expect(c.error, PosPaymentError.creditRequiresCustomer);
      expect(c.isValid, isFalse);
    });

    test('ignores input amount entirely', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.credit,
        inputAmount: 9999,
        cartTotal: 100,
        hasCustomer: true,
      );
      expect(c.appliedToSale, 0);
      expect(c.changeToCustomer, 0);
    });
  });

  // ===========================================================================
  // Factory: PosPaymentCalculation.fromCart
  // ===========================================================================

  group('PosPaymentCalculation.fromCart', () {
    test('reads total, balance, hasCustomer and isEmpty from the cart', () {
      final PosCartState cart = cartWith(
        subtotal: 100,
        customerId: 'c-1',
        customerBalance: 25,
      );
      final PosPaymentCalculation c = PosPaymentCalculation.fromCart(
        cart: cart,
        method: PosPaymentMethod.cash,
        inputAmount: 100,
      );
      expect(c.cartTotal, closeTo(100, 0.001));
      expect(c.customerBalance, closeTo(25, 0.001));
      expect(c.hasCustomer, isTrue);
      expect(c.cartIsEmpty, isFalse);
    });

    test('detects an empty cart', () {
      final PosCartState cart = cartWith(subtotal: 0);
      final PosPaymentCalculation c = PosPaymentCalculation.fromCart(
        cart: cart,
        method: PosPaymentMethod.cash,
        inputAmount: 0,
      );
      expect(c.cartIsEmpty, isTrue);
      expect(c.error, PosPaymentError.emptyCart);
    });

    test('applies discount and tax to the total', () {
      final PosCartState cart = cartWith(
        subtotal: 100,
        discount: 20,
        taxAmount: 10,
      );
      // total = 100 - 20 + 10 = 90
      final PosPaymentCalculation c = PosPaymentCalculation.fromCart(
        cart: cart,
        method: PosPaymentMethod.cash,
        inputAmount: 90,
      );
      expect(c.cartTotal, closeTo(90, 0.001));
      expect(c.isValid, isTrue);
    });

    test('a cash sale with no customer is valid when fully paid', () {
      final PosCartState cart = cartWith(subtotal: 100);
      final PosPaymentCalculation c = PosPaymentCalculation.fromCart(
        cart: cart,
        method: PosPaymentMethod.cash,
        inputAmount: 100,
      );
      expect(c.hasCustomer, isFalse);
      expect(c.isValid, isTrue);
      expect(c.isFullyPaid, isTrue);
    });
  });

  // ===========================================================================
  // Edge cases
  // ===========================================================================

  group('edge cases', () {
    test('fractional amounts keep their precision', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.cash,
        inputAmount: 33.33,
        cartTotal: 100,
        hasCustomer: true,
      );
      expect(c.appliedToSale, closeTo(33.33, 0.001));
      expect(c.addedToBalance, closeTo(66.67, 0.001));
    });

    test('negative input is treated as zero', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.cash,
        inputAmount: -50,
        cartTotal: 100,
        hasCustomer: true,
      );
      expect(c.appliedToSale, 0);
      expect(c.addedToBalance, closeTo(100, 0.001));
    });

    test('cash overpay on customer with previous balance: no new debt', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.cash,
        inputAmount: 150,
        cartTotal: 100,
        customerBalance: 200,
        hasCustomer: true,
      );
      expect(c.changeToCustomer, closeTo(50, 0.001));
      expect(c.addedToBalance, 0);
      expect(c.resultingBalance, closeTo(200, 0.001));
    });

    test('isFullyPaid is true when change == 0 && addedToBalance == 0', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.cash,
        inputAmount: 100,
        cartTotal: 100,
      );
      expect(c.isFullyPaid, isTrue);
    });

    test('isFullyPaid is false when the customer owes more', () {
      final PosPaymentCalculation c = calc(
        method: PosPaymentMethod.credit,
        inputAmount: 0,
        cartTotal: 100,
        hasCustomer: true,
      );
      expect(c.isFullyPaid, isFalse);
    });

    test('appliedToSale is always capped at cartTotal', () {
      for (final double input in <double>[100, 150, 500, 9999]) {
        final PosPaymentCalculation c = calc(
          method: PosPaymentMethod.cash,
          inputAmount: input,
          cartTotal: 100,
        );
        expect(
          c.appliedToSale,
          lessThanOrEqualTo(c.cartTotal),
          reason: 'input=$input',
        );
      }
    });
  });
}

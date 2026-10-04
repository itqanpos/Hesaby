// test/features/pos/pos_cart_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/pos/domain/entities/pos_cart.dart';
import 'package:hesabi/features/pos/domain/entities/pos_cart_line.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Fixtures
  // ---------------------------------------------------------------------------

  PosCartLine line({
    required String productId,
    String unitId = 'u1',
    double quantity = 1,
    double unitPrice = 10,
    String productName = 'منتج',
    String unitName = 'قطعة',
  }) =>
      PosCartLine(
        productId: productId,
        productName: productName,
        unitId: unitId,
        unitName: unitName,
        conversionFactor: 1,
        quantity: quantity,
        unitPrice: unitPrice,
      );

  // ---------------------------------------------------------------------------
  // Emptiness
  // ---------------------------------------------------------------------------

  group('PosCart emptiness', () {
    test('empty cart is empty and has no lines', () {
      const PosCart cart = PosCart();
      expect(cart.isEmpty, isTrue);
      expect(cart.isNotEmpty, isFalse);
      expect(cart.lineCount, 0);
      expect(cart.subtotal, 0);
      expect(cart.total, 0);
    });

    test('cart with one line is not empty', () {
      final PosCart cart = PosCart(
        lines: <PosCartLine>[line(productId: 'p1')],
      );
      expect(cart.isEmpty, isFalse);
      expect(cart.isNotEmpty, isTrue);
      expect(cart.lineCount, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // Totals
  // ---------------------------------------------------------------------------

  group('PosCart totals', () {
    test('subtotal is the sum of line totals', () {
      final PosCart cart = PosCart(
        lines: <PosCartLine>[
          line(productId: 'p1', quantity: 2, unitPrice: 10), // 20
          line(productId: 'p2', quantity: 3, unitPrice: 5), // 15
        ],
      );
      expect(cart.subtotal, 35);
    });

    test('total = subtotal - discount + tax', () {
      final PosCart cart = PosCart(
        lines: <PosCartLine>[
          line(productId: 'p1', quantity: 2, unitPrice: 10), // 20
        ],
        discount: 5,
        taxAmount: 3,
      );
      expect(cart.subtotal, 20);
      expect(cart.total, 18); // 20 - 5 + 3
    });

    test('totalQuantity sums quantities across units', () {
      final PosCart cart = PosCart(
        lines: <PosCartLine>[
          line(productId: 'p1', quantity: 2),
          line(productId: 'p2', quantity: 3.5),
        ],
      );
      expect(cart.totalQuantity, 5.5);
    });

    test('total is zero when discount equals subtotal and no tax', () {
      final PosCart cart = PosCart(
        lines: <PosCartLine>[
          line(productId: 'p1', quantity: 1, unitPrice: 50),
        ],
        discount: 50,
      );
      expect(cart.total, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Customer
  // ---------------------------------------------------------------------------

  group('PosCart customer', () {
    test('a fresh cart has no customer', () {
      const PosCart cart = PosCart();
      expect(cart.hasCustomer, isFalse);
      expect(cart.hasCustomerBalance, isFalse);
      expect(cart.settlementTotal, 0);
    });

    test('hasCustomer is true when customerId is set', () {
      const PosCart cart = PosCart(
        customerId: 'c1',
        customerName: 'أحمد',
      );
      expect(cart.hasCustomer, isTrue);
      expect(cart.hasCustomerBalance, isFalse);
    });

    test('hasCustomerBalance is true only when balance > 0', () {
      const PosCart withZero = PosCart(
        customerId: 'c1',
        customerName: 'أحمد',
        customerBalance: 0,
      );
      const PosCart withBalance = PosCart(
        customerId: 'c1',
        customerName: 'أحمد',
        customerBalance: 150,
      );
      expect(withZero.hasCustomerBalance, isFalse);
      expect(withBalance.hasCustomerBalance, isTrue);
    });

    test('settlementTotal = customerBalance + total', () {
      final PosCart cart = PosCart(
        lines: <PosCartLine>[
          line(productId: 'p1', quantity: 2, unitPrice: 25), // 50
        ],
        customerId: 'c1',
        customerName: 'أحمد',
        customerBalance: 100,
      );
      expect(cart.total, 50);
      expect(cart.settlementTotal, 150);
    });
  });

  // ---------------------------------------------------------------------------
  // findLine
  // ---------------------------------------------------------------------------

  group('PosCart.findLine', () {
    test('returns null when the cart is empty', () {
      const PosCart cart = PosCart();
      expect(
        cart.findLine(productId: 'p1', unitId: 'u1'),
        isNull,
      );
    });

    test('returns the matching line', () {
      final PosCartLine target = line(
        productId: 'p2',
        unitId: 'u2',
        quantity: 5,
      );
      final PosCart cart = PosCart(
        lines: <PosCartLine>[
          line(productId: 'p1'),
          target,
        ],
      );

      final PosCartLine? found =
          cart.findLine(productId: 'p2', unitId: 'u2');
      expect(found, isNotNull);
      expect(found!.quantity, 5);
    });

    test('returns null when the unit does not match', () {
      final PosCart cart = PosCart(
        lines: <PosCartLine>[
          line(productId: 'p1', unitId: 'u1'),
        ],
      );
      expect(
        cart.findLine(productId: 'p1', unitId: 'u9'),
        isNull,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  group('PosCart.copyWith', () {
    final PosCart base = PosCart(
      lines: <PosCartLine>[line(productId: 'p1')],
      customerId: 'c1',
      customerName: 'أحمد',
      customerBalance: 100,
      discount: 5,
      taxAmount: 2,
    );

    test('replaces lines only', () {
      final PosCart next = base.copyWith(
        lines: <PosCartLine>[line(productId: 'p2')],
      );
      expect(next.lines.length, 1);
      expect(next.lines.first.productId, 'p2');
      expect(next.customerId, base.customerId);
      expect(next.discount, base.discount);
    });

    test('replaces discount only', () {
      final PosCart next = base.copyWith(discount: 10);
      expect(next.discount, 10);
      expect(next.taxAmount, base.taxAmount);
      expect(next.customerId, base.customerId);
    });

    test('clearCustomer resets the customer fields', () {
      final PosCart next = base.copyWith(clearCustomer: true);
      expect(next.customerId, isNull);
      expect(next.customerName, isNull);
      expect(next.customerBalance, 0);
      expect(next.discount, base.discount);
    });

    test('setting a new customer replaces the old one', () {
      final PosCart next = base.copyWith(
        customerId: 'c2',
        customerName: 'سارة',
        customerBalance: 250,
      );
      expect(next.customerId, 'c2');
      expect(next.customerName, 'سارة');
      expect(next.customerBalance, 250);
    });
  });

  // ---------------------------------------------------------------------------
  // Equality
  // ---------------------------------------------------------------------------

  group('PosCart equality', () {
    final PosCart a = PosCart(
      lines: <PosCartLine>[line(productId: 'p1')],
      discount: 5,
    );
    final PosCart b = PosCart(
      lines: <PosCartLine>[line(productId: 'p1')],
      discount: 5,
    );

    test('two carts with identical content are equal', () {
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('a discount difference is significant', () {
      final PosCart c = b.copyWith(discount: 10);
      expect(a, isNot(equals(c)));
    });

    test('a line count difference is significant', () {
      final PosCart c = PosCart(
        lines: <PosCartLine>[
          line(productId: 'p1'),
          line(productId: 'p2'),
        ],
        discount: 5,
      );
      expect(a, isNot(equals(c)));
    });
  });
}

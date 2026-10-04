// test/features/pos/pos_cart_notifier_test.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/pos/domain/entities/pos_cart.dart';
import 'package:hesabi/features/pos/domain/entities/pos_cart_line.dart';
import 'package:hesabi/features/pos/presentation/state/pos_cart_notifier.dart';
import 'package:hesabi/features/pos/presentation/state/pos_providers.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  PosCartNotifier notifier() => container.read(posCartProvider.notifier);
  PosCart cart() => container.read(posCartProvider);

  // ---------------------------------------------------------------------------
  // addLine
  // ---------------------------------------------------------------------------

  group('addLine', () {
    test('adds a new line with the given fields', () {
      final bool added = notifier().addLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u1',
        unitName: 'قطعة',
        conversionFactor: 1,
        quantity: 2,
        unitPrice: 12,
      );

      expect(added, isTrue);
      expect(cart().lines.length, 1);
      final PosCartLine line = cart().lines.first;
      expect(line.productId, 'p1');
      expect(line.quantity, 2);
      expect(line.unitPrice, 12);
    });

    test('rejects quantity <= 0', () {
      final bool added = notifier().addLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u1',
        unitName: 'قطعة',
        conversionFactor: 1,
        quantity: 0,
        unitPrice: 12,
      );
      expect(added, isFalse);
      expect(cart().isEmpty, isTrue);
    });

    test('merges quantities for the same (product, unit)', () {
      notifier().addLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u1',
        unitName: 'قطعة',
        conversionFactor: 1,
        quantity: 2,
        unitPrice: 12,
      );
      notifier().addLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u1',
        unitName: 'قطعة',
        conversionFactor: 1,
        quantity: 3,
        unitPrice: 12,
      );

      expect(cart().lines.length, 1);
      expect(cart().lines.first.quantity, 5);
    });

    test('creates a second line for a different unit', () {
      notifier().addLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u1',
        unitName: 'قطعة',
        conversionFactor: 1,
        quantity: 2,
        unitPrice: 12,
      );
      notifier().addLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u2',
        unitName: 'كرتونة',
        conversionFactor: 24,
        quantity: 1,
        unitPrice: 240,
      );

      expect(cart().lines.length, 2);
    });

    test('rejects when the resulting quantity exceeds availableStock', () {
      final bool added = notifier().addLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u1',
        unitName: 'قطعة',
        conversionFactor: 1,
        quantity: 5,
        unitPrice: 12,
        availableStock: 3,
      );
      expect(added, isFalse);
      expect(cart().isEmpty, isTrue);
    });

    test('rejects the merge when the summed quantity exceeds availableStock',
        () {
      notifier().addLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u1',
        unitName: 'قطعة',
        conversionFactor: 1,
        quantity: 2,
        unitPrice: 12,
        availableStock: 3,
      );
      final bool added = notifier().addLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u1',
        unitName: 'قطعة',
        conversionFactor: 1,
        quantity: 2,
        unitPrice: 12,
        availableStock: 3,
      );
      expect(added, isFalse);
      expect(cart().lines.first.quantity, 2);
    });
  });

  // ---------------------------------------------------------------------------
  // increment / decrement
  // ---------------------------------------------------------------------------

  group('incrementLine / decrementLine', () {
    void seed({double? stock}) {
      notifier().addLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u1',
        unitName: 'قطعة',
        conversionFactor: 1,
        quantity: 2,
        unitPrice: 12,
        availableStock: stock,
      );
    }

    test('incrementLine increases by one', () {
      seed();
      final bool applied = notifier().incrementLine(
        productId: 'p1',
        unitId: 'u1',
      );
      expect(applied, isTrue);
      expect(cart().lines.first.quantity, 3);
    });

    test('incrementLine is refused at the stock limit', () {
      seed(stock: 2);
      final bool applied = notifier().incrementLine(
        productId: 'p1',
        unitId: 'u1',
      );
      expect(applied, isFalse);
      expect(cart().lines.first.quantity, 2);
    });

    test('decrementLine reduces by one', () {
      seed();
      notifier().decrementLine(productId: 'p1', unitId: 'u1');
      expect(cart().lines.first.quantity, 1);
    });

    test('decrementLine removes the line when reaching zero', () {
      seed();
      notifier().decrementLine(productId: 'p1', unitId: 'u1');
      notifier().decrementLine(productId: 'p1', unitId: 'u1');
      expect(cart().isEmpty, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // setLineQuantity
  // ---------------------------------------------------------------------------

  group('setLineQuantity', () {
    void seed({double? stock}) {
      notifier().addLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u1',
        unitName: 'قطعة',
        conversionFactor: 1,
        quantity: 1,
        unitPrice: 12,
        availableStock: stock,
      );
    }

    test('applies the given quantity', () {
      seed();
      final bool ok = notifier().setLineQuantity(
        productId: 'p1',
        unitId: 'u1',
        quantity: 7,
      );
      expect(ok, isTrue);
      expect(cart().lines.first.quantity, 7);
    });

    test('removes the line when quantity is zero', () {
      seed();
      notifier().setLineQuantity(
        productId: 'p1',
        unitId: 'u1',
        quantity: 0,
      );
      expect(cart().isEmpty, isTrue);
    });

    test('is refused when quantity exceeds availableStock', () {
      seed(stock: 5);
      final bool ok = notifier().setLineQuantity(
        productId: 'p1',
        unitId: 'u1',
        quantity: 10,
      );
      expect(ok, isFalse);
      expect(cart().lines.first.quantity, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // setLinePrice
  // ---------------------------------------------------------------------------

  group('setLinePrice', () {
    void seed() {
      notifier().addLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u1',
        unitName: 'قطعة',
        conversionFactor: 1,
        quantity: 1,
        unitPrice: 12,
        minSellingPrice: 10,
        maxSellingPrice: 15,
      );
    }

    test('accepts a price within the range', () {
      seed();
      final bool ok = notifier().setLinePrice(
        productId: 'p1',
        unitId: 'u1',
        unitPrice: 14,
      );
      expect(ok, isTrue);
      expect(cart().lines.first.unitPrice, 14);
    });

    test('refuses a price below the minimum', () {
      seed();
      final bool ok = notifier().setLinePrice(
        productId: 'p1',
        unitId: 'u1',
        unitPrice: 5,
      );
      expect(ok, isFalse);
      expect(cart().lines.first.unitPrice, 12);
    });

    test('refuses a price above the maximum', () {
      seed();
      final bool ok = notifier().setLinePrice(
        productId: 'p1',
        unitId: 'u1',
        unitPrice: 20,
      );
      expect(ok, isFalse);
      expect(cart().lines.first.unitPrice, 12);
    });

    test('refuses a negative price', () {
      seed();
      final bool ok = notifier().setLinePrice(
        productId: 'p1',
        unitId: 'u1',
        unitPrice: -1,
      );
      expect(ok, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // removeLine / clearLines / reset
  // ---------------------------------------------------------------------------

  group('removeLine / clearLines / reset', () {
    void seedTwo() {
      notifier().addLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u1',
        unitName: 'قطعة',
        conversionFactor: 1,
        quantity: 1,
        unitPrice: 12,
      );
      notifier().addLine(
        productId: 'p2',
        productName: 'شيبسي',
        unitId: 'u1',
        unitName: 'كيس',
        conversionFactor: 1,
        quantity: 1,
        unitPrice: 6,
      );
    }

    test('removeLine removes exactly one line', () {
      seedTwo();
      notifier().removeLine(productId: 'p1', unitId: 'u1');
      expect(cart().lines.length, 1);
      expect(cart().lines.first.productId, 'p2');
    });

    test('clearLines keeps the customer and the discount', () {
      seedTwo();
      notifier().setCustomer(
        customerId: 'c1',
        customerName: 'أحمد',
        customerBalance: 100,
      );
      notifier().setDiscount(5);

      notifier().clearLines();

      expect(cart().isEmpty, isTrue);
      expect(cart().customerId, 'c1');
      expect(cart().discount, 5);
    });

    test('reset clears everything', () {
      seedTwo();
      notifier().setCustomer(
        customerId: 'c1',
        customerName: 'أحمد',
        customerBalance: 100,
      );
      notifier().setDiscount(5);
      notifier().setTaxAmount(2);

      notifier().reset();

      expect(cart().isEmpty, isTrue);
      expect(cart().customerId, isNull);
      expect(cart().discount, 0);
      expect(cart().taxAmount, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Customer
  // ---------------------------------------------------------------------------

  group('setCustomer / clearCustomer', () {
    test('setCustomer attaches a customer with its balance', () {
      notifier().setCustomer(
        customerId: 'c1',
        customerName: 'أحمد',
        customerBalance: 150,
      );
      expect(cart().customerId, 'c1');
      expect(cart().customerName, 'أحمد');
      expect(cart().customerBalance, 150);
    });

    test('clearCustomer resets the customer fields', () {
      notifier().setCustomer(
        customerId: 'c1',
        customerName: 'أحمد',
        customerBalance: 150,
      );
      notifier().clearCustomer();
      expect(cart().customerId, isNull);
      expect(cart().customerName, isNull);
      expect(cart().customerBalance, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Discount / tax
  // ---------------------------------------------------------------------------

  group('setDiscount / setTaxAmount', () {
    test('setDiscount clamps negative values to zero', () {
      notifier().setDiscount(-5);
      expect(cart().discount, 0);
    });

    test('setDiscount stores positive values', () {
      notifier().setDiscount(25);
      expect(cart().discount, 25);
    });

    test('setTaxAmount clamps negative values to zero', () {
      notifier().setTaxAmount(-10);
      expect(cart().taxAmount, 0);
    });

    test('setTaxAmount stores positive values', () {
      notifier().setTaxAmount(14);
      expect(cart().taxAmount, 14);
    });
  });
}

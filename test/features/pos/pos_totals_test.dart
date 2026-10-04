// test/features/pos/pos_totals_test.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/pos/domain/entities/pos_cart_line.dart';
import 'package:hesabi/features/pos/presentation/state/pos_providers.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Value object
  // ---------------------------------------------------------------------------

  group('PosTotals', () {
    test('reports empty when lineCount is zero', () {
      const PosTotals totals = PosTotals(
        lineCount: 0,
        subtotal: 0,
        discount: 0,
        taxAmount: 0,
        total: 0,
      );

      expect(totals.isEmpty, isTrue);
      expect(totals.isNotEmpty, isFalse);
    });

    test('reports non-empty when lineCount > 0', () {
      const PosTotals totals = PosTotals(
        lineCount: 2,
        subtotal: 50,
        discount: 5,
        taxAmount: 3,
        total: 48,
      );

      expect(totals.isEmpty, isFalse);
      expect(totals.isNotEmpty, isTrue);
    });

    test('equality compares every field', () {
      const PosTotals a = PosTotals(
        lineCount: 2,
        subtotal: 50,
        discount: 5,
        taxAmount: 3,
        total: 48,
      );
      const PosTotals b = PosTotals(
        lineCount: 2,
        subtotal: 50,
        discount: 5,
        taxAmount: 3,
        total: 48,
      );
      const PosTotals c = PosTotals(
        lineCount: 2,
        subtotal: 50,
        discount: 5,
        taxAmount: 3,
        total: 49,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // Provider (end-to-end on cart changes)
  // ---------------------------------------------------------------------------

  group('posTotalsProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    PosTotals totals() => container.read(posTotalsProvider);

    test('empty cart yields empty totals', () {
      final PosTotals t = totals();
      expect(t.isEmpty, isTrue);
      expect(t.subtotal, 0);
      expect(t.total, 0);
      expect(t.lineCount, 0);
    });

    test('adding a line updates the totals', () {
      container.read(posCartProvider.notifier).addLine(
            productId: 'p1',
            productName: 'بيبسي',
            unitId: 'u1',
            unitName: 'قطعة',
            conversionFactor: 1,
            quantity: 2,
            unitPrice: 12,
          );

      final PosTotals t = totals();
      expect(t.lineCount, 1);
      expect(t.subtotal, 24);
      expect(t.total, 24);
    });

    test('discount and tax are reflected in the total', () {
      final PosCartNotifier notifier =
          container.read(posCartProvider.notifier);
      notifier.addLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u1',
        unitName: 'قطعة',
        conversionFactor: 1,
        quantity: 2,
        unitPrice: 25,
      ); // 50
      notifier.setDiscount(5);
      notifier.setTaxAmount(3);

      final PosTotals t = totals();
      expect(t.subtotal, 50);
      expect(t.discount, 5);
      expect(t.taxAmount, 3);
      expect(t.total, 48);
    });

    test('merging two lines updates the totals', () {
      final PosCartNotifier notifier =
          container.read(posCartProvider.notifier);
      notifier.addLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u1',
        unitName: 'قطعة',
        conversionFactor: 1,
        quantity: 1,
        unitPrice: 10,
      );
      notifier.addLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u1',
        unitName: 'قطعة',
        conversionFactor: 1,
        quantity: 1,
        unitPrice: 10,
      );

      final PosTotals t = totals();
      expect(t.lineCount, 1);
      expect(t.subtotal, 20);
    });

    test('removing the only line empties the totals', () {
      final PosCartNotifier notifier =
          container.read(posCartProvider.notifier);
      notifier.addLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u1',
        unitName: 'قطعة',
        conversionFactor: 1,
        quantity: 1,
        unitPrice: 10,
      );
      notifier.removeLine(productId: 'p1', unitId: 'u1');

      final PosTotals t = totals();
      expect(t.isEmpty, isTrue);
    });

    test('two lines with different products sum their totals', () {
      final PosCartNotifier notifier =
          container.read(posCartProvider.notifier);
      notifier.addLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u1',
        unitName: 'قطعة',
        conversionFactor: 1,
        quantity: 2,
        unitPrice: 10,
      ); // 20
      notifier.addLine(
        productId: 'p2',
        productName: 'شيبسي',
        unitId: 'u1',
        unitName: 'كيس',
        conversionFactor: 1,
        quantity: 3,
        unitPrice: 5,
      ); // 15

      final PosTotals t = totals();
      expect(t.lineCount, 2);
      expect(t.subtotal, 35);
      expect(t.total, 35);
    });
  });
}

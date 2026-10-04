// test/features/pos/pos_cart_line_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/pos/domain/entities/pos_cart_line.dart';

void main() {
  group('PosCartLine.derived', () {
    test('lineTotal = quantity * unitPrice', () {
      const PosCartLine line = PosCartLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u1',
        unitName: 'قطعة',
        conversionFactor: 1,
        quantity: 3,
        unitPrice: 12.5,
      );

      expect(line.lineTotal, 37.5);
    });

    test('key combines productId and unitId', () {
      const PosCartLine line = PosCartLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u1',
        unitName: 'قطعة',
        conversionFactor: 1,
        quantity: 1,
        unitPrice: 12,
      );

      expect(line.key, 'p1::u1');
    });

    test('hasNotes is false when notes is null', () {
      const PosCartLine line = PosCartLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u1',
        unitName: 'قطعة',
        conversionFactor: 1,
        quantity: 1,
        unitPrice: 12,
      );

      expect(line.hasNotes, isFalse);
    });

    test('hasNotes is false when notes is whitespace only', () {
      const PosCartLine line = PosCartLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u1',
        unitName: 'قطعة',
        conversionFactor: 1,
        quantity: 1,
        unitPrice: 12,
        notes: '   ',
      );

      expect(line.hasNotes, isFalse);
    });

    test('hasNotes is true when notes has content', () {
      const PosCartLine line = PosCartLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u1',
        unitName: 'قطعة',
        conversionFactor: 1,
        quantity: 1,
        unitPrice: 12,
        notes: 'بدون ثلج',
      );

      expect(line.hasNotes, isTrue);
    });
  });

  group('PosCartLine.isPriceValid', () {
    PosCartLine build({
      double unitPrice = 12,
      double? min,
      double? max,
    }) =>
        PosCartLine(
          productId: 'p1',
          productName: 'بيبسي',
          unitId: 'u1',
          unitName: 'قطعة',
          conversionFactor: 1,
          quantity: 1,
          unitPrice: unitPrice,
          minSellingPrice: min,
          maxSellingPrice: max,
        );

    test('true when no bounds are set', () {
      expect(build().isPriceValid, isTrue);
      expect(build().hasPriceRange, isFalse);
    });

    test('true when price is inside bounds', () {
      final PosCartLine line = build(unitPrice: 12, min: 10, max: 15);
      expect(line.hasPriceRange, isTrue);
      expect(line.isPriceValid, isTrue);
    });

    test('false when price is below the minimum', () {
      expect(build(unitPrice: 9, min: 10, max: 15).isPriceValid, isFalse);
    });

    test('false when price is above the maximum', () {
      expect(build(unitPrice: 20, min: 10, max: 15).isPriceValid, isFalse);
    });

    test('true at exactly the minimum and maximum', () {
      expect(build(unitPrice: 10, min: 10, max: 15).isPriceValid, isTrue);
      expect(build(unitPrice: 15, min: 10, max: 15).isPriceValid, isTrue);
    });
  });

  group('PosCartLine.canIncrease', () {
    PosCartLine build({double quantity = 1, double? stock}) => PosCartLine(
          productId: 'p1',
          productName: 'بيبسي',
          unitId: 'u1',
          unitName: 'قطعة',
          conversionFactor: 1,
          quantity: quantity,
          unitPrice: 12,
          availableStock: stock,
        );

    test('true when availableStock is null (unbounded)', () {
      expect(build(quantity: 100).canIncrease, isTrue);
    });

    test('true while quantity is below stock', () {
      expect(build(quantity: 1, stock: 5).canIncrease, isTrue);
      expect(build(quantity: 4, stock: 5).canIncrease, isTrue);
    });

    test('false when quantity reaches the stock', () {
      expect(build(quantity: 5, stock: 5).canIncrease, isFalse);
      expect(build(quantity: 6, stock: 5).canIncrease, isFalse);
    });
  });

  group('PosCartLine.copyWith', () {
    const PosCartLine base = PosCartLine(
      productId: 'p1',
      productName: 'بيبسي',
      unitId: 'u1',
      unitName: 'قطعة',
      conversionFactor: 1,
      quantity: 2,
      unitPrice: 12,
      minSellingPrice: 10,
      maxSellingPrice: 15,
      availableStock: 20,
      notes: 'ملاحظة',
    );

    test('quantity is replaced', () {
      final PosCartLine next = base.copyWith(quantity: 5);
      expect(next.quantity, 5);
      expect(next.productId, base.productId);
      expect(next.unitPrice, base.unitPrice);
    });

    test('unitPrice is replaced', () {
      final PosCartLine next = base.copyWith(unitPrice: 14);
      expect(next.unitPrice, 14);
      expect(next.quantity, base.quantity);
    });

    test('clearMinSellingPrice removes the lower bound', () {
      final PosCartLine next =
          base.copyWith(clearMinSellingPrice: true);
      expect(next.minSellingPrice, isNull);
      expect(next.maxSellingPrice, base.maxSellingPrice);
    });

    test('clearMaxSellingPrice removes the upper bound', () {
      final PosCartLine next =
          base.copyWith(clearMaxSellingPrice: true);
      expect(next.maxSellingPrice, isNull);
      expect(next.minSellingPrice, base.minSellingPrice);
    });

    test('clearAvailableStock removes the stock snapshot', () {
      final PosCartLine next =
          base.copyWith(clearAvailableStock: true);
      expect(next.availableStock, isNull);
    });

    test('clearNotes removes the note', () {
      final PosCartLine next = base.copyWith(clearNotes: true);
      expect(next.notes, isNull);
      expect(next.hasNotes, isFalse);
    });
  });

  group('PosCartLine equality', () {
    const PosCartLine a = PosCartLine(
      productId: 'p1',
      productName: 'بيبسي',
      unitId: 'u1',
      unitName: 'قطعة',
      conversionFactor: 1,
      quantity: 2,
      unitPrice: 12,
    );

    const PosCartLine b = PosCartLine(
      productId: 'p1',
      productName: 'بيبسي',
      unitId: 'u1',
      unitName: 'قطعة',
      conversionFactor: 1,
      quantity: 2,
      unitPrice: 12,
    );

    test('two lines with identical fields are equal', () {
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('a quantity difference is significant', () {
      final PosCartLine c = a.copyWith(quantity: 3);
      expect(a, isNot(equals(c)));
    });

    test('a unit difference is significant', () {
      const PosCartLine c = PosCartLine(
        productId: 'p1',
        productName: 'بيبسي',
        unitId: 'u2',
        unitName: 'كرتونة',
        conversionFactor: 24,
        quantity: 2,
        unitPrice: 12,
      );
      expect(a, isNot(equals(c)));
    });
  });
}

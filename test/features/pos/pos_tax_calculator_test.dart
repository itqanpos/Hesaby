import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/pos/domain/services/pos_tax_calculator.dart';

void main() {
  group('PosTaxCalculator.taxFor', () {
    test('default rate applies to the amount after discount', () {
      expect(
        PosTaxCalculator.taxFor(
          afterDiscount: 100,
          manualTax: 0,
          defaultTaxRate: 14,
        ),
        14,
      );
      expect(
        PosTaxCalculator.taxFor(
          afterDiscount: 90,
          manualTax: 0,
          defaultTaxRate: 14,
        ),
        12.6,
      );
    });

    test('a positive manual tax overrides the default rate', () {
      expect(
        PosTaxCalculator.taxFor(
          afterDiscount: 100,
          manualTax: 5,
          defaultTaxRate: 14,
        ),
        5,
      );
    });

    test('zero rate and no manual tax means no tax', () {
      expect(
        PosTaxCalculator.taxFor(
          afterDiscount: 100,
          manualTax: 0,
          defaultTaxRate: 0,
        ),
        0,
      );
    });

    test('tax is rounded to two decimals', () {
      expect(
        PosTaxCalculator.taxFor(
          afterDiscount: 33.33,
          manualTax: 0,
          defaultTaxRate: 14,
        ),
        4.67,
      );
    });

    test('a negative base produces no tax', () {
      expect(
        PosTaxCalculator.taxFor(
          afterDiscount: -20,
          manualTax: 0,
          defaultTaxRate: 14,
        ),
        0,
      );
    });
  });

  group('PosTaxCalculator.totalFor', () {
    test('total is amount after discount plus tax', () {
      expect(
        PosTaxCalculator.totalFor(afterDiscount: 90, tax: 12.6),
        102.6,
      );
    });

    test('total is never negative', () {
      expect(
        PosTaxCalculator.totalFor(afterDiscount: -5, tax: 0),
        0,
      );
    });
  });
}

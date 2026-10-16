import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/pos/presentation/state/pos_providers.dart';
import 'package:hesabi/features/settings/presentation/providers/company_settings_providers.dart';

void main() {
  group('posTotalsProvider with tax', () {
    ProviderContainer containerWithRate(double rate) => ProviderContainer(
          overrides: [defaultTaxRateProvider.overrideWith((ref) => rate)],
        );

    void addHundred(ProviderContainer container) {
      container.read(posCartProvider.notifier).addLine(
            productId: 'p1',
            productName: 'منتج',
            unitId: 'u1',
            unitName: 'قطعة',
            conversionFactor: 1,
            quantity: 1,
            unitPrice: 100,
          );
    }

    test('default rate adds tax to the total', () {
      final ProviderContainer container = containerWithRate(14);
      addHundred(container);

      final t = container.read(posTotalsProvider);
      expect(t.subtotal, 100);
      expect(t.taxAmount, 14);
      expect(t.total, 114);
    });

    test('default rate is applied after the discount', () {
      final ProviderContainer container = containerWithRate(14);
      addHundred(container);
      container.read(posCartProvider.notifier).setDiscount(10);

      final t = container.read(posTotalsProvider);
      expect(t.taxAmount, 12.6);
      expect(t.total, 102.6);
    });

    test('a manual tax amount overrides the default rate', () {
      final ProviderContainer container = containerWithRate(14);
      addHundred(container);
      container.read(posCartProvider.notifier).setTaxAmount(5);

      final t = container.read(posTotalsProvider);
      expect(t.taxAmount, 5);
      expect(t.total, 105);
    });
  });
}

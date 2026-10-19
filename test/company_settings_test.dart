// test/company_settings_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/settings/domain/entities/company_settings.dart';

void main() {
  group('CompanySettings', () {
    test('defaults showCurrencySymbol to true', () {
      final settings = CompanySettings.defaults('c1');
      expect(settings.showCurrencySymbol, isTrue);
    });

    test('copyWith updates showCurrencySymbol', () {
      final settings = CompanySettings.defaults('c1');
      final updated = settings.copyWith(showCurrencySymbol: false);
      
      expect(updated.showCurrencySymbol, isFalse);
      expect(settings.showCurrencySymbol, isTrue); // الأصل لم يتغير
    });
  });
}

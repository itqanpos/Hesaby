// test/receipt_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/pos/domain/entities/receipt.dart';

void main() {
  group('Receipt Entity', () {
    test('defaults showCurrencySymbol to true', () {
      final receipt = Receipt(
        saleId: 's1',
        dateTime: DateTime.now(),
        companyName: 'C1',
        branchName: 'B1',
        lines: const [],
        subtotal: 100,
        discount: 0,
        taxAmount: 0,
        total: 100,
        paidAmount: 100,
      );

      expect(receipt.showCurrencySymbol, isTrue);
    });

    test('hasBalanceChange is true when both balances are present', () {
      final receipt = Receipt(
        saleId: 's1',
        dateTime: DateTime.now(),
        companyName: 'C1',
        branchName: 'B1',
        lines: const [],
        subtotal: 100, discount: 0, taxAmount: 0, total: 100, paidAmount: 0,
        previousBalance: 50,
        newBalance: 150,
      );

      expect(receipt.hasBalanceChange, isTrue);
    });

    test('hasCreditBalance is true when newBalance < 0', () {
      final receipt = Receipt(
        saleId: 's1', dateTime: DateTime.now(), companyName: 'C', branchName: 'B',
        lines: const [], subtotal: 100, discount: 0, taxAmount: 0, total: 100, paidAmount: 150,
        previousBalance: 0, newBalance: -50,
      );

      expect(receipt.hasCreditBalance, isTrue);
      expect(receipt.newBalanceAbsolute, 50);
    });
  });
}

// test/pos_balance_scenarios_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/pos/domain/entities/pos_cart.dart';

void main() {
  group('POS Balance Scenarios (Math only)', () {
    // القيم الثابتة للاختبار
    const double previousBalance = 100.0;
    const double saleTotal = 200.0;

    // دالة تحاكي الحساب الموجود في pos_payment_dialog.dart
    double calculateNewBalance(double input) {
      final double settlementTotal = previousBalance + saleTotal;
      return settlementTotal - input;
    }

    test('Scenario 1: Pay 0 (Full Credit)', () {
      final double input = 0.0;
      final double newBalance = calculateNewBalance(input);

      expect(newBalance, 300.0); // 100 + 200 - 0
      expect(newBalance > 0, isTrue); // مدين (عليه)
    });

    test('Scenario 2: Pay 100 (Partial Payment)', () {
      final double input = 100.0;
      final double newBalance = calculateNewBalance(input);

      expect(newBalance, 200.0); // 100 + 200 - 100
      expect(newBalance > 0, isTrue); // مدين (عليه)
    });

    test('Scenario 3: Pay 300 (Full Settlement)', () {
      final double input = 300.0;
      final double newBalance = calculateNewBalance(input);

      expect(newBalance, 0.0); // 100 + 200 - 300
      expect(newBalance == 0, isTrue); // مستقر
    });

    test('Scenario 4: Pay 350 (Overpayment / Credit)', () {
      final double input = 350.0;
      final double newBalance = calculateNewBalance(input);

      expect(newBalance, -50.0); // 100 + 200 - 350
      expect(newBalance < 0, isTrue); // دائن (له عندنا)
    });

    test('Cart balance + Sale total = Settlement Total', () {
      final cart = PosCart(
        customerBalance: previousBalance,
        discount: 0,
        taxAmount: 0,
        lines: const [], // لا نحتاج بنوداً لحساب الإجمالي هنا
      );
      
      // بما أننا نحسب saleTotal يدوياً، نختبر فقط المعادلة
      final double settlement = cart.customerBalance + saleTotal;
      expect(settlement, 300.0);
    });
  });
}

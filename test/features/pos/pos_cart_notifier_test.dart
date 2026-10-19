// test/pos_cart_notifier_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hesabi/features/pos/domain/entities/pos_cart.dart';
import 'package:hesabi/features/pos/domain/entities/pos_cart_line.dart';
import 'package:hesabi/features/pos/presentation/state/pos_cart_notifier.dart';
import 'package:hesabi/features/pos/presentation/state/pos_providers.dart';

void main() {
  late ProviderContainer container;
  late PosCartNotifier notifier;

  setUp(() {
    container = ProviderContainer();
    notifier = container.read(posCartProvider.notifier);
  });

  tearDown(() {
    container.dispose();
  });

  group('PosCartNotifier', () {
    test('initial state is empty', () {
      expect(notifier.state.isEmpty, isTrue);
      expect(notifier.state.lines.length, 0);
    });

    test('addLine adds a new line', () {
      notifier.addLine(
        productId: 'p1',
        productName: 'Test Product',
        unitId: 'u1',
        unitName: 'Piece',
        conversionFactor: 1,
        quantity: 2,
        unitPrice: 50,
      );
      
      expect(notifier.state.lines.length, 1);
      expect(notifier.state.lines.first.productId, 'p1');
      expect(notifier.state.lines.first.quantity, 2);
    });

    test('addLine merges existing line', () {
      notifier.addLine(
        productId: 'p1', productName: 'Test', unitId: 'u1', unitName: 'Piece',
        conversionFactor: 1, quantity: 1, unitPrice: 50,
      );
      notifier.addLine(
        productId: 'p1', productName: 'Test', unitId: 'u1', unitName: 'Piece',
        conversionFactor: 1, quantity: 2, unitPrice: 50,
      );

      expect(notifier.state.lines.length, 1);
      expect(notifier.state.lines.first.quantity, 3);
    });

    test('restore replaces the entire state', () {
      final newCart = PosCart(
        lines: [
          const PosCartLine(
            productId: 'p2', productName: 'Restored', unitId: 'u2',
            unitName: 'Box', conversionFactor: 1, quantity: 5, unitPrice: 100,
          ),
        ],
        customerName: 'John',
        customerBalance: 200,
        discount: 10,
        taxAmount: 5,
      );

      notifier.restore(newCart);
      
      expect(notifier.state.lines.length, 1);
      expect(notifier.state.lines.first.productName, 'Restored');
      expect(notifier.state.customerName, 'John');
    });

    test('setLineQuantity rejects quantity above available stock', () {
      notifier.addLine(
        productId: 'p1', productName: 'Test', unitId: 'u1', unitName: 'Piece',
        conversionFactor: 1, quantity: 1, unitPrice: 50, availableStock: 5,
      );

      final accepted = notifier.setLineQuantity(
        productId: 'p1', unitId: 'u1', quantity: 10,
      );

      expect(accepted, isFalse);
      expect(notifier.state.lines.first.quantity, 1); // لم يتغير
    });
  });
}

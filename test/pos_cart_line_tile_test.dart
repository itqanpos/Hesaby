// test/pos_cart_line_tile_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hesabi/features/pos/domain/entities/pos_cart_line.dart';
import 'package:hesabi/features/pos/presentation/state/pos_providers.dart';
import 'package:hesabi/features/pos/presentation/widgets/pos_cart_line_tile.dart';

void main() {
  final testLine = PosCartLine(
    productId: 'p1',
    productName: 'Test',
    unitId: 'u1',
    unitName: 'Piece',
    conversionFactor: 1,
    quantity: 1,
    unitPrice: 50,
    availableStock: 5,
  );

  // ══════════════════════════════════════════════════════════════════════════
  // Test 1: Focus moves to quantity field when provider is set
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('focuses quantity when focusedCartLineProvider matches',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // ⬇️ بناء الواجهة أولاً (قبل تعيين الحالة)
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: PosCartLineTile(
              line: testLine,
              onSetQuantity: (double q) => true,
              onSetPrice: (double p) => true,
              onRemove: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // ⬇️ الآن نُغيّر الحالة لتفعيل ref.listen
    container.read(focusedCartLineProvider.notifier).state = testLine.key;
    await tester.pumpAndSettle();

    // التحقق من أن حقل الكمية حصل على التركيز
    final TextField quantityField =
        tester.widget<TextField>(find.byType(TextField).first);
    expect(quantityField.focusNode?.hasFocus, isTrue);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Test 2: SnackBar appears when quantity exceeds stock
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('shows SnackBar when quantity exceeds stock', (tester) async {
    bool quantityRejected = false;

    // ⬇️ إضافة ProviderScope لحل مشكلة "No ProviderScope found"
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: PosCartLineTile(
              line: testLine,
              onSetQuantity: (double q) {
                if (q > testLine.availableStock!) {
                  quantityRejected = true;
                  return false;
                }
                return true;
              },
              onSetPrice: (double p) => true,
              onRemove: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // إدخال كمية تتجاوز المتاح (5)
    await tester.enterText(find.byType(TextField).first, '10');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // التحقق من رفض الكمية
    expect(quantityRejected, isTrue);

    // التحقق من ظهور رسالة التحذير
    expect(
      find.text('عذراً، الكمية المتاحة هي 5 فقط.'),
      findsOneWidget,
    );
  });
}

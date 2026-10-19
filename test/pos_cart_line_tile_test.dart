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

  testWidgets('focuses quantity when focusedCartLineProvider matches', (tester) async {
    final container = ProviderContainer();
    container.read(focusedCartLineProvider.notifier).state = testLine.key;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: PosCartLineTile(
              line: testLine,
              onSetQuantity: (q) => true,
              onSetPrice: (p) => true,
              onRemove: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final textField = tester.widget<TextField>(find.byType(TextField).first);
    expect(textField.focusNode?.hasFocus, isTrue);

    container.dispose();
  });

  testWidgets('shows SnackBar when quantity exceeds stock', (tester) async {
    bool quantityRejected = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PosCartLineTile(
            line: testLine,
            onSetQuantity: (q) {
              if (q > testLine.availableStock!) {
                quantityRejected = true;
                return false;
              }
              return true;
            },
            onSetPrice: (p) => true,
            onRemove: () {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, '10');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // التحقق من أن الكمية رُفضت
    expect(quantityRejected, isTrue);

    // التحقق من ظهور رسالة التحذير
    expect(find.text('عذراً، الكمية المتاحة هي 5 فقط.'), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/pos/domain/entities/pos_cart.dart';
import 'package:hesabi/features/pos/domain/entities/pos_cart_line.dart';
import 'package:hesabi/features/pos/presentation/dialogs/pos_duplicate_line_dialog.dart';

PosCartLine _line({
  required String productId,
  required String unitId,
  double quantity = 1,
}) {
  return PosCartLine(
    productId: productId,
    productName: 'منتج',
    unitId: unitId,
    unitName: 'قطعة',
    conversionFactor: 1,
    quantity: quantity,
    unitPrice: 10,
  );
}

void main() {
  group('findExistingCartLine', () {
    test('returns null for an empty cart', () {
      expect(
        findExistingCartLine(const PosCart(), 'p1', 'u1'),
        isNull,
      );
    });

    test('finds a line with the same product and unit', () {
      final PosCart cart = const PosCart().copyWith(
        lines: <PosCartLine>[_line(productId: 'p1', unitId: 'u1', quantity: 2)],
      );
      final PosCartLine? found = findExistingCartLine(cart, 'p1', 'u1');
      expect(found, isNotNull);
      expect(found!.quantity, 2);
    });

    test('same product in another unit is not a duplicate', () {
      final PosCart cart = const PosCart().copyWith(
        lines: <PosCartLine>[_line(productId: 'p1', unitId: 'u1')],
      );
      expect(findExistingCartLine(cart, 'p1', 'u2'), isNull);
    });

    test('a different product in the same unit is not a duplicate', () {
      final PosCart cart = const PosCart().copyWith(
        lines: <PosCartLine>[_line(productId: 'p1', unitId: 'u1')],
      );
      expect(findExistingCartLine(cart, 'p2', 'u1'), isNull);
    });
  });
}

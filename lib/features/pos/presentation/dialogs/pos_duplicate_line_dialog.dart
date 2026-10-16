// lib/features/pos/presentation/dialogs/pos_duplicate_line_dialog.dart

import 'package:flutter/material.dart';

import '../../domain/entities/pos_cart.dart';
import '../../domain/entities/pos_cart_line.dart';

/// Returns the cart line that already holds [productId] in [unitId], if any.
///
/// Lines are unique per (product, unit): adding the same product in the same
/// unit merges into the existing line, so the cashier should be told first.
PosCartLine? findExistingCartLine(
  PosCart cart,
  String productId,
  String unitId,
) {
  for (final PosCartLine line in cart.lines) {
    if (line.productId == productId && line.unitId == unitId) {
      return line;
    }
  }
  return null;
}

/// Asks the cashier whether to increase the quantity of a product that is
/// already in the cart. Returns `true` only if they confirm.
Future<bool> confirmIncreaseExistingLine(
  BuildContext context, {
  required String productName,
  required double currentQuantity,
}) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('المنتج موجود في السلة'),
      content: Text(
        '«$productName» موجود بالفعل بكمية '
        '${_formatQuantity(currentQuantity)}.\n'
        'هل تريد زيادة الكمية بمقدار 1؟',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('زيادة الكمية'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

String _formatQuantity(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
}

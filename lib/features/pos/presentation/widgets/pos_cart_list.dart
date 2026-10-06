// lib/features/pos/presentation/widgets/pos_cart_list.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/app_empty.dart';
import '../../domain/entities/pos_cart.dart';
import '../../domain/entities/pos_cart_line.dart';
import '../state/pos_providers.dart';
import 'pos_cart_line_tile.dart';

/// The list of lines currently in the POS cart.
///
/// Behaviour:
/// * When the cart is empty, an [AppEmptyView] is shown with a short hint.
/// * Otherwise, one [PosCartLineTile] is rendered per line, separated by a
///   thin divider.
///
/// Quantity and price are edited **by typing** inside each tile. The tile
/// commits a new value by calling [PosCartNotifier.setLineQuantity] /
/// [PosCartNotifier.setLinePrice], which enforce the available-stock cap
/// and the price bounds respectively. When a value is rejected, the tile
/// resets its field and shows a small inline hint — no snack bar is
/// involved.
class PosCartList extends ConsumerWidget {
  const PosCartList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PosCart cart = ref.watch(posCartProvider);

    if (cart.isEmpty) {
      return const AppEmptyView(
        icon: Icons.shopping_cart_outlined,
        title: 'السلة فارغة',
        message: 'ابحث عن منتج أو امسح الباركود لإضافته.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: cart.lines.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final PosCartLine line = cart.lines[index];

        return PosCartLineTile(
          line: line,
          onSetQuantity: (double quantity) {
            return ref.read(posCartProvider.notifier).setLineQuantity(
                  productId: line.productId,
                  unitId: line.unitId,
                  quantity: quantity,
                );
          },
          onSetPrice: (double price) {
            return ref.read(posCartProvider.notifier).setLinePrice(
                  productId: line.productId,
                  unitId: line.unitId,
                  unitPrice: price,
                );
          },
          onRemove: () {
            ref.read(posCartProvider.notifier).removeLine(
                  productId: line.productId,
                  unitId: line.unitId,
                );
          },
        );
      },
    );
  }
}

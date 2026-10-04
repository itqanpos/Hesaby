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
/// Incrementing a line is subject to the line's known available stock
/// (`PosCartLine.canIncrease`). When the notifier rejects the increment,
/// a short snack bar is displayed explaining why.
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
          onIncrement: () => _handleIncrement(context, ref, line),
          onDecrement: () => _handleDecrement(context, ref, line),
          onRemove: () => _handleRemove(context, ref, line),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------------

  void _handleIncrement(
    BuildContext context,
    WidgetRef ref,
    PosCartLine line,
  ) {
    final bool applied = ref.read(posCartProvider.notifier).incrementLine(
          productId: line.productId,
          unitId: line.unitId,
        );

    if (!applied && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(
              'لا يمكن زيادة الكمية. الرصيد المتاح: '
              '${_formatStock(line.availableStock)}',
            ),
          ),
        );
    }
  }

  void _handleDecrement(
    BuildContext context,
    WidgetRef ref,
    PosCartLine line,
  ) {
    ref.read(posCartProvider.notifier).decrementLine(
          productId: line.productId,
          unitId: line.unitId,
        );
  }

  void _handleRemove(
    BuildContext context,
    WidgetRef ref,
    PosCartLine line,
  ) {
    ref.read(posCartProvider.notifier).removeLine(
          productId: line.productId,
          unitId: line.unitId,
        );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _formatStock(double? available) {
    if (available == null) {
      return '—';
    }
    if (available == available.roundToDouble()) {
      return available.toInt().toString();
    }
    return available.toStringAsFixed(2);
  }
}

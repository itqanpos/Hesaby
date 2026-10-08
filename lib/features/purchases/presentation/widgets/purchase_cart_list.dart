// lib/features/purchases/presentation/widgets/purchase_cart_list.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/purchase_cart.dart';
import '../../domain/entities/purchase_cart_line.dart';
import '../state/purchase_providers.dart';
import 'purchase_cart_line_tile.dart';

/// Renders the current purchase cart, or an empty-state hint.
class PurchaseCartList extends ConsumerWidget {
  const PurchaseCartList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PurchaseCart cart = ref.watch(purchaseCartProvider);

    if (cart.isEmpty) {
      return const _EmptyCartHint();
    }

    final PurchaseCartNotifier notifier =
        ref.read(purchaseCartProvider.notifier);

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: cart.lines.length,
      itemBuilder: (BuildContext context, int index) {
        final PurchaseCartLine line = cart.lines[index];
        return PurchaseCartLineTile(
          key: ValueKey<String>(line.key),
          line: line,
          onSetQuantity: (double qty) {
            notifier.setQuantity(line.key, qty);
            return true;
          },
          onSetCost: (double cost) {
            notifier.setUnitCost(line.key, cost);
            return true;
          },
          onRemove: () => notifier.removeLine(line.key),
        );
      },
    );
  }
}

// ============================================================================
// Empty hint
// ============================================================================

class _EmptyCartHint extends StatelessWidget {
  const _EmptyCartHint();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.shopping_bag_outlined,
              size: 48,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'السلة فارغة',
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'ابحث عن منتج أو امسح الباركود لإضافته.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

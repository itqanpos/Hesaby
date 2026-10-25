// lib/features/purchases/presentation/pages/purchase_desktop_layout.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/purchase_search_notifier.dart';
import '../state/purchase_providers.dart';
import '../widgets/purchase_bottom_panel.dart';
import '../widgets/purchase_cart_list.dart';
import '../widgets/purchase_header_bar.dart';
import '../widgets/purchase_results_list.dart';
import '../widgets/purchase_search_field.dart';

/// Purchase form layout for desktop / wide screens.
///
/// Split layout (5:3):
/// * **Left (5/8)**: supplier + date + invoice number, then search field,
///   then a grid of results (or a hint when not searching).
/// * **Right (3/8)**: cart lines, totals panel, save actions.
class PurchaseDesktopLayout extends ConsumerWidget {
  const PurchaseDesktopLayout({
    super.key,
    required this.onSaveDraft,
    required this.onSaveAndConfirm,
    required this.isSubmitting,
  });

  final VoidCallback onSaveDraft;
  final VoidCallback onSaveAndConfirm;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PurchaseSearchState search = ref.watch(purchaseSearchProvider);
    final bool isSearching = search.isNotEmpty;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ---- Left column ----
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const PurchaseHeaderBar(),
              const PurchaseSearchField(),
              Expanded(
                child: isSearching
                    ? const PurchaseResultsList()
                    : const _SearchHint(),
              ),
            ],
          ),
        ),
        VerticalDivider(width: 1, thickness: 1, color: scheme.outlineVariant),

        // ---- Right column ----
        Expanded(
          flex: 3,
          child: Container(
            color: scheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.shopping_bag_outlined,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'بنود الفاتورة',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const Expanded(child: PurchaseCartList()),
                Divider(
                  height: 2,
                  thickness: 2,
                  color: scheme.outlineVariant,
                ),
                PurchaseBottomPanel(
                  onSaveDraft: onSaveDraft,
                  onSaveAndConfirm: onSaveAndConfirm,
                  isSubmitting: isSubmitting,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

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
              Icons.touch_app_outlined,
              size: 64,
              color: scheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'ابحث عن منتج لإضافته إلى الفاتورة',
              style: theme.textTheme.titleMedium?.copyWith(
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

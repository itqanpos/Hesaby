// lib/features/pos/presentation/pages/pos_tablet_layout.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/pos_providers.dart';
import '../state/pos_search_notifier.dart';
import '../widgets/pos_cart_list.dart';
import '../widgets/pos_customer_bar.dart';
import '../widgets/pos_pay_button.dart';
import '../widgets/pos_results_list.dart';
import '../widgets/pos_search_field.dart';
import '../widgets/pos_totals_bar.dart';

/// POS layout for tablet screens (600 ≤ width < 1024 dp).
class PosTabletLayout extends ConsumerWidget {
  const PosTabletLayout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PosSearchState search = ref.watch(posSearchProvider);
    final bool isSearching = search.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ---------------------------------------------------------------------
        // Left column — context + search + results
        // ---------------------------------------------------------------------
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const PosCustomerBar(),
              const PosSearchField(),
              Expanded(
                child: isSearching
                    ? const PosResultsList()
                    : const _CartHint(),
              ),
            ],
          ),
        ),

        const VerticalDivider(width: 1, thickness: 1),

        // ---------------------------------------------------------------------
        // Right column — cart summary + totals + pay button
        // ---------------------------------------------------------------------
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Expanded(child: PosCartList()),
              const PosTotalsBar(),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    height: 56,
                    child: PosPayButton(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Left column placeholder when not searching
// ============================================================================

class _CartHint extends StatelessWidget {
  const _CartHint();

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
            Icon(Icons.search, size: 56, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              'ابحث عن منتج أو امسح الباركود',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'ستظهر النتائج هنا، وستبقى السلة على اليسار.',
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

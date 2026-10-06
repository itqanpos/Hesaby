// lib/features/pos/presentation/pages/pos_mobile_layout.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/pos_providers.dart';
import '../state/pos_search_notifier.dart';
import '../widgets/pos_bottom_panel.dart';
import '../widgets/pos_cart_list.dart';
import '../widgets/pos_customer_bar.dart';
import '../widgets/pos_results_list.dart';
import '../widgets/pos_search_field.dart';

/// POS layout for mobile screens (width < 600 dp).
///
/// Layout, top to bottom:
/// * [PosCustomerBar]     — attached customer.
/// * [PosSearchField]     — name / SKU / barcode search.
/// * Middle area:
///     - **Not searching**: cart fills the entire middle area.
///     - **Searching**:     search results and cart share the middle area
///                          using `Flexible` (results 2/5, cart 3/5), so
///                          the cart always stays visible **and** the
///                          bottom panel is never pushed above the
///                          keyboard.
/// * [PosBottomPanel]     — compact totals + pay button.
///
/// The previous implementation used a fixed `maxHeight` computed from the
/// **full** screen height, which caused the bottom panel to overlap the
/// search results once the soft keyboard pushed the body upwards. Using
/// `Flexible` instead makes the split responsive to the real available
/// height at any moment — including with the keyboard open.
class PosMobileLayout extends ConsumerWidget {
  const PosMobileLayout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PosSearchState search = ref.watch(posSearchProvider);
    final bool isSearching = search.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const PosCustomerBar(),
        const PosSearchField(),
        Expanded(
          child: isSearching
              ? const _SplitView()
              : const PosCartList(),
        ),
        const PosBottomPanel(),
      ],
    );
  }
}

// ============================================================================
// Split view — results + cart
// ============================================================================

class _SplitView extends StatelessWidget {
  const _SplitView();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SectionLabel(
          icon: Icons.search,
          label: 'نتائج البحث',
          tone: _LabelTone.accent,
        ),
        // Results take 2/5 of the available height.
        Flexible(
          flex: 2,
          child: PosResultsList(),
        ),
        _ThinDivider(),
        _SectionLabel(
          icon: Icons.shopping_cart_outlined,
          label: 'السلة',
          tone: _LabelTone.neutral,
        ),
        // Cart takes 3/5 of the available height, so it is always visible.
        Flexible(
          flex: 3,
          child: PosCartList(),
        ),
      ],
    );
  }
}

// ============================================================================
// Small helpers
// ============================================================================

enum _LabelTone { accent, neutral }

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.label,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final _LabelTone tone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color color = tone == _LabelTone.accent
        ? scheme.primary
        : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          Container(
            width: 24,
            height: 2,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinDivider extends StatelessWidget {
  const _ThinDivider();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: scheme.outlineVariant.withValues(alpha: 0.5),
    );
  }
}

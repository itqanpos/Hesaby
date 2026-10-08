// lib/features/purchases/presentation/pages/purchase_mobile_layout.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/purchase_providers.dart';
import '../state/purchase_search_notifier.dart';
import '../widgets/purchase_bottom_panel.dart';
import '../widgets/purchase_cart_list.dart';
import '../widgets/purchase_header_bar.dart';
import '../widgets/purchase_results_list.dart';
import '../widgets/purchase_search_field.dart';

/// Layout for the purchase form on mobile screens.
///
/// Structure (top → bottom):
/// * [PurchaseHeaderBar]   — supplier + date + invoice number.
/// * [PurchaseSearchField] — name / SKU / barcode search with scanner.
/// * Middle area:
///     - **Not searching**: cart fills the middle area.
///     - **Searching**:     search results and cart share the middle area
///                          (results 2/5, cart 3/5). The cart always stays
///                          visible while the user browses results.
/// * [PurchaseBottomPanel] — totals + save actions.
///
/// Mirrors `PosMobileLayout` for consistency.
class PurchaseMobileLayout extends ConsumerWidget {
  const PurchaseMobileLayout({
    super.key,
    required this.onSaveDraft,
    required this.onSaveAndConfirm,
    required this.isSubmitting,
  });

  /// Invoked when the user taps "حفظ كمسودة".
  final VoidCallback onSaveDraft;

  /// Invoked when the user taps "حفظ وتأكيد".
  final VoidCallback onSaveAndConfirm;

  /// Whether a save is in progress.
  final bool isSubmitting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PurchaseSearchState search = ref.watch(purchaseSearchProvider);
    final bool isSearching = search.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const PurchaseHeaderBar(),
        const PurchaseSearchField(),
        Expanded(
          child: isSearching
              ? const _SplitView()
              : const PurchaseCartList(),
        ),
        PurchaseBottomPanel(
          onSaveDraft: onSaveDraft,
          onSaveAndConfirm: onSaveAndConfirm,
          isSubmitting: isSubmitting,
        ),
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
        Flexible(
          flex: 2,
          child: PurchaseResultsList(),
        ),
        _ThinDivider(),
        _SectionLabel(
          icon: Icons.shopping_bag_outlined,
          label: 'بنود الفاتورة',
          tone: _LabelTone.neutral,
        ),
        Flexible(
          flex: 3,
          child: PurchaseCartList(),
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

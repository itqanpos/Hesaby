// lib/features/pos/presentation/pages/pos_desktop_layout.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/pos_providers.dart';
import '../state/pos_search_notifier.dart';
import '../widgets/pos_actions_sheet.dart';
import '../widgets/pos_cart_list.dart';
import '../widgets/pos_customer_bar.dart';
import '../widgets/pos_pay_button.dart';
import '../widgets/pos_results_list.dart';
import '../widgets/pos_search_field.dart';
import '../widgets/pos_totals_bar.dart';

/// POS layout for desktop and wide-desktop screens (width ≥ 1024 dp).
///
/// Three columns:
/// * **Left (≈ 45%)** — attached customer, search field, and either the
///   search results or a friendly hint.
/// * **Middle (≈ 30%)** — the cart, always visible, scrollable on its own.
/// * **Right (≈ 25%)** — totals, discount editor, and the action buttons.
///
/// The keyboard inset is intentionally ignored: desktop machines are
/// usually driven by a physical keyboard, and the operating system does
/// not raise an on-screen keyboard for this layout in practice.
class PosDesktopLayout extends ConsumerWidget {
  const PosDesktopLayout({super.key});

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
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const PosCustomerBar(),
              const PosSearchField(),
              Expanded(
                child: isSearching
                    ? const PosResultsList()
                    : const _SearchHint(),
              ),
            ],
          ),
        ),

        const VerticalDivider(width: 1, thickness: 1),

        // ---------------------------------------------------------------------
        // Middle column — the cart, always visible
        // ---------------------------------------------------------------------
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _ColumnHeader(label: 'السلة'),
              Expanded(
                child: const PosCartList(),
              ),
            ],
          ),
        ),

        const VerticalDivider(width: 1, thickness: 1),

        // ---------------------------------------------------------------------
        // Right column — totals + actions
        // ---------------------------------------------------------------------
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _ColumnHeader(label: 'الإجماليات'),
              Expanded(
                child: SingleChildScrollView(
                  child: const PosTotalsBar(),
                ),
              ),
              const _DesktopActions(),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Column header — small caption above each column
// ============================================================================

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Row(
        children: <Widget>[
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Search hint — shown in the left column when not typing
// ============================================================================

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
              Icons.search,
              size: 56,
              color: scheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'ابحث عن منتج أو امسح الباركود',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'ستظهر النتائج هنا. السلة على اليمين.',
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

// ============================================================================
// Bottom actions — إجراءات + دفع
// ============================================================================

class _DesktopActions extends StatelessWidget {
  const _DesktopActions();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            PosPayButton(),
            SizedBox(height: 8),
            _ActionsButton(),
          ],
        ),
      ),
    );
  }
}

class _ActionsButton extends StatelessWidget {
  const _ActionsButton();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return OutlinedButton(
      onPressed: () => showPosActionsSheet(context),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        side: BorderSide(color: scheme.outline),
        foregroundColor: scheme.onSurface,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.more_horiz, size: 20, color: scheme.onSurface),
          const SizedBox(width: 6),
          Text(
            'إجراءات',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

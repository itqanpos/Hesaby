// lib/features/pos/presentation/pages/pos_mobile_layout.dart

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

/// POS layout for mobile screens (width < 600 dp).
///
/// Structure, top to bottom:
/// * [PosCustomerBar]   — attached customer or "عميل نقدي".
/// * [PosSearchField]   — name / SKU / barcode search.
/// * middle area        — search results while typing, cart otherwise.
/// * [PosTotalsBar]     — subtotal, discount, total.
/// * bottom actions     — "إجراءات" and the primary pay button.
///
/// The bottom actions float above the software keyboard
/// ([MediaQuery.viewInsetsOf]) and respect the system safe area.
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
          child: isSearching ? const PosResultsList() : const PosCartList(),
        ),
        const PosTotalsBar(),
        const _BottomActions(),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Bottom actions — إجراءات + دفع
// -----------------------------------------------------------------------------

class _BottomActions extends StatelessWidget {
  const _BottomActions();

  static const double _buttonHeight = 56;

  @override
  Widget build(BuildContext context) {
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + keyboardInset),
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            Expanded(
              flex: 2,
              child: SizedBox(
                height: _buttonHeight,
                child: _ActionsButton(
                  onPressed: () => showPosActionsSheet(context: context),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              flex: 3,
              child: SizedBox(
                height: _buttonHeight,
                child: PosPayButton(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionsButton extends StatelessWidget {
  const _ActionsButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        side: BorderSide(color: scheme.outline),
        foregroundColor: scheme.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 12),
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

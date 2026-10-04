// lib/features/pos/presentation/pages/pos_mobile_layout.dart

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

/// POS layout for mobile screens (width < 600 dp).
///
/// Structure, top to bottom:
/// * [PosCustomerBar]   — attached customer or "عميل نقدي".
/// * [PosSearchField]   — name / SKU / barcode search.
/// * middle area        — search results while typing, cart otherwise.
/// * [PosTotalsBar]     — subtotal, discount, total.
/// * the pay button     — pinned at the bottom.
///
/// The keyboard resize is left to the enclosing `Scaffold`
/// (`resizeToAvoidBottomInset: true` by default). No manual `viewInsets`
/// padding is applied here, because it would push the whole layout —
/// including the totals bar — above the keyboard.
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
    );
  }
}

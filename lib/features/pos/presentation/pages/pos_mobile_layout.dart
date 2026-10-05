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
/// Structure, top to bottom:
/// * [PosCustomerBar]   — attached customer or "عميل نقدي".
/// * [PosSearchField]   — name / SKU / barcode search.
/// * middle area        — search results while typing, cart otherwise.
/// * [PosBottomPanel]   — compact totals + discount + pay button, pinned
///   at the bottom.
///
/// The keyboard resize is delegated to the enclosing [Scaffold]
/// (`resizeToAvoidBottomInset: true` by default). Because [PosBottomPanel]
/// is deliberately compact (~150 dp once the keyboard is open), the cart
/// list keeps a meaningful visible height even when the soft keyboard is
/// shown, which was the main UX complaint with the previous layout.
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
        const PosBottomPanel(),
      ],
    );
  }
}

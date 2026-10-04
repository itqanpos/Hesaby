// lib/features/pos/presentation/widgets/pos_pay_button.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/app_button.dart';
import '../dialogs/pos_payment_dialog.dart';
import '../state/pos_providers.dart';

/// The primary POS pay button.
///
/// Displays the current cart total inline and opens the payment dialog
/// when tapped. The button is automatically disabled while the cart is
/// empty, so the cashier never reaches the payment flow with nothing to
/// sell.
///
/// The button is a thin wrapper around [AppButton] so that it inherits the
/// project's theme, sizing and interaction language. No provider is read
/// except `posTotalsProvider`.
class PosPayButton extends ConsumerWidget {
  const PosPayButton({super.key});

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PosTotals totals = ref.watch(posTotalsProvider);
    final bool isEmpty = totals.isEmpty;
    final String label = isEmpty
        ? 'دفع'
        : 'دفع ${_money.format(totals.total)}';

    return AppButton(
      label: label,
      icon: Icons.check_circle_outline,
      expanded: true,
      size: AppButtonSize.large,
      onPressed: isEmpty ? null : () => _handlePay(context),
    );
  }

  Future<void> _handlePay(BuildContext context) async {
    await showPosPaymentDialog(context: context);
  }
}

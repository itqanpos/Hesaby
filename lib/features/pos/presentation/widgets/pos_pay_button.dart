// lib/features/pos/presentation/widgets/pos_pay_button.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/app_button.dart';
import '../../../companies/presentation/widgets/subscription_guard.dart';
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
/// project's theme, sizing and interaction language.
///
/// **Phase T-1:** the pay action is guarded by
/// [SubscriptionGuard.ensureCanWrite]. An expired account may still browse
/// the catalog and build a cart, but tapping the button surfaces the
/// "read-only" dialog instead of the payment dialog.
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
      onPressed: isEmpty ? null : () => _handlePay(context, ref),
    );
  }

  Future<void> _handlePay(BuildContext context, WidgetRef ref) async {
    final bool allowed = await SubscriptionGuard.ensureCanWrite(
      context: context,
      ref: ref,
    );
    if (!allowed || !context.mounted) return;

    await showPosPaymentDialog(context: context);
  }
}

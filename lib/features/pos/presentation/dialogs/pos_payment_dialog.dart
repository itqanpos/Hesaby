// lib/features/pos/presentation/dialogs/pos_payment_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/app_button.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../sales/domain/entities/sale_entities.dart';
import '../../../sales/domain/repositories/sales_repository.dart';
import '../../../sales/presentation/providers/sales_providers.dart';
import '../../domain/entities/pos_cart.dart';
import '../../domain/entities/pos_cart_line.dart';
import '../state/pos_providers.dart';

/// Payment methods supported by the POS.
abstract final class PosPaymentMethod {
  static const String cash = 'cash';
  static const String card = 'card';
  static const String credit = 'credit';
}

/// Opens the POS payment dialog.
///
/// Returns `true` when the sale was created and confirmed, `false` or
/// `null` when the dialog was dismissed without completing the sale.
Future<bool?> showPosPaymentDialog({required BuildContext context}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) => const _PosPaymentDialog(),
  );
}

// ============================================================================
// Payment dialog
// ============================================================================

class _PosPaymentDialog extends ConsumerStatefulWidget {
  const _PosPaymentDialog();

  @override
  ConsumerState<_PosPaymentDialog> createState() => _PosPaymentDialogState();
}

class _PosPaymentDialogState extends ConsumerState<_PosPaymentDialog> {
  late final PosCart _cart;
  late final TextEditingController _amountController;

  String _method = PosPaymentMethod.cash;
  bool _isSubmitting = false;
  SalesFailureType? _serverFailure;

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    // Snapshot the cart at open time. Any external mutation (for example a
    // reset from another widget) must not disturb an in-flight payment.
    _cart = ref.read(posCartProvider);
    _amountController = TextEditingController(
      text: _formatAmount(_cart.total),
    );
    _amountController.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    if (!mounted) {
      return;
    }
    if (_serverFailure != null) {
      setState(() => _serverFailure = null);
    } else {
      setState(() {});
    }
  }

  static String _formatAmount(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  // ---------------------------------------------------------------------------
  // Computed
  // ---------------------------------------------------------------------------

  double get _inputAmount =>
      double.tryParse(_amountController.text.trim()) ?? 0;

  /// Amount actually applied to the current invoice. Capped at the invoice
  /// total because of the database CHECK `paid_amount <= total`.
  double _appliedToSale() {
    if (_method == PosPaymentMethod.credit) {
      return 0;
    }
    final double total = _cart.total;
    if (_inputAmount <= 0) {
      return 0;
    }
    return _inputAmount >= total ? total : _inputAmount;
  }

  /// Cash refunded to the customer when the input exceeds the invoice
  /// total. Always zero for card and credit.
  double _changeToCustomer() {
    if (_method != PosPaymentMethod.cash) {
      return 0;
    }
    final double excess = _inputAmount - _cart.total;
    return excess > 0 ? excess : 0;
  }

  /// Amount added to the customer's outstanding balance.
  double _addedToBalance() => _cart.total - _appliedToSale();

  /// Resulting balance after this sale.
  double _resultingBalance() =>
      _cart.customerBalance + _addedToBalance();

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  String? _validationError() {
    if (_cart.isEmpty) {
      return 'السلة فارغة. أضف منتجاً قبل الدفع.';
    }

    if (_method == PosPaymentMethod.credit) {
      if (!_cart.hasCustomer) {
        return 'البيع الآجل يتطلب اختيار عميل مسجل.';
      }
      return null;
    }

    if (_method == PosPaymentMethod.card) {
      if (_inputAmount < _cart.total) {
        return 'الدفع بالبطاقة يجب أن يغطي كامل قيمة الفاتورة.';
      }
      if (_inputAmount > _cart.total) {
        return 'الدفع بالبطاقة لا يُعيد باقياً.';
      }
      return null;
    }

    // Cash: partial payments require a registered customer.
    if (_addedToBalance() > 0 && !_cart.hasCustomer) {
      return 'الدفع الجزئي يتطلب اختيار عميل مسجل.';
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (_validationError() != null) {
      return;
    }

    final CompanyContextState contextState =
        ref.read(companyContextProvider);
    final String? branchId = contextState.currentBranch?.id;
    if (branchId == null) {
      setState(() => _serverFailure = SalesFailureType.branchNotFound);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _serverFailure = null;
    });

    final SalesNotifier notifier = ref.read(salesProvider.notifier);

    try {
      final Sale sale = await notifier.createSale(
        branchId: branchId,
        customerId: _cart.customerId,
        saleDate: DateTime.now(),
        items: <SaleItemDraft>[
          for (final PosCartLine line in _cart.lines)
            SaleItemDraft(
              productId: line.productId,
              unitId: line.unitId,
              quantity: line.quantity,
              unitPrice: line.unitPrice,
            ),
        ],
        discount: _cart.discount,
        taxAmount: _cart.taxAmount,
        paidAmount: _appliedToSale(),
      );

      final Sale confirmed = await notifier.confirmSale(sale.id);

      if (!mounted) {
        return;
      }

      // The cart is no longer needed; the receipt dialog works on the
      // captured snapshot.
      ref.read(posCartProvider.notifier).reset();

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => _PosReceiptDialog(
          sale: confirmed,
          lines: _cart.lines,
          customerName: _cart.customerName,
          previousBalance: _cart.customerBalance,
          change: _changeToCustomer(),
        ),
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on SaleException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _serverFailure = error.type;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _serverFailure = SalesFailureType.unknown;
      });
    }
  }

  void _selectMethod(String method) {
    setState(() {
      _method = method;
      _serverFailure = null;

      if (method == PosPaymentMethod.credit) {
        _amountController.text = '0';
      } else if (method == PosPaymentMethod.card) {
        _amountController.text = _formatAmount(_cart.total);
      } else if (_amountController.text.trim() == '0' ||
          _amountController.text.trim().isEmpty) {
        _amountController.text = _formatAmount(_cart.total);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final String? validationError = _validationError();
    final String? failureMessage = _serverFailure != null
        ? _failureMessageFor(_serverFailure!)
        : null;
    final String? displayError = failureMessage ?? validationError;
    final bool canSubmit = !_isSubmitting && validationError == null;

    final double change = _changeToCustomer();
    final double addedToBalance = _addedToBalance();
    final double resultingBalance = _resultingBalance();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // ---- Title ----
                Row(
                  children: <Widget>[
                    Text('الدفع', style: theme.textTheme.titleLarge),
                    const Spacer(),
                    IconButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                // ---- Customer ----
                _CustomerRow(customerName: _cart.customerName),

                // ---- Balance details or plain total ----
                if (_cart.hasCustomer && _cart.customerBalance > 0) ...<Widget>[
                  const SizedBox(height: 12),
                  _BalanceDetails(
                    previousBalance: _cart.customerBalance,
                    currentInvoice: _cart.total,
                    totalOwed: _cart.settlementTotal,
                  ),
                ] else ...<Widget>[
                  const SizedBox(height: 12),
                  _TotalBanner(total: _cart.total),
                ],

                const SizedBox(height: 16),

                // ---- Payment method ----
                Text('طريقة الدفع', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _MethodTile(
                        label: 'نقدي',
                        icon: Icons.payments_outlined,
                        selected: _method == PosPaymentMethod.cash,
                        enabled: !_isSubmitting,
                        onTap: () => _selectMethod(PosPaymentMethod.cash),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _MethodTile(
                        label: 'بطاقة',
                        icon: Icons.credit_card,
                        selected: _method == PosPaymentMethod.card,
                        enabled: !_isSubmitting,
                        onTap: () => _selectMethod(PosPaymentMethod.card),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _MethodTile(
                        label: 'آجل',
                        icon: Icons.schedule,
                        selected: _method == PosPaymentMethod.credit,
                        enabled: !_isSubmitting,
                        onTap: () => _selectMethod(PosPaymentMethod.credit),
                      ),
                    ),
                  ],
                ),

                // ---- Amount input (hidden for credit) ----
                if (_method != PosPaymentMethod.credit) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(
                    'المبلغ المدفوع',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  _AmountField(
                    controller: _amountController,
                    enabled: !_isSubmitting,
                    hasError: displayError != null,
                  ),
                ],

                // ---- Error ----
                if (displayError != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _ErrorBanner(message: displayError),
                ],

                // ---- Summary ----
                const SizedBox(height: 16),
                if (change > 0)
                  _SummaryLine(
                    label: 'الباقي للعميل',
                    value: _money.format(change),
                    emphasized: true,
                    color: scheme.primary,
                  ),
                if (addedToBalance > 0) ...<Widget>[
                  _SummaryLine(
                    label: 'سيُضاف للرصيد',
                    value: _money.format(addedToBalance),
                    color: scheme.error,
                  ),
                  _SummaryLine(
                    label: 'الرصيد الجديد للعميل',
                    value: _money.format(resultingBalance),
                    emphasized: true,
                    color: scheme.error,
                  ),
                ],
                if (change == 0 && addedToBalance == 0)
                  _SummaryLine(
                    label: 'الحالة',
                    value: 'مدفوع بالكامل',
                    emphasized: true,
                    color: scheme.primary,
                  ),

                const SizedBox(height: 20),

                // ---- Submit ----
                AppButton(
                  label: 'إتمام البيع',
                  icon: Icons.check_circle_outline,
                  expanded: true,
                  size: AppButtonSize.large,
                  isLoading: _isSubmitting,
                  onPressed: canSubmit ? _submit : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Sub-widgets
// ============================================================================

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.customerName});

  final String? customerName;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool hasCustomer = customerName != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(
              hasCustomer ? Icons.person : Icons.person_outline,
              color: scheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasCustomer ? customerName! : 'عميل نقدي',
                style: theme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceDetails extends StatelessWidget {
  const _BalanceDetails({
    required this.previousBalance,
    required this.currentInvoice,
    required this.totalOwed,
  });

  final double previousBalance;
  final double currentInvoice;
  final double totalOwed;

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _row(
              label: 'الرصيد السابق',
              value: _money.format(previousBalance),
              color: scheme.error,
            ),
            const SizedBox(height: 6),
            _row(
              label: 'قيمة الفاتورة',
              value: _money.format(currentInvoice),
            ),
            const Divider(height: 16),
            _row(
              label: 'الإجمالي المطلوب',
              value: _money.format(totalOwed),
              emphasized: true,
              color: scheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row({
    required String label,
    required String value,
    bool emphasized = false,
    Color? color,
  }) {
    final BuildContext context = _ctx!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: emphasized
                ? theme.textTheme.titleMedium
                : theme.textTheme.bodyMedium,
          ),
        ),
        Text(
          value,
          style: (emphasized
                  ? theme.textTheme.headlineSmall
                  : theme.textTheme.bodyLarge)
              ?.copyWith(
            color: color ?? scheme.onSurface,
            fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // Hack: to avoid threading a context through `_row`, we capture it here.
  static BuildContext? _ctx;
}

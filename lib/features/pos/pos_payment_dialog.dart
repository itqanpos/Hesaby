// lib/features/pos/pos_payment_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../shared/widgets/app_button.dart';
import '../companies/presentation/providers/company_context_provider.dart';
import '../companies/presentation/providers/company_context_state.dart';
import '../sales/domain/entities/sale_entities.dart';
import '../sales/domain/repositories/sales_repository.dart';
import '../sales/presentation/providers/sales_providers.dart';
import 'pos_cart.dart';

/// Enum-like constants for the payment methods offered at the POS.
abstract final class PosPaymentMethod {
  static const String cash = 'cash';
  static const String card = 'card';
  static const String credit = 'credit';
}

/// Opens the POS payment dialog.
///
/// Returns `true` when a sale was completed, `false` or `null` otherwise.
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
  final TextEditingController _amountController = TextEditingController();

  String _method = PosPaymentMethod.cash;
  bool _isSubmitting = false;
  SalesFailureType? _serverFailure;

  @override
  void initState() {
    super.initState();
    final PosCartState cart = ref.read(posCartProvider);
    _amountController.text = _formatAmount(cart.total);
    _amountController.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    // Clear the previous server error as soon as the user changes the amount.
    if (_serverFailure != null) {
      setState(() => _serverFailure = null);
    } else {
      setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // Formatting
  // ---------------------------------------------------------------------------

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );

  static String _formatAmount(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  // ---------------------------------------------------------------------------
  // Computed values
  // ---------------------------------------------------------------------------

  double get _inputAmount =>
      double.tryParse(_amountController.text.trim()) ?? 0;

  double _appliedToSale(PosCartState cart) {
    if (_method == PosPaymentMethod.credit) {
      return 0;
    }
    final double total = cart.total;
    if (_inputAmount <= 0) {
      return 0;
    }
    return _inputAmount > total ? total : _inputAmount;
  }

  double _change(PosCartState cart) {
    if (_method != PosPaymentMethod.cash) {
      return 0;
    }
    final double excess = _inputAmount - cart.total;
    return excess > 0 ? excess : 0;
  }

  double _addedToBalance(PosCartState cart) =>
      cart.total - _appliedToSale(cart);

  double _newBalance(PosCartState cart) =>
      cart.customerBalance + _addedToBalance(cart);

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  /// Returns a localized error message when the current input cannot be
  /// submitted, or `null` when the dialog is ready.
  String? _validationError(PosCartState cart) {
    if (cart.isEmpty) {
      return 'السلة فارغة. أضف منتجاً قبل الدفع.';
    }

    final double addedToBalance = _addedToBalance(cart);

    if (_method == PosPaymentMethod.credit) {
      if (!cart.hasCustomer) {
        return 'البيع الآجل يتطلب اختيار عميل مسجل.';
      }
      return null;
    }

    if (_method == PosPaymentMethod.card) {
      if (_inputAmount < cart.total) {
        return 'الدفع بالبطاقة يجب أن يغطي كامل المبلغ.';
      }
      if (_inputAmount > cart.total) {
        return 'الدفع بالبطاقة لا يُعيد باقياً.';
      }
      return null;
    }

    // Cash: partial payments require a registered customer.
    if (addedToBalance > 0 && !cart.hasCustomer) {
      return 'الدفع الجزئي يتطلب اختيار عميل مسجل.';
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final PosCartState cart = ref.read(posCartProvider);
    final String? validationError = _validationError(cart);
    if (validationError != null) {
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
        customerId: cart.customerId,
        saleDate: DateTime.now(),
        items: <SaleItemDraft>[
          for (final PosCartLine line in cart.lines)
            SaleItemDraft(
              productId: line.productId,
              unitId: line.unitId,
              quantity: line.quantity,
              unitPrice: line.unitPrice,
            ),
        ],
        discount: cart.discount,
        taxAmount: cart.taxAmount,
        paidAmount: _appliedToSale(cart),
      );

      final Sale confirmed = await notifier.confirmSale(sale.id);

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => _PosReceiptDialog(
          sale: confirmed,
          lines: cart.lines,
          customerName: cart.customerName,
          previousBalance: cart.customerBalance,
          change: _change(cart),
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

  // ---------------------------------------------------------------------------
  // Quick amounts
  // ---------------------------------------------------------------------------

  List<double> _quickAmounts(double total) {
    if (total <= 0) {
      return const <double>[];
    }
    final Set<double> set = <double>{total};
    set.add(_roundUp(total, 100));
    set.add(_roundUp(total, 500));
    set.add(_roundUp(total, 1000));
    final List<double> list = set.toList()..sort();
    return list.take(4).toList(growable: false);
  }

  static double _roundUp(double value, int step) {
    final double result = (value / step).ceil() * step.toDouble();
    return result == value ? value + step : result;
  }

  void _setAmount(double value) {
    _amountController.text = _formatAmount(value);
    _amountController.selection = TextSelection.collapsed(
      offset: _amountController.text.length,
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final PosCartState cart = ref.watch(posCartProvider);

    final String? validationError = _validationError(cart);
    final String? failureMessage = _serverFailure != null
        ? _failureMessageFor(_serverFailure!)
        : null;
    final String? displayError = failureMessage ?? validationError;

    final bool canSubmit = !_isSubmitting && validationError == null;

    final double change = _change(cart);
    final double addedToBalance = _addedToBalance(cart);
    final double newBalance = _newBalance(cart);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
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

                // ---- Customer + balance ----
                _CustomerRow(
                  customerName: cart.customerName,
                  balance: cart.customerBalance,
                  money: _money,
                ),

                const SizedBox(height: 16),

                // ---- Total ----
                _TotalBanner(total: cart.total, money: _money),

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
                        value: PosPaymentMethod.cash,
                        selected: _method == PosPaymentMethod.cash,
                        enabled: !_isSubmitting,
                        onTap: () => _selectMethod(PosPaymentMethod.cash, cart),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _MethodTile(
                        label: 'بطاقة',
                        icon: Icons.credit_card,
                        value: PosPaymentMethod.card,
                        selected: _method == PosPaymentMethod.card,
                        enabled: !_isSubmitting,
                        onTap: () => _selectMethod(PosPaymentMethod.card, cart),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _MethodTile(
                        label: 'آجل',
                        icon: Icons.schedule,
                        value: PosPaymentMethod.credit,
                        selected: _method == PosPaymentMethod.credit,
                        enabled: !_isSubmitting,
                        onTap: () =>
                            _selectMethod(PosPaymentMethod.credit, cart),
                      ),
                    ),
                  ],
                ),

                // ---- Amount input (hidden for credit) ----
                if (_method != PosPaymentMethod.credit) ...<Widget>[
                  const SizedBox(height: 16),
                  Text('المبلغ المدفوع',
                      style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  _AmountField(
                    controller: _amountController,
                    enabled: !_isSubmitting,
                    hasError: displayError != null,
                  ),
                  const SizedBox(height: 8),
                  _QuickAmounts(
                    amounts: _quickAmounts(cart.total),
                    money: _money,
                    enabled: !_isSubmitting,
                    onSelect: _setAmount,
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
                    label: 'الرصيد الجديد',
                    value: _money.format(newBalance),
                    emphasized: true,
                    color: scheme.error,
                  ),
                ],
                if (change == 0 && addedToBalance == 0)
                  _SummaryLine(
                    label: 'الحالة',
                    value: 'مدفوع بالكامل',
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

  void _selectMethod(String method, PosCartState cart) {
    setState(() {
      _method = method;
      _serverFailure = null;

      if (method == PosPaymentMethod.credit) {
        _amountController.text = '0';
      } else if (method == PosPaymentMethod.card) {
        _amountController.text = _formatAmount(cart.total);
      } else if (_amountController.text.trim() == '0' ||
          _amountController.text.trim().isEmpty) {
        _amountController.text = _formatAmount(cart.total);
      }
    });
  }
}

// ============================================================================
// Sub-widgets
// ============================================================================

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({
    required this.customerName,
    required this.balance,
    required this.money,
  });

  final String? customerName;
  final double balance;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool hasCustomer = customerName != null;
    final bool hasBalance = hasCustomer && balance > 0;

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
            if (hasBalance)
              Text(
                money.format(balance),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TotalBanner extends StatelessWidget {
  const _TotalBanner({required this.total, required this.money});

  final double total;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'الإجمالي المطلوب',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              money.format(total),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.label,
    required this.icon,
    required this.value,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final String value;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Material(
      color: selected
          ? scheme.primary
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                color: selected ? scheme.onPrimary : scheme.onSurface,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected ? scheme.onPrimary : scheme.onSurface,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.enabled,
    required this.hasError,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: true,
      textAlign: TextAlign.center,
      style: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: InputDecoration(
        hintText: '0',
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: hasError ? scheme.error : scheme.outline,
            width: hasError ? 2 : 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: hasError ? scheme.error : scheme.primary,
            width: 2,
          ),
        ),
      ),
    );
  }
}

class _QuickAmounts extends StatelessWidget {
  const _QuickAmounts({
    required this.amounts,
    required this.money,
    required this.enabled,
    required this.onSelect,
  });

  final List<double> amounts;
  final NumberFormat money;
  final bool enabled;
  final ValueChanged<double> onSelect;

  @override
  Widget build(BuildContext context) {
    if (amounts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final double amount in amounts)
          OutlinedButton(
            onPressed: enabled ? () => onSelect(amount) : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(72, 42),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: Text(
              money.format(amount),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.color,
  });

  final String label;
  final String value;
  final bool emphasized;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final TextStyle? labelStyle = emphasized
        ? theme.textTheme.titleMedium
        : theme.textTheme.bodyMedium;
    final TextStyle? valueStyle = emphasized
        ? theme.textTheme.headlineSmall
        : theme.textTheme.bodyLarge;

    final Color effectiveColor = color ?? scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: labelStyle?.copyWith(color: effectiveColor),
            ),
          ),
          Text(
            value,
            style: valueStyle?.copyWith(
              color: effectiveColor,
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.error_outline,
              color: scheme.onErrorContainer,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Receipt dialog
// ============================================================================

class _PosReceiptDialog extends StatelessWidget {
  const _PosReceiptDialog({
    required this.sale,
    required this.lines,
    required this.customerName,
    required this.previousBalance,
    required this.change,
  });

  final Sale sale;
  final List<PosCartLine> lines;
  final String? customerName;
  final double previousBalance;
  final double change;

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );
  static final DateFormat _dateTime = DateFormat.yMd('ar_EG').add_Hm();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double newBalance = previousBalance + sale.amountDue;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.check_circle,
                        color: scheme.primary, size: 32),
                    const SizedBox(width: 10),
                    Text(
                      'تم إتمام البيع',
                      style: theme.textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                if (sale.invoiceNumber != null)
                  Text(
                    'الإيصال: ${sale.invoiceNumber}',
                    style: theme.textTheme.bodyMedium,
                  ),
                Text(
                  _dateTime.format(sale.saleDate.toLocal()),
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  customerName ?? 'عميل نقدي',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),

                for (final PosCartLine line in lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            line.productName,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          '${_fmtQty(line.quantity)} × '
                          '${_money.format(line.unitPrice)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _money.format(line.lineTotal),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),

                _row(theme, 'المجموع الفرعي', _money.format(sale.subtotal)),
                if (sale.discount > 0)
                  _row(theme, 'الخصم', _money.format(sale.discount)),
                if (sale.taxAmount > 0)
                  _row(theme, 'الضريبة', _money.format(sale.taxAmount)),
                _row(theme, 'الإجمالي', _money.format(sale.total),
                    emphasized: true),
                _row(theme, 'المدفوع', _money.format(sale.paidAmount)),
                if (change > 0)
                  _row(theme, 'الباقي', _money.format(change),
                      color: scheme.primary),
                if (previousBalance > 0) ...<Widget>[
                  const SizedBox(height: 6),
                  _row(theme, 'الرصيد السابق',
                      _money.format(previousBalance),
                      color: scheme.error),
                  _row(theme, 'الرصيد الجديد',
                      _money.format(newBalance),
                      color: scheme.error,
                      emphasized: true),
                ],

                const SizedBox(height: 16),

                AppButton(
                  label: 'فاتورة جديدة',
                  icon: Icons.add,
                  expanded: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _fmtQty(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  Widget _row(
    ThemeData theme,
    String label,
    String value, {
    bool emphasized = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Text(
            value,
            style: (emphasized
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.bodyMedium)
                ?.copyWith(
              color: color ??
                  (emphasized ? theme.colorScheme.primary : null),
              fontWeight: emphasized ? FontWeight.w700 : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Localization
// ============================================================================

String _failureMessageFor(SalesFailureType type) => switch (type) {
      SalesFailureType.network =>
        'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.',
      SalesFailureType.unauthorized =>
        'انتهت صلاحية الجلسة. يرجى تسجيل الدخول مجددًا.',
      SalesFailureType.notFound => 'الفاتورة غير موجودة.',
      SalesFailureType.invalidStatusTransition =>
        'لا يمكن إتمام العملية في الحالة الحالية.',
      SalesFailureType.emptySale => 'لا يمكن إتمام بيع بدون بنود.',
      SalesFailureType.invoiceNumberConflict =>
        'رقم الفاتورة مستخدم بالفعل.',
      SalesFailureType.customerNotFound =>
        'البيع الآجل يتطلب اختيار عميل مسجل.',
      SalesFailureType.branchNotFound =>
        'الفرع غير متاح. يرجى إعادة اختياره.',
      SalesFailureType.productNotFound =>
        'أحد المنتجات غير متاح. يرجى إزالته وإعادة المحاولة.',
      SalesFailureType.unitNotFound =>
        'إحدى الوحدات غير متاحة.',
      SalesFailureType.insufficientStock =>
        'الرصيد غير كافٍ. يرجى تقليل الكمية أو تحديث المخزون.',
      SalesFailureType.invalidPayment =>
        'قيمة الدفع غير صحيحة. يرجى مراجعة المبلغ والطريقة.',
      SalesFailureType.invalidResponse =>
        'تعذّر قراءة البيانات. يرجى المحاولة مجددًا.',
      SalesFailureType.unknown =>
        'تعذّر إتمام البيع. يرجى المحاولة مرة أخرى.',
    };

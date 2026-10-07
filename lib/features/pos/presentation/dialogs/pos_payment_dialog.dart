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
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../domain/entities/pos_cart.dart';
import '../../domain/entities/pos_cart_line.dart';
import '../../domain/entities/receipt.dart';
import '../state/pos_providers.dart';
import 'pos_print_preview_dialog.dart';

/// Payment methods supported by the POS.
abstract final class PosPaymentMethod {
  static const String cash = 'cash';
  static const String card = 'card';
  static const String credit = 'credit';
}

/// Opens the POS payment sheet.
Future<bool?> showPosPaymentDialog({required BuildContext context}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) => const _PosPaymentSheet(),
  );
}

// ============================================================================
// Payment sheet
// ============================================================================

class _PosPaymentSheet extends ConsumerStatefulWidget {
  const _PosPaymentSheet();

  @override
  ConsumerState<_PosPaymentSheet> createState() => _PosPaymentSheetState();
}

class _PosPaymentSheetState extends ConsumerState<_PosPaymentSheet> {
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
    _cart = ref.read(posCartProvider);
    _amountController = TextEditingController(
      text: _formatAmount(_effectiveTotal),
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
    setState(() => _serverFailure = null);
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

  /// Default tax rate from company settings. `0` while loading.
  double get _defaultTaxRate => ref.read(defaultTaxRateProvider);

  /// Effective tax amount. When the cart already carries a manual tax
  /// amount (> 0), it wins; otherwise the default rate is applied to the
  /// post-discount subtotal.
  double get _effectiveTax {
    if (_cart.taxAmount > 0) return _cart.taxAmount;
    final double base = _cart.subtotal - _cart.discount;
    return base * _defaultTaxRate / 100;
  }

  /// Effective total including the effective tax.
  double get _effectiveTotal =>
      _cart.subtotal - _cart.discount + _effectiveTax;

  double _appliedToSale() {
    if (_method == PosPaymentMethod.credit) {
      return 0;
    }
    if (_inputAmount <= 0) {
      return 0;
    }
    final double total = _effectiveTotal;
    return _inputAmount >= total ? total : _inputAmount;
  }

  double _appliedToBalance() {
    if (_method == PosPaymentMethod.credit) {
      return 0;
    }
    if (!_cart.hasCustomer) {
      return 0;
    }
    final double excess = _inputAmount - _effectiveTotal;
    if (excess <= 0) {
      return 0;
    }
    final double balance = _cart.customerBalance;
    return excess >= balance ? balance : excess;
  }

  double _changeToCustomer() {
    if (_method != PosPaymentMethod.cash) {
      return 0;
    }
    final double excess = _inputAmount - _effectiveTotal;
    if (excess <= 0) {
      return 0;
    }
    final double remaining = excess - _appliedToBalance();
    return remaining > 0 ? remaining : 0;
  }

  double _addedToBalance() => _effectiveTotal - _appliedToSale();

  double _resultingBalance() =>
      _cart.customerBalance + _addedToBalance() - _appliedToBalance();

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
      if (_inputAmount < _effectiveTotal) {
        return 'الدفع بالبطاقة يجب أن يغطي كامل قيمة الفاتورة.';
      }
      final double maxAllowed = _effectiveTotal +
          (_cart.hasCustomer ? _cart.customerBalance : 0);
      if (_inputAmount > maxAllowed) {
        return 'المبلغ يتجاوز قيمة الفاتورة + الرصيد المستحق.';
      }
      return null;
    }
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
      final double appliedToSale = _appliedToSale();
      final double appliedToBalance = _appliedToBalance();

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
        taxAmount: _effectiveTax,
        paidAmount: appliedToSale,
      );

      final Sale confirmed = await notifier.confirmSale(sale.id);

      if (appliedToBalance > 0 && _cart.customerId != null) {
        await ref.read(customersProvider.notifier).recordPayment(
              customerId: _cart.customerId!,
              amount: appliedToBalance,
              method: _method == PosPaymentMethod.card ? 'card' : 'cash',
              notes: 'دفعة زيادة من فاتورة '
                  '${confirmed.invoiceNumber ?? confirmed.id}',
            );
      }

      if (!mounted) {
        return;
      }

      final Receipt receipt = _buildReceipt(
        sale: confirmed,
        contextState: contextState,
      );

      ref.read(posCartProvider.notifier).reset();

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) =>
            _PosReceiptDialog(receipt: receipt),
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

  Receipt _buildReceipt({
    required Sale sale,
    required CompanyContextState contextState,
  }) {
    final double newBalance = _resultingBalance();
    final bool hasBalanceChange = _cart.hasCustomer &&
        newBalance != _cart.customerBalance;

    return Receipt(
      saleId: sale.id,
      invoiceNumber: sale.invoiceNumber,
      dateTime: sale.saleDate,
      companyName: contextState.currentCompany?.name ?? '—',
      branchName: contextState.currentBranch?.name ?? '—',
      lines: <ReceiptLine>[
        for (final PosCartLine line in _cart.lines)
          ReceiptLine(
            productName: line.productName,
            unitName: line.unitName,
            quantity: line.quantity,
            unitPrice: line.unitPrice,
            lineTotal: line.lineTotal,
          ),
      ],
      subtotal: _cart.subtotal,
      discount: _cart.discount,
      taxAmount: _effectiveTax,
      total: _effectiveTotal,
      paidAmount: _appliedToSale(),
      change: _changeToCustomer(),
      customerName: _cart.customerName,
      previousBalance: hasBalanceChange ? _cart.customerBalance : null,
      newBalance: hasBalanceChange ? newBalance : null,
    );
  }

  void _selectMethod(String method) {
    setState(() {
      _method = method;
      _serverFailure = null;
      if (method == PosPaymentMethod.credit) {
        _amountController.text = '0';
      } else if (method == PosPaymentMethod.card) {
        _amountController.text = _formatAmount(_effectiveTotal);
      } else if (_amountController.text.trim() == '0' ||
          _amountController.text.trim().isEmpty) {
        _amountController.text = _formatAmount(_effectiveTotal);
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
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    final String? validationError = _validationError();
    final String? failureMessage = _serverFailure != null
        ? _failureMessageFor(_serverFailure!)
        : null;
    final String? displayError = failureMessage ?? validationError;
    final bool canSubmit = !_isSubmitting && validationError == null;

    final double change = _changeToCustomer();
    final double addedToBalance = _addedToBalance();
    final double appliedToBalance = _appliedToBalance();
    final double resultingBalance = _resultingBalance();

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(20),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

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

                  _CustomerRow(customerName: _cart.customerName),

                  const SizedBox(height: 12),

                  if (_cart.hasCustomer && _cart.customerBalance > 0) ...<Widget>[
                    _BalanceDetails(
                      previousBalance: _cart.customerBalance,
                      currentInvoice: _effectiveTotal,
                      totalOwed: _cart.customerBalance + _effectiveTotal,
                    ),
                  ] else ...<Widget>[
                    _TotalBanner(total: _effectiveTotal),
                  ],

                  const SizedBox(height: 16),

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
                          onTap: () =>
                              _selectMethod(PosPaymentMethod.credit),
                        ),
                      ),
                    ],
                  ),

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

                  if (displayError != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _ErrorBanner(message: displayError),
                  ],

                  const SizedBox(height: 16),
                  if (change > 0)
                    _SummaryLine(
                      label: 'الباقي للعميل',
                      value: _money.format(change),
                      emphasized: true,
                      color: scheme.primary,
                    ),
                  if (appliedToBalance > 0) ...<Widget>[
                    _SummaryLine(
                      label: 'مدفوع على الرصيد',
                      value: _money.format(appliedToBalance),
                      color: scheme.primary,
                    ),
                    _SummaryLine(
                      label: 'الرصيد الجديد للعميل',
                      value: _money.format(resultingBalance),
                      emphasized: true,
                      color: scheme.primary,
                    ),
                  ],
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
                  if (change == 0 &&
                      addedToBalance == 0 &&
                      appliedToBalance == 0)
                    _SummaryLine(
                      label: 'الحالة',
                      value: 'مدفوع بالكامل',
                      emphasized: true,
                      color: scheme.primary,
                    ),

                  const SizedBox(height: 20),

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
              context,
              label: 'الرصيد السابق',
              value: _money.format(previousBalance),
              color: scheme.error,
            ),
            const SizedBox(height: 6),
            _row(
              context,
              label: 'قيمة الفاتورة',
              value: _money.format(currentInvoice),
            ),
            const Divider(height: 16),
            _row(
              context,
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

  Widget _row(
    BuildContext context, {
    required String label,
    required String value,
    bool emphasized = false,
    Color? color,
  }) {
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
}

class _TotalBanner extends StatelessWidget {
  const _TotalBanner({required this.total});

  final double total;

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
              _money.format(total),
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
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerHighest,
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
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
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
  const _PosReceiptDialog({required this.receipt});

  final Receipt receipt;

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

    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
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

                if (receipt.invoiceNumber != null)
                  Text(
                    'الإيصال: ${receipt.invoiceNumber}',
                    style: theme.textTheme.bodyMedium,
                  ),
                Text(
                  _dateTime.format(receipt.dateTime.toLocal()),
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  receipt.customerName ?? 'عميل نقدي',
                  style: theme.textTheme.bodyMedium,
                ),

                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),

                for (final ReceiptLine line in receipt.lines)
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

                _row(theme, 'المجموع الفرعي',
                    _money.format(receipt.subtotal)),
                if (receipt.discount > 0)
                  _row(theme, 'الخصم', _money.format(receipt.discount)),
                if (receipt.taxAmount > 0)
                  _row(theme, 'الضريبة', _money.format(receipt.taxAmount)),
                _row(theme, 'الإجمالي', _money.format(receipt.total),
                    emphasized: true),
                _row(theme, 'المدفوع', _money.format(receipt.paidAmount)),
                if (receipt.hasChange)
                  _row(theme, 'الباقي', _money.format(receipt.change),
                      color: scheme.primary),

                if (receipt.hasBalanceChange) ...<Widget>[
                  const SizedBox(height: 6),
                  _row(theme, 'الرصيد السابق',
                      _money.format(receipt.previousBalance!),
                      color: scheme.error),
                  if (receipt.previousBalance! > receipt.newBalance!)
                    _row(
                      theme,
                      'مدفوع على الرصيد',
                      _money.format(
                        receipt.previousBalance! - receipt.newBalance!,
                      ),
                      color: scheme.primary,
                    ),
                  _row(theme, 'الرصيد الجديد',
                      _money.format(receipt.newBalance!),
                      color: scheme.error,
                      emphasized: true),
                ],

                const SizedBox(height: 16),

                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppButton(
                        label: 'طباعة',
                        icon: Icons.print_outlined,
                        onPressed: () => showPosPrintPreviewDialog(
                          context: context,
                          receipt: receipt,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppButton(
                        label: 'فاتورة جديدة',
                        icon: Icons.add,
                        variant: AppButtonVariant.outline,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
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
      SalesFailureType.unitNotFound => 'إحدى الوحدات غير متاحة.',
      SalesFailureType.insufficientStock =>
        'الرصيد غير كافٍ. يرجى تقليل الكمية أو تحديث المخزون.',
      SalesFailureType.invalidPayment =>
        'قيمة الدفع غير صحيحة. يرجى مراجعة المبلغ والطريقة.',
      SalesFailureType.invalidResponse =>
        'تعذّر قراءة البيانات. يرجى المحاولة مجددًا.',
      SalesFailureType.unknown =>
        'تعذّر إتمام البيع. يرجى المحاولة مرة أخرى.',
    };

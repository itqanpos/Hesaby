// lib/features/pos/presentation/dialogs/pos_payment_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/invalidation/data_invalidation.dart';
import '../../../../core/network/network_status_provider.dart';
import '../../../../core/network/offline_writer.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../cash/domain/entities/cash_entities.dart';
import '../../../cash/presentation/providers/cash_providers.dart';
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

abstract final class PosPaymentMethod {
  static const String cash = 'cash';
  static const String card = 'card';
  static const String credit = 'credit';
}

/// How to handle the excess when the customer pays more than the total owed.
enum ExcessAction {
  /// Return the excess to the customer as cash change.
  cash,

  /// Keep the excess as a credit on the customer's balance.
  balance,
}

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
  ExcessAction _excessAction = ExcessAction.cash;
  bool _isSubmitting = false;
  SalesFailureType? _serverFailure;

  @override
  void initState() {
    super.initState();
    _cart = ref.read(posCartProvider);
    // Default: pay the exact amount owed (sale + old balance).
    _amountController = TextEditingController(
      text: _formatAmount(_settlementTotal),
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
    if (!mounted) return;
    setState(() => _serverFailure = null);
  }

  static String _formatAmount(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  // ---------------------------------------------------------------------------
  // Core math — the only source of truth for this dialog
  // ---------------------------------------------------------------------------

  double get _input => double.tryParse(_amountController.text.trim()) ?? 0;

  /// Sale total = invoice value only.
  double get _saleTotal => _cart.total;

  /// Total owed by the customer = old balance + sale total.
  double get _settlementTotal => _cart.customerBalance + _saleTotal;

  /// Amount applied to the invoice (capped at [_saleTotal]).
  double get _paidOnSale {
    if (_method == PosPaymentMethod.credit) return 0;
    if (_input <= 0) return 0;
    return _input >= _saleTotal ? _saleTotal : _input;
  }

  /// Amount applied to the old balance (only for cash).
  double get _paidOnBalance {
    if (_method != PosPaymentMethod.cash) return 0;
    if (!_cart.hasCustomer) return 0;
    final double afterSale = _input - _paidOnSale;
    if (afterSale <= 0) return 0;
    final double balance = _cart.customerBalance;
    return afterSale >= balance ? balance : afterSale;
  }

  /// Cash to refund — nonzero only when the operator chose [ExcessAction.cash].
  double get _change {
    if (_method != PosPaymentMethod.cash) return 0;
    if (_excessAction != ExcessAction.cash) return 0;
    final double afterSale = _input - _paidOnSale;
    final double afterBalance = afterSale - _paidOnBalance;
    return afterBalance > 0 ? afterBalance : 0;
  }

  /// Amount added to the customer's balance — nonzero only when the
  /// operator chose [ExcessAction.balance], OR when the invoice is underpaid.
  double get _addedToBalance {
    // Part 1: unpaid remainder of the invoice.
    final double unpaidInvoice = _saleTotal - _paidOnSale;

    // Part 2: excess chosen to stay on the balance.
    double extraOnBalance = 0;
    if (_method == PosPaymentMethod.cash &&
        _excessAction == ExcessAction.balance) {
      final double afterSale = _input - _paidOnSale;
      final double afterBalance = afterSale - _paidOnBalance;
      if (afterBalance > 0) extraOnBalance = afterBalance;
    }

    return unpaidInvoice - extraOnBalance;
  }

  /// Customer's balance after the sale.
  /// Positive = customer owes us; negative = we owe the customer.
  double get _newBalance => _cart.customerBalance + _addedToBalance;

  bool get _hasBalanceChange =>
      _cart.hasCustomer && _newBalance != _cart.customerBalance;

  /// Whether the operator must decide where the excess goes.
  bool get _hasExcess => _method == PosPaymentMethod.cash &&
      _input > _settlementTotal;

  String? _paymentMethodForOffline() {
    if (_method == PosPaymentMethod.credit) return null;
    if (_method == PosPaymentMethod.card) return 'card';
    return 'cash';
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  String? _validationError() {
    if (_cart.isEmpty) return 'السلة فارغة. أضف منتجاً قبل الدفع.';

    if (_method == PosPaymentMethod.credit) {
      if (!_cart.hasCustomer) {
        return 'البيع الآجل يتطلب اختيار عميل مسجل.';
      }
      return null;
    }

    if (_method == PosPaymentMethod.card) {
      if (_input < _saleTotal) {
        return 'الدفع بالبطاقة يجب أن يغطي كامل قيمة الفاتورة.';
      }
      if (_input > _saleTotal) {
        return 'الدفع بالبطاقة لا يُعيد باقياً ولا يُضاف للرصيد.';
      }
      return null;
    }

    // Cash: partial payment requires a registered customer.
    if (_addedToBalance > 0 && !_cart.hasCustomer) {
      return 'الدفع الجزئي أو الزائد يتطلب اختيار عميل مسجل.';
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Submission
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_validationError() != null) return;

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

    final bool isOnline = ref.read(isOnlineProvider);
    if (!isOnline) {
      await _submitOffline(contextState: contextState, branchId: branchId);
      return;
    }

    await _submitOnline(contextState: contextState, branchId: branchId);
  }

  Future<void> _submitOnline({
    required CompanyContextState contextState,
    required String branchId,
  }) async {
    final SalesNotifier notifier = ref.read(salesProvider.notifier);

    try {
      final double paidOnSale = _paidOnSale;
      final double paidOnBalance = _paidOnBalance;

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
        paidAmount: paidOnSale,
      );

      final Sale confirmed = await notifier.confirmSale(sale.id);

      if (paidOnSale > 0) {
        final String method =
            _method == PosPaymentMethod.card ? 'card' : 'cash';
        await ref.read(cashRepositoryProvider).recordSalePayments(
              companyId: contextState.currentCompany?.id ?? '',
              saleId: confirmed.id,
              payments: <SalePaymentDraft>[
                SalePaymentDraft(amount: paidOnSale, method: method),
              ],
            );
      }

      if (paidOnBalance > 0 && _cart.customerId != null) {
        await ref.read(customersProvider.notifier).recordPayment(
              customerId: _cart.customerId!,
              amount: paidOnBalance,
              method: _method == PosPaymentMethod.card ? 'card' : 'cash',
              notes: 'دفعة زيادة من فاتورة '
                  '${confirmed.invoiceNumber ?? confirmed.id}',
            );
      }

      DataInvalidation.afterSale(ref);

      if (!mounted) return;

      final Receipt receipt = _buildReceipt(
        saleId: confirmed.id,
        invoiceNumber: confirmed.invoiceNumber,
        saleDate: confirmed.saleDate,
        contextState: contextState,
      );

      ref.read(posCartProvider.notifier).reset();

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) =>
            _PosReceiptDialog(receipt: receipt),
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SaleException catch (error) {
      if (error.type == SalesFailureType.network) {
        if (!mounted) return;
        await _submitOffline(
          contextState: contextState,
          branchId: branchId,
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _serverFailure = error.type;
      });
    } on Object {
      if (!mounted) return;
      await _submitOffline(
        contextState: contextState,
        branchId: branchId,
      );
    }
  }

  Future<void> _submitOffline({
    required CompanyContextState contextState,
    required String branchId,
  }) async {
    final List<Map<String, Object?>> items = <Map<String, Object?>>[
      for (final PosCartLine line in _cart.lines)
        <String, Object?>{
          'product_id': line.productId,
          'unit_id': line.unitId,
          'quantity': line.quantity,
          'unit_price': line.unitPrice,
          'notes': null,
        },
    ];

    final double paidOnSale = _paidOnSale;
    final double paidOnBalance = _paidOnBalance;
    final String? paymentMethod = _paymentMethodForOffline();

    final String? saleUuid = await OfflineWriter.enqueueSale(
      ref: ref,
      branchId: branchId,
      customerId: _cart.customerId,
      saleDate: DateTime.now(),
      items: items,
      discount: _cart.discount,
      taxAmount: _cart.taxAmount,
      paidAmount: paidOnSale,
      paymentMethod: paymentMethod,
      notes: null,
    );

    if (saleUuid == null) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _serverFailure = SalesFailureType.unknown;
      });
      return;
    }

    if (paidOnBalance > 0 && _cart.customerId != null) {
      await OfflineWriter.enqueueCustomerPayment(
        ref: ref,
        customerId: _cart.customerId!,
        amount: paidOnBalance,
        method: paymentMethod ?? 'cash',
        notes: 'دفعة زيادة من فاتورة أوفلاين',
      );
    }

    if (!mounted) return;

    final Receipt receipt = _buildReceipt(
      saleId: saleUuid,
      invoiceNumber: null,
      saleDate: DateTime.now(),
      contextState: contextState,
    );

    ref.read(posCartProvider.notifier).reset();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => _PosReceiptDialog(
        receipt: receipt,
        isOffline: true,
      ),
    );

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Receipt _buildReceipt({
    required String saleId,
    required String? invoiceNumber,
    required DateTime saleDate,
    required CompanyContextState contextState,
  }) {
    return Receipt(
      saleId: saleId,
      invoiceNumber: invoiceNumber,
      dateTime: saleDate,
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
      taxAmount: _cart.taxAmount,
      total: _saleTotal,
      paidAmount: _paidOnSale,
      change: _change,
      paidOnBalance: _paidOnBalance,
      customerName: _cart.customerName,
      previousBalance:
          _cart.hasCustomer ? _cart.customerBalance : null,
      newBalance: _cart.hasCustomer ? _newBalance : null,
      footer: ref.read(receiptFooterProvider),
    );
  }

  void _selectMethod(String method) {
    setState(() {
      _method = method;
      _serverFailure = null;
      if (method == PosPaymentMethod.credit) {
        _amountController.text = '0';
      } else if (method == PosPaymentMethod.card) {
        _amountController.text = _formatAmount(_saleTotal);
      } else {
        // Cash: default to full settlement.
        _amountController.text = _formatAmount(_settlementTotal);
      }
    });
  }

  void _selectExcessAction(ExcessAction action) {
    setState(() {
      _excessAction = action;
      _serverFailure = null;
    });
  }

  // ---------------------------------------------------------------------------
  // UI
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
                  _TotalsCard(
                    saleTotal: _saleTotal,
                    customerBalance: _cart.customerBalance,
                    hasCustomer: _cart.hasCustomer,
                  ),
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
                    Text('المبلغ المدفوع',
                        style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    _AmountField(
                      controller: _amountController,
                      enabled: !_isSubmitting,
                      hasError: displayError != null,
                    ),
                  ],
                  if (_hasExcess) ...<Widget>[
                    const SizedBox(height: 12),
                    _ExcessChooser(
                      excess: _input - _settlementTotal,
                      action: _excessAction,
                      onChanged: _selectExcessAction,
                      enabled: !_isSubmitting,
                    ),
                  ],
                  if (displayError != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _ErrorBanner(message: displayError),
                  ],
                  const SizedBox(height: 16),
                  _SummaryBlock(
                    saleTotal: _saleTotal,
                    input: _input,
                    method: _method,
                    hasCustomer: _cart.hasCustomer,
                    customerBalance: _cart.customerBalance,
                    paidOnSale: _paidOnSale,
                    paidOnBalance: _paidOnBalance,
                    change: _change,
                    addedToBalance: _addedToBalance,
                    newBalance: _newBalance,
                    excessAction: _excessAction,
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

/// Shows the invoice total, the old balance (if any), and the total owed.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({
    required this.saleTotal,
    required this.customerBalance,
    required this.hasCustomer,
  });

  final double saleTotal;
  final double customerBalance;
  final bool hasCustomer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool showBalance = hasCustomer && customerBalance > 0;
    final double total = showBalance ? customerBalance + saleTotal : saleTotal;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: showBalance
            ? scheme.surfaceContainerHighest
            : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        child: showBalance
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _row(context, 'الرصيد السابق',
                      AppFormatters.money(customerBalance),
                      color: scheme.error),
                  const SizedBox(height: 6),
                  _row(context, 'قيمة الفاتورة',
                      AppFormatters.money(saleTotal)),
                  const Divider(height: 16),
                  _row(context, 'الإجمالي المطلوب',
                      AppFormatters.money(total),
                      emphasized: true,
                      color: scheme.primary),
                ],
              )
            : Column(
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
                    AppFormatters.money(total),
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

  Widget _row(
    BuildContext context,
    String label,
    String value, {
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

/// Let the operator choose where the excess goes.
class _ExcessChooser extends StatelessWidget {
  const _ExcessChooser({
    required this.excess,
    required this.action,
    required this.onChanged,
    required this.enabled,
  });

  final double excess;
  final ExcessAction action;
  final ValueChanged<ExcessAction> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.tertiary.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.info_outline,
                    size: 18, color: scheme.onTertiaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'الزائد: ${AppFormatters.money(excess)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onTertiaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            RadioListTile<ExcessAction>(
              value: ExcessAction.cash,
              groupValue: action,
              onChanged: enabled
                  ? (ExcessAction? v) {
                      if (v != null) onChanged(v);
                    }
                  : null,
              title: const Text('إرجاع نقدي للعميل'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            RadioListTile<ExcessAction>(
              value: ExcessAction.balance,
              groupValue: action,
              onChanged: enabled
                  ? (ExcessAction? v) {
                      if (v != null) onChanged(v);
                    }
                  : null,
              title: const Text('إضافته إلى رصيد العميل'),
              dense: true,
              contentPadding: EdgeInsets.zero,
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

/// Summary shown before the user presses "إتمام البيع".
class _SummaryBlock extends StatelessWidget {
  const _SummaryBlock({
    required this.saleTotal,
    required this.input,
    required this.method,
    required this.hasCustomer,
    required this.customerBalance,
    required this.paidOnSale,
    required this.paidOnBalance,
    required this.change,
    required this.addedToBalance,
    required this.newBalance,
    required this.excessAction,
  });

  final double saleTotal;
  final double input;
  final String method;
  final bool hasCustomer;
  final double customerBalance;
  final double paidOnSale;
  final double paidOnBalance;
  final double change;
  final double addedToBalance;
  final double newBalance;
  final ExcessAction excessAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool showBalance = hasCustomer;
    final List<Widget> rows = <Widget>[];

    // Cash + card: show paid + change.
    if (method != PosPaymentMethod.credit) {
      rows.add(_SummaryLine(
        label: 'المدفوع',
        value: AppFormatters.money(input),
      ));
    }

    if (change > 0) {
      rows.add(_SummaryLine(
        label: 'الباقي للعميل (نقدي)',
        value: AppFormatters.money(change),
        emphasized: true,
        color: scheme.primary,
      ));
    }

    if (showBalance && paidOnBalance > 0) {
      rows.add(_SummaryLine(
        label: 'مسدد من الرصيد السابق',
        value: AppFormatters.money(paidOnBalance),
        color: scheme.primary,
      ));
    }

    if (showBalance) {
      rows.add(const Divider(height: 16));
      rows.add(_SummaryLine(
        label: 'الرصيد السابق',
        value: AppFormatters.money(customerBalance),
        color: scheme.error,
      ));

      final String balanceLabel;
      final Color balanceColor;
      if (newBalance > 0) {
        balanceLabel = 'الرصيد الجديد (مدين)';
        balanceColor = scheme.error;
      } else if (newBalance < 0) {
        balanceLabel = 'الرصيد الجديد (دائن)';
        balanceColor = scheme.primary;
      } else {
        balanceLabel = 'الرصيد الجديد';
        balanceColor = scheme.primary;
      }

      rows.add(_SummaryLine(
        label: balanceLabel,
        value: AppFormatters.money(newBalance.abs()),
        emphasized: true,
        color: balanceColor,
      ));
    }

    if (rows.isEmpty) {
      rows.add(_SummaryLine(
        label: 'الحالة',
        value: 'مدفوع بالكامل',
        emphasized: true,
        color: scheme.primary,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
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

class _PosReceiptDialog extends ConsumerWidget {
  const _PosReceiptDialog({
    required this.receipt,
    this.isOffline = false,
  });

  final Receipt receipt;
  final bool isOffline;

  Future<void> _handlePrint(BuildContext context, WidgetRef ref) async {
    if (!context.mounted) return;
    await showPosPrintPreviewDialog(
      context: context,
      receipt: receipt,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    Icon(
                      isOffline
                          ? Icons.cloud_off_outlined
                          : Icons.check_circle,
                      color: scheme.primary,
                      size: 32,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isOffline
                            ? 'تم حفظ البيع محليًا'
                            : 'تم إتمام البيع',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),

                if (isOffline) ...<Widget>[
                  const SizedBox(height: 10),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.schedule,
                            size: 18,
                            color: scheme.onTertiaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'سيُرسل تلقائيًا عند عودة الاتصال. '
                              'رقم الفاتورة سيُحدَّد على الخادم.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onTertiaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),

                if (!isOffline && receipt.invoiceNumber != null)
                  Text(
                    'الإيصال: ${receipt.invoiceNumber}',
                    style: theme.textTheme.bodyMedium,
                  ),
                Text(
                  AppFormatters.dateTime(receipt.dateTime),
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
                          '${AppFormatters.quantity(line.quantity)} × '
                          '${AppFormatters.money(line.unitPrice)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppFormatters.money(line.lineTotal),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),

                _row(theme, 'المجموع الفرعي',
                    AppFormatters.money(receipt.subtotal)),
                if (receipt.discount > 0)
                  _row(theme, 'الخصم',
                      AppFormatters.money(receipt.discount)),
                if (receipt.taxAmount > 0)
                  _row(theme, 'الضريبة',
                      AppFormatters.money(receipt.taxAmount)),
                _row(theme, 'الإجمالي',
                    AppFormatters.money(receipt.total),
                    emphasized: true),
                _row(theme, 'المدفوع',
                    AppFormatters.money(receipt.paidAmount)),
                if (receipt.hasChange)
                  _row(theme, 'الباقي للعميل',
                      AppFormatters.money(receipt.change),
                      color: scheme.primary),

                if (receipt.hasBalanceChange) ...<Widget>[
                  const SizedBox(height: 6),
                  _row(theme, 'الرصيد السابق',
                      AppFormatters.money(receipt.previousBalance!),
                      color: scheme.error),
                  if (receipt.hasBalancePayment)
                    _row(
                      theme,
                      'مسدد من الرصيد السابق',
                      AppFormatters.money(receipt.paidOnBalance),
                      color: scheme.primary,
                    ),
                  _row(
                    theme,
                    (receipt.newBalance ?? 0) < 0
                        ? 'الرصيد الجديد (دائن)'
                        : 'الرصيد الجديد',
                    AppFormatters.money(
                      (receipt.newBalance ?? 0).abs(),
                    ),
                    color: (receipt.newBalance ?? 0) < 0
                        ? scheme.primary
                        : scheme.error,
                    emphasized: true,
                  ),
                ],

                const SizedBox(height: 16),

                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppButton(
                        label: 'طباعة',
                        icon: Icons.print_outlined,
                        onPressed: () => _handlePrint(context, ref),
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

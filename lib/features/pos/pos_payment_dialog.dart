// lib/features/pos/pos_payment_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
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
/// Returns:
/// * `true` when a sale was completed successfully.
/// * `false` or `null` when the dialog was dismissed without completing.
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
  SalesFailureType? _failureType;

  @override
  void initState() {
    super.initState();
    final PosCartState cart = ref.read(posCartProvider);
    _amountController.text = _formatNumber(cart.total);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  static String _formatNumber(double value) {
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

  /// Amount actually applied to the current invoice. Capped at the invoice
  /// total because of the database CHECK `paid_amount <= total`.
  double _appliedToSale(PosCartState cart) {
    if (_method == PosPaymentMethod.credit) {
      return 0;
    }
    final double total = cart.total;
    if (_inputAmount < 0) {
      return 0;
    }
    return _inputAmount > total ? total : _inputAmount;
  }

  /// Change to return to the customer (cash only).
  double _change(PosCartState cart) {
    if (_method != PosPaymentMethod.cash) {
      return 0;
    }
    final double excess = _inputAmount - cart.total;
    return excess > 0 ? excess : 0;
  }

  /// Amount that will be added to the customer balance.
  double _addedToBalance(PosCartState cart) {
    return cart.total - _appliedToSale(cart);
  }

  /// New customer balance after the sale.
  double _newBalance(PosCartState cart) {
    return cart.customerBalance + _addedToBalance(cart);
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  bool _isValid(PosCartState cart) {
    if (cart.isEmpty) {
      return false;
    }
    if (_method == PosPaymentMethod.credit && !cart.hasCustomer) {
      // A credit sale without a registered customer cannot be recorded.
      return false;
    }
    if (_method == PosPaymentMethod.card && _inputAmount > cart.total) {
      // Card cannot produce change.
      return false;
    }
    if (_addedToBalance(cart) > 0 && !cart.hasCustomer) {
      // Partial / credit / unpaid amounts require a registered customer.
      return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final PosCartState cart = ref.read(posCartProvider);
    if (!_isValid(cart)) {
      setState(() {
        _failureType = _method == PosPaymentMethod.credit && !cart.hasCustomer
            ? SalesFailureType.customerNotFound
            : SalesFailureType.invalidPayment;
      });
      return;
    }

    final CompanyContextState contextState =
        ref.read(companyContextProvider);
    final String? branchId = contextState.currentBranch?.id;
    if (branchId == null) {
      setState(() => _failureType = SalesFailureType.branchNotFound);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _failureType = null;
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
        _failureType = error.type;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _failureType = SalesFailureType.unknown;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final PosCartState cart = ref.watch(posCartProvider);
    final NumberFormat money = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

    final double applied = _appliedToSale(cart);
    final double change = _change(cart);
    final double addedToBalance = _addedToBalance(cart);
    final double newBalance = _newBalance(cart);
    final bool valid = _isValid(cart);
    final SalesFailureType? failure = _failureType;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
                    Text(
                      'الدفع',
                      style: theme.textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // ---- Customer ----
                Row(
                  children: <Widget>[
                    Icon(Icons.person_outline, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cart.customerName ?? 'عميل نقدي',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),

                if (cart.hasCustomer && cart.customerBalance > 0) ...<Widget>[
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  _kv(theme, 'الرصيد السابق',
                      money.format(cart.customerBalance),
                      color: scheme.error),
                  _kv(theme, 'الفاتورة الحالية', money.format(cart.total)),
                  const SizedBox(height: 6),
                  _kv(theme, 'الإجمالي المطلوب',
                      money.format(cart.settlementTotal),
                      emphasized: true),
                ] else ...<Widget>[
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  _kv(theme, 'إجمالي الفاتورة', money.format(cart.total),
                      emphasized: true),
                ],

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // ---- Method ----
                Text('طريقة الدفع', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _methodTile(
                        context,
                        label: 'نقدي',
                        icon: Icons.payments_outlined,
                        value: PosPaymentMethod.cash,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _methodTile(
                        context,
                        label: 'بطاقة',
                        icon: Icons.credit_card,
                        value: PosPaymentMethod.card,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _methodTile(
                        context,
                        label: 'آجل',
                        icon: Icons.schedule,
                        value: PosPaymentMethod.credit,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // ---- Amount ----
                if (_method != PosPaymentMethod.credit) ...<Widget>[
                  Text('المبلغ المدفوع',
                      style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  AppTextField(
                    controller: _amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    enabled: !_isSubmitting,
                    onChanged: (String _) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _quick(context, cart.total, label: 'كامل'),
                      _quick(context, 50),
                      _quick(context, 100),
                      _quick(context, 200),
                      _quick(context, 500),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                const Divider(height: 1),
                const SizedBox(height: 12),

                // ---- Summary ----
                if (_method != PosPaymentMethod.credit) ...<Widget>[
                  _kv(theme, 'المدفوع الآن', money.format(applied)),
                  if (change > 0)
                    _kv(theme, 'الباقي للعميل', money.format(change),
                        color: scheme.primary),
                ],
                if (addedToBalance > 0) ...<Widget>[
                  const SizedBox(height: 4),
                  _kv(theme, 'سيُضاف للرصيد',
                      money.format(addedToBalance),
                      color: scheme.error),
                  _kv(theme, 'الرصيد الجديد',
                      money.format(newBalance),
                      emphasized: true),
                ],

                if (failure != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _failureBanner(context, _failureMessage(failure)),
                ],

                const SizedBox(height: 16),

                // ---- Confirm ----
                AppButton(
                  label: 'إتمام البيع',
                  icon: Icons.check_circle_outline,
                  expanded: true,
                  size: AppButtonSize.large,
                  isLoading: _isSubmitting,
                  onPressed: _isSubmitting || !valid ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Widget helpers
  // ---------------------------------------------------------------------------

  Widget _methodTile(
    BuildContext context, {
    required String label,
    required IconData icon,
    required String value,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool selected = _method == value;

    return Material(
      color: selected
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _isSubmitting
            ? null
            : () {
                setState(() {
                  _method = value;
                  if (value == PosPaymentMethod.credit) {
                    _amountController.text = '0';
                  } else if (_amountController.text.trim() == '0' ||
                      _amountController.text.trim().isEmpty) {
                    _amountController.text = _formatNumber(
                      ref.read(posCartProvider).total,
                    );
                  }
                });
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurface,
                  fontWeight: selected ? FontWeight.w700 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quick(BuildContext context, double value, {String? label}) {
    final PosCartState cart = ref.read(posCartProvider);
    final NumberFormat money = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 0,
    );
    return OutlinedButton(
      onPressed: _isSubmitting
          ? null
          : () {
              setState(() {
                _amountController.text = _formatNumber(
                  label == 'كامل'
                      ? cart.total
                      : (_inputAmount + value),
                );
              });
            },
      child: Text(label ?? money.format(value)),
    );
  }

  Widget _kv(
    ThemeData theme,
    String label,
    String value, {
    bool emphasized = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
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

  Widget _failureBanner(BuildContext context, String message) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final NumberFormat money = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );
    final DateFormat dateTime = DateFormat.yMd('ar_EG').add_Hm();

    final double newBalance = previousBalance + sale.amountDue;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
                    const SizedBox(width: 8),
                    Text(
                      'تم إتمام البيع',
                      style: theme.textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
                if (sale.invoiceNumber != null)
                  Text(
                    'الإيصال: ${sale.invoiceNumber}',
                    style: theme.textTheme.bodyMedium,
                  ),
                Text(
                  dateTime.format(sale.saleDate.toLocal()),
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  customerName ?? 'عميل نقدي',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),

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
                          '${_fmtQty(line.quantity)} × ${money.format(line.unitPrice)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          money.format(line.lineTotal),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),

                _row(theme, 'المجموع الفرعي', money.format(sale.subtotal)),
                if (sale.discount > 0)
                  _row(theme, 'الخصم', money.format(sale.discount)),
                if (sale.taxAmount > 0)
                  _row(theme, 'الضريبة', money.format(sale.taxAmount)),
                _row(theme, 'الإجمالي', money.format(sale.total),
                    emphasized: true),
                _row(theme, 'المدفوع', money.format(sale.paidAmount)),
                if (change > 0)
                  _row(theme, 'الباقي', money.format(change),
                      color: scheme.primary),
                if (previousBalance > 0) ...<Widget>[
                  const SizedBox(height: 4),
                  _row(theme, 'الرصيد السابق',
                      money.format(previousBalance),
                      color: scheme.error),
                  _row(theme, 'الرصيد الجديد',
                      money.format(newBalance),
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
// Localization helpers
// ============================================================================

String _failureMessage(SalesFailureType type) => switch (type) {
      SalesFailureType.network =>
        'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.',
      SalesFailureType.unauthorized =>
        'انتهت صلاحية الجلسة أو لا تملك صلاحية. يرجى تسجيل الدخول مجددًا.',
      SalesFailureType.notFound => 'الفاتورة المطلوبة غير موجودة.',
      SalesFailureType.invalidStatusTransition =>
        'لا يمكن إتمام العملية على الفاتورة في حالتها الحالية.',
      SalesFailureType.emptySale =>
        'لا يمكن إتمام بيع بدون بنود.',
      SalesFailureType.invoiceNumberConflict =>
        'يوجد فاتورة أخرى بنفس الرقم في هذه الشركة.',
      SalesFailureType.customerNotFound =>
        'البيع الآجل أو الجزئي يتطلب عميلًا مسجلًا.',
      SalesFailureType.branchNotFound =>
        'الفرع المختار غير متاح. يرجى إعادة اختياره.',
      SalesFailureType.productNotFound =>
        'أحد المنتجات المختارة غير متاح.',
      SalesFailureType.unitNotFound =>
        'إحدى الوحدات المختارة غير متاحة.',
      SalesFailureType.insufficientStock =>
        'الرصيد غير كافٍ. يرجى تقليل الكمية أو تأكيد الإدخال في المخزون.',
      SalesFailureType.invalidPayment =>
        'قيمة الدفع غير صحيحة. يرجى مراجعة المبلغ والطريقة.',
      SalesFailureType.invalidResponse =>
        'القيم المُدخلة غير صحيحة. يرجى التحقق من الكميات والأسعار.',
      SalesFailureType.unknown =>
        'تعذّر إتمام البيع. يرجى المحاولة مرة أخرى.',
    };

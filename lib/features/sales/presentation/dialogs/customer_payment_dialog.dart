// lib/features/sales/presentation/dialogs/customer_payment_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/entities/customer_payment.dart';
import '../../domain/entities/sale_entities.dart';
import '../../domain/repositories/sales_repository.dart';
import '../providers/sales_providers.dart';

/// Opens the customer-payment dialog.
///
/// Returns the updated [Customer] when the payment was successfully
/// recorded, or `null` when the cashier cancelled. The caller is expected
/// to keep any in-memory copy of the customer in sync with the returned
/// value (for example the POS cart's balance snapshot).
///
/// The dialog is a bottom sheet so it can be reused both from the POS
/// actions sheet and from any future customer-facing screen without
/// depending on POS-specific widgets.
Future<Customer?> showCustomerPaymentDialog({
  required BuildContext context,
  required String customerId,
  required String customerName,
  required double currentBalance,
}) {
  return showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) => _CustomerPaymentSheet(
      customerId: customerId,
      customerName: customerName,
      currentBalance: currentBalance,
    ),
  );
}

// ============================================================================
// Sheet
// ============================================================================

class _CustomerPaymentSheet extends ConsumerStatefulWidget {
  const _CustomerPaymentSheet({
    required this.customerId,
    required this.customerName,
    required this.currentBalance,
  });

  final String customerId;
  final String customerName;
  final double currentBalance;

  @override
  ConsumerState<_CustomerPaymentSheet> createState() =>
      _CustomerPaymentSheetState();
}

class _CustomerPaymentSheetState
    extends ConsumerState<_CustomerPaymentSheet> {
  late final TextEditingController _amountController;
  late final TextEditingController _referenceController;
  late final TextEditingController _notesController;

  String _method = PaymentMethod.cash;
  bool _isSubmitting = false;
  CustomerFailureType? _serverFailure;

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: _formatAmount(widget.currentBalance),
    );
    _referenceController = TextEditingController();
    _notesController = TextEditingController();
    _amountController.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
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

  double get _remainingBalance {
    final double remaining = widget.currentBalance - _inputAmount;
    return remaining < 0 ? 0 : remaining;
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  String? _validationError() {
    if (widget.currentBalance <= 0) {
      return 'لا يوجد رصيد مستحق على هذا العميل.';
    }
    if (_inputAmount <= 0) {
      return 'المبلغ يجب أن يكون أكبر من صفر.';
    }
    if (_inputAmount > widget.currentBalance) {
      return 'المبلغ يتجاوز الرصيد الحالي.';
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

    setState(() {
      _isSubmitting = true;
      _serverFailure = null;
    });

    final String? reference = _referenceController.text.trim().isEmpty
        ? null
        : _referenceController.text.trim();
    final String? notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();

    try {
      await ref.read(customersProvider.notifier).recordPayment(
            customerId: widget.customerId,
            amount: _inputAmount,
            method: _method,
            reference: reference,
            notes: notes,
          );

      // Fetch the fresh customer directly from the repository so the
      // returned balance is guaranteed to reflect the DB trigger's
      // update, independent of any in-memory list timing.
      final Customer updated = await ref
          .read(customerRepositoryProvider)
          .getCustomer(widget.customerId);

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(updated);
    } on CustomerException catch (error) {
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
        _serverFailure = CustomerFailureType.unknown;
      });
    }
  }

  void _selectMethod(String method) {
    setState(() {
      _method = method;
      _serverFailure = null;
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

    final double remaining = _remainingBalance;

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
                      Text(
                        'تحصيل من العميل',
                        style: theme.textTheme.titleLarge,
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _isSubmitting
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),

                  _CustomerBanner(
                    customerName: widget.customerName,
                    currentBalance: widget.currentBalance,
                    money: _money,
                  ),

                  const SizedBox(height: 16),

                  Text('المبلغ المحصَّل', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  _AmountField(
                    controller: _amountController,
                    enabled: !_isSubmitting,
                    hasError: displayError != null,
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
                          selected: _method == PaymentMethod.cash,
                          enabled: !_isSubmitting,
                          onTap: () => _selectMethod(PaymentMethod.cash),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _MethodTile(
                          label: 'بطاقة',
                          icon: Icons.credit_card,
                          selected: _method == PaymentMethod.card,
                          enabled: !_isSubmitting,
                          onTap: () => _selectMethod(PaymentMethod.card),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _MethodTile(
                          label: 'تحويل',
                          icon: Icons.account_balance_outlined,
                          selected: _method == PaymentMethod.transfer,
                          enabled: !_isSubmitting,
                          onTap: () => _selectMethod(PaymentMethod.transfer),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  AppTextField(
                    controller: _referenceController,
                    label: 'المرجع — اختياري',
                    hint: 'مثال: RC-2026-001',
                    enabled: !_isSubmitting,
                  ),

                  const SizedBox(height: 12),

                  AppTextField(
                    controller: _notesController,
                    label: 'ملاحظات — اختياري',
                    enabled: !_isSubmitting,
                    maxLines: 2,
                  ),

                  if (displayError != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _ErrorBanner(message: displayError),
                  ],

                  const SizedBox(height: 16),

                  _SummaryLine(
                    label: 'الرصيد الحالي',
                    value: _money.format(widget.currentBalance),
                  ),
                  _SummaryLine(
                    label: 'المبلغ المحصَّل',
                    value: _money.format(
                      _inputAmount < 0 ? 0 : _inputAmount,
                    ),
                    color: scheme.primary,
                  ),
                  _SummaryLine(
                    label: 'الرصيد بعد التحصيل',
                    value: _money.format(remaining),
                    emphasized: true,
                  ),

                  const SizedBox(height: 20),

                  AppButton(
                    label: 'تسجيل الدفعة',
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

class _CustomerBanner extends StatelessWidget {
  const _CustomerBanner({
    required this.customerName,
    required this.currentBalance,
    required this.money,
  });

  final String customerName;
  final double currentBalance;
  final NumberFormat money;

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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: const Icon(Icons.person_outline),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    customerName,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'الرصيد الحالي: ${money.format(currentBalance)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
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
        suffixText: 'ج.م',
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
// Localization
// ============================================================================

String _failureMessageFor(CustomerFailureType type) {
  switch (type) {
    case CustomerFailureType.network:
      return 'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.';
    case CustomerFailureType.unauthorized:
      return 'انتهت صلاحية الجلسة. يرجى تسجيل الدخول مجددًا.';
    case CustomerFailureType.notFound:
      return 'العميل المطلوب غير موجود أو تم حذفه.';
    case CustomerFailureType.nameConflict:
      return 'يوجد عميل آخر بنفس الاسم.';
    case CustomerFailureType.codeConflict:
      return 'يوجد عميل آخر بنفس الكود.';
    case CustomerFailureType.phoneConflict:
      return 'يوجد عميل آخر بنفس رقم الهاتف.';
    case CustomerFailureType.inUse:
      return 'العميل مرتبط بفواتير ولا يمكن تعديل بياناته.';
    case CustomerFailureType.invalidAmount:
      return 'المبلغ غير صالح. يرجى مراجعة القيمة.';
    case CustomerFailureType.insufficientBalance:
      return 'الرصيد غير كافٍ لإتمام العملية.';
    case CustomerFailureType.invalidResponse:
      return 'تعذّر قراءة البيانات. يرجى المحاولة مجددًا.';
    case CustomerFailureType.unknown:
      return 'تعذّر تسجيل الدفعة. يرجى المحاولة مرة أخرى.';
  }
}

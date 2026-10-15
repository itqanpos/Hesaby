// lib/features/sales/presentation/dialogs/customer_adjustment_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/entities/customer_adjustment.dart';
import '../../domain/entities/customer_payment.dart';
import '../../domain/entities/sale_entities.dart';
import '../../domain/repositories/sales_repository.dart';
import '../providers/sales_providers.dart';

/// The three operations the adjustment sheet can perform.
enum _AdjustmentMode {
  increase,
  decrease,
  collect,
}

Future<Customer?> showCustomerAdjustmentDialog({
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
    builder: (BuildContext sheetContext) => _CustomerAdjustmentSheet(
      customerId: customerId,
      customerName: customerName,
      currentBalance: currentBalance,
    ),
  );
}

class _CustomerAdjustmentSheet extends ConsumerStatefulWidget {
  const _CustomerAdjustmentSheet({
    required this.customerId,
    required this.customerName,
    required this.currentBalance,
  });

  final String customerId;
  final String customerName;
  final double currentBalance;

  @override
  ConsumerState<_CustomerAdjustmentSheet> createState() =>
      _CustomerAdjustmentSheetState();
}

class _CustomerAdjustmentSheetState
    extends ConsumerState<_CustomerAdjustmentSheet> {
  late final TextEditingController _amountController;
  late final TextEditingController _notesController;
  late final TextEditingController _referenceController;

  _AdjustmentMode _mode = _AdjustmentMode.increase;
  String _reason = AdjustmentReason.openingBalance;
  String _paymentMethod = PaymentMethod.cash;

  bool _isSubmitting = false;
  CustomerFailureType? _serverFailure;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    _notesController = TextEditingController();
    _referenceController = TextEditingController();
    _amountController.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    _notesController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    if (!mounted) {
      return;
    }
    setState(() => _serverFailure = null);
  }

  double get _inputAmount =>
      double.tryParse(_amountController.text.trim()) ?? 0;

  double get _signedAmount {
    switch (_mode) {
      case _AdjustmentMode.increase:
        return _inputAmount;
      case _AdjustmentMode.decrease:
      case _AdjustmentMode.collect:
        return -_inputAmount;
    }
  }

  double get _resultingBalance => widget.currentBalance + _signedAmount;

  String? _validationError() {
    if (_inputAmount <= 0) {
      return 'المبلغ يجب أن يكون أكبر من صفر.';
    }
    if (_mode != _AdjustmentMode.increase && _resultingBalance < 0) {
      return 'التخفيض يتجاوز الرصيد الحالي.';
    }
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (_validationError() != null) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _serverFailure = null;
    });

    final String? notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();

    try {
      if (_mode == _AdjustmentMode.collect) {
        await _submitCollect(notes: notes);
      } else {
        await _submitAdjustment(notes: notes);
      }

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

  Future<void> _submitAdjustment({required String? notes}) async {
    await ref.read(customersProvider.notifier).addAdjustment(
          customerId: widget.customerId,
          amount: _signedAmount,
          reason: _reason,
          notes: notes,
        );
  }

  Future<void> _submitCollect({required String? notes}) async {
    // NOTE: `CustomersNotifier.recordPayment` resolves the active company
    // id itself, so it is NOT passed here.
    final String? reference = _referenceController.text.trim().isEmpty
        ? null
        : _referenceController.text.trim();

    await ref.read(customersProvider.notifier).recordPayment(
          customerId: widget.customerId,
          amount: _inputAmount,
          method: _paymentMethod,
          reference: reference,
          notes: notes,
        );
  }

  void _selectMode(_AdjustmentMode mode) {
    setState(() {
      _mode = mode;
      _serverFailure = null;

      if (mode == _AdjustmentMode.increase) {
        _reason = AdjustmentReason.openingBalance;
      } else if (mode == _AdjustmentMode.decrease) {
        _reason = AdjustmentReason.correction;
      }
    });
  }

  void _selectReason(String reason) {
    setState(() {
      _reason = reason;
      _serverFailure = null;
    });
  }

  void _selectPaymentMethod(String method) {
    setState(() {
      _paymentMethod = method;
      _serverFailure = null;
    });
  }

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

    final double resulting = _resultingBalance;
    final bool resultingIsValid = resulting >= 0;
    final bool isCollect = _mode == _AdjustmentMode.collect;

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
                        'تعديل رصيد العميل',
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
                  ),

                  const SizedBox(height: 16),

                  Text('نوع العملية', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),

                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _DirectionTile(
                          label: 'زيادة',
                          icon: Icons.arrow_upward,
                          selected: _mode == _AdjustmentMode.increase,
                          enabled: !_isSubmitting,
                          color: scheme.error,
                          onTap: () =>
                              _selectMode(_AdjustmentMode.increase),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _DirectionTile(
                          label: 'تخفيض',
                          icon: Icons.arrow_downward,
                          selected: _mode == _AdjustmentMode.decrease,
                          enabled: !_isSubmitting,
                          color: const Color(0xFFE65100),
                          onTap: () =>
                              _selectMode(_AdjustmentMode.decrease),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _DirectionTile(
                          label: 'تحصيل',
                          icon: Icons.payments_outlined,
                          selected: isCollect,
                          enabled: !_isSubmitting,
                          color: scheme.primary,
                          onTap: () =>
                              _selectMode(_AdjustmentMode.collect),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),
                  Text(
                    _modeDescription(_mode),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 16),

                  Text('المبلغ', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  _AmountField(
                    controller: _amountController,
                    enabled: !_isSubmitting,
                    hasError: displayError != null,
                  ),

                  if (isCollect) ...<Widget>[
                    const SizedBox(height: 16),
                    Text('طريقة الدفع',
                        style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    _PaymentMethodSelector(
                      selected: _paymentMethod,
                      enabled: !_isSubmitting,
                      onChanged: _selectPaymentMethod,
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _referenceController,
                      label: 'المرجع — اختياري',
                      hint: 'رقم إيصال أو معرّف عملية',
                      enabled: !_isSubmitting,
                    ),
                  ],

                  if (!isCollect) ...<Widget>[
                    const SizedBox(height: 16),
                    Text('السبب', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    _ReasonDropdown(
                      value: _reason,
                      enabled: !_isSubmitting,
                      onChanged: _selectReason,
                    ),
                  ],

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
                    value: AppFormatters.money(widget.currentBalance),
                  ),
                  _SummaryLine(
                    label: _mode == _AdjustmentMode.increase
                        ? 'الزيادة'
                        : (isCollect ? 'المُحصَّل' : 'التخفيض'),
                    value: AppFormatters.money(
                      _inputAmount < 0 ? 0 : _inputAmount,
                    ),
                    color: _mode == _AdjustmentMode.increase
                        ? scheme.error
                        : scheme.primary,
                  ),
                  _SummaryLine(
                    label: 'الرصيد بعد العملية',
                    value: AppFormatters.money(
                      resulting < 0 ? 0 : resulting,
                    ),
                    emphasized: true,
                    color: resultingIsValid ? null : scheme.error,
                  ),

                  const SizedBox(height: 20),

                  AppButton(
                    label: isCollect ? 'تسجيل التحصيل' : 'تسجيل التعديل',
                    icon: isCollect
                        ? Icons.payments_outlined
                        : Icons.save_outlined,
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
// Sub-widgets (كما هي من قبل)
// ============================================================================

class _CustomerBanner extends StatelessWidget {
  const _CustomerBanner({
    required this.customerName,
    required this.currentBalance,
  });

  final String customerName;
  final double currentBalance;

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
                    'الرصيد الحالي: '
                    '${AppFormatters.money(currentBalance)}',
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

class _DirectionTile extends StatelessWidget {
  const _DirectionTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final Color selectedBackground = color;
    final Color selectedForeground = Colors.white;

    return Material(
      color: selected ? selectedBackground : scheme.surfaceContainerHighest,
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
                color: selected ? selectedForeground : scheme.onSurface,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected ? selectedForeground : scheme.onSurface,
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

class _PaymentMethodSelector extends StatelessWidget {
  const _PaymentMethodSelector({
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final String selected;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (int i = 0; i < PaymentMethod.all.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: _MethodTile(
              method: PaymentMethod.all[i],
              selected: selected == PaymentMethod.all[i],
              enabled: enabled,
              onTap: () => onChanged(PaymentMethod.all[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.method,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String method;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final IconData icon;
    final String label;
    switch (method) {
      case PaymentMethod.cash:
        icon = Icons.payments_outlined;
        label = 'نقدي';
      case PaymentMethod.card:
        icon = Icons.credit_card;
        label = 'بطاقة';
      case PaymentMethod.transfer:
        icon = Icons.account_balance_outlined;
        label = 'تحويل';
      default:
        icon = Icons.help_outline;
        label = method;
    }

    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 20,
                color: selected ? scheme.onPrimary : scheme.onSurface,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
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

class _ReasonDropdown extends StatelessWidget {
  const _ReasonDropdown({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      items: <DropdownMenuItem<String>>[
        for (final String reason in AdjustmentReason.all)
          DropdownMenuItem<String>(
            value: reason,
            child: Text(_reasonLabel(reason)),
          ),
      ],
      onChanged: enabled
          ? (String? selected) {
              if (selected == null) {
                return;
              }
              onChanged(selected);
            }
          : null,
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

String _modeDescription(_AdjustmentMode mode) {
  switch (mode) {
    case _AdjustmentMode.increase:
      return 'زيادة المديونية — بلا تسجيل دفعة.';
    case _AdjustmentMode.decrease:
      return 'تخفيض يدوي — بلا تسجيل دفعة (تصحيح).';
    case _AdjustmentMode.collect:
      return 'تحصيل دفعة من العميل — يُسجَّل في كشف الحساب.';
  }
}

String _reasonLabel(String reason) {
  switch (reason) {
    case AdjustmentReason.openingBalance:
      return 'رصيد افتتاحي';
    case AdjustmentReason.correction:
      return 'تصحيح رصيد';
    case AdjustmentReason.discount:
      return 'خصم على العميل';
    case AdjustmentReason.penalty:
      return 'غرامة';
    case AdjustmentReason.other:
      return 'تعديل يدوي';
    default:
      return 'تعديل يدوي';
  }
}

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
      return 'المبلغ غير صالح. يجب أن يكون أكبر من صفر.';
    case CustomerFailureType.insufficientBalance:
      return 'التخفيض يتجاوز الرصيد الحالي.';
    case CustomerFailureType.invalidResponse:
      return 'تعذّر قراءة البيانات. يرجى المحاولة مجددًا.';
    case CustomerFailureType.unknown:
      return 'تعذّر تسجيل العملية. يرجى المحاولة مرة أخرى.';
  }
}

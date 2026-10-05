// lib/features/sales/presentation/dialogs/customer_adjustment_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/entities/customer_adjustment.dart';
import '../../domain/entities/sale_entities.dart';
import '../../domain/repositories/sales_repository.dart';
import '../providers/sales_providers.dart';

/// Opens the customer balance adjustment dialog.
///
/// Returns the updated [Customer] when the adjustment was successfully
/// recorded, or `null` when the operator cancelled. The caller is expected
/// to keep any in-memory copy of the customer in sync with the returned
/// value.
///
/// An adjustment is a **signed** delta:
/// * a positive amount increases what the customer owes (e.g. opening
///   balance, penalty),
/// * a negative amount decreases it (e.g. goodwill discount, correction).
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

// ============================================================================
// Sheet
// ============================================================================

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

  bool _isIncrease = true;
  String _reason = AdjustmentReason.openingBalance;
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
    _amountController = TextEditingController();
    _notesController = TextEditingController();
    _amountController.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    if (!mounted) {
      return;
    }
    setState(() => _serverFailure = null);
  }

  // ---------------------------------------------------------------------------
  // Computed
  // ---------------------------------------------------------------------------

  double get _inputAmount =>
      double.tryParse(_amountController.text.trim()) ?? 0;

  double get _signedAmount => _isIncrease ? _inputAmount : -_inputAmount;

  double get _resultingBalance => widget.currentBalance + _signedAmount;

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  String? _validationError() {
    if (_inputAmount <= 0) {
      return 'المبلغ يجب أن يكون أكبر من صفر.';
    }
    if (!_isIncrease && _resultingBalance < 0) {
      return 'التخفيض يتجاوز الرصيد الحالي.';
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

    final String? notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();

    try {
      await ref.read(customersProvider.notifier).addAdjustment(
            customerId: widget.customerId,
            amount: _signedAmount,
            reason: _reason,
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

  void _selectDirection({required bool increase}) {
    setState(() {
      _isIncrease = increase;
      _serverFailure = null;
    });
  }

  void _selectReason(String reason) {
    setState(() {
      _reason = reason;
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

    final double resulting = _resultingBalance;
    final bool resultingIsValid = resulting >= 0;

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
                    money: _money,
                  ),

                  const SizedBox(height: 16),

                  Text('نوع التعديل', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _DirectionTile(
                          label: 'زيادة الرصيد',
                          icon: Icons.arrow_upward,
                          selected: _isIncrease,
                          enabled: !_isSubmitting,
                          color: scheme.error,
                          onTap: () => _selectDirection(increase: true),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _DirectionTile(
                          label: 'تخفيض الرصيد',
                          icon: Icons.arrow_downward,
                          selected: !_isIncrease,
                          enabled: !_isSubmitting,
                          color: scheme.primary,
                          onTap: () => _selectDirection(increase: false),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  Text('المبلغ', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  _AmountField(
                    controller: _amountController,
                    enabled: !_isSubmitting,
                    hasError: displayError != null,
                  ),

                  const SizedBox(height: 16),

                  Text('السبب', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  _ReasonDropdown(
                    value: _reason,
                    enabled: !_isSubmitting,
                    onChanged: _selectReason,
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
                    label: _isIncrease ? 'الزيادة' : 'التخفيض',
                    value: _money.format(
                      _inputAmount < 0 ? 0 : _inputAmount,
                    ),
                    color: _isIncrease ? scheme.error : scheme.primary,
                  ),
                  _SummaryLine(
                    label: 'الرصيد بعد التعديل',
                    value: _money.format(resulting < 0 ? 0 : resulting),
                    emphasized: true,
                    color: resultingIsValid ? null : scheme.error,
                  ),

                  const SizedBox(height: 20),

                  AppButton(
                    label: 'تسجيل التعديل',
                    icon: Icons.save_outlined,
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

// ============================================================================
// Localization
// ============================================================================

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
      return 'تعذّر تسجيل التعديل. يرجى المحاولة مرة أخرى.';
  }
}

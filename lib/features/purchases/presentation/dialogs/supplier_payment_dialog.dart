// lib/features/purchases/presentation/dialogs/supplier_payment_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/entities/supplier_payment.dart';
import '../../domain/repositories/supplier_payment_repository.dart';
import '../providers/supplier_payment_providers.dart';

/// Opens the supplier-payment dialog.
///
/// * [supplierId] / [supplierName] identify the beneficiary.
/// * When [purchaseId] is provided, the payment is linked to that purchase
///   and [suggestedAmount] is pre-filled (typically the remaining balance).
/// * Returns `true` when a payment was recorded, `false` when cancelled.
Future<bool?> showSupplierPaymentDialog({
  required BuildContext context,
  required String supplierId,
  required String supplierName,
  String? purchaseId,
  String? purchaseLabel,
  double? suggestedAmount,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) => _SupplierPaymentSheet(
      supplierId: supplierId,
      supplierName: supplierName,
      purchaseId: purchaseId,
      purchaseLabel: purchaseLabel,
      suggestedAmount: suggestedAmount,
    ),
  );
}

// ============================================================================
// Sheet
// ============================================================================

class _SupplierPaymentSheet extends ConsumerStatefulWidget {
  const _SupplierPaymentSheet({
    required this.supplierId,
    required this.supplierName,
    this.purchaseId,
    this.purchaseLabel,
    this.suggestedAmount,
  });

  final String supplierId;
  final String supplierName;
  final String? purchaseId;
  final String? purchaseLabel;
  final double? suggestedAmount;

  @override
  ConsumerState<_SupplierPaymentSheet> createState() =>
      _SupplierPaymentSheetState();
}

class _SupplierPaymentSheetState
    extends ConsumerState<_SupplierPaymentSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _amountController;
  late final TextEditingController _referenceController;
  late final TextEditingController _notesController;

  String _method = SupplierPaymentMethod.cash;
  DateTime _paymentDate = DateTime.now();

  bool _isSubmitting = false;
  SupplierPaymentFailureType? _failure;

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );
  static final DateFormat _dateFormat = DateFormat.yMd('ar_EG');

  @override
  void initState() {
    super.initState();
    final double? suggested = widget.suggestedAmount;
    _amountController = TextEditingController(
      text: suggested != null && suggested > 0
          ? _formatAmount(suggested)
          : '',
    );
    _referenceController = TextEditingController();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  static String _formatAmount(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (_failure != null) {
      setState(() => _failure = null);
    }

    final bool valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    final double? amount =
        double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() =>
          _failure = SupplierPaymentFailureType.invalidAmount);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await ref
          .read(supplierPaymentsForSupplierProvider(widget.supplierId).notifier)
          .recordPayment(
            supplierId: widget.supplierId,
            amount: amount,
            paymentMethod: _method,
            paymentDate: _paymentDate,
            purchaseId: widget.purchaseId,
            reference: _nullIfEmpty(_referenceController.text),
            notes: _nullIfEmpty(_notesController.text),
          );

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('تم تسجيل الدفعة: ${_money.format(amount)}')),
        );
    } on SupplierPaymentException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _failure = error.type;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _failure = SupplierPaymentFailureType.unknown;
      });
    }
  }

  static String? _nullIfEmpty(String value) {
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  // ---------------------------------------------------------------------------
  // Validators
  // ---------------------------------------------------------------------------

  String? _validateAmount(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'الرجاء إدخال المبلغ';
    final double? parsed = double.tryParse(trimmed);
    if (parsed == null) return 'الرجاء إدخال رقم صحيح';
    if (parsed <= 0) return 'المبلغ يجب أن يكون أكبر من صفر';
    return null;
  }

  String? _validateReference(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.length > 64) {
      return 'المرجع طويل جدًا (الحد الأقصى 64 حرفًا)';
    }
    return null;
  }

  String? _validateNotes(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.length > 2000) {
      return 'الملاحظات طويلة جدًا (الحد الأقصى 2000 حرف)';
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

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
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // ---- Header ----
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
                        Icon(Icons.payments_outlined, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'تسجيل دفعة للمورد',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _isSubmitting
                              ? null
                              : () => Navigator.of(context).pop(false),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // ---- Supplier + optional purchase ----
                    _ContextCard(
                      supplierName: widget.supplierName,
                      purchaseLabel: widget.purchaseLabel,
                      suggestedAmount: widget.suggestedAmount,
                    ),

                    const SizedBox(height: 16),

                    // ---- Amount ----
                    AppTextField(
                      controller: _amountController,
                      label: 'المبلغ *',
                      hint: '0.00',
                      enabled: !_isSubmitting,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.next,
                      validator: _validateAmount,
                    ),

                    const SizedBox(height: 16),

                    // ---- Method ----
                    Text(
                      'طريقة الدفع',
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    _MethodSelector(
                      value: _method,
                      enabled: !_isSubmitting,
                      onChanged: (String v) =>
                          setState(() => _method = v),
                    ),

                    const SizedBox(height: 16),

                    // ---- Date ----
                    InkWell(
                      onTap: _isSubmitting
                          ? null
                          : () async {
                              final DateTime? picked = await showDatePicker(
                                context: context,
                                initialDate: _paymentDate,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setState(() => _paymentDate = picked);
                              }
                            },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'تاريخ الدفع',
                          border: OutlineInputBorder(),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(_dateFormat.format(_paymentDate)),
                            const Icon(
                              Icons.calendar_today_outlined,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ---- Reference ----
                    AppTextField(
                      controller: _referenceController,
                      label: 'المرجع — اختياري',
                      hint: 'رقم شيك، رقم تحويل…',
                      enabled: !_isSubmitting,
                      textInputAction: TextInputAction.next,
                      validator: _validateReference,
                    ),

                    const SizedBox(height: 14),

                    // ---- Notes ----
                    AppTextField(
                      controller: _notesController,
                      label: 'ملاحظات — اختياري',
                      enabled: !_isSubmitting,
                      maxLines: 2,
                      validator: _validateNotes,
                    ),

                    if (_failure != null) ...<Widget>[
                      const SizedBox(height: 12),
                      _ErrorBanner(message: _messageFor(_failure!)),
                    ],

                    const SizedBox(height: 20),

                    AppButton(
                      label: 'تسجيل الدفعة',
                      icon: Icons.check_circle_outline,
                      expanded: true,
                      size: AppButtonSize.large,
                      isLoading: _isSubmitting,
                      onPressed: _isSubmitting ? null : _submit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _messageFor(SupplierPaymentFailureType type) {
    switch (type) {
      case SupplierPaymentFailureType.network:
        return 'تعذّر الاتصال بالخادم. تحقق من اتصالك بالإنترنت.';
      case SupplierPaymentFailureType.unauthorized:
        return 'ليس لديك صلاحية لتسجيل دفعة. تواصل مع المالك أو المدير.';
      case SupplierPaymentFailureType.notFound:
        return 'المورد أو الفاتورة غير موجودة.';
      case SupplierPaymentFailureType.invalidAmount:
        return 'المبلغ يجب أن يكون أكبر من صفر.';
      case SupplierPaymentFailureType.invalidMethod:
        return 'طريقة الدفع غير مدعومة.';
      case SupplierPaymentFailureType.supplierNotFound:
        return 'المورد المختار غير متاح.';
      case SupplierPaymentFailureType.purchaseNotFound:
        return 'الفاتورة المختارة غير متاحة.';
      case SupplierPaymentFailureType.invalidResponse:
        return 'تعذّر قراءة البيانات. تحقق من المدخلات.';
      case SupplierPaymentFailureType.unknown:
        return 'تعذّر تسجيل الدفعة. حاول مرة أخرى.';
    }
  }
}

// ============================================================================
// Context card (supplier + optional purchase)
// ============================================================================

class _ContextCard extends StatelessWidget {
  const _ContextCard({
    required this.supplierName,
    required this.purchaseLabel,
    required this.suggestedAmount,
  });

  final String supplierName;
  final String? purchaseLabel;
  final double? suggestedAmount;

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool hasPurchase =
        purchaseLabel != null && purchaseLabel!.isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.local_shipping_outlined,
                    size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    supplierName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (hasPurchase) ...<Widget>[
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Icon(Icons.receipt_long_outlined,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'الفاتورة: $purchaseLabel',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (suggestedAmount != null && suggestedAmount! > 0) ...<Widget>[
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Icon(Icons.info_outline,
                      size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'المتبقي على الفاتورة: ${_money.format(suggestedAmount!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Method selector
// ============================================================================

class _MethodSelector extends StatelessWidget {
  const _MethodSelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final String method in SupplierPaymentMethod.all) ...<Widget>[
            ChoiceChip(
              label: Text(SupplierPaymentMethod.label(method)),
              selected: value == method,
              onSelected:
                  enabled ? (_) => onChanged(method) : null,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// Error banner
// ============================================================================

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.error_outline,
                color: scheme.onErrorContainer, size: 20),
            const SizedBox(width: 10),
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

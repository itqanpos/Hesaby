// lib/features/employees/presentation/widgets/salary_form_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../domain/entities/employee.dart';
import '../../domain/entities/employee_advance.dart';
import '../../domain/entities/employee_salary.dart';
import '../../domain/repositories/employee_salary_repository.dart';
import '../providers/payroll_providers.dart';

/// Bottom sheet to create or edit a single salary entry.
///
/// Two actions:
/// * **حفظ كمسودة** — saves without paying (`paid_at = null`).
/// * **حفظ ودفع** — saves and marks as paid immediately. The DB trigger
///   posts the cash movement and reduces the employee's open advances
///   by the `advancesDeducted` amount (FIFO).
Future<bool?> showSalaryFormSheet({
  required BuildContext context,
  required Employee employee,
  required DateTime salaryMonth,
  EmployeeSalary? existing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (BuildContext _) => _SalaryFormSheet(
      employee: employee,
      salaryMonth: salaryMonth,
      existing: existing,
    ),
  );
}

class _SalaryFormSheet extends ConsumerStatefulWidget {
  const _SalaryFormSheet({
    required this.employee,
    required this.salaryMonth,
    this.existing,
  });

  final Employee employee;
  final DateTime salaryMonth;
  final EmployeeSalary? existing;

  @override
  ConsumerState<_SalaryFormSheet> createState() => _SalaryFormSheetState();
}

class _SalaryFormSheetState extends ConsumerState<_SalaryFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _baseController;
  late final TextEditingController _bonusesController;
  late final TextEditingController _deductionsController;
  late final TextEditingController _advancesController;
  late final TextEditingController _notesController;

  String _paymentMethod = 'cash';
  bool _isSaving = false;
  SalaryFailureType? _failure;

  bool get _isEdit => widget.existing != null;
  bool get _isPaid => widget.existing?.isPaid ?? false;

  @override
  void initState() {
    super.initState();
    final EmployeeSalary? s = widget.existing;
    final Employee e = widget.employee;

    _baseController = TextEditingController(
      text: _fmt(s?.baseAmount ?? e.baseSalary),
    );
    _bonusesController = TextEditingController(
      text: s == null ? '' : _fmt(s.bonuses),
    );
    _deductionsController = TextEditingController(
      text: s == null ? '' : _fmt(s.deductions),
    );
    _advancesController = TextEditingController(
      text: s == null ? '' : _fmt(s.advancesDeducted),
    );
    _notesController = TextEditingController(text: s?.notes ?? '');
    _paymentMethod = s?.paymentMethod ?? 'cash';

    _baseController.addListener(_rebuild);
    _bonusesController.addListener(_rebuild);
    _deductionsController.addListener(_rebuild);
    _advancesController.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _baseController.dispose();
    _bonusesController.dispose();
    _deductionsController.dispose();
    _advancesController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double _parse(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0;

  double get _net => EmployeeSalary.computeNet(
        base: _parse(_baseController),
        bonuses: _parse(_bonusesController),
        deductions: _parse(_deductionsController),
        advancesDeducted: _parse(_advancesController),
      );

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  static String? _emptyToNull(String s) {
    final String t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _submit({required bool markPaid}) async {
    FocusScope.of(context).unfocus();
    if (_failure != null) setState(() => _failure = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);

    try {
      final double base = _parse(_baseController);
      final double bonuses = _parse(_bonusesController);
      final double deductions = _parse(_deductionsController);
      final double advances = _parse(_advancesController);
      final String? notes = _emptyToNull(_notesController.text);

      if (_isEdit) {
        await ref.read(salariesProvider.notifier).updateSalary(
              salaryId: widget.existing!.id,
              baseAmount: base,
              bonuses: bonuses,
              deductions: deductions,
              advancesDeducted: advances,
              paymentMethod: _paymentMethod,
              notes: notes,
              clearNotes: notes == null,
            );
        if (markPaid && !_isPaid) {
          await ref.read(salariesProvider.notifier).markPaid(
                salaryId: widget.existing!.id,
                paymentMethod: _paymentMethod,
              );
        }
      } else {
        await ref.read(salariesProvider.notifier).create(
              employeeId: widget.employee.id,
              salaryMonth: widget.salaryMonth,
              baseAmount: base,
              bonuses: bonuses,
              deductions: deductions,
              advancesDeducted: advances,
              paymentMethod: _paymentMethod,
              paidAt: markPaid ? DateTime.now() : null,
              notes: notes,
            );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SalaryException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _failure = e.type;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _failure = SalaryFailureType.unknown;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    final Employee e = widget.employee;

    // ---- Available advances (open) for this employee ----
    final List<EmployeeAdvance> employeeAdvances =
        (ref.watch(advancesProvider).valueOrNull ??
                const <EmployeeAdvance>[])
            .where((EmployeeAdvance a) =>
                a.employeeId == widget.employee.id &&
                !a.isFullyDeducted)
            .toList(growable: false);
    final double totalAvailableAdvances = employeeAdvances.fold<double>(
      0,
      (double s, EmployeeAdvance a) => s + a.remainingAmount,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  _isEdit ? 'تعديل راتب' : 'إضافة راتب',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${e.fullName} · '
                  '${AppFormatters.longMonth(widget.salaryMonth)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),

                if (_isPaid)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _InfoBanner(
                      icon: Icons.check_circle_outline,
                      message:
                          'هذا الراتب مدفوع بالفعل. التعديل لا يعيد الحركة في الخزنة.',
                      color: scheme.primary,
                    ),
                  ),

                // ---- Base ----
                _MoneyField(
                  controller: _baseController,
                  label: 'الراتب الأساسي',
                  enabled: !_isSaving && !_isPaid,
                ),
                const SizedBox(height: 12),

                // ---- Bonuses ----
                _MoneyField(
                  controller: _bonusesController,
                  label: 'الحوافز (+)',
                  enabled: !_isSaving && !_isPaid,
                ),
                const SizedBox(height: 12),

                // ---- Deductions ----
                _MoneyField(
                  controller: _deductionsController,
                  label: 'الخصومات (−)',
                  enabled: !_isSaving && !_isPaid,
                ),
                const SizedBox(height: 12),

                // ---- Advances (with available hint) ----
                _MoneyField(
                  controller: _advancesController,
                  label: 'خصم السلف (−)',
                  enabled: !_isSaving && !_isPaid,
                  helperText: totalAvailableAdvances > 0
                      ? 'المتاح للخصم من السلف: '
                          '${AppFormatters.money(totalAvailableAdvances)}'
                      : 'لا يوجد سلف مفتوحة لهذا الموظف',
                  validator: (String? v) {
                    final String t = (v ?? '').trim();
                    if (t.isEmpty) return null;
                    final double? d = double.tryParse(t);
                    if (d == null || d < 0) return 'قيمة غير صحيحة';
                    if (d > totalAvailableAdvances + 0.01) {
                      return 'المتاح: '
                          '${AppFormatters.money(totalAvailableAdvances)}';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ---- Net preview ----
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: <Widget>[
                        Text(
                          'الصافي',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          AppFormatters.money(_net),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Payment method ----
                DropdownButtonFormField<String>(
                  key: ValueKey<String>('pm-$_paymentMethod'),
                  initialValue: _paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'طريقة الدفع',
                    border: OutlineInputBorder(),
                  ),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(
                      value: 'cash',
                      child: Text('نقدي'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'card',
                      child: Text('بطاقة'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'instapay',
                      child: Text('InstaPay'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'bank_transfer',
                      child: Text('تحويل بنكي'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'other',
                      child: Text('أخرى'),
                    ),
                  ],
                  onChanged: (_isSaving || _isPaid)
                      ? null
                      : (String? v) {
                          if (v != null) {
                            setState(() => _paymentMethod = v);
                          }
                        },
                ),
                const SizedBox(height: 12),

                // ---- Notes ----
                TextFormField(
                  controller: _notesController,
                  enabled: !_isSaving,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),

                if (_failure != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _FailureBanner(message: _failureMessage(_failure!)),
                ],

                const SizedBox(height: 20),

                // ---- Actions ----
                if (!_isPaid) ...<Widget>[
                  AppButton(
                    label: 'حفظ ودفع',
                    icon: Icons.check_circle_outline,
                    expanded: true,
                    size: AppButtonSize.large,
                    isLoading: _isSaving,
                    onPressed: _isSaving
                        ? null
                        : () => _submit(markPaid: true),
                  ),
                  const SizedBox(height: 8),
                  AppButton(
                    label: 'حفظ كمسودة',
                    icon: Icons.save_outlined,
                    variant: AppButtonVariant.outline,
                    expanded: true,
                    onPressed: _isSaving
                        ? null
                        : () => _submit(markPaid: false),
                  ),
                ] else ...<Widget>[
                  AppButton(
                    label: 'حفظ التعديلات',
                    icon: Icons.save_outlined,
                    expanded: true,
                    size: AppButtonSize.large,
                    isLoading: _isSaving,
                    onPressed: _isSaving
                        ? null
                        : () => _submit(markPaid: false),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Money field
// ============================================================================

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.controller,
    required this.label,
    required this.enabled,
    this.helperText,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final String? helperText;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: '0',
        border: const OutlineInputBorder(),
        suffixText: 'ج.م',
        helperText: helperText,
      ),
      validator: validator ??
          (String? v) {
            final String t = (v ?? '').trim();
            if (t.isEmpty) return null;
            final double? d = double.tryParse(t);
            if (d == null || d < 0) return 'قيمة غير صحيحة';
            return null;
          },
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.message});

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
        padding: const EdgeInsets.all(12),
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

String _failureMessage(SalaryFailureType type) => switch (type) {
      SalaryFailureType.network =>
        'تعذّر الاتصال بالخادم. تحقق من اتصالك.',
      SalaryFailureType.unauthorized =>
        'لا تملك صلاحية إدارة الرواتب.',
      SalaryFailureType.notFound => 'الراتب غير موجود.',
      SalaryFailureType.invalidInput =>
        'تحقق من المبالغ المُدخلة (خصم السلف يتجاوز المتاح؟).',
      SalaryFailureType.duplicateEntry =>
        'يوجد راتب مسجَّل لهذا الموظف في هذا الشهر بالفعل.',
      SalaryFailureType.invalidResponse =>
        'تعذّر قراءة البيانات من الخادم.',
      SalaryFailureType.unknown => 'حدث خطأ غير متوقع. حاول مرة أخرى.',
    };

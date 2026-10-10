// lib/features/expenses/presentation/widgets/expense_form_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../shared/widgets/app_button.dart';
import '../../../cash/domain/entities/cash_entities.dart';
import '../../../cash/presentation/providers/cash_providers.dart';
import '../../domain/entities/expense.dart';
import '../../domain/repositories/expense_repository.dart';
import '../providers/expense_providers.dart';

/// Bottom sheet to add or edit an expense.
///
/// Returns `true` on successful save.
Future<bool?> showExpenseFormSheet({
  required BuildContext context,
  Expense? existing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (BuildContext _) => _ExpenseFormSheet(existing: existing),
  );
}

class _ExpenseFormSheet extends ConsumerStatefulWidget {
  const _ExpenseFormSheet({this.existing});

  final Expense? existing;

  @override
  ConsumerState<_ExpenseFormSheet> createState() => _ExpenseFormSheetState();
}

class _ExpenseFormSheetState extends ConsumerState<_ExpenseFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _descriptionController;
  late final TextEditingController _amountController;
  late final TextEditingController _referenceController;
  late final TextEditingController _notesController;

  late DateTime _expenseDate;
  String? _categoryId;
  String _paymentMethod = 'cash';
  bool _isSubmitting = false;
  ExpenseFailureType? _failure;

  static final DateFormat _dateFmt = DateFormat('yyyy/MM/dd');

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final Expense? e = widget.existing;
    _descriptionController =
        TextEditingController(text: e?.description ?? '');
    _amountController = TextEditingController(
      text: e == null ? '' : _fmtNum(e.amount),
    );
    _referenceController = TextEditingController(text: e?.reference ?? '');
    _notesController = TextEditingController(text: e?.notes ?? '');
    _expenseDate = e?.expenseDate ?? DateTime.now();
    _categoryId = e?.categoryId;
    _paymentMethod = e?.paymentMethod ?? 'cash';
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  static String _fmtNum(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  static String? _emptyToNull(String s) {
    final String t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _expenseDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 2),
      locale: const Locale('ar', 'EG'),
    );
    if (picked != null) {
      setState(() => _expenseDate = picked);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_failure != null) setState(() => _failure = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);

    final double amount = double.tryParse(_amountController.text.trim()) ?? 0;

    try {
      if (_isEdit) {
        await ref.read(expensesProvider.notifier).updateExpense(
              expenseId: widget.existing!.id,
              categoryId: _categoryId,
              clearCategory: _categoryId == null,
              description: _descriptionController.text.trim(),
              amount: amount,
              expenseDate: _expenseDate,
              paymentMethod: _paymentMethod,
              reference: _emptyToNull(_referenceController.text),
              clearReference: _emptyToNull(_referenceController.text) == null,
              notes: _emptyToNull(_notesController.text),
              clearNotes: _emptyToNull(_notesController.text) == null,
            );
      } else {
        await ref.read(expensesProvider.notifier).create(
              categoryId: _categoryId,
              description: _descriptionController.text.trim(),
              amount: amount,
              expenseDate: _expenseDate,
              paymentMethod: _paymentMethod,
              reference: _emptyToNull(_referenceController.text),
              notes: _emptyToNull(_notesController.text),
            );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ExpenseException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _failure = e.type;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _failure = ExpenseFailureType.unknown;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    final AsyncValue<List<CashCategory>> categoriesAsync =
        ref.watch(cashCategoriesProvider);
    final List<CashCategory> expenseCategories =
        (categoriesAsync.valueOrNull ?? const <CashCategory>[])
            .where((CashCategory c) => c.kind == CashCategoryKind.expense)
            .toList(growable: false);

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
                  _isEdit ? 'تعديل المصروف' : 'إضافة مصروف',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'سيُسجَّل تلقائيًا كحركة صادر في الخزنة.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),

                // ---- Description ----
                TextFormField(
                  controller: _descriptionController,
                  enabled: !_isSubmitting,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'الوصف *',
                    hintText: 'فاتورة كهرباء شهر أكتوبر',
                    border: OutlineInputBorder(),
                  ),
                  validator: (String? v) {
                    final String t = (v ?? '').trim();
                    if (t.isEmpty) return 'الرجاء إدخال وصف المصروف';
                    if (t.length > 300) return 'الوصف طويل جدًا';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // ---- Amount ----
                TextFormField(
                  controller: _amountController,
                  enabled: !_isSubmitting,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ *',
                    hintText: '0',
                    border: OutlineInputBorder(),
                    suffixText: 'ج.م',
                  ),
                  validator: (String? v) {
                    final double? d = double.tryParse((v ?? '').trim());
                    if (d == null || d <= 0) return 'أدخل مبلغًا صحيحًا';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // ---- Category ----
                DropdownButtonFormField<String>(
                  key: ValueKey<String>('category-${_categoryId ?? ''}'),
                  initialValue: _categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'التصنيف (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                  items: <DropdownMenuItem<String>>[
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('بدون تصنيف'),
                    ),
                    for (final CashCategory c in expenseCategories)
                      DropdownMenuItem<String>(
                        value: c.id,
                        child: Text(c.name),
                      ),
                  ],
                  onChanged: _isSubmitting
                      ? null
                      : (String? v) => setState(() => _categoryId = v),
                ),
                const SizedBox(height: 12),

                // ---- Payment method ----
                DropdownButtonFormField<String>(
                  key: ValueKey<String>('method-$_paymentMethod'),
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
                  onChanged: _isSubmitting
                      ? null
                      : (String? v) {
                          if (v != null) {
                            setState(() => _paymentMethod = v);
                          }
                        },
                ),
                const SizedBox(height: 12),

                // ---- Date ----
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: _isSubmitting ? null : _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'التاريخ',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    child: Text(_dateFmt.format(_expenseDate)),
                  ),
                ),
                const SizedBox(height: 12),

                // ---- Reference ----
                TextFormField(
                  controller: _referenceController,
                  enabled: !_isSubmitting,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'المرجع (اختياري)',
                    hintText: 'رقم فاتورة، رقم عملية…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // ---- Notes ----
                TextFormField(
                  controller: _notesController,
                  enabled: !_isSubmitting,
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

                AppButton(
                  label: _isEdit ? 'حفظ التعديلات' : 'تسجيل المصروف',
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

String _failureMessage(ExpenseFailureType type) => switch (type) {
      ExpenseFailureType.network =>
        'تعذّر الاتصال بالخادم. تحقق من اتصالك.',
      ExpenseFailureType.unauthorized =>
        'لا تملك صلاحية إدارة المصروفات.',
      ExpenseFailureType.notFound => 'المصروف غير موجود.',
      ExpenseFailureType.invalidInput => 'تحقق من البيانات المُدخلة.',
      ExpenseFailureType.invalidResponse =>
        'تعذّر قراءة البيانات من الخادم.',
      ExpenseFailureType.unknown => 'حدث خطأ غير متوقع. حاول مرة أخرى.',
    };

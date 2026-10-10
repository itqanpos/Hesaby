// lib/features/employees/presentation/widgets/advance_form_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../shared/widgets/app_button.dart';
import '../../domain/entities/employee.dart';
import '../../domain/repositories/employee_advance_repository.dart';
import '../providers/employee_providers.dart';
import '../providers/payroll_providers.dart';

/// Bottom sheet to record a new advance for an employee.
///
/// On success, the DB trigger posts an "out" cash movement automatically.
Future<bool?> showAdvanceFormSheet({
  required BuildContext context,
  String? initialEmployeeId,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (BuildContext _) => _AdvanceFormSheet(
      initialEmployeeId: initialEmployeeId,
    ),
  );
}

class _AdvanceFormSheet extends ConsumerStatefulWidget {
  const _AdvanceFormSheet({this.initialEmployeeId});

  final String? initialEmployeeId;

  @override
  ConsumerState<_AdvanceFormSheet> createState() =>
      _AdvanceFormSheetState();
}

class _AdvanceFormSheetState extends ConsumerState<_AdvanceFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  late String? _employeeId;
  DateTime _advanceDate = DateTime.now();
  bool _isSubmitting = false;
  AdvanceFailureType? _failure;

  static final DateFormat _dateFmt = DateFormat('yyyy/MM/dd');

  @override
  void initState() {
    super.initState();
    _employeeId = widget.initialEmployeeId;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  static String? _emptyToNull(String s) {
    final String t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _advanceDate,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      locale: const Locale('ar', 'EG'),
    );
    if (picked != null) {
      setState(() => _advanceDate = picked);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_failure != null) setState(() => _failure = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final String? employeeId = _employeeId;
    if (employeeId == null) {
      setState(() => _failure = AdvanceFailureType.invalidInput);
      return;
    }

    final double amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _failure = AdvanceFailureType.invalidInput);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await ref.read(advancesProvider.notifier).create(
            employeeId: employeeId,
            amount: amount,
            advanceDate: _advanceDate,
            reason: _emptyToNull(_reasonController.text),
            notes: _emptyToNull(_notesController.text),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AdvanceException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _failure = e.type;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _failure = AdvanceFailureType.unknown;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    final AsyncValue<List<Employee>> employeesAsync =
        ref.watch(employeesProvider);
    final List<Employee> employees = (employeesAsync.valueOrNull ??
            const <Employee>[])
        .where((Employee e) => e.isActive)
        .toList(growable: false);

    // Auto-select first if none.
    if (_employeeId == null && employees.isNotEmpty) {
      _employeeId = employees.first.id;
    }

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
                  'تسجيل سلفة موظف',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ستُسجَّل تلقائيًا كحركة صادر في الخزنة.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),

                // ---- Employee ----
                if (employees.isEmpty)
                  const _EmptyHint(
                    message: 'لا يوجد موظفون نشطون. أضف موظفًا أولًا.',
                  )
                else
                  DropdownButtonFormField<String>(
                    key: ValueKey<String>('emp-${_employeeId ?? ''}'),
                    initialValue: _employeeId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'الموظف',
                      border: OutlineInputBorder(),
                    ),
                    items: <DropdownMenuItem<String>>[
                      for (final Employee e in employees)
                        DropdownMenuItem<String>(
                          value: e.id,
                          child: Text(
                            e.position != null && e.position!.isNotEmpty
                                ? '${e.fullName} — ${e.position}'
                                : e.fullName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _isSubmitting
                        ? null
                        : (String? v) => setState(() => _employeeId = v),
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
                    labelText: 'المبلغ',
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

                // ---- Date ----
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: _isSubmitting ? null : _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'تاريخ السلفة',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    child: Text(_dateFmt.format(_advanceDate)),
                  ),
                ),
                const SizedBox(height: 12),

                // ---- Reason ----
                TextFormField(
                  controller: _reasonController,
                  enabled: !_isSubmitting,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'السبب (اختياري)',
                    hintText: 'مثال: ظروف طارئة',
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
                  label: 'تسجيل السلفة',
                  icon: Icons.check_circle_outline,
                  expanded: true,
                  size: AppButtonSize.large,
                  isLoading: _isSubmitting,
                  onPressed: (_isSubmitting || employees.isEmpty)
                      ? null
                      : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(message),
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

String _failureMessage(AdvanceFailureType type) => switch (type) {
      AdvanceFailureType.network =>
        'تعذّر الاتصال بالخادم. تحقق من اتصالك.',
      AdvanceFailureType.unauthorized =>
        'لا تملك صلاحية إدارة السلف.',
      AdvanceFailureType.notFound => 'السلفة غير موجودة.',
      AdvanceFailureType.invalidInput => 'تحقق من المبلغ والموظف.',
      AdvanceFailureType.invalidResponse =>
        'تعذّر قراءة البيانات من الخادم.',
      AdvanceFailureType.unknown => 'حدث خطأ غير متوقع. حاول مرة أخرى.',
    };

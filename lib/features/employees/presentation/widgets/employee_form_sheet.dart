// lib/features/employees/presentation/widgets/employee_form_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/app_button.dart';
import '../../domain/entities/employee.dart';
import '../../domain/repositories/employee_repository.dart';
import '../providers/employee_providers.dart';

/// Opens the employee add/edit sheet.
///
/// Pass [existing] to edit; omit it to create.
/// Returns `true` when a save succeeded.
Future<bool?> showEmployeeFormSheet({
  required BuildContext context,
  Employee? existing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (BuildContext _) => _EmployeeFormSheet(existing: existing),
  );
}

class _EmployeeFormSheet extends ConsumerStatefulWidget {
  const _EmployeeFormSheet({this.existing});

  final Employee? existing;

  @override
  ConsumerState<_EmployeeFormSheet> createState() =>
      _EmployeeFormSheetState();
}

class _EmployeeFormSheetState extends ConsumerState<_EmployeeFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _nationalIdController;
  late final TextEditingController _positionController;
  late final TextEditingController _baseSalaryController;
  late final TextEditingController _notesController;

  DateTime? _hireDate;
  bool _isActive = true;
  bool _isSubmitting = false;
  EmployeeFailureType? _failure;

  static final DateFormat _dateFmt = DateFormat('yyyy/MM/dd');

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final Employee? e = widget.existing;
    _nameController = TextEditingController(text: e?.fullName ?? '');
    _phoneController = TextEditingController(text: e?.phone ?? '');
    _emailController = TextEditingController(text: e?.email ?? '');
    _nationalIdController = TextEditingController(text: e?.nationalId ?? '');
    _positionController = TextEditingController(text: e?.position ?? '');
    _baseSalaryController = TextEditingController(
      text: e == null ? '' : _fmtNum(e.baseSalary),
    );
    _notesController = TextEditingController(text: e?.notes ?? '');
    _hireDate = e?.hireDate;
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _nationalIdController.dispose();
    _positionController.dispose();
    _baseSalaryController.dispose();
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

  Future<void> _pickHireDate() async {
    final DateTime now = DateTime.now();
    final DateTime initial = _hireDate ?? now;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 30),
      lastDate: DateTime(now.year + 5),
      locale: const Locale('ar', 'EG'),
    );
    if (picked != null) {
      setState(() => _hireDate = picked);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_failure != null) setState(() => _failure = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);

    final double salary =
        double.tryParse(_baseSalaryController.text.trim()) ?? 0;

    try {
      if (_isEdit) {
        await ref.read(employeesProvider.notifier).updateEmployee(
              employeeId: widget.existing!.id,
              fullName: _nameController.text.trim(),
              phone: _emptyToNull(_phoneController.text),
              clearPhone: _emptyToNull(_phoneController.text) == null,
              email: _emptyToNull(_emailController.text),
              clearEmail: _emptyToNull(_emailController.text) == null,
              nationalId: _emptyToNull(_nationalIdController.text),
              clearNationalId:
                  _emptyToNull(_nationalIdController.text) == null,
              position: _emptyToNull(_positionController.text),
              clearPosition: _emptyToNull(_positionController.text) == null,
              hireDate: _hireDate,
              clearHireDate: _hireDate == null,
              baseSalary: salary,
              notes: _emptyToNull(_notesController.text),
              clearNotes: _emptyToNull(_notesController.text) == null,
              isActive: _isActive,
            );
      } else {
        await ref.read(employeesProvider.notifier).create(
              fullName: _nameController.text.trim(),
              baseSalary: salary,
              phone: _emptyToNull(_phoneController.text),
              email: _emptyToNull(_emailController.text),
              nationalId: _emptyToNull(_nationalIdController.text),
              position: _emptyToNull(_positionController.text),
              hireDate: _hireDate,
              notes: _emptyToNull(_notesController.text),
            );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on EmployeeException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _failure = e.type;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _failure = EmployeeFailureType.unknown;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

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
                  _isEdit ? 'تعديل بيانات الموظف' : 'إضافة موظف جديد',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'يُستخدم هذا السجل للرواتب والسلف وتقارير الموظفين.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),

                // ---- Name ----
                TextFormField(
                  controller: _nameController,
                  enabled: !_isSubmitting,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'الاسم الكامل *',
                    hintText: 'محمد أحمد',
                    border: OutlineInputBorder(),
                  ),
                  validator: (String? v) {
                    final String t = (v ?? '').trim();
                    if (t.isEmpty) return 'الرجاء إدخال اسم الموظف';
                    if (t.length > 200) return 'الاسم طويل جدًا';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // ---- Position ----
                TextFormField(
                  controller: _positionController,
                  enabled: !_isSubmitting,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'المسمى الوظيفي',
                    hintText: 'كاشير / سائق / محاسب',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // ---- Phone ----
                TextFormField(
                  controller: _phoneController,
                  enabled: !_isSubmitting,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // ---- Email ----
                TextFormField(
                  controller: _emailController,
                  enabled: !_isSubmitting,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'البريد الإلكتروني',
                    border: OutlineInputBorder(),
                  ),
                  validator: (String? v) {
                    final String t = (v ?? '').trim();
                    if (t.isEmpty) return null;
                    final RegExp re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                    if (!re.hasMatch(t)) return 'بريد غير صحيح';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // ---- National ID ----
                TextFormField(
                  controller: _nationalIdController,
                  enabled: !_isSubmitting,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(20),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'الرقم القومي',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // ---- Base salary ----
                TextFormField(
                  controller: _baseSalaryController,
                  enabled: !_isSubmitting,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'الراتب الأساسي *',
                    hintText: '0',
                    border: OutlineInputBorder(),
                    suffixText: 'ج.م',
                  ),
                  validator: (String? v) {
                    final String t = (v ?? '').trim();
                    if (t.isEmpty) return 'الرجاء إدخال الراتب';
                    final double? d = double.tryParse(t);
                    if (d == null || d < 0) return 'قيمة غير صحيحة';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // ---- Hire date ----
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: _isSubmitting ? null : _pickHireDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'تاريخ التعيين',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    child: Text(
                      _hireDate == null
                          ? 'اختر التاريخ'
                          : _dateFmt.format(_hireDate!),
                      style: TextStyle(
                        color: _hireDate == null
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                    ),
                  ),
                ),
                if (_hireDate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: TextButton.icon(
                      onPressed: _isSubmitting
                          ? null
                          : () => setState(() => _hireDate = null),
                      icon: const Icon(Icons.close, size: 14),
                      label: const Text('مسح التاريخ'),
                    ),
                  ),
                const SizedBox(height: 12),

                // ---- Notes ----
                TextFormField(
                  controller: _notesController,
                  enabled: !_isSubmitting,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات',
                    border: OutlineInputBorder(),
                  ),
                ),

                // ---- Active toggle (edit only) ----
                if (_isEdit) ...<Widget>[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _isActive,
                    onChanged: _isSubmitting
                        ? null
                        : (bool v) => setState(() => _isActive = v),
                    title: const Text('موظف نشط'),
                    subtitle: const Text(
                      'الموظفون غير النشطين لا يظهرون في الرواتب الجديدة',
                    ),
                  ),
                ],

                if (_failure != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _FailureBanner(message: _failureMessage(_failure!)),
                ],

                const SizedBox(height: 20),

                AppButton(
                  label: _isEdit ? 'حفظ التعديلات' : 'إضافة الموظف',
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

String _failureMessage(EmployeeFailureType type) => switch (type) {
      EmployeeFailureType.network =>
        'تعذّر الاتصال بالخادم. تحقق من اتصالك.',
      EmployeeFailureType.unauthorized =>
        'لا تملك صلاحية إدارة الموظفين.',
      EmployeeFailureType.notFound => 'الموظف غير موجود.',
      EmployeeFailureType.invalidInput => 'تحقق من البيانات المُدخلة.',
      EmployeeFailureType.invalidResponse =>
        'تعذّر قراءة البيانات من الخادم.',
      EmployeeFailureType.unknown => 'حدث خطأ غير متوقع. حاول مرة أخرى.',
    };

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/app_button.dart';
import '../../domain/entities/sales_rep.dart';
import '../../domain/entities/sales_rep_candidate.dart';
import '../../domain/repositories/sales_rep_repository.dart';
import '../providers/sales_rep_providers.dart';

Future<bool?> showSalesRepFormSheet({
  required BuildContext context,
  required List<SalesRepCandidate> candidates,
  SalesRep? existing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _SalesRepFormSheet(
      existing: existing,
      candidates: candidates,
    ),
  );
}

class _SalesRepFormSheet extends ConsumerStatefulWidget {
  const _SalesRepFormSheet({
    required this.candidates,
    this.existing,
  });

  final List<SalesRepCandidate> candidates;
  final SalesRep? existing;

  @override
  ConsumerState<_SalesRepFormSheet> createState() =>
      _SalesRepFormSheetState();
}

class _SalesRepFormSheetState extends ConsumerState<_SalesRepFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _regionCtrl = TextEditingController();
  final TextEditingController _employeeCodeCtrl = TextEditingController();

  String? _selectedUserId;
  String? _selectedBranchId;
  String _repType = 'no_custody';
  bool _isActive = true;
  bool _isSubmitting = false;
  SalesRepFailureType? _failure;

  bool get _isEdit => widget.existing != null;

  List<SalesRepCandidate> get _availableCandidates {
    if (_isEdit) return const [];
    return widget.candidates.where((c) => !c.isAlreadyRep).toList();
  }

  @override
  void initState() {
    super.initState();
    final SalesRep? e = widget.existing;
    if (e != null) {
      _selectedUserId = e.userId;
      _selectedBranchId = e.branchId;
      _repType = e.repType;
      _phoneCtrl.text = e.phone ?? '';
      _regionCtrl.text = e.region ?? '';
      _employeeCodeCtrl.text = e.employeeCode ?? '';
      _isActive = e.isActive;
    } else {
      final avail = _availableCandidates;
      if (avail.isNotEmpty) _selectedUserId = avail.first.userId;
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _regionCtrl.dispose();
    _employeeCodeCtrl.dispose();
    super.dispose();
  }

  static String? _emptyToNull(String s) {
    final String t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_failure != null) setState(() => _failure = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedUserId == null || _selectedBranchId == null) return;

    setState(() => _isSubmitting = true);
    try {
      await ref.read(salesRepsProvider.notifier).upsert(
            userId: _selectedUserId!,
            repType: _repType,
            branchId: _selectedBranchId!,
            phone: _emptyToNull(_phoneCtrl.text),
            region: _emptyToNull(_regionCtrl.text),
            employeeCode: _emptyToNull(_employeeCodeCtrl.text),
            isActive: _isActive,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SalesRepException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _failure = e.type;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _failure = SalesRepFailureType.unknown;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final AsyncValue<List<Map<String, dynamic>>> branchesAsync =
        ref.watch(branchesForRepsProvider);

    if (!_isEdit && _availableCandidates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.info_outline, size: 48, color: scheme.primary),
            const SizedBox(height: 12),
            Text(
              'لا يوجد أعضاء متاحون لإضافتهم كمندوبين.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'أضف الأعضاء أولًا من صفحة "الفريق" أو "الصلاحيات والأدوار".',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'إغلاق',
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
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
                  _isEdit ? 'تعديل بيانات المندوب' : 'إضافة مندوب جديد',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'المندوب يجب أن يكون عضوًا نشطًا في الشركة.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),

                // ── العضو (dropdown في الإضافة، readonly في التعديل) ──
                if (_isEdit)
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'العضو',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(widget.existing!.fullName),
                  )
                else
                  DropdownButtonFormField<String>(
                    value: _selectedUserId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'العضو *',
                      border: OutlineInputBorder(),
                    ),
                    items: _availableCandidates
                        .map((c) => DropdownMenuItem<String>(
                              value: c.userId,
                              child: Text(
                                c.fullName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: _isSubmitting
                        ? null
                        : (v) => setState(() => _selectedUserId = v),
                    validator: (v) => v == null ? 'اختر عضوًا' : null,
                  ),
                const SizedBox(height: 12),

                // ── الفرع (إلزامي) ──
                branchesAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text(
                    'تعذّر تحميل الفروع',
                    style: TextStyle(color: Colors.red),
                  ),
                  data: (branches) => DropdownButtonFormField<String>(
                    value: _selectedBranchId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'الفرع *',
                      border: OutlineInputBorder(),
                    ),
                    items: branches
                        .map((b) => DropdownMenuItem<String>(
                              value: b['id'] as String,
                              child: Text(
                                b['name'] as String,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: _isSubmitting
                        ? null
                        : (v) => setState(() => _selectedBranchId = v),
                    validator: (v) => v == null ? 'اختر الفرع' : null,
                  ),
                ),
                const SizedBox(height: 12),

                // ── نوع العهدة ──
                DropdownButtonFormField<String>(
                  value: _repType,
                  decoration: const InputDecoration(
                    labelText: 'نوع العهدة *',
                    border: OutlineInputBorder(),
                  ),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(
                      value: 'no_custody',
                      child: Text('بدون عهدة'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'custody',
                      child: Text('عهدة'),
                    ),
                  ],
                  onChanged: _isSubmitting
                      ? null
                      : (v) => setState(() => _repType = v ?? 'no_custody'),
                ),
                const SizedBox(height: 12),

                // ── الهاتف ──
                TextFormField(
                  controller: _phoneCtrl,
                  enabled: !_isSubmitting,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                    border: OutlineInputBorder(),
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[0-9+\-\s]'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── كود الموظف ──
                TextFormField(
                  controller: _employeeCodeCtrl,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'كود الموظف (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // ── المنطقة ──
                TextFormField(
                  controller: _regionCtrl,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'المنطقة (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),

                // ── نشط (تعديل فقط) ──
                if (_isEdit) ...<Widget>[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _isActive,
                    onChanged: _isSubmitting
                        ? null
                        : (bool v) => setState(() => _isActive = v),
                    title: const Text('مندوب نشط'),
                    subtitle: const Text(
                      'المندوب غير النشط لا يظهر في شاشة POS',
                    ),
                  ),
                ],

                if (_failure != null) ...<Widget>[
                  const SizedBox(height: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.error_outline,
                            color: scheme.onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _failureMessage(_failure!),
                              style: TextStyle(
                                color: scheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                AppButton(
                  label: _isEdit ? 'حفظ التعديلات' : 'إضافة المندوب',
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

String _failureMessage(SalesRepFailureType type) => switch (type) {
      SalesRepFailureType.network =>
        'تعذّر الاتصال بالخادم. تحقق من اتصالك.',
      SalesRepFailureType.unauthorized =>
        'لا تملك صلاحية إدارة المندوبين.',
      SalesRepFailureType.permissionDenied =>
        'يتطلب دور مالك أو مدير أو مشرف.',
      SalesRepFailureType.validationFailed =>
        'تحقق من البيانات المُدخلة (الفرع، النوع، العضو).',
      SalesRepFailureType.notFound => 'المندوب غير موجود.',
      SalesRepFailureType.invalidResponse =>
        'تعذّر قراءة البيانات من الخادم.',
      SalesRepFailureType.unknown =>
        'حدث خطأ غير متوقع. حاول مرة أخرى.',
    };

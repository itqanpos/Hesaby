// lib/features/employees/presentation/pages/employees_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/entities/employee.dart';
import '../../domain/repositories/employee_repository.dart';
import '../providers/employee_providers.dart';
import '../widgets/employee_form_sheet.dart';

/// Employees list page.
///
/// Layout:
/// * KPI row (total / active / inactive).
/// * Search field.
/// * List of employees.
/// * FAB to add a new employee.
class EmployeesPage extends ConsumerStatefulWidget {
  const EmployeesPage({super.key});

  @override
  ConsumerState<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends ConsumerState<EmployeesPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 0,
  );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Employee> _filter(List<Employee> all) {
    final String q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((Employee e) {
      return e.fullName.toLowerCase().contains(q) ||
          (e.position ?? '').toLowerCase().contains(q) ||
          (e.phone ?? '').contains(q) ||
          (e.nationalId ?? '').contains(q);
    }).toList(growable: false);
  }

  Future<void> _openForm({Employee? existing}) async {
    final bool? saved = await showEmployeeFormSheet(
      context: context,
      existing: existing,
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(existing == null
                ? 'تم إضافة الموظف'
                : 'تم تحديث بيانات الموظف'),
          ),
        );
    }
  }

  Future<void> _confirmDelete(Employee employee) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('حذف الموظف'),
        content: Text(
          'هل تريد حذف "${employee.fullName}"؟\n'
          'لا يمكن التراجع عن هذا الإجراء.',
        ),
        actions: <Widget>[
          AppButton(
            label: 'إلغاء',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          AppButton(
            label: 'حذف',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await ref.read(employeesProvider.notifier).delete(employee.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الموظف')),
      );
    } on EmployeeException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_failureMessage(e.type))),
      );
    }
  }

  Future<void> _toggleActive(Employee employee) async {
    try {
      await ref.read(employeesProvider.notifier).updateEmployee(
            employeeId: employee.id,
            isActive: !employee.isActive,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            employee.isActive ? 'تم تعطيل الموظف' : 'تم تفعيل الموظف',
          ),
        ),
      );
    } on EmployeeException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_failureMessage(e.type))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Employee>> async = ref.watch(employeesProvider);
    final bool includeInactive =
        ref.watch(employeesIncludeInactiveProvider);

    return AppShell(
      appBar: AppBar(
        title: const Text('الموظفون'),
        actions: <Widget>[
          IconButton(
            tooltip: includeInactive
                ? 'إخفاء غير النشطين'
                : 'إظهار غير النشطين',
            icon: Icon(
              includeInactive
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            onPressed: () {
              ref
                  .read(employeesIncludeInactiveProvider.notifier)
                  .toggle();
            },
          ),
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(employeesProvider.notifier).refresh(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('موظف جديد'),
      ),
      body: async.when(
        loading: () => const AppLoader(),
        error: (Object e, StackTrace _) => AppErrorView(
          title: 'تعذّر تحميل الموظفين',
          message: e is EmployeeException
              ? _failureMessage(e.type)
              : 'حدث خطأ غير متوقع.',
          retryLabel: 'إعادة المحاولة',
          onRetry: () => ref.read(employeesProvider.notifier).refresh(),
        ),
        data: (List<Employee> all) {
          final List<Employee> filtered = _filter(all);
          final int total = all.length;
          final int active =
              all.where((Employee e) => e.isActive).length;
          final int inactive = total - active;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: _KpiRow(
                  total: total,
                  active: active,
                  inactive: inactive,
                  money: _money,
                  employees: all,
                ),
              ),
              AppTextField(
                controller: _searchController,
                hint: 'ابحث بالاسم أو المسمى أو الهاتف',
                prefixIcon: Icons.search,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'مسح',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                onChanged: (String v) => setState(() => _query = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: filtered.isEmpty
                    ? AppEmptyView(
                        icon: all.isEmpty
                            ? Icons.badge_outlined
                            : Icons.search_off_outlined,
                        title: all.isEmpty ? 'لا يوجد موظفون' : 'لا نتائج',
                        message: all.isEmpty
                            ? 'ابدأ بإضافة أول موظف لشركتك.'
                            : 'لم يُطابق أي موظف البحث.',
                        action: all.isEmpty
                            ? AppButton(
                                label: 'إضافة موظف',
                                icon: Icons.person_add_alt,
                                onPressed: () => _openForm(),
                              )
                            : null,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (BuildContext _, int i) {
                          final Employee e = filtered[i];
                          return _EmployeeCard(
                            employee: e,
                            money: _money,
                            onEdit: () => _openForm(existing: e),
                            onDelete: () => _confirmDelete(e),
                            onToggleActive: () => _toggleActive(e),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// KPI row
// ============================================================================

class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.total,
    required this.active,
    required this.inactive,
    required this.money,
    required this.employees,
  });

  final int total;
  final int active;
  final int inactive;
  final NumberFormat money;
  final List<Employee> employees;

  @override
  Widget build(BuildContext context) {
    final double totalSalaries = employees
        .where((Employee e) => e.isActive)
        .fold<double>(0, (double s, Employee e) => s + e.baseSalary);

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _KpiCard(
                icon: Icons.people_outline,
                label: 'الكل',
                value: '$total',
                color: const Color(0xFF0288D1),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiCard(
                icon: Icons.check_circle_outline,
                label: 'نشط',
                value: '$active',
                color: const Color(0xFF0F7B6C),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiCard(
                icon: Icons.pause_circle_outline,
                label: 'معطّل',
                value: '$inactive',
                color: const Color(0xFF7B5E3A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _KpiCard(
          icon: Icons.payments_outlined,
          label: 'إجمالي الرواتب الشهرية (النشطون)',
          value: money.format(totalSalaries),
          color: const Color(0xFF6A1B9A),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: <Widget>[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    value,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
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

// ============================================================================
// Employee card
// ============================================================================

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.employee,
    required this.money,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
  });

  final Employee employee;
  final NumberFormat money;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isActive = employee.isActive;
    final String initial = employee.fullName.trim().isEmpty
        ? '؟'
        : employee.fullName.characters.first.toUpperCase();

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                radius: 22,
                backgroundColor: isActive
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                foregroundColor: isActive
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
                child: Text(
                  initial,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            employee.fullName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!isActive)
                          _Badge(
                            label: 'معطّل',
                            background: scheme.surfaceContainerHighest,
                            foreground: scheme.onSurfaceVariant,
                          ),
                      ],
                    ),
                    if (employee.position != null) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        employee.position!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (employee.phone != null) ...<Widget>[
                      const SizedBox(height: 3),
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.phone_outlined,
                            size: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            employee.phone!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                            textDirection: TextDirection.ltr,
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      'راتب: ${money.format(employee.baseSalary)}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_EmployeeAction>(
                tooltip: 'خيارات',
                onSelected: (_EmployeeAction a) {
                  switch (a) {
                    case _EmployeeAction.edit:
                      onEdit();
                    case _EmployeeAction.toggle:
                      onToggleActive();
                    case _EmployeeAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (BuildContext _) =>
                    <PopupMenuEntry<_EmployeeAction>>[
                  const PopupMenuItem<_EmployeeAction>(
                    value: _EmployeeAction.edit,
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('تعديل'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem<_EmployeeAction>(
                    value: _EmployeeAction.toggle,
                    child: ListTile(
                      leading: Icon(
                        employee.isActive
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      title: Text(
                        employee.isActive ? 'تعطيل' : 'تفعيل',
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem<_EmployeeAction>(
                    value: _EmployeeAction.delete,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('حذف'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _EmployeeAction { edit, toggle, delete }

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

// ============================================================================
// Localization
// ============================================================================

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

// lib/features/employees/presentation/pages/salaries_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../domain/entities/employee.dart';
import '../../domain/entities/employee_advance.dart';
import '../../domain/entities/employee_salary.dart';
import '../../domain/repositories/employee_salary_repository.dart';
import '../providers/employee_providers.dart';
import '../providers/payroll_providers.dart';
import '../widgets/salary_form_sheet.dart';

/// Salaries management page.
class SalariesPage extends ConsumerWidget {
  const SalariesPage({super.key});

  static const List<String> _arabicMonths = <String>[
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  static String _monthLabel(DateTime month) =>
      '${_arabicMonths[month.month - 1]} ${month.year}';

  // ---------------------------------------------------------------------------
  // Generate drafts (مع أتمتة خصم السلف)
  // ---------------------------------------------------------------------------

  Future<void> _generateDrafts(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final DateTime month = ref.read(salaryMonthProvider);
    final List<Employee> employees =
        ref.read(employeesProvider).valueOrNull ?? const <Employee>[];
    final List<EmployeeSalary> existing =
        ref.read(salariesProvider).valueOrNull ?? const <EmployeeSalary>[];

    final Set<String> alreadyHas = <String>{
      for (final EmployeeSalary s in existing) s.employeeId,
    };

    final List<Employee> toCreate = employees
        .where((Employee e) => e.isActive && !alreadyHas.contains(e.id))
        .toList(growable: false);

    if (toCreate.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('كل الموظفين النشطين لديهم راتب لهذا الشهر.'),
          ),
        );
      return;
    }

    // ✅ حساب إجمالي السلف المتاحة لكل موظف
    final List<EmployeeAdvance> allAdvances =
        ref.read(advancesProvider).valueOrNull ?? const <EmployeeAdvance>[];
    
    final Map<String, double> employeeAdvances = <String, double>{};
    for (final EmployeeAdvance a in allAdvances) {
      if (!a.isFullyDeducted) {
        employeeAdvances[a.employeeId] = 
            (employeeAdvances[a.employeeId] ?? 0) + a.remainingAmount;
      }
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('توليد المسودات'),
        content: Text(
          'سيتم إنشاء ${AppFormatters.integer(toCreate.length)} سجل راتب '
          'بحالة مسودة بمبلغ الراتب الأساسي لكل موظف.\n\n'
          'الشهر: ${_monthLabel(month)}\n'
          'سيتم خصم السلف المتاحة تلقائياً.',
        ),
        actions: <Widget>[
          AppButton(
            label: 'إلغاء',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          AppButton(
            label: 'توليد',
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    int created = 0;
    int failed = 0;
    for (final Employee e in toCreate) {
      try {
        await ref.read(salariesProvider.notifier).create(
              employeeId: e.id,
              salaryMonth: month,
              baseAmount: e.baseSalary,
              advancesDeducted: employeeAdvances[e.id] ?? 0, // ✅ الخصم التلقائي
            );
        created++;
      } on Object {
        failed++;
      }
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? 'تم توليد ${AppFormatters.integer(created)} مسودة.'
                : 'تم توليد ${AppFormatters.integer(created)} مسودة. '
                    'فشل ${AppFormatters.integer(failed)}.',
          ),
        ),
      );
  }

  // ---------------------------------------------------------------------------
  // Edit / pay
  // ---------------------------------------------------------------------------

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    Employee employee,
    EmployeeSalary? salary,
  ) async {
    final DateTime month = ref.read(salaryMonthProvider);
    final bool? saved = await showSalaryFormSheet(
      context: context,
      employee: employee,
      salaryMonth: month,
      existing: salary,
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تم الحفظ.')),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<EmployeeSalary>> salariesAsync =
        ref.watch(salariesProvider);
    final AsyncValue<List<Employee>> employeesAsync =
        ref.watch(employeesProvider);
    final DateTime month = ref.watch(salaryMonthProvider);

    final bool anyLoading =
        salariesAsync.isLoading || employeesAsync.isLoading;
    final Object? firstError = salariesAsync.error ?? employeesAsync.error;

    return AppShell(
      appBar: AppBar(
        title: const Text('الرواتب'),
        actions: <Widget>[
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(salariesProvider.notifier).refresh();
              ref.invalidate(employeesProvider);
              ref.invalidate(advancesProvider);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: anyLoading
            ? null
            : () => _generateDrafts(context, ref),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('توليد المسودات'),
      ),
      body: Builder(
        builder: (BuildContext context) {
          if (anyLoading) return const AppLoader();
          if (firstError != null) {
            return AppErrorView(
              title: 'تعذّر تحميل الرواتب',
              message: firstError is SalaryException
                  ? _failureMessage(firstError.type)
                  : 'حدث خطأ غير متوقع.',
              retryLabel: 'إعادة المحاولة',
              onRetry: () {
                ref.invalidate(salariesProvider);
                ref.invalidate(employeesProvider);
              },
            );
          }

          final List<EmployeeSalary> salaries =
              salariesAsync.valueOrNull ?? const <EmployeeSalary>[];
          final List<Employee> employees = (employeesAsync.valueOrNull ??
                  const <Employee>[])
              .where((Employee e) => e.isActive)
              .toList(growable: false);

          final Map<String, Employee> byId = <String, Employee>{
            for (final Employee e in employees) e.id: e,
          };

          final double totalNet = salaries.fold<double>(
            0,
            (double s, EmployeeSalary sal) => s + sal.netAmount,
          );
          final double paidNet = salaries
              .where((EmployeeSalary s) => s.isPaid)
              .fold<double>(
                0,
                (double s, EmployeeSalary sal) => s + sal.netAmount,
              );
          final double unpaidNet = totalNet - paidNet;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ---- Month selector ----
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: _MonthSelector(
                  month: month,
                  onPrevious: () =>
                      ref.read(salaryMonthProvider.notifier).previous(),
                  onNext: () =>
                      ref.read(salaryMonthProvider.notifier).next(),
                  label: _monthLabel(month),
                ),
              ),

              // ---- KPI ----
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _KpiRow(
                  count: salaries.length,
                  total: totalNet,
                  paid: paidNet,
                  unpaid: unpaidNet,
                ),
              ),

              // ---- List ----
              Expanded(
                child: salaries.isEmpty
                    ? AppEmptyView(
                        icon: Icons.payments_outlined,
                        title: 'لا توجد رواتب لهذا الشهر',
                        message: 'اضغط "توليد المسودات" لإنشاء سجلات '
                            'لكل الموظفين النشطين.',
                        action: AppButton(
                          label: 'توليد المسودات',
                          icon: Icons.auto_awesome,
                          onPressed: () => _generateDrafts(context, ref),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: salaries.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (BuildContext _, int i) {
                          final EmployeeSalary s = salaries[i];
                          final Employee? emp = byId[s.employeeId];
                          return _SalaryCard(
                            salary: s,
                            employeeName: s.employeeName ??
                                emp?.fullName ??
                                'موظف',
                            onOpen: emp == null
                                ? null
                                : () => _openForm(context, ref, emp, s),
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
// Month selector
// ============================================================================

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.label,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DateTime now = DateTime.now();
    final bool isCurrentMonth =
        month.year == now.year && month.month == now.month;
    final bool canGoNext = !isCurrentMonth;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: <Widget>[
            IconButton(
              tooltip: 'الشهر السابق',
              icon: const Icon(Icons.chevron_right),
              onPressed: onPrevious,
            ),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              tooltip: 'الشهر التالي',
              icon: const Icon(Icons.chevron_left),
              onPressed: canGoNext ? onNext : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// KPI
// ============================================================================

class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.count,
    required this.total,
    required this.paid,
    required this.unpaid,
  });

  final int count;
  final double total;
  final double paid;
  final double unpaid;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _KpiCard(
                icon: Icons.people_outline,
                label: 'عدد السجلات',
                value: AppFormatters.integer(count),
                color: const Color(0xFF0288D1),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiCard(
                icon: Icons.summarize_outlined,
                label: 'الإجمالي',
                value: AppFormatters.money(total),
                color: const Color(0xFF6A1B9A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: _KpiCard(
                icon: Icons.check_circle_outline,
                label: 'مدفوع',
                value: AppFormatters.money(paid),
                color: const Color(0xFF0F7B6C),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiCard(
                icon: Icons.pending_outlined,
                label: 'غير مدفوع',
                value: AppFormatters.money(unpaid),
                color: const Color(0xFFE65100),
              ),
            ),
          ],
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
// Salary card
// ============================================================================

class _SalaryCard extends StatelessWidget {
  const _SalaryCard({
    required this.salary,
    required this.employeeName,
    required this.onOpen,
  });

  final EmployeeSalary salary;
  final String employeeName;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool paid = salary.isPaid;

    final Color statusColor =
        paid ? const Color(0xFF2E7D32) : const Color(0xFFE65100);

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: statusColor.withValues(alpha: 0.12),
                    foregroundColor: statusColor,
                    child: Icon(
                      paid
                          ? Icons.check_circle_outline
                          : Icons.pending_outlined,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          employeeName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          AppFormatters.longMonth(salary.salaryMonth),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppFormatters.money(salary.netAmount),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (onOpen != null) ...<Widget>[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_left,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: <Widget>[
                  _Badge(
                    label: paid ? 'مدفوع' : 'لم يُدفع',
                    color: statusColor,
                  ),
                  if (salary.bonuses > 0)
                    _Badge(
                      label: '+${AppFormatters.money(salary.bonuses)}',
                      color: const Color(0xFF0F7B6C),
                    ),
                  if (salary.deductions > 0)
                    _Badge(
                      label: '−${AppFormatters.money(salary.deductions)}',
                      color: const Color(0xFFC62828),
                    ),
                  if (salary.advancesDeducted > 0)
                    _Badge(
                      label: 'سلف: '
                          '${AppFormatters.money(salary.advancesDeducted)}',
                      color: const Color(0xFF6A1B9A),
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

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
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

String _failureMessage(SalaryFailureType type) => switch (type) {
      SalaryFailureType.network =>
        'تعذّر الاتصال بالخادم. تحقق من اتصالك.',
      SalaryFailureType.unauthorized =>
        'لا تملك صلاحية إدارة الرواتب.',
      SalaryFailureType.notFound => 'الراتب غير موجود.',
      SalaryFailureType.invalidInput => 'تحقق من المبالغ المُدخلة.',
      SalaryFailureType.duplicateEntry =>
        'يوجد راتب مسجَّل لهذا الموظف في هذا الشهر بالفعل.',
      SalaryFailureType.invalidResponse =>
        'تعذّر قراءة البيانات من الخادم.',
      SalaryFailureType.unknown => 'حدث خطأ غير متوقع. حاول مرة أخرى.',
    };

// lib/features/employees/presentation/pages/attendance_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

// ✅ [تم الحذف]: import '../../../../core/utils/formatters.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../domain/entities/attendance_record.dart';
import '../../domain/entities/employee.dart';
import '../../domain/repositories/attendance_repository.dart';
import '../providers/attendance_providers.dart';
import '../providers/employee_providers.dart';

class AttendancePage extends ConsumerStatefulWidget {
  const AttendancePage({super.key});

  @override
  ConsumerState<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends ConsumerState<AttendancePage> {
  Future<void> _pickDate() async {
    final DateTime current = ref.read(attendanceDateProvider);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'اختر تاريخ الحضور',
    );
    if (picked != null) {
      ref.read(attendanceDateProvider.notifier).setDate(picked);
    }
  }

  Future<void> _markAllPresent(List<Employee> employees) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('تحضير الجميع'),
        content: const Text('هل تريد تسجيل حضور جميع الموظفين النشطين لهذا اليوم؟'),
        actions: <Widget>[
          AppButton(
            label: 'إلغاء',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          AppButton(
            label: 'تأكيد',
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final notifier = ref.read(attendanceProvider.notifier);
    int success = 0;
    int failed = 0;

    for (final Employee e in employees) {
      try {
        await notifier.upsert(
          employeeId: e.id,
          status: AttendanceStatus.present,
        );
        success++;
      } on Object {
        failed++;
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? 'تم تحضير $success موظف.'
              : 'تم تحضير $success، وفشل $failed.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DateTime selectedDate = ref.watch(attendanceDateProvider);
    final AsyncValue<List<AttendanceRecord>> attendanceAsync =
        ref.watch(attendanceProvider);
    final AsyncValue<List<Employee>> employeesAsync =
        ref.watch(employeesProvider);

    final bool isLoading =
        attendanceAsync.isLoading || employeesAsync.isLoading;
    final Object? error = attendanceAsync.error ?? employeesAsync.error;

    return AppShell(
      appBar: AppBar(
        title: const Text('سجل الحضور'),
        actions: <Widget>[
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(attendanceProvider.notifier).refresh(),
          ),
        ],
      ),
      floatingActionButton: employeesAsync.valueOrNull == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _markAllPresent(
                employeesAsync.valueOrNull!
                    .where((Employee e) => e.isActive)
                    .toList(),
              ),
              icon: const Icon(Icons.done_all),
              label: const Text('تحضير الجميع'),
            ),
      body: Builder(
        builder: (BuildContext context) {
          if (isLoading) return const AppLoader();

          if (error != null) {
            return AppErrorView(
              title: 'تعذّر تحميل الحضور',
              message: error is AttendanceException
                  ? _failureMessage(error.type)
                  : 'حدث خطأ غير متوقع.',
              retryLabel: 'إعادة المحاولة',
              onRetry: () {
                ref.invalidate(attendanceProvider);
                ref.invalidate(employeesProvider);
              },
            );
          }

          final List<AttendanceRecord> records =
              attendanceAsync.valueOrNull ?? const <AttendanceRecord>[];
          final List<Employee> employees = (employeesAsync.valueOrNull ??
                  const <Employee>[])
              .where((Employee e) => e.isActive)
              .toList(growable: false);

          // تحويل السجلات إلى خريطة لسهولة الوصول
          final Map<String, AttendanceRecord> recordMap = {
            for (final r in records) r.employeeId: r,
          };

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ---- Date Selector ----
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: _DateSelectorCard(
                  date: selectedDate,
                  onTap: _pickDate,
                ),
              ),

              // ---- KPI ----
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _KpiRow(
                  total: employees.length,
                  present: records
                      .where((r) => r.status == AttendanceStatus.present)
                      .length,
                  absent: records
                      .where((r) => r.status == AttendanceStatus.absent)
                      .length,
                ),
              ),

              // ---- List ----
              Expanded(
                child: employees.isEmpty
                    ? const AppEmptyView(
                        icon: Icons.people_outline,
                        title: 'لا يوجد موظفون',
                        message: 'قم بإضافة موظفين أولاً من صفحة الفريق.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: employees.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (BuildContext _, int i) {
                          final Employee emp = employees[i];
                          final AttendanceRecord? record = recordMap[emp.id];
                          return _AttendanceCard(
                            employee: emp,
                            record: record,
                            onStatusChanged: (AttendanceStatus status) {
                              ref.read(attendanceProvider.notifier).upsert(
                                    employeeId: emp.id,
                                    status: status,
                                  );
                            },
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
// Date Selector
// ============================================================================

class _DateSelectorCard extends StatelessWidget {
  const _DateSelectorCard({required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String formattedDate =
        DateFormat('EEEE, d MMMM yyyy', 'ar').format(date);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.calendar_today_outlined, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                formattedDate,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// KPI Row
// ============================================================================

class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.total,
    required this.present,
    required this.absent,
  });

  final int total;
  final int present;
  final int absent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _KpiCard(
            icon: Icons.people_outline,
            label: 'الموظفون',
            value: total.toString(),
            color: const Color(0xFF0288D1),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            icon: Icons.check_circle_outline,
            label: 'حاضر',
            value: present.toString(),
            color: const Color(0xFF2E7D32),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            icon: Icons.cancel_outlined,
            label: 'غائب',
            value: absent.toString(),
            color: const Color(0xFFC62828),
          ),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Attendance Card
// ============================================================================

class _AttendanceCard extends StatelessWidget {
  const _AttendanceCard({
    required this.employee,
    required this.record,
    required this.onStatusChanged,
  });

  final Employee employee;
  final AttendanceRecord? record;
  final ValueChanged<AttendanceStatus> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AttendanceStatus? current = record?.status;

    Color getColor(AttendanceStatus status) {
      switch (status) {
        case AttendanceStatus.present:
          return const Color(0xFF2E7D32);
        case AttendanceStatus.absent:
          return const Color(0xFFC62828);
        case AttendanceStatus.late:
          return const Color(0xFFE65100);
        case AttendanceStatus.leave:
          return const Color(0xFF0288D1);
      }
    }

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Text(
                    employee.fullName.trim().isEmpty
                        ? '؟'
                        : employee.fullName.characters.first.toUpperCase(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        employee.fullName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (employee.position != null)
                        Text(
                          employee.position!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (current != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: getColor(current).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      current.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: getColor(current),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // أزرار الحضور
            Row(
              children: AttendanceStatus.values.map((status) {
                final bool isSelected = current == status;
                final Color color = getColor(status);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: InkWell(
                      onTap: () => onStatusChanged(status),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? color.withValues(alpha: 0.15)
                              : scheme.surfaceContainerHighest,
                          border: Border.all(
                            color: isSelected ? color : Colors.transparent,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: <Widget>[
                            Icon(
                              _getIcon(status),
                              size: 18,
                              color: isSelected ? color : scheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              status.label,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isSelected ? color : scheme.onSurfaceVariant,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIcon(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return Icons.check;
      case AttendanceStatus.absent:
        return Icons.close;
      case AttendanceStatus.late:
        return Icons.access_time;
      case AttendanceStatus.leave:
        return Icons.beach_access;
    }
  }
}

// ============================================================================
// Localization
// ============================================================================

String _failureMessage(AttendanceFailureType type) => switch (type) {
      AttendanceFailureType.network =>
        'تعذّر الاتصال بالخادم. تحقق من اتصالك.',
      AttendanceFailureType.unauthorized =>
        'لا تملك صلاحية إدارة الحضور.',
      AttendanceFailureType.notFound => 'السجل غير موجود.',
      AttendanceFailureType.invalidInput => 'تحقق من البيانات المدخلة.',
      AttendanceFailureType.invalidResponse =>
        'تعذّر قراءة البيانات من الخادم.',
      AttendanceFailureType.unknown => 'حدث خطأ غير متوقع. حاول مرة أخرى.',
    };

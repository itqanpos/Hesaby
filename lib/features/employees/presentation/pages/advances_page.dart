// lib/features/employees/presentation/pages/advances_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../domain/entities/employee_advance.dart';
import '../../domain/repositories/employee_advance_repository.dart';
import '../providers/payroll_providers.dart';
import '../widgets/advance_form_sheet.dart';

/// Advances management page.
class AdvancesPage extends ConsumerWidget {
  const AdvancesPage({super.key});

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );
  static final DateFormat _dateFmt = DateFormat('yyyy/MM/dd');

  Future<void> _openForm(BuildContext context) async {
    final bool? saved = await showAdvanceFormSheet(context: context);
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تم تسجيل السلفة.')),
        );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    EmployeeAdvance advance,
  ) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('حذف السلفة'),
        content: Text(
          'هل تريد حذف سلفة ${advance.employeeName ?? 'الموظف'} '
          'بمبلغ ${_money.format(advance.amount)}؟\n'
          'ستُحذف الحركة المرتبطة في الخزنة أيضًا.',
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
    if (ok != true || !context.mounted) return;

    try {
      await ref.read(advancesProvider.notifier).delete(advance.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف السلفة.')),
      );
    } on AdvanceException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_failureMessage(e.type))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<EmployeeAdvance>> async =
        ref.watch(advancesProvider);
    final bool onlyOpen = ref.watch(onlyOpenAdvancesProvider);

    return AppShell(
      appBar: AppBar(
        title: const Text('سلف الموظفين'),
        actions: <Widget>[
          IconButton(
            tooltip: onlyOpen ? 'إظهار الكل' : 'إظهار غير المخصوم فقط',
            icon: Icon(
              onlyOpen
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            onPressed: () {
              ref.read(onlyOpenAdvancesProvider.notifier).toggle();
            },
          ),
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(advancesProvider.notifier).refresh(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('سلفة جديدة'),
      ),
      body: async.when(
        loading: () => const AppLoader(),
        error: (Object e, StackTrace _) => AppErrorView(
          title: 'تعذّر تحميل السلف',
          message: e is AdvanceException
              ? _failureMessage(e.type)
              : 'حدث خطأ غير متوقع.',
          retryLabel: 'إعادة المحاولة',
          onRetry: () => ref.read(advancesProvider.notifier).refresh(),
        ),
        data: (List<EmployeeAdvance> all) {
          final int openCount =
              all.where((EmployeeAdvance a) => !a.isFullyDeducted).length;
          final double openAmount = all
              .where((EmployeeAdvance a) => !a.isFullyDeducted)
              .fold<double>(0, (double s, EmployeeAdvance a) =>
                  s + a.remainingAmount);
          final double totalPaid = all.fold<double>(
            0,
            (double s, EmployeeAdvance a) => s + a.amount,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: _KpiRow(
                  totalCount: all.length,
                  openCount: openCount,
                  openRemaining: openAmount,
                  totalPaid: totalPaid,
                  money: _money,
                ),
              ),
              Expanded(
                child: all.isEmpty
                    ? AppEmptyView(
                        icon: Icons.payments_outlined,
                        title: 'لا توجد سلف',
                        message: onlyOpen
                            ? 'لا توجد سلف غير مخصومة.'
                            : 'ابدأ بتسجيل أول سلفة لموظفيك.',
                        action: AppButton(
                          label: 'سلفة جديدة',
                          icon: Icons.add,
                          onPressed: () => _openForm(context),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: all.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (BuildContext _, int i) {
                          final EmployeeAdvance a = all[i];
                          return _AdvanceCard(
                            advance: a,
                            money: _money,
                            dateFmt: _dateFmt,
                            onDelete: () =>
                                _confirmDelete(context, ref, a),
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
// KPI
// ============================================================================

class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.totalCount,
    required this.openCount,
    required this.openRemaining,
    required this.totalPaid,
    required this.money,
  });

  final int totalCount;
  final int openCount;
  final double openRemaining;
  final double totalPaid;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _KpiCard(
                icon: Icons.receipt_long_outlined,
                label: 'إجمالي السلف',
                value: '$totalCount',
                color: const Color(0xFF0288D1),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiCard(
                icon: Icons.pending_outlined,
                label: 'غير مخصومة',
                value: '$openCount',
                color: const Color(0xFFE65100),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: _KpiCard(
                icon: Icons.money_off_outlined,
                label: 'متبقٍ للخصم',
                value: money.format(openRemaining),
                color: const Color(0xFFC62828),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiCard(
                icon: Icons.summarize_outlined,
                label: 'إجمالي المصروف',
                value: money.format(totalPaid),
                color: const Color(0xFF6A1B9A),
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
// Advance card
// ============================================================================

class _AdvanceCard extends StatelessWidget {
  const _AdvanceCard({
    required this.advance,
    required this.money,
    required this.dateFmt,
    required this.onDelete,
  });

  final EmployeeAdvance advance;
  final NumberFormat money;
  final DateFormat dateFmt;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool fullyDeducted = advance.isFullyDeducted;

    final Color statusColor = switch (advance.status) {
      AdvanceStatus.open => const Color(0xFFE65100),
      AdvanceStatus.partiallyDeducted => const Color(0xFFF9A825),
      AdvanceStatus.deducted => const Color(0xFF2E7D32),
    };

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.payments_outlined,
                    size: 20,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        advance.employeeName ?? 'موظف',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateFmt.format(advance.advanceDate),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      money.format(advance.amount),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.error,
                      ),
                    ),
                    if (!fullyDeducted) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        'متبقٍ: ${money.format(advance.remainingAmount)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
                IconButton(
                  tooltip: 'حذف',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    child: Text(
                      advance.status.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (advance.reason != null) ...<Widget>[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      advance.reason!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
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

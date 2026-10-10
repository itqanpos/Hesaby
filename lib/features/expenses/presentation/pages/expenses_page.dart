// lib/features/expenses/presentation/pages/expenses_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/entities/expense.dart';
import '../../domain/repositories/expense_repository.dart';
import '../providers/expense_providers.dart';
import '../widgets/expense_form_sheet.dart';

/// Expenses list page.
class ExpensesPage extends ConsumerStatefulWidget {
  const ExpensesPage({super.key});

  @override
  ConsumerState<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends ConsumerState<ExpensesPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );
  static final DateFormat _dateFmt = DateFormat('yyyy/MM/dd');

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Expense> _filter(List<Expense> all) {
    final String q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((Expense e) {
      return e.description.toLowerCase().contains(q) ||
          (e.categoryName ?? '').toLowerCase().contains(q) ||
          (e.reference ?? '').toLowerCase().contains(q);
    }).toList(growable: false);
  }

  Future<void> _openForm({Expense? existing}) async {
    final bool? saved = await showExpenseFormSheet(
      context: context,
      existing: existing,
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(existing == null
                ? 'تم تسجيل المصروف'
                : 'تم تحديث المصروف'),
          ),
        );
    }
  }

  Future<void> _confirmDelete(Expense expense) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('حذف المصروف'),
        content: Text(
          'هل تريد حذف "${expense.description}"?\n'
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
      await ref.read(expensesProvider.notifier).delete(expense.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف المصروف')),
      );
    } on ExpenseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_failureMessage(e.type))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Expense>> async = ref.watch(expensesProvider);
    final ExpenseFilter filter = ref.watch(expenseFilterProvider);

    return AppShell(
      appBar: AppBar(
        title: const Text('المصروفات'),
        actions: <Widget>[
          if (!filter.isEmpty)
            IconButton(
              tooltip: 'مسح الفلاتر',
              icon: const Icon(Icons.filter_alt_off_outlined),
              onPressed: () =>
                  ref.read(expenseFilterProvider.notifier).clear(),
            ),
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(expensesProvider.notifier).refresh(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.receipt_long_outlined),
        label: const Text('مصروف جديد'),
      ),
      body: async.when(
        loading: () => const AppLoader(),
        error: (Object e, StackTrace _) => AppErrorView(
          title: 'تعذّر تحميل المصروفات',
          message: e is ExpenseException
              ? _failureMessage(e.type)
              : 'حدث خطأ غير متوقع.',
          retryLabel: 'إعادة المحاولة',
          onRetry: () => ref.read(expensesProvider.notifier).refresh(),
        ),
        data: (List<Expense> all) {
          final List<Expense> filtered = _filter(all);
          final double total =
              all.fold<double>(0, (double s, Expense e) => s + e.amount);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: _KpiRow(
                  count: all.length,
                  total: total,
                  money: _money,
                ),
              ),
              AppTextField(
                controller: _searchController,
                hint: 'ابحث بالوصف أو التصنيف',
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
                            ? Icons.receipt_long_outlined
                            : Icons.search_off_outlined,
                        title: all.isEmpty ? 'لا مصروفات' : 'لا نتائج',
                        message: all.isEmpty
                            ? 'ابدأ بتسجيل أول مصروف للشركة.'
                            : 'لم يُطابق أي مصروف البحث.',
                        action: all.isEmpty
                            ? AppButton(
                                label: 'مصروف جديد',
                                icon: Icons.add,
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
                          final Expense e = filtered[i];
                          return _ExpenseCard(
                            expense: e,
                            money: _money,
                            dateFmt: _dateFmt,
                            onEdit: () => _openForm(existing: e),
                            onDelete: () => _confirmDelete(e),
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
    required this.count,
    required this.total,
    required this.money,
  });

  final int count;
  final double total;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _KpiCard(
            icon: Icons.receipt_long_outlined,
            label: 'عدد المصروفات',
            value: '$count',
            color: const Color(0xFF0288D1),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            icon: Icons.trending_down_outlined,
            label: 'الإجمالي',
            value: money.format(total),
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
// Expense card
// ============================================================================

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({
    required this.expense,
    required this.money,
    required this.dateFmt,
    required this.onEdit,
    required this.onDelete,
  });

  final Expense expense;
  final NumberFormat money;
  final DateFormat dateFmt;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.trending_down_outlined,
                  color: scheme.error,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      expense.description,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        if (expense.categoryName != null) ...<Widget>[
                          Icon(
                            Icons.category_outlined,
                            size: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            expense.categoryName!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          dateFmt.format(expense.expenseDate),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    '-${money.format(expense.amount)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.error,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  PopupMenuButton<_ExpenseAction>(
                    tooltip: 'خيارات',
                    onSelected: (_ExpenseAction a) {
                      switch (a) {
                        case _ExpenseAction.edit:
                          onEdit();
                        case _ExpenseAction.delete:
                          onDelete();
                      }
                    },
                    itemBuilder: (BuildContext _) =>
                        <PopupMenuEntry<_ExpenseAction>>[
                      const PopupMenuItem<_ExpenseAction>(
                        value: _ExpenseAction.edit,
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('تعديل'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem<_ExpenseAction>(
                        value: _ExpenseAction.delete,
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
            ],
          ),
        ),
      ),
    );
  }
}

enum _ExpenseAction { edit, delete }

// ============================================================================
// Localization
// ============================================================================

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

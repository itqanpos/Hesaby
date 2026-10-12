// lib/features/cash/presentation/pages/cash_reports_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../domain/entities/cash_report_entities.dart';
import '../providers/cash_report_providers.dart';

/// Cash reports page — three views over the cash ledger:
/// * **ملخص** — opening / in / out / closing for the period.
/// * **تصنيفات** — totals grouped by category.
/// * **حسابات** — totals grouped by account.
class CashReportsPage extends ConsumerStatefulWidget {
  const CashReportsPage({super.key});

  @override
  ConsumerState<CashReportsPage> createState() => _CashReportsPageState();
}

class _CashReportsPageState extends ConsumerState<CashReportsPage> {
  _ReportView _view = _ReportView.summary;

  @override
  Widget build(BuildContext context) {
    final CashReportPeriod period = ref.watch(cashReportPeriodProvider);
    final AsyncValue<CashReportBundle> async =
        ref.watch(cashReportsProvider);

    return AppShell(
      appBar: AppBar(
        title: const Text('تقارير الخزنة'),
        actions: <Widget>[
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(cashReportsProvider.notifier).refresh(),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ---- Period selector ----
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 12),
            child: _PeriodSelector(
              current: period.type,
              onSelect: (CashReportPeriodType type) {
                ref
                    .read(cashReportPeriodProvider.notifier)
                    .setType(type);
              },
            ),
          ),

          // ---- View selector ----
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ViewSelector(
              current: _view,
              onSelect: (_ReportView v) => setState(() => _view = v),
            ),
          ),

          // ---- Content ----
          Expanded(
            child: async.when(
              loading: () => const AppLoader(),
              error: (Object error, StackTrace _) => AppErrorView(
                title: 'تعذّر تحميل التقرير',
                message: 'حدث خطأ أثناء تجميع البيانات. حاول مرة أخرى.',
                retryLabel: 'إعادة المحاولة',
                onRetry: () =>
                    ref.read(cashReportsProvider.notifier).refresh(),
              ),
              data: (CashReportBundle bundle) {
                switch (_view) {
                  case _ReportView.summary:
                    return _SummaryView(bundle: bundle);
                  case _ReportView.categories:
                    return _CategoriesView(items: bundle.byCategory);
                  case _ReportView.accounts:
                    return _AccountsView(items: bundle.byAccount);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

enum _ReportView { summary, categories, accounts }

// ============================================================================
// Period selector
// ============================================================================

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.current,
    required this.onSelect,
  });

  final CashReportPeriodType current;
  final ValueChanged<CashReportPeriodType> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: <Widget>[
          for (final CashReportPeriodType t
              in CashReportPeriodType.values) ...<Widget>[
            ChoiceChip(
              label: Text(_label(t)),
              selected: current == t,
              onSelected: (_) => onSelect(t),
              showCheckmark: false,
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  static String _label(CashReportPeriodType type) => switch (type) {
        CashReportPeriodType.today => 'اليوم',
        CashReportPeriodType.thisMonth => 'هذا الشهر',
        CashReportPeriodType.thisYear => 'هذا العام',
        CashReportPeriodType.all => 'كل الفترات',
      };
}

// ============================================================================
// View selector
// ============================================================================

class _ViewSelector extends StatelessWidget {
  const _ViewSelector({
    required this.current,
    required this.onSelect,
  });

  final _ReportView current;
  final ValueChanged<_ReportView> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SegmentedButton<_ReportView>(
        segments: const <ButtonSegment<_ReportView>>[
          ButtonSegment<_ReportView>(
            value: _ReportView.summary,
            label: Text('ملخص'),
            icon: Icon(Icons.dashboard_outlined, size: 16),
          ),
          ButtonSegment<_ReportView>(
            value: _ReportView.categories,
            label: Text('تصنيفات'),
            icon: Icon(Icons.category_outlined, size: 16),
          ),
          ButtonSegment<_ReportView>(
            value: _ReportView.accounts,
            label: Text('حسابات'),
            icon: Icon(Icons.account_balance_wallet_outlined, size: 16),
          ),
        ],
        selected: <_ReportView>{current},
        onSelectionChanged: (Set<_ReportView> s) => onSelect(s.first),
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

// ============================================================================
// Summary view
// ============================================================================

class _SummaryView extends StatelessWidget {
  const _SummaryView({required this.bundle});

  final CashReportBundle bundle;

  @override
  Widget build(BuildContext context) {
    final CashFlowSummary s = bundle.summary;

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      children: <Widget>[
        // ---- Flow card ----
        _FlowCard(summary: s),
        const SizedBox(height: 12),

        // ---- KPIs ----
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _KpiCard(
                  icon: Icons.arrow_downward,
                  label: 'إجمالي الوارد',
                  value: AppFormatters.money(s.totalIn),
                  color: const Color(0xFF0F7B6C),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KpiCard(
                  icon: Icons.arrow_upward,
                  label: 'إجمالي الصادر',
                  value: AppFormatters.money(s.totalOut),
                  color: const Color(0xFFC62828),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _KpiCard(
                  icon: Icons.receipt_long_outlined,
                  label: 'عدد الحركات',
                  value: AppFormatters.integer(s.transactionCount),
                  color: const Color(0xFF0288D1),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KpiCard(
                  icon: Icons.trending_up,
                  label: 'صافي التغيير',
                  value: AppFormatters.money(s.netChange),
                  color: s.netChange >= 0
                      ? const Color(0xFF0F7B6C)
                      : const Color(0xFFC62828),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FlowCard extends StatelessWidget {
  const _FlowCard({required this.summary});

  final CashFlowSummary summary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'التدفق النقدي',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              _FlowRow(
                label: 'الرصيد الافتتاحي',
                value: AppFormatters.money(summary.openingBalance),
              ),
              _FlowRow(
                label: 'الوارد (+)',
                value: AppFormatters.money(summary.totalIn),
                color: const Color(0xFF0F7B6C),
              ),
              _FlowRow(
                label: 'الصادر (−)',
                value: AppFormatters.money(summary.totalOut),
                color: const Color(0xFFC62828),
              ),
              const Divider(height: 20),
              _FlowRow(
                label: 'الرصيد الختامي',
                value: AppFormatters.money(summary.closingBalance),
                emphasized: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlowRow extends StatelessWidget {
  const _FlowRow({
    required this.label,
    required this.value,
    this.color,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final Color? color;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: emphasized
                  ? theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    )
                  : theme.textTheme.bodyMedium,
            ),
          ),
          Text(
            value,
            style: (emphasized
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.bodyLarge)
                ?.copyWith(
              color: color ?? scheme.onSurface,
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Categories view
// ============================================================================

class _CategoriesView extends StatelessWidget {
  const _CategoriesView({required this.items});

  final List<CashCategoryBreakdown> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const AppEmptyView(
        icon: Icons.category_outlined,
        title: 'لا توجد حركات',
        message: 'لا توجد حركات في هذه الفترة لعرض تصنيفاتها.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext _, int i) => _BreakdownCard(
        title: items[i].categoryName,
        icon: Icons.category_outlined,
        totalIn: items[i].totalIn,
        totalOut: items[i].totalOut,
        count: items[i].count,
      ),
    );
  }
}

// ============================================================================
// Accounts view
// ============================================================================

class _AccountsView extends StatelessWidget {
  const _AccountsView({required this.items});

  final List<CashAccountBreakdown> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const AppEmptyView(
        icon: Icons.account_balance_wallet_outlined,
        title: 'لا توجد حركات',
        message: 'لا توجد حركات في هذه الفترة لعرض الحسابات.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext _, int i) => _BreakdownCard(
        title: items[i].accountName,
        icon: Icons.account_balance_wallet_outlined,
        totalIn: items[i].totalIn,
        totalOut: items[i].totalOut,
        count: items[i].count,
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.title,
    required this.icon,
    required this.totalIn,
    required this.totalOut,
    required this.count,
  });

  final String title;
  final IconData icon;
  final double totalIn;
  final double totalOut;
  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double net = totalIn - totalOut;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: scheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${AppFormatters.integer(count)} حركة',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _MiniStat(
                      label: 'وارد',
                      value: AppFormatters.money(totalIn),
                      color: const Color(0xFF0F7B6C),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MiniStat(
                      label: 'صادر',
                      value: AppFormatters.money(totalOut),
                      color: const Color(0xFFC62828),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MiniStat(
                      label: 'الصافي',
                      value: AppFormatters.money(net),
                      color: net >= 0
                          ? const Color(0xFF0F7B6C)
                          : const Color(0xFFC62828),
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

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ============================================================================
// KPI card
// ============================================================================

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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: color),
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

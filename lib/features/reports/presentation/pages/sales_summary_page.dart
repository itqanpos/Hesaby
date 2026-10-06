// lib/features/reports/presentation/pages/sales_summary_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/report_period.dart';
import '../../domain/entities/sales_reports.dart';
import '../../domain/repositories/reports_repository.dart';
import '../providers/reports_providers.dart';
import '../widgets/report_page_scaffold.dart';

/// Sales summary report page.
///
/// Shows aggregated KPIs for the selected company over the selected period:
/// gross sales, net sales (after returns), collected, outstanding, drafts,
/// cancellations, returns, and derived metrics (average invoice, collection
/// ratio).
class SalesSummaryPage extends ConsumerStatefulWidget {
  const SalesSummaryPage({super.key});

  @override
  ConsumerState<SalesSummaryPage> createState() => _SalesSummaryPageState();
}

class _SalesSummaryPageState extends ConsumerState<SalesSummaryPage> {
  static final NumberFormat _money = NumberFormat.currency(
    locale: 'ar_EG',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );
  static final NumberFormat _percent = NumberFormat.decimalPercentPattern(
    locale: 'ar_EG',
    decimalDigits: 1,
  );

  Future<void> _changePeriod(ReportPeriod newPeriod) async {
    ref.read(reportPagePeriodProvider.notifier).setPeriod(newPeriod);
    // Force refresh of the summary with the new period.
    final ReportPeriod p = ref.read(reportPagePeriodProvider);
    await ref
        .read(salesSummaryProvider(p).future)
        .catchError((_) => SalesSummary.empty(p));
  }

  @override
  Widget build(BuildContext context) {
    final ReportPeriod period = ref.watch(reportPagePeriodProvider);
    final AsyncValue<SalesSummary> summaryAsync =
        ref.watch(salesSummaryProvider(period));

    return ReportPageScaffold(
      title: 'ملخص المبيعات',
      period: period,
      onPeriodChanged: _changePeriod,
      isLoading: summaryAsync.isLoading,
      errorMessage: summaryAsync.hasError
          ? _errorMessage(summaryAsync.error!)
          : null,
      onRetry: () => ref.invalidate(salesSummaryProvider(period)),
      body: summaryAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
        data: (SalesSummary summary) => _SummaryBody(
          summary: summary,
          money: _money,
          percent: _percent,
        ),
      ),
    );
  }

  static String _errorMessage(Object error) {
    if (error is ReportException) {
      switch (error.type) {
        case ReportFailureType.network:
          return 'تعذّر الاتصال بالخادم.';
        case ReportFailureType.unauthorized:
          return 'انتهت صلاحية الجلسة.';
        case ReportFailureType.notFound:
          return 'البيانات المطلوبة غير متوفرة.';
        case ReportFailureType.invalidResponse:
          return 'تعذّر قراءة البيانات.';
        case ReportFailureType.unknown:
          return 'تعذّر تحميل التقرير.';
      }
    }
    return 'تعذّر تحميل التقرير.';
  }
}

// ============================================================================
// Body
// ============================================================================

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({
    required this.summary,
    required this.money,
    required this.percent,
  });

  final SalesSummary summary;
  final NumberFormat money;
  final NumberFormat percent;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        _PeriodHeader(period: summary.period),
        const SizedBox(height: 12),
        _HeroCard(
          title: 'صافي المبيعات',
          value: money.format(summary.netSales),
          subtitle: 'من ${summary.confirmedCount} فاتورة مؤكدة',
        ),
        const SizedBox(height: 12),
        _StatsGrid(
          summary: summary,
          money: money,
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'تفاصيل الفواتير',
          rows: <_RowData>[
            _RowData('مؤكدة', '${summary.confirmedCount}'),
            _RowData('مسودة', '${summary.draftCount}'),
            _RowData('ملغاة', '${summary.cancelledCount}'),
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'الإيرادات والخصومات',
          rows: <_RowData>[
            _RowData('إجمالي المبيعات', money.format(summary.totalSales)),
            _RowData('إجمالي الخصومات', money.format(summary.totalDiscount)),
            _RowData('إجمالي الضريبة', money.format(summary.totalTax)),
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'المرتجعات',
          rows: <_RowData>[
            _RowData('عدد المرتجعات', '${summary.returnCount}'),
            _RowData('قيمة المرتجعات', money.format(summary.returnTotal)),
            _RowData(
              'نسبة المرتجعات',
              summary.totalSales > 0
                  ? percent.format(summary.returnTotal / summary.totalSales)
                  : '—',
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================================
// Period header
// ============================================================================

class _PeriodHeader extends StatelessWidget {
  const _PeriodHeader({required this.period});

  final ReportPeriod period;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: <Widget>[
          Icon(Icons.event_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              period.label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Hero card
// ============================================================================

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: <Color>[
            scheme.primary,
            scheme.primaryContainer,
          ],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onPrimary.withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.displaySmall?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onPrimary.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Stats grid (2x2)
// ============================================================================

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.summary,
    required this.money,
  });

  final SalesSummary summary;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _StatCard(
                icon: Icons.receipt_long_outlined,
                color: const Color(0xFF0F7B6C),
                label: 'إجمالي المبيعات',
                value: money.format(summary.totalSales),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                icon: Icons.account_balance_wallet_outlined,
                color: const Color(0xFF2E7D32),
                label: 'المحصَّل',
                value: money.format(summary.totalPaid),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: _StatCard(
                icon: Icons.error_outline,
                color: const Color(0xFFC62828),
                label: 'غير محصَّل',
                value: money.format(summary.totalDue),
                emphasize: summary.totalDue > 0,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                icon: Icons.calculate_outlined,
                color: const Color(0xFF0288D1),
                label: 'متوسط الفاتورة',
                value: money.format(summary.averageInvoice),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: emphasize
              ? color.withValues(alpha: 0.5)
              : scheme.outlineVariant,
          width: emphasize ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: emphasize ? color : scheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Section card
// ============================================================================

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.rows});

  final String title;
  final List<_RowData> rows;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < rows.length; i++) ...<Widget>[
              _row(theme, scheme, rows[i]),
              if (i < rows.length - 1) const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, ColorScheme scheme, _RowData data) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            data.label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          data.value,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _RowData {
  const _RowData(this.label, this.value);
  final String label;
  final String value;
}

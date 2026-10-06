// lib/features/reports/presentation/pages/profit_loss_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/financial_reports.dart';
import '../../domain/entities/report_document.dart';
import '../../domain/entities/report_period.dart';
import '../../domain/repositories/reports_repository.dart';
import '../providers/reports_providers.dart';
import '../widgets/report_page_scaffold.dart';
import '../widgets/report_print_action.dart';

class ProfitLossPage extends ConsumerStatefulWidget {
  const ProfitLossPage({super.key});

  @override
  ConsumerState<ProfitLossPage> createState() => _ProfitLossPageState();
}

class _ProfitLossPageState extends ConsumerState<ProfitLossPage> {
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
    final ReportPeriod p = ref.read(reportPagePeriodProvider);
    await ref
        .read(profitLossProvider(p).future)
        .catchError((_) => ProfitLossSummary.empty(p));
  }

  ReportDocument? _buildDocument(
    ReportPeriod period,
    ProfitLossSummary report,
  ) {
    if (report.grossRevenue == 0 &&
        report.returnTotal == 0 &&
        report.costOfGoodsSold == 0) {
      return null;
    }

    return ReportDocument(
      title: 'الأرباح والخسائر',
      periodLabel: period.label,
      companyName: '—',
      generatedAt: DateTime.now(),
      sections: <ReportSection>[
        ReportSection(
          kpis: <ReportKpi>[
            ReportKpi(
              label: report.isProfitable ? 'صافي الربح' : 'صافي الخسارة',
              value: _money.format(report.netProfit.abs()),
              emphasized: true,
            ),
            ReportKpi(
              label: 'صافي الإيرادات',
              value: _money.format(report.netRevenue),
            ),
            ReportKpi(
              label: 'تكلفة المبيعات',
              value: _money.format(report.costOfGoodsSold),
            ),
            ReportKpi(
              label: 'هامش الربح',
              value: report.netRevenue > 0
                  ? _percent.format(report.netMargin)
                  : '—',
            ),
          ],
        ),
        ReportSection(
          title: 'الإيرادات',
          lines: <ReportLine>[
            ReportLine(
              label: 'إجمالي المبيعات',
              value: _money.format(report.grossRevenue),
            ),
            if (report.returnTotal > 0)
              ReportLine(
                label: 'المرتجعات',
                value: '−${_money.format(report.returnTotal)}',
              ),
            ReportLine(
              label: 'صافي الإيرادات',
              value: _money.format(report.netRevenue),
              emphasized: true,
            ),
          ],
        ),
        ReportSection(
          title: 'التكاليف',
          lines: <ReportLine>[
            ReportLine(
              label: 'تكلفة المبيعات (COGS)',
              value: _money.format(report.costOfGoodsSold),
            ),
            ReportLine(
              label: 'المصروفات التشغيلية',
              value: _money.format(report.operatingExpenses),
            ),
            ReportLine(
              label: 'إجمالي التكاليف',
              value: _money.format(
                report.costOfGoodsSold + report.operatingExpenses,
              ),
              emphasized: true,
            ),
          ],
        ),
        ReportSection(
          title: 'النتيجة',
          lines: <ReportLine>[
            ReportLine(
              label: 'الربح الإجمالي',
              value: _money.format(report.grossProfit),
            ),
            ReportLine(
              label: 'صافي الربح',
              value: _money.format(report.netProfit),
              emphasized: true,
            ),
            ReportLine(
              label: 'هامش الربح الإجمالي',
              value: report.netRevenue > 0
                  ? _percent.format(report.grossMargin)
                  : '—',
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ReportPeriod period = ref.watch(reportPagePeriodProvider);
    final AsyncValue<ProfitLossSummary> reportAsync =
        ref.watch(profitLossProvider(period));

    return ReportPageScaffold(
      title: 'الأرباح والخسائر',
      period: period,
      onPeriodChanged: _changePeriod,
      isLoading: reportAsync.isLoading,
      errorMessage:
          reportAsync.hasError ? _errorMessage(reportAsync.error!) : null,
      onRetry: () => ref.invalidate(profitLossProvider(period)),
      trailing: ReportPrintAction(
        documentBuilder: () {
          final ProfitLossSummary? report = reportAsync.valueOrNull;
          if (report == null) return null;
          return _buildDocument(period, report);
        },
      ),
      body: reportAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
        data: (ProfitLossSummary report) => _Body(
          report: report,
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

class _Body extends StatelessWidget {
  const _Body({
    required this.report,
    required this.money,
    required this.percent,
  });

  final ProfitLossSummary report;
  final NumberFormat money;
  final NumberFormat percent;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        _PeriodHeader(period: report.period),
        const SizedBox(height: 12),
        _HeroCard(report: report, money: money, percent: percent),
        const SizedBox(height: 16),
        _BreakdownCard(
          title: 'الإيرادات',
          tone: const Color(0xFF0F7B6C),
          rows: <_RowData>[
            _RowData('إجمالي المبيعات', money.format(report.grossRevenue)),
            if (report.returnTotal > 0)
              _RowData(
                'المرتجعات',
                '−${money.format(report.returnTotal)}',
              ),
            _RowData(
              'صافي الإيرادات',
              money.format(report.netRevenue),
              emphasized: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _BreakdownCard(
          title: 'التكاليف',
          tone: const Color(0xFFC62828),
          rows: <_RowData>[
            _RowData(
              'تكلفة المبيعات (COGS)',
              money.format(report.costOfGoodsSold),
            ),
            _RowData(
              'المصروفات التشغيلية',
              money.format(report.operatingExpenses),
            ),
            _RowData(
              'إجمالي التكاليف',
              money.format(
                report.costOfGoodsSold + report.operatingExpenses,
              ),
              emphasized: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _BreakdownCard(
          title: 'النتيجة',
          tone: report.isProfitable
              ? const Color(0xFF2E7D32)
              : const Color(0xFFC62828),
          rows: <_RowData>[
            _RowData(
              'الربح الإجمالي',
              money.format(report.grossProfit),
            ),
            _RowData(
              'صافي الربح',
              money.format(report.netProfit),
              emphasized: true,
            ),
            _RowData(
              'هامش الربح الإجمالي',
              report.netRevenue > 0
                  ? percent.format(report.grossMargin)
                  : '—',
            ),
          ],
        ),
      ],
    );
  }
}

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

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.report,
    required this.money,
    required this.percent,
  });

  final ProfitLossSummary report;
  final NumberFormat money;
  final NumberFormat percent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool positive = report.isProfitable;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: positive
              ? <Color>[
                  const Color(0xFF2E7D32),
                  const Color(0xFF66BB6A),
                ]
              : <Color>[scheme.error, scheme.errorContainer],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: (positive ? const Color(0xFF2E7D32) : scheme.error)
                .withValues(alpha: 0.25),
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
            Row(
              children: <Widget>[
                Icon(
                  positive ? Icons.trending_up : Icons.trending_down,
                  color: scheme.onPrimary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  positive ? 'صافي الربح' : 'صافي الخسارة',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onPrimary.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              money.format(report.netProfit.abs()),
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
              report.netRevenue > 0
                  ? 'هامش: ${percent.format(report.netMargin)} · '
                      'إيرادات: ${money.format(report.netRevenue)}'
                  : 'لا توجد إيرادات في هذه الفترة',
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

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.title,
    required this.tone,
    required this.rows,
  });

  final String title;
  final Color tone;
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
            Row(
              children: <Widget>[
                Container(
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    color: tone,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
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
            style: (data.emphasized
                    ? theme.textTheme.titleSmall
                    : theme.textTheme.bodyMedium)
                ?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight:
                  data.emphasized ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ),
        Text(
          data.value,
          style: (data.emphasized
                  ? theme.textTheme.titleSmall
                  : theme.textTheme.bodyLarge)
              ?.copyWith(
            fontWeight: data.emphasized ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _RowData {
  const _RowData(this.label, this.value, {this.emphasized = false});
  final String label;
  final String value;
  final bool emphasized;
}

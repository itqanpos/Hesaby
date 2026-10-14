// lib/features/reports/presentation/pages/payables_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../domain/entities/financial_reports.dart';
import '../../domain/entities/report_document.dart';
import '../../domain/entities/report_period.dart';
import '../../domain/repositories/reports_repository.dart';
import '../providers/reports_providers.dart';
import '../widgets/report_page_scaffold.dart';
import '../widgets/report_print_action.dart';

class PayablesPage extends ConsumerStatefulWidget {
  const PayablesPage({super.key});

  @override
  ConsumerState<PayablesPage> createState() => _PayablesPageState();
}

class _PayablesPageState extends ConsumerState<PayablesPage> {
  Future<void> _changePeriod(ReportPeriod newPeriod) async {
    ref.read(reportPagePeriodProvider.notifier).setPeriod(newPeriod);
    final ReportPeriod p = ref.read(reportPagePeriodProvider);
    await ref
        .read(payablesProvider(p).future)
        .catchError((_) => PayablesReport.empty(p));
  }

  ReportDocument? _buildDocument(
    ReportPeriod period,
    PayablesReport report,
  ) {
    if (report.isEmpty) return null;

    return ReportDocument(
      title: 'الموردون',
      periodLabel: period.label,
      companyName: '—',
      generatedAt: DateTime.now(),
      sections: <ReportSection>[
        ReportSection(
          kpis: <ReportKpi>[
            ReportKpi(
              label: 'إجمالي المشتريات',
              value: AppFormatters.money(report.totalPurchases),
              emphasized: true,
            ),
            ReportKpi(
              label: 'المدفوع',
              value: AppFormatters.money(report.totalPaid),
            ),
            ReportKpi(
              label: 'المتبقي',
              value: AppFormatters.money(report.totalDue),
            ),
            ReportKpi(
              label: 'عدد الموردين',
              value: AppFormatters.integer(report.supplierCount),
            ),
          ],
        ),
        ReportSection(
          title: 'التفاصيل',
          table: ReportTable(
            headers: <String>[
              '#',
              'المورد',
              'الفواتير',
              'إجمالي',
              'المدفوع',
              'المستحق',
            ],
            flex: <double>[0.4, 2.2, 0.8, 1.2, 1.2, 1.2],
            rows: <List<String>>[
              for (int i = 0; i < report.items.length; i++)
                <String>[
                  '${i + 1}',
                  report.items[i].supplierName,
                  AppFormatters.integer(report.items[i].invoiceCount),
                  AppFormatters.money(report.items[i].totalPurchases),
                  AppFormatters.money(report.items[i].totalPaid),
                  AppFormatters.money(report.items[i].totalDue),
                ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ReportPeriod period = ref.watch(reportPagePeriodProvider);
    final AsyncValue<PayablesReport> reportAsync =
        ref.watch(payablesProvider(period));

    return ReportPageScaffold(
      title: 'الموردون',
      period: period,
      onPeriodChanged: _changePeriod,
      isLoading: reportAsync.isLoading,
      errorMessage:
          reportAsync.hasError ? _errorMessage(reportAsync.error!) : null,
      onRetry: () => ref.invalidate(payablesProvider(period)),
      trailing: ReportPrintAction(
        documentBuilder: () {
          final PayablesReport? report = reportAsync.valueOrNull;
          if (report == null) return null;
          return _buildDocument(period, report);
        },
      ),
      body: reportAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
        data: (PayablesReport report) => _Body(report: report),
      ),
    );
  }

  static String _errorMessage(Object error) {
    if (error is ReportException) {
      return 'تعذّر تحميل تقرير الموردين.';
    }
    return 'تعذّر تحميل التقرير.';
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.report});

  final PayablesReport report;

  @override
  Widget build(BuildContext context) {
    if (report.isEmpty) {
      return const _EmptyState();
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        _SummaryCard(report: report),
        const SizedBox(height: 16),
        for (int i = 0; i < report.items.length; i++) ...<Widget>[
          _PayableRow(item: report.items[i]),
          if (i < report.items.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.report});

  final PayablesReport report;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: <Color>[
            const Color(0xFF00838F),
            const Color(0xFF4DD0E1),
          ],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF00838F).withValues(alpha: 0.25),
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
              'إجمالي المشتريات',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onPrimary.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              AppFormatters.money(report.totalPurchases),
              style: theme.textTheme.displaySmall?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: _cell(
                    theme,
                    scheme,
                    'المدفوع',
                    AppFormatters.money(report.totalPaid),
                  ),
                ),
                Expanded(
                  child: _cell(
                    theme,
                    scheme,
                    'المتبقي',
                    AppFormatters.money(report.totalDue),
                  ),
                ),
                Expanded(
                  child: _cell(
                    theme,
                    scheme,
                    'الموردون',
                    AppFormatters.integer(report.supplierCount),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(
    ThemeData theme,
    ColorScheme scheme,
    String label,
    String value,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onPrimary.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            color: scheme.onPrimary,
            fontWeight: FontWeight.w800,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _PayableRow extends StatelessWidget {
  const _PayableRow({required this.item});

  final PayableItem item;

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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.local_shipping_outlined,
                    color: scheme.primary,
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
                        item.supplierName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${AppFormatters.integer(item.invoiceCount)} فاتورة',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  AppFormatters.money(item.totalPurchases),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            if (item.totalDue > 0) ...<Widget>[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'المدفوع: ${AppFormatters.money(item.totalPaid)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    'المستحق: ${AppFormatters.money(item.totalDue)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.local_shipping_outlined,
              size: 48,
              color: scheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'لا توجد مشتريات مؤكدة',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

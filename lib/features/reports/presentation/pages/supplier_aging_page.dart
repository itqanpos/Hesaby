// lib/features/reports/presentation/pages/supplier_aging_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/aging_reports.dart';
import '../../domain/entities/report_document.dart';
import '../../domain/repositories/reports_repository.dart';
import '../providers/reports_providers.dart';
import '../widgets/report_print_action.dart';

/// Supplier aging report — mirror of the customer aging page from the
/// buyer's perspective: it shows how much we still owe each supplier and
/// how old that debt is.
class SupplierAgingPage extends ConsumerWidget {
  const SupplierAgingPage({super.key});

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'ar_EG',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );

  ReportDocument? _buildDocument(SupplierAgingReport report) {
    if (report.isEmpty) return null;

    return ReportDocument(
      title: 'أعمار ديون الموردين',
      periodLabel: 'حتى اللحظة',
      companyName: '—',
      generatedAt: DateTime.now(),
      sections: <ReportSection>[
        ReportSection(
          kpis: <ReportKpi>[
            ReportKpi(
              label: 'إجمالي المستحق للموردين',
              value: _money.format(report.totals.total),
              emphasized: true,
            ),
            ReportKpi(
              label: 'عدد الموردين',
              value: '${report.supplierCount}',
            ),
            ReportKpi(
              label: '0-30 يوم',
              value: _money.format(report.totals.days0to30),
            ),
            ReportKpi(
              label: '31-60 يوم',
              value: _money.format(report.totals.days31to60),
            ),
            ReportKpi(
              label: '61-90 يوم',
              value: _money.format(report.totals.days61to90),
            ),
            ReportKpi(
              label: '+90 يوم',
              value: _money.format(report.totals.days90plus),
              emphasized: report.totals.days90plus > 0,
            ),
          ],
        ),
        ReportSection(
          title: 'التفاصيل حسب المورد',
          table: ReportTable(
            headers: const <String>[
              'المورد',
              '0-30',
              '31-60',
              '61-90',
              '+90',
              'الإجمالي',
            ],
            rows: <List<String>>[
              for (final SupplierAgingRow r in report.rows)
                <String>[
                  r.supplierName,
                  r.buckets.days0to30 > 0
                      ? _money.format(r.buckets.days0to30)
                      : '—',
                  r.buckets.days31to60 > 0
                      ? _money.format(r.buckets.days31to60)
                      : '—',
                  r.buckets.days61to90 > 0
                      ? _money.format(r.buckets.days61to90)
                      : '—',
                  r.buckets.days90plus > 0
                      ? _money.format(r.buckets.days90plus)
                      : '—',
                  _money.format(r.balance),
                ],
            ],
            flex: const <double>[3, 2, 2, 2, 2, 2],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<SupplierAgingReport> reportAsync =
        ref.watch(supplierAgingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('أعمار ديون الموردين'),
        actions: <Widget>[
          ReportPrintAction(
            documentBuilder: () {
              final SupplierAgingReport? report = reportAsync.valueOrNull;
              if (report == null) return null;
              return _buildDocument(report);
            },
          ),
        ],
      ),
      body: reportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  _errorMessage(error),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(supplierAgingProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
        data: (SupplierAgingReport report) => _AgingBody(
          report: report,
          money: _money,
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

class _AgingBody extends StatelessWidget {
  const _AgingBody({required this.report, required this.money});

  final SupplierAgingReport report;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    if (report.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.check_circle_outline,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'لا توجد مبالغ مستحقة لأي مورد.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        _TotalsCard(report: report, money: money),
        const SizedBox(height: 12),
        _BucketsGrid(buckets: report.totals, money: money),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'التفاصيل حسب المورد',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < report.rows.length; i++) ...<Widget>[
          _SupplierAgingCard(
            row: report.rows[i],
            maxBalance: report.rows.first.balance,
            money: money,
          ),
          if (i < report.rows.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

// ============================================================================
// Totals hero card
// ============================================================================

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.report, required this.money});

  final SupplierAgingReport report;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: <Color>[scheme.primary, scheme.primaryContainer],
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
            Row(
              children: <Widget>[
                Icon(
                  Icons.local_shipping_outlined,
                  color: scheme.onPrimary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'إجمالي المستحق للموردين',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onPrimary.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              money.format(report.totals.total),
              style: theme.textTheme.displaySmall?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              '${report.supplierCount} مورد',
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
// Buckets grid
// ============================================================================

class _BucketsGrid extends StatelessWidget {
  const _BucketsGrid({required this.buckets, required this.money});

  final AgingBuckets buckets;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final double total = buckets.total;
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _BucketCard(
                label: '0-30 يوم',
                value: buckets.days0to30,
                total: total,
                color: const Color(0xFF0F7B6C),
                money: money,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _BucketCard(
                label: '31-60 يوم',
                value: buckets.days31to60,
                total: total,
                color: const Color(0xFFF9A825),
                money: money,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: _BucketCard(
                label: '61-90 يوم',
                value: buckets.days61to90,
                total: total,
                color: const Color(0xFFEF6C00),
                money: money,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _BucketCard(
                label: '+90 يوم',
                value: buckets.days90plus,
                total: total,
                color: const Color(0xFFC62828),
                money: money,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BucketCard extends StatelessWidget {
  const _BucketCard({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
    required this.money,
  });

  final String label;
  final double value;
  final double total;
  final Color color;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double share = total > 0 ? (value / total).clamp(0.0, 1.0) : 0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value > 0
              ? color.withValues(alpha: 0.5)
              : scheme.outlineVariant,
          width: value > 0 ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              money.format(value),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: value > 0 ? color : scheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 4,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Supplier row card
// ============================================================================

class _SupplierAgingCard extends StatelessWidget {
  const _SupplierAgingCard({
    required this.row,
    required this.maxBalance,
    required this.money,
  });

  final SupplierAgingRow row;
  final double maxBalance;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double share =
        maxBalance > 0 ? (row.balance / maxBalance).clamp(0.0, 1.0) : 0;

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
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        row.supplierName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (row.phone != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          row.phone!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  money.format(row.balance),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 4,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: _BucketPill(
                    label: '0-30',
                    value: row.buckets.days0to30,
                    color: const Color(0xFF0F7B6C),
                    money: money,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _BucketPill(
                    label: '31-60',
                    value: row.buckets.days31to60,
                    color: const Color(0xFFF9A825),
                    money: money,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _BucketPill(
                    label: '61-90',
                    value: row.buckets.days61to90,
                    color: const Color(0xFFEF6C00),
                    money: money,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _BucketPill(
                    label: '+90',
                    value: row.buckets.days90plus,
                    color: const Color(0xFFC62828),
                    money: money,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BucketPill extends StatelessWidget {
  const _BucketPill({
    required this.label,
    required this.value,
    required this.color,
    required this.money,
  });

  final String label;
  final double value;
  final Color color;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool empty = value <= 0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: empty
            ? scheme.surfaceContainerHighest
            : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: empty ? scheme.onSurfaceVariant : color,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              empty ? '—' : money.format(value),
              style: theme.textTheme.bodySmall?.copyWith(
                color: empty ? scheme.onSurfaceVariant : color,
                fontWeight: FontWeight.w700,
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

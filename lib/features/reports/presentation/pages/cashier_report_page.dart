// lib/features/reports/presentation/pages/cashier_report_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/report_document.dart';
import '../../domain/entities/report_period.dart';
import '../../domain/entities/sales_reports.dart';
import '../../domain/repositories/reports_repository.dart';
import '../providers/reports_providers.dart';
import '../widgets/report_page_scaffold.dart';
import '../widgets/report_print_action.dart';

/// Cashier performance report — aggregated sales per cashier.
///
/// The `created_by` column on `sales` is a Supabase user id. The repository
/// resolves the current user's id to their profile name (when readable) and
/// falls back to a short id for other cashiers, whose profiles are not
/// readable client-side (RLS allows reading one's own profile only).
class CashierReportPage extends ConsumerStatefulWidget {
  const CashierReportPage({super.key});

  @override
  ConsumerState<CashierReportPage> createState() => _CashierReportPageState();
}

class _CashierReportPageState extends ConsumerState<CashierReportPage> {
  static final NumberFormat _money = NumberFormat.currency(
    locale: 'ar_EG',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );

  Future<void> _changePeriod(ReportPeriod newPeriod) async {
    ref.read(reportPagePeriodProvider.notifier).setPeriod(newPeriod);
    final ReportPeriod p = ref.read(reportPagePeriodProvider);
    await ref
        .read(salesByCashierProvider(p).future)
        .catchError((_) => const <CashierSales>[]);
  }

  ReportDocument? _buildDocument(
    ReportPeriod period,
    List<CashierSales> rows,
  ) {
    if (rows.isEmpty) {
      return null;
    }

    double totalSales = 0;
    double totalPaid = 0;
    int totalInvoices = 0;
    for (final CashierSales c in rows) {
      totalSales += c.totalSales;
      totalPaid += c.totalPaid;
      totalInvoices += c.invoiceCount;
    }

    return ReportDocument(
      title: 'أداء الكاشير',
      periodLabel: period.label,
      companyName: '—',
      generatedAt: DateTime.now(),
      sections: <ReportSection>[
        ReportSection(
          kpis: <ReportKpi>[
            ReportKpi(
              label: 'إجمالي المبيعات',
              value: _money.format(totalSales),
              emphasized: true,
            ),
            ReportKpi(
              label: 'المحصَّل',
              value: _money.format(totalPaid),
            ),
            ReportKpi(
              label: 'عدد الفواتير',
              value: '$totalInvoices',
            ),
            ReportKpi(
              label: 'عدد الكاشير',
              value: '${rows.length}',
            ),
          ],
        ),
        ReportSection(
          title: 'الأداء التفصيلي',
          table: ReportTable(
            headers: const <String>[
              'الكاشير',
              'الفواتير',
              'المبيعات',
              'المحصَّل',
              'المتبقي',
            ],
            rows: <List<String>>[
              for (final CashierSales c in rows)
                <String>[
                  c.cashierName,
                  '${c.invoiceCount}',
                  _money.format(c.totalSales),
                  _money.format(c.totalPaid),
                  _money.format(c.totalDue),
                ],
            ],
            flex: const <double>[3, 1, 2, 2, 2],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ReportPeriod period = ref.watch(reportPagePeriodProvider);
    final AsyncValue<List<CashierSales>> rowsAsync =
        ref.watch(salesByCashierProvider(period));

    return ReportPageScaffold(
      title: 'أداء الكاشير',
      period: period,
      onPeriodChanged: _changePeriod,
      isLoading: rowsAsync.isLoading,
      errorMessage: rowsAsync.hasError
          ? _errorMessage(rowsAsync.error!)
          : null,
      onRetry: () => ref.invalidate(salesByCashierProvider(period)),
      trailing: ReportPrintAction(
        documentBuilder: () {
          final List<CashierSales>? rows = rowsAsync.valueOrNull;
          if (rows == null) return null;
          return _buildDocument(period, rows);
        },
      ),
      body: rowsAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
        data: (List<CashierSales> rows) => _CashierBody(
          rows: rows,
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

class _CashierBody extends StatelessWidget {
  const _CashierBody({required this.rows, required this.money});

  final List<CashierSales> rows;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.people_outline,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                'لا توجد مبيعات مؤكدة في هذه الفترة.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    double totalSales = 0;
    double totalPaid = 0;
    int totalInvoices = 0;
    for (final CashierSales c in rows) {
      totalSales += c.totalSales;
      totalPaid += c.totalPaid;
      totalInvoices += c.invoiceCount;
    }
    final CashierSales top = rows.first;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        _TopCashierCard(cashier: top, money: money),
        const SizedBox(height: 12),
        _SummaryGrid(
          totalSales: totalSales,
          totalPaid: totalPaid,
          totalInvoices: totalInvoices,
          cashierCount: rows.length,
          money: money,
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'الأداء التفصيلي',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < rows.length; i++) ...<Widget>[
          _CashierCard(
            rank: i + 1,
            cashier: rows[i],
            totalSales: totalSales,
            money: money,
          ),
          if (i < rows.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

// ============================================================================
// Top cashier card
// ============================================================================

class _TopCashierCard extends StatelessWidget {
  const _TopCashierCard({required this.cashier, required this.money});

  final CashierSales cashier;
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
                  Icons.emoji_events_outlined,
                  color: scheme.onPrimary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'الأعلى مبيعًا',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onPrimary.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              cashier.cashierName,
              style: theme.textTheme.titleLarge?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              money.format(cashier.totalSales),
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
              '${cashier.invoiceCount} فاتورة',
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
// Summary grid
// ============================================================================

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({
    required this.totalSales,
    required this.totalPaid,
    required this.totalInvoices,
    required this.cashierCount,
    required this.money,
  });

  final double totalSales;
  final double totalPaid;
  final int totalInvoices;
  final int cashierCount;
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
                value: money.format(totalSales),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                icon: Icons.account_balance_wallet_outlined,
                color: const Color(0xFF2E7D32),
                label: 'المحصَّل',
                value: money.format(totalPaid),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: _StatCard(
                icon: Icons.receipt_outlined,
                color: const Color(0xFF0288D1),
                label: 'عدد الفواتير',
                value: '$totalInvoices',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                icon: Icons.people_outline,
                color: const Color(0xFF6A1B9A),
                label: 'عدد الكاشير',
                value: '$cashierCount',
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
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

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
// Cashier row card
// ============================================================================

class _CashierCard extends StatelessWidget {
  const _CashierCard({
    required this.rank,
    required this.cashier,
    required this.totalSales,
    required this.money,
  });

  final int rank;
  final CashierSales cashier;
  final double totalSales;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final double share = totalSales > 0
        ? (cashier.totalSales / totalSales).clamp(0.0, 1.0)
        : 0;

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
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$rank',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    cashier.cashierName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${cashier.invoiceCount} فاتورة',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: _Kv(
                    label: 'المبيعات',
                    value: money.format(cashier.totalSales),
                    emphasized: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Kv(
                    label: 'المحصَّل',
                    value: money.format(cashier.totalPaid),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Kv(
                    label: 'المتبقي',
                    value: money.format(cashier.totalDue),
                    danger: cashier.totalDue > 0,
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

class _Kv extends StatelessWidget {
  const _Kv({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.danger = false,
  });

  final String label;
  final String value;
  final bool emphasized;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color valueColor = danger
        ? scheme.error
        : (emphasized ? scheme.primary : scheme.onSurface);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

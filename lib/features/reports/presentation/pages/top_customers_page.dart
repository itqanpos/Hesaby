// lib/features/reports/presentation/pages/top_customers_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/report_period.dart';
import '../../domain/entities/sales_reports.dart';
import '../../domain/repositories/reports_repository.dart';
import '../providers/reports_providers.dart';
import '../widgets/report_page_scaffold.dart';

/// Top customers report page.
///
/// Shows the biggest customers (by total spending) for the selected company
/// over the selected period. Only confirmed sales attached to a registered
/// customer are counted; cash sales are excluded.
class TopCustomersPage extends ConsumerStatefulWidget {
  const TopCustomersPage({super.key});

  @override
  ConsumerState<TopCustomersPage> createState() => _TopCustomersPageState();
}

class _TopCustomersPageState extends ConsumerState<TopCustomersPage> {
  static final NumberFormat _money = NumberFormat.currency(
    locale: 'ar_EG',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );

  Future<void> _changePeriod(ReportPeriod newPeriod) async {
    ref.read(reportPagePeriodProvider.notifier).setPeriod(newPeriod);
    final ReportPeriod p = ref.read(reportPagePeriodProvider);
    await ref
        .read(topCustomersProvider(p).future)
        .catchError((_) => const <TopCustomer>[]);
  }

  @override
  Widget build(BuildContext context) {
    final ReportPeriod period = ref.watch(reportPagePeriodProvider);
    final AsyncValue<List<TopCustomer>> customersAsync =
        ref.watch(topCustomersProvider(period));

    return ReportPageScaffold(
      title: 'العملاء الأكثر شراءً',
      period: period,
      onPeriodChanged: _changePeriod,
      isLoading: customersAsync.isLoading,
      errorMessage: customersAsync.hasError
          ? _errorMessage(customersAsync.error!)
          : null,
      onRetry: () => ref.invalidate(topCustomersProvider(period)),
      body: customersAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
        data: (List<TopCustomer> customers) => _Body(
          period: period,
          customers: customers,
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

class _Body extends StatelessWidget {
  const _Body({
    required this.period,
    required this.customers,
    required this.money,
  });

  final ReportPeriod period;
  final List<TopCustomer> customers;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    if (customers.isEmpty) {
      return const _EmptyState();
    }

    double totalSpent = 0;
    double totalDue = 0;
    for (final TopCustomer c in customers) {
      totalSpent += c.totalSpent;
      totalDue += c.totalDue;
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        _PeriodHeader(period: period),
        const SizedBox(height: 12),
        _SummaryStrip(
          count: customers.length,
          totalSpent: totalSpent,
          totalDue: totalDue,
          money: money,
        ),
        const SizedBox(height: 16),
        for (int i = 0; i < customers.length; i++) ...<Widget>[
          _CustomerRow(
            rank: i + 1,
            customer: customers[i],
            money: money,
          ),
          if (i < customers.length - 1) const SizedBox(height: 8),
        ],
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
// Summary strip
// ============================================================================

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.count,
    required this.totalSpent,
    required this.totalDue,
    required this.money,
  });

  final int count;
  final double totalSpent;
  final double totalDue;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _cell(
                theme,
                scheme,
                'عدد العملاء',
                '$count',
                null,
              ),
            ),
            Container(
              width: 1,
              height: 32,
              color: scheme.outlineVariant,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _cell(
                theme,
                scheme,
                'إجمالي الشراء',
                money.format(totalSpent),
                scheme.primary,
              ),
            ),
            Container(
              width: 1,
              height: 32,
              color: scheme.outlineVariant,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _cell(
                theme,
                scheme,
                'المستحق',
                money.format(totalDue),
                totalDue > 0 ? scheme.error : null,
              ),
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
    Color? valueColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: valueColor ?? scheme.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ============================================================================
// Customer row
// ============================================================================

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({
    required this.rank,
    required this.customer,
    required this.money,
  });

  final int rank;
  final TopCustomer customer;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final Color rankColor = _rankColor(rank, scheme);
    final bool hasDue = customer.totalDue > 0;

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
            // ---- Top row: rank + name + total ----
            Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: rankColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$rank',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: rankColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        customer.customerName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${customer.invoiceCount} فاتورة',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  money.format(customer.totalSpent),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),

            // ---- Bottom row: paid / due ----
            if (hasDue) ...<Widget>[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'المدفوع: ${money.format(customer.totalPaid)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    'المستحق: ${money.format(customer.totalDue)}',
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

  static Color _rankColor(int rank, ColorScheme scheme) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFB300);
      case 2:
        return const Color(0xFF9E9E9E);
      case 3:
        return const Color(0xFF8D6E63);
      default:
        return scheme.primary;
    }
  }
}

// ============================================================================
// Empty state
// ============================================================================

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
              Icons.people_outline,
              size: 48,
              color: scheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'لا توجد مبيعات لعميل مسجل في هذه الفترة',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'المبيعات النقدية غير مشمولة في هذا التقرير.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

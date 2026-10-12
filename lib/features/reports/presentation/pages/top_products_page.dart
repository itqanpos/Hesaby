// lib/features/reports/presentation/pages/top_products_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../domain/entities/report_document.dart';
import '../../domain/entities/report_period.dart';
import '../../domain/entities/sales_reports.dart';
import '../../domain/repositories/reports_repository.dart';
import '../providers/reports_providers.dart';
import '../widgets/report_page_scaffold.dart';
import '../widgets/report_print_action.dart';

class TopProductsPage extends ConsumerStatefulWidget {
  const TopProductsPage({super.key});

  @override
  ConsumerState<TopProductsPage> createState() => _TopProductsPageState();
}

class _TopProductsPageState extends ConsumerState<TopProductsPage> {
  Future<void> _changePeriod(ReportPeriod newPeriod) async {
    ref.read(reportPagePeriodProvider.notifier).setPeriod(newPeriod);
    final ReportPeriod p = ref.read(reportPagePeriodProvider);
    await ref
        .read(topProductsProvider(p).future)
        .catchError((_) => const <TopProduct>[]);
  }

  ReportDocument? _buildDocument(
    ReportPeriod period,
    List<TopProduct> products,
  ) {
    if (products.isEmpty) return null;

    double totalRevenue = 0;
    for (final TopProduct p in products) {
      totalRevenue += p.totalRevenue;
    }

    return ReportDocument(
      title: 'المنتجات الأكثر مبيعًا',
      periodLabel: period.label,
      companyName: '—',
      generatedAt: DateTime.now(),
      sections: <ReportSection>[
        ReportSection(
          kpis: <ReportKpi>[
            ReportKpi(
              label: 'عدد المنتجات',
              value: AppFormatters.integer(products.length),
            ),
            ReportKpi(
              label: 'إجمالي الإيرادات',
              value: AppFormatters.money(totalRevenue),
              emphasized: true,
            ),
          ],
        ),
        ReportSection(
          title: 'التفاصيل',
          table: ReportTable(
            headers: <String>['#', 'المنتج', 'الكمية', 'الفواتير', 'الإيراد'],
            flex: <double>[0.4, 2.6, 0.9, 0.9, 1.4],
            rows: <List<String>>[
              for (int i = 0; i < products.length; i++)
                <String>[
                  AppFormatters.integer(i + 1),
                  products[i].productName,
                  AppFormatters.quantity(products[i].totalQuantity),
                  AppFormatters.integer(products[i].invoiceCount),
                  AppFormatters.money(products[i].totalRevenue),
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
    final AsyncValue<List<TopProduct>> productsAsync =
        ref.watch(topProductsProvider(period));

    return ReportPageScaffold(
      title: 'المنتجات الأكثر مبيعًا',
      period: period,
      onPeriodChanged: _changePeriod,
      isLoading: productsAsync.isLoading,
      errorMessage: productsAsync.hasError
          ? _errorMessage(productsAsync.error!)
          : null,
      onRetry: () => ref.invalidate(topProductsProvider(period)),
      trailing: ReportPrintAction(
        documentBuilder: () {
          final List<TopProduct>? list = productsAsync.valueOrNull;
          if (list == null) return null;
          return _buildDocument(period, list);
        },
      ),
      body: productsAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
        data: (List<TopProduct> products) => _Body(
          period: period,
          products: products,
        ),
      ),
    );
  }

  static String _errorMessage(Object error) {
    if (error is ReportException) {
      return 'تعذّر تحميل التقرير.';
    }
    return 'تعذّر تحميل التقرير.';
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.period,
    required this.products,
  });

  final ReportPeriod period;
  final List<TopProduct> products;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return _EmptyState(period: period);
    }

    final double totalRevenue = products.fold<double>(
      0,
      (double sum, TopProduct p) => sum + p.totalRevenue,
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        _PeriodHeader(period: period),
        const SizedBox(height: 12),
        _SummaryStrip(
          count: products.length,
          totalRevenue: totalRevenue,
        ),
        const SizedBox(height: 16),
        for (int i = 0; i < products.length; i++) ...<Widget>[
          _ProductRow(
            rank: i + 1,
            product: products[i],
          ),
          if (i < products.length - 1) const SizedBox(height: 8),
        ],
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

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.count,
    required this.totalRevenue,
  });

  final int count;
  final double totalRevenue;

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'عدد المنتجات',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppFormatters.integer(count),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Container(width: 1, height: 32, color: scheme.outlineVariant),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'إجمالي الإيرادات',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppFormatters.money(totalRevenue),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
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

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.rank,
    required this.product,
  });

  final int rank;
  final TopProduct product;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color rankColor = _rankColor(rank, scheme);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
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
                AppFormatters.integer(rank),
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
                    product.productName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${AppFormatters.quantity(product.totalQuantity)} وحدة · '
                    '${AppFormatters.integer(product.invoiceCount)} فاتورة',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              AppFormatters.money(product.totalRevenue),
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.period});
  final ReportPeriod period;

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
              Icons.inventory_2_outlined,
              size: 48,
              color: scheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'لا توجد مبيعات في هذه الفترة',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

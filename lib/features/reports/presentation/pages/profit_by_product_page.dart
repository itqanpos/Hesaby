// lib/features/reports/presentation/pages/profit_by_product_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../domain/entities/profit_reports.dart';
import '../../domain/entities/report_document.dart';
import '../../domain/entities/report_period.dart';
import '../../domain/repositories/reports_repository.dart';
import '../providers/reports_providers.dart';
import '../widgets/report_page_scaffold.dart';
import '../widgets/report_print_action.dart';

/// "Profit by product" report — gross profit per product over a period.
///
/// Revenue is drawn from confirmed sale items; cost is drawn from
/// `sale_out` stock movements (historical average cost at the moment of
/// sale). See `ProductProfit` for details.
///
/// Layout:
/// 1. Period selector.
/// 2. Hero card: total profit + overall margin.
/// 3. Stats grid: revenue, cost, products count.
/// 4. List of products sorted by profit (descending).
///
/// A quick filter allows toggling between "all products" and "only
/// products that made a loss" to help spot issues.
class ProfitByProductPage extends ConsumerStatefulWidget {
  const ProfitByProductPage({super.key});

  @override
  ConsumerState<ProfitByProductPage> createState() =>
      _ProfitByProductPageState();
}

enum _ProfitFilter { all, onlyProfit, onlyLoss }

class _ProfitByProductPageState
    extends ConsumerState<ProfitByProductPage> {
  _ProfitFilter _filter = _ProfitFilter.all;

  Future<void> _changePeriod(ReportPeriod newPeriod) async {
    ref.read(reportPagePeriodProvider.notifier).setPeriod(newPeriod);
    final ReportPeriod p = ref.read(reportPagePeriodProvider);
    await ref
        .read(productProfitProvider(p).future)
        .catchError((_) => ProductProfitReport.empty());
  }

  ReportDocument? _buildDocument(
    ReportPeriod period,
    ProductProfitReport report,
  ) {
    if (report.isEmpty) return null;

    return ReportDocument(
      title: 'الربح من كل منتج',
      periodLabel: period.label,
      companyName: '—',
      generatedAt: DateTime.now(),
      sections: <ReportSection>[
        ReportSection(
          kpis: <ReportKpi>[
            ReportKpi(
              label: 'إجمالي الإيراد',
              value: AppFormatters.money(report.totalRevenue),
            ),
            ReportKpi(
              label: 'إجمالي التكلفة',
              value: AppFormatters.money(report.totalCost),
            ),
            ReportKpi(
              label: 'إجمالي الربح',
              value: AppFormatters.money(report.totalProfit),
              emphasized: true,
            ),
            ReportKpi(
              label: 'هامش الربح',
              value: report.overallMarginPercent != null
                  ? AppFormatters.percent(report.overallMarginPercent!)
                  : '—',
            ),
          ],
        ),
        ReportSection(
          title: 'تفاصيل المنتجات',
          table: ReportTable(
            headers: const <String>[
              '#',
              'المنتج',
              'الكمية',
              'الإيراد',
              'التكلفة',
              'الربح',
              'الهامش',
            ],
            flex: const <double>[0.4, 2.4, 0.8, 1.2, 1.2, 1.2, 0.9],
            rows: <List<String>>[
              for (int i = 0; i < report.items.length; i++)
                <String>[
                  AppFormatters.integer(i + 1),
                  report.items[i].productName,
                  AppFormatters.quantity(report.items[i].quantitySold),
                  AppFormatters.money(report.items[i].revenue),
                  AppFormatters.money(report.items[i].cost),
                  AppFormatters.money(report.items[i].profit),
                  report.items[i].marginPercent != null
                      ? AppFormatters.percent(
                          report.items[i].marginPercent!,
                        )
                      : '—',
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
    final AsyncValue<ProductProfitReport> reportAsync =
        ref.watch(productProfitProvider(period));

    return ReportPageScaffold(
      title: 'الربح من كل منتج',
      period: period,
      onPeriodChanged: _changePeriod,
      isLoading: reportAsync.isLoading,
      errorMessage: reportAsync.hasError
          ? _errorMessage(reportAsync.error!)
          : null,
      onRetry: () => ref.invalidate(productProfitProvider(period)),
      trailing: ReportPrintAction(
        documentBuilder: () {
          final ProductProfitReport? report = reportAsync.valueOrNull;
          if (report == null) return null;
          return _buildDocument(period, report);
        },
      ),
      body: reportAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
        data: (ProductProfitReport report) => _Body(
          report: report,
          filter: _filter,
          onFilterChanged: (_ProfitFilter f) =>
              setState(() => _filter = f),
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

// ============================================================================
// Body
// ============================================================================

class _Body extends StatelessWidget {
  const _Body({
    required this.report,
    required this.filter,
    required this.onFilterChanged,
  });

  final ProductProfitReport report;
  final _ProfitFilter filter;
  final ValueChanged<_ProfitFilter> onFilterChanged;

  List<ProductProfit> get _visibleItems {
    switch (filter) {
      case _ProfitFilter.all:
        return report.items;
      case _ProfitFilter.onlyProfit:
        return report.items
            .where((ProductProfit p) => p.isProfitable)
            .toList(growable: false);
      case _ProfitFilter.onlyLoss:
        return report.items
            .where((ProductProfit p) => p.isLoss)
            .toList(growable: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (report.isEmpty) {
      return const _EmptyState();
    }

    final List<ProductProfit> visible = _visibleItems;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        _HeroCard(report: report),
        const SizedBox(height: 12),
        _StatsGrid(report: report),
        const SizedBox(height: 16),

        // ---- Filter chips ----
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _FilterBar(
            filter: filter,
            lossCount: report.productsWithLoss,
            onChanged: onFilterChanged,
          ),
        ),
        const SizedBox(height: 12),

        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                'لا توجد منتجات في هذه الفئة.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          for (int i = 0; i < visible.length; i++) ...<Widget>[
            _ProductProfitCard(
              rank: i + 1,
              item: visible[i],
              totalProfit: report.totalProfit,
            ),
            if (i < visible.length - 1) const SizedBox(height: 8),
          ],
      ],
    );
  }
}

// ============================================================================
// Hero card
// ============================================================================

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.report});

  final ProductProfitReport report;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isProfit = report.totalProfit >= 0;
    final Color tone = isProfit
        ? const Color(0xFF0F7B6C)
        : const Color(0xFFC62828);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: <Color>[tone, tone.withValues(alpha: 0.75)],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: tone.withValues(alpha: 0.25),
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
                  isProfit ? Icons.trending_up : Icons.trending_down,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  isProfit ? 'إجمالي الربح' : 'إجمالي الخسارة',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              AppFormatters.money(report.totalProfit),
              style: theme.textTheme.displaySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              report.overallMarginPercent != null
                  ? 'هامش الربح: '
                      '${AppFormatters.percent(report.overallMarginPercent!)}'
                  : 'لا توجد مبيعات في الفترة',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Stats grid
// ============================================================================

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.report});

  final ProductProfitReport report;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _StatCard(
                icon: Icons.attach_money_outlined,
                color: const Color(0xFF0F7B6C),
                label: 'الإيراد',
                value: AppFormatters.money(report.totalRevenue),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                icon: Icons.shopping_bag_outlined,
                color: const Color(0xFFC62828),
                label: 'التكلفة',
                value: AppFormatters.money(report.totalCost),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: _StatCard(
                icon: Icons.inventory_2_outlined,
                color: const Color(0xFF0288D1),
                label: 'عدد المنتجات',
                value: AppFormatters.integer(report.productCount),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                icon: Icons.warning_amber_outlined,
                color: report.productsWithLoss > 0
                    ? const Color(0xFFC62828)
                    : const Color(0xFF7B5E3A),
                label: 'منتجات بخسارة',
                value: AppFormatters.integer(report.productsWithLoss),
                emphasize: report.productsWithLoss > 0,
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
// Filter bar
// ============================================================================

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.lossCount,
    required this.onChanged,
  });

  final _ProfitFilter filter;
  final int lossCount;
  final ValueChanged<_ProfitFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          ChoiceChip(
            label: const Text('الكل'),
            selected: filter == _ProfitFilter.all,
            onSelected: (_) => onChanged(_ProfitFilter.all),
            showCheckmark: false,
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('رابحة'),
            selected: filter == _ProfitFilter.onlyProfit,
            onSelected: (_) => onChanged(_ProfitFilter.onlyProfit),
            showCheckmark: false,
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: Text(
              lossCount > 0 ? 'خاسرة ($lossCount)' : 'خاسرة',
            ),
            selected: filter == _ProfitFilter.onlyLoss,
            onSelected: lossCount == 0
                ? null
                : (_) => onChanged(_ProfitFilter.onlyLoss),
            showCheckmark: false,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Product row card
// ============================================================================

class _ProductProfitCard extends StatelessWidget {
  const _ProductProfitCard({
    required this.rank,
    required this.item,
    required this.totalProfit,
  });

  final int rank;
  final ProductProfit item;

  /// Total profit of the whole report — used only for the visual bar
  /// that shows this product's share of the total.
  final double totalProfit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final bool isProfit = item.profit >= 0;
    final Color tone = isProfit
        ? const Color(0xFF0F7B6C)
        : const Color(0xFFC62828);

    // Progress bar: |profit| / |max profit|, capped at 1.
    final double share = (totalProfit.abs() > 0 && item.profit > 0)
        ? (item.profit / totalProfit.abs()).clamp(0.0, 1.0)
        : 0.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: !isProfit
              ? tone.withValues(alpha: 0.4)
              : scheme.outlineVariant,
          width: !isProfit ? 1.3 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // ---- Row 1: rank + name + profit ----
            Row(
              children: <Widget>[
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    AppFormatters.integer(rank),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.productName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      AppFormatters.signedMoney(item.profit),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (item.marginPercent != null)
                      Text(
                        'هامش '
                        '${AppFormatters.percent(item.marginPercent!)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // ---- Row 2: share bar (only for profitable items) ----
            if (isProfit && share > 0) ...<Widget>[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: share,
                  minHeight: 5,
                  color: tone,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ],

            const SizedBox(height: 10),

            // ---- Row 3: revenue / cost / quantity ----
            Row(
              children: <Widget>[
                Expanded(
                  child: _Kv(
                    label: 'الكمية',
                    value: AppFormatters.quantity(item.quantitySold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Kv(
                    label: 'الإيراد',
                    value: AppFormatters.money(item.revenue),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Kv(
                    label: 'التكلفة',
                    value: AppFormatters.money(item.cost),
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
  const _Kv({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

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
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
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
              Icons.trending_up_outlined,
              size: 48,
              color: scheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'لا توجد مبيعات في هذه الفترة',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'جرّب تغيير الفترة من الشريط العلوي.',
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

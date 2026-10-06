// lib/features/reports/presentation/pages/dead_stock_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/inventory_reports.dart';
import '../../domain/entities/report_document.dart';
import '../../domain/entities/report_period.dart';
import '../../domain/repositories/reports_repository.dart';
import '../providers/reports_providers.dart';
import '../widgets/report_page_scaffold.dart';
import '../widgets/report_print_action.dart';

class DeadStockPage extends ConsumerStatefulWidget {
  const DeadStockPage({super.key});

  @override
  ConsumerState<DeadStockPage> createState() => _DeadStockPageState();
}

class _DeadStockPageState extends ConsumerState<DeadStockPage> {
  static final NumberFormat _money = NumberFormat.currency(
    locale: 'ar_EG',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );
  static final NumberFormat _qty = NumberFormat.decimalPattern('ar_EG');
  static final DateFormat _date = DateFormat.yMd('ar_EG');

  ReportDocument? _buildDocument(
    DeadStockWindow window,
    List<DeadStockItem> items,
  ) {
    if (items.isEmpty) return null;

    double totalValue = 0;
    int neverSold = 0;
    for (final DeadStockItem it in items) {
      totalValue += it.stockValue;
      if (it.neverSold) neverSold++;
    }

    return ReportDocument(
      title: 'المنتجات الراكدة',
      periodLabel: 'لم تُبَع خلال ${window.label}',
      companyName: '—',
      generatedAt: DateTime.now(),
      sections: <ReportSection>[
        ReportSection(
          kpis: <ReportKpi>[
            ReportKpi(
              label: 'عدد المنتجات',
              value: '${items.length}',
            ),
            ReportKpi(
              label: 'قيمة المخزون',
              value: _money.format(totalValue),
              emphasized: true,
            ),
            if (neverSold > 0)
              ReportKpi(
                label: 'لم تُبَع أبدًا',
                value: '$neverSold',
              ),
          ],
        ),
        ReportSection(
          title: 'التفاصيل',
          table: ReportTable(
            headers: <String>[
              '#',
              'المنتج',
              'الكمية',
              'قيمة المخزون',
              'آخر بيع',
            ],
            flex: <double>[0.4, 2.2, 0.9, 1.3, 1.5],
            rows: <List<String>>[
              for (int i = 0; i < items.length; i++)
                <String>[
                  '${i + 1}',
                  items[i].productName,
                  _qty.format(items[i].quantityOnHand),
                  _money.format(items[i].stockValue),
                  items[i].lastSoldAt == null
                      ? 'لم تُبَع أبدًا'
                      : _date.format(items[i].lastSoldAt!.toLocal()),
                ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final DeadStockWindow window = ref.watch(deadStockWindowProvider);
    final AsyncValue<List<DeadStockItem>> itemsAsync =
        ref.watch(deadStockProvider(window));

    return ReportPageScaffold(
      title: 'المنتجات الراكدة',
      period: const ReportPeriod(type: ReportPeriodType.all),
      onPeriodChanged: (_) {},
      isLoading: itemsAsync.isLoading,
      errorMessage:
          itemsAsync.hasError ? _errorMessage(itemsAsync.error!) : null,
      onRetry: () => ref.invalidate(deadStockProvider(window)),
      trailing: _WindowSelector(
        window: window,
        onChanged: (DeadStockWindow w) =>
            ref.read(deadStockWindowProvider.notifier).setWindow(w),
      ),
      body: itemsAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
        data: (List<DeadStockItem> items) => _Body(
          window: window,
          items: items,
          money: _money,
          qty: _qty,
          date: _date,
        ),
      ),
    );
  }

  static String _errorMessage(Object error) {
    if (error is ReportException) {
      return 'تعذّر تحميل تقرير المنتجات الراكدة.';
    }
    return 'تعذّر تحميل التقرير.';
  }
}

// ============================================================================
// Window selector
// ============================================================================

class _WindowSelector extends StatelessWidget {
  const _WindowSelector({required this.window, required this.onChanged});

  final DeadStockWindow window;
  final ValueChanged<DeadStockWindow> onChanged;

  Future<void> _open(BuildContext context) async {
    final DeadStockWindow? selected =
        await showModalBottomSheet<DeadStockWindow>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (BuildContext ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'الفترة الزمنية',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final DeadStockWindow w in DeadStockWindow.values)
                    ChoiceChip(
                      label: Text(w.label),
                      selected: w == window,
                      onSelected: (_) => Navigator.of(ctx).pop(w),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      onChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _open(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.hourglass_empty,
                  size: 16,
                  color: scheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  window.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down,
                  size: 18,
                  color: scheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Body
// ============================================================================

class _Body extends StatelessWidget {
  const _Body({
    required this.window,
    required this.items,
    required this.money,
    required this.qty,
    required this.date,
  });

  final DeadStockWindow window;
  final List<DeadStockItem> items;
  final NumberFormat money;
  final NumberFormat qty;
  final DateFormat date;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyState();
    }

    double totalValue = 0;
    int neverSold = 0;
    for (final DeadStockItem it in items) {
      totalValue += it.stockValue;
      if (it.neverSold) neverSold++;
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        _SummaryStrip(
          window: window,
          count: items.length,
          totalValue: totalValue,
          neverSold: neverSold,
          money: money,
        ),
        const SizedBox(height: 16),
        for (int i = 0; i < items.length; i++) ...<Widget>[
          _DeadStockRow(
            item: items[i],
            money: money,
            qty: qty,
            date: date,
          ),
          if (i < items.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.window,
    required this.count,
    required this.totalValue,
    required this.neverSold,
    required this.money,
  });

  final DeadStockWindow window;
  final int count;
  final double totalValue;
  final int neverSold;
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'لم تُبَع خلال ${window.label}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: _cell(
                    theme,
                    scheme,
                    'عدد المنتجات',
                    '$count',
                    null,
                  ),
                ),
                Container(width: 1, height: 28, color: scheme.outlineVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: _cell(
                    theme,
                    scheme,
                    'قيمة المخزون',
                    money.format(totalValue),
                    scheme.error,
                  ),
                ),
                if (neverSold > 0) ...<Widget>[
                  Container(
                    width: 1,
                    height: 28,
                    color: scheme.outlineVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _cell(
                      theme,
                      scheme,
                      'لم تُبَع أبدًا',
                      '$neverSold',
                      scheme.error,
                    ),
                  ),
                ],
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

class _DeadStockRow extends StatelessWidget {
  const _DeadStockRow({
    required this.item,
    required this.money,
    required this.qty,
    required this.date,
  });

  final DeadStockItem item;
  final NumberFormat money;
  final NumberFormat qty;
  final DateFormat date;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String unitSuffix =
        item.unitName != null ? ' ${item.unitName}' : '';

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
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.hourglass_empty,
                color: scheme.onSurfaceVariant,
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
                    item.productName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'الرصيد: ${qty.format(item.quantityOnHand)}$unitSuffix · '
                    '${_lastSoldLabel()}',
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
              money.format(item.stockValue),
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.error,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _lastSoldLabel() {
    if (item.neverSold) {
      return 'لم تُبَع أبدًا';
    }
    final int? days = item.daysSinceLastSale;
    final String dateStr = date.format(item.lastSoldAt!.toLocal());
    if (days == null) return 'آخر بيع: $dateStr';
    return 'آخر بيع: $dateStr ($days يومًا)';
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
            Icon(Icons.check_circle_outline, size: 48, color: scheme.primary),
            const SizedBox(height: 12),
            Text(
              'لا توجد منتجات راكدة',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

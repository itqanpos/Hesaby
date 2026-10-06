// lib/features/reports/presentation/pages/low_stock_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/inventory_reports.dart';
import '../../domain/entities/report_period.dart';
import '../../domain/repositories/reports_repository.dart';
import '../providers/reports_providers.dart';
import '../widgets/report_page_scaffold.dart';

/// Products whose on-hand stock is at or below their configured minimum.
class LowStockPage extends ConsumerStatefulWidget {
  const LowStockPage({super.key});

  @override
  ConsumerState<LowStockPage> createState() => _LowStockPageState();
}

class _LowStockPageState extends ConsumerState<LowStockPage> {
  static final NumberFormat _qty = NumberFormat.decimalPattern('ar_EG');

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<LowStockItem>> itemsAsync =
        ref.watch(lowStockProvider);

    return ReportPageScaffold(
      title: 'المخزون المنخفض',
      period: const ReportPeriod(type: ReportPeriodType.all),
      onPeriodChanged: (_) {},
      isLoading: itemsAsync.isLoading,
      errorMessage:
          itemsAsync.hasError ? _errorMessage(itemsAsync.error!) : null,
      onRetry: () => ref.invalidate(lowStockProvider),
      body: itemsAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
        data: (List<LowStockItem> items) => _Body(items: items, qty: _qty),
      ),
    );
  }

  static String _errorMessage(Object error) {
    if (error is ReportException) {
      return 'تعذّر تحميل تقرير المخزون المنخفض.';
    }
    return 'تعذّر تحميل التقرير.';
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.items, required this.qty});

  final List<LowStockItem> items;
  final NumberFormat qty;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _AllGoodState();
    }

    final int outOfStock =
        items.where((LowStockItem i) => i.isOutOfStock).length;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        _SummaryStrip(
          total: items.length,
          outOfStock: outOfStock,
        ),
        const SizedBox(height: 16),
        for (int i = 0; i < items.length; i++) ...<Widget>[
          _LowStockRow(item: items[i], qty: qty),
          if (i < items.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.total, required this.outOfStock});

  final int total;
  final int outOfStock;

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
                'إجمالي المنتجات',
                '$total',
                null,
              ),
            ),
            Container(width: 1, height: 32, color: scheme.outlineVariant),
            const SizedBox(width: 14),
            Expanded(
              child: _cell(
                theme,
                scheme,
                'نفدت تمامًا',
                '$outOfStock',
                outOfStock > 0 ? scheme.error : null,
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
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: valueColor ?? scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _LowStockRow extends StatelessWidget {
  const _LowStockRow({required this.item, required this.qty});

  final LowStockItem item;
  final NumberFormat qty;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isOut = item.isOutOfStock;
    final Color accent = isOut ? scheme.error : const Color(0xFFE65100);
    final String unitSuffix =
        item.unitName != null ? ' ${item.unitName}' : '';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isOut ? Icons.error_outline : Icons.warning_amber_outlined,
                color: accent,
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
                    'الحد: ${qty.format(item.minStock)}',
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
              isOut ? 'نفد' : 'نقص ${qty.format(item.deficit)}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllGoodState extends StatelessWidget {
  const _AllGoodState();

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
              Icons.check_circle_outline,
              size: 48,
              color: scheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'كل المنتجات فوق حد الطلب',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'لا توجد منتجات تحتاج إعادة طلب حاليًا.',
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

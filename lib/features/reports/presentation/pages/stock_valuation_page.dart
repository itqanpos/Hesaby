// lib/features/reports/presentation/pages/stock_valuation_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/inventory_reports.dart';
import '../../domain/repositories/reports_repository.dart';
import '../providers/reports_providers.dart';
import '../widgets/report_page_scaffold.dart';

/// Current stock valuation report page.
class StockValuationPage extends ConsumerStatefulWidget {
  const StockValuationPage({super.key});

  @override
  ConsumerState<StockValuationPage> createState() =>
      _StockValuationPageState();
}

class _StockValuationPageState extends ConsumerState<StockValuationPage> {
  static final NumberFormat _money = NumberFormat.currency(
    locale: 'ar_EG',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );
  static final NumberFormat _qty = NumberFormat.decimalPattern('ar_EG');

  @override
  Widget build(BuildContext context) {
    final AsyncValue<StockValuationReport> reportAsync =
        ref.watch(stockValuationProvider);

    return ReportPageScaffold(
      title: 'تقييم المخزون',
      period: const ReportPeriod(type: ReportPeriodType.all),
      onPeriodChanged: (_) {},
      isLoading: reportAsync.isLoading,
      errorMessage:
          reportAsync.hasError ? _errorMessage(reportAsync.error!) : null,
      onRetry: () => ref.invalidate(stockValuationProvider),
      body: reportAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
        data: (StockValuationReport report) => _Body(
          report: report,
          money: _money,
          qty: _qty,
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

class _Body extends StatelessWidget {
  const _Body({
    required this.report,
    required this.money,
    required this.qty,
  });

  final StockValuationReport report;
  final NumberFormat money;
  final NumberFormat qty;

  @override
  Widget build(BuildContext context) {
    if (report.isEmpty) {
      return const _EmptyState();
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        _SummaryStrip(report: report, money: money),
        const SizedBox(height: 16),
        for (int i = 0; i < report.items.length; i++) ...<Widget>[
          _ValuationRow(item: report.items[i], money: money, qty: qty),
          if (i < report.items.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.report, required this.money});

  final StockValuationReport report;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: <Color>[scheme.primary, scheme.primaryContainer],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'إجمالي قيمة المخزون',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onPrimary.withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              money.format(report.totalValue),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w900,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '${report.itemCount} منتج',
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

class _ValuationRow extends StatelessWidget {
  const _ValuationRow({
    required this.item,
    required this.money,
    required this.qty,
  });

  final StockValuationItem item;
  final NumberFormat money;
  final NumberFormat qty;

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
                    '${qty.format(item.quantityOnHand)}$unitSuffix · '
                    'متوسط التكلفة: ${money.format(item.averageCost)}',
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
              money.format(item.totalValue),
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
            Icon(Icons.warehouse_outlined, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              'لا يوجد مخزون حاليًا',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

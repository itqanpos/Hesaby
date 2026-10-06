// lib/features/sales/presentation/widgets/sales_kpi_row.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/sale_entities.dart';

/// A 2×2 grid of KPI cards shown at the top of the sales page.
///
/// All four KPIs are computed from the full sales list (never from the
/// filtered result), so the cards always reflect the company's overall
/// performance regardless of what filters the user applies below.
class SalesKpiRow extends StatelessWidget {
  const SalesKpiRow({super.key, required this.sales});

  final List<Sale> sales;

  @override
  Widget build(BuildContext context) {
    final _KpiData data = _KpiData.from(sales);
    final NumberFormat money = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _KpiCard(
                icon: Icons.today_outlined,
                iconColor: const Color(0xFF0F7B6C),
                label: 'اليوم',
                value: money.format(data.todayTotal),
                subtitle: '${data.todayCount} فاتورة',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiCard(
                icon: Icons.calendar_month_outlined,
                iconColor: const Color(0xFF0288D1),
                label: 'هذا الشهر',
                value: money.format(data.monthTotal),
                subtitle: '${data.monthCount} فاتورة',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: _KpiCard(
                icon: Icons.account_balance_wallet_outlined,
                iconColor: const Color(0xFFE65100),
                label: 'غير محصَّل',
                value: money.format(data.uncollectedTotal),
                subtitle: '${data.uncollectedCount} فاتورة',
                emphasize: data.uncollectedTotal > 0,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiCard(
                icon: Icons.cancel_outlined,
                iconColor: const Color(0xFFC62828),
                label: 'ملغاة (الشهر)',
                value: '${data.cancelledThisMonthCount}',
                subtitle: 'فاتورة',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================================
// Aggregation
// ============================================================================

class _KpiData {
  const _KpiData({
    required this.todayCount,
    required this.todayTotal,
    required this.monthCount,
    required this.monthTotal,
    required this.uncollectedCount,
    required this.uncollectedTotal,
    required this.cancelledThisMonthCount,
  });

  factory _KpiData.from(List<Sale> sales) {
    final DateTime now = DateTime.now();

    int todayCount = 0;
    double todayTotal = 0;
    int monthCount = 0;
    double monthTotal = 0;
    int uncollectedCount = 0;
    double uncollectedTotal = 0;
    int cancelledThisMonth = 0;

    for (final Sale sale in sales) {
      final DateTime local = sale.saleDate.toLocal();
      final bool isSameDay = local.year == now.year &&
          local.month == now.month &&
          local.day == now.day;
      final bool isSameMonth =
          local.year == now.year && local.month == now.month;

      // --- Confirmed sales feed the "today" / "month" totals ---
      if (sale.isConfirmed) {
        if (isSameDay) {
          todayCount++;
          todayTotal += sale.total;
        }
        if (isSameMonth) {
          monthCount++;
          monthTotal += sale.total;
        }
      }

      // --- Uncollected balance across ALL confirmed sales, regardless of
      //     when they happened. This is the true outstanding amount. ---
      if (sale.isConfirmed && sale.amountDue > 0) {
        uncollectedCount++;
        uncollectedTotal += sale.amountDue;
      }

      // --- Cancelled count for the current month ---
      if (sale.isCancelled && isSameMonth) {
        cancelledThisMonth++;
      }
    }

    return _KpiData(
      todayCount: todayCount,
      todayTotal: todayTotal,
      monthCount: monthCount,
      monthTotal: monthTotal,
      uncollectedCount: uncollectedCount,
      uncollectedTotal: uncollectedTotal,
      cancelledThisMonthCount: cancelledThisMonth,
    );
  }

  final int todayCount;
  final double todayTotal;
  final int monthCount;
  final double monthTotal;
  final int uncollectedCount;
  final double uncollectedTotal;
  final int cancelledThisMonthCount;
}

// ============================================================================
// Card
// ============================================================================

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.subtitle,
    this.emphasize = false,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String subtitle;
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
              ? iconColor.withValues(alpha: 0.5)
              : scheme.outlineVariant,
          width: emphasize ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 15, color: iconColor),
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
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: emphasize ? iconColor : scheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
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

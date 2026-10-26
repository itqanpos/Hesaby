// lib/shared/widgets/statements/widgets/statement_summary_bar.dart
//
// Compact four-cell summary bar: opening balance → total debit →
// total credit → closing balance.
//
// * Placed **fixed** above the entries list (not scrolled away), so the
//   accountant always sees the period totals.
// * Totals are computed from the **full** statement, not from the
//   currently filtered view. `ComputedStatement.displayFiltered` filters
//   display only — see its doc. This bar therefore always reflects the
//   real period aggregates.
// * Uses `moneyPlain` (no "ج.م") to keep the cells readable on narrow
//   phones; the currency symbol is shown once in `StatementInfoCard`
//   just above.

import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';

class StatementSummaryBar extends StatelessWidget {
  const StatementSummaryBar({
    required this.openingBalance,
    required this.totalDebit,
    required this.totalCredit,
    required this.closingBalance,
    super.key,
  });

  final double openingBalance;
  final double totalDebit;
  final double totalCredit;
  final double closingBalance;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final bool closingWeOwe = closingBalance > 0.01;
    final bool closingTheyOweUs = closingBalance < -0.01;
    final Color closingColor = closingWeOwe
        ? scheme.error
        : closingTheyOweUs
            ? const Color(0xFF1B5E20)
            : scheme.onSurfaceVariant;

    final List<_Cell> cells = <_Cell>[
      _Cell(
        label: 'افتتاحي',
        value: openingBalance.abs(),
        color: scheme.onSurfaceVariant,
      ),
      _Cell(
        label: 'مدين',
        value: totalDebit,
        color: scheme.error,
      ),
      _Cell(
        label: 'دائن',
        value: totalCredit,
        color: const Color(0xFF1B5E20),
      ),
      _Cell(
        label: 'ختامي',
        value: closingBalance.abs(),
        color: closingColor,
        bold: true,
      ),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < cells.length; i++) ...<Widget>[
            if (i > 0)
              Container(
                width: 1,
                height: 28,
                color: scheme.outlineVariant,
              ),
            Expanded(child: _CellView(cell: cells[i])),
          ],
        ],
      ),
    );
  }
}

class _Cell {
  const _Cell({
    required this.label,
    required this.value,
    required this.color,
    this.bold = false,
  });

  final String label;
  final double value;
  final Color color;
  final bool bold;
}

class _CellView extends StatelessWidget {
  const _CellView({required this.cell});

  final _Cell cell;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          cell.label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            AppFormatters.moneyPlain(cell.value),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 12,
              fontWeight:
                  cell.bold ? FontWeight.w800 : FontWeight.w700,
              color: cell.color,
            ),
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

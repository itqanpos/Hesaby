// lib/shared/widgets/statements/widgets/statement_entry_row.dart
//
// Single row of the account statement table.
//
// Visual parity with the v14 `_EntryRow` (customer + supplier), driven
// entirely by [AugmentedEntry]. Differences from v14 — see the batch 2c
// design decisions announced in chat:
// * Date column is `dd/MM/yy` at [StatementColumns.date] (62px).
// * Numeric columns use `moneyPlain` + [FittedBox] to prevent overflow.
// * The invoice breakdown lines ("قيمة" / "مدفوع") use `money` (with
//   currency) because the description cell has horizontal room.
// * The row is tappable **only** when [onTap] is provided by the parent;
//   otherwise it renders as a plain `Container` (no Material/InkWell
//   overhead per row).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/utils/formatters.dart';
import '../models/statement_models.dart';
import 'statement_table_header.dart';

class StatementEntryRow extends StatelessWidget {
  const StatementEntryRow({
    required this.aug,
    required this.isEven,
    this.onTap,
    super.key,
  });

  final AugmentedEntry aug;

  /// Alternating row background (zebra striping).
  final bool isEven;

  /// Optional tap handler. When null, the row is a plain container.
  final void Function(AugmentedEntry)? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final StatementEntryView entry = aug.entry;

    final Color rowColor = isEven
        ? scheme.surface
        : scheme.surfaceContainerHighest.withValues(alpha: 0.3);

    final Color typeColor =
        entry.debit > 0 ? scheme.error : const Color(0xFF1B5E20);

    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // Date
          SizedBox(
            width: StatementColumns.date,
            child: Text(
              DateFormat('dd/MM/yy', 'en_US')
                  .format(entry.date.toLocal()),
              style: const TextStyle(fontSize: 11),
            ),
          ),
          // Description
          Expanded(
            child: _DescriptionCell(entry: entry, typeColor: typeColor),
          ),
          // Previous balance
          _NumericCell(
            width: StatementColumns.prevBalance,
            text: _balanceText(aug.previousBalance),
            color: _balanceColor(aug.previousBalance, scheme),
            weight: FontWeight.w600,
          ),
          // Paid (this movement's credit)
          _NumericCell(
            width: StatementColumns.paid,
            text: entry.credit > 0
                ? AppFormatters.moneyPlain(entry.credit)
                : '—',
            color: entry.credit > 0
                ? const Color(0xFF1B5E20)
                : scheme.onSurfaceVariant,
            weight:
                entry.credit > 0 ? FontWeight.w600 : FontWeight.normal,
          ),
          // Current balance
          _NumericCell(
            width: StatementColumns.currentBalance,
            text: _balanceText(aug.currentBalance),
            color: _balanceColor(aug.currentBalance, scheme),
            weight: FontWeight.w800,
          ),
        ],
      ),
    );

    if (onTap == null) {
      return Container(color: rowColor, child: content);
    }
    return Material(
      color: rowColor,
      child: InkWell(
        onTap: () => onTap!(aug),
        child: content,
      ),
    );
  }

  static String _balanceText(double balance) {
    if (balance > 0.01) {
      return '+${AppFormatters.moneyPlain(balance)}';
    }
    if (balance < -0.01) {
      return '−${AppFormatters.moneyPlain(balance.abs())}';
    }
    return '0.00';
  }

  static Color _balanceColor(double balance, ColorScheme scheme) {
    if (balance > 0.01) return scheme.error;
    if (balance < -0.01) return const Color(0xFF1B5E20);
    return scheme.onSurfaceVariant;
  }
}

// ============================================================================
// Description cell
// ============================================================================

class _DescriptionCell extends StatelessWidget {
  const _DescriptionCell({
    required this.entry,
    required this.typeColor,
  });

  final StatementEntryView entry;
  final Color typeColor;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool showBreakdown = entry.showsInvoiceBreakdown;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          entry.hasDescription
              ? entry.description!
              : entry.kind.arabicLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: typeColor,
          ),
        ),
        if (showBreakdown && entry.debit > 0) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            'قيمة: ${AppFormatters.money(entry.debit)}',
            style: TextStyle(fontSize: 10, color: scheme.error),
          ),
        ],
        if (showBreakdown && entry.credit > 0) ...<Widget>[
          const SizedBox(height: 1),
          Text(
            'مدفوع: ${AppFormatters.money(entry.credit)}',
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF1B5E20),
            ),
          ),
        ],
        if (entry.hasReference) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            entry.reference!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================================
// Numeric cell
// ============================================================================

class _NumericCell extends StatelessWidget {
  const _NumericCell({
    required this.width,
    required this.text,
    required this.color,
    required this.weight,
  });

  final double width;
  final String text;
  final Color color;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            text,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              fontWeight: weight,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

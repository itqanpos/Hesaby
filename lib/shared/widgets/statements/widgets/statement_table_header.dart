// lib/shared/widgets/statements/widgets/statement_table_header.dart
//
// Sticky table header row for the account statement.
//
// **Sticky, not scrolled:** unlike v14 (where the header lived at index 0
// of the ListView and scrolled away), this header is placed by the parent
// in a `Column` above the `ListView`. The parent must therefore render it
// only when `!statement.isEmpty`.
//
// **Column widths** are exported via the `StatementColumns` class so the
// row widget in `statement_entry_row.dart` can consume the exact same
// constants — no risk of drift between header and rows.
//
// Column order (RTL visual order is the reverse of the widget order, i.e.
// `Date` appears rightmost, `CurrentBalance` leftmost — matching v14):
//
//   [Date] | [Description (Expanded)] | [PrevBalance] | [Paid] | [CurrentBalance]

import 'package:flutter/material.dart';

/// Shared column widths for the statement table header **and** entry rows.
///
/// Changing any value here automatically affects both.
abstract final class StatementColumns {
  /// Fits `dd/MM/yy` at fontSize 11 (~48px text) plus ~14px of padding.
  static const double date = 62;

  /// Fits `+1,234.56` at fontSize 11.
  static const double prevBalance = 70;

  /// Fits `1,234.56` at fontSize 11.
  static const double paid = 70;

  /// Fits `+1,234.56` at fontSize 11 with bold weight.
  static const double currentBalance = 84;
}

class StatementTableHeader extends StatelessWidget {
  const StatementTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    const TextStyle style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: Colors.grey,
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: const Row(
        children: <Widget>[
          _HeaderCell(
            width: StatementColumns.date,
            text: 'التاريخ',
            style: style,
          ),
          _HeaderCell(
            text: 'البيان',
            style: style,
            isExpanded: true,
          ),
          _HeaderCell(
            width: StatementColumns.prevBalance,
            text: 'الرصيد',
            style: style,
            alignRight: true,
          ),
          _HeaderCell(
            width: StatementColumns.paid,
            text: 'المدفوع',
            style: style,
            alignRight: true,
          ),
          _HeaderCell(
            width: StatementColumns.currentBalance,
            text: 'الرصيد الحالي',
            style: style,
            alignRight: true,
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.text,
    required this.style,
    this.width = 0,
    this.isExpanded = false,
    this.alignRight = false,
  });

  final double width;
  final String text;
  final TextStyle style;
  final bool isExpanded;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: style,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
      ),
    );

    if (isExpanded) {
      return Expanded(child: content);
    }
    return SizedBox(width: width, child: content);
  }
}

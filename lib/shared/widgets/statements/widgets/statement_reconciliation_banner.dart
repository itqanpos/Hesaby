// lib/shared/widgets/statements/widgets/statement_reconciliation_banner.dart
//
// Warning banner shown when the balance cached on the party row
// (`customers.balance`) disagrees with the balance computed from the
// statement entries.
//
// This is a **soft** warning, not an error:
// * The statement's computed balance is authoritative for the UI.
// * The cached balance is a denormalized column maintained by triggers;
//   occasional drift is a data-integrity signal, not a UI bug.
// * The banner lets the user refresh the statement (usually enough — the
//   cached column is typically fixed on the next write to the party).
//
// Shown only when `StatementView.hasReconciliationMismatch` is true,
// which for suppliers is always false because `Supplier` does not carry a
// cached balance column.

import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';

class StatementReconciliationBanner extends StatelessWidget {
  const StatementReconciliationBanner({
    required this.storedBalance,
    required this.computedBalance,
    this.onRefresh,
    super.key,
  });

  /// The balance cached on the party row.
  final double storedBalance;

  /// The balance recomputed from the statement entries — authoritative.
  final double computedBalance;

  /// Optional refresh callback (usually the page's own `_refresh`).
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double diff = storedBalance - computedBalance;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFCC80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.warning_amber_outlined,
            color: Color(0xFFE65100),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'الرصيد المخزَّن يختلف عن الرصيد المحسوب',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF5D4037),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'المخزَّن: ${AppFormatters.money(storedBalance)}  ·  '
                  'المحسوب: ${AppFormatters.money(computedBalance)}  ·  '
                  'الفرق: ${AppFormatters.signedMoney(diff)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF5D4037),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (onRefresh != null)
            TextButton(
              onPressed: () => onRefresh!(),
              child: const Text('تحديث'),
            ),
        ],
      ),
    );
  }
}

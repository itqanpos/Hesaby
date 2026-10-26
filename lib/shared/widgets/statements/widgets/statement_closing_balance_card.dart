// lib/shared/widgets/statements/widgets/statement_closing_balance_card.dart
//
// Closing balance card shown at the bottom of the entries list.
//
// Uses [StatementView.closingBalanceLabel] for the wording (customer vs
// supplier) and the **recomputed** [closingBalance] for the number, so
// any drift between the domain entity and the recomputed value never
// silently affects the displayed amount.

import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../models/statement_models.dart';

class StatementClosingBalanceCard extends StatelessWidget {
  const StatementClosingBalanceCard({
    required this.view,
    required this.closingBalance,
    required this.entryCount,
    super.key,
  });

  /// Used only for the party-kind-aware label.
  final StatementView view;

  /// The authoritative closing balance
  /// ([ComputedStatement.closingBalance]).
  final double closingBalance;

  final int entryCount;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final bool weOwe = closingBalance > 0.01;
    final bool theyOweUs = closingBalance < -0.01;

    final Color bg = weOwe
        ? scheme.errorContainer
        : theyOweUs
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest;
    final Color fg = weOwe
        ? scheme.onErrorContainer
        : theyOweUs
            ? scheme.onPrimaryContainer
            : scheme.onSurfaceVariant;
    final IconData icon = weOwe
        ? Icons.warning_amber_outlined
        : theyOweUs
            ? Icons.account_balance_wallet_outlined
            : Icons.check_circle_outline;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, color: fg, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      view.closingBalanceLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                AppFormatters.money(closingBalance.abs()),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: fg,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'عدد الحركات: ${AppFormatters.integer(entryCount)}',
                style: theme.textTheme.bodySmall?.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

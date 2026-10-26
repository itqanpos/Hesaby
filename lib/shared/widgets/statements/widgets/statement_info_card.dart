// lib/shared/widgets/statements/widgets/statement_info_card.dart
//
// Party identity card shown at the top of every account statement.
// Visual parity with the legacy `_CustomerInfoCard` / `_SupplierInfoCard`
// from v14, but driven entirely by [StatementView].

import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../models/statement_models.dart';

class StatementInfoCard extends StatelessWidget {
  const StatementInfoCard({
    required this.view,
    required this.avatarIcon,
    required this.computedClosingBalance,
    super.key,
  });

  /// Flattened statement view carrying the party identity.
  final StatementView view;

  /// Avatar icon — `Icons.person_outline` for customers,
  /// `Icons.local_shipping_outlined` for suppliers.
  final IconData avatarIcon;

  /// The authoritative closing balance computed by
  /// [ComputedStatement.closingBalance]. Used instead of
  /// [StatementView.closingBalance] so any drift between the domain
  /// entity and the recomputed value is never silently displayed.
  final double computedClosingBalance;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final List<String> meta = <String>[];
    final String? code = view.partyCode;
    if (code != null && code.trim().isNotEmpty) {
      meta.add('كود: $code');
    }
    final String? phone = view.partyPhone;
    if (phone != null && phone.trim().isNotEmpty) {
      meta.add(phone);
    }

    final double bal = computedClosingBalance;
    final bool weOwe = bal > 0.01;
    final bool theyOweUs = bal < -0.01;
    final Color balanceColor = weOwe
        ? scheme.error
        : theyOweUs
            ? const Color(0xFF1B5E20)
            : scheme.onSurfaceVariant;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Icon(avatarIcon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        view.partyName,
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (meta.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          meta.join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    view.partyBalanceLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: balanceColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  AppFormatters.money(bal.abs()),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: balanceColor,
                    fontWeight: FontWeight.w800,
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

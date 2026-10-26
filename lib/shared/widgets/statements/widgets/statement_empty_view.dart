// lib/shared/widgets/statements/widgets/statement_empty_view.dart
//
// Empty state for the entries list. Wrapped in a `RefreshIndicator` +
// `ListView` so pull-to-refresh still works when the statement has no
// movements.

import 'package:flutter/material.dart';

import '../../app_empty.dart';
import '../models/statement_models.dart';

class StatementEmptyView extends StatelessWidget {
  const StatementEmptyView({
    required this.onRefresh,
    required this.partyKind,
    super.key,
  });

  final Future<void> Function() onRefresh;
  final StatementPartyKind partyKind;

  @override
  Widget build(BuildContext context) {
    final String message = partyKind == StatementPartyKind.customer
        ? 'لم تُسجَّل أي حركة على هذا العميل في الفترة المحددة.'
        : 'لم تُسجَّل أي حركة على هذا المورد في الفترة المحددة.';

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          SizedBox(
            height: 320,
            child: AppEmptyView(
              icon: Icons.receipt_long_outlined,
              title: 'لا توجد حركات',
              message: message,
            ),
          ),
        ],
      ),
    );
  }
}

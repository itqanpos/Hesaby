// lib/shared/widgets/statements/widgets/statement_entry_filter_chips.dart
//
// Horizontal chips row for the entry-type filter (all / sale /
// saleReversal / purchase / payment / adjustment).
//
// * The available filter list is computed **by the parent** via
//   `availableEntryFilters(partyKind)` and passed in. This keeps the
//   widget stateless and testable, and lets future party types (employee,
//   cashbox) define their own filter sets without touching this widget.
// * When the list contains at most one filter, the entire row is hidden
//   (see Phase 2b design decision #3) — showing a single "all" chip would
//   be noise.
// * Chips drive display-only filtering (`ComputedStatement.displayFiltered`).
//   Totals and opening/closing balances are **not** affected — see
//   `ComputedStatement.displayFiltered` docs for the rationale.

import 'package:flutter/material.dart';

import '../models/statement_models.dart';

class StatementEntryFilterChips extends StatelessWidget {
  const StatementEntryFilterChips({
    required this.filters,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  /// Filters offered for the current party, produced by
  /// `availableEntryFilters(partyKind)`. Must contain
  /// [StatementEntryFilter.all].
  final List<StatementEntryFilter> filters;

  /// Currently active filter.
  final StatementEntryFilter selected;

  final void Function(StatementEntryFilter) onSelect;

  @override
  Widget build(BuildContext context) {
    if (filters.length <= 1) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < filters.length; i++) ...<Widget>[
            _chip(context, filters[i]),
            if (i != filters.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, StatementEntryFilter value) {
    final bool isSelected = selected == value;
    return FilterChip(
      label: Text(value.arabicLabel),
      selected: isSelected,
      onSelected: (_) => onSelect(value),
      showCheckmark: false,
    );
  }
}

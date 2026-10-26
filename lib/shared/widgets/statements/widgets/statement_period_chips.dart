// lib/shared/widgets/statements/widgets/statement_period_chips.dart
//
// Horizontal chips row for the quick period presets.
//
// **Phase 4 update:** no more `customRange` parameter — the `custom`
// preset was removed (see `statement_filters.dart`). This widget is now
// only used inside `statement_filter_sheet.dart`.

import 'package:flutter/material.dart';

import '../models/statement_filters.dart';

class StatementPeriodChips extends StatelessWidget {
  const StatementPeriodChips({
    required this.preset,
    required this.onSelect,
    super.key,
  });

  final StatementPeriodPreset preset;
  final void Function(StatementPeriodPreset) onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: <Widget>[
          for (final StatementPeriodPreset value
              in StatementPeriodPreset.values) ...<Widget>[
            ChoiceChip(
              label: Text(value.label),
              selected: preset == value,
              onSelected: (_) => onSelect(value),
              showCheckmark: false,
            ),
            if (value != StatementPeriodPreset.values.last)
              const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

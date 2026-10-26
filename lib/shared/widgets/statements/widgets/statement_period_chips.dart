// lib/shared/widgets/statements/widgets/statement_period_chips.dart
//
// Horizontal chips row for the quick period presets.
//
// * `customRange` uses a record `(DateTime, DateTime)?` rather than
//   Material's `DateTimeRange?` so this widget stays free of `material`
//   dependencies beyond widgets themselves, and so it lines up 1-to-1
//   with the `StatementPeriodPresetX.computeFrom/computeTo` signatures
//   defined in `statement_filters.dart`.
// * The parent (`AccountStatementPage`) is responsible for opening the
//   date-range picker when `custom` is selected; this widget only emits
//   the preset change.

import 'package:flutter/material.dart';

import '../models/statement_filters.dart';

class StatementPeriodChips extends StatelessWidget {
  const StatementPeriodChips({
    required this.preset,
    required this.customRange,
    required this.onSelect,
    super.key,
  });

  final StatementPeriodPreset preset;

  /// The currently selected custom range, if any. Used only to label the
  /// "نطاق مخصص" chip when `preset == StatementPeriodPreset.custom`.
  final (DateTime, DateTime)? customRange;

  /// Emitted when the user taps a chip. The parent is expected to handle
  /// `StatementPeriodPreset.custom` by opening a date-range picker.
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
            _chip(context, value),
            if (value != StatementPeriodPreset.values.last)
              const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, StatementPeriodPreset value) {
    return ChoiceChip(
      label: Text(value.label(customRange: customRange)),
      selected: preset == value,
      onSelected: (_) => onSelect(value),
      showCheckmark: false,
    );
  }
}

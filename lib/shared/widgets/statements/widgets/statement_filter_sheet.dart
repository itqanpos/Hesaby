// lib/shared/widgets/statements/widgets/statement_filter_sheet.dart
//
// Bottom sheet that groups the period presets and the entry-type filters
// in a single place. Replaces the previous two horizontal chip rows that
// lived above the statement table.
//
// Behaviour:
// * The sheet owns a **local** copy of the current filter state via its
//   own `State`. Chips update this state immediately (visible feedback)
//   but the page is only notified when the user taps "تطبيق".
// * "إعادة تعيين" resets both the period and the entry filter to `all`
//   in-place (without closing) so the user can still adjust further
//   before applying.
// * Dismissing the sheet (barrier tap, drag down) returns `null` —
//   the page keeps its current filter state untouched.
//
// The sheet re-uses [StatementPeriodChips] and [StatementEntryFilterChips]
// so the visual language stays consistent with the rest of the app.

import 'package:flutter/material.dart';

import '../models/statement_filters.dart';
import '../models/statement_models.dart';
import 'statement_entry_filter_chips.dart';
import 'statement_period_chips.dart';

/// Result of the filter sheet — returned when the user taps "تطبيق".
@immutable
class StatementFilterResult {
  const StatementFilterResult({
    required this.preset,
    required this.entryFilter,
  });

  final StatementPeriodPreset preset;
  final StatementEntryFilter entryFilter;

  /// Whether both filters are back to their default "all" values.
  bool get isDefault =>
      preset == StatementPeriodPreset.all &&
      entryFilter == StatementEntryFilter.all;
}

/// Opens the filter sheet and returns the user's selection, or `null` if
/// the sheet was dismissed without applying.
Future<StatementFilterResult?> showStatementFilterSheet({
  required BuildContext context,
  required StatementPeriodPreset initialPreset,
  required StatementEntryFilter initialEntryFilter,
  required StatementPartyKind partyKind,
}) {
  final List<StatementEntryFilter> filters =
      availableEntryFilters(partyKind);

  return showModalBottomSheet<StatementFilterResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext ctx) {
      return _FilterSheetBody(
        initialPreset: initialPreset,
        initialEntryFilter: initialEntryFilter,
        filters: filters,
      );
    },
  );
}

// ============================================================================
// Sheet body
// ============================================================================

class _FilterSheetBody extends StatefulWidget {
  const _FilterSheetBody({
    required this.initialPreset,
    required this.initialEntryFilter,
    required this.filters,
  });

  final StatementPeriodPreset initialPreset;
  final StatementEntryFilter initialEntryFilter;
  final List<StatementEntryFilter> filters;

  @override
  State<_FilterSheetBody> createState() => _FilterSheetBodyState();
}

class _FilterSheetBodyState extends State<_FilterSheetBody> {
  late StatementPeriodPreset _preset = widget.initialPreset;
  late StatementEntryFilter _entryFilter = widget.initialEntryFilter;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ---- Header ---------------------------------------------
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Row(
                  children: <Widget>[
                    Text(
                      'تصفية الكشف',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _preset = StatementPeriodPreset.all;
                          _entryFilter = StatementEntryFilter.all;
                        });
                      },
                      child: const Text('إعادة تعيين'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              const SizedBox(height: 8),

              // ---- Period section -------------------------------------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'الفترة',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              StatementPeriodChips(
                preset: _preset,
                onSelect: (StatementPeriodPreset p) =>
                    setState(() => _preset = p),
              ),

              // ---- Entry type section (only when >1 filter) ------------
              if (widget.filters.length > 1) ...<Widget>[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'نوع الحركة',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                StatementEntryFilterChips(
                  filters: widget.filters,
                  selected: _entryFilter,
                  onSelect: (StatementEntryFilter f) =>
                      setState(() => _entryFilter = f),
                ),
              ],

              // ---- Apply button ----------------------------------------
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      StatementFilterResult(
                        preset: _preset,
                        entryFilter: _entryFilter,
                      ),
                    );
                  },
                  child: const Text('تطبيق'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

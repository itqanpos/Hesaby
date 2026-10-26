// lib/shared/widgets/statements/widgets/statement_filter_sheet.dart
//
// Bottom sheet that groups the period presets and the entry-type filters
// in a single place. Replaces the previous two horizontal chip rows.
//
// Behaviour:
// * The sheet owns a **local** copy of the current filter state. Chips
//   update this local state immediately (visible feedback) but the page
//   is only notified when the user taps "تطبيق".
// * "إعادة تعيين" resets both the period and the entry filter to `all`.
// * Selecting "نطاق مخصص" temporarily closes the sheet (Material's
//   `showDateRangePicker` is a full-screen route) and re-opens it once the
//   user has picked a range. This is the standard pattern for combining
//   `showModalBottomSheet` with date pickers on mobile.
//
// The sheet re-uses [StatementPeriodChips] and [StatementEntryFilterChips]
// so the visual language stays consistent.

import 'package:flutter/material.dart';

import '../models/statement_filters.dart';
import '../models/statement_models.dart';
import 'statement_entry_filter_chips.dart';
import 'statement_period_chips.dart';

/// Result of the filter sheet.
@immutable
class StatementFilterResult {
  const StatementFilterResult({
    required this.preset,
    required this.customRange,
    required this.entryFilter,
  });

  final StatementPeriodPreset preset;
  final (DateTime, DateTime)? customRange;
  final StatementEntryFilter entryFilter;

  bool get isDefault =>
      preset == StatementPeriodPreset.all &&
      entryFilter == StatementEntryFilter.all;
}

/// Opens the filter sheet and returns the user's selection, or `null` if
/// the sheet was dismissed without applying.
Future<StatementFilterResult?> showStatementFilterSheet({
  required BuildContext context,
  required StatementPeriodPreset initialPreset,
  required (DateTime, DateTime)? initialCustomRange,
  required StatementEntryFilter initialEntryFilter,
  required StatementPartyKind partyKind,
}) async {
  StatementPeriodPreset localPreset = initialPreset;
  (DateTime, DateTime)? localRange = initialCustomRange;
  StatementEntryFilter localFilter = initialEntryFilter;

  final List<StatementEntryFilter> filters =
      availableEntryFilters(partyKind);

  bool customRangePicked = false;

  while (true) {
    final StatementFilterResult? result =
        await showModalBottomSheet<StatementFilterResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetCtx) {
        return _FilterSheetBody(
          preset: localPreset,
          customRange: localRange,
          entryFilter: localFilter,
          filters: filters,
          onPresetChanged: (StatementPeriodPreset p) {
            if (p == StatementPeriodPreset.custom) {
              // Signal the outer loop to open the date picker and
              // re-open the sheet afterwards.
              customRangePicked = true;
              Navigator.of(sheetCtx).pop(_FilterSheetAction.openCustomRange);
            } else {
              localPreset = p;
              localRange = null;
              _rebuildSheet(sheetCtx);
            }
          },
          onEntryFilterChanged: (StatementEntryFilter f) {
            localFilter = f;
            _rebuildSheet(sheetCtx);
          },
          onApply: () {
            Navigator.of(sheetCtx).pop(
              StatementFilterResult(
                preset: localPreset,
                customRange: localRange,
                entryFilter: localFilter,
              ),
            );
          },
          onReset: () {
            localPreset = StatementPeriodPreset.all;
            localRange = null;
            localFilter = StatementEntryFilter.all;
            _rebuildSheet(sheetCtx);
          },
        );
      },
    );

    // The sheet returned a sentinel asking us to open the date picker.
    if (identical(result, _FilterSheetAction.openCustomRange)) {
      if (!context.mounted) return null;
      final DateTime now = DateTime.now();
      final DateTimeRange? picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: now,
        initialDateRange: localRange == null
            ? null
            : DateTimeRange(start: localRange!.$1, end: localRange!.$2),
        helpText: 'اختر الفترة',
        saveText: 'تطبيق',
      );
      if (picked == null) {
        // User cancelled the date picker; re-open the sheet unchanged.
        if (!context.mounted) return null;
        continue;
      }
      localPreset = StatementPeriodPreset.custom;
      localRange = (picked.start, picked.end);
      if (!context.mounted) return null;
      continue;
    }

    // Normal dismissal (barrier tap) returns null; keep the previous
    // selection untouched.
    return result;
  }
}

/// Sentinel value used to signal "open the date picker, then re-open the
/// sheet". Identical() is used to distinguish it from a real result.
class _FilterSheetAction {
  static const StatementFilterResult openCustomRange =
      StatementFilterResult(
    preset: StatementPeriodPreset.all,
    customRange: null,
    entryFilter: StatementEntryFilter.all,
  );
}

void _rebuildSheet(BuildContext sheetCtx) {
  // Trigger a rebuild of the sheet body using its own State.
  // `showModalBottomSheet` does not expose a setState, so we rely on the
  // `StatefulBuilder` used inside `_FilterSheetBody` instead.
  // This function is therefore a no-op kept for readability — the actual
  // rebuild is handled inside `_FilterSheetBody`'s StatefulBuilder.
}

// ============================================================================
// Sheet body
// ============================================================================

class _FilterSheetBody extends StatefulWidget {
  const _FilterSheetBody({
    required this.preset,
    required this.customRange,
    required this.entryFilter,
    required this.filters,
    required this.onPresetChanged,
    required this.onEntryFilterChanged,
    required this.onApply,
    required this.onReset,
  });

  final StatementPeriodPreset preset;
  final (DateTime, DateTime)? customRange;
  final StatementEntryFilter entryFilter;
  final List<StatementEntryFilter> filters;
  final void Function(StatementPeriodPreset) onPresetChanged;
  final void Function(StatementEntryFilter) onEntryFilterChanged;
  final VoidCallback onApply;
  final VoidCallback onReset;

  @override
  State<_FilterSheetBody> createState() => _FilterSheetBodyState();
}

class _FilterSheetBodyState extends State<_FilterSheetBody> {
  late StatementPeriodPreset _preset = widget.preset;
  late (DateTime, DateTime)? _customRange = widget.customRange;
  late StatementEntryFilter _entryFilter = widget.entryFilter;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
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
                        _customRange = null;
                        _entryFilter = StatementEntryFilter.all;
                      });
                      widget.onReset();
                    },
                    child: const Text('إعادة تعيين'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
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
              customRange: _customRange,
              onSelect: (StatementPeriodPreset p) {
                if (p == StatementPeriodPreset.custom) {
                  widget.onPresetChanged(p);
                  return;
                }
                setState(() {
                  _preset = p;
                  _customRange = null;
                });
              },
            ),
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
                onSelect: (StatementEntryFilter f) {
                  setState(() => _entryFilter = f);
                },
              ),
            ],
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FilledButton(
                onPressed: () {
                  // Sync the local state into the outer closure before
                  // applying, so the caller sees the final values.
                  widget.onPresetChanged(_preset);
                  widget.onEntryFilterChanged(_entryFilter);
                  widget.onApply();
                },
                child: const Text('تطبيق'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

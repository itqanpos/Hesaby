// lib/shared/widgets/statements/models/statement_filters.dart
//
// Display-only period shortcuts for account statements.
//
// **Phase 4 update:** the `custom` preset was removed in favour of a
// simpler 4-chip model (all / this month / last 30 days / this year).
// Reason: combining `showModalBottomSheet` with `showDateRangePicker`
// inside a single "filter button" flow added complexity that was not worth
// the UX gain — a user needing an arbitrary range can pick one of the
// presets, and the statement is regenerated from the provider anyway.
//
// This file intentionally contains **only** `StatementPeriodPreset` and
// its extension. The entry-type filter (`StatementEntryFilter`) lives in
// `statement_models.dart` because it is consumed directly by
// `ComputedStatement.displayFiltered`.

// ============================================================================
// Period preset
// ============================================================================

/// Quick period shortcuts shown inside the statement filter sheet.
enum StatementPeriodPreset { all, thisMonth, last30Days, thisYear }

extension StatementPeriodPresetX on StatementPeriodPreset {
  /// Computes the inclusive `from` date for this preset, or `null` for
  /// "since the beginning".
  ///
  /// [now] is passed explicitly so the method is pure and testable.
  DateTime? computeFrom({required DateTime now}) {
    switch (this) {
      case StatementPeriodPreset.all:
        return null;
      case StatementPeriodPreset.thisMonth:
        return DateTime(now.year, now.month, 1);
      case StatementPeriodPreset.last30Days:
        return DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 30));
      case StatementPeriodPreset.thisYear:
        return DateTime(now.year, 1, 1);
    }
  }

  /// Computes the inclusive `to` date for this preset, or `null` for
  /// "up to now".
  DateTime? computeTo({required DateTime now}) {
    switch (this) {
      case StatementPeriodPreset.all:
        return null;
      case StatementPeriodPreset.thisMonth:
      case StatementPeriodPreset.last30Days:
      case StatementPeriodPreset.thisYear:
        return now;
    }
  }

  /// Arabic label for the chip.
  String get label {
    switch (this) {
      case StatementPeriodPreset.all:
        return 'الكل';
      case StatementPeriodPreset.thisMonth:
        return 'هذا الشهر';
      case StatementPeriodPreset.last30Days:
        return 'آخر 30 يومًا';
      case StatementPeriodPreset.thisYear:
        return 'هذا العام';
    }
  }
}

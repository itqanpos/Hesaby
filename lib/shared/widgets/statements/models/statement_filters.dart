// lib/shared/widgets/statements/models/statement_filters.dart
//
// Display-only period shortcuts for account statements.
//
// NOTE: This file intentionally contains **only** `StatementPeriodPreset`
// and its extension. The entry-type filter (`StatementEntryFilter`) lives
// in `statement_models.dart` because it is consumed directly by
// `ComputedStatement.displayFiltered` — keeping it here would create a
// circular import between the two model files.

import '../../../../core/utils/formatters.dart';

// ============================================================================
// Period preset
// ============================================================================

/// Quick period shortcuts shown as chips above the statement.
enum StatementPeriodPreset { all, thisMonth, last30Days, thisYear, custom }

extension StatementPeriodPresetX on StatementPeriodPreset {
  /// Computes the inclusive `from` date for this preset, or `null` for
  /// "since the beginning".
  ///
  /// [now] is passed explicitly so the method is pure and testable.
  /// [customRange] is a `(start, end)` record used only for
  /// [StatementPeriodPreset.custom].
  DateTime? computeFrom({
    required DateTime now,
    (DateTime, DateTime)? customRange,
  }) {
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
      case StatementPeriodPreset.custom:
        return customRange?.$1;
    }
  }

  /// Computes the inclusive `to` date for this preset, or `null` for
  /// "up to now".
  DateTime? computeTo({
    required DateTime now,
    (DateTime, DateTime)? customRange,
  }) {
    switch (this) {
      case StatementPeriodPreset.all:
        return null;
      case StatementPeriodPreset.thisMonth:
      case StatementPeriodPreset.last30Days:
      case StatementPeriodPreset.thisYear:
        return now;
      case StatementPeriodPreset.custom:
        if (customRange == null) return null;
        final DateTime end = customRange.$2;
        return DateTime(end.year, end.month, end.day, 23, 59, 59);
    }
  }

  /// Human-readable label for the chip.
  String label({(DateTime, DateTime)? customRange}) {
    switch (this) {
      case StatementPeriodPreset.all:
        return 'الكل';
      case StatementPeriodPreset.thisMonth:
        return 'هذا الشهر';
      case StatementPeriodPreset.last30Days:
        return 'آخر 30 يومًا';
      case StatementPeriodPreset.thisYear:
        return 'هذا العام';
      case StatementPeriodPreset.custom:
        if (customRange == null) return 'نطاق مخصص';
        return '${AppFormatters.date(customRange.$1)} → '
            '${AppFormatters.date(customRange.$2)}';
    }
  }
}

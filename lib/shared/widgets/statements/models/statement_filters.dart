// lib/shared/widgets/statements/models/statement_filters.dart
//
// Display-only filters for account statements:
// * [StatementPeriodPreset] — quick period shortcuts (this month, last 30
//   days, …). The actual date range is computed by the caller, not here.
// * [StatementEntryFilter] — chip filter for the movement type.
//
// The filtering logic lives entirely in the model layer so the UI stays
// dumb: `_EntriesList` just calls `ComputedStatement.displayFiltered(filter)`
// and renders the result.

import 'package:flutter/foundation.dart';

import '../../../../core/utils/formatters.dart';
import 'statement_models.dart';

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

// ============================================================================
// Entry type filter
// ============================================================================

/// Chip filter for the movement type.
///
/// The set of filters offered to the user depends on the party:
/// * customer → [all, sale, saleReversal, payment, adjustment]
/// * supplier → [all, purchase, payment]
///
/// Use [availableEntryFilters] to obtain the right list.
enum StatementEntryFilter {
  all,
  sale,
  saleReversal,
  purchase,
  payment,
  adjustment;

  /// Arabic label for the chip.
  String get arabicLabel {
    switch (this) {
      case StatementEntryFilter.all:
        return 'الكل';
      case StatementEntryFilter.sale:
        return 'فواتير بيع';
      case StatementEntryFilter.saleReversal:
        return 'إلغاءات';
      case StatementEntryFilter.purchase:
        return 'مشتريات';
      case StatementEntryFilter.payment:
        return 'دفعات';
      case StatementEntryFilter.adjustment:
        return 'تعديلات';
    }
  }

  /// Whether the given entry should be shown when this filter is active.
  bool matches(StatementEntryView entry) {
    switch (this) {
      case StatementEntryFilter.all:
        return true;
      case StatementEntryFilter.sale:
        return entry.kind == StatementEntryKind.sale;
      case StatementEntryFilter.saleReversal:
        return entry.kind == StatementEntryKind.saleReversal;
      case StatementEntryFilter.purchase:
        return entry.kind == StatementEntryKind.purchase;
      case StatementEntryFilter.payment:
        return entry.kind == StatementEntryKind.payment;
      case StatementEntryFilter.adjustment:
        return entry.kind == StatementEntryKind.adjustment;
    }
  }
}

/// Returns the filters that make sense for the given party kind.
///
/// Always non-empty and always starts with [StatementEntryFilter.all].
@immutable
List<StatementEntryFilter> availableEntryFilters(StatementPartyKind kind) {
  switch (kind) {
    case StatementPartyKind.customer:
      return const <StatementEntryFilter>[
        StatementEntryFilter.all,
        StatementEntryFilter.sale,
        StatementEntryFilter.saleReversal,
        StatementEntryFilter.payment,
        StatementEntryFilter.adjustment,
      ];
    case StatementPartyKind.supplier:
      return const <StatementEntryFilter>[
        StatementEntryFilter.all,
        StatementEntryFilter.purchase,
        StatementEntryFilter.payment,
      ];
  }
}

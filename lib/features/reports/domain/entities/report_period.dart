// lib/features/reports/domain/entities/report_period.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:intl/intl.dart';

/// Preset choices for a report's time window.
enum ReportPeriodType {
  all,
  today,
  thisWeek,
  thisMonth,
  thisYear,
  last30Days,
  custom,
}

/// Immutable, timezone-aware period value object shared by every report.
///
/// `null` on either end of [fromDate] / [toDate] means "open-ended" on that
/// side; both being `null` is the canonical "all time" window.
@immutable
class ReportPeriod extends Equatable {
  const ReportPeriod({
    this.type = ReportPeriodType.all,
    this.customRange,
  });

  /// Convenience constructor for the current month.
  factory ReportPeriod.thisMonth() =>
      const ReportPeriod(type: ReportPeriodType.thisMonth);

  final ReportPeriodType type;
  final DateTimeRange? customRange;

  /// Inclusive lower bound of the window, in local time.
  DateTime? get fromDate {
    final DateTime now = DateTime.now();
    switch (type) {
      case ReportPeriodType.all:
        return null;
      case ReportPeriodType.today:
        return DateTime(now.year, now.month, now.day);
      case ReportPeriodType.thisWeek:
        // ISO 8601: Monday is the first day of the week.
        return DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
      case ReportPeriodType.thisMonth:
        return DateTime(now.year, now.month, 1);
      case ReportPeriodType.thisYear:
        return DateTime(now.year, 1, 1);
      case ReportPeriodType.last30Days:
        return DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 29));
      case ReportPeriodType.custom:
        final DateTime? start = customRange?.start;
        if (start == null) return null;
        return DateTime(start.year, start.month, start.day);
    }
  }

  /// Inclusive upper bound of the window, in local time.
  DateTime? get toDate {
    final DateTime now = DateTime.now();
    switch (type) {
      case ReportPeriodType.all:
        return null;
      case ReportPeriodType.today:
      case ReportPeriodType.last30Days:
        return DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      case ReportPeriodType.thisWeek:
      case ReportPeriodType.thisMonth:
      case ReportPeriodType.thisYear:
        return now;
      case ReportPeriodType.custom:
        final DateTime? end = customRange?.end;
        if (end == null) return null;
        return DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    }
  }

  /// Whether the window covers the whole dataset.
  bool get isAll => type == ReportPeriodType.all;

  /// Short Arabic label suitable for chips and PDF headers.
  String get label {
    switch (type) {
      case ReportPeriodType.all:
        return 'الكل';
      case ReportPeriodType.today:
        return 'اليوم';
      case ReportPeriodType.thisWeek:
        return 'هذا الأسبوع';
      case ReportPeriodType.thisMonth:
        return 'هذا الشهر';
      case ReportPeriodType.thisYear:
        return 'هذا العام';
      case ReportPeriodType.last30Days:
        return 'آخر 30 يومًا';
      case ReportPeriodType.custom:
        final DateTimeRange? r = customRange;
        if (r == null) return 'نطاق مخصص';
        final DateFormat fmt = DateFormat('yyyy-MM-dd');
        return '${fmt.format(r.start)} → ${fmt.format(r.end)}';
    }
  }

  ReportPeriod copyWith({
    ReportPeriodType? type,
    DateTimeRange? customRange,
    bool clearCustomRange = false,
  }) {
    return ReportPeriod(
      type: type ?? this.type,
      customRange:
          clearCustomRange ? null : (customRange ?? this.customRange),
    );
  }

  @override
  List<Object?> get props => <Object?>[type, customRange];
}

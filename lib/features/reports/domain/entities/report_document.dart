// lib/features/reports/domain/entities/report_document.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// A printable representation of any report.
@immutable
class ReportDocument extends Equatable {
  const ReportDocument({
    required this.title,
    required this.companyName,
    required this.generatedAt,
    required this.sections,
    this.periodLabel,
    this.branchName,
  });

  final String title;

  /// Localized period label (e.g. "هذا الشهر"). `null` for state reports
  /// like stock valuation or receivables.
  final String? periodLabel;

  final String companyName;
  final String? branchName;
  final DateTime generatedAt;
  final List<ReportSection> sections;

  ReportDocument copyWith({
    String? title,
    String? periodLabel,
    String? companyName,
    String? branchName,
    DateTime? generatedAt,
    List<ReportSection>? sections,
  }) {
    return ReportDocument(
      title: title ?? this.title,
      periodLabel: periodLabel ?? this.periodLabel,
      companyName: companyName ?? this.companyName,
      branchName: branchName ?? this.branchName,
      generatedAt: generatedAt ?? this.generatedAt,
      sections: sections ?? this.sections,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        title,
        periodLabel,
        companyName,
        branchName,
        generatedAt,
        sections,
      ];
}

/// A logical block inside a report. May contain KPIs (small grid),
/// simple label/value lines, and/or a table.
@immutable
class ReportSection extends Equatable {
  const ReportSection({
    this.title,
    this.kpis,
    this.lines,
    this.table,
  });

  final String? title;
  final List<ReportKpi>? kpis;
  final List<ReportLine>? lines;
  final ReportTable? table;

  @override
  List<Object?> get props => <Object?>[title, kpis, lines, table];
}

/// A single KPI cell (label + value). Rendered as a small card.
@immutable
class ReportKpi extends Equatable {
  const ReportKpi({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  List<Object?> get props => <Object?>[label, value, emphasized];
}

/// A single label/value row (totals, breakdowns).
@immutable
class ReportLine extends Equatable {
  const ReportLine({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  List<Object?> get props => <Object?>[label, value, emphasized];
}

/// A tabular block (top products, receivables, payables, etc.).
///
/// [flex] gives the relative width of each column. When omitted, all
/// columns are given equal width.
@immutable
class ReportTable extends Equatable {
  const ReportTable({
    required this.headers,
    required this.rows,
    this.flex,
  });

  final List<String> headers;
  final List<List<String>> rows;

  /// Optional per-column flex factors. Must have the same length as
  /// [headers] when provided.
  final List<double>? flex;

  int get columnCount => headers.length;

  @override
  List<Object?> get props => <Object?>[headers, rows, flex];
}

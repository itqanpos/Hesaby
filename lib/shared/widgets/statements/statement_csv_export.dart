// lib/shared/widgets/statements/statement_csv_export.dart
//
// CSV exporter for account statements.
//
// Design:
// * UTF-8 with BOM (`\uFEFF`) so Excel on Windows/macOS shows Arabic
//   correctly without manual encoding selection.
// * `\r\n` line endings (Excel-friendly).
// * Summary block (party name, kind, period, opening, closing) followed
//   by a blank line, then the data table. This survives round-trips
//   through Excel/LibreOffice without confusing the parser.
// * Respects the caller-supplied filter (WYSIWYG): whatever the user sees
//   in the UI is what gets exported.
// * Numeric cells use `moneyPlain` (`-X.XX`, ASCII minus) so Excel treats
//   them as numbers; the UI keeps the typographic minus (U+2212).
// * All cells run through [_esc], which quotes fields containing `,`,
//   `"`, `\n` or `\r` and doubles embedded quotes — standard RFC 4180.

import '../../../../core/utils/formatters.dart';
import 'models/statement_models.dart';

class StatementCsvExporter {
  const StatementCsvExporter._();

  /// Builds the CSV text for the given statement view.
  ///
  /// [computed] is required (not recomputed here) so the caller controls
  /// how the running balances were derived — the exporter never re-runs
  /// the ordering rule.
  static String build({
    required StatementView view,
    required ComputedStatement computed,
    required StatementEntryFilter filter,
  }) {
    final StringBuffer out = StringBuffer();

    // UTF-8 BOM — keeps Excel from mistaking the file for ANSI.
    out.write('\uFEFF');

    // ---- Summary block --------------------------------------------------
    out.write(_row(<String>['كشف حساب', view.partyName]));
    out.write(_row(<String>['النوع', _partyKindLabel(view.partyKind)]));
    out.write(
      _row(<String>['الفترة', _formatPeriod(view.fromDate, view.toDate)]),
    );
    out.write(_row(<String>[
      'الرصيد الافتتاحي',
      AppFormatters.moneyPlain(view.openingBalance),
    ]));
    out.write(_row(<String>[
      'الرصيد الختامي',
      AppFormatters.moneyPlain(computed.closingBalance),
    ]));

    // Blank separator row.
    out.write('\r\n');

    // ---- Data table -----------------------------------------------------
    out.write(_row(<String>[
      'التاريخ',
      'النوع',
      'البيان',
      'المرجع',
      'مدين',
      'دائن',
      'الرصيد السابق',
      'الرصيد الحالي',
    ]));

    // Chronological order (oldest first) for spreadsheet reading.
    final List<AugmentedEntry> rows =
        computed.displayFiltered(filter).reversed.toList(growable: false);

    for (final AugmentedEntry a in rows) {
      final StatementEntryView e = a.entry;
      out.write(_row(<String>[
        AppFormatters.date(e.date),
        e.kind.arabicLabel,
        e.hasDescription ? e.description! : '',
        e.hasReference ? e.reference! : '',
        e.debit > 0 ? AppFormatters.moneyPlain(e.debit) : '',
        e.credit > 0 ? AppFormatters.moneyPlain(e.credit) : '',
        AppFormatters.moneyPlain(a.previousBalance),
        AppFormatters.moneyPlain(a.currentBalance),
      ]));
    }

    return out.toString();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _row(List<String> cells) =>
      '${cells.map(_esc).join(',')}\r\n';

  static String _esc(String value) {
    final bool needsQuoting = value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    if (!needsQuoting) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  static String _partyKindLabel(StatementPartyKind kind) {
    switch (kind) {
      case StatementPartyKind.customer:
        return 'عميل';
      case StatementPartyKind.supplier:
        return 'مورد';
    }
  }

  static String _formatPeriod(DateTime? from, DateTime? to) {
    if (from == null && to == null) return 'كل الفترات';
    final String f = from == null ? 'البداية' : AppFormatters.date(from);
    final String t = to == null ? 'الآن' : AppFormatters.date(to);
    return '$f → $t';
  }
}

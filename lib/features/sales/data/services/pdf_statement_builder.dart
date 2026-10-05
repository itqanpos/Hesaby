// lib/features/sales/data/services/pdf_statement_builder.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/entities/customer_statement.dart';

/// Builds an A4 PDF statement from a [CustomerStatement].
///
/// The layout is a single dense accounting table:
///
/// ```
/// ┌──────────────────────────────────────────────────────────┐
/// │                  اسم الشركة                              │
/// │                  كشف حساب عميل                            │
/// ├──────────────────────────────────────────────────────────┤
/// │ العميل: أحمد محمد        الفترة: 01/10 → 31/10           │
/// │ الرصيد الافتتاحي: 0.00 ج.م                                │
/// ├──────────┬─────────────────┬────────┬────────┬──────────┤
/// │ التاريخ  │ البيان          │ مدين   │ دائن   │ الرصيد   │
/// ├──────────┼─────────────────┼────────┼────────┼──────────┤
/// │ ...      │ ...             │ ...    │ ...    │ ...      │
/// ├──────────┴─────────────────┼────────┼────────┼──────────┤
/// │ الإجماليات                 │ X      │ Y      │ Z        │
/// └────────────────────────────┴────────┴────────┴──────────┘
/// ```
///
/// Arabic text is rendered right-to-left with the Cairo font, downloaded
/// on demand by the `printing` package and cached afterwards.
abstract final class PdfStatementBuilder {
  /// Builds the PDF and returns its bytes.
  ///
  /// The statement is assumed to be well-formed (typically the output of
  /// `CustomerStatement.build`); an empty entry list produces a valid PDF
  /// showing only the opening and closing balances.
  static Future<Uint8List> build({
    required CustomerStatement statement,
  }) async {
    final pw.ThemeData theme = await _loadTheme();

    final pw.Document document = pw.Document(
      theme: theme,
      title: 'كشف حساب - ${statement.customer.name}',
      author: 'Hesabi',
      creator: 'Hesabi',
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        textDirection: pw.TextDirection.rtl,
        header: (pw.Context context) => _buildPageHeader(context, statement),
        footer: _buildPageFooter,
        build: (pw.Context context) => _buildContent(statement),
      ),
    );

    return document.save();
  }

  // ---------------------------------------------------------------------------
  // Fonts
  // ---------------------------------------------------------------------------

  static Future<pw.ThemeData> _loadTheme() async {
    final pw.Font regular = await PdfGoogleFonts.cairoRegular();
    final pw.Font bold = await PdfGoogleFonts.cairoBold();
    return pw.ThemeData.withFont(base: regular, bold: bold);
  }

  // ---------------------------------------------------------------------------
  // Page header (repeated on every page)
  // ---------------------------------------------------------------------------

  static pw.Widget _buildPageHeader(
    pw.Context context,
    CustomerStatement statement,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        pw.Text(
          'كشف حساب عميل',
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          statement.customer.name,
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 8),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Content
  // ---------------------------------------------------------------------------

  static List<pw.Widget> _buildContent(CustomerStatement statement) {
    return <pw.Widget>[
      _buildInfoBlock(statement),
      pw.SizedBox(height: 12),
      _buildTable(statement),
      pw.SizedBox(height: 12),
      _buildSummaryBlock(statement),
    ];
  }

  static pw.Widget _buildInfoBlock(CustomerStatement statement) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          _infoRow('العميل', statement.customer.name),
          if (statement.customer.hasPhone)
            _infoRow('الهاتف', statement.customer.phone!),
          if (statement.customer.hasCode)
            _infoRow('الكود', statement.customer.code!),
          _infoRow('الفترة', _formatPeriod(statement)),
          _infoRow(
            'تاريخ الإصدار',
            _formatDate(statement.generatedAt),
          ),
        ],
      ),
    );
  }

  static pw.Widget _infoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Table
  // ---------------------------------------------------------------------------

  static pw.Widget _buildTable(CustomerStatement statement) {
    const double fontSize = 9;
    const double headerFontSize = 9;

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(1.6), // date
        1: pw.FlexColumnWidth(3.4), // description
        2: pw.FlexColumnWidth(1.4), // debit
        3: pw.FlexColumnWidth(1.4), // credit
        4: pw.FlexColumnWidth(1.6), // balance
      },
      children: <pw.TableRow>[
        _headerRow(fontSize: headerFontSize),
        _openingBalanceRow(statement, fontSize),
        for (final CustomerStatementEntry entry in statement.entries)
          _entryRow(entry, fontSize),
      ],
    );
  }

  static pw.TableRow _headerRow({required double fontSize}) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: <pw.Widget>[
        _cell('التاريخ', fontSize: fontSize, bold: true, center: true),
        _cell('البيان', fontSize: fontSize, bold: true, center: true),
        _cell('مدين', fontSize: fontSize, bold: true, center: true),
        _cell('دائن', fontSize: fontSize, bold: true, center: true),
        _cell('الرصيد', fontSize: fontSize, bold: true, center: true),
      ],
    );
  }

  static pw.TableRow _openingBalanceRow(
    CustomerStatement statement,
    double fontSize,
  ) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
      children: <pw.Widget>[
        _cell('—', fontSize: fontSize, center: true),
        _cell(
          'رصيد افتتاحي',
          fontSize: fontSize,
          bold: true,
        ),
        _cell('', fontSize: fontSize),
        _cell('', fontSize: fontSize),
        _cell(
          _formatMoney(statement.openingBalance),
          fontSize: fontSize,
          bold: true,
          center: true,
        ),
      ],
    );
  }

  static pw.TableRow _entryRow(
    CustomerStatementEntry entry,
    double fontSize,
  ) {
    final String description = entry.hasDescription
        ? entry.description!
        : _typeLabel(entry.type);

    return pw.TableRow(
      children: <pw.Widget>[
        _cell(
          _formatDate(entry.date),
          fontSize: fontSize,
          center: true,
        ),
        _cell(description, fontSize: fontSize),
        _cell(
          entry.isDebit ? _formatMoney(entry.debit) : '—',
          fontSize: fontSize,
          center: true,
        ),
        _cell(
          entry.isCredit ? _formatMoney(entry.credit) : '—',
          fontSize: fontSize,
          center: true,
        ),
        _cell(
          _formatMoney(entry.balanceAfter ?? 0),
          fontSize: fontSize,
          bold: true,
          center: true,
        ),
      ],
    );
  }

  static pw.Widget _cell(
    String text, {
    required double fontSize,
    bool bold = false,
    bool center = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.right,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Summary
  // ---------------------------------------------------------------------------

  static pw.Widget _buildSummaryBlock(CustomerStatement statement) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          _summaryRow('عدد الحركات', statement.entryCount.toString()),
          _summaryRow('إجمالي المدين', _formatMoney(statement.totalDebit)),
          _summaryRow('إجمالي الدائن', _formatMoney(statement.totalCredit)),
          pw.Divider(height: 8, thickness: 0.4),
          _summaryRow(
            'الرصيد النهائي',
            _formatMoney(statement.closingBalance),
            emphasized: true,
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryRow(
    String label,
    String value, {
    bool emphasized = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: emphasized ? 11 : 9,
              fontWeight:
                  emphasized ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: emphasized ? 11 : 9,
              fontWeight:
                  emphasized ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Page footer
  // ---------------------------------------------------------------------------

  static pw.Widget _buildPageFooter(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.center,
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Text(
        'صفحة ${context.pageNumber} من ${context.pagesCount}',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _formatMoney(double value) {
    final String fixed = value.toStringAsFixed(2);
    return '$fixed ج.م';
  }

  static String _formatDate(DateTime value) {
    final DateTime local = value.toLocal();
    final String y = local.year.toString().padLeft(4, '0');
    final String m = local.month.toString().padLeft(2, '0');
    final String d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _formatPeriod(CustomerStatement statement) {
    final DateTime? from = statement.fromDate;
    final DateTime? to = statement.toDate;
    if (from == null && to == null) {
      return 'من البداية حتى الآن';
    }
    if (from != null && to != null) {
      return '${_formatDate(from)} → ${_formatDate(to)}';
    }
    if (from != null) {
      return 'من ${_formatDate(from)}';
    }
    return 'حتى ${_formatDate(to!)}';
  }

  static String _typeLabel(String type) {
    switch (type) {
      case StatementEntryType.sale:
        return 'فاتورة بيع';
      case StatementEntryType.saleReversal:
        return 'إلغاء فاتورة';
      case StatementEntryType.payment:
        return 'دفعة';
      case StatementEntryType.adjustment:
        return 'تعديل رصيد';
      default:
        return 'حركة';
    }
  }
}

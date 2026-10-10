// lib/features/sales/data/services/pdf_statement_builder.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../settings/domain/entities/company_settings.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../domain/entities/customer_statement.dart';

/// Builds an A4 PDF statement from a [CustomerStatement].
///
/// **Phase P-1b:** accepts an optional [PrintStyleSettings] that scales
/// every font size and selects a base weight.
abstract final class PdfStatementBuilder {
  static Future<Uint8List> build({
    required CustomerStatement statement,
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
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
        header: (pw.Context context) =>
            _buildPageHeader(context, statement, style),
        footer: (pw.Context context) => _buildPageFooter(context, style),
        build: (pw.Context context) => _buildContent(statement, style),
      ),
    );

    return document.save();
  }

  // ---------------------------------------------------------------------------
  // Weight resolution
  // ---------------------------------------------------------------------------

  static pw.FontWeight _weight({
    required PrintFontWeight userWeight,
    required bool emphasized,
  }) {
    if (emphasized || userWeight == PrintFontWeight.bold) {
      return pw.FontWeight.bold;
    }
    return pw.FontWeight.normal;
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
    PrintStyleSettings style,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        pw.Text(
          'كشف حساب عميل',
          style: pw.TextStyle(
            fontSize: style.scale(16),
            fontWeight: _weight(
              userWeight: style.fontWeight,
              emphasized: true,
            ),
          ),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          statement.customer.name,
          style: pw.TextStyle(
            fontSize: style.scale(13),
            fontWeight: _weight(
              userWeight: style.fontWeight,
              emphasized: true,
            ),
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

  static List<pw.Widget> _buildContent(
    CustomerStatement statement,
    PrintStyleSettings style,
  ) {
    return <pw.Widget>[
      _buildInfoBlock(statement, style),
      pw.SizedBox(height: 12),
      _buildTable(statement, style),
      pw.SizedBox(height: 12),
      _buildSummaryBlock(statement, style),
    ];
  }

  static pw.Widget _buildInfoBlock(
    CustomerStatement statement,
    PrintStyleSettings style,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          _infoRow('العميل', statement.customer.name, style),
          if (statement.customer.hasPhone)
            _infoRow('الهاتف', statement.customer.phone!, style),
          if (statement.customer.hasCode)
            _infoRow('الكود', statement.customer.code!, style),
          _infoRow('الفترة', _formatPeriod(statement), style),
          _infoRow(
            'تاريخ الإصدار',
            _formatDate(statement.generatedAt),
            style,
          ),
        ],
      ),
    );
  }

  static pw.Widget _infoRow(
    String label,
    String value,
    PrintStyleSettings style,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: style.scale(9),
              fontWeight: _weight(
                userWeight: style.fontWeight,
                emphasized: false,
              ),
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: style.scale(9),
              fontWeight: _weight(
                userWeight: style.fontWeight,
                emphasized: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Table
  // ---------------------------------------------------------------------------

  static pw.Widget _buildTable(
    CustomerStatement statement,
    PrintStyleSettings style,
  ) {
    final double fontSize = style.scale(9);

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
        _headerRow(fontSize: fontSize, style: style),
        _openingBalanceRow(statement, fontSize, style),
        for (final CustomerStatementEntry entry in statement.entries)
          _entryRow(entry, fontSize, style),
      ],
    );
  }

  static pw.TableRow _headerRow({
    required double fontSize,
    required PrintStyleSettings style,
  }) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: <pw.Widget>[
        _cell('التاريخ',
            fontSize: fontSize,
            style: style,
            emphasized: true,
            center: true),
        _cell('البيان',
            fontSize: fontSize,
            style: style,
            emphasized: true,
            center: true),
        _cell('مدين',
            fontSize: fontSize,
            style: style,
            emphasized: true,
            center: true),
        _cell('دائن',
            fontSize: fontSize,
            style: style,
            emphasized: true,
            center: true),
        _cell('الرصيد',
            fontSize: fontSize,
            style: style,
            emphasized: true,
            center: true),
      ],
    );
  }

  static pw.TableRow _openingBalanceRow(
    CustomerStatement statement,
    double fontSize,
    PrintStyleSettings style,
  ) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
      children: <pw.Widget>[
        _cell('—', fontSize: fontSize, style: style, center: true),
        _cell('رصيد افتتاحي',
            fontSize: fontSize, style: style, emphasized: true),
        _cell('', fontSize: fontSize, style: style),
        _cell('', fontSize: fontSize, style: style),
        _cell(
          _formatMoney(statement.openingBalance),
          fontSize: fontSize,
          style: style,
          emphasized: true,
          center: true,
        ),
      ],
    );
  }

  static pw.TableRow _entryRow(
    CustomerStatementEntry entry,
    double fontSize,
    PrintStyleSettings style,
  ) {
    final String description = entry.hasDescription
        ? entry.description!
        : _typeLabel(entry.type);

    return pw.TableRow(
      children: <pw.Widget>[
        _cell(
          _formatDate(entry.date),
          fontSize: fontSize,
          style: style,
          center: true,
        ),
        _cell(description, fontSize: fontSize, style: style),
        _cell(
          entry.isDebit ? _formatMoney(entry.debit) : '—',
          fontSize: fontSize,
          style: style,
          center: true,
        ),
        _cell(
          entry.isCredit ? _formatMoney(entry.credit) : '—',
          fontSize: fontSize,
          style: style,
          center: true,
        ),
        _cell(
          _formatMoney(entry.balanceAfter ?? 0),
          fontSize: fontSize,
          style: style,
          emphasized: true,
          center: true,
        ),
      ],
    );
  }

  static pw.Widget _cell(
    String text, {
    required double fontSize,
    required PrintStyleSettings style,
    bool emphasized = false,
    bool center = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: _weight(
            userWeight: style.fontWeight,
            emphasized: emphasized,
          ),
        ),
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.right,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Summary
  // ---------------------------------------------------------------------------

  static pw.Widget _buildSummaryBlock(
    CustomerStatement statement,
    PrintStyleSettings style,
  ) {
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
          _summaryRow('عدد الحركات',
              statement.entryCount.toString(), style),
          _summaryRow('إجمالي المدين',
              _formatMoney(statement.totalDebit), style),
          _summaryRow('إجمالي الدائن',
              _formatMoney(statement.totalCredit), style),
          pw.Divider(height: 8, thickness: 0.4),
          _summaryRow(
            'الرصيد النهائي',
            _formatMoney(statement.closingBalance),
            style,
            emphasized: true,
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryRow(
    String label,
    String value,
    PrintStyleSettings style, {
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
              fontSize: style.scale(emphasized ? 11 : 9),
              fontWeight: _weight(
                userWeight: style.fontWeight,
                emphasized: emphasized,
              ),
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: style.scale(emphasized ? 11 : 9),
              fontWeight: _weight(
                userWeight: style.fontWeight,
                emphasized: emphasized,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Page footer
  // ---------------------------------------------------------------------------

  static pw.Widget _buildPageFooter(
    pw.Context context,
    PrintStyleSettings style,
  ) {
    return pw.Container(
      alignment: pw.Alignment.center,
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Text(
        'صفحة ${context.pageNumber} من ${context.pagesCount}',
        style: pw.TextStyle(
          fontSize: style.scale(8),
          color: PdfColors.grey600,
          fontWeight: _weight(
            userWeight: style.fontWeight,
            emphasized: false,
          ),
        ),
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

// lib/features/reports/data/services/pdf_report_builder.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/entities/report_document.dart';

/// Builds an A4 PDF from a [ReportDocument].
///
/// The layout is intentionally uniform across every report:
/// * company header (name + branch),
/// * report title,
/// * period + generation timestamp,
/// * one or more sections (KPIs / lines / tables),
/// * page footer with `صفحة X من Y`.
///
/// Arabic text is rendered RTL with the Cairo font, downloaded on demand
/// by the `printing` package.
abstract final class PdfReportBuilder {
  /// Builds the PDF and returns its bytes.
  static Future<Uint8List> build({
    required ReportDocument document,
  }) async {
    final pw.ThemeData theme = await _loadTheme();

    final pw.Document pdf = pw.Document(
      theme: theme,
      title: document.title,
      author: document.companyName,
      creator: 'Hesabi',
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        textDirection: pw.TextDirection.rtl,
        header: (pw.Context context) => _buildPageHeader(document),
        footer: _buildPageFooter,
        build: (pw.Context context) => _buildContent(document),
      ),
    );

    return pdf.save();
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

  static pw.Widget _buildPageHeader(ReportDocument document) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        pw.Text(
          document.companyName,
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
        if (document.branchName != null) ...<pw.Widget>[
          pw.SizedBox(height: 1),
          pw.Text(
            document.branchName!,
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey700,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ],
        pw.SizedBox(height: 6),
        pw.Divider(height: 1, thickness: 0.4),
        pw.SizedBox(height: 6),
      ],
    );
  }

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
  // Content
  // ---------------------------------------------------------------------------

  static List<pw.Widget> _buildContent(ReportDocument document) {
    return <pw.Widget>[
      _buildTitleBlock(document),
      pw.SizedBox(height: 12),
      for (int i = 0; i < document.sections.length; i++) ...<pw.Widget>[
        _buildSection(document.sections[i]),
        if (i < document.sections.length - 1) pw.SizedBox(height: 14),
      ],
    ];
  }

  static pw.Widget _buildTitleBlock(ReportDocument document) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          pw.Text(
            document.title,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(
                document.periodLabel != null
                    ? 'الفترة: ${document.periodLabel}'
                    : 'الفترة: الكل',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'تاريخ الإصدار: ${_formatDateTime(document.generatedAt)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section
  // ---------------------------------------------------------------------------

  static pw.Widget _buildSection(ReportSection section) {
    final List<pw.Widget> children = <pw.Widget>[];

    if (section.title != null) {
      children.add(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 6),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(
                width: 0.5,
                color: PdfColors.grey500,
              ),
            ),
          ),
          child: pw.Text(
            section.title!,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      );
      children.add(pw.SizedBox(height: 8));
    }

    if (section.kpis != null && section.kpis!.isNotEmpty) {
      children.add(_buildKpiGrid(section.kpis!));
      children.add(pw.SizedBox(height: 8));
    }

    if (section.lines != null && section.lines!.isNotEmpty) {
      for (final ReportLine line in section.lines!) {
        children.add(_buildLine(line));
      }
      children.add(pw.SizedBox(height: 4));
    }

    if (section.table != null && section.table!.rows.isNotEmpty) {
      children.add(_buildTable(section.table!));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: children,
    );
  }

  // ---------------------------------------------------------------------------
  // KPI grid (2 columns)
  // ---------------------------------------------------------------------------

  static pw.Widget _buildKpiGrid(List<ReportKpi> kpis) {
    const int columns = 2;
    final List<pw.Widget> rows = <pw.Widget>[];

    for (int i = 0; i < kpis.length; i += columns) {
      final List<pw.Widget> cells = <pw.Widget>[];
      for (int j = 0; j < columns; j++) {
        final int index = i + j;
        if (index < kpis.length) {
          cells.add(pw.Expanded(child: _buildKpiCard(kpis[index])));
        } else {
          cells.add(pw.Expanded(child: pw.SizedBox()));
        }
        if (j < columns - 1) cells.add(pw.SizedBox(width: 8));
      }
      rows.add(pw.Row(children: cells));
      if (i + columns < kpis.length) rows.add(pw.SizedBox(height: 8));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  static pw.Widget _buildKpiCard(ReportKpi kpi) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(
          color: kpi.emphasized ? PdfColors.blueGrey600 : PdfColors.grey400,
          width: kpi.emphasized ? 0.8 : 0.4,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            kpi.label,
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey700,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            kpi.value,
            style: pw.TextStyle(
              fontSize: kpi.emphasized ? 12 : 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Label / value line
  // ---------------------------------------------------------------------------

  static pw.Widget _buildLine(ReportLine line) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Text(
              line.label,
              style: const pw.TextStyle(fontSize: 10),
              softWrap: true,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Text(
            line.value,
            style: pw.TextStyle(
              fontSize: line.emphasized ? 11 : 10,
              fontWeight:
                  line.emphasized ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
            textAlign: pw.TextAlign.right,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Table
  // ---------------------------------------------------------------------------

  static pw.Widget _buildTable(ReportTable table) {
    const double fontSize = 9;

    final Map<int, pw.TableColumnWidth> columnWidths =
        <int, pw.TableColumnWidth>{};
    for (int i = 0; i < table.columnCount; i++) {
      final double flex = (table.flex != null && i < table.flex!.length)
          ? table.flex![i]
          : 1;
      columnWidths[i] = pw.FlexColumnWidth(flex);
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      columnWidths: columnWidths,
      children: <pw.TableRow>[
        // Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: <pw.Widget>[
            for (final String h in table.headers)
              _cell(h, fontSize: fontSize, bold: true, center: true),
          ],
        ),
        // Rows
        for (final List<String> row in table.rows)
          pw.TableRow(
            children: <pw.Widget>[
              for (int i = 0; i < table.columnCount; i++)
                _cell(
                  i < row.length ? row[i] : '',
                  fontSize: fontSize,
                  center: i > 0,
                ),
            ],
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
        softWrap: true,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Formatting
  // ---------------------------------------------------------------------------

  static String _formatDateTime(DateTime value) {
    final DateTime local = value.toLocal();
    final String y = local.year.toString().padLeft(4, '0');
    final String m = local.month.toString().padLeft(2, '0');
    final String d = local.day.toString().padLeft(2, '0');
    final String hh = local.hour.toString().padLeft(2, '0');
    final String mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

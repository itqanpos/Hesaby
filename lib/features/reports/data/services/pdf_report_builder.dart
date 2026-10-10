// lib/features/reports/data/services/pdf_report_builder.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../settings/domain/entities/company_settings.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../domain/entities/report_document.dart';

/// Builds an A4 PDF from a [ReportDocument].
///
/// **Phase P-1b:** accepts a [PrintStyleSettings] that scales every font
/// size and selects a base weight for the body text.
abstract final class PdfReportBuilder {
  static Future<Uint8List> build({
    required ReportDocument document,
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
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
        header: (pw.Context context) =>
            _buildPageHeader(document, style),
        footer: (pw.Context context) =>
            _buildPageFooter(context, style),
        build: (pw.Context context) => _buildContent(document, style),
      ),
    );

    return pdf.save();
  }

  // ---------------------------------------------------------------------------
  // Weight resolution
  // ---------------------------------------------------------------------------

  /// Maps the user's base weight + an emphasis flag to a `pdf` weight.
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
  // Digit normalization
  // ---------------------------------------------------------------------------

  static String _norm(String input) {
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final int c = input.codeUnitAt(i);
      switch (c) {
        case 0x0660:
          out.write('0');
          break;
        case 0x0661:
          out.write('1');
          break;
        case 0x0662:
          out.write('2');
          break;
        case 0x0663:
          out.write('3');
          break;
        case 0x0664:
          out.write('4');
          break;
        case 0x0665:
          out.write('5');
          break;
        case 0x0666:
          out.write('6');
          break;
        case 0x0667:
          out.write('7');
          break;
        case 0x0668:
          out.write('8');
          break;
        case 0x0669:
          out.write('9');
          break;
        case 0x066B:
          out.write('.');
          break;
        case 0x066C:
          out.write(',');
          break;
        case 0x200E:
        case 0x200F:
        case 0x202A:
        case 0x202B:
        case 0x202C:
        case 0x202D:
        case 0x202E:
          break;
        default:
          out.writeCharCode(c);
      }
    }
    return out.toString();
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
  // Page header / footer
  // ---------------------------------------------------------------------------

  static pw.Widget _buildPageHeader(
    ReportDocument document,
    PrintStyleSettings style,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        pw.Text(
          _norm(document.companyName),
          style: pw.TextStyle(
            fontSize: style.scale(13),
            fontWeight: _weight(
              userWeight: style.fontWeight,
              emphasized: true,
            ),
          ),
          textAlign: pw.TextAlign.center,
        ),
        if (document.branchName != null &&
            document.branchName!.isNotEmpty) ...<pw.Widget>[
          pw.SizedBox(height: 1),
          pw.Text(
            _norm(document.branchName!),
            style: pw.TextStyle(
              fontSize: style.scale(9),
              color: PdfColors.grey700,
              fontWeight: _weight(
                userWeight: style.fontWeight,
                emphasized: false,
              ),
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
  // Content
  // ---------------------------------------------------------------------------

  static List<pw.Widget> _buildContent(
    ReportDocument document,
    PrintStyleSettings style,
  ) {
    return <pw.Widget>[
      _buildTitleBlock(document, style),
      pw.SizedBox(height: 12),
      for (int i = 0; i < document.sections.length; i++) ...<pw.Widget>[
        _buildSection(document.sections[i], style),
        if (i < document.sections.length - 1) pw.SizedBox(height: 14),
      ],
    ];
  }

  static pw.Widget _buildTitleBlock(
    ReportDocument document,
    PrintStyleSettings style,
  ) {
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
            _norm(document.title),
            style: pw.TextStyle(
              fontSize: style.scale(16),
              fontWeight: _weight(
                userWeight: style.fontWeight,
                emphasized: true,
              ),
            ),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(
                document.periodLabel != null
                    ? _norm('الفترة: ${document.periodLabel}')
                    : 'الفترة: الكل',
                style: pw.TextStyle(
                  fontSize: style.scale(9),
                  fontWeight: _weight(
                    userWeight: style.fontWeight,
                    emphasized: false,
                  ),
                ),
              ),
              pw.Text(
                _norm(
                  'تاريخ الإصدار: ${_formatDateTime(document.generatedAt)}',
                ),
                style: pw.TextStyle(
                  fontSize: style.scale(9),
                  fontWeight: _weight(
                    userWeight: style.fontWeight,
                    emphasized: false,
                  ),
                ),
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

  static pw.Widget _buildSection(
    ReportSection section,
    PrintStyleSettings style,
  ) {
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
            _norm(section.title!),
            style: pw.TextStyle(
              fontSize: style.scale(12),
              fontWeight: _weight(
                userWeight: style.fontWeight,
                emphasized: true,
              ),
            ),
          ),
        ),
      );
      children.add(pw.SizedBox(height: 8));
    }

    if (section.kpis != null && section.kpis!.isNotEmpty) {
      children.add(_buildKpiGrid(section.kpis!, style));
      children.add(pw.SizedBox(height: 8));
    }

    if (section.lines != null && section.lines!.isNotEmpty) {
      for (final ReportLine line in section.lines!) {
        children.add(_buildLine(line, style));
      }
      children.add(pw.SizedBox(height: 4));
    }

    if (section.table != null && section.table!.rows.isNotEmpty) {
      children.add(_buildTable(section.table!, style));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: children,
    );
  }

  // ---------------------------------------------------------------------------
  // KPI grid
  // ---------------------------------------------------------------------------

  static pw.Widget _buildKpiGrid(
    List<ReportKpi> kpis,
    PrintStyleSettings style,
  ) {
    const int columns = 2;
    final List<pw.Widget> rows = <pw.Widget>[];

    for (int i = 0; i < kpis.length; i += columns) {
      final List<pw.Widget> cells = <pw.Widget>[];
      for (int j = 0; j < columns; j++) {
        final int index = i + j;
        if (index < kpis.length) {
          cells.add(pw.Expanded(child: _buildKpiCard(kpis[index], style)));
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

  static pw.Widget _buildKpiCard(
    ReportKpi kpi,
    PrintStyleSettings style,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(
          color: kpi.emphasized
              ? PdfColors.blueGrey600
              : PdfColors.grey400,
          width: kpi.emphasized ? 0.8 : 0.4,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            _norm(kpi.label),
            style: pw.TextStyle(
              fontSize: style.scale(9),
              color: PdfColors.grey700,
              fontWeight: _weight(
                userWeight: style.fontWeight,
                emphasized: false,
              ),
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            _norm(kpi.value),
            style: pw.TextStyle(
              fontSize: style.scale(kpi.emphasized ? 12 : 11),
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
  // Line
  // ---------------------------------------------------------------------------

  static pw.Widget _buildLine(
    ReportLine line,
    PrintStyleSettings style,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Text(
              _norm(line.label),
              style: pw.TextStyle(
                fontSize: style.scale(10),
                fontWeight: _weight(
                  userWeight: style.fontWeight,
                  emphasized: false,
                ),
              ),
              softWrap: true,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Text(
            _norm(line.value),
            style: pw.TextStyle(
              fontSize: style.scale(line.emphasized ? 11 : 10),
              fontWeight: _weight(
                userWeight: style.fontWeight,
                emphasized: line.emphasized,
              ),
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

  static pw.Widget _buildTable(
    ReportTable table,
    PrintStyleSettings style,
  ) {
    final double fontSize = style.scale(9);

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
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: <pw.Widget>[
            for (final String h in table.headers)
              _cell(h,
                  fontSize: fontSize,
                  style: style,
                  emphasized: true,
                  center: true),
          ],
        ),
        for (final List<String> row in table.rows)
          pw.TableRow(
            children: <pw.Widget>[
              for (int i = 0; i < table.columnCount; i++)
                _cell(
                  i < row.length ? row[i] : '',
                  fontSize: fontSize,
                  style: style,
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
    required PrintStyleSettings style,
    bool emphasized = false,
    bool center = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        _norm(text),
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: _weight(
            userWeight: style.fontWeight,
            emphasized: emphasized,
          ),
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

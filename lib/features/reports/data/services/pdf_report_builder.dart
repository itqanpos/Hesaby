// lib/features/reports/data/services/pdf_report_builder.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/printing/pdf_shared_components.dart';
import '../../../pos/data/services/pdf_receipt_builder.dart'
    show ReceiptPaperSize;
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../domain/entities/report_document.dart';

/// Builds a PDF document from a [ReportDocument].
///
/// **Unified Template:** uses `PdfSharedHeader`, `PdfSharedFooter`, and
/// `PdfSharedFormat` for visual consistency across the app.
///
/// **Supports:**
/// * `ReceiptPaperSize.a4` — Full detailed report (multi-page).
/// * `ReceiptPaperSize.mm80` / `mm58` — Thermal summary (KPIs + Lines).
abstract final class PdfReportBuilder {
  static Future<Uint8List> build({
    required ReportDocument document,
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
    Uint8List? logoBytes,
    ReceiptPaperSize size = ReceiptPaperSize.a4,
  }) async {
    final pw.ThemeData theme = await PdfSharedFonts.loadTheme();

    final pw.Document pdf = pw.Document(
      theme: theme,
      title: document.title,
      author: document.companyName,
      creator: 'Hesabi',
    );

    if (size != ReceiptPaperSize.a4) {
      // 🔴 طباعة حرارية: ملخص
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
            80 * PdfPageFormat.mm,
            250 * PdfPageFormat.mm,
            marginAll: 0,
          ),
          margin: const pw.EdgeInsets.all(6),
          textDirection: pw.TextDirection.rtl,
          build: (pw.Context ctx) => _buildThermalContent(
            document: document,
            style: style,
            logoBytes: logoBytes,
            context: ctx,
          ),
        ),
      );
    } else {
      // 🟢 A4: تفصيل كامل
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          textDirection: pw.TextDirection.rtl,
          header: (pw.Context context) => PdfSharedHeader.build(
            title: 'تقرير',
            subtitle: document.title,
            companyName: document.companyName,
            branchName: document.branchName,
            style: style,
            logoBytes: logoBytes,
            logoWidth: 70,
            titleFontSize: 16,
          ),
          footer: (pw.Context context) =>
              PdfSharedFooter.build(context, style),
          build: (pw.Context context) => _buildA4Content(document, style),
        ),
      );
    }

    return pdf.save();
  }

  // ---------------------------------------------------------------------------
  // A4 Content
  // ---------------------------------------------------------------------------

  static List<pw.Widget> _buildA4Content(
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
            PdfSharedFormat.norm(document.title),
            style: pw.TextStyle(
              fontSize: PdfSharedStyle.size(style, 16),
              fontWeight:
                  PdfSharedStyle.weight(style, emphasized: true),
            ),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(
                document.periodLabel != null
                    ? PdfSharedFormat.norm('الفترة: ${document.periodLabel}')
                    : 'الفترة: الكل',
                style: pw.TextStyle(
                  fontSize: PdfSharedStyle.size(style, 9),
                  fontWeight: PdfSharedStyle.weight(style,
                      emphasized: false),
                ),
              ),
              pw.Text(
                PdfSharedFormat.norm(
                  'تاريخ الإصدار: ${PdfSharedFormat.date(document.generatedAt)}',
                ),
                style: pw.TextStyle(
                  fontSize: PdfSharedStyle.size(style, 9),
                  fontWeight: PdfSharedStyle.weight(style,
                      emphasized: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

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
            PdfSharedFormat.norm(section.title!),
            style: pw.TextStyle(
              fontSize: PdfSharedStyle.size(style, 12),
              fontWeight:
                  PdfSharedStyle.weight(style, emphasized: true),
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
            PdfSharedFormat.norm(kpi.label),
            style: pw.TextStyle(
              fontSize: PdfSharedStyle.size(style, 9),
              color: PdfColors.grey700,
              fontWeight:
                  PdfSharedStyle.weight(style, emphasized: false),
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            PdfSharedFormat.norm(kpi.value),
            style: pw.TextStyle(
              fontSize:
                  PdfSharedStyle.size(style, kpi.emphasized ? 12 : 11),
              fontWeight:
                  PdfSharedStyle.weight(style, emphasized: true),
            ),
          ),
        ],
      ),
    );
  }

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
              PdfSharedFormat.norm(line.label),
              style: pw.TextStyle(
                fontSize: PdfSharedStyle.size(style, 10),
                fontWeight:
                    PdfSharedStyle.weight(style, emphasized: false),
              ),
              softWrap: true,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Text(
            PdfSharedFormat.norm(line.value),
            style: pw.TextStyle(
              fontSize:
                  PdfSharedStyle.size(style, line.emphasized ? 11 : 10),
              fontWeight: PdfSharedStyle.weight(style,
                  emphasized: line.emphasized),
            ),
            textAlign: pw.TextAlign.right,
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTable(
    ReportTable table,
    PrintStyleSettings style,
  ) {
    final double fontSize = PdfSharedStyle.size(style, 9);

    final Map<int, pw.TableColumnWidth> columnWidths =
        <int, pw.TableColumnWidth>{};
    for (int i = 0; i < table.columnCount; i++) {
      final double flex = (table.flex != null && i < table.flex!.length)
          ? table.flex![i]
          : 1;
      columnWidths[i] = pw.FlexColumnWidth(flex);
    }

    return pw.Table(
      border: PdfSharedTable.border,
      columnWidths: columnWidths,
      children: <pw.TableRow>[
        pw.TableRow(
          decoration: PdfSharedTable.headerDecoration,
          children: <pw.Widget>[
            for (final String h in table.headers)
              _cell(h,
                  fontSize: fontSize,
                  style: style,
                  emphasized: true,
                  center: true),
          ],
        ),
        for (int r = 0; r < table.rows.length; r++)
          pw.TableRow(
            decoration: PdfSharedTable.zebraDecoration(r.isOdd),
            children: <pw.Widget>[
              for (int i = 0; i < table.columnCount; i++)
                _cell(
                  i < table.rows[r].length ? table.rows[r][i] : '',
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
        PdfSharedFormat.norm(text),
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight:
              PdfSharedStyle.weight(style, emphasized: emphasized),
        ),
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.right,
        softWrap: true,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Thermal Content (Summary)
  // ---------------------------------------------------------------------------

  static pw.Widget _buildThermalContent({
    required ReportDocument document,
    required PrintStyleSettings style,
    Uint8List? logoBytes,
    required pw.Context context,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        PdfSharedHeader.build(
          title: 'تقرير',
          subtitle: document.title,
          companyName: document.companyName,
          branchName: document.branchName,
          style: style,
          logoBytes: logoBytes,
          logoWidth: 80,
          titleFontSize: 12,
        ),
        pw.Divider(thickness: 0.5),
        _thermRow('الفترة', document.periodLabel ?? 'الكل', style),
        _thermRow(
            'التاريخ', PdfSharedFormat.date(document.generatedAt), style),
        pw.Divider(thickness: 0.5),
        for (final ReportSection section in document.sections) ...<pw.Widget>[
          if (section.title != null) ...<pw.Widget>[
            pw.SizedBox(height: 4),
            pw.Text(
              PdfSharedFormat.norm(section.title!),
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight:
                    PdfSharedStyle.weight(style, emphasized: true),
              ),
            ),
            pw.SizedBox(height: 2),
          ],
          if (section.kpis != null)
            for (final ReportKpi kpi in section.kpis!)
              _thermRow(kpi.label, kpi.value, style),
          if (section.lines != null)
            for (final ReportLine line in section.lines!)
              _thermRow(line.label, line.value, style),
          if (section.table != null && section.table!.rows.isNotEmpty) ...<pw.Widget>[
            pw.SizedBox(height: 4),
            pw.Text(
              'الجدول التفصيلي متاح في نسخة A4 فقط.',
              style: pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey600,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ],
          pw.Divider(thickness: 0.3, color: PdfColors.grey400),
        ],
        pw.SizedBox(height: 8),
        PdfSharedFooter.build(context, style, showPageNumber: false),
      ],
    );
  }

  static pw.Widget _thermRow(
      String label, String value, PrintStyleSettings style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Text(
              PdfSharedFormat.norm(label),
              style:
                  pw.TextStyle(fontSize: PdfSharedStyle.size(style, 9)),
            ),
          ),
          pw.Text(
            PdfSharedFormat.norm(value),
            style: pw.TextStyle(
              fontSize: PdfSharedStyle.size(style, 9),
              fontWeight:
                  PdfSharedStyle.weight(style, emphasized: true),
            ),
          ),
        ],
      ),
    );
  }
}

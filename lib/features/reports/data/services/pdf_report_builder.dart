// lib/features/reports/data/services/pdf_report_builder.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/printing/pdf_shared_components.dart';
import '../../../pos/data/services/pdf_receipt_builder.dart' show ReceiptPaperSize;
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../domain/entities/report_document.dart';

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
      // 🔴 طباعة حرارية: ملخص (KPIs + Lines فقط)
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, 250 * PdfPageFormat.mm, marginAll: 0),
          margin: const pw.EdgeInsets.all(6),
          textDirection: pw.TextDirection.rtl,
          build: (ctx) => _buildThermalContent(document, style, logoBytes, ctx),
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
          footer: (pw.Context context) => PdfSharedFooter.build(context, style),
          build: (pw.Context context) => _buildA4Content(document, style),
        ),
      );
    }

    return pdf.save();
  }

  static List<pw.Widget> _buildA4Content(ReportDocument document, PrintStyleSettings style) {
    // ... (نفس كود A4 الأصلي، لكن باستخدام PdfSharedFormat و PdfSharedTable)
  }

  static pw.Widget _buildThermalContent(
    ReportDocument document,
    PrintStyleSettings style,
    Uint8List? logoBytes,
    pw.Context context,
  ) {
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
        _thermRow('التاريخ', PdfSharedFormat.dayDate(document.generatedAt), style),
        pw.Divider(thickness: 0.5),
        for (final ReportSection section in document.sections) ...[
          if (section.title != null) ...[
            pw.SizedBox(height: 4),
            pw.Text(PdfSharedFormat.norm(section.title!), style: pw.TextStyle(fontSize: 11, fontWeight: PdfSharedStyle.weight(style, emphasized: true))),
            pw.SizedBox(height: 2),
          ],
          if (section.kpis != null)
            for (final kpi in section.kpis!)
              _thermRow(kpi.label, kpi.value, style),
          if (section.lines != null)
            for (final line in section.lines!)
              _thermRow(line.label, line.value, style),
          if (section.table != null && section.table!.rows.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text('الجدول التفصيلي متاح في نسخة A4 فقط.', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600, fontStyle: pw.FontStyle.italic)),
          ],
          pw.Divider(thickness: 0.3, color: PdfColors.grey400),
        ],
        pw.SizedBox(height: 8),
        PdfSharedFooter.build(context, style, showPageNumber: false),
      ],
    );
  }

  static pw.Widget _thermRow(String label, String value, PrintStyleSettings style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Expanded(child: pw.Text(PdfSharedFormat.norm(label), style: pw.TextStyle(fontSize: PdfSharedStyle.size(style, 9)))),
          pw.Text(PdfSharedFormat.norm(value), style: pw.TextStyle(fontSize: PdfSharedStyle.size(style, 9), fontWeight: PdfSharedStyle.weight(style, emphasized: true))),
        ],
      ),
    );
  }
}

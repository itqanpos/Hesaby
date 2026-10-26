// lib/features/sales/data/services/pdf_statement_builder.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/printing/pdf_shared_components.dart';
import '../../../pos/data/services/pdf_receipt_builder.dart' show ReceiptPaperSize;
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../domain/entities/customer_statement.dart';

abstract final class PdfStatementBuilder {
  static Future<Uint8List> build({
    required CustomerStatement statement,
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
    Uint8List? logoBytes,
    ReceiptPaperSize size = ReceiptPaperSize.a4,
    String? companyName,
    String? branchName,
    String? companyAddress,
    String? companyPhone,
    String? taxNumber,
    String? commercialRegister,
  }) async {
    final pw.ThemeData theme = await PdfSharedFonts.loadTheme();

    final pw.Document document = pw.Document(
      theme: theme,
      title: 'كشف حساب - ${statement.customer.name}',
      author: 'Hesabi',
      creator: 'Hesabi',
    );

    if (size != ReceiptPaperSize.a4) {
      // 🔴 طباعة حرارية: ملخص فقط
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, 150 * PdfPageFormat.mm, marginAll: 0),
          margin: const pw.EdgeInsets.all(6),
          textDirection: pw.TextDirection.rtl,
          build: (ctx) => _buildThermalContent(
            statement: statement,
            style: style,
            logoBytes: logoBytes,
            companyName: companyName,
            branchName: branchName,
            companyAddress: companyAddress,
            companyPhone: companyPhone,
            taxNumber: taxNumber,
            commercialRegister: commercialRegister,
            context: ctx,
          ),
        ),
      );
    } else {
      // 🟢 A4: تفصيل كامل
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          textDirection: pw.TextDirection.rtl,
          header: (pw.Context context) => PdfSharedHeader.build(
            title: 'كشف حساب عميل',
            subtitle: statement.customer.name,
            companyName: companyName,
            branchName: branchName,
            address: companyAddress,
            phone: companyPhone,
            taxNumber: taxNumber,
            commercialRegister: commercialRegister,
            style: style,
            logoBytes: logoBytes,
            logoWidth: 130,
            titleFontSize: 16,
          ),
          footer: (pw.Context context) => PdfSharedFooter.build(context, style),
          build: (pw.Context context) => _buildA4Content(statement, style),
        ),
      );
    }

    return document.save();
  }

  static List<pw.Widget> _buildA4Content(CustomerStatement statement, PrintStyleSettings style) {
    return <pw.Widget>[
      // ... (نفس كود A4 الأصلي، لكن باستخدام PdfSharedFormat و PdfSharedTable)
    ];
  }

  static pw.Widget _buildThermalContent({
    required CustomerStatement statement,
    required PrintStyleSettings style,
    Uint8List? logoBytes,
    String? companyName,
    String? branchName,
    String? companyAddress,
    String? companyPhone,
    String? taxNumber,
    String? commercialRegister,
    required pw.Context context,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        PdfSharedHeader.build(
          title: 'كشف حساب عميل',
          subtitle: statement.customer.name,
          companyName: companyName,
          branchName: branchName,
          address: companyAddress,
          phone: companyPhone,
          taxNumber: taxNumber,
          commercialRegister: commercialRegister,
          style: style,
          logoBytes: logoBytes,
          logoWidth: 80,
          titleFontSize: 12,
        ),
        pw.Divider(thickness: 0.5),
        _thermRow('الفترة', PdfSharedFormat.period(statement.fromDate, statement.toDate), style),
        _thermRow('التاريخ', PdfSharedFormat.date(statement.generatedAt), style),
        pw.Divider(thickness: 0.5),
        _thermRow('رصيد افتتاحي', PdfSharedFormat.money(statement.openingBalance), style),
        _thermRow('إجمالي مدين', PdfSharedFormat.money(statement.totalDebit), style),
        _thermRow('إجمالي دائن', PdfSharedFormat.money(statement.totalCredit), style),
        _thermRow('عدد الحركات', statement.entryCount.toString(), style),
        pw.Divider(thickness: 0.5),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.black, width: 1),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text('الرصيد الختامي', style: pw.TextStyle(fontSize: 12, fontWeight: PdfSharedStyle.weight(style, emphasized: true))),
              pw.Text(PdfSharedFormat.money(statement.closingBalance), style: pw.TextStyle(fontSize: 12, fontWeight: PdfSharedStyle.weight(style, emphasized: true))),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        PdfSharedFooter.build(context, style, showPageNumber: false),
      ],
    );
  }

  static pw.Widget _thermRow(String label, String value, PrintStyleSettings style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text(label, style: pw.TextStyle(fontSize: PdfSharedStyle.size(style, 9))),
          pw.Text(value, style: pw.TextStyle(fontSize: PdfSharedStyle.size(style, 9), fontWeight: PdfSharedStyle.weight(style, emphasized: true))),
        ],
      ),
    );
  }
}

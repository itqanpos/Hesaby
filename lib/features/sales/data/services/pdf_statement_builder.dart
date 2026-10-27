// lib/features/sales/data/services/pdf_statement_builder.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/printing/pdf_shared_components.dart';
import '../../../pos/data/services/pdf_receipt_builder.dart'
    show ReceiptPaperSize;
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../domain/entities/customer_statement.dart';

/// Builds a PDF document from a [CustomerStatement].
///
/// **Unified Template:** uses `PdfSharedHeader`, `PdfSharedFooter`, and
/// `PdfSharedFormat` for visual consistency across the app.
///
/// **Supports:**
/// * `ReceiptPaperSize.a4` — Full detailed table (multi-page).
/// * `ReceiptPaperSize.mm80` / `mm58` — Thermal summary (KPIs only).
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
          pageFormat: PdfPageFormat(
            80 * PdfPageFormat.mm,
            160 * PdfPageFormat.mm,
            marginAll: 0,
          ),
          margin: const pw.EdgeInsets.all(6),
          textDirection: pw.TextDirection.rtl,
          build: (pw.Context ctx) => _buildThermalContent(
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
          footer: (pw.Context context) =>
              PdfSharedFooter.build(context, style),
          build: (pw.Context context) => _buildA4Content(statement, style),
        ),
      );
    }

    return document.save();
  }

  // ---------------------------------------------------------------------------
  // A4 Content
  // ---------------------------------------------------------------------------

  static List<pw.Widget> _buildA4Content(
    CustomerStatement statement,
    PrintStyleSettings style,
  ) {
    return <pw.Widget>[
      _buildInfoBlockA4(statement, style),
      pw.SizedBox(height: 12),
      _buildTableA4(statement, style),
      pw.SizedBox(height: 12),
      _buildSummaryBlockA4(statement, style),
    ];
  }

  static pw.Widget _buildInfoBlockA4(
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
          _infoRowA4('العميل', statement.customer.name, style),
          if (statement.customer.hasPhone)
            _infoRowA4('الهاتف', statement.customer.phone!, style),
          if (statement.customer.hasCode)
            _infoRowA4('الكود', statement.customer.code!, style),
          _infoRowA4(
            'الفترة',
            PdfSharedFormat.period(statement.fromDate, statement.toDate),
            style,
          ),
          _infoRowA4(
            'تاريخ الإصدار',
            PdfSharedFormat.date(statement.generatedAt),
            style,
          ),
        ],
      ),
    );
  }

  static pw.Widget _infoRowA4(
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
            PdfSharedFormat.norm(label),
            style: pw.TextStyle(
              fontSize: PdfSharedStyle.size(style, 9),
              fontWeight:
                  PdfSharedStyle.weight(style, emphasized: false),
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

  static pw.Widget _buildTableA4(
    CustomerStatement statement,
    PrintStyleSettings style,
  ) {
    final double fontSize = PdfSharedStyle.size(style, 9);

    return pw.Table(
      border: PdfSharedTable.border,
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(1.6),
        1: pw.FlexColumnWidth(3.4),
        2: pw.FlexColumnWidth(1.4),
        3: pw.FlexColumnWidth(1.4),
        4: pw.FlexColumnWidth(1.6),
      },
      children: <pw.TableRow>[
        _headerRowA4(fontSize: fontSize, style: style),
        _openingBalanceRowA4(statement, fontSize, style),
        for (final CustomerStatementEntry entry in statement.entries)
          _entryRowA4(entry, fontSize, style),
      ],
    );
  }

  static pw.TableRow _headerRowA4({
    required double fontSize,
    required PrintStyleSettings style,
  }) {
    return pw.TableRow(
      decoration: PdfSharedTable.headerDecoration,
      children: <pw.Widget>[
        _cellA4('التاريخ',
            fontSize: fontSize,
            style: style,
            emphasized: true,
            center: true),
        _cellA4('البيان',
            fontSize: fontSize,
            style: style,
            emphasized: true,
            center: true),
        _cellA4('مدين',
            fontSize: fontSize,
            style: style,
            emphasized: true,
            center: true),
        _cellA4('دائن',
            fontSize: fontSize,
            style: style,
            emphasized: true,
            center: true),
        _cellA4('الرصيد',
            fontSize: fontSize,
            style: style,
            emphasized: true,
            center: true),
      ],
    );
  }

  static pw.TableRow _openingBalanceRowA4(
    CustomerStatement statement,
    double fontSize,
    PrintStyleSettings style,
  ) {
    return pw.TableRow(
      decoration: PdfSharedTable.totalsDecoration,
      children: <pw.Widget>[
        _cellA4('—', fontSize: fontSize, style: style, center: true),
        _cellA4('رصيد افتتاحي',
            fontSize: fontSize, style: style, emphasized: true),
        _cellA4('', fontSize: fontSize, style: style),
        _cellA4('', fontSize: fontSize, style: style),
        _cellA4(
          PdfSharedFormat.money(statement.openingBalance),
          fontSize: fontSize,
          style: style,
          emphasized: true,
          center: true,
        ),
      ],
    );
  }

  static pw.TableRow _entryRowA4(
    CustomerStatementEntry entry,
    double fontSize,
    PrintStyleSettings style,
  ) {
    final String description = entry.hasDescription
        ? entry.description!
        : _typeLabel(entry.type);

    return pw.TableRow(
      children: <pw.Widget>[
        _cellA4(
          PdfSharedFormat.date(entry.date),
          fontSize: fontSize,
          style: style,
          center: true,
        ),
        _cellA4(description, fontSize: fontSize, style: style),
        _cellA4(
          entry.isDebit ? PdfSharedFormat.money(entry.debit) : '—',
          fontSize: fontSize,
          style: style,
          center: true,
        ),
        _cellA4(
          entry.isCredit ? PdfSharedFormat.money(entry.credit) : '—',
          fontSize: fontSize,
          style: style,
          center: true,
        ),
        _cellA4(
          PdfSharedFormat.money(entry.balanceAfter ?? 0),
          fontSize: fontSize,
          style: style,
          emphasized: true,
          center: true,
        ),
      ],
    );
  }

  static pw.Widget _cellA4(
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
      ),
    );
  }

  static pw.Widget _buildSummaryBlockA4(
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
          _summaryRowA4('عدد الحركات', statement.entryCount.toString(), style),
          _summaryRowA4('إجمالي المدين',
              PdfSharedFormat.money(statement.totalDebit), style),
          _summaryRowA4('إجمالي الدائن',
              PdfSharedFormat.money(statement.totalCredit), style),
          pw.Divider(height: 8, thickness: 0.4),
          _summaryRowA4(
            'الرصيد النهائي',
            PdfSharedFormat.money(statement.closingBalance),
            style,
            emphasized: true,
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryRowA4(
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
            PdfSharedFormat.norm(label),
            style: pw.TextStyle(
              fontSize: PdfSharedStyle.size(style, emphasized ? 11 : 9),
              fontWeight:
                  PdfSharedStyle.weight(style, emphasized: emphasized),
            ),
          ),
          pw.Text(
            PdfSharedFormat.norm(value),
            style: pw.TextStyle(
              fontSize: PdfSharedStyle.size(style, emphasized ? 11 : 9),
              fontWeight:
                  PdfSharedStyle.weight(style, emphasized: emphasized),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Thermal Content (Summary)
  // ---------------------------------------------------------------------------

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
        _thermRow('الفترة',
            PdfSharedFormat.period(statement.fromDate, statement.toDate),
            style),
        _thermRow('التاريخ', PdfSharedFormat.date(statement.generatedAt),
            style),
        pw.Divider(thickness: 0.5),
        _thermRow('رصيد افتتاحي',
            PdfSharedFormat.money(statement.openingBalance), style),
        _thermRow('إجمالي مدين',
            PdfSharedFormat.money(statement.totalDebit), style),
        _thermRow('إجمالي دائن',
            PdfSharedFormat.money(statement.totalCredit), style),
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
              pw.Text('الرصيد الختامي',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight:
                        PdfSharedStyle.weight(style, emphasized: true),
                  )),
              pw.Text(PdfSharedFormat.money(statement.closingBalance),
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight:
                        PdfSharedStyle.weight(style, emphasized: true),
                  )),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        PdfSharedFooter.build(context, style, showPageNumber: false),
      ],
    );
  }

  static pw.Widget _thermRow(
      String label, String value, PrintStyleSettings style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text(PdfSharedFormat.norm(label),
              style:
                  pw.TextStyle(fontSize: PdfSharedStyle.size(style, 9))),
          pw.Text(PdfSharedFormat.norm(value),
              style: pw.TextStyle(
                fontSize: PdfSharedStyle.size(style, 9),
                fontWeight:
                    PdfSharedStyle.weight(style, emphasized: true),
              )),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

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

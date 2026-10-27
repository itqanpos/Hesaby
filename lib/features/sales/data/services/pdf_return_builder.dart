// lib/features/sales/data/services/pdf_return_builder.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/printing/pdf_shared_components.dart';
import '../../../pos/data/services/pdf_receipt_builder.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../domain/entities/return_receipt.dart';

/// Builds a PDF document from a [ReturnReceipt].
///
/// **Phase P-1b:** accepts an optional [PrintStyleSettings].
/// **Phase U-5:** accepts optional [logoBytes] drawn centered at the top.
/// **Unified Template:** now uses `PdfSharedHeader`, `PdfSharedFooter`, and
/// `PdfSharedFormat` for visual consistency across the app.
abstract final class PdfReturnBuilder {
  static const double _thermalFixedMm = 120;
  static const double _thermalPerLineMm = 12;

  static double _thermalHeightFor(int lineCount) {
    final double estimatedMm =
        _thermalFixedMm + lineCount * _thermalPerLineMm;
    final double clampedMm = estimatedMm.clamp(140.0, 400.0);
    return clampedMm * PdfPageFormat.mm;
  }

  /// Logo width in PDF points, chosen from the paper size.
  static double _logoWidthFor(ReceiptPaperSize size) {
    switch (size) {
      case ReceiptPaperSize.mm58:
        return 70;
      case ReceiptPaperSize.mm80:
        return 100;
      case ReceiptPaperSize.a4:
        return 130;
    }
  }

  static Future<Uint8List> build({
    required ReturnReceipt receipt,
    required ReceiptPaperSize size,
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
    Uint8List? logoBytes,
  }) async {
    final pw.ThemeData theme = await PdfSharedFonts.loadTheme();

    final PdfPageFormat pageFormat;
    final double padding;
    switch (size) {
      case ReceiptPaperSize.mm58:
        pageFormat = PdfPageFormat(
          58 * PdfPageFormat.mm,
          _thermalHeightFor(receipt.lines.length),
          marginAll: 0,
        );
        padding = 4;
      case ReceiptPaperSize.mm80:
        pageFormat = PdfPageFormat(
          80 * PdfPageFormat.mm,
          _thermalHeightFor(receipt.lines.length),
          marginAll: 0,
        );
        padding = 6;
      case ReceiptPaperSize.a4:
        pageFormat = PdfPageFormat.a4;
        padding = 32;
    }

    final pw.Document document = pw.Document(
      theme: theme,
      title: 'مرتجع ${receipt.returnNumber ?? receipt.returnId}',
      author: receipt.companyName,
      creator: 'Hesabi',
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.all(padding),
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) => _buildContent(
          receipt: receipt,
          paperSize: size,
          style: style,
          logoBytes: logoBytes,
        ),
      ),
    );

    return document.save();
  }

  // ---------------------------------------------------------------------------
  // Content
  // ---------------------------------------------------------------------------

  static List<pw.Widget> _buildContent({
    required ReturnReceipt receipt,
    required ReceiptPaperSize paperSize,
    required PrintStyleSettings style,
    Uint8List? logoBytes,
  }) {
    final bool isThermal = paperSize != ReceiptPaperSize.a4;
    final double scale = style.fontScale.clamp(0.8, 1.6);

    final double baseFont = (isThermal ? 8 : 10) * scale;
    final double smallFont = (isThermal ? 7 : 9) * scale;

    return <pw.Widget>[
      // ---- Header (Unified) ----
      PdfSharedHeader.build(
        title: 'إيصال مرتجع',
        companyName: receipt.companyName,
        branchName: receipt.branchName,
        style: style,
        logoBytes: logoBytes,
        logoWidth: _logoWidthFor(paperSize),
        // ✅ إرسال الحجم الأساسي (غير المُضاعف)
        titleFontSize: isThermal ? 11 : 16,
      ),
      
      pw.SizedBox(height: 6),
      _divider(),
      pw.SizedBox(height: 6),

      // ---- Meta ----
      _keyValue(
        'رقم المرتجع',
        receipt.returnNumber ?? '—',
        baseFont,
        style,
        emphasized: true,
      ),
      _keyValue('التاريخ', PdfSharedFormat.date(receipt.dateTime), baseFont, style),
      if (receipt.hasSaleInvoice)
        _keyValue(
          'الفاتورة الأصلية',
          receipt.saleInvoiceNumber!,
          baseFont,
          style,
        ),
      if (receipt.hasCustomer)
        _keyValue('العميل', receipt.customerName!, baseFont, style),
      if (receipt.hasCashier)
        _keyValue('الكاشير', receipt.cashierName!, baseFont, style),

      pw.SizedBox(height: 6),
      _divider(),
      pw.SizedBox(height: 6),

      // ---- Items ----
      pw.Text(
        'البنود المُرجَعة',
        style: pw.TextStyle(
          fontSize: isThermal ? 11 * scale : 16 * scale, // Scaled here once
          fontWeight:
              PdfSharedStyle.weight(style, emphasized: true),
        ),
      ),
      pw.SizedBox(height: 4),
      for (final ReturnReceiptLine line in receipt.lines)
        _buildLine(line, isThermal, baseFont, smallFont, style),

      pw.SizedBox(height: 6),
      _divider(),
      pw.SizedBox(height: 6),

      // ---- Total ----
      _keyValue(
        'طريقة الاسترداد',
        receipt.refundMethodLabel,
        baseFont,
        style,
      ),
      pw.SizedBox(height: 2),
      _keyValue(
        'إجمالي المرتجع',
        PdfSharedFormat.money(receipt.total),
        isThermal ? 10 * scale : 12 * scale,
        style,
        emphasized: true,
      ),

      if (receipt.hasNotes) ...<pw.Widget>[
        pw.SizedBox(height: 6),
        _divider(),
        pw.SizedBox(height: 4),
        pw.Text(
          'ملاحظات:',
          style: pw.TextStyle(
            fontSize: smallFont,
            fontWeight:
                PdfSharedStyle.weight(style, emphasized: true),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          PdfSharedFormat.norm(receipt.notes!),
          style: pw.TextStyle(
            fontSize: smallFont,
            fontWeight:
                PdfSharedStyle.weight(style, emphasized: false),
          ),
        ),
      ],

      pw.SizedBox(height: 10),

      // ---- Footer ----
      pw.Center(
        child: pw.Text(
          PdfSharedFormat.norm(_footerText(receipt)),
          style: pw.TextStyle(
            fontSize: baseFont,
            color: PdfColors.grey700,
            fontWeight:
                PdfSharedStyle.weight(style, emphasized: false),
          ),
          textAlign: pw.TextAlign.center,
        ),
      ),
    ];
  }

  static String _footerText(ReturnReceipt receipt) {
    final String? custom = receipt.footer;
    if (custom != null && custom.trim().isNotEmpty) {
      return custom.trim();
    }
    return PdfSharedFooter.defaultThankYou;
  }

  // ---------------------------------------------------------------------------
  // Line item
  // ---------------------------------------------------------------------------

  static pw.Widget _buildLine(
    ReturnReceiptLine line,
    bool isThermal,
    double baseFont,
    double smallFont,
    PrintStyleSettings style,
  ) {
    if (isThermal) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: <pw.Widget>[
            pw.Text(
              PdfSharedFormat.norm(line.productName),
              style: pw.TextStyle(
                fontSize: baseFont,
                fontWeight:
                    PdfSharedStyle.weight(style, emphasized: true),
              ),
              softWrap: true,
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Expanded(
                  child: pw.Text(
                    '${PdfSharedFormat.quantity(line.quantity)} ${line.unitName} '
                    '× ${PdfSharedFormat.money(line.unitPrice)}',
                    style: pw.TextStyle(
                      fontSize: smallFont,
                      fontWeight: PdfSharedStyle.weight(style,
                          emphasized: false),
                    ),
                    softWrap: true,
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.Text(
                  PdfSharedFormat.money(line.lineTotal),
                  style: pw.TextStyle(
                    fontSize: baseFont,
                    fontWeight: PdfSharedStyle.weight(style,
                        emphasized: true),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Expanded(
            flex: 4,
            child: pw.Text(
              PdfSharedFormat.norm(line.productName),
              style: pw.TextStyle(
                fontSize: baseFont,
                fontWeight: PdfSharedStyle.weight(style,
                    emphasized: false),
              ),
              softWrap: true,
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              '${PdfSharedFormat.quantity(line.quantity)} ${line.unitName}',
              style: pw.TextStyle(
                fontSize: baseFont,
                fontWeight: PdfSharedStyle.weight(style,
                    emphasized: false),
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              PdfSharedFormat.money(line.unitPrice),
              style: pw.TextStyle(
                fontSize: baseFont,
                fontWeight: PdfSharedStyle.weight(style,
                    emphasized: false),
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              PdfSharedFormat.money(line.lineTotal),
              style: pw.TextStyle(
                fontSize: baseFont,
                fontWeight: PdfSharedStyle.weight(style,
                    emphasized: true),
              ),
              textAlign: pw.TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static pw.Widget _divider() => pw.Container(
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(
              width: 0.5,
              color: PdfColors.grey600,
            ),
          ),
        ),
      );

  static pw.Widget _keyValue(
    String label,
    String value,
    double fontSize,
    PrintStyleSettings style, {
    bool emphasized = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Text(
              PdfSharedFormat.norm(label),
              style: pw.TextStyle(
                fontSize: fontSize,
                fontWeight: PdfSharedStyle.weight(style,
                    emphasized: false),
              ),
              softWrap: true,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Text(
            PdfSharedFormat.norm(value),
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: PdfSharedStyle.weight(style,
                  emphasized: emphasized),
            ),
            textAlign: pw.TextAlign.right,
          ),
        ],
      ),
    );
  }
}

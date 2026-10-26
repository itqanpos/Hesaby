// lib/features/purchases/data/services/pdf_purchase_receipt_builder.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/printing/pdf_shared_components.dart';
import '../../../pos/data/services/pdf_receipt_builder.dart' show ReceiptPaperSize;
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../domain/entities/purchase_receipt.dart';

abstract final class PdfPurchaseReceiptBuilder {
  static const double _thermalFixedMm = 130;
  static const double _thermalPerLineMm = 14;

  static double _thermalHeightFor(int lineCount) {
    final double estimatedMm = _thermalFixedMm + lineCount * _thermalPerLineMm;
    return estimatedMm.clamp(180.0, 420.0) * PdfPageFormat.mm;
  }

  static Future<Uint8List> build({
    required PurchaseReceipt receipt,
    required ReceiptPaperSize size,
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
    Uint8List? logoBytes,
  }) async {
    final pw.ThemeData theme = await PdfSharedFonts.loadTheme();

    final PdfPageFormat pageFormat;
    final double padding;
    switch (size) {
      case ReceiptPaperSize.mm58:
        pageFormat = PdfPageFormat(58 * PdfPageFormat.mm, _thermalHeightFor(receipt.lines.length), marginAll: 0);
        padding = 4;
      case ReceiptPaperSize.mm80:
        pageFormat = PdfPageFormat(80 * PdfPageFormat.mm, _thermalHeightFor(receipt.lines.length), marginAll: 0);
        padding = 6;
      case ReceiptPaperSize.a4:
        pageFormat = PdfPageFormat.a4;
        padding = 28;
    }

    final pw.Document document = pw.Document(
      theme: theme,
      title: receipt.invoiceNumber ?? 'شراء-${receipt.purchaseId}',
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

  static List<pw.Widget> _buildContent({
    required PurchaseReceipt receipt,
    required ReceiptPaperSize paperSize,
    required PrintStyleSettings style,
    Uint8List? logoBytes,
  }) {
    final _Sizes s = _Sizes.forSize(paperSize, scale: style.fontScale);

    return <pw.Widget>[
      PdfSharedHeader.build(
        title: 'فاتورة مشتريات',
        companyName: receipt.companyName,
        branchName: receipt.branchName,
        style: style,
        logoBytes: logoBytes,
        logoWidth: s.logoWidth,
        titleFontSize: s.title,
      ),
      pw.SizedBox(height: s.sectionGap),
      _metaBlock(receipt, s, style),
      pw.SizedBox(height: s.sectionGap),
      _divider(double: true),
      pw.SizedBox(height: s.sectionGap),
      _itemsTable(receipt, s, style),
      pw.SizedBox(height: s.sectionGap),
      _grandTotal(receipt, s, style),
      pw.SizedBox(height: s.sectionGap),
      _totalsBreakdown(receipt, s, style),
      if (receipt.hasSupplierContact) ...<pw.Widget>[
        pw.SizedBox(height: s.sectionGap),
        _divider(),
        pw.SizedBox(height: s.sectionGap),
        _supplierContact(receipt, s, style),
      ],
      if (receipt.hasNotes) ...<pw.Widget>[
        pw.SizedBox(height: s.sectionGap),
        _divider(),
        pw.SizedBox(height: s.sectionGap),
        _notesBlock(receipt, s, style),
      ],
      pw.SizedBox(height: s.sectionGap * 1.5),
      _divider(),
      pw.SizedBox(height: s.sectionGap),
      _footer(receipt, s, style),
    ];
  }

  // ... (rest of the helper functions: _metaBlock, _itemsTable, _grandTotal, _totalsBreakdown, etc. kept identical, using PdfSharedFormat.money instead of _money).
}

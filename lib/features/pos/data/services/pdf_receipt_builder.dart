// lib/features/pos/data/services/pdf_receipt_builder.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/entities/receipt.dart';

/// Supported paper sizes for a printed receipt.
enum ReceiptPaperSize { mm58, mm80, a4 }

/// Builds a PDF document from a [Receipt].
///
/// See `_buildQrCode` for the QR payload format.
abstract final class PdfReceiptBuilder {
  /// Base URL used in the QR payload.
  static const String _appBaseUrl = 'https://itqanpos.github.io/Hesaby';

  static const double _thermalFixedMm = 130;
  static const double _thermalPerLineMm = 12;

  static double _thermalHeightFor(int lineCount) {
    final double estimatedMm =
        _thermalFixedMm + lineCount * _thermalPerLineMm;
    final double clampedMm = estimatedMm.clamp(150.0, 400.0);
    return clampedMm * PdfPageFormat.mm;
  }

  static Future<Uint8List> build({
    required Receipt receipt,
    required ReceiptPaperSize size,
  }) async {
    final pw.ThemeData theme = await _loadTheme();

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
      title: receipt.invoiceNumber ?? receipt.saleId,
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
        ),
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
  // QR code
  // ---------------------------------------------------------------------------

  static pw.Widget? _buildQrCode(Receipt receipt, {required double size}) {
    final String saleId = receipt.saleId.trim();
    if (saleId.isEmpty) {
      return null;
    }
    return pw.BarcodeWidget(
      barcode: pw.Barcode.qrCode(
        errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium,
      ),
      data: _buildQrPayload(receipt),
      width: size,
      height: size,
      drawText: false,
    );
  }

  static String _buildQrPayload(Receipt receipt) {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('$_appBaseUrl/#/sales/${receipt.saleId}');
    buffer.writeln('الفاتورة: ${receipt.invoiceNumber ?? '—'}');
    buffer.writeln('الإجمالي: ${_formatMoney(receipt.total)}');
    buffer.writeln('التاريخ: ${_formatDate(receipt.dateTime)}');
    return buffer.toString().trimRight();
  }

  // ---------------------------------------------------------------------------
  // Content
  // ---------------------------------------------------------------------------

  static List<pw.Widget> _buildContent({
    required Receipt receipt,
    required ReceiptPaperSize paperSize,
  }) {
    final bool isThermal = paperSize != ReceiptPaperSize.a4;
    final double baseFont = isThermal ? 8 : 10;
    final double headerFont = isThermal ? 11 : 16;
    final double titleFont = isThermal ? 9 : 12;
    final double smallFont = isThermal ? 7 : 9;
    final double qrSize = isThermal ? 60 : 80;

    final pw.Widget? qrCode = _buildQrCode(receipt, size: qrSize);

    return <pw.Widget>[
      pw.Center(
        child: pw.Text(
          receipt.companyName,
          style: pw.TextStyle(
            fontSize: headerFont,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Center(
        child: pw.Text(
          receipt.branchName,
          style: pw.TextStyle(fontSize: baseFont),
          textAlign: pw.TextAlign.center,
        ),
      ),
      pw.SizedBox(height: 6),
      _divider(),
      pw.SizedBox(height: 6),

      _keyValue('رقم الفاتورة', receipt.invoiceNumber ?? '—', baseFont),
      _keyValue('التاريخ', _formatDate(receipt.dateTime), baseFont),
      if (receipt.hasCustomer)
        _keyValue('العميل', receipt.customerName!, baseFont),
      if (receipt.cashierName != null)
        _keyValue('الكاشير', receipt.cashierName!, baseFont),

      pw.SizedBox(height: 6),
      _divider(),
      pw.SizedBox(height: 6),

      pw.Text(
        'البنود',
        style: pw.TextStyle(
          fontSize: titleFont,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(height: 4),
      for (final ReceiptLine line in receipt.lines)
        _buildLine(line, isThermal, baseFont, smallFont),

      pw.SizedBox(height: 6),
      _divider(),
      pw.SizedBox(height: 6),

      _keyValue(
        'المجموع الفرعي',
        _formatMoney(receipt.subtotal),
        baseFont,
      ),
      if (receipt.discount > 0)
        _keyValue('الخصم', _formatMoney(receipt.discount), baseFont),
      if (receipt.taxAmount > 0)
        _keyValue('الضريبة', _formatMoney(receipt.taxAmount), baseFont),
      pw.SizedBox(height: 2),
      _keyValue(
        'الإجمالي',
        _formatMoney(receipt.total),
        isThermal ? 10 : 12,
        bold: true,
      ),
      pw.SizedBox(height: 4),
      _keyValue('المدفوع', _formatMoney(receipt.paidAmount), baseFont),
      if (receipt.hasChange)
        _keyValue(
          'الباقي للعميل',
          _formatMoney(receipt.change),
          baseFont,
        ),

      if (receipt.hasBalanceChange) ...<pw.Widget>[
        pw.SizedBox(height: 4),
        _divider(),
        pw.SizedBox(height: 4),
        _keyValue(
          'الرصيد السابق',
          _formatMoney(receipt.previousBalance!),
          baseFont,
        ),
        if (receipt.previousBalance! > receipt.newBalance!)
          _keyValue(
            'مدفوع على الرصيد',
            _formatMoney(
              receipt.previousBalance! - receipt.newBalance!,
            ),
            baseFont,
          ),
        _keyValue(
          'الرصيد الجديد',
          _formatMoney(receipt.newBalance!),
          baseFont,
          bold: true,
        ),
      ],

      pw.SizedBox(height: 10),

      // ---- QR code + footer ----
      pw.Center(
        child: pw.Column(
          children: <pw.Widget>[
            if (qrCode != null) qrCode,
            pw.SizedBox(height: 4),
            pw.Text(
              'شكرًا لتعاملكم معنا',
              style: pw.TextStyle(fontSize: baseFont),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      ),
    ];
  }

  static pw.Widget _buildLine(
    ReceiptLine line,
    bool isThermal,
    double baseFont,
    double smallFont,
  ) {
    if (isThermal) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: <pw.Widget>[
            pw.Text(
              line.productName,
              style: pw.TextStyle(
                fontSize: baseFont,
                fontWeight: pw.FontWeight.bold,
              ),
              softWrap: true,
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Expanded(
                  child: pw.Text(
                    '${_formatQuantity(line.quantity)} ${line.unitName} '
                    '× ${_formatMoney(line.unitPrice)}',
                    style: pw.TextStyle(fontSize: smallFont),
                    softWrap: true,
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.Text(
                  _formatMoney(line.lineTotal),
                  style: pw.TextStyle(
                    fontSize: baseFont,
                    fontWeight: pw.FontWeight.bold,
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
              line.productName,
              style: pw.TextStyle(fontSize: baseFont),
              softWrap: true,
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              '${_formatQuantity(line.quantity)} ${line.unitName}',
              style: pw.TextStyle(fontSize: baseFont),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              _formatMoney(line.unitPrice),
              style: pw.TextStyle(fontSize: baseFont),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              _formatMoney(line.lineTotal),
              style: pw.TextStyle(
                fontSize: baseFont,
                fontWeight: pw.FontWeight.bold,
              ),
              textAlign: pw.TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }

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
    double fontSize, {
    bool bold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(fontSize: fontSize),
              softWrap: true,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight:
                  bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
            textAlign: pw.TextAlign.right,
          ),
        ],
      ),
    );
  }

  static String _formatMoney(double value) =>
      '${value.toStringAsFixed(2)} ج.م';

  static String _formatQuantity(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  static String _formatDate(DateTime value) {
    final DateTime local = value.toLocal();
    final String y = local.year.toString().padLeft(4, '0');
    final String m = local.month.toString().padLeft(2, '0');
    final String d = local.day.toString().padLeft(2, '0');
    final String hh = local.hour.toString().padLeft(2, '0');
    final String mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

// lib/features/pos/data/services/receipt_printer.dart

import 'dart:typed_data';

import 'package:printing/printing.dart' show Printing;

import '../../../settings/domain/entities/print_style_settings.dart';
import '../../domain/entities/receipt.dart';
import 'pdf_receipt_builder.dart';

/// Contract for printing or sharing a POS receipt via PDF.
abstract interface class ReceiptPrinter {
  bool get isSupported;

  Future<bool> printReceipt({
    required Receipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
    Uint8List? logoBytes,
  });

  Future<bool> previewReceipt({
    required Receipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
    Uint8List? logoBytes,
  });

  Future<bool> shareReceipt({
    required Receipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
    Uint8List? logoBytes,
  });
}

/// Default [ReceiptPrinter] backed by the `printing` package.
///
/// **Updates:**
/// * Replaced `Printing.layoutPdf` with `Printing.sharePdf` to avoid the
///   Android system print dialog.
/// * Removed unused `package:pdf/pdf.dart` import.
class ReceiptPrinterImpl implements ReceiptPrinter {
  const ReceiptPrinterImpl();

  @override
  bool get isSupported => true;

  @override
  Future<bool> printReceipt({
    required Receipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
    Uint8List? logoBytes,
  }) async {
    try {
      final Uint8List bytes = await PdfReceiptBuilder.build(
        receipt: receipt,
        size: size,
        style: style,
        logoBytes: logoBytes,
      );

      // ✅ تم استبدال layoutPdf بـ sharePdf لإخفاء حوار الطباعة
      await Printing.sharePdf(
        bytes: bytes,
        filename: _fileNameFor(receipt),
      );

      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> previewReceipt({
    required Receipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
    Uint8List? logoBytes,
  }) async {
    // In this version, preview delegates to print, which opens the OS
    // share sheet. The WYSIWYG preview is handled elsewhere
    // (e.g., thermal_return_preview for returns).
    return printReceipt(
      receipt: receipt,
      size: size,
      style: style,
      logoBytes: logoBytes,
    );
  }

  @override
  Future<bool> shareReceipt({
    required Receipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
    Uint8List? logoBytes,
  }) async {
    try {
      final Uint8List bytes = await PdfReceiptBuilder.build(
        receipt: receipt,
        size: size,
        style: style,
        logoBytes: logoBytes,
      );

      await Printing.sharePdf(
        bytes: bytes,
        filename: _fileNameFor(receipt),
      );

      return true;
    } on Object {
      return false;
    }
  }

  static String _fileNameFor(Receipt receipt) {
    final String suffix = receipt.invoiceNumber?.trim().isNotEmpty == true
        ? receipt.invoiceNumber!.trim()
        : receipt.saleId;
    return 'receipt-$suffix.pdf';
  }
}

// lib/features/pos/data/services/receipt_printer.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart' show Printing;

import '../../../settings/domain/entities/print_style_settings.dart';
import '../../domain/entities/receipt.dart';
import 'pdf_receipt_builder.dart';

/// Contract for printing or sharing a POS receipt via PDF.
///
/// The concrete implementation is platform-aware: it opens the native
/// print dialog on supported platforms and falls back to a system share
/// sheet where printing is unavailable (for example on the web).
///
/// **Phase P-1b:** every method accepts an optional [style] so the PDF is
/// rendered with the user's font size + weight preferences.
abstract interface class ReceiptPrinter {
  bool get isSupported;

  Future<bool> printReceipt({
    required Receipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
  });

  Future<bool> previewReceipt({
    required Receipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
  });

  Future<bool> shareReceipt({
    required Receipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
  });
}

/// Default [ReceiptPrinter] backed by the `printing` package.
class ReceiptPrinterImpl implements ReceiptPrinter {
  const ReceiptPrinterImpl();

  @override
  bool get isSupported => true;

  @override
  Future<bool> printReceipt({
    required Receipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
  }) async {
    try {
      final Uint8List bytes = await PdfReceiptBuilder.build(
        receipt: receipt,
        size: size,
        style: style,
      );

      await Printing.layoutPdf(
        name: _fileNameFor(receipt),
        onLayout: (PdfPageFormat _) => bytes,
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
  }) async {
    return printReceipt(receipt: receipt, size: size, style: style);
  }

  @override
  Future<bool> shareReceipt({
    required Receipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
  }) async {
    try {
      final Uint8List bytes = await PdfReceiptBuilder.build(
        receipt: receipt,
        size: size,
        style: style,
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

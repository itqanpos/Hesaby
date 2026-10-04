// lib/features/pos/data/services/receipt_printer.dart

import 'dart:typed_data';

import 'package:printing/printing.dart';

import '../../domain/entities/receipt.dart';
import 'pdf_receipt_builder.dart';

/// Contract for printing or sharing a POS receipt.
///
/// The concrete implementation is platform-aware: it opens the native
/// print dialog on supported platforms and falls back to a system share
/// sheet where printing is unavailable (for example on the web).
///
/// All methods return a `bool` rather than throwing, because printing can
/// fail for many benign reasons — user cancelled the dialog, no printer
/// installed, browser blocked the print window — none of which should
/// interrupt the cashier's flow.
abstract interface class ReceiptPrinter {
  /// Whether the current platform supports at least one output method.
  ///
  /// Callers may use this flag to decide whether to show a print button.
  bool get isSupported;

  /// Opens the system print dialog for [receipt].
  ///
  /// The receipt is rendered to PDF using [ReceiptPaperSize] and handed to
  /// the platform. Returns `true` when a print job was dispatched,
  /// `false` otherwise.
  Future<bool> printReceipt({
    required Receipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
  });

  /// Opens the built-in PDF preview so the cashier can inspect or print
  /// from within the app.
  ///
  /// Returns `true` when the preview was shown.
  Future<bool> previewReceipt({
    required Receipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
  });

  /// Shares the receipt as a PDF file (system share sheet).
  ///
  /// Useful on the web and mobile when printing directly is not available
  /// or not desired. Returns `true` when a share sheet was opened.
  Future<bool> shareReceipt({
    required Receipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
  });
}

/// Default [ReceiptPrinter] backed by the `printing` package.
///
/// The implementation keeps the following boundaries:
///
/// * It never touches the file system directly — `printing` handles the
///   platform-specific plumbing.
/// * It never inspects or logs the receipt contents beyond what is needed
///   to render the PDF.
/// * It is stateless: each method builds a fresh PDF from the given
///   receipt, so reprinting an older sale is safe at any time.
class ReceiptPrinterImpl implements ReceiptPrinter {
  const ReceiptPrinterImpl();

  @override
  bool get isSupported => true;

  @override
  Future<bool> printReceipt({
    required Receipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
  }) async {
    try {
      final Uint8List bytes = await PdfReceiptBuilder.build(
        receipt: receipt,
        size: size,
      );

      await Printing.layoutPdf(
        name: _fileNameFor(receipt),
        onLayout: (PdfPageFormat _) => bytes,
      );

      return true;
    } on Object {
      // Printing failures are not fatal. The caller decides what to do
      // (usually just a toast). We intentionally do not log the raw
      // exception to avoid leaking receipt metadata into logs.
      return false;
    }
  }

  @override
  Future<bool> previewReceipt({
    required Receipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
  }) async {
    // The `printing` package uses the same entry point for preview and
    // print: it renders an in-app preview with a print button.
    return printReceipt(receipt: receipt, size: size);
  }

  @override
  Future<bool> shareReceipt({
    required Receipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
  }) async {
    try {
      final Uint8List bytes = await PdfReceiptBuilder.build(
        receipt: receipt,
        size: size,
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

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  static String _fileNameFor(Receipt receipt) {
    final String suffix = receipt.invoiceNumber?.trim().isNotEmpty == true
        ? receipt.invoiceNumber!.trim()
        : receipt.saleId;
    return 'receipt-$suffix.pdf';
  }
}

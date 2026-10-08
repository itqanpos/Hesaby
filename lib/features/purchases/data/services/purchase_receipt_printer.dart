// lib/features/purchases/data/services/purchase_receipt_printer.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart' show Printing;

import '../../../pos/data/services/pdf_receipt_builder.dart'
    show ReceiptPaperSize;
import '../../domain/entities/purchase_receipt.dart';
import 'pdf_purchase_receipt_builder.dart';

/// Contract for printing or sharing a purchase receipt.
///
/// Mirrors `ReceiptPrinter` (POS) — the same three operations, the same
/// failure semantics (return `false` on any error rather than throwing).
abstract interface class PurchaseReceiptPrinter {
  /// Whether the current platform supports at least one output method.
  bool get isSupported;

  /// Opens the system print dialog for [receipt].
  Future<bool> printReceipt({
    required PurchaseReceipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
  });

  /// Shares the receipt as a PDF (system share sheet).
  Future<bool> shareReceipt({
    required PurchaseReceipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
  });
}

/// Default [PurchaseReceiptPrinter] backed by the `printing` package.
class PurchaseReceiptPrinterImpl implements PurchaseReceiptPrinter {
  const PurchaseReceiptPrinterImpl();

  @override
  bool get isSupported => true;

  @override
  Future<bool> printReceipt({
    required PurchaseReceipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
  }) async {
    try {
      final Uint8List bytes = await PdfPurchaseReceiptBuilder.build(
        receipt: receipt,
        size: size,
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
  Future<bool> shareReceipt({
    required PurchaseReceipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
  }) async {
    try {
      final Uint8List bytes = await PdfPurchaseReceiptBuilder.build(
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

  static String _fileNameFor(PurchaseReceipt receipt) {
    final String suffix =
        receipt.invoiceNumber?.trim().isNotEmpty == true
            ? receipt.invoiceNumber!.trim()
            : receipt.purchaseId;
    return 'purchase-$suffix.pdf';
  }
}

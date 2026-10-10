// lib/features/purchases/data/services/purchase_receipt_printer.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart' show Printing;

import '../../../pos/data/services/pdf_receipt_builder.dart'
    show ReceiptPaperSize;
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../domain/entities/purchase_receipt.dart';
import 'pdf_purchase_receipt_builder.dart';

/// Contract for printing or sharing a purchase receipt.
///
/// **Phase P-1b:** every method accepts an optional [style] so the PDF is
/// rendered with the user's font size + weight preferences.
abstract interface class PurchaseReceiptPrinter {
  bool get isSupported;

  Future<bool> printReceipt({
    required PurchaseReceipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
  });

  Future<bool> shareReceipt({
    required PurchaseReceipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
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
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
  }) async {
    try {
      final Uint8List bytes = await PdfPurchaseReceiptBuilder.build(
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
  Future<bool> shareReceipt({
    required PurchaseReceipt receipt,
    ReceiptPaperSize size = ReceiptPaperSize.mm80,
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
  }) async {
    try {
      final Uint8List bytes = await PdfPurchaseReceiptBuilder.build(
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

  static String _fileNameFor(PurchaseReceipt receipt) {
    final String suffix =
        receipt.invoiceNumber?.trim().isNotEmpty == true
            ? receipt.invoiceNumber!.trim()
            : receipt.purchaseId;
    return 'purchase-$suffix.pdf';
  }
}

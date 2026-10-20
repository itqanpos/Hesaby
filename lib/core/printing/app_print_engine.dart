// lib/core/printing/app_print_engine.dart

import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

import '../../features/pos/data/services/pdf_receipt_builder.dart';
import '../../features/pos/data/services/esc_pos_receipt_builder.dart';
import '../../features/pos/domain/entities/receipt.dart';
import '../../features/settings/domain/entities/print_style_settings.dart';
import '../../features/pos/presentation/providers/printer_providers.dart';
import '../../features/pos/data/services/printer_service.dart';
import '../../core/utils/logger.dart';

class AppPrintEngine {
  final Ref _ref;
  AppPrintEngine(this._ref);

  /// 1️⃣ طباعة حرارية (إيصال)
  Future<bool> printThermal({
    required Receipt receipt,
    required int paperWidthDots,
    Uint8List? logoBytes,
    required PrintStyleSettings style,
  }) async {
    try {
      final savedPrinter = _ref.read(savedPrinterProvider).valueOrNull;
      if (savedPrinter == null) return false;

      final service = _ref.read(printerServiceProvider);
      if (!service.isConnected) {
        final connected = await service.connect(savedPrinter.toDevice());
        if (!connected) return false;
      }

      final bytes = await EscPosReceiptBuilder.build(
        receipt: receipt,
        paperWidthDots: paperWidthDots,
        logoBytes: logoBytes,
        fontScale: style.fontScale,
        fontWeight: style.fontWeight,
      );

      await service.sendBytes(bytes);
      return true;
    } catch (e, s) {
      AppLogger.error('Thermal Print Engine Failed', e, s);
      return false;
    }
  }

  /// 2️⃣ طباعة A4 (فاتورة رسمية)
  Future<bool> printInvoiceA4({
    required Receipt receipt,
    Uint8List? logoBytes,
    required PrintStyleSettings style,
  }) async {
    try {
      final bytes = await PdfReceiptBuilder.build(
        receipt: receipt,
        size: ReceiptPaperSize.a4, // ⬅️ إجبار المقاس على A4
        style: style,
        logoBytes: logoBytes,
      );

      await Printing.layoutPdf(
        name: 'invoice-${receipt.invoiceNumber ?? receipt.saleId}.pdf',
        onLayout: (PdfPageFormat _) => bytes,
      );
      return true;
    } catch (e, s) {
      AppLogger.error('A4 Print Engine Failed', e, s);
      return false;
    }
  }

  /// 3️⃣ مشاركة A4
  Future<bool> shareInvoiceA4({
    required Receipt receipt,
    Uint8List? logoBytes,
    required PrintStyleSettings style,
  }) async {
    try {
      final bytes = await PdfReceiptBuilder.build(
        receipt: receipt,
        size: ReceiptPaperSize.a4, // ⬅️ إجبار المقاس على A4
        style: style,
        logoBytes: logoBytes,
      );

      await Printing.sharePdf(
        bytes: bytes,
        filename: 'invoice-${receipt.invoiceNumber ?? receipt.saleId}.pdf',
      );
      return true;
    } catch (e, s) {
      AppLogger.error('A4 Share Engine Failed', e, s);
      return false;
    }
  }

  /// 4️⃣ طباعة تقارير وكشوف (A4 جاهزة)
  Future<bool> printRawPdf({required Uint8List bytes, required String filename}) async {
    try {
      await Printing.layoutPdf(
        name: filename,
        onLayout: (PdfPageFormat _) => bytes,
      );
      return true;
    } catch (e, s) {
      AppLogger.error('Raw PDF Print Failed', e, s);
      return false;
    }
  }

  /// 5️⃣ مشاركة تقارير وكشوف
  Future<bool> shareRawPdf({required Uint8List bytes, required String filename}) async {
    try {
      await Printing.sharePdf(bytes: bytes, filename: filename);
      return true;
    } catch (e, s) {
      AppLogger.error('Raw PDF Share Failed', e, s);
      return false;
    }
  }
}

final appPrintEngineProvider = Provider<AppPrintEngine>((ref) {
  return AppPrintEngine(ref);
});

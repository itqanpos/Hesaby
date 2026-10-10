// lib/features/pos/data/services/direct_print_service.dart

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart' show Printer, Printing;

import '../../../../core/utils/logger.dart';
import '../../../settings/data/services/company_logo_loader.dart';
import '../../../settings/domain/entities/company_settings.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../domain/entities/printer_device.dart';
import '../../domain/entities/receipt.dart';
import '../../presentation/providers/printer_providers.dart';
import 'esc_pos_receipt_builder.dart';
import 'pdf_receipt_builder.dart' show ReceiptPaperSize;
import 'pos_preferences.dart';

/// Central orchestrator for "direct print" mode.
///
/// When the user enables print-direct in printer settings, POS and other
/// print entry points attempt to print *without* opening a Flutter dialog
/// and *without* the OS print dialog.
///
/// **Platform reality:**
/// * **Android** — `Printing.directPrintPdf(printer: …)` reaches the OS
///   print service directly. Bluetooth thermal printers are driven by
///   `PrinterService.sendBytes`.
/// * **Web** — direct printing is impossible; the browser always shows
///   its own print dialog. This service therefore returns `false` on the
///   web, and callers fall back to the regular dialog.
///
/// The service never throws. A failure (`false`) is the signal to the
/// caller to open the standard dialog.
abstract final class DirectPrintService {
  /// Tries a direct thermal print of a POS [receipt].
  ///
  /// * Reuses the printer saved in `savedPrinterProvider`.
  /// * Reconnects if the session dropped the connection.
  /// * Falls back to `false` on any error — never throws.
  static Future<bool> tryThermalReceipt({
    required WidgetRef ref,
    required Receipt receipt,
  }) async {
    try {
      final SavedPrinter? saved =
          ref.read(savedPrinterProvider).valueOrNull;
      if (saved == null) return false;

      final service = ref.read(printerServiceProvider);
      if (!service.isConnected) {
        final bool ok = await service.connect(saved.toDevice());
        if (!ok) return false;
      }

      final Uint8List? logoBytes = await _loadLogoBytes(ref);

      final ReceiptPaperSize size =
          ref.read(posPaperSizeProvider).valueOrNull ??
              PosPreferences.defaultPaperSize;
      final int widthDots = size == ReceiptPaperSize.mm58
          ? EscPosReceiptBuilder.widthMm58
          : EscPosReceiptBuilder.widthMm80;

      final CompanySettings? settings =
          ref.read(companySettingsProvider).valueOrNull;
      final PrintStyleSettings style = settings == null
          ? const PrintStyleSettings.defaults()
          : PrintStyleSettings.fromCompanySettings(settings);

      final List<int> bytes = await EscPosReceiptBuilder.build(
        receipt: receipt,
        paperWidthDots: widthDots,
        logoBytes: logoBytes,
        fontScale: style.fontScale,
        fontWeight: style.fontWeight,
      );
      await service.sendBytes(bytes);
      return true;
    } on Object catch (e) {
      AppLogger.warning('Direct thermal print failed (non-fatal): $e');
      return false;
    }
  }

  /// Tries a direct PDF print of [bytes] to the system's default printer.
  ///
  /// Returns `false` on the web (direct printing is unavailable), when no
  /// printer is registered, or on any error.
  static Future<bool> tryPdfBytes({
    required Uint8List bytes,
    String name = 'document.pdf',
  }) async {
    try {
      final List<Printer> printers = await Printing.listPrinters();
      if (printers.isEmpty) return false;

      Printer? target;
      for (final Printer p in printers) {
        if (p.isDefault) {
          target = p;
          break;
        }
      }
      target ??= printers.first;

      return await Printing.directPrintPdf(
        printer: target,
        name: name,
        onLayout: (PdfPageFormat _) => bytes,
      );
    } on Object catch (e) {
      AppLogger.warning('Direct PDF print failed (non-fatal): $e');
      return false;
    }
  }

  static Future<Uint8List?> _loadLogoBytes(WidgetRef ref) async {
    try {
      final CompanySettings? s =
          ref.read(companySettingsProvider).valueOrNull;
      if (s == null || s.companyId.isEmpty) return null;
      return await const CompanyLogoLoader().load(
        companyId: s.companyId,
        logoUrl: s.logoUrl,
      );
    } on Object {
      return null;
    }
  }
}

// lib/features/sales/presentation/services/sale_print_actions.dart

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart' show Printing;

import '../../../../core/utils/logger.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../pos/data/services/esc_pos_receipt_builder.dart';
import '../../../pos/data/services/pdf_receipt_builder.dart';
import '../../../pos/data/services/pos_preferences.dart';
import '../../../pos/data/services/printer_service.dart';
import '../../../pos/domain/entities/printer_device.dart';
import '../../../pos/domain/entities/receipt.dart';
import '../../../pos/presentation/providers/printer_providers.dart';
import '../../../settings/data/services/company_logo_loader.dart';
import '../../../settings/domain/entities/company_settings.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../domain/entities/sale_entities.dart';

/// Outcome of a direct thermal print attempt.
enum DirectSalePrintResult {
  success,
  noPrinter,
  connectFailed,
  sendFailed,
}

/// Prints [sale] directly to the saved thermal printer — no preview
/// dialog, no PDF, no share sheet.
Future<DirectSalePrintResult> printSaleDirect({
  required WidgetRef ref,
  required Sale sale,
  required List<SaleItem> items,
  required String customerName,
  String? customerAddress,
  String? customerPhone,
  String? cashierName,
  required Map<String, String> productNames,
  required Map<String, String> unitNames,
}) async {
  if (items.isEmpty) {
    return DirectSalePrintResult.sendFailed;
  }

  final SavedPrinter? saved = ref.read(savedPrinterProvider).valueOrNull;
  if (saved == null) {
    return DirectSalePrintResult.noPrinter;
  }

  final PrinterService service = ref.read(printerServiceProvider);

  try {
    if (!service.isConnected) {
      final bool connected = await service.connect(saved.toDevice());
      if (!connected) {
        return DirectSalePrintResult.connectFailed;
      }
    }

    final Receipt receipt = buildReceiptFromSale(
      ref: ref,
      sale: sale,
      items: items,
      customerName: customerName,
      customerAddress: customerAddress,
      customerPhone: customerPhone,
      cashierName: cashierName,
      productNames: productNames,
      unitNames: unitNames,
    );

    final Uint8List? logoBytes = await _loadLogoBytes(ref);
    final PrintStyleSettings style = _readStyle(ref);
    final int widthDots = _resolveWidthDots(ref);

    final List<int> bytes = await EscPosReceiptBuilder.build(
      receipt: receipt,
      paperWidthDots: widthDots,
      logoBytes: logoBytes,
      fontScale: style.fontScale,
      fontWeight: style.fontWeight,
    );

    await service.sendBytes(bytes);
    return DirectSalePrintResult.success;
  } on PrinterException catch (error) {
    AppLogger.error('Direct sale print failed', error);
    return DirectSalePrintResult.sendFailed;
  } on Object catch (error, stackTrace) {
    AppLogger.error('Direct sale print failed', error, stackTrace);
    return DirectSalePrintResult.sendFailed;
  }
}

/// Builds a PDF for [sale] and opens the platform share sheet.
Future<bool> shareSalePdf({
  required WidgetRef ref,
  required Sale sale,
  required List<SaleItem> items,
  required String customerName,
  String? customerAddress,
  String? customerPhone,
  String? cashierName,
  required Map<String, String> productNames,
  required Map<String, String> unitNames,
}) async {
  if (items.isEmpty) {
    return false;
  }

  try {
    final Receipt receipt = buildReceiptFromSale(
      ref: ref,
      sale: sale,
      items: items,
      customerName: customerName,
      customerAddress: customerAddress,
      customerPhone: customerPhone,
      cashierName: cashierName,
      productNames: productNames,
      unitNames: unitNames,
    );

    final Uint8List? logoBytes = await _loadLogoBytes(ref);
    final PrintStyleSettings style = _readStyle(ref);
    final ReceiptPaperSize size =
        ref.read(posPaperSizeProvider).valueOrNull ??
            PosPreferences.defaultPaperSize;

    final Uint8List bytes = await PdfReceiptBuilder.build(
      receipt: receipt,
      size: size,
      style: style,
      logoBytes: logoBytes,
    );

    final String suffix =
        (sale.invoiceNumber?.trim().isNotEmpty ?? false)
            ? sale.invoiceNumber!.trim()
            : sale.id;

    await Printing.sharePdf(
      bytes: bytes,
      filename: 'sale-$suffix.pdf',
    );
    return true;
  } on Object catch (error, stackTrace) {
    AppLogger.error('Sale PDF share failed', error, stackTrace);
    return false;
  }
}

/// Builds a [Receipt] snapshot from a stored [Sale] and its related data.
Receipt buildReceiptFromSale({
  required WidgetRef ref,
  required Sale sale,
  required List<SaleItem> items,
  required String customerName,
  String? customerAddress,
  String? customerPhone,
  String? cashierName,
  required Map<String, String> productNames,
  required Map<String, String> unitNames,
}) {
  final CompanyContextState contextState =
      ref.read(companyContextProvider);
  final CompanySettings? settings =
      ref.read(companySettingsProvider).valueOrNull;

  return Receipt(
    saleId: sale.id,
    invoiceNumber: sale.invoiceNumber,
    dateTime: sale.saleDate,
    companyName: contextState.currentCompany?.name ?? '—',
    branchName: contextState.currentBranch?.name ?? '—',
    companyAddress: contextState.currentCompany?.address,
    companyPhone: contextState.currentCompany?.phone,
    companyTaxNumber: contextState.currentCompany?.taxNumber,
    companyCommercialRegister:
        contextState.currentCompany?.commercialRegister,
    showTaxNumberOnPrint: settings?.showTaxNumberOnPrint ?? false,
    showCommercialRegisterOnPrint:
        settings?.showCommercialRegisterOnPrint ?? false,
    showCurrencySymbol: settings?.showCurrencySymbol ?? true,
    lines: <ReceiptLine>[
      for (final SaleItem item in items)
        ReceiptLine(
          productName: productNames[item.productId] ?? 'منتج محذوف',
          unitName: unitNames[item.unitId] ?? 'وحدة',
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          lineTotal: item.lineTotal,
        ),
    ],
    subtotal: sale.subtotal,
    discount: sale.discount,
    taxAmount: sale.taxAmount,
    total: sale.total,
    paidAmount: sale.paidAmount,
    customerName: sale.customerId != null ? customerName : null,
    customerAddress: sale.customerId != null ? customerAddress : null,
    customerPhone: sale.customerId != null ? customerPhone : null,
    cashierName: cashierName,
  );
}

/// Localised message for a [DirectSalePrintResult].
String directSalePrintMessage(DirectSalePrintResult result) {
  switch (result) {
    case DirectSalePrintResult.success:
      return 'تم إرسال الفاتورة للطابعة.';
    case DirectSalePrintResult.noPrinter:
      return 'لا توجد طابعة محفوظة. اضبط طابعة من الإعدادات.';
    case DirectSalePrintResult.connectFailed:
      return 'تعذّر الاتصال بالطابعة. تأكد من تشغيلها.';
    case DirectSalePrintResult.sendFailed:
      return 'تعذّر إرسال الفاتورة للطابعة.';
  }
}

// ============================================================================
// Internal helpers
// ============================================================================

Future<Uint8List?> _loadLogoBytes(WidgetRef ref) async {
  final CompanySettings? s =
      ref.read(companySettingsProvider).valueOrNull;
  if (s == null || s.companyId.isEmpty) return null;
  try {
    return await const CompanyLogoLoader().load(
      companyId: s.companyId,
      logoUrl: s.logoUrl,
    );
  } on Object catch (e) {
    AppLogger.warning('Logo load failed (non-fatal): $e');
    return null;
  }
}

PrintStyleSettings _readStyle(WidgetRef ref) {
  final CompanySettings? s =
      ref.read(companySettingsProvider).valueOrNull;
  if (s == null) return const PrintStyleSettings.defaults();
  return PrintStyleSettings.fromCompanySettings(s);
}

int _resolveWidthDots(WidgetRef ref) {
  final ReceiptPaperSize size =
      ref.read(posPaperSizeProvider).valueOrNull ??
          PosPreferences.defaultPaperSize;
  switch (size) {
    case ReceiptPaperSize.mm58:
      return EscPosReceiptBuilder.widthMm58;
    case ReceiptPaperSize.mm80:
    case ReceiptPaperSize.a4:
      return EscPosReceiptBuilder.widthMm80;
  }
}

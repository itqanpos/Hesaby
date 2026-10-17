// lib/features/pos/presentation/dialogs/pos_print_preview_dialog.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/logger.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../settings/data/services/company_logo_loader.dart';
import '../../../settings/domain/entities/company_settings.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../data/services/esc_pos_receipt_builder.dart';
import '../../data/services/pdf_receipt_builder.dart';
import '../../data/services/pos_preferences.dart';
import '../../data/services/printer_service.dart';
import '../../data/services/receipt_printer.dart';
import '../../domain/entities/printer_device.dart';
import '../../domain/entities/receipt.dart';
import '../providers/printer_providers.dart';
import '../widgets/thermal_receipt_preview.dart';

/// Opens the print preview dialog for [receipt].
///
/// The dialog shows:
/// * A live **thermal preview** — the exact bitmap that will be sent to
///   the printer (WYSIWYG).
/// * Up to three actions (in order):
///     1. **طباعة حرارية** (Bluetooth) — only when a saved printer exists.
///     2. **طباعة** — prints a PDF via the system dialog.
///     3. **مشاركة** — shares a PDF via the platform sheet.
Future<void> showPosPrintPreviewDialog({
  required BuildContext context,
  required Receipt receipt,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext dialogContext) =>
        _PosPrintPreviewDialog(receipt: receipt),
  );
}

class _PosPrintPreviewDialog extends ConsumerStatefulWidget {
  const _PosPrintPreviewDialog({required this.receipt});

  final Receipt receipt;

  @override
  ConsumerState<_PosPrintPreviewDialog> createState() =>
      _PosPrintPreviewDialogState();
}

class _PosPrintPreviewDialogState
    extends ConsumerState<_PosPrintPreviewDialog> {
  static const ReceiptPrinter _pdfPrinter = ReceiptPrinterImpl();

  bool _isPrinting = false;
  bool _isSharing = false;
  bool _isBluetoothPrinting = false;

  bool get _isBusy => _isPrinting || _isSharing || _isBluetoothPrinting;

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  PrintStyleSettings _readStyle({bool forA4 = false}) {
    final CompanySettings? settings =
        ref.read(companySettingsProvider).valueOrNull;
    if (settings == null) return const PrintStyleSettings.defaults();
    if (forA4) {
      return PrintStyleSettings(
        fontScale: settings.printFontScaleA4,
        fontWeight: settings.printFontWeight,
      );
    }
    return PrintStyleSettings.fromCompanySettings(settings);
  }

  Future<Uint8List?> _loadLogoBytes() async {
    final CompanySettings? settings =
        ref.read(companySettingsProvider).valueOrNull;
    if (settings == null || settings.companyId.isEmpty) return null;
    try {
      return await const CompanyLogoLoader().load(
        companyId: settings.companyId,
        logoUrl: settings.logoUrl,
      );
    } on Object catch (e) {
      AppLogger.warning('Logo load failed (non-fatal): $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // PDF actions
  // ---------------------------------------------------------------------------

  Future<void> _print() async {
    setState(() => _isPrinting = true);
    try {
      final ReceiptPaperSize size = _currentPaperSize();
      final Uint8List? logo = await _loadLogoBytes();

      final bool ok = await _pdfPrinter.printReceipt(
        receipt: widget.receipt,
        size: size,
        style: _readStyle(forA4: size == ReceiptPaperSize.a4),
        logoBytes: logo,
      );

      if (!mounted) return;
      setState(() => _isPrinting = false);

      if (ok) {
        Navigator.of(context).pop();
        return;
      }
      _showFailure('تعذّرت الطباعة. يرجى المحاولة مرة أخرى.');
    } on Object {
      if (!mounted) return;
      setState(() => _isPrinting = false);
      _showFailure('تعذّرت الطباعة. حاول مرة أخرى.');
    }
  }

  Future<void> _share() async {
    setState(() => _isSharing = true);
    try {
      final ReceiptPaperSize size = _currentPaperSize();
      final Uint8List? logo = await _loadLogoBytes();

      final bool ok = await _pdfPrinter.shareReceipt(
        receipt: widget.receipt,
        size: size,
        style: _readStyle(forA4: size == ReceiptPaperSize.a4),
        logoBytes: logo,
      );

      if (!mounted) return;
      setState(() => _isSharing = false);

      if (ok) {
        Navigator.of(context).pop();
        return;
      }
      _showFailure('تعذّرت مشاركة الإيصال.');
    } on Object {
      if (!mounted) return;
      setState(() => _isSharing = false);
      _showFailure('تعذّرت مشاركة الإيصال.');
    }
  }

  // ---------------------------------------------------------------------------
  // Bluetooth action
  // ---------------------------------------------------------------------------

  Future<void> _printBluetooth(SavedPrinter saved) async {
    setState(() => _isBluetoothPrinting = true);

    final PrinterService service = ref.read(printerServiceProvider);

    try {
      if (!service.isConnected) {
        final bool connected = await service.connect(saved.toDevice());
        if (!connected) {
          if (!mounted) return;
          _showFailure('تعذّر الاتصال بالطابعة. تأكد من تشغيلها.');
          return;
        }
      }

      final Uint8List? logoBytes = await _loadLogoBytes();
      final PrintStyleSettings style = _readStyle();

      final int widthDots = _bluetoothWidthDots();
      final List<int> bytes = await EscPosReceiptBuilder.build(
        receipt: widget.receipt,
        paperWidthDots: widthDots,
        logoBytes: logoBytes,
        fontScale: style.fontScale,
        fontWeight: style.fontWeight,
      );

      await service.sendBytes(bytes);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تم إرسال الإيصال للطابعة.')),
        );
    } on PrinterException catch (error) {
      AppLogger.error('Bluetooth print failed', error);
      if (!mounted) return;
      _showFailure(_bluetoothFailureMessage(error.type));
    } on Object catch (error, stackTrace) {
      AppLogger.error('Bluetooth print failed', error, stackTrace);
      if (!mounted) return;
      _showFailure('تعذّرت الطباعة عبر Bluetooth. حاول مرة أخرى.');
    } finally {
      if (mounted) {
        setState(() => _isBluetoothPrinting = false);
      }
    }
  }

  int _bluetoothWidthDots() {
    final ReceiptPaperSize size = _currentPaperSize();
    switch (size) {
      case ReceiptPaperSize.mm58:
        return EscPosReceiptBuilder.widthMm58;
      case ReceiptPaperSize.mm80:
      case ReceiptPaperSize.a4:
        return EscPosReceiptBuilder.widthMm80;
    }
  }

  static String _bluetoothFailureMessage(PrinterFailureType type) {
    switch (type) {
      case PrinterFailureType.notSupported:
        return 'الطباعة عبر Bluetooth غير مدعومة على هذا الجهاز.';
      case PrinterFailureType.connectFailed:
        return 'تعذّر الاتصال بالطابعة. تأكد من تشغيلها.';
      case PrinterFailureType.notConnected:
        return 'لا توجد طابعة متصلة.';
      case PrinterFailureType.sendFailed:
        return 'تعذّر إرسال الإيصال للطابعة.';
      case PrinterFailureType.unknown:
        return 'حدث خطأ غير متوقع أثناء الطباعة.';
    }
  }

  void _showFailure(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  ReceiptPaperSize _currentPaperSize() {
    return ref.read(posPaperSizeProvider).valueOrNull ??
        PosPreferences.defaultPaperSize;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Receipt receipt = widget.receipt;

    final AsyncValue<SavedPrinter?> savedAsync =
        ref.watch(savedPrinterProvider);
    final SavedPrinter? savedPrinter = savedAsync.valueOrNull;

    return AlertDialog(
      title: Row(
        children: <Widget>[
          Icon(Icons.print_outlined, color: scheme.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('معاينة الإيصال')),
          IconButton(
            onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 96).clamp(260.0, 420.0)
            .toDouble(),
        child: ThermalReceiptPreview(
          receipt: receipt,
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (savedPrinter != null)
              AppButton(
                label: 'طباعة حرارية',
                icon: Icons.bluetooth,
                expanded: true,
                size: AppButtonSize.large,
                isLoading: _isBluetoothPrinting,
                onPressed: _isBusy
                    ? null
                    : () => _printBluetooth(savedPrinter),
              ),
            if (savedPrinter != null) const SizedBox(height: 8),
            AppButton(
              label: 'طباعة',
              icon: Icons.print_outlined,
              expanded: true,
              size: savedPrinter != null
                  ? AppButtonSize.medium
                  : AppButtonSize.large,
              isLoading: _isPrinting,
              onPressed: _isBusy ? null : _print,
            ),
            const SizedBox(height: 8),
            AppButton(
              label: 'مشاركة',
              icon: Icons.ios_share,
              variant: AppButtonVariant.outline,
              expanded: true,
              isLoading: _isSharing,
              onPressed: _isBusy ? null : _share,
            ),
          ],
        ),
      ],
      backgroundColor: scheme.surface,
      scrollable: false,
    );
  }
}

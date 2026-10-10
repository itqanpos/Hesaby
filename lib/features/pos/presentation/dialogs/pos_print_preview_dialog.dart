// lib/features/pos/presentation/dialogs/pos_print_preview_dialog.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/logger.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../settings/data/services/company_logo_loader.dart';
import '../../../settings/domain/entities/company_settings.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../data/services/esc_pos_receipt_builder.dart';
import '../../data/services/pdf_receipt_builder.dart';
import '../../data/services/pos_preferences.dart';
import '../../data/services/printer_service.dart';
import '../../data/services/receipt_printer.dart';
import '../../domain/entities/printer_device.dart';
import '../../domain/entities/receipt.dart';
import '../providers/printer_providers.dart';

/// Opens the print preview dialog for [receipt].
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

// ============================================================================
// Dialog
// ============================================================================

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
  // PDF actions
  // ---------------------------------------------------------------------------

  Future<void> _print() async {
    setState(() => _isPrinting = true);

    final bool ok = await _pdfPrinter.printReceipt(
      receipt: widget.receipt,
      size: _currentPaperSize(),
    );

    if (!mounted) return;
    setState(() => _isPrinting = false);

    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    _showFailure('تعذّرت الطباعة. يرجى المحاولة مرة أخرى.');
  }

  Future<void> _share() async {
    setState(() => _isSharing = true);

    final bool ok = await _pdfPrinter.shareReceipt(
      receipt: widget.receipt,
      size: _currentPaperSize(),
    );

    if (!mounted) return;
    setState(() => _isSharing = false);

    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    _showFailure('تعذّرت مشاركة الإيصال.');
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

      final int widthDots = _bluetoothWidthDots(saved);
      final List<int> bytes = await EscPosReceiptBuilder.build(
        receipt: widget.receipt,
        paperWidthDots: widthDots,
        logoBytes: logoBytes,
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

  /// Loads the current company's logo bytes.
  ///
  /// Returns `null` — never throws — so a missing or corrupt logo simply
  /// prints the receipt without one.
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

  int _bluetoothWidthDots(SavedPrinter _) {
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

  static String _labelOf(ReceiptPaperSize size) {
    switch (size) {
      case ReceiptPaperSize.mm58:
        return '58 مم';
      case ReceiptPaperSize.mm80:
        return '80 مم';
      case ReceiptPaperSize.a4:
        return 'A4';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Receipt receipt = widget.receipt;

    final AsyncValue<ReceiptPaperSize> asyncSize =
        ref.watch(posPaperSizeProvider);
    final ReceiptPaperSize currentSize = asyncSize.valueOrNull ??
        PosPreferences.defaultPaperSize;
    final AsyncValue<SavedPrinter?> savedAsync =
        ref.watch(savedPrinterProvider);
    final SavedPrinter? savedPrinter = savedAsync.valueOrNull;

    return AlertDialog(
      title: Row(
        children: <Widget>[
          Icon(Icons.print_outlined, color: scheme.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('طباعة الإيصال')),
          IconButton(
            onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _summaryRow(
                      theme,
                      label: 'رقم الفاتورة',
                      value: receipt.invoiceNumber ?? '—',
                    ),
                    _summaryRow(
                      theme,
                      label: 'عدد البنود',
                      value: receipt.lineCount.toString(),
                    ),
                    _summaryRow(
                      theme,
                      label: 'الإجمالي',
                      value: _formatMoney(receipt.total),
                      emphasized: true,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            if (savedPrinter != null)
              _BluetoothPrinterRow(printer: savedPrinter)
            else
              _NoBluetoothPrinterHint(
                onConfigure: () {
                  Navigator.of(context).pop();
                },
              ),

            const SizedBox(height: 12),

            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.description_outlined,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'مقاس الورق',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      _labelOf(currentSize),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'لتغيير المقاس: قائمة الخيارات (⋮) ← إعدادات الطباعة',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (savedPrinter != null)
              AppButton(
                label: 'طباعة عبر Bluetooth',
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
              label: 'طباعة (PDF)',
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
              label: 'مشاركة PDF',
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

  Widget _summaryRow(
    ThemeData theme, {
    required String label,
    required String value,
    bool emphasized = false,
  }) {
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            value,
            style: (emphasized
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.bodyLarge)
                ?.copyWith(
              color: emphasized ? scheme.primary : scheme.onSurface,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatMoney(double value) {
    final String fixed = value.toStringAsFixed(2);
    return '$fixed ج.م';
  }
}

// ============================================================================
// Bluetooth status widgets
// ============================================================================

class _BluetoothPrinterRow extends StatelessWidget {
  const _BluetoothPrinterRow({required this.printer});

  final SavedPrinter printer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(Icons.bluetooth, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    printer.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'سيتم استخدام الطابعة المحفوظة',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoBluetoothPrinterHint extends StatelessWidget {
  const _NoBluetoothPrinterHint({required this.onConfigure});

  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.bluetooth_disabled,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'لا توجد طابعة محفوظة. '
                'اضبط طابعة من الإعدادات لتفعيل الطباعة المباشرة.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

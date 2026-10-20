// lib/shared/printing/app_print_preview_dialog.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/printing/app_print_engine.dart';
import '../../features/pos/data/services/pdf_receipt_builder.dart'; // ⬅️ تم إضافة هذا الاستيراد
import '../../features/pos/data/services/pos_preferences.dart';
import '../../features/pos/domain/entities/receipt.dart';
import '../../features/pos/presentation/widgets/thermal_receipt_preview.dart';
import '../../features/settings/data/services/company_logo_loader.dart';
import '../../features/settings/domain/entities/print_style_settings.dart';
import '../../features/settings/presentation/providers/company_settings_providers.dart';
import '../../features/pos/presentation/providers/printer_providers.dart';
import '../widgets/app_button.dart';

Future<void> showAppPrintPreviewDialog({
  required BuildContext context,
  required Receipt receipt,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _AppPrintPreviewDialog(receipt: receipt),
  );
}

class _AppPrintPreviewDialog extends ConsumerStatefulWidget {
  const _AppPrintPreviewDialog({required this.receipt});
  final Receipt receipt;

  @override
  ConsumerState<_AppPrintPreviewDialog> createState() => _AppPrintPreviewDialogState();
}

class _AppPrintPreviewDialogState extends ConsumerState<_AppPrintPreviewDialog> {
  bool _isPrintingThermal = false;
  bool _isPrintingA4 = false;
  bool _isSharingA4 = false;

  bool get _isBusy => _isPrintingThermal || _isPrintingA4 || _isSharingA4;

  PrintStyleSettings _readStyle() {
    final settings = ref.read(companySettingsProvider).valueOrNull;
    if (settings == null) return const PrintStyleSettings.defaults();
    return PrintStyleSettings.fromCompanySettings(settings);
  }

  Future<Uint8List?> _loadLogoBytes() async {
    final settings = ref.read(companySettingsProvider).valueOrNull;
    if (settings == null || settings.companyId.isEmpty) return null;
    try {
      return await const CompanyLogoLoader().load(
        companyId: settings.companyId,
        logoUrl: settings.logoUrl,
      );
    } catch (e) {
      return null;
    }
  }

  int _thermalWidthDots() {
    final size = ref.read(posPaperSizeProvider).valueOrNull ?? PosPreferences.defaultPaperSize;
    return size == ReceiptPaperSize.mm58 ? 384 : 576;
  }

  Future<void> _handleThermalPrint() async {
    setState(() => _isPrintingThermal = true);
    final logo = await _loadLogoBytes();
    final success = await ref.read(appPrintEngineProvider).printThermal(
      receipt: widget.receipt,
      paperWidthDots: _thermalWidthDots(),
      logoBytes: logo,
      style: _readStyle(),
    );

    if (!mounted) return;
    setState(() => _isPrintingThermal = false);
    if (success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال الإيصال للطابعة الحرارية.')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّرت الطباعة. تأكد من اتصال الطابعة.')));
    }
  }

  Future<void> _handleA4Print() async {
    setState(() => _isPrintingA4 = true);
    final logo = await _loadLogoBytes();
    final success = await ref.read(appPrintEngineProvider).printInvoiceA4(
      receipt: widget.receipt,
      logoBytes: logo,
      style: _readStyle(),
    );

    if (!mounted) return;
    setState(() => _isPrintingA4 = false);
    if (success) Navigator.of(context).pop();
  }

  Future<void> _handleA4Share() async {
    setState(() => _isSharingA4 = true);
    final logo = await _loadLogoBytes();
    final success = await ref.read(appPrintEngineProvider).shareInvoiceA4(
      receipt: widget.receipt,
      logoBytes: logo,
      style: _readStyle(),
    );

    if (!mounted) return;
    setState(() => _isSharingA4 = false);
    if (success) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasPrinter = ref.watch(savedPrinterProvider).valueOrNull != null;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.print_outlined, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text('معاينة ${widget.receipt.documentType.label}')),
          IconButton(
            onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 96).clamp(260.0, 420.0).toDouble(),
        child: ThermalReceiptPreview(
          receipt: widget.receipt,
          maxHeight: MediaQuery.sizeOf(context).height * 0.55,
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasPrinter) ...[
              AppButton(
                label: 'طباعة إيصال حراري',
                icon: Icons.receipt_long,
                expanded: true,
                size: AppButtonSize.large,
                isLoading: _isPrintingThermal,
                onPressed: _isBusy ? null : _handleThermalPrint,
              ),
              const SizedBox(height: 8),
            ],
            
            AppButton(
              label: 'طباعة A4',
              icon: Icons.print_outlined,
              expanded: true,
              size: hasPrinter ? AppButtonSize.medium : AppButtonSize.large,
              isLoading: _isPrintingA4,
              onPressed: _isBusy ? null : _handleA4Print,
            ),
            const SizedBox(height: 8),
            
            AppButton(
              label: 'مشاركة A4',
              icon: Icons.ios_share,
              variant: AppButtonVariant.outline,
              expanded: true,
              isLoading: _isSharingA4,
              onPressed: _isBusy ? null : _handleA4Share,
            ),
          ],
        ),
      ],
    );
  }
}

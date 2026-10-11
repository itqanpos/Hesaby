// lib/features/purchases/presentation/dialogs/purchase_print_dialog.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/logger.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../pos/data/services/direct_print_service.dart';
import '../../../pos/data/services/pdf_receipt_builder.dart'
    show ReceiptPaperSize;
import '../../../settings/data/services/company_logo_loader.dart';
import '../../../settings/domain/entities/company_settings.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../data/services/pdf_purchase_receipt_builder.dart';
import '../../data/services/purchase_receipt_printer.dart';
import '../../domain/entities/purchase_receipt.dart';
import '../widgets/thermal_purchase_preview.dart';

/// Opens the print dialog for a purchase receipt.
///
/// The dialog shows:
/// * A compact paper-size selector (58 مم / 80 مم / A4).
/// * A live **thermal preview** — the exact bitmap that will be sent to a
///   thermal printer (WYSIWYG). For A4 the preview still uses the 80 mm
///   shape; the printed PDF respects the selected size.
/// * Two actions: **طباعة** (system dialog or direct print) and
///   **مشاركة** (share the PDF).
Future<void> showPurchasePrintDialog({
  required BuildContext context,
  required PurchaseReceipt receipt,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext dialogContext) =>
        _PurchasePrintDialog(receipt: receipt),
  );
}

class _PurchasePrintDialog extends ConsumerStatefulWidget {
  const _PurchasePrintDialog({required this.receipt});

  final PurchaseReceipt receipt;

  @override
  ConsumerState<_PurchasePrintDialog> createState() =>
      _PurchasePrintDialogState();
}

class _PurchasePrintDialogState
    extends ConsumerState<_PurchasePrintDialog> {
  static const PurchaseReceiptPrinter _printer =
      PurchaseReceiptPrinterImpl();

  ReceiptPaperSize _size = ReceiptPaperSize.mm80;
  bool _isPrinting = false;
  bool _isSharing = false;

  bool get _isBusy => _isPrinting || _isSharing;

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  PrintStyleSettings _readStyle() {
    final CompanySettings? s =
        ref.read(companySettingsProvider).valueOrNull;
    if (s == null) return const PrintStyleSettings.defaults();
    if (_size == ReceiptPaperSize.a4) {
      return PrintStyleSettings(
        fontScale: s.printFontScaleA4,
        fontWeight: s.printFontWeight,
      );
    }
    return PrintStyleSettings.fromCompanySettings(s);
  }

  Future<Uint8List?> _loadLogoBytes() async {
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

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _print() async {
    setState(() => _isPrinting = true);
    try {
      final bool direct =
          ref.read(companySettingsProvider).valueOrNull?.printDirectEnabled ??
              false;

      final Uint8List? logo = await _loadLogoBytes();

      // Direct-print path for non-A4 sizes.
      if (direct && _size != ReceiptPaperSize.a4) {
        final Uint8List bytes = await _buildPdf(logo);
        final bool ok = await DirectPrintService.tryPdfBytes(
          bytes: bytes,
          name: _fileNameFor(widget.receipt),
        );
        if (ok) {
          if (!mounted) return;
          Navigator.of(context).pop();
          return;
        }
      }

      // Fallback: system dialog.
      final bool ok = await _printer.printReceipt(
        receipt: widget.receipt,
        size: _size,
        style: _readStyle(),
        logoBytes: logo,
      );
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop();
        return;
      }
      _showFailure('تعذّرت الطباعة. يرجى المحاولة مرة أخرى.');
    } on Object {
      if (!mounted) return;
      _showFailure('تعذّرت الطباعة. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<Uint8List> _buildPdf(Uint8List? logo) {
    return PdfPurchaseReceiptBuilder.build(
      receipt: widget.receipt,
      size: _size,
      style: _readStyle(),
      logoBytes: logo,
    );
  }

  Future<void> _share() async {
    setState(() => _isSharing = true);
    try {
      final Uint8List? logo = await _loadLogoBytes();
      final bool ok = await _printer.shareReceipt(
        receipt: widget.receipt,
        size: _size,
        style: _readStyle(),
        logoBytes: logo,
      );
      if (!mounted) return;
      setState(() => _isSharing = false);
      if (ok) {
        Navigator.of(context).pop();
        return;
      }
      _showFailure('تعذّرت مشاركة الفاتورة.');
    } on Object {
      if (!mounted) return;
      setState(() => _isSharing = false);
      _showFailure('تعذّرت مشاركة الفاتورة.');
    }
  }

  void _showFailure(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onSizeSelected(Set<ReceiptPaperSize> selection) {
    if (selection.isEmpty || _isBusy) return;
    setState(() => _size = selection.first);
  }

  static String _fileNameFor(PurchaseReceipt r) {
    final String suffix = r.invoiceNumber?.trim().isNotEmpty == true
        ? r.invoiceNumber!.trim()
        : r.purchaseId;
    return 'purchase-$suffix.pdf';
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: <Widget>[
          Icon(Icons.print_outlined, color: scheme.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('معاينة الفاتورة')),
          IconButton(
            onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: SegmentedButton<ReceiptPaperSize>(
                segments: const <ButtonSegment<ReceiptPaperSize>>[
                  ButtonSegment<ReceiptPaperSize>(
                    value: ReceiptPaperSize.mm58,
                    label: Text('58 مم'),
                  ),
                  ButtonSegment<ReceiptPaperSize>(
                    value: ReceiptPaperSize.mm80,
                    label: Text('80 مم'),
                  ),
                  ButtonSegment<ReceiptPaperSize>(
                    value: ReceiptPaperSize.a4,
                    label: Text('A4'),
                  ),
                ],
                selected: <ReceiptPaperSize>{_size},
                onSelectionChanged: _isBusy ? null : _onSizeSelected,
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ThermalPurchasePreview(
              receipt: widget.receipt,
              paperSize: _size,
              maxHeight: 520,
            ),
            if (_size == ReceiptPaperSize.a4) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'المعاينة تظهر بشكل إيصال حراري. '
                'سيتم إنشاء PDF بمقاس A4 عند الطباعة.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppButton(
              label: 'طباعة',
              icon: Icons.print_outlined,
              expanded: true,
              size: AppButtonSize.large,
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

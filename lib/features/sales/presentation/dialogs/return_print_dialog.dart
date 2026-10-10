// lib/features/sales/presentation/dialogs/return_print_dialog.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart' show Printing;

import '../../../../shared/widgets/app_button.dart';
import '../../../pos/data/services/direct_print_service.dart';
import '../../../pos/data/services/pdf_receipt_builder.dart';
import '../../../settings/domain/entities/company_settings.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../data/services/pdf_return_builder.dart';
import '../../domain/entities/return_receipt.dart';

/// Opens the print dialog for a return receipt.
Future<void> showReturnPrintDialog({
  required BuildContext context,
  required ReturnReceipt receipt,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext dialogContext) =>
        _ReturnPrintDialog(receipt: receipt),
  );
}

class _ReturnPrintDialog extends ConsumerStatefulWidget {
  const _ReturnPrintDialog({required this.receipt});

  final ReturnReceipt receipt;

  @override
  ConsumerState<_ReturnPrintDialog> createState() =>
      _ReturnPrintDialogState();
}

class _ReturnPrintDialogState extends ConsumerState<_ReturnPrintDialog> {
  ReceiptPaperSize _selectedSize = ReceiptPaperSize.mm80;
  bool _isPrinting = false;
  bool _isSharing = false;

  bool get _isBusy => _isPrinting || _isSharing;

  PrintStyleSettings _readStyle() {
    final CompanySettings? settings =
        ref.read(companySettingsProvider).valueOrNull;
    if (settings == null) return const PrintStyleSettings.defaults();
    if (_selectedSize == ReceiptPaperSize.a4) {
      return PrintStyleSettings(
        fontScale: settings.printFontScaleA4,
        fontWeight: settings.printFontWeight,
      );
    }
    return PrintStyleSettings.fromCompanySettings(settings);
  }

  Future<void> _print() async {
    setState(() => _isPrinting = true);
    try {
      final Uint8List bytes = await PdfReturnBuilder.build(
        receipt: widget.receipt,
        size: _selectedSize,
        style: _readStyle(),
      );

      // Direct-print path when enabled and not A4.
      final bool direct =
          ref.read(companySettingsProvider).valueOrNull?.printDirectEnabled ??
              false;

      if (direct && _selectedSize != ReceiptPaperSize.a4) {
        final bool ok = await DirectPrintService.tryPdfBytes(
          bytes: bytes,
          name: _fileName(),
        );
        if (ok) {
          if (!mounted) return;
          Navigator.of(context).pop();
          return;
        }
      }

      await Printing.layoutPdf(
        name: _fileName(),
        onLayout: (PdfPageFormat _) => bytes,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      _showFailure('تعذّرت الطباعة. يرجى المحاولة مرة أخرى.');
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _share() async {
    setState(() => _isSharing = true);
    try {
      final Uint8List bytes = await PdfReturnBuilder.build(
        receipt: widget.receipt,
        size: _selectedSize,
        style: _readStyle(),
      );

      await Printing.sharePdf(bytes: bytes, filename: _fileName());

      if (!mounted) return;
      Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      _showFailure('تعذّرت مشاركة الإيصال.');
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  void _showFailure(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _fileName() {
    final String suffix =
        widget.receipt.returnNumber?.trim().isNotEmpty == true
            ? widget.receipt.returnNumber!.trim()
            : widget.receipt.returnId;
    return 'return-$suffix.pdf';
  }

  void _onSizeSelected(Set<ReceiptPaperSize> selection) {
    if (selection.isEmpty || _isBusy) return;
    setState(() => _selectedSize = selection.first);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final ReturnReceipt receipt = widget.receipt;

    return AlertDialog(
      title: Row(
        children: <Widget>[
          Icon(Icons.print_outlined, color: scheme.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('طباعة المرتجع')),
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
                    _row(theme,
                        label: 'رقم المرتجع',
                        value: receipt.returnNumber ?? '—'),
                    _row(theme,
                        label: 'عدد البنود',
                        value: receipt.lineCount.toString()),
                    _row(theme,
                        label: 'طريقة الاسترداد',
                        value: receipt.refundMethodLabel),
                    _row(theme,
                        label: 'إجمالي المرتجع',
                        value: _formatMoney(receipt.total),
                        emphasized: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('مقاس الورق', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<ReceiptPaperSize>(
              segments: const <ButtonSegment<ReceiptPaperSize>>[
                ButtonSegment<ReceiptPaperSize>(
                  value: ReceiptPaperSize.mm80,
                  label: Text('80 مم'),
                  icon: Icon(Icons.receipt_outlined),
                ),
                ButtonSegment<ReceiptPaperSize>(
                  value: ReceiptPaperSize.a4,
                  label: Text('A4'),
                  icon: Icon(Icons.description_outlined),
                ),
              ],
              selected: <ReceiptPaperSize>{_selectedSize},
              onSelectionChanged: _isBusy ? null : _onSizeSelected,
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
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

  Widget _row(
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

  static String _formatMoney(double value) =>
      '${value.toStringAsFixed(2)} ج.م';
}

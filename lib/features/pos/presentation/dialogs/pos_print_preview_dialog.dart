// lib/features/pos/presentation/dialogs/pos_print_preview_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/app_button.dart';
import '../../data/services/pdf_receipt_builder.dart';
import '../../data/services/receipt_printer.dart';
import '../../domain/entities/receipt.dart';

/// Opens the print preview dialog for [receipt].
///
/// The dialog lets the cashier choose the paper size (58 mm, 80 mm or A4)
/// and then either print the receipt or share it as a PDF file. Failures
/// are surfaced as a short snack bar; the dialog stays open so the cashier
/// can retry.
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
  static const ReceiptPrinter _printer = ReceiptPrinterImpl();

  ReceiptPaperSize _selectedSize = ReceiptPaperSize.mm80;
  bool _isPrinting = false;
  bool _isSharing = false;

  bool get _isBusy => _isPrinting || _isSharing;

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _print() async {
    setState(() => _isPrinting = true);

    final bool ok = await _printer.printReceipt(
      receipt: widget.receipt,
      size: _selectedSize,
    );

    if (!mounted) {
      return;
    }

    setState(() => _isPrinting = false);

    if (ok) {
      Navigator.of(context).pop();
      return;
    }

    _showFailure('تعذّرت الطباعة. يرجى المحاولة مرة أخرى.');
  }

  Future<void> _share() async {
    setState(() => _isSharing = true);

    final bool ok = await _printer.shareReceipt(
      receipt: widget.receipt,
      size: _selectedSize,
    );

    if (!mounted) {
      return;
    }

    setState(() => _isSharing = false);

    if (ok) {
      Navigator.of(context).pop();
      return;
    }

    _showFailure('تعذّرت مشاركة الإيصال.');
  }

  void _showFailure(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onPaperSizeChanged(ReceiptPaperSize? value) {
    if (value == null || _isBusy) {
      return;
    }
    setState(() => _selectedSize = value);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Receipt receipt = widget.receipt;

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
            // ---- Receipt summary ----
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

            const SizedBox(height: 16),

            // ---- Paper size ----
            Text(
              'مقاس الورق',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            RadioGroup<ReceiptPaperSize>(
              groupValue: _selectedSize,
              onChanged: _isBusy ? null : _onPaperSizeChanged,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  RadioListTile<ReceiptPaperSize>(
                    value: ReceiptPaperSize.mm58,
                    contentPadding: EdgeInsets.zero,
                    title: Text('58 مم (حراري صغير)'),
                  ),
                  RadioListTile<ReceiptPaperSize>(
                    value: ReceiptPaperSize.mm80,
                    contentPadding: EdgeInsets.zero,
                    title: Text('80 مم (حراري قياسي)'),
                  ),
                  RadioListTile<ReceiptPaperSize>(
                    value: ReceiptPaperSize.a4,
                    contentPadding: EdgeInsets.zero,
                    title: Text('A4 (ورق مكتبي)'),
                  ),
                ],
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

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

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
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium,
            ),
          ),
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

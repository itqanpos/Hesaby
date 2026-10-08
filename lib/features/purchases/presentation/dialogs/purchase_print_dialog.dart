// lib/features/purchases/presentation/dialogs/purchase_print_dialog.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/app_button.dart';
import '../../../pos/data/services/pdf_receipt_builder.dart'
    show ReceiptPaperSize;
import '../../data/services/purchase_receipt_printer.dart';
import '../../domain/entities/purchase_receipt.dart';

/// Opens the print dialog for a purchase receipt.
///
/// Two actions: print (system dialog) or share as PDF. The paper size is
/// selectable inside the dialog (58 / 80 / A4) and remembered for the
/// current session only (the persisted default lives in POS settings).
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

// ============================================================================
// Dialog
// ============================================================================

class _PurchasePrintDialog extends StatefulWidget {
  const _PurchasePrintDialog({required this.receipt});

  final PurchaseReceipt receipt;

  @override
  State<_PurchasePrintDialog> createState() =>
      _PurchasePrintDialogState();
}

class _PurchasePrintDialogState extends State<_PurchasePrintDialog> {
  static const PurchaseReceiptPrinter _printer =
      PurchaseReceiptPrinterImpl();

  ReceiptPaperSize _size = ReceiptPaperSize.mm80;
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
      size: _size,
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
    final bool ok = await _printer.shareReceipt(
      receipt: widget.receipt,
      size: _size,
    );
    if (!mounted) return;
    setState(() => _isSharing = false);
    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    _showFailure('تعذّرت مشاركة الفاتورة.');
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

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final PurchaseReceipt receipt = widget.receipt;
    final NumberFormat money = NumberFormat.currency(
      locale: 'en_US',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

    return AlertDialog(
      title: Row(
        children: <Widget>[
          Icon(Icons.print_outlined, color: scheme.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('طباعة الفاتورة')),
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
            // ---- Summary ----
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
                      label: 'المورد',
                      value: receipt.supplierName,
                    ),
                    _summaryRow(
                      theme,
                      label: 'عدد البنود',
                      value: receipt.lineCount.toString(),
                    ),
                    _summaryRow(
                      theme,
                      label: 'الإجمالي',
                      value: money.format(receipt.total),
                      emphasized: true,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ---- Paper size ----
            Text('مقاس الورق', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<ReceiptPaperSize>(
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
}

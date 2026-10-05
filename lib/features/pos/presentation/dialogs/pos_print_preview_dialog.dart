// lib/features/pos/presentation/dialogs/pos_print_preview_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/app_button.dart';
import '../../data/services/pdf_receipt_builder.dart';
import '../../data/services/pos_preferences.dart';
import '../../data/services/receipt_printer.dart';
import '../../domain/entities/receipt.dart';

/// Opens the print preview dialog for [receipt].
///
/// The dialog only performs two actions — print or share as PDF — and
/// shows which paper size will be used. **The paper size itself is no
/// longer selectable here**; the cashier changes it from
/// `PosActionsSheet → إعدادات الطباعة`, and the choice is persisted in
/// `PreferencesStorage`. This keeps the print flow one-tap for the common
/// case (roll of 80 mm) and avoids repeating the picker on every sale.
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
      size: _currentPaperSize(),
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
      size: _currentPaperSize(),
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

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Reads the persisted paper size at the exact moment an action runs.
  ///
  /// Falls back to [PosPreferences.defaultPaperSize] while the async
  /// provider is still loading or when it has errored out, so the cashier
  /// can always complete a sale.
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

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Receipt receipt = widget.receipt;

    final AsyncValue<ReceiptPaperSize> asyncSize =
        ref.watch(posPaperSizeProvider);
    final ReceiptPaperSize currentSize = asyncSize.valueOrNull ??
        PosPreferences.defaultPaperSize;

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

            const SizedBox(height: 12),

            // ---- Current paper size (read-only) ----
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
  // Summary row helper
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

// lib/features/pos/presentation/dialogs/pos_print_settings_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/logger.dart';
import '../../data/services/pos_preferences.dart';
import '../../data/services/receipt_printer.dart';

/// Opens the POS print-settings bottom sheet.
///
/// The sheet is the single place where the cashier changes the default
/// receipt paper size. The value is persisted through
/// `posPaperSizeProvider` and is read back by the print-preview dialog
/// on the next print, so the size is never selected twice in a row.
Future<void> showPosPrintSettingsSheet({required BuildContext context}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext sheetContext) => const _PosPrintSettingsSheet(),
  );
}

// ============================================================================
// Sheet
// ============================================================================

class _PosPrintSettingsSheet extends ConsumerWidget {
  const _PosPrintSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AsyncValue<ReceiptPaperSize> asyncSize =
        ref.watch(posPaperSizeProvider);
    final ReceiptPaperSize current =
        asyncSize.valueOrNull ?? PosPreferences.defaultPaperSize;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.print_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'إعدادات الطباعة',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'مقاس الورق الافتراضي',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'يُستخدم تلقائيًا عند طباعة الإيصالات من نقطة البيع.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _PaperSizeSelector(
              current: current,
              isBusy: asyncSize.isLoading,
              onSelected: (ReceiptPaperSize size) =>
                  _persist(context, ref, size),
            ),
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'المقاس الحالي: ${_labelOf(current)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  Future<void> _persist(
    BuildContext context,
    WidgetRef ref,
    ReceiptPaperSize size,
  ) async {
    try {
      await ref.read(posPaperSizeProvider.notifier).setPaperSize(size);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to persist paper size', error, stackTrace);

      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('تعذّر حفظ الإعداد. حاول مرة أخرى.'),
          ),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

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
}

// ============================================================================
// Paper-size selector
// ============================================================================

/// Segmented selector for the three paper sizes supported by the printer.
///
/// Follows the project convention of using [SegmentedButton] instead of the
/// deprecated [RadioListTile] family.
class _PaperSizeSelector extends StatelessWidget {
  const _PaperSizeSelector({
    required this.current,
    required this.isBusy,
    required this.onSelected,
  });

  final ReceiptPaperSize current;
  final bool isBusy;
  final ValueChanged<ReceiptPaperSize> onSelected;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ReceiptPaperSize>(
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
      selected: <ReceiptPaperSize>{current},
      onSelectionChanged: isBusy
          ? null
          : (Set<ReceiptPaperSize> selection) {
              if (selection.isEmpty) {
                return;
              }
              final ReceiptPaperSize picked = selection.first;
              if (picked == current) {
                return;
              }
              onSelected(picked);
            },
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.comfortable,
      ),
    );
  }
}

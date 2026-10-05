// lib/features/pos/presentation/widgets/pos_actions_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/pdf_receipt_builder.dart';
import '../../data/services/pos_preferences.dart';
import '../../domain/entities/pos_cart.dart';
import '../dialogs/pos_print_settings_sheet.dart';
import '../state/pos_providers.dart';

/// Opens the POS actions menu.
///
/// The menu is presented as a bottom sheet anchored to the bottom of the
/// screen. Most entries are navigation contracts or explicit "قريبًا"
/// placeholders; the print-settings entry is the only one that currently
/// performs a real action — it opens `showPosPrintSettingsSheet`.
Future<void> showPosActionsSheet({required BuildContext context}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext sheetContext) => const _PosActionsSheet(),
  );
}

class _PosActionsSheet extends ConsumerWidget {
  const _PosActionsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final PosCart cart = ref.watch(posCartProvider);
    final String? customerName = cart.customerName;

    final AsyncValue<ReceiptPaperSize> asyncSize =
        ref.watch(posPaperSizeProvider);
    final ReceiptPaperSize currentSize = asyncSize.valueOrNull ??
        PosPreferences.defaultPaperSize;

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
                Text(
                  'خيارات',
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
            const SizedBox(height: 4),

            if (customerName != null) ...<Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'العميل المحدد: $customerName',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],

            // -------------------------------------------------------------------
            // Active action — print settings
            // -------------------------------------------------------------------
            _ActionTile(
              icon: Icons.print_outlined,
              title: 'إعدادات الطباعة',
              subtitle: 'مقاس الورق الحالي: ${_labelOf(currentSize)}',
              enabled: true,
              onTap: () => _openPrintSettings(context),
            ),

            const SizedBox(height: 6),
            const Divider(height: 1),
            const SizedBox(height: 6),

            // -------------------------------------------------------------------
            // Placeholder actions — available in later phases
            // -------------------------------------------------------------------
            _ActionTile(
              icon: Icons.payments_outlined,
              title: 'تحصيل من العميل',
              subtitle: customerName == null
                  ? 'يتطلب اختيار عميل أولًا'
                  : 'تسجيل دفعة على رصيد $customerName',
              enabled: false,
            ),
            _ActionTile(
              icon: Icons.receipt_long_outlined,
              title: 'الفاتورة الحالية',
              subtitle: 'مراجعة بنود الفاتورة الحالية',
              enabled: false,
            ),
            _ActionTile(
              icon: Icons.assignment_return_outlined,
              title: 'إنشاء فاتورة مرتجع',
              subtitle: 'إرجاع منتجات من فاتورة سابقة',
              enabled: false,
            ),
            _ActionTile(
              icon: Icons.history_outlined,
              title: 'إعادة طباعة الإيصال',
              subtitle: 'طباعة آخر إيصال مكتمل',
              enabled: false,
            ),

            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 10),

            Text(
              'بقية الإجراءات ستكون متاحة في المراحل القادمة.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Closes this sheet, then opens the print-settings sheet.
  ///
  /// `Navigator.pop` is synchronous in Flutter — it schedules the route
  /// removal but the current context stays mounted for the duration of the
  /// same synchronous block, so a follow-up `showModalBottomSheet` on that
  /// context will still resolve the same root navigator.
  void _openPrintSettings(BuildContext context) {
    Navigator.of(context).pop();
    showPosPrintSettingsSheet(context: context);
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
}

// ============================================================================
// Action tile
// ============================================================================

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final Color iconColor = enabled
        ? scheme.primary
        : scheme.onSurfaceVariant.withValues(alpha: 0.5);
    final Color foreground = enabled
        ? scheme.onSurface
        : scheme.onSurfaceVariant.withValues(alpha: 0.65);

    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 4,
        vertical: 6,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!enabled)
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                child: Text(
                  'قريبًا',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          else
            Icon(
              Icons.chevron_left, // RTL: points left, meaning "forward"
              color: scheme.onSurfaceVariant,
            ),
        ],
      ),
    );

    return Opacity(
      opacity: enabled ? 1.0 : 0.75,
      child: enabled
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: content,
            )
          : content,
    );
  }
}

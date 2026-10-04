// lib/features/pos/presentation/widgets/pos_actions_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/pos_cart.dart';
import '../state/pos_providers.dart';

/// Opens the POS actions menu.
///
/// The menu is presented as a bottom sheet anchored to the bottom of the
/// screen. Every entry is defined as a navigation contract or an explicit
/// "قريبًا" placeholder — no backend call is issued by this widget.
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
              icon: Icons.print_outlined,
              title: 'إعادة طباعة الإيصال',
              subtitle: 'طباعة آخر إيصال مكتمل',
              enabled: false,
            ),

            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 10),

            Text(
              'هذه الإجراءات ستكون متاحة في المراحل القادمة.',
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
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;

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

    return Opacity(
      opacity: enabled ? 1.0 : 0.75,
      child: Padding(
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
              ),
          ],
        ),
      ),
    );
  }
}

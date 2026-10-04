// lib/features/pos/presentation/widgets/pos_actions_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../domain/entities/pos_cart.dart';
import '../state/pos_providers.dart';

/// Opens the POS actions sheet.
///
/// The sheet is a bottom-anchored menu of secondary actions. Actions that
/// are already available in the application (sales list, customers,
/// inventory) navigate to their corresponding routes. Actions that belong
/// to later phases (customer collection, returns, reprint, daily reports)
/// are rendered disabled with a "قريبًا" badge and do not perform any
/// network request or database mutation.
Future<void> showPosActionsSheet({required BuildContext context}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext sheetContext) => const _PosActionsSheet(),
  );
}

// ============================================================================
// Actions sheet
// ============================================================================

class _PosActionsSheet extends ConsumerWidget {
  const _PosActionsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool hasLines = ref.watch(
      posCartProvider.select((PosCart cart) => cart.isNotEmpty),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // ---- Title ----
            Row(
              children: <Widget>[
                Text(
                  'إجراءات',
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

            // ---- Section: available now ----
            _SectionLabel(label: 'متاح الآن', scheme: scheme, theme: theme),
            const SizedBox(height: 6),

            _ActionTile(
              icon: Icons.receipt_long_outlined,
              title: 'فواتير البيع',
              subtitle: 'عرض الفواتير المؤكدة والمسودات',
              onTap: () => _navigate(context, AppRouter.salesName),
            ),
            _ActionTile(
              icon: Icons.people_outline,
              title: 'العملاء',
              subtitle: 'إدارة بيانات العملاء',
              onTap: () => _navigate(context, AppRouter.customersName),
            ),
            _ActionTile(
              icon: Icons.warehouse_outlined,
              title: 'المخزون',
              subtitle: 'عرض أرصدة الفروع',
              onTap: () => _navigate(context, AppRouter.inventoryName),
            ),

            const SizedBox(height: 12),

            // ---- Section: coming soon ----
            _SectionLabel(
              label: 'قريبًا',
              scheme: scheme,
              theme: theme,
            ),
            const SizedBox(height: 6),

            _ActionTile(
              icon: Icons.payments_outlined,
              title: 'تحصيل من عميل',
              subtitle: 'تسجيل دفعة على رصيد العميل',
              enabled: false,
            ),
            _ActionTile(
              icon: Icons.assignment_return_outlined,
              title: 'مرتجع',
              subtitle: 'إرجاع منتجات من فاتورة سابقة',
              enabled: false,
            ),
            _ActionTile(
              icon: Icons.print_outlined,
              title: 'إعادة طباعة',
              subtitle: 'طباعة آخر إيصال',
              enabled: !hasLines && false,
            ),
            _ActionTile(
              icon: Icons.insights_outlined,
              title: 'مبيعات اليوم',
              subtitle: 'ملخص مبيعات الفرع الحالي',
              enabled: false,
            ),

            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 10),

            Text(
              'الميزات المُعلَّمة بـ "قريبًا" ستصبح متاحة في مراحل لاحقة.',
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

  /// Pops the sheet, then navigates to the given named route.
  static void _navigate(BuildContext context, String routeName) {
    Navigator.of(context).pop();
    context.pushNamed(routeName);
  }
}

// ============================================================================
// Section label
// ============================================================================

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    required this.scheme,
    required this.theme,
  });

  final String label;
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
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
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// Called when the tile is tapped. Ignored when [enabled] is `false`.
  final VoidCallback? onTap;

  /// Whether the action is currently available. When `false`, the tile is
  /// dimmed and a "قريبًا" badge is shown on the trailing edge.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final Color foreground = enabled
        ? scheme.onSurface
        : scheme.onSurfaceVariant.withValues(alpha: 0.65);
    final Color iconColor = enabled
        ? scheme.primary
        : scheme.onSurfaceVariant.withValues(alpha: 0.5);

    return Opacity(
      opacity: enabled ? 1.0 : 0.75,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
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
                  _ComingSoonBadge(scheme: scheme, theme: theme)
                else
                  Icon(
                    Icons.chevron_left,
                    color: scheme.onSurfaceVariant,
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Coming-soon badge
// ============================================================================

class _ComingSoonBadge extends StatelessWidget {
  const _ComingSoonBadge({required this.scheme, required this.theme});

  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          'قريبًا',
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// lib/features/reports/presentation/pages/reports_hub_page.dart

import 'package:flutter/material.dart';

import '../../../../shared/layouts/app_shell.dart';

/// Reports hub — a single entry point that groups every report by theme.
///
/// All reports are placeholders for now: tapping any tile shows a
/// "قريبًا" snack bar. As each report is implemented in a later phase, its
/// tile's `_handleTap` will navigate to the corresponding route.
class ReportsHubPage extends StatelessWidget {
  const ReportsHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      appBar: AppBar(title: const Text('التقارير')),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: const <Widget>[
          _Section(
            title: 'المبيعات',
            tiles: <_ReportTile>[
              _ReportTile(
                icon: Icons.receipt_long_outlined,
                color: Color(0xFF0F7B6C),
                title: 'ملخص المبيعات',
                subtitle: 'إجماليات، مدفوع، متبقٍ، مرتجعات',
              ),
              _ReportTile(
                icon: Icons.local_fire_department_outlined,
                color: Color(0xFFE65100),
                title: 'المنتجات الأكثر مبيعًا',
                subtitle: 'Top 20 حسب الكمية والقيمة',
              ),
              _ReportTile(
                icon: Icons.star_outline,
                color: Color(0xFF0288D1),
                title: 'العملاء الأكثر شراءً',
                subtitle: 'Top 20 حسب القيمة',
              ),
            ],
          ),
          SizedBox(height: 8),
          _Section(
            title: 'المخزون',
            tiles: <_ReportTile>[
              _ReportTile(
                icon: Icons.warehouse_outlined,
                color: Color(0xFF6A1B9A),
                title: 'تقييم المخزون',
                subtitle: 'قيمة المخزون الحالي لكل منتج',
              ),
              _ReportTile(
                icon: Icons.warning_amber_outlined,
                color: Color(0xFFC62828),
                title: 'المخزون المنخفض',
                subtitle: 'منتجات تحت حد الطلب',
              ),
              _ReportTile(
                icon: Icons.hourglass_empty,
                color: Color(0xFF5D4037),
                title: 'المنتجات الراكدة',
                subtitle: 'لم تُبَع خلال 30 / 60 / 90 يومًا',
              ),
            ],
          ),
          SizedBox(height: 8),
          _Section(
            title: 'مالي',
            tiles: <_ReportTile>[
              _ReportTile(
                icon: Icons.trending_up_outlined,
                color: Color(0xFF2E7D32),
                title: 'الأرباح والخسائر',
                subtitle: 'إيرادات − تكلفة المبيعات − مرتجعات',
              ),
              _ReportTile(
                icon: Icons.account_balance_wallet_outlined,
                color: Color(0xFFEF6C00),
                title: 'المدينون',
                subtitle: 'أرصدة العملاء المستحقة',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Section
// ============================================================================

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.tiles});

  final String title;
  final List<_ReportTile> tiles;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Row(
            children: <Widget>[
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        for (int i = 0; i < tiles.length; i++) ...<Widget>[
          tiles[i],
          if (i < tiles.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

// ============================================================================
// Tile
// ============================================================================

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  void _handleTap(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('هذا التقرير قريبًا.')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _handleTap(context),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
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
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
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
        ),
      ),
    );
  }
}

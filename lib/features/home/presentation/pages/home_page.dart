// lib/features/home/presentation/pages/home_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/config/app_config.dart';
import '../../../../app/router.dart';
import '../../../../core/responsive/responsive_helper.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../companies/presentation/widgets/branch_selector.dart';
import '../../../companies/presentation/widgets/company_selector.dart';

/// Home screen — the primary navigation hub.
///
/// Layout (top to bottom):
/// 1. Context card (company + branch).
/// 2. Large POS hero banner.
/// 3. Quick-actions row (sales / purchases / returns).
/// 4. Catalog & inventory section.
/// 5. People section (customers / suppliers).
/// 6. Analytics section (reports).
///
/// The page holds no business logic: every action is navigation or a state
/// read.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppConfig config = ref.watch(appConfigProvider);
    final CompanyContextState contextState =
        ref.watch(companyContextProvider);

    final bool hasCompany = contextState.currentCompany != null;

    return AppShell(
      appBar: AppBar(
        title: Text(l10n.appName),
        actions: <Widget>[
          IconButton(
            tooltip: 'الإعدادات',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.pushNamed(AppRouter.settingsName),
          ),
          _EnvironmentPill(config: config),
          const SizedBox(width: 12),
        ],
      ),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double availableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : ResponsiveHelper.contentMaxWidth;

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const SizedBox(height: 8),

                // ---- Context ----
                const _ContextCard(),

                if (hasCompany) ...<Widget>[
                  const SizedBox(height: 16),

                  // ---- POS hero ----
                  const _PosHeroBanner(),

                  const SizedBox(height: 24),

                  // ---- Quick actions ----
                  const _SectionHeader(
                    title: 'العمليات',
                    icon: Icons.flash_on_outlined,
                  ),
                  const SizedBox(height: 10),
                  _QuickActionsRow(availableWidth: availableWidth),

                  const SizedBox(height: 24),

                  // ---- Catalog & inventory ----
                  const _SectionHeader(
                    title: 'الكتالوج والمخزون',
                    icon: Icons.inventory_2_outlined,
                  ),
                  const SizedBox(height: 10),
                  _CatalogGrid(availableWidth: availableWidth),

                  const SizedBox(height: 24),

                  // ---- People ----
                  const _SectionHeader(
                    title: 'العلاقات',
                    icon: Icons.people_outline,
                  ),
                  const SizedBox(height: 10),
                  _PeopleGrid(availableWidth: availableWidth),

                  const SizedBox(height: 24),

                  // ---- Analytics ----
                  const _SectionHeader(
                    title: 'التحليلات',
                    icon: Icons.analytics_outlined,
                  ),
                  const SizedBox(height: 10),
                  const _ReportsBanner(),
                ] else ...<Widget>[
                  const SizedBox(height: 16),
                  const _EmptyCompanyHint(),
                ],

                const SizedBox(height: 32),

                _InfrastructureFooter(config: config),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Context card
// -----------------------------------------------------------------------------

class _ContextCard extends StatelessWidget {
  const _ContextCard();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.business_center_outlined,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'سياق العمل',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const CompanySelector(),
            const SizedBox(height: 6),
            const BranchSelector(),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// POS hero banner
// -----------------------------------------------------------------------------

class _PosHeroBanner extends StatelessWidget {
  const _PosHeroBanner();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.pushNamed(AppRouter.posName),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: <Color>[
                scheme.primary,
                Color.lerp(scheme.primary, scheme.primaryContainer, 0.6) ??
                    scheme.primaryContainer,
              ],
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.onPrimary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.point_of_sale_outlined,
                    color: scheme.onPrimary,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'نقطة البيع',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ابدأ بيعًا سريعًا الآن',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onPrimary.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.onPrimary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios_outlined,
                    color: scheme.onPrimary,
                    size: 18,
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

// -----------------------------------------------------------------------------
// Section header
// -----------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Row(
      children: <Widget>[
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Quick actions (3 tiles)
// -----------------------------------------------------------------------------

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({required this.availableWidth});

  final double availableWidth;

  @override
  Widget build(BuildContext context) {
    const double spacing = 8;
    const int columns = 3;
    final double tileWidth =
        (availableWidth - spacing * (columns - 1)) / columns;

    final List<_TileData> tiles = <_TileData>[
      const _TileData(
        icon: Icons.receipt_long_outlined,
        title: 'فواتير البيع',
        color: Color(0xFF0F7B6C),
        routeName: AppRouter.salesName,
      ),
      const _TileData(
        icon: Icons.shopping_bag_outlined,
        title: 'فواتير الشراء',
        color: Color(0xFF0288D1),
        routeName: AppRouter.purchasesName,
      ),
      const _TileData(
        icon: Icons.assignment_return_outlined,
        title: 'المرتجعات',
        color: Color(0xFF6A1B9A),
        routeName: AppRouter.returnsName,
      ),
    ];

    return Row(
      children: <Widget>[
        for (int i = 0; i < tiles.length; i++) ...<Widget>[
          SizedBox(
            width: tileWidth,
            child: _Tile(data: tiles[i]),
          ),
          if (i < tiles.length - 1) const SizedBox(width: spacing),
        ],
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Catalog & inventory (5 tiles)
// -----------------------------------------------------------------------------

class _CatalogGrid extends StatelessWidget {
  const _CatalogGrid({required this.availableWidth});

  final double availableWidth;

  @override
  Widget build(BuildContext context) {
    const double spacing = 8;
    const int columns = 3;
    final double tileWidth =
        (availableWidth - spacing * (columns - 1)) / columns;

    final List<_TileData> tiles = <_TileData>[
      const _TileData(
        icon: Icons.inventory_2_outlined,
        title: 'المنتجات',
        color: Color(0xFF0F7B6C),
        routeName: AppRouter.productsName,
      ),
      const _TileData(
        icon: Icons.warehouse_outlined,
        title: 'المخزون',
        color: Color(0xFF5D4037),
        routeName: AppRouter.inventoryName,
      ),
      const _TileData(
        icon: Icons.category_outlined,
        title: 'التصنيفات',
        color: Color(0xFFEF6C00),
        routeName: AppRouter.categoriesName,
      ),
      const _TileData(
        icon: Icons.straighten_outlined,
        title: 'الوحدات',
        color: Color(0xFF455A64),
        routeName: AppRouter.unitsName,
      ),
      const _TileData(
        icon: Icons.local_shipping_outlined,
        title: 'الموردون',
        color: Color(0xFF00838F),
        routeName: AppRouter.suppliersName,
      ),
    ];

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: <Widget>[
        for (final _TileData tile in tiles)
          SizedBox(
            width: tileWidth,
            child: _Tile(data: tile),
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// People grid
// -----------------------------------------------------------------------------

class _PeopleGrid extends StatelessWidget {
  const _PeopleGrid({required this.availableWidth});

  final double availableWidth;

  @override
  Widget build(BuildContext context) {
    const double spacing = 8;
    const int columns = 3;
    final double tileWidth =
        (availableWidth - spacing * (columns - 1)) / columns;

    return Row(
      children: <Widget>[
        SizedBox(
          width: tileWidth,
          child: const _Tile(
            data: _TileData(
              icon: Icons.people_outline,
              title: 'العملاء',
              color: Color(0xFF0288D1),
              routeName: AppRouter.customersName,
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Reports banner
// -----------------------------------------------------------------------------

class _ReportsBanner extends StatelessWidget {
  const _ReportsBanner();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.pushNamed(AppRouter.reportsName),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[
                        scheme.primary,
                        scheme.tertiary,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.analytics_outlined,
                    color: scheme.onPrimary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'التقارير',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'مبيعات · مخزون · أرباح · مدينون',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_left,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Generic tile
// -----------------------------------------------------------------------------

class _TileData {
  const _TileData({
    required this.icon,
    required this.title,
    required this.color,
    required this.routeName,
  });

  final IconData icon;
  final String title;
  final Color color;
  final String routeName;
}

class _Tile extends StatelessWidget {
  const _Tile({required this.data});

  final _TileData data;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.pushNamed(data.routeName),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: data.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    data.icon,
                    color: data.color,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  data.title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Empty company hint
// -----------------------------------------------------------------------------

class _EmptyCompanyHint extends StatelessWidget {
  const _EmptyCompanyHint();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.apartment_outlined,
              color: scheme.primary,
              size: 36,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'لم تختر شركة بعد',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'اختر شركة من الأعلى لعرض أدوات العمل.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Infrastructure footer
// -----------------------------------------------------------------------------

class _InfrastructureFooter extends StatelessWidget {
  const _InfrastructureFooter({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: <Widget>[
          Icon(
            config.isSupabaseConfigured
                ? Icons.cloud_done_outlined
                : Icons.cloud_off_outlined,
            size: 16,
            color: config.isSupabaseConfigured
                ? scheme.primary
                : scheme.error,
          ),
          const SizedBox(width: 6),
          Text(
            config.isSupabaseConfigured
                ? 'متصل بالخادم'
                : 'غير متصل بالخادم',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            'v0.1.0',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Environment pill (AppBar action)
// -----------------------------------------------------------------------------

class _EnvironmentPill extends StatelessWidget {
  const _EnvironmentPill({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final String label = switch (config.environment) {
      AppEnvironment.development => 'تطوير',
      AppEnvironment.staging => 'اختبار',
      AppEnvironment.production => 'إنتاج',
    };

    final Color color = switch (config.environment) {
      AppEnvironment.development => scheme.tertiary,
      AppEnvironment.staging => scheme.secondary,
      AppEnvironment.production => scheme.primary,
    };

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

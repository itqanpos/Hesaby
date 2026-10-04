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

/// Home screen — dashboard-style entry point.
///
/// Layout (top to bottom):
/// * compact hero with brand + environment
/// * unified business-context card (company + branch)
/// * prominent POS banner
/// * "البيع" section with two primary tiles
/// * "الإدارة" section with six administration tiles
/// * compact infrastructure status card
///
/// Contains no business logic: every action is navigation or a state read.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppConfig config = ref.watch(appConfigProvider);
    final CompanyContextState contextState =
        ref.watch(companyContextProvider);
    final TextTheme textTheme = Theme.of(context).textTheme;

    final bool hasCompany = contextState.currentCompany != null;

    return AppShell(
      appBar: AppBar(
        title: Text(l10n.appName),
        actions: <Widget>[
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
                const _ContextCard(),
                if (hasCompany) ...<Widget>[
                  const SizedBox(height: 16),
                  const _PosBanner(),
                  const SizedBox(height: 24),
                  _SectionHeader(title: 'البيع'),
                  const SizedBox(height: 12),
                  _PrimaryTilesRow(availableWidth: availableWidth),
                  const SizedBox(height: 24),
                  _SectionHeader(title: 'الإدارة'),
                  const SizedBox(height: 12),
                  _AdminGrid(availableWidth: availableWidth),
                  const SizedBox(height: 24),
                ] else ...<Widget>[
                  const SizedBox(height: 16),
                  _EmptyCompanyHint(textTheme: textTheme),
                  const SizedBox(height: 24),
                ],
                _SectionHeader(title: 'حالة البنية التحتية'),
                const SizedBox(height: 12),
                _StatusCard(config: config),
                const SizedBox(height: 24),
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
              child: Text(
                'سياق العمل',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
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
// POS banner — main call to action
// -----------------------------------------------------------------------------

class _PosBanner extends StatelessWidget {
  const _PosBanner();

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
                scheme.primaryContainer,
              ],
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.onPrimary.withValues(alpha: 0.15),
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
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ابدأ بيعًا سريعًا الآن',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onPrimary.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_outlined,
                  color: scheme.onPrimary,
                  size: 20,
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
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Row(
      children: <Widget>[
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Primary tiles (البيع)
// -----------------------------------------------------------------------------

class _PrimaryTilesRow extends StatelessWidget {
  const _PrimaryTilesRow({required this.availableWidth});

  final double availableWidth;

  @override
  Widget build(BuildContext context) {
    const double spacing = 12;
    final double tileWidth = (availableWidth - spacing) / 2;

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: <Widget>[
        SizedBox(
          width: tileWidth,
          child: _PrimaryTile(
            icon: Icons.receipt_long_outlined,
            title: 'فواتير البيع',
            subtitle: 'الطلبات والفواتير',
            color: const Color(0xFF0F7B6C),
            routeName: AppRouter.salesName,
          ),
        ),
        SizedBox(
          width: tileWidth,
          child: _PrimaryTile(
            icon: Icons.shopping_bag_outlined,
            title: 'فواتير الشراء',
            subtitle: 'استلام المخزون',
            color: const Color(0xFF0288D1),
            routeName: AppRouter.purchasesName,
          ),
        ),
      ],
    );
  }
}

class _PrimaryTile extends StatelessWidget {
  const _PrimaryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.routeName,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final String routeName;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.pushNamed(routeName),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
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
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Admin grid (الإدارة)
// -----------------------------------------------------------------------------

class _AdminGrid extends StatelessWidget {
  const _AdminGrid({required this.availableWidth});

  final double availableWidth;

  @override
  Widget build(BuildContext context) {
    const double spacing = 10;
    const int columns = 3;
    final double tileWidth =
        (availableWidth - spacing * (columns - 1)) / columns;

    final List<_AdminTileData> tiles = <_AdminTileData>[
      const _AdminTileData(
        icon: Icons.inventory_2_outlined,
        title: 'المنتجات',
        routeName: AppRouter.productsName,
      ),
      const _AdminTileData(
        icon: Icons.people_outline,
        title: 'العملاء',
        routeName: AppRouter.customersName,
      ),
      const _AdminTileData(
        icon: Icons.local_shipping_outlined,
        title: 'الموردون',
        routeName: AppRouter.suppliersName,
      ),
      const _AdminTileData(
        icon: Icons.warehouse_outlined,
        title: 'المخزون',
        routeName: AppRouter.inventoryName,
      ),
      const _AdminTileData(
        icon: Icons.category_outlined,
        title: 'التصنيفات',
        routeName: AppRouter.categoriesName,
      ),
      const _AdminTileData(
        icon: Icons.straighten_outlined,
        title: 'الوحدات',
        routeName: AppRouter.unitsName,
      ),
    ];

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: <Widget>[
        for (final _AdminTileData tile in tiles)
          SizedBox(
            width: tileWidth,
            child: _AdminTile(data: tile),
          ),
      ],
    );
  }
}

class _AdminTileData {
  const _AdminTileData({
    required this.icon,
    required this.title,
    required this.routeName,
  });

  final IconData icon;
  final String title;
  final String routeName;
}

class _AdminTile extends StatelessWidget {
  const _AdminTile({required this.data});

  final _AdminTileData data;

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
              horizontal: 10,
              vertical: 14,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Icon(data.icon, color: scheme.primary, size: 26),
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
// Status card (مضغوط)
// -----------------------------------------------------------------------------

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final List<_StatusRowData> rows = <_StatusRowData>[
      const _StatusRowData(
        icon: Icons.flutter_dash,
        title: 'Flutter framework',
        isReady: true,
      ),
      const _StatusRowData(
        icon: Icons.route_outlined,
        title: 'Routing',
        isReady: true,
      ),
      const _StatusRowData(
        icon: Icons.palette_outlined,
        title: 'Theme',
        isReady: true,
      ),
      const _StatusRowData(
        icon: Icons.translate_outlined,
        title: 'Localization',
        isReady: true,
      ),
      const _StatusRowData(
        icon: Icons.devices_outlined,
        title: 'Responsive layout',
        isReady: true,
      ),
      _StatusRowData(
        icon: Icons.cloud_outlined,
        title: 'Supabase',
        isReady: config.isSupabaseConfigured,
      ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < rows.length; i++) ...<Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: _StatusRow(
                  data: rows[i],
                  theme: theme,
                  scheme: scheme,
                ),
              ),
              if (i < rows.length - 1)
                Divider(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusRowData {
  const _StatusRowData({
    required this.icon,
    required this.title,
    required this.isReady,
  });

  final IconData icon;
  final String title;
  final bool isReady;
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.data,
    required this.theme,
    required this.scheme,
  });

  final _StatusRowData data;
  final ThemeData theme;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final Color accent = data.isReady ? scheme.primary : scheme.outline;

    return Row(
      children: <Widget>[
        Icon(data.icon, color: accent, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            data.title,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        Icon(
          data.isReady ? Icons.check_circle : Icons.radio_button_unchecked,
          color: accent,
          size: 18,
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Empty company hint
// -----------------------------------------------------------------------------

class _EmptyCompanyHint extends StatelessWidget {
  const _EmptyCompanyHint({required this.textTheme});

  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: <Widget>[
            Icon(Icons.apartment_outlined, color: scheme.primary, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'اختر شركة من الأعلى لعرض أدوات العمل.',
                style: textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Environment pill (in AppBar)
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

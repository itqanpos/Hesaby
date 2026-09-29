// lib/features/home/presentation/pages/home_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/config/app_config.dart';
import '../../../../core/responsive/responsive_helper.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../companies/presentation/widgets/branch_selector.dart';
import '../../../companies/presentation/widgets/company_selector.dart';

/// Phase 3 placeholder screen.
///
/// It intentionally contains no business logic. Its purpose is to prove that
/// routing, theming, localization, responsiveness, configuration and — as of
/// Phase 3 — the company/branch context selectors are wired correctly.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppConfig config = ref.watch(appConfigProvider);
    final TextTheme textTheme = Theme.of(context).textTheme;

    final List<_FoundationItem> items = <_FoundationItem>[
      _FoundationItem(icon: Icons.flutter_dash, title: l10n.homeStatusFlutter),
      _FoundationItem(icon: Icons.route_outlined, title: l10n.homeStatusRouting),
      _FoundationItem(icon: Icons.palette_outlined, title: l10n.homeStatusTheme),
      _FoundationItem(
        icon: Icons.translate_outlined,
        title: l10n.homeStatusLocalization,
      ),
      _FoundationItem(
        icon: Icons.devices_outlined,
        title: l10n.homeStatusResponsive,
      ),
      _FoundationItem(
        icon: Icons.cloud_outlined,
        title: l10n.homeStatusSupabase,
        isReady: config.isSupabaseConfigured,
      ),
    ];

    return AppShell(
      appBar: AppBar(title: Text(l10n.appName)),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double availableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : ResponsiveHelper.contentMaxWidth;
          final int columns = ResponsiveHelper.gridColumns(
            ResponsiveHelper.deviceTypeOf(availableWidth),
          );
          const double spacing = 16;
          final double itemWidth = columns <= 1
              ? availableWidth
              : (availableWidth - spacing * (columns - 1)) / columns;

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _HeroSection(l10n: l10n, config: config),
                const SizedBox(height: 24),
                const _ContextSection(),
                const SizedBox(height: 32),
                Text(
                  l10n.homeFoundationStatusTitle,
                  style: textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: <Widget>[
                    for (final _FoundationItem item in items)
                      SizedBox(
                        width: itemWidth,
                        child: _StatusCard(
                          item: item,
                          readyLabel: l10n.homeStatusReady,
                          pendingLabel: l10n.homeStatusPending,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Company and branch selectors grouped under a single section header.
///
/// The two selectors read their data from the company context provider and
/// render their own loading, empty and error states. This section contains
/// no logic beyond layout.
class _ContextSection extends StatelessWidget {
  const _ContextSection();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'سياق العمل',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        const CompanySelector(),
        const SizedBox(height: 8),
        const BranchSelector(),
      ],
    );
  }
}

String _environmentLabel(
  AppLocalizations l10n,
  AppEnvironment environment,
) => switch (environment) {
      AppEnvironment.development => l10n.homeEnvironmentDevelopment,
      AppEnvironment.staging => l10n.homeEnvironmentStaging,
      AppEnvironment.production => l10n.homeEnvironmentProduction,
    };

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.l10n, required this.config});

  final AppLocalizations l10n;
  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: <Color>[scheme.primary, scheme.primaryContainer],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.appName,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.appTagline,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onPrimary,
              ),
            ),
            const SizedBox(height: 20),
            _Pill(
              label: l10n.homePhaseLabel,
              foreground: scheme.onPrimary,
              background: scheme.primary,
            ),
            const SizedBox(height: 10),
            _Pill(
              label:
                  '${l10n.homeEnvironmentLabel}: '
                  '${_environmentLabel(l10n, config.environment)}',
              foreground: scheme.onPrimary,
              background: scheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: foreground),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.item,
    required this.readyLabel,
    required this.pendingLabel,
  });

  final _FoundationItem item;
  final String readyLabel;
  final String pendingLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isReady = item.isReady;
    final Color accent = isReady ? scheme.primary : scheme.outline;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(item.icon, color: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(item.title, style: theme.textTheme.bodyLarge),
            ),
            Text(
              isReady ? readyLabel : pendingLabel,
              style: theme.textTheme.labelMedium?.copyWith(color: accent),
            ),
          ],
        ),
      ),
    );
  }
}

@immutable
class _FoundationItem {
  const _FoundationItem({
    required this.icon,
    required this.title,
    this.isReady = true,
  });

  final IconData icon;
  final String title;
  final bool isReady;
}

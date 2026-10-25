// lib/shared/layouts/app_shell.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/operation_trigger.dart';
import '../../core/responsive/responsive_helper.dart';
import '../../features/admin/presentation/providers/admin_app_config_provider.dart';
import '../../features/admin/presentation/providers/platform_admin_provider.dart';
import '../widgets/sync_status_indicator.dart';
import '../widgets/update_available_banner.dart';
import 'app_navigation.dart';

/// Standard page scaffold used across HESABI.
class AppShell extends ConsumerWidget {
  const AppShell({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.backgroundColor,
    this.applyHorizontalPadding = true,
    this.constrainContentWidth = true,
    this.resizeToAvoidBottomInset = true,
    this.includeNavigation = true,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Color? backgroundColor;
  final bool applyHorizontalPadding;
  final bool constrainContentWidth;
  final bool resizeToAvoidBottomInset;
  final bool includeNavigation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DeviceType deviceType = context.deviceType;
    final double horizontalPadding = applyHorizontalPadding
        ? ResponsiveHelper.horizontalPadding(deviceType)
        : 0;

    final bool isWide = deviceType == DeviceType.desktop ||
        deviceType == DeviceType.wideDesktop;

    final bool hasAppBar = appBar != null;
    final bool showSidebar = includeNavigation && hasAppBar && isWide;
    final bool showDrawer = includeNavigation && hasAppBar && !isWide;

    // -------------------------------------------------------------------------
    // Maintenance mode gate
    // -------------------------------------------------------------------------
    final AppConfig? appConfig =
        ref.watch(adminAppConfigProvider).valueOrNull;
    final bool isAdmin = ref.watch(isPlatformAdminProvider);
    final bool underMaintenance =
        (appConfig?.maintenanceMode ?? false) && !isAdmin;

    if (underMaintenance) {
      return _MaintenanceView(
        message: appConfig?.maintenanceMessage ?? 'التطبيق تحت الصيانة.',
      );
    }

    // -------------------------------------------------------------------------
    // Announcement banner
    // -------------------------------------------------------------------------
    final Widget? announcementBanner =
        (appConfig?.announcementVisible ?? false) &&
                (appConfig?.announcementText.isNotEmpty ?? false)
            ? _AnnouncementBanner(
                text: appConfig!.announcementText,
                severity: appConfig.announcementSeverity,
              )
            : null;

    // -------------------------------------------------------------------------
    // Content
    // -------------------------------------------------------------------------
    final Widget content = SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (announcementBanner != null) announcementBanner,
          const SyncStatusIndicator(),
          const UpdateAvailableBanner(),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constrainContentWidth
                      ? ResponsiveHelper.contentMaxWidth
                      : double.infinity,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: body,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final Widget scaffold = Scaffold(
      backgroundColor: backgroundColor,
      appBar: appBar,
      drawer: showDrawer ? const AppDrawer() : null,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: showSidebar
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const AppSidebar(),
                Expanded(child: content),
              ],
            )
          : content,
    );

    return OperationTriggerScope(child: scaffold);
  }
}

// ============================================================================
// Maintenance View
// ============================================================================

class _MaintenanceView extends StatelessWidget {
  const _MaintenanceView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(
                      Icons.engineering_outlined,
                      size: 56,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'التطبيق تحت الصيانة',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'سنعود قريباً — شكراً لصبركم.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Announcement Banner
// ============================================================================

class _AnnouncementBanner extends StatelessWidget {
  const _AnnouncementBanner({
    required this.text,
    required this.severity,
  });

  final String text;
  final String severity;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final Color bg;
    final Color fg;
    final IconData icon;

    switch (severity) {
      case 'critical':
        bg = const Color(0xFFC62828);
        fg = Colors.white;
        icon = Icons.dangerous_outlined;
        break;
      case 'warning':
        bg = const Color(0xFFF9A825);
        fg = Colors.black87;
        icon = Icons.warning_amber_outlined;
        break;
      case 'info':
      default:
        bg = const Color(0xFF0288D1);
        fg = Colors.white;
        icon = Icons.info_outline;
        break;
    }

    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(icon, color: fg, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

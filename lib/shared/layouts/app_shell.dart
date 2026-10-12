// lib/shared/layouts/app_shell.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/operation_trigger.dart';
import '../../core/responsive/responsive_helper.dart';
import '../widgets/offline_banner.dart';
import 'app_navigation.dart';

/// Standard page scaffold used across HESABI.
///
/// Adds the app-wide navigation based on screen width:
///
/// * **mobile / tablet (< 1024)** — the navigation is a [Drawer] accessible
///   from the standard hamburger icon in the [AppBar].
/// * **desktop / wide desktop (>= 1024)** — the navigation is a permanent
///   [AppSidebar] on the "start" side (right in RTL, left in LTR). No
///   hamburger is shown because the sidebar is always visible.
///
/// Pages that must use the full width (currently only POS) opt out by
/// passing `includeNavigation: false`.
///
/// It also applies safe-area handling, responsive horizontal padding and
/// the project's maximum content width.
///
/// **Phase O-1:** an [OfflineBanner] is automatically rendered at the top
/// of the content area. It takes zero height while online, so it is safe
/// on every screen.
///
/// **Phase O-2:** the shell is wrapped in an [OperationTriggerScope] so
/// every screen automatically fires the offline queue when the device
/// comes back online, the company switches, or the app resumes.
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

  /// Forwarded to [Scaffold.resizeToAvoidBottomInset].
  ///
  /// * `true` (default) — the body shrinks when the soft keyboard appears.
  /// * `false` — the body keeps its full height; the keyboard overlays it.
  ///   Used by the POS page.
  final bool resizeToAvoidBottomInset;

  /// Whether the app-wide navigation (sidebar on wide screens, drawer on
  /// narrow ones) should be attached.
  ///
  /// Defaults to `true`. Pages with `appBar == null` (login, loading)
  /// never receive navigation regardless of this flag.
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

    // Offline banner sits at the top of the content area. It collapses to
    // zero height while online, so it never disturbs existing layouts.
    final Widget content = SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const OfflineBanner(),
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
                // First child in a `Row` lands on the "start" side, which
                // is the right in RTL and the left in LTR — exactly where
                // we want the sidebar.
                const AppSidebar(),
                Expanded(child: content),
              ],
            )
          : content,
    );

    // The trigger scope is mounted once per shell. It observes
    // connectivity, company switches and app-resume events to drive the
    // offline queue. Renders `scaffold` unchanged.
    return OperationTriggerScope(child: scaffold);
  }
}

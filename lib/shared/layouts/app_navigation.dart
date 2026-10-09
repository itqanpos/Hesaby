// lib/shared/layouts/app_navigation.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A single entry in the app-wide navigation.
@immutable
class _NavDestination {
  const _NavDestination({
    required this.label,
    required this.path,
    required this.icon,
  });

  final String label;
  final String path;
  final IconData icon;
}

/// The app-wide destinations, in display order.
///
/// Paths are plain URLs (not route names) so the sidebar and drawer do not
/// need to import the router constants — and so a future change to a route
/// name cannot silently break navigation.
const List<_NavDestination> _destinations = <_NavDestination>[
  _NavDestination(label: 'الرئيسية', path: '/', icon: Icons.home_outlined),
  _NavDestination(
    label: 'نقطة البيع',
    path: '/pos',
    icon: Icons.point_of_sale_outlined,
  ),
  _NavDestination(
    label: 'المنتجات',
    path: '/products',
    icon: Icons.inventory_2_outlined,
  ),
  _NavDestination(
    label: 'الفواتير',
    path: '/sales',
    icon: Icons.receipt_long_outlined,
  ),
  _NavDestination(
    label: 'المشتريات',
    path: '/purchases',
    icon: Icons.shopping_bag_outlined,
  ),
  _NavDestination(
    label: 'التقارير',
    path: '/reports',
    icon: Icons.analytics_outlined,
  ),
  _NavDestination(
    label: 'الإعدادات',
    path: '/settings',
    icon: Icons.settings_outlined,
  ),
];

// ============================================================================
// Helpers
// ============================================================================

/// Returns the current matched location, or `'/'` when the widget is not
/// inside a GoRouter (e.g. during widget tests).
String _currentLocation(BuildContext context) {
  try {
    return GoRouterState.of(context).matchedLocation;
  } on Object {
    return '/';
  }
}

/// Whether [path] is the destination for the current [location].
///
/// A destination is considered active when the location is exactly the
/// destination's path, or a nested path under it (`/products/categories`
/// activates `/products`).
bool _isActive(String location, String path) {
  if (path == '/') {
    return location == '/';
  }
  return location == path || location.startsWith('$path/');
}

// ============================================================================
// Sidebar — permanent navigation on wide screens
// ============================================================================

/// Permanent vertical navigation rail shown on desktop and wide-desktop.
///
/// In RTL (the default for this app) it appears on the **right**; in LTR it
/// appears on the left. A thin border separates it from the content.
class AppSidebar extends StatelessWidget {
  const AppSidebar({super.key});

  /// Width of the rail, in logical pixels.
  static const double width = 240;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: BorderDirectional(
          end: BorderSide(color: scheme.outlineVariant, width: 0.5),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _NavigationHeader(),
            Divider(height: 1, color: scheme.outlineVariant),
            const Expanded(child: _NavigationList()),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Drawer — navigation on mobile and tablet
// ============================================================================

/// Slide-out drawer with the same destinations as [AppSidebar].
///
/// On RTL it opens from the right automatically (Flutter's `Drawer` uses
/// the directionality's "start" side).
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _NavigationHeader(),
            Divider(height: 1, color: scheme.outlineVariant),
            const Expanded(child: _NavigationList()),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Internal: header
// ============================================================================

class _NavigationHeader extends StatelessWidget {
  const _NavigationHeader();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.point_of_sale_outlined,
              color: scheme.onPrimaryContainer,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'حسابي',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Internal: list
// ============================================================================

class _NavigationList extends StatelessWidget {
  const _NavigationList();

  @override
  Widget build(BuildContext context) {
    final String location = _currentLocation(context);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _destinations.length,
      itemBuilder: (BuildContext context, int index) {
        final _NavDestination destination = _destinations[index];
        return _NavigationTile(
          destination: destination,
          isActive: _isActive(location, destination.path),
        );
      },
    );
  }
}

// ============================================================================
// Internal: tile
// ============================================================================

class _NavigationTile extends StatelessWidget {
  const _NavigationTile({
    required this.destination,
    required this.isActive,
  });

  final _NavDestination destination;
  final bool isActive;

  void _handleTap(BuildContext context) {
    // The current location rebuilds the widget tree on navigation, so the
    // drawer is closed automatically when the route changes. Tapping the
    // active destination is a no-op.
    if (isActive) {
      return;
    }
    context.go(destination.path);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final Color foreground =
        isActive ? scheme.primary : scheme.onSurfaceVariant;
    final Color titleColor =
        isActive ? scheme.primary : scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isActive ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _handleTap(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            child: Row(
              children: <Widget>[
                Icon(destination.icon, size: 20, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    destination.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          isActive ? FontWeight.w700 : FontWeight.w500,
                      color: titleColor,
                    ),
                    overflow: TextOverflow.ellipsis,
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

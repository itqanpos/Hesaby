// lib/shared/layouts/app_navigation.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/companies/domain/entities/company_member.dart';
import '../../features/companies/domain/entities/member_permission.dart';
import '../../features/companies/presentation/providers/company_context_provider.dart';
import '../../features/companies/presentation/providers/company_context_state.dart';
import '../../features/companies/presentation/providers/members_providers.dart';

// ============================================================================
// Destinations
// ============================================================================

@immutable
class _NavDestination {
  const _NavDestination({
    required this.label,
    required this.path,
    required this.icon,
    required this.color,
    this.requiredPermission,
  });

  final String label;
  final String path;
  final IconData icon;
  final Color color;

  /// Permission code required to see this destination.
  ///
  /// `null` means "always visible" (e.g. the dashboard and the settings
  /// entry, which must remain reachable even for restricted members).
  final String? requiredPermission;
}

@immutable
class _NavSection {
  const _NavSection({required this.title, required this.items});

  final String title;
  final List<_NavDestination> items;
}

const List<_NavSection> _sections = <_NavSection>[
  _NavSection(
    title: 'الرئيسية',
    items: <_NavDestination>[
      _NavDestination(
        label: 'لوحة التحكم',
        path: '/',
        icon: Icons.space_dashboard_outlined,
        color: Color(0xFF0288D1),
        // Always visible — the home dashboard is the entry point for every
        // member, including cashiers.
      ),
      _NavDestination(
        label: 'نقطة البيع',
        path: '/pos',
        icon: Icons.point_of_sale_outlined,
        color: Color(0xFF0F7B6C),
        requiredPermission: MemberPermission.posUse,
      ),
    ],
  ),
  _NavSection(
    title: 'المتجر',
    items: <_NavDestination>[
      _NavDestination(
        label: 'المنتجات',
        path: '/products',
        icon: Icons.inventory_2_outlined,
        color: Color(0xFF0F7B6C),
        requiredPermission: MemberPermission.productsView,
      ),
      _NavDestination(
        label: 'الفواتير',
        path: '/sales',
        icon: Icons.receipt_long_outlined,
        color: Color(0xFF6A1B9A),
        requiredPermission: MemberPermission.salesView,
      ),
      _NavDestination(
        label: 'المشتريات',
        path: '/purchases',
        icon: Icons.shopping_bag_outlined,
        color: Color(0xFF0288D1),
        requiredPermission: MemberPermission.purchasesView,
      ),
      _NavDestination(
        label: 'المرتجعات',
        path: '/returns',
        icon: Icons.assignment_return_outlined,
        color: Color(0xFF00838F),
        requiredPermission: MemberPermission.returnsView,
      ),
    ],
  ),
  _NavSection(
    title: 'البيانات',
    items: <_NavDestination>[
      _NavDestination(
        label: 'العملاء',
        path: '/customers',
        icon: Icons.people_outline,
        color: Color(0xFFEF6C00),
        requiredPermission: MemberPermission.customersView,
      ),
      _NavDestination(
        label: 'الموردون',
        path: '/suppliers',
        icon: Icons.local_shipping_outlined,
        color: Color(0xFF00838F),
        requiredPermission: MemberPermission.suppliersView,
      ),
      _NavDestination(
        label: 'التقارير',
        path: '/reports',
        icon: Icons.analytics_outlined,
        color: Color(0xFFB71C1C),
        requiredPermission: MemberPermission.reportsView,
      ),
    ],
  ),
  _NavSection(
    title: 'النظام',
    items: <_NavDestination>[
      _NavDestination(
        label: 'الإعدادات',
        path: '/settings',
        icon: Icons.settings_outlined,
        color: Color(0xFF455A64),
        // Always visible — every member can change theme/locale and log
        // out, even without any other permission.
      ),
    ],
  ),
];

// ============================================================================
// Helpers
// ============================================================================

String _currentLocation(BuildContext context) {
  try {
    return GoRouterState.of(context).matchedLocation;
  } on Object {
    return '/';
  }
}

bool _isActive(String location, String path) {
  if (path == '/') {
    return location == '/';
  }
  return location == path || location.startsWith('$path/');
}

/// Returns the sections the current user is allowed to see, filtered by
/// their permissions.
///
/// A destination is kept when its [requiredPermission] is `null` or when
/// the current member holds that permission. Sections whose items are all
/// hidden are dropped entirely.
///
/// While the member is still loading, we optimistically show everything so
/// the sidebar does not flash empty on first paint.
List<_NavSection> _visibleSections(WidgetRef ref) {
  final AsyncValue<CompanyMember?> memberAsync =
      ref.watch(currentMemberProvider);

  // Show everything during the initial load — avoids a jarring flash of
  // an almost-empty sidebar.
  if (memberAsync.isLoading && !memberAsync.hasValue) {
    return _sections;
  }

  final CompanyMember? member = memberAsync.valueOrNull;

  // No member row available (unauthenticated, or a company was not yet
  // resolved): keep the sidebar minimal but not broken.
  if (member == null) {
    return _sections
        .map(
          (_NavSection s) => _NavSection(
            title: s.title,
            items: s.items
                .where((_NavDestination d) => d.requiredPermission == null)
                .toList(growable: false),
          ),
        )
        .where((_NavSection s) => s.items.isNotEmpty)
        .toList(growable: false);
  }

  final List<_NavSection> result = <_NavSection>[];
  for (final _NavSection section in _sections) {
    final List<_NavDestination> visible = section.items
        .where(
          (_NavDestination d) =>
              d.requiredPermission == null ||
              member.hasPermission(d.requiredPermission!),
        )
        .toList(growable: false);
    if (visible.isEmpty) continue;
    result.add(_NavSection(title: section.title, items: visible));
  }
  return result;
}

// ============================================================================
// Sidebar (wide screens)
// ============================================================================

class AppSidebar extends StatelessWidget {
  const AppSidebar({super.key});

  static const double width = 260;

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
      child: const SafeArea(child: _NavigationBody()),
    );
  }
}

// ============================================================================
// Drawer (mobile / tablet)
// ============================================================================

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      backgroundColor: scheme.surface,
      child: const SafeArea(child: _NavigationBody()),
    );
  }
}

// ============================================================================
// Shared body
// ============================================================================

class _NavigationBody extends ConsumerWidget {
  const _NavigationBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String location = _currentLocation(context);
    final List<_NavSection> visible = _visibleSections(ref);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _Header(),
        Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.6)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: <Widget>[
              for (final _NavSection section in visible)
                _SectionGroup(
                  section: section,
                  location: location,
                ),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.6)),
        const _Footer(),
      ],
    );
  }
}

// ============================================================================
// Header
// ============================================================================

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final CompanyContextState ctx = ref.watch(companyContextProvider);
    final AuthState auth = ref.watch(authProvider);

    final String companyName = ctx.currentCompany?.name ?? 'حسابي';
    final String? branchName = ctx.currentBranch?.name;
    final String? email = auth.session?.email;

    final List<String> meta = <String>[];
    if (branchName != null && branchName.isNotEmpty) {
      meta.add(branchName);
    }
    if (email != null && email.isNotEmpty) {
      meta.add(email);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.point_of_sale_outlined,
              color: scheme.onPrimary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  companyName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (meta.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    meta.join(' · '),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Section
// ============================================================================

class _SectionGroup extends StatelessWidget {
  const _SectionGroup({
    required this.section,
    required this.location,
  });

  final _NavSection section;
  final String location;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
            child: Text(
              section.title.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                fontSize: 10,
              ),
            ),
          ),
          for (final _NavDestination destination in section.items)
            _NavigationTile(
              destination: destination,
              isActive: _isActive(location, destination.path),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// Tile
// ============================================================================

class _NavigationTile extends StatelessWidget {
  const _NavigationTile({
    required this.destination,
    required this.isActive,
  });

  final _NavDestination destination;
  final bool isActive;

  void _handleTap(BuildContext context) {
    if (isActive) return;
    context.go(destination.path);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final Color background = isActive
        ? scheme.onSurface.withValues(alpha: 0.06)
        : Colors.transparent;
    final Color badgeBackground = isActive
        ? destination.color.withValues(alpha: 0.16)
        : destination.color.withValues(alpha: 0.10);
    final Color iconColor = isActive
        ? destination.color
        : destination.color.withValues(alpha: 0.75);
    final Color titleColor =
        isActive ? scheme.onSurface : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _handleTap(context),
          child: Stack(
            children: <Widget>[
              if (isActive)
                PositionedDirectional(
                  start: 0,
                  top: 8,
                  bottom: 8,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: destination.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: badgeBackground,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        destination.icon,
                        size: 18,
                        color: iconColor,
                      ),
                    ),
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
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Footer
// ============================================================================

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'حسابي',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            'v0.1.0',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

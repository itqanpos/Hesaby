// lib/app/router.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/pages/login_page.dart';
import '../features/auth/presentation/providers/auth_provider.dart';
import '../features/home/presentation/pages/home_page.dart';
import '../features/products/presentation/pages/categories_page.dart';
import '../features/products/presentation/pages/products_page.dart';
import '../features/products/presentation/pages/units_page.dart';
import '../l10n/app_localizations.dart';
import '../shared/widgets/app_error.dart';
import '../shared/widgets/app_loader.dart';

/// Route paths and names used across the application.
///
/// Kept as a namespace of constants so no route is ever hard-coded twice.
abstract final class AppRouter {
  static const String homePath = '/';
  static const String homeName = 'home';

  static const String loginPath = '/login';
  static const String loginName = 'login';

  static const String loadingPath = '/loading';
  static const String loadingName = 'loading';

  static const String productsPath = '/products';
  static const String productsName = 'products';

  static const String categoriesPath = '/products/categories';
  static const String categoriesName = 'categories';

  static const String unitsPath = '/products/units';
  static const String unitsName = 'units';
}

/// Provides the application router.
///
/// The router observes [authProvider] and applies authentication-based
/// redirection:
///
/// * `AuthStatus.unknown`      → `/loading` (waiting for session restoration)
/// * `AuthStatus.unauthenticated` → `/login`  (all other routes, including
///   `/products`, are unreachable)
/// * `AuthStatus.authenticated`  → every route except `/login` and
///   `/loading` is reachable, including the product catalog pages.
///
/// The redirect callback is intentionally synchronous: `go_router` requires
/// a deterministic decision on every navigation. The current authentication
/// state is read synchronously via `ref.read`.
final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((ref) {
  final GoRouter router = GoRouter(
    initialLocation: AppRouter.homePath,
    redirect: (BuildContext context, GoRouterState state) {
      final AuthState auth = ref.read(authProvider);
      final String location = state.matchedLocation;

      if (auth.isUnknown) {
        return location == AppRouter.loadingPath ? null : AppRouter.loadingPath;
      }

      if (auth.isUnauthenticated) {
        return location == AppRouter.loginPath ? null : AppRouter.loginPath;
      }

      // Authenticated: the login and loading screens are no longer reachable.
      if (location == AppRouter.loginPath ||
          location == AppRouter.loadingPath) {
        return AppRouter.homePath;
      }

      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRouter.homePath,
        name: AppRouter.homeName,
        builder: (BuildContext context, GoRouterState state) =>
            const HomePage(),
      ),
      GoRoute(
        path: AppRouter.loginPath,
        name: AppRouter.loginName,
        builder: (BuildContext context, GoRouterState state) =>
            const LoginPage(),
      ),
      GoRoute(
        path: AppRouter.loadingPath,
        name: AppRouter.loadingName,
        builder: (BuildContext context, GoRouterState state) =>
            const _AuthLoadingPage(),
      ),
      GoRoute(
        path: AppRouter.productsPath,
        name: AppRouter.productsName,
        builder: (BuildContext context, GoRouterState state) =>
            const ProductsPage(),
      ),
      GoRoute(
        path: AppRouter.categoriesPath,
        name: AppRouter.categoriesName,
        builder: (BuildContext context, GoRouterState state) =>
            const CategoriesPage(),
      ),
      GoRoute(
        path: AppRouter.unitsPath,
        name: AppRouter.unitsName,
        builder: (BuildContext context, GoRouterState state) =>
            const UnitsPage(),
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) {
      final AppLocalizations l10n = AppLocalizations.of(context);
      return Scaffold(
        body: AppErrorView(
          title: l10n.errorTitle,
          message: l10n.errorRouteNotFound,
          retryLabel: l10n.actionGoHome,
          onRetry: () => context.goNamed(AppRouter.homeName),
        ),
      );
    },
  );

  // Re-evaluate the redirect whenever the authentication status changes.
  // Refreshing only on status transitions avoids redundant rebuilds when
  // only session details (e.g. email) differ.
  ref.listen<AuthState>(authProvider, (AuthState? previous, AuthState next) {
    if (previous?.status != next.status) {
      router.refresh();
    }
  });

  ref.onDispose(router.dispose);

  return router;
});

/// Minimal loading screen shown while session restoration is in flight.
///
/// It is private to the router because it carries no business meaning; it
/// exists solely to bridge the `AuthStatus.unknown` state without flashing
/// either [HomePage] or [LoginPage].
class _AuthLoadingPage extends StatelessWidget {
  const _AuthLoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: AppLoader());
  }
}

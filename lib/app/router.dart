// lib/app/router.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/home/presentation/pages/home_page.dart';
import '../l10n/app_localizations.dart';
import '../shared/widgets/app_error.dart';

/// The single source of truth for navigation in HESABI.
abstract final class AppRouter {
  static const String homePath = '/';
  static const String homeName = 'home';

  static GoRouter create() {
    return GoRouter(
      initialLocation: homePath,
      routes: <RouteBase>[
        GoRoute(
          path: homePath,
          name: homeName,
          builder: (BuildContext context, GoRouterState state) =>
              const HomePage(),
        ),
      ],
      errorBuilder: (BuildContext context, GoRouterState state) {
        final AppLocalizations l10n = AppLocalizations.of(context);
        return Scaffold(
          body: AppErrorView(
            title: l10n.errorTitle,
            message: l10n.errorRouteNotFound,
            retryLabel: l10n.actionGoHome,
            onRetry: () => context.goNamed(homeName),
          ),
        );
      },
    );
  }
}

/// Provides the application router.
final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((ref) {
  final GoRouter router = AppRouter.create();
  ref.onDispose(router.dispose);
  return router;
});

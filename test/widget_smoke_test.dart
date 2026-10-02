// test/widget_smoke_test.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/app/app.dart';
import 'package:hesabi/features/auth/presentation/pages/login_page.dart';
import 'package:hesabi/shared/layouts/app_shell.dart';

/// Smoke test: verifies that the application boots without framework or
/// provider errors and settles on the screen produced by the current router
/// configuration for an unauthenticated session.
///
/// After Phase 1, HESABI's router redirects unauthenticated users to the
/// login screen. This test intentionally does NOT mock authentication: it
/// lets the real [authProvider] resolve to its default `unauthenticated`
/// state (no Supabase session is available in a test environment) and
/// asserts that the router lands on [LoginPage] without throwing.
void main() {
  testWidgets(
    'HesabiApp boots without errors and lands on the login page',
    (WidgetTester tester) async {
      await tester.pumpWidget(const ProviderScope(child: HesabiApp()));

      // Give the router enough frames to resolve the initial redirect
      // chain (unknown -> /loading -> unauthenticated -> /login). Each
      // pump advances a frame and flushes pending microtasks, so a handful
      // of short pumps covers the asynchronous session restore.
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Fail if any framework or provider exception escaped during boot.
      expect(tester.takeException(), isNull);

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(AppShell), findsOneWidget);
    },
  );
}

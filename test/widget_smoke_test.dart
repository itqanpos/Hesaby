// test/widget_smoke_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/app/app.dart';
import 'package:hesabi/features/auth/domain/entities/auth_session.dart';
import 'package:hesabi/features/auth/presentation/providers/auth_provider.dart';
import 'package:hesabi/features/home/presentation/pages/home_page.dart';
import 'package:hesabi/shared/layouts/app_shell.dart';

void main() {
  testWidgets('HesabiApp boots into the home page', (
    WidgetTester tester,
  ) async {
    // Create a test-authenticated state
    const testSession = AuthSession(
      userId: 'test-user-id',
      email: 'test@example.com',
    );
    
    const testAuthState = AuthState.authenticated(testSession);

    await tester.pumpWidget(
      ProviderContainer(
        overrides: <Override>[
          // Override the entire authProvider notifier to return a fixed state
          authProvider.overrideWith(
            (ref) => testAuthState as AuthNotifier,
          ),
        ],
        child: const ProviderScope(child: HesabiApp()),
      ),
    );

    // Allow the localization delegates to resolve before asserting.
    for (int i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(AppShell), findsOneWidget);
  });
}

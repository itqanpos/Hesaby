// test/widget_smoke_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/app/app.dart';
import 'package:hesabi/features/auth/domain/entities/auth_session.dart';
import 'package:hesabi/features/auth/presentation/providers/auth_provider.dart';
import 'package:hesabi/features/home/presentation/pages/home_page.dart';
import 'package:hesabi/shared/layouts/app_shell.dart';

class _AuthenticatedAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    return const AuthState.authenticated(
      AuthSession(
        userId: 'test-user-id',
        email: 'test@example.com',
      ),
    );
  }
}

void main() {
  testWidgets('HesabiApp boots into the home page', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        authProvider.overrideWith(() => _AuthenticatedAuthNotifier()),
      ],
    );
    addTearDown(container.dispose);

    // Initialize the overridden notifier before GoRouter evaluates redirects.
    expect(container.read(authProvider).isAuthenticated, isTrue);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const HesabiApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(AppShell), findsOneWidget);
  });
}

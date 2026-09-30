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
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authProvider.overrideWith(() => _AuthenticatedAuthNotifier()),
        ],
        child: const HesabiApp(),
      ),
    );

    for (int i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(AppShell), findsOneWidget);
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabi/app/app.dart';
import 'package:hesabi/app/router.dart';
import 'package:hesabi/features/auth/domain/entities/auth_session.dart';
import 'package:hesabi/features/auth/presentation/providers/auth_provider.dart';
import 'package:hesabi/features/home/presentation/pages/home_page.dart';

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
          appRouterProvider.overrideWith((ref) {
            final router = GoRouter(
              initialLocation: AppRouter.homePath,
              routes: <RouteBase>[
                GoRoute(
                  path: AppRouter.homePath,
                  name: AppRouter.homeName,
                  builder: (context, state) => const HomePage(),
                ),
              ],
            );

            ref.listen<AuthState>(authProvider, (previous, next) {
              if (previous?.status != next.status) {
                router.refresh();
              }
            });

            ref.onDispose(router.dispose);
            return router;
          }),
        ],
        child: const HesabiApp(),
      ),
    );

    // انتظار اكتمال جميع عمليات التوجيه وبناء الشاشات
    await tester.pumpAndSettle();

    expect(find.byType(HomePage), findsOneWidget);
  });
}

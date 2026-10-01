import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; 
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// 🔴 هام: قم بتغيير هذا المسار ليتطابق تماماً مع مسار AppLocalizations في تطبيقك!
// يمكنك نسخه من ملف lib/app/app.dart
import 'package:hesabi/l10n/app_localizations.dart'; // <--- ضع الاستيراد الصحيح هنا

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

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authProvider.overrideWith(() => _AuthenticatedAuthNotifier()),
          appRouterProvider.overrideWithValue(router),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          // تم إزالة const من القائمة لحل خطأ (non_constant_list_element)
          localizationsDelegates: [
            AppLocalizations.delegate, 
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('ar'), 
            Locale('en'),
          ],
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(HomePage), findsOneWidget);
  });
}

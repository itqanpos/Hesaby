import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; // إضافة استيراد مكتبة اللغات
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// تأكد من مسار استيراد AppLocalizations الخاص بمشروعك (هذا هو المسار الافتراضي غالباً)
import 'package:flutter_gen/gen_l10n/app_localizations.dart'; 

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
          // إضافة إعدادات الترجمة المطابقة لما في تطبيقك الأصلي
          localizationsDelegates: const [
            AppLocalizations.delegate, 
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('ar'), // أو اللغات التي يدعمها تطبيقك
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

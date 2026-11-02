// test/widget_smoke_test.dart

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/app/app.dart';
import 'package:hesabi/data/local/app_database.dart';
import 'package:hesabi/data/local/sync/sync_service.dart';
import 'package:hesabi/features/auth/presentation/pages/login_page.dart';
import 'package:hesabi/shared/layouts/app_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// نسخة وهمية من SyncService لاستخدامها في الاختبارات.
/// تقوم بتجاوز دالة التهيئة لمنع محاولة الاتصال بالشبكة أو قراءة الأجهزة.
class TestSyncService extends SyncService {
  TestSyncService(AppDatabase db, SupabaseClient supabase)
      : super(db, supabase);

  @override
  void _init() {
    // لا تفعل شيئاً في بيئة الاختبار
  }
}

/// Smoke test: verifies that the application boots without framework or
/// provider errors and settles on the screen produced by the current router
/// configuration for an unauthenticated session.
void main() {
  testWidgets(
    'HesabiApp boots without errors and lands on the login page',
    (WidgetTester tester) async {
      // ✅ 1. تهيئة قاعدة بيانات وهمية في الذاكرة
      final AppDatabase db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      // ✅ 2. تهيئة عميل Supabase وهمي (لا يتصل بالشبكة)
      final SupabaseClient dummySupabase = SupabaseClient(
        'https://dummy.supabase.co',
        'dummy_key',
      );

      await tester.pumpWidget(
        ProviderScope(
          // ✅ 3. تجاوز المزودات (Overrides) لمنع أي اتصال بالشبكة
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            syncServiceProvider.overrideWith(
              (ref) => TestSyncService(db, dummySupabase),
            ),
          ],
          child: const HesabiApp(),
        ),
      );

      // Give the router enough frames to resolve the initial redirect
      // chain (unknown -> /loading -> unauthenticated -> /login).
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

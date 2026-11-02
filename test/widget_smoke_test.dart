// test/widget_smoke_test.dart

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/app/app.dart';
import 'package:hesabi/data/local/app_database.dart';
import 'package:hesabi/data/local/sync/sync_service.dart';
import 'package:hesabi/features/auth/presentation/pages/login_page.dart';
import 'package:hesabi/shared/layouts/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    // ✅ 1. تهيئة SharedPreferences بشكل وهمي لتجنب أخطاء المنصة
    SharedPreferences.setMockInitialValues({});
    
    // ✅ 2. تهيئة Supabase بشكل وهمي مع تعطيل المؤقت (Auto Refresh)
    await Supabase.initialize(
      url: 'https://dummy.supabase.co',
      publishableKey: 'dummy_key', // ✅ استخدام publishableKey بدلاً من anonKey
      authOptions: const FlutterAuthClientOptions( // ✅ استخدام FlutterAuthClientOptions
        autoRefreshToken: false,
      ),
    );
  });

  testWidgets(
    'HesabiApp boots without errors and lands on the login page',
    (WidgetTester tester) async {
      // ✅ 3. استخدام قاعدة بيانات في الذاكرة
      final AppDatabase db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            // ✅ 4. استخدام خدمة مزامنة وهمية لا تتصل بالشبكة
            syncServiceProvider.overrideWith((ref) => FakeSyncService()),
          ],
          child: const HesabiApp(),
        ),
      );

      // Give the router enough frames to resolve the initial redirect chain
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

/// ✅ كلاس وهمي يطبق واجهة SyncService بدون أي عمليات شبكة أو مؤقتات
class FakeSyncService implements SyncService {
  @override
  Stream<SyncStatus> get statusStream => const Stream.empty();

  @override
  SyncStatus get currentStatus => SyncStatus.idle;

  @override
  Future<void> processOutbox() async {}

  @override
  void dispose() {}
}

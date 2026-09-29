// test/app_config_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/app/config/app_config.dart';

void main() {
  group('AppConfig', () {
    test('fromEnvironment falls back to empty credentials in development', () {
      final AppConfig config = AppConfig.fromEnvironment();

      expect(config.supabaseUrl, isEmpty);
      expect(config.supabaseAnonKey, isEmpty);
      expect(config.environment, AppEnvironment.development);
      expect(config.isDevelopment, isTrue);
      expect(config.isSupabaseConfigured, isFalse);
    });

    test('isSupabaseConfigured requires both url and key', () {
      const AppConfig complete = AppConfig(
        supabaseUrl: 'https://example.supabase.co',
        supabaseAnonKey: 'public-anon-key',
        environment: AppEnvironment.production,
      );
      expect(complete.isSupabaseConfigured, isTrue);
      expect(complete.isProduction, isTrue);
      expect(complete.isDevelopment, isFalse);

      const AppConfig missingKey = AppConfig(
        supabaseUrl: 'https://example.supabase.co',
        supabaseAnonKey: '',
        environment: AppEnvironment.staging,
      );
      expect(missingKey.isSupabaseConfigured, isFalse);

      const AppConfig missingUrl = AppConfig(
        supabaseUrl: '   ',
        supabaseAnonKey: 'public-anon-key',
        environment: AppEnvironment.staging,
      );
      expect(missingUrl.isSupabaseConfigured, isFalse);
    });

    test('environment is exposed through AppEnvironment', () {
      const AppConfig config = AppConfig(
        supabaseUrl: '',
        supabaseAnonKey: '',
        environment: AppEnvironment.staging,
      );

      expect(config.environment.name, 'staging');
      expect(config.isStaging, isTrue);
      expect(config.isProduction, isFalse);
    });
  });
}

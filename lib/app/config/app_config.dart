// lib/app/config/app_config.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The environment a build targets.
enum AppEnvironment { development, staging, production }

/// Immutable, compile-time configuration for the HESABI application.
///
/// Values are injected at build time so that no credential is ever committed:
///
/// ```sh
/// flutter run \
///   --dart-define=APP_ENV=development \
///   --dart-define=SUPABASE_URL=https://<project>.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=<anon-key>
/// ```
///
/// Only the public `anon` / publishable key may be shipped to a client.
/// A `service_role` or secret key must never be used here.
@immutable
class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.environment,
  });

  /// Reads the configuration injected through `--dart-define`.
  factory AppConfig.fromEnvironment() {
    return AppConfig(
      supabaseUrl: _rawSupabaseUrl,
      supabaseAnonKey: _rawSupabaseAnonKey,
      environment: _parseEnvironment(_rawAppEnv),
    );
  }

  static const String _rawSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _rawSupabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );
  static const String _rawAppEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  /// Public URL of the Supabase project.
  final String supabaseUrl;

  /// Public (anon / publishable) key of the Supabase project.
  final String supabaseAnonKey;

  /// Environment this build targets.
  final AppEnvironment environment;

  bool get isDevelopment => environment == AppEnvironment.development;

  bool get isStaging => environment == AppEnvironment.staging;

  bool get isProduction => environment == AppEnvironment.production;

  /// `true` when both Supabase values were supplied at build time.
  bool get isSupabaseConfigured =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  static AppEnvironment _parseEnvironment(String rawValue) {
    switch (rawValue.trim().toLowerCase()) {
      case 'production':
      case 'prod':
        return AppEnvironment.production;
      case 'staging':
      case 'stage':
        return AppEnvironment.staging;
      default:
        return AppEnvironment.development;
    }
  }

  @override
  String toString() =>
      'AppConfig(environment: ${environment.name}, '
      'supabaseConfigured: $isSupabaseConfigured)';
}

/// The active application configuration.
///
/// Overridden in `main()` with the instance created during bootstrap.
final Provider<AppConfig> appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

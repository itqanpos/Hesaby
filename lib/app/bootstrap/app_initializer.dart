// lib/app/bootstrap/app_initializer.dart

import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/error_handler.dart';
import '../../core/utils/logger.dart';
import '../config/app_config.dart';
import '../config/app_constants.dart';

abstract final class AppInitializer {
  static Future<void> initialize(AppConfig config) async {
    WidgetsFlutterBinding.ensureInitialized();

    AppLogger.configure(verbose: config.isDevelopment);

    await initializeDateFormatting(AppConstants.defaultLocaleTag);

    _installErrorHandlers();

    await _initializeSupabase(config);

    AppLogger.info(
      'Hesabi initialised (environment: ${config.environment.name}, '
      'supabaseConfigured: ${config.isSupabaseConfigured}).',
    );
  }

  static void _installErrorHandlers() {
    FlutterError.onError = ErrorHandler.handleFlutterError;
    WidgetsBinding.instance.platformDispatcher.onError =
        ErrorHandler.handlePlatformError;
  }

  static Future<void> _initializeSupabase(AppConfig config) async {
    if (!config.isSupabaseConfigured) {
      AppLogger.warning(
        'Supabase credentials were not provided at build time. '
        'Skipping Supabase initialisation.',
      );
      return;
    }

    try {
      await Supabase.initialize(
        url: config.supabaseUrl,
        publishableKey: config.supabaseAnonKey,
        debug: config.isDevelopment,
      );
      AppLogger.info('Supabase client initialised.');
    } on Object catch (error, stackTrace) {
      ErrorHandler.handle(
        error,
        stackTrace,
        source: 'AppInitializer._initializeSupabase',
      );
    }
  }
}

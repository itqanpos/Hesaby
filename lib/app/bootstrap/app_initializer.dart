// lib/app/bootstrap/app_initializer.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/error_handler.dart';
import '../../core/utils/logger.dart';
import '../config/app_config.dart';
import '../config/app_constants.dart';

/// Boots the HESABI foundation exactly once, before the first frame.
///
/// This phase prepares the infrastructure only. No authentication, no
/// database access and no business logic happens here.
abstract final class AppInitializer {
  /// Runs the bootstrap sequence.
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
        anonKey: config.supabaseAnonKey,
        debug: config.isDevelopment,
      );
      AppLogger.info('Supabase client initialised.');
    } on Object catch (error, stackTrace) {
      // A backend that is temporarily unreachable must never prevent the
      // application from starting.
      ErrorHandler.handle(
        error,
        stackTrace,
        source: 'AppInitializer._initializeSupabase',
      );
    }
  }
}

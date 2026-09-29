// lib/core/errors/error_handler.dart
import 'package:flutter/foundation.dart';

import '../utils/logger.dart';
import 'app_exception.dart';
import 'failure.dart';

/// Central translation point between thrown errors and safe [Failure] values.
abstract final class ErrorHandler {
  /// Logs [error] and converts it into a [Failure].
  static Failure handle(
    Object error,
    StackTrace stackTrace, {
    String? source,
  }) {
    AppLogger.error(
      source == null ? 'Unhandled error' : 'Error in $source',
      error,
      stackTrace,
    );
    return toFailure(error);
  }

  /// Converts any thrown object into a [Failure] without logging.
  static Failure toFailure(Object error) => switch (error) {
        Failure() => error,
        ConfigException() => const Failure.config(),
        NetworkException() => const Failure.network(),
        StorageException() => const Failure.storage(),
        AppException() => const Failure.unexpected(),
        _ => const Failure.unexpected(),
      };

  /// Handler installed on [FlutterError.onError].
  static void handleFlutterError(FlutterErrorDetails details) {
    AppLogger.error(
      'Flutter framework error',
      details.exception,
      details.stack,
    );

    if (!kReleaseMode) {
      FlutterError.presentError(details);
    }
  }

  /// Handler installed on `PlatformDispatcher.onError`.
  ///
  /// Returning `true` marks the error as handled so the platform does not
  /// terminate the isolate.
  static bool handlePlatformError(Object error, StackTrace stackTrace) {
    handle(error, stackTrace, source: 'PlatformDispatcher');
    return true;
  }
}

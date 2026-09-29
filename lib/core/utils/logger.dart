// lib/core/utils/logger.dart
import 'package:logger/logger.dart';

/// Application-wide logging facade.
///
/// Application code must never call `print` directly. Routing every log
/// statement through this facade keeps the log destination swappable.
abstract final class AppLogger {
  static final LogPrinter _printer = PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 100,
    colors: false,
    printEmojis: false,
  );

  static Logger _logger = Logger(printer: _printer, level: Level.debug);

  /// Enables verbose output when [verbose] is `true`.
  static void configure({required bool verbose}) {
    _logger = Logger(
      printer: _printer,
      level: verbose ? Level.debug : Level.warning,
    );
  }

  static void debug(String message) => _logger.d(message);

  static void info(String message) => _logger.i(message);

  static void warning(String message) => _logger.w(message);

  static void error(
    String message, [
    Object? cause,
    StackTrace? stackTrace,
  ]) => _logger.e(message, error: cause, stackTrace: stackTrace);
}

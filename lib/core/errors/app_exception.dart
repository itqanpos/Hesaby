// lib/core/errors/app_exception.dart
import 'package:flutter/foundation.dart';

/// Base type for every exception raised by HESABI's own code.
@immutable
sealed class AppException implements Exception {
  const AppException({required this.message, this.cause, this.stackTrace});

  /// Developer-facing description. Never shown to end users verbatim.
  final String message;

  /// The original error, when this exception wraps another one.
  final Object? cause;

  /// The original stack trace, when available.
  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType: $message';
}

/// Raised when the application is misconfigured.
final class ConfigException extends AppException {
  const ConfigException({required super.message, super.cause, super.stackTrace});
}

/// Raised when a network operation cannot be completed.
final class NetworkException extends AppException {
  const NetworkException({required super.message, super.cause, super.stackTrace});
}

/// Raised when a persistence operation fails.
final class StorageException extends AppException {
  const StorageException({required super.message, super.cause, super.stackTrace});
}

/// Raised for errors that do not fit any specific category.
final class UnexpectedException extends AppException {
  const UnexpectedException({
    required super.message,
    super.cause,
    super.stackTrace,
  });
}

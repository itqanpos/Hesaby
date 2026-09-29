// lib/core/errors/failure.dart
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Stable, machine-readable identifiers for [Failure] instances.
///
/// The presentation layer maps these codes to localized messages, so raw
/// backend errors are never surfaced to the user.
abstract final class FailureCodes {
  static const String unexpected = 'unexpected';
  static const String network = 'network';
  static const String storage = 'storage';
  static const String config = 'config';
}

/// A safe, user-presentable description of something that went wrong.
@immutable
class Failure extends Equatable {
  const Failure({required this.code, this.message});

  const Failure.unexpected()
      : code = FailureCodes.unexpected,
        message = null;

  const Failure.network()
      : code = FailureCodes.network,
        message = null;

  const Failure.storage()
      : code = FailureCodes.storage,
        message = null;

  const Failure.config()
      : code = FailureCodes.config,
        message = null;

  /// Machine-readable failure identifier.
  final String code;

  /// Optional developer-facing detail. Never displayed directly.
  final String? message;

  @override
  List<Object?> get props => <Object?>[code, message];

  @override
  String toString() => 'Failure(code: $code, message: $message)';
}

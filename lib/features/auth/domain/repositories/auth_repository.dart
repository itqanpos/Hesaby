// lib/features/auth/domain/repositories/auth_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/auth_session.dart';

/// Categories of authentication failures that the presentation layer can
/// safely translate into localized user messages.
///
/// The domain deliberately avoids leaking backend-specific error codes or
/// raw messages. The data layer is responsible for mapping backend errors
/// into one of these categories.
enum AuthFailureType {
  /// The supplied email / password combination was rejected.
  invalidCredentials,

  /// The account exists but its email has not been confirmed yet.
  emailNotConfirmed,

  /// No account is associated with the supplied identifier.
  userNotFound,

  /// The backend is rate-limiting authentication attempts.
  tooManyRequests,

  /// The request could not reach the backend.
  network,

  /// Any other unclassified authentication failure.
  unknown,
}

/// Domain-level exception raised by [AuthRepository] operations.
///
/// Carries a safe [AuthFailureType] rather than a raw backend message, so
/// the presentation layer can produce localized, user-friendly errors.
@immutable
class AuthException extends Equatable implements Exception {
  const AuthException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  /// Safe, categorized reason for the failure.
  final AuthFailureType type;

  /// Original error, kept for logging. Never displayed to end users.
  final Object? cause;

  /// Original stack trace, kept for logging.
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'AuthException(type: ${type.name})';
}

/// Contract for authentication operations.
///
/// This abstraction lives in the Domain layer and must remain free of any
/// dependency on Supabase, Flutter widgets, or persistence details. The data
/// layer provides the concrete implementation.
abstract interface class AuthRepository {
  /// Emits the current session on every authentication state change.
  ///
  /// Emits `null` when the user is signed out. The stream is expected to
  /// emit the current state immediately upon subscription.
  Stream<AuthSession?> get authStateChanges;

  /// Returns the session restored from persistent storage, if any.
  ///
  /// Returns `null` when no session is available.
  Future<AuthSession?> getCurrentSession();

  /// Authenticates a user with an email and password.
  ///
  /// Throws [AuthException] when authentication fails.
  Future<AuthSession> login({
    required String email,
    required String password,
  });

  /// Signs the current user out.
  ///
  /// Throws [AuthException] when the sign-out request fails.
  Future<void> logout();
}

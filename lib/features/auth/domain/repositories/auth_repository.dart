// lib/features/auth/domain/repositories/auth_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/auth_session.dart';

/// Categories of authentication failures that the presentation layer can
/// safely translate into localized user messages.
enum AuthFailureType {
  /// The supplied email / password combination was rejected.
  invalidCredentials,

  /// The account exists but its email has not been confirmed yet.
  emailNotConfirmed,

  /// No account is associated with the supplied identifier.
  userNotFound,

  /// The backend is rate-limiting authentication attempts.
  tooManyRequests,

  /// The supplied password does not meet the backend's minimum strength.
  weakPassword,

  /// The request could not reach the backend.
  network,

  /// Any other unclassified authentication failure.
  unknown,
}

/// Domain-level exception raised by [AuthRepository] operations.
@immutable
class AuthException extends Equatable implements Exception {
  const AuthException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  final AuthFailureType type;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'AuthException(type: ${type.name})';
}

/// Contract for authentication operations.
abstract interface class AuthRepository {
  /// Emits the current session on every authentication state change.
  Stream<AuthSession?> get authStateChanges;

  /// Returns the session restored from persistent storage, if any.
  Future<AuthSession?> getCurrentSession();

  /// Authenticates a user with an email and password.
  Future<AuthSession> login({
    required String email,
    required String password,
  });

  /// Signs the current user out.
  Future<void> logout();

  /// Changes the password of the currently authenticated user.
  ///
  /// Supabase enforces a minimum strength policy; a weak password is
  /// surfaced as [AuthFailureType.weakPassword]. The current session must
  /// be valid, otherwise the request fails with
  /// [AuthFailureType.invalidCredentials].
  Future<void> changePassword({required String newPassword});
}

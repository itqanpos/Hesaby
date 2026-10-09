// lib/features/auth/domain/repositories/auth_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/auth_session.dart';

/// Categories of authentication failures that the presentation layer can
/// safely translate into localized user messages.
enum AuthFailureType {
  invalidCredentials,
  emailNotConfirmed,
  userNotFound,
  tooManyRequests,
  weakPassword,
  emailAlreadyInUse,
  network,
  unknown,
}

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
  Stream<AuthSession?> get authStateChanges;
  Future<AuthSession?> getCurrentSession();
  Future<AuthSession> login({
    required String email,
    required String password,
  });
  Future<void> logout();
  Future<void> changePassword({required String newPassword});

  /// Registers a new user and, when [companyName] is provided, bootstraps
  /// a company owned by the new user.
  ///
  /// * When Supabase is configured to require email confirmation, the
  ///   returned session may be `null`; in that case the caller should
  ///   show a "check your email" message.
  /// * When email confirmation is disabled, the user is signed in
  ///   immediately and a session is returned.
  Future<AuthSession?> signUp({
    required String email,
    required String password,
    String? fullName,
    String? companyName,
  });

  /// Starts the Google OAuth flow.
  ///
  /// On web the current page is redirected to Google and back; on mobile
  /// the platform browser is opened (deep-link handling is configured
  /// separately). The returned Future completes when the browser step is
  /// finished — the actual session arrives through [authStateChanges].
  ///
  /// Throws [AuthException] when the flow cannot be launched. A user who
  /// simply closes the browser without completing the flow receives no
  /// session, and no error surfaces here — the app remains in its
  /// previous authentication state.
  Future<void> signInWithGoogle();
}

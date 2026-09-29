// lib/features/auth/domain/usecases/login.dart

import '../entities/auth_session.dart';
import '../repositories/auth_repository.dart';

/// Use case: authenticate a user with an email and a password.
///
/// Normalises the email before delegating to [AuthRepository]. It performs
/// no field validation and produces no UI messages; input validation belongs
/// to the presentation layer, where errors can be localized and shown
/// immediately. Any [AuthException] thrown by the repository is propagated
/// unchanged so that the caller can map its [AuthFailureType] to a safe,
/// localized message.
class Login {
  const Login(this._repository);

  final AuthRepository _repository;

  /// Executes the login operation and returns the authenticated session.
  ///
  /// Throws [AuthException] when authentication fails.
  Future<AuthSession> call({
    required String email,
    required String password,
  }) {
    final String normalizedEmail = email.trim().toLowerCase();
    return _repository.login(email: normalizedEmail, password: password);
  }
}

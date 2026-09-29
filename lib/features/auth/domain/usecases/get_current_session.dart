// lib/features/auth/domain/usecases/get_current_session.dart

import '../entities/auth_session.dart';
import '../repositories/auth_repository.dart';

/// Use case: read the session currently held by the application.
///
/// Used during session restoration at startup and whenever the presentation
/// layer needs the current authenticated session without subscribing to
/// [AuthRepository.authStateChanges].
///
/// Returns `null` when no session is available. Any [AuthException] raised
/// by the repository is propagated unchanged so the caller can decide how
/// to react.
class GetCurrentSession {
  const GetCurrentSession(this._repository);

  final AuthRepository _repository;

  /// Returns the current [AuthSession], or `null` when the user is signed
  /// out.
  Future<AuthSession?> call() => _repository.getCurrentSession();
}

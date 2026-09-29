// lib/features/auth/domain/usecases/logout.dart

import '../repositories/auth_repository.dart';

/// Use case: sign the current user out.
///
/// Delegates to [AuthRepository.logout]. Any [AuthException] raised by the
/// repository is propagated unchanged so that the caller can decide how to
/// present the failure. This use case holds no state and produces no side
/// effects beyond the repository call.
class Logout {
  const Logout(this._repository);

  final AuthRepository _repository;

  /// Executes the logout operation.
  ///
  /// Throws [AuthException] when the sign-out request fails.
  Future<void> call() => _repository.logout();
}

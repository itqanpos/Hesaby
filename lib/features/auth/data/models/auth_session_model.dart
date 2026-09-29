// lib/features/auth/data/models/auth_session_model.dart

import 'package:equatable/equatable.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Session, User;

import '../../domain/entities/auth_session.dart';

/// Data-layer representation of an authenticated session.
///
/// This is the only file within the auth feature that is permitted to
/// reference Supabase session types. The Domain layer never sees these
/// types: they are translated into a pure [AuthSession] entity via
/// [toEntity] before crossing the layer boundary.
///
/// The model intentionally does not extend [AuthSession]. Extending would
/// make `Equatable` compare `runtimeType`, which would cause a model and
/// its corresponding entity to be considered unequal despite holding the
/// same values. An explicit `toEntity` mapping keeps the boundary clean
/// and the equality semantics predictable.
class AuthSessionModel extends Equatable {
  const AuthSessionModel({
    required this.userId,
    required this.email,
  });

  /// Builds a model from a Supabase [Session].
  factory AuthSessionModel.fromSupabaseSession(Session session) {
    return AuthSessionModel.fromSupabaseUser(session.user);
  }

  /// Builds a model from a Supabase [User].
  ///
  /// Falls back to an empty string when the backend does not expose an
  /// email for the user. In the Phase 1 email/password flow this should not
  /// happen, but the mapping stays defensive so it never throws for a
  /// nullable field.
  factory AuthSessionModel.fromSupabaseUser(User user) {
    return AuthSessionModel(
      userId: user.id,
      email: user.email ?? '',
    );
  }

  /// Unique identifier of the authenticated user.
  final String userId;

  /// Email address of the authenticated user, or an empty string when the
  /// backend did not provide one.
  final String email;

  /// Maps this data-layer model into the pure Domain entity.
  AuthSession toEntity() => AuthSession(userId: userId, email: email);

  @override
  List<Object?> get props => <Object?>[userId, email];

  @override
  String toString() => 'AuthSessionModel(userId: $userId, email: $email)';
}

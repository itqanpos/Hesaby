// lib/features/auth/domain/entities/auth_session.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Represents the currently authenticated user's session.
///
/// This is a pure Domain entity. It knows nothing about Supabase, Flutter,
/// or any specific backend. The data layer is responsible for mapping the
/// backend session into this entity.
///
/// Phase 1 scope only: it intentionally exposes just the minimum identity
/// information required to authenticate a user. Concepts such as company,
/// branch, role, or permissions belong to later phases and must not be added
/// here.
@immutable
class AuthSession extends Equatable {
  const AuthSession({
    required this.userId,
    required this.email,
  });

  /// Unique identifier of the authenticated user.
  ///
  /// Matches the backend's user identifier (e.g. Supabase `auth.users.id`).
  final String userId;

  /// Email address associated with the authenticated user.
  final String email;

  /// Whether the entity holds a non-empty user identifier.
  ///
  /// Useful for defensive checks in the presentation layer without exposing
  /// backend-specific notions of "valid session".
  bool get hasValidIdentity => userId.trim().isNotEmpty;

  @override
  List<Object?> get props => <Object?>[userId, email];

  @override
  String toString() => 'AuthSession(userId: $userId, email: $email)';
}

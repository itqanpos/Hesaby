// lib/features/settings/domain/repositories/user_profile_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/user_profile.dart';

/// Categories of user-profile failures that the presentation layer can
/// safely translate into localized user messages.
enum UserProfileFailureType {
  /// The request could not reach the backend.
  network,

  /// The backend rejected the request as unauthorised.
  unauthorized,

  /// No profile row exists for the current user.
  notFound,

  /// The backend rejected the input (typically a check-constraint failure).
  invalidInput,

  /// The response could not be interpreted.
  invalidResponse,

  /// Any other unclassified failure.
  unknown,
}

/// Domain-level exception raised by [UserProfileRepository] operations.
@immutable
class UserProfileException extends Equatable implements Exception {
  const UserProfileException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  final UserProfileFailureType type;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'UserProfileException(type: ${type.name})';
}

/// Contract for reading and updating the current user's profile.
///
/// All access is restricted by Row Level Security to the authenticated
/// user's own row: the repository never accepts a `userId`.
abstract interface class UserProfileRepository {
  /// Reads the current user's profile row.
  ///
  /// Throws [UserProfileException] when the request fails. A missing row
  /// (which should not happen, thanks to the database trigger that
  /// provisions one on signup) is surfaced as
  /// [UserProfileFailureType.notFound].
  Future<UserProfile> getMyProfile();

  /// Updates the current user's profile and returns the updated row.
  ///
  /// A `null` value for [fullName] or [phone] clears the column. Passing
  /// `null` for a field means "clear it" (there is no partial update
  /// semantics here, because the profile page always submits the full
  /// form).
  Future<UserProfile> updateMyProfile({
    required String? fullName,
    required String? phone,
  });
}

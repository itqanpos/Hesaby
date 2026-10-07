// lib/features/settings/domain/entities/user_profile.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Per-user profile data, one-to-one with `auth.users`.
///
/// Deliberately separate from `AuthSession` (which carries authentication
/// identity only: user id + email). This entity carries the application
/// data stored in `public.profiles` and can evolve independently of the
/// authentication contract.
@immutable
class UserProfile extends Equatable {
  const UserProfile({
    required this.userId,
    required this.createdAt,
    required this.updatedAt,
    this.fullName,
    this.phone,
  });

  /// Identifier matching `auth.users.id`.
  final String userId;

  /// Display name. `null` until the user completes their profile.
  final String? fullName;

  /// Optional contact phone number.
  final String? phone;

  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  List<Object?> get props => <Object?>[
        userId,
        fullName,
        phone,
        createdAt,
        updatedAt,
      ];

  UserProfile copyWith({
    String? fullName,
    bool clearFullName = false,
    String? phone,
    bool clearPhone = false,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      userId: userId,
      fullName:
          clearFullName ? null : (fullName ?? this.fullName),
      phone: clearPhone ? null : (phone ?? this.phone),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'UserProfile(userId: $userId, fullName: $fullName, hasPhone: ${phone != null})';
}

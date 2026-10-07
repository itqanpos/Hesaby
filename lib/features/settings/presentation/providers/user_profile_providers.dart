// lib/features/settings/presentation/providers/user_profile_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/repositories/user_profile_repository_impl.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/user_profile_repository.dart';

/// The application's user-profile repository.
final Provider<UserProfileRepository> userProfileRepositoryProvider =
    Provider<UserProfileRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return UserProfileRepositoryImpl(client);
});

/// Provides the current user's profile.
///
/// The notifier watches `authProvider`; when the user signs in or out, the
/// profile is automatically re-fetched (or reset to `null`).
///
/// When the user is not authenticated, `build()` returns `null` so the UI
/// can distinguish "no user" from "loading".
class UserProfileNotifier extends AsyncNotifier<UserProfile?> {
  bool _isDisposed = false;

  @override
  Future<UserProfile?> build() async {
    _isDisposed = false;
    ref.onDispose(() => _isDisposed = true);

    final bool isAuthenticated = ref.watch(
      authProvider.select((AuthState s) => s.isAuthenticated),
    );

    if (!isAuthenticated) {
      return null;
    }

    return ref.read(userProfileRepositoryProvider).getMyProfile();
  }

  /// Updates the current user's profile and refreshes the state.
  ///
  /// Throws [UserProfileException] on failure. On success the fresh entity
  /// is published to `state` directly.
  Future<UserProfile> updateProfile({
    required String? fullName,
    required String? phone,
  }) async {
    final UserProfile? previous = state.valueOrNull;
    if (previous == null) {
      throw const UserProfileException(
        type: UserProfileFailureType.unauthorized,
        cause: 'No authenticated profile to update.',
      );
    }

    final UserProfile updated = await ref
        .read(userProfileRepositoryProvider)
        .updateMyProfile(fullName: fullName, phone: phone);

    if (!_isDisposed) {
      state = AsyncData<UserProfile>(updated);
    }
    return updated;
  }

  /// Re-fetches the profile from the server.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

/// Provides the current user's profile, or `null` when unauthenticated.
final AsyncNotifierProvider<UserProfileNotifier, UserProfile?>
    userProfileProvider =
    AsyncNotifierProvider<UserProfileNotifier, UserProfile?>(
  UserProfileNotifier.new,
);

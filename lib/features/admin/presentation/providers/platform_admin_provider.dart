// lib/features/admin/presentation/providers/platform_admin_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/presentation/providers/user_profile_providers.dart';

/// Whether the signed-in user is a platform administrator.
///
/// Derived from `userProfileProvider`. Returns `false` while the profile is
/// loading or when the user is signed out — this is the safe default: the
/// admin UI entry points stay hidden until we can positively confirm access.
///
/// **Security note:** this is a UI convenience only. The authoritative check
/// lives in PostgreSQL (`is_platform_admin()` + RLS policies on `companies`
/// and `profiles`). Even if this provider were forced to `true` on the
/// client, no additional data would leak.
final Provider<bool> isPlatformAdminProvider = Provider<bool>((ref) {
  return ref.watch(userProfileProvider).valueOrNull?.isPlatformAdmin ?? false;
});

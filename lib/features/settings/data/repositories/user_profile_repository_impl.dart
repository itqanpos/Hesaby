// lib/features/settings/data/repositories/user_profile_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/user_profile_repository.dart';

/// Concrete implementation of [UserProfileRepository] backed by Supabase.
///
/// Talks directly to the `profiles` table. A separate datasource layer is
/// omitted on purpose: the surface is only two operations (read + update of
/// the current user's own row), so a datasource would add indirection
/// without value — same reasoning as `CompanySettingsRepositoryImpl`.
///
/// **Important:** every read and write is scoped to `auth.uid()` on the
/// client side as well as in the database. This is not a security measure
/// (RLS already enforces it) but a correctness one: a platform admin sees
/// every row through `profiles_platform_admin_select_all`, so an unfiltered
/// `maybeSingle()` would fail with "multiple rows returned". Scoping by
/// user id keeps the query result deterministic for every caller.
class UserProfileRepositoryImpl implements UserProfileRepository {
  const UserProfileRepositoryImpl(this._client);

  final supabase.SupabaseClient? _client;

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  @override
  Future<UserProfile> getMyProfile() async {
    try {
      final supabase.SupabaseClient client = _requireClient();

      final String? userId = client.auth.currentUser?.id;
      if (userId == null) {
        throw const UserProfileException(
          type: UserProfileFailureType.unauthorized,
          cause: 'No authenticated user.',
        );
      }

      // Filter by the current user id explicitly. RLS would return only
      // this row for a regular user, but a platform admin sees every row,
      // so `maybeSingle()` needs a deterministic single-row filter to
      // avoid throwing "multiple rows returned".
      final Map<String, dynamic>? row = await client
          .from('profiles')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (row == null) {
        throw const UserProfileException(
          type: UserProfileFailureType.notFound,
          cause: 'No profiles row for the current user.',
        );
      }

      return _fromMap(row);
    } on UserProfileException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getMyProfile');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'getMyProfile');
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getMyProfile');
    }
  }

  // ---------------------------------------------------------------------------
  // Update
  // ---------------------------------------------------------------------------

  @override
  Future<UserProfile> updateMyProfile({
    required String? fullName,
    required String? phone,
  }) async {
    try {
      final supabase.SupabaseClient client = _requireClient();

      final String? userId = client.auth.currentUser?.id;
      if (userId == null) {
        throw const UserProfileException(
          type: UserProfileFailureType.unauthorized,
          cause: 'No authenticated user.',
        );
      }

      final Map<String, dynamic> payload = <String, dynamic>{
        'full_name': fullName,
        'phone': phone,
      };

      // Same reasoning as [getMyProfile]: scope by user_id so the returned
      // row is exactly the current user's, regardless of the caller's
      // platform-admin status.
      final Map<String, dynamic>? row = await client
          .from('profiles')
          .update(payload)
          .eq('user_id', userId)
          .select()
          .maybeSingle();

      if (row == null) {
        throw const UserProfileException(
          type: UserProfileFailureType.notFound,
          cause: 'Update affected no rows.',
        );
      }

      return _fromMap(row);
    } on UserProfileException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'updateMyProfile');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'updateMyProfile');
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'updateMyProfile');
    }
  }

  // ---------------------------------------------------------------------------
  // Mapping
  // ---------------------------------------------------------------------------

  static UserProfile _fromMap(Map<String, dynamic> map) {
    return UserProfile(
      userId: _requireString(map, 'user_id'),
      fullName: _optionalString(map, 'full_name'),
      phone: _optionalString(map, 'phone'),
      createdAt: _requireTimestamp(map, 'created_at'),
      updatedAt: _requireTimestamp(map, 'updated_at'),
      isPlatformAdmin: _optionalBool(map, 'is_platform_admin') ?? false,
    );
  }

  static String _requireString(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException(
      'UserProfile: missing or invalid "$key".',
    );
  }

  static String? _optionalString(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) {
      return null;
    }
    if (value is String) {
      final String trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return value.toString();
  }

  static bool? _optionalBool(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final String lower = value.toLowerCase();
      if (lower == 'true' || lower == 't' || lower == '1') return true;
      if (lower == 'false' || lower == 'f' || lower == '0') return false;
    }
    return null;
  }

  static DateTime _requireTimestamp(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is DateTime) return value.toUtc();
    if (value is String && value.isNotEmpty) {
      final DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    throw FormatException(
      'UserProfile: "$key" is not a valid timestamp.',
    );
  }

  // ---------------------------------------------------------------------------
  // Client
  // ---------------------------------------------------------------------------

  supabase.SupabaseClient _requireClient() {
    final supabase.SupabaseClient? client = _client;
    if (client == null) {
      throw const UserProfileException(
        type: UserProfileFailureType.unknown,
        cause: 'Supabase client is not initialised.',
      );
    }
    return client;
  }
}

// ============================================================================
// Error mapping
// ============================================================================

UserProfileException _mapPostgrest(
  supabase.PostgrestException error,
  StackTrace stackTrace, {
  required String operation,
}) {
  final UserProfileFailureType type = _classifyPostgrest(error);

  AppLogger.warning(
    'UserProfile PostgREST error during "$operation" '
    'mapped to ${type.name} (code: ${error.code ?? 'n/a'}).',
  );

  return UserProfileException(
    type: type,
    cause: error,
    stackTrace: stackTrace,
  );
}

UserProfileException _mapAuth(
  supabase.AuthException error,
  StackTrace stackTrace, {
  required String operation,
}) {
  AppLogger.warning(
    'UserProfile auth error during "$operation" mapped to unauthorized.',
  );
  return UserProfileException(
    type: UserProfileFailureType.unauthorized,
    cause: error,
    stackTrace: stackTrace,
  );
}

UserProfileException _mapUnknown(
  Object error,
  StackTrace stackTrace, {
  required String operation,
}) {
  final UserProfileFailureType type = _looksLikeNetwork(error)
      ? UserProfileFailureType.network
      : UserProfileFailureType.unknown;

  AppLogger.error(
    'Unhandled user-profile error during "$operation" '
    '(runtimeType: ${error.runtimeType}, mapped: ${type.name}).',
    error,
    stackTrace,
  );

  return UserProfileException(
    type: type,
    cause: error,
    stackTrace: stackTrace,
  );
}

UserProfileFailureType _classifyPostgrest(
  supabase.PostgrestException error,
) {
  final String code = (error.code ?? '').toUpperCase();
  final String message = error.message.toLowerCase();
  final String full = error.toString().toLowerCase();

  if (code == '23514') {
    return UserProfileFailureType.invalidInput;
  }
  if (code == 'PGRST116') {
    return UserProfileFailureType.notFound;
  }
  if (code.startsWith('42501') || code.startsWith('28')) {
    return UserProfileFailureType.unauthorized;
  }
  if (code.startsWith('42')) {
    return UserProfileFailureType.invalidResponse;
  }

  if (message.contains('permission denied') ||
      message.contains('row level security') ||
      message.contains('jwt')) {
    return UserProfileFailureType.unauthorized;
  }

  if (full.contains('profiles_full_name_length') ||
      full.contains('profiles_phone_length')) {
    return UserProfileFailureType.invalidInput;
  }

  if (_messageLooksLikeNetwork(message)) {
    return UserProfileFailureType.network;
  }

  return UserProfileFailureType.unknown;
}

bool _looksLikeNetwork(Object error) =>
    _messageLooksLikeNetwork(error.toString().toLowerCase());

bool _messageLooksLikeNetwork(String value) {
  return value.contains('socket') ||
      value.contains('network') ||
      value.contains('connection') ||
      value.contains('timeout') ||
      value.contains('timed out') ||
      value.contains('unreachable') ||
      value.contains('failed host lookup') ||
      value.contains('clientexception');
}

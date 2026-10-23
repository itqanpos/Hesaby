// lib/features/settings/data/repositories/user_profile_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/user_profile_repository.dart';

class UserProfileRepositoryImpl implements UserProfileRepository {
  const UserProfileRepositoryImpl(this._client);

  final supabase.SupabaseClient? _client;

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

      // 1. محاولة جلب الملف الشخصي
      final Map<String, dynamic>? row = await client
          .from('profiles')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      // 2. إذا لم يوجد الملف، نقوم بإنشائه فوراً
      if (row == null) {
        AppLogger.warning('UserProfile not found. Auto-creating profile for $userId.');
        
        final Map<String, dynamic> newProfile = <String, dynamic>{
          'user_id': userId,
          'full_name': client.auth.currentUser?.userMetadata?['full_name'] ?? 'مستخدم جديد',
          'is_platform_admin': false,
        };

        final Map<String, dynamic> createdRow = await client
            .from('profiles')
            .insert(newProfile)
            .select()
            .single();

        return _fromMap(createdRow);
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
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('UserProfile: missing or invalid "$key".');
  }

  static String? _optionalString(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) return null;
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
    if (value == null) return DateTime.now().toUtc();
    
    if (value is DateTime) return value.toUtc();
    
    if (value is String && value.isNotEmpty) {
      DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();

      try {
        String normalized = value.trim();
        // ⬇️ تم إضافة الأقواس {} لحل مشكلة الـ Linter
        if (normalized.contains(' ')) {
          normalized = normalized.replaceFirst(' ', 'T');
        }
        if (normalized.endsWith('+00')) {
          normalized = normalized.replaceAll('+00', 'Z');
        } else if (normalized.endsWith('-00')) {
          normalized = normalized.replaceAll('-00', 'Z');
        }
        
        parsed = DateTime.tryParse(normalized);
        if (parsed != null) return parsed.toUtc();
      } catch (_) {}
    }
    return DateTime.now().toUtc();
  }

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

UserProfileException _mapPostgrest(supabase.PostgrestException error, StackTrace stackTrace, {required String operation}) {
  final UserProfileFailureType type = _classifyPostgrest(error);
  AppLogger.warning('UserProfile PostgREST error during "$operation" mapped to ${type.name}.');
  return UserProfileException(type: type, cause: error, stackTrace: stackTrace);
}

UserProfileException _mapAuth(supabase.AuthException error, StackTrace stackTrace, {required String operation}) {
  return UserProfileException(type: UserProfileFailureType.unauthorized, cause: error, stackTrace: stackTrace);
}

UserProfileException _mapUnknown(Object error, StackTrace stackTrace, {required String operation}) {
  final UserProfileFailureType type = _looksLikeNetwork(error) ? UserProfileFailureType.network : UserProfileFailureType.unknown;
  AppLogger.error('Unhandled user-profile error during "$operation".', error, stackTrace);
  return UserProfileException(type: type, cause: error, stackTrace: stackTrace);
}

UserProfileFailureType _classifyPostgrest(supabase.PostgrestException error) {
  final String code = (error.code ?? '').toUpperCase();
  final String message = error.message.toLowerCase();
  if (code == '23514') return UserProfileFailureType.invalidInput;
  if (code == 'PGRST116') return UserProfileFailureType.notFound;
  if (code.startsWith('42501') || code.startsWith('28')) return UserProfileFailureType.unauthorized;
  if (code.startsWith('42')) return UserProfileFailureType.invalidResponse;
  if (message.contains('permission denied') || message.contains('row level security')) return UserProfileFailureType.unauthorized;
  if (_messageLooksLikeNetwork(message)) return UserProfileFailureType.network;
  return UserProfileFailureType.unknown;
}

bool _looksLikeNetwork(Object error) => _messageLooksLikeNetwork(error.toString().toLowerCase());

bool _messageLooksLikeNetwork(String value) {
  return value.contains('socket') || value.contains('network') || value.contains('connection') || value.contains('timeout');
}

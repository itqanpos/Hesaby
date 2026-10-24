// lib/features/admin/data/services/admin_user_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

class AdminUserService {
  const AdminUserService(this._client);

  final SupabaseClient _client;

  Future<String> createUser({
    required String email,
    required String password,
    String? fullName,
  }) async {
    try {
      final FunctionResponse response = await _client.functions.invoke(
        'admin-create-user',
        body: <String, dynamic>{
          'email': email.trim().toLowerCase(),
          'password': password,
          if (fullName != null && fullName.trim().isNotEmpty)
            'fullName': fullName.trim(),
        },
      );

      if (response.status != 200) {
        throw AdminUserException(_extractError(response));
      }

      final Map<String, dynamic> data =
          (response.data as Map<dynamic, dynamic>).cast<String, dynamic>();
      final Object? id = data['user_id'];
      if (id is! String || id.isEmpty) {
        throw const AdminUserException('استجابة غير صالحة من الخادم.');
      }
      return id;
    } on AdminUserException {
      rethrow;
    } on FunctionException catch (error) {
      throw AdminUserException(
        _translateErrorDetails(error.details, error.reasonPhrase),
      );
    } on Object catch (error) {
      throw AdminUserException('تعذّر الاتصال بالخادم: $error');
    }
  }

  Future<void> updateUser({
    required String userId,
    String? email,
    String? password,
    String? fullName,
    bool? isPlatformAdmin,
    bool? isBanned, // ⬅️ تمت إضافة هذا المتغير
  }) async {
    try {
      final FunctionResponse response = await _client.functions.invoke(
        'admin-update-user',
        body: <String, dynamic>{
          'userId': userId,
          if (email != null && email.trim().isNotEmpty)
            'email': email.trim().toLowerCase(),
          if (password != null && password.isNotEmpty) 'password': password,
          if (fullName != null) 'fullName': fullName.trim(),
          if (isPlatformAdmin != null) 'isPlatformAdmin': isPlatformAdmin,
          if (isBanned != null) 'isBanned': isBanned, // ⬅️ تمرير المتغير للـ Edge Function
        },
      );

      if (response.status != 200) {
        throw AdminUserException(_extractError(response));
      }
    } on AdminUserException {
      rethrow;
    } on FunctionException catch (error) {
      throw AdminUserException(
        _translateErrorDetails(error.details, error.reasonPhrase),
      );
    } on Object catch (error) {
      throw AdminUserException('تعذّر الاتصال بالخادم: $error');
    }
  }

  static String _extractError(FunctionResponse response) {
    final Object? data = response.data;
    if (data is Map) {
      final Object? error = data['error'];
      if (error is String && error.isNotEmpty) {
        return _translateServerMessage(error);
      }
    }
    return 'تعذّر إتمام العملية (رمز ${response.status}).';
  }

  static String _translateErrorDetails(Object? details, String? reason) {
    if (details is Map) {
      final Object? error = details['error'];
      final Object? extra = details['details'];
      if (error is String) {
        final String base = _translateServerMessage(error);
        return extra == null ? base : '$base\n$extra';
      }
    }
    if (details is String && details.isNotEmpty) {
      return _translateServerMessage(details);
    }
    return reason ?? 'تعذّر إتمام العملية.';
  }

  static String _translateServerMessage(String raw) {
    final String lower = raw.toLowerCase();
    if (lower.contains('already') && lower.contains('registered')) {
      return 'هذا البريد مستخدم بالفعل.';
    }
    if (lower.contains('invalid email')) return 'بريد إلكتروني غير صالح.';
    if (lower.contains('password') && lower.contains('6')) {
      return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل.';
    }
    if (lower.contains('forbidden')) return 'غير مصرّح لهذه العملية.';
    if (lower.contains('invalid session')) {
      return 'انتهت الجلسة. سجّل الدخول مجددًا.';
    }
    if (lower.contains('non-2xx')) {
      return 'تعذّر تنفيذ الطلب على الخادم.';
    }
    return raw;
  }
}

class AdminUserException implements Exception {
  const AdminUserException(this.message);
  final String message;

  @override
  String toString() => message;
}

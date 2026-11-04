// lib/features/admin/data/services/admin_user_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

class AdminUserException implements Exception {
  final String message;
  AdminUserException(this.message);
  @override
  String toString() => message;
}

class AdminUserService {
  final SupabaseClient _client;

  AdminUserService(this._client);

  Future<String?> createUser({
    required String email,
    required String password,
    String? fullName,
    bool isPlatformAdmin = false,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'admin-create-user',
        body: {
          'email': email,
          'password': password,
          'fullName': fullName,
          'isPlatformAdmin': isPlatformAdmin,
        },
      );

      if (response.status != 200) {
        final errorMsg = response.data?['error'] ?? 'حدث خطأ أثناء إنشاء المستخدم';
        throw AdminUserException(errorMsg);
      }

      return response.data?['user_id'] as String?;
    } on FunctionException catch (e) {
      throw AdminUserException(e.details?['error'] ?? 'فشل الاتصال بالخادم');
    } catch (e) {
      throw AdminUserException(e.toString());
    }
  }

  Future<void> updateUser({
    required String userId,
    String? email,
    String? password,
    String? fullName,
    required bool isPlatformAdmin,
    required bool isBanned,
  }) async {
    try {
      final payload = <String, dynamic>{
        'userId': userId,
        'isPlatformAdmin': isPlatformAdmin,
        'isBanned': isBanned,
      };
      if (email != null && email.isNotEmpty) payload['email'] = email;
      if (password != null && password.isNotEmpty) payload['password'] = password;
      if (fullName != null) payload['fullName'] = fullName;

      final response = await _client.functions.invoke(
        'admin-update-user',
        body: payload,
      );

      if (response.status != 200) {
        final errorMsg = response.data?['error'] ?? 'حدث خطأ أثناء تحديث المستخدم';
        throw AdminUserException(errorMsg);
      }
    } on FunctionException catch (e) {
      throw AdminUserException(e.details?['error'] ?? 'فشل الاتصال بالخادم');
    } catch (e) {
      throw AdminUserException(e.toString());
    }
  }
}

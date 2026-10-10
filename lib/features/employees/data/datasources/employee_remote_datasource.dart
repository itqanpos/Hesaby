// lib/features/employees/data/datasources/employee_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../domain/repositories/employee_repository.dart';

/// Supabase access for the employees feature.
///
/// The only file in this feature that talks to Supabase directly. RLS
/// enforces tenant isolation via `has_permission(...)`.
class EmployeeRemoteDataSource {
  const EmployeeRemoteDataSource(this._client);

  final SupabaseClient? _client;

  bool get isAvailable => _client != null;

  Future<List<Map<String, dynamic>>> fetchEmployees({
    required String companyId,
    required bool includeInactive,
  }) async {
    final SupabaseClient client = _requireClient();
    var query = client.from('employees').select().eq('company_id', companyId);
    if (!includeInactive) {
      query = query.eq('is_active', true);
    }
    final List<Map<String, dynamic>> rows =
        await query.order('full_name', ascending: true);
    return rows;
  }

  Future<Map<String, dynamic>> insertEmployee(
    Map<String, dynamic> payload,
  ) async {
    final SupabaseClient client = _requireClient();
    return await client
        .from('employees')
        .insert(payload)
        .select()
        .single();
  }

  Future<Map<String, dynamic>?> updateEmployee(
    String employeeId,
    Map<String, dynamic> payload,
  ) async {
    final SupabaseClient client = _requireClient();
    return await client
        .from('employees')
        .update(payload)
        .eq('id', employeeId)
        .select()
        .maybeSingle();
  }

  Future<void> deleteEmployee(String employeeId) async {
    final SupabaseClient client = _requireClient();
    await client.from('employees').delete().eq('id', employeeId);
  }

  SupabaseClient _requireClient() {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw const EmployeeException(
        type: EmployeeFailureType.unknown,
        cause: 'Supabase client is not initialised.',
      );
    }
    return client;
  }
}

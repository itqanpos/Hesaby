// lib/features/employees/data/datasources/employee_payroll_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../domain/repositories/employee_advance_repository.dart';

/// Supabase access for payroll (advances + salaries).
///
/// The only file in this feature that talks to Supabase for payroll
/// operations. RLS enforces tenant isolation via `has_permission(...)`.
///
/// All reads join `employees` to resolve the employee name.
class EmployeePayrollRemoteDataSource {
  const EmployeePayrollRemoteDataSource(this._client);

  final SupabaseClient? _client;

  bool get isAvailable => _client != null;

  // ---------------------------------------------------------------------------
  // Advances
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchAdvances({
    required String companyId,
    String? employeeId,
    required bool onlyOpen,
    required int limit,
  }) async {
    final SupabaseClient client = _requireClient();
    var query = client
        .from('employee_advances')
        .select('*, employees(full_name)')
        .eq('company_id', companyId);

    if (employeeId != null) {
      query = query.eq('employee_id', employeeId);
    }
    if (onlyOpen) {
      query = query.neq('status', 'deducted');
    }

    final List<Map<String, dynamic>> rows = await query
        .order('advance_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows;
  }

  Future<Map<String, dynamic>> insertAdvance(
    Map<String, dynamic> payload,
  ) async {
    final SupabaseClient client = _requireClient();
    return await client
        .from('employee_advances')
        .insert(payload)
        .select('*, employees(full_name)')
        .single();
  }

  Future<Map<String, dynamic>?> updateAdvance(
    String advanceId,
    Map<String, dynamic> payload,
  ) async {
    final SupabaseClient client = _requireClient();
    return await client
        .from('employee_advances')
        .update(payload)
        .eq('id', advanceId)
        .select('*, employees(full_name)')
        .maybeSingle();
  }

  Future<void> deleteAdvance(String advanceId) async {
    final SupabaseClient client = _requireClient();
    await client.from('employee_advances').delete().eq('id', advanceId);
  }

  // ---------------------------------------------------------------------------
  // Salaries
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchSalaries({
    required String companyId,
    DateTime? monthStart,
    String? employeeId,
    required int limit,
  }) async {
    final SupabaseClient client = _requireClient();
    var query = client
        .from('employee_salaries')
        .select('*, employees(full_name)')
        .eq('company_id', companyId);

    if (monthStart != null) {
      final String iso = monthStart.toIso8601String().split('T').first;
      query = query.eq('salary_month', iso);
    }
    if (employeeId != null) {
      query = query.eq('employee_id', employeeId);
    }

    final List<Map<String, dynamic>> rows = await query
        .order('salary_month', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows;
  }

  Future<Map<String, dynamic>> insertSalary(
    Map<String, dynamic> payload,
  ) async {
    final SupabaseClient client = _requireClient();
    return await client
        .from('employee_salaries')
        .insert(payload)
        .select('*, employees(full_name)')
        .single();
  }

  Future<Map<String, dynamic>?> updateSalary(
    String salaryId,
    Map<String, dynamic> payload,
  ) async {
    final SupabaseClient client = _requireClient();
    return await client
        .from('employee_salaries')
        .update(payload)
        .eq('id', salaryId)
        .select('*, employees(full_name)')
        .maybeSingle();
  }

  Future<void> deleteSalary(String salaryId) async {
    final SupabaseClient client = _requireClient();
    await client.from('employee_salaries').delete().eq('id', salaryId);
  }

  // ---------------------------------------------------------------------------
  // Client
  // ---------------------------------------------------------------------------

  SupabaseClient _requireClient() {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw const AdvanceException(
        type: AdvanceFailureType.unknown,
        cause: 'Supabase client is not initialised.',
      );
    }
    return client;
  }
}

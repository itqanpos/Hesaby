// lib/features/employees/data/datasources/attendance_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart';

class AttendanceRemoteDataSource {
  const AttendanceRemoteDataSource(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _db {
    if (_client == null) {
      throw const PostgrestException(
        message: 'Supabase client is not initialized.',
        code: 'CLIENT_NULL',
      );
    }
    return _client;
  }

  /// جلب سجلات الحضور بتاريخ معين (مع اسم الموظف)
  Future<List<Map<String, dynamic>>> fetchAttendance({
    required String companyId,
    required DateTime date,
  }) async {
    // تحويل التاريخ إلى صيغة YYYY-MM-DD
    final String dateStr = date.toIso8601String().split('T').first;

    final List<Map<String, dynamic>> response = await _db
        .from('attendance_records')
        .select('*, employees(full_name)')
        .eq('company_id', companyId)
        .eq('date', dateStr);

    return response;
  }

  /// إضافة أو تعديل سجل حضور (Upsert)
  Future<Map<String, dynamic>> upsertAttendance(
    Map<String, dynamic> payload,
  ) async {
    final Map<String, dynamic> response = await _db
        .from('attendance_records')
        .upsert(
          payload,
          onConflict: 'company_id, employee_id, date',
        )
        .select('*, employees(full_name)')
        .single();

    return response;
  }

  /// حذف سجل حضور
  Future<void> deleteAttendance(String attendanceId) async {
    await _db.from('attendance_records').delete().eq('id', attendanceId);
  }
}

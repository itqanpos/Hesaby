// lib/features/employees/data/repositories/attendance_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/attendance_record.dart';
import '../../domain/repositories/attendance_repository.dart';
import '../datasources/attendance_remote_datasource.dart';

class AttendanceRepositoryImpl implements AttendanceRepository {
  const AttendanceRepositoryImpl(this._remote);

  final AttendanceRemoteDataSource _remote;

  // ---------------------------------------------------------------------------
  // Mapping
  // ---------------------------------------------------------------------------

  static String _requireString(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v is String && v.isNotEmpty) return v;
    throw FormatException('Attendance: missing or invalid "$k".');
  }

  static String? _optionalString(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v == null) return null;
    if (v is String) {
      final String t = v.trim();
      return t.isEmpty ? null : t;
    }
    return v.toString();
  }

  static DateTime _requireDate(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v is DateTime) return DateTime(v.year, v.month, v.day);
    if (v is String && v.isNotEmpty) {
      final DateTime? d = DateTime.tryParse(v);
      if (d != null) return DateTime(d.year, d.month, d.day);
    }
    throw FormatException('Attendance: "$k" is not a date.');
  }

  static DateTime? _optionalTimestamp(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v == null) return null;
    if (v is DateTime) return v.toUtc();
    if (v is String && v.isNotEmpty) {
      return DateTime.tryParse(v)?.toUtc();
    }
    return null;
  }

  static DateTime _requireTimestamp(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v is DateTime) return v.toUtc();
    if (v is String) {
      final DateTime? d = DateTime.tryParse(v);
      if (d != null) return d.toUtc();
    }
    throw FormatException('Attendance: "$k" is not a timestamp.');
  }

  static String? _employeeNameFrom(Map<String, dynamic> m) {
    final Object? nested = m['employees'];
    if (nested is Map<String, dynamic>) {
      final Object? name = nested['full_name'];
      if (name is String && name.isNotEmpty) return name;
    }
    return null;
  }

  static AttendanceRecord _map(Map<String, dynamic> m) {
    return AttendanceRecord(
      id: _requireString(m, 'id'),
      companyId: _requireString(m, 'company_id'),
      employeeId: _requireString(m, 'employee_id'),
      date: _requireDate(m, 'date'),
      status: AttendanceStatus.fromDb(_optionalString(m, 'status')),
      checkInTime: _optionalTimestamp(m, 'check_in_time'),
      checkOutTime: _optionalTimestamp(m, 'check_out_time'),
      notes: _optionalString(m, 'notes'),
      createdAt: _requireTimestamp(m, 'created_at'),
      updatedAt: _requireTimestamp(m, 'updated_at'),
      employeeName: _employeeNameFrom(m),
    );
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  @override
  Future<List<AttendanceRecord>> listAttendance({
    required String companyId,
    required DateTime date,
  }) async {
    try {
      final List<Map<String, dynamic>> rows =
          await _remote.fetchAttendance(companyId: companyId, date: date);
      return rows.map(_map).toList(growable: false);
    } on FormatException catch (e, s) {
      throw _invalidResponse(e, s, 'listAttendance');
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'listAttendance');
    } on AttendanceException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'listAttendance');
    }
  }

  @override
  Future<AttendanceRecord> upsertAttendance({
    required String companyId,
    required String employeeId,
    required DateTime date,
    required AttendanceStatus status,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    String? notes,
  }) async {
    try {
      final String dateStr = date.toIso8601String().split('T').first;

      final Map<String, dynamic> payload = <String, dynamic>{
        'company_id': companyId,
        'employee_id': employeeId,
        'date': dateStr,
        'status': status.dbValue,
        'check_in_time': checkInTime?.toUtc().toIso8601String(),
        'check_out_time': checkOutTime?.toUtc().toIso8601String(),
        'notes': notes,
      };

      final Map<String, dynamic> row =
          await _remote.upsertAttendance(payload);
      return _map(row);
    } on FormatException catch (e, s) {
      throw _invalidResponse(e, s, 'upsertAttendance');
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'upsertAttendance');
    } on AttendanceException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'upsertAttendance');
    }
  }

  @override
  Future<void> deleteAttendance(String attendanceId) async {
    try {
      await _remote.deleteAttendance(attendanceId);
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'deleteAttendance');
    } on AttendanceException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'deleteAttendance');
    }
  }

  // ---------------------------------------------------------------------------
  // Error mapping
  // ---------------------------------------------------------------------------

  static AttendanceException _invalidResponse(
    FormatException e,
    StackTrace s,
    String op,
  ) {
    AppLogger.error('Attendance invalid response "$op".', e, s);
    return AttendanceException(
      type: AttendanceFailureType.invalidResponse,
      cause: e,
      stackTrace: s,
    );
  }

  static AttendanceException _postgrest(
    supabase.PostgrestException e,
    StackTrace s,
    String op,
  ) {
    final String code = (e.code ?? '').toUpperCase();
    final AttendanceFailureType type;

    if (code.startsWith('42501') || code.startsWith('28')) {
      type = AttendanceFailureType.unauthorized;
    } else if (code == '23505') {
      type = AttendanceFailureType.invalidInput; // تكرار (نادراً ما يحدث بسبب Upsert)
    } else if (code.startsWith('23')) {
      type = AttendanceFailureType.invalidInput;
    } else if (code == 'PGRST116') {
      type = AttendanceFailureType.notFound;
    } else {
      type = AttendanceFailureType.unknown;
    }

    AppLogger.warning('Attendance PostgREST "$op" → ${type.name} ($code).');
    return AttendanceException(type: type, cause: e, stackTrace: s);
  }

  static AttendanceException _unknown(Object e, StackTrace s, String op) {
    final String desc = e.toString().toLowerCase();
    final AttendanceFailureType type = (desc.contains('socket') ||
            desc.contains('network') ||
            desc.contains('timeout'))
        ? AttendanceFailureType.network
        : AttendanceFailureType.unknown;
    AppLogger.error('Attendance unknown error "$op".', e, s);
    return AttendanceException(type: type, cause: e, stackTrace: s);
  }
}

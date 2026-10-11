// lib/features/employees/data/repositories/employee_advance_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/employee_advance.dart';
import '../../domain/repositories/employee_advance_repository.dart';
import '../datasources/employee_payroll_remote_datasource.dart';

class EmployeeAdvanceRepositoryImpl implements EmployeeAdvanceRepository {
  const EmployeeAdvanceRepositoryImpl(this._remote);

  final EmployeePayrollRemoteDataSource _remote;

  // ---------------------------------------------------------------------------
  // Mapping
  // ---------------------------------------------------------------------------

  static String _requireString(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v is String && v.isNotEmpty) return v;
    throw FormatException('Advance: missing or invalid "$k".');
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

  static double _double(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static DateTime _requireTimestamp(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v is DateTime) return v.toUtc();
    if (v is String) {
      final DateTime? d = DateTime.tryParse(v);
      if (d != null) return d.toUtc();
    }
    throw FormatException('Advance: "$k" is not a timestamp.');
  }

  static DateTime _requireDate(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v is DateTime) return DateTime(v.year, v.month, v.day);
    if (v is String && v.isNotEmpty) {
      final DateTime? d = DateTime.tryParse(v);
      if (d != null) return DateTime(d.year, d.month, d.day);
    }
    throw FormatException('Advance: "$k" is not a date.');
  }

  static String? _employeeNameFrom(Map<String, dynamic> m) {
    final Object? nested = m['employees'];
    if (nested is Map<String, dynamic>) {
      final Object? name = nested['full_name'];
      if (name is String && name.isNotEmpty) return name;
    }
    return null;
  }

  static EmployeeAdvance _map(Map<String, dynamic> m) {
    return EmployeeAdvance(
      id: _requireString(m, 'id'),
      companyId: _requireString(m, 'company_id'),
      employeeId: _requireString(m, 'employee_id'),
      employeeName: _employeeNameFrom(m),
      amount: _double(m, 'amount'),
      remainingAmount: _double(m, 'remaining_amount'),
      advanceDate: _requireDate(m, 'advance_date'),
      reason: _optionalString(m, 'reason'),
      status: AdvanceStatus.fromString(m['status'] as String?),
      notes: _optionalString(m, 'notes'),
      createdAt: _requireTimestamp(m, 'created_at'),
      updatedAt: _requireTimestamp(m, 'updated_at'),
    );
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  @override
  Future<List<EmployeeAdvance>> listAdvances({
    required String companyId,
    String? employeeId,
    bool onlyOpen = false,
    int limit = 200,
  }) async {
    try {
      final List<Map<String, dynamic>> rows =
          await _remote.fetchAdvances(
        companyId: companyId,
        employeeId: employeeId,
        onlyOpen: onlyOpen,
        limit: limit,
      );
      return rows.map(_map).toList(growable: false);
    } on FormatException catch (e, s) {
      throw _invalidResponse(e, s, 'listAdvances');
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'listAdvances');
    } on AdvanceException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'listAdvances');
    }
  }

  @override
  Future<EmployeeAdvance> createAdvance({
    required String companyId,
    required String employeeId,
    required double amount,
    required DateTime advanceDate,
    String? reason,
    String? notes,
  }) async {
    try {
      final Map<String, dynamic> payload = <String, dynamic>{
        'company_id': companyId,
        'employee_id': employeeId,
        'amount': amount,
        'remaining_amount': amount,
        'advance_date': advanceDate.toIso8601String().split('T').first,
        'status': 'open',
        'reason': reason,
        'notes': notes,
      };
      final Map<String, dynamic> row =
          await _remote.insertAdvance(payload);
      return _map(row);
    } on FormatException catch (e, s) {
      throw _invalidResponse(e, s, 'createAdvance');
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'createAdvance');
    } on AdvanceException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'createAdvance');
    }
  }

  @override
  Future<void> deleteAdvance(String advanceId) async {
    try {
      await _remote.deleteAdvance(advanceId);
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'deleteAdvance');
    } on AdvanceException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'deleteAdvance');
    }
  }

  // ---------------------------------------------------------------------------
  // Error mapping
  // ---------------------------------------------------------------------------

  static AdvanceException _invalidResponse(
    FormatException e,
    StackTrace s,
    String op,
  ) {
    AppLogger.error('Advance invalid response "$op".', e, s);
    return AdvanceException(
      type: AdvanceFailureType.invalidResponse,
      cause: e,
      stackTrace: s,
    );
  }

  static AdvanceException _postgrest(
    supabase.PostgrestException e,
    StackTrace s,
    String op,
  ) {
    final String code = (e.code ?? '').toUpperCase();
    final AdvanceFailureType type;
    if (code.startsWith('42501') || code.startsWith('28')) {
      type = AdvanceFailureType.unauthorized;
    } else if (code.startsWith('23')) {
      type = AdvanceFailureType.invalidInput;
    } else if (code == 'PGRST116') {
      type = AdvanceFailureType.notFound;
    } else {
      type = AdvanceFailureType.unknown;
    }
    AppLogger.warning('Advance PostgREST "$op" → ${type.name} ($code).');
    return AdvanceException(type: type, cause: e, stackTrace: s);
  }

  static AdvanceException _unknown(Object e, StackTrace s, String op) {
    final String desc = e.toString().toLowerCase();
    final AdvanceFailureType type = (desc.contains('socket') ||
            desc.contains('network') ||
            desc.contains('timeout'))
        ? AdvanceFailureType.network
        : AdvanceFailureType.unknown;
    AppLogger.error('Advance unknown error "$op".', e, s);
    return AdvanceException(type: type, cause: e, stackTrace: s);
  }
}

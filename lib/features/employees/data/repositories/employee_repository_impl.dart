// lib/features/employees/data/repositories/employee_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/employee.dart';
import '../../domain/repositories/employee_repository.dart';
import '../datasources/employee_remote_datasource.dart';

class EmployeeRepositoryImpl implements EmployeeRepository {
  const EmployeeRepositoryImpl(this._remote);

  final EmployeeRemoteDataSource _remote;

  // ---------------------------------------------------------------------------
  // Mapping
  // ---------------------------------------------------------------------------

  static String _requireString(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v is String && v.isNotEmpty) return v;
    throw FormatException('Employee: missing or invalid "$k".');
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

  static bool _bool(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final String l = v.toLowerCase();
      return l == 'true' || l == 't' || l == '1';
    }
    return false;
  }

  static double _double(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v is num) return v.toDouble();
    if (v is String) {
      final double? d = double.tryParse(v);
      if (d != null) return d;
    }
    return 0;
  }

  static DateTime _requireTimestamp(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v is DateTime) return v.toUtc();
    if (v is String) {
      final DateTime? d = DateTime.tryParse(v);
      if (d != null) return d.toUtc();
    }
    throw FormatException('Employee: "$k" is not a timestamp.');
  }

  static DateTime? _optionalDate(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v == null) return null;
    if (v is DateTime) return DateTime(v.year, v.month, v.day);
    if (v is String && v.isNotEmpty) {
      final DateTime? d = DateTime.tryParse(v);
      if (d != null) return DateTime(d.year, d.month, d.day);
    }
    return null;
  }

  static Employee _map(Map<String, dynamic> m) {
    return Employee(
      id: _requireString(m, 'id'),
      companyId: _requireString(m, 'company_id'),
      fullName: _requireString(m, 'full_name'),
      phone: _optionalString(m, 'phone'),
      email: _optionalString(m, 'email'),
      nationalId: _optionalString(m, 'national_id'),
      position: _optionalString(m, 'position'),
      hireDate: _optionalDate(m, 'hire_date'),
      baseSalary: _double(m, 'base_salary'),
      notes: _optionalString(m, 'notes'),
      isActive: _bool(m, 'is_active'),
      companyMemberId: _optionalString(m, 'company_member_id'),
      createdAt: _requireTimestamp(m, 'created_at'),
      updatedAt: _requireTimestamp(m, 'updated_at'),
    );
  }

  static Map<String, dynamic> _compact(Map<String, dynamic> map) {
    final Map<String, dynamic> result = <String, dynamic>{};
    for (final MapEntry<String, dynamic> e in map.entries) {
      if (e.value != null) result[e.key] = e.value;
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  @override
  Future<List<Employee>> listEmployees(
    String companyId, {
    bool includeInactive = false,
  }) async {
    try {
      final List<Map<String, dynamic>> rows = await _remote.fetchEmployees(
        companyId: companyId,
        includeInactive: includeInactive,
      );
      return rows.map(_map).toList(growable: false);
    } on FormatException catch (e, s) {
      throw _invalidResponse(e, s, 'listEmployees');
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'listEmployees');
    } on EmployeeException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'listEmployees');
    }
  }

  @override
  Future<Employee> createEmployee({
    required String companyId,
    required String fullName,
    required double baseSalary,
    String? phone,
    String? email,
    String? nationalId,
    String? position,
    DateTime? hireDate,
    String? notes,
    String? companyMemberId,
  }) async {
    try {
      final Map<String, dynamic> payload = <String, dynamic>{
        'company_id': companyId,
        'full_name': fullName.trim(),
        'base_salary': baseSalary,
        'phone': phone,
        'email': email,
        'national_id': nationalId,
        'position': position,
        'hire_date': hireDate?.toIso8601String().split('T').first,
        'notes': notes,
        'company_member_id': companyMemberId,
      };
      final Map<String, dynamic> row =
          await _remote.insertEmployee(_compact(payload));
      return _map(row);
    } on FormatException catch (e, s) {
      throw _invalidResponse(e, s, 'createEmployee');
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'createEmployee');
    } on EmployeeException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'createEmployee');
    }
  }

  @override
  Future<Employee> updateEmployee({
    required String employeeId,
    String? fullName,
    String? phone,
    bool clearPhone = false,
    String? email,
    bool clearEmail = false,
    String? nationalId,
    bool clearNationalId = false,
    String? position,
    bool clearPosition = false,
    DateTime? hireDate,
    bool clearHireDate = false,
    double? baseSalary,
    String? notes,
    bool clearNotes = false,
    bool? isActive,
    String? companyMemberId,
    bool clearCompanyMember = false,
  }) async {
    try {
      final Map<String, dynamic> payload = <String, dynamic>{};
      if (fullName != null) payload['full_name'] = fullName.trim();
      if (clearPhone) {
        payload['phone'] = null;
      } else if (phone != null) {
        payload['phone'] = phone;
      }
      if (clearEmail) {
        payload['email'] = null;
      } else if (email != null) {
        payload['email'] = email;
      }
      if (clearNationalId) {
        payload['national_id'] = null;
      } else if (nationalId != null) {
        payload['national_id'] = nationalId;
      }
      if (clearPosition) {
        payload['position'] = null;
      } else if (position != null) {
        payload['position'] = position;
      }
      if (clearHireDate) {
        payload['hire_date'] = null;
      } else if (hireDate != null) {
        payload['hire_date'] = hireDate.toIso8601String().split('T').first;
      }
      if (baseSalary != null) payload['base_salary'] = baseSalary;
      if (clearNotes) {
        payload['notes'] = null;
      } else if (notes != null) {
        payload['notes'] = notes;
      }
      if (isActive != null) payload['is_active'] = isActive;
      if (clearCompanyMember) {
        payload['company_member_id'] = null;
      } else if (companyMemberId != null) {
        payload['company_member_id'] = companyMemberId;
      }

      if (payload.isEmpty) {
        throw const EmployeeException(
          type: EmployeeFailureType.invalidInput,
          cause: 'Empty update payload.',
        );
      }

      final Map<String, dynamic>? row =
          await _remote.updateEmployee(employeeId, payload);
      if (row == null) {
        throw const EmployeeException(
          type: EmployeeFailureType.notFound,
          cause: 'Employee not found or update blocked by RLS.',
        );
      }
      return _map(row);
    } on FormatException catch (e, s) {
      throw _invalidResponse(e, s, 'updateEmployee');
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'updateEmployee');
    } on EmployeeException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'updateEmployee');
    }
  }

  @override
  Future<void> deleteEmployee(String employeeId) async {
    try {
      await _remote.deleteEmployee(employeeId);
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'deleteEmployee');
    } on EmployeeException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'deleteEmployee');
    }
  }

  // ---------------------------------------------------------------------------
  // Error mapping
  // ---------------------------------------------------------------------------

  static EmployeeException _invalidResponse(
    FormatException e,
    StackTrace s,
    String op,
  ) {
    AppLogger.error('Employee invalid response "$op".', e, s);
    return EmployeeException(
      type: EmployeeFailureType.invalidResponse,
      cause: e,
      stackTrace: s,
    );
  }

  static EmployeeException _postgrest(
    supabase.PostgrestException e,
    StackTrace s,
    String op,
  ) {
    final String code = (e.code ?? '').toUpperCase();
    final EmployeeFailureType type;
    if (code.startsWith('42501') || code.startsWith('28')) {
      type = EmployeeFailureType.unauthorized;
    } else if (code.startsWith('23')) {
      type = EmployeeFailureType.invalidInput;
    } else if (code == 'PGRST116') {
      type = EmployeeFailureType.notFound;
    } else {
      type = EmployeeFailureType.unknown;
    }
    AppLogger.warning('Employee PostgREST "$op" → ${type.name} ($code).');
    return EmployeeException(type: type, cause: e, stackTrace: s);
  }

  static EmployeeException _unknown(Object e, StackTrace s, String op) {
    final String desc = e.toString().toLowerCase();
    final EmployeeFailureType type = (desc.contains('socket') ||
            desc.contains('network') ||
            desc.contains('timeout'))
        ? EmployeeFailureType.network
        : EmployeeFailureType.unknown;
    AppLogger.error('Employee unknown error "$op".', e, s);
    return EmployeeException(type: type, cause: e, stackTrace: s);
  }
}

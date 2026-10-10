// lib/features/employees/data/repositories/employee_salary_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/employee_salary.dart';
import '../../domain/repositories/employee_salary_repository.dart';
import '../datasources/employee_payroll_remote_datasource.dart';

class EmployeeSalaryRepositoryImpl implements EmployeeSalaryRepository {
  const EmployeeSalaryRepositoryImpl(this._remote);

  final EmployeePayrollRemoteDataSource _remote;

  // ---------------------------------------------------------------------------
  // Mapping
  // ---------------------------------------------------------------------------

  static String _requireString(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v is String && v.isNotEmpty) return v;
    throw FormatException('Salary: missing or invalid "$k".');
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
    throw FormatException('Salary: "$k" is not a timestamp.');
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

  static DateTime _requireDate(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v is DateTime) return DateTime(v.year, v.month, v.day);
    if (v is String && v.isNotEmpty) {
      final DateTime? d = DateTime.tryParse(v);
      if (d != null) return DateTime(d.year, d.month, d.day);
    }
    throw FormatException('Salary: "$k" is not a date.');
  }

  static String? _employeeNameFrom(Map<String, dynamic> m) {
    final Object? nested = m['employees'];
    if (nested is Map<String, dynamic>) {
      final Object? name = nested['full_name'];
      if (name is String && name.isNotEmpty) return name;
    }
    return null;
  }

  static EmployeeSalary _map(Map<String, dynamic> m) {
    return EmployeeSalary(
      id: _requireString(m, 'id'),
      companyId: _requireString(m, 'company_id'),
      employeeId: _requireString(m, 'employee_id'),
      employeeName: _employeeNameFrom(m),
      salaryMonth: _requireDate(m, 'salary_month'),
      baseAmount: _double(m, 'base_amount'),
      bonuses: _double(m, 'bonuses'),
      deductions: _double(m, 'deductions'),
      advancesDeducted: _double(m, 'advances_deducted'),
      netAmount: _double(m, 'net_amount'),
      paymentMethod: _requireString(m, 'payment_method'),
      paidAt: _optionalTimestamp(m, 'paid_at'),
      notes: _optionalString(m, 'notes'),
      createdAt: _requireTimestamp(m, 'created_at'),
      updatedAt: _requireTimestamp(m, 'updated_at'),
    );
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  @override
  Future<List<EmployeeSalary>> listSalaries({
    required String companyId,
    DateTime? monthStart,
    String? employeeId,
    int limit = 500,
  }) async {
    try {
      final List<Map<String, dynamic>> rows = await _remote.fetchSalaries(
        companyId: companyId,
        monthStart: monthStart,
        employeeId: employeeId,
        limit: limit,
      );
      return rows.map(_map).toList(growable: false);
    } on FormatException catch (e, s) {
      throw _invalidResponse(e, s, 'listSalaries');
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'listSalaries');
    } on SalaryException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'listSalaries');
    }
  }

  @override
  Future<EmployeeSalary> createSalary({
    required String companyId,
    required String employeeId,
    required DateTime salaryMonth,
    required double baseAmount,
    double bonuses = 0,
    double deductions = 0,
    double advancesDeducted = 0,
    String paymentMethod = 'cash',
    DateTime? paidAt,
    String? notes,
  }) async {
    try {
      final DateTime monthFirst =
          DateTime(salaryMonth.year, salaryMonth.month, 1);
      final double net = EmployeeSalary.computeNet(
        base: baseAmount,
        bonuses: bonuses,
        deductions: deductions,
        advancesDeducted: advancesDeducted,
      );

      final Map<String, dynamic> payload = <String, dynamic>{
        'company_id': companyId,
        'employee_id': employeeId,
        'salary_month': monthFirst.toIso8601String().split('T').first,
        'base_amount': baseAmount,
        'bonuses': bonuses,
        'deductions': deductions,
        'advances_deducted': advancesDeducted,
        'net_amount': net,
        'payment_method': paymentMethod,
        'paid_at': paidAt?.toUtc().toIso8601String(),
        'notes': notes,
      };
      final Map<String, dynamic> row = await _remote.insertSalary(payload);
      return _map(row);
    } on FormatException catch (e, s) {
      throw _invalidResponse(e, s, 'createSalary');
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'createSalary');
    } on SalaryException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'createSalary');
    }
  }

  @override
  Future<EmployeeSalary> updateSalary({
    required String salaryId,
    double? baseAmount,
    double? bonuses,
    double? deductions,
    String? paymentMethod,
    String? notes,
    bool clearNotes = false,
  }) async {
    try {
      final Map<String, dynamic> payload = <String, dynamic>{};
      if (baseAmount != null) payload['base_amount'] = baseAmount;
      if (bonuses != null) payload['bonuses'] = bonuses;
      if (deductions != null) payload['deductions'] = deductions;
      if (paymentMethod != null) {
        payload['payment_method'] = paymentMethod;
      }
      if (clearNotes) {
        payload['notes'] = null;
      } else if (notes != null) {
        payload['notes'] = notes;
      }

      if (payload.isEmpty) {
        throw const SalaryException(
          type: SalaryFailureType.invalidInput,
          cause: 'Empty update payload.',
        );
      }

      final Map<String, dynamic>? row =
          await _remote.updateSalary(salaryId, payload);
      if (row == null) {
        throw const SalaryException(
          type: SalaryFailureType.notFound,
          cause: 'Salary not found or update blocked by RLS.',
        );
      }
      return _map(row);
    } on FormatException catch (e, s) {
      throw _invalidResponse(e, s, 'updateSalary');
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'updateSalary');
    } on SalaryException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'updateSalary');
    }
  }

  @override
  Future<EmployeeSalary> markPaid({
    required String salaryId,
    String? paymentMethod,
    DateTime? paidAt,
  }) async {
    try {
      final Map<String, dynamic> payload = <String, dynamic>{
        'paid_at': (paidAt ?? DateTime.now()).toUtc().toIso8601String(),
      };
      if (paymentMethod != null) {
        payload['payment_method'] = paymentMethod;
      }

      final Map<String, dynamic>? row =
          await _remote.updateSalary(salaryId, payload);
      if (row == null) {
        throw const SalaryException(
          type: SalaryFailureType.notFound,
          cause: 'Salary not found or update blocked by RLS.',
        );
      }
      return _map(row);
    } on FormatException catch (e, s) {
      throw _invalidResponse(e, s, 'markPaid');
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'markPaid');
    } on SalaryException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'markPaid');
    }
  }

  @override
  Future<void> deleteSalary(String salaryId) async {
    try {
      await _remote.deleteSalary(salaryId);
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'deleteSalary');
    } on SalaryException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'deleteSalary');
    }
  }

  // ---------------------------------------------------------------------------
  // Error mapping
  // ---------------------------------------------------------------------------

  static SalaryException _invalidResponse(
    FormatException e,
    StackTrace s,
    String op,
  ) {
    AppLogger.error('Salary invalid response "$op".', e, s);
    return SalaryException(
      type: SalaryFailureType.invalidResponse,
      cause: e,
      stackTrace: s,
    );
  }

  static SalaryException _postgrest(
    supabase.PostgrestException e,
    StackTrace s,
    String op,
  ) {
    final String code = (e.code ?? '').toUpperCase();
    final SalaryFailureType type;
    if (code.startsWith('42501') || code.startsWith('28')) {
      type = SalaryFailureType.unauthorized;
    } else if (code == '23505') {
      type = SalaryFailureType.duplicateEntry;
    } else if (code.startsWith('23')) {
      type = SalaryFailureType.invalidInput;
    } else if (code == 'PGRST116') {
      type = SalaryFailureType.notFound;
    } else {
      type = SalaryFailureType.unknown;
    }
    AppLogger.warning('Salary PostgREST "$op" → ${type.name} ($code).');
    return SalaryException(type: type, cause: e, stackTrace: s);
  }

  static SalaryException _unknown(Object e, StackTrace s, String op) {
    final String desc = e.toString().toLowerCase();
    final SalaryFailureType type = (desc.contains('socket') ||
            desc.contains('network') ||
            desc.contains('timeout'))
        ? SalaryFailureType.network
        : SalaryFailureType.unknown;
    AppLogger.error('Salary unknown error "$op".', e, s);
    return SalaryException(type: type, cause: e, stackTrace: s);
  }
}

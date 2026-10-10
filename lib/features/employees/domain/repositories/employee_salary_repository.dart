// lib/features/employees/domain/repositories/employee_salary_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/employee_salary.dart';

enum SalaryFailureType {
  network,
  unauthorized,
  notFound,
  invalidInput,
  duplicateEntry,
  invalidResponse,
  unknown,
}

@immutable
class SalaryException extends Equatable implements Exception {
  const SalaryException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  final SalaryFailureType type;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'SalaryException(type: ${type.name})';
}

abstract interface class EmployeeSalaryRepository {
  /// Lists salaries of [companyId], optionally filtered by month.
  ///
  /// [monthStart] must be the first day of a month.
  Future<List<EmployeeSalary>> listSalaries({
    required String companyId,
    DateTime? monthStart,
    String? employeeId,
    int limit = 500,
  });

  /// Creates a salary entry. When [paidAt] is provided, the DB trigger
  /// posts the cash movement.
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
  });

  /// Updates editable fields of a salary entry that is not yet paid.
  ///
  /// Paid entries cannot be modified (a DB-level rule ensures this in the
  /// UI layer — this method simply refuses to change them).
  Future<EmployeeSalary> updateSalary({
    required String salaryId,
    double? baseAmount,
    double? bonuses,
    double? deductions,
    String? paymentMethod,
    String? notes,
    bool clearNotes = false,
  });

  /// Marks a salary as paid at [paidAt] (defaults to now).
  ///
  /// Triggers the cash movement on the database side.
  Future<EmployeeSalary> markPaid({
    required String salaryId,
    String? paymentMethod,
    DateTime? paidAt,
  });

  Future<void> deleteSalary(String salaryId);
}

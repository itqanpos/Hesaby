// lib/features/employees/domain/repositories/employee_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/employee.dart';

enum EmployeeFailureType {
  network,
  unauthorized,
  notFound,
  invalidInput,
  invalidResponse,
  unknown,
}

@immutable
class EmployeeException extends Equatable implements Exception {
  const EmployeeException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  final EmployeeFailureType type;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'EmployeeException(type: ${type.name})';
}

abstract interface class EmployeeRepository {
  /// Returns every employee of [companyId], newest first.
  Future<List<Employee>> listEmployees(
    String companyId, {
    bool includeInactive = false,
  });

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
  });

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
  });

  Future<void> deleteEmployee(String employeeId);
}

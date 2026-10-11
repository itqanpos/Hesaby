// lib/features/employees/domain/repositories/employee_advance_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/employee_advance.dart';

enum AdvanceFailureType {
  network,
  unauthorized,
  notFound,
  invalidInput,
  invalidResponse,
  unknown,
}

@immutable
class AdvanceException extends Equatable implements Exception {
  const AdvanceException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  final AdvanceFailureType type;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'AdvanceException(type: ${type.name})';
}

abstract interface class EmployeeAdvanceRepository {
  /// Lists advances of [companyId], optionally filtered by employee.
  Future<List<EmployeeAdvance>> listAdvances({
    required String companyId,
    String? employeeId,
    bool onlyOpen = false,
    int limit = 200,
  });

  Future<EmployeeAdvance> createAdvance({
    required String companyId,
    required String employeeId,
    required double amount,
    required DateTime advanceDate,
    String? reason,
    String? notes,
  });

  Future<void> deleteAdvance(String advanceId);

  // Note: applying a deduction is handled automatically by the
  // `apply_advance_deduction` DB trigger whenever a salary is marked as
  // paid. There is no manual "apply deduction" method on purpose.
}

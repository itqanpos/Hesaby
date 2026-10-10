// lib/features/employees/domain/entities/employee_advance.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Status of an employee advance.
enum AdvanceStatus {
  /// Fully outstanding — no deduction applied yet.
  open,

  /// Partially deducted from a salary.
  partiallyDeducted,

  /// Fully deducted from salaries.
  deducted;

  static AdvanceStatus fromString(String? raw) {
    switch (raw) {
      case 'partially_deducted':
        return AdvanceStatus.partiallyDeducted;
      case 'deducted':
        return AdvanceStatus.deducted;
      default:
        return AdvanceStatus.open;
    }
  }

  String get value => switch (this) {
        AdvanceStatus.open => 'open',
        AdvanceStatus.partiallyDeducted => 'partially_deducted',
        AdvanceStatus.deducted => 'deducted',
      };

  String get label => switch (this) {
        AdvanceStatus.open => 'غير مخصومة',
        AdvanceStatus.partiallyDeducted => 'مخصومة جزئيًا',
        AdvanceStatus.deducted => 'مخصومة بالكامل',
      };
}

/// An advance paid to an employee.
///
/// Recording an advance immediately posts an "out" cash movement. The
/// remaining amount is reduced when a salary is paid and an explicit
/// deduction is applied.
@immutable
class EmployeeAdvance extends Equatable {
  const EmployeeAdvance({
    required this.id,
    required this.companyId,
    required this.employeeId,
    required this.amount,
    required this.remainingAmount,
    required this.advanceDate,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.employeeName,
    this.reason,
    this.notes,
  });

  final String id;
  final String companyId;
  final String employeeId;

  /// Optional employee name — filled by the repository via a join.
  final String? employeeName;

  final double amount;
  final double remainingAmount;
  final DateTime advanceDate;
  final String? reason;
  final AdvanceStatus status;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  double get deductedAmount => amount - remainingAmount;
  bool get isOpen => status == AdvanceStatus.open;
  bool get isFullyDeducted => status == AdvanceStatus.deducted;

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        employeeId,
        amount,
        remainingAmount,
        advanceDate,
        status,
        updatedAt,
      ];
}

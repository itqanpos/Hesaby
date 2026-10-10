// lib/features/employees/domain/entities/employee_salary.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Status of a salary record (derived: unpaid if `paidAt` is null).
enum SalaryStatus {
  unpaid,
  paid;

  String get label => this == SalaryStatus.paid ? 'مدفوع' : 'لم يُدفع';
}

/// A monthly salary entry for one employee.
///
/// Net = base + bonuses - deductions - advancesDeducted.
/// Recording an entry with `paidAt != null` immediately posts an "out"
/// cash movement (see the DB trigger).
@immutable
class EmployeeSalary extends Equatable {
  const EmployeeSalary({
    required this.id,
    required this.companyId,
    required this.employeeId,
    required this.salaryMonth,
    required this.baseAmount,
    required this.bonuses,
    required this.deductions,
    required this.advancesDeducted,
    required this.netAmount,
    required this.paymentMethod,
    required this.createdAt,
    required this.updatedAt,
    this.employeeName,
    this.paidAt,
    this.notes,
  });

  final String id;
  final String companyId;
  final String employeeId;

  /// Optional employee name — filled by the repository via a join.
  final String? employeeName;

  /// First day of the month (day = 1).
  final DateTime salaryMonth;

  final double baseAmount;
  final double bonuses;
  final double deductions;
  final double advancesDeducted;
  final double netAmount;
  final String paymentMethod;
  final DateTime? paidAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isPaid => paidAt != null;
  SalaryStatus get status =>
      isPaid ? SalaryStatus.paid : SalaryStatus.unpaid;

  /// Computes the net from the components — used before insert.
  static double computeNet({
    required double base,
    required double bonuses,
    required double deductions,
    required double advancesDeducted,
  }) {
    final double net = base + bonuses - deductions - advancesDeducted;
    return net < 0 ? 0 : net;
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        employeeId,
        salaryMonth,
        baseAmount,
        bonuses,
        deductions,
        advancesDeducted,
        netAmount,
        paymentMethod,
        paidAt,
        updatedAt,
      ];
}

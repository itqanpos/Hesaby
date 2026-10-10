// lib/features/employees/domain/entities/employee.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// A single employee of a company.
///
/// Optionally linked to a [CompanyMember] row via [companyMemberId] — used
/// when the employee also uses the app (cashier, manager). Employees who
/// do not use the app (driver, cleaner, ...) leave it null.
@immutable
class Employee extends Equatable {
  const Employee({
    required this.id,
    required this.companyId,
    required this.fullName,
    required this.baseSalary,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.phone,
    this.email,
    this.nationalId,
    this.position,
    this.hireDate,
    this.notes,
    this.companyMemberId,
  });

  final String id;
  final String companyId;
  final String fullName;
  final String? phone;
  final String? email;
  final String? nationalId;
  final String? position;
  final DateTime? hireDate;
  final double baseSalary;
  final String? notes;
  final bool isActive;

  /// Optional link to `company_members.id` — the app-account this employee
  /// uses. Null for staff without an app login.
  final String? companyMemberId;

  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        fullName,
        phone,
        email,
        nationalId,
        position,
        hireDate,
        baseSalary,
        notes,
        isActive,
        companyMemberId,
        createdAt,
        updatedAt,
      ];
}

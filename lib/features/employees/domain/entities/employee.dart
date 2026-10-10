// lib/features/employees/domain/entities/employee.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// A single employee of a company.
///
/// Deliberately separate from `company_members`: an employee may not have
/// an app login. Only the payroll-relevant information is captured here.
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
        createdAt,
        updatedAt,
      ];
}

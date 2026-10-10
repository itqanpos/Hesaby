// lib/features/employees/domain/entities/employee.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// A single employee of a company.
///
/// Optionally linked to a [CompanyMember] row via [companyMemberId] — used
/// when the employee also uses the app. When [loginCode] is set, the
/// employee can sign in using the code instead of an email.
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
    this.loginCode,
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

  /// Optional link to `company_members.id` — the app account.
  final String? companyMemberId;

  /// Optional login code (lowercase). Null when the employee has no
  /// account yet.
  final String? loginCode;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasAccount => companyMemberId != null;

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
        loginCode,
        createdAt,
        updatedAt,
      ];
}

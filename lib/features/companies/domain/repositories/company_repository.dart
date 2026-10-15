// lib/features/companies/domain/repositories/company_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/branch.dart';
import '../entities/company.dart';

enum CompanyFailureType {
  network,
  unauthorized,
  noCompanies,
  companyNotAccessible,
  noBranches,
  invalidResponse,
  unknown,
}

@immutable
class CompanyException extends Equatable implements Exception {
  const CompanyException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  final CompanyFailureType type;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'CompanyException(type: ${type.name})';
}

/// Contract for retrieving and mutating companies and branches accessible
/// to the currently authenticated user.
abstract interface class CompanyRepository {
  Future<List<Company>> getMyCompanies();
  Future<List<Company>> getAllCompanies();

  /// Updates a company's profile.
  ///
  /// [taxNumber] and [commercialRegister] are optional; passing `null`
  /// clears the corresponding column on the server.
  Future<Company> updateCompany({
    required String companyId,
    required String name,
    required String currency,
    required String timezone,
    String? legalName,
    String? phone,
    String? email,
    String? address,
    String? taxNumber,
    String? commercialRegister,
  });

  Future<Company> updateCompanySubscription({
    required String companyId,
    required String subscriptionStatus,
    String? planId,
    String? billingCycle,
    DateTime? subscribedUntil,
  });

  Future<Company> createMyCompany({required String name});

  Future<List<Branch>> getCompanyBranches(String companyId);
  Future<List<Branch>> getAllCompanyBranches(String companyId);
  Future<Branch> createBranch({
    required String companyId,
    required String name,
    String? code,
    String? address,
    String? phone,
  });
  Future<Branch> updateBranch({
    required String branchId,
    required String name,
    String? code,
    String? address,
    String? phone,
  });
  Future<Branch> setBranchActive({
    required String branchId,
    required bool isActive,
  });
}

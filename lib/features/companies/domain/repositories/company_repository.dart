// lib/features/companies/domain/repositories/company_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/branch.dart';
import '../entities/company.dart';

/// Categories of company/branch retrieval and mutation failures that the
/// presentation layer can safely translate into localized user messages.
///
/// Mirrors the Phase 1 `AuthFailureType` convention so the application has a
/// single, consistent way of categorising safe failures. Backend-specific
/// error codes and raw messages never leave the data layer.
enum CompanyFailureType {
  /// The request could not reach the backend.
  network,

  /// The backend rejected the request as unauthorised.
  unauthorized,

  /// The authenticated user has no active membership in any company.
  noCompanies,

  /// The requested company is not accessible to the authenticated user.
  companyNotAccessible,

  /// The authenticated user has no accessible branches in the company.
  noBranches,

  /// The response could not be interpreted, or a validation/constraint
  /// violation was raised by the database (for example a duplicate branch
  /// name or code, or a check-constraint failure).
  invalidResponse,

  /// Any other unclassified failure.
  unknown,
}

/// Domain-level exception raised by [CompanyRepository] operations.
///
/// Carries a safe [CompanyFailureType] rather than a raw backend message so
/// the presentation layer can produce localized, user-friendly errors.
@immutable
class CompanyException extends Equatable implements Exception {
  const CompanyException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  /// Safe, categorized reason for the failure.
  final CompanyFailureType type;

  /// Original error, kept for logging. Never displayed to end users.
  final Object? cause;

  /// Original stack trace, kept for logging.
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'CompanyException(type: ${type.name})';
}

/// Contract for retrieving and mutating companies and branches accessible
/// to the currently authenticated user.
///
/// All access decisions are ultimately enforced by Row Level Security in the
/// database. This repository never accepts a `userId`: the identity is taken
/// from the authenticated session (`auth.uid()`) by the data layer, so a
/// malicious client cannot query on behalf of another user by supplying a
/// forged identifier.
///
/// Mutation operations are restricted by RLS to `owner` and `admin` roles of
/// the target company. Attempts by other roles or by non-members fail with
/// [CompanyFailureType.unauthorized].
abstract interface class CompanyRepository {
  // ---------------------------------------------------------------------------
  // Companies
  // ---------------------------------------------------------------------------

  /// Returns every company the current user has an active membership in.
  ///
  /// The list is empty when the user belongs to no company.
  /// Throws [CompanyException] when the request fails.
  Future<List<Company>> getMyCompanies();

  /// Updates the profile of [companyId] and returns the updated row.
  ///
  /// [name], [currency] and [timezone] are mandatory: the database columns
  /// are `not null`. The remaining fields are optional and are written as
  /// `null` when not provided.
  ///
  /// Throws [CompanyException] when the request fails or when the current
  /// user lacks the required role.
  Future<Company> updateCompany({
    required String companyId,
    required String name,
    required String currency,
    required String timezone,
    String? legalName,
    String? phone,
    String? email,
    String? address,
  });

  // ---------------------------------------------------------------------------
  // Branches — reads
  // ---------------------------------------------------------------------------

  /// Returns every active branch of [companyId] the current user may access.
  ///
  /// The list is empty when the company has no active branches, or when the
  /// current user has no membership in the company (RLS filters rows).
  /// Throws [CompanyException] when the request fails.
  Future<List<Branch>> getCompanyBranches(String companyId);

  /// Returns every branch (active and inactive) of [companyId] the current
  /// user may access. Used by the branches management page so that inactive
  /// branches remain visible and can be reactivated.
  ///
  /// Throws [CompanyException] when the request fails.
  Future<List<Branch>> getAllCompanyBranches(String companyId);

  // ---------------------------------------------------------------------------
  // Branches — mutations
  // ---------------------------------------------------------------------------

  /// Creates a new branch inside [companyId] and returns the created row.
  ///
  /// [name] is mandatory and must be unique per company. [code], when
  /// provided, must also be unique per company.
  ///
  /// Throws [CompanyException] when the request fails or when the current
  /// user lacks the required role.
  Future<Branch> createBranch({
    required String companyId,
    required String name,
    String? code,
    String? address,
    String? phone,
  });

  /// Updates the profile of an existing branch and returns the updated row.
  ///
  /// The owning company is never changed: it is fixed at creation time and
  /// is read from the row inside the database.
  ///
  /// Throws [CompanyException] when the request fails or when the current
  /// user lacks the required role.
  Future<Branch> updateBranch({
    required String branchId,
    required String name,
    String? code,
    String? address,
    String? phone,
  });

  /// Activates or deactivates a branch and returns the updated row.
  ///
  /// Deactivation is a soft delete: the row is kept so that future business
  /// records that reference the branch keep their foreign keys intact. The
  /// caller is responsible for ensuring the company always keeps at least
  /// one active branch.
  ///
  /// Throws [CompanyException] when the request fails or when the current
  /// user lacks the required role.
  Future<Branch> setBranchActive({
    required String branchId,
    required bool isActive,
  });
}

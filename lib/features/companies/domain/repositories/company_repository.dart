// lib/features/companies/domain/repositories/company_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/branch.dart';
import '../entities/company.dart';

/// Categories of company/branch retrieval failures that the presentation
/// layer can safely translate into localized user messages.
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

  /// The response could not be interpreted.
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

/// Contract for retrieving companies and branches accessible to the
/// currently authenticated user.
///
/// All access decisions are ultimately enforced by Row Level Security in the
/// database. This repository never accepts a `userId`: the identity is taken
/// from the authenticated session (`auth.uid()`) by the data layer, so a
/// malicious client cannot query on behalf of another user by supplying a
/// forged identifier.
abstract interface class CompanyRepository {
  /// Returns every company the current user has an active membership in.
  ///
  /// The list is empty when the user belongs to no company.
  /// Throws [CompanyException] when the request fails.
  Future<List<Company>> getMyCompanies();

  /// Returns every branch of [companyId] that the current user may access.
  ///
  /// The list is empty when the company has no accessible branches, or when
  /// the current user has no membership in the company (RLS filters rows).
  /// Throws [CompanyException] when the request fails.
  Future<List<Branch>> getCompanyBranches(String companyId);
}

// lib/features/companies/data/repositories/company_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/branch.dart';
import '../../domain/entities/company.dart';
import '../../domain/repositories/company_repository.dart';
import '../datasources/company_remote_datasource.dart';
import '../models/branch_model.dart';
import '../models/company_model.dart';

/// Concrete implementation of [CompanyRepository] backed by Supabase.
///
/// Responsibilities:
/// * Call the remote data source.
/// * Translate Supabase rows into pure Domain entities.
/// * Translate low-level errors into safe [CompanyException]s carrying a
///   [CompanyFailureType]. Raw backend messages never leave this layer, and
///   no credential or token is ever logged.
///
/// An empty result list is a valid outcome, not an error: the presentation
/// layer decides how to present "no companies" and "no branches" states.
class CompanyRepositoryImpl implements CompanyRepository {
  const CompanyRepositoryImpl(this._remoteDataSource);

  final CompanyRemoteDataSource _remoteDataSource;

  // ---------------------------------------------------------------------------
  // Companies
  // ---------------------------------------------------------------------------

  @override
  Future<List<Company>> getMyCompanies() async {
    try {
      final List<CompanyModel> models =
          await _remoteDataSource.fetchMyCompanies();
      return models
          .map((CompanyModel model) => model.toEntity())
          .toList(growable: false);
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'getMyCompanies');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getMyCompanies');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'getMyCompanies');
    } on CompanyException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getMyCompanies');
    }
  }

  @override
  Future<List<Company>> getAllCompanies() async {
    try {
      final List<CompanyModel> models =
          await _remoteDataSource.fetchAllCompanies();
      return models
          .map((CompanyModel model) => model.toEntity())
          .toList(growable: false);
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(
        error,
        stackTrace,
        operation: 'getAllCompanies',
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(
        error,
        stackTrace,
        operation: 'getAllCompanies',
      );
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(
        error,
        stackTrace,
        operation: 'getAllCompanies',
      );
    } on CompanyException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(
        error,
        stackTrace,
        operation: 'getAllCompanies',
      );
    }
  }

  @override
  Future<Company> updateCompany({
    required String companyId,
    required String name,
    required String currency,
    required String timezone,
    String? legalName,
    String? phone,
    String? email,
    String? address,
  }) async {
    try {
      final CompanyModel model = await _remoteDataSource.updateCompany(
        companyId: companyId,
        name: name,
        currency: currency,
        timezone: timezone,
        legalName: legalName,
        phone: phone,
        email: email,
        address: address,
      );
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'updateCompany');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'updateCompany');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'updateCompany');
    } on CompanyException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'updateCompany');
    }
  }

  @override
  Future<Company> updateCompanySubscription({
    required String companyId,
    required String subscriptionStatus,
    String? planId,
    String? billingCycle,
    DateTime? subscribedUntil,
  }) async {
    try {
      final CompanyModel model =
          await _remoteDataSource.updateCompanySubscription(
        companyId: companyId,
        subscriptionStatus: subscriptionStatus,
        planId: planId,
        billingCycle: billingCycle,
        subscribedUntil: subscribedUntil,
      );
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(
        error,
        stackTrace,
        operation: 'updateCompanySubscription',
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(
        error,
        stackTrace,
        operation: 'updateCompanySubscription',
      );
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(
        error,
        stackTrace,
        operation: 'updateCompanySubscription',
      );
    } on CompanyException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(
        error,
        stackTrace,
        operation: 'updateCompanySubscription',
      );
    }
  }

  @override
  Future<Company> createMyCompany({required String name}) async {
    try {
      final CompanyModel model =
          await _remoteDataSource.createMyCompany(name: name);
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(
        error,
        stackTrace,
        operation: 'createMyCompany',
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(
        error,
        stackTrace,
        operation: 'createMyCompany',
      );
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(
        error,
        stackTrace,
        operation: 'createMyCompany',
      );
    } on CompanyException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(
        error,
        stackTrace,
        operation: 'createMyCompany',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Branches — reads
  // ---------------------------------------------------------------------------

  @override
  Future<List<Branch>> getCompanyBranches(String companyId) async {
    try {
      final List<BranchModel> models =
          await _remoteDataSource.fetchCompanyBranches(companyId);
      return models
          .map((BranchModel model) => model.toEntity())
          .toList(growable: false);
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(
        error,
        stackTrace,
        operation: 'getCompanyBranches',
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(
        error,
        stackTrace,
        operation: 'getCompanyBranches',
      );
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(
        error,
        stackTrace,
        operation: 'getCompanyBranches',
      );
    } on CompanyException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(
        error,
        stackTrace,
        operation: 'getCompanyBranches',
      );
    }
  }

  @override
  Future<List<Branch>> getAllCompanyBranches(String companyId) async {
    try {
      final List<BranchModel> models =
          await _remoteDataSource.fetchAllCompanyBranches(companyId);
      return models
          .map((BranchModel model) => model.toEntity())
          .toList(growable: false);
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(
        error,
        stackTrace,
        operation: 'getAllCompanyBranches',
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(
        error,
        stackTrace,
        operation: 'getAllCompanyBranches',
      );
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(
        error,
        stackTrace,
        operation: 'getAllCompanyBranches',
      );
    } on CompanyException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(
        error,
        stackTrace,
        operation: 'getAllCompanyBranches',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Branches — mutations
  // ---------------------------------------------------------------------------

  @override
  Future<Branch> createBranch({
    required String companyId,
    required String name,
    String? code,
    String? address,
    String? phone,
  }) async {
    try {
      final BranchModel model = await _remoteDataSource.insertBranch(
        companyId: companyId,
        name: name,
        code: code,
        address: address,
        phone: phone,
      );
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'createBranch');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'createBranch');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'createBranch');
    } on CompanyException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'createBranch');
    }
  }

  @override
  Future<Branch> updateBranch({
    required String branchId,
    required String name,
    String? code,
    String? address,
    String? phone,
  }) async {
    try {
      final BranchModel model = await _remoteDataSource.updateBranch(
        branchId: branchId,
        name: name,
        code: code,
        address: address,
        phone: phone,
      );
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'updateBranch');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'updateBranch');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'updateBranch');
    } on CompanyException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'updateBranch');
    }
  }

  @override
  Future<Branch> setBranchActive({
    required String branchId,
    required bool isActive,
  }) async {
    try {
      final BranchModel model = await _remoteDataSource.updateBranchActive(
        branchId: branchId,
        isActive: isActive,
      );
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(
        error,
        stackTrace,
        operation: 'setBranchActive',
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(
        error,
        stackTrace,
        operation: 'setBranchActive',
      );
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(
        error,
        stackTrace,
        operation: 'setBranchActive',
      );
    } on CompanyException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(
        error,
        stackTrace,
        operation: 'setBranchActive',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Error mapping
  // ---------------------------------------------------------------------------

  static CompanyException _mapInvalidResponse(
    FormatException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    AppLogger.error(
      'Invalid response during "$operation" '
      '(FormatException).',
      error,
      stackTrace,
    );
    return CompanyException(
      type: CompanyFailureType.invalidResponse,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static CompanyException _mapPostgrest(
    supabase.PostgrestException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    final CompanyFailureType type = _classifyPostgrest(error);

    AppLogger.warning(
      'PostgREST error during "$operation" mapped to ${type.name} '
      '(code: ${error.code ?? 'n/a'}).',
    );

    return CompanyException(
      type: type,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static CompanyException _mapAuth(
    supabase.AuthException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    AppLogger.warning(
      'Auth error during "$operation" mapped to unauthorized '
      '(code: ${error.code ?? 'n/a'}).',
    );

    return CompanyException(
      type: CompanyFailureType.unauthorized,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static CompanyException _mapUnknown(
    Object error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    final CompanyFailureType type = _looksLikeNetworkFailure(error)
        ? CompanyFailureType.network
        : CompanyFailureType.unknown;

    AppLogger.error(
      'Unhandled error during "$operation" '
      '(runtimeType: ${error.runtimeType}, mapped: ${type.name}).',
      error,
      stackTrace,
    );

    return CompanyException(
      type: type,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static CompanyFailureType _classifyPostgrest(
    supabase.PostgrestException error,
  ) {
    final String code = (error.code ?? '').toLowerCase();
    final String message = error.message.toLowerCase();

    // PostgreSQL SQLSTATE prefixes: 42xxx (syntax/undefined), 23xxx
    // (integrity: unique, check, foreign key), 42501 (insufficient
    // privilege), etc.
    if (code.startsWith('42501')) {
      return CompanyFailureType.unauthorized;
    }
    if (code.startsWith('28')) {
      return CompanyFailureType.unauthorized;
    }
    if (code.startsWith('23')) {
      // Unique / check violation — surfaced to the UI as a generic
      // "invalid input" so the form can prompt the user to review the
      // values (typically a duplicate branch name or code).
      return CompanyFailureType.invalidResponse;
    }
    if (code.startsWith('42')) {
      return CompanyFailureType.invalidResponse;
    }

    if (message.contains('permission denied') ||
        message.contains('row level security') ||
        message.contains('jwt')) {
      return CompanyFailureType.unauthorized;
    }

    if (_messageLooksLikeNetwork(message)) {
      return CompanyFailureType.network;
    }

    return CompanyFailureType.unknown;
  }

  static bool _looksLikeNetworkFailure(Object error) {
    final String description = error.toString().toLowerCase();
    return _messageLooksLikeNetwork(description);
  }

  static bool _messageLooksLikeNetwork(String value) {
    return value.contains('socket') ||
        value.contains('network') ||
        value.contains('connection') ||
        value.contains('timeout') ||
        value.contains('timed out') ||
        value.contains('unreachable') ||
        value.contains('failed host lookup') ||
        value.contains('clientexception');
  }
}

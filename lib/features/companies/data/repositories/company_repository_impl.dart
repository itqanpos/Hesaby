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
    // (integrity), 42501 (insufficient privilege), etc.
    if (code.startsWith('42501')) {
      return CompanyFailureType.unauthorized;
    }
    if (code.startsWith('28')) {
      return CompanyFailureType.unauthorized;
    }
    if (code.startsWith('23')) {
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

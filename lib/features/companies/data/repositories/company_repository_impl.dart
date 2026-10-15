// lib/features/companies/data/repositories/company_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../domain/entities/branch.dart';
import '../../domain/entities/company.dart';
import '../../domain/repositories/company_repository.dart';
import '../datasources/company_remote_datasource.dart';
import '../models/branch_model.dart';
import '../models/company_model.dart';

/// Concrete implementation of [CompanyRepository] backed by Supabase.
class CompanyRepositoryImpl implements CompanyRepository {
  const CompanyRepositoryImpl(this._remoteDataSource);

  final CompanyRemoteDataSource _remoteDataSource;

  // ---------------------------------------------------------------------------
  // Companies — reads
  // ---------------------------------------------------------------------------

  @override
  Future<List<Company>> getMyCompanies() async {
    try {
      final List<CompanyModel> rows =
          await _remoteDataSource.fetchMyCompanies();
      return rows.map((CompanyModel m) => m.toEntity()).toList(
            growable: false,
          );
    } on CompanyException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getMyCompanies');
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getMyCompanies');
    }
  }

  @override
  Future<List<Company>> getAllCompanies() async {
    try {
      final List<CompanyModel> rows =
          await _remoteDataSource.fetchAllCompanies();
      return rows.map((CompanyModel m) => m.toEntity()).toList(
            growable: false,
          );
    } on CompanyException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getAllCompanies');
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getAllCompanies');
    }
  }

  // ---------------------------------------------------------------------------
  // Companies — mutations
  // ---------------------------------------------------------------------------

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
    String? taxNumber,
    String? commercialRegister,
  }) async {
    try {
      final CompanyModel updated =
          await _remoteDataSource.updateCompany(
        companyId: companyId,
        name: name,
        currency: currency,
        timezone: timezone,
        legalName: legalName,
        phone: phone,
        email: email,
        address: address,
        taxNumber: taxNumber,
        commercialRegister: commercialRegister,
      );
      return updated.toEntity();
    } on CompanyException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'updateCompany');
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
      final CompanyModel updated =
          await _remoteDataSource.updateCompanySubscription(
        companyId: companyId,
        subscriptionStatus: subscriptionStatus,
        planId: planId,
        billingCycle: billingCycle,
        subscribedUntil: subscribedUntil,
      );
      return updated.toEntity();
    } on CompanyException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(
        error,
        stackTrace,
        operation: 'updateCompanySubscription',
      );
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
      final CompanyModel created =
          await _remoteDataSource.createMyCompany(name: name);
      return created.toEntity();
    } on CompanyException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'createMyCompany');
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'createMyCompany');
    }
  }

  // ---------------------------------------------------------------------------
  // Branches — reads
  // ---------------------------------------------------------------------------

  @override
  Future<List<Branch>> getCompanyBranches(String companyId) async {
    try {
      final List<BranchModel> rows =
          await _remoteDataSource.fetchCompanyBranches(companyId);
      return rows.map((BranchModel m) => m.toEntity()).toList(
            growable: false,
          );
    } on CompanyException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getCompanyBranches');
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getCompanyBranches');
    }
  }

  @override
  Future<List<Branch>> getAllCompanyBranches(String companyId) async {
    try {
      final List<BranchModel> rows =
          await _remoteDataSource.fetchAllCompanyBranches(companyId);
      return rows.map((BranchModel m) => m.toEntity()).toList(
            growable: false,
          );
    } on CompanyException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(
        error,
        stackTrace,
        operation: 'getAllCompanyBranches',
      );
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
      final BranchModel created = await _remoteDataSource.insertBranch(
        companyId: companyId,
        name: name,
        code: code,
        address: address,
        phone: phone,
      );
      return created.toEntity();
    } on CompanyException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'createBranch');
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
      final BranchModel updated = await _remoteDataSource.updateBranch(
        branchId: branchId,
        name: name,
        code: code,
        address: address,
        phone: phone,
      );
      return updated.toEntity();
    } on CompanyException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'updateBranch');
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
      final BranchModel updated = await _remoteDataSource.updateBranchActive(
        branchId: branchId,
        isActive: isActive,
      );
      return updated.toEntity();
    } on CompanyException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'setBranchActive');
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'setBranchActive');
    }
  }
}

// ============================================================================
// Error mapping
// ============================================================================

CompanyException _mapPostgrest(
  supabase.PostgrestException error,
  StackTrace stackTrace, {
  required String operation,
}) {
  final CompanyFailureType type = _classify(error);
  return CompanyException(
    type: type,
    cause: error,
    stackTrace: stackTrace,
  );
}

CompanyException _mapUnknown(
  Object error,
  StackTrace stackTrace, {
  required String operation,
}) {
  return CompanyException(
    type: CompanyFailureType.unknown,
    cause: error,
    stackTrace: stackTrace,
  );
}

CompanyFailureType _classify(supabase.PostgrestException error) {
  final String code = (error.code ?? '').toUpperCase();
  final String message = error.message.toLowerCase();

  if (code == 'PGRST116') {
    return CompanyFailureType.companyNotAccessible;
  }
  if (code.startsWith('42501') || code.startsWith('28')) {
    return CompanyFailureType.unauthorized;
  }
  if (message.contains('permission denied') ||
      message.contains('row level security') ||
      message.contains('jwt')) {
    return CompanyFailureType.unauthorized;
  }
  return CompanyFailureType.unknown;
}

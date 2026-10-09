// lib/features/companies/data/repositories/company_members_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/company_member.dart';
import '../../domain/repositories/company_members_repository.dart';
import '../datasources/company_members_remote_datasource.dart';
import '../models/company_member_model.dart';

/// Concrete implementation of [CompanyMembersRepository] backed by Supabase.
class CompanyMembersRepositoryImpl implements CompanyMembersRepository {
  const CompanyMembersRepositoryImpl(this._dataSource);

  final CompanyMembersRemoteDataSource _dataSource;

  @override
  Future<List<CompanyMember>> listMembers(String companyId) async {
    try {
      final List<CompanyMemberModel> models =
          await _dataSource.listMembers(companyId);
      return models
          .map((CompanyMemberModel m) => m.toEntity())
          .toList(growable: false);
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'listMembers');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'listMembers');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'listMembers');
    } on MemberException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'listMembers');
    }
  }

  @override
  Future<CompanyMember?> getMemberByUser({
    required String companyId,
    required String userId,
  }) async {
    try {
      final CompanyMemberModel? model = await _dataSource.getMemberByUser(
        companyId: companyId,
        userId: userId,
      );
      return model?.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(
        error,
        stackTrace,
        operation: 'getMemberByUser',
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getMemberByUser');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'getMemberByUser');
    } on MemberException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getMemberByUser');
    }
  }

  @override
  Future<CompanyMember> updateMember({
    required String memberId,
    String? role,
    bool? isActive,
    List<String>? deniedPermissions,
  }) async {
    try {
      final CompanyMemberModel model = await _dataSource.updateMember(
        memberId: memberId,
        role: role,
        isActive: isActive,
        deniedPermissions: deniedPermissions,
      );
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'updateMember');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'updateMember');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'updateMember');
    } on MemberException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'updateMember');
    }
  }

  // ---------------------------------------------------------------------------
  // Error mapping
  // ---------------------------------------------------------------------------

  static MemberException _mapInvalidResponse(
    FormatException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    AppLogger.error(
      'Invalid response during "$operation" (FormatException).',
      error,
      stackTrace,
    );
    return MemberException(
      type: MemberFailureType.invalidResponse,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static MemberException _mapPostgrest(
    supabase.PostgrestException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    final MemberFailureType type = _classifyPostgrest(error);

    AppLogger.warning(
      'Member PostgREST error during "$operation" '
      'mapped to ${type.name} (code: ${error.code ?? 'n/a'}).',
    );

    return MemberException(
      type: type,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static MemberException _mapAuth(
    supabase.AuthException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    AppLogger.warning(
      'Member auth error during "$operation" mapped to unauthorized.',
    );
    return MemberException(
      type: MemberFailureType.unauthorized,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static MemberException _mapUnknown(
    Object error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    final MemberFailureType type = _looksLikeNetwork(error)
        ? MemberFailureType.network
        : MemberFailureType.unknown;

    AppLogger.error(
      'Unhandled member error during "$operation" '
      '(runtimeType: ${error.runtimeType}, mapped: ${type.name}).',
      error,
      stackTrace,
    );

    return MemberException(
      type: type,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static MemberFailureType _classifyPostgrest(
    supabase.PostgrestException error,
  ) {
    final String code = (error.code ?? '').toUpperCase();
    final String message = error.message.toLowerCase();
    final String full = error.toString().toLowerCase();

    if (code == '23514') {
      if (message.contains('owner') ||
          full.contains('cannot revoke permissions from an owner')) {
        return MemberFailureType.cannotModifyOwner;
      }
      if (message.contains('last active owner')) {
        return MemberFailureType.lastOwnerProtection;
      }
      return MemberFailureType.invalidResponse;
    }

    if (code == 'PGRST116') {
      return MemberFailureType.notFound;
    }
    if (code.startsWith('42501') || code.startsWith('28')) {
      return MemberFailureType.unauthorized;
    }
    if (code.startsWith('42')) {
      return MemberFailureType.invalidResponse;
    }

    if (message.contains('permission denied') ||
        message.contains('row level security') ||
        message.contains('jwt')) {
      return MemberFailureType.unauthorized;
    }

    if (full.contains('cannot revoke permissions from an owner')) {
      return MemberFailureType.cannotModifyOwner;
    }
    if (full.contains('last active owner')) {
      return MemberFailureType.lastOwnerProtection;
    }

    if (_messageLooksLikeNetwork(message)) {
      return MemberFailureType.network;
    }

    return MemberFailureType.unknown;
  }

  static bool _looksLikeNetwork(Object error) =>
      _messageLooksLikeNetwork(error.toString().toLowerCase());

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

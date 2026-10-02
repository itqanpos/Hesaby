// lib/features/products/data/repositories/unit_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/unit.dart';
import '../../domain/repositories/unit_repository.dart';
import '../datasources/unit_remote_datasource.dart';
import '../models/unit_model.dart';

/// Concrete implementation of [UnitRepository] backed by Supabase.
///
/// Responsibilities:
/// * Call the remote data source.
/// * Translate [UnitModel] rows into pure [Unit] entities.
/// * Translate Supabase / PostgREST errors into safe [UnitException]s
///   carrying a [UnitFailureType]. Raw backend messages never leave this
///   layer, and no credential or token is ever logged.
class UnitRepositoryImpl implements UnitRepository {
  const UnitRepositoryImpl(this._remoteDataSource);

  final UnitRemoteDataSource _remoteDataSource;

  @override
  Future<List<Unit>> listUnits(String companyId) async {
    try {
      final List<UnitModel> models =
          await _remoteDataSource.listUnits(companyId);
      return models
          .map((UnitModel model) => model.toEntity())
          .toList(growable: false);
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'listUnits');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'listUnits');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'listUnits');
    } on UnitException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'listUnits');
    }
  }

  @override
  Future<Unit> getUnit(String unitId) async {
    try {
      final UnitModel model = await _remoteDataSource.getUnit(unitId);
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'getUnit');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getUnit');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'getUnit');
    } on UnitException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getUnit');
    }
  }

  @override
  Future<Unit> createUnit({
    required String companyId,
    required String name,
    String? symbol,
  }) async {
    try {
      final UnitModel model = await _remoteDataSource.createUnit(
        companyId: companyId,
        name: name,
        symbol: symbol,
      );
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'createUnit');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'createUnit');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'createUnit');
    } on UnitException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'createUnit');
    }
  }

  @override
  Future<Unit> updateUnit({
    required String unitId,
    String? name,
    String? symbol,
    bool clearSymbol = false,
    bool? isActive,
  }) async {
    try {
      final UnitModel model = await _remoteDataSource.updateUnit(
        unitId: unitId,
        name: name,
        symbol: symbol,
        clearSymbol: clearSymbol,
        isActive: isActive,
      );
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'updateUnit');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'updateUnit');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'updateUnit');
    } on UnitException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'updateUnit');
    }
  }

  @override
  Future<void> deleteUnit(String unitId) async {
    try {
      await _remoteDataSource.deleteUnit(unitId);
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'deleteUnit');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'deleteUnit');
    } on UnitException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'deleteUnit');
    }
  }

  // ---------------------------------------------------------------------------
  // Error mapping
  // ---------------------------------------------------------------------------

  static UnitException _mapInvalidResponse(
    FormatException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    AppLogger.error(
      'Invalid response during "$operation" (FormatException).',
      error,
      stackTrace,
    );
    return UnitException(
      type: UnitFailureType.invalidResponse,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static UnitException _mapPostgrest(
    supabase.PostgrestException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    final UnitFailureType type = _classifyPostgrest(error);

    AppLogger.warning(
      'PostgREST error during "$operation" mapped to ${type.name} '
      '(code: ${error.code ?? 'n/a'}).',
    );

    return UnitException(
      type: type,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static UnitException _mapAuth(
    supabase.AuthException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    AppLogger.warning(
      'Auth error during "$operation" mapped to unauthorized '
      '(code: ${error.code ?? 'n/a'}).',
    );

    return UnitException(
      type: UnitFailureType.unauthorized,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static UnitException _mapUnknown(
    Object error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    final UnitFailureType type = _looksLikeNetworkFailure(error)
        ? UnitFailureType.network
        : UnitFailureType.unknown;

    AppLogger.error(
      'Unhandled error during "$operation" '
      '(runtimeType: ${error.runtimeType}, mapped: ${type.name}).',
      error,
      stackTrace,
    );

    return UnitException(
      type: type,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  /// Classifies a PostgREST error into a safe [UnitFailureType].
  ///
  /// Both name uniqueness and symbol uniqueness are reported by PostgreSQL
  /// as `23505` (unique_violation). The specific constraint name is
  /// therefore inspected in the error message to distinguish the two cases:
  /// `uniq_units_company_symbol` → symbolConflict; anything else → nameConflict.
  static UnitFailureType _classifyPostgrest(
    supabase.PostgrestException error,
  ) {
    final String code = (error.code ?? '').toUpperCase();
    final String message = error.message.toLowerCase();
    final String full = error.toString().toLowerCase();

    if (code == '23505') {
      if (full.contains('uniq_units_company_symbol')) {
        return UnitFailureType.symbolConflict;
      }
      return UnitFailureType.nameConflict;
    }
    if (code == '23503') {
      return UnitFailureType.inUse;
    }
    if (code == 'PGRST116') {
      return UnitFailureType.notFound;
    }
    if (code.startsWith('42501') || code.startsWith('28')) {
      return UnitFailureType.unauthorized;
    }
    if (code.startsWith('42')) {
      return UnitFailureType.invalidResponse;
    }

    if (message.contains('permission denied') ||
        message.contains('row level security') ||
        message.contains('jwt')) {
      return UnitFailureType.unauthorized;
    }

    if (full.contains('uniq_units_company_symbol')) {
      return UnitFailureType.symbolConflict;
    }
    if (message.contains('duplicate key') ||
        message.contains('unique constraint')) {
      return UnitFailureType.nameConflict;
    }

    if (message.contains('foreign key') ||
        message.contains('violates foreign key')) {
      return UnitFailureType.inUse;
    }

    if (_messageLooksLikeNetwork(message)) {
      return UnitFailureType.network;
    }

    return UnitFailureType.unknown;
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

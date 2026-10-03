// lib/features/suppliers/data/repositories/supplier_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/supplier.dart';
import '../../domain/repositories/supplier_repository.dart';
import '../datasources/supplier_remote_datasource.dart';
import '../models/supplier_model.dart';

/// Concrete implementation of [SupplierRepository] backed by Supabase.
///
/// Responsibilities:
/// * Call the remote data source.
/// * Translate [SupplierModel] rows into pure [Supplier] entities.
/// * Translate Supabase / PostgREST errors into safe [SupplierException]s
///   carrying a [SupplierFailureType]. Raw backend messages never leave
///   this layer, and no credential or token is ever logged.
///
/// Typed error disambiguation:
/// All three uniqueness violations (name, code, phone) report the same
/// PostgreSQL code `23505`. The specific failure type is therefore
/// resolved by inspecting the constraint name present in the error text.
/// Constraint names are declared in the Phase 6 migration and are stable,
/// so this mapping is deterministic.
class SupplierRepositoryImpl implements SupplierRepository {
  const SupplierRepositoryImpl(this._remoteDataSource);

  final SupplierRemoteDataSource _remoteDataSource;

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  @override
  Future<List<Supplier>> listSuppliers(
    String companyId, {
    bool includeInactive = false,
  }) async {
    try {
      final List<SupplierModel> models =
          await _remoteDataSource.listSuppliers(
        companyId,
        includeInactive: includeInactive,
      );
      return models
          .map((SupplierModel model) => model.toEntity())
          .toList(growable: false);
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'listSuppliers');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'listSuppliers');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'listSuppliers');
    } on SupplierException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'listSuppliers');
    }
  }

  @override
  Future<Supplier> getSupplier(String supplierId) async {
    try {
      final SupplierModel model =
          await _remoteDataSource.getSupplier(supplierId);
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'getSupplier');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getSupplier');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'getSupplier');
    } on SupplierException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getSupplier');
    }
  }

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  @override
  Future<Supplier> createSupplier({
    required String companyId,
    required String name,
    String? code,
    String? phone,
    String? email,
    String? address,
    String? notes,
  }) async {
    try {
      final SupplierModel model = await _remoteDataSource.createSupplier(
        companyId: companyId,
        name: name,
        code: code,
        phone: phone,
        email: email,
        address: address,
        notes: notes,
      );
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'createSupplier');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'createSupplier');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'createSupplier');
    } on SupplierException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'createSupplier');
    }
  }

  @override
  Future<Supplier> updateSupplier({
    required String supplierId,
    String? name,
    String? code,
    bool clearCode = false,
    String? phone,
    bool clearPhone = false,
    String? email,
    bool clearEmail = false,
    String? address,
    bool clearAddress = false,
    String? notes,
    bool clearNotes = false,
    bool? isActive,
  }) async {
    try {
      final SupplierModel model = await _remoteDataSource.updateSupplier(
        supplierId: supplierId,
        name: name,
        code: code,
        clearCode: clearCode,
        phone: phone,
        clearPhone: clearPhone,
        email: email,
        clearEmail: clearEmail,
        address: address,
        clearAddress: clearAddress,
        notes: notes,
        clearNotes: clearNotes,
        isActive: isActive,
      );
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'updateSupplier');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'updateSupplier');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'updateSupplier');
    } on SupplierException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'updateSupplier');
    }
  }

  @override
  Future<void> deleteSupplier(String supplierId) async {
    try {
      await _remoteDataSource.deleteSupplier(supplierId);
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'deleteSupplier');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'deleteSupplier');
    } on SupplierException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'deleteSupplier');
    }
  }

  // ---------------------------------------------------------------------------
  // Error mapping
  // ---------------------------------------------------------------------------

  static SupplierException _mapInvalidResponse(
    FormatException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    AppLogger.error(
      'Invalid response during "$operation" (FormatException).',
      error,
      stackTrace,
    );
    return SupplierException(
      type: SupplierFailureType.invalidResponse,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static SupplierException _mapPostgrest(
    supabase.PostgrestException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    final SupplierFailureType type = _classifyPostgrest(error);

    AppLogger.warning(
      'PostgREST error during "$operation" mapped to ${type.name} '
      '(code: ${error.code ?? 'n/a'}).',
    );

    return SupplierException(
      type: type,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static SupplierException _mapAuth(
    supabase.AuthException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    AppLogger.warning(
      'Auth error during "$operation" mapped to unauthorized '
      '(code: ${error.code ?? 'n/a'}).',
    );

    return SupplierException(
      type: SupplierFailureType.unauthorized,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static SupplierException _mapUnknown(
    Object error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    final SupplierFailureType type = _looksLikeNetworkFailure(error)
        ? SupplierFailureType.network
        : SupplierFailureType.unknown;

    AppLogger.error(
      'Unhandled error during "$operation" '
      '(runtimeType: ${error.runtimeType}, mapped: ${type.name}).',
      error,
      stackTrace,
    );

    return SupplierException(
      type: type,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  /// Classifies a PostgREST error into a safe [SupplierFailureType].
  ///
  /// Constraint names referenced below are declared in the Phase 6
  /// migration:
  /// * `suppliers_company_name_unique`  → nameConflict
  /// * `uniq_suppliers_company_code`    → codeConflict
  /// * `uniq_suppliers_company_phone`   → phoneConflict
  /// * any other 23505                  → nameConflict (default)
  /// * any 23503                        → inUse (reserved for Phase 7)
  ///
  /// Codes handled explicitly:
  /// * `PGRST116` → notFound
  /// * `42501` / `28xxx` → unauthorized
  /// * `42xxx` → invalidResponse
  static SupplierFailureType _classifyPostgrest(
    supabase.PostgrestException error,
  ) {
    final String code = (error.code ?? '').toUpperCase();
    final String message = error.message.toLowerCase();
    final String full = error.toString().toLowerCase();

    if (code == '23505') {
      if (full.contains('uniq_suppliers_company_code')) {
        return SupplierFailureType.codeConflict;
      }
      if (full.contains('uniq_suppliers_company_phone')) {
        return SupplierFailureType.phoneConflict;
      }
      // Covers `suppliers_company_name_unique` explicitly, and any other
      // uniqueness on the table as a defensive default.
      return SupplierFailureType.nameConflict;
    }

    if (code == '23503') {
      return SupplierFailureType.inUse;
    }

    if (code == 'PGRST116') {
      return SupplierFailureType.notFound;
    }

    if (code.startsWith('42501') || code.startsWith('28')) {
      return SupplierFailureType.unauthorized;
    }

    if (code.startsWith('42')) {
      return SupplierFailureType.invalidResponse;
    }

    if (message.contains('permission denied') ||
        message.contains('row level security') ||
        message.contains('jwt')) {
      return SupplierFailureType.unauthorized;
    }

    // Textual fallbacks for environments where the constraint name is not
    // included in `error.code` (older PostgREST versions).
    if (full.contains('uniq_suppliers_company_code')) {
      return SupplierFailureType.codeConflict;
    }
    if (full.contains('uniq_suppliers_company_phone')) {
      return SupplierFailureType.phoneConflict;
    }
    if (full.contains('suppliers_company_name_unique')) {
      return SupplierFailureType.nameConflict;
    }

    if (message.contains('duplicate key') ||
        message.contains('unique constraint')) {
      return SupplierFailureType.nameConflict;
    }

    if (message.contains('foreign key') ||
        message.contains('violates foreign key')) {
      return SupplierFailureType.inUse;
    }

    if (_messageLooksLikeNetwork(message)) {
      return SupplierFailureType.network;
    }

    return SupplierFailureType.unknown;
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

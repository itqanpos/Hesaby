// lib/features/inventory/data/repositories/inventory_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/inventory_balance.dart';
import '../../domain/entities/stock_movement.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../datasources/inventory_remote_datasource.dart';
import '../models/inventory_balance_model.dart';
import '../models/stock_movement_model.dart';

/// Concrete implementation of [InventoryRepository] backed by Supabase.
class InventoryRepositoryImpl implements InventoryRepository {
  const InventoryRepositoryImpl(this._remoteDataSource);

  final InventoryRemoteDataSource _remoteDataSource;

  // ---------------------------------------------------------------------------
  // Balances (read-only)
  // ---------------------------------------------------------------------------

  @override
  Future<List<InventoryBalance>> listBalances(
    String companyId,
    String branchId, {
    bool onlyInStock = true,
  }) async {
    try {
      final List<InventoryBalanceModel> models =
          await _remoteDataSource.listBalances(
        companyId,
        branchId,
        onlyInStock: onlyInStock,
      );
      return models
          .map((InventoryBalanceModel model) => model.toEntity())
          .toList(growable: false);
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'listBalances');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'listBalances');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'listBalances');
    } on InventoryException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'listBalances');
    }
  }

  @override
  Future<InventoryBalance> getBalance({
    required String companyId,
    required String branchId,
    required String productId,
  }) async {
    try {
      final InventoryBalanceModel model =
          await _remoteDataSource.getBalance(
        companyId: companyId,
        branchId: branchId,
        productId: productId,
      );
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'getBalance');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getBalance');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'getBalance');
    } on InventoryException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getBalance');
    }
  }

  // ---------------------------------------------------------------------------
  // Movements
  // ---------------------------------------------------------------------------

  @override
  Future<List<StockMovement>> listMovements(
    String companyId, {
    String? branchId,
    String? productId,
    int? limit,
  }) async {
    try {
      final List<StockMovementModel> models =
          await _remoteDataSource.listMovements(
        companyId,
        branchId: branchId,
        productId: productId,
        limit: limit,
      );
      return models
          .map((StockMovementModel model) => model.toEntity())
          .toList(growable: false);
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'listMovements');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'listMovements');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'listMovements');
    } on InventoryException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'listMovements');
    }
  }

  @override
  Future<StockMovement> recordMovement({
    required String companyId,
    required String branchId,
    required String productId,
    required String movementType,
    required double quantity,
    String? unitId,
    double? unitCost,
    String? referenceType,
    String? referenceId,
    String? notes,
  }) async {
    try {
      final StockMovementModel model =
          await _remoteDataSource.recordMovement(
        companyId: companyId,
        branchId: branchId,
        productId: productId,
        movementType: movementType,
        quantity: quantity,
        unitId: unitId,
        unitCost: unitCost,
        referenceType: referenceType,
        referenceId: referenceId,
        notes: notes,
      );
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'recordMovement');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'recordMovement');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'recordMovement');
    } on InventoryException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'recordMovement');
    }
  }

  // ---------------------------------------------------------------------------
  // Error mapping (unchanged)
  // ---------------------------------------------------------------------------

  static InventoryException _mapInvalidResponse(
    FormatException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    AppLogger.error(
      'Invalid response during "$operation" (FormatException).',
      error,
      stackTrace,
    );
    return InventoryException(
      type: InventoryFailureType.invalidResponse,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static InventoryException _mapPostgrest(
    supabase.PostgrestException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    final InventoryFailureType type = _classifyPostgrest(error);

    AppLogger.warning(
      'PostgREST error during "$operation" mapped to ${type.name} '
      '(code: ${error.code ?? 'n/a'}).',
    );

    return InventoryException(
      type: type,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static InventoryException _mapAuth(
    supabase.AuthException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    AppLogger.warning(
      'Auth error during "$operation" mapped to unauthorized '
      '(code: ${error.code ?? 'n/a'}).',
    );

    return InventoryException(
      type: InventoryFailureType.unauthorized,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static InventoryException _mapUnknown(
    Object error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    final InventoryFailureType type = _looksLikeNetworkFailure(error)
        ? InventoryFailureType.network
        : InventoryFailureType.unknown;

    AppLogger.error(
      'Unhandled error during "$operation" '
      '(runtimeType: ${error.runtimeType}, mapped: ${type.name}).',
      error,
      stackTrace,
    );

    return InventoryException(
      type: type,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static InventoryFailureType _classifyPostgrest(
    supabase.PostgrestException error,
  ) {
    final String code = (error.code ?? '').toUpperCase();
    final String message = error.message.toLowerCase();
    final String full = error.toString().toLowerCase();

    if (code == '23503') {
      if (full.contains('stock_movements_branch_company_fk') ||
          full.contains('inventory_balances_branch_company_fk')) {
        return InventoryFailureType.branchNotFound;
      }
      if (full.contains('stock_movements_product_company_fk') ||
          full.contains('inventory_balances_product_company_fk')) {
        return InventoryFailureType.productNotFound;
      }
      if (full.contains('stock_movements_unit_company_fk')) {
        return InventoryFailureType.invalidMovement;
      }
      return InventoryFailureType.notFound;
    }

    if (code == '23514') {
      if (message.contains('insufficient stock') ||
          full.contains('insufficient stock')) {
        return InventoryFailureType.insufficientStock;
      }
      if (full.contains('stock_movements_type_valid') ||
          full.contains('movement_type')) {
        return InventoryFailureType.invalidMovementType;
      }
      if (full.contains('stock_movements_quantity_not_zero') ||
          full.contains('stock_movements_reference_pair') ||
          full.contains('stock_movements_unit_cost_not_negative')) {
        return InventoryFailureType.invalidMovement;
      }
      return InventoryFailureType.invalidMovement;
    }

    if (code == 'PGRST116') {
      return InventoryFailureType.notFound;
    }

    if (code.startsWith('42501') || code.startsWith('28')) {
      return InventoryFailureType.unauthorized;
    }

    if (code.startsWith('42')) {
      return InventoryFailureType.invalidResponse;
    }

    if (message.contains('permission denied') ||
        message.contains('row level security') ||
        message.contains('jwt')) {
      return InventoryFailureType.unauthorized;
    }

    if (full.contains('insufficient stock')) {
      return InventoryFailureType.insufficientStock;
    }

    if (full.contains('stock_movements_branch_company_fk')) {
      return InventoryFailureType.branchNotFound;
    }
    if (full.contains('stock_movements_product_company_fk')) {
      return InventoryFailureType.productNotFound;
    }

    if (full.contains('stock_movements_type_valid')) {
      return InventoryFailureType.invalidMovementType;
    }

    if (full.contains('stock_movements_quantity_not_zero') ||
        full.contains('stock_movements_reference_pair') ||
        full.contains('stock_movements_unit_cost_not_negative')) {
      return InventoryFailureType.invalidMovement;
    }

    if (message.contains('duplicate key') ||
        message.contains('unique constraint')) {
      return InventoryFailureType.invalidMovement;
    }

    if (message.contains('foreign key') ||
        message.contains('violates foreign key')) {
      return InventoryFailureType.notFound;
    }

    if (_messageLooksLikeNetwork(message)) {
      return InventoryFailureType.network;
    }

    return InventoryFailureType.unknown;
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

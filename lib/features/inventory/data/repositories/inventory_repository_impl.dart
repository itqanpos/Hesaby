// lib/features/inventory/data/repositories/inventory_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../domain/entities/inventory_balance.dart';
import '../../domain/entities/stock_count.dart';
import '../../domain/entities/stock_movement.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../datasources/inventory_remote_datasource.dart';
import '../models/inventory_balance_model.dart';
import '../models/stock_count_model.dart';
import '../models/stock_movement_model.dart';

/// Concrete implementation of [InventoryRepository] backed by Supabase.
class InventoryRepositoryImpl implements InventoryRepository {
  const InventoryRepositoryImpl(this._remoteDataSource);

  final InventoryRemoteDataSource _remoteDataSource;

  // ---------------------------------------------------------------------------
  // Balances
  // ---------------------------------------------------------------------------

  @override
  Future<List<InventoryBalance>> listBalances(
    String companyId,
    String branchId, {
    bool onlyInStock = true,
  }) async {
    try {
      final List<InventoryBalanceModel> rows =
          await _remoteDataSource.listBalances(
        companyId,
        branchId,
        onlyInStock: onlyInStock,
      );
      return rows.map((InventoryBalanceModel m) => m.toEntity()).toList();
    } on InventoryException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'listBalances');
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
    } on InventoryException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getBalance');
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
      final List<StockMovementModel> rows =
          await _remoteDataSource.listMovements(
        companyId,
        branchId: branchId,
        productId: productId,
        limit: limit,
      );
      return rows.map((StockMovementModel m) => m.toEntity()).toList();
    } on InventoryException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'listMovements');
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
      final StockMovementModel created =
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
      return created.toEntity();
    } on InventoryException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'recordMovement');
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'recordMovement');
    }
  }

  // ---------------------------------------------------------------------------
  // Stock count sessions
  // ---------------------------------------------------------------------------

  @override
  Future<List<StockCountSession>> listStockCountSessions(
    String companyId, {
    String? branchId,
    String? status,
    int? limit,
  }) async {
    try {
      final List<StockCountSessionModel> rows =
          await _remoteDataSource.listStockCountSessions(
        companyId,
        branchId: branchId,
        status: status,
        limit: limit,
      );
      return rows
          .map((StockCountSessionModel m) => m.toEntity())
          .toList(growable: false);
    } on InventoryException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(
        error,
        stackTrace,
        operation: 'listStockCountSessions',
      );
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(
        error,
        stackTrace,
        operation: 'listStockCountSessions',
      );
    }
  }

  @override
  Future<StockCountSession> getStockCountSession(String sessionId) async {
    try {
      final StockCountSessionModel model =
          await _remoteDataSource.getStockCountSession(sessionId);
      return model.toEntity();
    } on InventoryException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(
        error,
        stackTrace,
        operation: 'getStockCountSession',
      );
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(
        error,
        stackTrace,
        operation: 'getStockCountSession',
      );
    }
  }

  @override
  Future<List<StockCountItem>> listStockCountItems(
    String sessionId,
  ) async {
    try {
      final List<StockCountItemModel> rows =
          await _remoteDataSource.listStockCountItems(sessionId);
      return rows
          .map((StockCountItemModel m) => m.toEntity())
          .toList(growable: false);
    } on InventoryException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(
        error,
        stackTrace,
        operation: 'listStockCountItems',
      );
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(
        error,
        stackTrace,
        operation: 'listStockCountItems',
      );
    }
  }

  @override
  Future<String> createStockCountSession({
    required String companyId,
    required String branchId,
    String? notes,
  }) async {
    try {
      return await _remoteDataSource.createStockCountSession(
        companyId: companyId,
        branchId: branchId,
        notes: notes,
      );
    } on InventoryException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(
        error,
        stackTrace,
        operation: 'createStockCountSession',
      );
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(
        error,
        stackTrace,
        operation: 'createStockCountSession',
      );
    }
  }

  @override
  Future<void> setStockCountItemActual({
    required String itemId,
    required double actualQuantity,
    String? notes,
  }) async {
    try {
      await _remoteDataSource.setStockCountItemActual(
        itemId: itemId,
        actualQuantity: actualQuantity,
        notes: notes,
      );
    } on InventoryException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(
        error,
        stackTrace,
        operation: 'setStockCountItemActual',
      );
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(
        error,
        stackTrace,
        operation: 'setStockCountItemActual',
      );
    }
  }

  @override
  Future<int> confirmStockCountSession(String sessionId) async {
    try {
      return await _remoteDataSource.confirmStockCountSession(sessionId);
    } on InventoryException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(
        error,
        stackTrace,
        operation: 'confirmStockCountSession',
      );
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(
        error,
        stackTrace,
        operation: 'confirmStockCountSession',
      );
    }
  }

  @override
  Future<void> cancelStockCountSession(String sessionId) async {
    try {
      await _remoteDataSource.cancelStockCountSession(sessionId);
    } on InventoryException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(
        error,
        stackTrace,
        operation: 'cancelStockCountSession',
      );
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(
        error,
        stackTrace,
        operation: 'cancelStockCountSession',
      );
    }
  }
}

// ============================================================================
// Error mapping
// ============================================================================

InventoryException _mapPostgrest(
  supabase.PostgrestException error,
  StackTrace stackTrace, {
  required String operation,
}) {
  final InventoryFailureType type = _classify(error);
  return InventoryException(
    type: type,
    cause: error,
    stackTrace: stackTrace,
  );
}

InventoryException _mapUnknown(
  Object error,
  StackTrace stackTrace, {
  required String operation,
}) {
  return InventoryException(
    type: InventoryFailureType.unknown,
    cause: error,
    stackTrace: stackTrace,
  );
}

InventoryFailureType _classify(supabase.PostgrestException error) {
  final String code = (error.code ?? '').toUpperCase();
  final String message = error.message.toLowerCase();

  if (code == 'PGRST116' || code == 'P0002') {
    return InventoryFailureType.notFound;
  }
  if (code.startsWith('42501') || code.startsWith('28')) {
    return InventoryFailureType.unauthorized;
  }
  if (code == '23514' || code == '22023') {
    return InventoryFailureType.invalidMovement;
  }
  if (code.startsWith('23')) {
    return InventoryFailureType.invalidMovement;
  }
  if (message.contains('permission denied') ||
      message.contains('row level security') ||
      message.contains('jwt')) {
    return InventoryFailureType.unauthorized;
  }
  if (message.contains('not found')) {
    return InventoryFailureType.notFound;
  }
  return InventoryFailureType.unknown;
}

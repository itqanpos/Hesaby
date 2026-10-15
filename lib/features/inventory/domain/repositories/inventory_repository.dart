// lib/features/inventory/domain/repositories/inventory_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/inventory_balance.dart';
import '../entities/stock_count.dart';
import '../entities/stock_movement.dart';

enum InventoryFailureType {
  network,
  unauthorized,
  notFound,
  insufficientStock,
  productNotFound,
  branchNotFound,
  invalidMovementType,
  invalidMovement,
  invalidResponse,
  unknown,
}

@immutable
class InventoryException extends Equatable implements Exception {
  const InventoryException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  final InventoryFailureType type;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'InventoryException(type: ${type.name})';
}

/// Contract for inventory operations.
abstract interface class InventoryRepository {
  // ---------------------------------------------------------------------------
  // Balances (read-only, derived)
  // ---------------------------------------------------------------------------

  Future<List<InventoryBalance>> listBalances(
    String companyId,
    String branchId, {
    bool onlyInStock = true,
  });

  Future<InventoryBalance> getBalance({
    required String companyId,
    required String branchId,
    required String productId,
  });

  // ---------------------------------------------------------------------------
  // Movements (append-only ledger)
  // ---------------------------------------------------------------------------

  Future<List<StockMovement>> listMovements(
    String companyId, {
    String? branchId,
    String? productId,
    int? limit,
  });

  /// Records a stock movement.
  ///
  /// [quantity] **must already be expressed in the product's base unit** —
  /// the caller is responsible for multiplying the user-entered quantity by
  /// `product_units.conversion_factor`. When [unitId] is provided, it is
  /// stored verbatim on the row for later reporting; it does not influence
  /// the stored quantity.
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
  });

  // ---------------------------------------------------------------------------
  // Stock count sessions
  // ---------------------------------------------------------------------------

  /// Lists the stock-count sessions of a company.
  ///
  /// When [branchId] is provided, only that branch's sessions are returned.
  /// When [status] is provided (one of [StockCountStatus] values), only
  /// sessions with that status are returned.
  Future<List<StockCountSession>> listStockCountSessions(
    String companyId, {
    String? branchId,
    String? status,
    int? limit,
  });

  /// Returns the session with [sessionId], or throws when inaccessible.
  Future<StockCountSession> getStockCountSession(String sessionId);

  /// Returns every item of [sessionId], oldest first.
  Future<List<StockCountItem>> listStockCountItems(String sessionId);

  /// Creates a new draft session for [branchId], pre-populated with the
  /// current balances of the branch. Returns the new session id.
  Future<String> createStockCountSession({
    required String companyId,
    required String branchId,
    String? notes,
  });

  /// Updates the actual counted quantity of one item.
  ///
  /// [actualQuantity] must be >= 0. The session must still be in `draft`.
  Future<void> setStockCountItemActual({
    required String itemId,
    required double actualQuantity,
    String? notes,
  });

  /// Confirms [sessionId]. Non-zero variances are written as
  /// `adjustment_in` / `adjustment_out` movements. Returns the number of
  /// movements written.
  Future<int> confirmStockCountSession(String sessionId);

  /// Cancels [sessionId]. No movements are written. Only `draft` sessions
  /// can be cancelled.
  Future<void> cancelStockCountSession(String sessionId);
}

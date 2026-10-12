// lib/features/inventory/domain/repositories/inventory_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/inventory_balance.dart';
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
}

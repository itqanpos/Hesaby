// lib/features/inventory/domain/repositories/inventory_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/inventory_balance.dart';
import '../entities/stock_movement.dart';

/// Categories of failures that the presentation layer can safely translate
/// into localized user messages.
///
/// Mirrors the Phase 1, Phase 3 and Phase 4 conventions so the application
/// has a single, consistent way of categorising safe failures. Backend-
/// specific error codes and raw messages never leave the data layer.
enum InventoryFailureType {
  /// The request could not reach the backend.
  network,

  /// The backend rejected the request as unauthorised (RLS or session).
  unauthorized,

  /// The requested balance or movement does not exist or is not accessible.
  notFound,

  /// An OUT movement would drive the balance negative. Raised by the
  /// database trigger in Phase 5 migration 3.
  insufficientStock,

  /// The referenced product does not exist or is not accessible.
  productNotFound,

  /// The referenced branch does not exist or is not accessible.
  branchNotFound,

  /// The movement type is not among the values accepted by the CHECK
  /// constraint on `stock_movements.movement_type`.
  invalidMovementType,

  /// The movement payload is structurally invalid (zero quantity,
  /// reference pair mismatch, negative unit cost, etc.).
  invalidMovement,

  /// The response could not be interpreted.
  invalidResponse,

  /// Any other unclassified failure.
  unknown,
}

/// Domain-level exception raised by [InventoryRepository] operations.
///
/// Carries a safe [InventoryFailureType] rather than a raw backend message
/// so the presentation layer can produce localized, user-friendly errors.
@immutable
class InventoryException extends Equatable implements Exception {
  const InventoryException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  /// Safe, categorized reason for the failure.
  final InventoryFailureType type;

  /// Original error, kept for logging. Never displayed to end users.
  final Object? cause;

  /// Original stack trace, kept for logging.
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'InventoryException(type: ${type.name})';
}

/// Contract for inventory operations.
///
/// All access decisions are ultimately enforced by Row Level Security in
/// the database: the data layer never accepts a `userId`, and `companyId`
/// is only ever used to filter results — RLS rejects any attempt to read
/// or write rows outside the caller's memberships.
///
/// The repository exposes a single write operation ([recordMovement]) and
/// several read operations. Balances cannot be written directly: they are
/// derived state, maintained exclusively by the database trigger.
abstract interface class InventoryRepository {
  // ---------------------------------------------------------------------------
  // Balances (read-only, derived)
  // ---------------------------------------------------------------------------

  /// Returns the inventory balances of [branchId] visible to the current
  /// user.
  ///
  /// When [onlyInStock] is `true`, rows with `quantity_on_hand == 0` are
  /// omitted. Results are ordered by product id for stable pagination in
  /// the presentation layer.
  /// Throws [InventoryException] when the request fails.
  Future<List<InventoryBalance>> listBalances(
    String companyId,
    String branchId, {
    bool onlyInStock = true,
  });

  /// Returns the balance of a single product in a single branch.
  ///
  /// Throws [InventoryException] with type [InventoryFailureType.notFound]
  /// when the (branch, product) pair has no balance row or is not
  /// accessible to the current user.
  Future<InventoryBalance> getBalance({
    required String companyId,
    required String branchId,
    required String productId,
  });

  // ---------------------------------------------------------------------------
  // Movements (append-only ledger)
  // ---------------------------------------------------------------------------

  /// Returns stock movements, most recent first.
  ///
  /// [branchId] and [productId] are optional filters. [limit] caps the
  /// number of rows returned; when omitted, the data source applies a
  /// conservative default (100) to protect the client from unbounded
  /// payloads.
  /// Throws [InventoryException] when the request fails.
  Future<List<StockMovement>> listMovements(
    String companyId, {
    String? branchId,
    String? productId,
    int? limit,
  });

  /// Records a stock movement.
  ///
  /// The signed [quantity] determines the direction: positive increases
  /// stock, negative decreases it. When a decrease would drive the balance
  /// below zero, the database raises an error that is mapped to
  /// [InventoryFailureType.insufficientStock].
  ///
  /// [movementType] must be one of the values declared by the database
  /// CHECK constraint (see [StockMovementType.all]).
  ///
  /// [referenceType] and [referenceId] must be either both provided or both
  /// omitted; providing only one is rejected as
  /// [InventoryFailureType.invalidMovement].
  ///
  /// The recording user (`created_by`) is resolved automatically from the
  /// authenticated session; the caller never supplies it.
  ///
  /// Throws [InventoryException] when the movement is rejected.
  Future<StockMovement> recordMovement({
    required String companyId,
    required String branchId,
    required String productId,
    required String movementType,
    required double quantity,
    double? unitCost,
    String? referenceType,
    String? referenceId,
    String? notes,
  });
}

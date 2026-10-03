// lib/features/purchases/domain/repositories/purchase_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/purchase.dart';
import '../entities/purchase_item.dart';

/// Input value object describing a single line item when creating or
/// updating a draft purchase.
///
/// `id` and `lineTotal` are intentionally absent: both are maintained by
/// the database. `purchase_id` is derived by the data layer from the
/// surrounding operation, so the caller never supplies it.
@immutable
class PurchaseItemDraft extends Equatable {
  const PurchaseItemDraft({
    required this.productId,
    required this.unitId,
    required this.quantity,
    required this.unitCost,
    this.notes,
  });

  /// Identifier of the product to purchase.
  final String productId;

  /// Identifier of the unit of measure.
  final String unitId;

  /// Quantity purchased. Must be strictly positive.
  final double quantity;

  /// Unit cost. Must be non-negative.
  final double unitCost;

  /// Optional free-form note for this line.
  final String? notes;

  @override
  List<Object?> get props =>
      <Object?>[productId, unitId, quantity, unitCost, notes];

  @override
  String toString() =>
      'PurchaseItemDraft(productId: $productId, unitId: $unitId, '
      'quantity: $quantity, unitCost: $unitCost)';
}

/// Categories of failures that the presentation layer can safely translate
/// into localized user messages.
enum PurchaseFailureType {
  network,
  unauthorized,
  notFound,
  invalidStatusTransition,
  emptyPurchase,
  invoiceNumberConflict,
  supplierNotFound,
  branchNotFound,
  productNotFound,
  unitNotFound,
  insufficientStock,
  invalidResponse,
  unknown,
}

/// Domain-level exception raised by [PurchaseRepository] operations.
@immutable
class PurchaseException extends Equatable implements Exception {
  const PurchaseException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  final PurchaseFailureType type;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'PurchaseException(type: ${type.name})';
}

/// Contract for purchase operations.
///
/// All access decisions are ultimately enforced by Row Level Security in
/// the database: the data layer never accepts a `userId`, and `companyId`
/// is only ever used to scope the operation — RLS rejects any attempt to
/// read or write rows outside the caller's memberships.
abstract interface class PurchaseRepository {
  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  Future<List<Purchase>> listPurchases(
    String companyId, {
    String? branchId,
    String? status,
    int? limit,
  });

  Future<Purchase> getPurchase(String purchaseId);

  Future<List<PurchaseItem>> listPurchaseItems(String purchaseId);

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  /// Creates a new draft purchase with its items, in a single logical
  /// operation.
  ///
  /// The purchase is always created with `status = draft`; the database
  /// enforces this. [items] may be empty (the purchase is completed and
  /// confirmed in a later step).
  Future<Purchase> createPurchase({
    required String companyId,
    required String branchId,
    required String supplierId,
    required DateTime purchaseDate,
    List<PurchaseItemDraft> items,
    String? invoiceNumber,
    double discount,
    double taxAmount,
    String? notes,
  });

  /// Replaces the header and items of an existing draft purchase.
  ///
  /// All existing items are removed and replaced by [items]. The operation
  /// is rejected with [PurchaseFailureType.invalidStatusTransition] when
  /// the purchase is not in `draft`.
  Future<Purchase> updateDraft({
    required String purchaseId,
    required String companyId,
    required String branchId,
    required String supplierId,
    required DateTime purchaseDate,
    required List<PurchaseItemDraft> items,
    String? invoiceNumber,
    double discount,
    double taxAmount,
    String? notes,
  });

  /// Confirms a draft purchase.
  ///
  /// The database trigger inserts the corresponding `purchase_in` stock
  /// movements. A purchase with no items is rejected with
  /// [PurchaseFailureType.emptyPurchase].
  Future<Purchase> confirmPurchase(String purchaseId);

  /// Cancels a purchase.
  ///
  /// A draft purchase is cancelled without touching stock. A confirmed
  /// purchase has its movements reversed; if that reversal would drive a
  /// stock balance negative, the operation fails with
  /// [PurchaseFailureType.insufficientStock].
  Future<Purchase> cancelPurchase(String purchaseId);
}

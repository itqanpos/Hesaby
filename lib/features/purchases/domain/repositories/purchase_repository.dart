// lib/features/purchases/domain/repositories/purchase_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/purchase.dart';
import '../entities/purchase_item.dart';

/// Input value object describing a single line item when creating or
/// updating a draft purchase.
///
/// `id` and `lineTotal` are intentionally absent: both are maintained by
/// the database. `company_id` and `purchase_id` are derived by the data
/// layer from the surrounding operation, so the caller never supplies them.
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
///
/// Mirrors the Phase 1, Phase 3, Phase 4, Phase 5 and Phase 6 conventions
/// so the application has a single, consistent way of categorising safe
/// failures. Backend-specific error codes and raw messages never leave the
/// data layer.
enum PurchaseFailureType {
  /// The request could not reach the backend.
  network,

  /// The backend rejected the request as unauthorised (RLS or session).
  unauthorized,

  /// The requested purchase does not exist or is not accessible.
  notFound,

  /// The status transition is not allowed (for example, editing a
  /// non-draft, or confirming an already-cancelled purchase).
  invalidStatusTransition,

  /// The purchase has no line items and therefore cannot be confirmed.
  emptyPurchase,

  /// An invoice number collision on the same company.
  invoiceNumberConflict,

  /// The referenced supplier does not exist or is not accessible.
  supplierNotFound,

  /// The referenced branch does not exist or is not accessible.
  branchNotFound,

  /// The referenced product does not exist or is not accessible.
  productNotFound,

  /// The referenced unit does not exist or is not accessible.
  unitNotFound,

  /// Reversing a confirmed purchase would drive a stock balance negative.
  /// Raised by the Phase 5 trigger during cancellation.
  insufficientStock,

  /// The response could not be interpreted.
  invalidResponse,

  /// Any other unclassified failure.
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

  /// Safe, categorized reason for the failure.
  final PurchaseFailureType type;

  /// Original error, kept for logging. Never displayed to end users.
  final Object? cause;

  /// Original stack trace, kept for logging.
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
/// is only ever used to filter results — RLS rejects any attempt to read
/// or write rows outside the caller's memberships.
///
/// State machine:
/// A purchase is always created in `draft`. Its header and items may only
/// be modified while it remains in `draft`. [confirmPurchase] transitions
/// it to `confirmed` and (via the database trigger) generates the
/// corresponding `purchase_in` stock movements. [cancelPurchase] transitions
/// it to `cancelled`, generating reverse `sale_out` movements if it was
/// previously confirmed.
abstract interface class PurchaseRepository {
  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  /// Returns purchases of [companyId], most recent first.
  ///
  /// [branchId] and [status] narrow the result when supplied. [limit] caps
  /// the number of rows returned; the data source applies a conservative
  /// default when omitted.
  /// Throws [PurchaseException] when the request fails.
  Future<List<Purchase>> listPurchases(
    String companyId, {
    String? branchId,
    String? status,
    int? limit,
  });

  /// Returns the header of a single purchase.
  ///
  /// Throws [PurchaseException] with type [PurchaseFailureType.notFound]
  /// when the purchase does not exist or is not accessible.
  Future<Purchase> getPurchase(String purchaseId);

  /// Returns the line items of [purchaseId].
  ///
  /// Throws [PurchaseException] when the request fails.
  Future<List<PurchaseItem>> listPurchaseItems(String purchaseId);

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  /// Creates a new draft purchase with its items, in a single logical
  /// operation.
  ///
  /// The purchase is always created with `status = draft`; the database
  /// enforces this. [items] may be empty (the purchase is completed and
  /// confirmed in a later step). The header total is recomputed by the
  /// database from the line items.
  ///
  /// Throws [PurchaseException] with type
  /// [PurchaseFailureType.invoiceNumberConflict] on invoice number
  /// collisions, or [PurchaseFailureType.supplierNotFound] /
  /// [branchNotFound] / [productNotFound] / [unitNotFound] when a
  /// referenced row is unavailable.
  Future<Purchase> createPurchase({
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
  /// All existing items are removed and replaced by [items]. Callers are
  /// expected to pass the complete new set of line items. The operation is
  /// rejected with [PurchaseFailureType.invalidStatusTransition] when the
  /// purchase is not in `draft`.
  ///
  /// Throws the same typed failures as [createPurchase].
  Future<Purchase> updateDraft({
    required String purchaseId,
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
  /// [PurchaseFailureType.emptyPurchase]. A non-draft purchase is rejected
  /// with [PurchaseFailureType.invalidStatusTransition].
  Future<Purchase> confirmPurchase(String purchaseId);

  /// Cancels a purchase.
  ///
  /// A draft purchase is cancelled without touching stock. A confirmed
  /// purchase has its movements reversed (via `sale_out`); if that reversal
  /// would drive a stock balance negative, the operation fails with
  /// [PurchaseFailureType.insufficientStock].
  Future<Purchase> cancelPurchase(String purchaseId);
}

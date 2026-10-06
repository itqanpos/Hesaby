// lib/features/sales/domain/entities/sale_return.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

// ============================================================================
// Return status constants
// ============================================================================

/// Canonical return status identifiers used by `sale_returns.status`.
///
/// The three values match the `sale_returns_status_valid` CHECK constraint
/// declared in migration `202610110001_sale_returns.sql`.
abstract final class ReturnStatus {
  static const String draft = 'draft';
  static const String confirmed = 'confirmed';
  static const String cancelled = 'cancelled';

  static const List<String> all = <String>[draft, confirmed, cancelled];
}

// ============================================================================
// Refund method constants
// ============================================================================

/// Canonical refund-method identifiers used by
/// `sale_returns.refund_method`.
///
/// * [cash]        — money returned to the customer in cash.
/// * [card]        — money returned to the customer's card.
/// * [creditNote]  — amount credited against the customer's balance (the
///                   only method that touches `customers.balance`).
/// * [none]        — no refund (e.g. an exchange handled elsewhere).
abstract final class RefundMethod {
  static const String cash = 'cash';
  static const String card = 'card';
  static const String creditNote = 'credit_note';
  static const String none = 'none';

  static const List<String> all = <String>[cash, card, creditNote, none];
}

// ============================================================================
// Sale return
// ============================================================================

/// Represents a return of one or more items from a confirmed sale.
///
/// Lifecycle:
/// * Created in `draft` — items may be freely added, edited, or removed.
/// * [confirm] — inserts `return_in` stock movements, reduces the customer
///   balance when the refund method is `credit_note`, and locks the row
///   against further structural changes.
/// * [cancel] — reverses both effects and locks the row completely.
///
/// Money values are exposed as `double`, matching `numeric(15,4)` in the
/// database; the same rationale documented on `Product` and `Sale` applies.
@immutable
class SaleReturn extends Equatable {
  const SaleReturn({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.saleId,
    required this.returnDate,
    required this.status,
    required this.subtotal,
    required this.discount,
    required this.taxAmount,
    required this.total,
    required this.refundMethod,
    required this.createdAt,
    required this.updatedAt,
    this.customerId,
    this.returnNumber,
    this.notes,
    this.createdBy,
    this.confirmedAt,
    this.cancelledAt,
  });

  final String id;
  final String companyId;
  final String branchId;
  final String saleId;
  final String? customerId;
  final String? returnNumber;
  final DateTime returnDate;
  final String status;
  final double subtotal;
  final double discount;
  final double taxAmount;
  final double total;
  final String refundMethod;
  final String? notes;
  final String? createdBy;
  final DateTime? confirmedAt;
  final DateTime? cancelledAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  // ---------------------------------------------------------------------------
  // Convenience getters (UI only — no business rules)
  // ---------------------------------------------------------------------------

  bool get isDraft => status == ReturnStatus.draft;
  bool get isConfirmed => status == ReturnStatus.confirmed;
  bool get isCancelled => status == ReturnStatus.cancelled;
  bool get canEdit => isDraft;
  bool get canTransition => isDraft || isConfirmed;

  bool get hasCustomer => customerId != null;
  bool get hasReturnNumber =>
      returnNumber != null && returnNumber!.trim().isNotEmpty;
  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;
  bool get wasConfirmed => confirmedAt != null;
  bool get wasCancelled => cancelledAt != null;

  bool get isCashRefund => refundMethod == RefundMethod.cash;
  bool get isCardRefund => refundMethod == RefundMethod.card;
  bool get isCreditNote => refundMethod == RefundMethod.creditNote;
  bool get isNoRefund => refundMethod == RefundMethod.none;

  /// Whether confirming this return will affect the customer balance.
  bool get affectsCustomerBalance =>
      isCreditNote && customerId != null;

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        branchId,
        saleId,
        customerId,
        returnNumber,
        returnDate,
        status,
        subtotal,
        discount,
        taxAmount,
        total,
        refundMethod,
        notes,
        createdBy,
        confirmedAt,
        cancelledAt,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'SaleReturn(id: $id, saleId: $saleId, status: $status, '
      'total: $total, refundMethod: $refundMethod)';
}

// ============================================================================
// Sale return item
// ============================================================================

/// A single line in a sale return.
///
/// Every row references the original [SaleItem] it reverses, so the
/// over-return guard in the database can enforce
/// `sum(returned) <= original_quantity`.
@immutable
class SaleReturnItem extends Equatable {
  const SaleReturnItem({
    required this.id,
    required this.companyId,
    required this.returnId,
    required this.saleItemId,
    required this.productId,
    required this.unitId,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
  });

  final String id;
  final String companyId;
  final String returnId;
  final String saleItemId;
  final String productId;
  final String unitId;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;
  double get value => lineTotal;

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        returnId,
        saleItemId,
        productId,
        unitId,
        quantity,
        unitPrice,
        lineTotal,
        notes,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'SaleReturnItem(id: $id, returnId: $returnId, '
      'saleItemId: $saleItemId, quantity: $quantity)';
}

// ============================================================================
// Sale return item draft (input value object)
// ============================================================================

/// Input value object used when creating or updating return items.
///
/// The `company_id` and `return_id` are resolved by the caller — this class
/// is a plain data carrier used at the boundary of the repository.
@immutable
class SaleReturnItemDraft extends Equatable {
  const SaleReturnItemDraft({
    required this.saleItemId,
    required this.productId,
    required this.unitId,
    required this.quantity,
    required this.unitPrice,
    this.notes,
  });

  final String saleItemId;
  final String productId;
  final String unitId;
  final double quantity;
  final double unitPrice;
  final String? notes;

  /// Convenience: line total computed locally so the caller does not have
  /// to pass it as a redundant parameter.
  double get lineTotal => quantity * unitPrice;

  @override
  List<Object?> get props => <Object?>[
        saleItemId,
        productId,
        unitId,
        quantity,
        unitPrice,
        notes,
      ];

  @override
  String toString() =>
      'SaleReturnItemDraft(saleItemId: $saleItemId, '
      'quantity: $quantity, unitPrice: $unitPrice)';
}

// lib/features/sales/domain/entities/sale_entities.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

// ============================================================================
// Status constants
// ============================================================================

/// Canonical sale status identifiers used by `sales.status`.
///
/// Declared as constants rather than a Dart `enum` because the database
/// stores the value as `text` with a CHECK constraint; adding a new status
/// in a future migration should not require changing existing entity
/// instances.
abstract final class SaleStatus {
  static const String draft = 'draft';
  static const String confirmed = 'confirmed';
  static const String cancelled = 'cancelled';

  static const List<String> all = <String>[draft, confirmed, cancelled];
}

/// Canonical payment status identifiers used by `sales.payment_status`.
///
/// Derived by the database from `paid_amount` and `total`; the client reads
/// it but never sets it directly.
abstract final class PaymentStatus {
  static const String unpaid = 'unpaid';
  static const String partial = 'partial';
  static const String paid = 'paid';

  static const List<String> all = <String>[unpaid, partial, paid];
}

// ============================================================================
// Customer
// ============================================================================

/// Represents a customer of a company.
@immutable
class Customer extends Equatable {
  const Customer({
    required this.id,
    required this.companyId,
    required this.name,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.code,
    this.phone,
    this.email,
    this.address,
    this.notes,
  });

  final String id;
  final String companyId;
  final String name;
  final String? code;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasCode => code != null && code!.trim().isNotEmpty;
  bool get hasPhone => phone != null && phone!.trim().isNotEmpty;
  bool get hasEmail => email != null && email!.trim().isNotEmpty;
  bool get hasAddress => address != null && address!.trim().isNotEmpty;
  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;
  bool get hasContactInfo => hasPhone || hasEmail;

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        name,
        code,
        phone,
        email,
        address,
        notes,
        isActive,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'Customer(id: $id, companyId: $companyId, name: $name, code: $code, '
      'isActive: $isActive)';
}

// ============================================================================
// Sale
// ============================================================================

/// Represents a single sales invoice (a customer receipt header).
///
/// Money values are exposed as `double`, matching `numeric(15,4)` in the
/// database; the same rationale documented on `Product` applies.
@immutable
class Sale extends Equatable {
  const Sale({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.customerId,
    required this.saleDate,
    required this.status,
    required this.subtotal,
    required this.discount,
    required this.taxAmount,
    required this.total,
    required this.paidAmount,
    required this.paymentStatus,
    required this.createdAt,
    required this.updatedAt,
    this.invoiceNumber,
    this.notes,
    this.createdBy,
    this.confirmedAt,
    this.cancelledAt,
  });

  final String id;
  final String companyId;
  final String branchId;
  final String customerId;
  final String? invoiceNumber;
  final DateTime saleDate;
  final String status;
  final double subtotal;
  final double discount;
  final double taxAmount;
  final double total;
  final double paidAmount;
  final String paymentStatus;
  final String? notes;
  final String? createdBy;
  final DateTime? confirmedAt;
  final DateTime? cancelledAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  // ---------------------------------------------------------------------------
  // Convenience getters (UI only — no business rules)
  // ---------------------------------------------------------------------------

  bool get isDraft => status == SaleStatus.draft;
  bool get isConfirmed => status == SaleStatus.confirmed;
  bool get isCancelled => status == SaleStatus.cancelled;

  /// Whether the sale is in a state that accepts edits to its items and
  /// header fields beyond notes.
  bool get canEdit => isDraft;

  /// Whether the sale can still be confirmed or cancelled.
  bool get canTransition => isDraft || isConfirmed;

  bool get hasInvoiceNumber =>
      invoiceNumber != null && invoiceNumber!.trim().isNotEmpty;

  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;

  bool get wasConfirmed => confirmedAt != null;
  bool get wasCancelled => cancelledAt != null;

  bool get isUnpaid => paymentStatus == PaymentStatus.unpaid;
  bool get isPartiallyPaid => paymentStatus == PaymentStatus.partial;
  bool get isFullyPaid => paymentStatus == PaymentStatus.paid;

  /// Remaining amount to collect.
  double get amountDue {
    final double due = total - paidAmount;
    return due < 0 ? 0 : due;
  }

  /// Net total after subtracting the discount (before tax).
  double get netAfterDiscount => subtotal - discount;

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        branchId,
        customerId,
        invoiceNumber,
        saleDate,
        status,
        subtotal,
        discount,
        taxAmount,
        total,
        paidAmount,
        paymentStatus,
        notes,
        createdBy,
        confirmedAt,
        cancelledAt,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'Sale(id: $id, customerId: $customerId, status: $status, '
      'total: $total, paidAmount: $paidAmount)';
}

// ============================================================================
// Sale item
// ============================================================================

/// Represents a single line item of a sale.
///
/// `lineTotal` is maintained by the database and always equals
/// `quantity * unitPrice`.
@immutable
class SaleItem extends Equatable {
  const SaleItem({
    required this.id,
    required this.companyId,
    required this.saleId,
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
  final String saleId;
  final String productId;
  final String unitId;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;

  /// Alias for [lineTotal] to make it explicit at call sites that this is
  /// the value of the line, independent of how it was computed.
  double get value => lineTotal;

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        saleId,
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
      'SaleItem(id: $id, saleId: $saleId, productId: $productId, '
      'quantity: $quantity, unitPrice: $unitPrice, lineTotal: $lineTotal)';
}

// ============================================================================
// Sale item draft (input value object)
// ============================================================================

/// Input value object describing a single line item when creating or
/// updating a draft sale.
///
/// `id` and `lineTotal` are maintained by the database; `sale_id` is derived
/// by the data layer from the surrounding operation.
@immutable
class SaleItemDraft extends Equatable {
  const SaleItemDraft({
    required this.productId,
    required this.unitId,
    required this.quantity,
    required this.unitPrice,
    this.notes,
  });

  final String productId;
  final String unitId;
  final double quantity;
  final double unitPrice;
  final String? notes;

  @override
  List<Object?> get props =>
      <Object?>[productId, unitId, quantity, unitPrice, notes];

  @override
  String toString() =>
      'SaleItemDraft(productId: $productId, unitId: $unitId, '
      'quantity: $quantity, unitPrice: $unitPrice)';
}

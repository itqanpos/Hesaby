// lib/features/purchases/domain/entities/purchase.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Canonical purchase status identifiers used by `purchases.status`.
///
/// Declared as constants rather than a Dart `enum` because the database
/// stores the value as `text` with a CHECK constraint; adding a new status
/// in a future migration should not require changing existing entity
/// instances.
abstract final class PurchaseStatus {
  static const String draft = 'draft';
  static const String confirmed = 'confirmed';
  static const String cancelled = 'cancelled';

  /// Every status currently accepted by the database CHECK constraint.
  static const List<String> all = <String>[
    draft,
    confirmed,
    cancelled,
  ];
}

/// Represents a single purchase order (a supplier invoice header).
///
/// This is a pure Domain entity. It knows nothing about Supabase,
/// PostgreSQL, or Flutter widgets.
///
/// Money representation:
/// `subtotal`, `discount`, `taxAmount` and `total` are exposed as `double`,
/// matching `numeric(15,4)` in the database. The same rationale documented
/// on `Product` applies.
///
/// A purchase always belongs to exactly one company; [companyId] is part of
/// the entity so that the presentation layer can verify tenant coherence
/// without an extra query.
@immutable
class Purchase extends Equatable {
  const Purchase({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.supplierId,
    required this.purchaseDate,
    required this.status,
    required this.subtotal,
    required this.discount,
    required this.taxAmount,
    required this.total,
    required this.createdAt,
    required this.updatedAt,
    this.invoiceNumber,
    this.notes,
    this.createdBy,
    this.confirmedAt,
    this.cancelledAt,
  });

  /// Unique identifier of the purchase (uuid).
  final String id;

  /// Identifier of the owning company.
  final String companyId;

  /// Identifier of the receiving branch.
  final String branchId;

  /// Identifier of the supplier.
  final String supplierId;

  /// Optional supplier invoice number. Unique per company when present.
  final String? invoiceNumber;

  /// Business date of the purchase.
  final DateTime purchaseDate;

  /// One of [PurchaseStatus.all].
  final String status;

  /// Sum of line totals. Maintained by the database trigger.
  final double subtotal;

  /// Header-level discount.
  final double discount;

  /// Header-level tax amount.
  final double taxAmount;

  /// Net total = subtotal - discount + taxAmount.
  final double total;

  /// Optional free-form notes.
  final String? notes;

  /// Optional `auth.users.id` of the user who created the purchase.
  final String? createdBy;

  /// When the purchase was confirmed. `null` while in draft.
  final DateTime? confirmedAt;

  /// When the purchase was cancelled. `null` otherwise.
  final DateTime? cancelledAt;

  /// Creation timestamp (UTC).
  final DateTime createdAt;

  /// Last modification timestamp (UTC).
  final DateTime updatedAt;

  // ---------------------------------------------------------------------------
  // Convenience getters (UI only — no business rules)
  // ---------------------------------------------------------------------------

  bool get isDraft => status == PurchaseStatus.draft;

  bool get isConfirmed => status == PurchaseStatus.confirmed;

  bool get isCancelled => status == PurchaseStatus.cancelled;

  /// Whether the purchase is in a state that accepts edits to its items
  /// and header fields beyond notes.
  bool get canEdit => isDraft;

  /// Whether the purchase can still be confirmed or cancelled.
  bool get canTransition =>
      isDraft || isConfirmed;

  bool get hasInvoiceNumber =>
      invoiceNumber != null && invoiceNumber!.trim().isNotEmpty;

  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;

  bool get wasConfirmed => confirmedAt != null;

  bool get wasCancelled => cancelledAt != null;

  /// Net total after subtracting the discount (before tax).
  double get netAfterDiscount => subtotal - discount;

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        branchId,
        supplierId,
        invoiceNumber,
        purchaseDate,
        status,
        subtotal,
        discount,
        taxAmount,
        total,
        notes,
        createdBy,
        confirmedAt,
        cancelledAt,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'Purchase(id: $id, companyId: $companyId, supplierId: $supplierId, '
      'status: $status, total: $total)';
}

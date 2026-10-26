// lib/features/sales/domain/entities/sale_return.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

// ============================================================================
// Return status constants
// ============================================================================

abstract final class ReturnStatus {
  static const String draft = 'draft';
  static const String confirmed = 'confirmed';
  static const String cancelled = 'cancelled';

  static const List<String> all = <String>[draft, confirmed, cancelled];
}

// ============================================================================
// Refund method constants
// ============================================================================

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

@immutable
class SaleReturn extends Equatable {
  const SaleReturn({
    required this.id,
    required this.companyId,
    required this.branchId,
    this.saleId, // ✅ nullable — يدعم المرتجع المستقل
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
  final String? saleId; // ✅ nullable
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
  // Convenience getters
  // ---------------------------------------------------------------------------

  bool get isDraft => status == ReturnStatus.draft;
  bool get isConfirmed => status == ReturnStatus.confirmed;
  bool get isCancelled => status == ReturnStatus.cancelled;
  bool get canEdit => isDraft;
  bool get canTransition => isDraft || isConfirmed;

  bool get hasSale => saleId != null; // ✅ جديد
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

  bool get affectsCustomerBalance => isCreditNote && customerId != null;

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

@immutable
class SaleReturnItem extends Equatable {
  const SaleReturnItem({
    required this.id,
    required this.companyId,
    required this.returnId,
    this.saleItemId, // ✅ nullable
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
  final String? saleItemId; // ✅ nullable
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
// Sale return item draft — ✅ التعديل الجوهري هنا
// ============================================================================

@immutable
class SaleReturnItemDraft extends Equatable {
  const SaleReturnItemDraft({
    this.saleItemId, // ✅ بدون required — nullable
    required this.productId,
    required this.unitId,
    required this.quantity,
    required this.unitPrice,
    this.notes,
  });

  /// `null` للمرتجعات المستقلة (بدون فاتورة أصلية).
  final String? saleItemId; // ✅ String? — يقبل null
  final String productId;
  final String unitId;
  final double quantity;
  final double unitPrice;
  final String? notes;

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

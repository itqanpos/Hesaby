// lib/features/purchases/domain/entities/purchase_receipt.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Immutable snapshot of a purchase, prepared for printing.
///
/// Deliberately self-contained (like `Receipt` for POS): the printer layer
/// sees only fields that actually appear on the printed document, and does
/// not depend on the broader purchase/supplier/product graphs.
@immutable
class PurchaseReceipt extends Equatable {
  const PurchaseReceipt({
    required this.purchaseId,
    required this.purchaseDate,
    required this.companyName,
    required this.branchName,
    required this.supplierName,
    required this.lines,
    required this.subtotal,
    required this.discount,
    required this.taxAmount,
    required this.total,
    required this.status,
    this.invoiceNumber,
    this.supplierPhone,
    this.supplierEmail,
    this.supplierAddress,
    this.notes,
    this.footer,
  });

  final String purchaseId;
  final String? invoiceNumber;
  final DateTime purchaseDate;
  final String companyName;
  final String branchName;
  final String supplierName;
  final String? supplierPhone;
  final String? supplierEmail;
  final String? supplierAddress;
  final List<PurchaseReceiptLine> lines;
  final double subtotal;
  final double discount;
  final double taxAmount;
  final double total;

  /// One of `PurchaseStatus.all` (`draft` / `confirmed` / `cancelled`).
  final String status;

  final String? notes;
  final String? footer;

  // ---------------------------------------------------------------------------
  // Convenience
  // ---------------------------------------------------------------------------

  int get lineCount => lines.length;

  bool get hasSupplierContact =>
      (supplierPhone != null && supplierPhone!.trim().isNotEmpty) ||
      (supplierEmail != null && supplierEmail!.trim().isNotEmpty);

  bool get hasSupplierAddress =>
      supplierAddress != null && supplierAddress!.trim().isNotEmpty;

  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;

  bool get hasFooter => footer != null && footer!.trim().isNotEmpty;

  bool get hasDiscount => discount > 0;

  bool get hasTax => taxAmount > 0;

  @override
  List<Object?> get props => <Object?>[
        purchaseId,
        invoiceNumber,
        purchaseDate,
        companyName,
        branchName,
        supplierName,
        supplierPhone,
        supplierEmail,
        supplierAddress,
        lines,
        subtotal,
        discount,
        taxAmount,
        total,
        status,
        notes,
        footer,
      ];

  @override
  String toString() =>
      'PurchaseReceipt(purchaseId: $purchaseId, '
      'invoiceNumber: $invoiceNumber, lines: ${lines.length}, '
      'total: $total)';
}

/// A single line in a printed purchase receipt.
@immutable
class PurchaseReceiptLine extends Equatable {
  const PurchaseReceiptLine({
    required this.productName,
    required this.unitName,
    required this.quantity,
    required this.unitCost,
    required this.lineTotal,
  });

  final String productName;
  final String unitName;
  final double quantity;
  final double unitCost;
  final double lineTotal;

  @override
  List<Object?> get props =>
      <Object?>[productName, unitName, quantity, unitCost, lineTotal];

  @override
  String toString() =>
      'PurchaseReceiptLine(productName: $productName, '
      'quantity: $quantity, unitCost: $unitCost)';
}

// lib/features/sales/domain/entities/return_receipt.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// A single line in a printed return receipt.
@immutable
class ReturnReceiptLine extends Equatable {
  const ReturnReceiptLine({
    required this.productName,
    required this.unitName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String productName;
  final String unitName;
  final double quantity;
  final double unitPrice;
  final double lineTotal;

  @override
  List<Object?> get props =>
      [productName, unitName, quantity, unitPrice, lineTotal];
}

/// Immutable snapshot of a return, prepared for printing.
///
/// Deliberately separate from `SaleReturn` (domain) and from `Receipt`
/// (POS) so that the printer layer does not depend on either: it only sees
/// the fields that actually appear on the printed document.
@immutable
class ReturnReceipt extends Equatable {
  const ReturnReceipt({
    required this.returnId,
    required this.returnNumber,
    required this.dateTime,
    required this.companyName,
    required this.branchName,
    required this.lines,
    required this.total,
    required this.refundMethodLabel,
    this.saleInvoiceNumber,
    this.customerName,
    this.notes,
    this.cashierName,
  });

  final String returnId;
  final String? returnNumber;
  final DateTime dateTime;
  final String companyName;
  final String branchName;
  final List<ReturnReceiptLine> lines;
  final double total;

  /// Localized label (e.g. "رصيد", "نقدي"). The printer treats this as a
  /// plain string.
  final String refundMethodLabel;

  final String? saleInvoiceNumber;
  final String? customerName;
  final String? notes;
  final String? cashierName;

  int get lineCount => lines.length;
  bool get hasCustomer =>
      customerName != null && customerName!.trim().isNotEmpty;
  bool get hasSaleInvoice =>
      saleInvoiceNumber != null && saleInvoiceNumber!.trim().isNotEmpty;
  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;
  bool get hasCashier =>
      cashierName != null && cashierName!.trim().isNotEmpty;

  @override
  List<Object?> get props => <Object?>[
        returnId,
        returnNumber,
        dateTime,
        companyName,
        branchName,
        lines,
        total,
        refundMethodLabel,
        saleInvoiceNumber,
        customerName,
        notes,
        cashierName,
      ];
}

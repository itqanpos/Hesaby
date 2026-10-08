// lib/features/pos/domain/entities/receipt.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Immutable, self-contained representation of a sale receipt.
@immutable
class Receipt extends Equatable {
  const Receipt({
    required this.saleId,
    required this.dateTime,
    required this.companyName,
    required this.branchName,
    required this.lines,
    required this.subtotal,
    required this.discount,
    required this.taxAmount,
    required this.total,
    required this.paidAmount,
    required this.change,
    this.paidOnBalance = 0,
    this.invoiceNumber,
    this.customerName,
    this.cashierName,
    this.previousBalance,
    this.newBalance,
    this.footer,
  });

  final String saleId;
  final String? invoiceNumber;
  final DateTime dateTime;
  final String companyName;
  final String branchName;
  final List<ReceiptLine> lines;
  final double subtotal;
  final double discount;
  final double taxAmount;
  final double total;

  /// Amount of the received cash that was applied to this invoice.
  final double paidAmount;

  /// Cash returned to the customer (0 for card and credit).
  final double change;

  /// Amount of the received cash that was applied to the customer's
  /// previous balance. Zero for cash sales without a prior balance or
  /// when nothing was applied to the old balance.
  final double paidOnBalance;

  final String? customerName;
  final String? cashierName;
  final double? previousBalance;
  final double? newBalance;
  final String? footer;

  // ---------------------------------------------------------------------------
  // Convenience
  // ---------------------------------------------------------------------------

  bool get hasCustomer => customerName != null;

  bool get hasBalanceChange =>
      previousBalance != null && newBalance != null;

  bool get hasChange => change > 0;

  bool get hasBalancePayment => paidOnBalance > 0;

  bool get hasFooter => footer != null && footer!.trim().isNotEmpty;

  int get lineCount => lines.length;

  /// Total cash the customer physically handed over.
  ///
  /// Sum of: what was applied to the invoice, what was applied to the
  /// previous balance, and what was returned as change.
  double get cashReceived => paidAmount + paidOnBalance + change;

  @override
  List<Object?> get props => <Object?>[
        saleId,
        invoiceNumber,
        dateTime,
        companyName,
        branchName,
        lines,
        subtotal,
        discount,
        taxAmount,
        total,
        paidAmount,
        change,
        paidOnBalance,
        customerName,
        cashierName,
        previousBalance,
        newBalance,
        footer,
      ];

  @override
  String toString() =>
      'Receipt(saleId: $saleId, invoiceNumber: $invoiceNumber, '
      'lines: ${lines.length}, total: $total)';
}

/// Immutable, self-contained representation of a single receipt line.
@immutable
class ReceiptLine extends Equatable {
  const ReceiptLine({
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
      <Object?>[productName, unitName, quantity, unitPrice, lineTotal];

  @override
  String toString() =>
      'ReceiptLine(productName: $productName, quantity: $quantity, '
      'unitPrice: $unitPrice)';
}

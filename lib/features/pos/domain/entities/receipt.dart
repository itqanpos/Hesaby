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
    this.addedToBalance = 0,
    this.invoiceNumber,
    this.companyAddress,
    this.companyPhone,
    this.companyTaxNumber,
    this.companyCommercialRegister,
    this.showTaxNumberOnPrint = false,
    this.showCommercialRegisterOnPrint = false,
    this.customerName,
    this.customerAddress,
    this.customerPhone,
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

  /// Amount of the input that was applied to this invoice.
  final double paidAmount;

  /// Cash returned to the customer (0 unless the operator chose to
  /// return the excess as cash).
  final double change;

  /// Amount of the input that was applied to the customer's previous
  /// balance. Zero for card and credit sales, and for cash sales with no
  /// prior balance.
  final double paidOnBalance;

  /// Amount added to the customer's balance beyond the invoice total.
  /// Positive = customer still owes; negative = customer has a credit.
  /// This is the balance **delta**, not the resulting balance.
  final double addedToBalance;

  // ---- Company identity ----
  final String? companyAddress;
  final String? companyPhone;
  final String? companyTaxNumber;
  final String? companyCommercialRegister;
  final bool showTaxNumberOnPrint;
  final bool showCommercialRegisterOnPrint;

  // ---- Parties ----
  final String? customerName;
  final String? customerAddress;
  final String? customerPhone;
  final String? cashierName;
  final double? previousBalance;
  final double? newBalance;
  final String? footer;

  // ---------------------------------------------------------------------------
  // Derived
  // ---------------------------------------------------------------------------

  /// Total amount the customer owed at the start of this sale
  /// (previous balance + invoice total). Falls back to [total] when no
  /// previous balance exists.
  double get settlementTotal =>
      (previousBalance ?? 0) + total;

  bool get hasCustomer => customerName != null;

  bool get hasCustomerAddress =>
      customerAddress != null && customerAddress!.trim().isNotEmpty;

  bool get hasCustomerPhone =>
      customerPhone != null && customerPhone!.trim().isNotEmpty;

  bool get hasCompanyAddress =>
      companyAddress != null && companyAddress!.trim().isNotEmpty;

  bool get hasCompanyPhone =>
      companyPhone != null && companyPhone!.trim().isNotEmpty;

  bool get hasTaxNumberToPrint =>
      showTaxNumberOnPrint &&
          companyTaxNumber != null &&
          companyTaxNumber!.trim().isNotEmpty;

  bool get hasCommercialRegisterToPrint =>
      showCommercialRegisterOnPrint &&
          companyCommercialRegister != null &&
          companyCommercialRegister!.trim().isNotEmpty;

  bool get hasBalanceChange =>
      previousBalance != null && newBalance != null;

  bool get hasChange => change > 0;

  bool get hasBalancePayment => paidOnBalance > 0;

  /// Whether the resulting balance is negative (customer has a credit).
  bool get hasCreditBalance => (newBalance ?? 0) < 0;

  bool get hasFooter => footer != null && footer!.trim().isNotEmpty;

  int get lineCount => lines.length;

  /// Total cash the customer physically handed over.
  double get cashReceived => paidAmount + paidOnBalance + change;

  @override
  List<Object?> get props => <Object?>[
        saleId,
        invoiceNumber,
        dateTime,
        companyName,
        branchName,
        companyAddress,
        companyPhone,
        companyTaxNumber,
        companyCommercialRegister,
        showTaxNumberOnPrint,
        showCommercialRegisterOnPrint,
        lines,
        subtotal,
        discount,
        taxAmount,
        total,
        paidAmount,
        change,
        paidOnBalance,
        addedToBalance,
        customerName,
        customerAddress,
        customerPhone,
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

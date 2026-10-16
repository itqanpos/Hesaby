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

  /// Amount the customer paid toward the invoice + old balance.
  final double paidAmount;

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

  /// Customer's balance before this sale (positive = owes us).
  final double? previousBalance;

  /// Customer's balance after this sale.
  /// * `> 0` → customer owes us (debit).
  /// * `< 0` → we owe the customer (credit).
  /// * `= 0` → settled.
  final double? newBalance;

  final String? footer;

  // ---------------------------------------------------------------------------
  // Derived
  // ---------------------------------------------------------------------------

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

  /// Whether the resulting balance is negative (customer credit).
  bool get hasCreditBalance => (newBalance ?? 0) < 0;

  /// Whether the resulting balance is positive (customer debt).
  bool get hasDebitBalance => (newBalance ?? 0) > 0;

  /// Absolute new-balance amount, safe for display.
  double get newBalanceAbsolute => (newBalance ?? 0).abs();

  bool get hasFooter => footer != null && footer!.trim().isNotEmpty;

  int get lineCount => lines.length;

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
      'lines: ${lines.length}, total: $total, paidAmount: $paidAmount, '
      'newBalance: $newBalance)';
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

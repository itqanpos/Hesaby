// lib/features/pos/domain/entities/receipt.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// أنواع المستندات التي يمكن طباعتها في النظام
enum DocumentType {
  sale,
  purchase,
  saleReturn,
  purchaseReturn,
  stockCount;

  String get label {
    switch (this) {
      case DocumentType.sale:
        return 'فاتورة مبيعات';
      case DocumentType.purchase:
        return 'فاتورة مشتريات';
      case DocumentType.saleReturn:
        return 'مرتجع مبيعات';
      case DocumentType.purchaseReturn:
        return 'مرتجع مشتريات';
      case DocumentType.stockCount:
        return 'جرد مخزون';
    }
  }
}

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
    this.documentType = DocumentType.sale,
    this.invoiceNumber,
    this.companyAddress,
    this.companyPhone,
    this.companyTaxNumber,
    this.companyCommercialRegister,
    this.showTaxNumberOnPrint = false,
    this.showCommercialRegisterOnPrint = false,
    this.showCurrencySymbol = true,
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

  /// نوع المستند (مبيعات، مشتريات، مرتجع، إلخ)
  final DocumentType documentType;

  // ---- Company identity ----
  final String? companyAddress;
  final String? companyPhone;
  final String? companyTaxNumber;
  final String? companyCommercialRegister;
  final bool showTaxNumberOnPrint;
  final bool showCommercialRegisterOnPrint;

  /// Whether the currency symbol (ج.م) is printed next to amounts.
  final bool showCurrencySymbol;

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

  /// A discount row is printed only when there is a discount.
  bool get hasDiscountToPrint => discount > 0;

  /// A tax row is printed only when tax was applied.
  bool get hasTaxToPrint => taxAmount > 0;

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

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  Receipt copyWith({
    String? saleId,
    String? invoiceNumber,
    DateTime? dateTime,
    String? companyName,
    String? branchName,
    List<ReceiptLine>? lines,
    double? subtotal,
    double? discount,
    double? taxAmount,
    double? total,
    double? paidAmount,
    DocumentType? documentType,
    String? companyAddress,
    String? companyPhone,
    String? companyTaxNumber,
    String? companyCommercialRegister,
    bool? showTaxNumberOnPrint,
    bool? showCommercialRegisterOnPrint,
    bool? showCurrencySymbol,
    String? customerName,
    String? customerAddress,
    String? customerPhone,
    String? cashierName,
    double? previousBalance,
    double? newBalance,
    String? footer,
  }) {
    return Receipt(
      saleId: saleId ?? this.saleId,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      dateTime: dateTime ?? this.dateTime,
      companyName: companyName ?? this.companyName,
      branchName: branchName ?? this.branchName,
      lines: lines ?? this.lines,
      subtotal: subtotal ?? this.subtotal,
      discount: discount ?? this.discount,
      taxAmount: taxAmount ?? this.taxAmount,
      total: total ?? this.total,
      paidAmount: paidAmount ?? this.paidAmount,
      documentType: documentType ?? this.documentType,
      companyAddress: companyAddress ?? this.companyAddress,
      companyPhone: companyPhone ?? this.companyPhone,
      companyTaxNumber: companyTaxNumber ?? this.companyTaxNumber,
      companyCommercialRegister:
          companyCommercialRegister ?? this.companyCommercialRegister,
      showTaxNumberOnPrint:
          showTaxNumberOnPrint ?? this.showTaxNumberOnPrint,
      showCommercialRegisterOnPrint:
          showCommercialRegisterOnPrint ?? this.showCommercialRegisterOnPrint,
      showCurrencySymbol: showCurrencySymbol ?? this.showCurrencySymbol,
      customerName: customerName ?? this.customerName,
      customerAddress: customerAddress ?? this.customerAddress,
      customerPhone: customerPhone ?? this.customerPhone,
      cashierName: cashierName ?? this.cashierName,
      previousBalance: previousBalance ?? this.previousBalance,
      newBalance: newBalance ?? this.newBalance,
      footer: footer ?? this.footer,
    );
  }

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
        documentType,
        companyAddress,
        companyPhone,
        companyTaxNumber,
        companyCommercialRegister,
        showTaxNumberOnPrint,
        showCommercialRegisterOnPrint,
        showCurrencySymbol,
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
      'type: ${documentType.name}, '
      'lines: ${lines.length}, total: $total, paidAmount: $paidAmount, '
      'newBalance: $newBalance, showCurrencySymbol: $showCurrencySymbol)';
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

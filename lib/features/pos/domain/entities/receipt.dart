// lib/features/pos/domain/entities/receipt.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Immutable, self-contained representation of a sale receipt.
///
/// A [Receipt] is the data the POS needs to render or print an invoice. It
/// is intentionally independent of any other entity:
///
/// * It is **not** built from `Sale` directly inside this file, because
///   `Sale` lives in the sales feature and would create a feature-to-feature
///   dependency from `pos/domain` to `sales/domain`. The caller (the
///   payment dialog) composes the two.
/// * It is **not** tied to `PosCart` either, so a reprint of an older sale
///   can be modelled with the same type.
///
/// The entity is pure Dart: it does not know about Supabase, Flutter
/// widgets, or file systems. Rendering to PDF or to a thermal printer is
/// the responsibility of the data layer.
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
    this.invoiceNumber,
    this.customerName,
    this.cashierName,
    this.previousBalance,
    this.newBalance,
  });

  /// Stable identifier of the underlying sale (UUID).
  final String saleId;

  /// Optional human-facing invoice number.
  final String? invoiceNumber;

  /// Moment the sale was confirmed.
  final DateTime dateTime;

  /// Display name of the company that owns the sale.
  final String companyName;

  /// Display name of the branch where the sale was made.
  final String branchName;

  /// Line items, in the order they should be printed.
  final List<ReceiptLine> lines;

  /// Sum of line totals, before discount and tax.
  final double subtotal;

  /// Header-level discount.
  final double discount;

  /// Header-level tax amount.
  final double taxAmount;

  /// Net total = subtotal - discount + taxAmount.
  final double total;

  /// Amount actually paid by the customer.
  final double paidAmount;

  /// Cash returned to the customer (0 for card and credit).
  final double change;

  /// Optional customer name. `null` for cash sales.
  final String? customerName;

  /// Optional cashier name. `null` when unavailable.
  final String? cashierName;

  /// Customer balance before this sale, or `null` for cash sales.
  final double? previousBalance;

  /// Customer balance after this sale, or `null` for cash sales.
  final double? newBalance;

  // ---------------------------------------------------------------------------
  // Convenience
  // ---------------------------------------------------------------------------

  /// Whether the receipt carries a customer identity.
  bool get hasCustomer => customerName != null;

  /// Whether the receipt shows a balance evolution.
  bool get hasBalanceChange =>
      previousBalance != null && newBalance != null;

  /// Whether change was given back to the customer.
  bool get hasChange => change > 0;

  /// Number of distinct lines.
  int get lineCount => lines.length;

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
        customerName,
        cashierName,
        previousBalance,
        newBalance,
      ];

  @override
  String toString() =>
      'Receipt(saleId: $saleId, invoiceNumber: $invoiceNumber, '
      'lines: ${lines.length}, total: $total)';
}

/// Immutable, self-contained representation of a single receipt line.
///
/// Unlike `PosCartLine`, this type is deliberately minimal: it holds only
/// the fields that must appear on the printed receipt. It carries no
/// identifiers, no stock information, and no price bounds.
@immutable
class ReceiptLine extends Equatable {
  const ReceiptLine({
    required this.productName,
    required this.unitName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  /// Display name of the product.
  final String productName;

  /// Display name of the chosen unit (piece, carton, kilogram, ...).
  final String unitName;

  /// Quantity in [unitName]. Always strictly positive.
  final double quantity;

  /// Unit price applied to this line.
  final double unitPrice;

  /// Line total = quantity * unitPrice.
  final double lineTotal;

  @override
  List<Object?> get props =>
      <Object?>[productName, unitName, quantity, unitPrice, lineTotal];

  @override
  String toString() =>
      'ReceiptLine(productName: $productName, quantity: $quantity, '
      'unitPrice: $unitPrice)';
}

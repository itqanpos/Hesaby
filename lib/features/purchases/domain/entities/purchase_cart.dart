// lib/features/purchases/domain/entities/purchase_cart.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'purchase_cart_line.dart';

/// Immutable snapshot of the purchase cart.
///
/// Holds the current basket plus the header-level fields that the user
/// fills in alongside it: supplier, date, invoice number, notes, and the
/// header-level discount and tax. Mutations happen inside the notifier;
/// this class is never modified in place.
@immutable
class PurchaseCart extends Equatable {
  const PurchaseCart({
    this.lines = const <PurchaseCartLine>[],
    this.supplierId,
    this.supplierName,
    this.purchaseDate,
    this.invoiceNumber = '',
    this.notes = '',
    this.discount = 0,
    this.taxAmount = 0,
  });

  /// The lines currently in the cart, in insertion order.
  final List<PurchaseCartLine> lines;

  /// Identifier of the attached supplier, or `null`.
  final String? supplierId;

  /// Display name of the attached supplier.
  final String? supplierName;

  /// Business date of the purchase. `null` until the user picks one.
  final DateTime? purchaseDate;

  /// Optional supplier invoice number. Empty string when not set.
  final String invoiceNumber;

  /// Optional free-form notes. Empty string when not set.
  final String notes;

  /// Header-level discount, in the company's currency.
  final double discount;

  /// Header-level tax amount, in the company's currency.
  final double taxAmount;

  // ---------------------------------------------------------------------------
  // Status
  // ---------------------------------------------------------------------------

  bool get isEmpty => lines.isEmpty;

  bool get isNotEmpty => lines.isNotEmpty;

  bool get hasSupplier => supplierId != null;

  bool get hasPurchaseDate => purchaseDate != null;

  int get lineCount => lines.length;

  // ---------------------------------------------------------------------------
  // Totals
  // ---------------------------------------------------------------------------

  /// Sum of every line total, before discount and tax.
  double get subtotal => lines.fold<double>(
        0,
        (double sum, PurchaseCartLine line) => sum + line.lineTotal,
      );

  /// Net total = [subtotal] - [discount] + [taxAmount].
  double get total => subtotal - discount + taxAmount;

  // ---------------------------------------------------------------------------
  // Line lookup
  // ---------------------------------------------------------------------------

  /// Returns the line with the given `(productId, unitId)` pair, or `null`.
  PurchaseCartLine? findLine({
    required String productId,
    required String unitId,
  }) {
    final String target = '$productId::$unitId';
    for (final PurchaseCartLine line in lines) {
      if (line.key == target) {
        return line;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  PurchaseCart copyWith({
    List<PurchaseCartLine>? lines,
    String? supplierId,
    String? supplierName,
    bool clearSupplier = false,
    DateTime? purchaseDate,
    String? invoiceNumber,
    String? notes,
    double? discount,
    double? taxAmount,
  }) {
    return PurchaseCart(
      lines: lines ?? this.lines,
      supplierId: clearSupplier ? null : (supplierId ?? this.supplierId),
      supplierName:
          clearSupplier ? null : (supplierName ?? this.supplierName),
      purchaseDate: purchaseDate ?? this.purchaseDate,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      notes: notes ?? this.notes,
      discount: discount ?? this.discount,
      taxAmount: taxAmount ?? this.taxAmount,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        lines,
        supplierId,
        supplierName,
        purchaseDate,
        invoiceNumber,
        notes,
        discount,
        taxAmount,
      ];

  @override
  String toString() =>
      'PurchaseCart(lines: ${lines.length}, supplierId: $supplierId, '
      'discount: $discount, taxAmount: $taxAmount, total: $total)';
}

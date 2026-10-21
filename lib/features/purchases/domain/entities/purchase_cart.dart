// lib/features/purchases/domain/entities/purchase_cart.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'purchase_cart_line.dart';

/// Immutable snapshot of the purchase cart.
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
    this.paidAmount = 0,
    this.paymentMethod = 'cash',
  });

  final List<PurchaseCartLine> lines;
  final String? supplierId;
  final String? supplierName;
  final DateTime? purchaseDate;
  final String invoiceNumber;
  final String notes;
  final double discount;
  final double taxAmount;
  
  /// ⬇️ جديد: المبلغ المدفوع وطريقة الدفع
  final double paidAmount;
  final String paymentMethod;

  // ---------------------------------------------------------------------------
  // Computed
  // ---------------------------------------------------------------------------

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;
  int get lineCount => lines.length;

  bool get hasSupplier => supplierId != null;
  bool get hasPurchaseDate => purchaseDate != null;

  double get subtotal => lines.fold<double>(
        0,
        (double sum, PurchaseCartLine line) => sum + line.lineTotal,
      );

  double get total => subtotal - discount + taxAmount;

  // ---------------------------------------------------------------------------
  // Line lookup
  // ---------------------------------------------------------------------------

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
    double? paidAmount,
    String? paymentMethod,
  }) {
    return PurchaseCart(
      lines: lines ?? this.lines,
      supplierId:
          clearSupplier ? null : (supplierId ?? this.supplierId),
      supplierName:
          clearSupplier ? null : (supplierName ?? this.supplierName),
      purchaseDate: purchaseDate ?? this.purchaseDate,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      notes: notes ?? this.notes,
      discount: discount ?? this.discount,
      taxAmount: taxAmount ?? this.taxAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
    );
  }

  // ---------------------------------------------------------------------------
  // Equatable
  // ---------------------------------------------------------------------------

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
        paidAmount,
        paymentMethod,
      ];

  @override
  String toString() =>
      'PurchaseCart(lines: ${lines.length}, supplierId: $supplierId, '
      'total: $total, paid: $paidAmount)';
}

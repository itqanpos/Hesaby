// lib/features/pos/domain/entities/pos_cart.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'pos_cart_line.dart';

/// Immutable snapshot of the POS cart.
///
/// This is a pure value object: it holds the current basket, the attached
/// customer (if any), and the header-level discount and tax. All mutations
/// happen inside the notifier; this class is never modified in place.
///
/// Computed getters are provided for the presentation layer so that
/// rebuilding a totals bar never requires re-walking the lines by hand.
@immutable
class PosCart extends Equatable {
  const PosCart({
    this.lines = const <PosCartLine>[],
    this.customerId,
    this.customerName,
    this.customerBalance = 0,
    this.discount = 0,
    this.taxAmount = 0,
  });

  /// The lines currently in the cart, in insertion order.
  ///
  /// A line is uniquely identified by `(productId, unitId)`; the notifier
  /// merges matching lines instead of appending duplicates.
  final List<PosCartLine> lines;

  /// Identifier of the attached customer, or `null` for a cash sale.
  final String? customerId;

  /// Display name of the attached customer. Meaningful only when
  /// [customerId] is not `null`.
  final String? customerName;

  /// Snapshot of the customer's outstanding balance at the moment they
  /// were attached. Used by the payment dialog; never authoritative.
  final double customerBalance;

  /// Header-level discount, in the company's currency.
  final double discount;

  /// Header-level tax amount, in the company's currency. This is a fixed
  /// amount (not a percentage), matching the `sales.tax_amount` column.
  final double taxAmount;

  // ---------------------------------------------------------------------------
  // Status
  // ---------------------------------------------------------------------------

  /// Whether the cart holds no lines.
  bool get isEmpty => lines.isEmpty;

  /// Whether the cart holds at least one line.
  bool get isNotEmpty => lines.isNotEmpty;

  /// Number of distinct lines in the cart.
  int get lineCount => lines.length;

  /// Sum of every line's quantity, in their own units.
  ///
  /// This is a rough measure for display only — units may differ across
  /// lines, so it should not be interpreted as a physical count.
  double get totalQuantity => lines.fold<double>(
        0,
        (double sum, PosCartLine line) => sum + line.quantity,
      );

  // ---------------------------------------------------------------------------
  // Totals
  // ---------------------------------------------------------------------------

  /// Sum of every line total, before discount and tax.
  double get subtotal => lines.fold<double>(
        0,
        (double sum, PosCartLine line) => sum + line.lineTotal,
      );

  /// Net total = [subtotal] - [discount] + [taxAmount].
  double get total => subtotal - discount + taxAmount;

  // ---------------------------------------------------------------------------
  // Customer
  // ---------------------------------------------------------------------------

  /// Whether a registered customer is attached to the cart.
  bool get hasCustomer => customerId != null;

  /// Whether the attached customer has an outstanding balance.
  bool get hasCustomerBalance => hasCustomer && customerBalance > 0;

  /// Total amount the customer will be asked to settle, including any
  /// previous balance.
  ///
  /// Used by the payment dialog to show "الإجمالي المطلوب".
  double get settlementTotal => customerBalance + total;

  // ---------------------------------------------------------------------------
  // Line lookup
  // ---------------------------------------------------------------------------

  /// Returns the line with the given `(productId, unitId)` pair, or `null`
  /// when the cart does not contain it.
  PosCartLine? findLine({
    required String productId,
    required String unitId,
  }) {
    final String target = '$productId::$unitId';
    for (final PosCartLine line in lines) {
      if (line.key == target) {
        return line;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  /// Returns a copy with the given fields replaced.
  ///
  /// Nullable customer fields are preserved unless [clearCustomer] is
  /// `true`, so callers can distinguish "leave as is" from "reset".
  PosCart copyWith({
    List<PosCartLine>? lines,
    String? customerId,
    String? customerName,
    double? customerBalance,
    bool clearCustomer = false,
    double? discount,
    double? taxAmount,
  }) {
    return PosCart(
      lines: lines ?? this.lines,
      customerId: clearCustomer ? null : (customerId ?? this.customerId),
      customerName:
          clearCustomer ? null : (customerName ?? this.customerName),
      customerBalance:
          clearCustomer ? 0 : (customerBalance ?? this.customerBalance),
      discount: discount ?? this.discount,
      taxAmount: taxAmount ?? this.taxAmount,
    );
  }

  // ---------------------------------------------------------------------------
  // Equatable
  // ---------------------------------------------------------------------------

  @override
  List<Object?> get props => <Object?>[
        lines,
        customerId,
        customerName,
        customerBalance,
        discount,
        taxAmount,
      ];

  @override
  String toString() =>
      'PosCart(lines: ${lines.length}, customerId: $customerId, '
      'discount: $discount, taxAmount: $taxAmount, total: $total)';
}

// lib/features/pos/pos_cart.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ============================================================================
// Cart line
// ============================================================================

/// One line in the POS cart.
///
/// A line is uniquely identified by the pair `(productId, unitId)`. Adding
/// the same product with the same unit merges quantities into a single line;
/// adding it with a different unit creates a second line.
///
/// Display data (`productName`, `unitName`) is cached so that the cart and
/// the receipt do not need to re-resolve names on every rebuild.
@immutable
class PosCartLine extends Equatable {
  const PosCartLine({
    required this.productId,
    required this.productName,
    required this.unitId,
    required this.unitName,
    required this.conversionFactor,
    required this.quantity,
    required this.unitPrice,
  });

  final String productId;
  final String productName;
  final String unitId;
  final String unitName;

  /// How many base units equal one of [unitId]. Provided for display only.
  final double conversionFactor;

  /// Quantity. Always strictly positive.
  final double quantity;

  /// Selling price per [unitId]. Always non-negative.
  final double unitPrice;

  /// Line total = quantity * unitPrice.
  double get lineTotal => quantity * unitPrice;

  /// Equality key for line identity within the cart.
  String get key => '$productId::$unitId';

  PosCartLine copyWith({
    String? productName,
    String? unitName,
    double? conversionFactor,
    double? quantity,
    double? unitPrice,
  }) {
    return PosCartLine(
      productId: productId,
      productName: productName ?? this.productName,
      unitId: unitId,
      unitName: unitName ?? this.unitName,
      conversionFactor: conversionFactor ?? this.conversionFactor,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        productId,
        productName,
        unitId,
        unitName,
        conversionFactor,
        quantity,
        unitPrice,
      ];

  @override
  String toString() =>
      'PosCartLine(productId: $productId, unitId: $unitId, '
      'quantity: $quantity, unitPrice: $unitPrice)';
}

// ============================================================================
// Cart state
// ============================================================================

/// Immutable snapshot of the POS cart.
@immutable
class PosCartState extends Equatable {
  const PosCartState({
    this.lines = const <PosCartLine>[],
    this.customerId,
    this.customerName,
    this.customerBalance = 0,
    this.discount = 0,
    this.taxAmount = 0,
  });

  final List<PosCartLine> lines;

  /// Customer identifier, or `null` for a cash sale.
  final String? customerId;

  /// Cached customer name for display. Meaningful only when [customerId] is
  /// not null.
  final String? customerName;

  /// The customer's existing balance at the moment they were attached to
  /// the cart. Cached so the payment dialog does not need an extra query.
  final double customerBalance;

  final double discount;
  final double taxAmount;

  // ---------------------------------------------------------------------------
  // Computed
  // ---------------------------------------------------------------------------

  bool get isEmpty => lines.isEmpty;

  bool get isNotEmpty => lines.isNotEmpty;

  int get lineCount => lines.length;

  /// Total number of physical units in the cart (sum of quantities).
  double get totalQuantity => lines.fold<double>(
        0,
        (double sum, PosCartLine line) => sum + line.quantity,
      );

  double get subtotal => lines.fold<double>(
        0,
        (double sum, PosCartLine line) => sum + line.lineTotal,
      );

  double get total => subtotal - discount + taxAmount;

  bool get hasCustomer => customerId != null;

  /// Amount the customer will owe after this sale if nothing is paid now.
  /// Old balance + current invoice total.
  double get settlementTotal => customerBalance + total;

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  PosCartState copyWith({
    List<PosCartLine>? lines,
    String? customerId,
    String? customerName,
    double? customerBalance,
    bool clearCustomer = false,
    double? discount,
    double? taxAmount,
  }) {
    return PosCartState(
      lines: lines ?? this.lines,
      customerId: clearCustomer ? null : (customerId ?? this.customerId),
      customerName: clearCustomer ? null : (customerName ?? this.customerName),
      customerBalance:
          clearCustomer ? 0 : (customerBalance ?? this.customerBalance),
      discount: discount ?? this.discount,
      taxAmount: taxAmount ?? this.taxAmount,
    );
  }

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
      'PosCartState(lines: ${lines.length}, '
      'customerId: $customerId, discount: $discount, tax: $taxAmount, '
      'total: $total)';
}

// ============================================================================
// Cart notifier
// ============================================================================

/// Owns the POS cart state.
///
/// All operations are synchronous and local: nothing reaches the database
/// until the sale is completed from the payment dialog. The notifier is
/// intentionally not an `AsyncNotifier` — the cart is pure UI state.
class PosCartNotifier extends Notifier<PosCartState> {
  @override
  PosCartState build() => const PosCartState();

  // ---------------------------------------------------------------------------
  // Line operations
  // ---------------------------------------------------------------------------

  /// Adds a product line to the cart.
  ///
  /// When a line with the same `(productId, unitId)` already exists, its
  /// quantity is increased by [quantity] and its unit price is updated to
  /// [unitPrice] (the caller is expected to pass the same price).
  /// Otherwise a new line is appended.
  void addLine({
    required String productId,
    required String productName,
    required String unitId,
    required String unitName,
    required double conversionFactor,
    required double quantity,
    required double unitPrice,
  }) {
    if (quantity <= 0) {
      return;
    }
    final String key = '$productId::$unitId';

    final List<PosCartLine> next = <PosCartLine>[];
    bool merged = false;

    for (final PosCartLine line in state.lines) {
      if (line.key == key) {
        next.add(
          line.copyWith(
            quantity: line.quantity + quantity,
            unitPrice: unitPrice,
            productName: productName,
            unitName: unitName,
            conversionFactor: conversionFactor,
          ),
        );
        merged = true;
      } else {
        next.add(line);
      }
    }

    if (!merged) {
      next.add(
        PosCartLine(
          productId: productId,
          productName: productName,
          unitId: unitId,
          unitName: unitName,
          conversionFactor: conversionFactor,
          quantity: quantity,
          unitPrice: unitPrice,
        ),
      );
    }

    state = state.copyWith(lines: next);
  }

  /// Replaces the quantity of a specific line.
  ///
  /// A quantity of zero or less removes the line.
  void setLineQuantity({
    required String productId,
    required String unitId,
    required double quantity,
  }) {
    final String key = '$productId::$unitId';
    final List<PosCartLine> next = <PosCartLine>[];

    for (final PosCartLine line in state.lines) {
      if (line.key != key) {
        next.add(line);
      } else if (quantity > 0) {
        next.add(line.copyWith(quantity: quantity));
      }
    }

    state = state.copyWith(lines: next);
  }

  /// Replaces the unit price of a specific line.
  void setLinePrice({
    required String productId,
    required String unitId,
    required double unitPrice,
  }) {
    final String key = '$productId::$unitId';
    final List<PosCartLine> next = state.lines.map((PosCartLine line) {
      if (line.key != key) {
        return line;
      }
      return line.copyWith(unitPrice: unitPrice);
    }).toList(growable: false);

    state = state.copyWith(lines: next);
  }

  /// Increments the quantity of a line by one.
  void incrementLine({
    required String productId,
    required String unitId,
  }) {
    final String key = '$productId::$unitId';
    final List<PosCartLine> next = state.lines.map((PosCartLine line) {
      if (line.key != key) {
        return line;
      }
      return line.copyWith(quantity: line.quantity + 1);
    }).toList(growable: false);

    state = state.copyWith(lines: next);
  }

  /// Decrements the quantity of a line by one.
  ///
  /// When the resulting quantity reaches zero, the line is removed.
  void decrementLine({
    required String productId,
    required String unitId,
  }) {
    final String key = '$productId::$unitId';
    final List<PosCartLine> next = <PosCartLine>[];

    for (final PosCartLine line in state.lines) {
      if (line.key != key) {
        next.add(line);
        continue;
      }
      final double newQuantity = line.quantity - 1;
      if (newQuantity > 0) {
        next.add(line.copyWith(quantity: newQuantity));
      }
    }

    state = state.copyWith(lines: next);
  }

  /// Removes a line regardless of its quantity.
  void removeLine({
    required String productId,
    required String unitId,
  }) {
    final String key = '$productId::$unitId';
    final List<PosCartLine> next = state.lines
        .where((PosCartLine line) => line.key != key)
        .toList(growable: false);

    state = state.copyWith(lines: next);
  }

  /// Clears every line but keeps the customer, discount and tax settings.
  void clearLines() {
    state = state.copyWith(lines: const <PosCartLine>[]);
  }

  /// Resets the entire cart to its initial state.
  void reset() {
    state = const PosCartState();
  }

  // ---------------------------------------------------------------------------
  // Customer
  // ---------------------------------------------------------------------------

  /// Attaches a registered customer to the cart.
  void setCustomer({
    required String customerId,
    required String customerName,
    required double customerBalance,
  }) {
    state = state.copyWith(
      customerId: customerId,
      customerName: customerName,
      customerBalance: customerBalance,
    );
  }

  /// Detaches the current customer (reverts to a cash sale).
  void clearCustomer() {
    state = state.copyWith(clearCustomer: true);
  }

  // ---------------------------------------------------------------------------
  // Discount / tax
  // ---------------------------------------------------------------------------

  void setDiscount(double discount) {
    state = state.copyWith(discount: discount < 0 ? 0 : discount);
  }

  void setTaxAmount(double taxAmount) {
    state = state.copyWith(taxAmount: taxAmount < 0 ? 0 : taxAmount);
  }
}

/// Provides the POS cart.
final NotifierProvider<PosCartNotifier, PosCartState> posCartProvider =
    NotifierProvider<PosCartNotifier, PosCartState>(PosCartNotifier.new);

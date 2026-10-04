// lib/features/pos/presentation/state/pos_cart_notifier.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/pos_cart.dart';
import '../../domain/entities/pos_cart_line.dart';

/// Owns the POS cart state.
///
/// Every operation is synchronous and local. Nothing reaches the database
/// until the sale is confirmed from the payment dialog; this notifier is
/// strictly UI state.
///
/// Conventions:
/// * Lines are uniquely identified by `(productId, unitId)`. Adding the
///   same product with the same unit merges quantities; adding it with a
///   different unit creates a second line.
/// * A line whose quantity reaches zero is removed automatically.
/// * The cashier may edit the unit price only within the bounds carried by
///   each line ([PosCartLine.isPriceValid]); out-of-range inputs are
///   rejected silently by the notifier and the caller is expected to have
///   validated them first.
/// * Discount and tax are clamped at zero.
class PosCartNotifier extends Notifier<PosCart> {
  @override
  PosCart build() => const PosCart();

  // ---------------------------------------------------------------------------
  // Line operations
  // ---------------------------------------------------------------------------

  /// Adds a product line to the cart, or merges into an existing line with
  /// the same `(productId, unitId)`.
  ///
  /// The merge rule is:
  /// * quantities are summed,
  /// * the newest [unitPrice], [productName], [unitName] and
  ///   [conversionFactor] replace the previous ones,
  /// * price bounds and the available-stock snapshot are taken from the
  ///   newest call (they are advisory only).
  ///
  /// Returns `true` when a line was added or merged; `false` when the call
  /// was rejected (quantity ≤ 0, or the resulting quantity would exceed
  /// the known available stock).
  bool addLine({
    required String productId,
    required String productName,
    required String unitId,
    required String unitName,
    required double conversionFactor,
    required double quantity,
    required double unitPrice,
    double? minSellingPrice,
    double? maxSellingPrice,
    double? availableStock,
    String? notes,
  }) {
    if (quantity <= 0) {
      return false;
    }

    final String key = '$productId::$unitId';
    final List<PosCartLine> next = <PosCartLine>[];
    bool merged = false;

    for (final PosCartLine line in state.lines) {
      if (line.key != key) {
        next.add(line);
        continue;
      }

      final double mergedQuantity = line.quantity + quantity;
      if (availableStock != null && mergedQuantity > availableStock) {
        // Reject silently: the caller is expected to have validated.
        return false;
      }

      next.add(
        line.copyWith(
          productName: productName,
          unitName: unitName,
          conversionFactor: conversionFactor,
          quantity: mergedQuantity,
          unitPrice: unitPrice,
          minSellingPrice: minSellingPrice,
          clearMinSellingPrice: minSellingPrice == null,
          maxSellingPrice: maxSellingPrice,
          clearMaxSellingPrice: maxSellingPrice == null,
          availableStock: availableStock,
          clearAvailableStock: availableStock == null,
          notes: notes,
          clearNotes: notes == null || notes.trim().isEmpty,
        ),
      );
      merged = true;
    }

    if (!merged) {
      if (availableStock != null && quantity > availableStock) {
        return false;
      }
      next.add(
        PosCartLine(
          productId: productId,
          productName: productName,
          unitId: unitId,
          unitName: unitName,
          conversionFactor: conversionFactor,
          quantity: quantity,
          unitPrice: unitPrice,
          minSellingPrice: minSellingPrice,
          maxSellingPrice: maxSellingPrice,
          availableStock: availableStock,
          notes: notes,
        ),
      );
    }

    state = state.copyWith(lines: next);
    return true;
  }

  /// Increments the quantity of a line by one, if allowed by its known
  /// available stock.
  ///
  /// Returns `true` when the increment was applied.
  bool incrementLine({
    required String productId,
    required String unitId,
  }) {
    final String key = '$productId::$unitId';
    bool applied = false;

    final List<PosCartLine> next = state.lines.map((PosCartLine line) {
      if (line.key != key || !line.canIncrease) {
        return line;
      }
      applied = true;
      return line.copyWith(quantity: line.quantity + 1);
    }).toList(growable: false);

    if (applied) {
      state = state.copyWith(lines: next);
    }
    return applied;
  }

  /// Decrements the quantity of a line by one. A line whose resulting
  /// quantity reaches zero is removed.
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
      // Otherwise, drop the line silently.
    }

    state = state.copyWith(lines: next);
  }

  /// Sets the exact quantity of a line. A quantity ≤ 0 removes the line.
  ///
  /// Returns `true` when the value was accepted (either applied or used
  /// to remove the line); `false` when the new quantity exceeds the known
  /// available stock.
  bool setLineQuantity({
    required String productId,
    required String unitId,
    required double quantity,
  }) {
    final String key = '$productId::$unitId';
    final List<PosCartLine> next = <PosCartLine>[];
    bool rejected = false;

    for (final PosCartLine line in state.lines) {
      if (line.key != key) {
        next.add(line);
        continue;
      }
      if (quantity <= 0) {
        // Remove the line.
        continue;
      }
      final double? available = line.availableStock;
      if (available != null && quantity > available) {
        rejected = true;
        next.add(line);
        continue;
      }
      next.add(line.copyWith(quantity: quantity));
    }

    if (!rejected) {
      state = state.copyWith(lines: next);
      return true;
    }
    return false;
  }

  /// Sets the unit price of a line, provided it is within the line's
  /// allowed range.
  ///
  /// Returns `true` when the value was accepted.
  bool setLinePrice({
    required String productId,
    required String unitId,
    required double unitPrice,
  }) {
    final String key = '$productId::$unitId';
    final List<PosCartLine> next = <PosCartLine>[];
    bool rejected = false;

    for (final PosCartLine line in state.lines) {
      if (line.key != key) {
        next.add(line);
        continue;
      }
      if (unitPrice < 0) {
        rejected = true;
        next.add(line);
        continue;
      }
      final PosCartLine candidate = line.copyWith(unitPrice: unitPrice);
      if (!candidate.isPriceValid) {
        rejected = true;
        next.add(line);
        continue;
      }
      next.add(candidate);
    }

    if (!rejected) {
      state = state.copyWith(lines: next);
      return true;
    }
    return false;
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

  /// Clears every line but keeps the attached customer, discount and tax.
  void clearLines() {
    state = state.copyWith(lines: const <PosCartLine>[]);
  }

  /// Resets the entire cart to its initial empty state.
  void reset() {
    state = const PosCart();
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

  /// Detaches the current customer, reverting to a cash sale.
  void clearCustomer() {
    state = state.copyWith(clearCustomer: true);
  }

  // ---------------------------------------------------------------------------
  // Discount / tax
  // ---------------------------------------------------------------------------

  /// Sets the header-level discount. Negative values are clamped to zero.
  void setDiscount(double discount) {
    state = state.copyWith(discount: discount < 0 ? 0 : discount);
  }

  /// Sets the header-level tax amount. Negative values are clamped to zero.
  void setTaxAmount(double taxAmount) {
    state = state.copyWith(taxAmount: taxAmount < 0 ? 0 : taxAmount);
  }
}

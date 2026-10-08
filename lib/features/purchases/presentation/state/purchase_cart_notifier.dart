// lib/features/purchases/presentation/state/purchase_cart_notifier.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/unit.dart';
import '../../domain/entities/purchase_cart.dart';
import '../../domain/entities/purchase_cart_line.dart';

/// Owns the state of the purchase cart.
///
/// Synchronous by design: every method mutates the state in place. The
/// submission to the backend happens elsewhere (in the form page). This
/// mirrors `PosCartNotifier` for consistency.
class PurchaseCartNotifier extends Notifier<PurchaseCart> {
  @override
  PurchaseCart build() => const PurchaseCart();

  // ---------------------------------------------------------------------------
  // Lines
  // ---------------------------------------------------------------------------

  /// Adds [product] (with [unit]) to the cart.
  ///
  /// When [unitCost] is `null`, the product's current `costPrice` is used.
  /// When the same `(productId, unitId)` already exists, its quantity is
  /// increased instead of adding a second line.
  void addProduct({
    required Product product,
    required Unit unit,
    double quantity = 1,
    double? unitCost,
  }) {
    if (quantity <= 0) {
      return;
    }

    final double cost = unitCost ?? product.costPrice;
    final PurchaseCartLine? existing = state.findLine(
      productId: product.id,
      unitId: unit.id,
    );

    if (existing != null) {
      state = state.copyWith(
        lines: <PurchaseCartLine>[
          for (final PurchaseCartLine line in state.lines)
            if (line.key == existing.key)
              line.copyWith(quantity: line.quantity + quantity)
            else
              line,
        ],
      );
      return;
    }

    final PurchaseCartLine newLine = PurchaseCartLine(
      productId: product.id,
      productName: product.name,
      unitId: unit.id,
      unitName: unit.name,
      conversionFactor: 1,
      quantity: quantity,
      unitCost: cost,
    );

    state = state.copyWith(
      lines: <PurchaseCartLine>[...state.lines, newLine],
    );
  }

  /// Removes the line with [key] (`productId::unitId`).
  void removeLine(String key) {
    state = state.copyWith(
      lines: state.lines
          .where((PurchaseCartLine line) => line.key != key)
          .toList(growable: false),
    );
  }

  /// Sets a new quantity for the line with [key]. Rejected when ≤ 0.
  void setQuantity(String key, double quantity) {
    if (quantity <= 0) {
      return;
    }
    state = state.copyWith(
      lines: <PurchaseCartLine>[
        for (final PurchaseCartLine line in state.lines)
          if (line.key == key)
            line.copyWith(quantity: quantity)
          else
            line,
      ],
    );
  }

  /// Sets a new unit cost for the line with [key]. Rejected when < 0.
  void setUnitCost(String key, double cost) {
    if (cost < 0) {
      return;
    }
    state = state.copyWith(
      lines: <PurchaseCartLine>[
        for (final PurchaseCartLine line in state.lines)
          if (line.key == key) line.copyWith(unitCost: cost) else line,
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Header fields
  // ---------------------------------------------------------------------------

  /// Attaches a supplier to the cart.
  void setSupplier({required String id, required String name}) {
    state = state.copyWith(supplierId: id, supplierName: name);
  }

  /// Detaches the current supplier.
  void clearSupplier() {
    state = state.copyWith(clearSupplier: true);
  }

  /// Sets the purchase business date.
  void setPurchaseDate(DateTime date) {
    state = state.copyWith(purchaseDate: date);
  }

  /// Sets the (optional) supplier invoice number.
  void setInvoiceNumber(String value) {
    state = state.copyWith(invoiceNumber: value);
  }

  /// Sets the (optional) free-form notes.
  void setNotes(String value) {
    state = state.copyWith(notes: value);
  }

  /// Sets the header-level discount. Negative values are clamped to 0.
  void setDiscount(double value) {
    state = state.copyWith(discount: value < 0 ? 0 : value);
  }

  /// Sets the header-level tax amount. Negative values are clamped to 0.
  void setTaxAmount(double value) {
    state = state.copyWith(taxAmount: value < 0 ? 0 : value);
  }

  // ---------------------------------------------------------------------------
  // Reset
  // ---------------------------------------------------------------------------

  /// Clears the whole cart back to its initial empty state.
  void reset() {
    state = const PurchaseCart();
  }
}

// lib/features/purchases/presentation/state/purchase_cart_notifier.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/unit.dart';
import '../../domain/entities/purchase_cart.dart';
import '../../domain/entities/purchase_cart_line.dart';

class PurchaseCartNotifier extends Notifier<PurchaseCart> {
  @override
  PurchaseCart build() => const PurchaseCart();

  // ---------------------------------------------------------------------------
  // Lines
  // ---------------------------------------------------------------------------

  void addProduct({
    required Product product,
    required Unit unit,
    double quantity = 1,
    double? unitCost,
    double conversionFactor = 1,
  }) {
    if (quantity <= 0) return;

    final double factor = conversionFactor > 0 ? conversionFactor : 1;
    final double cost = unitCost ?? (product.costPrice * factor);
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
      conversionFactor: factor,
      quantity: quantity,
      unitCost: cost,
    );

    state = state.copyWith(
      lines: <PurchaseCartLine>[...state.lines, newLine],
    );
  }

  void removeLine(String key) {
    state = state.copyWith(
      lines: state.lines
          .where((PurchaseCartLine line) => line.key != key)
          .toList(growable: false),
    );
  }

  void setQuantity(String key, double quantity) {
    if (quantity <= 0) return;
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

  void setUnitCost(String key, double cost) {
    if (cost < 0) return;
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

  void setSupplier({required String id, required String name}) {
    state = state.copyWith(supplierId: id, supplierName: name);
  }

  void clearSupplier() {
    state = state.copyWith(clearSupplier: true);
  }

  void setPurchaseDate(DateTime date) {
    state = state.copyWith(purchaseDate: date);
  }

  void setInvoiceNumber(String value) {
    state = state.copyWith(invoiceNumber: value);
  }

  void setNotes(String value) {
    state = state.copyWith(notes: value);
  }

  void setDiscount(double value) {
    state = state.copyWith(discount: value < 0 ? 0 : value);
  }

  void setTaxAmount(double value) {
    state = state.copyWith(taxAmount: value < 0 ? 0 : value);
  }

  // ⬇️ دوال الدفع الجديدة
  void setPaidAmount(double value) {
    state = state.copyWith(paidAmount: value < 0 ? 0 : value);
  }

  void setPaymentMethod(String value) {
    state = state.copyWith(paymentMethod: value);
  }

  // ---------------------------------------------------------------------------
  // Reset
  // ---------------------------------------------------------------------------

  void reset() {
    state = const PurchaseCart();
  }
}

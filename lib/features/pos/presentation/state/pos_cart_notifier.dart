// lib/features/pos/presentation/state/pos_cart_notifier.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/pos_cart.dart';
import '../../domain/entities/pos_cart_line.dart';

/// Owns the POS cart state.
class PosCartNotifier extends Notifier<PosCart> {
  @override
  PosCart build() => const PosCart();

  // ---------------------------------------------------------------------------
  // Line operations
  // ---------------------------------------------------------------------------

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
      final double candidate = line.quantity + 1;
      final double? available = line.availableStock;
      if (available != null && candidate > available) {
        return line;
      }
      applied = true;
      return line.copyWith(quantity: candidate);
    }).toList(growable: false);

    if (applied) {
      state = state.copyWith(lines: next);
    }
    return applied;
  }

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

  void clearLines() {
    state = state.copyWith(lines: const <PosCartLine>[]);
  }

  void reset() {
    state = const PosCart();
  }

  /// ⬇️ دالة جديدة: استعادة السلة المعلقة
  /// تستبدل الحالة الحالية بالكامل بالسلة المحفوظة مسبقاً.
  void restore(PosCart cart) {
    state = cart;
  }

  // ---------------------------------------------------------------------------
  // Customer
  // ---------------------------------------------------------------------------

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

  void updateCustomerBalance(double customerBalance) {
    if (state.customerId == null) {
      return;
    }
    if (state.customerBalance == customerBalance) {
      return;
    }
    state = state.copyWith(customerBalance: customerBalance);
  }

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

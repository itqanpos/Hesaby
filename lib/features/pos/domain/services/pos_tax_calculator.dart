// lib/features/pos/domain/services/pos_tax_calculator.dart

/// Tax and total rules for a POS sale.
///
/// Pure Dart, with no Flutter or Riverpod imports, so every screen (totals
/// bar, pay button, bottom panel, payment dialog, receipt) can share it and
/// it can be unit-tested directly.
abstract final class PosTaxCalculator {
  /// Rounds an amount to two decimals.
  static double roundMoney(double value) =>
      (value * 100).roundToDouble() / 100;

  /// Tax for a sale.
  ///
  /// * A manual tax amount entered in the cart wins when it is positive.
  /// * Otherwise the company default rate applies to the amount after discount.
  /// * Never negative, and no tax when the base is zero.
  static double taxFor({
    required double afterDiscount,
    required double manualTax,
    required double defaultTaxRate,
  }) {
    if (manualTax > 0) {
      return roundMoney(manualTax);
    }
    final double base = afterDiscount < 0 ? 0 : afterDiscount;
    if (defaultTaxRate <= 0 || base == 0) {
      return 0;
    }
    return roundMoney(base * defaultTaxRate / 100);
  }

  /// Net total: amount after discount plus tax. Never negative.
  static double totalFor({
    required double afterDiscount,
    required double tax,
  }) {
    final double base = afterDiscount < 0 ? 0 : afterDiscount;
    return roundMoney(base + tax);
  }
}

// lib/features/pos/domain/services/receipt_number_format.dart

/// Number formatting shared by the receipt builders (ESC/POS and PDF).
///
/// Kept free of Flutter and PDF imports so it can be unit-tested directly.
abstract final class ReceiptNumberFormat {
  /// Formats an amount as `1,250.50 <currency>`.
  ///
  /// Thousands are separated in both the whole and the decimal form
  /// (`1,250` and `1,250.50`). Negative amounts keep a leading minus sign,
  /// and a value that rounds to zero is never shown as `-0.00`.
  static String money(double value, {required String currency}) {
    final double abs = value.abs();
    final String absFixed = abs.toStringAsFixed(2);
    final bool negative = value < 0 && absFixed != '0.00';

    final String body;
    if (abs == abs.roundToDouble()) {
      body = thousands(abs.toInt().toString());
    } else {
      final int dot = absFixed.indexOf('.');
      body = '${thousands(absFixed.substring(0, dot))}${absFixed.substring(dot)}';
    }
    return '${negative ? '-' : ''}$body $currency';
  }

  /// Formats a quantity: whole numbers without decimals, otherwise two.
  static String quantity(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  /// Inserts a comma every three digits in an integer string.
  /// Accepts an optional leading minus sign.
  static String thousands(String intStr) {
    final bool negative = intStr.startsWith('-');
    final String digits = negative ? intStr.substring(1) : intStr;
    final StringBuffer buf = StringBuffer();
    if (negative) buf.write('-');
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buf.write(',');
      }
      buf.write(digits[i]);
    }
    return buf.toString();
  }
}

// lib/core/utils/formatters.dart

import 'package:intl/intl.dart';

/// Centralised number, currency and date formatters used across the app.
///
/// **Why this file exists**
/// -----------------------
/// Every screen in Hesabi must display numbers with **Latin digits**
/// (0–9), even though the UI is Arabic. The `intl` package defaults to
/// Arabic-Indic digits when the locale is `ar_EG`, so we always build the
/// `NumberFormat` / `DateFormat` instances against `en_US` — the layout
/// stays Arabic because the *labels* are Arabic; only the digits are
/// Latin.
///
/// Centralising the formats here guarantees:
/// * The same currency symbol and decimal places everywhere.
/// * The same 12-hour time style with ص / م markers.
/// * A single place to change when a future requirement arrives.
abstract final class AppFormatters {
  // ---------------------------------------------------------------------------
  // Money
  // ---------------------------------------------------------------------------

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );

  static final NumberFormat _moneyPlain = NumberFormat('#,##0.00', 'en_US');

  /// `12,345.67 ج.م`
  static String money(double value) => _money.format(value);

  /// `12,345.67` (no currency symbol).
  static String moneyPlain(double value) => _moneyPlain.format(value);

  /// Signed money, e.g. `+ 500.00 ج.م` / `− 500.00 ج.م`.
  ///
  /// Uses a real Unicode minus (U+2212) for better readability in Arabic
  /// contexts.
  static String signedMoney(double value) {
    if (value < 0) return '− ${_moneyPlain.format(-value)} ج.م';
    if (value > 0) return '+ ${_moneyPlain.format(value)} ج.م';
    return '0.00 ج.م';
  }

  // ---------------------------------------------------------------------------
  // Numbers
  // ---------------------------------------------------------------------------

  static final NumberFormat _integer = NumberFormat('#,##0', 'en_US');
  static final NumberFormat _decimal = NumberFormat('#,##0.##', 'en_US');

  /// `12,345`
  static String integer(int value) => _integer.format(value);

  /// `12,345` or `12,345.5` — as many decimals as needed (max 2).
  static String number(num value) => _decimal.format(value);

  /// Quantities on receipts: `3` (int) or `2.5` (fractional), never with
  /// trailing zeros.
  static String quantity(double value) {
    if (value == value.roundToDouble()) {
      return _integer.format(value.toInt());
    }
    return _decimal.format(value);
  }

  /// Percentage: `12.5%`.
  static String percent(double value) {
    return '${_decimal.format(value)}%';
  }

  // ---------------------------------------------------------------------------
  // Dates & times
  // ---------------------------------------------------------------------------

  /// `2026/10/11  08:33 م`
  ///
  /// Uses 12-hour time with Arabic markers (`ص` / `م`), Latin digits, and
  /// the internationally unambiguous `yyyy/MM/dd` order.
  static String dateTime(DateTime value) {
    final DateTime l = value.toLocal();
    final int h24 = l.hour;
    final int h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    final String ampm = h24 >= 12 ? 'م' : 'ص';
    return '${_datePart(l)}  ${_two(h12)}:${_two(l.minute)} $ampm';
  }

  /// `2026/10/11`
  static String date(DateTime value) => _datePart(value.toLocal());

  /// `08:33 م` — time only.
  static String time(DateTime value) {
    final DateTime l = value.toLocal();
    final int h24 = l.hour;
    final int h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    final String ampm = h24 >= 12 ? 'م' : 'ص';
    return '${_two(h12)}:${_two(l.minute)} $ampm';
  }

  /// `11 أكتوبر 2026` — Arabic month name, Latin digits.
  ///
  /// Used where a "long" date is needed (statements, reports).
  static String longDate(DateTime value) {
    final DateTime l = value.toLocal();
    return '${l.day} ${_arabicMonth(l.month)} ${l.year}';
  }

  /// Short day label used in the receipts (`الأحد`).
  static String dayName(DateTime value) {
    final DateTime l = value.toLocal();
    return _arabicDays[(l.weekday - 1).clamp(0, 6)];
  }

  // ---------------------------------------------------------------------------
  // Relative time (`قبل 3 دقائق`)
  // ---------------------------------------------------------------------------

  static String relative(DateTime value) {
    final Duration diff = DateTime.now().difference(value);
    if (diff.inSeconds < 60) return 'قبل لحظات';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} ساعة';
    if (diff.inDays < 7) return 'قبل ${diff.inDays} يوم';
    return dateTime(value);
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static String _datePart(DateTime l) =>
      '${l.year.toString().padLeft(4, '0')}/'
      '${_two(l.month)}/${_two(l.day)}';

  static String _two(int n) => n.toString().padLeft(2, '0');

  static const List<String> _arabicDays = <String>[
    'الإثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];

  static const List<String> _arabicMonths = <String>[
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  static String _arabicMonth(int month) =>
      _arabicMonths[(month - 1).clamp(0, 11)];
}

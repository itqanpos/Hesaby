// lib/core/utils/formatters.dart
import 'package:intl/intl.dart';

import '../../app/config/app_constants.dart';

/// Locale-aware formatting helpers.
///
/// Date formatting requires `initializeDateFormatting`, which is performed
/// during [AppInitializer.initialize].
abstract final class Formatters {
  static String currency(num amount, {String? locale}) {
    return NumberFormat.currency(
      locale: locale ?? AppConstants.defaultLocaleTag,
      symbol: '${AppConstants.defaultCurrencySymbol} ',
      decimalDigits: 2,
    ).format(amount);
  }

  static String decimal(num value, {String? locale}) {
    return NumberFormat.decimalPattern(
      locale ?? AppConstants.defaultLocaleTag,
    ).format(value);
  }

  static String compactNumber(num value, {String? locale}) {
    return NumberFormat.compact(
      locale: locale ?? AppConstants.defaultLocaleTag,
    ).format(value);
  }

  static String shortDate(DateTime date, {String? locale}) {
    return DateFormat.yMd(
      locale ?? AppConstants.defaultLocaleTag,
    ).format(date);
  }

  static String shortTime(DateTime date, {String? locale}) {
    return DateFormat.Hm(locale ?? AppConstants.defaultLocaleTag).format(date);
  }

  static String shortDateTime(DateTime date, {String? locale}) {
    final String tag = locale ?? AppConstants.defaultLocaleTag;
    return DateFormat.yMd(tag).add_Hm().format(date);
  }
}

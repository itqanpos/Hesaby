// lib/app/config/app_constants.dart
/// Application-wide constant values.
abstract final class AppConstants {
  /// Latin application name, used for platform-level titles.
  static const String appName = 'Hesabi';

  /// Canonical locale tag used as the default for the application.
  static const String defaultLocaleTag = 'ar_EG';

  /// ISO 4217 code of the default currency.
  static const String defaultCurrencyCode = 'EGP';

  /// Display symbol of the default currency.
  static const String defaultCurrencySymbol = 'ج.م';

  /// Maximum width of centred page content.
  static const double contentMaxWidth = 1200;

  /// Upper bound (exclusive) of the mobile breakpoint.
  static const double breakpointMobile = 600;

  /// Upper bound (exclusive) of the tablet breakpoint.
  static const double breakpointTablet = 1024;

  /// Upper bound (exclusive) of the desktop breakpoint.
  static const double breakpointDesktop = 1440;
}

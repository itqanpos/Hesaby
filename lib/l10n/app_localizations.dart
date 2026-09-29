// lib/l10n/app_localizations.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

/// Localized strings used by the application.
///
/// A hand-written [LocalizationsDelegate] is used instead of generated ARB
/// code so that the foundation stays deterministic and code-generation free.
/// Adding a language is a matter of adding one subclass.
abstract class AppLocalizations {
  const AppLocalizations();

  /// Default locale of the application.
  static const Locale defaultLocale = Locale('ar', 'EG');

  /// Locales supported by the application, most preferred first.
  ///
  /// Because `ar_EG` is listed first, it is also the fallback locale used
  /// when the device locale is not supported.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar', 'EG'),
    Locale('en'),
  ];

  /// The delegate that resolves [AppLocalizations] for a [Locale].
  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// Returns the [AppLocalizations] instance of the current [context].
  static AppLocalizations of(BuildContext context) {
    final AppLocalizations? instance = Localizations.of<AppLocalizations>(
      context,
      AppLocalizations,
    );
    assert(
      instance != null,
      'AppLocalizations.of() was called with a context that does not contain '
      'an AppLocalizations delegate.',
    );
    return instance!;
  }

  String get appName;
  String get appTagline;

  String get homeTitle;
  String get homeSubtitle;
  String get homePhaseLabel;
  String get homeFoundationStatusTitle;
  String get homeStatusFlutter;
  String get homeStatusRouting;
  String get homeStatusTheme;
  String get homeStatusLocalization;
  String get homeStatusResponsive;
  String get homeStatusSupabase;
  String get homeStatusReady;
  String get homeStatusPending;
  String get homeEnvironmentLabel;
  String get homeEnvironmentDevelopment;
  String get homeEnvironmentStaging;
  String get homeEnvironmentProduction;

  String get errorTitle;
  String get errorRouteNotFound;
  String get actionGoHome;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
        (Locale supported) => supported.languageCode == locale.languageCode,
      );

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(_lookup(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations _lookup(Locale locale) => switch (locale.languageCode) {
      'ar' => const AppLocalizationsAr(),
      'en' => const AppLocalizationsEn(),
      _ => const AppLocalizationsAr(),
    };

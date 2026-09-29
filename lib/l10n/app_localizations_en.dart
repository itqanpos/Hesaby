// lib/l10n/app_localizations_en.dart
import 'app_localizations.dart';

/// English strings.
class AppLocalizationsEn extends AppLocalizations {
  const AppLocalizationsEn();

  @override
  String get appName => 'Hesabi';

  @override
  String get appTagline =>
      'An all-in-one platform for POS, inventory, sales and accounting';

  @override
  String get homeTitle => 'Welcome to Hesabi';

  @override
  String get homeSubtitle =>
      'This is the Phase 0 foundation build, used to verify that the project '
      'infrastructure works correctly.';

  @override
  String get homePhaseLabel => 'Phase 0 — Foundation';

  @override
  String get homeFoundationStatusTitle => 'Foundation status';

  @override
  String get homeStatusFlutter => 'Flutter framework';

  @override
  String get homeStatusRouting => 'Routing';

  @override
  String get homeStatusTheme => 'Theme';

  @override
  String get homeStatusLocalization => 'Localization';

  @override
  String get homeStatusResponsive => 'Responsive layout';

  @override
  String get homeStatusSupabase => 'Supabase connection';

  @override
  String get homeStatusReady => 'Ready';

  @override
  String get homeStatusPending => 'Not configured';

  @override
  String get homeEnvironmentLabel => 'Environment';

  @override
  String get homeEnvironmentDevelopment => 'Development';

  @override
  String get homeEnvironmentStaging => 'Staging';

  @override
  String get homeEnvironmentProduction => 'Production';

  @override
  String get errorTitle => 'Something went wrong';

  @override
  String get errorRouteNotFound => 'The requested page could not be found.';

  @override
  String get actionGoHome => 'Back to home';
}

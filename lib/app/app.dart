// lib/app/app.dart

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/preferences/app_preferences_providers.dart';
import '../l10n/app_localizations.dart';
import 'config/app_constants.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// Root widget of the HESABI application.
///
/// The theme mode and the preferred locale are read from local
/// preferences; both fall back to sensible defaults while the async
/// providers are still loading.
class HesabiApp extends ConsumerWidget {
  const HesabiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = ref.watch(appRouterProvider);

    final ThemeMode themeMode =
        ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system;
    final Locale? locale = ref.watch(localeProvider).valueOrNull;

    return MaterialApp.router(
      title: AppConstants.appName,
      onGenerateTitle: (BuildContext context) =>
          AppLocalizations.of(context).appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: locale,
      routerConfig: router,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

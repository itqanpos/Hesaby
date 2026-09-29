// lib/main.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap/app_initializer.dart';
import 'app/config/app_config.dart';

Future<void> main() async {
  final AppConfig config = AppConfig.fromEnvironment();

  await AppInitializer.initialize(config);

  runApp(
    ProviderScope(
      overrides: <Override>[appConfigProvider.overrideWithValue(config)],
      child: const HesabiApp(),
    ),
  );
}

// lib/features/admin/presentation/providers/admin_app_config_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/logger.dart';

class AppConfig {
  const AppConfig({
    required this.maintenanceMode,
    required this.maintenanceMessage,
    required this.announcementVisible,
    required this.announcementText,
    required this.announcementSeverity,
    required this.featureFlags,
  });

  final bool maintenanceMode;
  final String maintenanceMessage;
  final bool announcementVisible;
  final String announcementText;
  final String announcementSeverity; // 'info', 'warning', 'critical'
  final Map<String, dynamic> featureFlags;

  /// Safe defaults — used when the config cannot be fetched.
  /// Everything is off, no announcement, all features enabled.
  factory AppConfig.defaults() {
    return const AppConfig(
      maintenanceMode: false,
      maintenanceMessage: '',
      announcementVisible: false,
      announcementText: '',
      announcementSeverity: 'info',
      featureFlags: <String, dynamic>{},
    );
  }

  factory AppConfig.fromMap(Map<String, dynamic> map) {
    return AppConfig(
      maintenanceMode: map['maintenance_mode'] as bool? ?? false,
      maintenanceMessage: map['maintenance_message'] as String? ?? '',
      announcementVisible: map['announcement_visible'] as bool? ?? false,
      announcementText: map['announcement_text'] as String? ?? '',
      announcementSeverity: map['announcement_severity'] as String? ?? 'info',
      featureFlags: (map['feature_flags'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'maintenance_mode': maintenanceMode,
      'maintenance_message': maintenanceMessage,
      'announcement_visible': announcementVisible,
      'announcement_text': announcementText,
      'announcement_severity': announcementSeverity,
      'feature_flags': featureFlags,
    };
  }
}

class AppConfigNotifier extends AsyncNotifier<AppConfig> {
  @override
  Future<AppConfig> build() async {
    try {
      final client = Supabase.instance.client;
      final response = await client
          .from('app_config')
          .select()
          .eq('id', 'singleton')
          .single()
          .timeout(const Duration(seconds: 5));

      return AppConfig.fromMap(response);
    } on Object catch (error, stackTrace) {
      // Do not block the app if the config cannot be fetched.
      // Return safe defaults so the user can still use the app.
      AppLogger.warning(
        'Failed to load app_config (non-fatal). Using defaults.',
      );
      AppLogger.error('app_config load failed', error, stackTrace);
      return AppConfig.defaults();
    }
  }

  Future<void> save(AppConfig config) async {
    final client = Supabase.instance.client;
    await client
        .from('app_config')
        .update(config.toMap())
        .eq('id', 'singleton');

    // تحديث الحالة فوراً بعد الحفظ
    state = AsyncData<AppConfig>(config);
  }
}

final AsyncNotifierProvider<AppConfigNotifier, AppConfig>
    adminAppConfigProvider =
    AsyncNotifierProvider<AppConfigNotifier, AppConfig>(
  AppConfigNotifier.new,
);

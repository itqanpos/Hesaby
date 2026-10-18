// lib/features/admin/presentation/providers/admin_app_config_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    final client = Supabase.instance.client;
    final response = await client
        .from('app_config')
        .select()
        .eq('id', 'singleton')
        .single();
    return AppConfig.fromMap(response);
  }

  Future<void> save(AppConfig config) async {
    final client = Supabase.instance.client;
    await client
        .from('app_config')
        .update(config.toMap())
        .eq('id', 'singleton');
    
    // تحديث الحالة فوراً بعد الحفظ
    state = AsyncData(config);
  }
}

final adminAppConfigProvider =
    AsyncNotifierProvider<AppConfigNotifier, AppConfig>(
  AppConfigNotifier.new,
);

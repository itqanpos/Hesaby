// test/app_config_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/admin/presentation/providers/admin_app_config_provider.dart';

void main() {
  group('AppConfig', () {
    test('parses map correctly', () {
      final map = {
        'maintenance_mode': true,
        'maintenance_message': 'Down for maintenance',
        'announcement_visible': true,
        'announcement_text': 'New update!',
        'announcement_severity': 'warning',
        'feature_flags': {'pos': false, 'reports': true},
      };

      final config = AppConfig.fromMap(map);

      expect(config.maintenanceMode, isTrue);
      expect(config.announcementSeverity, 'warning');
      expect(config.featureFlags['pos'], isFalse);
      expect(config.featureFlags['reports'], isTrue);
    });

    test('defaults factory returns safe values', () {
      final config = AppConfig.defaults();
      
      expect(config.maintenanceMode, isFalse);
      expect(config.announcementVisible, isFalse);
      expect(config.featureFlags, isEmpty);
    });
  });
}

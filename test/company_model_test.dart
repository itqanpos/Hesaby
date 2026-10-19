// test/company_model_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/companies/data/models/company_model.dart';

void main() {
  group('CompanyModel', () {
    test('parses new suspension fields correctly', () {
      final map = {
        'id': 'c1',
        'name': 'Test Co',
        'currency': 'EGP',
        'timezone': 'Africa/Cairo',
        'is_active': true,
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
        'subscription_status': 'active',
        'is_suspended': true,
        'suspension_reason': 'Fraud',
        'max_users': 10,
        'max_branches': 3,
      };

      final model = CompanyModel.fromMap(map);
      final entity = model.toEntity();

      expect(entity.isSuspended, isTrue);
      expect(entity.suspensionReason, 'Fraud');
      expect(entity.maxUsers, 10);
      expect(entity.maxBranches, 3);
    });

    test('defaults missing new fields', () {
      final map = {
        'id': 'c1', 'name': 'Test Co', 'currency': 'EGP', 'timezone': 'Cairo',
        'is_active': true, 'created_at': '2026-01-01T00:00:00Z', 'updated_at': '2026-01-01T00:00:00Z',
        'subscription_status': 'trial',
      };

      final model = CompanyModel.fromMap(map);
      final entity = model.toEntity();

      expect(entity.isSuspended, isFalse);
      expect(entity.maxUsers, 5); // القيمة الافتراضية
      expect(entity.maxBranches, 1);
    });
  });
}

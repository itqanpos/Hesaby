// test/features/products/category_validation_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/products/data/models/category_model.dart';
import 'package:hesabi/features/products/domain/entities/category.dart';

void main() {
  group('CategoryModel.fromMap', () {
    test('parses a complete valid row', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'cat-1',
        'company_id': 'company-1',
        'name': 'مشروبات',
        'description': 'مشروبات باردة وساخنة',
        'sort_order': 5,
        'is_active': true,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:30:00.000Z',
      };

      final CategoryModel model = CategoryModel.fromMap(row);

      expect(model.id, 'cat-1');
      expect(model.companyId, 'company-1');
      expect(model.name, 'مشروبات');
      expect(model.description, 'مشروبات باردة وساخنة');
      expect(model.sortOrder, 5);
      expect(model.isActive, isTrue);
      expect(model.createdAt.isUtc, isTrue);
      expect(model.updatedAt.isUtc, isTrue);
    });

    test('parses a minimal valid row with optional fields absent', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'cat-2',
        'company_id': 'company-1',
        'name': 'أغذية',
        'sort_order': 0,
        'is_active': true,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      final CategoryModel model = CategoryModel.fromMap(row);

      expect(model.description, isNull);
      expect(model.sortOrder, 0);
    });

    test('treats an empty description as null', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'cat-3',
        'company_id': 'company-1',
        'name': 'تصنيف',
        'description': '   ',
        'sort_order': 0,
        'is_active': true,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      final CategoryModel model = CategoryModel.fromMap(row);

      expect(model.description, isNull);
    });

    test('defaults sortOrder to 0 when the column is absent', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'cat-4',
        'company_id': 'company-1',
        'name': 'بدون ترتيب',
        'is_active': true,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      final CategoryModel model = CategoryModel.fromMap(row);

      expect(model.sortOrder, 0);
    });

    test('coerces a numeric sort_order provided as a string', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'cat-5',
        'company_id': 'company-1',
        'name': 'مرتب',
        'sort_order': '10',
        'is_active': true,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      final CategoryModel model = CategoryModel.fromMap(row);

      expect(model.sortOrder, 10);
    });

    test('throws FormatException when a required string is missing', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': '',
        'company_id': 'company-1',
        'name': 'تصنيف',
        'sort_order': 0,
        'is_active': true,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      expect(
        () => CategoryModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when a timestamp is invalid', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'cat-6',
        'company_id': 'company-1',
        'name': 'تصنيف',
        'sort_order': 0,
        'is_active': true,
        'created_at': 'not-a-date',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      expect(
        () => CategoryModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('parses timestamps as UTC', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'cat-7',
        'company_id': 'company-1',
        'name': 'تصنيف',
        'sort_order': 0,
        'is_active': true,
        'created_at': '2026-10-02T12:00:00+02:00',
        'updated_at': '2026-10-02T12:00:00+02:00',
      };

      final CategoryModel model = CategoryModel.fromMap(row);

      expect(model.createdAt.isUtc, isTrue);
      expect(model.createdAt.toUtc(), DateTime.utc(2026, 10, 2, 10));
    });
  });

  group('CategoryModel.toEntity', () {
    test('produces a ProductCategory with identical field values', () {
      final CategoryModel model = CategoryModel.fromMap(<String, dynamic>{
        'id': 'cat-1',
        'company_id': 'company-1',
        'name': 'مشروبات',
        'description': 'وصف',
        'sort_order': 3,
        'is_active': true,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      });

      final ProductCategory entity = model.toEntity();

      expect(entity.id, model.id);
      expect(entity.companyId, model.companyId);
      expect(entity.name, model.name);
      expect(entity.description, model.description);
      expect(entity.sortOrder, model.sortOrder);
      expect(entity.isActive, model.isActive);
      expect(entity.createdAt, model.createdAt);
      expect(entity.updatedAt, model.updatedAt);
    });
  });

  group('ProductCategory equality', () {
    test('two entities with the same fields are equal', () {
      final DateTime timestamp = DateTime.utc(2026, 10, 2);

      final ProductCategory a = ProductCategory(
        id: 'cat-1',
        companyId: 'company-1',
        name: 'مشروبات',
        description: 'وصف',
        sortOrder: 3,
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final ProductCategory b = ProductCategory(
        id: 'cat-1',
        companyId: 'company-1',
        name: 'مشروبات',
        description: 'وصف',
        sortOrder: 3,
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('two entities differing in isActive are not equal', () {
      final DateTime timestamp = DateTime.utc(2026, 10, 2);

      final ProductCategory a = ProductCategory(
        id: 'cat-1',
        companyId: 'company-1',
        name: 'مشروبات',
        sortOrder: 0,
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final ProductCategory b = ProductCategory(
        id: 'cat-1',
        companyId: 'company-1',
        name: 'مشروبات',
        sortOrder: 0,
        isActive: false,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(a, isNot(equals(b)));
    });

    test('description difference is significant', () {
      final DateTime timestamp = DateTime.utc(2026, 10, 2);

      final ProductCategory a = ProductCategory(
        id: 'cat-1',
        companyId: 'company-1',
        name: 'مشروبات',
        description: 'أ',
        sortOrder: 0,
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final ProductCategory b = ProductCategory(
        id: 'cat-1',
        companyId: 'company-1',
        name: 'مشروبات',
        description: 'ب',
        sortOrder: 0,
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(a, isNot(equals(b)));
    });
  });
}

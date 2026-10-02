// test/features/products/unit_validation_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/products/data/models/unit_model.dart';
import 'package:hesabi/features/products/domain/entities/unit.dart';

void main() {
  group('UnitModel.fromMap', () {
    test('parses a complete valid row', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'unit-1',
        'company_id': 'company-1',
        'name': 'كيلو',
        'symbol': 'kg',
        'is_active': true,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:30:00.000Z',
      };

      final UnitModel model = UnitModel.fromMap(row);

      expect(model.id, 'unit-1');
      expect(model.companyId, 'company-1');
      expect(model.name, 'كيلو');
      expect(model.symbol, 'kg');
      expect(model.isActive, isTrue);
      expect(model.createdAt.isUtc, isTrue);
    });

    test('parses a minimal valid row without symbol', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'unit-2',
        'company_id': 'company-1',
        'name': 'قطعة',
        'is_active': true,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      final UnitModel model = UnitModel.fromMap(row);

      expect(model.symbol, isNull);
    });

    test('treats an empty or whitespace symbol as null', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'unit-3',
        'company_id': 'company-1',
        'name': 'لتر',
        'symbol': '   ',
        'is_active': true,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      final UnitModel model = UnitModel.fromMap(row);

      expect(model.symbol, isNull);
    });

    test('trims surrounding whitespace from symbol', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'unit-4',
        'company_id': 'company-1',
        'name': 'لتر',
        'symbol': '  L  ',
        'is_active': true,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      final UnitModel model = UnitModel.fromMap(row);

      expect(model.symbol, 'L');
    });

    test('defaults isActive to true when the column is absent', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'unit-5',
        'company_id': 'company-1',
        'name': 'كرتونة',
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      final UnitModel model = UnitModel.fromMap(row);

      expect(model.isActive, isTrue);
    });

    test('coerces is_active provided as a string', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'unit-6',
        'company_id': 'company-1',
        'name': 'متر',
        'is_active': 'false',
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      final UnitModel model = UnitModel.fromMap(row);

      expect(model.isActive, isFalse);
    });

    test('throws FormatException when a required string is missing', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'unit-7',
        'company_id': '',
        'name': 'قطعة',
        'is_active': true,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      expect(
        () => UnitModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when a timestamp is invalid', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'unit-8',
        'company_id': 'company-1',
        'name': 'قطعة',
        'is_active': true,
        'created_at': 'not-a-date',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      expect(
        () => UnitModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('parses timestamps as UTC', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'unit-9',
        'company_id': 'company-1',
        'name': 'قطعة',
        'is_active': true,
        'created_at': '2026-10-02T12:00:00+02:00',
        'updated_at': '2026-10-02T12:00:00+02:00',
      };

      final UnitModel model = UnitModel.fromMap(row);

      expect(model.createdAt.isUtc, isTrue);
      expect(model.createdAt.toUtc(), DateTime.utc(2026, 10, 2, 10));
    });
  });

  group('UnitModel.toEntity', () {
    test('produces a Unit with identical field values', () {
      final UnitModel model = UnitModel.fromMap(<String, dynamic>{
        'id': 'unit-1',
        'company_id': 'company-1',
        'name': 'كيلو',
        'symbol': 'kg',
        'is_active': true,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      });

      final Unit entity = model.toEntity();

      expect(entity.id, model.id);
      expect(entity.companyId, model.companyId);
      expect(entity.name, model.name);
      expect(entity.symbol, model.symbol);
      expect(entity.isActive, model.isActive);
      expect(entity.createdAt, model.createdAt);
      expect(entity.updatedAt, model.updatedAt);
    });
  });

  group('Unit equality', () {
    test('two entities with the same fields are equal', () {
      final DateTime timestamp = DateTime.utc(2026, 10, 2);

      final Unit a = Unit(
        id: 'unit-1',
        companyId: 'company-1',
        name: 'كيلو',
        symbol: 'kg',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Unit b = Unit(
        id: 'unit-1',
        companyId: 'company-1',
        name: 'كيلو',
        symbol: 'kg',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('two entities differing in symbol are not equal', () {
      final DateTime timestamp = DateTime.utc(2026, 10, 2);

      final Unit a = Unit(
        id: 'unit-1',
        companyId: 'company-1',
        name: 'كيلو',
        symbol: 'kg',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Unit b = Unit(
        id: 'unit-1',
        companyId: 'company-1',
        name: 'كيلو',
        symbol: 'KG',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(a, isNot(equals(b)));
    });

    test('null symbol differs from empty string symbol', () {
      final DateTime timestamp = DateTime.utc(2026, 10, 2);

      final Unit a = Unit(
        id: 'unit-1',
        companyId: 'company-1',
        name: 'قطعة',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Unit b = Unit(
        id: 'unit-1',
        companyId: 'company-1',
        name: 'قطعة',
        symbol: '',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(a, isNot(equals(b)));
    });

    test('isActive difference is significant', () {
      final DateTime timestamp = DateTime.utc(2026, 10, 2);

      final Unit a = Unit(
        id: 'unit-1',
        companyId: 'company-1',
        name: 'قطعة',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Unit b = Unit(
        id: 'unit-1',
        companyId: 'company-1',
        name: 'قطعة',
        isActive: false,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(a, isNot(equals(b)));
    });
  });
}

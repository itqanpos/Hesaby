// test/features/suppliers/supplier_model_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/suppliers/data/models/supplier_model.dart';
import 'package:hesabi/features/suppliers/domain/entities/supplier.dart';

void main() {
  // ---------------------------------------------------------------------------
  // SupplierModel.fromMap
  // ---------------------------------------------------------------------------

  group('SupplierModel.fromMap', () {
    test('parses a complete valid row', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'sup-1',
        'company_id': 'company-1',
        'name': 'شركة الأمل للتوريدات',
        'code': 'SUP-001',
        'phone': '01012345678',
        'email': 'sales@amal.example',
        'address': 'القاهرة - مدينة نصر',
        'notes': 'مورد معتمد',
        'is_active': true,
        'created_at': '2026-10-03T12:00:00.000Z',
        'updated_at': '2026-10-03T12:30:00.000Z',
      };

      final SupplierModel model = SupplierModel.fromMap(row);

      expect(model.id, 'sup-1');
      expect(model.companyId, 'company-1');
      expect(model.name, 'شركة الأمل للتوريدات');
      expect(model.code, 'SUP-001');
      expect(model.phone, '01012345678');
      expect(model.email, 'sales@amal.example');
      expect(model.address, 'القاهرة - مدينة نصر');
      expect(model.notes, 'مورد معتمد');
      expect(model.isActive, isTrue);
      expect(model.createdAt.isUtc, isTrue);
      expect(model.updatedAt.isUtc, isTrue);
    });

    test('parses a minimal valid row without optional fields', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'sup-2',
        'company_id': 'company-1',
        'name': 'مورد بسيط',
        'is_active': true,
        'created_at': '2026-10-03T12:00:00.000Z',
        'updated_at': '2026-10-03T12:00:00.000Z',
      };

      final SupplierModel model = SupplierModel.fromMap(row);

      expect(model.code, isNull);
      expect(model.phone, isNull);
      expect(model.email, isNull);
      expect(model.address, isNull);
      expect(model.notes, isNull);
    });

    test('treats empty or whitespace optional strings as null', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'sup-3',
        'company_id': 'company-1',
        'name': 'مورد',
        'code': '',
        'phone': '   ',
        'email': '',
        'address': '   ',
        'notes': '',
        'is_active': true,
        'created_at': '2026-10-03T12:00:00.000Z',
        'updated_at': '2026-10-03T12:00:00.000Z',
      };

      final SupplierModel model = SupplierModel.fromMap(row);

      expect(model.code, isNull);
      expect(model.phone, isNull);
      expect(model.email, isNull);
      expect(model.address, isNull);
      expect(model.notes, isNull);
    });

    test('trims surrounding whitespace from optional strings', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'sup-4',
        'company_id': 'company-1',
        'name': 'مورد',
        'code': '  SUP-002  ',
        'phone': '  01012345678  ',
        'email': '  sales@x.example  ',
        'is_active': true,
        'created_at': '2026-10-03T12:00:00.000Z',
        'updated_at': '2026-10-03T12:00:00.000Z',
      };

      final SupplierModel model = SupplierModel.fromMap(row);

      expect(model.code, 'SUP-002');
      expect(model.phone, '01012345678');
      expect(model.email, 'sales@x.example');
    });

    test('defaults isActive to true when the column is absent', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'sup-5',
        'company_id': 'company-1',
        'name': 'مورد',
        'created_at': '2026-10-03T12:00:00.000Z',
        'updated_at': '2026-10-03T12:00:00.000Z',
      };

      final SupplierModel model = SupplierModel.fromMap(row);

      expect(model.isActive, isTrue);
    });

    test('coerces is_active provided as a string', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'sup-6',
        'company_id': 'company-1',
        'name': 'مورد',
        'is_active': 'false',
        'created_at': '2026-10-03T12:00:00.000Z',
        'updated_at': '2026-10-03T12:00:00.000Z',
      };

      final SupplierModel model = SupplierModel.fromMap(row);

      expect(model.isActive, isFalse);
    });

    test('throws FormatException when id is empty', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': '',
        'company_id': 'company-1',
        'name': 'مورد',
        'is_active': true,
        'created_at': '2026-10-03T12:00:00.000Z',
        'updated_at': '2026-10-03T12:00:00.000Z',
      };

      expect(
        () => SupplierModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when name is missing', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'sup-7',
        'company_id': 'company-1',
        'is_active': true,
        'created_at': '2026-10-03T12:00:00.000Z',
        'updated_at': '2026-10-03T12:00:00.000Z',
      };

      expect(
        () => SupplierModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when a timestamp is invalid', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'sup-8',
        'company_id': 'company-1',
        'name': 'مورد',
        'is_active': true,
        'created_at': 'not-a-date',
        'updated_at': '2026-10-03T12:00:00.000Z',
      };

      expect(
        () => SupplierModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('parses timestamps as UTC', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'sup-9',
        'company_id': 'company-1',
        'name': 'مورد',
        'is_active': true,
        'created_at': '2026-10-03T12:00:00+02:00',
        'updated_at': '2026-10-03T12:00:00+02:00',
      };

      final SupplierModel model = SupplierModel.fromMap(row);

      expect(model.createdAt.isUtc, isTrue);
      expect(model.createdAt.toUtc(), DateTime.utc(2026, 10, 3, 10));
    });
  });

  // ---------------------------------------------------------------------------
  // SupplierModel.toEntity
  // ---------------------------------------------------------------------------

  group('SupplierModel.toEntity', () {
    test('produces a Supplier with identical field values', () {
      final SupplierModel model = SupplierModel.fromMap(<String, dynamic>{
        'id': 'sup-1',
        'company_id': 'company-1',
        'name': 'شركة الأمل',
        'code': 'SUP-001',
        'phone': '01012345678',
        'email': 'sales@amal.example',
        'address': 'القاهرة',
        'notes': 'مورد معتمد',
        'is_active': true,
        'created_at': '2026-10-03T12:00:00.000Z',
        'updated_at': '2026-10-03T12:00:00.000Z',
      });

      final Supplier entity = model.toEntity();

      expect(entity.id, model.id);
      expect(entity.companyId, model.companyId);
      expect(entity.name, model.name);
      expect(entity.code, model.code);
      expect(entity.phone, model.phone);
      expect(entity.email, model.email);
      expect(entity.address, model.address);
      expect(entity.notes, model.notes);
      expect(entity.isActive, model.isActive);
      expect(entity.createdAt, model.createdAt);
      expect(entity.updatedAt, model.updatedAt);
    });
  });

  // ---------------------------------------------------------------------------
  // Supplier getters
  // ---------------------------------------------------------------------------

  group('Supplier getters', () {
    final DateTime timestamp = DateTime.utc(2026, 10, 3);

    test('hasCode is true only when code is non-null and non-blank', () {
      final Supplier withCode = Supplier(
        id: 's',
        companyId: 'c',
        name: 'n',
        code: 'SUP-001',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Supplier withBlankCode = Supplier(
        id: 's',
        companyId: 'c',
        name: 'n',
        code: '   ',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Supplier withoutCode = Supplier(
        id: 's',
        companyId: 'c',
        name: 'n',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(withCode.hasCode, isTrue);
      expect(withBlankCode.hasCode, isFalse);
      expect(withoutCode.hasCode, isFalse);
    });

    test('hasPhone is true only when phone is non-null and non-blank', () {
      final Supplier withPhone = Supplier(
        id: 's',
        companyId: 'c',
        name: 'n',
        phone: '01012345678',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Supplier withBlankPhone = Supplier(
        id: 's',
        companyId: 'c',
        name: 'n',
        phone: '   ',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(withPhone.hasPhone, isTrue);
      expect(withBlankPhone.hasPhone, isFalse);
    });

    test('hasEmail is true only when email is non-null and non-blank', () {
      final Supplier withEmail = Supplier(
        id: 's',
        companyId: 'c',
        name: 'n',
        email: 'x@y.example',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Supplier withBlankEmail = Supplier(
        id: 's',
        companyId: 'c',
        name: 'n',
        email: '   ',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(withEmail.hasEmail, isTrue);
      expect(withBlankEmail.hasEmail, isFalse);
    });

    test('hasAddress is true only when address is non-null and non-blank', () {
      final Supplier withAddress = Supplier(
        id: 's',
        companyId: 'c',
        name: 'n',
        address: 'القاهرة',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Supplier withBlankAddress = Supplier(
        id: 's',
        companyId: 'c',
        name: 'n',
        address: '   ',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(withAddress.hasAddress, isTrue);
      expect(withBlankAddress.hasAddress, isFalse);
    });

    test('hasNotes is true only when notes is non-null and non-blank', () {
      final Supplier withNotes = Supplier(
        id: 's',
        companyId: 'c',
        name: 'n',
        notes: 'ملاحظة',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Supplier withBlankNotes = Supplier(
        id: 's',
        companyId: 'c',
        name: 'n',
        notes: '   ',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(withNotes.hasNotes, isTrue);
      expect(withBlankNotes.hasNotes, isFalse);
    });

    test('hasContactInfo is true when phone or email is present', () {
      final Supplier onlyPhone = Supplier(
        id: 's',
        companyId: 'c',
        name: 'n',
        phone: '010',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Supplier onlyEmail = Supplier(
        id: 's',
        companyId: 'c',
        name: 'n',
        email: 'x@y.example',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Supplier neither = Supplier(
        id: 's',
        companyId: 'c',
        name: 'n',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(onlyPhone.hasContactInfo, isTrue);
      expect(onlyEmail.hasContactInfo, isTrue);
      expect(neither.hasContactInfo, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Supplier equality
  // ---------------------------------------------------------------------------

  group('Supplier equality', () {
    final DateTime timestamp = DateTime.utc(2026, 10, 3);

    test('two entities with the same fields are equal', () {
      final Supplier a = Supplier(
        id: 's',
        companyId: 'c',
        name: 'مورد',
        code: 'SUP-001',
        phone: '010',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Supplier b = Supplier(
        id: 's',
        companyId: 'c',
        name: 'مورد',
        code: 'SUP-001',
        phone: '010',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('name difference is significant', () {
      final Supplier a = Supplier(
        id: 's',
        companyId: 'c',
        name: 'مورد أ',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Supplier b = Supplier(
        id: 's',
        companyId: 'c',
        name: 'مورد ب',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(a, isNot(equals(b)));
    });

    test('isActive difference is significant', () {
      final Supplier a = Supplier(
        id: 's',
        companyId: 'c',
        name: 'مورد',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Supplier b = Supplier(
        id: 's',
        companyId: 'c',
        name: 'مورد',
        isActive: false,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(a, isNot(equals(b)));
    });

    test('null code differs from empty string code', () {
      final Supplier a = Supplier(
        id: 's',
        companyId: 'c',
        name: 'مورد',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Supplier b = Supplier(
        id: 's',
        companyId: 'c',
        name: 'مورد',
        code: '',
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(a, isNot(equals(b)));
    });
  });
}

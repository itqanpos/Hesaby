// test/features/purchases/purchase_item_model_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/purchases/data/models/purchase_item_model.dart';
import 'package:hesabi/features/purchases/domain/entities/purchase_item.dart';

void main() {
  // ---------------------------------------------------------------------------
  // PurchaseItemModel.fromMap
  // ---------------------------------------------------------------------------

  group('PurchaseItemModel.fromMap', () {
    test('parses a complete valid row', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pit-1',
        'company_id': 'company-1',
        'purchase_id': 'pur-1',
        'product_id': 'prod-1',
        'unit_id': 'unit-1',
        'quantity': '24.0000',
        'unit_cost': '8.5000',
        'line_total': '204.0000',
        'notes': 'بند أول',
        'created_at': '2026-10-03T10:00:00.000Z',
        'updated_at': '2026-10-03T10:00:00.000Z',
      };

      final PurchaseItemModel model = PurchaseItemModel.fromMap(row);

      expect(model.id, 'pit-1');
      expect(model.companyId, 'company-1');
      expect(model.purchaseId, 'pur-1');
      expect(model.productId, 'prod-1');
      expect(model.unitId, 'unit-1');
      expect(model.quantity, 24.0);
      expect(model.unitCost, 8.5);
      expect(model.lineTotal, 204.0);
      expect(model.notes, 'بند أول');
      expect(model.createdAt.isUtc, isTrue);
      expect(model.updatedAt.isUtc, isTrue);
    });

    test('parses a minimal row without notes', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pit-2',
        'company_id': 'company-1',
        'purchase_id': 'pur-1',
        'product_id': 'prod-1',
        'unit_id': 'unit-1',
        'quantity': 1,
        'unit_cost': 0,
        'line_total': 0,
        'created_at': '2026-10-03T10:00:00.000Z',
        'updated_at': '2026-10-03T10:00:00.000Z',
      };

      final PurchaseItemModel model = PurchaseItemModel.fromMap(row);

      expect(model.notes, isNull);
      expect(model.quantity, 1.0);
      expect(model.unitCost, 0);
      expect(model.lineTotal, 0);
    });

    test('parses numeric columns delivered as numeric strings (PostgREST)',
        () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pit-3',
        'company_id': 'company-1',
        'purchase_id': 'pur-1',
        'product_id': 'prod-1',
        'unit_id': 'unit-1',
        'quantity': '0.333333',
        'unit_cost': '12.7500',
        'line_total': '4.250000',
        'created_at': '2026-10-03T10:00:00.000Z',
        'updated_at': '2026-10-03T10:00:00.000Z',
      };

      final PurchaseItemModel model = PurchaseItemModel.fromMap(row);

      expect(model.quantity, closeTo(0.333333, 0.000001));
      expect(model.unitCost, 12.75);
      expect(model.lineTotal, closeTo(4.25, 0.0001));
    });

    test('trims surrounding whitespace from notes', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pit-4',
        'company_id': 'company-1',
        'purchase_id': 'pur-1',
        'product_id': 'prod-1',
        'unit_id': 'unit-1',
        'quantity': 1,
        'unit_cost': 0,
        'line_total': 0,
        'notes': '  ملاحظة مهمة  ',
        'created_at': '2026-10-03T10:00:00.000Z',
        'updated_at': '2026-10-03T10:00:00.000Z',
      };

      final PurchaseItemModel model = PurchaseItemModel.fromMap(row);

      expect(model.notes, 'ملاحظة مهمة');
    });

    test('treats whitespace-only notes as null', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pit-5',
        'company_id': 'company-1',
        'purchase_id': 'pur-1',
        'product_id': 'prod-1',
        'unit_id': 'unit-1',
        'quantity': 1,
        'unit_cost': 0,
        'line_total': 0,
        'notes': '   ',
        'created_at': '2026-10-03T10:00:00.000Z',
        'updated_at': '2026-10-03T10:00:00.000Z',
      };

      final PurchaseItemModel model = PurchaseItemModel.fromMap(row);

      expect(model.notes, isNull);
    });

    test('throws FormatException when id is empty', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': '',
        'company_id': 'company-1',
        'purchase_id': 'pur-1',
        'product_id': 'prod-1',
        'unit_id': 'unit-1',
        'quantity': 1,
        'unit_cost': 0,
        'line_total': 0,
        'created_at': '2026-10-03T10:00:00.000Z',
        'updated_at': '2026-10-03T10:00:00.000Z',
      };

      expect(
        () => PurchaseItemModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when purchase_id is empty', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pit-6',
        'company_id': 'company-1',
        'purchase_id': '',
        'product_id': 'prod-1',
        'unit_id': 'unit-1',
        'quantity': 1,
        'unit_cost': 0,
        'line_total': 0,
        'created_at': '2026-10-03T10:00:00.000Z',
        'updated_at': '2026-10-03T10:00:00.000Z',
      };

      expect(
        () => PurchaseItemModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when quantity is missing', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pit-7',
        'company_id': 'company-1',
        'purchase_id': 'pur-1',
        'product_id': 'prod-1',
        'unit_id': 'unit-1',
        'unit_cost': 0,
        'line_total': 0,
        'created_at': '2026-10-03T10:00:00.000Z',
        'updated_at': '2026-10-03T10:00:00.000Z',
      };

      expect(
        () => PurchaseItemModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when quantity is not numeric', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pit-8',
        'company_id': 'company-1',
        'purchase_id': 'pur-1',
        'product_id': 'prod-1',
        'unit_id': 'unit-1',
        'quantity': 'abc',
        'unit_cost': 0,
        'line_total': 0,
        'created_at': '2026-10-03T10:00:00.000Z',
        'updated_at': '2026-10-03T10:00:00.000Z',
      };

      expect(
        () => PurchaseItemModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when a timestamp is invalid', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pit-9',
        'company_id': 'company-1',
        'purchase_id': 'pur-1',
        'product_id': 'prod-1',
        'unit_id': 'unit-1',
        'quantity': 1,
        'unit_cost': 0,
        'line_total': 0,
        'created_at': 'not-a-date',
        'updated_at': '2026-10-03T10:00:00.000Z',
      };

      expect(
        () => PurchaseItemModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('parses timestamps as UTC', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pit-10',
        'company_id': 'company-1',
        'purchase_id': 'pur-1',
        'product_id': 'prod-1',
        'unit_id': 'unit-1',
        'quantity': 1,
        'unit_cost': 0,
        'line_total': 0,
        'created_at': '2026-10-03T12:00:00+02:00',
        'updated_at': '2026-10-03T12:00:00+02:00',
      };

      final PurchaseItemModel model = PurchaseItemModel.fromMap(row);

      expect(model.createdAt.isUtc, isTrue);
      expect(model.createdAt.toUtc(), DateTime.utc(2026, 10, 3, 10));
    });
  });

  // ---------------------------------------------------------------------------
  // PurchaseItemModel.toEntity
  // ---------------------------------------------------------------------------

  group('PurchaseItemModel.toEntity', () {
    test('produces a PurchaseItem with identical field values', () {
      final PurchaseItemModel model =
          PurchaseItemModel.fromMap(<String, dynamic>{
        'id': 'pit-1',
        'company_id': 'company-1',
        'purchase_id': 'pur-1',
        'product_id': 'prod-1',
        'unit_id': 'unit-1',
        'quantity': '24.0',
        'unit_cost': '8.5',
        'line_total': '204.0',
        'notes': 'بند',
        'created_at': '2026-10-03T10:00:00.000Z',
        'updated_at': '2026-10-03T10:00:00.000Z',
      });

      final PurchaseItem entity = model.toEntity();

      expect(entity.id, model.id);
      expect(entity.companyId, model.companyId);
      expect(entity.purchaseId, model.purchaseId);
      expect(entity.productId, model.productId);
      expect(entity.unitId, model.unitId);
      expect(entity.quantity, model.quantity);
      expect(entity.unitCost, model.unitCost);
      expect(entity.lineTotal, model.lineTotal);
      expect(entity.notes, model.notes);
      expect(entity.createdAt, model.createdAt);
      expect(entity.updatedAt, model.updatedAt);
    });
  });

  // ---------------------------------------------------------------------------
  // PurchaseItem getters
  // ---------------------------------------------------------------------------

  group('PurchaseItem getters', () {
    final DateTime timestamp = DateTime.utc(2026, 10, 3);

    PurchaseItem build({String? notes, double lineTotal = 204}) => PurchaseItem(
          id: 'pit',
          companyId: 'c',
          purchaseId: 'p',
          productId: 'prod',
          unitId: 'u',
          quantity: 24,
          unitCost: 8.5,
          lineTotal: lineTotal,
          notes: notes,
          createdAt: timestamp,
          updatedAt: timestamp,
        );

    test('hasNotes treats null and blank as absent', () {
      expect(build().hasNotes, isFalse);
      expect(build(notes: '   ').hasNotes, isFalse);
      expect(build(notes: 'ملاحظة').hasNotes, isTrue);
    });

    test('value is an alias for lineTotal', () {
      final PurchaseItem item = build(lineTotal: 204);
      expect(item.value, 204);
      expect(item.value, item.lineTotal);
    });
  });

  // ---------------------------------------------------------------------------
  // PurchaseItem equality
  // ---------------------------------------------------------------------------

  group('PurchaseItem equality', () {
    final DateTime timestamp = DateTime.utc(2026, 10, 3);

    PurchaseItem build({
      double quantity = 24,
      double unitCost = 8.5,
      double lineTotal = 204,
    }) =>
        PurchaseItem(
          id: 'pit',
          companyId: 'c',
          purchaseId: 'p',
          productId: 'prod',
          unitId: 'u',
          quantity: quantity,
          unitCost: unitCost,
          lineTotal: lineTotal,
          createdAt: timestamp,
          updatedAt: timestamp,
        );

    test('two entities with the same fields are equal', () {
      final PurchaseItem a = build();
      final PurchaseItem b = build();

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('quantity difference is significant', () {
      expect(build(quantity: 24), isNot(equals(build(quantity: 25))));
    });

    test('unitCost difference is significant', () {
      expect(build(unitCost: 8.5), isNot(equals(build(unitCost: 9.0))));
    });

    test('lineTotal difference is significant', () {
      expect(build(lineTotal: 204), isNot(equals(build(lineTotal: 205))));
    });
  });
}

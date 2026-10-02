// test/features/inventory/inventory_balance_model_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/inventory/data/models/inventory_balance_model.dart';
import 'package:hesabi/features/inventory/domain/entities/inventory_balance.dart';

void main() {
  // ---------------------------------------------------------------------------
  // InventoryBalanceModel.fromMap
  // ---------------------------------------------------------------------------

  group('InventoryBalanceModel.fromMap', () {
    test('parses a complete valid row', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'bal-1',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'product_id': 'prod-1',
        'quantity_on_hand': 24.5,
        'average_cost': 8.75,
        'last_movement_at': '2026-10-02T12:30:00.000Z',
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:30:00.000Z',
      };

      final InventoryBalanceModel model =
          InventoryBalanceModel.fromMap(row);

      expect(model.id, 'bal-1');
      expect(model.companyId, 'company-1');
      expect(model.branchId, 'branch-1');
      expect(model.productId, 'prod-1');
      expect(model.quantityOnHand, 24.5);
      expect(model.averageCost, 8.75);
      expect(model.lastMovementAt, isNotNull);
      expect(model.lastMovementAt!.isUtc, isTrue);
      expect(model.createdAt.isUtc, isTrue);
      expect(model.updatedAt.isUtc, isTrue);
    });

    test('parses quantities delivered as numeric strings (PostgREST)', () {
      // PostgREST returns `numeric` columns as strings to preserve precision.
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'bal-2',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'product_id': 'prod-1',
        'quantity_on_hand': '100.0000',
        'average_cost': '12.5000',
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      final InventoryBalanceModel model =
          InventoryBalanceModel.fromMap(row);

      expect(model.quantityOnHand, 100.0);
      expect(model.averageCost, 12.5);
    });

    test('parses integer quantities without loss', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'bal-3',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'product_id': 'prod-1',
        'quantity_on_hand': 24,
        'average_cost': 8,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      final InventoryBalanceModel model =
          InventoryBalanceModel.fromMap(row);

      expect(model.quantityOnHand, 24.0);
      expect(model.averageCost, 8.0);
    });

    test('lastMovementAt is null when the column is absent', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'bal-4',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'product_id': 'prod-1',
        'quantity_on_hand': 0,
        'average_cost': 0,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      final InventoryBalanceModel model =
          InventoryBalanceModel.fromMap(row);

      expect(model.lastMovementAt, isNull);
    });

    test('lastMovementAt is null when the column is explicitly null', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'bal-5',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'product_id': 'prod-1',
        'quantity_on_hand': 0,
        'average_cost': 0,
        'last_movement_at': null,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      final InventoryBalanceModel model =
          InventoryBalanceModel.fromMap(row);

      expect(model.lastMovementAt, isNull);
    });

    test('lastMovementAt tolerates an unparseable string', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'bal-6',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'product_id': 'prod-1',
        'quantity_on_hand': 10,
        'average_cost': 5,
        'last_movement_at': 'not-a-date',
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      final InventoryBalanceModel model =
          InventoryBalanceModel.fromMap(row);

      expect(model.lastMovementAt, isNull);
    });

    test('throws FormatException when a required id is empty', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': '',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'product_id': 'prod-1',
        'quantity_on_hand': 0,
        'average_cost': 0,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      expect(
        () => InventoryBalanceModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when quantity_on_hand is missing', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'bal-7',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'product_id': 'prod-1',
        'average_cost': 0,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      expect(
        () => InventoryBalanceModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when a timestamp is invalid', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'bal-8',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'product_id': 'prod-1',
        'quantity_on_hand': 0,
        'average_cost': 0,
        'created_at': 'not-a-date',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      expect(
        () => InventoryBalanceModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('parses timestamps as UTC', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'bal-9',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'product_id': 'prod-1',
        'quantity_on_hand': 0,
        'average_cost': 0,
        'created_at': '2026-10-02T12:00:00+02:00',
        'updated_at': '2026-10-02T12:00:00+02:00',
      };

      final InventoryBalanceModel model =
          InventoryBalanceModel.fromMap(row);

      expect(model.createdAt.isUtc, isTrue);
      expect(model.createdAt.toUtc(), DateTime.utc(2026, 10, 2, 10));
    });
  });

  // ---------------------------------------------------------------------------
  // InventoryBalanceModel.toEntity
  // ---------------------------------------------------------------------------

  group('InventoryBalanceModel.toEntity', () {
    test('produces an InventoryBalance with identical field values', () {
      final InventoryBalanceModel model =
          InventoryBalanceModel.fromMap(<String, dynamic>{
        'id': 'bal-1',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'product_id': 'prod-1',
        'quantity_on_hand': 24.5,
        'average_cost': 8.75,
        'last_movement_at': '2026-10-02T12:30:00.000Z',
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:30:00.000Z',
      });

      final InventoryBalance entity = model.toEntity();

      expect(entity.id, model.id);
      expect(entity.companyId, model.companyId);
      expect(entity.branchId, model.branchId);
      expect(entity.productId, model.productId);
      expect(entity.quantityOnHand, model.quantityOnHand);
      expect(entity.averageCost, model.averageCost);
      expect(entity.lastMovementAt, model.lastMovementAt);
      expect(entity.createdAt, model.createdAt);
      expect(entity.updatedAt, model.updatedAt);
    });
  });

  // ---------------------------------------------------------------------------
  // InventoryBalance getters
  // ---------------------------------------------------------------------------

  group('InventoryBalance getters', () {
    final DateTime timestamp = DateTime.utc(2026, 10, 2);

    test('isOutOfStock is true when quantity is zero or negative', () {
      final InventoryBalance zeroBalance = InventoryBalance(
        id: 'b',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        quantityOnHand: 0,
        averageCost: 0,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final InventoryBalance inStock = InventoryBalance(
        id: 'b',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        quantityOnHand: 10,
        averageCost: 5,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(zeroBalance.isOutOfStock, isTrue);
      expect(inStock.isOutOfStock, isFalse);
    });

    test('totalValue = quantity * averageCost', () {
      final InventoryBalance balance = InventoryBalance(
        id: 'b',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        quantityOnHand: 24,
        averageCost: 8.5,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(balance.totalValue, closeTo(204.0, 0.0001));
    });

    test('totalValue is zero when quantity is zero', () {
      final InventoryBalance balance = InventoryBalance(
        id: 'b',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        quantityOnHand: 0,
        averageCost: 8.5,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(balance.totalValue, 0);
    });

    test('hasNoMovementYet reflects lastMovementAt nullness', () {
      final InventoryBalance fresh = InventoryBalance(
        id: 'b',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        quantityOnHand: 0,
        averageCost: 0,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final InventoryBalance touched = InventoryBalance(
        id: 'b',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        quantityOnHand: 10,
        averageCost: 5,
        lastMovementAt: timestamp,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(fresh.hasNoMovementYet, isTrue);
      expect(touched.hasNoMovementYet, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // InventoryBalance equality
  // ---------------------------------------------------------------------------

  group('InventoryBalance equality', () {
    final DateTime timestamp = DateTime.utc(2026, 10, 2);

    test('two entities with the same fields are equal', () {
      final InventoryBalance a = InventoryBalance(
        id: 'b',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        quantityOnHand: 24,
        averageCost: 8.5,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final InventoryBalance b = InventoryBalance(
        id: 'b',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        quantityOnHand: 24,
        averageCost: 8.5,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('quantity difference is significant', () {
      final InventoryBalance a = InventoryBalance(
        id: 'b',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        quantityOnHand: 24,
        averageCost: 8.5,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final InventoryBalance b = InventoryBalance(
        id: 'b',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        quantityOnHand: 25,
        averageCost: 8.5,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(a, isNot(equals(b)));
    });

    test('lastMovementAt difference is significant', () {
      final InventoryBalance a = InventoryBalance(
        id: 'b',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        quantityOnHand: 24,
        averageCost: 8.5,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final InventoryBalance b = InventoryBalance(
        id: 'b',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        quantityOnHand: 24,
        averageCost: 8.5,
        lastMovementAt: timestamp,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(a, isNot(equals(b)));
    });
  });
}

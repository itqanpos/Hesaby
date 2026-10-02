// test/features/inventory/stock_movement_model_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/inventory/data/models/stock_movement_model.dart';
import 'package:hesabi/features/inventory/domain/entities/stock_movement.dart';

void main() {
  // ---------------------------------------------------------------------------
  // StockMovementType constants
  // ---------------------------------------------------------------------------

  group('StockMovementType', () {
    test('declares the nine movement types accepted by the DB constraint', () {
      expect(StockMovementType.all.length, 9);
      expect(StockMovementType.all, contains(StockMovementType.adjustmentIn));
      expect(StockMovementType.all, contains(StockMovementType.adjustmentOut));
      expect(StockMovementType.all, contains(StockMovementType.purchaseIn));
      expect(StockMovementType.all, contains(StockMovementType.saleOut));
      expect(StockMovementType.all, contains(StockMovementType.transferIn));
      expect(StockMovementType.all, contains(StockMovementType.transferOut));
      expect(StockMovementType.all, contains(StockMovementType.returnIn));
      expect(StockMovementType.all, contains(StockMovementType.returnOut));
      expect(StockMovementType.all, contains(StockMovementType.openingBalance));
    });

    test('uses snake_case identifiers matching the database CHECK', () {
      expect(StockMovementType.adjustmentIn, 'adjustment_in');
      expect(StockMovementType.adjustmentOut, 'adjustment_out');
      expect(StockMovementType.purchaseIn, 'purchase_in');
      expect(StockMovementType.saleOut, 'sale_out');
      expect(StockMovementType.transferIn, 'transfer_in');
      expect(StockMovementType.transferOut, 'transfer_out');
      expect(StockMovementType.returnIn, 'return_in');
      expect(StockMovementType.returnOut, 'return_out');
      expect(StockMovementType.openingBalance, 'opening_balance');
    });
  });

  // ---------------------------------------------------------------------------
  // StockMovementModel.fromMap
  // ---------------------------------------------------------------------------

  group('StockMovementModel.fromMap', () {
    test('parses a complete IN movement', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'mov-1',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'product_id': 'prod-1',
        'movement_type': StockMovementType.purchaseIn,
        'quantity': 24.0,
        'unit_cost': 8.5,
        'reference_type': 'purchase',
        'reference_id': 'po-1',
        'notes': 'استلام مخزون',
        'created_by': 'user-1',
        'created_at': '2026-10-02T12:00:00.000Z',
      };

      final StockMovementModel model = StockMovementModel.fromMap(row);

      expect(model.id, 'mov-1');
      expect(model.companyId, 'company-1');
      expect(model.branchId, 'branch-1');
      expect(model.productId, 'prod-1');
      expect(model.movementType, StockMovementType.purchaseIn);
      expect(model.quantity, 24.0);
      expect(model.unitCost, 8.5);
      expect(model.referenceType, 'purchase');
      expect(model.referenceId, 'po-1');
      expect(model.notes, 'استلام مخزون');
      expect(model.createdBy, 'user-1');
      expect(model.createdAt.isUtc, isTrue);
    });

    test('parses a minimal OUT movement without optional fields', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'mov-2',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'product_id': 'prod-1',
        'movement_type': StockMovementType.adjustmentOut,
        'quantity': -5.0,
        'created_at': '2026-10-02T12:00:00.000Z',
      };

      final StockMovementModel model = StockMovementModel.fromMap(row);

      expect(model.quantity, -5.0);
      expect(model.unitCost, isNull);
      expect(model.referenceType, isNull);
      expect(model.referenceId, isNull);
      expect(model.notes, isNull);
      expect(model.createdBy, isNull);
    });

    test('parses quantity delivered as a numeric string (PostgREST)', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'mov-3',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'product_id': 'prod-1',
        'movement_type': StockMovementType.adjustmentIn,
        'quantity': '10.5000',
        'unit_cost': '12.7500',
        'created_at': '2026-10-02T12:00:00.000Z',
      };

      final StockMovementModel model = StockMovementModel.fromMap(row);

      expect(model.quantity, 10.5);
      expect(model.unitCost, 12.75);
    });

    test('parses an integer quantity without loss', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'mov-4',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'product_id': 'prod-1',
        'movement_type': StockMovementType.openingBalance,
        'quantity': 100,
        'created_at': '2026-10-02T12:00:00.000Z',
      };

      final StockMovementModel model = StockMovementModel.fromMap(row);

      expect(model.quantity, 100.0);
    });

    test('treats empty notes as null', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'mov-5',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'product_id': 'prod-1',
        'movement_type': StockMovementType.adjustmentIn,
        'quantity': 1.0,
        'notes': '   ',
        'created_at': '2026-10-02T12:00:00.000Z',
      };

      final StockMovementModel model = StockMovementModel.fromMap(row);

      expect(model.notes, isNull);
    });

    test('throws FormatException when a required id is empty', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': '',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'product_id': 'prod-1',
        'movement_type': StockMovementType.adjustmentIn,
        'quantity': 1.0,
        'created_at': '2026-10-02T12:00:00.000Z',
      };

      expect(
        () => StockMovementModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when quantity is missing', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'mov-6',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'product_id': 'prod-1',
        'movement_type': StockMovementType.adjustmentIn,
        'created_at': '2026-10-02T12:00:00.000Z',
      };

      expect(
        () => StockMovementModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when quantity is not numeric', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'mov-7',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'product_id': 'prod-1',
        'movement_type': StockMovementType.adjustmentIn,
        'quantity': 'abc',
        'created_at': '2026-10-02T12:00:00.000Z',
      };

      expect(
        () => StockMovementModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when a timestamp is invalid', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'mov-8',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'product_id': 'prod-1',
        'movement_type': StockMovementType.adjustmentIn,
        'quantity': 1.0,
        'created_at': 'not-a-date',
      };

      expect(
        () => StockMovementModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('parses created_at as UTC', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'mov-9',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'product_id': 'prod-1',
        'movement_type': StockMovementType.adjustmentIn,
        'quantity': 1.0,
        'created_at': '2026-10-02T12:00:00+02:00',
      };

      final StockMovementModel model = StockMovementModel.fromMap(row);

      expect(model.createdAt.isUtc, isTrue);
      expect(model.createdAt.toUtc(), DateTime.utc(2026, 10, 2, 10));
    });
  });

  // ---------------------------------------------------------------------------
  // StockMovementModel.toEntity
  // ---------------------------------------------------------------------------

  group('StockMovementModel.toEntity', () {
    test('produces a StockMovement with identical field values', () {
      final StockMovementModel model =
          StockMovementModel.fromMap(<String, dynamic>{
        'id': 'mov-1',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'product_id': 'prod-1',
        'movement_type': StockMovementType.purchaseIn,
        'quantity': 24.0,
        'unit_cost': 8.5,
        'reference_type': 'purchase',
        'reference_id': 'po-1',
        'notes': 'استلام',
        'created_by': 'user-1',
        'created_at': '2026-10-02T12:00:00.000Z',
      });

      final StockMovement entity = model.toEntity();

      expect(entity.id, model.id);
      expect(entity.companyId, model.companyId);
      expect(entity.branchId, model.branchId);
      expect(entity.productId, model.productId);
      expect(entity.movementType, model.movementType);
      expect(entity.quantity, model.quantity);
      expect(entity.unitCost, model.unitCost);
      expect(entity.referenceType, model.referenceType);
      expect(entity.referenceId, model.referenceId);
      expect(entity.notes, model.notes);
      expect(entity.createdBy, model.createdBy);
      expect(entity.createdAt, model.createdAt);
    });
  });

  // ---------------------------------------------------------------------------
  // StockMovement getters
  // ---------------------------------------------------------------------------

  group('StockMovement getters', () {
    final DateTime timestamp = DateTime.utc(2026, 10, 2);

    test('isIncrease / isDecrease reflect the sign of quantity', () {
      final StockMovement incoming = StockMovement(
        id: 'm',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        movementType: StockMovementType.adjustmentIn,
        quantity: 10,
        createdAt: timestamp,
      );
      final StockMovement outgoing = StockMovement(
        id: 'm',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        movementType: StockMovementType.adjustmentOut,
        quantity: -10,
        createdAt: timestamp,
      );

      expect(incoming.isIncrease, isTrue);
      expect(incoming.isDecrease, isFalse);
      expect(outgoing.isIncrease, isFalse);
      expect(outgoing.isDecrease, isTrue);
    });

    test('absoluteQuantity is always non-negative', () {
      final StockMovement incoming = StockMovement(
        id: 'm',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        movementType: StockMovementType.adjustmentIn,
        quantity: 10,
        createdAt: timestamp,
      );
      final StockMovement outgoing = StockMovement(
        id: 'm',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        movementType: StockMovementType.adjustmentOut,
        quantity: -10,
        createdAt: timestamp,
      );

      expect(incoming.absoluteQuantity, 10);
      expect(outgoing.absoluteQuantity, 10);
    });

    test('hasReference is true only when both fields are present', () {
      final StockMovement withReference = StockMovement(
        id: 'm',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        movementType: StockMovementType.purchaseIn,
        quantity: 1,
        referenceType: 'purchase',
        referenceId: 'po-1',
        createdAt: timestamp,
      );
      final StockMovement withoutReference = StockMovement(
        id: 'm',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        movementType: StockMovementType.adjustmentIn,
        quantity: 1,
        createdAt: timestamp,
      );

      expect(withReference.hasReference, isTrue);
      expect(withoutReference.hasReference, isFalse);
    });

    test('hasUnitCost is true only when a cost is provided', () {
      final StockMovement withCost = StockMovement(
        id: 'm',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        movementType: StockMovementType.purchaseIn,
        quantity: 1,
        unitCost: 8.5,
        createdAt: timestamp,
      );
      final StockMovement withoutCost = StockMovement(
        id: 'm',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        movementType: StockMovementType.adjustmentIn,
        quantity: 1,
        createdAt: timestamp,
      );

      expect(withCost.hasUnitCost, isTrue);
      expect(withoutCost.hasUnitCost, isFalse);
    });

    test('hasNotes treats empty strings as absent', () {
      final StockMovement blank = StockMovement(
        id: 'm',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        movementType: StockMovementType.adjustmentIn,
        quantity: 1,
        notes: '   ',
        createdAt: timestamp,
      );
      final StockMovement filled = StockMovement(
        id: 'm',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        movementType: StockMovementType.adjustmentIn,
        quantity: 1,
        notes: 'سبب التسوية',
        createdAt: timestamp,
      );

      expect(blank.hasNotes, isFalse);
      expect(filled.hasNotes, isTrue);
    });

    test('hasCreatedBy reflects the presence of a user id', () {
      final StockMovement withUser = StockMovement(
        id: 'm',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        movementType: StockMovementType.adjustmentIn,
        quantity: 1,
        createdBy: 'user-1',
        createdAt: timestamp,
      );
      final StockMovement withoutUser = StockMovement(
        id: 'm',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        movementType: StockMovementType.adjustmentIn,
        quantity: 1,
        createdAt: timestamp,
      );

      expect(withUser.hasCreatedBy, isTrue);
      expect(withoutUser.hasCreatedBy, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // StockMovement equality
  // ---------------------------------------------------------------------------

  group('StockMovement equality', () {
    final DateTime timestamp = DateTime.utc(2026, 10, 2);

    test('two entities with the same fields are equal', () {
      final StockMovement a = StockMovement(
        id: 'm',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        movementType: StockMovementType.adjustmentIn,
        quantity: 10,
        unitCost: 8.5,
        createdAt: timestamp,
      );
      final StockMovement b = StockMovement(
        id: 'm',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        movementType: StockMovementType.adjustmentIn,
        quantity: 10,
        unitCost: 8.5,
        createdAt: timestamp,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('quantity difference is significant', () {
      final StockMovement a = StockMovement(
        id: 'm',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        movementType: StockMovementType.adjustmentIn,
        quantity: 10,
        createdAt: timestamp,
      );
      final StockMovement b = StockMovement(
        id: 'm',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        movementType: StockMovementType.adjustmentIn,
        quantity: 11,
        createdAt: timestamp,
      );

      expect(a, isNot(equals(b)));
    });

    test('movementType difference is significant', () {
      final StockMovement a = StockMovement(
        id: 'm',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        movementType: StockMovementType.adjustmentIn,
        quantity: 10,
        createdAt: timestamp,
      );
      final StockMovement b = StockMovement(
        id: 'm',
        companyId: 'c',
        branchId: 'br',
        productId: 'p',
        movementType: StockMovementType.purchaseIn,
        quantity: 10,
        createdAt: timestamp,
      );

      expect(a, isNot(equals(b)));
    });
  });
}

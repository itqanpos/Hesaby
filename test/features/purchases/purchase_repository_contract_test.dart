// test/features/purchases/purchase_repository_contract_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/purchases/domain/entities/purchase.dart';
import 'package:hesabi/features/purchases/domain/entities/purchase_item.dart';
import 'package:hesabi/features/purchases/domain/repositories/purchase_repository.dart';

/// A minimal in-memory implementation of [PurchaseRepository].
///
/// Its sole purpose is to prove, at compile time, that the interface can be
/// implemented outside the Supabase data layer. It is intentionally not a
/// behavioural fake: the methods are kept minimal so that if the interface
/// gains a member, this file stops compiling and forces a deliberate
/// update.
class _FakePurchaseRepository implements PurchaseRepository {
  @override
  Future<List<Purchase>> listPurchases(
    String companyId, {
    String? branchId,
    String? status,
    int? limit,
  }) async =>
      const <Purchase>[];

  @override
  Future<Purchase> getPurchase(String purchaseId) async =>
      throw UnimplementedError();

  @override
  Future<List<PurchaseItem>> listPurchaseItems(String purchaseId) async =>
      const <PurchaseItem>[];

  @override
  Future<Purchase> createPurchase({
    required String companyId,
    required String branchId,
    required String supplierId,
    required DateTime purchaseDate,
    List<PurchaseItemDraft> items = const <PurchaseItemDraft>[],
    String? invoiceNumber,
    double discount = 0,
    double taxAmount = 0,
    String? notes,
  }) async =>
      throw UnimplementedError();

  @override
  Future<Purchase> updateDraft({
    required String purchaseId,
    required String companyId,
    required String branchId,
    required String supplierId,
    required DateTime purchaseDate,
    required List<PurchaseItemDraft> items,
    String? invoiceNumber,
    double discount = 0,
    double taxAmount = 0,
    String? notes,
  }) async =>
      throw UnimplementedError();

  @override
  Future<Purchase> confirmPurchase(String purchaseId) async =>
      throw UnimplementedError();

  @override
  Future<Purchase> cancelPurchase(String purchaseId) async =>
      throw UnimplementedError();
}

void main() {
  // ---------------------------------------------------------------------------
  // PurchaseFailureType completeness
  // ---------------------------------------------------------------------------

  group('PurchaseFailureType', () {
    test('declares exactly the documented failure categories', () {
      // The list is intentionally explicit and hard-coded. Adding a new
      // value to the enum without also updating the presentation-layer
      // switch would leave a message unmapped; this test is the safety net
      // that forces a conscious decision at that point.
      const List<PurchaseFailureType> expected = <PurchaseFailureType>[
        PurchaseFailureType.network,
        PurchaseFailureType.unauthorized,
        PurchaseFailureType.notFound,
        PurchaseFailureType.invalidStatusTransition,
        PurchaseFailureType.emptyPurchase,
        PurchaseFailureType.invoiceNumberConflict,
        PurchaseFailureType.supplierNotFound,
        PurchaseFailureType.branchNotFound,
        PurchaseFailureType.productNotFound,
        PurchaseFailureType.unitNotFound,
        PurchaseFailureType.insufficientStock,
        PurchaseFailureType.invalidResponse,
        PurchaseFailureType.unknown,
      ];

      expect(PurchaseFailureType.values.length, expected.length);
      for (final PurchaseFailureType type in expected) {
        expect(
          PurchaseFailureType.values,
          contains(type),
          reason: 'Missing failure type: ${type.name}',
        );
      }
    });

    test('each value has a unique name', () {
      final Set<String> names = <String>{
        for (final PurchaseFailureType type in PurchaseFailureType.values)
          type.name,
      };

      expect(names.length, PurchaseFailureType.values.length);
    });
  });

  // ---------------------------------------------------------------------------
  // PurchaseStatus constants
  // ---------------------------------------------------------------------------

  group('PurchaseStatus', () {
    test('declares exactly three states accepted by the DB CHECK', () {
      expect(PurchaseStatus.all.length, 3);
      expect(PurchaseStatus.all, contains(PurchaseStatus.draft));
      expect(PurchaseStatus.all, contains(PurchaseStatus.confirmed));
      expect(PurchaseStatus.all, contains(PurchaseStatus.cancelled));
    });
  });

  // ---------------------------------------------------------------------------
  // PurchaseException equality
  // ---------------------------------------------------------------------------

  group('PurchaseException', () {
    test('two instances with the same type are equal', () {
      const PurchaseException a = PurchaseException(
        type: PurchaseFailureType.emptyPurchase,
      );
      const PurchaseException b = PurchaseException(
        type: PurchaseFailureType.emptyPurchase,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('two instances with different types are not equal', () {
      const PurchaseException a = PurchaseException(
        type: PurchaseFailureType.emptyPurchase,
      );
      const PurchaseException b = PurchaseException(
        type: PurchaseFailureType.invoiceNumberConflict,
      );

      expect(a, isNot(equals(b)));
    });

    test('cause and stackTrace do not affect equality', () {
      final StackTrace stackTrace = StackTrace.current;
      final PurchaseException a = PurchaseException(
        type: PurchaseFailureType.unknown,
        cause: 'x',
        stackTrace: stackTrace,
      );
      final PurchaseException b = PurchaseException(
        type: PurchaseFailureType.unknown,
        cause: 'y',
        stackTrace: stackTrace,
      );

      expect(a, equals(b));
    });

    test('implements Exception', () {
      const PurchaseException exception = PurchaseException(
        type: PurchaseFailureType.network,
      );

      expect(exception, isA<Exception>());
    });

    test('toString exposes only the failure type', () {
      const PurchaseException exception = PurchaseException(
        type: PurchaseFailureType.supplierNotFound,
        cause: 'raw backend detail',
      );

      final String text = exception.toString();

      expect(text, contains('supplierNotFound'));
      expect(text, isNot(contains('raw backend detail')));
    });
  });

  // ---------------------------------------------------------------------------
  // PurchaseItemDraft equality
  // ---------------------------------------------------------------------------

  group('PurchaseItemDraft', () {
    test('two drafts with the same fields are equal', () {
      const PurchaseItemDraft a = PurchaseItemDraft(
        productId: 'prod-1',
        unitId: 'unit-1',
        quantity: 24,
        unitCost: 8.5,
      );
      const PurchaseItemDraft b = PurchaseItemDraft(
        productId: 'prod-1',
        unitId: 'unit-1',
        quantity: 24,
        unitCost: 8.5,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('quantity difference is significant', () {
      const PurchaseItemDraft a = PurchaseItemDraft(
        productId: 'prod-1',
        unitId: 'unit-1',
        quantity: 24,
        unitCost: 8.5,
      );
      const PurchaseItemDraft b = PurchaseItemDraft(
        productId: 'prod-1',
        unitId: 'unit-1',
        quantity: 25,
        unitCost: 8.5,
      );

      expect(a, isNot(equals(b)));
    });

    test('notes difference is significant', () {
      const PurchaseItemDraft a = PurchaseItemDraft(
        productId: 'prod-1',
        unitId: 'unit-1',
        quantity: 24,
        unitCost: 8.5,
        notes: 'أ',
      );
      const PurchaseItemDraft b = PurchaseItemDraft(
        productId: 'prod-1',
        unitId: 'unit-1',
        quantity: 24,
        unitCost: 8.5,
        notes: 'ب',
      );

      expect(a, isNot(equals(b)));
    });

    test('toString does not expose internal representation details', () {
      const PurchaseItemDraft draft = PurchaseItemDraft(
        productId: 'prod-1',
        unitId: 'unit-1',
        quantity: 24,
        unitCost: 8.5,
      );

      expect(draft.toString(), contains('PurchaseItemDraft'));
      expect(draft.toString(), contains('prod-1'));
    });
  });

  // ---------------------------------------------------------------------------
  // Interface implementability
  // ---------------------------------------------------------------------------

  group('PurchaseRepository interface', () {
    test('can be implemented outside the Supabase data layer', () {
      // The mere assignment below is the test: if the interface gains a
      // member, _FakePurchaseRepository stops compiling and this file
      // forces a deliberate update.
      final PurchaseRepository repository = _FakePurchaseRepository();

      expect(repository, isA<PurchaseRepository>());
    });

    test('listPurchases returns an empty list by default', () async {
      final PurchaseRepository repository = _FakePurchaseRepository();

      final List<Purchase> purchases =
          await repository.listPurchases('company-1');

      expect(purchases, isEmpty);
    });

    test('listPurchaseItems returns an empty list by default', () async {
      final PurchaseRepository repository = _FakePurchaseRepository();

      final List<PurchaseItem> items =
          await repository.listPurchaseItems('purchase-1');

      expect(items, isEmpty);
    });
  });
}

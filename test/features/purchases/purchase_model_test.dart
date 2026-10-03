// test/features/purchases/purchase_model_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/purchases/data/models/purchase_model.dart';
import 'package:hesabi/features/purchases/domain/entities/purchase.dart';

void main() {
  // ---------------------------------------------------------------------------
  // PurchaseStatus constants
  // ---------------------------------------------------------------------------

  group('PurchaseStatus', () {
    test('declares exactly the three statuses accepted by the DB CHECK', () {
      expect(PurchaseStatus.all.length, 3);
      expect(PurchaseStatus.all, contains(PurchaseStatus.draft));
      expect(PurchaseStatus.all, contains(PurchaseStatus.confirmed));
      expect(PurchaseStatus.all, contains(PurchaseStatus.cancelled));
    });

    test('uses snake-case identifiers matching the database CHECK', () {
      expect(PurchaseStatus.draft, 'draft');
      expect(PurchaseStatus.confirmed, 'confirmed');
      expect(PurchaseStatus.cancelled, 'cancelled');
    });
  });

  // ---------------------------------------------------------------------------
  // PurchaseModel.fromMap
  // ---------------------------------------------------------------------------

  group('PurchaseModel.fromMap', () {
    test('parses a complete valid row', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pur-1',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'supplier_id': 'sup-1',
        'invoice_number': 'INV-2026-001',
        'purchase_date': '2026-10-03',
        'status': PurchaseStatus.confirmed,
        'subtotal': '1000.0000',
        'discount': '50.0000',
        'tax_amount': '14.0000',
        'total': '964.0000',
        'notes': 'استلام مخزون',
        'created_by': 'user-1',
        'confirmed_at': '2026-10-03T14:00:00.000Z',
        'cancelled_at': null,
        'created_at': '2026-10-03T10:00:00.000Z',
        'updated_at': '2026-10-03T14:00:00.000Z',
      };

      final PurchaseModel model = PurchaseModel.fromMap(row);

      expect(model.id, 'pur-1');
      expect(model.companyId, 'company-1');
      expect(model.branchId, 'branch-1');
      expect(model.supplierId, 'sup-1');
      expect(model.invoiceNumber, 'INV-2026-001');
      expect(model.status, PurchaseStatus.confirmed);
      expect(model.subtotal, 1000.0);
      expect(model.discount, 50.0);
      expect(model.taxAmount, 14.0);
      expect(model.total, 964.0);
      expect(model.notes, 'استلام مخزون');
      expect(model.createdBy, 'user-1');
      expect(model.confirmedAt, isNotNull);
      expect(model.cancelledAt, isNull);
    });

    test('parses a minimal draft row without optional fields', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pur-2',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'supplier_id': 'sup-1',
        'purchase_date': '2026-10-03',
        'status': PurchaseStatus.draft,
        'subtotal': 0,
        'discount': 0,
        'tax_amount': 0,
        'total': 0,
        'created_at': '2026-10-03T10:00:00.000Z',
        'updated_at': '2026-10-03T10:00:00.000Z',
      };

      final PurchaseModel model = PurchaseModel.fromMap(row);

      expect(model.invoiceNumber, isNull);
      expect(model.notes, isNull);
      expect(model.createdBy, isNull);
      expect(model.confirmedAt, isNull);
      expect(model.cancelledAt, isNull);
    });

    test('parses numeric columns delivered as numeric strings (PostgREST)',
        () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pur-3',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'supplier_id': 'sup-1',
        'purchase_date': '2026-10-03',
        'status': PurchaseStatus.draft,
        'subtotal': '999.9999',
        'discount': '0.0000',
        'tax_amount': '14.5000',
        'total': '1014.4999',
        'created_at': '2026-10-03T10:00:00.000Z',
        'updated_at': '2026-10-03T10:00:00.000Z',
      };

      final PurchaseModel model = PurchaseModel.fromMap(row);

      expect(model.subtotal, closeTo(999.9999, 0.0001));
      expect(model.discount, 0);
      expect(model.taxAmount, 14.5);
      expect(model.total, closeTo(1014.4999, 0.0001));
    });

    test('parses purchase_date as midnight UTC', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pur-4',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'supplier_id': 'sup-1',
        'purchase_date': '2026-10-03',
        'status': PurchaseStatus.draft,
        'subtotal': 0,
        'discount': 0,
        'tax_amount': 0,
        'total': 0,
        'created_at': '2026-10-03T10:00:00.000Z',
        'updated_at': '2026-10-03T10:00:00.000Z',
      };

      final PurchaseModel model = PurchaseModel.fromMap(row);

      expect(model.purchaseDate.isUtc, isTrue);
      expect(model.purchaseDate, DateTime.utc(2026, 10, 3));
      expect(model.purchaseDate.hour, 0);
      expect(model.purchaseDate.minute, 0);
    });

    test('trims whitespace from optional strings', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pur-5',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'supplier_id': 'sup-1',
        'invoice_number': '  INV-2026-002  ',
        'purchase_date': '2026-10-03',
        'status': PurchaseStatus.draft,
        'subtotal': 0,
        'discount': 0,
        'tax_amount': 0,
        'total': 0,
        'notes': '   ',
        'created_at': '2026-10-03T10:00:00.000Z',
        'updated_at': '2026-10-03T10:00:00.000Z',
      };

      final PurchaseModel model = PurchaseModel.fromMap(row);

      expect(model.invoiceNumber, 'INV-2026-002');
      expect(model.notes, isNull);
    });

    test('throws FormatException when id is empty', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': '',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'supplier_id': 'sup-1',
        'purchase_date': '2026-10-03',
        'status': PurchaseStatus.draft,
        'subtotal': 0,
        'discount': 0,
        'tax_amount': 0,
        'total': 0,
        'created_at': '2026-10-03T10:00:00.000Z',
        'updated_at': '2026-10-03T10:00:00.000Z',
      };

      expect(
        () => PurchaseModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when status is missing', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pur-6',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'supplier_id': 'sup-1',
        'purchase_date': '2026-10-03',
        'subtotal': 0,
        'discount': 0,
        'tax_amount': 0,
        'total': 0,
        'created_at': '2026-10-03T10:00:00.000Z',
        'updated_at': '2026-10-03T10:00:00.000Z',
      };

      expect(
        () => PurchaseModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when purchase_date is invalid', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pur-7',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'supplier_id': 'sup-1',
        'purchase_date': 'not-a-date',
        'status': PurchaseStatus.draft,
        'subtotal': 0,
        'discount': 0,
        'tax_amount': 0,
        'total': 0,
        'created_at': '2026-10-03T10:00:00.000Z',
        'updated_at': '2026-10-03T10:00:00.000Z',
      };

      expect(
        () => PurchaseModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when a timestamp is invalid', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pur-8',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'supplier_id': 'sup-1',
        'purchase_date': '2026-10-03',
        'status': PurchaseStatus.draft,
        'subtotal': 0,
        'discount': 0,
        'tax_amount': 0,
        'total': 0,
        'created_at': 'not-a-date',
        'updated_at': '2026-10-03T10:00:00.000Z',
      };

      expect(
        () => PurchaseModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('parses timestamps as UTC', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pur-9',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'supplier_id': 'sup-1',
        'purchase_date': '2026-10-03',
        'status': PurchaseStatus.draft,
        'subtotal': 0,
        'discount': 0,
        'tax_amount': 0,
        'total': 0,
        'created_at': '2026-10-03T12:00:00+02:00',
        'updated_at': '2026-10-03T12:00:00+02:00',
      };

      final PurchaseModel model = PurchaseModel.fromMap(row);

      expect(model.createdAt.isUtc, isTrue);
      expect(model.createdAt.toUtc(), DateTime.utc(2026, 10, 3, 10));
    });
  });

  // ---------------------------------------------------------------------------
  // PurchaseModel.toEntity
  // ---------------------------------------------------------------------------

  group('PurchaseModel.toEntity', () {
    test('produces a Purchase with identical field values', () {
      final PurchaseModel model = PurchaseModel.fromMap(<String, dynamic>{
        'id': 'pur-1',
        'company_id': 'company-1',
        'branch_id': 'branch-1',
        'supplier_id': 'sup-1',
        'invoice_number': 'INV-001',
        'purchase_date': '2026-10-03',
        'status': PurchaseStatus.confirmed,
        'subtotal': '100.5',
        'discount': '10',
        'tax_amount': '14',
        'total': '104.5',
        'notes': 'ملاحظة',
        'created_by': 'user-1',
        'confirmed_at': '2026-10-03T14:00:00.000Z',
        'created_at': '2026-10-03T10:00:00.000Z',
        'updated_at': '2026-10-03T14:00:00.000Z',
      });

      final Purchase entity = model.toEntity();

      expect(entity.id, model.id);
      expect(entity.companyId, model.companyId);
      expect(entity.branchId, model.branchId);
      expect(entity.supplierId, model.supplierId);
      expect(entity.invoiceNumber, model.invoiceNumber);
      expect(entity.purchaseDate, model.purchaseDate);
      expect(entity.status, model.status);
      expect(entity.subtotal, model.subtotal);
      expect(entity.discount, model.discount);
      expect(entity.taxAmount, model.taxAmount);
      expect(entity.total, model.total);
      expect(entity.notes, model.notes);
      expect(entity.createdBy, model.createdBy);
      expect(entity.confirmedAt, model.confirmedAt);
      expect(entity.cancelledAt, model.cancelledAt);
      expect(entity.createdAt, model.createdAt);
      expect(entity.updatedAt, model.updatedAt);
    });
  });

  // ---------------------------------------------------------------------------
  // Purchase getters
  // ---------------------------------------------------------------------------

  group('Purchase getters', () {
    final DateTime timestamp = DateTime.utc(2026, 10, 3);

    Purchase build({
      String status = PurchaseStatus.draft,
      String? invoiceNumber,
      String? notes,
      DateTime? confirmedAt,
      DateTime? cancelledAt,
      double subtotal = 100,
      double discount = 10,
      double taxAmount = 5,
    }) =>
        Purchase(
          id: 'p',
          companyId: 'c',
          branchId: 'b',
          supplierId: 's',
          purchaseDate: timestamp,
          status: status,
          subtotal: subtotal,
          discount: discount,
          taxAmount: taxAmount,
          total: subtotal - discount + taxAmount,
          invoiceNumber: invoiceNumber,
          notes: notes,
          confirmedAt: confirmedAt,
          cancelledAt: cancelledAt,
          createdAt: timestamp,
          updatedAt: timestamp,
        );

    test('isDraft / isConfirmed / isCancelled reflect status', () {
      expect(build(status: PurchaseStatus.draft).isDraft, isTrue);
      expect(build(status: PurchaseStatus.draft).isConfirmed, isFalse);
      expect(build(status: PurchaseStatus.draft).isCancelled, isFalse);

      expect(build(status: PurchaseStatus.confirmed).isConfirmed, isTrue);
      expect(build(status: PurchaseStatus.confirmed).isDraft, isFalse);

      expect(build(status: PurchaseStatus.cancelled).isCancelled, isTrue);
      expect(build(status: PurchaseStatus.cancelled).isDraft, isFalse);
    });

    test('canEdit is true only for drafts', () {
      expect(build(status: PurchaseStatus.draft).canEdit, isTrue);
      expect(build(status: PurchaseStatus.confirmed).canEdit, isFalse);
      expect(build(status: PurchaseStatus.cancelled).canEdit, isFalse);
    });

    test('canTransition is true for drafts and confirmed, false for cancelled',
        () {
      expect(build(status: PurchaseStatus.draft).canTransition, isTrue);
      expect(build(status: PurchaseStatus.confirmed).canTransition, isTrue);
      expect(build(status: PurchaseStatus.cancelled).canTransition, isFalse);
    });

    test('hasInvoiceNumber treats null and blank as absent', () {
      expect(build().hasInvoiceNumber, isFalse);
      expect(build(invoiceNumber: '   ').hasInvoiceNumber, isFalse);
      expect(build(invoiceNumber: 'INV-1').hasInvoiceNumber, isTrue);
    });

    test('hasNotes treats null and blank as absent', () {
      expect(build().hasNotes, isFalse);
      expect(build(notes: '   ').hasNotes, isFalse);
      expect(build(notes: 'ملاحظة').hasNotes, isTrue);
    });

    test('wasConfirmed / wasCancelled reflect timestamps', () {
      expect(build().wasConfirmed, isFalse);
      expect(build().wasCancelled, isFalse);
      expect(build(confirmedAt: timestamp).wasConfirmed, isTrue);
      expect(build(cancelledAt: timestamp).wasCancelled, isTrue);
    });

    test('netAfterDiscount = subtotal - discount', () {
      final Purchase purchase = build(subtotal: 100, discount: 25);
      expect(purchase.netAfterDiscount, 75);
    });
  });

  // ---------------------------------------------------------------------------
  // Purchase equality
  // ---------------------------------------------------------------------------

  group('Purchase equality', () {
    final DateTime timestamp = DateTime.utc(2026, 10, 3);

    test('two entities with the same fields are equal', () {
      final Purchase a = Purchase(
        id: 'p',
        companyId: 'c',
        branchId: 'b',
        supplierId: 's',
        purchaseDate: timestamp,
        status: PurchaseStatus.draft,
        subtotal: 100,
        discount: 0,
        taxAmount: 0,
        total: 100,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Purchase b = Purchase(
        id: 'p',
        companyId: 'c',
        branchId: 'b',
        supplierId: 's',
        purchaseDate: timestamp,
        status: PurchaseStatus.draft,
        subtotal: 100,
        discount: 0,
        taxAmount: 0,
        total: 100,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('status difference is significant', () {
      final Purchase a = Purchase(
        id: 'p',
        companyId: 'c',
        branchId: 'b',
        supplierId: 's',
        purchaseDate: timestamp,
        status: PurchaseStatus.draft,
        subtotal: 100,
        discount: 0,
        taxAmount: 0,
        total: 100,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Purchase b = Purchase(
        id: 'p',
        companyId: 'c',
        branchId: 'b',
        supplierId: 's',
        purchaseDate: timestamp,
        status: PurchaseStatus.confirmed,
        subtotal: 100,
        discount: 0,
        taxAmount: 0,
        total: 100,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(a, isNot(equals(b)));
    });

    test('total difference is significant', () {
      final Purchase a = Purchase(
        id: 'p',
        companyId: 'c',
        branchId: 'b',
        supplierId: 's',
        purchaseDate: timestamp,
        status: PurchaseStatus.draft,
        subtotal: 100,
        discount: 0,
        taxAmount: 0,
        total: 100,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Purchase b = Purchase(
        id: 'p',
        companyId: 'c',
        branchId: 'b',
        supplierId: 's',
        purchaseDate: timestamp,
        status: PurchaseStatus.draft,
        subtotal: 100,
        discount: 0,
        taxAmount: 0,
        total: 101,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(a, isNot(equals(b)));
    });
  });
}

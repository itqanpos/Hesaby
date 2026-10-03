// test/features/purchases/purchase_status_flow_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/purchases/domain/entities/purchase.dart';

/// State-machine tests for [Purchase].
///
/// These tests document, in an executable form, which actions the UI is
/// allowed to surface for each status. They exercise the entity's helper
/// getters only; no database, no providers.
void main() {
  // ---------------------------------------------------------------------------
  // Fixtures
  // ---------------------------------------------------------------------------

  final DateTime timestamp = DateTime.utc(2026, 10, 3);

  Purchase build({
    required String status,
    double subtotal = 100,
    double discount = 0,
    double taxAmount = 0,
    DateTime? confirmedAt,
    DateTime? cancelledAt,
  }) =>
      Purchase(
        id: 'pur-1',
        companyId: 'company-1',
        branchId: 'branch-1',
        supplierId: 'sup-1',
        purchaseDate: timestamp,
        status: status,
        subtotal: subtotal,
        discount: discount,
        taxAmount: taxAmount,
        total: subtotal - discount + taxAmount,
        confirmedAt: confirmedAt,
        cancelledAt: cancelledAt,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

  // ---------------------------------------------------------------------------
  // Draft state
  // ---------------------------------------------------------------------------

  group('Draft state', () {
    final Purchase draft = build(status: PurchaseStatus.draft);

    test('identifies as draft', () {
      expect(draft.isDraft, isTrue);
      expect(draft.isConfirmed, isFalse);
      expect(draft.isCancelled, isFalse);
    });

    test('allows editing header and items', () {
      expect(draft.canEdit, isTrue);
    });

    test('allows transitioning (confirm or cancel)', () {
      expect(draft.canTransition, isTrue);
    });

    test('has no confirmation or cancellation timestamps', () {
      expect(draft.wasConfirmed, isFalse);
      expect(draft.wasCancelled, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Confirmed state
  // ---------------------------------------------------------------------------

  group('Confirmed state', () {
    final Purchase confirmed = build(
      status: PurchaseStatus.confirmed,
      confirmedAt: timestamp,
    );

    test('identifies as confirmed', () {
      expect(confirmed.isConfirmed, isTrue);
      expect(confirmed.isDraft, isFalse);
      expect(confirmed.isCancelled, isFalse);
    });

    test('does not allow editing', () {
      expect(confirmed.canEdit, isFalse);
    });

    test('still allows transition to cancelled', () {
      expect(confirmed.canTransition, isTrue);
    });

    test('has a confirmation timestamp but no cancellation one', () {
      expect(confirmed.wasConfirmed, isTrue);
      expect(confirmed.wasCancelled, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Cancelled state
  // ---------------------------------------------------------------------------

  group('Cancelled state', () {
    test('cancelled from draft has only a cancelled timestamp', () {
      final Purchase cancelled = build(
        status: PurchaseStatus.cancelled,
        cancelledAt: timestamp,
      );

      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.isDraft, isFalse);
      expect(cancelled.isConfirmed, isFalse);
      expect(cancelled.wasConfirmed, isFalse);
      expect(cancelled.wasCancelled, isTrue);
    });

    test('cancelled from confirmed has both timestamps', () {
      final Purchase cancelledAfterConfirm = build(
        status: PurchaseStatus.cancelled,
        confirmedAt: DateTime.utc(2026, 10, 3, 10),
        cancelledAt: DateTime.utc(2026, 10, 3, 12),
      );

      expect(cancelledAfterConfirm.isCancelled, isTrue);
      expect(cancelledAfterConfirm.wasConfirmed, isTrue);
      expect(cancelledAfterConfirm.wasCancelled, isTrue);
    });

    test('does not allow editing', () {
      final Purchase cancelled = build(
        status: PurchaseStatus.cancelled,
        cancelledAt: timestamp,
      );

      expect(cancelled.canEdit, isFalse);
    });

    test('does not allow further transitions', () {
      final Purchase cancelled = build(
        status: PurchaseStatus.cancelled,
        cancelledAt: timestamp,
      );

      expect(cancelled.canTransition, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Full transition flow
  // ---------------------------------------------------------------------------

  group('Full lifecycle', () {
    test('draft -> confirmed -> cancelled exposes the expected actions', () {
      // Step 1: draft.
      final Purchase draft = build(status: PurchaseStatus.draft);
      expect(draft.canEdit, isTrue);
      expect(draft.canTransition, isTrue);

      // Step 2: confirmed (after the trigger inserts stock movements).
      final Purchase confirmed = build(
        status: PurchaseStatus.confirmed,
        confirmedAt: timestamp,
      );
      expect(confirmed.canEdit, isFalse);
      expect(confirmed.canTransition, isTrue);

      // Step 3: cancelled (after reversing stock movements).
      final Purchase cancelled = build(
        status: PurchaseStatus.cancelled,
        confirmedAt: timestamp,
        cancelledAt: timestamp,
      );
      expect(cancelled.canEdit, isFalse);
      expect(cancelled.canTransition, isFalse);
    });

    test('draft -> cancelled exposes the expected actions', () {
      final Purchase draft = build(status: PurchaseStatus.draft);
      expect(draft.canEdit, isTrue);

      final Purchase cancelled = build(
        status: PurchaseStatus.cancelled,
        cancelledAt: timestamp,
      );
      expect(cancelled.canEdit, isFalse);
      expect(cancelled.canTransition, isFalse);
      expect(cancelled.wasConfirmed, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Optional fields across states
  // ---------------------------------------------------------------------------

  group('Optional fields across states', () {
    test('invoice number and notes do not affect action availability', () {
      final Purchase draftWithExtras = Purchase(
        id: 'pur-2',
        companyId: 'company-1',
        branchId: 'branch-1',
        supplierId: 'sup-1',
        purchaseDate: timestamp,
        status: PurchaseStatus.draft,
        subtotal: 100,
        discount: 0,
        taxAmount: 0,
        total: 100,
        invoiceNumber: 'INV-001',
        notes: 'ملاحظة',
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(draftWithExtras.hasInvoiceNumber, isTrue);
      expect(draftWithExtras.hasNotes, isTrue);
      expect(draftWithExtras.canEdit, isTrue);
      expect(draftWithExtras.canTransition, isTrue);
    });

    test('netAfterDiscount is independent of status', () {
      final Purchase draft = build(
        status: PurchaseStatus.draft,
        subtotal: 200,
        discount: 50,
      );
      final Purchase confirmed = build(
        status: PurchaseStatus.confirmed,
        subtotal: 200,
        discount: 50,
        confirmedAt: timestamp,
      );

      expect(draft.netAfterDiscount, 150);
      expect(confirmed.netAfterDiscount, 150);
    });
  });
}

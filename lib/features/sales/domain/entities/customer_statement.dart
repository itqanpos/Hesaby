// lib/features/sales/domain/entities/customer_statement.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'sale_entities.dart';

// ============================================================================
// Statement entry type constants
// ============================================================================

/// Canonical types of a single line in a customer statement.
///
/// The four values map 1-to-1 to the four sources of balance movement:
/// * [sale]         — a confirmed sale (adds to what the customer owes),
/// * [saleReversal] — a previously confirmed sale that was cancelled,
/// * [payment]      — a standalone payment (reduces the balance),
/// * [adjustment]   — a manual balance adjustment (signed).
abstract final class StatementEntryType {
  static const String sale = 'sale';
  static const String saleReversal = 'sale_reversal';
  static const String payment = 'payment';
  static const String adjustment = 'adjustment';
}

// ============================================================================
// Statement entry
// ============================================================================

/// A single movement in a customer statement.
///
/// Accounting convention (customer perspective — a debtor):
/// * [debit]  = the customer owes more after this movement.
/// * [credit] = the customer owes less after this movement.
///
/// Both [debit] and [credit] are stored as **non-negative** values. Exactly
/// one of them is typically non-zero for a given entry, but both may be zero
/// in a theoretical no-op entry (they never should be in practice).
///
/// [balanceAfter] is the running balance **after** applying this entry. It
/// is filled by [CustomerStatement.build] and is therefore nullable on the
/// raw entry, but always non-null inside a [CustomerStatement].
@immutable
class CustomerStatementEntry extends Equatable {
  const CustomerStatementEntry({
    required this.id,
    required this.type,
    required this.date,
    required this.debit,
    required this.credit,
    this.reference,
    this.description,
    this.notes,
    this.balanceAfter,
  });

  /// Identifier of the underlying row (sale / payment / adjustment id).
  final String id;

  /// One of [StatementEntryType].
  final String type;

  /// When the movement occurred. UTC.
  final DateTime date;

  /// Amount added to what the customer owes. Never negative.
  final double debit;

  /// Amount removed from what the customer owes. Never negative.
  final double credit;

  /// Short external reference — invoice number, receipt number, etc.
  final String? reference;

  /// Human-readable one-line summary in Arabic.
  final String? description;

  /// Optional free-form notes.
  final String? notes;

  /// Running balance after this entry. `null` until the enclosing
  /// statement computes it.
  final double? balanceAfter;

  // ---------------------------------------------------------------------------
  // Convenience getters (UI only — no business rules)
  // ---------------------------------------------------------------------------

  bool get isSale => type == StatementEntryType.sale;
  bool get isSaleReversal => type == StatementEntryType.saleReversal;
  bool get isPayment => type == StatementEntryType.payment;
  bool get isAdjustment => type == StatementEntryType.adjustment;

  bool get hasReference =>
      reference != null && reference!.trim().isNotEmpty;
  bool get hasDescription =>
      description != null && description!.trim().isNotEmpty;
  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;

  bool get isDebit => debit > 0;
  bool get isCredit => credit > 0;

  CustomerStatementEntry copyWith({
    double? balanceAfter,
  }) {
    return CustomerStatementEntry(
      id: id,
      type: type,
      date: date,
      debit: debit,
      credit: credit,
      reference: reference,
      description: description,
      notes: notes,
      balanceAfter: balanceAfter ?? this.balanceAfter,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        type,
        date,
        debit,
        credit,
        reference,
        description,
        notes,
        balanceAfter,
      ];

  @override
  String toString() =>
      'CustomerStatementEntry(id: $id, type: $type, date: $date, '
      'debit: $debit, credit: $credit, balanceAfter: $balanceAfter)';
}

// ============================================================================
// Customer statement
// ============================================================================

/// A complete, ordered account statement for a single customer.
///
/// The statement is **immutable**: [build] sorts the entries, computes the
/// running balance for each, and derives [closingBalance]. Every entry
/// therefore has a non-null `balanceAfter` inside a well-formed statement.
///
/// [openingBalance] is the customer's balance **before** the earliest
/// entry in the selected period. It is computed by the repository as
/// `closingBalance - sum(debit) + sum(credit)` over the entries, so the
/// statement reconciles regardless of the filter window.
@immutable
class CustomerStatement extends Equatable {
  const CustomerStatement({
    required this.customer,
    required this.entries,
    required this.openingBalance,
    required this.closingBalance,
    required this.generatedAt,
    this.fromDate,
    this.toDate,
  });

  /// Builds a statement from an unordered list of entries.
  ///
  /// * Entries are sorted by [CustomerStatementEntry.date] (then by [id] as
  ///   a stable tie-breaker for same-timestamp rows).
  /// * [openingBalance] is trusted as-is — the repository is responsible for
  ///   computing it correctly, since it may need to look at rows outside the
  ///   requested window.
  /// * The running balance is recomputed from [openingBalance] using the
  ///   debit/credit rule: `balance = balance + debit - credit`.
  factory CustomerStatement.build({
    required Customer customer,
    required List<CustomerStatementEntry> entries,
    required double openingBalance,
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    final List<CustomerStatementEntry> sorted =
        List<CustomerStatementEntry>.of(entries)
          ..sort((CustomerStatementEntry a, CustomerStatementEntry b) {
            final int byDate = a.date.compareTo(b.date);
            if (byDate != 0) {
              return byDate;
            }
            return a.id.compareTo(b.id);
          });

    double running = openingBalance;
    final List<CustomerStatementEntry> filled =
        <CustomerStatementEntry>[];
    for (final CustomerStatementEntry entry in sorted) {
      running = running + entry.debit - entry.credit;
      filled.add(entry.copyWith(balanceAfter: running));
    }

    return CustomerStatement(
      customer: customer,
      entries: List<CustomerStatementEntry>.unmodifiable(filled),
      openingBalance: openingBalance,
      closingBalance: running,
      fromDate: fromDate,
      toDate: toDate,
      generatedAt: DateTime.now().toUtc(),
    );
  }

  final Customer customer;

  /// Entries, sorted ascending by date, each carrying its running balance.
  final List<CustomerStatementEntry> entries;

  /// Balance carried into the statement (before the first entry).
  final double openingBalance;

  /// Balance after the last entry. Always equals
  /// `openingBalance + totalDebit - totalCredit`.
  final double closingBalance;

  /// Inclusive lower bound of the filtered window, or `null` for "since the
  /// beginning".
  final DateTime? fromDate;

  /// Inclusive upper bound of the filtered window, or `null` for "up to
  /// now".
  final DateTime? toDate;

  /// When this statement was assembled (UTC). Used in the print header.
  final DateTime generatedAt;

  // ---------------------------------------------------------------------------
  // Derived aggregates (UI only — no business rules)
  // ---------------------------------------------------------------------------

  bool get isEmpty => entries.isEmpty;
  bool get hasEntries => entries.isNotEmpty;
  int get entryCount => entries.length;

  double get totalDebit => entries.fold<double>(
        0,
        (double sum, CustomerStatementEntry e) => sum + e.debit,
      );

  double get totalCredit => entries.fold<double>(
        0,
        (double sum, CustomerStatementEntry e) => sum + e.credit,
      );

  /// Whether the customer still owes anything at the end of the period.
  bool get isInDebt => closingBalance > 0;

  /// Whether the account is fully settled at the end of the period.
  bool get isSettled => closingBalance <= 0;

  @override
  List<Object?> get props => <Object?>[
        customer,
        entries,
        openingBalance,
        closingBalance,
        fromDate,
        toDate,
        generatedAt,
      ];

  @override
  String toString() =>
      'CustomerStatement(customerId: ${customer.id}, '
      'entryCount: $entryCount, openingBalance: $openingBalance, '
      'closingBalance: $closingBalance)';
}

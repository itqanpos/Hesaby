// lib/features/suppliers/domain/entities/supplier_statement.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'supplier.dart';

/// Canonical types of a single line in a supplier statement.
///
/// Accounting convention (from OUR perspective as the buyer):
/// * [purchase] — a confirmed purchase (increases what we owe).
/// * [payment]  — a payment made to the supplier (decreases what we owe).
abstract final class SupplierStatementEntryType {
  static const String purchase = 'purchase';
  static const String payment = 'payment';
}

/// A single movement in a supplier statement.
///
/// Convention (from OUR perspective as the buyer):
/// * [debit]  = we owe the supplier more (a purchase).
/// * [credit] = we owe the supplier less (a payment).
///
/// Both are stored as non-negative values. `balanceAfter` is filled by
/// [SupplierStatement.build].
@immutable
class SupplierStatementEntry extends Equatable {
  const SupplierStatementEntry({
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

  final String id;
  final String type;
  final DateTime date;

  /// Amount added to what we owe the supplier. Never negative.
  final double debit;

  /// Amount removed from what we owe the supplier. Never negative.
  final double credit;

  final String? reference;
  final String? description;
  final String? notes;
  final double? balanceAfter;

  bool get isPurchase => type == SupplierStatementEntryType.purchase;
  bool get isPayment => type == SupplierStatementEntryType.payment;

  bool get hasReference =>
      reference != null && reference!.trim().isNotEmpty;
  bool get hasDescription =>
      description != null && description!.trim().isNotEmpty;
  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;

  bool get isDebit => debit > 0;
  bool get isCredit => credit > 0;

  SupplierStatementEntry copyWith({double? balanceAfter}) {
    return SupplierStatementEntry(
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
      'SupplierStatementEntry(id: $id, type: $type, '
      'debit: $debit, credit: $credit, balanceAfter: $balanceAfter)';
}

/// A complete, ordered account statement for a single supplier.
///
/// Immutable: [build] sorts entries and computes a running balance.
///
/// [openingBalance] is the amount we owed the supplier **before** the
/// earliest entry in the selected period.
@immutable
class SupplierStatement extends Equatable {
  const SupplierStatement({
    required this.supplier,
    required this.entries,
    required this.openingBalance,
    required this.closingBalance,
    required this.generatedAt,
    this.fromDate,
    this.toDate,
  });

  factory SupplierStatement.build({
    required Supplier supplier,
    required List<SupplierStatementEntry> entries,
    required double openingBalance,
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    final List<SupplierStatementEntry> sorted =
        List<SupplierStatementEntry>.of(entries)
          ..sort((SupplierStatementEntry a, SupplierStatementEntry b) {
            final int byDate = a.date.compareTo(b.date);
            if (byDate != 0) return byDate;
            return a.id.compareTo(b.id);
          });

    double running = openingBalance;
    final List<SupplierStatementEntry> filled = <SupplierStatementEntry>[];
    for (final SupplierStatementEntry entry in sorted) {
      running = running + entry.debit - entry.credit;
      filled.add(entry.copyWith(balanceAfter: running));
    }

    return SupplierStatement(
      supplier: supplier,
      entries: List<SupplierStatementEntry>.unmodifiable(filled),
      openingBalance: openingBalance,
      closingBalance: running,
      fromDate: fromDate,
      toDate: toDate,
      generatedAt: DateTime.now().toUtc(),
    );
  }

  final Supplier supplier;
  final List<SupplierStatementEntry> entries;
  final double openingBalance;
  final double closingBalance;
  final DateTime? fromDate;
  final DateTime? toDate;
  final DateTime generatedAt;

  bool get isEmpty => entries.isEmpty;
  bool get hasEntries => entries.isNotEmpty;
  int get entryCount => entries.length;

  double get totalDebit => entries.fold<double>(
        0,
        (double s, SupplierStatementEntry e) => s + e.debit,
      );

  double get totalCredit => entries.fold<double>(
        0,
        (double s, SupplierStatementEntry e) => s + e.credit,
      );

  /// Whether we still owe the supplier at the end of the period.
  bool get isOwedToSupplier => closingBalance > 0;

  /// Whether the account is settled (or in advance).
  bool get isSettled => closingBalance <= 0;

  @override
  List<Object?> get props => <Object?>[
        supplier,
        entries,
        openingBalance,
        closingBalance,
        fromDate,
        toDate,
        generatedAt,
      ];

  @override
  String toString() =>
      'SupplierStatement(supplierId: ${supplier.id}, '
      'entryCount: $entryCount, openingBalance: $openingBalance, '
      'closingBalance: $closingBalance)';
}

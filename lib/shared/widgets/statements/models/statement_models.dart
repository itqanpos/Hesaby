// lib/shared/widgets/statements/models/statement_models.dart
//
// Value objects shared by every account statement (customer / supplier /
// future: employee, cashbox). These are pure, immutable, widget-agnostic.
//
// **Design notes**
// ----------------
// * The original domain entities (`CustomerStatementEntry` and
//   `SupplierStatementEntry`) are near-identical in shape but carry
//   feature-specific getters (`isSale` / `isPurchase`). This file flattens
//   them into a single `StatementEntryView` so the UI never needs to branch
//   on the concrete party type.
// * `ComputedStatement.from` reproduces the exact ordering rule used by the
//   legacy `_ComputedStatement` in both statement pages:
//     1. sort ascending by date,
//     2. for entries sharing the same date, sort **descending by original
//        index** (LIFO), so the resulting chronological running balance
//        matches the historical behaviour.
//   Any change here must be cross-checked against v14 note "إصلاح ترتيب
//   الحركات في نفس اليوم".
// * `storedBalance` is the balance cached on the party row
//   (`customers.balance` / `suppliers.balance`) and is used later to warn
//   about reconciliation drift. It may be `null` if not provided.
// * `StatementEntryFilter` lives here (not in `statement_filters.dart`)
//   because `ComputedStatement.displayFiltered` consumes it directly; the
//   `statement_filters.dart` file is reserved for period presets, which are
//   independent of the entry shape.

import 'package:flutter/foundation.dart';

// ============================================================================
// Entry kind
// ============================================================================

/// Canonical classification of a movement line, independent of the party.
///
/// This enum is a superset of [customer types] and [supplier types]:
/// * customer statements produce `sale`, `saleReversal`, `payment`,
///   `adjustment` (or `unknown` if a new type appears).
/// * supplier statements produce `purchase`, `payment` (or `unknown`).
enum StatementEntryKind {
  sale,
  saleReversal,
  purchase,
  payment,
  adjustment,
  unknown;

  /// Arabic label used as a fallback when the entry has no description.
  String get arabicLabel {
    switch (this) {
      case StatementEntryKind.sale:
        return 'فاتورة بيع';
      case StatementEntryKind.saleReversal:
        return 'إلغاء فاتورة';
      case StatementEntryKind.purchase:
        return 'فاتورة مشتريات';
      case StatementEntryKind.payment:
        return 'دفعة';
      case StatementEntryKind.adjustment:
        return 'تعديل رصيد';
      case StatementEntryKind.unknown:
        return 'حركة';
    }
  }

  /// Whether this kind normally carries an invoice breakdown (debit =
  /// invoice total, credit = amount paid at the point of creation).
  ///
  /// Mirrors the legacy `entry.isSale` / `entry.isPurchase` guards in the
  /// previous `_EntryRow` implementations — so `saleReversal`, `payment`
  /// and `adjustment` do **not** show the breakdown subtitles.
  bool get showsInvoiceBreakdown {
    return this == StatementEntryKind.sale ||
        this == StatementEntryKind.purchase;
  }
}

/// The party whose statement is being displayed.
enum StatementPartyKind { customer, supplier }

// ============================================================================
// Entry filter
// ============================================================================

/// Chip filter for the movement type.
///
/// The set of filters offered to the user depends on the party:
/// * customer → [all, sale, saleReversal, payment, adjustment]
/// * supplier → [all, purchase, payment]
///
/// Use [availableEntryFilters] to obtain the right list for a party.
enum StatementEntryFilter {
  all,
  sale,
  saleReversal,
  purchase,
  payment,
  adjustment;

  /// Arabic label for the chip.
  String get arabicLabel {
    switch (this) {
      case StatementEntryFilter.all:
        return 'الكل';
      case StatementEntryFilter.sale:
        return 'فواتير بيع';
      case StatementEntryFilter.saleReversal:
        return 'إلغاءات';
      case StatementEntryFilter.purchase:
        return 'مشتريات';
      case StatementEntryFilter.payment:
        return 'دفعات';
      case StatementEntryFilter.adjustment:
        return 'تعديلات';
    }
  }

  /// Whether the given entry should be shown when this filter is active.
  bool matches(StatementEntryView entry) {
    switch (this) {
      case StatementEntryFilter.all:
        return true;
      case StatementEntryFilter.sale:
        return entry.kind == StatementEntryKind.sale;
      case StatementEntryFilter.saleReversal:
        return entry.kind == StatementEntryKind.saleReversal;
      case StatementEntryFilter.purchase:
        return entry.kind == StatementEntryKind.purchase;
      case StatementEntryFilter.payment:
        return entry.kind == StatementEntryKind.payment;
      case StatementEntryFilter.adjustment:
        return entry.kind == StatementEntryKind.adjustment;
    }
  }
}

/// Returns the filters that make sense for the given party kind.
///
/// Always non-empty and always starts with [StatementEntryFilter.all].
List<StatementEntryFilter> availableEntryFilters(StatementPartyKind kind) {
  switch (kind) {
    case StatementPartyKind.customer:
      return const <StatementEntryFilter>[
        StatementEntryFilter.all,
        StatementEntryFilter.sale,
        StatementEntryFilter.saleReversal,
        StatementEntryFilter.payment,
        StatementEntryFilter.adjustment,
      ];
    case StatementPartyKind.supplier:
      return const <StatementEntryFilter>[
        StatementEntryFilter.all,
        StatementEntryFilter.purchase,
        StatementEntryFilter.payment,
      ];
  }
}

// ============================================================================
// Entry view
// ============================================================================

/// A flattened, UI-facing representation of a single statement line.
///
/// Built from `CustomerStatementEntry` or `SupplierStatementEntry` by the
/// corresponding adapter in `adapters/`.
@immutable
class StatementEntryView {
  const StatementEntryView({
    required this.id,
    required this.kind,
    required this.rawType,
    required this.date,
    required this.debit,
    required this.credit,
    this.reference,
    this.description,
    this.notes,
  });

  /// The identifier of the underlying row (sale / payment / adjustment id).
  final String id;

  /// Canonical classification of this line.
  final StatementEntryKind kind;

  /// The original `type` string from the domain entity. Preserved for
  /// debugging, logging and future migrations that need to round-trip.
  final String rawType;

  /// When the movement occurred (local time).
  final DateTime date;

  /// Amount added to the balance. Never negative.
  final double debit;

  /// Amount removed from the balance. Never negative.
  final double credit;

  /// External short reference (invoice number, receipt number).
  final String? reference;

  /// Human-readable summary in Arabic.
  final String? description;

  /// Free-form notes.
  final String? notes;

  // ---------------------------------------------------------------------------
  // Convenience getters (pure)
  // ---------------------------------------------------------------------------

  bool get hasReference =>
      reference != null && reference!.trim().isNotEmpty;

  bool get hasDescription =>
      description != null && description!.trim().isNotEmpty;

  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;

  bool get isDebit => debit > 0;
  bool get isCredit => credit > 0;

  /// See [StatementEntryKind.showsInvoiceBreakdown].
  bool get showsInvoiceBreakdown => kind.showsInvoiceBreakdown;
}

// ============================================================================
// Statement view
// ============================================================================

/// A flattened, UI-facing representation of a complete statement.
///
/// Built from `CustomerStatement` or `SupplierStatement` by the
/// corresponding adapter.
@immutable
class StatementView {
  const StatementView({
    required this.partyId,
    required this.partyName,
    required this.partyKind,
    required this.entries,
    required this.openingBalance,
    required this.closingBalance,
    this.partyCode,
    this.partyPhone,
    this.storedBalance,
    this.fromDate,
    this.toDate,
    this.generatedAt,
  });

  /// The id of the customer / supplier being displayed.
  final String partyId;

  final String partyName;
  final String? partyCode;
  final String? partyPhone;

  /// Customer vs supplier — drives wording and available filters.
  final StatementPartyKind partyKind;

  /// Entries, in the order provided by the domain entity
  /// (already sorted ascending by `(date, id)` inside `build()`).
  final List<StatementEntryView> entries;

  /// Balance carried into the statement (before the first entry).
  final double openingBalance;

  /// Balance after the last entry, as declared by the domain entity.
  ///
  /// Note: consumers should prefer `ComputedStatement.closingBalance`
  /// because it is always recomputed from the entries. The two values
  /// should match; if they don't, that's a domain bug worth investigating.
  final double closingBalance;

  /// The balance cached on the party row
  /// (`customers.balance` / `suppliers.balance`), used to warn about
  /// reconciliation drift. May be `null`.
  final double? storedBalance;

  final DateTime? fromDate;
  final DateTime? toDate;
  final DateTime? generatedAt;

  // ---------------------------------------------------------------------------
  // Aggregates (pure)
  // ---------------------------------------------------------------------------

  bool get isEmpty => entries.isEmpty;
  bool get hasEntries => entries.isNotEmpty;
  int get entryCount => entries.length;

  double get totalDebit => entries.fold<double>(
        0,
        (double sum, StatementEntryView e) => sum + e.debit,
      );

  double get totalCredit => entries.fold<double>(
        0,
        (double sum, StatementEntryView e) => sum + e.credit,
      );

  /// Whether "we" (the party's perspective) owe more at the end.
  bool get weOwe => closingBalance > 0.01;

  /// Whether the other side owes us at the end.
  bool get theyOweUs => closingBalance < -0.01;

  /// Whether the statement is settled (or in advance).
  bool get isSettled => !weOwe && !theyOweUs;

  /// Label for the party balance line in the info card.
  String get partyBalanceLabel {
    switch (partyKind) {
      case StatementPartyKind.customer:
        if (weOwe) return 'مستحق على العميل';
        if (theyOweUs) return 'لك عند العميل';
        return 'الرصيد مسدد';
      case StatementPartyKind.supplier:
        if (weOwe) return 'مستحق للمورد';
        if (theyOweUs) return 'لك عند المورد';
        return 'الرصيد مسدد';
    }
  }

  /// Label for the closing balance card at the bottom of the list.
  String get closingBalanceLabel {
    switch (partyKind) {
      case StatementPartyKind.customer:
        if (weOwe) return 'الرصيد النهائي — مستحق على العميل';
        if (theyOweUs) return 'الرصيد النهائي — لك عند العميل';
        return 'الرصيد النهائي — مسدد';
      case StatementPartyKind.supplier:
        if (weOwe) return 'الرصيد النهائي — مستحق للمورد';
        if (theyOweUs) return 'الرصيد النهائي — لك عند المورد';
        return 'الرصيد النهائي — مسدد';
    }
  }

  /// Whether the cached party balance (if any) disagrees with the computed
  /// closing balance by more than one piaster. Used for the reconciliation
  /// warning in the summary bar (Phase 4).
  bool get hasReconciliationMismatch {
    final double? stored = storedBalance;
    if (stored == null) return false;
    return (stored - closingBalance).abs() > 0.01;
  }
}

// ============================================================================
// Augmented entry
// ============================================================================

/// A statement entry paired with the balance before and after applying it.
@immutable
class AugmentedEntry {
  const AugmentedEntry({
    required this.entry,
    required this.previousBalance,
    required this.currentBalance,
  });

  final StatementEntryView entry;
  final double previousBalance;
  final double currentBalance;
}

// ============================================================================
// Computed statement
// ============================================================================

/// A statement with running balances recomputed in chronological order.
///
/// This class replaces the identical `_ComputedStatement` previously
/// duplicated in both statement pages.
@immutable
class ComputedStatement {
  const ComputedStatement({
    required this.source,
    required this.chronologicalEntries,
    required this.closingBalance,
  });

  /// Recomputes the running balance from the statement's declared
  /// [StatementView.openingBalance].
  ///
  /// Ordering rule (kept byte-for-byte identical to v14's legacy
  /// implementation, see the class doc):
  /// 1. ascending by date,
  /// 2. for the same date: descending by original index (LIFO).
  factory ComputedStatement.from(StatementView source) {
    final List<_Indexed> indexed = <_Indexed>[];
    for (int i = 0; i < source.entries.length; i++) {
      indexed.add(_Indexed(source.entries[i], i));
    }

    indexed.sort((_Indexed a, _Indexed b) {
      final int byDate = a.entry.date.compareTo(b.entry.date);
      if (byDate != 0) return byDate;
      return b.originalIndex.compareTo(a.originalIndex);
    });

    double balance = source.openingBalance;
    final List<AugmentedEntry> augmented = <AugmentedEntry>[];
    for (final _Indexed item in indexed) {
      final StatementEntryView e = item.entry;
      final double previous = balance;
      balance = balance + e.debit - e.credit;
      augmented.add(AugmentedEntry(
        entry: e,
        previousBalance: previous,
        currentBalance: balance,
      ));
    }

    return ComputedStatement(
      source: source,
      chronologicalEntries: List<AugmentedEntry>.unmodifiable(augmented),
      closingBalance: balance,
    );
  }

  /// The original, unmodified statement view.
  final StatementView source;

  /// Entries in chronological order (oldest first), each carrying the
  /// running balance before/after it.
  final List<AugmentedEntry> chronologicalEntries;

  /// Balance after the last entry — authoritative value for the UI.
  final double closingBalance;

  /// Entries ready to render (newest first).
  List<AugmentedEntry> get displayEntries =>
      chronologicalEntries.reversed.toList(growable: false);

  /// [displayEntries] filtered by the given entry filter.
  ///
  /// Filtering is display-only: opening balance, totals and closing balance
  /// remain those of the full [source]. This matches the previous behaviour
  /// (no per-filter recomputation) and avoids surprising jumps in the
  /// summary bar.
  List<AugmentedEntry> displayFiltered(StatementEntryFilter filter) {
    if (filter == StatementEntryFilter.all) {
      return displayEntries;
    }
    return chronologicalEntries.reversed
        .where((AugmentedEntry a) => filter.matches(a.entry))
        .toList(growable: false);
  }
}

/// Internal helper used only by [ComputedStatement.from].
@immutable
class _Indexed {
  const _Indexed(this.entry, this.originalIndex);
  final StatementEntryView entry;
  final int originalIndex;
}

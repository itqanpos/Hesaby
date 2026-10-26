// lib/shared/widgets/statements/adapters/statement_adapter.dart
//
// Domain → generic adapters for account statements.
//
// The two concrete adapters (`CustomerStatementAdapter` and
// `SupplierStatementAdapter`) flatten the feature-specific entities into
// the shared `StatementView` consumed by `AccountStatementPage`.
//
// **Why flatten?**
// `CustomerStatementEntry` and `SupplierStatementEntry` share the same
// shape (id, type, date, debit, credit, reference, description, notes,
// balanceAfter). Flattening them into `StatementEntryView` lets the UI
// render both without any branch on the party type. The mapping between
// raw `type` strings and `StatementEntryKind` is the only place that must
// stay in sync with the domain constants.

import '../../../../features/sales/domain/entities/customer_statement.dart';
import '../../../../features/suppliers/domain/entities/supplier_statement.dart';
import '../models/statement_models.dart';

// ============================================================================
// Customer adapter
// ============================================================================

/// Converts a [CustomerStatement] into the generic [StatementView].
class CustomerStatementAdapter {
  const CustomerStatementAdapter();

  StatementView adapt(CustomerStatement statement) {
    return StatementView(
      partyId: statement.customer.id,
      partyName: statement.customer.name,
      partyCode: statement.customer.code,
      partyPhone: statement.customer.phone,
      partyKind: StatementPartyKind.customer,
      entries: List<StatementEntryView>.unmodifiable(
        statement.entries.map(_adaptEntry),
      ),
      openingBalance: statement.openingBalance,
      closingBalance: statement.closingBalance,
      storedBalance: statement.customer.balance,
      fromDate: statement.fromDate,
      toDate: statement.toDate,
      generatedAt: statement.generatedAt,
    );
  }

  StatementEntryView _adaptEntry(CustomerStatementEntry e) {
    return StatementEntryView(
      id: e.id,
      kind: _kindFromType(e.type),
      rawType: e.type,
      date: e.date,
      debit: e.debit,
      credit: e.credit,
      reference: e.reference,
      description: e.description,
      notes: e.notes,
    );
  }

  StatementEntryKind _kindFromType(String type) {
    switch (type) {
      case StatementEntryType.sale:
        return StatementEntryKind.sale;
      case StatementEntryType.saleReversal:
        return StatementEntryKind.saleReversal;
      case StatementEntryType.payment:
        return StatementEntryKind.payment;
      case StatementEntryType.adjustment:
        return StatementEntryKind.adjustment;
      default:
        return StatementEntryKind.unknown;
    }
  }
}

// ============================================================================
// Supplier adapter
// ============================================================================

/// Converts a [SupplierStatement] into the generic [StatementView].
class SupplierStatementAdapter {
  const SupplierStatementAdapter();

  StatementView adapt(SupplierStatement statement) {
    return StatementView(
      partyId: statement.supplier.id,
      partyName: statement.supplier.name,
      partyCode: statement.supplier.code,
      partyPhone: statement.supplier.phone,
      partyKind: StatementPartyKind.supplier,
      entries: List<StatementEntryView>.unmodifiable(
        statement.entries.map(_adaptEntry),
      ),
      openingBalance: statement.openingBalance,
      closingBalance: statement.closingBalance,
      // The `Supplier` domain entity does not carry a cached balance
      // column (unlike `Customer`). Leaving `storedBalance` null keeps
      // the reconciliation warning inert for supplier statements.
      storedBalance: null,
      fromDate: statement.fromDate,
      toDate: statement.toDate,
      generatedAt: statement.generatedAt,
    );
  }

  StatementEntryView _adaptEntry(SupplierStatementEntry e) {
    return StatementEntryView(
      id: e.id,
      kind: _kindFromType(e.type),
      rawType: e.type,
      date: e.date,
      debit: e.debit,
      credit: e.credit,
      reference: e.reference,
      description: e.description,
      notes: e.notes,
    );
  }

  StatementEntryKind _kindFromType(String type) {
    switch (type) {
      case SupplierStatementEntryType.purchase:
        return StatementEntryKind.purchase;
      case SupplierStatementEntryType.payment:
        return StatementEntryKind.payment;
      default:
        return StatementEntryKind.unknown;
    }
  }
}

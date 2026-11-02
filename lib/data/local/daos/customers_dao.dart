// lib/data/local/daos/customers_dao.dart

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../app_database.dart';
import '../tables/customers_table.dart';
import '../tables/outbox_table.dart';

// ✅ استيراد الكيان الأصلي
import '../../../features/sales/domain/entities/sale_entities.dart';

part 'customers_dao.g.dart';

/// DAO (Data Access Object) for the `customers` table.
///
/// Handles all local read/write operations for customers.
/// Write operations are wrapped in a transaction to also write to the
/// `outbox` table, ensuring offline-first consistency.
@DriftAccessor(tables: [CustomersTable, OutboxTable])
class CustomersDao extends DatabaseAccessor<AppDatabase>
    with _$CustomersDaoMixin {
  CustomersDao(super.db);

  final Uuid _uuid = const Uuid();

  // ---------------------------------------------------------------------------
  // Read Operations
  // ---------------------------------------------------------------------------

  /// Watches the list of customers for a specific company.
  /// Returns a [Customer] entity which includes the `balance`.
  Stream<List<Customer>> watchCustomers({
    required String companyId,
    bool includeInactive = false,
    String? searchQuery,
  }) {
    final SimpleSelectStatement<$CustomersTableTable, CustomerRow> query =
        select(customersTable)
          ..where((t) => t.companyId.equals(companyId));

    if (!includeInactive) {
      query.where((t) => t.isActive.equals(true));
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final String term = '%${searchQuery.trim()}%';
      query.where((t) =>
          t.name.like(term) |
          t.code.like(term) |
          t.phone.like(term));
    }

    query.orderBy([(t) => OrderingTerm(expression: t.name)]);

    // ✅ تحويل النتيجة إلى كيان Customer
    return query.watch().map((List<CustomerRow> rows) =>
        rows.map((CustomerRow row) => row.toEntity()).toList(growable: false));
  }

  /// Gets a single customer by ID.
  Future<Customer?> getCustomerById(String customerId) async {
    final CustomerRow? row = await (select(customersTable)
          ..where((t) => t.id.equals(customerId)))
        .getSingleOrNull();
    return row?.toEntity();
  }

  // ---------------------------------------------------------------------------
  // Write Operations (with Outbox)
  // ---------------------------------------------------------------------------

  /// Creates a new customer locally and enqueues the operation in the outbox.
  Future<void> createCustomer({
    required CustomersTableCompanion customer,
    required String customerPayload,
  }) async {
    await transaction(() async {
      // 1. Insert into local customers table
      await into(customersTable).insert(customer);

      // 2. Insert into outbox
      await _enqueueOutbox(
        companyId: customer.companyId.value,
        operation: 'insert',
        recordId: customer.id.value,
        payload: customerPayload,
      );
    });
  }

  /// Updates an existing customer locally and enqueues the operation.
  Future<void> updateCustomer({
    required CustomersTableCompanion customer,
    required String customerPayload,
  }) async {
    await transaction(() async {
      // 1. Update local customers table
      await (update(customersTable)..where((t) => t.id.equals(customer.id.value)))
          .write(customer);

      // 2. Insert into outbox
      await _enqueueOutbox(
        companyId: customer.companyId.value,
        operation: 'update',
        recordId: customer.id.value,
        payload: customerPayload,
      );
    });
  }

  /// Deletes a customer locally and enqueues the delete operation.
  Future<void> deleteCustomer({
    required String customerId,
    required String companyId,
  }) async {
    await transaction(() async {
      // 1. Delete from local customers table
      await (delete(customersTable)..where((t) => t.id.equals(customerId))).go();

      // 2. Insert into outbox
      await _enqueueOutbox(
        companyId: companyId,
        operation: 'delete',
        recordId: customerId,
        payload: '{"id": "$customerId"}',
      );
    });
  }

  /// Updates ONLY the balance of a customer locally (useful for POS operations).
  /// Note: The sync with Supabase for balance updates is usually handled
  /// by the server (via Triggers on sales/payments), but we update it locally
  /// so the UI reflects the change instantly offline.
  Future<void> updateCustomerBalance({
    required String customerId,
    required double newBalance,
  }) async {
    await (update(customersTable)..where((t) => t.id.equals(customerId)))
        .write(CustomersTableCompanion(
      balance: Value(newBalance),
      updatedAt: Value(DateTime.now()),
    ));
  }

  // ---------------------------------------------------------------------------
  // Internal Helpers
  // ---------------------------------------------------------------------------

  Future<void> _enqueueOutbox({
    required String companyId,
    required String operation,
    required String recordId,
    required String payload,
  }) async {
    await into(outboxTable).insert(
      OutboxTableCompanion.insert(
        id: _uuid.v4(),
        companyId: companyId,
        targetTable: 'customers', // ✅ اسم الجدول في Supabase
        operation: operation,
        recordId: recordId,
        payload: payload,
        status: const Value('pending'),
        retryCount: const Value(0),
        createdAt: DateTime.now(),
      ),
    );
  }
}

// ✅ إضافة Extension لتحويل CustomerRow (Drift) إلى Customer (Domain)
extension CustomerRowMapper on CustomerRow {
  Customer toEntity() {
    return Customer(
      id: id,
      companyId: companyId,
      name: name,
      balance: balance,
      isActive: isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
      code: code,
      phone: phone,
      email: email,
      address: address,
      notes: notes,
    );
  }
}

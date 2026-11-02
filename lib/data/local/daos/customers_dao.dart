// lib/data/local/daos/customers_dao.dart

import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../app_database.dart';
import '../tables/customers_table.dart';
import '../tables/outbox_table.dart';

import '../../../features/sales/domain/entities/sale_entities.dart';

part 'customers_dao.g.dart';

@DriftAccessor(tables: [CustomersTable, OutboxTable])
class CustomersDao extends DatabaseAccessor<AppDatabase>
    with _$CustomersDaoMixin {
  CustomersDao(super.db);

  final Uuid _uuid = const Uuid();

  // ---------------------------------------------------------------------------
  // Read Operations
  // ---------------------------------------------------------------------------

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

    return query.watch().map((List<CustomerRow> rows) =>
        rows.map((CustomerRow row) => row.toEntity()).toList(growable: false));
  }

  Future<Customer?> getCustomerById(String customerId) async {
    final CustomerRow? row = await (select(customersTable)
          ..where((t) => t.id.equals(customerId)))
        .getSingleOrNull();
    return row?.toEntity();
  }

  // ---------------------------------------------------------------------------
  // Write Operations (with Outbox)
  // ---------------------------------------------------------------------------

  Future<void> createCustomer({
    required CustomersTableCompanion customer,
    required String customerPayload,
  }) async {
    await transaction(() async {
      await into(customersTable).insert(customer);
      await _enqueueOutbox(
        companyId: customer.companyId.value,
        operation: 'insert',
        recordId: customer.id.value,
        payload: customerPayload,
      );
    });
  }

  Future<void> updateCustomer({
    required CustomersTableCompanion customer,
    required String customerPayload,
  }) async {
    await transaction(() async {
      await (update(customersTable)..where((t) => t.id.equals(customer.id.value)))
          .write(customer);
      await _enqueueOutbox(
        companyId: customer.companyId.value,
        operation: 'update',
        recordId: customer.id.value,
        payload: customerPayload,
      );
    });
  }

  Future<void> deleteCustomer({
    required String customerId,
    required String companyId,
  }) async {
    await transaction(() async {
      await (delete(customersTable)..where((t) => t.id.equals(customerId))).go();
      await _enqueueOutbox(
        companyId: companyId,
        operation: 'delete',
        recordId: customerId,
        payload: '{"id": "$customerId"}',
      );
    });
  }

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
        targetTable: 'customers',
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

// ============================================================================
// Extensions for Mapping
// ============================================================================

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

extension CustomerDomainMapper on Customer {
  /// يحول الكيان إلى Companion لاستخدامه في Drift
  CustomersTableCompanion toCompanion() {
    return CustomersTableCompanion(
      id: Value(id),
      companyId: Value(companyId),
      name: Value(name),
      balance: Value(balance),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      code: Value(code),
      phone: Value(phone),
      email: Value(email),
      address: Value(address),
      notes: Value(notes),
    );
  }

  /// يحول الكيان إلى JSON لإرساله في الـ Outbox
  String toJsonPayload() {
    return jsonEncode({
      'id': id,
      'company_id': companyId,
      'name': name,
      'balance': balance,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'code': code,
      'phone': phone,
      'email': email,
      'address': address,
      'notes': notes,
    });
  }
}

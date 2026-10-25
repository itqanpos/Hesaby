// lib/features/sales/data/repositories/cached_customer_repository.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/cache/json_local_cache.dart';
import '../../../../core/cache/local_cache_provider.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/customer_adjustment.dart';
import '../../domain/entities/customer_payment.dart';
import '../../domain/entities/customer_statement.dart';
import '../../domain/entities/sale_entities.dart';
import '../../domain/repositories/sales_repository.dart';
import '../models/sale_models.dart';

/// Offline-first decorator around [CustomerRepository].
class CachedCustomerRepositoryImpl implements CustomerRepository {
  CachedCustomerRepositoryImpl({
    required CustomerRepository remote,
    required Ref ref,
  })  : _remote = remote,
        _ref = ref;

  final CustomerRepository _remote;
  final Ref _ref;

  static const String _customersPrefix = 'customers';

  static Map<String, Object?> _customerToMap(Customer c) {
    return <String, Object?>{
      'id': c.id,
      'company_id': c.companyId,
      'name': c.name,
      'code': c.code,
      'phone': c.phone,
      'email': c.email,
      'address': c.address,
      'notes': c.notes,
      'is_active': c.isActive,
      'balance': c.balance,
      'created_at': c.createdAt.toUtc().toIso8601String(),
      'updated_at': c.updatedAt.toUtc().toIso8601String(),
    };
  }

  Future<JsonLocalCache?> _cache() async {
    try {
      return await _ref.read(jsonLocalCacheProvider.future);
    } on Object {
      return null;
    }
  }

  @override
  Future<List<Customer>> listCustomers(
    String companyId, {
    bool includeInactive = false,
  }) async {
    try {
      final List<Customer> fresh = await _remote.listCustomers(
        companyId,
        includeInactive: includeInactive,
      );

      if (!includeInactive) {
        final cache = await _cache();
        if (cache != null) {
          await cache.saveList(
            prefix: _customersPrefix,
            companyId: companyId,
            items: fresh.map(_customerToMap).toList(growable: false),
          );
        }
      }

      return fresh;
    } on CustomerException catch (error) {
      if (error.type == CustomerFailureType.network) {
        final cache = await _cache();
        if (cache != null) {
          final List<Map<String, dynamic>>? cached = cache.loadList(
            prefix: _customersPrefix,
            companyId: companyId,
          );
          if (cached != null && cached.isNotEmpty) {
            AppLogger.info(
              'CachedCustomerRepository: serving ${cached.length} customers from cache.',
            );
            return cached
                .map((m) => CustomerModel.fromMap(m).toEntity())
                .toList(growable: false);
          }
        }
      }
      rethrow;
    }
  }

  @override
  Future<Customer> getCustomer(String customerId) async {
    // No offline fallback: `getCustomer` is only called from management
    // screens (not POS). Offline users will see a network error, which is
    // acceptable. POS uses `listCustomers` (cached).
    return _remote.getCustomer(customerId);
  }

  // ---------------------------------------------------------------------------
  // Mutations — delegate directly
  // ---------------------------------------------------------------------------

  @override
  Future<Customer> createCustomer({
    required String companyId,
    required String name,
    String? code,
    String? phone,
    String? email,
    String? address,
    String? notes,
  }) {
    return _remote.createCustomer(
      companyId: companyId,
      name: name,
      code: code,
      phone: phone,
      email: email,
      address: address,
      notes: notes,
    );
  }

  @override
  Future<Customer> updateCustomer({
    required String customerId,
    String? name,
    String? code,
    bool clearCode = false,
    String? phone,
    bool clearPhone = false,
    String? email,
    bool clearEmail = false,
    String? address,
    bool clearAddress = false,
    String? notes,
    bool clearNotes = false,
    bool? isActive,
  }) {
    return _remote.updateCustomer(
      customerId: customerId,
      name: name,
      code: code,
      clearCode: clearCode,
      phone: phone,
      clearPhone: clearPhone,
      email: email,
      clearEmail: clearEmail,
      address: address,
      clearAddress: clearAddress,
      notes: notes,
      clearNotes: clearNotes,
      isActive: isActive,
    );
  }

  @override
  Future<void> deleteCustomer(String customerId) {
    return _remote.deleteCustomer(customerId);
  }

  @override
  Future<List<CustomerPayment>> listPayments(
    String customerId, {
    int? limit,
  }) {
    return _remote.listPayments(customerId, limit: limit);
  }

  @override
  Future<CustomerPayment> recordPayment({
    required String companyId,
    required String customerId,
    required double amount,
    required String method,
    String? reference,
    String? notes,
  }) {
    return _remote.recordPayment(
      companyId: companyId,
      customerId: customerId,
      amount: amount,
      method: method,
      reference: reference,
      notes: notes,
    );
  }

  @override
  Future<List<CustomerAdjustment>> listAdjustments(
    String customerId, {
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    return _remote.listAdjustments(
      customerId,
      fromDate: fromDate,
      toDate: toDate,
    );
  }

  @override
  Future<CustomerAdjustment> addAdjustment({
    required String companyId,
    required String customerId,
    required double amount,
    required String reason,
    String? notes,
  }) {
    return _remote.addAdjustment(
      companyId: companyId,
      customerId: customerId,
      amount: amount,
      reason: reason,
      notes: notes,
    );
  }

  @override
  Future<CustomerStatement> buildStatement({
    required String customerId,
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    return _remote.buildStatement(
      customerId: customerId,
      fromDate: fromDate,
      toDate: toDate,
    );
  }

  // ---------------------------------------------------------------------------
  // Prefetch
  // ---------------------------------------------------------------------------

  Future<void> prefetchCustomers(String companyId) async {
    try {
      final List<Customer> customers =
          await _remote.listCustomers(companyId);
      final cache = await _cache();
      if (cache == null) return;
      await cache.saveList(
        prefix: _customersPrefix,
        companyId: companyId,
        items: customers.map(_customerToMap).toList(growable: false),
      );
      AppLogger.info(
        'CachedCustomerRepository: prefetched ${customers.length} customers for $companyId.',
      );
    } on Object catch (error) {
      AppLogger.warning('Customer prefetch failed: $error');
    }
  }
}

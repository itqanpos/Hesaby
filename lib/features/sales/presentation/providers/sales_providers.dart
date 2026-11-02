// lib/features/sales/presentation/providers/sales_providers.dart

import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;
import 'package:uuid/uuid.dart';

import '../../../../core/utils/logger.dart';
import '../../../../data/local/app_database.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../data/datasources/sales_remote_datasource.dart';
import '../../data/repositories/cached_customer_repository.dart';
import '../../data/repositories/sales_repository_impl.dart';
import '../../data/services/sales_cache_service.dart';
import '../../domain/entities/customer_adjustment.dart';
import '../../domain/entities/customer_payment.dart';
import '../../domain/entities/customer_statement.dart';
import '../../domain/entities/sale_entities.dart';
import '../../domain/entities/sale_return.dart';
import '../../domain/repositories/sales_repository.dart';

// ============================================================================
// Repository providers (Legacy - used for Payments/Adjustments/Statements)
// ============================================================================

final Provider<CustomerRepository> customerRepositoryProvider =
    Provider<CustomerRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  final CustomerRepository remote =
      CustomerRepositoryImpl(SalesRemoteDataSource(client));
  return CachedCustomerRepositoryImpl(
    remote: remote,
    ref: ref,
  );
});

final Provider<SalesRepository> salesRepositoryProvider =
    Provider<SalesRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return SalesRepositoryImpl(SalesRemoteDataSource(client));
});

final Provider<ReturnsRepository> returnsRepositoryProvider =
    Provider<ReturnsRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return ReturnsRepositoryImpl(SalesRemoteDataSource(client));
});

final FutureProvider<SalesCacheService?> salesCacheServiceProvider =
    FutureProvider<SalesCacheService?>((Ref ref) async {
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return SalesCacheService(prefs);
  } on Object catch (error, stackTrace) {
    AppLogger.error(
      'salesCacheServiceProvider: init failed.',
      error,
      stackTrace,
    );
    return null;
  }
});

// ============================================================================
// Customers (Offline-First via Drift)
// ============================================================================

class CustomersNotifier extends AsyncNotifier<List<Customer>> {
  @override
  Future<List<Customer>> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState state) => state.currentCompany?.id,
      ),
    );

    if (companyId == null) {
      return const <Customer>[];
    }

    final AppDatabase db = ref.watch(appDatabaseProvider);

    // 1. الاستماع المستمر للتغييرات في Drift
    final StreamSubscription<List<Customer>> sub =
        db.customersDao.watchCustomers(companyId: companyId).listen((List<Customer> data) {
      state = AsyncData(data);
    });

    ref.onDispose(() => sub.cancel());

    // 2. إرجاع القيمة الأولى لكي تظهر الشاشة فوراً
    return db.customersDao.watchCustomers(companyId: companyId).first;
  }

  Future<Customer> createCustomer({
    required String name,
    String? code,
    String? phone,
    String? email,
    String? address,
    String? notes,
  }) async {
    final String companyId = _requireCurrentCompanyId();
    final DateTime now = DateTime.now();
    final String newId = const Uuid().v4();

    final Customer newCustomer = Customer(
      id: newId,
      companyId: companyId,
      name: name,
      balance: 0,
      isActive: true,
      createdAt: now,
      updatedAt: now,
      code: code,
      phone: phone,
      email: email,
      address: address,
      notes: notes,
    );

    final AppDatabase db = ref.read(appDatabaseProvider);
    
    // الكتابة في Drift + Outbox
    await db.customersDao.createCustomer(
      customer: newCustomer.toCompanion(),
      customerPayload: newCustomer.toJsonPayload(),
    );

    // لا حاجة لـ _reload()، الـ Stream سيتكفل بتحديث الواجهة
    return newCustomer;
  }

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
  }) async {
    final AppDatabase db = ref.read(appDatabaseProvider);
    
    final Customer? existing = await db.customersDao.getCustomerById(customerId);
    if (existing == null) {
      throw const CustomerException(
        type: CustomerFailureType.notFound,
        cause: 'Customer not found locally.',
      );
    }

    final Customer updated = existing.copyWith(
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
      updatedAt: DateTime.now(),
    );

    await db.customersDao.updateCustomer(
      customer: updated.toCompanion(),
      customerPayload: updated.toJsonPayload(),
    );

    return updated;
  }

  Future<void> deleteCustomer(String customerId) async {
    final String companyId = _requireCurrentCompanyId();
    final AppDatabase db = ref.read(appDatabaseProvider);
    
    await db.customersDao.deleteCustomer(
      customerId: customerId,
      companyId: companyId,
    );
  }

  // ---------------------------------------------------------------------------
  // Payment & Adjustment (Phase 2 - Still uses Supabase for now)
  // ---------------------------------------------------------------------------

  Future<CustomerPayment> recordPayment({
    required String customerId,
    required double amount,
    required String method,
    String? reference,
    String? notes,
  }) async {
    final String companyId = _requireCurrentCompanyId();

    final CustomerPayment payment =
        await ref.read(customerRepositoryProvider).recordPayment(
              companyId: companyId,
              customerId: customerId,
              amount: amount,
              method: method,
              reference: reference,
              notes: notes,
            );

    ref.invalidate(customerPaymentsProvider(customerId));
    _invalidateStatements();
    // TODO(Phase 2): Move to Drift
    return payment;
  }

  Future<CustomerAdjustment> addAdjustment({
    required String customerId,
    required double amount,
    required String reason,
    String? notes,
  }) async {
    final String companyId = _requireCurrentCompanyId();

    final CustomerAdjustment adjustment =
        await ref.read(customerRepositoryProvider).addAdjustment(
              companyId: companyId,
              customerId: customerId,
              amount: amount,
              reason: reason,
              notes: notes,
            );

    _invalidateStatements();
    // TODO(Phase 2): Move to Drift
    return adjustment;
  }

  String _requireCurrentCompanyId() {
    final CompanyContextState context = ref.read(companyContextProvider);
    final String? companyId = context.currentCompany?.id;
    if (companyId == null) {
      throw const CustomerException(
        type: CustomerFailureType.unauthorized,
        cause: 'No company is currently selected.',
      );
    }
    return companyId;
  }

  void _invalidateStatements() {
    ref.invalidate(customerStatementProvider);
  }
}

final AsyncNotifierProvider<CustomersNotifier, List<Customer>>
    customersProvider =
    AsyncNotifierProvider<CustomersNotifier, List<Customer>>(
  CustomersNotifier.new,
);

// ============================================================================
// باقي الملف (Sales, Returns, etc.) يبقى كما هو تماماً...
// ============================================================================

class CustomerPaymentsNotifier
    extends FamilyAsyncNotifier<List<CustomerPayment>, String> {
  @override
  Future<List<CustomerPayment>> build(String customerId) async {
    if (customerId.isEmpty) {
      return const <CustomerPayment>[];
    }
    return ref.read(customerRepositoryProvider).listPayments(customerId);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final customerPaymentsProvider = AsyncNotifierProvider.family<
    CustomerPaymentsNotifier, List<CustomerPayment>, String>(
  CustomerPaymentsNotifier.new,
);

@immutable
class CustomerStatementArgs extends Equatable {
  const CustomerStatementArgs({
    required this.customerId,
    this.fromDate,
    this.toDate,
  });

  final String customerId;
  final DateTime? fromDate;
  final DateTime? toDate;

  @override
  List<Object?> get props => <Object?>[customerId, fromDate, toDate];

  @override
  String toString() =>
      'CustomerStatementArgs(customerId: $customerId, '
      'fromDate: $fromDate, toDate: $toDate)';
}

class CustomerStatementNotifier
    extends FamilyAsyncNotifier<CustomerStatement, CustomerStatementArgs> {
  @override
  Future<CustomerStatement> build(CustomerStatementArgs args) async {
    if (args.customerId.isEmpty) {
      throw const CustomerException(
        type: CustomerFailureType.notFound,
        cause: 'Cannot build a statement without a customer id.',
      );
    }

    return ref.read(customerRepositoryProvider).buildStatement(
          customerId: args.customerId,
          fromDate: args.fromDate,
          toDate: args.toDate,
        );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final customerStatementProvider = AsyncNotifierProvider.family<
    CustomerStatementNotifier, CustomerStatement, CustomerStatementArgs>(
  CustomerStatementNotifier.new,
);

class SalesNotifier extends AsyncNotifier<List<Sale>> {
  @override
  Future<List<Sale>> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState state) => state.currentCompany?.id,
      ),
    );

    if (companyId == null) {
      return const <Sale>[];
    }

    final SalesCacheService? cache =
        await ref.watch(salesCacheServiceProvider.future);

    try {
      final List<Sale> sales =
          await ref.read(salesRepositoryProvider).listSales(companyId);

      if (cache != null) {
        await cache.save(companyId, sales);
      }

      return sales;
    } on SaleException catch (error) {
      if (error.type == SalesFailureType.network) {
        final List<Sale>? cached = await cache?.load(companyId);
        if (cached != null) return cached;
        return const <Sale>[];
      }
      rethrow;
    }
  }

  Future<Sale> createSale({
    required String branchId,
    String? customerId,
    required DateTime saleDate,
    List<SaleItemDraft> items = const <SaleItemDraft>[],
    String? invoiceNumber,
    double discount = 0,
    double taxAmount = 0,
    double paidAmount = 0,
    String? notes,
  }) async {
    final String companyId = _requireCurrentCompanyId();

    final Sale created = await ref.read(salesRepositoryProvider).createSale(
          companyId: companyId,
          branchId: branchId,
          customerId: customerId,
          saleDate: saleDate,
          items: items,
          invoiceNumber: invoiceNumber,
          discount: discount,
          taxAmount: taxAmount,
          paidAmount: paidAmount,
          notes: notes,
        );

    await _reload();
    return created;
  }

  Future<Sale> updateDraft({
    required String saleId,
    required String branchId,
    String? customerId,
    required DateTime saleDate,
    required List<SaleItemDraft> items,
    String? invoiceNumber,
    double discount = 0,
    double taxAmount = 0,
    double paidAmount = 0,
    String? notes,
  }) async {
    final String companyId = _requireCurrentCompanyId();

    final Sale updated = await ref.read(salesRepositoryProvider).updateDraft(
          saleId: saleId,
          companyId: companyId,
          branchId: branchId,
          customerId: customerId,
          saleDate: saleDate,
          items: items,
          invoiceNumber: invoiceNumber,
          discount: discount,
          taxAmount: taxAmount,
          paidAmount: paidAmount,
          notes: notes,
        );

    ref.invalidate(saleItemsProvider(saleId));
    await _reload();
    return updated;
  }

  Future<Sale> confirmSale(String saleId) async {
    final Sale confirmed =
        await ref.read(salesRepositoryProvider).confirmSale(saleId);

    ref.invalidate(saleItemsProvider(saleId));
    _invalidateSaleReturns(saleId);
    await _reload();
    return confirmed;
  }

  Future<Sale> cancelSale(String saleId) async {
    final Sale cancelled =
        await ref.read(salesRepositoryProvider).cancelSale(saleId);

    ref.invalidate(saleItemsProvider(saleId));
    _invalidateSaleReturns(saleId);
    await _reload();
    return cancelled;
  }

  String _requireCurrentCompanyId() {
    final CompanyContextState context = ref.read(companyContextProvider);
    final String? companyId = context.currentCompany?.id;
    if (companyId == null) {
      throw const SaleException(
        type: SalesFailureType.unauthorized,
        cause: 'No company is currently selected.',
      );
    }
    return companyId;
  }

  void _invalidateSaleReturns(String saleId) {
    ref.invalidate(saleReturnsProvider(saleId));
  }

  Future<void> _reload() async {
    ref.invalidateSelf();
    await future;
  }
}

final AsyncNotifierProvider<SalesNotifier, List<Sale>> salesProvider =
    AsyncNotifierProvider<SalesNotifier, List<Sale>>(SalesNotifier.new);

class SaleItemsNotifier
    extends FamilyAsyncNotifier<List<SaleItem>, String> {
  @override
  Future<List<SaleItem>> build(String saleId) async {
    if (saleId.isEmpty) {
      return const <SaleItem>[];
    }
    return ref.read(salesRepositoryProvider).listSaleItems(saleId);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final saleItemsProvider = AsyncNotifierProvider.family<
    SaleItemsNotifier, List<SaleItem>, String>(SaleItemsNotifier.new);

class ReturnsNotifier extends AsyncNotifier<List<SaleReturn>> {
  @override
  Future<List<SaleReturn>> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState state) => state.currentCompany?.id,
      ),
    );

    if (companyId == null) {
      return const <SaleReturn>[];
    }

    return ref.read(returnsRepositoryProvider).listReturns(companyId);
  }

  Future<SaleReturn> createReturn({
    required String branchId,
    required String saleId,
    String? customerId,
    required DateTime returnDate,
    required List<SaleReturnItemDraft> items,
    String refundMethod = 'credit_note',
    String? notes,
  }) async {
    final String companyId = _requireCurrentCompanyId();

    final SaleReturn created =
        await ref.read(returnsRepositoryProvider).createReturn(
              companyId: companyId,
              branchId: branchId,
              saleId: saleId,
              customerId: customerId,
              returnDate: returnDate,
              items: items,
              refundMethod: refundMethod,
              notes: notes,
            );

    ref.invalidate(saleReturnsProvider(saleId));
    await _reload();
    return created;
  }

  Future<SaleReturn> updateDraft({
    required String returnId,
    required String branchId,
    required String saleId,
    String? customerId,
    required DateTime returnDate,
    required List<SaleReturnItemDraft> items,
    String refundMethod = 'credit_note',
    String? notes,
  }) async {
    final String companyId = _requireCurrentCompanyId();

    final SaleReturn updated =
        await ref.read(returnsRepositoryProvider).updateDraft(
              returnId: returnId,
              companyId: companyId,
              branchId: branchId,
              saleId: saleId,
              customerId: customerId,
              returnDate: returnDate,
              items: items,
              refundMethod: refundMethod,
              notes: notes,
            );

    ref.invalidate(returnItemsProvider(returnId));
    ref.invalidate(saleReturnsProvider(saleId));
    await _reload();
    return updated;
  }

  Future<SaleReturn> confirmReturn({
    required String returnId,
    required String saleId,
  }) async {
    final SaleReturn confirmed =
        await ref.read(returnsRepositoryProvider).confirmReturn(returnId);

    ref.invalidate(returnItemsProvider(returnId));
    ref.invalidate(saleReturnsProvider(saleId));
    ref.invalidate(customerStatementProvider);
    ref.invalidate(customersProvider);
    await _reload();
    return confirmed;
  }

  Future<SaleReturn> cancelReturn({
    required String returnId,
    required String saleId,
  }) async {
    final SaleReturn cancelled =
        await ref.read(returnsRepositoryProvider).cancelReturn(returnId);

    ref.invalidate(returnItemsProvider(returnId));
    ref.invalidate(saleReturnsProvider(saleId));
    ref.invalidate(customerStatementProvider);
    ref.invalidate(customersProvider);
    await _reload();
    return cancelled;
  }

  String _requireCurrentCompanyId() {
    final CompanyContextState context = ref.read(companyContextProvider);
    final String? companyId = context.currentCompany?.id;
    if (companyId == null) {
      throw const ReturnException(
        type: ReturnFailureType.unauthorized,
        cause: 'No company is currently selected.',
      );
    }
    return companyId;
  }

  Future<void> _reload() async {
    ref.invalidateSelf();
    await future;
  }
}

final AsyncNotifierProvider<ReturnsNotifier, List<SaleReturn>>
    returnsProvider =
    AsyncNotifierProvider<ReturnsNotifier, List<SaleReturn>>(
  ReturnsNotifier.new,
);

class ReturnItemsNotifier
    extends FamilyAsyncNotifier<List<SaleReturnItem>, String> {
  @override
  Future<List<SaleReturnItem>> build(String returnId) async {
    if (returnId.isEmpty) {
      return const <SaleReturnItem>[];
    }
    return ref.read(returnsRepositoryProvider).listReturnItems(returnId);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final returnItemsProvider = AsyncNotifierProvider.family<
    ReturnItemsNotifier, List<SaleReturnItem>, String>(
  ReturnItemsNotifier.new,
);

class SaleReturnsNotifier
    extends FamilyAsyncNotifier<List<SaleReturn>, String> {
  @override
  Future<List<SaleReturn>> build(String saleId) async {
    if (saleId.isEmpty) {
      return const <SaleReturn>[];
    }
    return ref.read(returnsRepositoryProvider).listReturnsForSale(saleId);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final saleReturnsProvider = AsyncNotifierProvider.family<
    SaleReturnsNotifier, List<SaleReturn>, String>(
  SaleReturnsNotifier.new,
);

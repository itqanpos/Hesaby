// lib/features/sales/presentation/providers/sales_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../data/datasources/sales_remote_datasource.dart';
import '../../data/repositories/sales_repository_impl.dart';
import '../../domain/entities/sale_entities.dart';
import '../../domain/repositories/sales_repository.dart';

// ============================================================================
// Repository providers
// ============================================================================

/// The application's customer repository.
final Provider<CustomerRepository> customerRepositoryProvider =
    Provider<CustomerRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return CustomerRepositoryImpl(SalesRemoteDataSource(client));
});

/// The application's sales repository.
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

// ============================================================================
// Customers
// ============================================================================

/// Provides the list of customers for the currently selected company.
///
/// The notifier reloads automatically whenever [companyContextProvider]
/// reports a different `currentCompany.id`. When no company is selected, it
/// resolves to an empty list.
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

    return ref.read(customerRepositoryProvider).listCustomers(companyId);
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

    final Customer created =
        await ref.read(customerRepositoryProvider).createCustomer(
              companyId: companyId,
              name: name,
              code: code,
              phone: phone,
              email: email,
              address: address,
              notes: notes,
            );

    await _reload();
    return created;
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
    final Customer updated =
        await ref.read(customerRepositoryProvider).updateCustomer(
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

    await _reload();
    return updated;
  }

  Future<void> deleteCustomer(String customerId) async {
    await ref.read(customerRepositoryProvider).deleteCustomer(customerId);
    await _reload();
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

  Future<void> _reload() async {
    ref.invalidateSelf();
    await future;
  }
}

/// Provides the current company's customers.
final AsyncNotifierProvider<CustomersNotifier, List<Customer>>
    customersProvider =
    AsyncNotifierProvider<CustomersNotifier, List<Customer>>(
  CustomersNotifier.new,
);

// ============================================================================
// Sales
// ============================================================================

/// Provides the list of sales for the currently selected company.
///
/// Note on naming: [AsyncNotifier] already declares `update`. Business
/// operations are therefore named `createSale`, `updateDraft`,
/// `confirmSale` and `cancelSale`.
///
/// A sale may be associated with a registered customer (`customerId` not
/// null) or with no customer at all — a cash sale. The POS uses the latter
/// by default.
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

    return ref.read(salesRepositoryProvider).listSales(companyId);
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

    // The new sale has just been created; no items provider exists yet for
    // its id, so no per-id invalidation is needed here.
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
    await _reload();
    return confirmed;
  }

  Future<Sale> cancelSale(String saleId) async {
    final Sale cancelled =
        await ref.read(salesRepositoryProvider).cancelSale(saleId);

    ref.invalidate(saleItemsProvider(saleId));
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

  Future<void> _reload() async {
    ref.invalidateSelf();
    await future;
  }
}

/// Provides the current company's sales.
final AsyncNotifierProvider<SalesNotifier, List<Sale>> salesProvider =
    AsyncNotifierProvider<SalesNotifier, List<Sale>>(SalesNotifier.new);

// ============================================================================
// Sale items (per sale)
// ============================================================================

/// Provides the line items of a single sale, keyed by `saleId`.
///
/// This is a read-only derived view over `sale_items`. It is invalidated
/// explicitly by [SalesNotifier] after any mutation that touches the sale's
/// lines (`updateDraft`, `confirmSale`, `cancelSale`).
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

/// Provides the line items of a single sale, keyed by `saleId`.
///
/// No explicit type annotation is used: `AsyncNotifierProvider.family` is a
/// factory constructor, not a type. Dart infers the correct
/// `AsyncNotifierProviderFamily<...>` from the value expression.
final saleItemsProvider = AsyncNotifierProvider.family<
    SaleItemsNotifier, List<SaleItem>, String>(SaleItemsNotifier.new);

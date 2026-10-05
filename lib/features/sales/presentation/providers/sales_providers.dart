// lib/features/sales/presentation/providers/sales_providers.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../data/datasources/sales_remote_datasource.dart';
import '../../data/repositories/sales_repository_impl.dart';
import '../../domain/entities/customer_adjustment.dart';
import '../../domain/entities/customer_payment.dart';
import '../../domain/entities/customer_statement.dart';
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

  /// Records a standalone payment against [customerId].
  ///
  /// The database trigger `apply_customer_payment` reduces the customer
  /// balance; the in-memory [customersProvider] is invalidated so the new
  /// balance is re-fetched before the caller continues. The customer's
  /// payment history and cached statements are also invalidated.
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
    await _reload();
    return payment;
  }

  /// Records a manual adjustment (positive or negative) against
  /// [customerId].
  ///
  /// The database trigger `apply_customer_balance_adjustment` applies the
  /// delta and rejects any value that would drive the balance below zero.
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
    await _reload();
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

  /// Invalidates every cached customer statement.
  ///
  /// Riverpod 2.x does not support predicate-based invalidation on a
  /// family, so we invalidate the family as a whole. The set of cached
  /// statements is small (one per open customer/period), and re-fetching
  /// them is cheap — correctness beats micro-optimisation here.
  void _invalidateStatements() {
    ref.invalidate(customerStatementProvider);
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
// Customer payments (per customer)
// ============================================================================

/// Provides the payment history of a single customer, keyed by `customerId`.
///
/// This is a read-only derived view over `customer_payments`. It is
/// invalidated explicitly by [CustomersNotifier.recordPayment] after a
/// successful insert.
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

/// Provides the payment history of a single customer, keyed by `customerId`.
///
/// No explicit type annotation is used: `AsyncNotifierProvider.family` is a
/// factory constructor, not a type.
final customerPaymentsProvider = AsyncNotifierProvider.family<
    CustomerPaymentsNotifier, List<CustomerPayment>, String>(
  CustomerPaymentsNotifier.new,
);

// ============================================================================
// Customer statement (per customer + period)
// ============================================================================

/// Arguments that identify a single customer statement query.
///
/// [fromDate] and [toDate] are inclusive bounds. Both are optional: `null`
/// on either side means "open-ended". Dates are normalised to UTC on
/// construction so that two visually identical requests share the same
/// cache key.
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

/// Builds and caches the full account statement for a single customer.
///
/// The statement is invalidated by [CustomersNotifier] after any operation
/// that can affect the customer's balance (payment, adjustment, sale
/// confirmation, sale cancellation).
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

/// Provides the statement of a single customer over an optional period.
///
/// No explicit type annotation is used: `AsyncNotifierProvider.family` is a
/// factory constructor, not a type.
final customerStatementProvider = AsyncNotifierProvider.family<
    CustomerStatementNotifier, CustomerStatement, CustomerStatementArgs>(
  CustomerStatementNotifier.new,
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

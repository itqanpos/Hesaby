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
import '../../domain/entities/sale_return.dart';
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

/// The application's returns repository.
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

// ============================================================================
// Customers
// ============================================================================

/// Provides the list of customers for the currently selected company.
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

// ============================================================================
// Customer statement (per customer + period)
// ============================================================================

/// Arguments that identify a single customer statement query.
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

// ============================================================================
// Sales
// ============================================================================

/// Provides the list of sales for the currently selected company.
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

  /// Invalidates the returns list attached to [saleId] so that the
  /// remaining returnable quantity shown in any open return dialog is
  /// refreshed after a sale confirmation or cancellation.
  void _invalidateSaleReturns(String saleId) {
    ref.invalidate(saleReturnsProvider(saleId));
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

// ============================================================================
// Returns (per company)
// ============================================================================

/// Provides the list of sale returns for the currently selected company.
///
/// The notifier reloads automatically whenever [companyContextProvider]
/// reports a different `currentCompany.id`. When no company is selected it
/// resolves to an empty list.
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

  /// Creates a draft return and invalidates any provider derived from it.
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

  /// Replaces the header and items of a draft return.
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

  /// Confirms a draft return.
  ///
  /// The database trigger creates the `return_in` stock movements and,
  /// when the refund method is `credit_note`, reduces the customer
  /// balance. Both the customer list and any open statement are
  /// invalidated afterwards so the UI reflects the new balance.
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

  /// Cancels a draft or confirmed return.
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

/// Provides the current company's sale returns.
final AsyncNotifierProvider<ReturnsNotifier, List<SaleReturn>>
    returnsProvider =
    AsyncNotifierProvider<ReturnsNotifier, List<SaleReturn>>(
  ReturnsNotifier.new,
);

// ============================================================================
// Return items (per return)
// ============================================================================

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

// ============================================================================
// Returns for a specific sale (per sale)
// ============================================================================

/// Lists every return (draft, confirmed, or cancelled) recorded against a
/// specific sale. Used by the return creation dialog to compute the
/// remaining returnable quantity per sale item.
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

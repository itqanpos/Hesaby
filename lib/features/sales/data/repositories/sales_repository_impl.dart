// lib/features/sales/data/repositories/sales_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/sale_entities.dart';
import '../../domain/repositories/sales_repository.dart';
import '../datasources/sales_remote_datasource.dart';
import '../models/sale_models.dart';

// ============================================================================
// CustomerRepositoryImpl
// ============================================================================

/// Concrete implementation of [CustomerRepository] backed by Supabase.
class CustomerRepositoryImpl implements CustomerRepository {
  const CustomerRepositoryImpl(this._remoteDataSource);

  final SalesRemoteDataSource _remoteDataSource;

  @override
  Future<List<Customer>> listCustomers(
    String companyId, {
    bool includeInactive = false,
  }) async {
    try {
      final List<CustomerModel> models =
          await _remoteDataSource.listCustomers(
        companyId,
        includeInactive: includeInactive,
      );
      return models
          .map((CustomerModel model) => model.toEntity())
          .toList(growable: false);
    } on FormatException catch (error, stackTrace) {
      throw _mapCustomerInvalidResponse(
        error,
        stackTrace,
        operation: 'listCustomers',
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapCustomerPostgrest(
        error,
        stackTrace,
        operation: 'listCustomers',
      );
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapCustomerAuth(error, stackTrace, operation: 'listCustomers');
    } on CustomerException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapCustomerUnknown(error, stackTrace, operation: 'listCustomers');
    }
  }

  @override
  Future<Customer> getCustomer(String customerId) async {
    try {
      final CustomerModel model =
          await _remoteDataSource.getCustomer(customerId);
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapCustomerInvalidResponse(
        error,
        stackTrace,
        operation: 'getCustomer',
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapCustomerPostgrest(
        error,
        stackTrace,
        operation: 'getCustomer',
      );
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapCustomerAuth(error, stackTrace, operation: 'getCustomer');
    } on CustomerException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapCustomerUnknown(error, stackTrace, operation: 'getCustomer');
    }
  }

  @override
  Future<Customer> createCustomer({
    required String companyId,
    required String name,
    String? code,
    String? phone,
    String? email,
    String? address,
    String? notes,
  }) async {
    try {
      final CustomerModel model = await _remoteDataSource.createCustomer(
        companyId: companyId,
        name: name,
        code: code,
        phone: phone,
        email: email,
        address: address,
        notes: notes,
      );
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapCustomerInvalidResponse(
        error,
        stackTrace,
        operation: 'createCustomer',
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapCustomerPostgrest(
        error,
        stackTrace,
        operation: 'createCustomer',
      );
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapCustomerAuth(error, stackTrace, operation: 'createCustomer');
    } on CustomerException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapCustomerUnknown(
        error,
        stackTrace,
        operation: 'createCustomer',
      );
    }
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
  }) async {
    try {
      final CustomerModel model = await _remoteDataSource.updateCustomer(
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
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapCustomerInvalidResponse(
        error,
        stackTrace,
        operation: 'updateCustomer',
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapCustomerPostgrest(
        error,
        stackTrace,
        operation: 'updateCustomer',
      );
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapCustomerAuth(error, stackTrace, operation: 'updateCustomer');
    } on CustomerException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapCustomerUnknown(
        error,
        stackTrace,
        operation: 'updateCustomer',
      );
    }
  }

  @override
  Future<void> deleteCustomer(String customerId) async {
    try {
      await _remoteDataSource.deleteCustomer(customerId);
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapCustomerPostgrest(
        error,
        stackTrace,
        operation: 'deleteCustomer',
      );
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapCustomerAuth(error, stackTrace, operation: 'deleteCustomer');
    } on CustomerException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapCustomerUnknown(
        error,
        stackTrace,
        operation: 'deleteCustomer',
      );
    }
  }
}

// ============================================================================
// SalesRepositoryImpl
// ============================================================================

/// Concrete implementation of [SalesRepository] backed by Supabase.
class SalesRepositoryImpl implements SalesRepository {
  const SalesRepositoryImpl(this._remoteDataSource);

  final SalesRemoteDataSource _remoteDataSource;

  @override
  Future<List<Sale>> listSales(
    String companyId, {
    String? branchId,
    String? status,
    int? limit,
  }) async {
    try {
      final List<SaleModel> models = await _remoteDataSource.listSales(
        companyId,
        branchId: branchId,
        status: status,
        limit: limit,
      );
      return models
          .map((SaleModel model) => model.toEntity())
          .toList(growable: false);
    } on FormatException catch (error, stackTrace) {
      throw _mapSaleInvalidResponse(error, stackTrace, operation: 'listSales');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapSalePostgrest(error, stackTrace, operation: 'listSales');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapSaleAuth(error, stackTrace, operation: 'listSales');
    } on SaleException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapSaleUnknown(error, stackTrace, operation: 'listSales');
    }
  }

  @override
  Future<Sale> getSale(String saleId) async {
    try {
      final SaleModel model = await _remoteDataSource.getSale(saleId);
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapSaleInvalidResponse(error, stackTrace, operation: 'getSale');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapSalePostgrest(error, stackTrace, operation: 'getSale');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapSaleAuth(error, stackTrace, operation: 'getSale');
    } on SaleException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapSaleUnknown(error, stackTrace, operation: 'getSale');
    }
  }

  @override
  Future<List<SaleItem>> listSaleItems(String saleId) async {
    try {
      final List<SaleItemModel> models =
          await _remoteDataSource.listSaleItems(saleId);
      return models
          .map((SaleItemModel model) => model.toEntity())
          .toList(growable: false);
    } on FormatException catch (error, stackTrace) {
      throw _mapSaleInvalidResponse(
        error,
        stackTrace,
        operation: 'listSaleItems',
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapSalePostgrest(error, stackTrace, operation: 'listSaleItems');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapSaleAuth(error, stackTrace, operation: 'listSaleItems');
    } on SaleException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapSaleUnknown(error, stackTrace, operation: 'listSaleItems');
    }
  }

  @override
  Future<Sale> createSale({
    required String companyId,
    required String branchId,
    required String customerId,
    required DateTime saleDate,
    List<SaleItemDraft> items = const <SaleItemDraft>[],
    String? invoiceNumber,
    double discount = 0,
    double taxAmount = 0,
    double paidAmount = 0,
    String? notes,
  }) async {
    try {
      final SaleModel model = await _remoteDataSource.createSale(
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
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapSaleInvalidResponse(
        error,
        stackTrace,
        operation: 'createSale',
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapSalePostgrest(error, stackTrace, operation: 'createSale');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapSaleAuth(error, stackTrace, operation: 'createSale');
    } on SaleException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapSaleUnknown(error, stackTrace, operation: 'createSale');
    }
  }

  @override
  Future<Sale> updateDraft({
    required String saleId,
    required String companyId,
    required String branchId,
    required String customerId,
    required DateTime saleDate,
    required List<SaleItemDraft> items,
    String? invoiceNumber,
    double discount = 0,
    double taxAmount = 0,
    double paidAmount = 0,
    String? notes,
  }) async {
    try {
      final SaleModel model = await _remoteDataSource.updateDraft(
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
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapSaleInvalidResponse(error, stackTrace, operation: 'updateDraft');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapSalePostgrest(error, stackTrace, operation: 'updateDraft');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapSaleAuth(error, stackTrace, operation: 'updateDraft');
    } on SaleException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapSaleUnknown(error, stackTrace, operation: 'updateDraft');
    }
  }

  @override
  Future<Sale> confirmSale(String saleId) async {
    try {
      final SaleModel model = await _remoteDataSource.confirmSale(saleId);
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapSaleInvalidResponse(
        error,
        stackTrace,
        operation: 'confirmSale',
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapSalePostgrest(error, stackTrace, operation: 'confirmSale');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapSaleAuth(error, stackTrace, operation: 'confirmSale');
    } on SaleException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapSaleUnknown(error, stackTrace, operation: 'confirmSale');
    }
  }

  @override
  Future<Sale> cancelSale(String saleId) async {
    try {
      final SaleModel model = await _remoteDataSource.cancelSale(saleId);
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapSaleInvalidResponse(
        error,
        stackTrace,
        operation: 'cancelSale',
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapSalePostgrest(error, stackTrace, operation: 'cancelSale');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapSaleAuth(error, stackTrace, operation: 'cancelSale');
    } on SaleException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapSaleUnknown(error, stackTrace, operation: 'cancelSale');
    }
  }
}

// ============================================================================
// Customer error mapping
// ============================================================================

CustomerException _mapCustomerInvalidResponse(
  FormatException error,
  StackTrace stackTrace, {
  required String operation,
}) {
  AppLogger.error(
    'Customer invalid response during "$operation" (FormatException).',
    error,
    stackTrace,
  );
  return CustomerException(
    type: CustomerFailureType.invalidResponse,
    cause: error,
    stackTrace: stackTrace,
  );
}

CustomerException _mapCustomerPostgrest(
  supabase.PostgrestException error,
  StackTrace stackTrace, {
  required String operation,
}) {
  final CustomerFailureType type = _classifyCustomerPostgrest(error);

  AppLogger.warning(
    'Customer PostgREST error during "$operation" mapped to ${type.name} '
    '(code: ${error.code ?? 'n/a'}).',
  );

  return CustomerException(
    type: type,
    cause: error,
    stackTrace: stackTrace,
  );
}

CustomerException _mapCustomerAuth(
  supabase.AuthException error,
  StackTrace stackTrace, {
  required String operation,
}) {
  AppLogger.warning(
    'Customer auth error during "$operation" mapped to unauthorized '
    '(code: ${error.code ?? 'n/a'}).',
  );
  return CustomerException(
    type: CustomerFailureType.unauthorized,
    cause: error,
    stackTrace: stackTrace,
  );
}

CustomerException _mapCustomerUnknown(
  Object error,
  StackTrace stackTrace, {
  required String operation,
}) {
  final CustomerFailureType type = _looksLikeNetworkFailure(error)
      ? CustomerFailureType.network
      : CustomerFailureType.unknown;

  AppLogger.error(
    'Unhandled customer error during "$operation" '
    '(runtimeType: ${error.runtimeType}, mapped: ${type.name}).',
    error,
    stackTrace,
  );

  return CustomerException(
    type: type,
    cause: error,
    stackTrace: stackTrace,
  );
}

/// Classifies a PostgREST error into a safe [CustomerFailureType].
///
/// Constraint names referenced below are declared in the Phase 8 migration:
/// * `customers_company_name_unique` → nameConflict
/// * `uniq_customers_company_code`   → codeConflict
/// * `uniq_customers_company_phone`  → phoneConflict
/// * `sales_customer_company_fk`     → inUse (customer referenced by a sale)
CustomerFailureType _classifyCustomerPostgrest(
  supabase.PostgrestException error,
) {
  final String code = (error.code ?? '').toUpperCase();
  final String message = error.message.toLowerCase();
  final String full = error.toString().toLowerCase();

  if (code == '23505') {
    if (full.contains('uniq_customers_company_code')) {
      return CustomerFailureType.codeConflict;
    }
    if (full.contains('uniq_customers_company_phone')) {
      return CustomerFailureType.phoneConflict;
    }
    return CustomerFailureType.nameConflict;
  }

  if (code == '23503') {
    return CustomerFailureType.inUse;
  }

  if (code == 'PGRST116') {
    return CustomerFailureType.notFound;
  }

  if (code.startsWith('42501') || code.startsWith('28')) {
    return CustomerFailureType.unauthorized;
  }

  if (code.startsWith('42')) {
    return CustomerFailureType.invalidResponse;
  }

  if (message.contains('permission denied') ||
      message.contains('row level security') ||
      message.contains('jwt')) {
    return CustomerFailureType.unauthorized;
  }

  if (full.contains('uniq_customers_company_code')) {
    return CustomerFailureType.codeConflict;
  }
  if (full.contains('uniq_customers_company_phone')) {
    return CustomerFailureType.phoneConflict;
  }
  if (full.contains('customers_company_name_unique')) {
    return CustomerFailureType.nameConflict;
  }

  if (message.contains('duplicate key') ||
      message.contains('unique constraint')) {
    return CustomerFailureType.nameConflict;
  }

  if (message.contains('foreign key') ||
      message.contains('violates foreign key')) {
    return CustomerFailureType.inUse;
  }

  if (_messageLooksLikeNetwork(message)) {
    return CustomerFailureType.network;
  }

  return CustomerFailureType.unknown;
}

// ============================================================================
// Sale error mapping
// ============================================================================

SaleException _mapSaleInvalidResponse(
  FormatException error,
  StackTrace stackTrace, {
  required String operation,
}) {
  AppLogger.error(
    'Sale invalid response during "$operation" (FormatException).',
    error,
    stackTrace,
  );
  return SaleException(
    type: SalesFailureType.invalidResponse,
    cause: error,
    stackTrace: stackTrace,
  );
}

SaleException _mapSalePostgrest(
  supabase.PostgrestException error,
  StackTrace stackTrace, {
  required String operation,
}) {
  final SalesFailureType type = _classifySalePostgrest(error);

  AppLogger.warning(
    'Sale PostgREST error during "$operation" mapped to ${type.name} '
    '(code: ${error.code ?? 'n/a'}).',
  );

  return SaleException(
    type: type,
    cause: error,
    stackTrace: stackTrace,
  );
}

SaleException _mapSaleAuth(
  supabase.AuthException error,
  StackTrace stackTrace, {
  required String operation,
}) {
  AppLogger.warning(
    'Sale auth error during "$operation" mapped to unauthorized '
    '(code: ${error.code ?? 'n/a'}).',
  );
  return SaleException(
    type: SalesFailureType.unauthorized,
    cause: error,
    stackTrace: stackTrace,
  );
}

SaleException _mapSaleUnknown(
  Object error,
  StackTrace stackTrace, {
  required String operation,
}) {
  final SalesFailureType type = _looksLikeNetworkFailure(error)
      ? SalesFailureType.network
      : SalesFailureType.unknown;

  AppLogger.error(
    'Unhandled sale error during "$operation" '
    '(runtimeType: ${error.runtimeType}, mapped: ${type.name}).',
    error,
    stackTrace,
  );

  return SaleException(
    type: type,
    cause: error,
    stackTrace: stackTrace,
  );
}

/// Classifies a PostgREST error into a safe [SalesFailureType].
///
/// Codes handled explicitly:
/// * `23505` unique_violation              → invoiceNumberConflict
/// * `23503` foreign_key_violation         → customerNotFound /
///   branchNotFound / productNotFound / unitNotFound
/// * `23514` check_violation               → invalidStatusTransition /
///   emptySale / insufficientStock / invalidPayment
///   (message-based; the triggers raise specific sentences)
/// * `PGRST116` no rows / multiple for single() → notFound
/// * `42501` / `28xxx`                     → unauthorized
/// * `42xxx`                               → invalidResponse
SalesFailureType _classifySalePostgrest(
  supabase.PostgrestException error,
) {
  final String code = (error.code ?? '').toUpperCase();
  final String message = error.message.toLowerCase();
  final String full = error.toString().toLowerCase();

  // --- Integrity: unique violations -----------------------------------------
  if (code == '23505') {
    if (full.contains('uniq_sales_company_invoice_number') ||
        message.contains('invoice_number')) {
      return SalesFailureType.invoiceNumberConflict;
    }
    return SalesFailureType.invalidResponse;
  }

  // --- Integrity: foreign key violations ------------------------------------
  if (code == '23503') {
    if (full.contains('sales_customer_company_fk')) {
      return SalesFailureType.customerNotFound;
    }
    if (full.contains('sales_branch_company_fk')) {
      return SalesFailureType.branchNotFound;
    }
    if (full.contains('sale_items_product_company_fk')) {
      return SalesFailureType.productNotFound;
    }
    if (full.contains('sale_items_unit_company_fk')) {
      return SalesFailureType.unitNotFound;
    }
    if (full.contains('sale_items_sale_company_fk')) {
      return SalesFailureType.notFound;
    }
    return SalesFailureType.notFound;
  }

  // --- Integrity: check violations (business rules) -------------------------
  if (code == '23514') {
    // Insufficient stock during confirmation is raised by the Phase 5
    // trigger with a stable leading sentence.
    if (message.contains('insufficient stock') ||
        full.contains('insufficient stock')) {
      return SalesFailureType.insufficientStock;
    }
    if (message.contains('without items') ||
        full.contains('cannot confirm sale')) {
      return SalesFailureType.emptySale;
    }
    // The payment CHECK is named; look for it explicitly.
    if (full.contains('sales_paid_amount_not_exceeding_total') ||
        message.contains('paid_amount')) {
      return SalesFailureType.invalidPayment;
    }
    if (message.contains('invalid sale status transition') ||
        message.contains('cannot modify a') ||
        message.contains('must be created with status = draft') ||
        message.contains('cannot modify items of a')) {
      return SalesFailureType.invalidStatusTransition;
    }
    return SalesFailureType.invalidStatusTransition;
  }

  // --- Not found ------------------------------------------------------------
  if (code == 'PGRST116') {
    return SalesFailureType.notFound;
  }

  // --- Authorization --------------------------------------------------------
  if (code.startsWith('42501') || code.startsWith('28')) {
    return SalesFailureType.unauthorized;
  }

  // --- Syntax / undefined objects -------------------------------------------
  if (code.startsWith('42')) {
    return SalesFailureType.invalidResponse;
  }

  // --- Textual fallbacks ----------------------------------------------------
  if (message.contains('permission denied') ||
      message.contains('row level security') ||
      message.contains('jwt')) {
    return SalesFailureType.unauthorized;
  }

  if (message.contains('insufficient stock')) {
    return SalesFailureType.insufficientStock;
  }
  if (message.contains('without items')) {
    return SalesFailureType.emptySale;
  }
  if (message.contains('invalid sale status transition') ||
      message.contains('cannot modify a') ||
      message.contains('cannot modify items of a')) {
    return SalesFailureType.invalidStatusTransition;
  }

  if (full.contains('uniq_sales_company_invoice_number')) {
    return SalesFailureType.invoiceNumberConflict;
  }
  if (full.contains('sales_paid_amount_not_exceeding_total')) {
    return SalesFailureType.invalidPayment;
  }
  if (full.contains('sales_customer_company_fk')) {
    return SalesFailureType.customerNotFound;
  }
  if (full.contains('sales_branch_company_fk')) {
    return SalesFailureType.branchNotFound;
  }
  if (full.contains('sale_items_product_company_fk')) {
    return SalesFailureType.productNotFound;
  }
  if (full.contains('sale_items_unit_company_fk')) {
    return SalesFailureType.unitNotFound;
  }

  if (message.contains('duplicate key') ||
      message.contains('unique constraint')) {
    return SalesFailureType.invoiceNumberConflict;
  }

  if (message.contains('foreign key') ||
      message.contains('violates foreign key')) {
    return SalesFailureType.notFound;
  }

  if (_messageLooksLikeNetwork(message)) {
    return SalesFailureType.network;
  }

  return SalesFailureType.unknown;
}

// ============================================================================
// Shared helpers
// ============================================================================

bool _looksLikeNetworkFailure(Object error) {
  final String description = error.toString().toLowerCase();
  return _messageLooksLikeNetwork(description);
}

bool _messageLooksLikeNetwork(String value) {
  return value.contains('socket') ||
      value.contains('network') ||
      value.contains('connection') ||
      value.contains('timeout') ||
      value.contains('timed out') ||
      value.contains('unreachable') ||
      value.contains('failed host lookup') ||
      value.contains('clientexception');
}

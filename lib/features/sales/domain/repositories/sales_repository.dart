// lib/features/sales/domain/repositories/sales_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/sale_entities.dart';

// ============================================================================
// Customer repository
// ============================================================================

/// Categories of failures raised by [CustomerRepository] operations.
enum CustomerFailureType {
  network,
  unauthorized,
  notFound,
  nameConflict,
  codeConflict,
  phoneConflict,
  inUse,
  invalidResponse,
  unknown,
}

/// Domain-level exception raised by [CustomerRepository] operations.
@immutable
class CustomerException extends Equatable implements Exception {
  const CustomerException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  final CustomerFailureType type;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'CustomerException(type: ${type.name})';
}

/// Contract for customer operations.
abstract interface class CustomerRepository {
  Future<List<Customer>> listCustomers(
    String companyId, {
    bool includeInactive = false,
  });

  Future<Customer> getCustomer(String customerId);

  Future<Customer> createCustomer({
    required String companyId,
    required String name,
    String? code,
    String? phone,
    String? email,
    String? address,
    String? notes,
  });

  /// Passing `null` for a nullable parameter leaves it unchanged, except for
  /// the five nullable fields that carry an explicit `clear*` flag:
  /// `code`, `phone`, `email`, `address`, `notes`.
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
  });

  /// Deletes a customer.
  ///
  /// Throws [CustomerException] with type [CustomerFailureType.inUse] when
  /// sales still reference the customer.
  Future<void> deleteCustomer(String customerId);
}

// ============================================================================
// Sales repository
// ============================================================================

/// Categories of failures raised by [SalesRepository] operations.
enum SalesFailureType {
  network,
  unauthorized,
  notFound,
  invalidStatusTransition,
  emptySale,
  invoiceNumberConflict,
  customerNotFound,
  branchNotFound,
  productNotFound,
  unitNotFound,
  insufficientStock,
  invalidPayment,
  invalidResponse,
  unknown,
}

/// Domain-level exception raised by [SalesRepository] operations.
@immutable
class SaleException extends Equatable implements Exception {
  const SaleException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  final SalesFailureType type;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'SaleException(type: ${type.name})';
}

/// Contract for sale operations.
///
/// State machine:
/// A sale is always created in `draft`. Its header and items may only be
/// modified while it remains in `draft`. [confirmSale] transitions it to
/// `confirmed` and (via the database trigger) generates the corresponding
/// `sale_out` stock movements. [cancelSale] transitions it to `cancelled`,
/// generating reverse `return_in` movements if it was previously confirmed.
abstract interface class SalesRepository {
  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  /// Returns sales of [companyId], most recent first.
  ///
  /// [branchId] and [status] narrow the result when supplied. [limit] caps
  /// the number of rows returned; the data source applies a conservative
  /// default when omitted.
  Future<List<Sale>> listSales(
    String companyId, {
    String? branchId,
    String? status,
    int? limit,
  });

  /// Returns the header of a single sale.
  Future<Sale> getSale(String saleId);

  /// Returns the line items of [saleId].
  Future<List<SaleItem>> listSaleItems(String saleId);

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  /// Creates a new draft sale with its items, in a single logical operation.
  ///
  /// The sale is always created with `status = draft`; the database enforces
  /// this. [paidAmount] is validated by the database to never exceed the
  /// computed [total]; the payment status is derived automatically.
Future<Sale> createSale({
  required String companyId,
  required String branchId,
  String? customerId,           // ← nullable
  required DateTime saleDate,
  ...
});

Future<Sale> updateDraft({
  required String saleId,
  required String companyId,
  required String branchId,
  String? customerId,           // ← nullable
  required DateTime saleDate,
  ...
});
  /// Confirms a draft sale.
  ///
  /// The database trigger inserts the corresponding `sale_out` stock
  /// movements. A sale with no items is rejected with
  /// [SalesFailureType.emptySale]. Insufficient stock aborts the operation
  /// with [SalesFailureType.insufficientStock].
  Future<Sale> confirmSale(String saleId);

  /// Cancels a sale.
  ///
  /// A draft sale is cancelled without touching stock. A confirmed sale has
  /// its movements reversed (via `return_in`).
  Future<Sale> cancelSale(String saleId);
}

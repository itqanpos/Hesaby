// lib/features/sales/domain/repositories/sales_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/customer_adjustment.dart';
import '../entities/customer_payment.dart';
import '../entities/customer_statement.dart';
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
  invalidAmount,
  insufficientBalance,
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
///
/// Payment and adjustment operations are grouped here (rather than in a
/// dedicated repository) because they mutate `customers.balance` directly
/// via dedicated database triggers and are always scoped to a single
/// customer.
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

  Future<void> deleteCustomer(String customerId);

  // ---------------------------------------------------------------------------
  // Payments
  // ---------------------------------------------------------------------------

  /// Returns the most recent payments recorded for [customerId].
  ///
  /// The list is ordered by `created_at DESC`. When [limit] is null or
  /// non-positive, a sensible default is applied by the data source.
  Future<List<CustomerPayment>> listPayments(
    String customerId, {
    int? limit,
  });

  /// Records a standalone payment against the customer's balance.
  ///
  /// The database trigger `apply_customer_payment` reduces
  /// `customers.balance` by [amount] immediately after the row is inserted.
  /// The amount must be strictly positive; the DB enforces this with a
  /// `CHECK` constraint, and callers are expected to validate it before
  /// submitting.
  Future<CustomerPayment> recordPayment({
    required String companyId,
    required String customerId,
    required double amount,
    required String method,
    String? reference,
    String? notes,
  });

  // ---------------------------------------------------------------------------
  // Adjustments
  // ---------------------------------------------------------------------------

  /// Returns the manual adjustments recorded for [customerId].
  ///
  /// When [fromDate] / [toDate] are provided they act as an inclusive
  /// window on `created_at`. The list is ordered by `created_at DESC`.
  Future<List<CustomerAdjustment>> listAdjustments(
    String customerId, {
    DateTime? fromDate,
    DateTime? toDate,
  });

  /// Records a manual adjustment (positive or negative) to the customer
  /// balance.
  ///
  /// The database trigger `apply_customer_balance_adjustment` applies the
  /// delta. A negative amount that would drive the balance below zero is
  /// rejected by the trigger, which raises a `23514` error that the
  /// repository maps to [CustomerFailureType.insufficientBalance].
  Future<CustomerAdjustment> addAdjustment({
    required String companyId,
    required String customerId,
    required double amount,
    required String reason,
    String? notes,
  });

  // ---------------------------------------------------------------------------
  // Statement
  // ---------------------------------------------------------------------------

  /// Builds a full account statement for [customerId].
  ///
  /// The statement merges three sources:
  /// * confirmed sales (and their reversal on cancellation),
  /// * standalone payments,
  /// * manual adjustments,
  ///
  /// then computes the running balance and derives the opening balance so
  /// that `closingBalance - openingBalance = totalDebit - totalCredit`.
  ///
  /// When [fromDate] / [toDate] are provided they restrict the **visible
  /// entries**; the opening balance continues to reflect everything that
  /// happened before [fromDate], so the final `closingBalance` always
  /// matches the customer's current balance.
  Future<CustomerStatement> buildStatement({
    required String customerId,
    DateTime? fromDate,
    DateTime? toDate,
  });
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

  Future<List<Sale>> listSales(
    String companyId, {
    String? branchId,
    String? status,
    int? limit,
  });

  Future<Sale> getSale(String saleId);

  Future<List<SaleItem>> listSaleItems(String saleId);

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  Future<Sale> createSale({
    required String companyId,
    required String branchId,
    String? customerId,
    required DateTime saleDate,
    List<SaleItemDraft> items,
    String? invoiceNumber,
    double discount,
    double taxAmount,
    double paidAmount,
    String? notes,
  });

  Future<Sale> updateDraft({
    required String saleId,
    required String companyId,
    required String branchId,
    String? customerId,
    required DateTime saleDate,
    required List<SaleItemDraft> items,
    String? invoiceNumber,
    double discount,
    double taxAmount,
    double paidAmount,
    String? notes,
  });

  Future<Sale> confirmSale(String saleId);

  Future<Sale> cancelSale(String saleId);
}

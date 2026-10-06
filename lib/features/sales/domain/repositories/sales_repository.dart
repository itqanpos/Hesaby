// lib/features/sales/domain/repositories/sales_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/customer_adjustment.dart';
import '../entities/customer_payment.dart';
import '../entities/customer_statement.dart';
import '../entities/sale_entities.dart';
import '../entities/sale_return.dart';

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

  Future<List<CustomerPayment>> listPayments(
    String customerId, {
    int? limit,
  });

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

  Future<List<CustomerAdjustment>> listAdjustments(
    String customerId, {
    DateTime? fromDate,
    DateTime? toDate,
  });

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
abstract interface class SalesRepository {
  Future<List<Sale>> listSales(
    String companyId, {
    String? branchId,
    String? status,
    int? limit,
  });

  Future<Sale> getSale(String saleId);

  Future<List<SaleItem>> listSaleItems(String saleId);

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

// ============================================================================
// Returns repository
// ============================================================================

/// Categories of failures raised by [ReturnsRepository] operations.
enum ReturnFailureType {
  network,
  unauthorized,
  notFound,

  /// The parent sale is not in a state that allows returns (must be
  /// `confirmed`).
  saleNotConfirmed,

  /// A return was created without any items, or confirmed while empty.
  emptyReturn,

  /// The requested quantity exceeds the remaining returnable quantity on
  /// the underlying sale item.
  excessiveQuantity,

  /// A `credit_note` refund was requested without an attached customer.
  creditNoteRequiresCustomer,

  /// The return is not in a state that allows the requested operation.
  invalidStatusTransition,

  /// A confirmed return was modified in a way other than adding notes.
  immutableConfirmedReturn,

  /// Reference lookup failure: one of the underlying rows is missing.
  referenceNotFound,

  invalidResponse,
  unknown,
}

/// Domain-level exception raised by [ReturnsRepository] operations.
@immutable
class ReturnException extends Equatable implements Exception {
  const ReturnException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  final ReturnFailureType type;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'ReturnException(type: ${type.name})';
}

/// Contract for sale-return operations.
///
/// State machine:
/// * A return is created in `draft`. Its header and items may only be
///   modified while it remains in `draft`.
/// * [confirmReturn] transitions it to `confirmed` and (via the database
///   trigger) generates the corresponding `return_in` stock movements and,
///   when the refund method is `credit_note`, reduces the customer balance.
/// * [cancelReturn] transitions it to `cancelled`, reversing the stock
///   movements and restoring the customer balance.
abstract interface class ReturnsRepository {
  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  Future<List<SaleReturn>> listReturns(
    String companyId, {
    String? branchId,
    String? saleId,
    String? status,
    int? limit,
  });

  Future<SaleReturn> getReturn(String returnId);

  Future<List<SaleReturnItem>> listReturnItems(String returnId);

  /// Lists the returns already recorded for a given sale, regardless of
  /// status. Useful for the "remaining returnable quantity" computation.
  Future<List<SaleReturn>> listReturnsForSale(String saleId);

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  /// Creates a draft return with its items.
  ///
  /// The database trigger `assign_sale_return_number` fills the
  /// `return_number` when it is omitted.
  Future<SaleReturn> createReturn({
    required String companyId,
    required String branchId,
    required String saleId,
    String? customerId,
    required DateTime returnDate,
    required List<SaleReturnItemDraft> items,
    String refundMethod,
    String? notes,
  });

  /// Replaces the header and items of an existing draft return.
  Future<SaleReturn> updateDraft({
    required String returnId,
    required String companyId,
    required String branchId,
    required String saleId,
    String? customerId,
    required DateTime returnDate,
    required List<SaleReturnItemDraft> items,
    String refundMethod,
    String? notes,
  });

  /// Confirms a draft return.
  Future<SaleReturn> confirmReturn(String returnId);

  /// Cancels a draft or confirmed return.
  Future<SaleReturn> cancelReturn(String returnId);
}

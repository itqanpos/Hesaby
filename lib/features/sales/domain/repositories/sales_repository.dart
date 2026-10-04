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

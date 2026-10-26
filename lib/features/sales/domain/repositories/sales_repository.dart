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

  Future<CustomerStatement> buildStatement({
    required String customerId,
    DateTime? fromDate,
    DateTime? toDate,
  });
}

// ============================================================================
// Sales repository
// ============================================================================

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

enum ReturnFailureType {
  network,
  unauthorized,
  notFound,
  saleNotConfirmed,
  emptyReturn,
  excessiveQuantity,
  creditNoteRequiresCustomer,
  invalidStatusTransition,
  immutableConfirmedReturn,
  referenceNotFound,
  invalidResponse,
  unknown,
}

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

abstract interface class ReturnsRepository {
  Future<List<SaleReturn>> listReturns(
    String companyId, {
    String? branchId,
    String? saleId,
    String? status,
    int? limit,
  });

  Future<SaleReturn> getReturn(String returnId);

  Future<List<SaleReturnItem>> listReturnItems(String returnId);

  Future<List<SaleReturn>> listReturnsForSale(String saleId);

  Future<SaleReturn> createReturn({
    required String companyId,
    required String branchId,
    String? saleId, // ⬅️ تم التعديل لدعم المرتجع المستقل
    String? customerId,
    required DateTime returnDate,
    required List<SaleReturnItemDraft> items,
    String refundMethod,
    String? notes,
  });

  Future<SaleReturn> updateDraft({
    required String returnId,
    required String companyId,
    required String branchId,
    String? saleId, // ⬅️ تم التعديل لدعم المرتجع المستقل
    String? customerId,
    required DateTime returnDate,
    required List<SaleReturnItemDraft> items,
    String refundMethod,
    String? notes,
  });

  Future<SaleReturn> confirmReturn(String returnId);

  Future<SaleReturn> cancelReturn(String returnId);
}

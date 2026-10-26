// lib/features/sales/domain/repositories/sales_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/customer_adjustment.dart';
import '../entities/customer_payment.dart';
import '../entities/customer_statement.dart';
import '../entities/sale_entities.dart';
import '../entities/sale_return.dart';

// ============================================================================
// Customer repository (لم يتغير)
// ============================================================================
// ... (اترك هذا الجزء كما هو في مشروعك) ...

// ============================================================================
// Sales repository (لم يتغير)
// ============================================================================
// ... (اترك هذا الجزء كما هو في مشروعك) ...

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

  Future<List<SaleReturn>> listReturnsForSale(String saleId);

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  /// تم تعديل saleId ليكون String? لدعم المرتجع المستقل
  Future<SaleReturn> createReturn({
    required String companyId,
    required String branchId,
    String? saleId, // ⬅️ تعديل
    String? customerId,
    required DateTime returnDate,
    required List<SaleReturnItemDraft> items,
    String refundMethod,
    String? notes,
  });

  /// تم تعديل saleId ليكون String?
  Future<SaleReturn> updateDraft({
    required String returnId,
    required String companyId,
    required String branchId,
    String? saleId, // ⬅️ تعديل
    String? customerId,
    required DateTime returnDate,
    required List<SaleReturnItemDraft> items,
    String refundMethod,
    String? notes,
  });

  Future<SaleReturn> confirmReturn(String returnId);

  Future<SaleReturn> cancelReturn(String returnId);
}

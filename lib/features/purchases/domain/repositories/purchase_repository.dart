// lib/features/purchases/domain/repositories/purchase_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/purchase.dart';
import '../entities/purchase_item.dart';

@immutable
class PurchaseItemDraft extends Equatable {
  const PurchaseItemDraft({
    required this.productId,
    required this.unitId,
    required this.quantity,
    required this.unitCost,
    this.notes,
  });

  final String productId;
  final String unitId;
  final double quantity;
  final double unitCost;
  final String? notes;

  @override
  List<Object?> get props =>
      <Object?>[productId, unitId, quantity, unitCost, notes];

  @override
  String toString() =>
      'PurchaseItemDraft(productId: $productId, unitId: $unitId, '
      'quantity: $quantity, unitCost: $unitCost)';
}

enum PurchaseFailureType {
  network,
  unauthorized,
  notFound,
  invalidStatusTransition,
  emptyPurchase,
  invoiceNumberConflict,
  supplierNotFound,
  branchNotFound,
  productNotFound,
  unitNotFound,
  insufficientStock,
  invalidResponse,
  unknown,
}

@immutable
class PurchaseException extends Equatable implements Exception {
  const PurchaseException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  final PurchaseFailureType type;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'PurchaseException(type: ${type.name})';
}

abstract interface class PurchaseRepository {
  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  Future<List<Purchase>> listPurchases(
    String companyId, {
    String? branchId,
    String? status,
    int? limit,
  });

  Future<Purchase> getPurchase(String purchaseId);

  Future<List<PurchaseItem>> listPurchaseItems(String purchaseId);

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  // ⬇️ إضافة paidAmount و paymentMethod
  Future<Purchase> createPurchase({
    required String companyId,
    required String branchId,
    required String supplierId,
    required DateTime purchaseDate,
    List<PurchaseItemDraft> items,
    String? invoiceNumber,
    double discount,
    double taxAmount,
    double paidAmount,
    String paymentMethod,
    String? notes,
  });

  // ⬇️ إضافة paidAmount و paymentMethod
  Future<Purchase> updateDraft({
    required String purchaseId,
    required String companyId,
    required String branchId,
    required String supplierId,
    required DateTime purchaseDate,
    required List<PurchaseItemDraft> items,
    String? invoiceNumber,
    double discount,
    double taxAmount,
    double paidAmount,
    String paymentMethod,
    String? notes,
  });

  Future<Purchase> confirmPurchase(String purchaseId);

  Future<Purchase> cancelPurchase(String purchaseId);
}

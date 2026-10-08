// lib/features/purchases/domain/repositories/supplier_payment_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/supplier_payment.dart';

/// Categories of failures that the presentation layer can safely translate
/// into localized user messages.
enum SupplierPaymentFailureType {
  network,
  unauthorized,
  notFound,
  invalidAmount,
  invalidMethod,
  supplierNotFound,
  purchaseNotFound,
  invalidResponse,
  unknown,
}

/// Domain-level exception raised by [SupplierPaymentRepository] operations.
@immutable
class SupplierPaymentException extends Equatable implements Exception {
  const SupplierPaymentException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  final SupplierPaymentFailureType type;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() =>
      'SupplierPaymentException(type: ${type.name})';
}

/// Contract for supplier-payment operations.
///
/// All access decisions are ultimately enforced by Row Level Security in
/// the database: the data layer never accepts a `userId`, and `companyId`
/// is only ever used to scope the operation.
abstract interface class SupplierPaymentRepository {
  /// Returns the payments made to [supplierId], most recent first.
  Future<List<SupplierPayment>> listPaymentsForSupplier(
    String supplierId, {
    int? limit,
  });

  /// Returns the payments tied to a specific [purchaseId], most recent first.
  Future<List<SupplierPayment>> listPaymentsForPurchase(String purchaseId);

  /// Returns the total amount paid to [supplierId] (sum of all payments).
  ///
  /// Used by the supplier detail / balance views. Cheap on the server side
  /// for typical SME volumes.
  Future<double> sumPaymentsForSupplier(String supplierId);

  /// Records a new payment.
  ///
  /// [amount] must be strictly positive. [paymentMethod] must be one of
  /// [SupplierPaymentMethod.all]. When [purchaseId] is provided, the target
  /// purchase must belong to the same company and the same supplier.
  Future<SupplierPayment> recordPayment({
    required String companyId,
    required String supplierId,
    required double amount,
    required String paymentMethod,
    required DateTime paymentDate,
    String? purchaseId,
    String? reference,
    String? notes,
  });

  /// Deletes a payment. Rejected for RLS reasons when the caller lacks the
  /// manager role.
  Future<void> deletePayment(String paymentId);
}

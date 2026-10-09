// lib/features/suppliers/domain/repositories/supplier_statement_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/supplier_statement.dart';

/// Categories of failures raised by statement operations.
enum SupplierStatementFailureType {
  network,
  unauthorized,
  notFound,
  invalidResponse,
  unknown,
}

@immutable
class SupplierStatementException extends Equatable implements Exception {
  const SupplierStatementException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  final SupplierStatementFailureType type;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() =>
      'SupplierStatementException(type: ${type.name})';
}

/// Contract for building a supplier's account statement.
///
/// The repository is responsible for:
/// * Fetching all confirmed purchases and all payments of the supplier.
/// * Computing the opening balance (before the requested window).
/// * Returning a fully built [SupplierStatement].
abstract interface class SupplierStatementRepository {
  /// Builds the statement for [supplierId] between [fromDate] and
  /// [toDate] (both inclusive, both optional).
  ///
  /// When [fromDate] is null, openingBalance is zero. When [toDate] is
  /// null, "now" is used as the upper bound.
  Future<SupplierStatement> buildStatement({
    required String supplierId,
    DateTime? fromDate,
    DateTime? toDate,
  });
}

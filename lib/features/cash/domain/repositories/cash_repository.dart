// lib/features/cash/domain/repositories/cash_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/cash_entities.dart';

enum CashFailureType {
  network,
  unauthorized,
  notFound,
  invalidInput,
  invalidResponse,
  unknown,
}

@immutable
class CashException extends Equatable implements Exception {
  const CashException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  final CashFailureType type;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'CashException(type: ${type.name})';
}

/// Contract for the cash register feature.
abstract interface class CashRepository {
  /// Returns every active account of [companyId].
  Future<List<CashAccount>> listAccounts(String companyId);

  /// Returns every active category of [companyId].
  Future<List<CashCategory>> listCategories(String companyId);

  /// Returns the cash overview: accounts + balances + total.
  Future<CashOverview> getOverview(String companyId);

  /// Returns the most recent transactions of [companyId].
  Future<List<CashTransaction>> listTransactions({
    required String companyId,
    String? accountId,
    DateTime? fromDate,
    DateTime? toDate,
    int limit = 100,
  });

  /// Records one or more sale payments for an already-confirmed sale.
  ///
  /// The database triggers translate these rows into cash movements.
  Future<void> recordSalePayments({
    required String companyId,
    required String saleId,
    required List<SalePaymentDraft> payments,
  });

  /// Records a manual cash movement.
  Future<CashTransaction> recordManualTransaction({
    required String companyId,
    required String accountId,
    String? branchId,
    String? categoryId,
    required CashDirection direction,
    required double amount,
    String? reference,
    String? notes,
    DateTime? transactionDate,
  });

  /// Creates a new account.
  Future<CashAccount> createAccount({
    required String companyId,
    required String name,
    required CashAccountType type,
  });

  /// Creates a new category.
  Future<CashCategory> createCategory({
    required String companyId,
    required String name,
    required CashCategoryKind kind,
  });
}

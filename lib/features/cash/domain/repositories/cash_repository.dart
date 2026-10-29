// lib/features/cash/domain/repositories/cash_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import '../entities/cash_entities.dart';

enum CashFailureType {
  network, unauthorized, notFound, invalidInput, invalidResponse, unknown,
}

@immutable
class CashException extends Equatable implements Exception {
  const CashException({required this.type, this.cause, this.stackTrace});
  final CashFailureType type;
  final Object? cause;
  final StackTrace? stackTrace;
  @override
  List<Object?> get props => <Object?>[type];
  @override
  String toString() => 'CashException(type: ${type.name})';
}

abstract interface class CashRepository {
  Future<List<CashAccount>> listAccounts(String companyId);
  Future<List<CashCategory>> listCategories(String companyId);
  Future<CashOverview> getOverview(String companyId);
  Future<List<CashTransaction>> listTransactions({
    required String companyId,
    String? accountId,
    String? shiftId,
    DateTime? fromDate,
    DateTime? toDate,
    int limit = 100,
  });
  Future<void> recordSalePayments({
    required String companyId,
    required String saleId,
    required List<SalePaymentDraft> payments,
  });
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
  Future<CashAccount> createAccount({
    required String companyId,
    required String name,
    required CashAccountType type,
  });
  Future<CashCategory> createCategory({
    required String companyId,
    required String name,
    required CashCategoryKind kind,
  });

  Future<Shift?> getActiveShift(String companyId);
  Future<Shift> getShiftById(String shiftId);
  Future<Shift> openShift({
    required String companyId,
    required String cashierId,
    String? branchId,
    required double openingBalance,
  });
  Future<Shift> closeShift({
    required String shiftId,
    required double actualClosingBalance,
    String? notes,
  });
}

// lib/features/expenses/domain/repositories/expense_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/expense.dart';

enum ExpenseFailureType {
  network,
  unauthorized,
  notFound,
  invalidInput,
  invalidResponse,
  unknown,
}

@immutable
class ExpenseException extends Equatable implements Exception {
  const ExpenseException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  final ExpenseFailureType type;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'ExpenseException(type: ${type.name})';
}

abstract interface class ExpenseRepository {
  /// Lists expenses of [companyId], newest first.
  ///
  /// [fromDate] / [toDate] filter by expense_date (inclusive).
  Future<List<Expense>> listExpenses({
    required String companyId,
    DateTime? fromDate,
    DateTime? toDate,
    int limit = 200,
  });

  Future<Expense> createExpense({
    required String companyId,
    String? branchId,
    String? categoryId,
    required String description,
    required double amount,
    required DateTime expenseDate,
    required String paymentMethod,
    String? reference,
    String? notes,
  });

  Future<Expense> updateExpense({
    required String expenseId,
    String? categoryId,
    bool clearCategory = false,
    String? description,
    double? amount,
    DateTime? expenseDate,
    String? paymentMethod,
    String? reference,
    bool clearReference = false,
    String? notes,
    bool clearNotes = false,
  });

  Future<void> deleteExpense(String expenseId);
}

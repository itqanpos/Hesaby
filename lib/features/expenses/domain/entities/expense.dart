// lib/features/expenses/domain/entities/expense.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// A single expense record.
///
/// Covers any outgoing payment that is not a purchase, salary, or advance:
/// rent, utilities, internet, maintenance, transportation, etc.
@immutable
class Expense extends Equatable {
  const Expense({
    required this.id,
    required this.companyId,
    required this.description,
    required this.amount,
    required this.expenseDate,
    required this.paymentMethod,
    required this.createdAt,
    required this.updatedAt,
    this.branchId,
    this.categoryId,
    this.categoryName,
    this.reference,
    this.notes,
  });

  final String id;
  final String companyId;
  final String? branchId;
  final String? categoryId;
  final String? categoryName;
  final String description;
  final double amount;
  final DateTime expenseDate;
  final String paymentMethod;
  final String? reference;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        description,
        amount,
        expenseDate,
        paymentMethod,
        categoryId,
      ];
}

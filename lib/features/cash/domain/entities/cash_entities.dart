// lib/features/cash/domain/entities/cash_entities.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Cash account types supported by the register.
enum CashAccountType {
  cash,
  card,
  bank,
  instapay,
  other;

  static CashAccountType fromString(String? raw) {
    switch (raw) {
      case 'cash':
        return CashAccountType.cash;
      case 'card':
        return CashAccountType.card;
      case 'bank':
        return CashAccountType.bank;
      case 'instapay':
        return CashAccountType.instapay;
      default:
        return CashAccountType.other;
    }
  }

  String get label => switch (this) {
        CashAccountType.cash => 'خزنة نقدية',
        CashAccountType.card => 'حساب بطاقة',
        CashAccountType.bank => 'حساب بنكي',
        CashAccountType.instapay => 'InstaPay',
        CashAccountType.other => 'أخرى',
      };
}

/// Direction of a cash movement.
enum CashDirection {
  inFlow,
  outFlow;

  static CashDirection fromString(String? raw) =>
      raw == 'out' ? CashDirection.outFlow : CashDirection.inFlow;

  String get value => this == CashDirection.inFlow ? 'in' : 'out';

  String get label =>
      this == CashDirection.inFlow ? 'وارد' : 'صادر';
}

/// Cash category kind.
enum CashCategoryKind {
  income,
  expense,
  transfer;

  static CashCategoryKind fromString(String? raw) {
    switch (raw) {
      case 'income':
        return CashCategoryKind.income;
      case 'transfer':
        return CashCategoryKind.transfer;
      default:
        return CashCategoryKind.expense;
    }
  }

  String get label => switch (this) {
        CashCategoryKind.income => 'إيراد',
        CashCategoryKind.expense => 'مصروف',
        CashCategoryKind.transfer => 'تحويل',
      };
}

/// A cash-equivalent account.
@immutable
class CashAccount extends Equatable {
  const CashAccount({
    required this.id,
    required this.companyId,
    required this.name,
    required this.type,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String companyId;
  final String name;
  final CashAccountType type;
  final bool isActive;
  final DateTime createdAt;

  @override
  List<Object?> get props => <Object?>[id, companyId, name, type, isActive];
}

/// A category used to classify cash movements.
@immutable
class CashCategory extends Equatable {
  const CashCategory({
    required this.id,
    required this.companyId,
    required this.name,
    required this.kind,
    required this.isSystem,
    required this.isActive,
  });

  final String id;
  final String companyId;
  final String name;
  final CashCategoryKind kind;
  final bool isSystem;
  final bool isActive;

  @override
  List<Object?> get props => <Object?>[id, name, kind, isSystem, isActive];
}

/// A single cash movement.
@immutable
class CashTransaction extends Equatable {
  const CashTransaction({
    required this.id,
    required this.companyId,
    required this.accountId,
    required this.accountName,
    required this.direction,
    required this.amount,
    required this.sourceType,
    required this.transactionDate,
    this.branchId,
    this.categoryId,
    this.categoryName,
    this.sourceId,
    this.reference,
    this.notes,
  });

  final String id;
  final String companyId;
  final String accountId;
  final String accountName;
  final String? branchId;
  final String? categoryId;
  final String? categoryName;
  final CashDirection direction;
  final double amount;
  final String sourceType;
  final String? sourceId;
  final String? reference;
  final String? notes;
  final DateTime transactionDate;

  double get signedAmount =>
      direction == CashDirection.inFlow ? amount : -amount;

  @override
  List<Object?> get props => <Object?>[id];
}

/// Aggregate snapshot for a single account.
@immutable
class CashAccountBalance extends Equatable {
  const CashAccountBalance({
    required this.account,
    required this.balance,
  });

  final CashAccount account;

  /// Positive = money in. Negative = overdrawn.
  final double balance;

  @override
  List<Object?> get props => <Object?>[account.id, balance];
}

/// Result of a cash register page load: the accounts + their balances.
@immutable
class CashOverview extends Equatable {
  const CashOverview({
    required this.balances,
    required this.totalBalance,
  });

  const CashOverview.empty()
      : balances = const <CashAccountBalance>[],
        totalBalance = 0;

  final List<CashAccountBalance> balances;
  final double totalBalance;

  @override
  List<Object?> get props => <Object?>[balances, totalBalance];
}

/// A payment leg of a sale — one method, one amount.
@immutable
class SalePaymentDraft extends Equatable {
  const SalePaymentDraft({
    required this.amount,
    required this.method,
  });

  final double amount;

  /// `cash` | `card` | `instapay` | `bank_transfer` | `other`.
  final String method;

  @override
  List<Object?> get props => <Object?>[amount, method];
}

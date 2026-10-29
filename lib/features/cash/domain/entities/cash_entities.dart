// lib/features/cash/domain/entities/cash_entities.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

enum CashAccountType {
  cash, card, bank, instapay, other;

  static CashAccountType fromString(String? raw) {
    switch (raw) {
      case 'cash': return CashAccountType.cash;
      case 'card': return CashAccountType.card;
      case 'bank': return CashAccountType.bank;
      case 'instapay': return CashAccountType.instapay;
      default: return CashAccountType.other;
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

enum CashDirection {
  inFlow, outFlow;

  static CashDirection fromString(String? raw) => raw == 'out' ? CashDirection.outFlow : CashDirection.inFlow;
  String get value => this == CashDirection.inFlow ? 'in' : 'out';
  String get label => this == CashDirection.inFlow ? 'وارد' : 'صادر';
}

enum CashCategoryKind {
  income, expense, transfer;

  static CashCategoryKind fromString(String? raw) {
    switch (raw) {
      case 'income': return CashCategoryKind.income;
      case 'transfer': return CashCategoryKind.transfer;
      default: return CashCategoryKind.expense;
    }
  }

  String get label => switch (this) {
        CashCategoryKind.income => 'إيراد',
        CashCategoryKind.expense => 'مصروف',
        CashCategoryKind.transfer => 'تحويل',
      };
}

@immutable
class CashAccount extends Equatable {
  const CashAccount({required this.id, required this.companyId, required this.name, required this.type, required this.isActive, required this.createdAt});
  final String id;
  final String companyId;
  final String name;
  final CashAccountType type;
  final bool isActive;
  final DateTime createdAt;

  @override
  List<Object?> get props => <Object?>[id, companyId, name, type, isActive];
}

@immutable
class CashCategory extends Equatable {
  const CashCategory({required this.id, required this.companyId, required this.name, required this.kind, required this.isSystem, required this.isActive});
  final String id;
  final String companyId;
  final String name;
  final CashCategoryKind kind;
  final bool isSystem;
  final bool isActive;

  @override
  List<Object?> get props => <Object?>[id, name, kind, isSystem, isActive];
}

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
    this.shiftId, // ✅ تمت إضافته
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
  final String? shiftId;
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

  double get signedAmount => direction == CashDirection.inFlow ? amount : -amount;

  @override
  List<Object?> get props => <Object?>[id];
}

@immutable
class CashAccountBalance extends Equatable {
  const CashAccountBalance({required this.account, required this.balance});
  final CashAccount account;
  final double balance;

  @override
  List<Object?> get props => <Object?>[account.id, balance];
}

@immutable
class CashOverview extends Equatable {
  const CashOverview({required this.balances, required this.totalBalance});
  const CashOverview.empty() : balances = const <CashAccountBalance>[], totalBalance = 0;

  final List<CashAccountBalance> balances;
  final double totalBalance;

  @override
  List<Object?> get props => <Object?>[balances, totalBalance];
}

@immutable
class SalePaymentDraft extends Equatable {
  const SalePaymentDraft({required this.amount, required this.method});
  final double amount;
  final String method;

  @override
  List<Object?> get props => <Object?>[amount, method];
}

// ✅ كيان الوردية الجديد
@immutable
class Shift extends Equatable {
  const Shift({
    required this.id,
    required this.companyId,
    required this.cashierId,
    required this.openedAt,
    required this.openingBalance,
    required this.status,
    this.branchId,
    this.closedAt,
    this.expectedClosingBalance,
    this.actualClosingBalance,
    this.difference,
    this.notes,
  });

  final String id;
  final String companyId;
  final String? branchId;
  final String cashierId;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingBalance;
  final double? expectedClosingBalance;
  final double? actualClosingBalance;
  final double? difference;
  final String status; // 'open' | 'closed'
  final String? notes;

  bool get isOpen => status == 'open';

  @override
  List<Object?> get props => <Object?>[id, status];
}

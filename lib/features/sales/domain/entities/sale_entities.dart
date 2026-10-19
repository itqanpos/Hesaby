// lib/features/sales/domain/entities/sale_entities.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

// ============================================================================
// Status constants
// ============================================================================

abstract final class SaleStatus {
  static const String draft = 'draft';
  static const String confirmed = 'confirmed';
  static const String cancelled = 'cancelled';

  static const List<String> all = <String>[draft, confirmed, cancelled];
}

abstract final class PaymentStatus {
  static const String unpaid = 'unpaid';
  static const String partial = 'partial';
  static const String paid = 'paid';

  static const List<String> all = <String>[unpaid, partial, paid];
}

// ============================================================================
// Customer
// ============================================================================

@immutable
class Customer extends Equatable {
  const Customer({
    required this.id,
    required this.companyId,
    required this.name,
    required this.balance,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.code,
    this.phone,
    this.email,
    this.address,
    this.notes,
  });

  final String id;
  final String companyId;
  final String name;
  final String? code;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final double balance;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  // ---------------------------------------------------------------------------
  // Convenience
  // ---------------------------------------------------------------------------

  bool get hasCode => code != null && code!.trim().isNotEmpty;
  bool get hasPhone => phone != null && phone!.trim().isNotEmpty;
  bool get hasEmail => email != null && email!.trim().isNotEmpty;
  bool get hasAddress => address != null && address!.trim().isNotEmpty;
  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;
  bool get hasContactInfo => hasPhone || hasEmail;
  bool get hasOutstandingBalance => balance > 0;
  bool get isDebtor => balance > 0;
  bool get isSettled => balance <= 0;

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  Customer copyWith({
    String? name,
    String? code,
    bool clearCode = false,
    String? phone,
    bool clearPhone = false,
    String? email,
    bool clearEmail = false,
    String? address,
    bool clearAddress = false,
    String? notes,
    bool clearNotes = false,
    double? balance,
    bool? isActive,
    DateTime? updatedAt,
  }) {
    return Customer(
      id: id,
      companyId: companyId,
      name: name ?? this.name,
      code: clearCode ? null : (code ?? this.code),
      phone: clearPhone ? null : (phone ?? this.phone),
      email: clearEmail ? null : (email ?? this.email),
      address: clearAddress ? null : (address ?? this.address),
      notes: clearNotes ? null : (notes ?? this.notes),
      balance: balance ?? this.balance,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        name,
        code,
        phone,
        email,
        address,
        notes,
        balance,
        isActive,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'Customer(id: $id, companyId: $companyId, name: $name, code: $code, '
      'balance: $balance, isActive: $isActive)';
}

// ... (بقية الملف: Sale, SaleItem, SaleItemDraft كما هي بدون تغيير) ...

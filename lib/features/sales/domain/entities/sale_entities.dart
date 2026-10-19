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

  bool get hasCode => code != null && code!.trim().isNotEmpty;
  bool get hasPhone => phone != null && phone!.trim().isNotEmpty;
  bool get hasEmail => email != null && email!.trim().isNotEmpty;
  bool get hasAddress => address != null && address!.trim().isNotEmpty;
  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;
  bool get hasContactInfo => hasPhone || hasEmail;
  bool get hasOutstandingBalance => balance > 0;
  bool get isDebtor => balance > 0;
  bool get isSettled => balance <= 0;

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

// ============================================================================
// Sale
// ============================================================================

@immutable
class Sale extends Equatable {
  const Sale({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.saleDate,
    required this.status,
    required this.subtotal,
    required this.discount,
    required this.taxAmount,
    required this.total,
    required this.paidAmount,
    required this.paymentStatus,
    required this.createdAt,
    required this.updatedAt,
    this.customerId,
    this.invoiceNumber,
    this.notes,
    this.createdBy,
    this.confirmedAt,
    this.cancelledAt,
  });

  final String id;
  final String companyId;
  final String branchId;
  final String? customerId;
  final String? invoiceNumber;
  final DateTime saleDate;
  final String status;
  final double subtotal;
  final double discount;
  final double taxAmount;
  final double total;
  final double paidAmount;
  final String paymentStatus;
  final String? notes;
  final String? createdBy;
  final DateTime? confirmedAt;
  final DateTime? cancelledAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isDraft => status == SaleStatus.draft;
  bool get isConfirmed => status == SaleStatus.confirmed;
  bool get isCancelled => status == SaleStatus.cancelled;
  bool get canEdit => isDraft;
  bool get canTransition => isDraft || isConfirmed;

  bool get hasCustomer => customerId != null;
  bool get hasInvoiceNumber =>
      invoiceNumber != null && invoiceNumber!.trim().isNotEmpty;
  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;
  bool get wasConfirmed => confirmedAt != null;
  bool get wasCancelled => cancelledAt != null;

  bool get isUnpaid => paymentStatus == PaymentStatus.unpaid;
  bool get isPartiallyPaid => paymentStatus == PaymentStatus.partial;
  bool get isFullyPaid => paymentStatus == PaymentStatus.paid;

  double get amountDue {
    final double due = total - paidAmount;
    return due < 0 ? 0 : due;
  }

  double get netAfterDiscount => subtotal - discount;

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        branchId,
        customerId,
        invoiceNumber,
        saleDate,
        status,
        subtotal,
        discount,
        taxAmount,
        total,
        paidAmount,
        paymentStatus,
        notes,
        createdBy,
        confirmedAt,
        cancelledAt,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'Sale(id: $id, customerId: $customerId, status: $status, '
      'total: $total, paidAmount: $paidAmount)';
}

// ============================================================================
// Sale item
// ============================================================================

@immutable
class SaleItem extends Equatable {
  const SaleItem({
    required this.id,
    required this.companyId,
    required this.saleId,
    required this.productId,
    required this.unitId,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
  });

  final String id;
  final String companyId;
  final String saleId;
  final String productId;
  final String unitId;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;
  double get value => lineTotal;

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        saleId,
        productId,
        unitId,
        quantity,
        unitPrice,
        lineTotal,
        notes,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'SaleItem(id: $id, saleId: $saleId, productId: $productId, '
      'quantity: $quantity, unitPrice: $unitPrice, lineTotal: $lineTotal)';
}

// ============================================================================
// Sale item draft
// ============================================================================

@immutable
class SaleItemDraft extends Equatable {
  const SaleItemDraft({
    required this.productId,
    required this.unitId,
    required this.quantity,
    required this.unitPrice,
    this.notes,
  });

  final String productId;
  final String unitId;
  final double quantity;
  final double unitPrice;
  final String? notes;

  @override
  List<Object?> get props =>
      <Object?>[productId, unitId, quantity, unitPrice, notes];

  @override
  String toString() =>
      'SaleItemDraft(productId: $productId, unitId: $unitId, '
      'quantity: $quantity, unitPrice: $unitPrice)';
}

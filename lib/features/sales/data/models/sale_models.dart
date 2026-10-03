// lib/features/sales/data/models/sale_models.dart

import 'package:equatable/equatable.dart';

import '../../domain/entities/sale_entities.dart';

// ============================================================================
// CustomerModel
// ============================================================================

class CustomerModel extends Equatable {
  const CustomerModel({
    required this.id,
    required this.companyId,
    required this.name,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.code,
    this.phone,
    this.email,
    this.address,
    this.notes,
  });

  factory CustomerModel.fromMap(Map<String, dynamic> map) {
    return CustomerModel(
      id: _requireString(map, 'id'),
      companyId: _requireString(map, 'company_id'),
      name: _requireString(map, 'name'),
      code: _optionalString(map, 'code'),
      phone: _optionalString(map, 'phone'),
      email: _optionalString(map, 'email'),
      address: _optionalString(map, 'address'),
      notes: _optionalString(map, 'notes'),
      isActive: _optionalBool(map, 'is_active') ?? true,
      createdAt: _requireTimestamp(map, 'created_at'),
      updatedAt: _requireTimestamp(map, 'updated_at'),
    );
  }

  final String id;
  final String companyId;
  final String name;
  final String? code;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Customer toEntity() => Customer(
        id: id,
        companyId: companyId,
        name: name,
        code: code,
        phone: phone,
        email: email,
        address: address,
        notes: notes,
        isActive: isActive,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  static String _requireString(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException(
      'CustomerModel: missing or invalid required column "$key".',
    );
  }

  static String? _optionalString(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) {
      return null;
    }
    if (value is String) {
      final String trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return value.toString();
  }

  static bool? _optionalBool(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) {
      return null;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final String lower = value.toLowerCase();
      if (lower == 'true' || lower == 't' || lower == '1') {
        return true;
      }
      if (lower == 'false' || lower == 'f' || lower == '0') {
        return false;
      }
    }
    return null;
  }

  static DateTime _requireTimestamp(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is String && value.isNotEmpty) {
      final DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed.toUtc();
      }
    }
    throw FormatException(
      'CustomerModel: missing or invalid timestamp column "$key".',
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
        isActive,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'CustomerModel(id: $id, companyId: $companyId, name: $name, code: $code)';
}

// ============================================================================
// SaleModel
// ============================================================================

class SaleModel extends Equatable {
  const SaleModel({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.customerId,
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
    this.invoiceNumber,
    this.notes,
    this.createdBy,
    this.confirmedAt,
    this.cancelledAt,
  });

  factory SaleModel.fromMap(Map<String, dynamic> map) {
    return SaleModel(
      id: _requireString(map, 'id'),
      companyId: _requireString(map, 'company_id'),
      branchId: _requireString(map, 'branch_id'),
      customerId: _requireString(map, 'customer_id'),
      invoiceNumber: _optionalString(map, 'invoice_number'),
      saleDate: _requireTimestamp(map, 'sale_date'),
      status: _requireString(map, 'status'),
      subtotal: _requireDouble(map, 'subtotal'),
      discount: _requireDouble(map, 'discount'),
      taxAmount: _requireDouble(map, 'tax_amount'),
      total: _requireDouble(map, 'total'),
      paidAmount: _requireDouble(map, 'paid_amount'),
      paymentStatus: _requireString(map, 'payment_status'),
      notes: _optionalString(map, 'notes'),
      createdBy: _optionalString(map, 'created_by'),
      confirmedAt: _optionalTimestamp(map, 'confirmed_at'),
      cancelledAt: _optionalTimestamp(map, 'cancelled_at'),
      createdAt: _requireTimestamp(map, 'created_at'),
      updatedAt: _requireTimestamp(map, 'updated_at'),
    );
  }

  final String id;
  final String companyId;
  final String branchId;
  final String customerId;
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

  Sale toEntity() => Sale(
        id: id,
        companyId: companyId,
        branchId: branchId,
        customerId: customerId,
        invoiceNumber: invoiceNumber,
        saleDate: saleDate,
        status: status,
        subtotal: subtotal,
        discount: discount,
        taxAmount: taxAmount,
        total: total,
        paidAmount: paidAmount,
        paymentStatus: paymentStatus,
        notes: notes,
        createdBy: createdBy,
        confirmedAt: confirmedAt,
        cancelledAt: cancelledAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  static String _requireString(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException(
      'SaleModel: missing or invalid required column "$key".',
    );
  }

  static String? _optionalString(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) {
      return null;
    }
    if (value is String) {
      final String trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return value.toString();
  }

  static double _requireDouble(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final String trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        final double? parsed = double.tryParse(trimmed);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    throw FormatException(
      'SaleModel: missing or invalid required column "$key".',
    );
  }

  static DateTime _requireTimestamp(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is String && value.isNotEmpty) {
      final DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed.toUtc();
      }
    }
    throw FormatException(
      'SaleModel: missing or invalid timestamp column "$key".',
    );
  }

  static DateTime? _optionalTimestamp(
    Map<String, dynamic> map,
    String key,
  ) {
    final Object? value = map[key];
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is String && value.isNotEmpty) {
      final DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed.toUtc();
      }
    }
    return null;
  }

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
      'SaleModel(id: $id, customerId: $customerId, status: $status, '
      'total: $total, paidAmount: $paidAmount)';
}

// ============================================================================
// SaleItemModel
// ============================================================================

class SaleItemModel extends Equatable {
  const SaleItemModel({
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

  factory SaleItemModel.fromMap(Map<String, dynamic> map) {
    return SaleItemModel(
      id: _requireString(map, 'id'),
      companyId: _requireString(map, 'company_id'),
      saleId: _requireString(map, 'sale_id'),
      productId: _requireString(map, 'product_id'),
      unitId: _requireString(map, 'unit_id'),
      quantity: _requireDouble(map, 'quantity'),
      unitPrice: _requireDouble(map, 'unit_price'),
      lineTotal: _requireDouble(map, 'line_total'),
      notes: _optionalString(map, 'notes'),
      createdAt: _requireTimestamp(map, 'created_at'),
      updatedAt: _requireTimestamp(map, 'updated_at'),
    );
  }

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

  SaleItem toEntity() => SaleItem(
        id: id,
        companyId: companyId,
        saleId: saleId,
        productId: productId,
        unitId: unitId,
        quantity: quantity,
        unitPrice: unitPrice,
        lineTotal: lineTotal,
        notes: notes,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  static String _requireString(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException(
      'SaleItemModel: missing or invalid required column "$key".',
    );
  }

  static String? _optionalString(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) {
      return null;
    }
    if (value is String) {
      final String trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return value.toString();
  }

  static double _requireDouble(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final String trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        final double? parsed = double.tryParse(trimmed);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    throw FormatException(
      'SaleItemModel: missing or invalid required column "$key".',
    );
  }

  static DateTime _requireTimestamp(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is String && value.isNotEmpty) {
      final DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed.toUtc();
      }
    }
    throw FormatException(
      'SaleItemModel: missing or invalid timestamp column "$key".',
    );
  }

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
      'SaleItemModel(id: $id, saleId: $saleId, productId: $productId, '
      'lineTotal: $lineTotal)';
}

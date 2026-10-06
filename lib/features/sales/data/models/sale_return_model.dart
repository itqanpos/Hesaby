// lib/features/sales/data/models/sale_return_model.dart

import 'package:equatable/equatable.dart';

import '../../domain/entities/sale_return.dart';

/// Data-layer representation of a row in `public.sale_returns`.
class SaleReturnModel extends Equatable {
  const SaleReturnModel({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.saleId,
    required this.returnDate,
    required this.status,
    required this.subtotal,
    required this.discount,
    required this.taxAmount,
    required this.total,
    required this.refundMethod,
    required this.createdAt,
    required this.updatedAt,
    this.customerId,
    this.returnNumber,
    this.notes,
    this.createdBy,
    this.confirmedAt,
    this.cancelledAt,
  });

  factory SaleReturnModel.fromMap(Map<String, dynamic> map) {
    return SaleReturnModel(
      id: _requireString(map, 'id'),
      companyId: _requireString(map, 'company_id'),
      branchId: _requireString(map, 'branch_id'),
      saleId: _requireString(map, 'sale_id'),
      customerId: _optionalString(map, 'customer_id'),
      returnNumber: _optionalString(map, 'return_number'),
      returnDate: _requireDate(map, 'return_date'),
      status: _requireString(map, 'status'),
      subtotal: _requireDouble(map, 'subtotal'),
      discount: _requireDouble(map, 'discount'),
      taxAmount: _requireDouble(map, 'tax_amount'),
      total: _requireDouble(map, 'total'),
      refundMethod: _requireString(map, 'refund_method'),
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
  final String saleId;
  final String? customerId;
  final String? returnNumber;
  final DateTime returnDate;
  final String status;
  final double subtotal;
  final double discount;
  final double taxAmount;
  final double total;
  final String refundMethod;
  final String? notes;
  final String? createdBy;
  final DateTime? confirmedAt;
  final DateTime? cancelledAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  SaleReturn toEntity() => SaleReturn(
        id: id,
        companyId: companyId,
        branchId: branchId,
        saleId: saleId,
        customerId: customerId,
        returnNumber: returnNumber,
        returnDate: returnDate,
        status: status,
        subtotal: subtotal,
        discount: discount,
        taxAmount: taxAmount,
        total: total,
        refundMethod: refundMethod,
        notes: notes,
        createdBy: createdBy,
        confirmedAt: confirmedAt,
        cancelledAt: cancelledAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  // ---------------------------------------------------------------------------
  // Field parsers
  // ---------------------------------------------------------------------------

  static String _requireString(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException(
      'SaleReturnModel: missing or invalid required column "$key".',
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
      'SaleReturnModel: missing or invalid required column "$key".',
    );
  }

  static DateTime _requireDate(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is String && value.isNotEmpty) {
      // `date` columns come back as "YYYY-MM-DD"; parse as UTC midnight.
      final DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return DateTime.utc(parsed.year, parsed.month, parsed.day);
      }
    }
    if (value is DateTime) {
      return DateTime.utc(value.year, value.month, value.day);
    }
    throw FormatException(
      'SaleReturnModel: missing or invalid date column "$key".',
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
      'SaleReturnModel: missing or invalid timestamp column "$key".',
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
        saleId,
        customerId,
        returnNumber,
        returnDate,
        status,
        subtotal,
        discount,
        taxAmount,
        total,
        refundMethod,
        notes,
        createdBy,
        confirmedAt,
        cancelledAt,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'SaleReturnModel(id: $id, saleId: $saleId, status: $status, '
      'total: $total)';
}

// ============================================================================
// SaleReturnItemModel
// ============================================================================

/// Data-layer representation of a row in `public.sale_return_items`.
class SaleReturnItemModel extends Equatable {
  const SaleReturnItemModel({
    required this.id,
    required this.companyId,
    required this.returnId,
    required this.saleItemId,
    required this.productId,
    required this.unitId,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
  });

  factory SaleReturnItemModel.fromMap(Map<String, dynamic> map) {
    return SaleReturnItemModel(
      id: _requireString(map, 'id'),
      companyId: _requireString(map, 'company_id'),
      returnId: _requireString(map, 'return_id'),
      saleItemId: _requireString(map, 'sale_item_id'),
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
  final String returnId;
  final String saleItemId;
  final String productId;
  final String unitId;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  SaleReturnItem toEntity() => SaleReturnItem(
        id: id,
        companyId: companyId,
        returnId: returnId,
        saleItemId: saleItemId,
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
      'SaleReturnItemModel: missing or invalid required column "$key".',
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
      'SaleReturnItemModel: missing or invalid required column "$key".',
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
      'SaleReturnItemModel: missing or invalid timestamp column "$key".',
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        returnId,
        saleItemId,
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
      'SaleReturnItemModel(id: $id, returnId: $returnId, '
      'saleItemId: $saleItemId, quantity: $quantity)';
}

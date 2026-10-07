// lib/features/settings/domain/entities/company_settings.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Per-company business defaults.
///
/// One row exists for every company (created automatically by a DB trigger
/// when a company is inserted). All values are business rules that the POS,
/// sales, and receipt printer consult before performing their work.
///
/// Money and percentage values use `double`, matching `numeric(5,2)` in the
/// database.
@immutable
class CompanySettings extends Equatable {
  const CompanySettings({
    required this.companyId,
    required this.defaultTaxRate,
    required this.maxDiscountPercent,
    required this.allowSaleWithoutStock,
    required this.allowCreditSale,
    required this.receiptFooter,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Fallback used by the UI while the real row is loading, or when the
  /// caller has no company selected.
  factory CompanySettings.defaults(String companyId) => CompanySettings(
        companyId: companyId,
        defaultTaxRate: 0,
        maxDiscountPercent: 100,
        allowSaleWithoutStock: false,
        allowCreditSale: true,
        receiptFooter: 'شكرًا لتعاملكم معنا',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

  final String companyId;

  /// Default tax rate applied to new invoices, in percent (`0`..`100`).
  final double defaultTaxRate;

  /// Highest discount a cashier may apply, in percent (`0`..`100`).
  final double maxDiscountPercent;

  /// Whether the POS may add a line whose quantity exceeds the current
  /// available stock.
  final bool allowSaleWithoutStock;

  /// Whether credit (آجل) sales are permitted.
  final bool allowCreditSale;

  /// Free-form text printed at the bottom of every receipt.
  final String receiptFooter;

  final DateTime createdAt;
  final DateTime updatedAt;

  // ---------------------------------------------------------------------------
  // Convenience
  // ---------------------------------------------------------------------------

  /// `true` when the default tax rate is above zero.
  bool get hasTax => defaultTaxRate > 0;

  /// `true` when discounts are allowed (limit > 0).
  bool get allowsDiscount => maxDiscountPercent > 0;

  @override
  List<Object?> get props => <Object?>[
        companyId,
        defaultTaxRate,
        maxDiscountPercent,
        allowSaleWithoutStock,
        allowCreditSale,
        receiptFooter,
        createdAt,
        updatedAt,
      ];

  CompanySettings copyWith({
    double? defaultTaxRate,
    double? maxDiscountPercent,
    bool? allowSaleWithoutStock,
    bool? allowCreditSale,
    String? receiptFooter,
    DateTime? updatedAt,
  }) {
    return CompanySettings(
      companyId: companyId,
      defaultTaxRate: defaultTaxRate ?? this.defaultTaxRate,
      maxDiscountPercent: maxDiscountPercent ?? this.maxDiscountPercent,
      allowSaleWithoutStock:
          allowSaleWithoutStock ?? this.allowSaleWithoutStock,
      allowCreditSale: allowCreditSale ?? this.allowCreditSale,
      receiptFooter: receiptFooter ?? this.receiptFooter,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'CompanySettings(companyId: $companyId, '
      'tax: $defaultTaxRate, '
      'maxDiscount: $maxDiscountPercent, '
      'allowNoStock: $allowSaleWithoutStock, '
      'allowCredit: $allowCreditSale)';
}

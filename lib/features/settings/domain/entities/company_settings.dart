// lib/features/settings/domain/entities/company_settings.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Font weight used in printed documents (thermal + A4).
enum PrintFontWeight {
  normal,
  medium,
  bold;

  static PrintFontWeight fromString(String? value) {
    switch (value) {
      case 'medium':
        return PrintFontWeight.medium;
      case 'bold':
        return PrintFontWeight.bold;
      default:
        return PrintFontWeight.normal;
    }
  }

  /// String stored in the database.
  String get value => name;

  /// Arabic label for the UI.
  String get label => switch (this) {
        PrintFontWeight.normal => 'عادي',
        PrintFontWeight.medium => 'متوسط',
        PrintFontWeight.bold => 'عريض',
      };
}

/// Per-company business defaults + print preferences.
///
/// One row exists for every company (created automatically by a DB trigger
/// when a company is inserted). All values are business rules that the POS,
/// sales, and receipt printer consult before performing their work.
@immutable
class CompanySettings extends Equatable {
  const CompanySettings({
    required this.companyId,
    required this.defaultTaxRate,
    required this.maxDiscountPercent,
    required this.allowSaleWithoutStock,
    required this.allowCreditSale,
    required this.receiptFooter,
    required this.printFontScale,
    required this.printFontWeight,
    required this.printFontScaleA4,
    required this.printDirectEnabled,
    required this.createdAt,
    required this.updatedAt,
    this.logoUrl,
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
        printFontScale: 1.0,
        printFontWeight: PrintFontWeight.normal,
        printFontScaleA4: 1.0,
        printDirectEnabled: false,
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

  // ---------------------------------------------------------------------------
  // Printing preferences
  // ---------------------------------------------------------------------------

  /// Public URL of the company logo, or `null` when none uploaded.
  final String? logoUrl;

  /// Font size multiplier for thermal receipts (0.8 – 1.6).
  final double printFontScale;

  /// Font weight for printed documents.
  final PrintFontWeight printFontWeight;

  /// Font size multiplier for A4 / PDF documents (0.8 – 1.6).
  final double printFontScaleA4;

  /// Whether to skip the print preview dialog and print immediately.
  final bool printDirectEnabled;

  final DateTime createdAt;
  final DateTime updatedAt;

  // ---------------------------------------------------------------------------
  // Convenience
  // ---------------------------------------------------------------------------

  bool get hasTax => defaultTaxRate > 0;
  bool get allowsDiscount => maxDiscountPercent > 0;
  bool get hasLogo => logoUrl != null && logoUrl!.trim().isNotEmpty;

  @override
  List<Object?> get props => <Object?>[
        companyId,
        defaultTaxRate,
        maxDiscountPercent,
        allowSaleWithoutStock,
        allowCreditSale,
        receiptFooter,
        logoUrl,
        printFontScale,
        printFontWeight,
        printFontScaleA4,
        printDirectEnabled,
        createdAt,
        updatedAt,
      ];

  CompanySettings copyWith({
    double? defaultTaxRate,
    double? maxDiscountPercent,
    bool? allowSaleWithoutStock,
    bool? allowCreditSale,
    String? receiptFooter,
    String? logoUrl,
    bool clearLogo = false,
    double? printFontScale,
    PrintFontWeight? printFontWeight,
    double? printFontScaleA4,
    bool? printDirectEnabled,
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
      logoUrl: clearLogo ? null : (logoUrl ?? this.logoUrl),
      printFontScale: printFontScale ?? this.printFontScale,
      printFontWeight: printFontWeight ?? this.printFontWeight,
      printFontScaleA4: printFontScaleA4 ?? this.printFontScaleA4,
      printDirectEnabled: printDirectEnabled ?? this.printDirectEnabled,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'CompanySettings(companyId: $companyId, '
      'tax: $defaultTaxRate, '
      'maxDiscount: $maxDiscountPercent, '
      'hasLogo: $hasLogo, '
      'fontScale: $printFontScale, '
      'fontWeight: ${printFontWeight.name})';
}

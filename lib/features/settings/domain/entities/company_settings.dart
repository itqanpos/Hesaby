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

  String get value => name;

  String get label => switch (this) {
        PrintFontWeight.normal => 'عادي',
        PrintFontWeight.medium => 'متوسط',
        PrintFontWeight.bold => 'عريض',
      };
}

/// Per-company business defaults + print preferences.
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
    required this.showTaxNumberOnPrint,
    required this.showCommercialRegisterOnPrint,
    required this.showCurrencySymbol,
    required this.createdAt,
    required this.updatedAt,
    this.logoUrl,
  });

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
        showTaxNumberOnPrint: false,
        showCommercialRegisterOnPrint: false,
        showCurrencySymbol: true,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

  final String companyId;

  final double defaultTaxRate;
  final double maxDiscountPercent;
  final bool allowSaleWithoutStock;
  final bool allowCreditSale;
  final String receiptFooter;

  final String? logoUrl;
  final double printFontScale;
  final PrintFontWeight printFontWeight;
  final double printFontScaleA4;
  final bool printDirectEnabled;

  /// Whether the company tax number is printed on receipts/invoices.
  final bool showTaxNumberOnPrint;

  /// Whether the company commercial register is printed on
  /// receipts/invoices.
  final bool showCommercialRegisterOnPrint;

  /// Whether the currency symbol (ج.م) is printed next to amounts.
  final bool showCurrencySymbol;

  final DateTime createdAt;
  final DateTime updatedAt;

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
        showTaxNumberOnPrint,
        showCommercialRegisterOnPrint,
        showCurrencySymbol,
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
    bool? showTaxNumberOnPrint,
    bool? showCommercialRegisterOnPrint,
    bool? showCurrencySymbol,
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
      showTaxNumberOnPrint:
          showTaxNumberOnPrint ?? this.showTaxNumberOnPrint,
      showCommercialRegisterOnPrint: showCommercialRegisterOnPrint ??
          this.showCommercialRegisterOnPrint,
      showCurrencySymbol: showCurrencySymbol ?? this.showCurrencySymbol,
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
      'showTaxNumberOnPrint: $showTaxNumberOnPrint, '
      'showCommercialRegisterOnPrint: $showCommercialRegisterOnPrint, '
      'showCurrencySymbol: $showCurrencySymbol)';
}

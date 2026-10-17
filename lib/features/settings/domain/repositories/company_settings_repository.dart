// lib/features/settings/domain/repositories/company_settings_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/company_settings.dart';

enum CompanySettingsFailureType {
  network,
  unauthorized,
  notFound,
  invalidTaxRate,
  invalidDiscountLimit,
  invalidFooter,
  invalidResponse,
  unknown,
}

@immutable
class CompanySettingsException extends Equatable implements Exception {
  const CompanySettingsException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  final CompanySettingsFailureType type;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'CompanySettingsException(type: ${type.name})';
}

/// Contract for reading and updating per-company business settings.
abstract interface class CompanySettingsRepository {
  Future<CompanySettings> getSettings(String companyId);

  /// Applies a partial update.
  ///
  /// Passing `null` for any parameter means "leave unchanged".
  ///
  /// For the logo:
  /// * Pass [logoUrl] to set a new value.
  /// * Pass [clearLogo] = `true` to remove the current logo.
  /// * Leave both untouched (default) to keep whatever is stored.
  ///
  /// [showTaxNumberOnPrint] and [showCommercialRegisterOnPrint] control
  /// whether the company tax number and commercial register are rendered
  /// on printed receipts and A4 invoices.
  ///
  /// [showCurrencySymbol] controls whether the currency symbol (ج.م) is
  /// printed next to amounts on receipts.
  Future<CompanySettings> updateSettings({
    required String companyId,
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
  });
}

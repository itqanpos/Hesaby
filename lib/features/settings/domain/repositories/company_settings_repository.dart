// lib/features/settings/domain/repositories/company_settings_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/company_settings.dart';

/// Categories of company-settings failures that the presentation layer can
/// safely translate into localized user messages.
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
  /// Reads the settings row of [companyId].
  Future<CompanySettings> getSettings(String companyId);

  /// Applies a partial update. `null` means "leave unchanged". For the
  /// logo, pass [logoUrl] to set a new value or [clearLogo] = `true` to
  /// remove it.
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
  });
}

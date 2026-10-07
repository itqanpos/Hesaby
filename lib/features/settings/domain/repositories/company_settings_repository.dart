// lib/features/settings/domain/repositories/company_settings_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/company_settings.dart';

// ============================================================================
// Failure types
// ============================================================================

/// Categories of failures raised by [CompanySettingsRepository] operations.
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

/// Domain-level exception raised by [CompanySettingsRepository] operations.
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
  String toString() =>
      'CompanySettingsException(type: ${type.name})';
}

// ============================================================================
// Repository contract
// ============================================================================

/// Contract for reading and updating a company's business defaults.
///
/// A row is guaranteed to exist for every company (created automatically by
/// a DB trigger when the company is inserted; existing companies were
/// backfilled by the migration). The repository never creates rows — it
/// only reads and updates.
abstract interface class CompanySettingsRepository {
  /// Fetches the settings row for [companyId].
  ///
  /// Throws [CompanySettingsException] with
  /// [CompanySettingsFailureType.notFound] when no row exists. In normal
  /// operation this should never happen: the trigger guarantees a row.
  Future<CompanySettings> getSettings(String companyId);

  /// Applies a partial update to the settings row of [companyId].
  ///
  /// Only the supplied fields are written; `null` means "leave unchanged".
  /// Returns the freshly-updated row.
  ///
  /// Validation is performed by the caller *and* by the database:
  /// * `defaultTaxRate` must be in `[0, 100]`.
  /// * `maxDiscountPercent` must be in `[0, 100]`.
  /// * `receiptFooter` must be non-empty and at most 200 characters.
  Future<CompanySettings> updateSettings({
    required String companyId,
    double? defaultTaxRate,
    double? maxDiscountPercent,
    bool? allowSaleWithoutStock,
    bool? allowCreditSale,
    String? receiptFooter,
  });
}

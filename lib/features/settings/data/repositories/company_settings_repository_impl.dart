// lib/features/settings/data/repositories/company_settings_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/company_settings.dart';
import '../../domain/repositories/company_settings_repository.dart';

/// Concrete implementation of [CompanySettingsRepository] backed by Supabase.
class CompanySettingsRepositoryImpl implements CompanySettingsRepository {
  const CompanySettingsRepositoryImpl(this._client);

  final supabase.SupabaseClient? _client;

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  @override
  Future<CompanySettings> getSettings(String companyId) async {
    try {
      final supabase.SupabaseClient client = _requireClient();

      final Map<String, dynamic>? row = await client
          .from('company_settings')
          .select()
          .eq('company_id', companyId)
          .maybeSingle();

      if (row == null) {
        throw const CompanySettingsException(
          type: CompanySettingsFailureType.notFound,
          cause: 'No company_settings row for this company.',
        );
      }

      return _fromMap(row);
    } on CompanySettingsException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getSettings');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'getSettings');
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getSettings');
    }
  }

  // ---------------------------------------------------------------------------
  // Update
  // ---------------------------------------------------------------------------

  @override
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
  }) async {
    try {
      final supabase.SupabaseClient client = _requireClient();

      final Map<String, dynamic> payload = <String, dynamic>{};
      if (defaultTaxRate != null) {
        payload['default_tax_rate'] = defaultTaxRate;
      }
      if (maxDiscountPercent != null) {
        payload['max_discount_percent'] = maxDiscountPercent;
      }
      if (allowSaleWithoutStock != null) {
        payload['allow_sale_without_stock'] = allowSaleWithoutStock;
      }
      if (allowCreditSale != null) {
        payload['allow_credit_sale'] = allowCreditSale;
      }
      if (receiptFooter != null) {
        payload['receipt_footer'] = receiptFooter;
      }
      if (clearLogo) {
        payload['logo_url'] = null;
      } else if (logoUrl != null) {
        payload['logo_url'] = logoUrl;
      }
      if (printFontScale != null) {
        payload['print_font_scale'] = printFontScale;
      }
      if (printFontWeight != null) {
        payload['print_font_weight'] = printFontWeight.value;
      }
      if (printFontScaleA4 != null) {
        payload['print_font_scale_a4'] = printFontScaleA4;
      }
      if (printDirectEnabled != null) {
        payload['print_direct_enabled'] = printDirectEnabled;
      }

      if (payload.isEmpty) {
        return await getSettings(companyId);
      }

      final Map<String, dynamic> row = await client
          .from('company_settings')
          .update(payload)
          .eq('company_id', companyId)
          .select()
          .single();

      return _fromMap(row);
    } on CompanySettingsException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'updateSettings');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'updateSettings');
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'updateSettings');
    }
  }

  // ---------------------------------------------------------------------------
  // Mapping
  // ---------------------------------------------------------------------------

  static CompanySettings _fromMap(Map<String, dynamic> map) {
    return CompanySettings(
      companyId: _requireString(map, 'company_id'),
      defaultTaxRate: _requireDouble(map, 'default_tax_rate'),
      maxDiscountPercent: _requireDouble(map, 'max_discount_percent'),
      allowSaleWithoutStock:
          _requireBool(map, 'allow_sale_without_stock'),
      allowCreditSale: _requireBool(map, 'allow_credit_sale'),
      receiptFooter: _requireString(map, 'receipt_footer'),
      logoUrl: _optionalString(map, 'logo_url'),
      printFontScale: _optionalDouble(map, 'print_font_scale') ?? 1.0,
      printFontWeight:
          PrintFontWeight.fromString(_optionalString(map, 'print_font_weight')),
      printFontScaleA4: _optionalDouble(map, 'print_font_scale_a4') ?? 1.0,
      printDirectEnabled:
          _optionalBool(map, 'print_direct_enabled') ?? false,
      createdAt: _requireTimestamp(map, 'created_at'),
      updatedAt: _requireTimestamp(map, 'updated_at'),
    );
  }

  static String _requireString(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is String) return value;
    throw FormatException('CompanySettings: missing or invalid "$key".');
  }

  static String? _optionalString(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) return null;
    if (value is String) {
      final String t = value.trim();
      return t.isEmpty ? null : t;
    }
    return value.toString();
  }

  static double _requireDouble(Map<String, dynamic> map, String key) {
    final double? v = _optionalDouble(map, key);
    if (v != null) return v;
    throw FormatException('CompanySettings: "$key" is not numeric.');
  }

  static double? _optionalDouble(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static bool _requireBool(Map<String, dynamic> map, String key) {
    final bool? v = _optionalBool(map, key);
    if (v != null) return v;
    throw FormatException('CompanySettings: "$key" is not boolean.');
  }

  static bool? _optionalBool(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final String lower = value.toLowerCase();
      if (lower == 'true' || lower == 't' || lower == '1') return true;
      if (lower == 'false' || lower == 'f' || lower == '0') return false;
    }
    return null;
  }

  static DateTime _requireTimestamp(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is DateTime) return value.toUtc();
    if (value is String && value.isNotEmpty) {
      final DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    throw FormatException(
      'CompanySettings: "$key" is not a valid timestamp.',
    );
  }

  supabase.SupabaseClient _requireClient() {
    final supabase.SupabaseClient? client = _client;
    if (client == null) {
      throw const CompanySettingsException(
        type: CompanySettingsFailureType.unknown,
        cause: 'Supabase client is not initialised.',
      );
    }
    return client;
  }
}

// ============================================================================
// Error mapping
// ============================================================================

CompanySettingsException _mapPostgrest(
  supabase.PostgrestException error,
  StackTrace stackTrace, {
  required String operation,
}) {
  final CompanySettingsFailureType type = _classifyPostgrest(error);
  AppLogger.warning(
    'CompanySettings PostgREST error during "$operation" '
    'mapped to ${type.name} (code: ${error.code ?? 'n/a'}).',
  );
  return CompanySettingsException(
    type: type,
    cause: error,
    stackTrace: stackTrace,
  );
}

CompanySettingsException _mapAuth(
  supabase.AuthException error,
  StackTrace stackTrace, {
  required String operation,
}) {
  AppLogger.warning(
    'CompanySettings auth error during "$operation" mapped to unauthorized.',
  );
  return CompanySettingsException(
    type: CompanySettingsFailureType.unauthorized,
    cause: error,
    stackTrace: stackTrace,
  );
}

CompanySettingsException _mapUnknown(
  Object error,
  StackTrace stackTrace, {
  required String operation,
}) {
  final CompanySettingsFailureType type = _looksLikeNetwork(error)
      ? CompanySettingsFailureType.network
      : CompanySettingsFailureType.unknown;
  AppLogger.error(
    'Unhandled company-settings error during "$operation".',
    error,
    stackTrace,
  );
  return CompanySettingsException(
    type: type,
    cause: error,
    stackTrace: stackTrace,
  );
}

CompanySettingsFailureType _classifyPostgrest(
  supabase.PostgrestException error,
) {
  final String code = (error.code ?? '').toUpperCase();
  final String message = error.message.toLowerCase();
  final String full = error.toString().toLowerCase();

  if (code == '23514') {
    if (full.contains('company_settings_font_scale_range') ||
        full.contains('print_font_scale')) {
      return CompanySettingsFailureType.invalidResponse;
    }
    if (full.contains('company_settings_font_weight_valid')) {
      return CompanySettingsFailureType.invalidResponse;
    }
    if (full.contains('company_settings_logo_url_length')) {
      return CompanySettingsFailureType.invalidResponse;
    }
    if (full.contains('company_settings_tax_rate_valid') ||
        message.contains('default_tax_rate')) {
      return CompanySettingsFailureType.invalidTaxRate;
    }
    if (full.contains('company_settings_max_discount_valid') ||
        message.contains('max_discount_percent')) {
      return CompanySettingsFailureType.invalidDiscountLimit;
    }
    if (full.contains('company_settings_footer_length') ||
        message.contains('receipt_footer')) {
      return CompanySettingsFailureType.invalidFooter;
    }
    return CompanySettingsFailureType.invalidResponse;
  }

  if (code == 'PGRST116') return CompanySettingsFailureType.notFound;
  if (code.startsWith('42501') || code.startsWith('28')) {
    return CompanySettingsFailureType.unauthorized;
  }
  if (code.startsWith('42')) {
    return CompanySettingsFailureType.invalidResponse;
  }

  if (message.contains('permission denied') ||
      message.contains('row level security') ||
      message.contains('jwt')) {
    return CompanySettingsFailureType.unauthorized;
  }

  if (_messageLooksLikeNetwork(message)) {
    return CompanySettingsFailureType.network;
  }

  return CompanySettingsFailureType.unknown;
}

bool _looksLikeNetwork(Object error) =>
    _messageLooksLikeNetwork(error.toString().toLowerCase());

bool _messageLooksLikeNetwork(String value) {
  return value.contains('socket') ||
      value.contains('network') ||
      value.contains('connection') ||
      value.contains('timeout') ||
      value.contains('timed out') ||
      value.contains('unreachable') ||
      value.contains('failed host lookup') ||
      value.contains('clientexception');
}

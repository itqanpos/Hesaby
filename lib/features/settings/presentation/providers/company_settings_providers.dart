// lib/features/settings/presentation/providers/company_settings_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../data/repositories/company_settings_repository_impl.dart';
import '../../domain/entities/company_settings.dart';
import '../../domain/repositories/company_settings_repository.dart';

// ============================================================================
// Repository
// ============================================================================

final Provider<CompanySettingsRepository>
    companySettingsRepositoryProvider =
    Provider<CompanySettingsRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return CompanySettingsRepositoryImpl(client);
});

// ============================================================================
// Settings notifier
// ============================================================================

class CompanySettingsNotifier extends AsyncNotifier<CompanySettings> {
  String? _companyId;
  bool _isDisposed = false;

  @override
  Future<CompanySettings> build() async {
    _isDisposed = false;
    ref.onDispose(() => _isDisposed = true);

    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );

    _companyId = companyId;

    if (companyId == null) {
      return CompanySettings.defaults('');
    }

    return ref.read(companySettingsRepositoryProvider).getSettings(companyId);
  }

  /// Applies a partial update. Optimistic: publishes the new state
  /// immediately, then persists; on failure restores the previous value.
  Future<void> updateSettings({
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
    final String? companyId = _companyId;
    if (companyId == null || companyId.isEmpty) {
      throw const CompanySettingsException(
        type: CompanySettingsFailureType.unauthorized,
        cause: 'No company is currently selected.',
      );
    }

    final CompanySettings? previous = state.valueOrNull;

    if (previous != null && !_isDisposed) {
      state = AsyncData<CompanySettings>(
        previous.copyWith(
          defaultTaxRate: defaultTaxRate,
          maxDiscountPercent: maxDiscountPercent,
          allowSaleWithoutStock: allowSaleWithoutStock,
          allowCreditSale: allowCreditSale,
          receiptFooter: receiptFooter,
          logoUrl: logoUrl,
          clearLogo: clearLogo,
          printFontScale: printFontScale,
          printFontWeight: printFontWeight,
          printFontScaleA4: printFontScaleA4,
          printDirectEnabled: printDirectEnabled,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    }

    try {
      final CompanySettings fresh = await ref
          .read(companySettingsRepositoryProvider)
          .updateSettings(
            companyId: companyId,
            defaultTaxRate: defaultTaxRate,
            maxDiscountPercent: maxDiscountPercent,
            allowSaleWithoutStock: allowSaleWithoutStock,
            allowCreditSale: allowCreditSale,
            receiptFooter: receiptFooter,
            logoUrl: logoUrl,
            clearLogo: clearLogo,
            printFontScale: printFontScale,
            printFontWeight: printFontWeight,
            printFontScaleA4: printFontScaleA4,
            printDirectEnabled: printDirectEnabled,
          );

      if (!_isDisposed) {
        state = AsyncData<CompanySettings>(fresh);
      }
    } catch (error, stackTrace) {
      if (!_isDisposed) {
        if (previous != null) {
          state = AsyncData<CompanySettings>(previous);
        } else {
          state = AsyncError<CompanySettings>(error, stackTrace);
        }
      }
      rethrow;
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final AsyncNotifierProvider<CompanySettingsNotifier, CompanySettings>
    companySettingsProvider =
    AsyncNotifierProvider<CompanySettingsNotifier, CompanySettings>(
  CompanySettingsNotifier.new,
);

// ============================================================================
// Derived providers — business settings
// ============================================================================

final Provider<double> defaultTaxRateProvider = Provider<double>((ref) {
  final CompanySettings settings =
      ref.watch(companySettingsProvider).valueOrNull ??
          CompanySettings.defaults('');
  return settings.defaultTaxRate;
});

final Provider<double> maxDiscountPercentProvider = Provider<double>((ref) {
  final CompanySettings settings =
      ref.watch(companySettingsProvider).valueOrNull ??
          CompanySettings.defaults('');
  return settings.maxDiscountPercent;
});

final Provider<bool> allowSaleWithoutStockProvider =
    Provider<bool>((ref) {
  final CompanySettings settings =
      ref.watch(companySettingsProvider).valueOrNull ??
          CompanySettings.defaults('');
  return settings.allowSaleWithoutStock;
});

final Provider<bool> allowCreditSaleProvider = Provider<bool>((ref) {
  final CompanySettings settings =
      ref.watch(companySettingsProvider).valueOrNull ??
          CompanySettings.defaults('');
  return settings.allowCreditSale;
});

final Provider<String> receiptFooterProvider = Provider<String>((ref) {
  final CompanySettings settings =
      ref.watch(companySettingsProvider).valueOrNull ??
          CompanySettings.defaults('');
  return settings.receiptFooter;
});

// ============================================================================
// Derived providers — print settings
// ============================================================================

/// Public URL of the company logo, or `null` when none uploaded.
final Provider<String?> companyLogoUrlProvider = Provider<String?>((ref) {
  return ref.watch(companySettingsProvider).valueOrNull?.logoUrl;
});

/// Font scale for thermal receipts (0.8 – 1.6).
final Provider<double> printFontScaleProvider = Provider<double>((ref) {
  final CompanySettings settings =
      ref.watch(companySettingsProvider).valueOrNull ??
          CompanySettings.defaults('');
  return settings.printFontScale;
});

/// Font weight for printed documents.
final Provider<PrintFontWeight> printFontWeightProvider =
    Provider<PrintFontWeight>((ref) {
  final CompanySettings settings =
      ref.watch(companySettingsProvider).valueOrNull ??
          CompanySettings.defaults('');
  return settings.printFontWeight;
});

/// Font scale for A4 / PDF documents (0.8 – 1.6).
final Provider<double> printFontScaleA4Provider = Provider<double>((ref) {
  final CompanySettings settings =
      ref.watch(companySettingsProvider).valueOrNull ??
          CompanySettings.defaults('');
  return settings.printFontScaleA4;
});

/// Whether printing skips the preview dialog.
final Provider<bool> printDirectEnabledProvider = Provider<bool>((ref) {
  final CompanySettings settings =
      ref.watch(companySettingsProvider).valueOrNull ??
          CompanySettings.defaults('');
  return settings.printDirectEnabled;
});

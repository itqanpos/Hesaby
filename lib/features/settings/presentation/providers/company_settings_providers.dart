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
// Repository provider
// ============================================================================

/// The application's company-settings repository.
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

/// Provides and updates the settings of the currently selected company.
///
/// The notifier watches [companyContextProvider]; when the selected company
/// changes, the settings are re-fetched automatically. When no company is
/// selected, it resolves to [CompanySettings.defaults] for an empty id so
/// the UI always has a non-null object to render.
///
/// Naming note: `AsyncNotifier` already declares an `update` method with a
/// different signature, so the mutating method here is named
/// `updateSettings`.
class CompanySettingsNotifier extends AsyncNotifier<CompanySettings> {
  /// Company id the current state belongs to.
  ///
  /// Used to reject stale responses after a company switch.
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
      // No company selected — expose safe defaults so the UI can render
      // without a null check. The id is empty to make it obvious the value
      // is not persisted.
      return CompanySettings.defaults('');
    }

    return ref.read(companySettingsRepositoryProvider).getSettings(companyId);
  }

  /// Applies a partial update to the current company's settings.
  ///
  /// Only the supplied fields are written; `null` means "leave unchanged".
  /// Updates are optimistic: the new state is published immediately, then
  /// persisted; on failure the previous value is restored and the error is
  /// re-thrown so the UI can show a message.
  Future<void> updateSettings({
    double? defaultTaxRate,
    double? maxDiscountPercent,
    bool? allowSaleWithoutStock,
    bool? allowCreditSale,
    String? receiptFooter,
  }) async {
    final String? companyId = _companyId;
    if (companyId == null || companyId.isEmpty) {
      throw const CompanySettingsException(
        type: CompanySettingsFailureType.unauthorized,
        cause: 'No company is currently selected.',
      );
    }

    final CompanySettings? previous = state.valueOrNull;

    // ---- Optimistic update ----
    if (previous != null && !_isDisposed) {
      state = AsyncData<CompanySettings>(
        previous.copyWith(
          defaultTaxRate: defaultTaxRate,
          maxDiscountPercent: maxDiscountPercent,
          allowSaleWithoutStock: allowSaleWithoutStock,
          allowCreditSale: allowCreditSale,
          receiptFooter: receiptFooter,
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

  /// Re-fetches the settings from the server.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

/// Provides the settings of the currently selected company.
final AsyncNotifierProvider<CompanySettingsNotifier, CompanySettings>
    companySettingsProvider =
    AsyncNotifierProvider<CompanySettingsNotifier, CompanySettings>(
  CompanySettingsNotifier.new,
);

// ============================================================================
// Derived providers — small, type-safe accessors for common fields
// ============================================================================

/// Default tax rate for new invoices, in percent. `0` while loading.
final Provider<double> defaultTaxRateProvider = Provider<double>((ref) {
  final CompanySettings settings =
      ref.watch(companySettingsProvider).valueOrNull ??
          CompanySettings.defaults('');
  return settings.defaultTaxRate;
});

/// Maximum discount a cashier may apply, in percent. `100` while loading.
final Provider<double> maxDiscountPercentProvider = Provider<double>((ref) {
  final CompanySettings settings =
      ref.watch(companySettingsProvider).valueOrNull ??
          CompanySettings.defaults('');
  return settings.maxDiscountPercent;
});

/// Whether the POS may sell products with insufficient stock.
final Provider<bool> allowSaleWithoutStockProvider =
    Provider<bool>((ref) {
  final CompanySettings settings =
      ref.watch(companySettingsProvider).valueOrNull ??
          CompanySettings.defaults('');
  return settings.allowSaleWithoutStock;
});

/// Whether credit (آجل) sales are permitted.
final Provider<bool> allowCreditSaleProvider = Provider<bool>((ref) {
  final CompanySettings settings =
      ref.watch(companySettingsProvider).valueOrNull ??
          CompanySettings.defaults('');
  return settings.allowCreditSale;
});

/// Receipt footer text shown on every printed document.
final Provider<String> receiptFooterProvider = Provider<String>((ref) {
  final CompanySettings settings =
      ref.watch(companySettingsProvider).valueOrNull ??
          CompanySettings.defaults('');
  return settings.receiptFooter;
});

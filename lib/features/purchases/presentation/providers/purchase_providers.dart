// lib/features/purchases/presentation/providers/purchase_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../data/datasources/purchase_remote_datasource.dart';
import '../../data/repositories/purchase_repository_impl.dart';
import '../../domain/entities/purchase.dart';
import '../../domain/entities/purchase_item.dart';
import '../../domain/repositories/purchase_repository.dart';

/// The application's purchase repository.
///
/// Builds a [PurchaseRepositoryImpl] from the active Supabase client. When
/// Supabase is not initialised (for example when credentials were not
/// provided at build time), the underlying data source wraps a `null`
/// client and every operation fails predictably with a
/// [PurchaseFailureType.unknown] exception instead of throwing a low-level
/// state error.
final Provider<PurchaseRepository> purchaseRepositoryProvider =
    Provider<PurchaseRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return PurchaseRepositoryImpl(PurchaseRemoteDataSource(client));
});

// -----------------------------------------------------------------------------
// Purchases list
// -----------------------------------------------------------------------------

/// Provides the list of purchases for the currently selected company.
///
/// The notifier reloads automatically whenever [companyContextProvider]
/// reports a different `currentCompany.id`. When no company is selected, it
/// resolves to an empty list.
///
/// Note on naming: [AsyncNotifier] already declares `update`. Business
/// operations are therefore named `createPurchase`, `updateDraft`,
/// `confirmPurchase` and `cancelPurchase`.
class PurchasesNotifier extends AsyncNotifier<List<Purchase>> {
  @override
  Future<List<Purchase>> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState state) => state.currentCompany?.id,
      ),
    );

    if (companyId == null) {
      return const <Purchase>[];
    }

    return ref.read(purchaseRepositoryProvider).listPurchases(companyId);
  }

  /// Creates a new draft purchase with its items.
  ///
  /// Throws [PurchaseException] when there is no current company, or when
  /// the underlying repository rejects the operation.
  Future<Purchase> createPurchase({
    required String branchId,
    required String supplierId,
    required DateTime purchaseDate,
    List<PurchaseItemDraft> items = const <PurchaseItemDraft>[],
    String? invoiceNumber,
    double discount = 0,
    double taxAmount = 0,
    String? notes,
  }) async {
    final String companyId = _requireCurrentCompanyId();

    final Purchase created =
        await ref.read(purchaseRepositoryProvider).createPurchase(
              companyId: companyId,
              branchId: branchId,
              supplierId: supplierId,
              purchaseDate: purchaseDate,
              items: items,
              invoiceNumber: invoiceNumber,
              discount: discount,
              taxAmount: taxAmount,
              notes: notes,
            );

    // The new purchase has just been created; no items provider exists yet
    // for its id, so no per-id invalidation is needed here.
    await _reload();
    return created;
  }

  /// Replaces the header and items of an existing draft purchase.
  ///
  /// Invalidates both the list and the item-level provider for the affected
  /// purchase.
  Future<Purchase> updateDraft({
    required String purchaseId,
    required String branchId,
    required String supplierId,
    required DateTime purchaseDate,
    required List<PurchaseItemDraft> items,
    String? invoiceNumber,
    double discount = 0,
    double taxAmount = 0,
    String? notes,
  }) async {
    final String companyId = _requireCurrentCompanyId();

    final Purchase updated =
        await ref.read(purchaseRepositoryProvider).updateDraft(
              purchaseId: purchaseId,
              companyId: companyId,
              branchId: branchId,
              supplierId: supplierId,
              purchaseDate: purchaseDate,
              items: items,
              invoiceNumber: invoiceNumber,
              discount: discount,
              taxAmount: taxAmount,
              notes: notes,
            );

    ref.invalidate(purchaseItemsProvider(purchaseId));
    await _reload();
    return updated;
  }

  /// Confirms a draft purchase.
  ///
  /// The database trigger inserts the corresponding `purchase_in` stock
  /// movements. On success, both the list and the item-level provider are
  /// invalidated so the UI reflects the new status and (indirectly) the
  /// updated stock.
  Future<Purchase> confirmPurchase(String purchaseId) async {
    final Purchase confirmed =
        await ref.read(purchaseRepositoryProvider).confirmPurchase(purchaseId);

    ref.invalidate(purchaseItemsProvider(purchaseId));
    await _reload();
    return confirmed;
  }

  /// Cancels a purchase.
  ///
  /// A draft purchase is cancelled without touching stock. A confirmed
  /// purchase has its movements reversed; if that reversal would drive a
  /// stock balance negative, the operation fails with
  /// [PurchaseFailureType.insufficientStock].
  Future<Purchase> cancelPurchase(String purchaseId) async {
    final Purchase cancelled =
        await ref.read(purchaseRepositoryProvider).cancelPurchase(purchaseId);

    ref.invalidate(purchaseItemsProvider(purchaseId));
    await _reload();
    return cancelled;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  String _requireCurrentCompanyId() {
    final CompanyContextState context = ref.read(companyContextProvider);
    final String? companyId = context.currentCompany?.id;
    if (companyId == null) {
      throw const PurchaseException(
        type: PurchaseFailureType.unauthorized,
        cause: 'No company is currently selected.',
      );
    }
    return companyId;
  }

  Future<void> _reload() async {
    ref.invalidateSelf();
    await future;
  }
}

/// Provides the current company's purchases.
final AsyncNotifierProvider<PurchasesNotifier, List<Purchase>>
    purchasesProvider =
    AsyncNotifierProvider<PurchasesNotifier, List<Purchase>>(
  PurchasesNotifier.new,
);

// -----------------------------------------------------------------------------
// Purchase items (per purchase)
// -----------------------------------------------------------------------------

/// Provides the line items of a single purchase, keyed by `purchaseId`.
///
/// This is a read-only derived view over `purchase_items`. It is
/// invalidated explicitly by [PurchasesNotifier] after any mutation that
/// touches the purchase's lines (`updateDraft`, `confirmPurchase`,
/// `cancelPurchase`).
class PurchaseItemsNotifier
    extends FamilyAsyncNotifier<List<PurchaseItem>, String> {
  @override
  Future<List<PurchaseItem>> build(String purchaseId) async {
    if (purchaseId.isEmpty) {
      return const <PurchaseItem>[];
    }
    return ref.read(purchaseRepositoryProvider).listPurchaseItems(purchaseId);
  }

  /// Reloads the items from the backend.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

/// Provides the line items of a single purchase, keyed by `purchaseId`.
///
/// No explicit type annotation is used: `AsyncNotifierProvider.family` is a
/// factory constructor, not a type. Dart infers the correct
/// `AsyncNotifierProviderFamily<...>` from the value expression.
final purchaseItemsProvider = AsyncNotifierProvider.family<
    PurchaseItemsNotifier, List<PurchaseItem>, String>(
  PurchaseItemsNotifier.new,
);

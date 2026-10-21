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

  // ⬇️ إضافة paidAmount و paymentMethod
  Future<Purchase> createPurchase({
    required String branchId,
    required String supplierId,
    required DateTime purchaseDate,
    List<PurchaseItemDraft> items = const <PurchaseItemDraft>[],
    String? invoiceNumber,
    double discount = 0,
    double taxAmount = 0,
    double paidAmount = 0,
    String paymentMethod = 'cash',
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
              paidAmount: paidAmount,
              paymentMethod: paymentMethod,
              notes: notes,
            );

    await _reload();
    return created;
  }

  // ⬇️ إضافة paidAmount و paymentMethod
  Future<Purchase> updateDraft({
    required String purchaseId,
    required String branchId,
    required String supplierId,
    required DateTime purchaseDate,
    required List<PurchaseItemDraft> items,
    String? invoiceNumber,
    double discount = 0,
    double taxAmount = 0,
    double paidAmount = 0,
    String paymentMethod = 'cash',
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
              paidAmount: paidAmount,
              paymentMethod: paymentMethod,
              notes: notes,
            );

    ref.invalidate(purchaseItemsProvider(purchaseId));
    await _reload();
    return updated;
  }

  Future<Purchase> confirmPurchase(String purchaseId) async {
    final Purchase confirmed =
        await ref.read(purchaseRepositoryProvider).confirmPurchase(purchaseId);

    ref.invalidate(purchaseItemsProvider(purchaseId));
    await _reload();
    return confirmed;
  }

  Future<Purchase> cancelPurchase(String purchaseId) async {
    final Purchase cancelled =
        await ref.read(purchaseRepositoryProvider).cancelPurchase(purchaseId);

    ref.invalidate(purchaseItemsProvider(purchaseId));
    await _reload();
    return cancelled;
  }

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

final AsyncNotifierProvider<PurchasesNotifier, List<Purchase>>
    purchasesProvider =
    AsyncNotifierProvider<PurchasesNotifier, List<Purchase>>(
  PurchasesNotifier.new,
);

class PurchaseItemsNotifier
    extends FamilyAsyncNotifier<List<PurchaseItem>, String> {
  @override
  Future<List<PurchaseItem>> build(String purchaseId) async {
    if (purchaseId.isEmpty) {
      return const <PurchaseItem>[];
    }
    return ref.read(purchaseRepositoryProvider).listPurchaseItems(purchaseId);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final purchaseItemsProvider = AsyncNotifierProvider.family<
    PurchaseItemsNotifier, List<PurchaseItem>, String>(
  PurchaseItemsNotifier.new,
);

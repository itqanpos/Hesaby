// lib/features/inventory/presentation/providers/inventory_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../data/datasources/inventory_remote_datasource.dart';
import '../../data/repositories/inventory_repository_impl.dart';
import '../../domain/entities/inventory_balance.dart';
import '../../domain/entities/stock_movement.dart';
import '../../domain/repositories/inventory_repository.dart';

/// The application's inventory repository.
///
/// Builds an [InventoryRepositoryImpl] from the active Supabase client. When
/// Supabase is not initialised (for example when credentials were not
/// provided at build time), the underlying data source wraps a `null`
/// client and every operation fails predictably with an
/// [InventoryFailureType.unknown] exception instead of throwing a
/// low-level state error.
final Provider<InventoryRepository> inventoryRepositoryProvider =
    Provider<InventoryRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return InventoryRepositoryImpl(InventoryRemoteDataSource(client));
});

// -----------------------------------------------------------------------------
// Balances
// -----------------------------------------------------------------------------

/// Provides the inventory balances of a single branch, keyed by `branchId`.
///
/// The notifier reloads automatically whenever [companyContextProvider]
/// reports a different `currentCompany.id`. When no company is selected, or
/// the branch has no balances, it resolves to an empty list.
///
/// Mutations are exposed as `recordMovement`, which appends to the ledger
/// and lets the database trigger update both the balances and any derived
/// view. The notifier itself never writes to `inventory_balances` directly:
/// that table is derived state.
class InventoryBalancesNotifier
    extends FamilyAsyncNotifier<List<InventoryBalance>, String> {
  @override
  Future<List<InventoryBalance>> build(String branchId) async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState state) => state.currentCompany?.id,
      ),
    );

    if (companyId == null || branchId.isEmpty) {
      return const <InventoryBalance>[];
    }

    return ref.read(inventoryRepositoryProvider).listBalances(
          companyId,
          branchId,
          onlyInStock: true,
        );
  }

  /// Records a stock movement for the current branch and reloads the list.
  ///
  /// The signed [quantity] determines the direction. The database trigger
  /// applies the change to the balance table in the same transaction; on
  /// failure (for example, insufficient stock) nothing is persisted.
  ///
  /// Throws [InventoryException] when the movement is rejected. The caller
  /// is expected to translate the failure type into a localized message.
  Future<StockMovement> recordMovement({
    required String productId,
    required String movementType,
    required double quantity,
    double? unitCost,
    String? referenceType,
    String? referenceId,
    String? notes,
  }) async {
    final String branchId = arg;
    final String companyId = _requireCurrentCompanyId();

    final StockMovement created =
        await ref.read(inventoryRepositoryProvider).recordMovement(
              companyId: companyId,
              branchId: branchId,
              productId: productId,
              movementType: movementType,
              quantity: quantity,
              unitCost: unitCost,
              referenceType: referenceType,
              referenceId: referenceId,
              notes: notes,
            );

    // Reload balances, and also invalidate any cached movement list for the
    // same branch so both views stay coherent.
    ref.invalidate(stockMovementsProvider(branchId));
    await _reload();

    return created;
  }

  /// Reloads the balances from the backend.
  Future<void> refresh() => _reload();

  String _requireCurrentCompanyId() {
    final CompanyContextState context = ref.read(companyContextProvider);
    final String? companyId = context.currentCompany?.id;
    if (companyId == null) {
      throw const InventoryException(
        type: InventoryFailureType.unauthorized,
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

/// Provides the balances of a single branch, keyed by `branchId`.
///
/// No explicit type annotation is used: `AsyncNotifierProvider.family` is a
/// factory constructor, not a type. Dart infers the correct
/// `AsyncNotifierProviderFamily<...>` from the value expression.
final inventoryBalancesProvider = AsyncNotifierProvider.family<
    InventoryBalancesNotifier, List<InventoryBalance>, String>(
  InventoryBalancesNotifier.new,
);

// -----------------------------------------------------------------------------
// Movements (ledger view)
// -----------------------------------------------------------------------------

/// Provides the most recent stock movements of a single branch, keyed by
/// `branchId`.
///
/// This is a read-only, derived view over the append-only ledger. It uses
/// the same company context as [InventoryBalancesNotifier], and reloads
/// when the company changes.
class StockMovementsNotifier
    extends FamilyAsyncNotifier<List<StockMovement>, String> {
  @override
  Future<List<StockMovement>> build(String branchId) async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState state) => state.currentCompany?.id,
      ),
    );

    if (companyId == null || branchId.isEmpty) {
      return const <StockMovement>[];
    }

    return ref.read(inventoryRepositoryProvider).listMovements(
          companyId,
          branchId: branchId,
        );
  }

  /// Reloads the movements from the backend.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

/// Provides the recent movements of a single branch, keyed by `branchId`.
final stockMovementsProvider = AsyncNotifierProvider.family<
    StockMovementsNotifier, List<StockMovement>, String>(
  StockMovementsNotifier.new,
);

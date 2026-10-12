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
  /// [quantity] must already be in the product's base unit — the caller
  /// (the adjustment dialog) applies any unit conversion before calling
  /// here. [unitId] is stored verbatim for reporting.
  Future<StockMovement> recordMovement({
    required String productId,
    required String movementType,
    required double quantity,
    String? unitId,
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
              unitId: unitId,
              unitCost: unitCost,
              referenceType: referenceType,
              referenceId: referenceId,
              notes: notes,
            );

    ref.invalidate(stockMovementsProvider(branchId));
    await _reload();

    return created;
  }

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

final inventoryBalancesProvider = AsyncNotifierProvider.family<
    InventoryBalancesNotifier, List<InventoryBalance>, String>(
  InventoryBalancesNotifier.new,
);

// -----------------------------------------------------------------------------
// Movements (ledger view)
// -----------------------------------------------------------------------------

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

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final stockMovementsProvider = AsyncNotifierProvider.family<
    StockMovementsNotifier, List<StockMovement>, String>(
  StockMovementsNotifier.new,
);

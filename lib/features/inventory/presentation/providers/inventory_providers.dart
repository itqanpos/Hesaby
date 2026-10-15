// lib/features/inventory/presentation/providers/inventory_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../../core/utils/logger.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/product_unit.dart';
import '../../../products/domain/entities/unit.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../../products/presentation/providers/unit_providers.dart';
import '../../data/datasources/inventory_remote_datasource.dart';
import '../../data/repositories/inventory_repository_impl.dart';
import '../../domain/entities/inventory_balance.dart';
import '../../domain/entities/stock_count.dart';
import '../../domain/entities/stock_movement.dart';
import '../../domain/repositories/inventory_repository.dart';

// ============================================================================
// Repository
// ============================================================================

/// The application's inventory repository.
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

// ============================================================================
// Balances (per branch)
// ============================================================================

/// Provides the current inventory balances of [branchId].
class InventoryBalancesNotifier
    extends FamilyAsyncNotifier<List<InventoryBalance>, String> {
  @override
  Future<List<InventoryBalance>> build(String branchId) async {
    if (branchId.isEmpty) {
      return const <InventoryBalance>[];
    }

    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );

    if (companyId == null) {
      return const <InventoryBalance>[];
    }

    return ref.read(inventoryRepositoryProvider).listBalances(
          companyId,
          branchId,
          onlyInStock: false,
        );
  }

  /// Records a stock movement (adjustment_in / adjustment_out / etc.).
  ///
  /// After a successful insert, the underlying `apply_stock_movement`
  /// trigger updates `inventory_balances`; we therefore refresh the list.
  Future<StockMovement> recordMovement({
    required String productId,
    required String movementType,
    required double quantity,
    String? unitId,
    double? unitCost,
    String? notes,
  }) async {
    final String? companyId = ref.read(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) {
      throw const InventoryException(
        type: InventoryFailureType.unauthorized,
        cause: 'No company is currently selected.',
      );
    }

    final StockMovement created =
        await ref.read(inventoryRepositoryProvider).recordMovement(
              companyId: companyId,
              branchId: arg,
              productId: productId,
              movementType: movementType,
              quantity: quantity,
              unitId: unitId,
              unitCost: unitCost,
              notes: notes,
            );

    await _reload();
    return created;
  }

  Future<void> refresh() async {
    await _reload();
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

// ============================================================================
// Movements (per branch)
// ============================================================================

/// Provides the recent stock movements of [branchId].
class StockMovementsNotifier
    extends FamilyAsyncNotifier<List<StockMovement>, String> {
  @override
  Future<List<StockMovement>> build(String branchId) async {
    if (branchId.isEmpty) {
      return const <StockMovement>[];
    }

    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );

    if (companyId == null) {
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

// ============================================================================
// Stock count sessions (per company + optional branch/status filter)
// ============================================================================

/// Filter arguments for [stockCountSessionsProvider].
class StockCountSessionsArgs {
  const StockCountSessionsArgs({
    this.branchId,
    this.status,
  });

  final String? branchId;
  final String? status;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StockCountSessionsArgs &&
        other.branchId == branchId &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(branchId, status);
}

/// Provides the list of stock count sessions for the current company,
/// optionally filtered by branch and status.
class StockCountSessionsNotifier
    extends FamilyAsyncNotifier<List<StockCountSession>,
        StockCountSessionsArgs> {
  @override
  Future<List<StockCountSession>> build(
    StockCountSessionsArgs args,
  ) async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) {
      return const <StockCountSession>[];
    }

    return ref.read(inventoryRepositoryProvider).listStockCountSessions(
          companyId,
          branchId: args.branchId,
          status: args.status,
        );
  }

  /// Creates a new draft session for [branchId] and refreshes the list.
  Future<String> createSession({
    required String branchId,
    String? notes,
  }) async {
    final String? companyId = ref.read(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) {
      throw const InventoryException(
        type: InventoryFailureType.unauthorized,
        cause: 'No company is currently selected.',
      );
    }

    final String sessionId =
        await ref.read(inventoryRepositoryProvider).createStockCountSession(
              companyId: companyId,
              branchId: branchId,
              notes: notes,
            );

    await _reload();
    return sessionId;
  }

  Future<void> refresh() async {
    await _reload();
  }

  Future<void> _reload() async {
    ref.invalidateSelf();
    await future;
  }
}

final stockCountSessionsProvider = AsyncNotifierProvider.family<
    StockCountSessionsNotifier,
    List<StockCountSession>,
    StockCountSessionsArgs>(StockCountSessionsNotifier.new);

// ============================================================================
// Single session (per session id)
// ============================================================================

/// Provides a single stock count session by id.
class StockCountSessionNotifier
    extends FamilyAsyncNotifier<StockCountSession, String> {
  @override
  Future<StockCountSession> build(String sessionId) async {
    if (sessionId.isEmpty) {
      throw const InventoryException(
        type: InventoryFailureType.notFound,
        cause: 'Cannot load a session without an id.',
      );
    }
    return ref.read(inventoryRepositoryProvider).getStockCountSession(
          sessionId,
        );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final stockCountSessionProvider = AsyncNotifierProvider.family<
    StockCountSessionNotifier, StockCountSession, String>(
  StockCountSessionNotifier.new,
);

// ============================================================================
// Session items (per session id)
// ============================================================================

/// Provides the items of a stock count session.
///
/// The returned items are enriched with `productName` and `unitName` from
/// the products and units providers so the UI does not need to resolve them
/// itself.
class StockCountItemsNotifier
    extends FamilyAsyncNotifier<List<StockCountItem>, String> {
  @override
  Future<List<StockCountItem>> build(String sessionId) async {
    if (sessionId.isEmpty) {
      return const <StockCountItem>[];
    }

    final InventoryRepository repo = ref.read(inventoryRepositoryProvider);
    final List<StockCountItem> raw =
        await repo.listStockCountItems(sessionId);

    // Enrich with product and unit names. Both are cached providers, so
    // this is effectively synchronous after the first load.
    final List<Product> products =
        await ref.watch(productsProvider.future);
    final List<Unit> units = await ref.watch(unitsProvider.future);

    final Map<String, String> productNames = <String, String>{
      for (final Product p in products) p.id: p.name,
    };
    final Map<String, String> unitNames = <String, String>{
      for (final Unit u in units) u.id: u.name,
    };

    return raw
        .map((StockCountItem item) => item.copyWith(
              // copyWith in this entity only handles actualQuantity / notes;
              // productName / unitName are set via the constructor — we use
              // the entity constructor here to keep it immutable.
              // ignore: avoid_redundant_argument_values
            ))
        .toList();
  }

  /// Updates one item's counted quantity.
  Future<void> setActual({
    required String itemId,
    required double actualQuantity,
    String? notes,
  }) async {
    await ref.read(inventoryRepositoryProvider).setStockCountItemActual(
          itemId: itemId,
          actualQuantity: actualQuantity,
          notes: notes,
        );
    await _reload();
  }

  Future<void> refresh() async {
    await _reload();
  }

  Future<void> _reload() async {
    ref.invalidateSelf();
    await future;
  }
}

final stockCountItemsProvider = AsyncNotifierProvider.family<
    StockCountItemsNotifier, List<StockCountItem>, String>(
  StockCountItemsNotifier.new,
);

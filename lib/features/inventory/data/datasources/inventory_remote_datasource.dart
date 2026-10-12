// lib/features/inventory/data/datasources/inventory_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../domain/repositories/inventory_repository.dart';
import '../models/inventory_balance_model.dart';
import '../models/stock_movement_model.dart';

/// Thin wrapper around the Supabase queries for `inventory_balances` and
/// `stock_movements`.
class InventoryRemoteDataSource {
  const InventoryRemoteDataSource(this._client);

  final SupabaseClient? _client;

  bool get isAvailable => _client != null;

  static const int defaultMovementLimit = 100;

  // ---------------------------------------------------------------------------
  // Balances (read-only)
  // ---------------------------------------------------------------------------

  Future<List<InventoryBalanceModel>> listBalances(
    String companyId,
    String branchId, {
    required bool onlyInStock,
  }) async {
    final SupabaseClient client = _requireClient();

    var query = client
        .from('inventory_balances')
        .select()
        .eq('company_id', companyId)
        .eq('branch_id', branchId);

    if (onlyInStock) {
      query = query.gt('quantity_on_hand', 0);
    }

    final List<Map<String, dynamic>> rows =
        await query.order('product_id', ascending: true);

    return rows.map(InventoryBalanceModel.fromMap).toList(growable: false);
  }

  Future<InventoryBalanceModel> getBalance({
    required String companyId,
    required String branchId,
    required String productId,
  }) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> row = await client
        .from('inventory_balances')
        .select()
        .eq('company_id', companyId)
        .eq('branch_id', branchId)
        .eq('product_id', productId)
        .single();

    return InventoryBalanceModel.fromMap(row);
  }

  // ---------------------------------------------------------------------------
  // Movements (append-only)
  // ---------------------------------------------------------------------------

  Future<List<StockMovementModel>> listMovements(
    String companyId, {
    String? branchId,
    String? productId,
    int? limit,
  }) async {
    final SupabaseClient client = _requireClient();

    final int effectiveLimit =
        (limit == null || limit <= 0) ? defaultMovementLimit : limit;

    var query = client
        .from('stock_movements')
        .select()
        .eq('company_id', companyId);

    if (branchId != null) {
      query = query.eq('branch_id', branchId);
    }
    if (productId != null) {
      query = query.eq('product_id', productId);
    }

    final List<Map<String, dynamic>> rows = await query
        .order('created_at', ascending: false)
        .limit(effectiveLimit);

    return rows.map(StockMovementModel.fromMap).toList(growable: false);
  }

  /// Inserts a stock movement and returns the created row.
  ///
  /// [quantity] is expected to already be in the product's **base** unit —
  /// the caller multiplies any user-entered quantity by the unit's
  /// conversion factor before calling this method. [unitId] is stored
  /// verbatim for informational purposes.
  Future<StockMovementModel> recordMovement({
    required String companyId,
    required String branchId,
    required String productId,
    required String movementType,
    required double quantity,
    String? unitId,
    double? unitCost,
    String? referenceType,
    String? referenceId,
    String? notes,
  }) async {
    final SupabaseClient client = _requireClient();

    final String? createdBy = client.auth.currentUser?.id;

    final Map<String, dynamic> payload = <String, dynamic>{
      'company_id': companyId,
      'branch_id': branchId,
      'product_id': productId,
      'movement_type': movementType,
      'quantity': quantity,
      if (unitId != null) 'unit_id': unitId,
      if (unitCost != null) 'unit_cost': unitCost,
      if (referenceType != null) 'reference_type': referenceType,
      if (referenceId != null) 'reference_id': referenceId,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (createdBy != null) 'created_by': createdBy,
    };

    final Map<String, dynamic> row = await client
        .from('stock_movements')
        .insert(payload)
        .select()
        .single();

    return StockMovementModel.fromMap(row);
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  SupabaseClient _requireClient() {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw const InventoryException(
        type: InventoryFailureType.unknown,
        cause: _supabaseUnavailableMessage,
      );
    }
    return client;
  }

  static const String _supabaseUnavailableMessage =
      'Supabase client is not initialised.';
}

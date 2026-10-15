// lib/features/inventory/data/datasources/inventory_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../domain/repositories/inventory_repository.dart';
import '../models/inventory_balance_model.dart';
import '../models/stock_count_model.dart';
import '../models/stock_movement_model.dart';

/// Thin wrapper around the Supabase queries for `inventory_balances`,
/// `stock_movements`, and the two stock-count tables.
class InventoryRemoteDataSource {
  const InventoryRemoteDataSource(this._client);

  final SupabaseClient? _client;

  bool get isAvailable => _client != null;

  static const int defaultMovementLimit = 100;
  static const int defaultSessionLimit = 100;
  static const int defaultItemLimit = 5000;
  static const int inFilterChunkSize = 150;

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
  // Stock count sessions
  // ---------------------------------------------------------------------------

  /// Lists the stock-count sessions of [companyId].
  ///
  /// When [branchId] is provided, only that branch's sessions are returned.
  /// When [status] is provided, only sessions with that status are returned.
  Future<List<StockCountSessionModel>> listStockCountSessions(
    String companyId, {
    String? branchId,
    String? status,
    int? limit,
  }) async {
    final SupabaseClient client = _requireClient();

    final int effectiveLimit =
        (limit == null || limit <= 0) ? defaultSessionLimit : limit;

    var query = client
        .from('stock_count_sessions')
        .select('id, company_id, branch_id, status, notes, '
            'started_at, confirmed_at, cancelled_at, '
            'created_by, created_at, updated_at')
        .eq('company_id', companyId);

    if (branchId != null) {
      query = query.eq('branch_id', branchId);
    }
    if (status != null) {
      query = query.eq('status', status);
    }

    final List<Map<String, dynamic>> rows = await query
        .order('started_at', ascending: false)
        .limit(effectiveLimit);

    return rows
        .map(StockCountSessionModel.fromMap)
        .toList(growable: false);
  }

  Future<StockCountSessionModel> getStockCountSession(
    String sessionId,
  ) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> row = await client
        .from('stock_count_sessions')
        .select('id, company_id, branch_id, status, notes, '
            'started_at, confirmed_at, cancelled_at, '
            'created_by, created_at, updated_at')
        .eq('id', sessionId)
        .single();

    return StockCountSessionModel.fromMap(row);
  }

  /// Returns every item of [sessionId], ordered by product_id.
  Future<List<StockCountItemModel>> listStockCountItems(
    String sessionId,
  ) async {
    final SupabaseClient client = _requireClient();
    final List<Map<String, dynamic>> allRows = <Map<String, dynamic>>[];

    // Paginate to avoid the 1000-row cap for very large catalogues.
    const int pageSize = 1000;
    int offset = 0;

    while (true) {
      final List<Map<String, dynamic>> rows = await client
          .from('stock_count_items')
          .select('id, company_id, session_id, product_id, unit_id, '
              'expected_quantity, actual_quantity, notes, '
              'created_at, updated_at')
          .eq('session_id', sessionId)
          .order('product_id', ascending: true)
          .range(offset, offset + pageSize - 1);

      allRows.addAll(rows);
      if (rows.length < pageSize) break;
      offset += pageSize;
      if (offset >= defaultItemLimit) break;
    }

    return allRows
        .map(StockCountItemModel.fromMap)
        .toList(growable: false);
  }

  /// Calls `create_stock_count_session` RPC, returns the new session id.
  Future<String> createStockCountSession({
    required String companyId,
    required String branchId,
    String? notes,
  }) async {
    final SupabaseClient client = _requireClient();

    final Object? result = await client.rpc(
      'create_stock_count_session',
      params: <String, Object?>{
        'p_company_id': companyId,
        'p_branch_id': branchId,
        'p_notes': notes,
      },
    );

    if (result is! String) {
      throw const InventoryException(
        type: InventoryFailureType.invalidResponse,
        cause: 'create_stock_count_session did not return a session id.',
      );
    }
    return result;
  }

  /// Calls `set_stock_count_item_actual` RPC.
  Future<void> setStockCountItemActual({
    required String itemId,
    required double actualQuantity,
    String? notes,
  }) async {
    final SupabaseClient client = _requireClient();

    await client.rpc(
      'set_stock_count_item_actual',
      params: <String, Object?>{
        'p_item_id': itemId,
        'p_actual_quantity': actualQuantity,
        'p_notes': notes,
      },
    );
  }

  /// Calls `confirm_stock_count_session` RPC, returns the number of
  /// movements written.
  Future<int> confirmStockCountSession(String sessionId) async {
    final SupabaseClient client = _requireClient();

    final Object? result = await client.rpc(
      'confirm_stock_count_session',
      params: <String, Object?>{'p_session_id': sessionId},
    );

    if (result is int) return result;
    if (result is num) return result.toInt();
    return 0;
  }

  /// Calls `cancel_stock_count_session` RPC.
  Future<void> cancelStockCountSession(String sessionId) async {
    final SupabaseClient client = _requireClient();

    await client.rpc(
      'cancel_stock_count_session',
      params: <String, Object?>{'p_session_id': sessionId},
    );
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

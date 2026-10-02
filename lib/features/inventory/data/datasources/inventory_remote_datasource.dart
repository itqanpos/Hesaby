// lib/features/inventory/data/datasources/inventory_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../domain/repositories/inventory_repository.dart';
import '../models/inventory_balance_model.dart';
import '../models/stock_movement_model.dart';

/// Thin wrapper around the Supabase queries for `inventory_balances` and
/// `stock_movements`.
///
/// This is the only file within the inventory feature that talks to
/// Supabase directly. Everything above this class deals with
/// [InventoryBalanceModel] / [StockMovementModel] and never sees Supabase
/// types.
///
/// Tenant isolation is enforced by Row Level Security, and consistency
/// between the ledger and the balance table is enforced by the database
/// trigger defined in Phase 5 migration 3:
/// * `select from inventory_balances` only returns rows of companies where
///   the current user has an active membership.
/// * `insert into stock_movements` is only accepted for members holding
///   owner / admin / manager role, and the trigger keeps the balance
///   table in sync in the same transaction.
///
/// The data source therefore never accepts a `userId` and never trusts a
/// client-supplied identity. The active identity is always `auth.uid()`,
/// evaluated inside the database.
class InventoryRemoteDataSource {
  const InventoryRemoteDataSource(this._client);

  /// Active Supabase client, or `null` when Supabase was not initialised.
  final SupabaseClient? _client;

  /// Whether this data source can perform remote queries.
  bool get isAvailable => _client != null;

  /// Default cap applied by [listMovements] when the caller does not
  /// provide one. Chosen to protect the client from unbounded payloads.
  static const int defaultMovementLimit = 100;

  // ---------------------------------------------------------------------------
  // Balances (read-only)
  // ---------------------------------------------------------------------------

  /// Returns the inventory balances of [branchId], ordered by product id.
  ///
  /// When [onlyInStock] is `true`, rows with a zero quantity are omitted
  /// on the server side (uses the partial index defined in migration 1).
  Future<List<InventoryBalanceModel>> listBalances(
    String companyId,
    String branchId, {
    required bool onlyInStock,
  }) async {
    final SupabaseClient client = _requireClient();

    // `var` infers `PostgrestFilterBuilder<PostgrestList>`. Reassignment is
    // used because the filter is applied conditionally.
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

  /// Returns the balance of a single (branch, product) pair.
  ///
  /// PostgREST raises `PGRST116` when no row matches; the repository maps
  /// that to [InventoryFailureType.notFound].
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

  /// Returns stock movements, most recent first.
  ///
  /// [branchId] and [productId] narrow the result when supplied. [limit]
  /// defaults to [defaultMovementLimit].
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
  /// `created_by` is derived from the authenticated session
  /// (`auth.currentUser.id`). If no user is signed in, the field is sent as
  /// `null`; the database allows `null` (ON DELETE SET NULL of the user)
  /// but in practice every insert happens under an authenticated session.
  ///
  /// The database trigger applies the movement to `inventory_balances` in
  /// the same transaction; a failure there (for example, insufficient
  /// stock) aborts the whole transaction and no row is persisted.
  Future<StockMovementModel> recordMovement({
    required String companyId,
    required String branchId,
    required String productId,
    required String movementType,
    required double quantity,
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

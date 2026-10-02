// lib/features/products/data/datasources/unit_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../domain/repositories/unit_repository.dart';
import '../models/unit_model.dart';

/// Thin wrapper around the Supabase queries for the `units` table.
///
/// This is the only file within the products feature that talks to Supabase
/// directly for units. Everything above this class deals with [UnitModel]
/// and never sees Supabase types.
///
/// Tenant isolation is enforced by Row Level Security:
/// * `select * from units` only returns rows of companies where the current
///   user has an active membership.
/// * `insert / update / delete` only succeed on rows of companies where the
///   current user holds an owner / admin / manager role.
///
/// The data source therefore never accepts a `userId` and never trusts a
/// client-supplied identity. The active identity is always `auth.uid()`,
/// evaluated inside the database.
class UnitRemoteDataSource {
  const UnitRemoteDataSource(this._client);

  /// Active Supabase client, or `null` when Supabase was not initialised.
  final SupabaseClient? _client;

  /// Whether this data source can perform remote queries.
  bool get isAvailable => _client != null;

  /// Returns every active unit of [companyId] visible to the current user,
  /// ordered by name.
  Future<List<UnitModel>> listUnits(String companyId) async {
    final SupabaseClient client = _requireClient();

    final List<Map<String, dynamic>> rows = await client
        .from('units')
        .select()
        .eq('company_id', companyId)
        .eq('is_active', true)
        .order('name', ascending: true);

    return rows.map(UnitModel.fromMap).toList(growable: false);
  }

  /// Returns the unit with [unitId], or throws if inaccessible.
  ///
  /// RLS filters the row out when the current user has no access, in which
  /// case PostgREST raises an error that the repository maps to
  /// [UnitFailureType.notFound].
  Future<UnitModel> getUnit(String unitId) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> row = await client
        .from('units')
        .select()
        .eq('id', unitId)
        .single();

    return UnitModel.fromMap(row);
  }

  /// Inserts a new unit and returns the created row.
  Future<UnitModel> createUnit({
    required String companyId,
    required String name,
    String? symbol,
  }) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> payload = <String, dynamic>{
      'company_id': companyId,
      'name': name.trim(),
      if (symbol != null && symbol.trim().isNotEmpty)
        'symbol': symbol.trim(),
    };

    final Map<String, dynamic> row = await client
        .from('units')
        .insert(payload)
        .select()
        .single();

    return UnitModel.fromMap(row);
  }

  /// Updates an existing unit and returns the updated row.
  ///
  /// Only the fields that are non-null are sent. Because `symbol` is itself
  /// nullable, [clearSymbol] forces the column to `null` explicitly; this
  /// disambiguates `null` meaning "leave as is" from "set to null".
  Future<UnitModel> updateUnit({
    required String unitId,
    String? name,
    String? symbol,
    bool clearSymbol = false,
    bool? isActive,
  }) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> payload = <String, dynamic>{
      if (name != null) 'name': name.trim(),
      if (clearSymbol) 'symbol': null,
      if (!clearSymbol && symbol != null) 'symbol': symbol.trim(),
      if (isActive != null) 'is_active': isActive,
    };

    final Map<String, dynamic> row = await client
        .from('units')
        .update(payload)
        .eq('id', unitId)
        .select()
        .single();

    return UnitModel.fromMap(row);
  }

  /// Deletes the unit with [unitId].
  Future<void> deleteUnit(String unitId) async {
    final SupabaseClient client = _requireClient();

    await client.from('units').delete().eq('id', unitId);
  }

  /// Returns the active Supabase client, or throws when Supabase was not
  /// initialised.
  SupabaseClient _requireClient() {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw const UnitException(
        type: UnitFailureType.unknown,
        cause: _supabaseUnavailableMessage,
      );
    }
    return client;
  }

  static const String _supabaseUnavailableMessage =
      'Supabase client is not initialised.';
}

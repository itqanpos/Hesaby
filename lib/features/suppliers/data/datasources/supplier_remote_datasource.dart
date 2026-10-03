// lib/features/suppliers/data/datasources/supplier_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../domain/repositories/supplier_repository.dart';
import '../models/supplier_model.dart';

/// Thin wrapper around the Supabase queries for the `suppliers` table.
///
/// This is the only file within the suppliers feature that talks to
/// Supabase directly. Everything above this class deals with
/// [SupplierModel] and never sees Supabase types.
///
/// Tenant isolation is enforced by Row Level Security:
/// * `select from suppliers` only returns rows of companies where the
///   current user has an active membership.
/// * `insert / update / delete` only succeed on rows of companies where
///   the current user holds an owner / admin / manager role.
///
/// The data source therefore never accepts a `userId` and never trusts a
/// client-supplied identity. The active identity is always `auth.uid()`,
/// evaluated inside the database.
class SupplierRemoteDataSource {
  const SupplierRemoteDataSource(this._client);

  /// Active Supabase client, or `null` when Supabase was not initialised.
  final SupabaseClient? _client;

  /// Whether this data source can perform remote queries.
  bool get isAvailable => _client != null;

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  /// Returns suppliers of [companyId], ordered by name.
  ///
  /// When [includeInactive] is `false`, rows with `is_active = false` are
  /// omitted on the server side.
  Future<List<SupplierModel>> listSuppliers(
    String companyId, {
    required bool includeInactive,
  }) async {
    final SupabaseClient client = _requireClient();

    // `var` infers `PostgrestFilterBuilder<PostgrestList>`. Reassignment is
    // used because the filter is applied conditionally.
    var query = client.from('suppliers').select().eq('company_id', companyId);

    if (!includeInactive) {
      query = query.eq('is_active', true);
    }

    final List<Map<String, dynamic>> rows =
        await query.order('name', ascending: true);

    return rows.map(SupplierModel.fromMap).toList(growable: false);
  }

  /// Returns the supplier with [supplierId], or throws if inaccessible.
  ///
  /// PostgREST raises `PGRST116` when no row matches; the repository maps
  /// that to [SupplierFailureType.notFound].
  Future<SupplierModel> getSupplier(String supplierId) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> row = await client
        .from('suppliers')
        .select()
        .eq('id', supplierId)
        .single();

    return SupplierModel.fromMap(row);
  }

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  /// Inserts a new supplier and returns the created row.
  Future<SupplierModel> createSupplier({
    required String companyId,
    required String name,
    String? code,
    String? phone,
    String? email,
    String? address,
    String? notes,
  }) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> payload = <String, dynamic>{
      'company_id': companyId,
      'name': name.trim(),
      if (code != null && code.trim().isNotEmpty) 'code': code.trim(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      if (address != null && address.trim().isNotEmpty)
        'address': address.trim(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    };

    final Map<String, dynamic> row = await client
        .from('suppliers')
        .insert(payload)
        .select()
        .single();

    return SupplierModel.fromMap(row);
  }

  /// Updates an existing supplier and returns the updated row.
  ///
  /// Only the fields that are non-null are sent, except for the five
  /// nullable fields that carry an explicit `clear*` flag to disambiguate
  /// "leave as is" from "set to null".
  Future<SupplierModel> updateSupplier({
    required String supplierId,
    String? name,
    String? code,
    bool clearCode = false,
    String? phone,
    bool clearPhone = false,
    String? email,
    bool clearEmail = false,
    String? address,
    bool clearAddress = false,
    String? notes,
    bool clearNotes = false,
    bool? isActive,
  }) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> payload = <String, dynamic>{
      if (name != null) 'name': name.trim(),
      if (clearCode) 'code': null,
      if (!clearCode && code != null) 'code': code.trim(),
      if (clearPhone) 'phone': null,
      if (!clearPhone && phone != null) 'phone': phone.trim(),
      if (clearEmail) 'email': null,
      if (!clearEmail && email != null) 'email': email.trim(),
      if (clearAddress) 'address': null,
      if (!clearAddress && address != null) 'address': address.trim(),
      if (clearNotes) 'notes': null,
      if (!clearNotes && notes != null) 'notes': notes.trim(),
      if (isActive != null) 'is_active': isActive,
    };

    final Map<String, dynamic> row = await client
        .from('suppliers')
        .update(payload)
        .eq('id', supplierId)
        .select()
        .single();

    return SupplierModel.fromMap(row);
  }

  /// Deletes the supplier with [supplierId].
  Future<void> deleteSupplier(String supplierId) async {
    final SupabaseClient client = _requireClient();

    await client.from('suppliers').delete().eq('id', supplierId);
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  SupabaseClient _requireClient() {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw const SupplierException(
        type: SupplierFailureType.unknown,
        cause: _supabaseUnavailableMessage,
      );
    }
    return client;
  }

  static const String _supabaseUnavailableMessage =
      'Supabase client is not initialised.';
}

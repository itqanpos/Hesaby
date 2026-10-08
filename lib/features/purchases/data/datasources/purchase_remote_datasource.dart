// lib/features/purchases/data/datasources/purchase_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../domain/repositories/purchase_repository.dart';
import '../models/purchase_item_model.dart';
import '../models/purchase_model.dart';

/// Thin wrapper around the Supabase queries for `purchases` and
/// `purchase_items`.
///
/// This is the only file within the purchases feature that talks to
/// Supabase directly. Everything above this class deals with
/// [PurchaseModel] / [PurchaseItemModel] and never sees Supabase types.
///
/// Invoice numbering:
/// When the caller does not supply an `invoice_number`, the data source
/// calls the `next_purchase_invoice_number` RPC, which returns a
/// company-scoped `PUR-YYYY-NNNN` value. This lets a user keep the
/// supplier's own invoice number when they have it, and still get a
/// stable internal number otherwise.
class PurchaseRemoteDataSource {
  const PurchaseRemoteDataSource(this._client);

  /// Active Supabase client, or `null` when Supabase was not initialised.
  final SupabaseClient? _client;

  /// Whether this data source can perform remote queries.
  bool get isAvailable => _client != null;

  /// Default cap applied by [listPurchases] when the caller does not provide
  /// one. Chosen to protect the client from unbounded payloads.
  static const int defaultLimit = 100;

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  /// Returns purchases of [companyId], most recent first.
  Future<List<PurchaseModel>> listPurchases(
    String companyId, {
    String? branchId,
    String? status,
    int? limit,
  }) async {
    final SupabaseClient client = _requireClient();

    final int effectiveLimit =
        (limit == null || limit <= 0) ? defaultLimit : limit;

    var query = client.from('purchases').select().eq('company_id', companyId);

    if (branchId != null) {
      query = query.eq('branch_id', branchId);
    }
    if (status != null) {
      query = query.eq('status', status);
    }

    final List<Map<String, dynamic>> rows = await query
        .order('purchase_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(effectiveLimit);

    return rows.map(PurchaseModel.fromMap).toList(growable: false);
  }

  /// Returns the header of a single purchase.
  Future<PurchaseModel> getPurchase(String purchaseId) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> row = await client
        .from('purchases')
        .select()
        .eq('id', purchaseId)
        .single();

    return PurchaseModel.fromMap(row);
  }

  /// Returns the line items of [purchaseId], oldest first.
  Future<List<PurchaseItemModel>> listPurchaseItems(
    String purchaseId,
  ) async {
    final SupabaseClient client = _requireClient();

    final List<Map<String, dynamic>> rows = await client
        .from('purchase_items')
        .select()
        .eq('purchase_id', purchaseId)
        .order('created_at', ascending: true);

    return rows.map(PurchaseItemModel.fromMap).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  /// Creates a draft purchase and its items.
  ///
  /// When [invoiceNumber] is `null` or empty, the server generates a
  /// `PUR-YYYY-NNNN` number for the company. When non-empty, the supplied
  /// value is stored as-is (typically the supplier's own invoice number).
  ///
  /// On failure of the item batch insert, the header is left in `draft` and
  /// a best-effort cancellation is issued before rethrowing.
  Future<PurchaseModel> createPurchase({
    required String companyId,
    required String branchId,
    required String supplierId,
    required DateTime purchaseDate,
    required List<PurchaseItemDraft> items,
    String? invoiceNumber,
    required double discount,
    required double taxAmount,
    String? notes,
  }) async {
    final SupabaseClient client = _requireClient();

    final String? createdBy = client.auth.currentUser?.id;

    // ---- Resolve the invoice number (user-supplied or auto-generated) ----
    final String effectiveInvoiceNumber =
        await _resolveInvoiceNumber(client, companyId, invoiceNumber);

    final Map<String, dynamic> headerPayload = <String, dynamic>{
      'company_id': companyId,
      'branch_id': branchId,
      'supplier_id': supplierId,
      'purchase_date': _formatDate(purchaseDate),
      'invoice_number': effectiveInvoiceNumber,
      'discount': discount,
      'tax_amount': taxAmount,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (createdBy != null) 'created_by': createdBy,
    };

    final Map<String, dynamic> headerRow = await client
        .from('purchases')
        .insert(headerPayload)
        .select()
        .single();

    final Object? rawId = headerRow['id'];
    if (rawId is! String || rawId.isEmpty) {
      throw const PurchaseException(
        type: PurchaseFailureType.invalidResponse,
        cause: 'Inserted purchase is missing an id.',
      );
    }
    final String purchaseId = rawId;

    if (items.isNotEmpty) {
      try {
        await _insertItems(
          client: client,
          companyId: companyId,
          purchaseId: purchaseId,
          items: items,
        );
      } on Object {
        // Best-effort cleanup: mark the orphan header as cancelled so it does
        // not show up as a live draft. The header cannot be hard-deleted
        // because the database forbids it by design.
        await _bestEffortCancel(client, purchaseId);
        rethrow;
      }
    }

    // Re-read the header so that totals recomputed by the trigger are
    // reflected in the returned entity.
    final Map<String, dynamic> finalRow = await client
        .from('purchases')
        .select()
        .eq('id', purchaseId)
        .single();

    return PurchaseModel.fromMap(finalRow);
  }

  /// Replaces the header and items of an existing draft purchase.
  ///
  /// Unlike [createPurchase], this method never auto-generates a number:
  /// the existing invoice number is preserved when [invoiceNumber] is
  /// empty, so an edit does not silently rotate the number.
  Future<PurchaseModel> updateDraft({
    required String purchaseId,
    required String companyId,
    required String branchId,
    required String supplierId,
    required DateTime purchaseDate,
    required List<PurchaseItemDraft> items,
    String? invoiceNumber,
    required double discount,
    required double taxAmount,
    String? notes,
  }) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> headerPayload = <String, dynamic>{
      'branch_id': branchId,
      'supplier_id': supplierId,
      'purchase_date': _formatDate(purchaseDate),
      'discount': discount,
      'tax_amount': taxAmount,
      'invoice_number':
          (invoiceNumber != null && invoiceNumber.trim().isNotEmpty)
              ? invoiceNumber.trim()
              : null,
      'notes': (notes != null && notes.trim().isNotEmpty)
          ? notes.trim()
          : null,
    };

    await client
        .from('purchases')
        .update(headerPayload)
        .eq('id', purchaseId);

    // Replace items: delete all then batch-insert. Both operations are
    // permitted only while the parent is in draft (enforced by trigger).
    await client
        .from('purchase_items')
        .delete()
        .eq('purchase_id', purchaseId);

    if (items.isNotEmpty) {
      await _insertItems(
        client: client,
        companyId: companyId,
        purchaseId: purchaseId,
        items: items,
      );
    }

    final Map<String, dynamic> finalRow = await client
        .from('purchases')
        .select()
        .eq('id', purchaseId)
        .single();

    return PurchaseModel.fromMap(finalRow);
  }

  /// Confirms a draft purchase.
  ///
  /// The database trigger inserts the corresponding `purchase_in` stock
  /// movements. A failure (for example, empty purchase) aborts the
  /// transaction and no partial state is persisted.
  Future<PurchaseModel> confirmPurchase(String purchaseId) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> row = await client
        .from('purchases')
        .update(<String, dynamic>{'status': 'confirmed'})
        .eq('id', purchaseId)
        .select()
        .single();

    return PurchaseModel.fromMap(row);
  }

  /// Cancels a purchase.
  ///
  /// A draft purchase is cancelled without touching stock. A confirmed
  /// purchase has its movements reversed; if the reversal would drive a
  /// stock balance negative, the database raises an error that is mapped by
  /// the repository to [PurchaseFailureType.insufficientStock].
  Future<PurchaseModel> cancelPurchase(String purchaseId) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> row = await client
        .from('purchases')
        .update(<String, dynamic>{'status': 'cancelled'})
        .eq('id', purchaseId)
        .select()
        .single();

    return PurchaseModel.fromMap(row);
  }

  // ---------------------------------------------------------------------------
  // Invoice number resolution
  // ---------------------------------------------------------------------------

  /// Returns the invoice number to store, generating one when [supplied]
  /// is null or empty.
  ///
  /// Throws [PurchaseException] with type
  /// [PurchaseFailureType.invalidResponse] when the server returns an
  /// unexpected value (the RPC is guaranteed to return a non-empty string
  /// on success).
  static Future<String> _resolveInvoiceNumber(
    SupabaseClient client,
    String companyId,
    String? supplied,
  ) async {
    final String trimmed = (supplied ?? '').trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }

    final Object? raw = await client.rpc(
      'next_purchase_invoice_number',
      params: <String, dynamic>{'p_company_id': companyId},
    );

    if (raw is String && raw.trim().isNotEmpty) {
      return raw.trim();
    }

    throw const PurchaseException(
      type: PurchaseFailureType.invalidResponse,
      cause:
          'next_purchase_invoice_number returned an unexpected value.',
    );
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Batch-inserts a list of draft items under [purchaseId].
  static Future<void> _insertItems({
    required SupabaseClient client,
    required String companyId,
    required String purchaseId,
    required List<PurchaseItemDraft> items,
  }) async {
    final List<Map<String, dynamic>> payloads =
        <Map<String, dynamic>>[
      for (final PurchaseItemDraft item in items)
        <String, dynamic>{
          'company_id': companyId,
          'purchase_id': purchaseId,
          'product_id': item.productId,
          'unit_id': item.unitId,
          'quantity': item.quantity,
          'unit_cost': item.unitCost,
          // line_total is maintained by the database trigger; a placeholder
          // is required because the column is NOT NULL. The BEFORE trigger
          // overwrites it before the row is written.
          'line_total': item.quantity * item.unitCost,
          if (item.notes != null && item.notes!.trim().isNotEmpty)
            'notes': item.notes!.trim(),
        },
    ];

    await client.from('purchase_items').insert(payloads);
  }

  /// Best-effort cancellation of an orphan header.
  ///
  /// Errors are intentionally swallowed: the caller is already handling the
  /// primary failure, and a secondary failure here must not mask it.
  static Future<void> _bestEffortCancel(
    SupabaseClient client,
    String purchaseId,
  ) async {
    try {
      await client
          .from('purchases')
          .update(<String, dynamic>{'status': 'cancelled'})
          .eq('id', purchaseId);
    } on Object {
      // Ignored by design.
    }
  }

  /// Formats a [DateTime] as `YYYY-MM-DD` for a PostgreSQL `date` column.
  static String _formatDate(DateTime value) {
    final String year = value.year.toString().padLeft(4, '0');
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  SupabaseClient _requireClient() {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw const PurchaseException(
        type: PurchaseFailureType.unknown,
        cause: _supabaseUnavailableMessage,
      );
    }
    return client;
  }

  static const String _supabaseUnavailableMessage =
      'Supabase client is not initialised.';
}

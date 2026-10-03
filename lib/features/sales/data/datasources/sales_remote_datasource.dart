// lib/features/sales/data/datasources/sales_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../domain/entities/sale_entities.dart';
import '../../domain/repositories/sales_repository.dart';
import '../models/sale_models.dart';

/// Thin wrapper around the Supabase queries for `customers`, `sales` and
/// `sale_items`.
///
/// This is the only file within the sales feature that talks to Supabase
/// directly. Everything above this class deals with the models defined in
/// `sale_models.dart` and never sees Supabase types.
///
/// Transactionality caveat:
/// The Supabase client cannot issue multi-statement transactions. Creating a
/// sale therefore proceeds as: insert header (status = draft), then
/// batch-insert the items. If the second step fails, the header is
/// best-effort cancelled so it does not linger as an orphan draft, and the
/// original error is rethrown. The database trigger guarantees that any
/// state transition performed inside a single statement (for example,
/// confirming) is atomic.
class SalesRemoteDataSource {
  const SalesRemoteDataSource(this._client);

  final SupabaseClient? _client;

  bool get isAvailable => _client != null;

  static const int defaultLimit = 100;

  // ===========================================================================
  // CUSTOMERS
  // ===========================================================================

  Future<List<CustomerModel>> listCustomers(
    String companyId, {
    required bool includeInactive,
  }) async {
    final SupabaseClient client = _requireClient();

    var query = client.from('customers').select().eq('company_id', companyId);

    if (!includeInactive) {
      query = query.eq('is_active', true);
    }

    final List<Map<String, dynamic>> rows =
        await query.order('name', ascending: true);

    return rows.map(CustomerModel.fromMap).toList(growable: false);
  }

  Future<CustomerModel> getCustomer(String customerId) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> row = await client
        .from('customers')
        .select()
        .eq('id', customerId)
        .single();

    return CustomerModel.fromMap(row);
  }

  Future<CustomerModel> createCustomer({
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
        .from('customers')
        .insert(payload)
        .select()
        .single();

    return CustomerModel.fromMap(row);
  }

  Future<CustomerModel> updateCustomer({
    required String customerId,
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
        .from('customers')
        .update(payload)
        .eq('id', customerId)
        .select()
        .single();

    return CustomerModel.fromMap(row);
  }

  Future<void> deleteCustomer(String customerId) async {
    final SupabaseClient client = _requireClient();
    await client.from('customers').delete().eq('id', customerId);
  }

  // ===========================================================================
  // SALES
  // ===========================================================================

  Future<List<SaleModel>> listSales(
    String companyId, {
    String? branchId,
    String? status,
    int? limit,
  }) async {
    final SupabaseClient client = _requireClient();

    final int effectiveLimit =
        (limit == null || limit <= 0) ? defaultLimit : limit;

    var query = client.from('sales').select().eq('company_id', companyId);

    if (branchId != null) {
      query = query.eq('branch_id', branchId);
    }
    if (status != null) {
      query = query.eq('status', status);
    }

    final List<Map<String, dynamic>> rows = await query
        .order('sale_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(effectiveLimit);

    return rows.map(SaleModel.fromMap).toList(growable: false);
  }

  Future<SaleModel> getSale(String saleId) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> row = await client
        .from('sales')
        .select()
        .eq('id', saleId)
        .single();

    return SaleModel.fromMap(row);
  }

  Future<List<SaleItemModel>> listSaleItems(String saleId) async {
    final SupabaseClient client = _requireClient();

    final List<Map<String, dynamic>> rows = await client
        .from('sale_items')
        .select()
        .eq('sale_id', saleId)
        .order('created_at', ascending: true);

    return rows.map(SaleItemModel.fromMap).toList(growable: false);
  }

  Future<SaleModel> createSale({
    required String companyId,
    required String branchId,
    required String customerId,
    required DateTime saleDate,
    required List<SaleItemDraft> items,
    String? invoiceNumber,
    required double discount,
    required double taxAmount,
    required double paidAmount,
    String? notes,
  }) async {
    final SupabaseClient client = _requireClient();

    final String? createdBy = client.auth.currentUser?.id;

    final Map<String, dynamic> headerPayload = <String, dynamic>{
      'company_id': companyId,
      'branch_id': branchId,
      'customer_id': customerId,
      'sale_date': _formatTimestamp(saleDate),
      'discount': discount,
      'tax_amount': taxAmount,
      'paid_amount': paidAmount,
      if (invoiceNumber != null && invoiceNumber.trim().isNotEmpty)
        'invoice_number': invoiceNumber.trim(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (createdBy != null) 'created_by': createdBy,
    };

    final Map<String, dynamic> headerRow = await client
        .from('sales')
        .insert(headerPayload)
        .select()
        .single();

    final Object? rawId = headerRow['id'];
    if (rawId is! String || rawId.isEmpty) {
      throw const SaleException(
        type: SalesFailureType.invalidResponse,
        cause: 'Inserted sale is missing an id.',
      );
    }
    final String saleId = rawId;

    if (items.isNotEmpty) {
      try {
        await _insertItems(
          client: client,
          companyId: companyId,
          saleId: saleId,
          items: items,
        );
      } on Object {
        await _bestEffortCancel(client, saleId);
        rethrow;
      }
    }

    final Map<String, dynamic> finalRow = await client
        .from('sales')
        .select()
        .eq('id', saleId)
        .single();

    return SaleModel.fromMap(finalRow);
  }

  Future<SaleModel> updateDraft({
    required String saleId,
    required String companyId,
    required String branchId,
    required String customerId,
    required DateTime saleDate,
    required List<SaleItemDraft> items,
    String? invoiceNumber,
    required double discount,
    required double taxAmount,
    required double paidAmount,
    String? notes,
  }) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> headerPayload = <String, dynamic>{
      'branch_id': branchId,
      'customer_id': customerId,
      'sale_date': _formatTimestamp(saleDate),
      'discount': discount,
      'tax_amount': taxAmount,
      'paid_amount': paidAmount,
      'invoice_number':
          (invoiceNumber != null && invoiceNumber.trim().isNotEmpty)
              ? invoiceNumber.trim()
              : null,
      'notes': (notes != null && notes.trim().isNotEmpty)
          ? notes.trim()
          : null,
    };

    await client.from('sales').update(headerPayload).eq('id', saleId);

    await client.from('sale_items').delete().eq('sale_id', saleId);

    if (items.isNotEmpty) {
      await _insertItems(
        client: client,
        companyId: companyId,
        saleId: saleId,
        items: items,
      );
    }

    final Map<String, dynamic> finalRow = await client
        .from('sales')
        .select()
        .eq('id', saleId)
        .single();

    return SaleModel.fromMap(finalRow);
  }

  Future<SaleModel> confirmSale(String saleId) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> row = await client
        .from('sales')
        .update(<String, dynamic>{'status': 'confirmed'})
        .eq('id', saleId)
        .select()
        .single();

    return SaleModel.fromMap(row);
  }

  Future<SaleModel> cancelSale(String saleId) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> row = await client
        .from('sales')
        .update(<String, dynamic>{'status': 'cancelled'})
        .eq('id', saleId)
        .select()
        .single();

    return SaleModel.fromMap(row);
  }

  // ===========================================================================
  // Internal helpers
  // ===========================================================================

  static Future<void> _insertItems({
    required SupabaseClient client,
    required String companyId,
    required String saleId,
    required List<SaleItemDraft> items,
  }) async {
    final List<Map<String, dynamic>> payloads =
        <Map<String, dynamic>>[
      for (final SaleItemDraft item in items)
        <String, dynamic>{
          'company_id': companyId,
          'sale_id': saleId,
          'product_id': item.productId,
          'unit_id': item.unitId,
          'quantity': item.quantity,
          'unit_price': item.unitPrice,
          // line_total is maintained by the database trigger; a placeholder
          // is required because the column is NOT NULL. The BEFORE trigger
          // overwrites it before the row is written.
          'line_total': item.quantity * item.unitPrice,
          if (item.notes != null && item.notes!.trim().isNotEmpty)
            'notes': item.notes!.trim(),
        },
    ];

    await client.from('sale_items').insert(payloads);
  }

  static Future<void> _bestEffortCancel(
    SupabaseClient client,
    String saleId,
  ) async {
    try {
      await client
          .from('sales')
          .update(<String, dynamic>{'status': 'cancelled'})
          .eq('id', saleId);
    } on Object {
      // Ignored by design: the caller is already handling the primary
      // failure, and a secondary failure here must not mask it.
    }
  }

  /// Formats a [DateTime] as an ISO 8601 string suitable for a `timestamptz`
  /// column. UTC is used so that PostgreSQL stores the exact instant.
  static String _formatTimestamp(DateTime value) => value.toUtc().toIso8601String();

  SupabaseClient _requireClient() {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw const CustomerException(
        type: CustomerFailureType.unknown,
        cause: _supabaseUnavailableMessage,
      );
    }
    return client;
  }

  static const String _supabaseUnavailableMessage =
      'Supabase client is not initialised.';
}

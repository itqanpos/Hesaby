// lib/features/sales/data/datasources/sales_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../domain/entities/sale_entities.dart';
import '../../domain/repositories/sales_repository.dart';
import '../models/customer_adjustment_model.dart';
import '../models/customer_payment_model.dart';
import '../models/sale_models.dart';

/// Thin wrapper around the Supabase queries for `customers`,
/// `customer_payments`, `customer_balance_adjustments`, `sales` and
/// `sale_items`.
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
  // CUSTOMER PAYMENTS
  // ===========================================================================

  /// Lists the most recent payments for [customerId], newest first.
  ///
  /// Falls back to [defaultLimit] when [limit] is null or non-positive.
  Future<List<CustomerPaymentModel>> listCustomerPayments(
    String customerId, {
    int? limit,
  }) async {
    final SupabaseClient client = _requireClient();

    final int effectiveLimit =
        (limit == null || limit <= 0) ? defaultLimit : limit;

    final List<Map<String, dynamic>> rows = await client
        .from('customer_payments')
        .select()
        .eq('customer_id', customerId)
        .order('created_at', ascending: false)
        .limit(effectiveLimit);

    return rows.map(CustomerPaymentModel.fromMap).toList(growable: false);
  }

  /// Inserts a standalone payment for [customerId].
  ///
  /// The database trigger `apply_customer_payment` runs immediately after
  /// the insert and reduces `customers.balance` by [amount]. The row is
  /// returned so the caller can update its in-memory copy of the customer.
  Future<CustomerPaymentModel> recordCustomerPayment({
    required String companyId,
    required String customerId,
    required double amount,
    required String method,
    String? reference,
    String? notes,
  }) async {
    final SupabaseClient client = _requireClient();

    final String? createdBy = client.auth.currentUser?.id;

    final Map<String, dynamic> payload = <String, dynamic>{
      'company_id': companyId,
      'customer_id': customerId,
      'amount': amount,
      'method': method,
      if (reference != null && reference.trim().isNotEmpty)
        'reference': reference.trim(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (createdBy != null) 'created_by': createdBy,
    };

    final Map<String, dynamic> row = await client
        .from('customer_payments')
        .insert(payload)
        .select()
        .single();

    return CustomerPaymentModel.fromMap(row);
  }

  // ===========================================================================
  // CUSTOMER ADJUSTMENTS
  // ===========================================================================

  /// Lists the manual adjustments recorded for [customerId], newest first.
  ///
  /// When [fromDate] / [toDate] are provided they act as an inclusive
  /// window on `created_at`.
  Future<List<CustomerAdjustmentModel>> listCustomerAdjustments(
    String customerId, {
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final SupabaseClient client = _requireClient();

    var query = client
        .from('customer_balance_adjustments')
        .select()
        .eq('customer_id', customerId);

    if (fromDate != null) {
      query = query.gte('created_at', _formatTimestamp(fromDate));
    }
    if (toDate != null) {
      query = query.lte('created_at', _formatTimestamp(toDate));
    }

    final List<Map<String, dynamic>> rows =
        await query.order('created_at', ascending: false);

    return rows
        .map(CustomerAdjustmentModel.fromMap)
        .toList(growable: false);
  }

  /// Inserts a manual adjustment for [customerId].
  ///
  /// The database trigger `apply_customer_balance_adjustment` runs
  /// immediately after the insert and applies the signed delta to
  /// `customers.balance`. A negative delta that would drive the balance
  /// below zero is rejected by the trigger with SQLSTATE `23514`.
  Future<CustomerAdjustmentModel> addCustomerAdjustment({
    required String companyId,
    required String customerId,
    required double amount,
    required String reason,
    String? notes,
  }) async {
    final SupabaseClient client = _requireClient();

    final String? createdBy = client.auth.currentUser?.id;

    final Map<String, dynamic> payload = <String, dynamic>{
      'company_id': companyId,
      'customer_id': customerId,
      'amount': amount,
      'reason': reason,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (createdBy != null) 'created_by': createdBy,
    };

    final Map<String, dynamic> row = await client
        .from('customer_balance_adjustments')
        .insert(payload)
        .select()
        .single();

    return CustomerAdjustmentModel.fromMap(row);
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

  /// Lists sales that involve [customerId], across the whole company.
  ///
  /// Used by the statement builder to reconstruct a customer's balance
  /// history. Only `confirmed` and `cancelled` sales are relevant — a
  /// `draft` sale has not affected the balance yet.
  Future<List<SaleModel>> listCustomerSales(String customerId) async {
    final SupabaseClient client = _requireClient();

    final List<Map<String, dynamic>> rows = await client
        .from('sales')
        .select()
        .eq('customer_id', customerId)
        .neq('status', 'draft')
        .order('sale_date', ascending: true);

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

  /// Creates a draft sale with its items.
  ///
  /// The header is inserted with `paid_amount = 0` because `total` is still
  /// `0` at that moment (the items have not been inserted yet) and the
  /// database enforces `paid_amount <= total`. Once the items are in place
  /// the parent subtotal is recomputed by a trigger, and the effective
  /// `paid_amount` is written in a follow-up update.
  Future<SaleModel> createSale({
    required String companyId,
    required String branchId,
    String? customerId,
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
      if (customerId != null) 'customer_id': customerId,
      'sale_date': _formatTimestamp(saleDate),
      'discount': discount,
      'tax_amount': taxAmount,
      'paid_amount': 0,
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

    try {
      if (items.isNotEmpty) {
        await _insertItems(
          client: client,
          companyId: companyId,
          saleId: saleId,
          items: items,
        );
      }

      // The parent subtotal has now been recomputed by the AFTER-INSERT
      // trigger on sale_items. We can safely set paid_amount (<= total).
      if (paidAmount > 0) {
        await client
            .from('sales')
            .update(<String, dynamic>{'paid_amount': paidAmount})
            .eq('id', saleId);
      }
    } on Object {
      await _bestEffortCancel(client, saleId);
      rethrow;
    }

    final Map<String, dynamic> finalRow = await client
        .from('sales')
        .select()
        .eq('id', saleId)
        .single();

    return SaleModel.fromMap(finalRow);
  }

  /// Replaces the header and items of an existing draft sale.
  ///
  /// Same reasoning as [createSale]: `paid_amount` is reset to `0` before
  /// items are replaced, then written in a final update.
  Future<SaleModel> updateDraft({
    required String saleId,
    required String companyId,
    required String branchId,
    String? customerId,
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
      'paid_amount': 0,
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

    if (paidAmount > 0) {
      await client
          .from('sales')
          .update(<String, dynamic>{'paid_amount': paidAmount})
          .eq('id', saleId);
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
      // Ignored by design.
    }
  }

  static String _formatTimestamp(DateTime value) =>
      value.toUtc().toIso8601String();

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

// lib/features/purchases/data/datasources/purchase_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../domain/repositories/purchase_repository.dart';
import '../models/purchase_item_model.dart';
import '../models/purchase_model.dart';

class PurchaseRemoteDataSource {
  const PurchaseRemoteDataSource(this._client);

  final SupabaseClient? _client;

  bool get isAvailable => _client != null;

  static const int defaultLimit = 100;

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

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

  Future<PurchaseModel> getPurchase(String purchaseId) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> row = await client
        .from('purchases')
        .select()
        .eq('id', purchaseId)
        .single();

    return PurchaseModel.fromMap(row);
  }

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

  Future<PurchaseModel> createPurchase({
    required String companyId,
    required String branchId,
    required String supplierId,
    required DateTime purchaseDate,
    required List<PurchaseItemDraft> items,
    String? invoiceNumber,
    required double discount,
    required double taxAmount,
    required double paidAmount,
    required String paymentMethod,
    String? notes,
  }) async {
    final SupabaseClient client = _requireClient();

    final String? createdBy = client.auth.currentUser?.id;

    final String effectiveInvoiceNumber =
        await _resolveInvoiceNumber(client, companyId, invoiceNumber);

    // ⬇️ استخدام paid_amount = 0 مبدئياً لتجنب مشكلة القيد (paid_amount <= total)
    final Map<String, dynamic> headerPayload = <String, dynamic>{
      'company_id': companyId,
      'branch_id': branchId,
      'supplier_id': supplierId,
      'purchase_date': _formatDate(purchaseDate),
      'invoice_number': effectiveInvoiceNumber,
      'discount': discount,
      'tax_amount': taxAmount,
      'paid_amount': 0.0, // ⬅️ تم التعديل
      'payment_method': paymentMethod,
      'status': 'draft',
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
        await _bestEffortCancel(client, purchaseId);
        rethrow;
      }
    }

    // ⬇️ تحديث المبلغ المدفوع بعد إدراج البنود (ليكون المجموع قد تم حسابه)
    if (paidAmount > 0) {
      await client
          .from('purchases')
          .update(<String, dynamic>{'paid_amount': paidAmount})
          .eq('id', purchaseId);
    }

    final Map<String, dynamic> finalRow = await client
        .from('purchases')
        .select()
        .eq('id', purchaseId)
        .single();

    return PurchaseModel.fromMap(finalRow);
  }

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
    required double paidAmount,
    required String paymentMethod,
    String? notes,
  }) async {
    final SupabaseClient client = _requireClient();

    // ⬇️ استخدام paid_amount = 0 مبدئياً هنا أيضاً
    final Map<String, dynamic> headerPayload = <String, dynamic>{
      'branch_id': branchId,
      'supplier_id': supplierId,
      'purchase_date': _formatDate(purchaseDate),
      'discount': discount,
      'tax_amount': taxAmount,
      'paid_amount': 0.0, // ⬅️ تم التعديل
      'payment_method': paymentMethod,
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

    // ⬇️ تحديث المبلغ المدفوع بعد إدراج البنود
    if (paidAmount > 0) {
      await client
          .from('purchases')
          .update(<String, dynamic>{'paid_amount': paidAmount})
          .eq('id', purchaseId);
    }

    final Map<String, dynamic> finalRow = await client
        .from('purchases')
        .select()
        .eq('id', purchaseId)
        .single();

    return PurchaseModel.fromMap(finalRow);
  }

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
          'line_total': item.quantity * item.unitCost,
          if (item.notes != null && item.notes!.trim().isNotEmpty)
            'notes': item.notes!.trim(),
        },
    ];

    await client.from('purchase_items').insert(payloads);
  }

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

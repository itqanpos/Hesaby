// lib/features/purchases/data/repositories/purchase_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/purchase.dart';
import '../../domain/entities/purchase_item.dart';
import '../../domain/repositories/purchase_repository.dart';
import '../datasources/purchase_remote_datasource.dart';
import '../models/purchase_item_model.dart';
import '../models/purchase_model.dart';

class PurchaseRepositoryImpl implements PurchaseRepository {
  const PurchaseRepositoryImpl(this._remoteDataSource);

  final PurchaseRemoteDataSource _remoteDataSource;

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  @override
  Future<List<Purchase>> listPurchases(
    String companyId, {
    String? branchId,
    String? status,
    int? limit,
  }) async {
    try {
      final List<PurchaseModel> models =
          await _remoteDataSource.listPurchases(
        companyId,
        branchId: branchId,
        status: status,
        limit: limit,
      );
      return models
          .map((PurchaseModel model) => model.toEntity())
          .toList(growable: false);
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'listPurchases');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'listPurchases');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'listPurchases');
    } on PurchaseException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'listPurchases');
    }
  }

  @override
  Future<Purchase> getPurchase(String purchaseId) async {
    try {
      final PurchaseModel model =
          await _remoteDataSource.getPurchase(purchaseId);
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'getPurchase');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getPurchase');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'getPurchase');
    } on PurchaseException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getPurchase');
    }
  }

  @override
  Future<List<PurchaseItem>> listPurchaseItems(String purchaseId) async {
    try {
      final List<PurchaseItemModel> models =
          await _remoteDataSource.listPurchaseItems(purchaseId);
      return models
          .map((PurchaseItemModel model) => model.toEntity())
          .toList(growable: false);
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(
        error,
        stackTrace,
        operation: 'listPurchaseItems',
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'listPurchaseItems');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'listPurchaseItems');
    } on PurchaseException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'listPurchaseItems');
    }
  }

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  @override
  Future<Purchase> createPurchase({
    required String companyId,
    required String branchId,
    required String supplierId,
    required DateTime purchaseDate,
    List<PurchaseItemDraft> items = const <PurchaseItemDraft>[],
    String? invoiceNumber,
    double discount = 0,
    double taxAmount = 0,
    double paidAmount = 0,          // ⬅️ جديد
    String paymentMethod = 'cash',  // ⬅️ جديد
    String? notes,
  }) async {
    try {
      final PurchaseModel model = await _remoteDataSource.createPurchase(
        companyId: companyId,
        branchId: branchId,
        supplierId: supplierId,
        purchaseDate: purchaseDate,
        items: items,
        invoiceNumber: invoiceNumber,
        discount: discount,
        taxAmount: taxAmount,
        paidAmount: paidAmount,
        paymentMethod: paymentMethod,
        notes: notes,
      );
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'createPurchase');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'createPurchase');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'createPurchase');
    } on PurchaseException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'createPurchase');
    }
  }

  @override
  Future<Purchase> updateDraft({
    required String purchaseId,
    required String companyId,
    required String branchId,
    required String supplierId,
    required DateTime purchaseDate,
    required List<PurchaseItemDraft> items,
    String? invoiceNumber,
    double discount = 0,
    double taxAmount = 0,
    double paidAmount = 0,          // ⬅️ جديد
    String paymentMethod = 'cash',  // ⬅️ جديد
    String? notes,
  }) async {
    try {
      final PurchaseModel model = await _remoteDataSource.updateDraft(
        purchaseId: purchaseId,
        companyId: companyId,
        branchId: branchId,
        supplierId: supplierId,
        purchaseDate: purchaseDate,
        items: items,
        invoiceNumber: invoiceNumber,
        discount: discount,
        taxAmount: taxAmount,
        paidAmount: paidAmount,
        paymentMethod: paymentMethod,
        notes: notes,
      );
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'updateDraft');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'updateDraft');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'updateDraft');
    } on PurchaseException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'updateDraft');
    }
  }

  @override
  Future<Purchase> confirmPurchase(String purchaseId) async {
    try {
      final PurchaseModel model =
          await _remoteDataSource.confirmPurchase(purchaseId);
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(
        error,
        stackTrace,
        operation: 'confirmPurchase',
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'confirmPurchase');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'confirmPurchase');
    } on PurchaseException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'confirmPurchase');
    }
  }

  @override
  Future<Purchase> cancelPurchase(String purchaseId) async {
    try {
      final PurchaseModel model =
          await _remoteDataSource.cancelPurchase(purchaseId);
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(
        error,
        stackTrace,
        operation: 'cancelPurchase',
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'cancelPurchase');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'cancelPurchase');
    } on PurchaseException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'cancelPurchase');
    }
  }

  // ---------------------------------------------------------------------------
  // Error mapping
  // ---------------------------------------------------------------------------

  static PurchaseException _mapInvalidResponse(
    FormatException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    AppLogger.error(
      'Invalid response during "$operation" (FormatException).',
      error,
      stackTrace,
    );
    return PurchaseException(
      type: PurchaseFailureType.invalidResponse,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static PurchaseException _mapPostgrest(
    supabase.PostgrestException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    final PurchaseFailureType type = _classifyPostgrest(error);

    AppLogger.warning(
      'PostgREST error during "$operation" mapped to ${type.name} '
      '(code: ${error.code ?? 'n/a'}).',
    );

    return PurchaseException(
      type: type,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static PurchaseException _mapAuth(
    supabase.AuthException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    AppLogger.warning(
      'Auth error during "$operation" mapped to unauthorized '
      '(code: ${error.code ?? 'n/a'}).',
    );

    return PurchaseException(
      type: PurchaseFailureType.unauthorized,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static PurchaseException _mapUnknown(
    Object error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    final PurchaseFailureType type = _looksLikeNetworkFailure(error)
        ? PurchaseFailureType.network
        : PurchaseFailureType.unknown;

    AppLogger.error(
      'Unhandled error during "$operation" '
      '(runtimeType: ${error.runtimeType}, mapped: ${type.name}).',
      error,
      stackTrace,
    );

    return PurchaseException(
      type: type,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static PurchaseFailureType _classifyPostgrest(
    supabase.PostgrestException error,
  ) {
    final String code = (error.code ?? '').toUpperCase();
    final String message = error.message.toLowerCase();
    final String full = error.toString().toLowerCase();

    if (code == '23505') {
      if (full.contains('uniq_purchases_company_invoice_number') ||
          message.contains('invoice_number')) {
        return PurchaseFailureType.invoiceNumberConflict;
      }
      return PurchaseFailureType.invalidResponse;
    }

    if (code == '23503') {
      if (full.contains('purchases_supplier_company_fk')) {
        return PurchaseFailureType.supplierNotFound;
      }
      if (full.contains('purchases_branch_company_fk')) {
        return PurchaseFailureType.branchNotFound;
      }
      if (full.contains('purchase_items_product_company_fk')) {
        return PurchaseFailureType.productNotFound;
      }
      if (full.contains('purchase_items_unit_company_fk')) {
        return PurchaseFailureType.unitNotFound;
      }
      if (full.contains('purchase_items_purchase_company_fk')) {
        return PurchaseFailureType.notFound;
      }
      return PurchaseFailureType.notFound;
    }

    if (code == '23514') {
      if (message.contains('insufficient stock') ||
          full.contains('insufficient stock')) {
        return PurchaseFailureType.insufficientStock;
      }
      if (message.contains('without items') ||
          full.contains('cannot confirm purchase')) {
        return PurchaseFailureType.emptyPurchase;
      }
      if (message.contains('invalid purchase status transition') ||
          message.contains('cannot modify a') ||
          message.contains('must be created with status = draft') ||
          message.contains('cannot modify items of a')) {
        return PurchaseFailureType.invalidStatusTransition;
      }
      return PurchaseFailureType.invalidStatusTransition;
    }

    if (code == 'PGRST116') {
      return PurchaseFailureType.notFound;
    }

    if (code.startsWith('42501') || code.startsWith('28')) {
      return PurchaseFailureType.unauthorized;
    }

    if (code.startsWith('42')) {
      return PurchaseFailureType.invalidResponse;
    }

    if (message.contains('permission denied') ||
        message.contains('row level security') ||
        message.contains('jwt')) {
      return PurchaseFailureType.unauthorized;
    }

    if (message.contains('insufficient stock')) {
      return PurchaseFailureType.insufficientStock;
    }
    if (message.contains('without items')) {
      return PurchaseFailureType.emptyPurchase;
    }
    if (message.contains('invalid purchase status transition') ||
        message.contains('cannot modify a') ||
        message.contains('cannot modify items of a')) {
      return PurchaseFailureType.invalidStatusTransition;
    }

    if (full.contains('uniq_purchases_company_invoice_number')) {
      return PurchaseFailureType.invoiceNumberConflict;
    }

    if (full.contains('purchases_supplier_company_fk')) {
      return PurchaseFailureType.supplierNotFound;
    }
    if (full.contains('purchases_branch_company_fk')) {
      return PurchaseFailureType.branchNotFound;
    }
    if (full.contains('purchase_items_product_company_fk')) {
      return PurchaseFailureType.productNotFound;
    }
    if (full.contains('purchase_items_unit_company_fk')) {
      return PurchaseFailureType.unitNotFound;
    }

    if (message.contains('duplicate key') ||
        message.contains('unique constraint')) {
      return PurchaseFailureType.invoiceNumberConflict;
    }

    if (message.contains('foreign key') ||
        message.contains('violates foreign key')) {
      return PurchaseFailureType.notFound;
    }

    if (_messageLooksLikeNetwork(message)) {
      return PurchaseFailureType.network;
    }

    return PurchaseFailureType.unknown;
  }

  static bool _looksLikeNetworkFailure(Object error) {
    final String description = error.toString().toLowerCase();
    return _messageLooksLikeNetwork(description);
  }

  static bool _messageLooksLikeNetwork(String value) {
    return value.contains('socket') ||
        value.contains('network') ||
        value.contains('connection') ||
        value.contains('timeout') ||
        value.contains('timed out') ||
        value.contains('unreachable') ||
        value.contains('failed host lookup') ||
        value.contains('clientexception');
  }
}

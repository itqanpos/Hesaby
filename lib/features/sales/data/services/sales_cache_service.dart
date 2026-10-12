// lib/features/sales/data/services/sales_cache_service.dart

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/logger.dart';
import '../../domain/entities/sale_entities.dart';

/// Local cache for the sales list so the "Sales" page can render while the
/// device is offline.
///
/// The cache is a single JSON blob keyed by company. It is written on every
/// successful online fetch and read as a fallback when the remote call
/// fails with a network error.
///
/// Only the fields required to render the list are persisted. The cache is
/// not a replacement for the database.
class SalesCacheService {
  SalesCacheService(this._prefs);

  final SharedPreferences _prefs;

  /// Bump when the on-disk shape changes in a backward-incompatible way.
  /// On mismatch the cache is silently ignored (a fresh one is written on
  /// the next successful fetch).
  static const int _schemaVersion = 1;

  String _key(String companyId) => 'hesabi.sales.cache.v1.$companyId';

  /// Saves [sales] for [companyId], replacing any previous snapshot.
  Future<void> save(String companyId, List<Sale> sales) async {
    try {
      final Map<String, Object?> payload = <String, Object?>{
        'version': _schemaVersion,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
        'sales': sales.map(_saleToJson).toList(growable: false),
      };
      await _prefs.setString(_key(companyId), jsonEncode(payload));
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'SalesCacheService: save failed.',
        error,
        stackTrace,
      );
    }
  }

  /// Loads the cached sales list for [companyId].
  ///
  /// Returns `null` when no cache exists, when it is corrupt, or when the
  /// schema version does not match.
  Future<List<Sale>?> load(String companyId) async {
    final String? raw = _prefs.getString(_key(companyId));
    if (raw == null || raw.isEmpty) return null;

    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final Object? versionRaw = decoded['version'];
      if (versionRaw is! int || versionRaw != _schemaVersion) {
        AppLogger.warning(
          'SalesCacheService: schema version mismatch — ignoring cache.',
        );
        return null;
      }

      final Object? salesRaw = decoded['sales'];
      if (salesRaw is! List) return null;

      final List<Sale> parsed = <Sale>[];
      for (final Object? entry in salesRaw) {
        if (entry is! Map) continue;
        final Map<String, Object?> map = <String, Object?>{
          for (final MapEntry<Object?, Object?> e in entry.entries)
            if (e.key is String) e.key! as String: e.value,
        };
        final Sale? sale = _saleFromJson(map);
        if (sale != null) parsed.add(sale);
      }
      return parsed;
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'SalesCacheService: load failed.',
        error,
        stackTrace,
      );
      return null;
    }
  }

  /// Clears the cache for [companyId].
  Future<void> clear(String companyId) async {
    await _prefs.remove(_key(companyId));
  }

  // ---------------------------------------------------------------------------
  // JSON
  // ---------------------------------------------------------------------------

  static Map<String, Object?> _saleToJson(Sale sale) => <String, Object?>{
        'id': sale.id,
        'company_id': sale.companyId,
        'branch_id': sale.branchId,
        'customer_id': sale.customerId,
        'invoice_number': sale.invoiceNumber,
        'sale_date': sale.saleDate.toUtc().toIso8601String(),
        'status': sale.status,
        'subtotal': sale.subtotal,
        'discount': sale.discount,
        'tax_amount': sale.taxAmount,
        'total': sale.total,
        'paid_amount': sale.paidAmount,
        'payment_status': sale.paymentStatus,
        'notes': sale.notes,
        'created_by': sale.createdBy,
        'confirmed_at': sale.confirmedAt?.toUtc().toIso8601String(),
        'cancelled_at': sale.cancelledAt?.toUtc().toIso8601String(),
        'created_at': sale.createdAt.toUtc().toIso8601String(),
        'updated_at': sale.updatedAt.toUtc().toIso8601String(),
      };

  static Sale? _saleFromJson(Map<String, Object?> json) {
    try {
      final Object? id = json['id'];
      final Object? companyId = json['company_id'];
      final Object? branchId = json['branch_id'];
      final Object? saleDateRaw = json['sale_date'];
      final Object? status = json['status'];
      final Object? paymentStatus = json['payment_status'];
      final Object? createdAtRaw = json['created_at'];
      final Object? updatedAtRaw = json['updated_at'];

      if (id is! String ||
          companyId is! String ||
          branchId is! String ||
          saleDateRaw is! String ||
          status is! String ||
          paymentStatus is! String ||
          createdAtRaw is! String ||
          updatedAtRaw is! String) {
        return null;
      }

      DateTime asDate(String s) => DateTime.parse(s).toLocal();

      return Sale(
        id: id,
        companyId: companyId,
        branchId: branchId,
        customerId: json['customer_id'] as String?,
        invoiceNumber: json['invoice_number'] as String?,
        saleDate: asDate(saleDateRaw),
        status: status,
        subtotal: _asDouble(json['subtotal']),
        discount: _asDouble(json['discount']),
        taxAmount: _asDouble(json['tax_amount']),
        total: _asDouble(json['total']),
        paidAmount: _asDouble(json['paid_amount']),
        paymentStatus: paymentStatus,
        notes: json['notes'] as String?,
        createdBy: json['created_by'] as String?,
        confirmedAt: json['confirmed_at'] is String
            ? asDate(json['confirmed_at']! as String)
            : null,
        cancelledAt: json['cancelled_at'] is String
            ? asDate(json['cancelled_at']! as String)
            : null,
        createdAt: asDate(createdAtRaw),
        updatedAt: asDate(updatedAtRaw),
      );
    } on Object {
      return null;
    }
  }

  /// Postgres `numeric` arrives as a `String` through PostgREST, so we
  /// accept both `num` and `String` here.
  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}

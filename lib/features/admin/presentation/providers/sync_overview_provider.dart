// lib/features/admin/presentation/providers/sync_overview_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================================
// DTOs (typed — مطابق لـ get_sync_overview RETURNS TABLE)
// ============================================================================

class SyncDevice {
  const SyncDevice({
    required this.deviceId,
    required this.companyName,
    required this.invoicesCount,
    required this.lastSyncAt,
    required this.lastActivityAt,
  });

  final String deviceId;
  final String? companyName; // null إذا لم يطابق tenant_id شركة
  final int invoicesCount;
  final DateTime? lastSyncAt;
  final DateTime? lastActivityAt;

  bool get neverSynced => lastSyncAt == null;

  /// "نشط" = مزامنة خلال آخر 24 ساعة.
  bool get active24h {
    final DateTime? t = lastSyncAt;
    if (t == null) return false;
    return DateTime.now().toUtc().difference(t) <= const Duration(hours: 24);
  }

  bool get active7d {
    final DateTime? t = lastSyncAt;
    if (t == null) return false;
    return DateTime.now().toUtc().difference(t) <= const Duration(days: 7);
  }

  bool get stale30d {
    final DateTime? t = lastSyncAt;
    if (t == null) return false;
    return DateTime.now().toUtc().difference(t) > const Duration(days: 30);
  }

  factory SyncDevice.fromRow(Map<String, Object?> row) {
    return SyncDevice(
      deviceId: _readString(row, 'device_id') ?? '',
      companyName: _readString(row, 'company_name'),
      invoicesCount: _readInt(row, 'invoices_count'),
      lastSyncAt: _readNullableTimestamp(row, 'last_sync_at'),
      lastActivityAt: _readNullableTimestamp(row, 'last_activity_at'),
    );
  }
}

class SyncOverview {
  const SyncOverview({
    required this.devicesTotal,
    required this.devicesActive24h,
    required this.devicesActive7d,
    required this.devicesStale30d,
    required this.devicesNeverSynced,
    required this.invoicesWithDevice,
    required this.invoicesSynced,
    required this.invoicesPending,
    required this.computedAt,
    required this.devices,
  });

  final int devicesTotal;
  final int devicesActive24h;
  final int devicesActive7d;
  final int devicesStale30d;
  final int devicesNeverSynced;
  final int invoicesWithDevice;
  final int invoicesSynced;
  final int invoicesPending;
  final DateTime computedAt;
  final List<SyncDevice> devices;

  factory SyncOverview.fromRow(Map<String, Object?> row) {
    return SyncOverview(
      devicesTotal: _readInt(row, 'devices_total'),
      devicesActive24h: _readInt(row, 'devices_active_24h'),
      devicesActive7d: _readInt(row, 'devices_active_7d'),
      devicesStale30d: _readInt(row, 'devices_stale_30d'),
      devicesNeverSynced: _readInt(row, 'devices_never_synced'),
      invoicesWithDevice: _readInt(row, 'invoices_with_device'),
      invoicesSynced: _readInt(row, 'invoices_synced'),
      invoicesPending: _readInt(row, 'invoices_pending'),
      computedAt: _readTimestamp(row, 'computed_at'),
      devices: _readDevices(row, 'devices'),
    );
  }
}

// ============================================================================
// Provider
// ============================================================================

class SyncOverviewException implements Exception {
  SyncOverviewException(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  String toString() => 'SyncOverviewException: $message';
}

class SyncOverviewNotifier
    extends AutoDisposeAsyncNotifier<SyncOverview> {
  @override
  Future<SyncOverview> build() async => _fetch();

  Future<void> refresh() async {
    state = const AsyncLoading<SyncOverview>();
    state = await AsyncValue.guard<SyncOverview>(_fetch);
  }

  Future<SyncOverview> _fetch() async {
    final SupabaseClient client = Supabase.instance.client;

    final Object raw;
    try {
      raw = await client.rpc('get_sync_overview');
    } on PostgrestException catch (error) {
      if (error.code == '42501') {
        throw SyncOverviewException(
          'ليس لديك صلاحية لعرض حالة المزامنة.',
          cause: error,
        );
      }
      throw SyncOverviewException(
        'تعذّر تحميل حالة المزامنة: ${error.message}',
        cause: error,
      );
    }

    final Map<String, Object?>? row = _asSingleRow(raw);
    if (row == null) {
      throw SyncOverviewException('استجابة غير صالحة من الخادم.');
    }

    try {
      return SyncOverview.fromRow(row);
    } on FormatException catch (error) {
      throw SyncOverviewException(
        'صيغة بيانات المزامنة غير صحيحة.',
        cause: error,
      );
    }
  }
}

final AutoDisposeAsyncNotifierProvider<SyncOverviewNotifier, SyncOverview>
    syncOverviewProvider =
    AsyncNotifierProvider.autoDispose<SyncOverviewNotifier, SyncOverview>(
  SyncOverviewNotifier.new,
);

// ============================================================================
// Parsing helpers
// ============================================================================

Map<String, Object?>? _asSingleRow(Object? raw) {
  if (raw is List) {
    if (raw.isEmpty) return null;
    final Object? first = raw.first;
    if (first is Map) return Map<String, Object?>.from(first);
    return null;
  }
  if (raw is Map) return Map<String, Object?>.from(raw);
  return null;
}

int _readInt(Map<String, Object?> row, String key) {
  final Object? v = row[key];
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

String? _readString(Map<String, Object?> row, String key) {
  final Object? v = row[key];
  if (v == null) return null;
  if (v is String) return v.isEmpty ? null : v;
  return v.toString();
}

/// rule 25: تواريخ Postgres على الأندرويد — nullable version.
DateTime? _readNullableTimestamp(Map<String, Object?> row, String key) {
  final Object? v = row[key];
  if (v == null) return null;
  if (v is DateTime) return v.toUtc();
  if (v is String) {
    String normalized = v.trim();
    if (normalized.isEmpty) return null;
    if (normalized.contains(' ')) {
      normalized = normalized.replaceFirst(' ', 'T');
    }
    if (normalized.endsWith('+00')) {
      normalized = normalized.replaceAll('+00', 'Z');
    }
    final DateTime? parsed = DateTime.tryParse(normalized);
    if (parsed != null) return parsed.toUtc();
  }
  return null;
}

DateTime _readTimestamp(Map<String, Object?> row, String key) {
  final DateTime? parsed = _readNullableTimestamp(row, key);
  if (parsed == null) {
    throw FormatException('column "$key": invalid timestamp.');
  }
  return parsed;
}

List<SyncDevice> _readDevices(Map<String, Object?> row, String key) {
  final Object? v = row[key];
  if (v is! List) return const <SyncDevice>[];
  final List<SyncDevice> out = <SyncDevice>[];
  for (final Object? e in v) {
    if (e is! Map) continue;
    out.add(SyncDevice.fromRow(Map<String, Object?>.from(e)));
  }
  return out;
}

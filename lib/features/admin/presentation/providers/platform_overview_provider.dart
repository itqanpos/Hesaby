// lib/features/admin/presentation/providers/platform_overview_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================================
// DTO (typed — مطابق لـ get_platform_overview RETURNS TABLE)
// ============================================================================

class RecentCompany {
  const RecentCompany({
    required this.id,
    required this.name,
    required this.subscriptionStatus,
    required this.isSuspended,
    required this.isLifetime,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String? subscriptionStatus;
  final bool isSuspended;
  final bool isLifetime;
  final DateTime createdAt;

  factory RecentCompany.fromRow(Map<String, Object?> row) {
    return RecentCompany(
      id: _readString(row, 'id') ?? '',
      name: _readString(row, 'name') ?? 'بدون اسم',
      subscriptionStatus: _readString(row, 'subscription_status'),
      isSuspended: _readBool(row, 'is_suspended') ?? false,
      isLifetime: _readBool(row, 'is_lifetime') ?? false,
      createdAt: _readTimestamp(row, 'created_at'),
    );
  }
}

class PlatformOverview {
  const PlatformOverview({
    required this.companiesTotal,
    required this.companiesActive,
    required this.companiesTrial,
    required this.companiesSuspended,
    required this.companiesLifetime,
    required this.companiesNewToday,
    required this.companiesNewThisMonth,
    required this.companiesNewThisYear,
    required this.companiesActiveLast7d,
    required this.usersTotal,
    required this.branchesTotal,
    required this.salesTotal,
    required this.salesToday,
    required this.salesThisMonth,
    required this.productsTotal,
    required this.customersTotal,
    required this.revenueTotal,
    required this.revenueThisMonth,
    required this.computedAt,
    required this.recentCompanies,
  });

  final int companiesTotal;
  final int companiesActive;
  final int companiesTrial;
  final int companiesSuspended;
  final int companiesLifetime;
  final int companiesNewToday;
  final int companiesNewThisMonth;
  final int companiesNewThisYear;
  final int companiesActiveLast7d;

  final int usersTotal;
  final int branchesTotal;

  final int salesTotal;
  final int salesToday;
  final int salesThisMonth;

  final int productsTotal;
  final int customersTotal;

  final num revenueTotal;
  final num revenueThisMonth;

  final DateTime computedAt;
  final List<RecentCompany> recentCompanies;

  // ----- derived helpers (للعرض) -----
  int get companiesNonSuspended =>
      companiesTotal - companiesSuspended;

  double get paidRatio {
    if (companiesTotal == 0) return 0;
    return (companiesActive + companiesLifetime) / companiesTotal;
  }

  factory PlatformOverview.fromRow(Map<String, Object?> row) {
    return PlatformOverview(
      companiesTotal: _readInt(row, 'companies_total'),
      companiesActive: _readInt(row, 'companies_active'),
      companiesTrial: _readInt(row, 'companies_trial'),
      companiesSuspended: _readInt(row, 'companies_suspended'),
      companiesLifetime: _readInt(row, 'companies_lifetime'),
      companiesNewToday: _readInt(row, 'companies_new_today'),
      companiesNewThisMonth: _readInt(row, 'companies_new_this_month'),
      companiesNewThisYear: _readInt(row, 'companies_new_this_year'),
      companiesActiveLast7d: _readInt(row, 'companies_active_last_7d'),
      usersTotal: _readInt(row, 'users_total'),
      branchesTotal: _readInt(row, 'branches_total'),
      salesTotal: _readInt(row, 'sales_total'),
      salesToday: _readInt(row, 'sales_today'),
      salesThisMonth: _readInt(row, 'sales_this_month'),
      productsTotal: _readInt(row, 'products_total'),
      customersTotal: _readInt(row, 'customers_total'),
      revenueTotal: _readNum(row, 'revenue_total'),
      revenueThisMonth: _readNum(row, 'revenue_this_month'),
      computedAt: _readTimestamp(row, 'computed_at'),
      recentCompanies: _readRecentCompanies(row, 'recent_companies'),
    );
  }
}

// ============================================================================
// Provider
// ============================================================================

class PlatformOverviewException implements Exception {
  PlatformOverviewException(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  String toString() => 'PlatformOverviewException: $message';
}

class PlatformOverviewNotifier
    extends AutoDisposeAsyncNotifier<PlatformOverview> {
  @override
  Future<PlatformOverview> build() async {
    return _fetch();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<PlatformOverview>();
    state = await AsyncValue.guard<PlatformOverview>(_fetch);
  }

  Future<PlatformOverview> _fetch() async {
    final SupabaseClient client = Supabase.instance.client;

    final Object raw;
    try {
      raw = await client.rpc('get_platform_overview');
    } on PostgrestException catch (error) {
      if (error.code == '42501') {
        throw PlatformOverviewException(
          'ليس لديك صلاحية لعرض ملخص المنصة.',
          cause: error,
        );
      }
      throw PlatformOverviewException(
        'تعذّر تحميل ملخص المنصة: ${error.message}',
        cause: error,
      );
    }

    final Map<String, Object?>? row = _asSingleRow(raw);
    if (row == null) {
      throw PlatformOverviewException('استجابة غير صالحة من الخادم.');
    }

    try {
      return PlatformOverview.fromRow(row);
    } on FormatException catch (error) {
      throw PlatformOverviewException(
        'صيغة بيانات ملخص المنصة غير صحيحة.',
        cause: error,
      );
    }
  }
}

final AutoDisposeAsyncNotifierProvider<PlatformOverviewNotifier,
        PlatformOverview> platformOverviewProvider =
    AsyncNotifierProvider.autoDispose<PlatformOverviewNotifier,
        PlatformOverview>(PlatformOverviewNotifier.new);

// ============================================================================
// Parsing helpers (rule 22 / rule 25)
// ============================================================================

/// RPC ذات RETURNS TABLE تُرجع List بصف واحد.
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

num _readNum(Map<String, Object?> row, String key) {
  final Object? v = row[key];
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

String? _readString(Map<String, Object?> row, String key) {
  final Object? v = row[key];
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

bool? _readBool(Map<String, Object?> row, String key) {
  final Object? v = row[key];
  if (v == null) return null;
  if (v is bool) return v;
  if (v is String) {
    if (v == 'true') return true;
    if (v == 'false') return false;
  }
  return null;
}

/// rule 25: تواريخ Postgres على الأندرويد.
DateTime _readTimestamp(Map<String, Object?> row, String key) {
  final Object? v = row[key];
  if (v is DateTime) return v.toUtc();
  if (v is String) {
    String normalized = v.trim();
    if (normalized.contains(' ')) {
      normalized = normalized.replaceFirst(' ', 'T');
    }
    if (normalized.endsWith('+00')) {
      normalized = normalized.replaceAll('+00', 'Z');
    }
    final DateTime? parsed = DateTime.tryParse(normalized);
    if (parsed != null) return parsed.toUtc();
  }
  throw FormatException('column "$key": invalid timestamp ($v).');
}

List<RecentCompany> _readRecentCompanies(
  Map<String, Object?> row,
  String key,
) {
  final Object? v = row[key];
  if (v is! List) return const <RecentCompany>[];
  final List<RecentCompany> out = <RecentCompany>[];
  for (final Object? e in v) {
    if (e is! Map) continue;
    out.add(RecentCompany.fromRow(Map<String, Object?>.from(e)));
  }
  return out;
}

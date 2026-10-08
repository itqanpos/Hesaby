// lib/features/suppliers/presentation/providers/supplier_stats_providers.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';

// ============================================================================
// KPI counts
// ============================================================================

/// Immutable counters for the suppliers KPI row.
@immutable
class SupplierCounts extends Equatable {
  const SupplierCounts({
    required this.total,
    required this.active,
    required this.inactive,
  });

  const SupplierCounts.zero()
      : total = 0,
        active = 0,
        inactive = 0;

  final int total;
  final int active;
  final int inactive;

  @override
  List<Object?> get props => <Object?>[total, active, inactive];
}

/// Counts suppliers of the current company.
///
/// Uses a single lightweight query (`id, is_active`) scoped to the
/// current company; RLS applies the tenant boundary transparently.
final FutureProvider<SupplierCounts> supplierCountsProvider =
    FutureProvider<SupplierCounts>((ref) async {
  final String? companyId = ref.watch(
    companyContextProvider.select(
      (CompanyContextState s) => s.currentCompany?.id,
    ),
  );
  if (companyId == null) {
    return const SupplierCounts.zero();
  }

  final SupabaseClient? client = _tryClient();
  if (client == null) {
    return const SupplierCounts.zero();
  }

  final List<Map<String, dynamic>> rows = await client
      .from('suppliers')
      .select('id, is_active')
      .eq('company_id', companyId);

  int active = 0;
  int inactive = 0;
  for (final Map<String, dynamic> row in rows) {
    final Object? flag = row['is_active'];
    final bool isActive = flag is bool ? flag : true;
    if (isActive) {
      active++;
    } else {
      inactive++;
    }
  }

  return SupplierCounts(
    total: rows.length,
    active: active,
    inactive: inactive,
  );
});

// ============================================================================
// Per-supplier balance
// ============================================================================

/// Per-supplier financial snapshot.
///
/// [balance] is **positive** when we owe the supplier (liability — a
/// purchase was confirmed but not fully paid), and **negative** when the
/// supplier owes us (advance paid beyond what we bought).
@immutable
class SupplierBalance extends Equatable {
  const SupplierBalance({
    required this.supplierId,
    required this.totalPurchased,
    required this.totalPaid,
  });

  const SupplierBalance.zero({required this.supplierId})
      : totalPurchased = 0,
        totalPaid = 0;

  final String supplierId;

  /// Sum of confirmed purchases for this supplier.
  final double totalPurchased;

  /// Sum of payments made to this supplier.
  final double totalPaid;

  /// `totalPurchased - totalPaid`.
  double get balance => totalPurchased - totalPaid;

  bool get hasActivity => totalPurchased > 0 || totalPaid > 0;
  bool get isSettled => balance == 0;
  bool get isOwedToSupplier => balance > 0;
  bool get isAdvanceToSupplier => balance < 0;

  @override
  List<Object?> get props =>
      <Object?>[supplierId, totalPurchased, totalPaid];
}

/// Provides a map of `supplierId → SupplierBalance` for the current
/// company.
///
/// Two lightweight queries are issued (one per aggregate source) and
/// aggregated in Dart, avoiding N+1 round-trips in the suppliers list.
final FutureProvider<Map<String, SupplierBalance>> supplierBalancesProvider =
    FutureProvider<Map<String, SupplierBalance>>((ref) async {
  final String? companyId = ref.watch(
    companyContextProvider.select(
      (CompanyContextState s) => s.currentCompany?.id,
    ),
  );
  if (companyId == null) {
    return const <String, SupplierBalance>{};
  }

  final SupabaseClient? client = _tryClient();
  if (client == null) {
    return const <String, SupplierBalance>{};
  }

  // Confirmed purchases only: drafts and cancelled rows do not affect the
  // supplier's running balance.
  final List<Map<String, dynamic>> purchases = await client
      .from('purchases')
      .select('supplier_id, total')
      .eq('company_id', companyId)
      .eq('status', 'confirmed');

  final List<Map<String, dynamic>> payments = await client
      .from('supplier_payments')
      .select('supplier_id, amount')
      .eq('company_id', companyId);

  final Map<String, double> purchased = <String, double>{};
  for (final Map<String, dynamic> row in purchases) {
    final Object? sid = row['supplier_id'];
    if (sid is! String) continue;
    purchased[sid] = (purchased[sid] ?? 0) + _parseNum(row['total']);
  }

  final Map<String, double> paid = <String, double>{};
  for (final Map<String, dynamic> row in payments) {
    final Object? sid = row['supplier_id'];
    if (sid is! String) continue;
    paid[sid] = (paid[sid] ?? 0) + _parseNum(row['amount']);
  }

  final Set<String> ids = <String>{
    ...purchased.keys,
    ...paid.keys,
  };

  return <String, SupplierBalance>{
    for (final String id in ids)
      id: SupplierBalance(
        supplierId: id,
        totalPurchased: purchased[id] ?? 0,
        totalPaid: paid[id] ?? 0,
      ),
  };
});

/// Returns the balance of a single supplier, computed from
/// [supplierBalancesProvider] to avoid an extra round-trip.
final ProviderFamily<SupplierBalance, String> supplierBalanceProvider =
    Provider.family<SupplierBalance, String>((ref, String supplierId) {
  final Map<String, SupplierBalance> map =
      ref.watch(supplierBalancesProvider).valueOrNull ??
          const <String, SupplierBalance>{};
  return map[supplierId] ??
      SupplierBalance.zero(supplierId: supplierId);
});

// ============================================================================
// Helpers
// ============================================================================

SupabaseClient? _tryClient() {
  try {
    return Supabase.instance.client;
  } on Object {
    return null;
  }
}

double _parseNum(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

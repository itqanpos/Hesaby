// lib/features/products/presentation/providers/unit_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../data/datasources/unit_remote_datasource.dart';
import '../../data/repositories/unit_repository_impl.dart';
import '../../domain/entities/unit.dart';
import '../../domain/repositories/unit_repository.dart';

/// The application's unit repository.
///
/// Builds a [UnitRepositoryImpl] from the active Supabase client. When
/// Supabase is not initialised (for example when credentials were not
/// provided at build time), the underlying data source wraps a `null`
/// client and every operation fails predictably with a
/// [UnitFailureType.unknown] exception instead of throwing a low-level
/// state error.
final Provider<UnitRepository> unitRepositoryProvider =
    Provider<UnitRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return UnitRepositoryImpl(UnitRemoteDataSource(client));
});

/// Provides the list of units for the currently selected company.
///
/// The notifier reloads automatically whenever [companyContextProvider]
/// reports a different `currentCompany.id`. When no company is selected, it
/// resolves to an empty list.
///
/// Note on naming: [AsyncNotifier] already declares an `update` method with
/// a different signature. Business operations are therefore named
/// `createUnit`, `updateUnit` and `deleteUnit`.
class UnitsNotifier extends AsyncNotifier<List<Unit>> {
  @override
  Future<List<Unit>> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState state) => state.currentCompany?.id,
      ),
    );

    if (companyId == null) {
      return const <Unit>[];
    }

    return ref.read(unitRepositoryProvider).listUnits(companyId);
  }

  /// Creates a new unit for the currently selected company.
  Future<Unit> createUnit({
    required String name,
    String? symbol,
  }) async {
    final String companyId = _requireCurrentCompanyId();

    final Unit created = await ref.read(unitRepositoryProvider).createUnit(
          companyId: companyId,
          name: name,
          symbol: symbol,
        );

    await _reload();
    return created;
  }

  /// Updates an existing unit.
  ///
  /// Passing `null` for a nullable parameter leaves it unchanged, except for
  /// [symbol]: clearing it requires [clearSymbol] to be `true`.
  Future<Unit> updateUnit({
    required String unitId,
    String? name,
    String? symbol,
    bool clearSymbol = false,
    bool? isActive,
  }) async {
    final Unit updated = await ref.read(unitRepositoryProvider).updateUnit(
          unitId: unitId,
          name: name,
          symbol: symbol,
          clearSymbol: clearSymbol,
          isActive: isActive,
        );

    await _reload();
    return updated;
  }

  /// Deletes a unit.
  ///
  /// Throws [UnitException] with type [UnitFailureType.inUse] when products
  /// or product-unit conversions still reference the unit.
  Future<void> deleteUnit(String unitId) async {
    await ref.read(unitRepositoryProvider).deleteUnit(unitId);
    await _reload();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  String _requireCurrentCompanyId() {
    final CompanyContextState context = ref.read(companyContextProvider);
    final String? companyId = context.currentCompany?.id;
    if (companyId == null) {
      throw const UnitException(
        type: UnitFailureType.unauthorized,
        cause: 'No company is currently selected.',
      );
    }
    return companyId;
  }

  Future<void> _reload() async {
    ref.invalidateSelf();
    await future;
  }
}

/// Provides the current company's units.
final AsyncNotifierProvider<UnitsNotifier, List<Unit>> unitsProvider =
    AsyncNotifierProvider<UnitsNotifier, List<Unit>>(UnitsNotifier.new);

// lib/features/suppliers/presentation/providers/supplier_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../data/datasources/supplier_remote_datasource.dart';
import '../../data/repositories/supplier_repository_impl.dart';
import '../../domain/entities/supplier.dart';
import '../../domain/repositories/supplier_repository.dart';

/// The application's supplier repository.
///
/// Builds a [SupplierRepositoryImpl] from the active Supabase client. When
/// Supabase is not initialised (for example when credentials were not
/// provided at build time), the underlying data source wraps a `null`
/// client and every operation fails predictably with a
/// [SupplierFailureType.unknown] exception instead of throwing a
/// low-level state error.
final Provider<SupplierRepository> supplierRepositoryProvider =
    Provider<SupplierRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return SupplierRepositoryImpl(SupplierRemoteDataSource(client));
});

/// Provides the list of suppliers for the currently selected company.
///
/// The notifier reloads automatically whenever [companyContextProvider]
/// reports a different `currentCompany.id`. When no company is selected,
/// it resolves to an empty list.
///
/// Note on naming: [AsyncNotifier] already declares an `update` method with
/// a different signature. Business operations are therefore named
/// `createSupplier`, `updateSupplier` and `deleteSupplier`.
class SuppliersNotifier extends AsyncNotifier<List<Supplier>> {
  @override
  Future<List<Supplier>> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState state) => state.currentCompany?.id,
      ),
    );

    if (companyId == null) {
      return const <Supplier>[];
    }

    return ref.read(supplierRepositoryProvider).listSuppliers(companyId);
  }

  /// Creates a new supplier for the currently selected company.
  ///
  /// Throws [SupplierException] when there is no current company, or when
  /// the underlying repository rejects the operation (name / code / phone
  /// conflict).
  Future<Supplier> createSupplier({
    required String name,
    String? code,
    String? phone,
    String? email,
    String? address,
    String? notes,
  }) async {
    final String companyId = _requireCurrentCompanyId();

    final Supplier created = await ref
        .read(supplierRepositoryProvider)
        .createSupplier(
          companyId: companyId,
          name: name,
          code: code,
          phone: phone,
          email: email,
          address: address,
          notes: notes,
        );

    await _reload();
    return created;
  }

  /// Updates an existing supplier.
  ///
  /// Passing `null` for a nullable parameter leaves it unchanged, except for
  /// the five nullable fields that carry an explicit `clear*` flag:
  /// `code`, `phone`, `email`, `address`, `notes`.
  Future<Supplier> updateSupplier({
    required String supplierId,
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
    final Supplier updated = await ref
        .read(supplierRepositoryProvider)
        .updateSupplier(
          supplierId: supplierId,
          name: name,
          code: code,
          clearCode: clearCode,
          phone: phone,
          clearPhone: clearPhone,
          email: email,
          clearEmail: clearEmail,
          address: address,
          clearAddress: clearAddress,
          notes: notes,
          clearNotes: clearNotes,
          isActive: isActive,
        );

    await _reload();
    return updated;
  }

  /// Deletes a supplier.
  ///
  /// Throws [SupplierException] with type [SupplierFailureType.inUse] when
  /// other rows still reference the supplier (reserved for Phase 7). Prefer
  /// [updateSupplier] with `isActive: false` for a soft disable.
  Future<void> deleteSupplier(String supplierId) async {
    await ref.read(supplierRepositoryProvider).deleteSupplier(supplierId);
    await _reload();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  String _requireCurrentCompanyId() {
    final CompanyContextState context = ref.read(companyContextProvider);
    final String? companyId = context.currentCompany?.id;
    if (companyId == null) {
      throw const SupplierException(
        type: SupplierFailureType.unauthorized,
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

/// Provides the current company's suppliers.
final AsyncNotifierProvider<SuppliersNotifier, List<Supplier>>
    suppliersProvider =
    AsyncNotifierProvider<SuppliersNotifier, List<Supplier>>(
  SuppliersNotifier.new,
);

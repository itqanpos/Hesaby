// lib/features/purchases/presentation/providers/supplier_payment_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../data/repositories/supplier_payment_repository_impl.dart';
import '../../domain/entities/supplier_payment.dart';
import '../../domain/repositories/supplier_payment_repository.dart';

/// Provides the singleton [SupplierPaymentRepository].
final Provider<SupplierPaymentRepository> supplierPaymentRepositoryProvider =
    Provider<SupplierPaymentRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return SupplierPaymentRepositoryImpl(client);
});

/// Provides the payments of a single supplier, most recent first.
///
/// Family provider: argument is the supplier id.
class SupplierPaymentsNotifier
    extends FamilyAsyncNotifier<List<SupplierPayment>, String> {
  @override
  Future<List<SupplierPayment>> build(String supplierId) async {
    return ref
        .read(supplierPaymentRepositoryProvider)
        .listPaymentsForSupplier(supplierId);
  }

  /// Records a payment and refreshes the local list.
  ///
  /// The `companyId` is read from the company context, never supplied by
  /// the caller. Throws [SupplierPaymentException] on failure.
  Future<SupplierPayment> recordPayment({
    required String supplierId,
    required double amount,
    required String paymentMethod,
    required DateTime paymentDate,
    String? purchaseId,
    String? reference,
    String? notes,
  }) async {
    final String companyId = _requireCurrentCompanyId();

    final SupplierPayment created =
        await ref.read(supplierPaymentRepositoryProvider).recordPayment(
              companyId: companyId,
              supplierId: supplierId,
              amount: amount,
              paymentMethod: paymentMethod,
              paymentDate: paymentDate,
              purchaseId: purchaseId,
              reference: reference,
              notes: notes,
            );

    // Refresh the supplier-scoped list.
    ref.invalidateSelf();
    // Also refresh the purchase-scoped list if a purchase was targeted.
    if (purchaseId != null && purchaseId.isNotEmpty) {
      ref.invalidate(supplierPaymentsForPurchaseProvider(purchaseId));
    }

    return created;
  }

  /// Deletes a payment and refreshes the local list.
  Future<void> deletePayment(String paymentId) async {
    await ref
        .read(supplierPaymentRepositoryProvider)
        .deletePayment(paymentId);
    ref.invalidateSelf();
  }

  String _requireCurrentCompanyId() {
    final CompanyContextState context = ref.read(companyContextProvider);
    final String? companyId = context.currentCompany?.id;
    if (companyId == null) {
      throw const SupplierPaymentException(
        type: SupplierPaymentFailureType.unauthorized,
        cause: 'No company is currently selected.',
      );
    }
    return companyId;
  }
}

/// Provides the payments of a single supplier, keyed by supplier id.
final supplierPaymentsForSupplierProvider = AsyncNotifierProvider.family<
    SupplierPaymentsNotifier,
    List<SupplierPayment>,
    String>(SupplierPaymentsNotifier.new);

/// Provides the payments tied to a single purchase, keyed by purchase id.
///
/// Read-only: mutation always goes through the supplier-scoped notifier
/// because a payment must belong to a supplier.
final supplierPaymentsForPurchaseProvider =
    FutureProvider.family<List<SupplierPayment>, String>(
        (ref, String purchaseId) async {
  return ref
      .read(supplierPaymentRepositoryProvider)
      .listPaymentsForPurchase(purchaseId);
});

/// Provides the total amount paid to a single supplier.
///
/// Family provider keyed by supplier id. Invalidate to refresh after
/// recording a payment.
final supplierTotalPaidProvider =
    FutureProvider.family<double, String>((ref, String supplierId) async {
  return ref
      .read(supplierPaymentRepositoryProvider)
      .sumPaymentsForSupplier(supplierId);
});

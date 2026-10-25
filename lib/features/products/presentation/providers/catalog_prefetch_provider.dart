// lib/features/products/presentation/providers/catalog_prefetch_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/network_status_provider.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../sales/data/repositories/cached_customer_repository.dart';
import '../../../sales/presentation/providers/sales_providers.dart';
import '../../data/repositories/cached_product_repository.dart';
import 'product_providers.dart';

/// Runs the offline-first prefetch for **products AND customers**:
/// * once on app start (if online),
/// * whenever the network transitions offline → online,
/// * whenever the current company changes.
///
/// Consumers don't need to do anything — just watch this provider once
/// (e.g. in `app.dart`) to keep it alive.
final Provider<bool> catalogPrefetchProvider = Provider<bool>((ref) {
  ref.keepAlive();

  final String? companyId = ref.watch(
    companyContextProvider.select((s) => s.currentCompany?.id),
  );
  final bool isOnline = ref.watch(isOnlineProvider);

  if (companyId != null && isOnline) {
    // Prefetch products + units
    final productRepo = ref.read(productRepositoryProvider);
    if (productRepo is CachedProductRepositoryImpl) {
      productRepo.prefetchCatalog(companyId);
    }

    // Prefetch customers
    final customerRepo = ref.read(customerRepositoryProvider);
    if (customerRepo is CachedCustomerRepositoryImpl) {
      customerRepo.prefetchCustomers(companyId);
    }
  }

  return true;
});

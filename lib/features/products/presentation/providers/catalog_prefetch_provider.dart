// lib/features/products/presentation/providers/catalog_prefetch_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/network_status_provider.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../data/repositories/cached_product_repository.dart';
import 'product_providers.dart';

/// Runs [CachedProductRepositoryImpl.prefetchCatalog] automatically:
/// * once on app start (if online),
/// * whenever the network transitions offline → online,
/// * whenever the current company changes.
///
/// Consumers don't need to call anything — just watch this provider
/// somewhere (e.g. in `app.dart`) to keep it alive.
final Provider<bool> catalogPrefetchProvider = Provider<bool>((ref) {
  // Keep the provider alive.
  ref.keepAlive();

  final String? companyId = ref.watch(
    companyContextProvider.select((s) => s.currentCompany?.id),
  );
  final bool isOnline = ref.watch(isOnlineProvider);

  if (companyId != null && isOnline) {
    // Fire and forget.
    final repository = ref.read(productRepositoryProvider);
    if (repository is CachedProductRepositoryImpl) {
      repository.prefetchCatalog(companyId);
    }
  }

  return true;
});

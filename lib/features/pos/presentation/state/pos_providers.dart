// lib/features/pos/presentation/state/pos_providers.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/domain/repositories/product_repository.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../domain/entities/pos_cart.dart';
import '../../domain/services/pos_tax_calculator.dart';
import 'pos_cart_notifier.dart';
import 'pos_search_notifier.dart';

// ============================================================================
// Primary providers
// ============================================================================

final NotifierProvider<PosCartNotifier, PosCart> posCartProvider =
    NotifierProvider<PosCartNotifier, PosCart>(PosCartNotifier.new);

final NotifierProvider<PosSearchNotifier, PosSearchState> posSearchProvider =
    NotifierProvider<PosSearchNotifier, PosSearchState>(
  PosSearchNotifier.new,
);

/// ⬇️ جديد: يتتبع المنتج الذي تمت إضافته للتو لتوجيه التركيز إلى حقل الكمية.
/// القيمة هي `key` الخاص بالسطر (productId::unitId).
final StateProvider<String?> focusedCartLineProvider =
    StateProvider<String?>((ref) => null);

// ... (بقية الملف كما هو: posServerSearchProvider, PosTotals, posTotalsProvider, إلخ) ...

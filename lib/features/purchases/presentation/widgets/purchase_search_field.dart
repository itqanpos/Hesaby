// lib/features/purchases/presentation/widgets/purchase_search_field.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../pos/domain/services/barcode_scanner_service.dart';
import '../../../pos/presentation/services/mobile_scanner_service.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/product_unit.dart';
import '../../../products/domain/entities/unit.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../../products/presentation/providers/unit_providers.dart';
import '../state/purchase_focus_providers.dart';
import '../state/purchase_providers.dart';

/// Search field for the purchase form.
///
/// Same UX as the POS search field:
/// * Debounced query (300ms).
/// * Barcode scan affordance.
/// * Clear button.
/// * Quick-add on Enter when exactly one match exists — uses the largest
///   available unit of the product (carton over piece).
class PurchaseSearchField extends ConsumerStatefulWidget {
  const PurchaseSearchField({super.key});

  @override
  ConsumerState<PurchaseSearchField> createState() =>
      _PurchaseSearchFieldState();
}

class _PurchaseSearchFieldState
    extends ConsumerState<PurchaseSearchField> {
  static const BarcodeScannerService _scanner = MobileScannerServiceImpl();
  static const Duration _debounceDelay = Duration(milliseconds: 300);

  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final String initial = ref.read(purchaseSearchProvider).query;
    _controller = TextEditingController(text: initial);
    _focusNode = ref.read(purchaseSearchFocusNodeProvider);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () {
      _debounce = null;
      if (!mounted) return;
      ref.read(purchaseSearchProvider.notifier).setQuery(value);
    });
  }

  void _commitQueryNow(String value) {
    _debounce?.cancel();
    _debounce = null;
    ref.read(purchaseSearchProvider.notifier).setQuery(value);
  }

  void _handleClear() {
    _debounce?.cancel();
    _debounce = null;
    _controller.clear();
    ref.read(purchaseSearchProvider.notifier).clear();
    _focusNode.requestFocus();
  }

  Future<void> _handleScan() async {
    if (!_scanner.isSupported) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'المسح بالكاميرا غير مدعوم. استخدم قارئ باركود خارجي '
              'أو اكتب الرقم يدويًا.',
            ),
          ),
        );
      return;
    }

    final String? barcode = await _scanner.scan(context);
    if (!mounted) return;
    if (barcode == null || barcode.trim().isEmpty) return;

    final String value = barcode.trim();
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _commitQueryNow(value);

    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await _quickAddIfSingleMatch();
  }

  Future<void> _handleSubmitted(String value) async {
    _commitQueryNow(value);
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await _quickAddIfSingleMatch();
  }

  Future<void> _quickAddIfSingleMatch() async {
    final AsyncValue<List<Product>> results =
        ref.read(purchaseSearchResultsProvider);
    final List<Product>? products = results.valueOrNull;
    if (products == null || products.length != 1) return;

    final Product product = products.first;

    try {
      final List<Unit> allUnits =
          ref.read(unitsProvider).valueOrNull ?? const <Unit>[];

      // Prefer the largest available unit (carton over piece).
      final List<ProductUnit> productUnits =
          await ref.read(productUnitsProvider(product.id).future);

      ProductUnit? largest;
      for (final ProductUnit pu in productUnits) {
        if (largest == null ||
            pu.conversionFactor > largest.conversionFactor) {
          largest = pu;
        }
      }

      Unit? pickedUnit;
      double pickedFactor = 1;

      if (largest != null) {
        for (final Unit u in allUnits) {
          if (u.id == largest.unitId) {
            pickedUnit = u;
            pickedFactor = largest.conversionFactor;
            break;
          }
        }
      }

      if (pickedUnit == null) {
        for (final Unit u in allUnits) {
          if (u.id == product.defaultUnitId) {
            pickedUnit = u;
            break;
          }
        }
      }

      if (pickedUnit == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('وحدة المنتج غير متاحة.')),
          );
        return;
      }

      final double pickedCost = product.costPrice * pickedFactor;

      ref.read(purchaseCartProvider.notifier).addProduct(
            product: product,
            unit: pickedUnit,
            quantity: 1,
            unitCost: pickedCost,
            conversionFactor: pickedFactor,
          );

      _debounce?.cancel();
      _debounce = null;
      _controller.clear();
      ref.read(purchaseSearchProvider.notifier).clear();
      _focusNode.requestFocus();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تعذّر إضافة المنتج.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PurchaseSearchState>(
      purchaseSearchProvider,
      (PurchaseSearchState? previous, PurchaseSearchState next) {
        if (next.query != _controller.text) {
          _controller.value = TextEditingValue(
            text: next.query,
            selection: TextSelection.collapsed(
              offset: next.query.length,
            ),
          );
        }
      },
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        textInputAction: TextInputAction.search,
        onChanged: _scheduleQuery,
        onSubmitted: _handleSubmitted,
        decoration: InputDecoration(
          hintText: 'ابحث بالاسم أو الكود أو امسح الباركود',
          prefixIcon: const Icon(Icons.search),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (
              BuildContext context,
              TextEditingValue value,
              Widget? _,
            ) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    tooltip: 'مسح الباركود',
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: _handleScan,
                  ),
                  if (value.text.isNotEmpty)
                    IconButton(
                      tooltip: 'مسح البحث',
                      icon: const Icon(Icons.close),
                      onPressed: _handleClear,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

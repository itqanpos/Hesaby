// lib/features/pos/presentation/widgets/pos_search_field.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/app_text_field.dart';
import '../../../products/domain/entities/product.dart';
import '../../domain/services/barcode_scanner_service.dart';
import '../services/mobile_scanner_service.dart';
import '../state/pos_providers.dart';
import '../state/pos_search_notifier.dart';
import 'pos_results_list.dart';

/// POS search field — the cashier's primary input.
///
/// Responsibilities:
/// * Keep the local [TextEditingController] in sync with
///   `posSearchProvider`.
/// * Provide a Scan affordance backed by [BarcodeScannerService] when the
///   current platform supports a camera.
/// * Support HID scanners (USB / Bluetooth barcode readers) transparently:
///   those devices type into the focused field and press Enter, so
///   [TextField.onSubmitted] is used to trigger a quick-add when exactly
///   one product matches the query.
/// * Offer a clear button when the field is not empty.
///
/// The field does **not** filter anything. Filtering lives in
/// `posSearchResultsProvider`.
class PosSearchField extends ConsumerStatefulWidget {
  const PosSearchField({super.key});

  @override
  ConsumerState<PosSearchField> createState() => _PosSearchFieldState();
}

class _PosSearchFieldState extends ConsumerState<PosSearchField> {
  static const BarcodeScannerService _scanner = MobileScannerServiceImpl();

  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    final String initial = ref.read(posSearchProvider).query;
    _controller = TextEditingController(text: initial);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------------

  void _handleQueryChanged(String value) {
    ref.read(posSearchProvider.notifier).setQuery(value);
  }

  void _handleClear() {
    _controller.clear();
    ref.read(posSearchProvider.notifier).clear();
    _focusNode.requestFocus();
  }

  /// Opens the camera scanner, then uses the scanned value as the query.
  ///
  /// If the scanned value matches exactly one product, that product is
  /// added to the cart immediately.
  Future<void> _handleScan() async {
    if (!_scanner.isSupported) {
      _showUnsupportedMessage();
      return;
    }

    final String? barcode = await _scanner.scan(context);
    if (!mounted) {
      return;
    }
    if (barcode == null || barcode.trim().isEmpty) {
      return;
    }

    final String value = barcode.trim();

    // Push the value into the search field and the notifier.
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    ref.read(posSearchProvider.notifier).setQuery(value);

    // Give the results provider a chance to react.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }

    _quickAddIfSingleMatch();
  }

  /// Called when the user presses Enter in the field.
  ///
  /// HID scanners send `\n` after the barcode; this callback is what makes
  /// them indistinguishable from a manual search plus Enter.
  void _handleSubmitted(String value) {
    _quickAddIfSingleMatch();
  }

  /// If the current search returns exactly one product, adds it to the
  /// cart and clears the field.
  ///
  /// The check is deliberately conservative:
  /// * zero results   → do nothing (the cashier can refine the query),
  /// * one result     → quick-add it,
  /// * two or more    → do nothing (require an explicit choice).
  void _quickAddIfSingleMatch() {
    final AsyncValue<List<Product>> results =
        ref.read(posSearchResultsProvider);
    final List<Product>? products = results.valueOrNull;
    if (products == null || products.length != 1) {
      return;
    }

    final bool added = posQuickAddProduct(ref, products.first);
    if (!added) {
      return;
    }

    _controller.clear();
    ref.read(posSearchProvider.notifier).clear();
    _focusNode.requestFocus();
  }

  void _showUnsupportedMessage() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'المسح بالكاميرا غير مدعوم على هذا الجهاز. '
            'استخدم قارئ باركود خارجي أو اكتب الرقم يدويًا.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Keep the controller in sync if the notifier is cleared from outside
    // (for example after a successful sale).
    final PosSearchState search = ref.watch(posSearchProvider);
    if (search.query != _controller.text) {
      _controller.value = TextEditingValue(
        text: search.query,
        selection: TextSelection.collapsed(offset: search.query.length),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: AppTextField(
        controller: _controller,
        focusNode: _focusNode,
        hint: 'ابحث بالاسم أو الكود أو امسح الباركود',
        prefixIcon: Icons.search,
        autofocus: false,
        enabled: true,
        textInputAction: TextInputAction.search,
        onChanged: _handleQueryChanged,
        onSubmitted: _handleSubmitted,
        suffixIcon: _SuffixActions(
          showClear: search.isNotEmpty,
          onScan: _handleScan,
          onClear: _handleClear,
        ),
      ),
    );
  }
}

// ============================================================================
// Suffix actions — Scan + Clear
// ============================================================================

class _SuffixActions extends StatelessWidget {
  const _SuffixActions({
    required this.showClear,
    required this.onScan,
    required this.onClear,
  });

  final bool showClear;
  final VoidCallback onScan;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          tooltip: 'مسح الباركود',
          icon: Icon(
            Icons.qr_code_scanner,
            color: scheme.onSurfaceVariant,
          ),
          onPressed: onScan,
        ),
        if (showClear)
          IconButton(
            tooltip: 'مسح البحث',
            icon: Icon(
              Icons.close,
              color: scheme.onSurfaceVariant,
            ),
            onPressed: onClear,
          ),
      ],
    );
  }
}

// lib/features/pos/presentation/widgets/pos_search_field.dart

import 'dart:async';

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
/// * **Debounce the notifier update** (see [_debounceDelay]) so a large
///   catalogue is not filtered on every keystroke.
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
///
/// Debounce design:
/// * The debounce is scoped to this widget only; the notifier stays
///   synchronous and unaware of it.
/// * Both Scan and Enter **cancel the pending timer and commit the query
///   immediately**, so the quick-add path never reads results computed
///   against a stale query.
/// * The controller is synced from the notifier via `ref.listen` (not
///   `ref.watch`), so that while a debounce is in flight — and the notifier
///   still holds the previous query — the controller is not reset.
class PosSearchField extends ConsumerStatefulWidget {
  const PosSearchField({super.key});

  @override
  ConsumerState<PosSearchField> createState() => _PosSearchFieldState();
}

class _PosSearchFieldState extends ConsumerState<PosSearchField> {
  static const BarcodeScannerService _scanner = MobileScannerServiceImpl();

  /// How long to wait after the last keystroke before pushing the query
  /// into the notifier.
  static const Duration _debounceDelay = Duration(milliseconds: 300);

  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  /// Pending debounce timer. `null` when no update is scheduled.
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final String initial = ref.read(posSearchProvider).query;
    _controller = TextEditingController(text: initial);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Debounce helpers
  // ---------------------------------------------------------------------------

  /// Schedules a query commit after [_debounceDelay]. Any previously
  /// scheduled commit is discarded.
  void _scheduleQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () {
      _debounce = null;
      if (!mounted) {
        return;
      }
      ref.read(posSearchProvider.notifier).setQuery(value);
    });
  }

  /// Cancels any pending debounce and commits [value] immediately.
  ///
  /// Used by the Scan flow and the Enter (HID) flow, where waiting for the
  /// debounce would compute results against a stale query.
  void _commitQueryNow(String value) {
    _debounce?.cancel();
    _debounce = null;
    ref.read(posSearchProvider.notifier).setQuery(value);
  }

  // ---------------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------------

  void _handleQueryChanged(String value) {
    _scheduleQuery(value);
  }

  void _handleClear() {
    _debounce?.cancel();
    _debounce = null;
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

    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _commitQueryNow(value);

    // Give the results provider a chance to react.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }

    _quickAddIfSingleMatch();
  }

  /// Called when the user presses Enter in the field.
  ///
  /// HID scanners send `\n` after the barcode; Enter commits the current
  /// text immediately (skipping the debounce) before attempting a
  /// quick-add.
  Future<void> _handleSubmitted(String value) async {
    _commitQueryNow(value);

    // Give the results provider a chance to react before reading it.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }

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

    _debounce?.cancel();
    _debounce = null;
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
    // Mirror the notifier's query into the controller whenever it changes
    // from *outside* this field (e.g. after a successful sale cleared the
    // search, or after an explicit `.clear()` call). Using `listen`
    // instead of `watch` means we do not fight the debounce: while the
    // user is typing, the notifier still holds the previous value, and we
    // do not want to reset the controller back to it.
    ref.listen<PosSearchState>(
      posSearchProvider,
      (PosSearchState? previous, PosSearchState next) {
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
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (
            BuildContext context,
            TextEditingValue value,
            Widget? _,
          ) {
            return _SuffixActions(
              showClear: value.text.isNotEmpty,
              onScan: _handleScan,
              onClear: _handleClear,
            );
          },
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

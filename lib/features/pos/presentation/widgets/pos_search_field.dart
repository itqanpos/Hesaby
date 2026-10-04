// lib/features/pos/presentation/widgets/pos_search_field.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/app_text_field.dart';
import '../state/pos_providers.dart';
import '../state/pos_search_notifier.dart';

/// POS search field — the cashier's primary input.
///
/// Responsibilities:
/// * Keep the local [TextEditingController] in sync with
///   `posSearchProvider`.
/// * Provide a Scan affordance that will later be wired to a camera /
///   Bluetooth / HID barcode reader. Until that is available, tapping the
///   icon shows a short "قريبًا" notice.
/// * Offer a clear button when the field is not empty.
///
/// The field does **not** filter anything. Filtering lives in
/// `posSearchResultsProvider`, which combines the current query with the
/// products stream. Keeping the field dumb is intentional: it lets the
/// notifier stay synchronous, testable, and independent of the widget
/// tree.
class PosSearchField extends ConsumerStatefulWidget {
  const PosSearchField({super.key});

  @override
  ConsumerState<PosSearchField> createState() => _PosSearchFieldState();
}

class _PosSearchFieldState extends ConsumerState<PosSearchField> {
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

  Future<void> _handleScan() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('مسح الباركود'),
        content: const Text(
          'ميزة مسح الباركود بالكاميرا أو القارئ الخارجي ستكون متاحة '
          'قريبًا. حاليًا يمكنك كتابة رقم الباركود يدويًا في حقل البحث.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('حسنًا'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Keep the controller in sync if the notifier is cleared from outside
    // (for example after a successful sale). The listener is attached here
    // rather than in initState so that it always observes the latest
    // notifier; provider rebuilds are cheap.
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

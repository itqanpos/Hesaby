// lib/features/pos/presentation/state/pos_focus_providers.dart

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared [FocusNode] for the POS search field.
///
/// Exposed as a provider so keyboard-shortcut handlers at the page level
/// can request focus on the search field without the field having to
/// listen for global keyboard events itself.
///
/// The node is created once per container and disposed with the container.
final Provider<FocusNode> posSearchFocusNodeProvider =
    Provider<FocusNode>((ref) {
  final FocusNode node = FocusNode(debugLabel: 'pos-search-field');
  ref.onDispose(node.dispose);
  return node;
});

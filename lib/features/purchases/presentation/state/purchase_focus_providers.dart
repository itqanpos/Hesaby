// lib/features/purchases/presentation/state/purchase_focus_providers.dart

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared focus node for the purchase search field.
///
/// Held in a provider so that the page can focus the field from outside
/// the widget tree (e.g. via a keyboard shortcut), and so the node is
/// disposed with the provider scope.
final Provider<FocusNode> purchaseSearchFocusNodeProvider =
    Provider<FocusNode>((ref) {
  final FocusNode node = FocusNode(debugLabel: 'purchase-search');
  ref.onDispose(node.dispose);
  return node;
});

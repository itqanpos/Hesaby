// lib/features/purchases/presentation/state/purchase_search_notifier.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Immutable state of the purchase search bar.
@immutable
class PurchaseSearchState extends Equatable {
  const PurchaseSearchState({this.query = ''});

  /// Raw query text as typed by the user. Not trimmed, not lowercased.
  final String query;

  bool get isEmpty => query.trim().isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// Normalised form used by the matcher: trimmed and lowercased.
  String get normalizedQuery => query.trim().toLowerCase();

  PurchaseSearchState copyWith({String? query}) =>
      PurchaseSearchState(query: query ?? this.query);

  @override
  List<Object?> get props => <Object?>[query];

  @override
  String toString() => 'PurchaseSearchState(query: "$query")';
}

/// Owns the purchase search query.
///
/// Mirrors `PosSearchNotifier`: synchronous, no I/O, no debouncing. The
/// debounce lives in the search field widget. Filtering is delegated to
/// `purchaseSearchResultsProvider`.
class PurchaseSearchNotifier extends Notifier<PurchaseSearchState> {
  @override
  PurchaseSearchState build() => const PurchaseSearchState();

  /// Replaces the query. No-op when unchanged.
  void setQuery(String query) {
    if (query == state.query) {
      return;
    }
    state = PurchaseSearchState(query: query);
  }

  /// Clears the query. No-op when already empty.
  void clear() {
    if (state.query.isEmpty) {
      return;
    }
    state = const PurchaseSearchState();
  }
}

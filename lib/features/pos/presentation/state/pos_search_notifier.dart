// lib/features/pos/presentation/state/pos_search_notifier.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Immutable state of the POS search bar.
///
/// Holds the raw text currently typed by the cashier. Filtering and
/// matching logic live in `posSearchResultsProvider` (defined in
/// `pos_providers.dart`), which combines this state with the products
/// stream.
@immutable
class PosSearchState extends Equatable {
  const PosSearchState({this.query = ''});

  /// Raw query text as typed by the user. Not trimmed, not lowercased.
  final String query;

  /// Whether the query is effectively empty (only whitespace).
  bool get isEmpty => query.trim().isEmpty;

  /// Whether the query carries at least one meaningful character.
  bool get isNotEmpty => !isEmpty;

  /// Normalised form used by the matcher: trimmed and lowercased.
  String get normalizedQuery => query.trim().toLowerCase();

  PosSearchState copyWith({String? query}) =>
      PosSearchState(query: query ?? this.query);

  @override
  List<Object?> get props => <Object?>[query];

  @override
  String toString() => 'PosSearchState(query: "$query")';
}

/// Owns the POS search query.
///
/// The notifier is intentionally minimal: it holds the current raw query
/// string and exposes [setQuery] and [clear]. It performs no I/O, no
/// filtering, and no debouncing. Debouncing — if it is ever needed — will
/// live in the presentation layer, not here.
///
/// Filtering the product list is delegated to `posSearchResultsProvider`,
/// which watches both this notifier and `productsProvider`. This keeps the
/// notifier synchronous and easy to test, while letting the results
/// provider forward loading and error states from the products stream.
class PosSearchNotifier extends Notifier<PosSearchState> {
  @override
  PosSearchState build() => const PosSearchState();

  /// Replaces the query.
  ///
  /// A no-op when the new query equals the current one, which avoids
  /// redundant rebuilds when the field fires multiple identical events.
  void setQuery(String query) {
    if (query == state.query) {
      return;
    }
    state = PosSearchState(query: query);
  }

  /// Clears the query.
  ///
  /// A no-op when the query is already empty.
  void clear() {
    if (state.query.isEmpty) {
      return;
    }
    state = const PosSearchState();
  }
}

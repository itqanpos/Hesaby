// test/features/pos/pos_search_notifier_test.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/pos/presentation/state/pos_providers.dart';
import 'package:hesabi/features/pos/presentation/state/pos_search_notifier.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  PosSearchNotifier notifier() => container.read(posSearchProvider.notifier);
  PosSearchState state() => container.read(posSearchProvider);

  // ---------------------------------------------------------------------------
  // PosSearchState
  // ---------------------------------------------------------------------------

  group('PosSearchState', () {
    test('default is empty', () {
      const PosSearchState s = PosSearchState();
      expect(s.query, '');
      expect(s.isEmpty, isTrue);
      expect(s.isNotEmpty, isFalse);
      expect(s.normalizedQuery, '');
    });

    test('isEmpty is true for whitespace-only query', () {
      const PosSearchState s = PosSearchState(query: '   ');
      expect(s.isEmpty, isTrue);
      expect(s.isNotEmpty, isFalse);
    });

    test('isNotEmpty is true for a meaningful query', () {
      const PosSearchState s = PosSearchState(query: 'بيبسي');
      expect(s.isEmpty, isFalse);
      expect(s.isNotEmpty, isTrue);
    });

    test('normalizedQuery trims and lowercases', () {
      const PosSearchState s = PosSearchState(query: '  PEPSI  ');
      expect(s.normalizedQuery, 'pepsi');
    });

    test('copyWith replaces the query only', () {
      const PosSearchState s = PosSearchState(query: 'old');
      final PosSearchState next = s.copyWith(query: 'new');
      expect(next.query, 'new');
    });

    test('equality is based on query', () {
      const PosSearchState a = PosSearchState(query: 'x');
      const PosSearchState b = PosSearchState(query: 'x');
      const PosSearchState c = PosSearchState(query: 'y');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  // ---------------------------------------------------------------------------
  // Notifier
  // ---------------------------------------------------------------------------

  group('PosSearchNotifier', () {
    test('initial state is empty', () {
      expect(state().query, '');
    });

    test('setQuery stores the value', () {
      notifier().setQuery('بيبسي');
      expect(state().query, 'بيبسي');
      expect(state().isNotEmpty, isTrue);
    });

    test('setQuery with an identical value is a no-op', () {
      notifier().setQuery('بيبسي');
      final PosSearchState first = state();

      notifier().setQuery('بيبسي');
      final PosSearchState second = state();

      // The state object must be identical: `setQuery` returns early when
      // the query does not change, so Riverpod does not notify listeners.
      expect(identical(first, second), isTrue);
    });

    test('setQuery accepts an empty string', () {
      notifier().setQuery('بيبسي');
      notifier().setQuery('');
      expect(state().isEmpty, isTrue);
    });

    test('clear resets the query', () {
      notifier().setQuery('بيبسي');
      notifier().clear();
      expect(state().query, '');
      expect(state().isEmpty, isTrue);
    });

    test('clear on an empty state is a no-op', () {
      final PosSearchState first = state();

      notifier().clear();
      final PosSearchState second = state();

      expect(identical(first, second), isTrue);
    });

    test('whitespace-only query is considered empty by the state', () {
      notifier().setQuery('   ');
      expect(state().isEmpty, isTrue);
      expect(state().isNotEmpty, isFalse);
    });
  });
}

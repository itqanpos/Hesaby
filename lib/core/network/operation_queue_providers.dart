// lib/core/network/operation_queue_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';
import 'operation_queue.dart';
import 'pending_operation.dart';

/// Provides a **loaded** [OperationQueue] instance.
///
/// The queue is created and loaded asynchronously (SharedPreferences needs
/// a platform round-trip on first access). Consumers should use:
///
/// * `ref.watch(operationQueueProvider)`         → `AsyncValue<OperationQueue>`
/// * `await ref.read(operationQueueProvider.future)`  → ready instance
/// * `ref.watch(operationQueueProvider).valueOrNull`  → `null` while loading
///
/// The underlying [OperationQueue] instance is stable for the lifetime of
/// the app: [AsyncNotifier.build] is called once per container, and the
/// notifier explicitly avoids self-invalidation so the in-memory cache
/// stays warm across rebuilds.
class OperationQueueNotifier extends AsyncNotifier<OperationQueue> {
  bool _isDisposed = false;

  @override
  Future<OperationQueue> build() async {
    // Rule 1: Riverpod 2.x has no `ref.mounted` — we track disposal
    // manually to guard async continuations.
    ref.onDispose(() {
      _isDisposed = true;
    });

    try {
      final SharedPreferences prefs =
          await SharedPreferences.getInstance();
      if (_isDisposed) {
        // The provider was disposed while we were loading. Returning a
        // value is still required by the type system, but no consumer
        // will read it — the container has already dropped us.
        return OperationQueue(prefs);
      }

      final OperationQueue queue = OperationQueue(prefs);
      await queue.load();
      if (_isDisposed) {
        return queue;
      }

      AppLogger.info(
        'OperationQueue loaded with ${queue.all().length} pending '
        'operation(s).',
      );
      return queue;
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'OperationQueue initialization failed.',
        error,
        stackTrace,
      );
      // Surface the failure to consumers so they can fall back to online
      // mode with a visible error, instead of pretending everything is
      // fine with an empty queue.
      rethrow;
    }
  }
}

/// Async provider exposing a ready-to-use [OperationQueue].
///
/// Consumers should treat the future as effectively single-shot: it
/// resolves once, then stays cached until the container is disposed.
final AsyncNotifierProvider<OperationQueueNotifier, OperationQueue>
    operationQueueProvider =
    AsyncNotifierProvider<OperationQueueNotifier, OperationQueue>(
  OperationQueueNotifier.new,
);

// ============================================================================
// Counters (derived providers)
// ============================================================================

/// Number of **pending** operations for [companyId].
///
/// Returns `0` while the queue is still loading, and `0` when the queue
/// fails to load — the caller should treat a failure via
/// [operationQueueProvider] itself.
///
/// Usage:
/// ```dart
/// final int pending = ref.watch(
///   pendingOperationCountProvider(companyId),
/// );
/// ```
final ProviderFamily<int, String> pendingOperationCountProvider =
    Provider.family<int, String>((Ref ref, String companyId) {
  final AsyncValue<OperationQueue> async = ref.watch(operationQueueProvider);
  return async.maybeWhen(
    data: (OperationQueue queue) => queue.forCompany(companyId)
        .where((PendingOperation op) => op.isPending)
        .length,
    orElse: () => 0,
  );
});

/// Number of **failed** operations for [companyId].
///
/// Failed operations require manual user intervention (retry or delete).
/// Surface this count in the UI so the operator knows something needs
/// attention.
final ProviderFamily<int, String> failedOperationCountProvider =
    Provider.family<int, String>((Ref ref, String companyId) {
  final AsyncValue<OperationQueue> async = ref.watch(operationQueueProvider);
  return async.maybeWhen(
    data: (OperationQueue queue) => queue.failedCountForCompany(companyId),
    orElse: () => 0,
  );
});

/// Total number of operations (pending + failed) for [companyId].
///
/// Convenience provider for badge displays where both states warrant the
/// same visual treatment.
final ProviderFamily<int, String> totalOperationCountProvider =
    Provider.family<int, String>((Ref ref, String companyId) {
  final AsyncValue<OperationQueue> async = ref.watch(operationQueueProvider);
  return async.maybeWhen(
    data: (OperationQueue queue) => queue.countForCompany(companyId),
    orElse: () => 0,
  );
});

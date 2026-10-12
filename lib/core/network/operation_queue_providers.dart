// lib/core/network/operation_queue_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';
import 'operation_queue.dart';
import 'pending_operation.dart';

/// Provides a **loaded** [OperationQueue] instance.
///
/// The underlying [OperationQueue] is mutable. Its in-memory cache is
/// shared with every derived provider, and mutations are broadcast via
/// [operationQueueRevisionProvider] so dependents rebuild automatically.
class OperationQueueNotifier extends AsyncNotifier<OperationQueue> {
  bool _isDisposed = false;

  @override
  Future<OperationQueue> build() async {
    ref.onDispose(() {
      _isDisposed = true;
    });

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (_isDisposed) {
      // The provider was disposed while we were loading. Return a fresh
      // (unloaded) queue so the type contract holds; no consumer will
      // read it.
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

    // Close the queue's broadcast stream when the container goes away.
    ref.onDispose(() {
      queue.dispose();
    });

    return queue;
  }
}

/// Async provider exposing a ready-to-use [OperationQueue].
final AsyncNotifierProvider<OperationQueueNotifier, OperationQueue>
    operationQueueProvider =
    AsyncNotifierProvider<OperationQueueNotifier, OperationQueue>(
  OperationQueueNotifier.new,
);

// ============================================================================
// Reactivity — revision stream
// ============================================================================

/// Emits the queue's current [OperationQueue.revision] and re-emits on
/// every mutation.
///
/// Every derived provider that reads the queue **must** watch this
/// provider to be notified when the queue changes. Reading the queue
/// alone is not enough because the instance stays the same.
final StreamProvider<int> operationQueueRevisionProvider =
    StreamProvider<int>((Ref ref) async* {
  final OperationQueue queue =
      await ref.watch(operationQueueProvider.future);

  // Emit the current revision immediately so late subscribers see the
  // present state, then bridge the queue's stream.
  yield queue.revision;

  await for (final void _ in queue.onChanged) {
    yield queue.revision;
  }
});

// ============================================================================
// Counters (derived providers)
// ============================================================================

/// Number of **pending** operations for [companyId].
final ProviderFamily<int, String> pendingOperationCountProvider =
    Provider.family<int, String>((Ref ref, String companyId) {
  // Reactivity: rebuild whenever the queue's revision changes.
  ref.watch(operationQueueRevisionProvider);

  final OperationQueue? queue =
      ref.watch(operationQueueProvider).valueOrNull;
  if (queue == null) return 0;

  return queue
      .forCompany(companyId)
      .where((PendingOperation op) => op.isPending)
      .length;
});

/// Number of **failed** operations for [companyId].
final ProviderFamily<int, String> failedOperationCountProvider =
    Provider.family<int, String>((Ref ref, String companyId) {
  ref.watch(operationQueueRevisionProvider);

  final OperationQueue? queue =
      ref.watch(operationQueueProvider).valueOrNull;
  if (queue == null) return 0;

  return queue.failedCountForCompany(companyId);
});

/// Total number of operations (pending + failed) for [companyId].
final ProviderFamily<int, String> totalOperationCountProvider =
    Provider.family<int, String>((Ref ref, String companyId) {
  ref.watch(operationQueueRevisionProvider);

  final OperationQueue? queue =
      ref.watch(operationQueueProvider).valueOrNull;
  if (queue == null) return 0;

  return queue.countForCompany(companyId);
});

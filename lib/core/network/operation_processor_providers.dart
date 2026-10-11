// lib/core/network/operation_processor_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/logger.dart';
import 'operation_processor.dart';
import 'operation_queue.dart';
import 'operation_queue_providers.dart';
import 'operation_senders.dart';
import 'pending_operation.dart';

// ============================================================================
// Sender provider
// ============================================================================

/// Provides the singleton [PendingOperationSender] used by the processor.
///
/// The sender wraps the current [SupabaseClient] and is stateless, so a
/// single instance is safe to share across the app.
final Provider<PendingOperationSender> operationSenderProvider =
    Provider<PendingOperationSender>((Ref ref) {
  return buildSupabaseOperationSender();
});

// ============================================================================
// Processor provider
// ============================================================================

/// Provides a ready-to-use [OperationProcessor].
///
/// Returns `null` while [operationQueueProvider] is still loading, or when
/// it has failed to load. Callers that need a processor synchronously must
/// guard against `null`:
///
/// ```dart
/// final OperationProcessor? processor = ref.read(operationProcessorProvider);
/// if (processor == null) return;
/// await processor.processAll(companyId: companyId);
/// ```
///
/// Because [operationQueueProvider] resolves once and stays cached, this
/// provider builds the processor exactly once for the lifetime of the
/// container. The processor's internal `_isRunning` guard therefore
/// correctly serializes concurrent invocations from all trigger points.
final Provider<OperationProcessor?> operationProcessorProvider =
    Provider<OperationProcessor?>((Ref ref) {
  final AsyncValue<OperationQueue> queueAsync =
      ref.watch(operationQueueProvider);
  final OperationQueue? queue = queueAsync.valueOrNull;
  if (queue == null) return null;

  final PendingOperationSender sender = ref.watch(operationSenderProvider);
  return OperationProcessor(queue: queue, sender: sender);
});

// ============================================================================
// Manual trigger
// ============================================================================

/// Convenience helper that processes every pending operation for
/// [companyId] on demand.
///
/// Intended for the "retry" button on the pending-operations page, or for
/// any explicit user action that should kick the queue. Automatic
/// background triggers (connectivity change, app resume) are wired
/// separately in `operation_trigger_provider.dart`.
///
/// Returns the number of operations that were successfully delivered
/// during this run. Returns `0` when the processor is not ready yet.
Future<int> runPendingOperations(
  Ref ref, {
  required String companyId,
}) async {
  final OperationProcessor? processor = ref.read(operationProcessorProvider);
  if (processor == null) {
    AppLogger.info(
      'runPendingOperations: processor not ready yet — skipping.',
    );
    return 0;
  }

  return processor.processAll(companyId: companyId);
}

/// Retries a single failed operation by [clientUuid].
///
/// Intended for the "retry" button next to a failed operation row.
/// Returns `true` when the operation was delivered and removed from the
/// queue.
Future<bool> retryPendingOperation(
  Ref ref, {
  required String clientUuid,
}) async {
  final OperationProcessor? processor = ref.read(operationProcessorProvider);
  if (processor == null) return false;
  return processor.retryOne(clientUuid);
}

/// Discards a single operation by [clientUuid] without sending it.
///
/// Intended for the "discard" button next to a failed operation row.
Future<void> discardPendingOperation(
  Ref ref, {
  required String clientUuid,
}) async {
  final OperationProcessor? processor = ref.read(operationProcessorProvider);
  if (processor == null) return;
  await processor.discardOne(clientUuid);
}

// ============================================================================
// Queue access (for UI)
// ============================================================================

/// Snapshot of every queued operation for [companyId], oldest first.
///
/// Returns an empty list while the queue is loading or when it fails to
/// load — the caller should surface a loading state via
/// [operationQueueProvider] itself if it needs finer-grained feedback.
final ProviderFamily<List<PendingOperation>, String>
    companyOperationsProvider =
    Provider.family<List<PendingOperation>, String>(
  (Ref ref, String companyId) {
    final AsyncValue<OperationQueue> queueAsync =
        ref.watch(operationQueueProvider);
    return queueAsync.maybeWhen(
      data: (OperationQueue queue) => queue.forCompany(companyId),
      orElse: () => const <PendingOperation>[],
    );
  },
);

/// Snapshot of every **failed** operation for [companyId], oldest first.
final ProviderFamily<List<PendingOperation>, String>
    failedOperationsProvider =
    Provider.family<List<PendingOperation>, String>(
  (Ref ref, String companyId) {
    final AsyncValue<OperationQueue> queueAsync =
        ref.watch(operationQueueProvider);
    return queueAsync.maybeWhen(
      data: (OperationQueue queue) => queue
          .forCompany(companyId)
          .where((PendingOperation op) => op.isFailed)
          .toList(growable: false),
      orElse: () => const <PendingOperation>[],
    );
  },
);

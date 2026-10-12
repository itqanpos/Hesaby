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
final Provider<PendingOperationSender> operationSenderProvider =
    Provider<PendingOperationSender>((Ref ref) {
  return buildSupabaseOperationSender();
});

// ============================================================================
// Processor provider
// ============================================================================

/// Provides a ready-to-use [OperationProcessor], or `null` while the
/// queue is still loading / failed to load.
final Provider<OperationProcessor?> operationProcessorProvider =
    Provider<OperationProcessor?>((Ref ref) {
  final OperationQueue? queue =
      ref.watch(operationQueueProvider).valueOrNull;
  if (queue == null) return null;

  final PendingOperationSender sender = ref.watch(operationSenderProvider);
  return OperationProcessor(queue: queue, sender: sender);
});

// ============================================================================
// Manual triggers (WidgetRef flavours — called from UI)
// ============================================================================

/// Processes every pending operation for [companyId] on demand.
///
/// Intended for a "send all" button, or the retry action in the pending
/// operations page. Automatic background triggers (connectivity change,
/// app resume) live in `operation_trigger.dart` and use a `Ref`.
///
/// Returns the number of operations that were successfully delivered
/// during this run. Returns `0` when the processor is not ready yet.
Future<int> runPendingOperations(
  WidgetRef ref, {
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
/// Returns `true` when the operation was delivered and removed from the
/// queue.
Future<bool> retryPendingOperation(
  WidgetRef ref, {
  required String clientUuid,
}) async {
  final OperationProcessor? processor = ref.read(operationProcessorProvider);
  if (processor == null) return false;
  return processor.retryOne(clientUuid);
}

/// Discards a single operation by [clientUuid] without sending it.
Future<void> discardPendingOperation(
  WidgetRef ref, {
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
final ProviderFamily<List<PendingOperation>, String>
    companyOperationsProvider =
    Provider.family<List<PendingOperation>, String>(
  (Ref ref, String companyId) {
    // Reactivity trigger — rebuild whenever the queue's revision changes.
    ref.watch(operationQueueRevisionProvider);

    final OperationQueue? queue =
        ref.watch(operationQueueProvider).valueOrNull;
    if (queue == null) return const <PendingOperation>[];

    return queue.forCompany(companyId);
  },
);

/// Snapshot of every **failed** operation for [companyId], oldest first.
final ProviderFamily<List<PendingOperation>, String>
    failedOperationsProvider =
    Provider.family<List<PendingOperation>, String>(
  (Ref ref, String companyId) {
    ref.watch(operationQueueRevisionProvider);

    final OperationQueue? queue =
        ref.watch(operationQueueProvider).valueOrNull;
    if (queue == null) return const <PendingOperation>[];

    return queue
        .forCompany(companyId)
        .where((PendingOperation op) => op.isFailed)
        .toList(growable: false);
  },
);

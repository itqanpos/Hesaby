// lib/core/network/operation_processor.dart

import '../utils/logger.dart';
import 'operation_queue.dart';
import 'pending_operation.dart';

// ============================================================================
// Sender interface
// ============================================================================

/// Abstraction over the "actual send" step of an operation.
///
/// Implementations translate a [PendingOperation] into concrete calls
/// against the backend (Supabase RPCs, REST inserts, …). They must:
///
/// 1. **Be idempotent.** Sending the same operation twice must not create
///    duplicate rows. The convention is to write the operation's
///    [PendingOperation.clientUuid] into the row's `client_uuid` column
///    and rely on the UNIQUE `(company_id, client_uuid)` index to reject
///    repeats. On a duplicate-key error the sender should treat it as
///    success and return normally.
///
/// 2. **Throw on real failures.** Any exception that reaches the processor
///    counts as an attempt and drives the retry / backoff policy. Network
///    errors and transient 5xx responses should be rethrown; permanent
///    validation errors should also be rethrown (they will exhaust the
///    retry budget quickly and become `failed`, which is the desired
///    outcome).
///
/// 3. **Not swallow cancellation.** There is currently no cancellation
///    mechanism, but future implementations should respect it.
abstract interface class PendingOperationSender {
  /// Sends [operation] to the backend.
  ///
  /// Returns normally on success (including the "already exists" case).
  /// Throws on failure.
  Future<void> send(PendingOperation operation);
}

// ============================================================================
// Processor
// ============================================================================

/// Drives the FIFO delivery of queued operations to the backend.
///
/// Responsibilities:
/// * Pick the oldest pending operation for a company.
/// * Mark it `processing` while the send is in flight.
/// * On success, remove it from the queue.
/// * On failure, increment `attemptCount`, record the error, and either
///   leave it `pending` (retries left) or mark it `failed` (budget spent).
/// * Apply a small backoff between attempts within a single run.
///
/// **Concurrency:** [processAll] is guarded by an internal flag so that
/// two concurrent runs cannot process the same queue. Callers that invoke
/// it from multiple trigger points (connectivity change, app resume,
/// manual retry) are safe.
///
/// **Error handling:** [send] errors are captured per operation. The
/// processor never throws out of [processAll] — a failing operation
/// becomes `failed`, and the loop continues with the next one.
class OperationProcessor {
  OperationProcessor({
    required OperationQueue queue,
    required PendingOperationSender sender,
  })  : _queue = queue,
        _sender = sender;

  final OperationQueue _queue;
  final PendingOperationSender _sender;

  /// Backoff schedule **between attempts of the same operation within a
  /// single run**. Index = `attemptCount - 1` when the attempt failed.
  ///
  /// ```text
  /// attempt 1 fails → wait 2s  → attempt 2
  /// attempt 2 fails → wait 8s  → attempt 3
  /// attempt 3 fails → stop (attemptCount == maxAttempts)
  /// ```
  static const List<Duration> _backoff = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 8),
  ];

  bool _isRunning = false;

  /// Whether a [processAll] run is currently in flight.
  bool get isRunning => _isRunning;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Processes every pending operation for [companyId] in FIFO order.
  ///
  /// Returns the number of operations successfully delivered during this
  /// run. Safe to call repeatedly — a no-op while another run is active.
  ///
  /// **Never throws.** All per-operation errors are captured internally.
  Future<int> processAll({required String companyId}) async {
    if (_isRunning) return 0;
    _isRunning = true;

    int delivered = 0;
    try {
      // Recover from a previous crash: any operation left in `processing`
      // is reset to `pending` so it can be retried.
      await _recoverStuckOperations(companyId: companyId);

      // Loop until the queue has nothing left to process for this company.
      // A hard cap protects against pathological loops (e.g. sender that
      // always succeeds without removing the operation from the queue).
      const int safetyCap = 200;
      int iterations = 0;

      while (iterations < safetyCap) {
        iterations++;

        final PendingOperation? next = _nextPending(companyId);
        if (next == null) break;

        final bool ok = await _processOne(next);
        if (ok) {
          delivered++;
          continue;
        }

        // The operation failed. If it still has retries left, wait the
        // prescribed backoff and try again immediately. Otherwise it has
        // been marked `failed` and we move on to the next operation.
        if (!next.hasRetriesLeft) {
          continue;
        }

        final Duration wait = _backoffFor(next.attemptCount);
        if (wait > Duration.zero) {
          await Future<void>.delayed(wait);
        }
      }

      if (delivered > 0) {
        AppLogger.info(
          'OperationProcessor: delivered $delivered operation(s) for '
          'company $companyId.',
        );
      }
    } on Object catch (error, stackTrace) {
      // Defensive: processAll must never throw.
      AppLogger.error(
        'OperationProcessor: unexpected error in processAll.',
        error,
        stackTrace,
      );
    } finally {
      _isRunning = false;
    }

    return delivered;
  }

  /// Attempts a single operation by its [PendingOperation.clientUuid].
  ///
  /// Intended for the "retry" button on a failed operation. Returns `true`
  /// when the operation was delivered and removed from the queue, `false`
  /// otherwise (including when the operation is not found).
  Future<bool> retryOne(String clientUuid) async {
    final PendingOperation? op = _queue.byUuid(clientUuid);
    if (op == null) return false;

    // Reset the counter so the operation gets a fresh retry budget.
    await _queue.update(
      op.copyWith(
        status: PendingOperationStatus.pending,
        attemptCount: 0,
        lastError: null,
      ),
    );

    final PendingOperation? refreshed = _queue.byUuid(clientUuid);
    if (refreshed == null) return false;

    return _processOne(refreshed);
  }

  /// Removes a single operation from the queue without sending it.
  ///
  /// Intended for the "discard" button on a failed operation.
  Future<void> discardOne(String clientUuid) async {
    await _queue.remove(clientUuid);
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  PendingOperation? _nextPending(String companyId) {
    final List<PendingOperation> all = _queue.forCompany(companyId);
    for (final PendingOperation op in all) {
      if (op.isPending && op.hasRetriesLeft) return op;
    }
    return null;
  }

  Future<bool> _processOne(PendingOperation op) async {
    // Mark as processing before touching the network.
    final PendingOperation processing = op.copyWith(
      status: PendingOperationStatus.processing,
      attemptCount: op.attemptCount + 1,
      lastAttemptAt: DateTime.now(),
    );
    await _queue.update(processing);

    try {
      await _sender.send(processing);
      await _queue.remove(processing.clientUuid);
      return true;
    } on Object catch (error, stackTrace) {
      final String message = _shortError(error);
      final bool hasRetries = processing.hasRetriesLeft;

      AppLogger.warning(
        'OperationProcessor: operation ${processing.clientUuid} '
        'failed (attempt ${processing.attemptCount}/'
        '${PendingOperation.maxAttempts}) — $message',
      );
      if (!hasRetries) {
        AppLogger.error(
          'OperationProcessor: operation ${processing.clientUuid} '
          'exhausted its retry budget.',
          error,
          stackTrace,
        );
      }

      await _queue.update(
        processing.copyWith(
          status: hasRetries
              ? PendingOperationStatus.pending
              : PendingOperationStatus.failed,
          lastError: message,
        ),
      );
      return false;
    }
  }

  /// Resets any operation that was left in `processing` (e.g. because the
  /// app was killed mid-send) back to `pending`.
  Future<void> _recoverStuckOperations({required String companyId}) async {
    final List<PendingOperation> stuck = _queue
        .forCompany(companyId)
        .where((PendingOperation op) => op.isProcessing)
        .toList(growable: false);

    for (final PendingOperation op in stuck) {
      await _queue.update(
        op.copyWith(
          status: PendingOperationStatus.pending,
          lastError: 'Recovered after app restart.',
        ),
      );
    }

    if (stuck.isNotEmpty) {
      AppLogger.info(
        'OperationProcessor: recovered ${stuck.length} stuck '
        'operation(s).',
      );
    }
  }

  static Duration _backoffFor(int attemptCount) {
    final int index = attemptCount - 1;
    if (index < 0 || index >= _backoff.length) return Duration.zero;
    return _backoff[index];
  }

  static String _shortError(Object error) {
    final String s = error.toString().trim();
    if (s.length <= 200) return s;
    return '${s.substring(0, 197)}...';
  }
}

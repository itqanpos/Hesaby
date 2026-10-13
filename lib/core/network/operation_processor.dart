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
///    counts as an attempt — **unless** the processor classifies it as
///    transient (network / timeout / server 5xx), in which case the retry
///    budget is preserved.
///
/// 3. **Not swallow cancellation.** There is currently no cancellation
///    mechanism, but future implementations should respect it.
abstract interface class PendingOperationSender {
  Future<void> send(PendingOperation operation);
}

// ============================================================================
// Processor
// ============================================================================

/// Drives the FIFO delivery of queued operations to the backend.
///
/// ## Retry policy
///
/// * **Transient errors** — network failures, timeouts, 5xx server
///   responses, "connection reset" — are **retried indefinitely** (until
///   the user discards the operation or the queue is cleared). They do
///   **not** consume the retry budget, because the failure is not caused
///   by the operation itself.
///
/// * **Permanent errors** — validation, authorization, 4xx, constraint
///   violations — count against `attemptCount`. After
///   [PendingOperation.maxAttempts] attempts, the operation is marked
///   [PendingOperationStatus.failed] and requires manual intervention.
///
/// * **Backoff within a run** — 2 s, then 8 s between attempts.
class OperationProcessor {
  OperationProcessor({
    required OperationQueue queue,
    required PendingOperationSender sender,
  })  : _queue = queue,
        _sender = sender;

  final OperationQueue _queue;
  final PendingOperationSender _sender;

  static const List<Duration> _backoff = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 8),
  ];

  bool _isRunning = false;

  bool get isRunning => _isRunning;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  Future<int> processAll({required String companyId}) async {
    if (_isRunning) return 0;
    _isRunning = true;

    int delivered = 0;
    try {
      await _recoverStuckOperations(companyId: companyId);

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

        // The operation failed and remains in the queue. Determine what
        // to do next.
        final PendingOperation? updated = _queue.byUuid(next.clientUuid);
        if (updated == null) {
          // Removed concurrently — move on.
          continue;
        }

        if (updated.isFailed) {
          // Budget spent — move to the next operation.
          continue;
        }

        // Still pending → wait the prescribed backoff and try again.
        final Duration wait = _backoffFor(updated.attemptCount);
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

  Future<bool> retryOne(String clientUuid) async {
    final PendingOperation? op = _queue.byUuid(clientUuid);
    if (op == null) return false;

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

  Future<void> discardOne(String clientUuid) async {
    await _queue.remove(clientUuid);
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  PendingOperation? _nextPending(String companyId) {
    final List<PendingOperation> all = _queue.forCompany(companyId);
    for (final PendingOperation op in all) {
      if (op.isPending) return op;
    }
    return null;
  }

  /// Sends a single operation and applies the retry policy based on
  /// whether the error is transient or permanent.
  Future<bool> _processOne(PendingOperation op) async {
    // Mark as processing **without** touching attemptCount — the count is
    // bumped only after we classify a failure as permanent.
    final PendingOperation processing = op.copyWith(
      status: PendingOperationStatus.processing,
      lastAttemptAt: DateTime.now(),
    );
    await _queue.update(processing);

    try {
      await _sender.send(processing);
      await _queue.remove(processing.clientUuid);
      return true;
    } on Object catch (error, stackTrace) {
      final String message = _shortError(error);
      final bool transient = _isTransientError(error);

      final int newAttemptCount = transient
          ? processing.attemptCount
          : processing.attemptCount + 1;

      final bool hasRetries = newAttemptCount < PendingOperation.maxAttempts;
      final PendingOperationStatus newStatus = transient
          ? PendingOperationStatus.pending
          : (hasRetries
              ? PendingOperationStatus.pending
              : PendingOperationStatus.failed);

      if (transient) {
        AppLogger.warning(
          'OperationProcessor: transient failure on '
          '${processing.clientUuid} — will retry without consuming budget. '
          '$message',
        );
      } else {
        AppLogger.warning(
          'OperationProcessor: operation ${processing.clientUuid} '
          'failed (attempt $newAttemptCount/${PendingOperation.maxAttempts}) '
          '— $message',
        );
        if (!hasRetries) {
          AppLogger.error(
            'OperationProcessor: operation ${processing.clientUuid} '
            'exhausted its retry budget.',
            error,
            stackTrace,
          );
        }
      }

      await _queue.update(
        processing.copyWith(
          status: newStatus,
          attemptCount: newAttemptCount,
          lastError: message,
        ),
      );
      return false;
    }
  }

  /// Returns `true` when the error is caused by the environment rather
  /// than by the operation payload — i.e. it is worth retrying without
  /// counting against the retry budget.
  ///
  /// Classification is done by inspecting the error type and the message
  /// text. We deliberately avoid importing `dart:io` (which is not
  /// available on Flutter Web) so the check is string-based.
  static bool _isTransientError(Object error) {
    final String description = error.toString().toLowerCase();

    // Network / connection issues.
    if (description.contains('socket') ||
        description.contains('network') ||
        description.contains('connection') ||
        description.contains('timeout') ||
        description.contains('timed out') ||
        description.contains('unreachable') ||
        description.contains('failed host lookup') ||
        description.contains('clientexception') ||
        description.contains('serverexception')) {
      return true;
    }

    // PostgREST 5xx errors surface either with an HTTP-status hint in the
    // message or with a PG code that starts with '5' (rare). We catch the
    // common text patterns.
    if (description.contains('http/5') ||
        description.contains('status: 500') ||
        description.contains('status: 502') ||
        description.contains('status: 503') ||
        description.contains('status: 504') ||
        description.contains('internal server error') ||
        description.contains('bad gateway') ||
        description.contains('service unavailable') ||
        description.contains('gateway timeout')) {
      return true;
    }

    return false;
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
    if (attemptCount <= 0) return Duration.zero;
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

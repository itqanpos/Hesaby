// lib/core/network/operation_queue.dart

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';
import 'pending_operation.dart';

/// Persistent FIFO queue of write operations awaiting delivery to the
/// server.
///
/// Storage: a single JSON blob in [SharedPreferences] under
/// [_storageKey]. The blob is a small object:
///
/// ```json
/// { "version": 1, "operations": [ {...}, {...} ] }
/// ```
///
/// **Reactivity:** the queue is mutable, so every successful mutation
/// bumps a monotonic [_revision] counter and emits a tick on [onChanged].
/// Riverpod consumers subscribe to that stream (see
/// `operationQueueRevisionProvider`) to rebuild whenever the queue
/// changes.
///
/// **Serialized writes.** A private lock guarantees that concurrent
/// mutations cannot interleave disk writes.
///
/// **Corruption-tolerant.** Individual operations that fail to decode
/// are dropped with a warning; the rest of the queue survives.
///
/// **Multi-tenant aware.** [forCompany] filters by `companyId` so a user
/// who is a member of more than one company sees only the operations of
/// the current tenant.
class OperationQueue {
  OperationQueue(this._prefs);

  final SharedPreferences _prefs;

  /// Bump this when the on-disk shape changes in a way that is not
  /// backward-compatible. On mismatch, the queue is silently dropped.
  static const int _schemaVersion = 1;

  static const String _storageKey = 'hesabi.offline.queue.v1';

  /// In-memory cache. Always in sync with disk while [_loaded] is `true`.
  final List<PendingOperation> _cache = <PendingOperation>[];

  bool _loaded = false;

  /// Guards [_writeToDisk] against concurrent disk writes.
  Future<void>? _writeLock;

  // ---------------------------------------------------------------------------
  // Reactivity
  // ---------------------------------------------------------------------------

  int _revision = 0;

  final StreamController<void> _revisionController =
      StreamController<void>.broadcast();

  /// Monotonic counter incremented after every successful mutation.
  ///
  /// Consumers can compare two reads to detect changes without comparing
  /// the queue's contents.
  int get revision => _revision;

  /// Broadcast stream that emits once per successful mutation.
  ///
  /// Emits `void` — the current [revision] must be read from the queue.
  /// The stream is closed by [dispose].
  Stream<void> get onChanged => _revisionController.stream;

  /// Increments [_revision] and notifies listeners.
  void _bump() {
    _revision++;
    if (!_revisionController.isClosed) {
      _revisionController.add(null);
    }
  }

  /// Closes the internal stream. Call once when the queue is no longer
  /// needed (typically when the Riverpod container is disposed).
  ///
  /// Safe to call multiple times.
  Future<void> dispose() async {
    if (_revisionController.isClosed) return;
    await _revisionController.close();
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  /// Loads the queue from disk. Idempotent — subsequent calls are no-ops.
  ///
  /// Safe to call multiple times; only the first call touches disk.
  Future<void> load() async {
    if (_loaded) return;

    final String? raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      _loaded = true;
      return;
    }

    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        AppLogger.warning(
          'OperationQueue: top-level JSON is not a Map — resetting.',
        );
        await _prefs.remove(_storageKey);
        _loaded = true;
        return;
      }

      final Object? versionRaw = decoded['version'];
      if (versionRaw is! int || versionRaw != _schemaVersion) {
        AppLogger.warning(
          'OperationQueue: schema version mismatch '
          '(found: $versionRaw, expected: $_schemaVersion) — resetting.',
        );
        await _prefs.remove(_storageKey);
        _loaded = true;
        return;
      }

      final Object? opsRaw = decoded['operations'];
      if (opsRaw is! List) {
        AppLogger.warning(
          'OperationQueue: "operations" is not a List — resetting.',
        );
        await _prefs.remove(_storageKey);
        _loaded = true;
        return;
      }

      final List<PendingOperation> parsed = <PendingOperation>[];
      for (final Object? entry in opsRaw) {
        if (entry is! Map) continue;
        final Map<String, Object?> map = <String, Object?>{
          for (final MapEntry<Object?, Object?> e in entry.entries)
            if (e.key is String) e.key! as String: e.value,
        };
        final PendingOperation? op = PendingOperation.tryFromJson(map);
        if (op == null) {
          AppLogger.warning('OperationQueue: skipping corrupt entry.');
          continue;
        }
        parsed.add(op);
      }

      _cache
        ..clear()
        ..addAll(parsed);
      _loaded = true;
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'OperationQueue: load failed — resetting.',
        error,
        stackTrace,
      );
      await _prefs.remove(_storageKey);
      _cache.clear();
      _loaded = true;
    }
  }

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  /// Returns a defensive copy of every queued operation (all companies).
  List<PendingOperation> all() => List<PendingOperation>.unmodifiable(_cache);

  /// Returns every queued operation for [companyId], oldest first.
  List<PendingOperation> forCompany(String companyId) {
    final List<PendingOperation> filtered = _cache
        .where((PendingOperation op) => op.companyId == companyId)
        .toList(growable: false);
    filtered.sort(
      (PendingOperation a, PendingOperation b) =>
          a.createdAt.compareTo(b.createdAt),
    );
    return List<PendingOperation>.unmodifiable(filtered);
  }

  /// Returns every queued operation of [type] for [companyId], oldest
  /// first.
  List<PendingOperation> forCompanyAndType(
    String companyId,
    PendingOperationType type,
  ) {
    return forCompany(companyId)
        .where((PendingOperation op) => op.type == type)
        .toList(growable: false);
  }

  /// Looks up a single operation by its client UUID, or returns `null`.
  PendingOperation? byUuid(String clientUuid) {
    for (final PendingOperation op in _cache) {
      if (op.clientUuid == clientUuid) return op;
    }
    return null;
  }

  /// Count of operations currently queued for [companyId].
  int countForCompany(String companyId) {
    return _cache
        .where((PendingOperation op) => op.companyId == companyId)
        .length;
  }

  /// Count of operations marked [PendingOperationStatus.failed] for
  /// [companyId].
  int failedCountForCompany(String companyId) {
    return _cache
        .where(
          (PendingOperation op) =>
              op.companyId == companyId && op.isFailed,
        )
        .length;
  }

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  /// Appends [operation] to the queue and persists the change.
  ///
  /// If an operation with the same [PendingOperation.clientUuid] already
  /// exists, the existing entry is replaced (idempotent enqueue).
  Future<void> enqueue(PendingOperation operation) async {
    _ensureLoaded();

    final int existingIndex = _cache.indexWhere(
      (PendingOperation op) => op.clientUuid == operation.clientUuid,
    );
    if (existingIndex >= 0) {
      _cache[existingIndex] = operation;
    } else {
      _cache.add(operation);
    }

    await _persist();
    _bump();
  }

  /// Replaces an existing operation in place.
  ///
  /// No-op if the operation is not present in the queue.
  Future<void> update(PendingOperation operation) async {
    _ensureLoaded();

    final int index = _cache.indexWhere(
      (PendingOperation op) => op.clientUuid == operation.clientUuid,
    );
    if (index < 0) return;
    _cache[index] = operation;
    await _persist();
    _bump();
  }

  /// Removes the operation identified by [clientUuid].
  ///
  /// No-op if the operation is not present.
  Future<void> remove(String clientUuid) async {
    _ensureLoaded();

    final int index = _cache.indexWhere(
      (PendingOperation op) => op.clientUuid == clientUuid,
    );
    if (index < 0) return;
    _cache.removeAt(index);
    await _persist();
    _bump();
  }

  /// Removes every operation belonging to [companyId].
  Future<void> clearForCompany(String companyId) async {
    _ensureLoaded();

    final int before = _cache.length;
    _cache.removeWhere(
      (PendingOperation op) => op.companyId == companyId,
    );
    if (_cache.length == before) return;

    await _persist();
    _bump();
  }

  /// Removes every queued operation (all companies).
  ///
  /// Intended for sign-out and account-switch flows.
  Future<void> clearAll() async {
    _ensureLoaded();

    final bool hadAnything = _cache.isNotEmpty;
    _cache.clear();
    await _prefs.remove(_storageKey);
    if (hadAnything) {
      _bump();
    }
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  void _ensureLoaded() {
    if (!_loaded) {
      throw StateError(
        'OperationQueue.load() must be called before any mutation. '
        'Use operationQueueProvider to obtain a loaded instance.',
      );
    }
  }

  /// Serializes [_cache] to disk.
  ///
  /// Uses a small internal lock so that two concurrent callers cannot
  /// interleave disk writes. Only one writer is allowed at a time.
  Future<void> _persist() {
    final Future<void> previous = _writeLock ?? Future<void>.value();
    final Future<void> next = previous.then((_) => _writeToDisk());
    _writeLock = next;
    return next;
  }

  Future<void> _writeToDisk() async {
    try {
      final Map<String, Object?> payload = <String, Object?>{
        'version': _schemaVersion,
        'operations': _cache
            .map((PendingOperation op) => op.toJson())
            .toList(growable: false),
      };
      final String encoded = jsonEncode(payload);
      await _prefs.setString(_storageKey, encoded);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'OperationQueue: persist failed.',
        error,
        stackTrace,
      );
    }
  }
}

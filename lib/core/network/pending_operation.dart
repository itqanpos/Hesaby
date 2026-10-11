// lib/core/network/pending_operation.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

// ============================================================================
// Enums
// ============================================================================

/// Type of a queued operation.
///
/// Each value maps 1:1 to a supported write path in the app. The string
/// stored on disk is [Enum.name], so the values must remain stable across
/// releases.
enum PendingOperationType {
  sale,
  customerPayment,
  supplierPayment,
  expense,
}

/// Lifecycle state of a queued operation.
///
/// * [pending]    — waiting to be sent (initial state after enqueue).
/// * [processing] — a send attempt is in flight right now.
/// * [failed]     — permanent failure after [PendingOperation.maxAttempts]
///                  attempts; requires manual user action.
enum PendingOperationStatus {
  pending,
  processing,
  failed,
}

// ============================================================================
// Model
// ============================================================================

/// A single write operation queued locally while the device is offline (or
/// while a previous send attempt failed) and awaiting delivery to Supabase.
///
/// The operation is identified by a **client-generated UUID**
/// ([clientUuid]). When it reaches the server, the corresponding row is
/// inserted with `client_uuid = this.clientUuid`; a UNIQUE index on
/// `(company_id, client_uuid)` rejects duplicates, so re-sending after a
/// network timeout cannot create the same document twice.
@immutable
class PendingOperation extends Equatable {
  const PendingOperation({
    required this.clientUuid,
    required this.type,
    required this.companyId,
    required this.payload,
    required this.createdAt,
    this.status = PendingOperationStatus.pending,
    this.attemptCount = 0,
    this.lastError,
    this.lastAttemptAt,
  });

  /// Client-generated UUID. Also stored on the server row as
  /// `client_uuid` for idempotency.
  final String clientUuid;

  final PendingOperationType type;

  /// ID of the company that owns this operation. Used to keep the queue
  /// scoped per company when the user is a member of more than one.
  final String companyId;

  /// Raw JSON payload of the write request.
  ///
  /// **Important:** every nested value must be JSON-serializable
  /// (`String` / `num` / `bool` / `null` / `List` / `Map`). Callers are
  /// responsible for converting domain objects before enqueueing.
  final Map<String, Object?> payload;

  /// Local timestamp of enqueue.
  final DateTime createdAt;

  final PendingOperationStatus status;

  /// Number of send attempts already made. Incremented before each try.
  final int attemptCount;

  /// Human-readable error from the last failed attempt (localized later).
  final String? lastError;

  /// Timestamp of the last attempt, or `null` if never attempted.
  final DateTime? lastAttemptAt;

  // ---------------------------------------------------------------------------
  // Constants
  // ---------------------------------------------------------------------------

  /// Maximum number of attempts before an operation is marked [failed].
  static const int maxAttempts = 3;

  // ---------------------------------------------------------------------------
  // Convenience
  // ---------------------------------------------------------------------------

  bool get isPending => status == PendingOperationStatus.pending;
  bool get isProcessing => status == PendingOperationStatus.processing;
  bool get isFailed => status == PendingOperationStatus.failed;

  /// Whether the processor is allowed to pick this operation up.
  bool get canBeProcessed =>
      status == PendingOperationStatus.pending ||
      (status == PendingOperationStatus.processing && attemptCount == 0);

  /// Whether the operation still has retries left after a failure.
  bool get hasRetriesLeft => attemptCount < maxAttempts;

  // ---------------------------------------------------------------------------
  // Copy
  // ---------------------------------------------------------------------------

  PendingOperation copyWith({
    PendingOperationStatus? status,
    int? attemptCount,
    Object? lastError = _sentinel,
    Object? lastAttemptAt = _sentinel,
  }) {
    return PendingOperation(
      clientUuid: clientUuid,
      type: type,
      companyId: companyId,
      payload: payload,
      createdAt: createdAt,
      status: status ?? this.status,
      attemptCount: attemptCount ?? this.attemptCount,
      lastError: identical(lastError, _sentinel)
          ? this.lastError
          : lastError as String?,
      lastAttemptAt: identical(lastAttemptAt, _sentinel)
          ? this.lastAttemptAt
          : lastAttemptAt as DateTime?,
    );
  }

  // ---------------------------------------------------------------------------
  // Equality
  // ---------------------------------------------------------------------------

  @override
  List<Object?> get props => <Object?>[
        clientUuid,
        type,
        companyId,
        payload,
        createdAt,
        status,
        attemptCount,
        lastError,
        lastAttemptAt,
      ];

  @override
  String toString() =>
      'PendingOperation(type: ${type.name}, uuid: $clientUuid, '
      'status: ${status.name}, attempts: $attemptCount)';

  // ---------------------------------------------------------------------------
  // JSON
  // ---------------------------------------------------------------------------

  /// Serializes the operation for local persistence.
  ///
  /// All values written to disk are JSON-safe primitives.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'client_uuid': clientUuid,
      'type': type.name,
      'company_id': companyId,
      'payload': payload,
      'created_at': createdAt.toUtc().toIso8601String(),
      'status': status.name,
      'attempt_count': attemptCount,
      if (lastError != null) 'last_error': lastError,
      if (lastAttemptAt != null)
        'last_attempt_at': lastAttemptAt!.toUtc().toIso8601String(),
    };
  }

  /// Reconstructs an operation from local storage.
  ///
  /// Throws [FormatException] when required fields are missing or have
  /// unexpected types. The caller is expected to skip corrupt entries
  /// (see [tryFromJson]).
  factory PendingOperation.fromJson(Map<String, Object?> json) {
    final Object? uuid = json['client_uuid'];
    final Object? typeRaw = json['type'];
    final Object? company = json['company_id'];
    final Object? payloadRaw = json['payload'];
    final Object? createdAtRaw = json['created_at'];
    final Object? statusRaw = json['status'];
    final Object? attemptsRaw = json['attempt_count'];

    if (uuid is! String || uuid.isEmpty) {
      throw const FormatException('client_uuid is missing or invalid.');
    }
    if (typeRaw is! String) {
      throw const FormatException('type is missing or invalid.');
    }
    if (company is! String || company.isEmpty) {
      throw const FormatException('company_id is missing or invalid.');
    }
    if (payloadRaw is! Map) {
      throw const FormatException('payload is missing or invalid.');
    }
    if (createdAtRaw is! String) {
      throw const FormatException('created_at is missing or invalid.');
    }

    final PendingOperationType type = _parseType(typeRaw);
    final Map<String, Object?> payload = <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in payloadRaw.entries)
        if (entry.key is String) entry.key! as String: entry.value,
    };

    return PendingOperation(
      clientUuid: uuid,
      type: type,
      companyId: company,
      payload: payload,
      createdAt: DateTime.parse(createdAtRaw).toLocal(),
      status: _parseStatus(statusRaw),
      attemptCount: attemptsRaw is int ? attemptsRaw : 0,
      lastError: json['last_error'] as String?,
      lastAttemptAt: json['last_attempt_at'] is String
          ? DateTime.parse(json['last_attempt_at']! as String).toLocal()
          : null,
    );
  }

  /// Lenient variant of [fromJson] that returns `null` instead of throwing.
  ///
  /// Used by the queue loader to skip corrupt entries without crashing the
  /// app on cold start.
  static PendingOperation? tryFromJson(Map<String, Object?> json) {
    try {
      return PendingOperation.fromJson(json);
    } on FormatException {
      return null;
    } on Object {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Internal parsing helpers
  // ---------------------------------------------------------------------------

  static PendingOperationType _parseType(String value) {
    for (final PendingOperationType t in PendingOperationType.values) {
      if (t.name == value) return t;
    }
    throw FormatException('Unknown PendingOperationType: $value');
  }

  static PendingOperationStatus _parseStatus(Object? value) {
    if (value is! String) return PendingOperationStatus.pending;
    for (final PendingOperationStatus s in PendingOperationStatus.values) {
      if (s.name == value) return s;
    }
    return PendingOperationStatus.pending;
  }
}

// ============================================================================
// Sentinel for copyWith
// ============================================================================

/// Distinguishes "argument omitted" from "argument explicitly set to null"
/// in [PendingOperation.copyWith].
const Object _sentinel = Object();

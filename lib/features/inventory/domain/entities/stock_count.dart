// lib/features/inventory/domain/entities/stock_count.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

// ============================================================================
// Status constants
// ============================================================================

/// Canonical status values for [StockCountSession].
///
/// Matches the CHECK constraint on `stock_count_sessions.status`:
/// `('draft', 'confirmed', 'cancelled')`.
abstract final class StockCountStatus {
  static const String draft = 'draft';
  static const String confirmed = 'confirmed';
  static const String cancelled = 'cancelled';

  static const List<String> all = <String>[draft, confirmed, cancelled];
}

// ============================================================================
// Session
// ============================================================================

/// A single stock-count session header.
///
/// A session groups a set of [StockCountItem] entries that were counted on
/// the same day, for the same branch, by the same operator. It starts in
/// `draft` (open for editing) and can be either confirmed (which writes
/// `adjustment_in` / `adjustment_out` movements for every non-zero
/// variance) or cancelled (which discards everything).
@immutable
class StockCountSession extends Equatable {
  const StockCountSession({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.status,
    required this.startedAt,
    this.notes,
    this.confirmedAt,
    this.cancelledAt,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.itemCount = 0,
    this.countedItemCount = 0,
    this.varianceItemCount = 0,
  });

  final String id;
  final String companyId;
  final String branchId;
  final String status;
  final DateTime startedAt;
  final String? notes;
  final DateTime? confirmedAt;
  final DateTime? cancelledAt;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Total number of items in the session (aggregated by the query).
  final int itemCount;

  /// Number of items whose `actual_quantity` has been set.
  final int countedItemCount;

  /// Number of items whose variance is non-zero (after counting).
  final int varianceItemCount;

  bool get isDraft => status == StockCountStatus.draft;
  bool get isConfirmed => status == StockCountStatus.confirmed;
  bool get isCancelled => status == StockCountStatus.cancelled;

  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;

  /// Progress from 0 to 1 — how many items have been counted.
  double get progress {
    if (itemCount == 0) return 0;
    return countedItemCount / itemCount;
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        branchId,
        status,
        startedAt,
        notes,
        confirmedAt,
        cancelledAt,
        createdBy,
        createdAt,
        updatedAt,
        itemCount,
        countedItemCount,
        varianceItemCount,
      ];

  @override
  String toString() =>
      'StockCountSession(id: $id, status: $status, '
      'items: $countedItemCount/$itemCount)';
}

// ============================================================================
// Item
// ============================================================================

/// A single line inside a [StockCountSession].
///
/// `expectedQuantity` is snapshotted when the session is created (from
/// `inventory_balances.quantity_on_hand`). `actualQuantity` is filled in by
/// the operator — it stays `null` until the item has been counted.
///
/// `variance` is `actual - expected` (or `0` when not yet counted), and is
/// used by [confirm] to decide the direction and size of the adjustment
/// movement.
@immutable
class StockCountItem extends Equatable {
  const StockCountItem({
    required this.id,
    required this.companyId,
    required this.sessionId,
    required this.productId,
    required this.expectedQuantity,
    this.unitId,
    this.actualQuantity,
    this.notes,
    // Display-only fields, resolved by the repository.
    this.productName,
    this.unitName,
  });

  final String id;
  final String companyId;
  final String sessionId;
  final String productId;
  final double expectedQuantity;
  final String? unitId;
  final double? actualQuantity;
  final String? notes;

  /// Display name resolved from the products list.
  final String? productName;

  /// Display unit name resolved from the units list.
  final String? unitName;

  bool get isCounted => actualQuantity != null;

  /// Difference between the counted quantity and the expected one.
  ///
  /// Returns `0` when the item has not been counted yet, so callers can
  /// treat "not counted" and "no variance" uniformly.
  double get variance {
    if (actualQuantity == null) return 0;
    return actualQuantity! - expectedQuantity;
  }

  bool get hasVariance => variance != 0;

  /// The movement type that would be written if the session were confirmed.
  String get movementType {
    if (variance > 0) return 'adjustment_in';
    if (variance < 0) return 'adjustment_out';
    return '';
  }

  StockCountItem copyWith({
    double? actualQuantity,
    bool clearActualQuantity = false,
    String? notes,
    bool clearNotes = false,
  }) {
    return StockCountItem(
      id: id,
      companyId: companyId,
      sessionId: sessionId,
      productId: productId,
      expectedQuantity: expectedQuantity,
      unitId: unitId,
      actualQuantity: clearActualQuantity
          ? null
          : (actualQuantity ?? this.actualQuantity),
      notes: clearNotes ? null : (notes ?? this.notes),
      productName: productName,
      unitName: unitName,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        sessionId,
        productId,
        expectedQuantity,
        unitId,
        actualQuantity,
        notes,
        productName,
        unitName,
      ];

  @override
  String toString() =>
      'StockCountItem(product: $productId, '
      'expected: $expectedQuantity, actual: $actualQuantity)';
}

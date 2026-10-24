// lib/features/admin/presentation/providers/audit_logs_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================================
// DTOs (type-safe — لا dynamic)
// ============================================================================

/// سجل تدقيق واحد — مطابق لـ RETURNS TABLE في get_audit_logs().
class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.createdAt,
    required this.actorUserId,
    required this.actorEmail,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.entityLabel,
    required this.reason,
    required this.beforeState,
    required this.afterState,
    required this.metadata,
  });

  final String id;
  final DateTime createdAt;
  final String? actorUserId;
  final String? actorEmail;
  final String action;         // e.g. 'company.suspend'
  final String entityType;     // 'company' | 'user' | 'system'
  final String? entityId;
  final String? entityLabel;
  final String? reason;
  final Map<String, Object?>? beforeState;
  final Map<String, Object?>? afterState;
  final Map<String, Object?>? metadata;

  // ---- Helpers للعرض ----
  String get actionLabel => switch (action) {
        'company.suspend' => 'إيقاف شركة',
        'company.unsuspend' => 'رفع إيقاف شركة',
        'company.update_subscription' => 'تعديل اشتراك',
        'user.create' => 'إنشاء مستخدم',
        'user.update' => 'تعديل مستخدم',
        'user.grant_admin' => 'منح صلاحية أدمن',
        'user.revoke_admin' => 'سحب صلاحية أدمن',
        _ => action,
      };

  String get entityLabelText => switch (entityType) {
        'company' => 'شركة',
        'user' => 'مستخدم',
        'system' => 'نظام',
        _ => entityType,
      };

  bool get isDestructive =>
      action == 'company.suspend' || action == 'user.revoke_admin';

  // ---- Factory من صفّ قاعدة البيانات ----
  factory AuditLogEntry.fromRow(Map<String, Object?> row) {
    return AuditLogEntry(
      id: _readString(row, 'id') ??
          (throw const FormatException('audit row: missing id')),
      createdAt: _readTimestamp(row, 'created_at'),
      actorUserId: _readString(row, 'actor_user_id'),
      actorEmail: _readString(row, 'actor_email'),
      action: _readString(row, 'action') ?? 'unknown',
      entityType: _readString(row, 'entity_type') ?? 'system',
      entityId: _readString(row, 'entity_id'),
      entityLabel: _readString(row, 'entity_label'),
      reason: _readString(row, 'reason'),
      beforeState: _readJsonb(row, 'before_state'),
      afterState: _readJsonb(row, 'after_state'),
      metadata: _readJsonb(row, 'metadata'),
    );
  }
}

// ============================================================================
// Filters
// ============================================================================

class AuditLogFilters {
  const AuditLogFilters({
    this.actionPrefix,
    this.entityType,
    this.search = '',
  });

  final String? actionPrefix; // null = all
  final String? entityType;   // null = all
  final String search;

  AuditLogFilters copyWith({
    String? actionPrefix,
    bool clearActionPrefix = false,
    String? entityType,
    bool clearEntityType = false,
    String? search,
  }) {
    return AuditLogFilters(
      actionPrefix:
          clearActionPrefix ? null : (actionPrefix ?? this.actionPrefix),
      entityType: clearEntityType ? null : (entityType ?? this.entityType),
      search: search ?? this.search,
    );
  }

  bool get isDefault =>
      actionPrefix == null && entityType == null && search.trim().isEmpty;
}

/// Action prefixes المعروضة في الشرائح. null = "الكل".
const List<({String? value, String label})> kAuditActionChips =
    <({String? value, String label})>[
  (value: null, label: 'الكل'),
  (value: 'company.', label: 'الشركات'),
  (value: 'user.', label: 'المستخدمون'),
];

/// Entity types المعروضة في الشرائح. null = "الكل".
const List<({String? value, String label})> kAuditEntityChips =
    <({String? value, String label})>[
  (value: null, label: 'الكل'),
  (value: 'company', label: 'شركة'),
  (value: 'user', label: 'مستخدم'),
  (value: 'system', label: 'نظام'),
];

// ============================================================================
// Page state
// ============================================================================

class AuditLogPage {
  const AuditLogPage({
    required this.entries,
    required this.hasMore,
    required this.isLoadingMore,
    required this.nextOffset,
  });

  final List<AuditLogEntry> entries;
  final bool hasMore;
  final bool isLoadingMore;
  final int nextOffset;

  static const AuditLogPage empty = AuditLogPage(
    entries: <AuditLogEntry>[],
    hasMore: false,
    isLoadingMore: false,
    nextOffset: 0,
  );

  AuditLogPage copyWith({
    List<AuditLogEntry>? entries,
    bool? hasMore,
    bool? isLoadingMore,
    int? nextOffset,
  }) {
    return AuditLogPage(
      entries: entries ?? this.entries,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      nextOffset: nextOffset ?? this.nextOffset,
    );
  }
}

// ============================================================================
// Filters provider (drives the AsyncNotifier via watch)
// ============================================================================

final StateProvider<AuditLogFilters> auditLogFiltersProvider =
    StateProvider<AuditLogFilters>((_) => const AuditLogFilters());

// ============================================================================
// Notifier
// ============================================================================

class AuditLogNotifier extends AutoDisposeAsyncNotifier<AuditLogPage> {
  static const int _pageSize = 50;
  static const int _maxPage = 500; // مطابق لـ LEAST في SQL

  @override
  Future<AuditLogPage> build() async {
    final AuditLogFilters filters = ref.watch(auditLogFiltersProvider);
    return _fetchFirstPage(filters);
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// يعيد تحميل الصفحة الأولى بعد أي تعديل على الفلاتر.
  Future<void> reload() async {
    final AuditLogFilters filters = ref.read(auditLogFiltersProvider);
    state = const AsyncLoading<AuditLogPage>();
    state = await AsyncValue.guard<AuditLogPage>(
      () => _fetchFirstPage(filters),
    );
  }

  /// يحمّل الصفحة التالية ويضيفها إلى القائمة الحالية.
  Future<void> loadMore() async {
    final AuditLogPage? current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    final AuditLogFilters filters = ref.read(auditLogFiltersProvider);
    state = AsyncData<AuditLogPage>(current.copyWith(isLoadingMore: true));

    try {
      final AuditLogPage next = await _fetchPage(
        filters,
        offset: current.nextOffset,
      );
      state = AsyncData<AuditLogPage>(
        current.copyWith(
          entries: <AuditLogEntry>[...current.entries, ...next.entries],
          hasMore: next.hasMore,
          isLoadingMore: false,
          nextOffset: current.nextOffset + next.entries.length,
        ),
      );
    } on Object catch (error, stack) {
      state = AsyncData<AuditLogPage>(current.copyWith(isLoadingMore: false));
      // نرفع الخطأ ليصل إلى UI (SnackBar) لكن لا نفسد القائمة الحالية
      Error.throwWithStackTrace(error, stack);
    }
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  Future<AuditLogPage> _fetchFirstPage(AuditLogFilters filters) =>
      _fetchPage(filters, offset: 0);

  Future<AuditLogPage> _fetchPage(
    AuditLogFilters filters, {
    required int offset,
  }) async {
    final SupabaseClient client = Supabase.instance.client;
    final int limit = _pageSize < _maxPage ? _pageSize : _maxPage;

    final Object? raw;
    try {
      raw = await client.rpc(
        'get_audit_logs',
        params: <String, Object?>{
          'p_action_prefix':
              (filters.actionPrefix == null || filters.actionPrefix!.isEmpty)
                  ? null
                  : filters.actionPrefix,
          'p_entity_type': filters.entityType,
          'p_search':
              filters.search.trim().isEmpty ? null : filters.search.trim(),
          'p_limit': limit,
          'p_offset': offset,
        },
      );
    } on PostgrestException catch (error) {
      throw AuditLogException(
        'تعذّر تحميل سجل التدقيق: ${error.message}',
        cause: error,
      );
    }

    final List<Map<String, Object?>> rows = _asRows(raw);
    final List<AuditLogEntry> entries;
    try {
      entries = rows.map(AuditLogEntry.fromRow).toList(growable: false);
    } on FormatException catch (error) {
      throw AuditLogException(
        'صيغة بيانات سجل التدقيق غير صحيحة.',
        cause: error,
      );
    }

    final bool hasMore = rows.length == limit;
    return AuditLogPage(
      entries: entries,
      hasMore: hasMore,
      isLoadingMore: false,
      nextOffset: offset + entries.length,
    );
  }
}

// ✅ الإصلاح: AutoDisposeAsyncNotifier ↔ AsyncNotifierProvider.autoDispose
final AutoDisposeAsyncNotifierProvider<AuditLogNotifier, AuditLogPage>
    auditLogNotifierProvider =
    AsyncNotifierProvider.autoDispose<AuditLogNotifier, AuditLogPage>(
  AuditLogNotifier.new,
);

// ============================================================================
// Exception
// ============================================================================

class AuditLogException implements Exception {
  AuditLogException(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  String toString() => 'AuditLogException: $message';
}

// ============================================================================
// Parsing helpers (rule 22 / rule 25)
// ============================================================================

/// rule 22: لا `as List<dynamic>`. نتحقق بـ `is` ثم نحوّل كل صف إلى Map typed.
List<Map<String, Object?>> _asRows(Object? raw) {
  if (raw is! List) {
    throw StateError(
      'get_audit_logs returned ${raw.runtimeType}, expected List.',
    );
  }
  final List<Map<String, Object?>> result = <Map<String, Object?>>[];
  for (final Object? element in raw) {
    if (element is! Map) {
      throw StateError(
        'audit row is ${element.runtimeType}, expected Map.',
      );
    }
    result.add(Map<String, Object?>.from(element));
  }
  return result;
}

String? _readString(Map<String, Object?> row, String key) {
  final Object? value = row[key];
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

Map<String, Object?>? _readJsonb(Map<String, Object?> row, String key) {
  final Object? value = row[key];
  if (value == null) return null;
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  // في حال عاد النوع كنص JSON (بعض إعدادات postgrest) — نفشل بأمان.
  throw FormatException(
    'column "$key": expected jsonb (Map), got ${value.runtimeType}.',
  );
}

/// rule 25: تواريخ Postgres على الأندرويد تحتاج ` ` → `T` و `+00` → `Z`.
DateTime _readTimestamp(Map<String, Object?> row, String key) {
  final Object? value = row[key];
  if (value is DateTime) return value.toUtc();
  if (value is String) {
    String normalized = value.trim();
    if (normalized.contains(' ')) {
      normalized = normalized.replaceFirst(' ', 'T');
    }
    if (normalized.endsWith('+00')) {
      normalized = normalized.replaceAll('+00', 'Z');
    }
    final DateTime? parsed = DateTime.tryParse(normalized);
    if (parsed != null) return parsed.toUtc();
  }
  throw FormatException('column "$key": invalid timestamp ($value).');
}

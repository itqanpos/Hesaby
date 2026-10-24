// lib/features/admin/presentation/pages/tabs/admin_audit_log_tab.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../../shared/widgets/app_empty.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loader.dart';
import '../../../../../shared/widgets/app_text_field.dart';
import '../../providers/audit_logs_provider.dart';

// ============================================================================
// Tab
// ============================================================================

class AdminAuditLogTab extends ConsumerStatefulWidget {
  const AdminAuditLogTab({super.key});

  @override
  ConsumerState<AdminAuditLogTab> createState() => _AdminAuditLogTabState();
}

class _AdminAuditLogTabState extends ConsumerState<AdminAuditLogTab> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final double threshold =
        _scrollController.position.maxScrollExtent - 200;
    if (_scrollController.position.pixels >= threshold) {
      ref.read(auditLogNotifierProvider.notifier).loadMore().catchError((_) {
        // الفشل يُعالَج في الـ UI عبر state؛ نمنع وصوله كـ unhandled future.
      });
    }
  }

  Future<void> _refresh() async {
    await ref.read(auditLogNotifierProvider.notifier).reload();
  }

  void _applyFilters(AuditLogFilters next) {
    ref.read(auditLogFiltersProvider.notifier).state = next;
    // الـ AsyncNotifier يبني من جديد بسبب ref.watch(auditLogFiltersProvider).
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<AuditLogPage> pageAsync =
        ref.watch(auditLogNotifierProvider);
    final AuditLogFilters filters = ref.watch(auditLogFiltersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ---- Search + Refresh ----
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: AppTextField(
                  controller: _searchController,
                  hint: 'ابحث بالشركة أو البريد أو السبب',
                  prefixIcon: Icons.search,
                  suffixIcon: filters.search.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'مسح',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchController.clear();
                            _applyFilters(
                              filters.copyWith(search: ''),
                            );
                          },
                        ),
                  onChanged: (String v) {
                    _applyFilters(filters.copyWith(search: v));
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'تحديث',
                onPressed: pageAsync.isLoading ? null : _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),

        // ---- Action chips ----
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _ChipBar(
            current: filters.actionPrefix,
            items: kAuditActionChips,
            onChanged: (String? v) {
              _applyFilters(
                filters.copyWith(
                  actionPrefix: v,
                  clearActionPrefix: v == null,
                ),
              );
            },
          ),
        ),

        // ---- Entity chips ----
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: _ChipBar(
            current: filters.entityType,
            items: kAuditEntityChips,
            onChanged: (String? v) {
              _applyFilters(
                filters.copyWith(
                  entityType: v,
                  clearEntityType: v == null,
                ),
              );
            },
          ),
        ),

        const Divider(height: 1),

        // ---- List ----
        Expanded(
          child: pageAsync.when(
            loading: () => const AppLoader(),
            error: (Object error, StackTrace _) => AppErrorView(
              title: 'تعذّر تحميل سجل التدقيق',
              message: _errorMessage(error),
              retryLabel: 'إعادة المحاولة',
              onRetry: _refresh,
            ),
            data: (AuditLogPage page) {
              if (page.entries.isEmpty) {
                return AppEmptyView(
                  icon: filters.isDefault
                      ? Icons.history_toggle_off
                      : Icons.search_off_outlined,
                  title: filters.isDefault
                      ? 'لا يوجد سجل تدقيق'
                      : 'لا نتائج',
                  message: filters.isDefault
                      ? 'لم يتم تسجيل أي إجراءات إدارية بعد.'
                      : 'لا توجد سجلات تطابق الفلاتر الحالية.',
                );
              }
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: page.entries.length + (page.hasMore ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) {
                    if (index >= page.entries.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final AuditLogEntry entry = page.entries[index];
                    return _AuditLogTile(
                      entry: entry,
                      onTap: () => _showDetails(context, entry),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showDetails(
    BuildContext context,
    AuditLogEntry entry,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _AuditLogDetailsDialog(entry: entry),
    );
  }

  static String _errorMessage(Object error) {
    if (error is AuditLogException) return error.message;
    return 'حدث خطأ غير متوقع. حاول مرة أخرى.';
  }
}

// ============================================================================
// Chip bar
// ============================================================================

class _ChipBar extends StatelessWidget {
  const _ChipBar({
    required this.current,
    required this.items,
    required this.onChanged,
  });

  final String? current;
  final List<({String? value, String label})> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final ({String? value, String label}) item in items) ...<Widget>[
            ChoiceChip(
              label: Text(item.label),
              selected: current == item.value,
              onSelected: (_) => onChanged(item.value),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// Tile
// ============================================================================

class _AuditLogTile extends StatelessWidget {
  const _AuditLogTile({required this.entry, required this.onTap});

  final AuditLogEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color accent = entry.isDestructive ? scheme.error : scheme.primary;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _iconFor(entry.action),
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // Title row
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            entry.actionLabel,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: accent,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          DateFormat('yyyy/MM/dd HH:mm')
                              .format(entry.createdAt.toLocal()),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Entity
                    Row(
                      children: <Widget>[
                        Text(
                          entry.entityLabelText,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (entry.entityLabel != null) ...<Widget>[
                          Text(
                            ' · ',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              entry.entityLabel!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),

                    // Reason
                    if (entry.reason != null && entry.reason!.isNotEmpty) ...<
                        Widget>[
                      const SizedBox(height: 4),
                      Text(
                        entry.reason!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    // Actor
                    if (entry.actorEmail != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        'بواسطة: ${entry.actorEmail}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_left, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(String action) {
    if (action.startsWith('company.suspend')) return Icons.block;
    if (action.startsWith('company.unsuspend')) return Icons.check_circle_outline;
    if (action.startsWith('company.')) return Icons.storefront_outlined;
    if (action.startsWith('user.grant')) return Icons.security;
    if (action.startsWith('user.revoke')) return Icons.lock_open;
    if (action.startsWith('user.')) return Icons.person_outline;
    return Icons.history;
  }
}

// ============================================================================
// Details dialog
// ============================================================================

class _AuditLogDetailsDialog extends StatelessWidget {
  const _AuditLogDetailsDialog({required this.entry});

  final AuditLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: <Widget>[
          Icon(
            entry.isDestructive ? Icons.warning_amber : Icons.info_outline,
            color: entry.isDestructive ? scheme.error : scheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(entry.actionLabel)),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _InfoRow(
                label: 'التاريخ',
                value: DateFormat('yyyy/MM/dd HH:mm:ss')
                    .format(entry.createdAt.toLocal()),
              ),
              _InfoRow(
                label: 'المنفّذ',
                value: entry.actorEmail ?? '—',
              ),
              _InfoRow(
                label: 'الكيان',
                value: '${entry.entityLabelText}'
                    '${entry.entityLabel != null ? ' — ${entry.entityLabel}' : ''}',
              ),
              if (entry.reason != null && entry.reason!.isNotEmpty)
                _InfoRow(label: 'السبب', value: entry.reason!),
              if (entry.beforeState != null || entry.afterState != null) ...<
                  Widget>[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Text(
                  'تفاصيل التغيير',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                _JsonDiff(
                  before: entry.beforeState,
                  after: entry.afterState,
                  highlightKeys: _preferredHighlightKeys(entry.action),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }

  /// مفاتيح نبرزها أولاً لتسهيل قراءة التغيير.
  static List<String> _preferredHighlightKeys(String action) {
    if (action.startsWith('company.suspend') ||
        action.startsWith('company.unsuspend')) {
      return const <String>['is_suspended', 'suspension_reason'];
    }
    if (action == 'company.update_subscription') {
      return const <String>[
        'subscription_status',
        'plan_id',
        'billing_cycle',
        'subscribed_until',
        'is_lifetime',
      ];
    }
    return const <String>[];
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// JSON diff viewer
// ============================================================================

class _JsonDiff extends StatelessWidget {
  const _JsonDiff({
    required this.before,
    required this.after,
    required this.highlightKeys,
  });

  final Map<String, Object?>? before;
  final Map<String, Object?>? after;
  final List<String> highlightKeys;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final Set<String> keys = <String>{
      ...?before?.keys,
      ...?after?.keys,
    };

    // ترتيب: المفاتيح المميّزة أولًا، ثم أبجديًا.
    final List<String> ordered = <String>[
      ...highlightKeys.where(keys.contains),
      ...(keys.toList()
        ..removeWhere(highlightKeys.contains)
        ..sort()),
    ];

    if (ordered.isEmpty) {
      return Text(
        'لا توجد حقول مسجَّلة.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final String key in ordered)
            _DiffRow(
              field: key,
              before: before?[key],
              after: after?[key],
            ),
        ],
      ),
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({
    required this.field,
    required this.before,
    required this.after,
  });

  final String field;
  final Object? before;
  final Object? after;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final bool changed = _stringify(before) != _stringify(after);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 130,
            child: Text(
              field,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: changed ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                _valueChip(
                  theme,
                  scheme,
                  _stringify(before),
                  bg: scheme.surface,
                  fg: scheme.onSurfaceVariant,
                ),
                if (changed)
                  Icon(
                    Icons.arrow_forward,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                _valueChip(
                  theme,
                  scheme,
                  _stringify(after),
                  bg: changed
                      ? scheme.primary.withValues(alpha: 0.12)
                      : scheme.surface,
                  fg: changed ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _valueChip(
    ThemeData theme,
    ColorScheme scheme,
    String text, {
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }

  static String _stringify(Object? value) {
    if (value == null) return '—';
    if (value is String) return value.isEmpty ? '""' : value;
    if (value is num || value is bool) return value.toString();
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } on Object {
      return value.toString();
    }
  }
}

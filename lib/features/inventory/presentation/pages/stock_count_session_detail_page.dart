// lib/features/inventory/presentation/pages/stock_count_session_detail_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/entities/stock_count.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../providers/inventory_providers.dart';

/// Detail page of a single stock-count session.
///
/// Responsibilities:
/// * Show every item with its `expected_quantity` and, once entered, its
///   `actual_quantity` and `variance`.
/// * Let the operator type the counted quantity for any item.
/// * Confirm the session (writes adjustment movements) or cancel it.
///
/// The page is read-only for `confirmed` / `cancelled` sessions.
class StockCountSessionDetailPage extends ConsumerStatefulWidget {
  const StockCountSessionDetailPage({
    super.key,
    required this.sessionId,
  });

  final String sessionId;

  @override
  ConsumerState<StockCountSessionDetailPage> createState() =>
      _StockCountSessionDetailPageState();
}

class _StockCountSessionDetailPageState
    extends ConsumerState<StockCountSessionDetailPage> {
  String? _searchQuery;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<StockCountSession> sessionAsync =
        ref.watch(stockCountSessionProvider(widget.sessionId));
    final AsyncValue<List<StockCountItem>> itemsAsync =
        ref.watch(stockCountItemsProvider(widget.sessionId));

    return AppShell(
      appBar: AppBar(
        title: const Text('تفاصيل الجرد'),
        actions: <Widget>[
          IconButton(
            tooltip: 'تحديث',
            onPressed: () {
              ref
                  .read(stockCountSessionProvider(widget.sessionId).notifier)
                  .refresh();
              ref
                  .read(stockCountItemsProvider(widget.sessionId).notifier)
                  .refresh();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Builder(
        builder: (BuildContext context) {
          if (sessionAsync.isLoading || itemsAsync.isLoading) {
            return const AppLoader();
          }
          if (sessionAsync.hasError) {
            return AppErrorView(
              title: 'تعذّر تحميل الجلسة',
              message: _errorMessage(sessionAsync.error!),
              retryLabel: 'إعادة المحاولة',
              onRetry: () => ref.invalidate(
                stockCountSessionProvider(widget.sessionId),
              ),
            );
          }
          if (itemsAsync.hasError) {
            return AppErrorView(
              title: 'تعذّر تحميل البنود',
              message: _errorMessage(itemsAsync.error!),
              retryLabel: 'إعادة المحاولة',
              onRetry: () => ref.invalidate(
                stockCountItemsProvider(widget.sessionId),
              ),
            );
          }

          final StockCountSession session = sessionAsync.value!;
          final List<StockCountItem> allItems = itemsAsync.value!;
          final List<StockCountItem> items =
              _filter(allItems, _searchQuery ?? '');

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: _Header(session: session, items: allItems),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: AppTextField(
                  hint: 'ابحث بالاسم أو الكود أو الباركود',
                  prefixIcon: Icons.search,
                  onChanged: (String value) {
                    setState(() => _searchQuery = value);
                  },
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? const AppEmptyView(
                        icon: Icons.search_off_outlined,
                        title: 'لا نتائج',
                        message: 'لم يُطابق أي منتج كلمة البحث.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (BuildContext context, int index) {
                          final StockCountItem item = items[index];
                          final bool editable = session.isDraft;
                          return _ItemCard(
                            item: item,
                            editable: editable,
                            onEdit: editable
                                ? () => _editItem(context, item)
                                : null,
                          );
                        },
                      ),
              ),
              if (session.isDraft)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: AppButton(
                          label: 'إلغاء الجلسة',
                          icon: Icons.cancel_outlined,
                          variant: AppButtonVariant.danger,
                          expanded: true,
                          onPressed: () =>
                              _cancelSession(context, session),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppButton(
                          label: 'اعتماد الجرد',
                          icon: Icons.check_circle_outline,
                          expanded: true,
                          onPressed: () =>
                              _confirmSession(context, session),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  List<StockCountItem> _filter(List<StockCountItem> items, String query) {
    final String trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return items;
    return items.where((StockCountItem item) {
      final String name = (item.productName ?? '').toLowerCase();
      return name.contains(trimmed);
    }).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _editItem(
    BuildContext context,
    StockCountItem item,
  ) async {
    final double? value = await showDialog<double>(
      context: context,
      builder: (BuildContext dialogContext) => _CountItemDialog(item: item),
    );
    if (value == null || !context.mounted) return;

    try {
      await ref
          .read(stockCountItemsProvider(widget.sessionId).notifier)
          .setActual(itemId: item.id, actualQuantity: value);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل الكمية الفعلية')),
      );
    } on InventoryException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_failureMessage(error.type))),
      );
    }
  }

  Future<void> _confirmSession(
    BuildContext context,
    StockCountSession session,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('اعتماد الجرد'),
        content: const Text(
          'سيتم إنشاء حركات تسوية لكل فرق. هل أنت متأكد؟',
        ),
        actions: <Widget>[
          AppButton(
            label: 'إلغاء',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            label: 'اعتماد',
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final int count = await ref
          .read(inventoryRepositoryProvider)
          .confirmStockCountSession(session.id);
      ref.invalidate(stockCountSessionsProvider(
        const StockCountSessionsArgs(),
      ));
      ref.invalidate(stockCountSessionProvider(session.id));
      ref.invalidate(inventoryBalancesProvider(session.branchId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم الاعتماد — $count حركة'),
        ),
      );
      Navigator.of(context).pop();
    } on InventoryException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_failureMessage(error.type))),
      );
    }
  }

  Future<void> _cancelSession(
    BuildContext context,
    StockCountSession session,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('إلغاء الجلسة'),
        content: const Text('هل أنت متأكد من إلغاء جلسة الجرد؟'),
        actions: <Widget>[
          AppButton(
            label: 'رجوع',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            label: 'إلغاء الجلسة',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(inventoryRepositoryProvider)
          .cancelStockCountSession(session.id);
      ref.invalidate(stockCountSessionsProvider(
        const StockCountSessionsArgs(),
      ));
      ref.invalidate(stockCountSessionProvider(session.id));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إلغاء الجلسة')),
      );
      Navigator.of(context).pop();
    } on InventoryException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_failureMessage(error.type))),
      );
    }
  }
}

// ============================================================================
// Header
// ============================================================================

class _Header extends StatelessWidget {
  const _Header({required this.session, required this.items});

  final StockCountSession session;
  final List<StockCountItem> items;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final int total = items.length;
    final int counted =
        items.where((StockCountItem i) => i.isCounted).length;
    final int withVariance =
        items.where((StockCountItem i) => i.isCounted && i.hasVariance).length;
    final double progress = total == 0 ? 0 : counted / total;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  AppFormatters.dateTime(session.startedAt.toLocal()),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  _statusLabel(session.status),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (session.hasNotes) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                session.notes!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Text(
                  'مُعدّ: $counted / $total',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (withVariance > 0)
                  Text(
                    'فروق: $withVariance',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.error,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Item card
// ============================================================================

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.editable,
    this.onEdit,
  });

  final StockCountItem item;
  final bool editable;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final bool counted = item.isCounted;
    final bool hasVariance = item.hasVariance;
    final Color accent = !counted
        ? scheme.onSurfaceVariant
        : (hasVariance ? scheme.error : scheme.primary);

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: editable ? onEdit : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  !counted
                      ? Icons.help_outline
                      : (hasVariance
                          ? Icons.warning_amber_outlined
                          : Icons.check_circle_outline),
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
                    Text(
                      item.productName ?? 'منتج',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _quantityLine(item),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (counted && hasVariance) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        _varianceLine(item),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (editable)
                Icon(
                  Icons.edit_outlined,
                  color: scheme.onSurfaceVariant,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _quantityLine(StockCountItem item) {
    final String unit = item.unitName ?? '';
    final String expected =
        AppFormatters.quantity(item.expectedQuantity);
    if (item.isCounted) {
      final String actual =
          AppFormatters.quantity(item.actualQuantity ?? 0);
      return 'النظام: $expected $unit · الفعلي: $actual $unit';
    }
    return 'النظام: $expected $unit · لم يُعدّ بعد';
  }

  String _varianceLine(StockCountItem item) {
    final double v = item.variance;
    final String sign = v > 0 ? '+' : '';
    return 'الفرق: $sign${AppFormatters.quantity(v)}';
  }
}

// ============================================================================
// Count item dialog
// ============================================================================

class _CountItemDialog extends StatefulWidget {
  const _CountItemDialog({required this.item});

  final StockCountItem item;

  @override
  State<_CountItemDialog> createState() => _CountItemDialogState();
}

class _CountItemDialogState extends State<_CountItemDialog> {
  late final TextEditingController _controller;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final double? initial = widget.item.actualQuantity;
    _controller = TextEditingController(
      text: initial == null ? '' : _formatNumber(initial),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static String _formatNumber(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    final double? value = double.tryParse(_controller.text.trim());
    if (value == null) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String unit = widget.item.unitName ?? '';
    return AlertDialog(
      title: Text(widget.item.productName ?? 'عدّ منتج'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'كمية النظام: '
                '${AppFormatters.quantity(widget.item.expectedQuantity)} $unit',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: 'الكمية الفعلية $unit',
                  border: const OutlineInputBorder(),
                ),
                validator: (String? value) {
                  final String trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return 'الرجاء إدخال الكمية';
                  final double? parsed = double.tryParse(trimmed);
                  if (parsed == null) return 'الرجاء إدخال رقم صحيح';
                  if (parsed < 0) return 'لا يمكن أن تكون الكمية سالبة';
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        AppButton(
          label: 'إلغاء',
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.of(context).pop(null),
        ),
        AppButton(
          label: 'حفظ',
          onPressed: _submit,
        ),
      ],
    );
  }
}

// ============================================================================
// Localization helpers
// ============================================================================

String _statusLabel(String status) {
  switch (status) {
    case StockCountStatus.draft:
      return 'مسودة';
    case StockCountStatus.confirmed:
      return 'معتمدة';
    case StockCountStatus.cancelled:
      return 'ملغاة';
    default:
      return 'غير معروفة';
  }
}

String _errorMessage(Object error) {
  if (error is InventoryException) {
    return _failureMessage(error.type);
  }
  return 'حدث خطأ غير متوقع.';
}

String _failureMessage(InventoryFailureType type) => switch (type) {
      InventoryFailureType.network =>
        'تعذّر الاتصال بالخادم. تحقق من الإنترنت.',
      InventoryFailureType.unauthorized =>
        'تحتاج صلاحية inventory.adjust.',
      InventoryFailureType.notFound => 'الجلسة غير موجودة.',
      InventoryFailureType.insufficientStock => 'الرصيد غير كافٍ.',
      InventoryFailureType.productNotFound => 'المنتج غير متاح.',
      InventoryFailureType.branchNotFound => 'الفرع غير متاح.',
      InventoryFailureType.invalidMovementType => 'نوع الحركة غير معروف.',
      InventoryFailureType.invalidMovement =>
        'بيانات غير صحيحة.',
      InventoryFailureType.invalidResponse =>
        'تعذّر قراءة البيانات.',
      InventoryFailureType.unknown =>
        'تعذّر إتمام العملية.',
    };

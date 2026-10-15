// lib/features/inventory/presentation/pages/stock_count_sessions_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../domain/entities/stock_count.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../providers/inventory_providers.dart';

/// Lists the stock-count sessions of the current company.
///
/// The page can be filtered by branch and by status. Tapping a session
/// opens the detail page (items + counting). The "new session" action
/// creates a draft and immediately navigates to the detail page.
class StockCountSessionsPage extends ConsumerStatefulWidget {
  const StockCountSessionsPage({super.key});

  @override
  ConsumerState<StockCountSessionsPage> createState() =>
      _StockCountSessionsPageState();
}

class _StockCountSessionsPageState
    extends ConsumerState<StockCountSessionsPage> {
  String? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final CompanyContextState contextState =
        ref.watch(companyContextProvider);
    final String? branchId = contextState.currentBranch?.id;

    if (branchId == null) {
      return AppShell(
        appBar: AppBar(title: const Text('جلسات الجرد')),
        body: const AppEmptyView(
          icon: Icons.store_mall_directory_outlined,
          title: 'لم يتم اختيار فرع',
          message: 'اختر فرعًا من الصفحة الرئيسية لعرض جلسات الجرد.',
        ),
      );
    }

    final StockCountSessionsArgs args = StockCountSessionsArgs(
      branchId: branchId,
      status: _statusFilter,
    );
    final AsyncValue<List<StockCountSession>> sessionsAsync =
        ref.watch(stockCountSessionsProvider(args));

    return AppShell(
      appBar: AppBar(
        title: const Text('جلسات الجرد'),
        actions: <Widget>[
          IconButton(
            tooltip: 'تحديث',
            onPressed: () => ref
                .read(stockCountSessionsProvider(args).notifier)
                .refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: _StatusFilterRow(
              selected: _statusFilter,
              onChanged: (String? status) {
                setState(() => _statusFilter = status);
              },
            ),
          ),
          Expanded(
            child: sessionsAsync.when(
              loading: () => const AppLoader(),
              error: (Object error, StackTrace _) => AppErrorView(
                title: 'تعذّر تحميل الجلسات',
                message: _errorMessage(error),
                retryLabel: 'إعادة المحاولة',
                onRetry: () => ref.invalidate(
                  stockCountSessionsProvider(args),
                ),
              ),
              data: (List<StockCountSession> sessions) {
                if (sessions.isEmpty) {
                  return AppEmptyView(
                    icon: Icons.fact_check_outlined,
                    title: 'لا توجد جلسات جرد',
                    message: _statusFilter == null
                        ? 'ابدأ بإنشاء جلسة جرد جديدة لفرعك الحالي.'
                        : 'لا توجد جلسات بالحالة المختارة.',
                    action: AppButton(
                      label: 'جرد جديد',
                      icon: Icons.add,
                      onPressed: () => _createSession(context, branchId),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) {
                    final StockCountSession session = sessions[index];
                    return _SessionCard(
                      session: session,
                      onTap: () => _openSession(context, session),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createSession(context, branchId),
        icon: const Icon(Icons.add),
        label: const Text('جرد جديد'),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _createSession(
    BuildContext context,
    String branchId,
  ) async {
    final String? notes = await showDialog<String?>(
      context: context,
      builder: (BuildContext dialogContext) => const _NewSessionDialog(),
    );
    if (!context.mounted) return;

    // `null` from the dialog means cancelled.
    if (notes == null) return;

    final StockCountSessionsArgs args = StockCountSessionsArgs(
      branchId: branchId,
      status: _statusFilter,
    );

    try {
      final String sessionId = await ref
          .read(stockCountSessionsProvider(args).notifier)
          .createSession(
            branchId: branchId,
            notes: notes.isEmpty ? null : notes,
          );

      if (!context.mounted) return;
      _openSessionById(context, sessionId);
    } on InventoryException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_failureMessage(error.type))),
      );
    }
  }

  void _openSession(
    BuildContext context,
    StockCountSession session,
  ) {
    _openSessionById(context, session.id);
  }

  void _openSessionById(BuildContext context, String sessionId) {
    context.pushNamed(
      AppRouter.stockCountDetailName,
      pathParameters: <String, String>{'id': sessionId},
    );
  }
}

// ============================================================================
// Status filter row
// ============================================================================

class _StatusFilterRow extends StatelessWidget {
  const _StatusFilterRow({
    required this.selected,
    required this.onChanged,
  });

  /// `null` = "الكل".
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          ChoiceChip(
            label: const Text('الكل'),
            selected: selected == null,
            onSelected: (_) => onChanged(null),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('مسودة'),
            selected: selected == StockCountStatus.draft,
            onSelected: (_) => onChanged(StockCountStatus.draft),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('معتمدة'),
            selected: selected == StockCountStatus.confirmed,
            onSelected: (_) => onChanged(StockCountStatus.confirmed),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('ملغاة'),
            selected: selected == StockCountStatus.cancelled,
            onSelected: (_) => onChanged(StockCountStatus.cancelled),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Session card
// ============================================================================

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.onTap,
  });

  final StockCountSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final _StatusAppearance appearance =
        _statusAppearance(session.status, scheme);

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: appearance.background,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      appearance.icon,
                      color: appearance.foreground,
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
                          AppFormatters.dateTime(session.startedAt.toLocal()),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          appearance.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: appearance.foreground,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_left,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              if (session.hasNotes) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  session.notes!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// New session dialog
// ============================================================================

class _NewSessionDialog extends StatefulWidget {
  const _NewSessionDialog();

  @override
  State<_NewSessionDialog> createState() => _NewSessionDialogState();
}

class _NewSessionDialogState extends State<_NewSessionDialog> {
  final TextEditingController _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('جرد جديد'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'سيتم إنشاء جلسة جرد جديدة تحتوي على كل منتجات الفرع '
              'مع أرصدتها الحالية. أدخل الكميات الفعلية بعد ذلك.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              maxLines: 2,
              enabled: true,
              decoration: const InputDecoration(
                labelText: 'ملاحظات — اختياري',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        AppButton(
          label: 'إلغاء',
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.of(context).pop(null),
        ),
        AppButton(
          label: 'إنشاء',
          onPressed: () => Navigator.of(context).pop(
            _notesController.text.trim(),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Status appearance
// ============================================================================

class _StatusAppearance {
  const _StatusAppearance({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
}

_StatusAppearance _statusAppearance(String status, ColorScheme scheme) {
  switch (status) {
    case StockCountStatus.draft:
      return _StatusAppearance(
        label: 'مسودة — قابلة للتعديل',
        icon: Icons.edit_note_outlined,
        background: const Color(0xFFE65100).withValues(alpha: 0.12),
        foreground: const Color(0xFFE65100),
      );
    case StockCountStatus.confirmed:
      return _StatusAppearance(
        label: 'معتمدة',
        icon: Icons.check_circle_outline,
        background: const Color(0xFF2E7D32).withValues(alpha: 0.12),
        foreground: const Color(0xFF2E7D32),
      );
    case StockCountStatus.cancelled:
      return _StatusAppearance(
        label: 'ملغاة',
        icon: Icons.cancel_outlined,
        background: scheme.errorContainer,
        foreground: scheme.error,
      );
    default:
      return _StatusAppearance(
        label: 'غير معروفة',
        icon: Icons.help_outline,
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurfaceVariant,
      );
  }
}

// ============================================================================
// Localization helpers
// ============================================================================

String _errorMessage(Object error) {
  if (error is InventoryException) {
    return _failureMessage(error.type);
  }
  return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
}

String _failureMessage(InventoryFailureType type) => switch (type) {
      InventoryFailureType.network =>
        'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.',
      InventoryFailureType.unauthorized =>
        'انتهت صلاحية الجلسة أو لا تملك صلاحية inventory.adjust.',
      InventoryFailureType.notFound => 'الجلسة المطلوبة غير موجودة.',
      InventoryFailureType.insufficientStock => 'الرصيد غير كافٍ.',
      InventoryFailureType.productNotFound => 'المنتج غير متاح.',
      InventoryFailureType.branchNotFound => 'الفرع غير متاح.',
      InventoryFailureType.invalidMovementType => 'نوع الحركة غير معروف.',
      InventoryFailureType.invalidMovement =>
        'بيانات غير صحيحة. تحقق من القيم.',
      InventoryFailureType.invalidResponse =>
        'تعذّر قراءة البيانات. يرجى المحاولة لاحقًا.',
      InventoryFailureType.unknown =>
        'تعذّر إتمام العملية. يرجى المحاولة مرة أخرى.',
    };

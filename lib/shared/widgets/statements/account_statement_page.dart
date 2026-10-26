// lib/shared/widgets/statements/account_statement_page.dart
//
// Generic account statement page — customer, supplier, and any future
// party (employee, cashbox, …).
//
// **Phase 4 update (filter redesign):**
// * The two chip rows (period + entry-type) that used to sit above the
//   table have been merged into a single AppBar filter button that opens
//   `statement_filter_sheet.dart`.
// * The button shows a `Badge.count` with the number of active filters
//   (0–2). When zero, the badge is hidden.
// * A compact `StatementActiveFilterBar` appears under the summary bar
//   **only** when at least one filter is active, with a "مسح" shortcut
//   that resets both filters in one tap.
// * `custom` period preset was removed — see `statement_filters.dart`.
//
// Layout (top → bottom):
//   InfoCard
//   SummaryBar              ← 4 cells: opening / debit / credit / closing
//   ReconciliationBanner    ← only when cached ≠ computed balance
//   ActiveFilterBar         ← only when a filter is active
//   TableHeader             ← sticky; hidden when statement is empty
//   Expanded(EntriesList)

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart' show Printing;

import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import 'models/statement_filters.dart';
import 'models/statement_models.dart';
import 'statement_csv_export.dart';
import 'widgets/statement_active_filter_bar.dart';
import 'widgets/statement_closing_balance_card.dart';
import 'widgets/statement_empty_view.dart';
import 'widgets/statement_entry_row.dart';
import 'widgets/statement_filter_sheet.dart';
import 'widgets/statement_info_card.dart';
import 'widgets/statement_reconciliation_banner.dart';
import 'widgets/statement_summary_bar.dart';
import 'widgets/statement_table_header.dart';

// ============================================================================
// Configuration
// ============================================================================

/// Extra AppBar action injected by the caller (e.g. "تعديل الرصيد" for a
/// customer, "تسجيل دفعة" for a supplier).
@immutable
class StatementExtraAction {
  const StatementExtraAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;

  /// Returns `true` when the page should refresh after it completes.
  final Future<bool> Function(
    BuildContext context,
    WidgetRef ref,
    StatementView? view,
  ) onPressed;
}

/// Everything the generic [AccountStatementPage] needs to render a
/// specific party's statement.
@immutable
class StatementPageConfig<T> {
  const StatementPageConfig({
    required this.title,
    required this.avatarIcon,
    required this.partyKind,
    required this.watch,
    required this.adapt,
    required this.refresh,
    required this.errorMessage,
    this.print,
    this.extraAction,
    this.enableCsvExport = true,
  });

  final String title;
  final IconData avatarIcon;
  final StatementPartyKind partyKind;

  final AsyncValue<T> Function(
    WidgetRef ref,
    DateTime? from,
    DateTime? to,
  ) watch;

  final StatementView Function(T raw) adapt;

  final Future<void> Function(
    WidgetRef ref,
    DateTime? from,
    DateTime? to,
  ) refresh;

  final String Function(Object error) errorMessage;

  final Future<void> Function(
    BuildContext context,
    WidgetRef ref,
    T rawStatement,
  )? print;

  final StatementExtraAction? extraAction;

  /// Show the "تصدير CSV" button in the AppBar. Defaults to `true`.
  final bool enableCsvExport;
}

// ============================================================================
// Page
// ============================================================================

class AccountStatementPage<T> extends ConsumerStatefulWidget {
  const AccountStatementPage({
    required this.config,
    super.key,
  });

  final StatementPageConfig<T> config;

  @override
  ConsumerState<AccountStatementPage<T>> createState() =>
      _AccountStatementPageState<T>();
}

class _AccountStatementPageState<T>
    extends ConsumerState<AccountStatementPage<T>> {
  StatementPeriodPreset _preset = StatementPeriodPreset.all;
  StatementEntryFilter _entryFilter = StatementEntryFilter.all;
  bool _isPrinting = false;
  bool _isExporting = false;

  // ---------------------------------------------------------------------------
  // Derived period bounds
  // ---------------------------------------------------------------------------

  DateTime? get _fromDate =>
      _preset.computeFrom(now: DateTime.now());

  DateTime? get _toDate =>
      _preset.computeTo(now: DateTime.now());

  /// Number of **active** filters (preset + entry type), used by the
  /// AppBar badge. Range: 0..2.
  int get _activeFilterCount {
    int count = 0;
    if (_preset != StatementPeriodPreset.all) count++;
    if (_entryFilter != StatementEntryFilter.all) count++;
    return count;
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _refresh() async {
    await widget.config.refresh(ref, _fromDate, _toDate);
  }

  Future<void> _openFilterSheet() async {
    final StatementFilterResult? result = await showStatementFilterSheet(
      context: context,
      initialPreset: _preset,
      initialEntryFilter: _entryFilter,
      partyKind: widget.config.partyKind,
    );
    if (result == null || !mounted) return;
    setState(() {
      _preset = result.preset;
      _entryFilter = result.entryFilter;
    });
  }

  void _clearFilters() {
    setState(() {
      _preset = StatementPeriodPreset.all;
      _entryFilter = StatementEntryFilter.all;
    });
  }

  Future<void> _print(T rawStatement) async {
    final Future<void> Function(BuildContext, WidgetRef, T)? printFn =
        widget.config.print;
    if (printFn == null) return;

    setState(() => _isPrinting = true);
    try {
      await printFn(context, ref, rawStatement);
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _exportCsv(StatementView view) async {
    final List<StatementEntryFilter> filters =
        availableEntryFilters(view.partyKind);
    final StatementEntryFilter activeFilter = filters.contains(_entryFilter)
        ? _entryFilter
        : StatementEntryFilter.all;
    final ComputedStatement computed = ComputedStatement.from(view);

    setState(() => _isExporting = true);
    try {
      final String csv = StatementCsvExporter.build(
        view: view,
        computed: computed,
        filter: activeFilter,
      );
      final Uint8List bytes = Uint8List.fromList(utf8.encode(csv));

      final String safeName = view.partyName
          .replaceAll(RegExp(r'[^\w\u0600-\u06FF-]'), '_');
      final String filename =
          'statement-$safeName-${DateTime.now().millisecondsSinceEpoch}.csv';

      await Printing.sharePdf(bytes: bytes, filename: filename);

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تم تجهيز ملف CSV.')),
        );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('تعذّر تصدير ملف CSV. حاول مرة أخرى.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _runExtraAction(StatementView? view) async {
    final StatementExtraAction? action = widget.config.extraAction;
    if (action == null) return;

    final bool shouldRefresh = await action.onPressed(context, ref, view);
    if (shouldRefresh && mounted) {
      await _refresh();
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final StatementPageConfig<T> config = widget.config;
    final DateTime? from = _fromDate;
    final DateTime? to = _toDate;
    final AsyncValue<T> async = config.watch(ref, from, to);
    final T? raw = async.valueOrNull;
    final StatementView? view = raw == null ? null : config.adapt(raw);

    return AppShell(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'رجوع',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(config.title),
        actions: <Widget>[
          // Filter button — always enabled (users may want to pre-set a
          // filter while data is still loading).
          _buildFilterButton(),
          if (config.extraAction != null)
            IconButton(
              tooltip: config.extraAction!.tooltip,
              icon: Icon(config.extraAction!.icon),
              onPressed: view == null ? null : () => _runExtraAction(view),
            ),
          if (config.enableCsvExport) _buildCsvButton(view),
          if (config.print != null)
            IconButton(
              tooltip: 'طباعة',
              icon: const Icon(Icons.print_outlined),
              onPressed: (_isPrinting || raw == null)
                  ? null
                  : () => _print(raw),
            ),
        ],
      ),
      body: async.when(
        loading: () => const AppLoader(),
        error: (Object error, StackTrace _) => AppErrorView(
          title: 'تعذّر تحميل كشف الحساب',
          message: config.errorMessage(error),
          retryLabel: 'إعادة المحاولة',
          onRetry: _refresh,
        ),
        data: (T rawData) => _buildBody(config.adapt(rawData)),
      ),
    );
  }

  Widget _buildFilterButton() {
    final Widget icon = const Icon(Icons.filter_alt_outlined);
    final int count = _activeFilterCount;

    return IconButton(
      tooltip: 'تصفية',
      icon: count > 0
          ? Badge.count(count: count, child: icon)
          : icon,
      onPressed: _openFilterSheet,
    );
  }

  Widget _buildCsvButton(StatementView? view) {
    if (view == null) {
      return const IconButton(
        tooltip: 'تصدير CSV',
        icon: Icon(Icons.file_download_outlined),
        onPressed: null,
      );
    }
    return IconButton(
      tooltip: 'تصدير CSV',
      icon: const Icon(Icons.file_download_outlined),
      onPressed:
          (_isExporting || _isPrinting) ? null : () => _exportCsv(view),
    );
  }

  // ---------------------------------------------------------------------------
  // Body
  // ---------------------------------------------------------------------------

  Widget _buildBody(StatementView view) {
    final ComputedStatement computed = ComputedStatement.from(view);
    final List<StatementEntryFilter> filters =
        availableEntryFilters(view.partyKind);
    final StatementEntryFilter activeFilter = filters.contains(_entryFilter)
        ? _entryFilter
        : StatementEntryFilter.all;

    final double? storedBalance = view.storedBalance;
    final bool showReconciliationBanner =
        storedBalance != null && view.hasReconciliationMismatch;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: StatementInfoCard(
            view: view,
            avatarIcon: widget.config.avatarIcon,
            computedClosingBalance: computed.closingBalance,
          ),
        ),
        StatementSummaryBar(
          openingBalance: view.openingBalance,
          totalDebit: view.totalDebit,
          totalCredit: view.totalCredit,
          closingBalance: computed.closingBalance,
        ),
        if (showReconciliationBanner)
          StatementReconciliationBanner(
            storedBalance: storedBalance,
            computedBalance: computed.closingBalance,
            onRefresh: _refresh,
          ),
        StatementActiveFilterBar(
          preset: _preset,
          entryFilter: activeFilter,
          onClear: _clearFilters,
        ),
        if (view.hasEntries) const StatementTableHeader(),
        Expanded(
          child: !view.hasEntries
              ? StatementEmptyView(
                  onRefresh: _refresh,
                  partyKind: view.partyKind,
                )
              : _buildEntriesList(
                  computed: computed,
                  filter: activeFilter,
                  view: view,
                ),
        ),
      ],
    );
  }

  Widget _buildEntriesList({
    required ComputedStatement computed,
    required StatementEntryFilter filter,
    required StatementView view,
  }) {
    final List<AugmentedEntry> display = computed.displayFiltered(filter);

    if (display.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 16),
          children: <Widget>[
            const SizedBox(height: 24),
            _FilterEmptyHint(visibleCount: display.length),
            StatementClosingBalanceCard(
              view: view,
              closingBalance: computed.closingBalance,
              entryCount: view.entryCount,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: display.length + 1,
        itemBuilder: (BuildContext context, int index) {
          if (index == display.length) {
            return StatementClosingBalanceCard(
              view: view,
              closingBalance: computed.closingBalance,
              entryCount: display.length,
            );
          }
          return StatementEntryRow(
            aug: display[index],
            isEven: index % 2 == 0,
          );
        },
      ),
    );
  }
}

// ============================================================================
// Filter-empty hint
// ============================================================================

class _FilterEmptyHint extends StatelessWidget {
  const _FilterEmptyHint({required this.visibleCount});

  final int visibleCount;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.filter_alt_off_outlined,
                color: scheme.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  visibleCount == 0
                      ? 'لا توجد حركات تطابق الفلتر المحدد.'
                      : 'تم عرض $visibleCount حركة فقط.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

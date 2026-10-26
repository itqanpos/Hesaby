// lib/shared/widgets/statements/account_statement_page.dart
//
// Generic account statement page — customer, supplier, and any future
// party (employee, cashbox, …). It owns:
//
// * page state (`_preset`, `_customRange`, `_entryFilter`, `_isPrinting`),
// * period + entry-type chips,
// * sticky table header,
// * loading / error / empty states,
// * pull-to-refresh,
// * the AppBar (back / extra action / print).
//
// Everything party-specific is injected via [StatementPageConfig]:
// data binding (watch / refresh), flattening (adapt), AppBar extra
// action, print handler, error messages.
//
// Layout (top → bottom, fixed above the scrolling list):
//
//   InfoCard
//   SummaryBar          ← 4 cells: opening / debit / credit / closing
//   PeriodChips
//   EntryFilterChips    ← hidden when only one filter is available
//   TableHeader         ← sticky; hidden when statement is empty
//   Expanded(EntriesList)
//
// This mirrors the v14 layout (info + chips were fixed above the list),
// and adds the summary bar + entry-type filter + sticky header.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import 'models/statement_filters.dart';
import 'models/statement_models.dart';
import 'widgets/statement_closing_balance_card.dart';
import 'widgets/statement_empty_view.dart';
import 'widgets/statement_entry_filter_chips.dart';
import 'widgets/statement_entry_row.dart';
import 'widgets/statement_info_card.dart';
import 'widgets/statement_period_chips.dart';
import 'widgets/statement_summary_bar.dart';
import 'widgets/statement_table_header.dart';

// ============================================================================
// Configuration
// ============================================================================

/// Extra AppBar action injected by the caller (e.g. "تعديل الرصيد" for a
/// customer, "تسجيل دفعة" for a supplier).
///
/// The callback returns `true` when the page should refresh after it
/// completes (e.g. a dialog saved something). The page then calls its own
/// `refresh` with the current period.
@immutable
class StatementExtraAction {
  const StatementExtraAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;

  /// [view] is `null` while the statement is loading or in error. The
  /// action is disabled in that case (the page prevents the callback from
  /// firing), so implementations can assume `view != null`.
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
  });

  /// AppBar title (e.g. "كشف حساب", "كشف حساب مورد").
  final String title;

  /// Avatar icon in the info card.
  final IconData avatarIcon;

  /// Drives wording, closing-balance label, and available filters.
  final StatementPartyKind partyKind;

  /// Watch the raw statement for the given period. Called from `build`.
  final AsyncValue<T> Function(
    WidgetRef ref,
    DateTime? from,
    DateTime? to,
  ) watch;

  /// Flatten the raw statement into the shared [StatementView].
  final StatementView Function(T raw) adapt;

  /// Force-refresh the raw statement for the given period. Must
  /// invalidate the underlying provider **and** await the new future, so
  /// that `RefreshIndicator` stays visible until data arrives.
  final Future<void> Function(
    WidgetRef ref,
    DateTime? from,
    DateTime? to,
  ) refresh;

  /// Map any error from [watch] to an Arabic message.
  final String Function(Object error) errorMessage;

  /// If non-null, a print button is shown in the AppBar. The callback
  /// receives the **raw** statement (needed by the party-specific PDF
  /// builder).
  final Future<void> Function(
    BuildContext context,
    WidgetRef ref,
    T rawStatement,
  )? print;

  /// If non-null, an extra icon button is shown before the print button.
  final StatementExtraAction? extraAction;
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
  (DateTime, DateTime)? _customRange;
  StatementEntryFilter _entryFilter = StatementEntryFilter.all;
  bool _isPrinting = false;

  // ---------------------------------------------------------------------------
  // Derived period bounds
  // ---------------------------------------------------------------------------

  DateTime? get _fromDate =>
      _preset.computeFrom(now: DateTime.now(), customRange: _customRange);

  DateTime? get _toDate =>
      _preset.computeTo(now: DateTime.now(), customRange: _customRange);

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _refresh() async {
    await widget.config.refresh(ref, _fromDate, _toDate);
  }

  Future<void> _selectPreset(StatementPeriodPreset preset) async {
    if (preset == StatementPeriodPreset.custom) {
      final DateTime now = DateTime.now();
      final (DateTime, DateTime)? current = _customRange;
      final DateTimeRange? picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: now,
        initialDateRange: current == null
            ? null
            : DateTimeRange(start: current.$1, end: current.$2),
        helpText: 'اختر الفترة',
        saveText: 'تطبيق',
      );
      if (picked == null || !mounted) return;
      setState(() {
        _preset = StatementPeriodPreset.custom;
        _customRange = (picked.start, picked.end);
      });
      return;
    }
    setState(() => _preset = preset);
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

  Future<void> _runExtraAction(StatementView? view) async {
    final StatementExtraAction? action = widget.config.extraAction;
    if (action == null) return;

    final bool shouldRefresh =
        await action.onPressed(context, ref, view);
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

    // Computed once per build; cheap (pure object construction).
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
          if (config.extraAction != null)
            IconButton(
              tooltip: config.extraAction!.tooltip,
              icon: Icon(config.extraAction!.icon),
              onPressed:
                  view == null ? null : () => _runExtraAction(view),
            ),
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
        data: (T rawData) {
          // `adapt` is cheap; recompute here to keep the body independent
          // of the `view` computed above (avoids a `!` on a nullable).
          return _buildBody(config.adapt(rawData));
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Body
  // ---------------------------------------------------------------------------

  Widget _buildBody(StatementView view) {
    final ComputedStatement computed = ComputedStatement.from(view);
    final List<StatementEntryFilter> filters =
        availableEntryFilters(view.partyKind);
    final StatementEntryFilter activeFilter =
        filters.contains(_entryFilter) ? _entryFilter : StatementEntryFilter.all;

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
        StatementPeriodChips(
          preset: _preset,
          customRange: _customRange,
          onSelect: _selectPreset,
        ),
        if (filters.length > 1)
          StatementEntryFilterChips(
            filters: filters,
            selected: activeFilter,
            onSelect: (StatementEntryFilter f) =>
                setState(() => _entryFilter = f),
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
    final List<AugmentedEntry> display =
        computed.displayFiltered(filter);

    // Filter hides everything: show a hint above the closing card so the
    // user knows the period is not empty — only the filter is.
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

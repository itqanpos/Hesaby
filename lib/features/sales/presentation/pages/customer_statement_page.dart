// lib/features/sales/presentation/pages/customer_statement_page.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart' show Printing;

import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/logger.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../pos/data/services/direct_print_service.dart';
import '../../../settings/data/services/company_logo_loader.dart';
import '../../../settings/domain/entities/company_settings.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../data/services/pdf_statement_builder.dart';
import '../../domain/entities/customer_statement.dart';
import '../../domain/entities/sale_entities.dart';
import '../../domain/repositories/sales_repository.dart';
import '../dialogs/customer_adjustment_dialog.dart';
import '../providers/sales_providers.dart';

enum _PeriodPreset { all, thisMonth, last30Days, thisYear, custom }

/// Full account statement page for a single customer.
class CustomerStatementPage extends ConsumerStatefulWidget {
  const CustomerStatementPage({
    super.key,
    required this.customer,
  });

  final Customer customer;

  @override
  ConsumerState<CustomerStatementPage> createState() =>
      _CustomerStatementPageState();
}

class _CustomerStatementPageState
    extends ConsumerState<CustomerStatementPage> {
  _PeriodPreset _preset = _PeriodPreset.all;
  DateTimeRange? _customRange;
  bool _isPrinting = false;

  DateTime? get _fromDate {
    final DateTime now = DateTime.now();
    switch (_preset) {
      case _PeriodPreset.all:
        return null;
      case _PeriodPreset.thisMonth:
        return DateTime(now.year, now.month, 1);
      case _PeriodPreset.last30Days:
        return DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 30));
      case _PeriodPreset.thisYear:
        return DateTime(now.year, 1, 1);
      case _PeriodPreset.custom:
        return _customRange?.start;
    }
  }

  DateTime? get _toDate {
    final DateTime now = DateTime.now();
    switch (_preset) {
      case _PeriodPreset.all:
        return null;
      case _PeriodPreset.thisMonth:
      case _PeriodPreset.last30Days:
      case _PeriodPreset.thisYear:
        return now;
      case _PeriodPreset.custom:
        final DateTime? end = _customRange?.end;
        if (end == null) return null;
        return DateTime(end.year, end.month, end.day, 23, 59, 59);
    }
  }

  CustomerStatementArgs get _args => CustomerStatementArgs(
        customerId: widget.customer.id,
        fromDate: _fromDate,
        toDate: _toDate,
      );

  Future<void> _refresh() async {
    ref.invalidate(customerStatementProvider(_args));
    await ref.read(customerStatementProvider(_args).future);
  }

  Future<void> _selectPreset(_PeriodPreset preset) async {
    if (preset == _PeriodPreset.custom) {
      final DateTime now = DateTime.now();
      final DateTimeRange? picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: now,
        initialDateRange: _customRange,
        helpText: 'اختر الفترة',
        saveText: 'تطبيق',
      );
      if (picked == null || !mounted) return;
      setState(() {
        _preset = _PeriodPreset.custom;
        _customRange = picked;
      });
      return;
    }
    setState(() => _preset = preset);
  }

  Future<void> _openAdjustment() async {
    final CustomerStatement? statement =
        ref.read(customerStatementProvider(_args)).valueOrNull;
    final double balance =
        statement?.customer.balance ?? widget.customer.balance;

    final Customer? updated = await showCustomerAdjustmentDialog(
      context: context,
      customerId: widget.customer.id,
      customerName: widget.customer.name,
      currentBalance: balance,
    );

    if (updated == null || !mounted) return;

    await _refresh();

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('تم تسجيل التعديل بنجاح.')),
      );
  }

  PrintStyleSettings _readA4Style() {
    final CompanySettings? s =
        ref.read(companySettingsProvider).valueOrNull;
    if (s == null) return const PrintStyleSettings.defaults();
    return PrintStyleSettings(
      fontScale: s.printFontScaleA4,
      fontWeight: s.printFontWeight,
    );
  }

  Future<Uint8List?> _loadLogoBytes() async {
    final CompanySettings? s =
        ref.read(companySettingsProvider).valueOrNull;
    if (s == null || s.companyId.isEmpty) return null;
    try {
      return await const CompanyLogoLoader().load(
        companyId: s.companyId,
        logoUrl: s.logoUrl,
      );
    } on Object catch (e) {
      AppLogger.warning('Logo load failed (non-fatal): $e');
      return null;
    }
  }

  Future<void> _print() async {
    final CustomerStatement? statement =
        ref.read(customerStatementProvider(_args)).valueOrNull;
    if (statement == null || statement.isEmpty) return;

    setState(() => _isPrinting = true);

    try {
      final Uint8List? logo = await _loadLogoBytes();
      final Uint8List bytes = await PdfStatementBuilder.build(
        statement: statement,
        style: _readA4Style(),
        logoBytes: logo,
      );

      final String fileName = 'statement-${statement.customer.name}.pdf';

      final bool direct =
          ref.read(companySettingsProvider).valueOrNull?.printDirectEnabled ??
              false;

      if (direct) {
        final bool ok = await DirectPrintService.tryPdfBytes(
          bytes: bytes,
          name: fileName,
        );
        if (ok) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(content: Text('تم إرسال الكشف للطابعة.')),
            );
          return;
        }
      }

      await Printing.layoutPdf(
        name: fileName,
        onLayout: (PdfPageFormat _) async => bytes,
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('تعذّرت الطباعة. حاول مرة أخرى.'),
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _isPrinting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'رجوع',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('كشف حساب'),
        actions: <Widget>[
          IconButton(
            tooltip: 'تعديل الرصيد',
            icon: const Icon(Icons.tune),
            onPressed: _openAdjustment,
          ),
          IconButton(
            tooltip: 'طباعة',
            icon: const Icon(Icons.print_outlined),
            onPressed: _isPrinting ? null : _print,
          ),
        ],
      ),
      body: ref.watch(customerStatementProvider(_args)).when(
            loading: () => const AppLoader(),
            error: (Object error, StackTrace _) => AppErrorView(
              title: 'تعذّر تحميل كشف الحساب',
              message: _errorMessage(error),
              retryLabel: 'إعادة المحاولة',
              onRetry: _refresh,
            ),
            data: (CustomerStatement statement) => _StatementBody(
              statement: statement,
              preset: _preset,
              customRange: _customRange,
              onSelectPreset: _selectPreset,
              onRefresh: _refresh,
            ),
          ),
    );
  }
}

// ============================================================================
// Body
// ============================================================================

class _StatementBody extends StatelessWidget {
  const _StatementBody({
    required this.statement,
    required this.preset,
    required this.customRange,
    required this.onSelectPreset,
    required this.onRefresh,
  });

  final CustomerStatement statement;
  final _PeriodPreset preset;
  final DateTimeRange? customRange;
  final Future<void> Function(_PeriodPreset) onSelectPreset;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final _ComputedStatement computed = _ComputedStatement.from(statement);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _CustomerInfoCard(
          statement: statement,
          closingBalance: computed.closingBalance,
        ),
        const SizedBox(height: 8),
        _PeriodChips(
          preset: preset,
          customRange: customRange,
          onSelect: onSelectPreset,
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _EntriesList(
            statement: statement,
            computed: computed,
            onRefresh: onRefresh,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Computed statement
// ============================================================================

class _ComputedStatement {
  const _ComputedStatement({
    required this.openingBalance,
    required this.chronologicalEntries,
    required this.closingBalance,
  });

  final double openingBalance;
  final List<_AugEntry> chronologicalEntries;
  final double closingBalance;

  factory _ComputedStatement.from(CustomerStatement statement) {
    final List<_IndexedEntry> indexed = [];
    for (int i = 0; i < statement.entries.length; i++) {
      indexed.add(_IndexedEntry(statement.entries[i], i));
    }

    indexed.sort((a, b) {
      final int c = a.entry.date.compareTo(b.entry.date);
      if (c != 0) return c;
      return b.originalIndex.compareTo(a.originalIndex);
    });

    double balance = statement.openingBalance;
    final List<_AugEntry> augmented = [];
    for (final item in indexed) {
      final CustomerStatementEntry e = item.entry;
      final double previous = balance;
      
      balance = balance + e.debit - e.credit;

      augmented.add(_AugEntry(
        entry: e,
        previousBalance: previous,
        currentBalance: balance,
      ));
    }

    return _ComputedStatement(
      openingBalance: statement.openingBalance,
      chronologicalEntries: augmented,
      closingBalance: balance,
    );
  }
}

class _IndexedEntry {
  _IndexedEntry(this.entry, this.originalIndex);
  final CustomerStatementEntry entry;
  final int originalIndex;
}

class _AugEntry {
  const _AugEntry({
    required this.entry,
    required this.previousBalance,
    required this.currentBalance,
  });
  final CustomerStatementEntry entry;
  final double previousBalance;
  final double currentBalance;
}

// ============================================================================
// Info card
// ============================================================================

class _CustomerInfoCard extends StatelessWidget {
  const _CustomerInfoCard({
    required this.statement,
    required this.closingBalance,
  });

  final CustomerStatement statement;
  final double closingBalance;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Customer customer = statement.customer;

    final List<String> meta = <String>[];
    if (customer.hasCode) meta.add('كود: ${customer.code}');
    if (customer.hasPhone) meta.add(customer.phone!);

    final bool weOwe = closingBalance > 0.01;
    final bool theyOweUs = closingBalance < -0.01;
    final String balanceLabel = weOwe
        ? 'مستحق على العميل'
        : theyOweUs
            ? 'لك عند العميل'
            : 'الرصيد مسدد';
    final Color balanceColor = weOwe
        ? scheme.error
        : theyOweUs
            ? const Color(0xFF1B5E20)
            : scheme.onSurfaceVariant;

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
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: const Icon(Icons.person_outline),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        customer.name,
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (meta.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          meta.join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Text(
                  balanceLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: balanceColor,
                  ),
                ),
                const Spacer(),
                Text(
                  AppFormatters.money(closingBalance.abs()),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: balanceColor,
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
// Period chips
// ============================================================================

class _PeriodChips extends StatelessWidget {
  const _PeriodChips({
    required this.preset,
    required this.customRange,
    required this.onSelect,
  });

  final _PeriodPreset preset;
  final DateTimeRange? customRange;
  final Future<void> Function(_PeriodPreset) onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _chip(context, _PeriodPreset.all, 'الكل'),
          _chip(context, _PeriodPreset.thisMonth, 'هذا الشهر'),
          _chip(context, _PeriodPreset.last30Days, 'آخر 30 يومًا'),
          _chip(context, _PeriodPreset.thisYear, 'هذا العام'),
          _chip(context, _PeriodPreset.custom, _customLabel()),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, _PeriodPreset value, String label) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: preset == value,
        onSelected: (_) => onSelect(value),
        showCheckmark: false,
      ),
    );
  }

  String _customLabel() {
    if (preset == _PeriodPreset.custom && customRange != null) {
      return '${AppFormatters.date(customRange!.start)} → '
          '${AppFormatters.date(customRange!.end)}';
    }
    return 'نطاق مخصص';
  }
}

// ============================================================================
// Entries list
// ============================================================================

class _EntriesList extends StatelessWidget {
  const _EntriesList({
    required this.statement,
    required this.computed,
    required this.onRefresh,
  });

  final CustomerStatement statement;
  final _ComputedStatement computed;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    if (statement.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            SizedBox(
              height: 320,
              child: AppEmptyView(
                icon: Icons.receipt_long_outlined,
                title: 'لا توجد حركات',
                message: 'لم تُسجَّل أي حركة على هذا العميل في الفترة المحددة.',
              ),
            ),
          ],
        ),
      );
    }

    final List<_AugEntry> display =
        computed.chronologicalEntries.reversed.toList(growable: false);

    final bool showOpening = computed.openingBalance.abs() > 0.01;
    final int headerIndex = showOpening ? 1 : 0;
    final int firstRowIndex = headerIndex + 1;
    final int closingIndex = firstRowIndex + display.length;

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: scheme.primary,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: closingIndex + 1,
        itemBuilder: (BuildContext context, int index) {
          if (showOpening && index == 0) {
            return _OpeningBalanceTile(
              openingBalance: computed.openingBalance,
            );
          }
          if (index == headerIndex) {
            return const _TableHeaderRow();
          }
          if (index == closingIndex) {
            return _ClosingBalanceCard(
              closingBalance: computed.closingBalance,
              entryCount: display.length,
            );
          }
          final int entryIdx = index - firstRowIndex;
          return _EntryRow(aug: display[entryIdx]);
        },
      ),
    );
  }
}

// ============================================================================
// Table header row (FIXED)
// ============================================================================

class _TableHeaderRow extends StatelessWidget {
  const _TableHeaderRow();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    const TextStyle style =
        TextStyle(fontSize: 11, fontWeight: FontWeight.w800);
    final Color borderColor = scheme.outlineVariant.withValues(alpha: 0.5);

    return IntrinsicHeight(
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          border: Border(bottom: BorderSide(color: borderColor, width: 1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _HeaderCell(width: 52, text: 'التاريخ', style: style, borderColor: borderColor),
            _HeaderCell(width: 0, text: 'البيان', style: style, borderColor: borderColor, isExpanded: true),
            _HeaderCell(width: 66, text: 'الرصيد', style: style, borderColor: borderColor, alignRight: true),
            _HeaderCell(width: 66, text: 'المدفوع', style: style, borderColor: borderColor, alignRight: true),
            _HeaderCell(width: 82, text: 'الرصيد الحالي', style: style, borderColor: borderColor, alignRight: true, isLast: true),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.width,
    required this.text,
    required this.style,
    required this.borderColor,
    this.isExpanded = false,
    this.alignRight = false,
    this.isLast = false,
  });

  final double width;
  final String text;
  final TextStyle style;
  final Color borderColor;
  final bool isExpanded;
  final bool alignRight;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final Widget content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(
        text,
        style: style,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
      ),
    );

    final Widget cell = Container(
      decoration: BoxDecoration(
        border: isLast ? null : Border(left: BorderSide(color: borderColor, width: 0.5)),
      ),
      child: content,
    );

    if (isExpanded) {
      return Expanded(child: cell);
    }
    return SizedBox(width: width, child: cell);
  }
}

// ============================================================================
// Entry row (FIXED)
// ============================================================================

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.aug});

  final _AugEntry aug;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final CustomerStatementEntry entry = aug.entry;
    final Color borderColor = scheme.outlineVariant.withValues(alpha: 0.5);
    
    final double paid = entry.credit;
    final double debit = entry.debit;
    
    final double prevBal = aug.previousBalance;
    final double currBal = aug.currentBalance;

    final bool prevWeOwe = prevBal > 0.01;
    final bool prevTheyOweUs = prevBal < -0.01;
    final Color prevColor = prevWeOwe ? scheme.error : (prevTheyOweUs ? const Color(0xFF1B5E20) : scheme.onSurfaceVariant);
    final String prevText = (prevWeOwe || prevTheyOweUs) ? '${prevWeOwe ? '+' : '−'}${AppFormatters.money(prevBal.abs())}' : '0.00';

    final bool currWeOwe = currBal > 0.01;
    final bool currTheyOweUs = currBal < -0.01;
    final Color currColor = currWeOwe ? scheme.error : (currTheyOweUs ? const Color(0xFF1B5E20) : scheme.onSurfaceVariant);
    final String currText = (currWeOwe || currTheyOweUs) ? '${currWeOwe ? '+' : '−'}${AppFormatters.money(currBal.abs())}' : '0.00';

    final String baseDesc = entry.hasDescription ? entry.description! : _typeLabel(entry.type);
    final Color typeColor = debit > 0 ? scheme.error : const Color(0xFF1B5E20);

    return IntrinsicHeight(
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: borderColor, width: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _DataCell(
              width: 52,
              borderColor: borderColor,
              child: Text(
                DateFormat('dd/MM').format(entry.date.toLocal()),
                style: const TextStyle(fontSize: 11),
              ),
            ),
            _DataCell(
              width: 0,
              isExpanded: true,
              borderColor: borderColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    baseDesc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: typeColor,
                    ),
                  ),
                  if (entry.isSale && debit > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      'قيمة: ${AppFormatters.money(debit)}',
                      style: TextStyle(fontSize: 10, color: scheme.error),
                    ),
                  ],
                  if (entry.isSale && paid > 0) ...[
                    const SizedBox(height: 1),
                    Text(
                      'مدفوع: ${AppFormatters.money(paid)}',
                      style: TextStyle(fontSize: 10, color: const Color(0xFF1B5E20)),
                    ),
                  ],
                  if (entry.hasReference) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.reference!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _DataCell(
              width: 66,
              borderColor: borderColor,
              alignRight: true,
              child: Text(
                prevText,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: prevColor),
              ),
            ),
            _DataCell(
              width: 66,
              borderColor: borderColor,
              alignRight: true,
              child: Text(
                paid > 0 ? AppFormatters.money(paid) : '—',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11,
                  color: paid > 0 ? const Color(0xFF1B5E20) : scheme.onSurfaceVariant,
                  fontWeight: paid > 0 ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            _DataCell(
              width: 82,
              isLast: true,
              borderColor: borderColor,
              alignRight: true,
              child: Text(
                currText,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: currColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _typeLabel(String type) {
    switch (type) {
      case StatementEntryType.sale:
        return 'فاتورة بيع';
      case StatementEntryType.saleReversal:
        return 'إلغاء فاتورة';
      case StatementEntryType.payment:
        return 'دفعة';
      case StatementEntryType.adjustment:
        return 'تعديل رصيد';
      default:
        return 'حركة';
    }
  }
}

class _DataCell extends StatelessWidget {
  const _DataCell({
    required this.width,
    required this.child,
    required this.borderColor,
    this.isExpanded = false,
    this.isLast = false,
    this.alignRight = false,
  });

  final double width;
  final Widget child;
  final Color borderColor;
  final bool isExpanded;
  final bool isLast;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final Widget content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: child,
    );

    final Widget cell = Container(
      decoration: BoxDecoration(
        border: isLast ? null : Border(left: BorderSide(color: borderColor, width: 0.5)),
      ),
      child: content,
    );

    if (isExpanded) {
      return Expanded(child: cell);
    }
    return SizedBox(width: width, child: cell);
  }
}

// ============================================================================
// Opening balance tile
// ============================================================================

class _OpeningBalanceTile extends StatelessWidget {
  const _OpeningBalanceTile({required this.openingBalance});

  final double openingBalance;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool weOwe = openingBalance > 0.01;
    final bool theyOweUs = openingBalance < -0.01;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: scheme.surfaceContainerHigh,
      child: Row(
        children: <Widget>[
          Icon(
            Icons.play_circle_outline,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            'رصيد افتتاحي',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            theyOweUs
                ? '−${AppFormatters.money(openingBalance.abs())}'
                : AppFormatters.money(openingBalance),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: weOwe
                  ? scheme.error
                  : theyOweUs
                      ? const Color(0xFF1B5E20)
                      : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Closing balance card
// ============================================================================

class _ClosingBalanceCard extends StatelessWidget {
  const _ClosingBalanceCard({
    required this.closingBalance,
    required this.entryCount,
  });

  final double closingBalance;
  final int entryCount;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool weOwe = closingBalance > 0.01;
    final bool theyOweUs = closingBalance < -0.01;

    final Color bg = weOwe
        ? scheme.errorContainer
        : theyOweUs
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest;
    final Color fg = weOwe
        ? scheme.onErrorContainer
        : theyOweUs
            ? scheme.onPrimaryContainer
            : scheme.onSurfaceVariant;
    final IconData icon = weOwe
        ? Icons.warning_amber_outlined
        : theyOweUs
            ? Icons.account_balance_wallet_outlined
            : Icons.check_circle_outline;
    final String label = weOwe
        ? 'الرصيد النهائي — مستحق على العميل'
        : theyOweUs
            ? 'الرصيد النهائي — لك عند العميل'
            : 'الرصيد النهائي — مسدد';

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, color: fg, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                AppFormatters.money(closingBalance.abs()),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: fg,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'عدد الحركات: ${AppFormatters.integer(entryCount)}',
                style: theme.textTheme.bodySmall?.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Localization
// ============================================================================

String _errorMessage(Object error) {
  if (error is CustomerException) {
    return _failureMessage(error.type);
  }
  return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
}

String _failureMessage(CustomerFailureType type) {
  switch (type) {
    case CustomerFailureType.network:
      return 'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.';
    case CustomerFailureType.unauthorized:
      return 'انتهت صلاحية الجلسة. يرجى تسجيل الدخول مجددًا.';
    case CustomerFailureType.notFound:
      return 'العميل المطلوب غير موجود أو تم حذفه.';
    case CustomerFailureType.nameConflict:
      return 'يوجد عميل آخر بنفس الاسم.';
    case CustomerFailureType.codeConflict:
      return 'يوجد عميل آخر بنفس الكود.';
    case CustomerFailureType.phoneConflict:
      return 'يوجد عميل آخر بنفس رقم الهاتف.';
    case CustomerFailureType.inUse:
      return 'العميل مرتبط بفواتير.';
    case CustomerFailureType.invalidAmount:
      return 'المبلغ غير صالح.';
    case CustomerFailureType.insufficientBalance:
      return 'الرصيد غير كافٍ لإتمام العملية.';
    case CustomerFailureType.invalidResponse:
      return 'تعذّر قراءة البيانات. يرجى المحاولة مجددًا.';
    case CustomerFailureType.unknown:
      return 'تعذّر إتمام العملية. يرجى المحاولة مرة أخرى.';
  }
}

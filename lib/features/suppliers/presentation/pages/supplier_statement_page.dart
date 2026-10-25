// lib/features/suppliers/presentation/pages/supplier_statement_page.dart

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
import '../../../purchases/presentation/dialogs/supplier_payment_dialog.dart';
import '../../../settings/data/services/company_logo_loader.dart';
import '../../../settings/domain/entities/company_settings.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../data/services/pdf_supplier_statement_builder.dart';
import '../../domain/entities/supplier.dart';
import '../../domain/entities/supplier_statement.dart';
import '../../domain/repositories/supplier_statement_repository.dart';
import '../providers/supplier_statement_providers.dart';

enum _PeriodPreset { all, thisMonth, last30Days, thisYear, custom }

class SupplierStatementPage extends ConsumerStatefulWidget {
  const SupplierStatementPage({super.key, required this.supplier});

  final Supplier supplier;

  @override
  ConsumerState<SupplierStatementPage> createState() =>
      _SupplierStatementPageState();
}

class _SupplierStatementPageState
    extends ConsumerState<SupplierStatementPage> {
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

  SupplierStatementArgs get _args => SupplierStatementArgs(
        supplierId: widget.supplier.id,
        fromDate: _fromDate,
        toDate: _toDate,
      );

  Future<void> _refresh() async {
    ref.invalidate(supplierStatementProvider(_args));
    await ref.read(supplierStatementProvider(_args).future);
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

  Future<void> _recordPayment() async {
    final bool? saved = await showSupplierPaymentDialog(
      context: context,
      supplierId: widget.supplier.id,
      supplierName: widget.supplier.name,
    );
    if (saved == true && mounted) {
      await _refresh();
    }
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
    final SupplierStatement? statement =
        ref.read(supplierStatementProvider(_args)).valueOrNull;
    if (statement == null || statement.isEmpty) return;

    setState(() => _isPrinting = true);
    try {
      final Uint8List? logo = await _loadLogoBytes();
      final Uint8List bytes = await PdfSupplierStatementBuilder.build(
        statement: statement,
        style: _readA4Style(),
        logoBytes: logo,
      );

      final String fileName =
          'supplier-statement-${statement.supplier.name}.pdf';

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
          const SnackBar(content: Text('تعذّرت الطباعة. حاول مرة أخرى.')),
        );
    } finally {
      if (mounted) setState(() => _isPrinting = false);
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
        title: const Text('كشف حساب مورد'),
        actions: <Widget>[
          IconButton(
            tooltip: 'تسجيل دفعة',
            icon: const Icon(Icons.payments_outlined),
            onPressed: _recordPayment,
          ),
          IconButton(
            tooltip: 'طباعة',
            icon: const Icon(Icons.print_outlined),
            onPressed: _isPrinting ? null : _print,
          ),
        ],
      ),
      body: ref.watch(supplierStatementProvider(_args)).when(
            loading: () => const AppLoader(),
            error: (Object error, StackTrace _) => AppErrorView(
              title: 'تعذّر تحميل كشف الحساب',
              message: _errorMessage(error),
              retryLabel: 'إعادة المحاولة',
              onRetry: _refresh,
            ),
            data: (SupplierStatement statement) => _StatementBody(
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

  final SupplierStatement statement;
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
        _SupplierInfoCard(
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
// Computed statement — حساب دقيق ومرتب
// ============================================================================

class _ComputedStatement {
  const _ComputedStatement({
    required this.openingBalance,
    required this.chronologicalEntries,
    required this.closingBalance,
  });

  final double openingBalance;
  final List<_AugEntry> chronologicalEntries; // الأقدم أولاً
  final double closingBalance;

  factory _ComputedStatement.from(SupplierStatement statement) {
    // 1. نضع فهرساً للحركات الأصلية لضمان استقرار الترتيب
    final List<_IndexedEntry> indexed = [];
    for (int i = 0; i < statement.entries.length; i++) {
      indexed.add(_IndexedEntry(statement.entries[i], i));
    }

    // 2. الترتيب من الأقدم للأحدث
    indexed.sort((a, b) {
      final int c = a.entry.date.compareTo(b.entry.date);
      if (c != 0) return c;

      // الفواتير قبل الدفعات في نفس اللحظة
      if (a.entry.isPurchase && !b.entry.isPurchase) return -1;
      if (!a.entry.isPurchase && b.entry.isPurchase) return 1;

      // في نفس اليوم، نعكس الترتيب الأصلي
      // (حتى تظهر الدفعة المضافة حديثاً في الأعلى بعد عكس القائمة)
      return b.originalIndex.compareTo(a.originalIndex);
    });

    // 3. حساب الرصيد التراكمي
    double balance = statement.openingBalance;
    final List<_AugEntry> augmented = [];
    for (final item in indexed) {
      final SupplierStatementEntry e = item.entry;
      final double amount = _extractAmount(e);
      final double previous = balance;

      if (e.isPurchase) {
        balance += amount; // فاتورة تزيد الرصيد
      } else {
        balance -= amount; // دفعة تقلل الرصيد
      }

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

  static double _extractAmount(SupplierStatementEntry e) {
    final double d = e.debit.abs();
    final double c = e.credit.abs();
    if (d > 0) return d;
    if (c > 0) return c;
    return 0;
  }
}

class _IndexedEntry {
  _IndexedEntry(this.entry, this.originalIndex);
  final SupplierStatementEntry entry;
  final int originalIndex;
}

class _AugEntry {
  const _AugEntry({
    required this.entry,
    required this.previousBalance,
    required this.currentBalance,
  });
  final SupplierStatementEntry entry;
  final double previousBalance;
  final double currentBalance;
}

// ============================================================================
// Info card
// ============================================================================

class _SupplierInfoCard extends StatelessWidget {
  const _SupplierInfoCard({
    required this.statement,
    required this.closingBalance,
  });

  final SupplierStatement statement;
  final double closingBalance;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Supplier supplier = statement.supplier;

    final List<String> meta = <String>[];
    if (supplier.hasCode) meta.add('كود: ${supplier.code}');
    if (supplier.hasPhone) meta.add(supplier.phone!);

    final bool weOwe = closingBalance > 0.01;
    final bool theyOweUs = closingBalance < -0.01;
    final String balanceLabel = weOwe
        ? 'مستحق للمورد'
        : theyOweUs
            ? 'لك عند المورد'
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
                  child: const Icon(Icons.local_shipping_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        supplier.name,
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

  final SupplierStatement statement;
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
                message:
                    'لم تُسجَّل أي حركة على هذا المورد في الفترة المحددة.',
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
// Table header row
// ============================================================================

class _TableHeaderRow extends StatelessWidget {
  const _TableHeaderRow();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    const TextStyle style =
        TextStyle(fontSize: 11, fontWeight: FontWeight.w800);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: scheme.surfaceContainerHighest,
      child: Row(
        children: const <Widget>[
          SizedBox(width: 54, child: Text('التاريخ', style: style)),
          Expanded(child: Text('البيان', style: style)),
          SizedBox(
            width: 68,
            child: Text('الرصيد', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 68,
            child: Text('المدفوع', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 76,
            child: Text('الرصيد الحالي', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Entry row
// ============================================================================

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.aug});

  final _AugEntry aug;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final SupplierStatementEntry entry = aug.entry;
    final bool isPurchase = entry.isPurchase;
    final double amount = _ComputedStatement._extractAmount(entry);
    final double paid = isPurchase ? 0.0 : amount;
    
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

    final String baseDesc = entry.hasDescription ? entry.description! : (isPurchase ? 'فاتورة مشتريات' : 'دفعة');
    final String amountLabel = isPurchase ? ' (+${AppFormatters.money(amount)})' : '';
    final String description = '$baseDesc$amountLabel';
    final Color typeColor = isPurchase ? scheme.error : const Color(0xFF1B5E20);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 54,
            child: Text(
              DateFormat('dd/MM').format(entry.date.toLocal()),
              style: const TextStyle(fontSize: 11),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: typeColor,
                  ),
                ),
                if (entry.hasReference)
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
            ),
          ),
          // Previous Balance (الرصيد)
          SizedBox(
            width: 68,
            child: Text(
              prevText,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: prevColor,
              ),
            ),
          ),
          // Paid (المدفوع)
          SizedBox(
            width: 68,
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
          // Current Balance (الرصيد الحالي)
          SizedBox(
            width: 76,
            child: Text(
              currText,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: currColor,
              ),
            ),
          ),
        ],
      ),
    );
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
        ? 'الرصيد النهائي — مستحق للمورد'
        : theyOweUs
            ? 'الرصيد النهائي — لك عند المورد'
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
  if (error is SupplierStatementException) {
    return _failureMessage(error.type);
  }
  return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
}

String _failureMessage(SupplierStatementFailureType type) {
  switch (type) {
    case SupplierStatementFailureType.network:
      return 'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.';
    case SupplierStatementFailureType.unauthorized:
      return 'انتهت صلاحية الجلسة. يرجى تسجيل الدخول مجددًا.';
    case SupplierStatementFailureType.notFound:
      return 'المورد المطلوب غير موجود.';
    case SupplierStatementFailureType.invalidResponse:
      return 'تعذّر قراءة البيانات. يرجى المحاولة مجددًا.';
    case SupplierStatementFailureType.unknown:
      return 'تعذّر إتمام العملية. يرجى المحاولة مرة أخرى.';
  }
}

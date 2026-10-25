// lib/features/suppliers/presentation/pages/supplier_statement_page.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Full account statement page for a single supplier.
class SupplierStatementPage extends ConsumerStatefulWidget {
  const SupplierStatementPage({
    super.key,
    required this.supplier,
  });

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

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

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
      ref.invalidate(supplierStatementProvider(_args));
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
      final Uint8List bytes =
          await PdfSupplierStatementBuilder.build(
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

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

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
              onRetry: () =>
                  ref.invalidate(supplierStatementProvider(_args)),
            ),
            data: (SupplierStatement statement) => _StatementBody(
              statement: statement,
              preset: _preset,
              customRange: _customRange,
              onSelectPreset: _selectPreset,
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
  });

  final SupplierStatement statement;
  final _PeriodPreset preset;
  final DateTimeRange? customRange;
  final Future<void> Function(_PeriodPreset) onSelectPreset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SupplierInfoCard(statement: statement),
        const SizedBox(height: 8),
        _PeriodChips(
          preset: preset,
          customRange: customRange,
          onSelect: onSelectPreset,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _EntriesList(statement: statement),
        ),
      ],
    );
  }
}

// ============================================================================
// Info card
// ============================================================================

class _SupplierInfoCard extends StatelessWidget {
  const _SupplierInfoCard({required this.statement});

  final SupplierStatement statement;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Supplier supplier = statement.supplier;

    final List<String> meta = <String>[];
    if (supplier.hasCode) meta.add('كود: ${supplier.code}');
    if (supplier.hasPhone) meta.add(supplier.phone!);

    final double balance = statement.closingBalance;
    final bool isOwed = balance > 0;

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
                  isOwed ? 'مستحق للمورد' : 'الرصيد',
                  style: theme.textTheme.bodyMedium,
                ),
                const Spacer(),
                Text(
                  AppFormatters.money(balance.abs()),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: isOwed ? scheme.error : scheme.primary,
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
// Entries list (Table View)
// ============================================================================

class _EntriesList extends StatelessWidget {
  const _EntriesList({required this.statement});

  final SupplierStatement statement;

  @override
  Widget build(BuildContext context) {
    if (statement.isEmpty) {
      return AppEmptyView(
        icon: Icons.receipt_long_outlined,
        title: 'لا توجد حركات',
        message: 'لم تُسجَّل أي حركة على هذا المورد في الفترة المحددة.',
        action: _OpeningBalanceTile(
          openingBalance: statement.openingBalance,
        ),
      );
    }

    // 1. Sort oldest first to calculate cumulative paid accurately
    final List<SupplierStatementEntry> chronological = List<SupplierStatementEntry>.of(statement.entries)
      ..sort((a, b) => a.date.compareTo(b.date));

    // 2. Calculate cumulative paid
    double runningPaid = 0;
    final List<_EntryWithCumulative> augmented = [];
    for (final entry in chronological) {
      runningPaid += entry.credit;
      augmented.add(_EntryWithCumulative(entry, runningPaid));
    }

    // 3. Reverse for display (newest first)
    final displayEntries = augmented.reversed.toList();

    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return SingleChildScrollView(
      child: Column(
        children: [
          _OpeningBalanceTile(openingBalance: statement.openingBalance),
          const SizedBox(height: 8),
          
          // Table
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(scheme.surfaceContainerHighest),
              dataRowMinHeight: 48,
              dataRowMaxHeight: 64,
              columnSpacing: 16,
              columns: const [
                DataColumn(label: Text('التاريخ', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('البيان', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('مدين (+)', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                DataColumn(label: Text('دائن (−)', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                DataColumn(label: Text('الدفعة الحالية', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                DataColumn(label: Text('إجمالي المدفوع', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                DataColumn(label: Text('الرصيد', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
              ],
              rows: displayEntries.map((augmentedEntry) {
                final entry = augmentedEntry.entry;
                final isPurchase = entry.isPurchase;
                final description = entry.hasDescription ? entry.description! : (isPurchase ? 'فاتورة مشتريات' : 'دفعة');
                
                return DataRow(
                  cells: [
                    DataCell(Text(AppFormatters.date(entry.date), style: const TextStyle(fontSize: 12))),
                    DataCell(
                      SizedBox(
                        width: 150, // Fixed width for description to avoid layout jump
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(description, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            if (entry.hasReference)
                              Text(entry.reference!, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ),
                    DataCell(Text(
                      entry.isDebit ? AppFormatters.money(entry.debit) : '-',
                      style: TextStyle(fontSize: 12, color: entry.isDebit ? scheme.error : null),
                    )),
                    DataCell(Text(
                      entry.isCredit ? AppFormatters.money(entry.credit) : '-',
                      style: TextStyle(fontSize: 12, color: entry.isCredit ? scheme.primary : null),
                    )),
                    DataCell(Text(
                      entry.isCredit ? AppFormatters.money(entry.credit) : '-',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: entry.isCredit ? scheme.primary : null),
                    )),
                    DataCell(Text(
                      augmentedEntry.cumulativePaid > 0 ? AppFormatters.money(augmentedEntry.cumulativePaid) : '-',
                      style: const TextStyle(fontSize: 12),
                    )),
                    DataCell(Text(
                      AppFormatters.money(entry.balanceAfter ?? 0),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: (entry.balanceAfter ?? 0) > 0 ? scheme.error : scheme.primary),
                    )),
                  ],
                );
              }).toList(),
            ),
          ),
          
          const SizedBox(height: 8),
          _ClosingBalanceCard(statement: statement),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _EntryWithCumulative {
  const _EntryWithCumulative(this.entry, this.cumulativePaid);
  final SupplierStatementEntry entry;
  final double cumulativePaid;
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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.play_circle_outline,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              'رصيد افتتاحي',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              AppFormatters.money(openingBalance),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: openingBalance > 0
                    ? scheme.error
                    : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Closing balance card
// ============================================================================

class _ClosingBalanceCard extends StatelessWidget {
  const _ClosingBalanceCard({required this.statement});

  final SupplierStatement statement;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool owed = statement.isOwedToSupplier;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: owed ? scheme.errorContainer : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  owed
                      ? Icons.warning_amber_outlined
                      : Icons.check_circle_outline,
                  color: owed
                      ? scheme.onErrorContainer
                      : scheme.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  owed
                      ? 'الرصيد النهائي (مستحق للمورد)'
                      : 'الرصيد النهائي',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: owed
                        ? scheme.onErrorContainer
                        : scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              AppFormatters.money(statement.closingBalance.abs()),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: owed
                    ? scheme.onErrorContainer
                    : scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'عدد الحركات: '
              '${AppFormatters.integer(statement.entryCount)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: owed
                    ? scheme.onErrorContainer
                    : scheme.onPrimaryContainer,
              ),
            ),
          ],
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

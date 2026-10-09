// lib/features/suppliers/presentation/pages/supplier_statement_page.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart' show Printing;

import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../purchases/presentation/dialogs/supplier_payment_dialog.dart';
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

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );
  static final DateFormat _dateShort = DateFormat('yyyy-MM-dd');

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

  Future<void> _print() async {
    final SupplierStatement? statement =
        ref.read(supplierStatementProvider(_args)).valueOrNull;
    if (statement == null || statement.isEmpty) {
      return;
    }

    setState(() => _isPrinting = true);
    try {
      final Uint8List bytes =
          await PdfSupplierStatementBuilder.build(statement: statement);

      await Printing.layoutPdf(
        name: 'supplier-statement-${statement.supplier.name}.pdf',
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
              money: _money,
              dateShort: _dateShort,
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
    required this.money,
    required this.dateShort,
  });

  final SupplierStatement statement;
  final _PeriodPreset preset;
  final DateTimeRange? customRange;
  final Future<void> Function(_PeriodPreset) onSelectPreset;
  final NumberFormat money;
  final DateFormat dateShort;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SupplierInfoCard(statement: statement, money: money),
        const SizedBox(height: 8),
        _PeriodChips(
          preset: preset,
          customRange: customRange,
          onSelect: onSelectPreset,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _EntriesList(
            statement: statement,
            money: money,
            dateShort: dateShort,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Info card
// ============================================================================

class _SupplierInfoCard extends StatelessWidget {
  const _SupplierInfoCard({
    required this.statement,
    required this.money,
  });

  final SupplierStatement statement;
  final NumberFormat money;

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
                  money.format(balance.abs()),
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
      final DateFormat fmt = DateFormat('yy/MM/dd');
      return '${fmt.format(customRange!.start)} → '
          '${fmt.format(customRange!.end)}';
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
    required this.money,
    required this.dateShort,
  });

  final SupplierStatement statement;
  final NumberFormat money;
  final DateFormat dateShort;

  @override
  Widget build(BuildContext context) {
    if (statement.isEmpty) {
      return AppEmptyView(
        icon: Icons.receipt_long_outlined,
        title: 'لا توجد حركات',
        message: 'لم تُسجَّل أي حركة على هذا المورد في الفترة المحددة.',
        action: _OpeningBalanceTile(
          openingBalance: statement.openingBalance,
          money: money,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: statement.entries.length + 2,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return _OpeningBalanceTile(
            openingBalance: statement.openingBalance,
            money: money,
          );
        }
        if (index == statement.entries.length + 1) {
          return _ClosingBalanceCard(
            statement: statement,
            money: money,
          );
        }
        return _EntryCard(
          entry: statement.entries[index - 1],
          money: money,
          dateShort: dateShort,
        );
      },
    );
  }
}

// ============================================================================
// Opening balance tile
// ============================================================================

class _OpeningBalanceTile extends StatelessWidget {
  const _OpeningBalanceTile({
    required this.openingBalance,
    required this.money,
  });

  final double openingBalance;
  final NumberFormat money;

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
              money.format(openingBalance),
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
// Entry card
// ============================================================================

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.money,
    required this.dateShort,
  });

  final SupplierStatementEntry entry;
  final NumberFormat money;
  final DateFormat dateShort;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final Color accent = entry.isDebit ? scheme.error : scheme.primary;
    final IconData icon = entry.isPurchase
        ? Icons.receipt_long_outlined
        : Icons.payments_outlined;
    final String description = entry.hasDescription
        ? entry.description!
        : (entry.isPurchase ? 'فاتورة مشتريات' : 'دفعة');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        description,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _metaLine(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '${entry.isDebit ? '+' : '−'}${money.format(entry.isDebit ? entry.debit : entry.credit)}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'الرصيد: ${money.format(entry.balanceAfter ?? 0)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (entry.hasNotes) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                entry.notes!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _metaLine() {
    final String date = dateShort.format(entry.date.toLocal());
    if (entry.hasReference) {
      return '$date · ${entry.reference}';
    }
    return date;
  }
}

// ============================================================================
// Closing balance card
// ============================================================================

class _ClosingBalanceCard extends StatelessWidget {
  const _ClosingBalanceCard({
    required this.statement,
    required this.money,
  });

  final SupplierStatement statement;
  final NumberFormat money;

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
                  owed ? 'الرصيد النهائي (مستحق للمورد)' : 'الرصيد النهائي',
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
              money.format(statement.closingBalance.abs()),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: owed
                    ? scheme.onErrorContainer
                    : scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'عدد الحركات: ${statement.entryCount}',
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

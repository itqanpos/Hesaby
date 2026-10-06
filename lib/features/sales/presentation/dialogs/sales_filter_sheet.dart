// lib/features/sales/presentation/dialogs/sales_filter_sheet.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/app_button.dart';
import '../../domain/entities/sale_entities.dart';

/// Date presets exposed in the filter sheet.
enum SalesDateFilter {
  all,
  today,
  thisWeek,
  thisMonth,
  thisYear,
  custom,
}

/// Value object holding the current filter selection for the sales page.
@immutable
class SalesFilter extends Equatable {
  const SalesFilter({
    this.dateFilter = SalesDateFilter.all,
    this.customRange,
    this.status,
    this.payment,
  });

  final SalesDateFilter dateFilter;
  final DateTimeRange? customRange;
  final String? status;
  final String? payment;

  /// Number of non-default filters currently active.
  int get activeCount {
    int c = 0;
    if (dateFilter != SalesDateFilter.all) c++;
    if (status != null) c++;
    if (payment != null) c++;
    return c;
  }

  bool get isEmpty => activeCount == 0;
  bool get isNotEmpty => activeCount > 0;

  DateTime? get fromDate {
    final DateTime now = DateTime.now();
    switch (dateFilter) {
      case SalesDateFilter.all:
        return null;
      case SalesDateFilter.today:
        return DateTime(now.year, now.month, now.day);
      case SalesDateFilter.thisWeek:
        return DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
      case SalesDateFilter.thisMonth:
        return DateTime(now.year, now.month, 1);
      case SalesDateFilter.thisYear:
        return DateTime(now.year, 1, 1);
      case SalesDateFilter.custom:
        final DateTime? start = customRange?.start;
        if (start == null) return null;
        return DateTime(start.year, start.month, start.day);
    }
  }

  DateTime? get toDate {
    final DateTime now = DateTime.now();
    switch (dateFilter) {
      case SalesDateFilter.all:
        return null;
      case SalesDateFilter.today:
        return DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      case SalesDateFilter.thisWeek:
      case SalesDateFilter.thisMonth:
      case SalesDateFilter.thisYear:
        return now;
      case SalesDateFilter.custom:
        final DateTime? end = customRange?.end;
        if (end == null) return null;
        return DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    }
  }

  SalesFilter copyWith({
    SalesDateFilter? dateFilter,
    DateTimeRange? customRange,
    bool clearCustomRange = false,
    String? status,
    bool clearStatus = false,
    String? payment,
    bool clearPayment = false,
  }) {
    return SalesFilter(
      dateFilter: dateFilter ?? this.dateFilter,
      customRange:
          clearCustomRange ? null : (customRange ?? this.customRange),
      status: clearStatus ? null : (status ?? this.status),
      payment: clearPayment ? null : (payment ?? this.payment),
    );
  }

  @override
  List<Object?> get props => [dateFilter, customRange, status, payment];
}

/// Opens the sales filter bottom sheet.
///
/// Returns the updated [SalesFilter], or `null` when the operator
/// dismissed the sheet without applying changes.
Future<SalesFilter?> showSalesFilterSheet({
  required BuildContext context,
  required SalesFilter current,
}) {
  return showModalBottomSheet<SalesFilter>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) =>
        _SalesFilterSheet(initial: current),
  );
}

class _SalesFilterSheet extends StatefulWidget {
  const _SalesFilterSheet({required this.initial});

  final SalesFilter initial;

  @override
  State<_SalesFilterSheet> createState() => _SalesFilterSheetState();
}

class _SalesFilterSheetState extends State<_SalesFilterSheet> {
  late SalesFilter _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  Future<void> _pickCustomRange() async {
    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _draft.customRange,
      helpText: 'اختر الفترة',
      saveText: 'تطبيق',
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _draft = _draft.copyWith(
        dateFilter: SalesDateFilter.custom,
        customRange: picked,
      );
    });
  }

  void _onDateSelected(SalesDateFilter value) {
    if (value == SalesDateFilter.custom) {
      _pickCustomRange();
      return;
    }
    setState(() {
      _draft = _draft.copyWith(
        dateFilter: value,
        clearCustomRange: true,
      );
    });
  }

  void _clearAll() {
    setState(() => _draft = const SalesFilter());
  }

  void _apply() {
    Navigator.of(context).pop(_draft);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 4,
          bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ---- Header ----
              Row(
                children: <Widget>[
                  Icon(Icons.filter_alt_outlined, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'الفلاتر',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (_draft.isNotEmpty)
                    TextButton.icon(
                      onPressed: _clearAll,
                      icon: const Icon(Icons.clear_all, size: 18),
                      label: const Text('مسح الكل'),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // ---- Date ----
              _sectionTitle(theme, 'الفترة'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _chip(
                    label: 'الكل',
                    value: SalesDateFilter.all,
                    selectedValue: _draft.dateFilter,
                    onSelected: _onDateSelected,
                  ),
                  _chip(
                    label: 'اليوم',
                    value: SalesDateFilter.today,
                    selectedValue: _draft.dateFilter,
                    onSelected: _onDateSelected,
                  ),
                  _chip(
                    label: 'هذا الأسبوع',
                    value: SalesDateFilter.thisWeek,
                    selectedValue: _draft.dateFilter,
                    onSelected: _onDateSelected,
                  ),
                  _chip(
                    label: 'هذا الشهر',
                    value: SalesDateFilter.thisMonth,
                    selectedValue: _draft.dateFilter,
                    onSelected: _onDateSelected,
                  ),
                  _chip(
                    label: 'هذا العام',
                    value: SalesDateFilter.thisYear,
                    selectedValue: _draft.dateFilter,
                    onSelected: _onDateSelected,
                  ),
                  _chip(
                    label: _customRangeLabel(),
                    value: SalesDateFilter.custom,
                    selectedValue: _draft.dateFilter,
                    onSelected: _onDateSelected,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ---- Status ----
              _sectionTitle(theme, 'حالة الفاتورة'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _statusChip(label: 'الكل', value: null),
                  _statusChip(label: 'مسودة', value: SaleStatus.draft),
                  _statusChip(label: 'مؤكدة', value: SaleStatus.confirmed),
                  _statusChip(label: 'ملغاة', value: SaleStatus.cancelled),
                ],
              ),
              const SizedBox(height: 16),

              // ---- Payment ----
              _sectionTitle(theme, 'حالة الدفع'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _paymentChip(label: 'الكل', value: null),
                  _paymentChip(
                    label: 'غير مدفوع',
                    value: PaymentStatus.unpaid,
                  ),
                  _paymentChip(
                    label: 'مدفوع جزئيًا',
                    value: PaymentStatus.partial,
                  ),
                  _paymentChip(
                    label: 'مدفوع',
                    value: PaymentStatus.paid,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ---- Actions ----
              Row(
                children: <Widget>[
                  Expanded(
                    child: AppButton(
                      label: 'إلغاء',
                      variant: AppButtonVariant.text,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: AppButton(
                      label: 'تطبيق',
                      icon: Icons.check,
                      onPressed: _apply,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _customRangeLabel() {
    if (_draft.dateFilter == SalesDateFilter.custom &&
        _draft.customRange != null) {
      final DateFormat fmt = DateFormat('yy/MM/dd');
      return '${fmt.format(_draft.customRange!.start)} → '
          '${fmt.format(_draft.customRange!.end)}';
    }
    return 'نطاق مخصص';
  }

  Widget _sectionTitle(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required SalesDateFilter value,
    required SalesDateFilter selectedValue,
    required ValueChanged<SalesDateFilter> onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selectedValue == value,
      onSelected: (_) => onSelected(value),
    );
  }

  Widget _statusChip({required String label, required String? value}) {
    return ChoiceChip(
      label: Text(label),
      selected: _draft.status == value,
      onSelected: (_) {
        setState(() {
          _draft = value == null
              ? _draft.copyWith(clearStatus: true)
              : _draft.copyWith(status: value);
        });
      },
    );
  }

  Widget _paymentChip({required String label, required String? value}) {
    return ChoiceChip(
      label: Text(label),
      selected: _draft.payment == value,
      onSelected: (_) {
        setState(() {
          _draft = value == null
              ? _draft.copyWith(clearPayment: true)
              : _draft.copyWith(payment: value);
        });
      },
    );
  }
}

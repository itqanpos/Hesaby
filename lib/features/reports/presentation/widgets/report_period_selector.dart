// lib/features/reports/presentation/widgets/report_period_selector.dart

import 'package:flutter/material.dart';

import '../../domain/entities/report_period.dart';

/// Opens the period-selection bottom sheet and returns the chosen
/// [ReportPeriod], or `null` when dismissed.
Future<ReportPeriod?> showReportPeriodSelector({
  required BuildContext context,
  required ReportPeriod current,
}) {
  return showModalBottomSheet<ReportPeriod>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) =>
        _ReportPeriodSheet(initial: current),
  );
}

class _ReportPeriodSheet extends StatefulWidget {
  const _ReportPeriodSheet({required this.initial});

  final ReportPeriod initial;

  @override
  State<_ReportPeriodSheet> createState() => _ReportPeriodSheetState();
}

class _ReportPeriodSheetState extends State<_ReportPeriodSheet> {
  late ReportPeriod _draft;

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
        type: ReportPeriodType.custom,
        customRange: picked,
      );
    });
  }

  void _onTypeSelected(ReportPeriodType type) {
    if (type == ReportPeriodType.custom) {
      _pickCustomRange();
      return;
    }
    setState(() {
      _draft = _draft.copyWith(
        type: type,
        clearCustomRange: true,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.event_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'الفترة',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _chip('الكل', ReportPeriodType.all),
                _chip('اليوم', ReportPeriodType.today),
                _chip('هذا الأسبوع', ReportPeriodType.thisWeek),
                _chip('هذا الشهر', ReportPeriodType.thisMonth),
                _chip('هذا العام', ReportPeriodType.thisYear),
                _chip('آخر 30 يومًا', ReportPeriodType.last30Days),
                _chip(_customLabel(), ReportPeriodType.custom),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('إلغاء'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(_draft),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('تطبيق'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, ReportPeriodType type) {
    return ChoiceChip(
      label: Text(label),
      selected: _draft.type == type,
      onSelected: (_) => _onTypeSelected(type),
    );
  }

  String _customLabel() {
    if (_draft.type == ReportPeriodType.custom &&
        _draft.customRange != null) {
      final DateFormat fmt = DateFormat('yy/MM/dd');
      return '${fmt.format(_draft.customRange!.start)} → '
          '${fmt.format(_draft.customRange!.end)}';
    }
    return 'نطاق مخصص';
  }
}

/// Compact inline button that shows the current period and opens the
/// selector when tapped. Designed to be placed in the AppBar actions row.
class ReportPeriodButton extends StatelessWidget {
  const ReportPeriodButton({
    super.key,
    required this.period,
    required this.onPressed,
  });

  final ReportPeriod period;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.calendar_month_outlined,
                  size: 16,
                  color: scheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  period.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down,
                  size: 18,
                  color: scheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

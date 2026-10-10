// lib/features/settings/presentation/widgets/print_font_settings_section.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/logger.dart';
import '../../domain/entities/company_settings.dart';
import '../../domain/repositories/company_settings_repository.dart';
import '../providers/company_settings_providers.dart';

/// Settings section that lets the user tune font size + weight for both
/// thermal receipts and A4 / PDF documents.
///
/// Live preview at the bottom reflects the current slider values so the
/// user can see the result before leaving the page.
class PrintFontSettingsSection extends ConsumerStatefulWidget {
  const PrintFontSettingsSection({super.key});

  @override
  ConsumerState<PrintFontSettingsSection> createState() =>
      _PrintFontSettingsSectionState();
}

class _PrintFontSettingsSectionState
    extends ConsumerState<PrintFontSettingsSection> {
  bool _isSaving = false;
  String? _error;

  // ---------------------------------------------------------------------------
  // Save helper
  // ---------------------------------------------------------------------------

  Future<void> _save({
    double? thermalScale,
    PrintFontWeight? weight,
    double? a4Scale,
  }) async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await ref.read(companySettingsProvider.notifier).updateSettings(
            printFontScale: thermalScale,
            printFontWeight: weight,
            printFontScaleA4: a4Scale,
          );
    } on CompanySettingsException catch (e) {
      if (mounted) setState(() => _error = _messageFor(e.type));
    } on Object catch (e, s) {
      AppLogger.error('Print settings save failed', e, s);
      if (mounted) {
        setState(() => _error = 'تعذّر حفظ الإعدادات. حاول مرة أخرى.');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  static String _messageFor(CompanySettingsFailureType type) => switch (type) {
        CompanySettingsFailureType.network =>
          'تعذّر الاتصال بالخادم. تحقق من اتصالك.',
        CompanySettingsFailureType.unauthorized =>
          'لا تملك صلاحية تعديل الإعدادات.',
        CompanySettingsFailureType.notFound =>
          'لم يتم العثور على إعدادات الشركة.',
        CompanySettingsFailureType.invalidTaxRate =>
          'قيمة غير صحيحة.',
        CompanySettingsFailureType.invalidDiscountLimit =>
          'قيمة غير صحيحة.',
        CompanySettingsFailureType.invalidFooter => 'قيمة غير صحيحة.',
        CompanySettingsFailureType.invalidResponse =>
          'تعذّر قراءة البيانات من الخادم.',
        CompanySettingsFailureType.unknown =>
          'حدث خطأ غير متوقع. حاول مرة أخرى.',
      };

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final CompanySettings settings =
        ref.watch(companySettingsProvider).valueOrNull ??
            CompanySettings.defaults('');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SectionHeader(
          icon: Icons.tune,
          title: 'حجم وثقل الخط',
        ),
        const SizedBox(height: 10),

        // ---- Thermal ----
        _Card(
          title: 'الإيصالات الحرارية',
          subtitle: 'يُطبَّق على إيصالات POS وفواتير الشراء الحرارية.',
          children: <Widget>[
            _SliderRow(
              label: 'حجم الخط',
              value: settings.printFontScale,
              onChanged: (double v) {
                ref
                    .read(companySettingsProvider.notifier)
                    .updateSettings(printFontScale: v);
              },
            ),
            const SizedBox(height: 12),
            _WeightSelector(
              current: settings.printFontWeight,
              enabled: !_isSaving,
              onChanged: (PrintFontWeight w) => _save(weight: w),
            ),
            const SizedBox(height: 14),
            _ThermalPreview(
              scale: settings.printFontScale,
              weight: settings.printFontWeight,
            ),
          ],
        ),

        const SizedBox(height: 12),

        // ---- A4 / PDF ----
        _Card(
          title: 'مستندات A4 / PDF',
          subtitle: 'يُطبَّق على التقارير، كشوف الحساب، وفواتير A4.',
          children: <Widget>[
            _SliderRow(
              label: 'حجم الخط',
              value: settings.printFontScaleA4,
              onChanged: (double v) {
                ref
                    .read(companySettingsProvider.notifier)
                    .updateSettings(printFontScaleA4: v);
              },
            ),
            const SizedBox(height: 12),
            _WeightSelector(
              current: settings.printFontWeight,
              enabled: !_isSaving,
              onChanged: (PrintFontWeight w) => _save(weight: w),
            ),
            const SizedBox(height: 14),
            _A4Preview(
              scale: settings.printFontScaleA4,
              weight: settings.printFontWeight,
            ),
          ],
        ),

        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          _ErrorBanner(message: _error!),
        ],
      ],
    );
  }
}

// ============================================================================
// Slider row
// ============================================================================

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '${value.toStringAsFixed(2)}×',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: 0.8,
          max: 1.6,
          divisions: 16,
          label: '${value.toStringAsFixed(2)}×',
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ============================================================================
// Weight selector
// ============================================================================

class _WeightSelector extends StatelessWidget {
  const _WeightSelector({
    required this.current,
    required this.enabled,
    required this.onChanged,
  });

  final PrintFontWeight current;
  final bool enabled;
  final ValueChanged<PrintFontWeight> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'ثقل الخط',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<PrintFontWeight>(
          segments: const <ButtonSegment<PrintFontWeight>>[
            ButtonSegment<PrintFontWeight>(
              value: PrintFontWeight.normal,
              label: Text('عادي'),
            ),
            ButtonSegment<PrintFontWeight>(
              value: PrintFontWeight.medium,
              label: Text('متوسط'),
            ),
            ButtonSegment<PrintFontWeight>(
              value: PrintFontWeight.bold,
              label: Text('عريض'),
            ),
          ],
          selected: <PrintFontWeight>{current},
          onSelectionChanged: enabled
              ? (Set<PrintFontWeight> s) => onChanged(s.first)
              : null,
        ),
      ],
    );
  }
}

// ============================================================================
// Preview widgets
// ============================================================================

class _ThermalPreview extends StatelessWidget {
  const _ThermalPreview({required this.scale, required this.weight});

  final double scale;
  final PrintFontWeight weight;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final double base = 11.0 * scale;
    final FontWeight w = _weightOf(weight);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _PreviewLabel(),
            const SizedBox(height: 8),
            Text(
              'مؤسسة النور',
              style: TextStyle(
                fontSize: 18 * scale,
                fontWeight: w,
                color: scheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'فاتورة مبيعات',
              style: TextStyle(
                fontSize: base,
                fontWeight: w,
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const Divider(height: 16),
            Row(
              children: <Widget>[
                Text('سكر 1 كجم', style: TextStyle(fontSize: base)),
                const Spacer(),
                Text('200 ج.م', style: TextStyle(fontSize: base)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Text('زيت 1 لتر', style: TextStyle(fontSize: base)),
                const Spacer(),
                Text('80 ج.م', style: TextStyle(fontSize: base)),
              ],
            ),
            const Divider(height: 16),
            Row(
              children: <Widget>[
                Text(
                  'الإجمالي',
                  style: TextStyle(fontSize: base * 1.1, fontWeight: w),
                ),
                const Spacer(),
                Text(
                  '280 ج.م',
                  style: TextStyle(fontSize: base * 1.1, fontWeight: w),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _A4Preview extends StatelessWidget {
  const _A4Preview({required this.scale, required this.weight});

  final double scale;
  final PrintFontWeight weight;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final double base = 11.0 * scale;
    final FontWeight w = _weightOf(weight);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _PreviewLabel(),
            const SizedBox(height: 8),
            Text(
              'تقرير المبيعات',
              style: TextStyle(
                fontSize: 14 * scale,
                fontWeight: w,
                color: scheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'الفترة: أكتوبر 2026',
              style: TextStyle(
                fontSize: base * 0.9,
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const Divider(height: 16),
            _A4Row(
              cells: const <String>['التاريخ', 'العميل', 'الإجمالي'],
              fontSize: base,
              weight: w,
              bold: true,
            ),
            const SizedBox(height: 4),
            _A4Row(
              cells: const <String>['01/10', 'أحمد محمد', '1,200 ج.م'],
              fontSize: base,
              weight: FontWeight.w400,
            ),
            _A4Row(
              cells: const <String>['02/10', 'سارة علي', '850 ج.م'],
              fontSize: base,
              weight: FontWeight.w400,
            ),
            _A4Row(
              cells: const <String>['03/10', 'خالد حسن', '2,400 ج.م'],
              fontSize: base,
              weight: FontWeight.w400,
            ),
          ],
        ),
      ),
    );
  }
}

class _A4Row extends StatelessWidget {
  const _A4Row({
    required this.cells,
    required this.fontSize,
    required this.weight,
    this.bold = false,
  });

  final List<String> cells;
  final double fontSize;
  final FontWeight weight;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 2,
            child: Text(
              cells[0],
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: weight,
                color: bold ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              cells[1],
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: weight,
                color: bold ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              cells[2],
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: weight,
                color: bold ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewLabel extends StatelessWidget {
  const _PreviewLabel();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Row(
      children: <Widget>[
        Icon(
          Icons.visibility_outlined,
          size: 14,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          'معاينة',
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Helpers
// ============================================================================

FontWeight _weightOf(PrintFontWeight w) => switch (w) {
      PrintFontWeight.normal => FontWeight.w400,
      PrintFontWeight.medium => FontWeight.w600,
      PrintFontWeight.bold => FontWeight.w800,
    };

// ============================================================================
// Card
// ============================================================================

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Section header
// ============================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Row(
      children: <Widget>[
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Error banner
// ============================================================================

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.error_outline,
              color: scheme.onErrorContainer,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

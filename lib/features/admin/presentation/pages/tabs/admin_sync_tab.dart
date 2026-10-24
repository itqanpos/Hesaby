// lib/features/admin/presentation/pages/tabs/admin_sync_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../../shared/widgets/app_empty.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loader.dart';
import '../../providers/sync_overview_provider.dart';

class AdminSyncTab extends ConsumerWidget {
  const AdminSyncTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<SyncOverview> async =
        ref.watch(syncOverviewProvider);

    return async.when(
      loading: () => const AppLoader(),
      error: (Object error, StackTrace _) => AppErrorView(
        title: 'تعذّر تحميل حالة المزامنة',
        message: error is SyncOverviewException
            ? error.message
            : 'حدث خطأ غير متوقع. حاول مرة أخرى.',
        retryLabel: 'إعادة المحاولة',
        onRetry: () => ref.read(syncOverviewProvider.notifier).refresh(),
      ),
      data: (SyncOverview data) {
        return RefreshIndicator(
          onRefresh: () => ref.read(syncOverviewProvider.notifier).refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: <Widget>[
              const _PartialCoverageBanner(),
              const SizedBox(height: 12),
              _Header(computedAt: data.computedAt),
              const SizedBox(height: 12),
              _DevicesKpiGrid(data: data),
              const SizedBox(height: 12),
              _InvoicesKpi(data: data),
              const SizedBox(height: 20),
              _SectionTitle(
                title: 'الأجهزة (${data.devices.length})',
              ),
              const SizedBox(height: 8),
              if (data.devices.isEmpty)
                const AppEmptyView(
                  icon: Icons.devices_other_outlined,
                  title: 'لا توجد أجهزة مسجّلة',
                  message:
                      'لم تُسجَّل أي فاتورة من جهاز بعد. ستظهر الأجهزة تلقائيًا بعد أول مزامنة.',
                )
              else
                Column(
                  children: data.devices
                      .map((SyncDevice d) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _DeviceTile(device: d),
                          ))
                      .toList(growable: false),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// Banner
// ============================================================================

class _PartialCoverageBanner extends StatelessWidget {
  const _PartialCoverageBanner();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline,
              color: scheme.onTertiaryContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'عرض جزئي — البيانات مستخرجة من الفواتير فقط. '
              'العمليات المعلقة والفاشلة وأسبابها، ومزامنة المخزون/المشتريات، '
              'غير متتبَّعة بعد. يتطلب Phase 5b (سجل sync_events كامل).',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Header
// ============================================================================

class _Header extends StatelessWidget {
  const _Header({required this.computedAt});
  final DateTime computedAt;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Row(
      children: <Widget>[
        Icon(Icons.sync, color: scheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'حالة مزامنة الأجهزة',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          DateFormat('yyyy/MM/dd HH:mm').format(computedAt.toLocal()),
          style: theme.textTheme.labelSmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ============================================================================
// KPIs — devices
// ============================================================================

class _DevicesKpiGrid extends StatelessWidget {
  const _DevicesKpiGrid({required this.data});
  final SyncOverview data;

  @override
  Widget build(BuildContext context) {
    final NumberFormat nf = NumberFormat.decimalPattern('en');
    final List<_Kpi> items = <_Kpi>[
      _Kpi(
        label: 'إجمالي الأجهزة',
        value: nf.format(data.devicesTotal),
        icon: Icons.devices_other,
        color: const Color(0xFF0288D1),
      ),
      _Kpi(
        label: 'نشطة (24س)',
        value: nf.format(data.devicesActive24h),
        icon: Icons.bolt,
        color: const Color(0xFF1B5E20),
      ),
      _Kpi(
        label: 'نشطة (7 أيام)',
        value: nf.format(data.devicesActive7d),
        icon: Icons.schedule,
        color: const Color(0xFF0F7B6C),
      ),
      _Kpi(
        label: 'خاملة (30+ يوم)',
        value: nf.format(data.devicesStale30d),
        icon: Icons.hourglass_bottom,
        color: const Color(0xFFC62828),
      ),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 700;
        return GridView.count(
          crossAxisCount: wide ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: wide ? 1.55 : 1.4,
          children:
              items.map((_Kpi k) => _KpiCard(kpi: k)).toList(growable: false),
        );
      },
    );
  }
}

class _Kpi {
  const _Kpi({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.kpi});
  final _Kpi kpi;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: kpi.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(kpi.icon, color: kpi.color, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  kpi.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            kpi.value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: kpi.color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Invoices mini KPI
// ============================================================================

class _InvoicesKpi extends StatelessWidget {
  const _InvoicesKpi({required this.data});
  final SyncOverview data;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final NumberFormat nf = NumberFormat.decimalPattern('en');

    final List<({IconData icon, String label, String value, Color color})>
        items = <({IconData icon, String label, String value, Color color})>[
      (
        icon: Icons.receipt_long_outlined,
        label: 'فواتير بجهاز',
        value: nf.format(data.invoicesWithDevice),
        color: scheme.onSurface,
      ),
      (
        icon: Icons.cloud_done_outlined,
        label: 'مُزامنة',
        value: nf.format(data.invoicesSynced),
        color: const Color(0xFF1B5E20),
      ),
      (
        icon: Icons.cloud_upload_outlined,
        label: 'معلقة',
        value: nf.format(data.invoicesPending),
        color: data.invoicesPending > 0
            ? const Color(0xFFC62828)
            : scheme.onSurfaceVariant,
      ),
      (
        icon: Icons.error_outline,
        label: 'لم تُزامن أبدًا',
        value: nf.format(data.devicesNeverSynced),
        color: data.devicesNeverSynced > 0
            ? const Color(0xFFC62828)
            : scheme.onSurfaceVariant,
      ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map((e) => _MiniChip(
                icon: e.icon,
                label: e.label,
                value: e.value,
                color: e.color,
              ))
          .toList(growable: false),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Device tile
// ============================================================================

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});
  final SyncDevice device;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final ({String label, Color bg, Color fg}) status =
        _resolveStatus(device, scheme);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.smartphone,
              color: scheme.onPrimaryContainer,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  device.deviceId.isEmpty ? 'جهاز غير معروف' : device.deviceId,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  device.companyName != null && device.companyName!.isNotEmpty
                      ? device.companyName!
                      : '— شركة غير مرتبطة',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'آخر مزامنة: ${_fmt(device.lastSyncAt)} · '
                  '${device.invoicesCount} فاتورة',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: status.bg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: status.fg,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime? t) {
    if (t == null) return '—';
    return DateFormat('yyyy/MM/dd HH:mm').format(t.toLocal());
  }

  static ({String label, Color bg, Color fg}) _resolveStatus(
    SyncDevice d,
    ColorScheme scheme,
  ) {
    if (d.neverSynced) {
      return (
        label: 'لم يُزامن',
        bg: scheme.error,
        fg: scheme.onError,
      );
    }
    if (d.stale30d) {
      return (
        label: 'خامل 30+ يوم',
        bg: scheme.errorContainer,
        fg: scheme.onErrorContainer,
      );
    }
    if (d.active24h) {
      return (
        label: 'نشط (24س)',
        bg: const Color(0xFFC8E6C9),
        fg: const Color(0xFF1B5E20),
      );
    }
    if (d.active7d) {
      return (
        label: 'نشط (7 أيام)',
        bg: const Color(0xFFFFECB3),
        fg: const Color(0xFF8D6E00),
      );
    }
    return (
      label: 'غير نشط',
      bg: scheme.surfaceContainerHighest,
      fg: scheme.onSurfaceVariant,
    );
  }
}

// ============================================================================
// Section title
// ============================================================================

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

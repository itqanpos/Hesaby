// lib/features/admin/presentation/pages/tabs/admin_overview_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../../shared/widgets/app_empty.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loader.dart';
import '../../providers/platform_overview_provider.dart';

class AdminOverviewTab extends ConsumerWidget {
  const AdminOverviewTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PlatformOverview> async =
        ref.watch(platformOverviewProvider);

    return async.when(
      loading: () => const AppLoader(),
      error: (Object error, StackTrace _) => AppErrorView(
        title: 'تعذّر تحميل ملخص المنصة',
        message: error is PlatformOverviewException
            ? error.message
            : 'حدث خطأ غير متوقع. حاول مرة أخرى.',
        retryLabel: 'إعادة المحاولة',
        onRetry: () => ref.read(platformOverviewProvider.notifier).refresh(),
      ),
      data: (PlatformOverview data) {
        return RefreshIndicator(
          onRefresh: () =>
              ref.read(platformOverviewProvider.notifier).refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: <Widget>[
              _Header(computedAt: data.computedAt),
              const SizedBox(height: 12),
              _KpiGrid(data: data),
              const SizedBox(height: 20),
              const _SectionTitle(title: 'توزيع حالة الشركات'),
              const SizedBox(height: 8),
              _CompanyDistribution(data: data),
              const SizedBox(height: 20),
              const _SectionTitle(title: 'مؤشرات إضافية'),
              const SizedBox(height: 8),
              _SecondaryKpis(data: data),
              const SizedBox(height: 20),
              const _SectionTitle(title: 'آخر الشركات المسجلة'),
              const SizedBox(height: 8),
              _RecentCompaniesList(companies: data.recentCompanies),
            ],
          ),
        );
      },
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
        Icon(Icons.insights, color: scheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'نظرة عامة على المنصة',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          DateFormat('yyyy/MM/dd HH:mm')
              .format(computedAt.toLocal()),
          style: theme.textTheme.labelSmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ============================================================================
// KPI grid (4 primary cards)
// ============================================================================

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.data});

  final PlatformOverview data;

  @override
  Widget build(BuildContext context) {
    final NumberFormat nf = NumberFormat.decimalPattern('en');
    final NumberFormat money =
        NumberFormat.currency(locale: 'en', symbol: 'EGP ', decimalDigits: 0);

    final List<_Kpi> items = <_Kpi>[
      _Kpi(
        label: 'الشركات',
        value: nf.format(data.companiesTotal),
        hint:
            'نشط ${nf.format(data.companiesActive + data.companiesLifetime)} · تجربة ${nf.format(data.companiesTrial)} · موقوفة ${nf.format(data.companiesSuspended)}',
        icon: Icons.storefront_outlined,
        color: const Color(0xFF0288D1),
      ),
      _Kpi(
        label: 'المستخدمون',
        value: nf.format(data.usersTotal),
        hint: 'الفروع ${nf.format(data.branchesTotal)}',
        icon: Icons.people_outline,
        color: const Color(0xFF0F7B6C),
      ),
      _Kpi(
        label: 'المبيعات',
        value: nf.format(data.salesTotal),
        hint:
            'اليوم ${nf.format(data.salesToday)} · الشهر ${nf.format(data.salesThisMonth)}',
        icon: Icons.point_of_sale_outlined,
        color: const Color(0xFF6A1B9A),
      ),
      _Kpi(
        label: 'إيرادات المنصة',
        value: money.format(data.revenueTotal),
        hint: 'هذا الشهر ${money.format(data.revenueThisMonth)}',
        icon: Icons.payments_outlined,
        color: const Color(0xFF1B5E20),
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
    required this.hint,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String hint;
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: kpi.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(kpi.icon, color: kpi.color, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  kpi.label,
                  style: theme.textTheme.labelMedium?.copyWith(
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
          const SizedBox(height: 2),
          Text(
            kpi.hint,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Company status distribution
// ============================================================================

class _CompanyDistribution extends StatelessWidget {
  const _CompanyDistribution({required this.data});

  final PlatformOverview data;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final int total = data.companiesTotal;
    if (total == 0) {
      return const AppEmptyView(
        icon: Icons.apartment_outlined,
        title: 'لا توجد شركات بعد',
        message: 'لم تُسجَّل أي شركة في المنصة حتى الآن.',
      );
    }

    final List<_Segment> segments = <_Segment>[
      _Segment(
        label: 'نشط',
        count: data.companiesActive,
        color: const Color(0xFF1B5E20),
      ),
      _Segment(
        label: 'مدى الحياة',
        count: data.companiesLifetime,
        color: const Color(0xFF6A1B9A),
      ),
      _Segment(
        label: 'تجربة',
        count: data.companiesTrial,
        color: const Color(0xFF8D6E00),
      ),
      _Segment(
        label: 'موقوفة',
        count: data.companiesSuspended,
        color: scheme.error,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 14,
              child: Row(
                children: <Widget>[
                  for (final _Segment s in segments)
                    if (s.count > 0)
                      Expanded(
                        flex: s.count,
                        child: Container(color: s.color),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: <Widget>[
              for (final _Segment s in segments)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: s.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${s.label} (${s.count})',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Segment {
  const _Segment({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;
}

// ============================================================================
// Secondary KPIs
// ============================================================================

class _SecondaryKpis extends StatelessWidget {
  const _SecondaryKpis({required this.data});

  final PlatformOverview data;

  @override
  Widget build(BuildContext context) {
    final NumberFormat nf = NumberFormat.decimalPattern('en');
    final List<({IconData icon, String label, String value})> items =
        <({IconData icon, String label, String value})>[
      (
        icon: Icons.inventory_2_outlined,
        label: 'المنتجات',
        value: nf.format(data.productsTotal),
      ),
      (
        icon: Icons.person_outline,
        label: 'العملاء',
        value: nf.format(data.customersTotal),
      ),
      (
        icon: Icons.add_business_outlined,
        label: 'شركات جديدة اليوم',
        value: nf.format(data.companiesNewToday),
      ),
      (
        icon: Icons.calendar_month_outlined,
        label: 'شركات جديدة هذا الشهر',
        value: nf.format(data.companiesNewThisMonth),
      ),
      (
        icon: Icons.trending_up,
        label: 'نشاط آخر 7 أيام',
        value: nf.format(data.companiesActiveLast7d),
      ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map((e) => _MiniKpi(icon: e.icon, label: e.label, value: e.value))
          .toList(growable: false),
    );
  }
}

class _MiniKpi extends StatelessWidget {
  const _MiniKpi({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

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
          Icon(icon, size: 16, color: scheme.primary),
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
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Recent companies
// ============================================================================

class _RecentCompaniesList extends StatelessWidget {
  const _RecentCompaniesList({required this.companies});

  final List<RecentCompany> companies;

  @override
  Widget build(BuildContext context) {
    if (companies.isEmpty) {
      return const AppEmptyView(
        icon: Icons.storefront_outlined,
        title: 'لا توجد شركات',
        message: 'لم يتم تسجيل أي شركة حتى الآن.',
      );
    }

    return Column(
      children: companies
          .map((RecentCompany c) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RecentCompanyTile(company: c),
              ))
          .toList(growable: false),
    );
  }
}

class _RecentCompanyTile extends StatelessWidget {
  const _RecentCompanyTile({required this.company});

  final RecentCompany company;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final ({String label, Color bg, Color fg}) badge =
        _resolveBadge(company, scheme);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 18,
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: Text(
              company.name.isEmpty
                  ? '?'
                  : company.name.characters.first.toUpperCase(),
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  company.name,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  DateFormat('yyyy/MM/dd')
                      .format(company.createdAt.toLocal()),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badge.bg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              badge.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: badge.fg,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static ({String label, Color bg, Color fg}) _resolveBadge(
    RecentCompany c,
    ColorScheme scheme,
  ) {
    if (c.isSuspended) {
      return (label: 'موقوفة', bg: scheme.error, fg: scheme.onError);
    }
    if (c.isLifetime) {
      return (
        label: 'مدى الحياة',
        bg: const Color(0xFFE1BEE7),
        fg: const Color(0xFF6A1B9A),
      );
    }
    return switch (c.subscriptionStatus) {
      'active' => (
          label: 'نشط',
          bg: const Color(0xFFC8E6C9),
          fg: const Color(0xFF1B5E20),
        ),
      'trial' => (
          label: 'تجربة',
          bg: const Color(0xFFFFECB3),
          fg: const Color(0xFF8D6E00),
        ),
      'expired' || 'cancelled' => (
          label: 'منتهي',
          bg: scheme.errorContainer,
          fg: scheme.onErrorContainer,
        ),
      _ => (
          label: c.subscriptionStatus ?? '—',
          bg: scheme.surfaceContainerHighest,
          fg: scheme.onSurfaceVariant,
        ),
    };
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

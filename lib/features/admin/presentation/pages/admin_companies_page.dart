// lib/features/admin/presentation/pages/admin_companies_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../companies/domain/entities/company.dart';
import '../../../companies/domain/entities/company_subscription.dart';
import '../../../companies/domain/repositories/company_repository.dart';
import '../../../settings/presentation/providers/user_profile_providers.dart';
import '../dialogs/admin_company_actions_dialog.dart';
import '../providers/admin_companies_provider.dart';

/// Phase T-2: platform admin dashboard.
///
/// Lists every company in the platform and lets the owner activate, extend,
/// or cancel a subscription in place — no SQL editor round trips.
///
/// Access is gated in three layers:
/// 1. `isPlatformAdminProvider` (UI — hides the tile).
/// 2. This page's own check (shows an "unauthorized" empty state).
/// 3. RLS policies on `companies` (authoritative — a non-admin sees an
///    empty list even if they somehow reach the page).
class AdminCompaniesPage extends ConsumerStatefulWidget {
  const AdminCompaniesPage({super.key});

  @override
  ConsumerState<AdminCompaniesPage> createState() =>
      _AdminCompaniesPageState();
}

class _AdminCompaniesPageState extends ConsumerState<AdminCompaniesPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  _StatusFilter _statusFilter = _StatusFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Filtering
  // ---------------------------------------------------------------------------

  List<Company> _applyFilters(List<Company> companies) {
    final String query = _searchQuery.trim().toLowerCase();

    return companies.where((Company c) {
      if (_statusFilter != _StatusFilter.all) {
        final CompanySubscription sub = CompanySubscription.fromCompany(c);
        final bool matches = switch (_statusFilter) {
          _StatusFilter.active => sub.isActive,
          _StatusFilter.trial => sub.isTrial,
          _StatusFilter.expired => sub.isExpired,
          _StatusFilter.all => true,
        };
        if (!matches) return false;
      }

      if (query.isEmpty) return true;

      final String name = c.name.toLowerCase();
      final String phone = (c.phone ?? '').toLowerCase();
      final String email = (c.email ?? '').toLowerCase();
      return name.contains(query) ||
          phone.contains(query) ||
          email.contains(query);
    }).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _openActions(Company company) async {
    final AdminSubscriptionChoice? choice =
        await showAdminCompanyActionsDialog(
      context: context,
      company: company,
    );
    if (choice == null || !mounted) return;

    try {
      if (choice.action == AdminSubscriptionAction.cancel) {
        await ref
            .read(adminCompaniesProvider.notifier)
            .updateSubscription(
              companyId: company.id,
              subscriptionStatus: 'cancelled',
            );
      } else {
        final CompanySubscription sub =
            CompanySubscription.fromCompany(company);
        final DateTime now = DateTime.now().toUtc();
        final DateTime? until = sub.subscribedUntil;
        final DateTime base = (sub.isActive &&
                until != null &&
                until.isAfter(now))
            ? until
            : now;
        final Duration duration = choice.billingCycle == 'yearly'
            ? const Duration(days: 365)
            : const Duration(days: 30);
        await ref
            .read(adminCompaniesProvider.notifier)
            .updateSubscription(
              companyId: company.id,
              subscriptionStatus: 'active',
              planId: choice.planId,
              billingCycle: choice.billingCycle,
              subscribedUntil: base.add(duration),
            );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تم تحديث الاشتراك')),
        );
    } on CompanyException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_failureMessage(error.type))),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = ref.watch(isPlatformAdminProvider);
    final AsyncValue<List<Company>> companiesAsync =
        ref.watch(adminCompaniesProvider);

    return AppShell(
      appBar: AppBar(
        title: const Text('لوحة المالك'),
        actions: <Widget>[
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(adminCompaniesProvider.notifier).refresh();
            },
          ),
        ],
      ),
      body: !isAdmin
          ? const AppEmptyView(
              icon: Icons.lock_outline,
              title: 'غير مصرّح',
              message: 'هذه الصفحة متاحة لمديري المنصة فقط.',
            )
          : companiesAsync.when(
              loading: () => const AppLoader(),
              error: (Object error, StackTrace _) => AppErrorView(
                title: 'تعذّر تحميل قائمة الشركات',
                message: error is CompanyException
                    ? _failureMessage(error.type)
                    : 'حدث خطأ غير متوقع. حاول مرة أخرى.',
                retryLabel: 'إعادة المحاولة',
                onRetry: () =>
                    ref.read(adminCompaniesProvider.notifier).refresh(),
              ),
              data: (List<Company> all) {
                final List<Company> filtered = _applyFilters(all);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 12),
                      child: _KpiRow(companies: all),
                    ),
                    AppTextField(
                      controller: _searchController,
                      hint: 'ابحث بالاسم أو الهاتف أو البريد',
                      prefixIcon: Icons.search,
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'مسح',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            ),
                      onChanged: (String v) {
                        setState(() => _searchQuery = v);
                      },
                    ),
                    const SizedBox(height: 8),
                    _StatusFilterBar(
                      current: _statusFilter,
                      onChanged: (f) => setState(() => _statusFilter = f),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? AppEmptyView(
                              icon: all.isEmpty
                                  ? Icons.apartment_outlined
                                  : Icons.search_off_outlined,
                              title: all.isEmpty
                                  ? 'لا توجد شركات'
                                  : 'لا نتائج',
                              message: all.isEmpty
                                  ? 'لم يتم العثور على أي شركة في المنصة.'
                                  : 'لا توجد شركات تطابق الفلاتر الحالية.',
                            )
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.only(bottom: 24),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (BuildContext _, int i) {
                                final Company company = filtered[i];
                                return _CompanyCard(
                                  company: company,
                                  onTap: () => _openActions(company),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  static String _failureMessage(CompanyFailureType type) => switch (type) {
        CompanyFailureType.network =>
          'تعذّر الاتصال بالخادم. تحقق من اتصالك بالإنترنت.',
        CompanyFailureType.unauthorized =>
          'ليس لديك صلاحية للقيام بهذا الإجراء.',
        CompanyFailureType.noCompanies => 'لا توجد شركات.',
        CompanyFailureType.companyNotAccessible =>
          'لا يمكن الوصول إلى هذه الشركة.',
        CompanyFailureType.noBranches => 'لا توجد فروع.',
        CompanyFailureType.invalidResponse =>
          'تعذّر قراءة البيانات من الخادم.',
        CompanyFailureType.unknown =>
          'حدث خطأ غير متوقع. حاول مرة أخرى.',
      };
}

// ============================================================================
// Status filter
// ============================================================================

enum _StatusFilter { all, active, trial, expired }

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({
    required this.current,
    required this.onChanged,
  });

  final _StatusFilter current;
  final ValueChanged<_StatusFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final _StatusFilter f in _StatusFilter.values) ...<Widget>[
            ChoiceChip(
              label: Text(_label(f)),
              selected: current == f,
              onSelected: (_) => onChanged(f),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  static String _label(_StatusFilter f) => switch (f) {
        _StatusFilter.all => 'الكل',
        _StatusFilter.active => 'نشط',
        _StatusFilter.trial => 'تجربة',
        _StatusFilter.expired => 'منتهي',
      };
}

// ============================================================================
// KPI row
// ============================================================================

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.companies});

  final List<Company> companies;

  @override
  Widget build(BuildContext context) {
    int active = 0;
    int trial = 0;
    int expired = 0;
    for (final Company c in companies) {
      final CompanySubscription sub = CompanySubscription.fromCompany(c);
      if (sub.isExpired) {
        expired++;
      } else if (sub.isTrial) {
        trial++;
      } else if (sub.isActive) {
        active++;
      }
    }

    return Row(
      children: <Widget>[
        Expanded(
          child: _KpiCard(
            label: 'الكل',
            value: companies.length.toString(),
            color: const Color(0xFF0288D1),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            label: 'نشط',
            value: active.toString(),
            color: const Color(0xFF0F7B6C),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            label: 'تجربة',
            value: trial.toString(),
            color: const Color(0xFFEF6C00),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            label: 'منتهي',
            value: expired.toString(),
            color: const Color(0xFFC62828),
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Company card
// ============================================================================

class _CompanyCard extends StatelessWidget {
  const _CompanyCard({required this.company, required this.onTap});

  final Company company;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final CompanySubscription sub = CompanySubscription.fromCompany(company);
    final _BadgeVisual badge = _resolveBadge(sub, scheme);

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 22,
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: Text(
                  company.name.characters.first.toUpperCase(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      company.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: badge.background,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            badge.label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: badge.foreground,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (sub.isActive && sub.plan != null) ...<Widget>[
                          const SizedBox(width: 6),
                          Text(
                            sub.plan!.label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_left,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static _BadgeVisual _resolveBadge(
    CompanySubscription sub,
    ColorScheme scheme,
  ) {
    if (sub.isExpired) {
      return _BadgeVisual(
        label: 'منتهي',
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
      );
    }
    if (sub.isTrial) {
      final int? d = sub.daysRemaining;
      return _BadgeVisual(
        label: d == null ? 'تجربة' : 'تجربة · $d يوم',
        background: const Color(0xFFFFECB3),
        foreground: const Color(0xFF8D6E00),
      );
    }
    final int? d = sub.daysRemaining;
    return _BadgeVisual(
      label: d == null ? 'نشط' : 'نشط · $d يوم',
      background: const Color(0xFFC8E6C9),
      foreground: const Color(0xFF1B5E20),
    );
  }
}

class _BadgeVisual {
  const _BadgeVisual({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;
}

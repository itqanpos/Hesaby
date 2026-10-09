// lib/features/home/presentation/pages/home_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/config/app_config.dart';
import '../../../../app/router.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../companies/domain/repositories/company_repository.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../companies/presentation/widgets/branch_selector.dart';
import '../../../companies/presentation/widgets/company_selector.dart';
import '../../../companies/presentation/widgets/subscription_banner.dart';
import '../../../reports/domain/entities/financial_reports.dart';
import '../../../reports/domain/entities/inventory_reports.dart';
import '../../../reports/presentation/providers/reports_providers.dart';
import '../../../sales/domain/entities/sale_entities.dart';
import '../../../sales/presentation/providers/sales_providers.dart';
import '../../../settings/domain/entities/user_profile.dart';
import '../../../settings/presentation/providers/user_profile_providers.dart';

/// Dashboard Home — the primary navigation hub.
///
/// Layout (top → bottom):
/// 1. Subscription reminder (only when trial / expiring / expired).
/// 2. Greeting + company/branch context.
/// 3. **Onboarding / context area** — one of:
///    * loading spinner while companies are being fetched,
///    * error card with a retry button,
///    * **onboarding card** when the user has no company yet (fresh
///      Google sign-up), pushing them to `/create-company`,
///    * **choose-company card** when the user is a member of several
///      companies but has not picked one yet,
///    * the full dashboard otherwise.
/// 4. Infrastructure footer.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppConfig config = ref.watch(appConfigProvider);
    final CompanyContextState ctx = ref.watch(companyContextProvider);

    return AppShell(
      appBar: AppBar(
        title: const Text('الرئيسية'),
        actions: <Widget>[
          IconButton(
            tooltip: 'الإعدادات',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.pushNamed(AppRouter.settingsName),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: <Widget>[
          const SubscriptionBanner(),
          const _GreetingCard(),
          const SizedBox(height: 16),
          _ContextArea(state: ctx),
          const SizedBox(height: 32),
          _InfrastructureFooter(config: config),
        ],
      ),
    );
  }
}

// ============================================================================
// Context area — decides what to show below the greeting.
// ============================================================================

class _ContextArea extends ConsumerWidget {
  const _ContextArea({required this.state});

  final CompanyContextState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1) Still loading the very first list of companies.
    if (state.isLoadingCompanies && state.companies.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: AppLoader(),
      );
    }

    // 2) Loaded, but the request failed.
    if (state.companiesFailure != null && state.companies.isEmpty) {
      return AppErrorView(
        title: 'تعذّر تحميل بيانات الشركات',
        message: _failureMessage(state.companiesFailure!),
        retryLabel: 'إعادة المحاولة',
        onRetry: () => ref.read(companyContextProvider.notifier).refresh(),
      );
    }

    // 3) No company at all — brand-new Google user, or a user whose
    //    membership list is empty. Push them into the onboarding flow.
    if (state.companies.isEmpty) {
      return const _OnboardingCard();
    }

    // 4) Companies exist but none is selected (multi-company user who has
    //    not picked one yet). Offer a compact chooser.
    if (state.currentCompany == null) {
      return const _ChooseCompanyCard();
    }

    // 5) Full dashboard.
    return const _DashboardContent();
  }

  static String _failureMessage(CompanyFailureType type) => switch (type) {
        CompanyFailureType.network =>
          'تعذّر الاتصال بالخادم. تحقق من اتصالك بالإنترنت.',
        CompanyFailureType.unauthorized =>
          'انتهت الجلسة. يرجى تسجيل الدخول من جديد.',
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
// Onboarding card — shown when the user has no company yet.
// ============================================================================

class _OnboardingCard extends ConsumerStatefulWidget {
  const _OnboardingCard();

  @override
  ConsumerState<_OnboardingCard> createState() => _OnboardingCardState();
}

class _OnboardingCardState extends ConsumerState<_OnboardingCard> {
  Future<void> _goToCreateCompany() async {
    await context.pushNamed(AppRouter.createCompanyName);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: <Color>[
            scheme.primary.withValues(alpha: 0.10),
            scheme.tertiary.withValues(alpha: 0.08),
          ],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.rocket_launch_outlined,
                  color: scheme.onPrimary,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'ابدأ رحلتك مع حسابي',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'أنشئ شركتك في خطوة واحدة لتبدأ البيع، إدارة المخزون، '
              'وتتبع الأرباح. سننشئ لك فرعًا رئيسيًا وتجربة مجانية 7 أيام.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            AppButton(
              label: 'أنشئ شركتك الآن',
              icon: Icons.arrow_forward,
              expanded: true,
              size: AppButtonSize.large,
              onPressed: _goToCreateCompany,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.verified_outlined,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'مجانًا · بدون بطاقة بنكية',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
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
// Choose-company card — shown when several companies exist and none is
// currently selected.
// ============================================================================

class _ChooseCompanyCard extends StatelessWidget {
  const _ChooseCompanyCard();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.apartment_outlined,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'اختر شركة للبدء',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'أنت عضو في أكثر من شركة. اختر واحدة للمتابعة.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const CompanySelector(),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Dashboard content — full widget tree for a selected company.
// ============================================================================

class _DashboardContent extends StatelessWidget {
  const _DashboardContent();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PosHeroBanner(),
        SizedBox(height: 20),
        _KpiGrid(),
        SizedBox(height: 24),
        _SectionHeader(
          title: 'إجراءات سريعة',
          icon: Icons.flash_on_outlined,
        ),
        SizedBox(height: 10),
        _QuickActionsGrid(),
        SizedBox(height: 24),
        _LowStockSection(),
        SizedBox(height: 16),
        _ReceivablesSection(),
        SizedBox(height: 24),
        _ReportsBanner(),
      ],
    );
  }
}

// ============================================================================
// Greeting card
// ============================================================================

class _GreetingCard extends ConsumerWidget {
  const _GreetingCard();

  static String _greeting() {
    final int h = DateTime.now().hour;
    if (h < 12) return 'صباح الخير';
    if (h < 17) return 'طاب يومك';
    return 'مساء الخير';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final AsyncValue<UserProfile?> profileAsync =
        ref.watch(userProfileProvider);
    final AuthState auth = ref.watch(authProvider);
    final CompanyContextState ctx = ref.watch(companyContextProvider);

    final String? fullName = profileAsync.valueOrNull?.fullName;
    final String email = auth.session?.email ?? '';
    final String displayName =
        (fullName != null && fullName.trim().isNotEmpty)
            ? fullName.trim()
            : (email.isNotEmpty ? email.split('@').first : 'أهلًا');

    final String companyName = ctx.currentCompany?.name ?? 'حسابي';
    final String? branchName = ctx.currentBranch?.name;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 22,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Text(
                    displayName.characters.first.toUpperCase(),
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
                        '${_greeting()}، $displayName',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        branchName != null && branchName.isNotEmpty
                            ? '$companyName · $branchName'
                            : companyName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const CompanySelector(),
            const SizedBox(height: 6),
            const BranchSelector(),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// POS hero
// ============================================================================

class _PosHeroBanner extends StatelessWidget {
  const _PosHeroBanner();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.pushNamed(AppRouter.posName),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: <Color>[
                scheme.primary,
                Color.lerp(scheme.primary, scheme.primaryContainer, 0.6) ??
                    scheme.primaryContainer,
              ],
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.onPrimary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.point_of_sale_outlined,
                    color: scheme.onPrimary,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'نقطة البيع',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ابدأ بيعًا سريعًا الآن',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onPrimary.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.onPrimary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios_outlined,
                    color: scheme.onPrimary,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// KPI grid (2 x 2)
// ============================================================================

class _KpiGrid extends ConsumerWidget {
  const _KpiGrid();

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 0,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ---- Today's sales + invoices ----
    final List<Sale> sales =
        ref.watch(salesProvider).valueOrNull ?? const <Sale>[];
    final DateTime now = DateTime.now();
    double todaySales = 0;
    int todayInvoices = 0;
    for (final Sale s in sales) {
      if (!s.isConfirmed) continue;
      final DateTime d = s.saleDate.toLocal();
      if (d.year == now.year && d.month == now.month && d.day == now.day) {
        todaySales += s.total;
        todayInvoices++;
      }
    }

    // ---- Low stock count ----
    final int lowStockCount =
        (ref.watch(lowStockProvider).valueOrNull ?? const <LowStockItem>[])
            .length;

    // ---- Receivables total ----
    final double receivables =
        ref.watch(receivablesProvider).valueOrNull?.totalBalance ?? 0;

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _KpiCard(
                icon: Icons.trending_up_outlined,
                color: const Color(0xFF0F7B6C),
                label: 'مبيعات اليوم',
                value: _money.format(todaySales),
                onTap: () => context.pushNamed(AppRouter.salesName),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiCard(
                icon: Icons.receipt_long_outlined,
                color: const Color(0xFF0288D1),
                label: 'فواتير اليوم',
                value: '$todayInvoices',
                onTap: () => context.pushNamed(AppRouter.salesName),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: _KpiCard(
                icon: Icons.warning_amber_outlined,
                color: const Color(0xFFE65100),
                label: 'مخزون منخفض',
                value: '$lowStockCount',
                emphasize: lowStockCount > 0,
                onTap: () =>
                    context.pushNamed(AppRouter.reportLowStockName),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiCard(
                icon: Icons.account_balance_wallet_outlined,
                color: const Color(0xFFC62828),
                label: 'مستحق العملاء',
                value: _money.format(receivables),
                emphasize: receivables > 0,
                onTap: () =>
                    context.pushNamed(AppRouter.reportReceivablesName),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.onTap,
    this.emphasize = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: emphasize
                  ? color.withValues(alpha: 0.5)
                  : scheme.outlineVariant,
              width: emphasize ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 16, color: color),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: emphasize ? color : scheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Quick actions (4 tiles)
// ============================================================================

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double spacing = 8;
        final double available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 32;
        final double width = (available - spacing * 3) / 4;

        return Row(
          children: <Widget>[
            SizedBox(
              width: width,
              child: const _QuickTile(
                icon: Icons.point_of_sale_outlined,
                color: Color(0xFF0F7B6C),
                title: 'بيع جديد',
                routeName: AppRouter.posName,
              ),
            ),
            const SizedBox(width: spacing),
            SizedBox(
              width: width,
              child: const _QuickTile(
                icon: Icons.shopping_bag_outlined,
                color: Color(0xFF0288D1),
                title: 'شراء جديد',
                routeName: AppRouter.purchaseNewName,
              ),
            ),
            const SizedBox(width: spacing),
            SizedBox(
              width: width,
              child: const _QuickTile(
                icon: Icons.people_outline,
                color: Color(0xFFEF6C00),
                title: 'العملاء',
                routeName: AppRouter.customersName,
              ),
            ),
            const SizedBox(width: spacing),
            SizedBox(
              width: width,
              child: const _QuickTile(
                icon: Icons.analytics_outlined,
                color: Color(0xFF6A1B9A),
                title: 'التقارير',
                routeName: AppRouter.reportsName,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.routeName,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String routeName;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.pushNamed(routeName),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Low stock section
// ============================================================================

class _LowStockSection extends ConsumerWidget {
  const _LowStockSection();

  static final NumberFormat _qty = NumberFormat.decimalPattern('en_US');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<LowStockItem>> async = ref.watch(lowStockProvider);

    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (List<LowStockItem> items) {
        if (items.isEmpty) {
          return const SizedBox.shrink();
        }

        final List<LowStockItem> top =
            items.take(5).toList(growable: false);
        final bool hasMore = items.length > top.length;

        return _SectionCard(
          title: 'مخزون منخفض',
          icon: Icons.warning_amber_outlined,
          accent: const Color(0xFFE65100),
          trailing: hasMore
              ? _SeeAllLink(
                  label: 'عرض الكل',
                  onTap: () =>
                      context.pushNamed(AppRouter.reportLowStockName),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < top.length; i++) ...<Widget>[
                _LowStockRow(item: top[i], qty: _qty),
                if (i < top.length - 1) const SizedBox(height: 6),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _LowStockRow extends StatelessWidget {
  const _LowStockRow({required this.item, required this.qty});

  final LowStockItem item;
  final NumberFormat qty;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Row(
      children: <Widget>[
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: Color(0xFFE65100),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            item.productName,
            style: theme.textTheme.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${qty.format(item.quantityOnHand)} / ${qty.format(item.minStock)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Receivables section
// ============================================================================

class _ReceivablesSection extends ConsumerWidget {
  const _ReceivablesSection();

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 0,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ReceivablesReport> async =
        ref.watch(receivablesProvider);

    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (ReceivablesReport report) {
        if (report.items.isEmpty) {
          return const SizedBox.shrink();
        }

        final List<ReceivableItem> top =
            report.items.take(5).toList(growable: false);
        final bool hasMore = report.items.length > top.length;

        return _SectionCard(
          title: 'أعلى العملاء مدينين',
          icon: Icons.account_balance_wallet_outlined,
          accent: const Color(0xFFC62828),
          trailing: hasMore
              ? _SeeAllLink(
                  label: 'عرض الكل',
                  onTap: () =>
                      context.pushNamed(AppRouter.reportReceivablesName),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < top.length; i++) ...<Widget>[
                _ReceivableRow(item: top[i], money: _money),
                if (i < top.length - 1) const SizedBox(height: 6),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ReceivableRow extends StatelessWidget {
  const _ReceivableRow({required this.item, required this.money});

  final ReceivableItem item;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Row(
      children: <Widget>[
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: Color(0xFFC62828),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            item.customerName,
            style: theme.textTheme.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          money.format(item.balance),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.error,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Reports banner
// ============================================================================

class _ReportsBanner extends StatelessWidget {
  const _ReportsBanner();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.pushNamed(AppRouter.reportsName),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[scheme.primary, scheme.tertiary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.analytics_outlined,
                    color: scheme.onPrimary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'التقارير',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'مبيعات · مخزون · أرباح · مدينون',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
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
      ),
    );
  }
}

// ============================================================================
// Section header + card
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final Widget child;
  final Widget? trailing;

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
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _SeeAllLink extends StatelessWidget {
  const _SeeAllLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_left,
              size: 14,
              color: scheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Infrastructure footer
// ============================================================================

class _InfrastructureFooter extends StatelessWidget {
  const _InfrastructureFooter({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: <Widget>[
          Icon(
            config.isSupabaseConfigured
                ? Icons.cloud_done_outlined
                : Icons.cloud_off_outlined,
            size: 16,
            color: config.isSupabaseConfigured
                ? scheme.primary
                : scheme.error,
          ),
          const SizedBox(width: 6),
          Text(
            config.isSupabaseConfigured
                ? 'متصل بالخادم'
                : 'غير متصل بالخادم',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            'v0.1.0',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

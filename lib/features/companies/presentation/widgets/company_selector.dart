// lib/features/companies/presentation/widgets/company_selector.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/responsive_helper.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../domain/entities/company.dart';
import '../../domain/repositories/company_repository.dart';
import '../providers/company_context_provider.dart';
import '../providers/company_context_state.dart';

/// Displays the current company and lets the user switch to another one.
///
/// The widget mirrors [CompanyContextState] directly:
/// * while loading companies → a loader;
/// * on failure              → an error view with retry;
/// * with no companies       → an empty view;
/// * otherwise               → a card showing the current company, which is
///   tappable only when the user has more than one accessible company.
///
/// It contains no authorization logic: the notifier rejects any selection
/// that is not part of the authorized list.
class CompanySelector extends ConsumerWidget {
  const CompanySelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CompanyContextState state = ref.watch(companyContextProvider);

    if (state.isInitial || state.isLoadingCompanies) {
      return const _SelectorShell(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: AppLoader(),
        ),
      );
    }

    if (state.hasCompaniesError) {
      return _SelectorShell(
        child: AppErrorView(
          title: 'تعذّر تحميل الشركات',
          message: _companyFailureMessage(state.companiesFailure),
          retryLabel: 'إعادة المحاولة',
          onRetry: () => ref.read(companyContextProvider.notifier).refresh(),
        ),
      );
    }

    if (state.hasNoCompanies) {
      return _SelectorShell(
        child: AppEmptyView(
          icon: Icons.apartment_outlined,
          title: 'لا توجد شركات',
          message:
              'حسابك غير مرتبط بأي شركة حتى الآن. تواصل مع مسؤول النظام لإضافتك إلى شركة.',
          action: AppButton(
            label: 'تحديث',
            icon: Icons.refresh,
            variant: AppButtonVariant.outline,
            onPressed: () =>
                ref.read(companyContextProvider.notifier).refresh(),
          ),
        ),
      );
    }

    final Company? currentCompany = state.currentCompany;
    final bool canSwitch = state.companies.length > 1;

    if (currentCompany == null) {
      // Multiple companies, none selected: prompt for an explicit choice.
      return _SelectorShell(
        child: _NoSelectionCard(
          title: 'اختر الشركة',
          message: 'لديك أكثر من شركة. اختر الشركة التي تريد العمل عليها.',
          actionLabel: 'اختيار شركة',
          onPressed: () => _showCompanyPicker(context, ref),
        ),
      );
    }

    return _SelectorShell(
      child: _CurrentCompanyCard(
        company: currentCompany,
        totalCompanies: state.companies.length,
        onTap: canSwitch ? () => _showCompanyPicker(context, ref) : null,
      ),
    );
  }

  Future<void> _showCompanyPicker(BuildContext context, WidgetRef ref) async {
    final CompanyContextNotifier notifier =
        ref.read(companyContextProvider.notifier);
    final CompanyContextState state = ref.read(companyContextProvider);
    final List<Company> companies = state.companies;
    final String? currentId = state.currentCompany?.id;

    final Company? selected = await showModalBottomSheet<Company>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        final DeviceType deviceType = sheetContext.deviceType;
        final double horizontalPadding =
            ResponsiveHelper.horizontalPadding(deviceType);

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              8,
              horizontalPadding,
              16 + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'اختر الشركة',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                  textAlign: TextAlign.start,
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: companies.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (BuildContext itemContext, int index) {
                      final Company company = companies[index];
                      final bool isCurrent = company.id == currentId;
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        leading: CircleAvatar(
                          child: Text(
                            company.name.characters.first.toUpperCase(),
                          ),
                        ),
                        title: Text(company.name),
                        subtitle: Text(company.currency),
                        trailing: isCurrent
                            ? const Icon(Icons.check_circle_outline)
                            : null,
                        selected: isCurrent,
                        onTap: () =>
                            Navigator.of(sheetContext).pop(company),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null && selected.id != currentId) {
      await notifier.selectCompany(selected);
    }
  }
}

// -----------------------------------------------------------------------------
// Internal layout helpers
// -----------------------------------------------------------------------------

/// Common padded container so all states share identical outer geometry.
class _SelectorShell extends StatelessWidget {
  const _SelectorShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: child,
    );
  }
}

class _CurrentCompanyCard extends StatelessWidget {
  const _CurrentCompanyCard({
    required this.company,
    required this.totalCompanies,
    required this.onTap,
  });

  final Company company;
  final int totalCompanies;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool interactive = onTap != null;

    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: Text(company.name.characters.first.toUpperCase()),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      company.name,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      totalCompanies > 1
                          ? '${company.currency} • $totalCompanies شركات متاحة'
                          : company.currency,
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (interactive)
                Icon(
                  Icons.expand_more,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoSelectionCard extends StatelessWidget {
  const _NoSelectionCard({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onPressed,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.apartment_outlined, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(message, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton(
                label: actionLabel,
                icon: Icons.swap_horiz,
                variant: AppButtonVariant.secondary,
                onPressed: onPressed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Arabic message for a company-list failure.
///
/// Kept local to this widget pending migration into `AppLocalizations`,
/// which is out of scope for Phase 3.
String _companyFailureMessage(CompanyFailureType? type) => switch (type) {
      CompanyFailureType.network =>
        'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.',
      CompanyFailureType.unauthorized =>
        'انتهت صلاحية الجلسة أو لا تملك صلاحية للوصول. يرجى تسجيل الدخول مجددًا.',
      CompanyFailureType.noCompanies =>
        'حسابك غير مرتبط بأي شركة حتى الآن.',
      CompanyFailureType.companyNotAccessible =>
        'لا تملك صلاحية الوصول إلى هذه الشركة.',
      CompanyFailureType.noBranches =>
        'لا توجد فروع متاحة في هذه الشركة.',
      CompanyFailureType.invalidResponse =>
        'تعذّر قراءة بيانات الشركات. يرجى المحاولة لاحقًا.',
      CompanyFailureType.unknown ||
      null =>
        'حدث خطأ غير متوقع أثناء تحميل الشركات. يرجى المحاولة مرة أخرى.',
    };

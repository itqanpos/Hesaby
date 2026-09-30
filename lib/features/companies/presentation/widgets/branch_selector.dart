// lib/features/companies/presentation/widgets/branch_selector.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/responsive_helper.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../domain/entities/branch.dart';
import '../../domain/repositories/company_repository.dart';
import '../providers/company_context_provider.dart';
import '../providers/company_context_state.dart';

/// Displays the current branch of the selected company and lets the user
/// switch to another branch.
///
/// Mirrors [CompanyContextState] for the branch level:
/// * no company selected     → renders nothing;
/// * branches loading        → a loader;
/// * branch load failure     → an error view with retry;
/// * no accessible branches  → an empty view;
/// * otherwise               → a card showing the current branch, tappable
///   only when the user has more than one accessible branch.
///
/// Authorization is not enforced here: the notifier rejects any selection
/// that is not part of the authorized branch list for the current company.
class BranchSelector extends ConsumerWidget {
  const BranchSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CompanyContextState state = ref.watch(companyContextProvider);

    // A branch has no meaning without a parent company.
    if (state.currentCompany == null) {
      return const SizedBox.shrink();
    }

    if (state.isLoadingBranches) {
      return const _SelectorShell(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: AppLoader(),
        ),
      );
    }

    final CompanyFailureType? failure = state.branchesFailure;
    if (failure != null) {
      return _SelectorShell(
        child: AppErrorView(
          title: 'تعذّر تحميل الفروع',
          message: _branchFailureMessage(failure),
          retryLabel: 'إعادة المحاولة',
          onRetry: () => ref.read(companyContextProvider.notifier).refresh(),
        ),
      );
    }

    if (state.hasNoBranches) {
      return _SelectorShell(
        child: AppEmptyView(
          icon: Icons.store_mall_directory_outlined,
          title: 'لا توجد فروع',
          message:
              'لا توجد فروع متاحة في الشركة المختارة حتى الآن. '
              'تواصل مع مسؤول الشركة لإضافة فرع.',
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

    final Branch? currentBranch = state.currentBranch;
    final bool canSwitch = state.branches.length > 1;

    if (currentBranch == null) {
      // Multiple branches, none selected: prompt for an explicit choice.
      return _SelectorShell(
        child: _NoSelectionCard(
          title: 'اختر الفرع',
          message:
              'لديك أكثر من فرع في هذه الشركة. اختر الفرع الذي تريد العمل عليه.',
          actionLabel: 'اختيار فرع',
          onPressed: () => _showBranchPicker(context, ref),
        ),
      );
    }

    return _SelectorShell(
      child: _CurrentBranchCard(
        branch: currentBranch,
        totalBranches: state.branches.length,
        onTap: canSwitch ? () => _showBranchPicker(context, ref) : null,
      ),
    );
  }

  Future<void> _showBranchPicker(BuildContext context, WidgetRef ref) async {
    final CompanyContextNotifier notifier = ref.read(
      companyContextProvider.notifier,
    );
    final CompanyContextState state = ref.read(companyContextProvider);
    final List<Branch> branches = state.branches;
    final String? currentId = state.currentBranch?.id;

    if (branches.isEmpty) {
      return;
    }

    final Branch? selected = await showModalBottomSheet<Branch>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        final DeviceType deviceType = sheetContext.deviceType;
        final double horizontalPadding = ResponsiveHelper.horizontalPadding(
          deviceType,
        );

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
                  'اختر الفرع',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                  textAlign: TextAlign.start,
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: branches.length,
                    // `__` is used rather than a repeated `_`, because
                    // wildcard parameters (multiple `_`) require Dart 3.7+,
                    // while this project targets Dart 3.5.
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (BuildContext itemContext, int index) {
                      final Branch branch = branches[index];
                      final bool isCurrent = branch.id == currentId;
                      final String? code = branch.code;
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        leading: const CircleAvatar(
                          child: Icon(Icons.store_mall_directory_outlined),
                        ),
                        title: Text(branch.name),
                        subtitle: code == null ? null : Text(code),
                        trailing: isCurrent
                            ? const Icon(Icons.check_circle_outline)
                            : null,
                        selected: isCurrent,
                        onTap: () => Navigator.of(sheetContext).pop(branch),
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
      await notifier.selectBranch(selected);
    }
  }
}

// -----------------------------------------------------------------------------
// Internal layout helpers
// -----------------------------------------------------------------------------

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

class _CurrentBranchCard extends StatelessWidget {
  const _CurrentBranchCard({
    required this.branch,
    required this.totalBranches,
    required this.onTap,
  });

  final Branch branch;
  final int totalBranches;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool interactive = onTap != null;
    final String? code = branch.code;

    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.store_mall_directory_outlined,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      branch.name,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(code, totalBranches),
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (interactive)
                Icon(Icons.expand_more, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  static String _subtitle(String? code, int totalBranches) {
    final String countLabel = '$totalBranches فروع متاحة';
    if (code == null) {
      return countLabel;
    }
    return '$code • $countLabel';
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
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.store_mall_directory_outlined,
                  color: scheme.primary,
                ),
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

/// Arabic message for a branch-list failure.
///
/// Kept local to this widget pending migration into `AppLocalizations`,
/// which is out of scope for Phase 3.
String _branchFailureMessage(CompanyFailureType type) => switch (type) {
  CompanyFailureType.network =>
    'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.',
  CompanyFailureType.unauthorized =>
    'انتهت صلاحية الجلسة أو لا تملك صلاحية للوصول. '
        'يرجى تسجيل الدخول مجددًا.',
  CompanyFailureType.noCompanies => 'حسابك غير مرتبط بأي شركة حتى الآن.',
  CompanyFailureType.companyNotAccessible =>
    'لا تملك صلاحية الوصول إلى فروع هذه الشركة.',
  CompanyFailureType.noBranches => 'لا توجد فروع متاحة في هذه الشركة.',
  CompanyFailureType.invalidResponse =>
    'تعذّر قراءة بيانات الفروع. يرجى المحاولة لاحقًا.',
  CompanyFailureType.unknown =>
    'حدث خطأ غير متوقع أثناء تحميل الفروع. يرجى المحاولة مرة أخرى.',
};

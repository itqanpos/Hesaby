// lib/features/companies/presentation/pages/branches_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../domain/entities/branch.dart';
import '../../domain/repositories/company_repository.dart';
import '../providers/company_context_provider.dart';
import '../providers/company_context_state.dart';

/// Branches management page.
///
/// Shows every branch of the currently selected company — active and
/// inactive — so deactivated branches remain reachable and can be
/// reactivated. Creating, editing and toggling is restricted server-side by
/// RLS to `owner` and `admin` roles; other roles receive a translated
/// "unauthorized" message.
class BranchesPage extends ConsumerWidget {
  const BranchesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CompanyContextState contextState =
        ref.watch(companyContextProvider);
    final AsyncValue<List<Branch>> branchesAsync =
        ref.watch(companyAllBranchesProvider);

    if (contextState.currentCompany == null) {
      return AppShell(
        appBar: AppBar(title: const Text('الفروع')),
        body: contextState.isLoadingCompanies
            ? const AppLoader()
            : const AppEmptyView(
                icon: Icons.business_outlined,
                title: 'لا توجد شركة محددة',
                message: 'اختر شركة من الصفحة الرئيسية ثم عد إلى هنا.',
              ),
      );
    }

    return AppShell(
      appBar: AppBar(title: const Text('الفروع')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.pushNamed(AppRouter.branchNewName),
        icon: const Icon(Icons.add),
        label: const Text('إضافة فرع'),
      ),
      body: branchesAsync.when(
        loading: () => const AppLoader(),
        error: (Object error, StackTrace _) => AppErrorView(
          title: 'تعذّر تحميل الفروع',
          message: _errorMessage(error),
          retryLabel: 'إعادة المحاولة',
          onRetry: () => ref.invalidate(companyAllBranchesProvider),
        ),
        data: (List<Branch> branches) {
          if (branches.isEmpty) {
            return AppEmptyView(
              icon: Icons.store_mall_directory_outlined,
              title: 'لا توجد فروع بعد',
              message:
                  'ابدأ بإضافة أول فرع للشركة ليتمكن المستخدمون من العمل عليه.',
              action: AppButton(
                label: 'إضافة فرع',
                icon: Icons.add,
                onPressed: () =>
                    context.pushNamed(AppRouter.branchNewName),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.only(
              top: 8,
              bottom: 96,
            ),
            itemCount: branches.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (BuildContext itemContext, int index) {
              final Branch branch = branches[index];
              return _BranchCard(
                branch: branch,
                onEdit: () => context.pushNamed(
                  AppRouter.branchEditName,
                  pathParameters: <String, String>{'id': branch.id},
                ),
                onToggleActive: () => _toggleActive(
                  context,
                  ref,
                  branches,
                  branch,
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Toggle active
  // ---------------------------------------------------------------------------

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    List<Branch> allBranches,
    Branch branch,
  ) async {
    final bool targetActive = !branch.isActive;

    // Guard: never allow deactivating the last active branch. The DB has no
    // equivalent constraint, so the rule lives here.
    if (!targetActive) {
      final int activeCount =
          allBranches.where((Branch b) => b.isActive).length;
      if (activeCount <= 1) {
        _showSnack(
          context,
          'لا يمكن تعطيل آخر فرع نشط. أضف فرعًا آخر أو فعّل فرعًا قبل ذلك.',
        );
        return;
      }

      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('تعطيل الفرع'),
          content: Text(
            'سيتم تعطيل "${branch.name}". '
            'لن يظهر في شاشات البيع والتقارير بعد ذلك.',
          ),
          actions: <Widget>[
            AppButton(
              label: 'إلغاء',
              variant: AppButtonVariant.text,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            AppButton(
              label: 'تعطيل',
              variant: AppButtonVariant.danger,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return;
      }
    }

    try {
      await ref
          .read(companyContextProvider.notifier)
          .setBranchActive(
            branchId: branch.id,
            isActive: targetActive,
          );
      if (!context.mounted) {
        return;
      }
      _showSnack(
        context,
        targetActive ? 'تم تفعيل الفرع.' : 'تم تعطيل الفرع.',
      );
    } on CompanyException catch (error) {
      if (!context.mounted) {
        return;
      }
      _showSnack(context, _failureMessage(error.type));
    } on Object {
      if (!context.mounted) {
        return;
      }
      _showSnack(context, 'تعذّر تحديث حالة الفرع. حاول مرة أخرى.');
    }
  }

  static void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

// ============================================================================
// Branch card
// ============================================================================

class _BranchCard extends StatelessWidget {
  const _BranchCard({
    required this.branch,
    required this.onEdit,
    required this.onToggleActive,
  });

  final Branch branch;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isActive = branch.isActive;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (isActive ? scheme.primary : scheme.onSurfaceVariant)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.store_mall_directory_outlined,
                  size: 20,
                  color: isActive
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            branch.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isActive
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!isActive)
                          _InactiveBadge(scheme: scheme),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(branch),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<_BranchAction>(
                tooltip: 'خيارات',
                icon: const Icon(Icons.more_vert),
                onSelected: (_BranchAction action) {
                  switch (action) {
                    case _BranchAction.edit:
                      onEdit();
                    case _BranchAction.activate:
                    case _BranchAction.deactivate:
                      onToggleActive();
                  }
                },
                itemBuilder: (BuildContext _) => <PopupMenuEntry<_BranchAction>>[
                  const PopupMenuItem<_BranchAction>(
                    value: _BranchAction.edit,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('تعديل'),
                    ),
                  ),
                  if (isActive)
                    const PopupMenuItem<_BranchAction>(
                      value: _BranchAction.deactivate,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.block_outlined),
                        title: Text('تعطيل'),
                      ),
                    )
                  else
                    const PopupMenuItem<_BranchAction>(
                      value: _BranchAction.activate,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.check_circle_outline),
                        title: Text('تفعيل'),
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

  static String _subtitle(Branch branch) {
    final List<String> parts = <String>[];
    if (branch.code != null) {
      parts.add(branch.code!);
    }
    if (branch.phone != null) {
      parts.add(branch.phone!);
    }
    if (branch.address != null) {
      parts.add(branch.address!);
    }
    if (parts.isEmpty) {
      return 'لا توجد تفاصيل إضافية';
    }
    return parts.join(' • ');
  }
}

enum _BranchAction { edit, activate, deactivate }

class _InactiveBadge extends StatelessWidget {
  const _InactiveBadge({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          'معطّل',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

// ============================================================================
// Localization
// ============================================================================

String _errorMessage(Object error) {
  if (error is CompanyException) {
    return _failureMessage(error.type);
  }
  return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
}

String _failureMessage(CompanyFailureType type) {
  switch (type) {
    case CompanyFailureType.network:
      return 'تعذّر الاتصال بالخادم. تحقق من اتصالك بالإنترنت.';
    case CompanyFailureType.unauthorized:
      return 'ليس لديك صلاحية لإدارة الفروع. '
          'تواصل مع المالك أو المدير.';
    case CompanyFailureType.noCompanies:
      return 'لم يتم العثور على شركات مرتبطة بحسابك.';
    case CompanyFailureType.companyNotAccessible:
      return 'لا يمكن الوصول إلى فروع هذه الشركة.';
    case CompanyFailureType.noBranches:
      return 'لا توجد فروع متاحة.';
    case CompanyFailureType.invalidResponse:
      return 'تعذّر قراءة بيانات الفروع. يرجى المحاولة لاحقًا.';
    case CompanyFailureType.unknown:
      return 'تعذّر إتمام العملية. حاول مرة أخرى.';
  }
}

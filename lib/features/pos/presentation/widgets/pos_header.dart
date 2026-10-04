// lib/features/pos/presentation/widgets/pos_header.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../companies/domain/entities/branch.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';

/// POS header — compact AppBar with the current branch as a subtitle.
///
/// Layout:
/// * First line: "نقطة البيع".
/// * Second line: the active branch name (ellipsised if too long).
/// * Action (only when the company has more than one branch): a small
///   icon that opens a bottom sheet to pick another branch.
///
/// The back button is left to the default [AppBar] behaviour: it appears
/// automatically when the route was pushed onto the stack.
class PosHeader extends ConsumerWidget implements PreferredSizeWidget {
  const PosHeader({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final CompanyContextState state = ref.watch(companyContextProvider);

    final String branchName = state.currentBranch?.name ?? 'لا يوجد فرع';
    final bool canSwitch = state.branches.length > 1;

    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'نقطة البيع',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            branchName,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: <Widget>[
        if (canSwitch)
          IconButton(
            tooltip: 'تغيير الفرع',
            icon: const Icon(Icons.store_outlined),
            onPressed: () => _openBranchPicker(context, ref),
          )
        else
          const SizedBox(width: 8),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Branch picker
  // ---------------------------------------------------------------------------

  Future<void> _openBranchPicker(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final CompanyContextState state = ref.read(companyContextProvider);
    final List<Branch> branches = state.branches;
    final String? currentId = state.currentBranch?.id;

    if (branches.length < 2) {
      return;
    }

    final Branch? selected = await showModalBottomSheet<Branch>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        final ThemeData theme = Theme.of(sheetContext);

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'اختر الفرع',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: branches.length,
                  itemBuilder: (BuildContext itemContext, int index) {
                    final Branch branch = branches[index];
                    final bool isCurrent = branch.id == currentId;
                    final String? code = branch.code;

                    return ListTile(
                      leading: const Icon(
                        Icons.store_mall_directory_outlined,
                      ),
                      title: Text(branch.name),
                      subtitle: code == null ? null : Text(code),
                      trailing: isCurrent
                          ? const Icon(Icons.check_circle_outline)
                          : null,
                      selected: isCurrent,
                      onTap: () =>
                          Navigator.of(sheetContext).pop(branch),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selected == null || selected.id == currentId) {
      return;
    }

    await ref
        .read(companyContextProvider.notifier)
        .selectBranch(selected);
  }
}

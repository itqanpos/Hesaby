// lib/features/companies/presentation/pages/member_permissions_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../domain/entities/company_member.dart';
import '../../domain/entities/member_permission.dart';
import '../../domain/repositories/company_members_repository.dart';
import '../providers/members_providers.dart';
import '../widgets/permission_group_card.dart';

/// Permissions editor for a single member.
///
/// The model is a deny-list: the local `_denied` set holds the codes the
/// manager wants to revoke. On save, the set replaces the member's stored
/// `denied_permissions` array.
class MemberPermissionsPage extends ConsumerStatefulWidget {
  const MemberPermissionsPage({super.key, required this.memberId});

  final String memberId;

  @override
  ConsumerState<MemberPermissionsPage> createState() =>
      _MemberPermissionsPageState();
}

class _MemberPermissionsPageState
    extends ConsumerState<MemberPermissionsPage> {
  /// Working copy of the deny-list, mutated as the manager toggles.
  Set<String> _denied = <String>{};

  /// Snapshot at page-open time, used to detect unsaved changes.
  Set<String> _initialDenied = <String>{};

  /// Id of the member we already initialized from. Ensures initialization
  /// happens exactly once per member.
  String? _initializedFor;

  bool _isSaving = false;

  bool get _hasChanges {
    if (_denied.length != _initialDenied.length) return true;
    for (final String code in _denied) {
      if (!_initialDenied.contains(code)) return true;
    }
    return false;
  }

  void _ensureInitialized(CompanyMember member) {
    if (_initializedFor == member.id) return;
    _initializedFor = member.id;
    _initialDenied = Set<String>.of(member.deniedPermissions);
    _denied = Set<String>.of(member.deniedPermissions);
  }

  // ---------------------------------------------------------------------------
  // Toggles
  // ---------------------------------------------------------------------------

  void _onToggle(String code, bool granted) {
    setState(() {
      if (granted) {
        _denied.remove(code);
      } else {
        _denied.add(code);
      }
    });
  }

  void _onToggleAll(PermissionGroup group, bool grantAll) {
    setState(() {
      if (grantAll) {
        for (final String code in group.permissions) {
          _denied.remove(code);
        }
      } else {
        for (final String code in group.permissions) {
          _denied.add(code);
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  Future<void> _save(CompanyMember member) async {
    setState(() => _isSaving = true);
    try {
      await ref.read(membersProvider.notifier).updateMember(
            memberId: member.id,
            deniedPermissions: _denied.toList(growable: false),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تم حفظ الصلاحيات.')),
        );
      if (context.mounted) context.pop();
    } on MemberException catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(_errorMessage(error))),
        );
    } on Object {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تعذّر الحفظ. حاول مرة أخرى.')),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<CompanyMember>> membersAsync =
        ref.watch(membersProvider);

    return AppShell(
      appBar: AppBar(
        title: const Text('الصلاحيات'),
        actions: <Widget>[
          membersAsync.maybeWhen(
            data: (List<CompanyMember> members) {
              final CompanyMember? member = _findMember(members);
              if (member == null || member.isOwner) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: TextButton(
                  onPressed: !_hasChanges || _isSaving
                      ? null
                      : () => _save(member),
                  child: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('حفظ'),
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: membersAsync.when(
        loading: () => const AppLoader(),
        error: (Object error, StackTrace _) => AppErrorView(
          title: 'تعذّر تحميل الأعضاء',
          message: 'حاول مرة أخرى.',
          retryLabel: 'إعادة المحاولة',
          onRetry: () =>
              ref.read(membersProvider.notifier).refresh(),
        ),
        data: (List<CompanyMember> members) {
          final CompanyMember? member = _findMember(members);
          if (member == null) {
            return const AppErrorView(
              title: 'العضو غير موجود',
              message: 'ربما تم حذفه أو إزالته من الشركة.',
            );
          }

          _ensureInitialized(member);

          // Owners are protected by a DB trigger — no permission edits.
          if (member.isOwner) {
            return _OwnerInfoBody(member: member);
          }

          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 32),
            children: <Widget>[
              _MemberHeaderCard(member: member),
              const SizedBox(height: 12),
              _NoticeCard(),
              const SizedBox(height: 16),
              for (final PermissionGroup group in kPermissionGroups) ...<Widget>[
                PermissionGroupCard(
                  group: group,
                  denied: _denied,
                  enabled: !_isSaving,
                  onToggle: _onToggle,
                  onToggleAll: (bool grantAll) =>
                      _onToggleAll(group, grantAll),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }

  CompanyMember? _findMember(List<CompanyMember> members) {
    for (final CompanyMember m in members) {
      if (m.id == widget.memberId) return m;
    }
    return null;
  }

  static String _errorMessage(MemberException error) {
    switch (error.type) {
      case MemberFailureType.network:
        return 'تعذّر الاتصال بالخادم.';
      case MemberFailureType.unauthorized:
        return 'ليس لديك صلاحية لتعديل الصلاحيات.';
      case MemberFailureType.cannotModifyOwner:
        return 'لا يمكن تعديل صلاحيات المالك.';
      case MemberFailureType.lastOwnerProtection:
        return 'لا يمكن إزالة آخر مالك للشركة.';
      default:
        return 'تعذّر الحفظ. حاول مرة أخرى.';
    }
  }
}

// ============================================================================
// Header
// ============================================================================

class _MemberHeaderCard extends StatelessWidget {
  const _MemberHeaderCard({required this.member});

  final CompanyMember member;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final String displayName = member.displayName?.trim().isNotEmpty == true
        ? member.displayName!.trim()
        : (member.email?.split('@').first ?? 'مستخدم');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
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
                    displayName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (member.email != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      member.email!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'الدور: ${MemberRole.label(member.role)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Notice
// ============================================================================

class _NoticeCard extends StatelessWidget {
  const _NoticeCard();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.info_outline,
              size: 18,
              color: scheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'كل الصلاحيات مفعّلة افتراضيًا. ألغِ ما لا تريده '
                'لهذا العضو ثم اضغط "حفظ".',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Owner body (read-only)
// ============================================================================

class _OwnerInfoBody extends StatelessWidget {
  const _OwnerInfoBody({required this.member});

  final CompanyMember member;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.shield_outlined,
              size: 56,
              color: scheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'المالك',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'المالك يمتلك جميع الصلاحيات دائمًا، ولا يمكن '
              'إلغاء أي منها. هذه حماية مدمجة لمنع قفل الشركة.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

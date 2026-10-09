// lib/features/companies/presentation/pages/members_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/entities/company_member.dart';
import '../../domain/repositories/company_members_repository.dart';
import '../providers/members_providers.dart';

/// Members management page.
///
/// Lists every member of the currently selected company, with their role
/// and the number of permissions denied to them. Tapping a member opens
/// the permissions editor. Only owner/admin/manager can reach this page —
/// the underlying RLS rejects other roles.
class MembersPage extends ConsumerStatefulWidget {
  const MembersPage({super.key});

  @override
  ConsumerState<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends ConsumerState<MembersPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CompanyMember> _filter(List<CompanyMember> members) {
    final String q = _query.trim().toLowerCase();
    if (q.isEmpty) return members;
    return members.where((CompanyMember m) {
      final String name = (m.displayName ?? '').toLowerCase();
      final String email = (m.email ?? '').toLowerCase();
      final String phone = (m.phone ?? '').toLowerCase();
      return name.contains(q) || email.contains(q) || phone.contains(q);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<CompanyMember>> membersAsync =
        ref.watch(membersProvider);

    return AppShell(
      appBar: AppBar(
        title: const Text('الأعضاء والصلاحيات'),
        actions: <Widget>[
          IconButton(
            tooltip: 'تحديث',
            onPressed: () =>
                ref.read(membersProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: membersAsync.when(
        loading: () => const AppLoader(),
        error: (Object error, StackTrace _) => AppErrorView(
          title: 'تعذّر تحميل الأعضاء',
          message: _errorMessage(error),
          retryLabel: 'إعادة المحاولة',
          onRetry: () =>
              ref.read(membersProvider.notifier).refresh(),
        ),
        data: (List<CompanyMember> members) {
          final List<CompanyMember> visible = _filter(members);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 8),
              _KpiRow(members: members),
              const SizedBox(height: 12),
              AppTextField(
                controller: _searchController,
                hint: 'ابحث بالاسم أو البريد أو الهاتف',
                prefixIcon: Icons.search,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'مسح',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                onChanged: (String v) => setState(() => _query = v),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: members.isEmpty
                    ? const AppEmptyView(
                        icon: Icons.people_outline,
                        title: 'لا يوجد أعضاء',
                        message: 'لم يُعثر على أي عضو في هذه الشركة.',
                      )
                    : visible.isEmpty
                        ? const AppEmptyView(
                            icon: Icons.search_off_outlined,
                            title: 'لا نتائج',
                            message: 'لم يُطابق أي عضو كلمة البحث.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: visible.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder:
                                (BuildContext context, int index) {
                              final CompanyMember member = visible[index];
                              return _MemberCard(
                                member: member,
                                onTap: () => context.pushNamed(
                                  AppRouter.memberPermissionsName,
                                  pathParameters: <String, String>{
                                    'id': member.id,
                                  },
                                ),
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

  static String _errorMessage(Object error) {
    if (error is MemberException) {
      switch (error.type) {
        case MemberFailureType.network:
          return 'تعذّر الاتصال بالخادم.';
        case MemberFailureType.unauthorized:
          return 'ليس لديك صلاحية لعرض الأعضاء.';
        case MemberFailureType.notFound:
          return 'لم يُعثر على الشركة.';
        default:
          return 'تعذّر تحميل الأعضاء.';
      }
    }
    return 'تعذّر تحميل الأعضاء.';
  }
}

// ============================================================================
// KPI row
// ============================================================================

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.members});

  final List<CompanyMember> members;

  @override
  Widget build(BuildContext context) {
    int active = 0;
    int inactive = 0;
    for (final CompanyMember m in members) {
      if (m.isActive) {
        active++;
      } else {
        inactive++;
      }
    }

    return Row(
      children: <Widget>[
        Expanded(
          child: _KpiCard(
            icon: Icons.groups_outlined,
            color: const Color(0xFF0288D1),
            label: 'الإجمالي',
            value: members.length.toString(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            icon: Icons.check_circle_outline,
            color: const Color(0xFF0F7B6C),
            label: 'نشط',
            value: active.toString(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            icon: Icons.pause_circle_outline,
            color: const Color(0xFF7B5E3A),
            label: 'معطّل',
            value: inactive.toString(),
            emphasize: inactive > 0,
          ),
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
    this.emphasize = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: emphasize
              ? color.withValues(alpha: 0.5)
              : scheme.outlineVariant,
          width: emphasize ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, size: 14, color: color),
                ),
                const SizedBox(width: 6),
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
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: emphasize ? color : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Member card
// ============================================================================

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member, required this.onTap});

  final CompanyMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final String displayName = _displayName(member);
    final String? email = member.email;
    final (Color roleBg, Color roleFg) = _roleColors(scheme, member.role);

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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 20,
                backgroundColor: member.isActive
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                foregroundColor: member.isActive
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
                child: Text(
                  displayName.characters.first.toUpperCase(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
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
                            displayName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!member.isActive)
                          _Chip(
                            label: 'معطّل',
                            background: scheme.surfaceContainerHighest,
                            foreground: scheme.onSurfaceVariant,
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    if (email != null && email.isNotEmpty)
                      Text(
                        email,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        _Chip(
                          label: MemberRole.label(member.role),
                          background: roleBg,
                          foreground: roleFg,
                        ),
                        if (member.deniedCount > 0) ...<Widget>[
                          const SizedBox(width: 6),
                          _Chip(
                            label: '${member.deniedCount} مُلغاة',
                            background: scheme.errorContainer,
                            foreground: scheme.onErrorContainer,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
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

  static String _displayName(CompanyMember member) {
    final String? name = member.displayName;
    if (name != null && name.trim().isNotEmpty) {
      return name.trim();
    }
    final String? email = member.email;
    if (email != null && email.trim().isNotEmpty) {
      return email.split('@').first;
    }
    final String id = member.userId;
    return id.length > 6 ? 'مستخدم ${id.substring(id.length - 6)}' : id;
  }

  static (Color, Color) _roleColors(ColorScheme scheme, String role) {
    switch (role) {
      case MemberRole.owner:
        return (
          const Color(0xFFF57F17).withValues(alpha: 0.15),
          const Color(0xFFF57F17),
        );
      case MemberRole.admin:
        return (
          const Color(0xFF6A1B9A).withValues(alpha: 0.15),
          const Color(0xFF6A1B9A),
        );
      case MemberRole.manager:
        return (
          const Color(0xFF00838F).withValues(alpha: 0.15),
          const Color(0xFF00838F),
        );
      case MemberRole.cashier:
        return (
          const Color(0xFF0F7B6C).withValues(alpha: 0.15),
          const Color(0xFF0F7B6C),
        );
      case MemberRole.inventoryClerk:
        return (
          const Color(0xFF5D4037).withValues(alpha: 0.15),
          const Color(0xFF5D4037),
        );
      default:
        return (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        );
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// lib/features/admin/presentation/pages/tabs/admin_users_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../shared/widgets/app_empty.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loader.dart';
import '../../../../../shared/widgets/app_text_field.dart';

// ============================================================================
// Models
// ============================================================================

class AdminUserCompany {
  const AdminUserCompany({
    required this.companyId,
    required this.companyName,
    required this.role,
  });

  final String companyId;
  final String companyName;
  final String role;
}

class AdminUser {
  const AdminUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.isAdmin,
    required this.createdAt,
    required this.companies,
  });

  final String id;
  final String fullName;
  final String email;
  final bool isAdmin;
  final DateTime createdAt;
  final List<AdminUserCompany> companies;
}

// ============================================================================
// Provider
// ============================================================================

/// Fetches all users (profiles), their emails, and their company roles.
/// 
/// Note: To get the email, this assumes the backend exposes it via a view or RPC.
/// If it fails, it falls back to the user_id.
final adminUsersProvider = FutureProvider.autoDispose<List<AdminUser>>((ref) async {
  final client = Supabase.instance.client;

  // 1. Fetch all profiles (RLS allows platform admin to select all).
  // Assuming the table has user_id, full_name, created_at, is_platform_admin.
  // We might need to join with an RPC to get the email from auth.users.
  // For now, let's fetch profiles and company_members in parallel.
  
  final profilesResponse = await client
      .from('profiles')
      .select('user_id, full_name, is_platform_admin, created_at')
      .order('created_at', ascending: false);

  final membersResponse = await client
      .from('company_members')
      .select('user_id, role, companies(name)');

  // Group memberships by user_id
  final Map<String, List<AdminUserCompany>> memberships = {};
  for (final row in membersResponse as List) {
    final userId = row['user_id'] as String;
    final companyData = row['companies'] as Map<String, dynamic>?;
    
    if (companyData != null) {
      final companyName = companyData['name'] as String? ?? 'شركة محذوفة';
      final role = row['role'] as String? ?? 'عضو';
      
      memberships.putIfAbsent(userId, () => []).add(
        AdminUserCompany(
          companyId: companyData['id']?.toString() ?? '',
          companyName: companyName,
          role: role,
        ),
      );
    }
  }

  // Build the final list
  final List<AdminUser> users = [];
  for (final p in profilesResponse as List) {
    final userId = p['user_id'] as String;
    // Note: If email is not in profiles, we use a placeholder. 
    // We will fix this in the DB migration step.
    final email = p['email'] as String? ?? 'غير متوفر ($userId)'; 
    
    users.add(
      AdminUser(
        id: userId,
        fullName: p['full_name'] as String? ?? 'بدون اسم',
        email: email,
        isAdmin: p['is_platform_admin'] as bool? ?? false,
        createdAt: DateTime.parse(p['created_at'] as String),
        companies: memberships[userId] ?? [],
      ),
    );
  }

  return users;
});

// ============================================================================
// UI
// ============================================================================

class AdminUsersTab extends ConsumerStatefulWidget {
  const AdminUsersTab({super.key});

  @override
  ConsumerState<AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends ConsumerState<AdminUsersTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(adminUsersProvider);

    return usersAsync.when(
      loading: () => const AppLoader(),
      error: (Object error, StackTrace _) => AppErrorView(
        title: 'تعذّر تحميل المستخدمين',
        message: 'حدث خطأ أثناء جلب قائمة المشتركين.',
        retryLabel: 'إعادة المحاولة',
        onRetry: () => ref.invalidate(adminUsersProvider),
      ),
      data: (List<AdminUser> allUsers) {
        final filtered = allUsers.where((u) {
          final q = _searchQuery.trim().toLowerCase();
          if (q.isEmpty) return true;
          return u.fullName.toLowerCase().contains(q) ||
                 u.email.toLowerCase().contains(q);
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16),
              child: AppTextField(
                controller: _searchController,
                hint: 'ابحث بالاسم أو البريد الإلكتروني',
                prefixIcon: Icons.search,
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const AppEmptyView(
                      icon: Icons.people_outline,
                      title: 'لا يوجد مشتركون',
                      message: 'لم يتم العثور على مستخدمين يطابقون بحثك.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        return _UserCard(user: filtered[index]);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

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
              CircleAvatar(
                radius: 22,
                backgroundColor: user.isAdmin ? scheme.errorContainer : scheme.primaryContainer,
                foregroundColor: user.isAdmin ? scheme.onErrorContainer : scheme.onPrimaryContainer,
                child: Icon(
                  user.isAdmin ? Icons.security : Icons.person,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          user.fullName,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (user.isAdmin) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.error,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'أدمن',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      textDirection: TextDirection.ltr, // الإيميل بالإنجليزي
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (user.companies.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text('الشركات التابعة له:', style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: user.companies.map((c) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.storefront, size: 14, color: scheme.primary),
                      const SizedBox(width: 4),
                      Text('${c.companyName} (${c.role})', style: theme.textTheme.labelSmall),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

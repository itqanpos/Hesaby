// lib/features/admin/presentation/pages/admin_platform_team_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../data/services/admin_user_service.dart'; 
import 'tabs/admin_users_tab.dart'; // نستخدم نفس الموديل

// ✅ إنشاء مزود خاص بفريق المنصة (يستخدم الدالة الجديدة)
final platformTeamProvider = FutureProvider.autoDispose<List<AdminUser>>((ref) async {
  final client = Supabase.instance.client;
  final rpcResponse = await client.rpc('get_platform_team'); // ✅ استدعاء الدالة الجديدة
  
  List<dynamic> membersResponse = [];
  try {
    membersResponse = await client.from('company_members').select('user_id, role, companies(name)');
  } catch (_) {}

  final Map<String, List<AdminUserCompany>> memberships = {};
  for (final row in membersResponse) {
    final userId = row['user_id'] as String?;
    final companyData = row['companies'] as Map<String, dynamic>?;
    if (userId != null && companyData != null) {
      memberships.putIfAbsent(userId, () => []).add(
        AdminUserCompany(
          companyName: companyData['name'] as String? ?? 'شركة محذوفة',
          role: row['role'] as String? ?? 'عضو',
        ),
      );
    }
  }

  final List<AdminUser> users = [];
  if (rpcResponse is List) {
    for (final p in rpcResponse) {
      final map = p as Map<String, dynamic>;
      final userId = map['user_id'] as String?;
      if (userId == null) continue;
      
      users.add(
        AdminUser(
          id: userId,
          fullName: map['full_name'] as String? ?? 'بدون اسم',
          email: map['email'] as String? ?? 'غير متوفر',
          isAdmin: map['is_platform_admin'] as bool? ?? false,
          isStaff: map['is_platform_staff'] as bool? ?? false,
          isBanned: map['banned_until'] != null && DateTime.tryParse(map['banned_until'].toString())?.isAfter(DateTime.now()) == true,
          createdAt: _safeParseDate(map['created_at']),
          companies: memberships[userId] ?? [],
        ),
      );
    }
  }
  return users;
});

DateTime _safeParseDate(Object? value) {
  if (value == null) return DateTime.now();
  if (value is DateTime) return value;
  if (value is String) {
    DateTime? parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
    try {
      String normalized = value.trim();
      if (normalized.contains(' ')) normalized = normalized.replaceFirst(' ', 'T');
      if (normalized.endsWith('+00')) normalized = normalized.replaceAll('+00', 'Z');
      parsed = DateTime.tryParse(normalized);
      if (parsed != null) return parsed;
    } catch (_) {}
  }
  return DateTime.now();
}

class AdminPlatformTeamPage extends ConsumerStatefulWidget {
  const AdminPlatformTeamPage({super.key});

  @override
  ConsumerState<AdminPlatformTeamPage> createState() => _AdminPlatformTeamPageState();
}

class _AdminPlatformTeamPageState extends ConsumerState<AdminPlatformTeamPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showAddAdminDialog() async {
    final bool? created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AddPlatformAdminDialog(),
    );
    if (created == true) ref.invalidate(platformTeamProvider);
  }

  Future<void> _promoteExistingUser(AdminUser user) async {
    final bool? confirmed = await _showWarning(
      context,
      user.fullName,
      isRevoke: user.isAdmin,
    );
    if (confirmed != true) return;

    try {
      final service = AdminUserService(Supabase.instance.client);
      await service.updateUser(
        userId: user.id,
        isPlatformAdmin: !user.isAdmin, 
        isBanned: user.isBanned,
      );
      if (mounted) {
        ref.invalidate(platformTeamProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(user.isAdmin ? 'تم إلغاء صلاحية الأدمن' : 'تم ترقية المستخدم إلى أدمن'),
            backgroundColor: user.isAdmin ? Colors.orange : Colors.green,
          ),
        );
      }
    } on AdminUserException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(platformTeamProvider); // ✅ استخدام المزود الجديد

    return Scaffold(
      appBar: AppBar(
        title: const Text('فريق المنصة'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(platformTeamProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddAdminDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('إضافة عضو جديد'),
      ),
      body: usersAsync.when(
        loading: () => const AppLoader(),
        error: (error, _) => Center(child: Text('خطأ: $error')),
        data: (allUsers) {
          final filtered = allUsers.where((u) {
            final q = _searchQuery.toLowerCase();
            return u.fullName.toLowerCase().contains(q) || u.email.toLowerCase().contains(q);
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: AppTextField(
                  controller: _searchController,
                  hint: 'ابحث بالاسم أو البريد',
                  prefixIcon: Icons.search,
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const AppEmptyView(icon: Icons.people_outline, title: 'لا يوجد أعضاء', message: 'ابحث عن شخص أو أضف عضواً جديداً.')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final user = filtered[index];
                          return _PlatformMemberCard(
                            user: user,
                            onToggleRole: () => _promoteExistingUser(user),
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
}

class _PlatformMemberCard extends StatelessWidget {
  const _PlatformMemberCard({required this.user, required this.onToggleRole});
  final AdminUser user;
  final VoidCallback onToggleRole;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: user.isAdmin ? Colors.green : scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: user.isAdmin ? Colors.green.withValues(alpha: 0.15) : scheme.surfaceContainerHighest,
            child: Icon(user.isAdmin ? Icons.shield : Icons.support_agent, color: user.isAdmin ? Colors.green : scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(user.fullName, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    if (user.isAdmin)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(4)),
                        child: const Text('أدمن', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(4)),
                        child: Text('موظف', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                Text(user.email, style: theme.textTheme.bodySmall, textDirection: TextDirection.ltr),
              ],
            ),
          ),
          IconButton(
            tooltip: user.isAdmin ? 'إلغاء صلاحية الأدمن' : 'ترقية إلى أدمن',
            icon: Icon(
              user.isAdmin ? Icons.remove_moderator : Icons.add_moderator,
              color: user.isAdmin ? Colors.orange : Colors.green,
            ),
            onPressed: onToggleRole,
          ),
        ],
      ),
    );
  }
}

class _AddPlatformAdminDialog extends ConsumerStatefulWidget {
  const _AddPlatformAdminDialog();

  @override
  ConsumerState<_AddPlatformAdminDialog> createState() => _AddPlatformAdminDialogState();
}

class _AddPlatformAdminDialogState extends ConsumerState<_AddPlatformAdminDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String _role = 'staff';
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final bool isAdmin = _role == 'admin';

    if (isAdmin) {
      final confirmed = await _showWarning(context, _nameCtrl.text);
      if (confirmed != true) return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final service = AdminUserService(Supabase.instance.client);
      await service.createUser(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
        fullName: _nameCtrl.text,
        isPlatformAdmin: isAdmin,
        isPlatformStaff: !isAdmin,
      );

      if (mounted) Navigator.pop(context, true);
    } on AdminUserException catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = e.message; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة عضو للمنصة'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(controller: _nameCtrl, label: 'الاسم', validator: (v) => v!.isEmpty ? 'مطلوب' : null),
              const SizedBox(height: 12),
              AppTextField(controller: _emailCtrl, label: 'البريد الإلكتروني', validator: (v) => v!.contains('@') ? null : 'بريد غير صالح'),
              const SizedBox(height: 12),
              AppTextField(controller: _passwordCtrl, label: 'كلمة المرور', obscureText: true, validator: (v) => v!.length >= 6 ? null : '6 أحرف على الأقل'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _role, 
                decoration: const InputDecoration(labelText: 'الدور', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'staff', child: Text('موظف منصة')),
                  DropdownMenuItem(value: 'admin', child: Text('مدير منصة (صلاحيات كاملة)')),
                ],
                onChanged: (v) => setState(() => _role = v!),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ]
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _isLoading ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        AppButton(label: 'إنشاء', isLoading: _isLoading, onPressed: _isLoading ? null : _submit),
      ],
    );
  }
}

Future<bool?> _showWarning(BuildContext context, String name, {bool isRevoke = false}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        isRevoke ? Icons.gpp_bad_outlined : Icons.warning_amber_rounded,
        color: isRevoke ? Colors.orange : Colors.red,
        size: 48,
      ),
      title: Text(isRevoke ? 'تأكيد إلغاء صلاحية الأدمن' : 'تأكيد منح صلاحية الأدمن'),
      content: Text(
        isRevoke
            ? 'أنت على وشك سحب صلاحيات الأدمن من "$name".\n\nلن يتمكن من رؤية أو تعديل اشتراكات الشركات.\n\nهل أنت متأكد؟'
            : 'أنت على وشك منح "$name" صلاحيات كاملة كمدير للمنصة (Platform Admin).\n\nهذا يمنحه وصولاً كاملاً لجميع الشركات.\n\nهل أنت متأكد؟'
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: isRevoke ? Colors.orange : Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(isRevoke ? 'نعم، اسحب' : 'نعم، امنح'),
        ),
      ],
    ),
  );
}

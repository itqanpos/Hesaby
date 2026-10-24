// lib/features/admin/presentation/pages/tabs/admin_users_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../shared/widgets/app_button.dart';
import '../../../../../shared/widgets/app_empty.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loader.dart';
import '../../../../../shared/widgets/app_text_field.dart';
import '../../../data/services/admin_user_service.dart';

// ============================================================================
// Models
// ============================================================================

class AdminUserCompany {
  const AdminUserCompany({required this.companyName, required this.role});
  final String companyName;
  final String role;
}

class AdminUser {
  const AdminUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.isAdmin,
    required this.isBanned,
    required this.createdAt,
    required this.companies,
  });

  final String id;
  final String fullName;
  final String email;
  final bool isAdmin;
  final bool isBanned;
  final DateTime createdAt;
  final List<AdminUserCompany> companies;
}

// ============================================================================
// Provider
// ============================================================================

final adminUsersProvider = FutureProvider.autoDispose<List<AdminUser>>((ref) async {
  final client = Supabase.instance.client;
  final rpcResponse = await client.rpc('get_admin_users');
  
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

  Future<void> _showCreateUserDialog() async {
    final bool? created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CreateUserDialog(),
    );
    if (created == true) ref.invalidate(adminUsersProvider);
  }

  Future<void> _showEditUserDialog(AdminUser user) async {
    final bool? updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditUserDialog(user: user),
    );
    if (updated == true) ref.invalidate(adminUsersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(adminUsersProvider);

    return usersAsync.when(
      loading: () => const AppLoader(),
      error: (Object error, StackTrace _) => AppErrorView(
        title: 'تعذّر تحميل المستخدمين',
        message: 'حدث خطأ: $error',
        retryLabel: 'إعادة المحاولة',
        onRetry: () => ref.invalidate(adminUsersProvider),
      ),
      data: (List<AdminUser> allUsers) {
        final filtered = allUsers.where((u) {
          final q = _searchQuery.toLowerCase();
          return u.fullName.toLowerCase().contains(q) || u.email.toLowerCase().contains(q);
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                children: [
                  AppButton(
                    label: 'إنشاء مستخدم جديد',
                    icon: Icons.person_add,
                    onPressed: _showCreateUserDialog,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _searchController,
                    hint: 'ابحث بالاسم أو البريد',
                    prefixIcon: Icons.search,
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const AppEmptyView(icon: Icons.people_outline, title: 'لا يوجد مستخدمون', message: '')
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final user = filtered[index];
                        return _UserCard(
                          user: user,
                          onEdit: () => _showEditUserDialog(user),
                        );
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
  const _UserCard({required this.user, required this.onEdit});
  final AdminUser user;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: user.isBanned ? scheme.error : scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                backgroundColor: user.isAdmin ? scheme.errorContainer : (user.isBanned ? scheme.surfaceContainerHighest : scheme.primaryContainer),
                child: Icon(user.isAdmin ? Icons.security : Icons.person, color: user.isAdmin ? scheme.onErrorContainer : scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(user.fullName, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                        if (user.isAdmin) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: scheme.error, borderRadius: BorderRadius.circular(4)),
                            child: const Text('أدمن', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ],
                        if (user.isBanned) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(4)),
                            child: Text('محظور', style: TextStyle(color: scheme.onErrorContainer, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ]
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(user.email, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant), textDirection: TextDirection.ltr),
                  ],
                ),
              ),
              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: onEdit, color: scheme.primary),
            ],
          ),
          if (user.companies.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text('الشركات:', style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: user.companies.map((c) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                child: Text('${c.companyName} (${c.role})', style: theme.textTheme.labelSmall),
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// Create User Dialog
// ============================================================================
class _CreateUserDialog extends ConsumerStatefulWidget {
  const _CreateUserDialog();
  @override
  ConsumerState<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends ConsumerState<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _error = null; });

    try {
      final service = AdminUserService(Supabase.instance.client);
      await service.createUser(email: _emailCtrl.text, password: _passwordCtrl.text, fullName: _nameCtrl.text);
      if (mounted) Navigator.of(context).pop(true);
    } on AdminUserException catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = e.message; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إنشاء مستخدم جديد'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(controller: _nameCtrl, label: 'الاسم (اختياري)'),
            const SizedBox(height: 12),
            AppTextField(controller: _emailCtrl, label: 'البريد الإلكتروني', validator: (v) => v!.contains('@') ? null : 'بريد غير صالح'),
            const SizedBox(height: 12),
            AppTextField(controller: _passwordCtrl, label: 'كلمة المرور', obscureText: true, validator: (v) => v!.length >= 6 ? null : '6 أحرف على الأقل'),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ]
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _isLoading ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        AppButton(label: 'إنشاء', isLoading: _isLoading, onPressed: _isLoading ? null : _submit),
      ],
    );
  }
}

// ============================================================================
// Edit User Dialog
// ============================================================================
class _EditUserDialog extends ConsumerStatefulWidget {
  final AdminUser user;
  const _EditUserDialog({required this.user});
  @override
  ConsumerState<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends ConsumerState<_EditUserDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(text: widget.user.fullName);
  late final _emailCtrl = TextEditingController(text: widget.user.email);
  final _passwordCtrl = TextEditingController();
  late bool _isAdmin = widget.user.isAdmin;
  late bool _isBanned = widget.user.isBanned;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _error = null; });

    try {
      final service = AdminUserService(Supabase.instance.client);
      await service.updateUser(
        userId: widget.user.id,
        email: _emailCtrl.text != widget.user.email ? _emailCtrl.text : null,
        password: _passwordCtrl.text.isNotEmpty ? _passwordCtrl.text : null,
        fullName: _nameCtrl.text,
        isPlatformAdmin: _isAdmin,
        isBanned: _isBanned, // إرسال حالة الحظر
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AdminUserException catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = e.message; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تعديل بيانات المستخدم'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(controller: _nameCtrl, label: 'الاسم'),
              const SizedBox(height: 12),
              AppTextField(controller: _emailCtrl, label: 'البريد الإلكتروني'),
              const SizedBox(height: 12),
              AppTextField(controller: _passwordCtrl, label: 'كلمة مرور جديدة (اختياري)', obscureText: true),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('صلاحية أدمن (Platform Admin)'),
                value: _isAdmin,
                onChanged: (v) => setState(() => _isAdmin = v),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text('حظر المستخدم (منع الدخول)'),
                subtitle: const Text('لن يتمكن المستخدم من تسجيل الدخول'),
                value: _isBanned,
                onChanged: (v) => setState(() => _isBanned = v),
                contentPadding: EdgeInsets.zero,
                activeColor: Theme.of(context).colorScheme.error,
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
        AppButton(label: 'حفظ', isLoading: _isLoading, onPressed: _isLoading ? null : _submit),
      ],
    );
  }
}

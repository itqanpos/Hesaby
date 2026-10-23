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
// Provider (مضاد للأخطاء)
// ============================================================================

final adminUsersProvider = FutureProvider.autoDispose<List<AdminUser>>((ref) async {
  final client = Supabase.instance.client;

  // 1. جلب المستخدمين عبر الدالة الآمنة
  final rpcResponse = await client.rpc('get_admin_users');

  // 2. جلب عضويات الشركات
  List<dynamic> membersResponse = [];
  try {
    membersResponse = await client
        .from('company_members')
        .select('user_id, role, companies(name)');
  } catch (e) {
    // إذا فشل جلب الشركات، نكمل بدونها بدلاً من انهيار الشاشة
    debugPrint('Failed to fetch company members: $e');
  }

  // تجميع عضويات الشركات
  final Map<String, List<AdminUserCompany>> memberships = {};
  for (final row in membersResponse) {
    final userId = row['user_id'] as String?;
    if (userId == null) continue;
    
    final companyData = row['companies'] as Map<String, dynamic>?;
    if (companyData != null) {
      final companyName = companyData['name'] as String? ?? 'شركة محذوفة';
      final role = row['role'] as String? ?? 'عضو';
      final companyId = companyData['id']?.toString() ?? '';
      
      memberships.putIfAbsent(userId, () => []).add(
        AdminUserCompany(
          companyId: companyId,
          companyName: companyName,
          role: role,
        ),
      );
    }
  }

  // بناء القائمة النهائية
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
          createdAt: _safeParseDate(map['created_at']),
          companies: memberships[userId] ?? [],
        ),
      );
    }
  }

  return users;
});

// شبكة أمان لتحويل التواريخ
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
    if (created == true) {
      ref.invalidate(adminUsersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنشاء المستخدم بنجاح')),
        );
      }
    }
  }

  Future<void> _showEditUserDialog(AdminUser user) async {
    final bool? updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditUserDialog(user: user),
    );
    if (updated == true) {
      ref.invalidate(adminUsersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث بيانات المستخدم بنجاح')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(adminUsersProvider);

    return usersAsync.when(
      loading: () => const AppLoader(),
      error: (Object error, StackTrace _) => AppErrorView(
        title: 'تعذّر تحميل المستخدمين',
        message: 'حدث خطأ أثناء جلب قائمة المشتركين: $error',
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppButton(
                    label: 'إنشاء مستخدم جديد',
                    icon: Icons.person_add,
                    onPressed: _showCreateUserDialog,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
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
                ],
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
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
                tooltip: 'تعديل بيانات المستخدم',
                color: scheme.primary,
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

// ============================================================================
// Create & Edit Dialogs (كاملة كما هي من الرد السابق)
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
  bool _obscure = true;
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
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final service = AdminUserService(Supabase.instance.client);
      await service.createUser(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
        fullName: _nameCtrl.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AdminUserException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إنشاء مستخدم جديد'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(
                  controller: _nameCtrl,
                  label: 'الاسم الكامل (اختياري)',
                  prefixIcon: Icons.person_outline,
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _emailCtrl,
                  label: 'البريد الإلكتروني',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  enabled: !_isLoading,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'مطلوب';
                    if (!v.contains('@')) return 'بريد غير صالح';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _passwordCtrl,
                  label: 'كلمة المرور',
                  prefixIcon: Icons.lock_outline,
                  obscureText: _obscure,
                  enabled: !_isLoading,
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  validator: (v) {
                    if (v == null || v.length < 6) return '6 أحرف على الأقل';
                    return null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ]
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        AppButton(
          label: 'إنشاء',
          isLoading: _isLoading,
          onPressed: _isLoading ? null : _submit,
        ),
      ],
    );
  }
}

class _EditUserDialog extends ConsumerStatefulWidget {
  final AdminUser user;
  const _EditUserDialog({required this.user});

  @override
  ConsumerState<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends ConsumerState<_EditUserDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  final _passwordCtrl = TextEditingController();
  late bool _isAdmin;
  bool _obscure = true;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.user.fullName);
    _emailCtrl = TextEditingController(text: widget.user.email);
    _isAdmin = widget.user.isAdmin;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final service = AdminUserService(Supabase.instance.client);
      await service.updateUser(
        userId: widget.user.id,
        email: _emailCtrl.text.trim() != widget.user.email ? _emailCtrl.text : null,
        password: _passwordCtrl.text.isNotEmpty ? _passwordCtrl.text : null,
        fullName: _nameCtrl.text,
        isPlatformAdmin: _isAdmin,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AdminUserException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تعديل بيانات المستخدم'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(
                  controller: _nameCtrl,
                  label: 'الاسم الكامل',
                  prefixIcon: Icons.person_outline,
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _emailCtrl,
                  label: 'البريد الإلكتروني',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  enabled: !_isLoading,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'مطلوب';
                    if (!v.contains('@')) return 'بريد غير صالح';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _passwordCtrl,
                  label: 'كلمة مرور جديدة (اختياري)',
                  hint: 'اتركه فارغاً لعدم التغيير',
                  prefixIcon: Icons.lock_outline,
                  obscureText: _obscure,
                  enabled: !_isLoading,
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  validator: (v) {
                    if (v != null && v.isNotEmpty && v.length < 6) return '6 أحرف على الأقل';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('صلاحية أدمن (Platform Admin)'),
                  subtitle: const Text('يمنح هذا المستخدم حق الوصول للوحة تحكم المنصة'),
                  value: _isAdmin,
                  onChanged: _isLoading ? null : (v) => setState(() => _isAdmin = v),
                  contentPadding: EdgeInsets.zero,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ]
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        AppButton(
          label: 'حفظ التعديلات',
          isLoading: _isLoading,
          onPressed: _isLoading ? null : _submit,
        ),
      ],
    );
  }
}

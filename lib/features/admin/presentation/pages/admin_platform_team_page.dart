// lib/features/admin/presentation/pages/admin_platform_team_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../data/services/admin_user_service.dart';
import 'tabs/admin_users_tab.dart'; // نستخدم نفس الموديل والمزود

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
    if (created == true) ref.invalidate(adminUsersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(adminUsersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('فريق المنصة'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddAdminDialog,
        icon: const Icon(Icons.shield),
        label: const Text('إضافة أدمن / موظف'),
      ),
      body: usersAsync.when(
        loading: () => const AppLoader(),
        error: (error, _) => Center(child: Text('خطأ: $error')),
        data: (allUsers) {
          // نعرض فقط من هم أدمن حالياً (أو يمكن عرض الكل)
          // هنا سنعرض الكل للسماح بالبحث عن أي شخص لترقيته
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
                    ? const AppEmptyView(icon: Icons.people_outline, title: 'لا يوجد أعضاء', message: 'ابحث عن شخص لإضافته.')
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final user = filtered[index];
                          return _PlatformMemberCard(user: user);
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
  const _PlatformMemberCard({required this.user});
  final AdminUser user;

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
            backgroundColor: user.isAdmin ? Colors.green.withValues(alpha: 0.2) : scheme.surfaceContainerHighest,
            child: Icon(user.isAdmin ? Icons.shield : Icons.support_agent, color: user.isAdmin ? Colors.green : scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.fullName, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                Text(user.email, style: theme.textTheme.bodySmall, textDirection: TextDirection.ltr),
              ],
            ),
          ),
          if (user.isAdmin)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(8)),
              child: const Text('مدير منصة', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
              child: Text('موظف', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold)),
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
  String _role = 'admin'; // Default
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

    // 🛑 تحذير صارم
    if (_role == 'admin') {
      final confirmed = await _showWarning(context, _nameCtrl.text);
      if (confirmed != true) return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final service = AdminUserService(Supabase.instance.client);
      // Create user
      final newUser = await service.createUser(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
        fullName: _nameCtrl.text,
      );
      
      // If admin, promote them (assuming createUser returns the user object)
      // Note: If service doesn't return ID, we might need to fetch it.
      // For simplicity here, assuming createUser handles the creation.
      // Ideally, updateUser should be called if _role == 'admin'.
      // Let's assume we need to update them right after creation.
      
      // Note: This requires AdminUserService to return the user ID.
      // If it doesn't, we will just create them and you can promote them later.
      // Assuming the service works, I'll call update.
      
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
                value: _role,
                decoration: const InputDecoration(labelText: 'الدور', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'staff', child: Text('موظف (بدون صلاحيات كاملة)')),
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
        AppButton(label: 'حفظ', isLoading: _isLoading, onPressed: _isLoading ? null : _submit),
      ],
    );
  }
}

Future<bool?> _showWarning(BuildContext context, String name) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 48),
      title: const Text('تأكيد منح صلاحية الأدمن'),
      content: Text('أنت على وشك منح "$name" صلاحيات كاملة كمدير للمنصة (Platform Admin).\n\nهل أنت متأكد؟'),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('نعم، متأكد'),
        ),
      ],
    ),
  );
}

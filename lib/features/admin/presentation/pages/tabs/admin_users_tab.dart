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
// Models (typed — لا dynamic)
// ============================================================================

class AdminUserCompany {
  const AdminUserCompany({
    required this.companyId,
    required this.companyName,
    required this.role,
    required this.isActive,
    required this.isSuspended,
    required this.subscriptionStatus,
    required this.billingCycle,
  });

  final String companyId;
  final String companyName;
  final String role;
  final bool isActive;
  final bool isSuspended;
  final String? subscriptionStatus; // trial|active|expired|cancelled
  final String? billingCycle;       // monthly|yearly|lifetime

  bool get isLifetime => billingCycle == 'lifetime';

  String get subscriptionLabel {
    if (isSuspended) return 'محظورة';
    if (isLifetime) return 'مدى الحياة';
    return switch (subscriptionStatus) {
      'active' => 'نشط',
      'trial' => 'تجربة',
      'expired' => 'منتهي',
      'cancelled' => 'ملغى',
      _ => '—',
    };
  }
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
// Row parsing (typed)
// ============================================================================

class _AdminUserRow {
  const _AdminUserRow({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.isPlatformAdmin,
    required this.createdAt,
  });

  final String userId;
  final String fullName;
  final String email;
  final bool isPlatformAdmin;
  final DateTime createdAt;

  static _AdminUserRow? tryParse(Map<String, Object?> row) {
    final String? userId = _readString(row, 'user_id');
    if (userId == null || userId.isEmpty) return null;
    return _AdminUserRow(
      userId: userId,
      fullName: _readString(row, 'full_name') ?? 'بدون اسم',
      email: _readString(row, 'email') ?? 'غير متوفر',
      isPlatformAdmin: _readBool(row, 'is_platform_admin') ?? false,
      createdAt: _readTimestamp(row, 'created_at'),
    );
  }
}

class _MemberRow {
  const _MemberRow({
    required this.userId,
    required this.companyId,
    required this.companyName,
    required this.role,
    required this.isActive,
    required this.isSuspended,
    required this.subscriptionStatus,
    required this.billingCycle,
  });

  final String userId;
  final String companyId;
  final String companyName;
  final String role;
  final bool isActive;
  final bool isSuspended;
  final String? subscriptionStatus;
  final String? billingCycle;

  /// يُرجع null إذا كانت الشركة محذوفة (FK انكسر) أو id مفقود.
  static _MemberRow? tryParse(Map<String, Object?> row) {
    final String? userId = _readString(row, 'user_id');
    if (userId == null || userId.isEmpty) return null;

    final Object? companiesRaw = row['companies'];
    if (companiesRaw is! Map) return null;
    final Map<String, Object?> company = Map<String, Object?>.from(companiesRaw);

    final String? companyId = _readString(company, 'id');
    if (companyId == null || companyId.isEmpty) return null;

    return _MemberRow(
      userId: userId,
      companyId: companyId,
      companyName: _readString(company, 'name') ?? 'شركة محذوفة',
      role: _readString(row, 'role') ?? 'عضو',
      isActive: _readBool(row, 'is_active') ?? true,
      isSuspended: _readBool(company, 'is_suspended') ?? false,
      subscriptionStatus: _readString(company, 'subscription_status'),
      billingCycle: _readString(company, 'billing_cycle'),
    );
  }
}

// ============================================================================
// Provider
// ============================================================================

final adminUsersProvider =
    FutureProvider.autoDispose<List<AdminUser>>((ref) async {
  final client = Supabase.instance.client;

  // 1. المستخدمون عبر RPC الآمنة.
  //    ملاحظة (U5): الكتابة في audit_logs لعمليات المستخدمين تتم من Edge Functions
  //    (admin-create-user / admin-update-user) — راجع C6. لا يمكن للعميل
  //    استدعاء audit_log_insert مباشرة (REVOKE صريح من authenticated).
  final Object rpcResponse = await client.rpc('get_admin_users');

  // 2. عضويات الشركات (مع id الشركة وحالتها).
  //    includeInactive: لا نفلتر بـ is_active — نُظهر الكل ونعرض الحالة.
  List<Map<String, Object?>> memberRows = <Map<String, Object?>>[];
  try {
    final Object? raw = await client
        .from('company_members')
        .select(
          'user_id, role, is_active, '
          'companies(id, name, is_suspended, subscription_status, billing_cycle)',
        );
    memberRows = _asRows(raw);
  } on Object catch (e) {
    debugPrint('Failed to fetch company members: $e');
  }

  // تجميع العضويات حسب المستخدم.
  final Map<String, List<AdminUserCompany>> byUser =
      <String, List<AdminUserCompany>>{};
  for (final Map<String, Object?> row in memberRows) {
    final _MemberRow? m = _MemberRow.tryParse(row);
    if (m == null) continue;
    byUser.putIfAbsent(m.userId, () => <AdminUserCompany>[]).add(
          AdminUserCompany(
            companyId: m.companyId,
            companyName: m.companyName,
            role: m.role,
            isActive: m.isActive,
            isSuspended: m.isSuspended,
            subscriptionStatus: m.subscriptionStatus,
            billingCycle: m.billingCycle,
          ),
        );
  }

  // بناء القائمة النهائية.
  final List<AdminUser> users = <AdminUser>[];
  for (final Map<String, Object?> row in _asRows(rpcResponse)) {
    final _AdminUserRow? u = _AdminUserRow.tryParse(row);
    if (u == null) continue;
    users.add(
      AdminUser(
        id: u.userId,
        fullName: u.fullName,
        email: u.email,
        isAdmin: u.isPlatformAdmin,
        createdAt: u.createdAt,
        companies: byUser[u.userId] ?? const <AdminUserCompany>[],
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

  void _refresh() => ref.invalidate(adminUsersProvider);

  Future<void> _showCreateUserDialog() async {
    final bool? created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CreateUserDialog(),
    );
    if (created == true && mounted) {
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنشاء المستخدم بنجاح')),
      );
    }
  }

  Future<void> _showEditUserDialog(AdminUser user) async {
    final bool? updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditUserDialog(user: user),
    );
    if (updated == true && mounted) {
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث بيانات المستخدم بنجاح')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<AdminUser>> usersAsync =
        ref.watch(adminUsersProvider);

    return usersAsync.when(
      loading: () => const AppLoader(),
      error: (Object error, StackTrace _) => AppErrorView(
        title: 'تعذّر تحميل المستخدمين',
        message: 'حدث خطأ أثناء جلب قائمة المشتركين.',
        retryLabel: 'إعادة المحاولة',
        onRetry: _refresh,
      ),
      data: (List<AdminUser> allUsers) {
        final String q = _searchQuery.trim().toLowerCase();
        final List<AdminUser> filtered = allUsers.where((AdminUser u) {
          if (q.isEmpty) return true;
          return u.fullName.toLowerCase().contains(q) ||
              u.email.toLowerCase().contains(q);
        }).toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
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
                            tooltip: 'مسح',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                    onChanged: (String v) =>
                        setState(() => _searchQuery = v),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? AppEmptyView(
                      icon: allUsers.isEmpty
                          ? Icons.people_outline
                          : Icons.search_off_outlined,
                      title: allUsers.isEmpty
                          ? 'لا يوجد مشتركون'
                          : 'لا نتائج',
                      message: allUsers.isEmpty
                          ? 'لم يتم العثور على أي مستخدمين في المنصة.'
                          : 'لا يوجد مستخدمون يطابقون بحثك.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final AdminUser user = filtered[index];
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

// ============================================================================
// User card
// ============================================================================

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, required this.onEdit});

  final AdminUser user;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

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
                backgroundColor: user.isAdmin
                    ? scheme.errorContainer
                    : scheme.primaryContainer,
                foregroundColor: user.isAdmin
                    ? scheme.onErrorContainer
                    : scheme.onPrimaryContainer,
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
                        Flexible(
                          child: Text(
                            user.fullName,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (user.isAdmin) ...<Widget>[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.error,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'أدمن',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
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
          if (user.companies.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text(
              'الشركات التابعة له:',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: user.companies
                  .map((AdminUserCompany c) =>
                      _CompanyChip(company: c, scheme: scheme, theme: theme))
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompanyChip extends StatelessWidget {
  const _CompanyChip({
    required this.company,
    required this.scheme,
    required this.theme,
  });

  final AdminUserCompany company;
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final ({Color bg, Color fg}) colors = _resolveColors(scheme);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: company.isActive
            ? null
            : Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            company.isSuspended
                ? Icons.block
                : (company.isActive
                    ? Icons.storefront
                    : Icons.storefront_outlined),
            size: 14,
            color: company.isSuspended ? scheme.error : scheme.primary,
          ),
          const SizedBox(width: 4),
          Text(
            '${company.companyName} (${company.role})',
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: colors.bg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              company.subscriptionLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9,
                color: colors.fg,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (!company.isActive) ...<Widget>[
            const SizedBox(width: 4),
            Icon(Icons.person_off_outlined,
                size: 12, color: scheme.onSurfaceVariant),
          ],
        ],
      ),
    );
  }

  ({Color bg, Color fg}) _resolveColors(ColorScheme scheme) {
    if (company.isSuspended) {
      return (bg: scheme.error, fg: scheme.onError);
    }
    if (company.isLifetime) {
      return (bg: const Color(0xFFE1BEE7), fg: const Color(0xFF6A1B9A));
    }
    return switch (company.subscriptionStatus) {
      'active' => (bg: const Color(0xFFC8E6C9), fg: const Color(0xFF1B5E20)),
      'trial' => (bg: const Color(0xFFFFECB3), fg: const Color(0xFF8D6E00)),
      'expired' || 'cancelled' => (
          bg: scheme.errorContainer,
          fg: scheme.onErrorContainer,
        ),
      _ => (bg: scheme.surface, fg: scheme.onSurfaceVariant),
    };
  }
}

// ============================================================================
// Create dialog
// ============================================================================

class _CreateUserDialog extends ConsumerStatefulWidget {
  const _CreateUserDialog();

  @override
  ConsumerState<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends ConsumerState<_CreateUserDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
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
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final AdminUserService service = AdminUserService(Supabase.instance.client);
      await service.createUser(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        fullName: _nameCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AdminUserException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.message;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'تعذّر إنشاء المستخدم. حاول مرة أخرى.';
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
              children: <Widget>[
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
                  validator: (String? v) {
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
                    icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  validator: (String? v) {
                    if (v == null || v.length < 6) {
                      return '6 أحرف على الأقل';
                    }
                    return null;
                  },
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
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

// ============================================================================
// Edit dialog
// ============================================================================

class _EditUserDialog extends ConsumerStatefulWidget {
  const _EditUserDialog({required this.user});

  final AdminUser user;

  @override
  ConsumerState<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends ConsumerState<_EditUserDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  final TextEditingController _passwordCtrl = TextEditingController();
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

  /// U6: تأكيد قبل منح/سحب صلاحية الأدمن.
  Future<bool> _confirmAdminToggle(bool newValue) async {
    if (newValue == widget.user.isAdmin) return true;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(newValue ? 'منح صلاحية أدمن' : 'سحب صلاحية أدمن'),
        content: Text(
          newValue
              ? 'سيتمكن هذا المستخدم من الوصول الكامل إلى لوحة تحكم المنصة '
                  'وإدارة جميع الشركات. هذا الإجراء يُسجَّل في سجل التدقيق.'
              : 'سيتم إلغاء وصول هذا المستخدم إلى لوحة تحكم المنصة. '
                  'هذا الإجراء يُسجَّل في سجل التدقيق.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: newValue
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                    foregroundColor: Theme.of(ctx).colorScheme.onError,
                  ),
            child: Text(newValue ? 'تأكيد المنح' : 'تأكيد السحب'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_isAdmin != widget.user.isAdmin) {
      final bool ok = await _confirmAdminToggle(_isAdmin);
      if (!ok) return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final AdminUserService service = AdminUserService(Supabase.instance.client);
      await service.updateUser(
        userId: widget.user.id,
        email: _emailCtrl.text.trim() != widget.user.email
            ? _emailCtrl.text.trim()
            : null,
        password: _passwordCtrl.text.isNotEmpty ? _passwordCtrl.text : null,
        fullName: _nameCtrl.text.trim(),
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
    } on Object {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'تعذّر تحديث المستخدم. حاول مرة أخرى.';
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
              children: <Widget>[
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
                  validator: (String? v) {
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
                    icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  validator: (String? v) {
                    if (v != null && v.isNotEmpty && v.length < 6) {
                      return '6 أحرف على الأقل';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('صلاحية أدمن (Platform Admin)'),
                  subtitle: const Text(
                    'يمنح هذا المستخدم حق الوصول للوحة تحكم المنصة',
                  ),
                  value: _isAdmin,
                  onChanged: _isLoading
                      ? null
                      : (bool v) => setState(() => _isAdmin = v),
                  contentPadding: EdgeInsets.zero,
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
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

// ============================================================================
// Parsing helpers (rule 22 / rule 25)
// ============================================================================

List<Map<String, Object?>> _asRows(Object? raw) {
  if (raw is! List) return const <Map<String, Object?>>[];
  final List<Map<String, Object?>> result = <Map<String, Object?>>[];
  for (final Object? element in raw) {
    if (element is! Map) continue;
    result.add(Map<String, Object?>.from(element));
  }
  return result;
}

String? _readString(Map<String, Object?> row, String key) {
  final Object? value = row[key];
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

bool? _readBool(Map<String, Object?> row, String key) {
  final Object? value = row[key];
  if (value == null) return null;
  if (value is bool) return value;
  if (value is String) {
    if (value == 'true') return true;
    if (value == 'false') return false;
  }
  return null;
}

/// rule 25: تواريخ Postgres على الأندرويد تحتاج ` ` → `T` و `+00` → `Z`.
DateTime _readTimestamp(Map<String, Object?> row, String key) {
  final Object? value = row[key];
  if (value is DateTime) return value.toUtc();
  if (value is String) {
    String normalized = value.trim();
    if (normalized.contains(' ')) {
      normalized = normalized.replaceFirst(' ', 'T');
    }
    if (normalized.endsWith('+00')) {
      normalized = normalized.replaceAll('+00', 'Z');
    }
    final DateTime? parsed = DateTime.tryParse(normalized);
    if (parsed != null) return parsed.toUtc();
  }
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

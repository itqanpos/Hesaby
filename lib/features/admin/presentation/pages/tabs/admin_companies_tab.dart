// lib/features/admin/presentation/pages/tabs/admin_companies_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../shared/widgets/app_empty.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loader.dart';
import '../../../../../shared/widgets/app_text_field.dart';

// ============================================================================
// Models
// ============================================================================

class SubscriptionPlan {
  const SubscriptionPlan({required this.id, required this.name, required this.label, required this.price, this.durationDays});
  final String id;
  final String name;
  final String label;
  final double price;
  final int? durationDays;

  factory SubscriptionPlan.fromMap(Map<String, dynamic> map) {
    return SubscriptionPlan(
      id: map['id'] as String,
      name: map['name'] as String,
      label: map['label'] as String,
      price: (map['price'] as num).toDouble(),
      durationDays: map['duration_days'] as int?,
    );
  }
}

class AdminCompany {
  const AdminCompany({
    required this.id,
    required this.name,
    required this.isActive,
    required this.subscriptionStatus,
    required this.createdAt,
    this.phone,
    this.suspensionReason,
    this.subscriptionEnd,
  });

  final String id;
  final String name;
  final bool isActive;
  final String subscriptionStatus;
  final DateTime createdAt;
  final String? phone;
  final String? suspensionReason;
  final DateTime? subscriptionEnd;

  factory AdminCompany.fromMap(Map<String, dynamic> map) {
    return AdminCompany(
      id: map['id'] as String,
      name: map['name'] as String? ?? 'شركة بدون اسم',
      isActive: map['is_active'] as bool? ?? true,
      subscriptionStatus: map['subscription_status'] as String? ?? 'trial',
      createdAt: _parseDate(map['created_at']),
      phone: map['phone'] as String?,
      suspensionReason: map['suspension_reason'] as String?,
      subscriptionEnd: map['subscription_end'] != null ? _parseDate(map['subscription_end']) : null,
    );
  }

  static DateTime _parseDate(Object? value) {
    if (value is DateTime) return value.toLocal();
    if (value is String) {
      DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toLocal();
      try {
        String normalized = value.trim();
        if (normalized.contains(' ')) normalized = normalized.replaceFirst(' ', 'T');
        if (normalized.endsWith('+00')) normalized = normalized.replaceAll('+00', 'Z');
        parsed = DateTime.tryParse(normalized);
        if (parsed != null) return parsed.toLocal();
      } catch (_) {}
    }
    return DateTime.now();
  }
}

// ============================================================================
// Providers
// ============================================================================

final adminCompaniesProvider = FutureProvider.autoDispose<List<AdminCompany>>((ref) async {
  final client = Supabase.instance.client;
  final response = await client.from('companies').select().order('created_at', ascending: false);
  final List<dynamic> data = response as List<dynamic>;
  return data.map((e) => AdminCompany.fromMap(e as Map<String, dynamic>)).toList();
});

final subscriptionPlansProvider = FutureProvider.autoDispose<List<SubscriptionPlan>>((ref) async {
  final client = Supabase.instance.client;
  final response = await client.from('subscription_plans').select();
  final List<dynamic> data = response as List<dynamic>;
  return data.map((e) => SubscriptionPlan.fromMap(e as Map<String, dynamic>)).toList();
});

// ============================================================================
// UI
// ============================================================================

class AdminCompaniesTab extends ConsumerStatefulWidget {
  const AdminCompaniesTab({super.key});

  @override
  ConsumerState<AdminCompaniesTab> createState() => _AdminCompaniesTabState();
}

class _AdminCompaniesTabState extends ConsumerState<AdminCompaniesTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _toggleCompanyStatus(AdminCompany company) async {
    if (company.isActive) {
      final String? reason = await _showSuspensionDialog(context);
      if (reason == null) return;
      try {
        await Supabase.instance.client.from('companies').update({'is_active': false, 'suspension_reason': reason}).eq('id', company.id);
        ref.invalidate(adminCompaniesProvider);
      } catch (e) { _showError(context, e); }
    } else {
      try {
        await Supabase.instance.client.from('companies').update({'is_active': true, 'suspension_reason': null}).eq('id', company.id);
        ref.invalidate(adminCompaniesProvider);
      } catch (e) { _showError(context, e); }
    }
  }

  Future<void> _showRenewSubscriptionDialog(AdminCompany company) async {
    final bool? renewed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RenewSubscriptionDialog(company: company),
    );
    if (renewed == true) {
      ref.invalidate(adminCompaniesProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تجديد الاشتراك بنجاح.')));
    }
  }

  void _showError(BuildContext context, Object e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
  }

  Future<String?> _showSuspensionDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إيقاف الشركة'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'سبب الإيقاف', border: OutlineInputBorder()),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.isNotEmpty) Navigator.pop(context, reason);
            },
            child: const Text('إيقاف'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncCompanies = ref.watch(adminCompaniesProvider);

    return asyncCompanies.when(
      loading: () => const AppLoader(),
      error: (Object error, StackTrace _) => AppErrorView(
        title: 'تعذّر تحميل الشركات',
        message: 'حدث خطأ أثناء جلب قائمة الشركات.',
        retryLabel: 'إعادة المحاولة',
        onRetry: () => ref.invalidate(adminCompaniesProvider),
      ),
      data: (List<AdminCompany> companies) {
        final filtered = companies.where((c) => c.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: AppTextField(
                controller: _searchController,
                hint: 'ابحث عن شركة...',
                prefixIcon: Icons.search,
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const AppEmptyView(icon: Icons.storefront_outlined, title: 'لا توجد شركات', message: '')
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final company = filtered[index];
                        return _CompanyCard(
                          company: company,
                          onToggleStatus: () => _toggleCompanyStatus(company),
                          onRenew: () => _showRenewSubscriptionDialog(company),
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

class _CompanyCard extends StatelessWidget {
  const _CompanyCard({required this.company, required this.onToggleStatus, required this.onRenew});
  final AdminCompany company;
  final VoidCallback onToggleStatus;
  final VoidCallback onRenew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isActive = company.isActive;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isActive ? scheme.outlineVariant : scheme.error.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                backgroundColor: isActive ? scheme.primaryContainer : scheme.errorContainer,
                child: Icon(Icons.business, color: isActive ? scheme.onPrimaryContainer : scheme.onErrorContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(company.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    if (company.subscriptionEnd != null)
                      Text(
                        'ينتهي: ${DateFormat('yyyy/MM/dd').format(company.subscriptionEnd!)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary),
                      )
                    else
                      Text('الاشتراك: ${company.subscriptionStatus}', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Switch(
                value: isActive,
                onChanged: (_) => onToggleStatus(),
                activeThumbColor: const Color(0xFF0F7B6C),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onRenew,
                icon: const Icon(Icons.workspace_premium, size: 18),
                label: const Text('تجديد الاشتراك'),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF6C00)),
              ),
            ],
          ),
          if (!isActive && company.suspensionReason != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(8)),
              child: Text('سبب الإيقاف: ${company.suspensionReason}', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer)),
            ),
          ]
        ],
      ),
    );
  }
}

// ============================================================================
// Renew Subscription Dialog
// ============================================================================

class _RenewSubscriptionDialog extends ConsumerStatefulWidget {
  final AdminCompany company;
  const _RenewSubscriptionDialog({required this.company});
  @override
  ConsumerState<_RenewSubscriptionDialog> createState() => _RenewSubscriptionDialogState();
}

class _RenewSubscriptionDialogState extends ConsumerState<_RenewSubscriptionDialog> {
  String? _selectedPlanId;
  bool _isLoading = false;
  String? _error;

  Future<void> _submit() async {
    if (_selectedPlanId == null) {
      setState(() => _error = 'الرجاء اختيار الخطة');
      return;
    }
    setState(() { _isLoading = true; _error = null; });

    try {
      final client = Supabase.instance.client;
      final plans = await ref.read(subscriptionPlansProvider.future);
      final plan = plans.firstWhere((p) => p.id == _selectedPlanId);

      // حساب تاريخ الانتهاء
      DateTime? expiryDate;
      if (plan.durationDays != null) {
        final now = DateTime.now();
        // إذا كان هناك اشتراك سابق لم ينته، نضيف عليه
        final baseDate = (widget.company.subscriptionEnd != null && widget.company.subscriptionEnd!.isAfter(now))
            ? widget.company.subscriptionEnd!
            : now;
        expiryDate = baseDate.add(Duration(days: plan.durationDays!));
      }

      // 1. تسجيل الدفعة
      await client.from('subscription_payments').insert({
        'company_id': widget.company.id,
        'plan_id': plan.id,
        'amount': plan.price,
        'expiry_date': expiryDate?.toUtc().toIso8601String(),
        'created_by': client.auth.currentUser?.id,
      });

      // 2. تحديث الشركة
      await client.from('companies').update({
        'plan_id': plan.id,
        'subscription_start': DateTime.now().toUtc().toIso8601String(),
        'subscription_end': expiryDate?.toUtc().toIso8601String(),
        'subscription_status': plan.name,
        'is_active': true, // تفعيل الشركة تلقائياً عند التجديد
        'suspension_reason': null,
      }).eq('id', widget.company.id);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = 'خطأ: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(subscriptionPlansProvider);

    return AlertDialog(
      title: Text('تجديد اشتراك: ${widget.company.name}'),
      content: SizedBox(
        width: 400,
        child: plansAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('خطأ في تحميل الخطط: $e'),
          data: (plans) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...plans.map((p) => RadioListTile<String>(
                  title: Text(p.label),
                  subtitle: Text('${p.price} ج.م'),
                  value: p.id,
                  groupValue: _selectedPlanId,
                  onChanged: (v) => setState(() => _selectedPlanId = v),
                )),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ]
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: _isLoading ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('تأكيد الدفع والتجديد'),
        ),
      ],
    );
  }
}

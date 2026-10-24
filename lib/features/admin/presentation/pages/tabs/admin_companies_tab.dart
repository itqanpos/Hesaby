// lib/features/admin/presentation/pages/tabs/admin_companies_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⬇️ تم حذف استيراد intl و app_button
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../shared/widgets/app_empty.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loader.dart';
import '../../../../../shared/widgets/app_text_field.dart';

// ... (الموديل والبروفايدر كما هما بدون تغيير) ...
class AdminCompany {
  const AdminCompany({
    required this.id,
    required this.name,
    required this.isActive,
    required this.subscriptionStatus,
    required this.createdAt,
    this.phone,
    this.suspensionReason,
    this.trialEndsAt,
    this.subscribedUntil,
  });

  final String id;
  final String name;
  final bool isActive;
  final String subscriptionStatus;
  final DateTime createdAt;
  final String? phone;
  final String? suspensionReason;
  final DateTime? trialEndsAt;
  final DateTime? subscribedUntil;

  factory AdminCompany.fromMap(Map<String, dynamic> map) {
    return AdminCompany(
      id: map['id'] as String,
      name: map['name'] as String? ?? 'شركة بدون اسم',
      isActive: map['is_active'] as bool? ?? true,
      subscriptionStatus: map['subscription_status'] as String? ?? 'trial',
      createdAt: _parseDate(map['created_at']),
      phone: map['phone'] as String?,
      suspensionReason: map['suspension_reason'] as String?,
      trialEndsAt: map['trial_ends_at'] != null ? _parseDate(map['trial_ends_at']) : null,
      subscribedUntil: map['subscribed_until'] != null ? _parseDate(map['subscribed_until']) : null,
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

final adminCompaniesProvider = FutureProvider.autoDispose<List<AdminCompany>>((ref) async {
  final client = Supabase.instance.client;
  final response = await client
      .from('companies')
      .select()
      .order('created_at', ascending: false);

  final List<dynamic> data = response as List<dynamic>;
  return data
      .map((e) => AdminCompany.fromMap(e as Map<String, dynamic>))
      .toList();
});

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
        await Supabase.instance.client.from('companies').update({
          'is_active': false,
          'suspension_reason': reason,
        }).eq('id', company.id);
        ref.invalidate(adminCompaniesProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إيقاف الشركة بنجاح.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: $e')),
          );
        }
      }
    } else {
      try {
        await Supabase.instance.client.from('companies').update({
          'is_active': true,
          'suspension_reason': null,
        }).eq('id', company.id);
        ref.invalidate(adminCompaniesProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم تفعيل الشركة بنجاح.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: $e')),
          );
        }
      }
    }
  }

  Future<String?> _showSuspensionDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إيقاف الشركة'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'سبب الإيقاف (سيُسجل في سجل التدقيق)',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.isNotEmpty) Navigator.of(context).pop(reason);
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
        final filtered = companies.where((c) {
          final q = _searchQuery.toLowerCase();
          return c.name.toLowerCase().contains(q);
        }).toList();

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
                  ? const AppEmptyView(
                      icon: Icons.storefront_outlined,
                      title: 'لا توجد شركات',
                      message: 'لم يتم العثور على أي شركة تطابق بحثك.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final company = filtered[index];
                        return _CompanyCard(
                          company: company,
                          onToggleStatus: () => _toggleCompanyStatus(company),
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
  const _CompanyCard({required this.company, required this.onToggleStatus});
  final AdminCompany company;
  final VoidCallback onToggleStatus;

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
                    Text(
                      'اشتراك: ${company.subscriptionStatus}',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isActive,
                onChanged: (_) => onToggleStatus(),
                activeThumbColor: const Color(0xFF0F7B6C), // ⬅️ تم إصلاح التحذير
              ),
            ],
          ),
          if (!isActive && company.suspensionReason != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(8)),
              child: Text(
                'سبب الإيقاف: ${company.suspensionReason}',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
          ]
        ],
      ),
    );
  }
}

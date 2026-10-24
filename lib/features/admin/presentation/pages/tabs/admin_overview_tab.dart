// lib/features/admin/presentation/pages/tabs/admin_overview_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../shared/widgets/app_empty.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loader.dart';

// ============================================================================
// Provider
// ============================================================================

class OverviewData {
  const OverviewData({
    required this.totalCompanies,
    required this.activeCompanies,
    required this.suspendedCompanies,
    required this.totalUsers,
    required this.totalInvoices,
    required this.totalRevenue,
    required this.recentCompanies,
  });

  final int totalCompanies;
  final int activeCompanies;
  final int suspendedCompanies;
  final int totalUsers;
  final int totalInvoices;
  final double totalRevenue;
  final List<Map<String, dynamic>> recentCompanies;

  factory OverviewData.fromJson(Map<String, dynamic> json) {
    return OverviewData(
      totalCompanies: json['total_companies'] as int? ?? 0,
      activeCompanies: json['active_companies'] as int? ?? 0,
      suspendedCompanies: json['suspended_companies'] as int? ?? 0,
      totalUsers: json['total_users'] as int? ?? 0,
      totalInvoices: json['total_invoices'] as int? ?? 0,
      totalRevenue: (json['total_revenue'] as num?)?.toDouble() ?? 0,
      recentCompanies: List<Map<String, dynamic>>.from(json['recent_companies'] ?? []),
    );
  }
}

final overviewProvider = FutureProvider.autoDispose<OverviewData>((ref) async {
  final client = Supabase.instance.client;
  final response = await client.rpc('get_super_admin_overview');
  
  if (response is! Map) {
    throw Exception('Invalid response from overview RPC');
  }
  return OverviewData.fromJson(Map<String, dynamic>.from(response));
});

// ============================================================================
// UI
// ============================================================================

class AdminOverviewTab extends ConsumerWidget {
  const AdminOverviewTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(overviewProvider);

    return asyncData.when(
      loading: () => const AppLoader(),
      error: (Object error, StackTrace _) => AppErrorView(
        title: 'تعذّر تحميل الإحصائيات',
        message: 'حدث خطأ: $error',
        retryLabel: 'إعادة المحاولة',
        onRetry: () => ref.invalidate(overviewProvider),
      ),
      data: (OverviewData data) {
        return RefreshIndicator(
          onRefresh: () => ref.refresh(overviewProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              const _SectionHeader(title: 'الشركات'),
              const SizedBox(height: 8),
              _KpiGrid(children: [
                _KpiCard(
                  icon: Icons.storefront,
                  label: 'إجمالي الشركات',
                  value: data.totalCompanies.toString(),
                  color: const Color(0xFF0288D1),
                ),
                _KpiCard(
                  icon: Icons.check_circle,
                  label: 'شركات نشطة',
                  value: data.activeCompanies.toString(),
                  color: const Color(0xFF0F7B6C),
                ),
                _KpiCard(
                  icon: Icons.block,
                  label: 'شركات موقوفة',
                  value: data.suspendedCompanies.toString(),
                  color: const Color(0xFFC62828),
                ),
                _KpiCard(
                  icon: Icons.people,
                  label: 'إجمالي المستخدمين',
                  value: data.totalUsers.toString(),
                  color: const Color(0xFF6A1B9A),
                ),
              ]),
              
              const SizedBox(height: 24),
              const _SectionHeader(title: 'الإيرادات والنشاط'),
              const SizedBox(height: 8),
              _KpiGrid(children: [
                _KpiCard(
                  icon: Icons.payments,
                  label: 'إجمالي الإيرادات',
                  value: NumberFormat.currency(locale: 'en_US', symbol: 'ج.م ').format(data.totalRevenue),
                  color: const Color(0xFFEF6C00),
                  isWide: true,
                ),
                _KpiCard(
                  icon: Icons.receipt_long,
                  label: 'إجمالي الفواتير',
                  value: data.totalInvoices.toString(),
                  color: const Color(0xFF00838F),
                  isWide: true,
                ),
              ]),

              const SizedBox(height: 24),
              const _SectionHeader(title: 'أحدث الشركات المنضمة'),
              const SizedBox(height: 8),
              if (data.recentCompanies.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: Text('لا توجد شركات مسجلة بعد.')),
                )
              else
                ...data.recentCompanies.map((c) => Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: c['is_active'] == true 
                          ? Theme.of(context).colorScheme.primaryContainer 
                          : Theme.of(context).colorScheme.errorContainer,
                      child: Icon(
                        Icons.business, 
                        color: c['is_active'] == true 
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                    title: Text(c['name'] as String),
                    subtitle: Text('انضمت: ${DateFormat('yyyy/MM/dd').format(DateTime.parse(c['created_at']).toLocal())}'),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: c['is_active'] == true ? const Color(0xFFC8E6C9) : Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        c['is_active'] == true ? 'نشطة' : 'موقوفة',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: c['is_active'] == true ? const Color(0xFF1B5E20) : Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                )),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// Components
// ============================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: children.map((child) {
            final kpi = child as _KpiCard;
            final width = kpi.isWide
                ? (isWide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth)
                : (isWide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2);
            return SizedBox(width: width, child: kpi);
          }).toList(),
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.isWide = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

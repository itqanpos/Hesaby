// lib/features/admin/presentation/pages/admin_dashboard_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/router.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/platform_admin_provider.dart';
import 'admin_notifications_page.dart';
import 'tabs/admin_overview_tab.dart';
import 'tabs/admin_audit_log_tab.dart';
import 'tabs/admin_companies_tab.dart';
import 'tabs/admin_users_tab.dart';
import 'tabs/admin_sync_tab.dart';
import 'tabs/admin_app_control_tab.dart';
import 'tabs/admin_expenses_tab.dart';
import 'tabs/admin_support_tab.dart';
import 'tabs/admin_storage_tab.dart';
import 'tabs/admin_versions_tab.dart';
import 'tabs/admin_reports_tab.dart';

// عدد الإشعارات غير المقروءة
final unreadNotificationsCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final client = Supabase.instance.client;
  final response = await client
      .from('admin_notifications')
      .select('id')
      .eq('is_read', false);
  return (response as List).length;
});

class AdminDashboardPage extends ConsumerWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isPlatformAdmin = ref.watch(isPlatformAdminProvider);
    final String? email = ref.watch(authProvider).session?.email;
    final bool isAdmin = isPlatformAdmin || email == 'mohammedelsonbaty866@gmail.com';

    if (!isAdmin) {
      return AppShell(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.goNamed(AppRouter.homeName),
          ),
          title: const Text('لوحة تحكم المنصة'),
        ),
        body: const AppEmptyView(
          icon: Icons.lock_outline,
          title: 'غير مصرّح',
          message: 'هذه الصفحة متاحة لمديري المنصة فقط.',
        ),
      );
    }

    final int unreadCount = ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0;

    return DefaultTabController(
      length: 11,
      child: AppShell(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'العودة للتطبيق',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.goNamed(AppRouter.homeName),
          ),
          title: const Text('لوحة تحكم المنصة'),
          actions: <Widget>[
            Stack(
              children: <Widget>[
                IconButton(
                  tooltip: 'الإشعارات',
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AdminNotificationsPage()),
                    );
                    ref.invalidate(unreadNotificationsCountProvider);
                  },
                ),
                if (unreadCount > 0)
                  Positioned(
                    right: 6, top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        unreadCount > 99 ? '99+' : unreadCount.toString(),
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            tabs: <Widget>[
              Tab(icon: Icon(Icons.insights), text: 'نظرة عامة'),
              Tab(icon: Icon(Icons.history), text: 'سجل التدقيق'),
              Tab(icon: Icon(Icons.storefront_outlined), text: 'الاشتراكات'),
              Tab(icon: Icon(Icons.money_off), text: 'المصروفات'),
              Tab(icon: Icon(Icons.support_agent), text: 'الدعم الفني'),
              Tab(icon: Icon(Icons.system_update), text: 'الإصدارات'),
              Tab(icon: Icon(Icons.bar_chart), text: 'التقارير'),
              Tab(icon: Icon(Icons.dns), text: 'قاعدة البيانات'),
              Tab(icon: Icon(Icons.sync), text: 'المزامنة'),
              Tab(icon: Icon(Icons.people_outline), text: 'المشتركون'),
              Tab(icon: Icon(Icons.settings_suggest_outlined), text: 'التحكم'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            AdminOverviewTab(),
            AdminAuditLogTab(),
            AdminCompaniesTab(),
            AdminExpensesTab(),
            AdminSupportTab(),
            AdminVersionsTab(),
            AdminReportsTab(),
            AdminStorageTab(),
            AdminSyncTab(),
            AdminUsersTab(),
            AdminAppControlTab(),
          ],
        ),
      ),
    );
  }
}

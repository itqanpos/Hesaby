// lib/features/admin/presentation/pages/admin_dashboard_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/platform_admin_provider.dart';
import 'tabs/admin_overview_tab.dart';
import 'tabs/admin_audit_log_tab.dart';
import 'tabs/admin_companies_tab.dart';
import 'tabs/admin_users_tab.dart';
import 'tabs/admin_sync_tab.dart';
import 'tabs/admin_app_control_tab.dart';
import 'tabs/admin_expenses_tab.dart'; // ⬅️ التبويب الجديد

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

    return DefaultTabController(
      length: 7, // ⬅️ زيادة العدد
      child: AppShell(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'العودة للتطبيق',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.goNamed(AppRouter.homeName),
          ),
          title: const Text('لوحة تحكم المنصة'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            tabs: <Widget>[
              Tab(icon: Icon(Icons.insights), text: 'نظرة عامة'),
              Tab(icon: Icon(Icons.history), text: 'سجل التدقيق'),
              Tab(icon: Icon(Icons.storefront_outlined), text: 'الاشتراكات'),
              Tab(icon: Icon(Icons.money_off), text: 'المصروفات'), // ⬅️ التبويب الجديد
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
            AdminExpensesTab(), // ⬅️ التبويب الجديد
            AdminSyncTab(),
            AdminUsersTab(),
            AdminAppControlTab(),
          ],
        ),
      ),
    );
  }
}

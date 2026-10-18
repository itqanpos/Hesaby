// lib/features/admin/presentation/pages/admin_dashboard_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../providers/platform_admin_provider.dart';
import 'tabs/admin_companies_tab.dart';
import 'tabs/admin_users_tab.dart';
import 'tabs/admin_app_control_tab.dart';

/// Platform Admin Dashboard.
class AdminDashboardPage extends ConsumerWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isAdmin = ref.watch(isPlatformAdminProvider);

    // Security check: Only platform admins can access this page.
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
      length: 3,
      child: AppShell(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'العودة للتطبيق',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.goNamed(AppRouter.homeName),
          ),
          title: const Text('لوحة تحكم المنصة'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(icon: Icon(Icons.storefront_outlined), text: 'الاشتراكات'),
              Tab(icon: Icon(Icons.people_outline), text: 'المشتركون'),
              Tab(icon: Icon(Icons.settings_suggest_outlined), text: 'التحكم'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            AdminCompaniesTab(),
            AdminUsersTab(),
            AdminAppControlTab(),
          ],
        ),
      ),
    );
  }
}

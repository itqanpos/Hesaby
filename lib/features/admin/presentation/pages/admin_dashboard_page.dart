// lib/features/admin/presentation/pages/admin_dashboard_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../providers/platform_admin_provider.dart';

/// Platform Admin Dashboard.
///
/// Contains three main tabs:
/// 1. Companies & Subscriptions
/// 2. Users (Subscribers)
/// 3. App Control (Maintenance, Announcements, Feature Flags)
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
            labelColor: Colors.teal, // يمكن تعديل اللون حسب الثيم
            indicatorColor: Colors.teal,
            tabs: <Widget>[
              Tab(icon: Icon(Icons.storefront_outlined), text: 'الاشتراكات'),
              Tab(icon: Icon(Icons.people_outline), text: 'المشتركون'),
              Tab(icon: Icon(Icons.settings_suggest_outlined), text: 'التحكم'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            _CompaniesTabPlaceholder(),
            _UsersTabPlaceholder(),
            _AppControlTabPlaceholder(),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Placeholders (سيتم استبدالها بالملفات الفعلية لاحقاً)
// ============================================================================

class _CompaniesTabPlaceholder extends StatelessWidget {
  const _CompaniesTabPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('تبويب الشركات والاشتراكات (قيد الإنشاء...)'),
    );
  }
}

class _UsersTabPlaceholder extends StatelessWidget {
  const _UsersTabPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('تبويب المشتركين (قيد الإنشاء...)'),
    );
  }
}

class _AppControlTabPlaceholder extends StatelessWidget {
  const _AppControlTabPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('تبويب التحكم في التطبيق (قيد الإنشاء...)'),
    );
  }
}

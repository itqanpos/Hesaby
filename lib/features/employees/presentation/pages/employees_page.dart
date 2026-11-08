// lib/features/employees/presentation/pages/employees_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/entities/employee.dart';
import '../../domain/entities/sales_rep.dart';
import '../../domain/repositories/employee_repository.dart';
import '../../domain/repositories/sales_rep_repository.dart';
import '../providers/employee_providers.dart';
import '../providers/sales_rep_providers.dart';
import '../widgets/employee_form_sheet.dart';
import '../widgets/sales_rep_card.dart';
import '../widgets/sales_rep_form_sheet.dart';
import 'attendance_page.dart';

class EmployeesPage extends ConsumerStatefulWidget {
  const EmployeesPage({super.key});

  @override
  ConsumerState<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends ConsumerState<EmployeesPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _repSearchController = TextEditingController();
  late final TabController _tabController;
  String _query = '';
  String _repQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _repSearchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  List<Employee> _filter(List<Employee> all) {
    final String q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((Employee e) {
      return e.fullName.toLowerCase().contains(q) ||
          (e.position ?? '').toLowerCase().contains(q) ||
          (e.phone ?? '').contains(q) ||
          (e.nationalId ?? '').contains(q) ||
          (e.loginCode ?? '').toLowerCase().contains(q);
    }).toList(growable: false);
  }

  List<SalesRep> _filterReps(List<SalesRep> all) {
    final String q = _repQuery.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((SalesRep r) {
      return r.fullName.toLowerCase().contains(q) ||
          r.branchName.toLowerCase().contains(q) ||
          (r.phone ?? '').contains(q) ||
          (r.employeeCode ?? '').toLowerCase().contains(q);
    }).toList(growable: false);
  }

  // ============== الموظفون: نفس منطق الأصل ==============

  Future<void> _openForm({Employee? existing}) async {
    final bool? saved = await showEmployeeFormSheet(
      context: context,
      existing: existing,
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(existing == null
                ? 'تم إضافة الموظف'
                : 'تم تحديث بيانات الموظف'),
          ),
        );
    }
  }

  Future<void> _createLogin(Employee employee) async {
    final bool? saved = await showCreateLoginDialog(
      context: context,
      employee: employee,
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تم إنشاء حساب الدخول.')),
        );
    }
  }

  Future<void> _confirmDelete(Employee employee) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('حذف الموظف'),
        content: Text(
          'هل تريد حذف "${employee.fullName}"؟\n'
          'لا يمكن التراجع عن هذا الإجراء.',
        ),
        actions: <Widget>[
          AppButton(
            label: 'إلغاء',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          AppButton(
            label: 'حذف',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(employeesProvider.notifier).delete(employee.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الموظف')),
      );
    } on EmployeeException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_failureMessage(e.type))),
      );
    }
  }

  Future<void> _toggleActive(Employee employee) async {
    try {
      await ref.read(employeesProvider.notifier).updateEmployee(
            employeeId: employee.id,
            isActive: !employee.isActive,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            employee.isActive ? 'تم تعطيل الموظف' : 'تم تفعيل الموظف',
          ),
        ),
      );
    } on EmployeeException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_failureMessage(e.type))),
      );
    }
  }

  // ============== المندوبون ==============

  Future<void> _openRepForm({SalesRep? existing}) async {
    // تأكد من تحميل المرشحين
    if (!ref.read(repCandidatesProvider).hasValue) {
      try {
        await ref.read(repCandidatesProvider.future);
      } on Object {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر تحميل قائمة المرشحين')),
        );
        return;
      }
    }
    if (!mounted) return;
    final candidates = ref.read(repCandidatesProvider).valueOrNull ?? const [];
    final bool? saved = await showSalesRepFormSheet(
      context: context,
      candidates: candidates,
      existing: existing,
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(existing == null
                ? 'تم إضافة المندوب'
                : 'تم تحديث بيانات المندوب'),
          ),
        );
    }
  }

  Future<void> _toggleRepActive(SalesRep rep) async {
    try {
      await ref.read(salesRepsProvider.notifier).toggleActive(rep);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            rep.isActive ? 'تم تعطيل المندوب' : 'تم تفعيل المندوب',
          ),
        ),
      );
    } on SalesRepException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_salesRepFailureMessage(e.type))),
      );
    }
  }

  // ============== build ==============

  @override
  Widget build(BuildContext context) {
    return AppShell(
      appBar: AppBar(
        title: const Text('الفريق'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const <Widget>[
            Tab(text: 'الموظفون', icon: Icon(Icons.badge_outlined, size: 18)),
            Tab(text: 'المندوبون', icon: Icon(Icons.store_outlined, size: 18)),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'الصلاحيات والأدوار',
            icon: const Icon(Icons.admin_panel_settings_outlined),
            onPressed: () => context.pushNamed(AppRouter.membersName),
          ),
          IconButton(
            tooltip: 'سجل الحضور',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AttendancePage(),
                ),
              );
            },
          ),
          if (_tabController.index == 0)
            IconButton(
              tooltip: ref.watch(employeesIncludeInactiveProvider)
                  ? 'إخفاء غير النشطين'
                  : 'إظهار غير النشطين',
              icon: Icon(
                ref.watch(employeesIncludeInactiveProvider)
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () => ref
                  .read(employeesIncludeInactiveProvider.notifier)
                  .toggle(),
            ),
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (_tabController.index == 0) {
                ref.read(employeesProvider.notifier).refresh();
              } else {
                ref.read(salesRepsProvider.notifier).refresh();
                ref.invalidate(repCandidatesProvider);
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_tabController.index == 0) {
            _openForm();
          } else {
            _openRepForm();
          }
        },
        icon: Icon(_tabController.index == 0
            ? Icons.person_add_alt
            : Icons.storefront_outlined),
        label: Text(_tabController.index == 0 ? 'موظف جديد' : 'مندوب جديد'),
      ),
      body: TabBarView(
        controller: _tabController,
        children: <Widget>[
          _buildEmployeesTabContent(),
          _buildSalesRepsTabContent(),
        ],
      ),
    );
  }

  // ── محتوى تبويب الموظفين (منقول كما هو تقريبًا) ──
  Widget _buildEmployeesTabContent() {
    final AsyncValue<List<Employee>> async = ref.watch(employeesProvider);
    return async.when(
      loading: () => const AppLoader(),
      error: (Object e, StackTrace _) => AppErrorView(
        title: 'تعذّر تحميل الموظفين',
        message: e is EmployeeException
            ? _failureMessage(e.type)
            : 'حدث خطأ غير متوقع.',
        retryLabel: 'إعادة المحاولة',
        onRetry: () => ref.read(employeesProvider.notifier).refresh(),
      ),
      data: (List<Employee> all) {
        final List<Employee> filtered = _filter(all);
        final int total = all.length;
        final int active = all.where((Employee e) => e.isActive).length;
        final int withAccount =
            all.where((Employee e) => e.hasAccount).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: _KpiRow(
                total: total,
                active: active,
                withAccount: withAccount,
                employees: all,
              ),
            ),
            AppTextField(
              controller: _searchController,
              hint: 'ابحث بالاسم أو المسمى أو الهاتف أو الكود',
              prefixIcon: Icons.search,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'مسح',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
              onChanged: (String v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? AppEmptyView(
                      icon: all.isEmpty
                          ? Icons.badge_outlined
                          : Icons.search_off_outlined,
                      title: all.isEmpty ? 'لا يوجد موظفون' : 'لا نتائج',
                      message: all.isEmpty
                          ? 'ابدأ بإضافة أول موظف لشركتك.'
                          : 'لم يُطابق أي موظف البحث.',
                      action: all.isEmpty
                          ? AppButton(
                              label: 'إضافة موظف',
                              icon: Icons.person_add_alt,
                              onPressed: () => _openForm(),
                            )
                          : null,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 90),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (BuildContext _, int i) {
                        final Employee e = filtered[i];
                        return _EmployeeCard(
                          employee: e,
                          onEdit: () => _openForm(existing: e),
                          onDelete: () => _confirmDelete(e),
                          onToggleActive: () => _toggleActive(e),
                          onCreateLogin: () => _createLogin(e),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  // ── محتوى تبويب المندوبين (جديد) ──
  Widget _buildSalesRepsTabContent() {
    final AsyncValue<List<SalesRep>> async = ref.watch(salesRepsProvider);
    return async.when(
      loading: () => const AppLoader(),
      error: (Object e, StackTrace _) => AppErrorView(
        title: 'تعذّر تحميل المندوبين',
        message: e is SalesRepException
            ? _salesRepFailureMessage(e.type)
            : 'حدث خطأ غير متوقع.',
        retryLabel: 'إعادة المحاولة',
        onRetry: () => ref.read(salesRepsProvider.notifier).refresh(),
      ),
      data: (List<SalesRep> all) {
        final List<SalesRep> filtered = _filterReps(all);
        final int total = all.length;
        final int active = all.where((SalesRep r) => r.isActive).length;
        final int withCustody = all
            .where((SalesRep r) => r.isActive && r.hasCustody)
            .length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: _RepsKpiRow(
                total: total,
                active: active,
                withCustody: withCustody,
              ),
            ),
            AppTextField(
              controller: _repSearchController,
              hint: 'ابحث بالاسم أو الفرع أو الهاتف',
              prefixIcon: Icons.search,
              suffixIcon: _repQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'مسح',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _repSearchController.clear();
                        setState(() => _repQuery = '');
                      },
                    ),
              onChanged: (String v) => setState(() => _repQuery = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? AppEmptyView(
                      icon: all.isEmpty
                          ? Icons.storefront_outlined
                          : Icons.search_off_outlined,
                      title: all.isEmpty ? 'لا يوجد مندوبون' : 'لا نتائج',
                      message: all.isEmpty
                          ? 'أضف أول مندوب من فريق عملك.'
                          : 'لم يُطابق أي مندوب البحث.',
                      action: all.isEmpty
                          ? AppButton(
                              label: 'إضافة مندوب',
                              icon: Icons.storefront_outlined,
                              onPressed: () => _openRepForm(),
                            )
                          : null,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 90),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (BuildContext _, int i) {
                        final SalesRep r = filtered[i];
                        return SalesRepCard(
                          rep: r,
                          onEdit: () => _openRepForm(existing: r),
                          onToggleActive: () => _toggleRepActive(r),
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
// KPI للمندوبين (جديد)
// ============================================================================

class _RepsKpiRow extends StatelessWidget {
  const _RepsKpiRow({
    required this.total,
    required this.active,
    required this.withCustody,
  });

  final int total;
  final int active;
  final int withCustody;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _KpiCard(
            icon: Icons.storefront_outlined,
            label: 'الكل',
            value: AppFormatters.integer(total),
            color: const Color(0xFF0288D1),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            icon: Icons.check_circle_outline,
            label: 'نشط',
            value: AppFormatters.integer(active),
            color: const Color(0xFF0F7B6C),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            icon: Icons.inventory_2_outlined,
            label: 'لديه عهدة',
            value: AppFormatters.integer(withCustody),
            color: const Color(0xFF6A1B9A),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Localization (موظفون — كما هو)
// ============================================================================

String _failureMessage(EmployeeFailureType type) => switch (type) {
      EmployeeFailureType.network =>
        'تعذّر الاتصال بالخادم. تحقق من اتصالك.',
      EmployeeFailureType.unauthorized =>
        'لا تملك صلاحية إدارة الموظفين.',
      EmployeeFailureType.notFound => 'الموظف غير موجود.',
      EmployeeFailureType.invalidInput => 'تحقق من البيانات المُدخلة.',
      EmployeeFailureType.codeConflict =>
        'كود الدخول مستخدم بالفعل. اختر كودًا آخر.',
      EmployeeFailureType.alreadyHasAccount =>
        'هذا الموظف لديه حساب دخول بالفعل.',
      EmployeeFailureType.invalidResponse =>
        'تعذّر قراءة البيانات من الخادم.',
      EmployeeFailureType.unknown =>
        'حدث خطأ غير متوقع. حاول مرة أخرى.',
    };

String _salesRepFailureMessage(SalesRepFailureType type) => switch (type) {
      SalesRepFailureType.network =>
        'تعذّر الاتصال بالخادم. تحقق من اتصالك.',
      SalesRepFailureType.unauthorized =>
        'لا تملك صلاحية إدارة المندوبين.',
      SalesRepFailureType.permissionDenied =>
        'يتطلب دور مالك أو مدير أو مشرف.',
      SalesRepFailureType.validationFailed =>
        'تحقق من البيانات المُدخلة.',
      SalesRepFailureType.notFound => 'المندوب غير موجود.',
      SalesRepFailureType.invalidResponse =>
        'تعذّر قراءة البيانات من الخادم.',
      SalesRepFailureType.unknown =>
        'حدث خطأ غير متوقع. حاول مرة أخرى.',
    };

// ============================================================================
// Widgets مشتركة — مستوردة من الأصل (لم تُعدّل)
// ============================================================================

// _KpiRow, _KpiCard, _EmployeeCard, _Badge, _EmployeeAction, showCreateLoginDialog
// — كل هذه تُنسخ **كما هي** من ملفك الأصلي (لم تُعدّل).

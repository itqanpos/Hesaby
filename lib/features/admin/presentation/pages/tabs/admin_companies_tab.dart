// lib/features/admin/presentation/pages/tabs/admin_companies_tab.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../shared/widgets/app_empty.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loader.dart';
import '../../../../../shared/widgets/app_text_field.dart';
import '../../../../companies/domain/entities/company.dart';
import '../../../../companies/domain/entities/company_subscription.dart';
import '../../../../companies/domain/repositories/company_repository.dart';
import '../../dialogs/admin_company_actions_dialog.dart';
import '../../dialogs/admin_company_payments_dialog.dart';
import '../../providers/admin_companies_provider.dart';

/// هل الشركة على ترخيص "مدى الحياة"؟
///
/// مصدر الحقيقة في DB هو `companies.is_lifetime`، لكن هذا الملف يعتمد على
/// `billing_cycle == 'lifetime'` (مطابق لما تفعله دالة SQL في A1) لتجنّب
/// الاعتماد على وجود حقل `isLifetime` في `Company` قبل إضافته.
bool _isLifetime(Company c) => c.billingCycle == 'lifetime';

class AdminCompaniesTab extends ConsumerStatefulWidget {
  const AdminCompaniesTab({super.key});

  @override
  ConsumerState<AdminCompaniesTab> createState() => _AdminCompaniesTabState();
}

class _AdminCompaniesTabState extends ConsumerState<AdminCompaniesTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  _StatusFilter _statusFilter = _StatusFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Filtering
  // ---------------------------------------------------------------------------

  List<Company> _applyFilters(List<Company> companies) {
    final String query = _searchQuery.trim().toLowerCase();

    return companies.where((Company c) {
      if (_statusFilter != _StatusFilter.all) {
        final CompanySubscription sub = CompanySubscription.fromCompany(c);
        final bool lifetime = _isLifetime(c);
        final bool matches = switch (_statusFilter) {
          // نشط = مدفوع، غير منتهٍ، غير lifetime، غير محظور.
          _StatusFilter.active =>
            !c.isSuspended && !lifetime && sub.isActive,
          _StatusFilter.trial =>
            !c.isSuspended && !lifetime && sub.isTrial,
          // منتهي/محظور = محظور (أي نوع) أو منتهي (غير lifetime).
          _StatusFilter.expired =>
            c.isSuspended || (!lifetime && sub.isExpired),
          // مدى الحياة = lifetime وغير محظور.
          _StatusFilter.lifetime => !c.isSuspended && lifetime,
          _StatusFilter.all => true,
        };
        if (!matches) return false;
      }

      if (query.isEmpty) return true;

      final String name = c.name.toLowerCase();
      final String phone = (c.phone ?? '').toLowerCase();
      final String email = (c.email ?? '').toLowerCase();
      return name.contains(query) ||
          phone.contains(query) ||
          email.contains(query);
    }).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _openActions(Company company) async {
    final AdminSubscriptionChoice? choice = await showAdminCompanyActionsDialog(
      context: context,
      company: company,
    );
    if (choice == null || !mounted) return;

    final client = Supabase.instance.client;

    try {
      bool showSnackbar = true;

      switch (choice.action) {
        case AdminSubscriptionAction.cancel:
          await client.rpc('admin_update_subscription', params: <String, Object?>{
            'p_company_id': company.id,
            'p_status': 'cancelled',
            'p_plan_id': company.planId,
            'p_billing_cycle': company.billingCycle,
            'p_subscribed_until': company.subscribedUntil?.toIso8601String(),
          });

        case AdminSubscriptionAction.suspend:
          final String? reason = choice.reason;
          if (reason == null || reason.trim().length < 5) {
            // دفاعي: الحوار يفرض السبب، لكن لا نفترض.
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('سبب الإيقاف مطلوب.')),
            );
            return;
          }
          await client.rpc('admin_suspend_company', params: <String, Object?>{
            'p_company_id': company.id,
            'p_suspend': true,
            'p_reason': reason.trim(),
          });

        case AdminSubscriptionAction.unsuspend:
          await client.rpc('admin_suspend_company', params: <String, Object?>{
            'p_company_id': company.id,
            'p_suspend': false,
          });

        case AdminSubscriptionAction.renew:
          final String? cycle = choice.billingCycle;
          final String? planId = choice.planId;
          if (cycle == null || planId == null) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('بيانات التجديد غير مكتملة.')),
            );
            return;
          }

          // احسب subscribed_until فقط إذا لم يكن lifetime.
          String? newUntilIso;
          if (cycle != 'lifetime') {
            final CompanySubscription sub =
                CompanySubscription.fromCompany(company);
            final DateTime now = DateTime.now().toUtc();
            final DateTime? until = sub.subscribedUntil;
            final DateTime base =
                (sub.isActive && until != null && until.isAfter(now))
                    ? until
                    : now;
            final Duration duration = cycle == 'yearly'
                ? const Duration(days: 365)
                : const Duration(days: 30);
            newUntilIso = base.add(duration).toIso8601String();
          }
          // lifetime → newUntilIso = null → SQL يضبط is_lifetime=true تلقائيًا.

          await client.rpc('admin_update_subscription', params: <String, Object?>{
            'p_company_id': company.id,
            'p_status': 'active',
            'p_plan_id': planId,
            'p_billing_cycle': cycle,
            'p_subscribed_until': newUntilIso,
          });

        case AdminSubscriptionAction.viewPayments:
          if (!mounted) return;
          await showAdminCompanyPaymentsDialog(
            context: context,
            company: company,
          );
          if (!mounted) return;
          // نُحدّث القائمة لأن الحوار قد يُغيّر حالة الاشتراك (مثلًا دفع فاتورة).
          showSnackbar = false;
      }

      await ref.read(adminCompaniesProvider.notifier).refresh();

      if (!mounted) return;
      if (showSnackbar) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('تم تحديث بيانات الشركة')),
          );
      }
    } on PostgrestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: ${error.message}')),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر إتمام العملية. حاول مرة أخرى.')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------
  //
  // ملاحظة: الخط الافتراضي في PDF هو Helvetica (لا يدعم العربية) — الأسماء
  // العربية ستظهر كمربعات. إصلاحه يتطلب تضمين خط عربي (Cairo/Noto Naskh) في
  // assets + تحميله عبر rootBundle. مُدرج كـ follow-up خارج نطاق هذه المرحلة
  // لأنه يحتاج ملف font في المستودع.

  Future<void> _exportReport(List<Company> companies) async {
    try {
      final List<List<String>> rows = <List<String>>[
        <String>[
          'Company Name',
          'Status',
          'Plan',
          'Billing Cycle',
          'Subscribed Until',
          'Suspended',
          'Suspension Reason',
          'Max Users',
          'Max Branches',
          'Phone',
          'Email',
        ],
      ];

      for (final Company c in companies) {
        final CompanySubscription sub = CompanySubscription.fromCompany(c);
        final bool lifetime = _isLifetime(c);
        final String status = c.isSuspended
            ? 'Suspended'
            : lifetime
                ? 'Lifetime'
                : sub.isActive
                    ? 'Active'
                    : sub.isTrial
                        ? 'Trial'
                        : 'Expired';
        rows.add(<String>[
          c.name,
          status,
          c.planId ?? '-',
          c.billingCycle ?? '-',
          lifetime ? 'Lifetime' : (c.subscribedUntil?.toIso8601String() ?? '-'),
          c.isSuspended ? 'Yes' : 'No',
          c.suspensionReason ?? '-',
          c.maxUsers.toString(),
          c.maxBranches.toString(),
          c.phone ?? '-',
          c.email ?? '-',
        ]);
      }

      final pw.Document doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          build: (pw.Context context) {
            return <pw.Widget>[
              pw.Header(
                level: 0,
                child: pw.Text(
                  'Hesaby — Companies Export',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Generated: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 12),
              pw.TableHelper.fromTextArray(
                headers: rows.first,
                data: rows.skip(1).toList(),
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8,
                ),
                cellStyle: const pw.TextStyle(fontSize: 7),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey300),
                cellPadding: const pw.EdgeInsets.all(3),
                border: pw.TableBorder.all(
                  color: PdfColors.grey600,
                  width: 0.4,
                ),
              ),
            ];
          },
        ),
      );

      final Uint8List pdfBytes = await doc.save();

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename:
            'companies_export_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر التصدير: $e')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Company>> companiesAsync =
        ref.watch(adminCompaniesProvider);

    return companiesAsync.when(
      loading: () => const AppLoader(),
      error: (Object error, StackTrace _) => AppErrorView(
        title: 'تعذّر تحميل قائمة الشركات',
        message: error is CompanyException
            ? _failureMessage(error.type)
            : 'حدث خطأ غير متوقع. حاول مرة أخرى.',
        retryLabel: 'إعادة المحاولة',
        onRetry: () => ref.read(adminCompaniesProvider.notifier).refresh(),
      ),
      data: (List<Company> all) {
        final List<Company> filtered = _applyFilters(all);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 12),
              child: _KpiRow(companies: all),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: AppTextField(
                      controller: _searchController,
                      hint: 'ابحث بالاسم أو الهاتف أو البريد',
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
                      onChanged: (String v) {
                        setState(() => _searchQuery = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'تصدير PDF',
                    onPressed: () => _exportReport(filtered),
                    icon: const Icon(Icons.download),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _StatusFilterBar(
                current: _statusFilter,
                onChanged: (f) => setState(() => _statusFilter = f),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? AppEmptyView(
                      icon: all.isEmpty
                          ? Icons.apartment_outlined
                          : Icons.search_off_outlined,
                      title: all.isEmpty ? 'لا توجد شركات' : 'لا نتائج',
                      message: all.isEmpty
                          ? 'لم يتم العثور على أي شركة في المنصة.'
                          : 'لا توجد شركات تطابق الفلاتر الحالية.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (BuildContext _, int i) {
                        final Company company = filtered[i];
                        return _CompanyCard(
                          company: company,
                          onTap: () => _openActions(company),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  static String _failureMessage(CompanyFailureType type) => switch (type) {
        CompanyFailureType.network =>
          'تعذّر الاتصال بالخادم. تحقق من اتصالك بالإنترنت.',
        CompanyFailureType.unauthorized =>
          'ليس لديك صلاحية للقيام بهذا الإجراء.',
        CompanyFailureType.noCompanies => 'لا توجد شركات.',
        CompanyFailureType.companyNotAccessible =>
          'لا يمكن الوصول إلى هذه الشركة.',
        CompanyFailureType.noBranches => 'لا توجد فروع.',
        CompanyFailureType.invalidResponse =>
          'تعذّر قراءة البيانات من الخادم.',
        CompanyFailureType.unknown =>
          'حدث خطأ غير متوقع. حاول مرة أخرى.',
      };
}

// ============================================================================
// Status filter
// ============================================================================

enum _StatusFilter { all, active, trial, expired, lifetime }

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({
    required this.current,
    required this.onChanged,
  });

  final _StatusFilter current;
  final ValueChanged<_StatusFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final _StatusFilter f in _StatusFilter.values) ...<Widget>[
            ChoiceChip(
              label: Text(_label(f)),
              selected: current == f,
              onSelected: (_) => onChanged(f),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  static String _label(_StatusFilter f) => switch (f) {
        _StatusFilter.all => 'الكل',
        _StatusFilter.active => 'نشط',
        _StatusFilter.trial => 'تجربة',
        _StatusFilter.expired => 'منتهي/محظور',
        _StatusFilter.lifetime => 'مدى الحياة',
      };
}

// ============================================================================
// KPI row
// ============================================================================

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.companies});

  final List<Company> companies;

  @override
  Widget build(BuildContext context) {
    int active = 0;
    int trial = 0;
    int expired = 0;
    for (final Company c in companies) {
      if (c.isSuspended) {
        expired++;
      } else if (_isLifetime(c)) {
        // مدى الحياة يُحسب ضمن "نشط" في KPI (لكن الفلتر يفصله).
        active++;
      } else {
        final CompanySubscription sub = CompanySubscription.fromCompany(c);
        if (sub.isExpired) {
          expired++;
        } else if (sub.isTrial) {
          trial++;
        } else if (sub.isActive) {
          active++;
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _KpiCard(
              label: 'الكل',
              value: companies.length.toString(),
              color: const Color(0xFF0288D1),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _KpiCard(
              label: 'نشط',
              value: active.toString(),
              color: const Color(0xFF0F7B6C),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _KpiCard(
              label: 'تجربة',
              value: trial.toString(),
              color: const Color(0xFFEF6C00),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _KpiCard(
              label: 'منتهي/محظور',
              value: expired.toString(),
              color: const Color(0xFFC62828),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Company card
// ============================================================================

class _CompanyCard extends StatelessWidget {
  const _CompanyCard({required this.company, required this.onTap});

  final Company company;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final CompanySubscription sub = CompanySubscription.fromCompany(company);
    final bool lifetime = _isLifetime(company);
    final _BadgeVisual badge = _resolveBadge(company, sub, scheme);

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: company.isSuspended
                  ? scheme.error
                  : scheme.outlineVariant,
              width: company.isSuspended ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 22,
                backgroundColor: company.isSuspended
                    ? scheme.errorContainer
                    : scheme.primaryContainer,
                foregroundColor: company.isSuspended
                    ? scheme.onErrorContainer
                    : scheme.onPrimaryContainer,
                child: Text(
                  company.name.isEmpty
                      ? '?'
                      : company.name.characters.first.toUpperCase(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      company.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: badge.background,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            badge.label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: badge.foreground,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (!company.isSuspended &&
                            (lifetime || sub.isActive) &&
                            sub.plan != null) ...<Widget>[
                          const SizedBox(width: 6),
                          Text(
                            sub.plan!.label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '👥 ${company.maxUsers} مستخدم · 🏢 ${company.maxBranches} فرع',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    // سبب الإيقاف (إن وُجد) — A3
                    if (company.isSuspended &&
                        company.suspensionReason != null &&
                        company.suspensionReason!.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.info_outline,
                                size: 12, color: scheme.error),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                company.suspensionReason!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.error,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_left,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static _BadgeVisual _resolveBadge(
    Company company,
    CompanySubscription sub,
    ColorScheme scheme,
  ) {
    if (company.isSuspended) {
      return _BadgeVisual(
        label: 'محظور',
        background: scheme.error,
        foreground: scheme.onError,
      );
    }
    if (_isLifetime(company)) {
      return _BadgeVisual(
        label: 'مدى الحياة',
        background: const Color(0xFFE1BEE7),
        foreground: const Color(0xFF6A1B9A),
      );
    }
    if (sub.isExpired) {
      return _BadgeVisual(
        label: 'منتهي',
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
      );
    }
    if (sub.isTrial) {
      final int? d = sub.daysRemaining;
      return _BadgeVisual(
        label: d == null ? 'تجربة' : 'تجربة · $d يوم',
        background: const Color(0xFFFFECB3),
        foreground: const Color(0xFF8D6E00),
      );
    }
    final int? d = sub.daysRemaining;
    return _BadgeVisual(
      label: d == null ? 'نشط' : 'نشط · $d يوم',
      background: const Color(0xFFC8E6C9),
      foreground: const Color(0xFF1B5E20),
    );
  }
}

class _BadgeVisual {
  const _BadgeVisual({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;
}

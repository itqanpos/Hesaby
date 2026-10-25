// lib/features/admin/presentation/pages/tabs/admin_reports_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../shared/widgets/app_button.dart';

// ============================================================================
// Providers
// ============================================================================

final companiesReportProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final client = Supabase.instance.client;
  final response = await client.from('companies').select().order('created_at', ascending: false);
  return (response as List).whereType<Map<String, dynamic>>().toList();
});

final revenueReportProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final client = Supabase.instance.client;
  final response = await client
      .from('subscription_payments')
      .select('*, companies(name), subscription_plans(label)')
      .order('payment_date', ascending: false);
  return (response as List).whereType<Map<String, dynamic>>().toList();
});

final usersReportProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final client = Supabase.instance.client;
  final response = await client.rpc('get_admin_users');
  if (response is! List) return <Map<String, dynamic>>[];
  return response.whereType<Map<String, dynamic>>().toList();
});

// ============================================================================
// UI
// ============================================================================

class AdminReportsTab extends ConsumerWidget {
  const AdminReportsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const <Widget>[
        _ReportCard(
          title: 'تقرير الشركات',
          description: 'قائمة كاملة بجميع الشركات المسجلة، مع تاريخ التسجيل وحالة النشاط.',
          icon: Icons.business,
          color: Color(0xFF0288D1),
          reportType: _ReportType.companies,
        ),
        SizedBox(height: 12),
        _ReportCard(
          title: 'تقرير الإيرادات',
          description: 'كل عمليات الدفع والاشتراكات، مع أسماء الشركات والخطط.',
          icon: Icons.payments,
          color: Color(0xFF0F7B6C),
          reportType: _ReportType.revenue,
        ),
        SizedBox(height: 12),
        _ReportCard(
          title: 'تقرير المستخدمين',
          description: 'قائمة بجميع المستخدمين، مع بريدهم وحالة الحساب.',
          icon: Icons.people,
          color: Color(0xFF6A1B9A),
          reportType: _ReportType.users,
        ),
      ],
    );
  }
}

// ============================================================================
// Report Card
// ============================================================================

enum _ReportType { companies, revenue, users }

class _ReportCard extends ConsumerStatefulWidget {
  const _ReportCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.reportType,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final _ReportType reportType;

  @override
  ConsumerState<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends ConsumerState<_ReportCard> {
  bool _isExporting = false;

  Future<void> _export() async {
    setState(() => _isExporting = true);
    try {
      final (String csvContent, _) = await _generateCsv();
      await Clipboard.setData(ClipboardData(text: csvContent));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم نسخ التقرير إلى الحافظة. يمكنك لصقه في Excel أو محرر نصوص.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء التصدير: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<(String, String)> _generateCsv() async {
    final String dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    switch (widget.reportType) {
      case _ReportType.companies:
        final data = await ref.read(companiesReportProvider.future);
        final buffer = StringBuffer();
        buffer.writeln('اسم الشركة,الهاتف,الحالة,حالة الاشتراك,تاريخ التسجيل');
        for (final c in data) {
          buffer.writeln('${_esc(c['name'])},${_esc(c['phone'])},${c['is_active'] == true ? "نشطة" : "موقوفة"},${_esc(c['subscription_status'])},${_formatDate(c['created_at'])}');
        }
        return (buffer.toString(), 'companies_$dateStr.csv');

      case _ReportType.revenue:
        final data = await ref.read(revenueReportProvider.future);
        final buffer = StringBuffer();
        buffer.writeln('التاريخ,الشركة,الخطة,المبلغ,ملاحظات');
        for (final p in data) {
          buffer.writeln('${_formatDate(p['payment_date'])},${_esc((p['companies'] as Map?)?['name'])},${_esc((p['subscription_plans'] as Map?)?['label'])},${p['amount']?.toString() ?? "0"},${_esc(p['notes'])}');
        }
        return (buffer.toString(), 'revenue_$dateStr.csv');

      case _ReportType.users:
        final data = await ref.read(usersReportProvider.future);
        final buffer = StringBuffer();
        buffer.writeln('الاسم,البريد الإلكتروني,أدمن منصة,تاريخ التسجيل,حالة الحساب');
        for (final u in data) {
          buffer.writeln('${_esc(u['full_name'])},${_esc(u['email'])},${u['is_platform_admin'] == true ? "نعم" : "لا"},${_formatDate(u['created_at'])},${u['banned_until'] != null ? "محظور" : "نشط"}');
        }
        return (buffer.toString(), 'users_$dateStr.csv');
    }
  }

  String _esc(Object? v) {
    if (v == null) return '';
    final String s = v.toString();
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  String _formatDate(Object? v) {
    if (v == null) return '';
    final DateTime? dt = DateTime.tryParse(v.toString())?.toLocal();
    if (dt == null) return v.toString();
    return DateFormat('yyyy/MM/dd HH:mm').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(widget.icon, color: widget.color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(widget.description, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: _isExporting ? 'جاري التصدير...' : 'نسخ التقرير (CSV)',
              icon: Icons.copy,
              isLoading: _isExporting,
              onPressed: _isExporting ? null : _export,
            ),
          ),
        ],
      ),
    );
  }
}

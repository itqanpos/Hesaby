// lib/features/companies/presentation/pages/my_account_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../support/presentation/pages/company_support_page.dart';
import '../domain/entities/company_subscription.dart';
import '../providers/company_context_provider.dart';
import '../providers/subscription_providers.dart';

class MyAccountPage extends ConsumerStatefulWidget {
  const MyAccountPage({super.key});

  @override
  ConsumerState<MyAccountPage> createState() => _MyAccountPageState();
}

class _MyAccountPageState extends ConsumerState<MyAccountPage> {
  final TextEditingController _renewalNotesController = TextEditingController();
  bool _isRequestingRenewal = false;

  @override
  void dispose() {
    _renewalNotesController.dispose();
    super.dispose();
  }

  Future<void> _requestRenewal() async {
    final notes = _renewalNotesController.text.trim();
    final companyId = ref.read(companyContextProvider).currentCompany?.id;
    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (companyId == null || userId == null) return;

    setState(() => _isRequestingRenewal = true);

    try {
      await Supabase.instance.client.from('support_tickets').insert({
        'company_id': companyId,
        'user_id': userId,
        'subject': 'طلب تجديد اشتراك',
        'description': notes.isEmpty ? 'العميل يرغب في تجديد الاشتراك.' : notes,
        'status': 'new',
        'priority': 'high',
      });

      if (!mounted) return;
      _renewalNotesController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال طلب التجديد بنجاح. سيتواصل معك فريق الدعم.')),
      );
      
      ref.invalidate(companyTicketsProvider);
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      if (mounted) setState(() => _isRequestingRenewal = false);
    }
  }

  void _showRenewalDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('طلب تجديد الاشتراك'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('سيتم إرسال طلبك إلى إدارة المنصة للتواصل معك وتحديد طريقة الدفع.'),
            const SizedBox(height: 16),
            AppTextField(
              controller: _renewalNotesController,
              label: 'ملاحظات إضافية (اختياري)',
              hint: 'مثال: أرغب في الدفع عن طريق التحويل البنكي',
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          AppButton(
            label: 'إرسال الطلب',
            isLoading: _isRequestingRenewal,
            onPressed: _isRequestingRenewal ? null : _requestRenewal,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final CompanySubscription? subscription = ref.watch(subscriptionProvider);

    return AppShell(
      appBar: AppBar(title: const Text('حسابي')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          // ⬇️ القسم الأول: تفاصيل الاشتراك
          _SectionHeader(title: 'تفاصيل الاشتراك', icon: Icons.workspace_premium),
          const SizedBox(height: 8),
          _SubscriptionCard(
            subscription: subscription,
            onRenew: _showRenewalDialog,
          ),

          const SizedBox(height: 24),

          // ⬇️ القسم الثاني: الدعم الفني
          _SectionHeader(title: 'تذاكر الدعم الفني', icon: Icons.support_agent),
          const SizedBox(height: 8),
          const _SupportSection(),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ============================================================================
// Subscription Section
// ============================================================================

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.subscription, required this.onRenew});

  final CompanySubscription? subscription;
  final VoidCallback onRenew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final String planName = subscription?.plan?.label ?? 'تجربة مجانية';
    final String status = subscription?.isExpired == true
        ? 'منتهي'
        : (subscription?.isTrial == true ? 'تجريبي' : 'نشط');
    
    final int? daysLeft = subscription?.daysRemaining;
    final DateTime? endDate = subscription?.subscribedUntil;

    final Color statusColor = subscription?.isExpired == true
        ? scheme.error
        : (daysLeft != null && daysLeft <= 7 ? const Color(0xFFEF6C00) : const Color(0xFF0F7B6C));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.verified, color: statusColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(planName, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    Text('الحالة: $status', style: theme.textTheme.bodySmall?.copyWith(color: statusColor, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          if (endDate != null) ...[
            _InfoRow(label: 'تاريخ الانتهاء', value: DateFormat('yyyy/MM/dd').format(endDate)),
            if (daysLeft != null) ...[
              const SizedBox(height: 8),
              _InfoRow(
                label: 'المتبقي',
                value: daysLeft > 0 ? '$daysLeft يوم' : 'انتهى',
                valueColor: statusColor,
              ),
            ],
          ] else
            const _InfoRow(label: 'تاريخ الانتهاء', value: 'غير محدد'),

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: subscription?.isExpired == true ? 'تجديد الاشتراك الآن' : 'طلب تجديد مبكر',
              icon: Icons.autorenew,
              onPressed: onRenew,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Support Section
// ============================================================================

class _SupportSection extends ConsumerWidget {
  const _SupportSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTickets = ref.watch(companyTicketsProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return asyncTickets.when(
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
      error: (e, _) => Text('خطأ في تحميل التذاكر: $e', style: TextStyle(color: scheme.error)),
      data: (tickets) {
        if (tickets.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: scheme.outlineVariant)),
            child: Column(
              children: [
                const AppEmptyView(icon: Icons.support_agent, title: 'لا توجد تذاكر', message: 'إذا واجهت مشكلة، يمكنك فتح تذكرة جديدة.'),
                const SizedBox(height: 12),
                AppButton(label: 'فتح صفحة الدعم', icon: Icons.add, onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const CompanySupportPage()));
                }),
              ],
            ),
          );
        }

        return Column(
          children: <Widget>[
            ...tickets.take(3).map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TicketCard(ticket: t),
            )),
            if (tickets.length > 3)
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompanySupportPage())),
                child: Text('عرض كل التذاكر (${tickets.length})'),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: 'فتح تذكرة جديدة',
                icon: Icons.add,
                variant: AppButtonVariant.outline,
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const CompanySupportPage()));
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket});
  final CompanyTicket ticket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ticket.subject, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(DateFormat('yyyy/MM/dd').format(ticket.createdAt), style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: ticket.status == 'resolved' ? const Color(0xFFC8E6C9) : scheme.errorContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              ticket.statusLabel,
              style: TextStyle(
                color: ticket.status == 'resolved' ? const Color(0xFF1B5E20) : scheme.onErrorContainer,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Helpers
// ============================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: valueColor)),
      ],
    );
  }
}

// lib/features/admin/presentation/dialogs/admin_company_actions_dialog.dart

import 'package:flutter/material.dart';
import '../../../companies/domain/entities/company.dart';
import '../../../companies/domain/entities/company_subscription.dart';

enum AdminSubscriptionAction {
  renew,
  cancel,
  suspend,
  unsuspend,
  viewPayments,
}

class AdminSubscriptionChoice {
  const AdminSubscriptionChoice({
    required this.action,
    this.planId,
    this.billingCycle,
  });

  final AdminSubscriptionAction action;
  final String? planId;
  final String? billingCycle;
}

/// Opens the actions dialog for a company.
Future<AdminSubscriptionChoice?> showAdminCompanyActionsDialog({
  required BuildContext context,
  required Company company,
}) {
  return showModalBottomSheet<AdminSubscriptionChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (BuildContext ctx) => _AdminCompanyActionsSheet(company: company),
  );
}

class _AdminCompanyActionsSheet extends StatefulWidget {
  const _AdminCompanyActionsSheet({required this.company});

  final Company company;

  @override
  State<_AdminCompanyActionsSheet> createState() =>
      _AdminCompanyActionsSheetState();
}

class _AdminCompanyActionsSheetState
    extends State<_AdminCompanyActionsSheet> {
  String _planId = 'pro';
  String _billingCycle = 'monthly';
  bool _isSuspended = false;

  @override
  void initState() {
    super.initState();
    final sub = CompanySubscription.fromCompany(widget.company);
    if (sub.plan != null) {
      _planId = sub.plan!.id;
    }
    // Note: We need to read isSuspended from the company object (assuming it was updated)
    // For now, we will use a local variable and let the parent handle the actual API call.
    // _isSuspended = widget.company.isSuspended; 
  }

  void _submit(AdminSubscriptionAction action) {
    Navigator.of(context).pop(
      AdminSubscriptionChoice(
        action: action,
        planId: _planId,
        billingCycle: _billingCycle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: [
              Icon(Icons.business, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.company.name,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          // 1. Renew / Change Plan
          Text('تجديد الاشتراك', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'basic', label: Text('أساسي')),
                    ButtonSegment(value: 'pro', label: Text('احترافي')),
                  ],
                  selected: {_planId},
                  onSelectionChanged: (s) => setState(() => _planId = s.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'monthly', label: Text('شهري')),
                    ButtonSegment(value: 'yearly', label: Text('سنوي')),
                  ],
                  selected: {_billingCycle},
                  onSelectionChanged: (s) => setState(() => _billingCycle = s.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _submit(AdminSubscriptionAction.renew),
            icon: const Icon(Icons.check_circle),
            label: const Text('تجديد الآن'),
          ),
          
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          // 2. Suspend Company
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.block, color: scheme.error),
            title: const Text('تعليق الشركة (حظر)'),
            subtitle: const Text('إيقاف وصول جميع المستخدمين لهذه الشركة.'),
            onTap: () => _submit(AdminSubscriptionAction.suspend),
          ),
          
          // 3. View Payments
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.receipt_long, color: scheme.primary),
            title: const Text('سجل المدفوعات'),
            subtitle: const Text('عرض تاريخ الدفعات السابقة.'),
            onTap: () => _submit(AdminSubscriptionAction.viewPayments),
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          // 4. Cancel Subscription
          OutlinedButton.icon(
            onPressed: () => _submit(AdminSubscriptionAction.cancel),
            icon: Icon(Icons.cancel, color: scheme.error),
            label: Text('إلغاء الاشتراك', style: TextStyle(color: scheme.error)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
            ),
          ),
        ],
      ),
    );
  }
}

// lib/features/admin/presentation/dialogs/admin_company_payments_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../companies/domain/entities/company.dart';

// ============================================================================
// Provider
// ============================================================================

final companyPaymentsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
        (ref, companyId) async {
  final client = Supabase.instance.client;
  final response = await client
      .from('subscription_payments')
      .select()
      .eq('company_id', companyId)
      .order('created_at', ascending: false);

  return List<Map<String, dynamic>>.from(response);
});

// ============================================================================
// Dialog
// ============================================================================

Future<void> showAdminCompanyPaymentsDialog({
  required BuildContext context,
  required Company company,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext ctx) => _AdminCompanyPaymentsDialog(company: company),
  );
}

class _AdminCompanyPaymentsDialog extends ConsumerStatefulWidget {
  const _AdminCompanyPaymentsDialog({required this.company});

  final Company company;

  @override
  ConsumerState<_AdminCompanyPaymentsDialog> createState() =>
      _AdminCompanyPaymentsDialogState();
}

class _AdminCompanyPaymentsDialogState
    extends ConsumerState<_AdminCompanyPaymentsDialog> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  String _paymentMethod = 'cash';
  bool _isSaving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _addPayment() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال مبلغ صحيح.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final client = Supabase.instance.client;
      await client.from('subscription_payments').insert({
        'company_id': widget.company.id,
        'amount': amount,
        'payment_method': _paymentMethod,
        'notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      });

      if (!mounted) return;
      _amountController.clear();
      _notesController.clear();
      
      // Refresh the list
      ref.invalidate(companyPaymentsProvider(widget.company.id));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل الدفعة بنجاح.')),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: ${e.message}')),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر حفظ الدفعة.')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final paymentsAsync = ref.watch(companyPaymentsProvider(widget.company.id));

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Header
              Row(
                children: [
                  Icon(Icons.receipt_long, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'سجل المدفوعات - ${widget.company.name}',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(),

              // Add Payment Form
              Text('تسجيل دفعة جديدة', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: _amountController,
                      label: 'المبلغ',
                      hint: '0.00',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _paymentMethod,
                      decoration: const InputDecoration(
                        labelText: 'طريقة الدفع',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('نقدي')),
                        DropdownMenuItem(value: 'card', child: Text('بطاقة')),
                        DropdownMenuItem(value: 'bank', child: Text('تحويل بنكي')),
                      ],
                      onChanged: (v) => setState(() => _paymentMethod = v ?? 'cash'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AppTextField(
                controller: _notesController,
                label: 'ملاحظات (اختياري)',
                hint: 'مثال: تجديد سنوي',
              ),
              const SizedBox(height: 8),
              AppButton(
                label: 'إضافة الدفعة',
                icon: Icons.add,
                expanded: true,
                isLoading: _isSaving,
                onPressed: _isSaving ? null : _addPayment,
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // History List
              Text('الدفعات السابقة', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: paymentsAsync.when(
                  loading: () => const AppLoader(),
                  error: (e, _) => Center(child: Text('خطأ: $e')),
                  data: (payments) {
                    if (payments.isEmpty) {
                      return const Center(child: Text('لا توجد دفعات سابقة.'));
                    }
                    return ListView.separated(
                      itemCount: payments.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final p = payments[index];
                        final amount = (p['amount'] as num).toDouble();
                        final date = DateTime.parse(p['created_at'] as String).toLocal();
                        final method = p['payment_method'] as String;
                        final notes = p['notes'] as String?;

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: scheme.primaryContainer,
                            child: Icon(Icons.attach_money, color: scheme.onPrimaryContainer),
                          ),
                          title: Text(
                            NumberFormat.currency(locale: 'ar_EG', symbol: 'ج.م', decimalDigits: 2).format(amount),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${DateFormat('yyyy/MM/dd - hh:mm a').format(date)}\n'
                            'طريقة الدفع: ${_methodLabel(method)}'
                            '${notes != null ? '\n$notes' : ''}',
                          ),
                          isThreeLine: true,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _methodLabel(String method) {
    switch (method) {
      case 'cash': return 'نقدي';
      case 'card': return 'بطاقة';
      case 'bank': return 'تحويل بنكي';
      default: return method;
    }
  }
}

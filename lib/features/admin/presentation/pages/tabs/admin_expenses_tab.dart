// lib/features/admin/presentation/pages/tabs/admin_expenses_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../shared/widgets/app_button.dart';
import '../../../../../shared/widgets/app_empty.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loader.dart';
import '../../../../../shared/widgets/app_text_field.dart';

// ============================================================================
// Models
// ============================================================================

class OperatingExpense {
  const OperatingExpense({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.expenseDate,
    this.notes,
  });

  final String id;
  final String title;
  final double amount;
  final String category;
  final DateTime expenseDate;
  final String? notes;

  factory OperatingExpense.fromMap(Map<String, dynamic> map) {
    return OperatingExpense(
      id: map['id'] as String,
      title: map['title'] as String? ?? 'مصروف',
      amount: (map['amount'] as num).toDouble(),
      category: map['category'] as String? ?? 'other',
      expenseDate: _parseDate(map['expense_date']),
      notes: map['notes'] as String?,
    );
  }

  static DateTime _parseDate(Object? value) {
    if (value is DateTime) return value.toLocal();
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toLocal();
    }
    return DateTime.now();
  }

  String get categoryLabel {
    switch (category) {
      case 'hosting': return 'استضافة';
      case 'domains': return 'نطاقات';
      case 'support': return 'دعم فني';
      case 'development': return 'تطوير';
      default: return 'أخرى';
    }
  }
}

// ============================================================================
// Provider
// ============================================================================

final expensesProvider = FutureProvider.autoDispose<List<OperatingExpense>>((ref) async {
  final client = Supabase.instance.client;
  final response = await client
      .from('operating_expenses')
      .select()
      .order('expense_date', ascending: false);

  final List<dynamic> data = response as List<dynamic>;
  return data.map((e) => OperatingExpense.fromMap(e as Map<String, dynamic>)).toList();
});

// ============================================================================
// UI
// ============================================================================

class AdminExpensesTab extends ConsumerStatefulWidget {
  const AdminExpensesTab({super.key});

  @override
  ConsumerState<AdminExpensesTab> createState() => _AdminExpensesTabState();
}

class _AdminExpensesTabState extends ConsumerState<AdminExpensesTab> {
  Future<void> _showAddExpenseDialog() async {
    final bool? added = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AddExpenseDialog(),
    );
    if (added == true) {
      ref.invalidate(expensesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إضافة المصروف بنجاح.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncExpenses = ref.watch(expensesProvider);

    return asyncExpenses.when(
      loading: () => const AppLoader(),
      error: (Object error, StackTrace _) => AppErrorView(
        title: 'تعذّر تحميل المصروفات',
        message: 'حدث خطأ: $error',
        retryLabel: 'إعادة المحاولة',
        onRetry: () => ref.invalidate(expensesProvider),
      ),
      data: (List<OperatingExpense> expenses) {
        final totalExpenses = expenses.fold<double>(0, (sum, e) => sum + e.amount);
        final money = NumberFormat.currency(locale: 'en_US', symbol: 'ج.م ');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // إجمالي المصروفات
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFC62828).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFC62828).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.money_off, color: Color(0xFFC62828), size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('إجمالي المصروفات التشغيلية', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        Text(money.format(totalExpenses), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFC62828))),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppButton(
                label: 'إضافة مصروف جديد',
                icon: Icons.add,
                onPressed: _showAddExpenseDialog,
              ),
            ),

            const SizedBox(height: 16),

            Expanded(
              child: expenses.isEmpty
                  ? const AppEmptyView(
                      icon: Icons.receipt,
                      title: 'لا توجد مصروفات',
                      message: 'ابدأ بتسجيل تكاليف الاستضافة والدعم لمعرفة صافي الربح.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: expenses.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        return _ExpenseCard(expense: expenses[index]);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({required this.expense});
  final OperatingExpense expense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = NumberFormat.currency(locale: 'en_US', symbol: 'ج.م ');

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFC62828).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_upward, color: Color(0xFFC62828), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(expense.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  '${expense.categoryLabel} · ${DateFormat('yyyy/MM/dd').format(expense.expenseDate)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (expense.notes != null && expense.notes!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(expense.notes!, style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline)),
                ]
              ],
            ),
          ),
          Text(
            money.format(expense.amount),
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFFC62828)),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Add Expense Dialog
// ============================================================================

class _AddExpenseDialog extends ConsumerStatefulWidget {
  const _AddExpenseDialog();
  @override
  ConsumerState<_AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends ConsumerState<_AddExpenseDialog> {
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _category = 'hosting';
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;

    if (title.isEmpty || amount <= 0) {
      setState(() => _error = 'الرجاء إدخال عنوان ومبلغ صحيحين');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final client = Supabase.instance.client;
      await client.from('operating_expenses').insert({
        'title': title,
        'amount': amount,
        'category': _category,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'created_by': client.auth.currentUser?.id,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() { _isLoading = false; _error = 'خطأ: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة مصروف جديد'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(controller: _titleCtrl, label: 'عنوان المصروف', hint: 'مثال: استضافة Supabase - أكتوبر'),
            const SizedBox(height: 12),
            AppTextField(
              controller: _amountCtrl,
              label: 'المبلغ (ج.م)',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'التصنيف', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'hosting', child: Text('استضافة')),
                DropdownMenuItem(value: 'domains', child: Text('نطاقات')),
                DropdownMenuItem(value: 'support', child: Text('دعم فني')),
                DropdownMenuItem(value: 'development', child: Text('تطوير')),
                DropdownMenuItem(value: 'other', child: Text('أخرى')),
              ],
              onChanged: (v) { if (v != null) setState(() => _category = v); },
            ),
            const SizedBox(height: 12),
            AppTextField(controller: _notesCtrl, label: 'ملاحظات (اختياري)', maxLines: 2),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ]
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _isLoading ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        AppButton(label: 'إضافة', isLoading: _isLoading, onPressed: _isLoading ? null : _submit),
      ],
    );
  }
}

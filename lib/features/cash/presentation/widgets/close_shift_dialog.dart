// lib/features/cash/presentation/widgets/close_shift_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../domain/entities/cash_entities.dart';
import '../../domain/repositories/cash_repository.dart';
import '../providers/cash_providers.dart';

Future<Shift?> showCloseShiftDialog({required BuildContext context, required Shift shift}) {
  return showDialog<Shift>(context: context, barrierDismissible: false, builder: (_) => _CloseShiftDialog(shift: shift));
}

class _CloseShiftDialog extends ConsumerStatefulWidget {
  const _CloseShiftDialog({required this.shift});
  final Shift shift;
  @override
  ConsumerState<_CloseShiftDialog> createState() => _CloseShiftDialogState();
}

class _CloseShiftDialogState extends ConsumerState<_CloseShiftDialog> {
  final _formKey = GlobalKey<FormState>();
  final _actualController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() { _actualController.dispose(); _notesController.dispose(); super.dispose(); }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final actual = double.tryParse(_actualController.text.trim()) ?? 0;
    setState(() { _isSubmitting = true; _error = null; });
    try {
      final closed = await ref.read(activeShiftProvider.notifier).closeShift(actualClosingBalance: actual, notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop(closed);
    } on CashException catch (e) {
      if (!mounted) return;
      setState(() { _isSubmitting = false; _error = _message(e.type); });
    } on Object {
      if (!mounted) return;
      setState(() { _isSubmitting = false; _error = 'تعذّر إغلاق الوردية. حاول مرة أخرى.'; });
    }
  }

  String _message(CashFailureType t) => switch (t) {
    CashFailureType.network => 'تعذّر الاتصال بالخادم.',
    CashFailureType.unauthorized => 'لا تملك صلاحية إغلاق الوردية.',
    CashFailureType.notFound => 'الوردية غير موجودة.',
    CashFailureType.invalidInput => 'تحقق من المبلغ المُدخل.',
    CashFailureType.invalidResponse => 'تعذّر قراءة البيانات.',
    CashFailureType.unknown => 'حدث خطأ غير متوقع.',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(children: [Icon(Icons.stop_circle_outlined, color: scheme.error), const SizedBox(width: 8), const Expanded(child: Text('إغلاق الوردية'))]),
      content: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('الرصيد الافتتاحي: ${AppFormatters.money(widget.shift.openingBalance)}'),
          const SizedBox(height: 8),
          const Text('أدخل مبلغ النقدية الفعلي الموجود في الدرج الآن. سيقوم النظام بحساب الفرق تلقائياً.'),
          const SizedBox(height: 16),
          TextFormField(
            controller: _actualController,
            enabled: !_isSubmitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            textAlign: TextAlign.center,
            decoration: const InputDecoration(labelText: 'النقدية الفعلية', hintText: '0.00', border: OutlineInputBorder(), suffixText: 'ج.م'),
            validator: (v) {
              final d = double.tryParse((v ?? '').trim());
              if (d == null || d < 0) return 'أدخل مبلغاً صحيحاً';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _notesController, enabled: !_isSubmitting, maxLines: 2, decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)', border: OutlineInputBorder())),
          if (_error != null) ...[
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(10)),
              child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [Icon(Icons.error_outline, color: scheme.onErrorContainer), const SizedBox(width: 8), Expanded(child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)))])),
            ),
          ],
        ]),
      ),
      actions: [
        AppButton(label: 'إلغاء', variant: AppButtonVariant.text, onPressed: _isSubmitting ? null : () => Navigator.of(context).pop()),
        AppButton(label: 'إغلاق الوردية', icon: Icons.check_circle_outline, variant: AppButtonVariant.danger, isLoading: _isSubmitting, onPressed: _isSubmitting ? null : _submit),
      ],
    );
  }
}

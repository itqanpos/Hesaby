// lib/features/cash/presentation/widgets/open_shift_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../domain/entities/cash_entities.dart';
import '../../domain/repositories/cash_repository.dart';
import '../providers/cash_providers.dart';

Future<Shift?> showOpenShiftDialog({required BuildContext context}) {
  return showDialog<Shift>(context: context, barrierDismissible: false, builder: (_) => const _OpenShiftDialog());
}

class _OpenShiftDialog extends ConsumerStatefulWidget {
  const _OpenShiftDialog();
  @override
  ConsumerState<_OpenShiftDialog> createState() => _OpenShiftDialogState();
}

class _OpenShiftDialogState extends ConsumerState<_OpenShiftDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() { _amountController.dispose(); super.dispose(); }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final opening = double.tryParse(_amountController.text.trim()) ?? 0;
    setState(() { _isSubmitting = true; _error = null; });
    try {
      final shift = await ref.read(activeShiftProvider.notifier).openShift(openingBalance: opening);
      if (!mounted) return;
      Navigator.of(context).pop(shift);
    } on CashException catch (e) {
      if (!mounted) return;
      setState(() { _isSubmitting = false; _error = _message(e.type); });
    } on Object {
      if (!mounted) return;
      setState(() { _isSubmitting = false; _error = 'تعذّر فتح الوردية. حاول مرة أخرى.'; });
    }
  }

  String _message(CashFailureType t) => switch (t) {
    CashFailureType.network => 'تعذّر الاتصال بالخادم.',
    CashFailureType.unauthorized => 'لا تملك صلاحية فتح وردية.',
    CashFailureType.notFound => 'الحساب غير موجود.',
    CashFailureType.invalidInput => 'تحقق من المبلغ المُدخل.',
    CashFailureType.invalidResponse => 'تعذّر قراءة البيانات.',
    CashFailureType.unknown => 'حدث خطأ غير متوقع.',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(children: [Icon(Icons.play_arrow, color: scheme.primary), const SizedBox(width: 8), const Expanded(child: Text('فتح وردية جديدة'))]),
      content: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('أدخل مبلغ النقدية الافتتاحي (الموجود في الدرج حالياً).'),
          const SizedBox(height: 16),
          TextFormField(
            controller: _amountController,
            enabled: !_isSubmitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            textAlign: TextAlign.center,
            decoration: const InputDecoration(labelText: 'الرصيد الافتتاحي', hintText: '0.00', border: OutlineInputBorder(), suffixText: 'ج.م'),
            validator: (v) {
              final d = double.tryParse((v ?? '').trim());
              if (d == null || d < 0) return 'أدخل مبلغاً صحيحاً';
              return null;
            },
          ),
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
        AppButton(label: 'فتح الوردية', icon: Icons.play_arrow, isLoading: _isSubmitting, onPressed: _isSubmitting ? null : _submit),
      ],
    );
  }
}

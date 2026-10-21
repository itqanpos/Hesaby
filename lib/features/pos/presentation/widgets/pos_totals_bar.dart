// lib/features/pos/presentation/widgets/pos_totals_bar.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../state/pos_providers.dart';

class PosTotalsBar extends ConsumerWidget {
  const PosTotalsBar({super.key});

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final PosTotals totals = ref.watch(posTotalsProvider);

    return Container(
      color: scheme.surface, // ليتناسب مع العمود الأيمن
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _TotalsRow(
            label: 'الأصناف',
            value: totals.lineCount.toString(),
            theme: theme,
          ),
          const SizedBox(height: 6),
          _TotalsRow(
            label: 'الإجمالي',
            value: _money.format(totals.subtotal),
            theme: theme,
          ),
          const SizedBox(height: 8),
          _DiscountRow(
            discount: totals.discount,
            money: _money,
            onChanged: (double value) =>
                ref.read(posCartProvider.notifier).setDiscount(value),
          ),
          const Divider(height: 24),
          _TotalsRow(
            label: 'الصافي',
            value: _money.format(totals.total),
            theme: theme,
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

// ... (باقي كلاسات _TotalsRow و _DiscountRow كما هي في كودك السابق بدون أي تغيير) ...
class _TotalsRow extends StatelessWidget {
  const _TotalsRow({
    required this.label,
    required this.value,
    required this.theme,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final ThemeData theme;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = theme.colorScheme;
    final TextStyle? labelStyle = emphasized
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.bodyMedium;
    final TextStyle? valueStyle = emphasized
        ? theme.textTheme.headlineSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800)
        : theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600);

    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: labelStyle)),
        Text(value, style: valueStyle),
      ],
    );
  }
}

class _DiscountRow extends StatefulWidget {
  const _DiscountRow({
    required this.discount,
    required this.money,
    required this.onChanged,
  });

  final double discount;
  final NumberFormat money;
  final ValueChanged<double> onChanged;

  @override
  State<_DiscountRow> createState() => _DiscountRowState();
}

class _DiscountRowState extends State<_DiscountRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatDiscount(widget.discount));
    _focusNode = FocusNode();
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(_DiscountRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.discount != oldWidget.discount && !_focusNode.hasFocus) {
      _controller.text = _formatDiscount(widget.discount);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final double parsed = double.tryParse(_controller.text.trim()) ?? 0;
    widget.onChanged(parsed);
  }

  static String _formatDiscount(double value) {
    if (value == 0) return '';
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        SizedBox(width: 76, child: Text('الخصم', style: theme.textTheme.bodyMedium)),
        const Spacer(),
        SizedBox(
          width: 110,
          height: 40,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            textAlign: TextAlign.center,
            textAlignVertical: TextAlignVertical.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: '0',
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text('ج.م', style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

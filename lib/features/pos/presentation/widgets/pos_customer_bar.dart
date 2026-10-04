// lib/features/pos/presentation/widgets/pos_customer_bar.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../sales/domain/entities/sale_entities.dart';
import '../../../sales/presentation/providers/sales_providers.dart';
import '../../domain/entities/pos_cart.dart';
import '../state/pos_providers.dart';

/// Compact bar showing the customer attached to the POS cart.
///
/// Behaviour:
/// * Default: "عميل نقدي" + a "تغيير" button that opens a picker.
/// * With a customer attached: name (and outstanding balance when > 0)
///   plus a small clear button that reverts to a cash sale.
///
/// The bar is deliberately thin — the POS is a selling tool, not a
/// customer-management screen, so the customer strip never grows beyond a
/// single line.
class PosCustomerBar extends ConsumerWidget {
  const PosCustomerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final PosCart cart = ref.watch(posCartProvider);

    final bool hasCustomer = cart.hasCustomer;
    final bool hasBalance = cart.hasCustomerBalance;

    final NumberFormat money = NumberFormat.currency(
      locale: 'en_US',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openCustomerPicker(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  hasCustomer
                      ? Icons.person
                      : Icons.person_outline,
                  color: scheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        hasCustomer
                            ? (cart.customerName ?? 'عميل')
                            : 'عميل نقدي',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (hasBalance)
                        Text(
                          'الرصيد: ${money.format(cart.customerBalance)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (hasCustomer)
                  IconButton(
                    tooltip: 'إزالة العميل',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () =>
                        ref.read(posCartProvider.notifier).clearCustomer(),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'تغيير',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_left,
                        color: scheme.primary,
                        size: 18,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Customer picker
  // ---------------------------------------------------------------------------

  Future<void> _openCustomerPicker(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final Customer? selected = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => const _CustomerPickerSheet(),
    );

    if (selected == null) {
      return;
    }

    ref.read(posCartProvider.notifier).setCustomer(
          customerId: selected.id,
          customerName: selected.name,
          customerBalance: selected.balance,
        );
  }
}

// ============================================================================
// Customer picker sheet
// ============================================================================

class _CustomerPickerSheet extends ConsumerStatefulWidget {
  const _CustomerPickerSheet();

  @override
  ConsumerState<_CustomerPickerSheet> createState() =>
      _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends ConsumerState<_CustomerPickerSheet> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Customer> _filter(List<Customer> customers) {
    final String trimmed = _query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return customers;
    }
    return customers.where((Customer customer) {
      final String name = customer.name.toLowerCase();
      final String phone = (customer.phone ?? '').toLowerCase();
      final String code = (customer.code ?? '').toLowerCase();
      return name.contains(trimmed) ||
          phone.contains(trimmed) ||
          code.contains(trimmed);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AsyncValue<List<Customer>> customersAsync =
        ref.watch(customersProvider);
    final NumberFormat money = NumberFormat.currency(
      locale: 'en_US',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: <Widget>[
                  Text(
                    'اختيار العميل',
                    style: theme.textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'ابحث بالاسم أو الهاتف أو الكود...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (String value) =>
                    setState(() => _query = value),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: customersAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (_, __) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'تعذّر تحميل العملاء. حاول مرة أخرى.',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                data: (List<Customer> customers) {
                  final List<Customer> filtered = _filter(customers);
                  if (filtered.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _query.trim().isEmpty
                              ? 'لا يوجد عملاء مسجلون بعد.'
                              : 'لا يوجد عميل مطابق للبحث.',
                          style: theme.textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scrollController,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      final Customer customer = filtered[index];
                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person_outline),
                        ),
                        title: Text(
                          customer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: customer.hasPhone
                            ? Text(customer.phone!)
                            : null,
                        trailing: customer.balance > 0
                            ? Text(
                                money.format(customer.balance),
                                style: TextStyle(
                                  color: scheme.error,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : null,
                        onTap: () =>
                            Navigator.of(context).pop(customer),
                      );
                    },
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

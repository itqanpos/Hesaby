// lib/features/purchases/presentation/widgets/purchase_header_bar.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../suppliers/domain/entities/supplier.dart';
import '../../../suppliers/presentation/providers/supplier_providers.dart';
import '../../domain/entities/purchase_cart.dart';
import '../state/purchase_cart_notifier.dart';
import '../state/purchase_providers.dart';

/// Compact header bar for the purchase form.
///
/// Layout (RTL):
/// ```
/// ┌──────────────────────────────────────────────────────┐
/// │ المورد: [شركة الأمل ▾]   التاريخ: [2026/10/09 📅]  │
/// │ رقم الفاتورة: [_________________________________]   │
/// │ ℹ️ اتركه فارغًا ليُولَّد تلقائيًا                     │
/// └──────────────────────────────────────────────────────┘
/// ```
class PurchaseHeaderBar extends ConsumerWidget {
  const PurchaseHeaderBar({super.key});

  static final DateFormat _dateFormat = DateFormat.yMd('ar_EG');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Supplier>> suppliersAsync =
        ref.watch(suppliersProvider);
    final PurchaseCart cart = ref.watch(purchaseCartProvider);
    final PurchaseCartNotifier notifier =
        ref.read(purchaseCartProvider.notifier);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              // ---- Supplier picker ----
              Expanded(
                flex: 3,
                child: _SupplierSelector(
                  suppliers: suppliersAsync,
                  supplierId: cart.supplierId,
                  supplierName: cart.supplierName,
                  enabled: true,
                  onSelected: (Supplier supplier) {
                    notifier.setSupplier(
                      id: supplier.id,
                      name: supplier.name,
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),

              // ---- Date picker ----
              Expanded(
                flex: 2,
                child: _DateSelector(
                  date: cart.purchaseDate,
                  dateFormat: _dateFormat,
                  onPicked: notifier.setPurchaseDate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ---- Invoice number ----
          _InvoiceNumberField(
            value: cart.invoiceNumber,
            onChanged: notifier.setInvoiceNumber,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Supplier selector
// ============================================================================

class _SupplierSelector extends StatelessWidget {
  const _SupplierSelector({
    required this.suppliers,
    required this.supplierId,
    required this.supplierName,
    required this.enabled,
    required this.onSelected,
  });

  final AsyncValue<List<Supplier>> suppliers;
  final String? supplierId;
  final String? supplierName;
  final bool enabled;
  final ValueChanged<Supplier> onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool hasSupplier = supplierId != null;
    final String label = hasSupplier ? (supplierName ?? '—') : 'اختر المورد';

    return Material(
      color: hasSupplier
          ? scheme.primaryContainer.withValues(alpha: 0.4)
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled
            ? () => _openSupplierPicker(
                  context,
                  suppliers.value ?? const <Supplier>[],
                )
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.local_shipping_outlined,
                size: 16,
                color: hasSupplier ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: hasSupplier
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (suppliers.isLoading)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.expand_more,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSupplierPicker(
    BuildContext context,
    List<Supplier> suppliers,
  ) async {
    if (suppliers.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('لا يوجد موردون. أضف موردًا أولًا.'),
          ),
        );
      return;
    }

    final Supplier? picked = await showModalBottomSheet<Supplier>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) =>
          _SupplierPickerSheet(suppliers: suppliers),
    );

    if (picked != null) {
      onSelected(picked);
    }
  }
}

// ============================================================================
// Supplier picker sheet with search
// ============================================================================

class _SupplierPickerSheet extends StatefulWidget {
  const _SupplierPickerSheet({required this.suppliers});

  final List<Supplier> suppliers;

  @override
  State<_SupplierPickerSheet> createState() => _SupplierPickerSheetState();
}

class _SupplierPickerSheetState extends State<_SupplierPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Supplier> get _filtered {
    final String q = _query.trim().toLowerCase();
    if (q.isEmpty) {
      return widget.suppliers;
    }
    return widget.suppliers.where((Supplier s) {
      final String name = s.name.toLowerCase();
      final String code = (s.code ?? '').toLowerCase();
      final String phone = (s.phone ?? '').toLowerCase();
      return name.contains(q) || code.contains(q) || phone.contains(q);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<Supplier> filtered = _filtered;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'اختر المورد',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: (String v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'ابحث بالاسم أو الكود أو الهاتف',
                    prefixIcon: const Icon(Icons.search),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'لا نتائج مطابقة.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (BuildContext itemContext, int index) {
                          final Supplier s = filtered[index];
                          return ListTile(
                            leading: const Icon(
                              Icons.local_shipping_outlined,
                            ),
                            title: Text(s.name),
                            subtitle: s.hasPhone ? Text(s.phone!) : null,
                            onTap: () =>
                                Navigator.of(context).pop(s),
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
}

// ============================================================================
// Date selector
// ============================================================================

class _DateSelector extends StatelessWidget {
  const _DateSelector({
    required this.date,
    required this.dateFormat,
    required this.onPicked,
  });

  final DateTime? date;
  final DateFormat dateFormat;
  final ValueChanged<DateTime> onPicked;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool hasDate = date != null;

    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final DateTime picked = await showDatePicker(
            context: context,
            initialDate: date ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          ) ??
              DateTime.now();
          onPicked(picked);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.calendar_today_outlined,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasDate ? dateFormat.format(date!) : 'التاريخ',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: hasDate
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Invoice number field
// ============================================================================

class _InvoiceNumberField extends StatefulWidget {
  const _InvoiceNumberField({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_InvoiceNumberField> createState() => _InvoiceNumberFieldState();
}

class _InvoiceNumberFieldState extends State<_InvoiceNumberField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        isDense: true,
        labelText: 'رقم الفاتورة — اختياري',
        hintText: 'اتركه فارغًا ليُولَّد تلقائيًا',
        helperText: 'إذا تركته فارغًا سيعطيك النظام رقمًا داخليًا '
            'مثل PUR-2026-0001',
        helperMaxLines: 2,
        prefixIcon: const Icon(Icons.numbers, size: 18),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}

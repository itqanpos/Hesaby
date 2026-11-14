// lib/features/purchases/presentation/widgets/purchase_header_bar.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// │  🔍 [ ابحث عن مورد بالاسم أو الكود أو الهاتف... ]  │
/// └──────────────────────────────────────────────────────┘
/// ```
class PurchaseHeaderBar extends ConsumerWidget {
  const PurchaseHeaderBar({super.key});

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
    );
  }
}

// ============================================================================
// Supplier selector (Search style)
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
    final String label = hasSupplier ? (supplierName ?? '—') : 'ابحث عن مورد...';

    return Material(
      color: hasSupplier
          ? scheme.primaryContainer.withValues(alpha: 0.3)
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
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hasSupplier ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.search,
                size: 20,
                color: hasSupplier ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: hasSupplier ? FontWeight.w700 : FontWeight.w600,
                    color: hasSupplier
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (suppliers.isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (hasSupplier)
                Icon(
                  Icons.check_circle,
                  size: 18,
                  color: scheme.primary,
                )
              else
                Icon(
                  Icons.expand_more,
                  size: 20,
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

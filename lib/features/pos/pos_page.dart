// lib/features/pos/pos_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../shared/layouts/app_shell.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_empty.dart';
import '../../shared/widgets/app_error.dart';
import '../../shared/widgets/app_loader.dart';
import '../../shared/widgets/app_text_field.dart';
import '../products/domain/entities/product.dart';
import '../products/domain/entities/product_unit.dart';
import '../products/domain/entities/unit.dart';
import '../products/presentation/providers/product_providers.dart';
import '../products/presentation/providers/unit_providers.dart';
import '../sales/domain/entities/sale_entities.dart';
import '../sales/presentation/providers/sales_providers.dart';
import 'pos_cart.dart';
import 'pos_payment_dialog.dart';

/// POS main page — search-first, cart-first.
///
/// Layout (top → bottom):
/// * customer chip (tap to pick a registered customer or keep cash)
/// * product search field
/// * suggestions overlay (appears while typing)
/// * cart list (scrollable)
/// * totals block
/// * actions (cancel / pay)
///
/// Selecting a suggestion opens a small modal to pick the unit, quantity
/// and price (constrained by the product's min / max price range).
class PosPage extends ConsumerStatefulWidget {
  const PosPage({super.key});

  @override
  ConsumerState<PosPage> createState() => _PosPageState();
}

class _PosPageState extends ConsumerState<PosPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';
  bool _showSuggestions = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Search helpers
  // ---------------------------------------------------------------------------

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      _showSuggestions = value.trim().isNotEmpty;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _query = '';
      _showSuggestions = false;
    });
    _searchFocus.requestFocus();
  }

  void _closeSuggestions() {
    setState(() => _showSuggestions = false);
  }

  List<Product> _filter(List<Product> products) {
    final String trimmed = _query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return const <Product>[];
    }
    final List<Product> matches = <Product>[];
    for (final Product product in products) {
      final String name = product.name.toLowerCase();
      final String sku = (product.sku ?? '').toLowerCase();
      final String barcode = (product.barcode ?? '').toLowerCase();
      if (name.contains(trimmed) ||
          sku.contains(trimmed) ||
          barcode.contains(trimmed)) {
        matches.add(product);
        if (matches.length >= 20) {
          break;
        }
      }
    }
    return matches;
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _openAddLineDialog(Product product) async {
    _closeSuggestions();
    _clearSearch();

    final bool? added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) =>
          _AddLineSheet(product: product),
    );

    if (!mounted) {
      return;
    }
    if (added == true) {
      _searchFocus.requestFocus();
    }
  }

  Future<void> _openClientPicker() async {
    final bool? picked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) => const _ClientPickerSheet(),
    );
    if (!mounted || picked != true) {
      return;
    }
    _searchFocus.requestFocus();
  }

  Future<void> _cancelCart() async {
    final PosCartState cart = ref.read(posCartProvider);
    if (cart.isEmpty) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('إلغاء الفاتورة'),
        content: const Text(
          'سيتم مسح جميع البنود. هل تريد المتابعة؟',
        ),
        actions: <Widget>[
          AppButton(
            label: 'رجوع',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            label: 'إلغاء الفاتورة',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    ref.read(posCartProvider.notifier).reset();
    _searchFocus.requestFocus();
  }

  Future<void> _openPayment() async {
    final PosCartState cart = ref.read(posCartProvider);
    if (cart.isEmpty) {
      return;
    }
    final bool? completed = await showPosPaymentDialog(context: context);
    if (!mounted) {
      return;
    }
    if (completed == true) {
      ref.read(posCartProvider.notifier).reset();
      _searchFocus.requestFocus();
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final PosCartState cart = ref.watch(posCartProvider);
    final AsyncValue<List<Product>> productsAsync =
        ref.watch(productsProvider);

    return AppShell(
      appBar: AppBar(
        title: const Text('نقطة البيع'),
        actions: <Widget>[
          IconButton(
            tooltip: 'مسح السلة',
            onPressed: cart.isEmpty ? null : _cancelCart,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Builder(
        builder: (BuildContext context) {
          if (productsAsync.isLoading) {
            return const AppLoader();
          }
          if (productsAsync.hasError) {
            return AppErrorView(
              title: 'تعذّر تحميل المنتجات',
              message: 'حدث خطأ غير متوقع أثناء تحميل المنتجات.',
              retryLabel: 'إعادة المحاولة',
              onRetry: () => ref.invalidate(productsProvider),
            );
          }

          final List<Product> products =
              productsAsync.value ?? const <Product>[];
          final List<Product> suggestions = _filter(products);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _ClientChip(
                customerName: cart.customerName,
                balance: cart.customerBalance,
                onTap: _openClientPicker,
                onClear: cart.hasCustomer
                    ? () =>
                        ref.read(posCartProvider.notifier).clearCustomer()
                    : null,
              ),
              _SearchField(
                controller: _searchController,
                focusNode: _searchFocus,
                query: _query,
                onChanged: _onQueryChanged,
                onClear: _clearSearch,
              ),
              Expanded(
                child: Stack(
                  children: <Widget>[
                    _CartBody(
                      cart: cart,
                      onPay: _openPayment,
                      onCancel: _cancelCart,
                    ),
                    if (_showSuggestions)
                      _SuggestionsOverlay(
                        products: suggestions,
                        onPick: _openAddLineDialog,
                        onDismiss: _closeSuggestions,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// Client chip
// ============================================================================

class _ClientChip extends StatelessWidget {
  const _ClientChip({
    required this.customerName,
    required this.balance,
    required this.onTap,
    required this.onClear,
  });

  final String? customerName;
  final double balance;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final NumberFormat money = NumberFormat.currency(
      locale: 'en_US',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );
    final bool hasCustomer = customerName != null;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: <Widget>[
                Icon(Icons.person_outline, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        hasCustomer ? customerName! : 'عميل نقدي',
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (hasCustomer && balance > 0)
                        Text(
                          'رصيد سابق: ${money.format(balance)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
                if (onClear != null)
                  IconButton(
                    tooltip: 'إزالة العميل',
                    icon: const Icon(Icons.close),
                    onPressed: onClear,
                  )
                else
                  Icon(
                    Icons.chevron_left,
                    color: scheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Search field
// ============================================================================

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppTextField(
        controller: controller,
        focusNode: focusNode,
        hint: 'امسح باركود أو اكتب اسم/كود المنتج...',
        prefixIcon: Icons.search,
        autofocus: false,
        enabled: true,
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: onClear,
              ),
        onChanged: onChanged,
      ),
    );
  }
}

// ============================================================================
// Suggestions overlay
// ============================================================================

class _SuggestionsOverlay extends StatelessWidget {
  const _SuggestionsOverlay({
    required this.products,
    required this.onPick,
    required this.onDismiss,
  });

  final List<Product> products;
  final ValueChanged<Product> onPick;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final NumberFormat money = NumberFormat.currency(
      locale: 'en_US',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

    return Positioned.fill(
      child: Material(
        color: scheme.surface,
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              child: Row(
                children: <Widget>[
                  Text(
                    products.isEmpty
                        ? 'لا نتائج'
                        : '${products.length} نتيجة',
                    style: theme.textTheme.labelLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onDismiss,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: products.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('لا يوجد منتج مطابق'),
                      ),
                    )
                  : ListView.separated(
                      itemCount: products.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) {
                        final Product product = products[index];
                        final String? sku = product.sku;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: scheme.primaryContainer,
                            foregroundColor: scheme.onPrimaryContainer,
                            child: Text(
                              product.name.characters.first.toUpperCase(),
                            ),
                          ),
                          title: Text(
                            product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: sku == null
                              ? null
                              : Text('SKU: $sku'),
                          trailing: Text(
                            money.format(product.sellingPrice),
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onTap: () => onPick(product),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Cart body (cart list + totals + actions)
// ============================================================================

class _CartBody extends StatelessWidget {
  const _CartBody({
    required this.cart,
    required this.onPay,
    required this.onCancel,
  });

  final PosCartState cart;
  final VoidCallback onPay;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: cart.isEmpty
              ? const AppEmptyView(
                  icon: Icons.shopping_cart_outlined,
                  title: 'السلة فارغة',
                  message: 'اختر منتجاً من البحث للبدء',
                )
              : _CartList(cart: cart),
        ),
        const Divider(height: 1),
        _TotalsSection(cart: cart),
        _ActionsSection(
          isEmpty: cart.isEmpty,
          onPay: onPay,
          onCancel: onCancel,
        ),
      ],
    );
  }
}

class _CartList extends ConsumerWidget {
  const _CartList({required this.cart});

  final PosCartState cart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final NumberFormat money = NumberFormat.currency(
      locale: 'en_US',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: cart.lines.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final PosCartLine line = cart.lines[index];

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      line.productName,
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'حذف',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => ref
                        .read(posCartProvider.notifier)
                        .removeLine(
                          productId: line.productId,
                          unitId: line.unitId,
                        ),
                  ),
                ],
              ),
              Row(
                children: <Widget>[
                  Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: () => ref
                              .read(posCartProvider.notifier)
                              .decrementLine(
                                productId: line.productId,
                                unitId: line.unitId,
                              ),
                        ),
                        Text(
                          line.quantity.toStringAsFixed(
                            line.quantity == line.quantity.roundToDouble()
                                ? 0
                                : 2,
                          ),
                          style: theme.textTheme.titleMedium,
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () => ref
                              .read(posCartProvider.notifier)
                              .incrementLine(
                                productId: line.productId,
                                unitId: line.unitId,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    line.unitName,
                    style: theme.textTheme.bodySmall,
                  ),
                  const Spacer(),
                  Text(
                    '× ${money.format(line.unitPrice)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    money.format(line.lineTotal),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TotalsSection extends ConsumerWidget {
  const _TotalsSection({required this.cart});

  final PosCartState cart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final NumberFormat money = NumberFormat.currency(
      locale: 'en_US',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('الأصناف', style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text(
                cart.lineCount.toString(),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Text('الإجمالي', style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text(
                money.format(cart.subtotal),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _DiscountRow(
            discount: cart.discount,
            onChanged: (double value) =>
                ref.read(posCartProvider.notifier).setDiscount(value),
          ),
          const Divider(height: 20),
          Row(
            children: <Widget>[
              Text(
                'الصافي',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                money.format(cart.total),
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiscountRow extends StatefulWidget {
  const _DiscountRow({required this.discount, required this.onChanged});

  final double discount;
  final ValueChanged<double> onChanged;

  @override
  State<_DiscountRow> createState() => _DiscountRowState();
}

class _DiscountRowState extends State<_DiscountRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.discount == 0
          ? ''
          : widget.discount.toStringAsFixed(
              widget.discount == widget.discount.roundToDouble() ? 0 : 2,
            ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const SizedBox(width: 76, child: Text('الخصم')),
        Expanded(
          child: AppTextField(
            controller: _controller,
            hint: '0',
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            onChanged: (String value) {
              final double parsed = double.tryParse(value.trim()) ?? 0;
              widget.onChanged(parsed);
            },
          ),
        ),
        const SizedBox(width: 8),
        const Text('ج.م'),
      ],
    );
  }
}

class _ActionsSection extends StatelessWidget {
  const _ActionsSection({
    required this.isEmpty,
    required this.onPay,
    required this.onCancel,
  });

  final bool isEmpty;
  final VoidCallback onPay;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
      child: Row(
        children: <Widget>[
          Expanded(
            child: AppButton(
              label: 'إلغاء',
              icon: Icons.delete_outline,
              variant: AppButtonVariant.outline,
              onPressed: isEmpty ? null : onCancel,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AppButton(
              label: 'دفع',
              icon: Icons.check_circle_outline,
              onPressed: isEmpty ? null : onPay,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Client picker sheet
// ============================================================================

class _ClientPickerSheet extends ConsumerStatefulWidget {
  const _ClientPickerSheet();

  @override
  ConsumerState<_ClientPickerSheet> createState() => _ClientPickerSheetState();
}

class _ClientPickerSheetState extends ConsumerState<_ClientPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
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

  void _chooseCash() {
    ref.read(posCartProvider.notifier).clearCustomer();
    Navigator.of(context).pop(true);
  }

  void _chooseCustomer(Customer customer) {
    ref.read(posCartProvider.notifier).setCustomer(
          customerId: customer.id,
          customerName: customer.name,
          customerBalance: customer.balance,
        );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
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
        return DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: <Widget>[
                    Text(
                      'اختيار العميل',
                      style: theme.textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AppTextField(
                  controller: _searchController,
                  hint: 'ابحث بالاسم أو الهاتف...',
                  prefixIcon: Icons.search,
                  autofocus: true,
                  onChanged: (String value) =>
                      setState(() => _query = value),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('عميل نقدي (بدون رصيد)'),
                onTap: _chooseCash,
              ),
              const Divider(height: 1),
              Expanded(
                child: customersAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('تعذّر تحميل العملاء'),
                    ),
                  ),
                  data: (List<Customer> customers) {
                    final List<Customer> filtered = _filter(customers);
                    if (filtered.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('لا يوجد عميل مطابق'),
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
                          title: Text(customer.name),
                          subtitle: customer.hasPhone
                              ? Text(customer.phone!)
                              : null,
                          trailing: customer.balance > 0
                              ? Text(
                                  money.format(customer.balance),
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : null,
                          onTap: () => _chooseCustomer(customer),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// Add-line sheet (unit + quantity + price)
// ============================================================================

class _AddLineSheet extends ConsumerStatefulWidget {
  const _AddLineSheet({required this.product});

  final Product product;

  @override
  ConsumerState<_AddLineSheet> createState() => _AddLineSheetState();
}

class _AddLineSheetState extends ConsumerState<_AddLineSheet> {
  late final TextEditingController _quantityController;
  late final TextEditingController _priceController;
  String? _selectedUnitId;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(text: '1');
    _priceController = TextEditingController(
      text: _formatNumber(widget.product.sellingPrice),
    );
    _selectedUnitId = widget.product.defaultUnitId;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  double get _quantity =>
      double.tryParse(_quantityController.text.trim()) ?? 0;

  double get _unitPrice =>
      double.tryParse(_priceController.text.trim()) ?? 0;

  // ---------------------------------------------------------------------------
  // Unit / price resolution
  // ---------------------------------------------------------------------------

  /// Builds the ordered list of units selectable for the current product:
  /// its default unit first, then any additional units registered through
  /// `product_units`.
  static List<Unit> _availableUnits(
    Product product,
    List<Unit> allUnits,
    List<ProductUnit> extras,
  ) {
    final List<Unit> result = <Unit>[];
    final Set<String> seen = <String>{};

    for (final Unit unit in allUnits) {
      if (unit.id == product.defaultUnitId) {
        result.add(unit);
        seen.add(unit.id);
        break;
      }
    }
    for (final ProductUnit extra in extras) {
      for (final Unit unit in allUnits) {
        if (unit.id == extra.unitId && seen.add(unit.id)) {
          result.add(unit);
          break;
        }
      }
    }
    return result;
  }

  static ProductUnit? _extraFor(String unitId, List<ProductUnit> extras) {
    for (final ProductUnit extra in extras) {
      if (extra.unitId == unitId) {
        return extra;
      }
    }
    return null;
  }

  double? _effectiveMin(String unitId, List<ProductUnit> extras) {
    if (unitId == widget.product.defaultUnitId) {
      return widget.product.minSellingPrice;
    }
    final ProductUnit? extra = _extraFor(unitId, extras);
    if (extra?.minSellingPrice != null) {
      return extra!.minSellingPrice;
    }
    final double? baseMin = widget.product.minSellingPrice;
    if (baseMin == null || extra == null) {
      return null;
    }
    return baseMin * extra.conversionFactor;
  }

  double? _effectiveMax(String unitId, List<ProductUnit> extras) {
    if (unitId == widget.product.defaultUnitId) {
      return widget.product.maxSellingPrice;
    }
    final ProductUnit? extra = _extraFor(unitId, extras);
    if (extra?.maxSellingPrice != null) {
      return extra!.maxSellingPrice;
    }
    final double? baseMax = widget.product.maxSellingPrice;
    if (baseMax == null || extra == null) {
      return null;
    }
    return baseMax * extra.conversionFactor;
  }

  double _suggestedPrice(String unitId, List<ProductUnit> extras) {
    if (unitId == widget.product.defaultUnitId) {
      return widget.product.sellingPrice;
    }
    final ProductUnit? extra = _extraFor(unitId, extras);
    if (extra == null) {
      return widget.product.sellingPrice;
    }
    if (extra.sellingPrice != null) {
      return extra.sellingPrice!;
    }
    return widget.product.sellingPrice * extra.conversionFactor;
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  void _submit({
    required List<ProductUnit> extras,
    required List<Unit> availableUnits,
  }) {
    if (_quantity <= 0) {
      return;
    }
    final String? unitId = _selectedUnitId;
    if (unitId == null) {
      return;
    }

    final double? minPrice = _effectiveMin(unitId, extras);
    final double? maxPrice = _effectiveMax(unitId, extras);
    if (minPrice != null && _unitPrice < minPrice) {
      return;
    }
    if (maxPrice != null && _unitPrice > maxPrice) {
      return;
    }

    // Resolve the selected unit from the available list.
    Unit? selectedUnit;
    for (final Unit unit in availableUnits) {
      if (unit.id == unitId) {
        selectedUnit = unit;
        break;
      }
    }
    if (selectedUnit == null) {
      return;
    }

    final ProductUnit? extra = _extraFor(unitId, extras);
    final double conversionFactor = extra?.conversionFactor ?? 1;

    ref.read(posCartProvider.notifier).addLine(
          productId: widget.product.id,
          productName: widget.product.name,
          unitId: unitId,
          unitName: selectedUnit.name,
          conversionFactor: conversionFactor,
          quantity: _quantity,
          unitPrice: _unitPrice,
        );

    Navigator.of(context).pop(true);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final NumberFormat money = NumberFormat.currency(
      locale: 'en_US',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

    final AsyncValue<List<ProductUnit>> extrasAsync =
        ref.watch(productUnitsProvider(widget.product.id));
    final AsyncValue<List<Unit>> unitsAsync = ref.watch(unitsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: Builder(
            builder: (BuildContext context) {
              if (extrasAsync.isLoading || unitsAsync.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              final List<ProductUnit> extras =
                  extrasAsync.value ?? const <ProductUnit>[];
              final List<Unit> allUnits =
                  unitsAsync.value ?? const <Unit>[];
              final List<Unit> available = _availableUnits(
                widget.product,
                allUnits,
                extras,
              );

              // Resolve the currently selected unit. If the stored id is no
              // longer available, fall back to the first entry.
              Unit? currentUnit;
              for (final Unit unit in available) {
                if (unit.id == _selectedUnitId) {
                  currentUnit = unit;
                  break;
                }
              }
              if (currentUnit == null && available.isNotEmpty) {
                currentUnit = available.first;
                _selectedUnitId = currentUnit.id;
              }

              final double? minPrice = currentUnit == null
                  ? null
                  : _effectiveMin(currentUnit.id, extras);
              final double? maxPrice = currentUnit == null
                  ? null
                  : _effectiveMax(currentUnit.id, extras);
              final double lineTotal = _quantity * _unitPrice;
              final bool priceValid =
                  (minPrice == null || _unitPrice >= minPrice) &&
                      (maxPrice == null || _unitPrice <= maxPrice);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            widget.product.name,
                            style: theme.textTheme.titleLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: <Widget>[
                        Text('الوحدة', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedUnitId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                          ),
                          items: <DropdownMenuItem<String>>[
                            for (final Unit unit in available)
                              DropdownMenuItem<String>(
                                value: unit.id,
                                child: Text(unit.name),
                              ),
                          ],
                          onChanged: (String? value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _selectedUnitId = value;
                              _priceController.text = _formatNumber(
                                _suggestedPrice(value, extras),
                              );
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        Text('الكمية', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 6),
                        Row(
                          children: <Widget>[
                            IconButton.filledTonal(
                              onPressed: () {
                                final double current = _quantity;
                                final double next =
                                    current > 1 ? current - 1 : 1;
                                _quantityController.text =
                                    _formatNumber(next);
                                setState(() {});
                              },
                              icon: const Icon(Icons.remove),
                            ),
                            Expanded(
                              child: AppTextField(
                                controller: _quantityController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                onChanged: (String _) => setState(() {}),
                              ),
                            ),
                            IconButton.filledTonal(
                              onPressed: () {
                                _quantityController.text =
                                    _formatNumber(_quantity + 1);
                                setState(() {});
                              },
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text('سعر الوحدة',
                            style: theme.textTheme.labelLarge),
                        const SizedBox(height: 6),
                        AppTextField(
                          controller: _priceController,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (String _) => setState(() {}),
                        ),
                        if (minPrice != null || maxPrice != null) ...<Widget>[
                          const SizedBox(height: 6),
                          Text(
                            'النطاق المسموح: '
                            '${minPrice == null ? '—' : money.format(minPrice)} '
                            '– '
                            '${maxPrice == null ? '—' : money.format(maxPrice)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: priceValid
                                  ? scheme.onSurfaceVariant
                                  : scheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Row(
                          children: <Widget>[
                            Text('الإجمالي',
                                style: theme.textTheme.titleMedium),
                            const Spacer(),
                            Text(
                              money.format(lineTotal),
                              style:
                                  theme.textTheme.headlineSmall?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: AppButton(
                      label: 'إضافة إلى السلة',
                      icon: Icons.add_shopping_cart,
                      expanded: true,
                      size: AppButtonSize.large,
                      onPressed: _quantity > 0 && priceValid
                          ? () => _submit(
                                extras: extras,
                                availableUnits: available,
                              )
                          : null,
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

class PosScreen extends StatefulWidget {
  final String companyId;
  final String branchId;
  const PosScreen({super.key, required this.companyId, required this.branchId});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  // بيانات المتجر
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];
  Map<String, double> _stockMap = {};
  List<Map<String, dynamic>> _customers = [];
  
  // حالة الشاشة
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  bool _loading = true;
  bool _isSearching = false;

  // السلة
  List<Map<String, dynamic>> _cart = [];
  Map<String, dynamic>? _selectedCustomer;
  double _discount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final client = Supabase.instance.client;
      
      // 1. جلب المنتجات
      final prods = await client
          .from('products')
          .select('id, name, product_units(id, unit_name, sell_price, min_selling_price, max_selling_price, barcode)')
          .eq('company_id', widget.companyId)
          .eq('is_active', true);

      // 2. جلب المخزون في هذا الفرع
      final stock = await client
          .from('inventory_balances')
          .select('product_id, quantity_on_hand')
          .eq('branch_id', widget.branchId);

      final Map<String, double> sMap = {};
      for (var s in stock) {
        if (s['product_id'] != null && s['quantity_on_hand'] != null) {
          sMap[s['product_id']] = (s['quantity_on_hand'] as num).toDouble();
        }
      }

      // 3. جلب العملاء
      final custs = await client
          .from('customers')
          .select('id, name, phone, balance')
          .eq('company_id', widget.companyId)
          .order('name');

      if (mounted) {
        setState(() {
          _products = (prods as List).cast<Map<String, dynamic>>();
          _filteredProducts = _products;
          _stockMap = sMap;
          _customers = (custs as List).cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في التحميل: $e')));
      }
    }
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final q = _searchCtrl.text.toLowerCase().trim();
      setState(() {
        _isSearching = q.isNotEmpty;
        _filteredProducts = _products.where((p) {
          final name = (p['name'] ?? '').toString().toLowerCase();
          final units = p['product_units'] as List?;
          bool barcodeMatch = false;
          if (units != null) {
            for (var u in units) {
              if ((u['barcode'] ?? '').toString().toLowerCase().contains(q)) {
                barcodeMatch = true;
                break;
              }
            }
          }
          return name.contains(q) || barcodeMatch;
        }).toList();
      });
    });
  }

  // --- دوال السلة ---
  double get _subtotal => _cart.fold(0, (sum, item) => sum + (item['price'] * item['qty']));
  double get _total => _subtotal - _discount;
  bool get _hasCustomer => _selectedCustomer != null;
  double get _customerBalance => (_selectedCustomer?['balance'] as num?)?.toDouble() ?? 0.0;

  void _addToCart(Map<String, dynamic> line) {
    setState(() {
      final existingIndex = _cart.indexWhere(
        (item) => item['product_id'] == line['product_id'] && item['unit_id'] == line['unit_id']
      );
      if (existingIndex >= 0) {
        _cart[existingIndex]['qty'] += line['qty'];
      } else {
        _cart.add(line);
      }
    });
  }

  void _updateQty(int index, double newQty) {
    setState(() => _cart[index]['qty'] = newQty);
  }

  void _updatePrice(int index, double newPrice) {
    setState(() => _cart[index]['price'] = newPrice);
  }

  void _removeLine(int index) {
    setState(() => _cart.removeAt(index));
  }

  void _clearCustomer() => setState(() => _selectedCustomer = null);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('نقطة البيع'),
        actions: [
          if (_cart.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.red),
              onPressed: () => setState(() => _cart.clear()),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 1. شريط العميل
                _buildCustomerBar(),
                // 2. شريط البحث
                _buildSearchField(),
                // 3. المنطقة الوسطى (المنتجات أو السلة)
                Expanded(
                  child: _isSearching ? _buildSearchResults() : _buildCartList(),
                ),
                // 4. الشريط السفلي (الإجمالي وزر الدفع)
                if (!_isSearching && _cart.isNotEmpty) _buildBottomPanel(),
              ],
            ),
    );
  }

  // ================= المكونات الفرعية =================

  Widget _buildCustomerBar() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openCustomerPicker(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(_hasCustomer ? Icons.person : Icons.person_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _hasCustomer ? _selectedCustomer!['name'] : 'عميل نقدي',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (_hasCustomer && _customerBalance != 0)
                        Text(
                          'الرصيد: ${_customerBalance.toStringAsFixed(2)} ج.م',
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ),
                if (_hasCustomer)
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: _clearCustomer)
                else
                  Row(
                    children: [
                      Text('تغيير', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                      Icon(Icons.chevron_left, color: theme.colorScheme.primary, size: 18),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        decoration: InputDecoration(
          hintText: 'ابحث بالاسم أو الباركود...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: () async {
                  final res = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const _ScannerPage()));
                  if (res != null) { _searchCtrl.text = res; }
                },
              ),
              if (_searchCtrl.text.isNotEmpty)
                IconButton(icon: const Icon(Icons.close), onPressed: () => _searchCtrl.clear()),
            ],
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_filteredProducts.isEmpty) {
      return const Center(child: Text('لا توجد نتائج مطابقة', style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _filteredProducts.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final p = _filteredProducts[i];
        final stock = _stockMap[p['id']] ?? 0.0;
        final units = p['product_units'] as List?;
        final defaultUnit = (units != null && units.isNotEmpty) ? units.first : null;
        final price = (defaultUnit?['sell_price'] as num?)?.toDouble() ?? 0.0;

        return InkWell(
          onTap: () => _openUnitSelector(p),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.inventory_2_outlined, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (defaultUnit != null)
                        Text(defaultUnit['unit_name'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                _buildStockBadge(stock),
                const SizedBox(width: 8),
                Text('${price.toStringAsFixed(2)} ج.م', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                const Icon(Icons.chevron_left, size: 18, color: Colors.grey),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStockBadge(double stock) {
    final (Color bg, Color fg, String label) = stock <= 0
        ? (const Color(0xFFFFEBEE), const Color(0xFFC62828), 'نفد')
        : stock <= 10
            ? (const Color(0xFFFFF3E0), const Color(0xFFE65100), '${stock.toInt()} متبقٍ')
            : (const Color(0xFFE8F5E9), const Color(0xFF2E7D32), '${stock.toInt()} متاح');
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4), border: Border.all(color: fg.withOpacity(0.3))),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  Widget _buildCartList() {
    if (_cart.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('السلة فارغة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
            Text('ابحث عن منتج أو امسح الباركود لإضافته.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _cart.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final line = _cart[index];
        return _CartLineTile(
          line: line,
          onQtyChanged: (q) => _updateQty(index, q),
          onPriceChanged: (p) => _updatePrice(index, p),
          onRemove: () => _removeLine(index),
        );
      },
    );
  }

  Widget _buildBottomPanel() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('المجموع الفرعي:', style: TextStyle(fontSize: 14)),
              Text('${_subtotal.toStringAsFixed(2)} ج.م', style: const TextStyle(fontSize: 14)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('الخصم:', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    height: 28,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(contentPadding: EdgeInsets.zero, isDense: true, border: OutlineInputBorder()),
                      onChanged: (v) => setState(() => _discount = double.tryParse(v) ?? 0),
                    ),
                  ),
                ],
              ),
              Text('- ${_discount.toStringAsFixed(2)} ج.م', style: const TextStyle(fontSize: 14, color: Colors.red)),
            ],
          ),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('الإجمالي:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('${_total.toStringAsFixed(2)} ج.م', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: _openPaymentSheet,
              icon: const Icon(Icons.payment),
              label: const Text('الدفع', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // ================= النوافذ المنبثقة =================

  Future<void> _openCustomerPicker() async {
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CustomerPickerSheet(customers: _customers),
    );
    if (selected != null) setState(() => _selectedCustomer = selected);
  }

  Future<void> _openUnitSelector(Map<String, dynamic> product) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _UnitSelectorSheet(product: product, stock: _stockMap[product['id']] ?? 0),
    );
    if (result != null) {
      _addToCart(result);
      _searchCtrl.clear();
      _searchFocus.unfocus();
    }
  }

  Future<void> _openPaymentSheet() async {
    final success = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PaymentSheet(
        companyId: widget.companyId,
        branchId: widget.branchId,
        cart: _cart,
        customer: _selectedCustomer,
        discount: _discount,
        subtotal: _subtotal,
        total: _total,
        customerBalance: _customerBalance,
      ),
    );
    if (success == true) {
      setState(() {
        _cart.clear();
        _discount = 0;
        _selectedCustomer = null;
      });
      _loadData(); // تحديث المخزون
    }
  }
}

// ============================================================================
// 1. بطاقة السلة (Cart Line Tile)
// ============================================================================
class _CartLineTile extends StatefulWidget {
  final Map<String, dynamic> line;
  final Function(double) onQtyChanged;
  final Function(double) onPriceChanged;
  final VoidCallback onRemove;

  const _CartLineTile({required this.line, required this.onQtyChanged, required this.onPriceChanged, required this.onRemove});

  @override
  State<_CartLineTile> createState() => _CartLineTileState();
}

class _CartLineTileState extends State<_CartLineTile> {
  late TextEditingController _qtyCtrl;
  late TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: widget.line['qty'].toString());
    _priceCtrl = TextEditingController(text: widget.line['price'].toString());
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _commitQty() {
    final val = double.tryParse(_qtyCtrl.text);
    if (val != null && val > 0) widget.onQtyChanged(val);
    else _qtyCtrl.text = widget.line['qty'].toString();
  }

  void _commitPrice() {
    final val = double.tryParse(_priceCtrl.text);
    final min = (widget.line['min_price'] as num?)?.toDouble();
    final max = (widget.line['max_price'] as num?)?.toDouble();
    
    if (val != null && val >= 0 && (min == null || val >= min) && (max == null || val <= max)) {
      widget.onPriceChanged(val);
    } else {
      _priceCtrl.text = widget.line['price'].toString();
      if (val != null && min != null && val < min) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('أقل سعر مسموح هو $min'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = widget.line;
    final total = (line['qty'] as double) * (line['price'] as double);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(line['product_name'], style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 6),
          SizedBox(width: 50, height: 40, child: TextField(controller: _qtyCtrl, textAlign: TextAlign.center, keyboardType: TextInputType.number, decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.zero, border: OutlineInputBorder()), onSubmitted: (_) => _commitQty(), onTapOutside: (_) { FocusScope.of(context).unfocus(); _commitQty(); })),
          const SizedBox(width: 4),
          SizedBox(width: 40, child: Text(line['unit_name'], style: const TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 4),
          SizedBox(width: 65, height: 40, child: TextField(controller: _priceCtrl, textAlign: TextAlign.center, keyboardType: TextInputType.number, decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.zero, border: OutlineInputBorder()), onSubmitted: (_) => _commitPrice(), onTapOutside: (_) { FocusScope.of(context).unfocus(); _commitPrice(); })),
          const SizedBox(width: 6),
          SizedBox(width: 70, child: Text(total.toStringAsFixed(2), textAlign: TextAlign.end, style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold))),
          IconButton(icon: const Icon(Icons.close, size: 18, color: Colors.grey), onPressed: widget.onRemove),
        ],
      ),
    );
  }
}

// ============================================================================
// 2. نافذة اختيار الوحدة (Unit Selector)
// ============================================================================
class _UnitSelectorSheet extends StatefulWidget {
  final Map<String, dynamic> product;
  final double stock;
  const _UnitSelectorSheet({required this.product, required this.stock});

  @override
  State<_UnitSelectorSheet> createState() => _UnitSelectorSheetState();
}

class _UnitSelectorSheetState extends State<_UnitSelectorSheet> {
  String? _selectedUnitId;
  late TextEditingController _qtyCtrl;
  late TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    final units = widget.product['product_units'] as List;
    _selectedUnitId = units.first['id'];
    _qtyCtrl = TextEditingController(text: '1');
    _priceCtrl = TextEditingController(text: (units.first['sell_price'] ?? 0).toString());
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _currentUnit => (widget.product['product_units'] as List).firstWhere((u) => u['id'] == _selectedUnitId);

  @override
  Widget build(BuildContext context) {
    final units = widget.product['product_units'] as List;
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    final price = double.tryParse(_priceCtrl.text) ?? 0;
    final min = (_currentUnit['min_selling_price'] as num?)?.toDouble();
    final max = (_currentUnit['max_selling_price'] as num?)?.toDouble();
    final isValid = (min == null || price >= min) && (max == null || price <= max);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scroll) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(
            children: [
              const Text('تفاصيل المنتج', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedUnitId,
                decoration: const InputDecoration(labelText: 'الوحدة', border: OutlineInputBorder()),
                items: units.map<DropdownMenuItem<String>>((u) => DropdownMenuItem(value: u['id'], child: Text(u['unit_name'] ?? ''))).toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedUnitId = v;
                    _priceCtrl.text = (_currentUnit['sell_price'] ?? 0).toString();
                  });
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: TextField(controller: _qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية', border: OutlineInputBorder()), onChanged: (_) => setState((){}))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: _priceCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'السعر', border: const OutlineInputBorder(), errorText: isValid ? null : 'خارج النطاق'), onChanged: (_) => setState((){}))),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: (qty > 0 && isValid) ? () {
                    Navigator.pop(context, {
                      'product_id': widget.product['id'],
                      'product_name': widget.product['name'],
                      'unit_id': _selectedUnitId,
                      'unit_name': _currentUnit['unit_name'],
                      'qty': qty,
                      'price': price,
                      'min_price': min,
                      'max_price': max,
                    });
                  } : null,
                  child: const Text('إضافة إلى السلة'),
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
// 3. نافذة اختيار العميل (Customer Picker)
// ============================================================================
class _CustomerPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> customers;
  const _CustomerPickerSheet({required this.customers});

  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.customers.where((c) {
      final q = _query.toLowerCase();
      return (c['name'] ?? '').toString().toLowerCase().contains(q) || (c['phone'] ?? '').toString().contains(q);
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      expand: false,
      builder: (context, scroll) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(
            children: [
              const Text('اختيار العميل', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(hintText: 'ابحث بالاسم أو الهاتف...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  controller: scroll,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final c = filtered[i];
                    final bal = (c['balance'] as num?)?.toDouble() ?? 0;
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(c['name']),
                      subtitle: c['phone'] != null ? Text(c['phone']) : null,
                      trailing: bal > 0 ? Text('${bal.toStringAsFixed(2)} ج.م', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)) : null,
                      onTap: () => Navigator.pop(context, c),
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
// 4. نافذة الدفع (Payment Sheet)
// ============================================================================
class _PaymentSheet extends StatefulWidget {
  final String companyId;
  final String branchId;
  final List<Map<String, dynamic>> cart;
  final Map<String, dynamic>? customer;
  final double discount;
  final double subtotal;
  final double total;
  final double customerBalance;

  const _PaymentSheet({required this.companyId, required this.branchId, required this.cart, this.customer, required this.discount, required this.subtotal, required this.total, required this.customerBalance});

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  String _method = 'cash';
  late TextEditingController _paidCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _paidCtrl = TextEditingController(text: widget.total.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _paidCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _isSaving = true);
    try {
      final paid = double.tryParse(_paidCtrl.text) ?? widget.total;
      final isCredit = _method == 'credit';

      if (isCredit && widget.customer == null) {
        throw 'البيع الآجل يتطلب اختيار عميل';
      }
      if (paid > widget.total && widget.customer == null) {
        throw 'الدفع الزائد يتطلب اختيار عميل';
      }

      final items = widget.cart.map((item) => {
        'product_id': item['product_id'],
        'unit_id': item['unit_id'],
        'quantity': item['qty'],
        'unit_price': item['price'],
      }).toList();

      await Supabase.instance.client.rpc('create_rep_sale', params: {
        'p_company_id': widget.companyId,
        'p_client_uuid': const Uuid().v4(),
        'p_payload': {
          'customer_id': widget.customer?['id'],
          'items': items,
          'payment_method': isCredit ? null : _method,
          'paid_amount': isCredit ? 0 : paid,
          'discount': widget.discount,
          'notes': 'فاتورة مندوب',
        }
      });

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalRequired = widget.total + widget.customerBalance;
    final paid = double.tryParse(_paidCtrl.text) ?? 0;
    final remaining = totalRequired - paid;

    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('إتمام الدفع', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          
          // الإجماليات
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                if (widget.customerBalance != 0) ...[
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('الرصيد السابق'), Text(widget.customerBalance.toStringAsFixed(2))]),
                  const SizedBox(height: 4),
                ],
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('قيمة الفاتورة'), Text(widget.total.toStringAsFixed(2))]),
                const Divider(),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('الإجمالي المطلوب', style: TextStyle(fontWeight: FontWeight.bold)), Text(totalRequired.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))]),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // طريقة الدفع
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'cash', label: Text('نقدي'), icon: Icon(Icons.payments)),
              ButtonSegment(value: 'credit', label: Text('آجل'), icon: Icon(Icons.schedule)),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
          const SizedBox(height: 16),

          if (_method != 'credit') ...[
            TextField(
              controller: _paidCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'المبلغ المدفوع', border: OutlineInputBorder(), suffixText: 'ج.م'),
              onChanged: (_) => setState((){}),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(remaining > 0 ? 'المتبقي:' : remaining < 0 ? 'الزيادة (تُضاف للرصيد):' : 'مطابق'),
                Text(
                  remaining.abs().toStringAsFixed(2),
                  style: TextStyle(fontWeight: FontWeight.bold, color: remaining > 0 ? Colors.red : remaining < 0 ? Colors.green : Colors.green),
                ),
              ],
            ),
          ] else ...[
            const Text('سيتم إضافة كامل قيمة الفاتورة إلى رصيد العميل.', style: TextStyle(color: Colors.orange)),
          ],

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _submit,
              icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
              label: Text(_isSaving ? 'جارٍ الحفظ...' : 'تأكيد وإتمام البيع'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ============================================================================
// 5. شاشة مسح الباركود
// ============================================================================
class _ScannerPage extends StatelessWidget {
  const _ScannerPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مسح الباركود')),
      body: MobileScanner(
        onDetect: (capture) {
          final barcodes = capture.barcodes;
          for (final b in barcodes) {
            if (b.rawValue != null) {
              Navigator.pop(context, b.rawValue);
              break;
            }
          }
        },
      ),
    );
  }
}

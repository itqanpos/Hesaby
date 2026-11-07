import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/pos_repository.dart';
import '../../domain/pos_models.dart';

class _C {
  static const primary = Color(0xFF00897B);
  static const primaryDark = Color(0xFF00695C);
  static const primaryLight = Color(0xFFE0F2F1);
  static const success = Color(0xFF2E7D32);
  static const successLight = Color(0xFFE8F5E9);
  static const warning = Color(0xFFE65100);
  static const danger = Color(0xFFC62828);
  static const dangerLight = Color(0xFFFFEBEE);
  static const surface = Colors.white;
  static const surfaceGray = Color(0xFFF5F5F5);
  static const border = Color(0xFFE0E0E0);
  static const text = Color(0xFF1A1A1A);
  static const textSecondary = Color(0xFF757575);
  static const bg = Color(0xFFFAFAFA);
}

class PosPage extends StatefulWidget {
  final String companyId;
  final String branchId;

  const PosPage({
    super.key,
    required this.companyId,
    required this.branchId,
  });

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  late final PosRepository _repo;
  final _searchCtrl = TextEditingController();

  List<PosProduct> _products = [];
  List<PosCustomer> _customers = [];
  List<PosCartLine> _cart = [];
  PosCustomer? _selectedCustomer;
  PosCartState? _heldCart; // لتخزين السلة المعلقة

  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  double _discount = 0;
  final double _taxAmount = 0; // يمكن ربطها بإعدادات الشركة

  @override
  void initState() {
    super.initState();
    _repo = PosRepository(Supabase.instance.client);
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.loadProducts(companyId: widget.companyId, branchId: widget.branchId),
        _repo.loadCustomers(companyId: widget.companyId),
      ]);
      if (!mounted) return;
      setState(() {
        _products = results[0] as List<PosProduct>;
        _customers = results[1] as List<PosCustomer>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ─── Cart Logic ───
  double get _subtotal => _cart.fold(0.0, (s, line) => s + line.lineTotal);
  double get _total => _subtotal - _discount + _taxAmount;
  int get _lineCount => _cart.length;

  Future<void> _addToCart(PosProduct product) async {
    final choice = await showModalBottomSheet<PosProductUnit>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UnitSelectorSheet(product: product),
    );
    if (choice == null) return;

    // فحص التكرار (مثل Hesabi)
    final existingIndex = _cart.indexWhere(
      (l) => l.product.id == product.id && l.unit.id == choice.id,
    );

    if (existingIndex >= 0) {
      // تأكيد الزيادة
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('المنتج موجود في السلة'),
          content: Text('«${product.name}» موجود بالفعل. هل تريد زيادة الكمية؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('زيادة')),
          ],
        ),
      );
      if (confirm != true) return;
      
      setState(() {
        _cart[existingIndex].quantity += 1;
      });
    } else {
      setState(() {
        _cart.add(PosCartLine(
          product: product,
          unit: choice,
          quantity: 1,
          unitPrice: choice.effectivePrice,
        ));
      });
    }
  }

  void _removeLine(int index) {
    setState(() => _cart.removeAt(index));
  }

  void _updateQuantity(int index, double newQty) {
    if (newQty <= 0) {
      _removeLine(index);
    } else {
      setState(() => _cart[index].quantity = newQty);
    }
  }

  void _clearCart() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الفاتورة'),
        content: const Text('هل أنت متأكد من إلغاء الفاتورة الحالية وحذف جميع الأصناف؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تراجع')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _C.danger),
            onPressed: () {
              setState(() => _cart.clear());
              Navigator.pop(ctx);
            },
            child: const Text('نعم، إلغاء'),
          ),
        ],
      ),
    );
  }

  // ─── Hold / Restore ───
  void _holdCart() {
    if (_cart.isEmpty) return;
    setState(() {
      _heldCart = PosCartState(
        lines: List.from(_cart),
        customer: _selectedCustomer,
        discount: _discount,
      );
      _cart.clear();
      _selectedCustomer = null;
      _discount = 0;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تعليق الفاتورة')));
  }

  void _restoreCart() {
    if (_heldCart == null) return;
    setState(() {
      _cart = List.from(_heldCart!.lines);
      _selectedCustomer = _heldCart!.customer;
      _discount = _heldCart!.discount;
      _heldCart = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم استعادة الفاتورة المعلقة')));
  }

  // ─── UI ───
  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: _C.primary)));
    if (_error != null) return Scaffold(body: Center(child: Text(_error!)));

    final isSearching = _searchQuery.isNotEmpty;

    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        backgroundColor: _C.surface,
        title: const Text('نقطة البيع', style: TextStyle(fontWeight: FontWeight.bold, color: _C.text)),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: _C.primary),
            onPressed: () async {
              final barcode = await Navigator.push<String>(
                context,
                MaterialPageRoute(builder: (_) => const _MockScannerPage()),
              );
              if (barcode != null) {
                _searchCtrl.text = barcode;
                setState(() => _searchQuery = barcode);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: _C.text),
            onPressed: _showActionsSheet,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _C.border),
        ),
      ),
      body: Column(
        children: [
          _buildCustomerBar(),
          _buildSearchField(),
          Expanded(
            child: isSearching
                ? _buildSplitView()
                : _buildCartList(),
          ),
          _buildBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildCustomerBar() {
    return InkWell(
      onTap: _showCustomerPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _selectedCustomer != null ? _C.primaryLight : Colors.white,
          border: const Border(bottom: BorderSide(color: _C.border)),
        ),
        child: Row(
          children: [
            Icon(Icons.person, color: _selectedCustomer != null ? _C.primaryDark : _C.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _selectedCustomer?.name ?? 'تحديد عميل (اختياري)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: _selectedCustomer != null ? FontWeight.bold : FontWeight.normal,
                  color: _selectedCustomer != null ? _C.primaryDark : _C.textSecondary,
                ),
              ),
            ),
            if (_selectedCustomer != null)
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: _C.primaryDark),
                onPressed: () => setState(() => _selectedCustomer = null),
              )
            else
              const Icon(Icons.chevron_left, color: _C.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'ابحث باسم المنتج أو الباركود...',
          prefixIcon: const Icon(Icons.search, color: _C.textSecondary),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() { _searchCtrl.clear(); _searchQuery = ''; }))
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _C.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _C.border),
          ),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  Widget _buildSplitView() {
    final results = _products.where((p) {
      final q = _searchQuery.toLowerCase();
      return p.name.toLowerCase().contains(q) || (p.barcode ?? '').contains(q);
    }).toList();

    return Column(
      children: [
        // النتائج
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text('نتائج البحث', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _C.primary)),
          ),
        ),
        Flexible(
          flex: 2,
          child: results.isEmpty
              ? const Center(child: Text('لا توجد نتائج', style: TextStyle(color: _C.textSecondary)))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _ResultTile(product: results[i], onTap: () => _addToCart(results[i])),
                ),
        ),
        const Divider(height: 1, color: _C.border),
        // السلة
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text('السلة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _C.textSecondary)),
          ),
        ),
        Flexible(flex: 3, child: _buildCartList()),
      ],
    );
  }

  Widget _buildCartList() {
    if (_cart.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 64, color: _C.textSecondary),
            SizedBox(height: 12),
            Text('السلة فارغة', style: TextStyle(color: _C.textSecondary, fontSize: 16)),
            SizedBox(height: 4),
            Text('ابحث عن منتج لإضافته', style: TextStyle(color: _C.textSecondary, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _cart.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final line = _cart[i];
        return _CartLineTile(
          line: line,
          onRemove: () => _removeLine(i),
          onQtyChanged: (q) => _updateQuantity(i, q),
        );
      },
    );
  }

  Widget _buildBottomPanel() {
    final maxDiscount = _subtotal * 0.2; // افتراضي 20%
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -4))],
        border: const Border(top: BorderSide(color: _C.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.shopping_bag_outlined, size: 16, color: _C.textSecondary),
                const SizedBox(width: 4),
                Text('الأصناف: $_lineCount', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _C.textSecondary)),
                const Spacer(),
                const Text('الخصم', style: TextStyle(fontSize: 12, color: _C.textSecondary)),
                const SizedBox(width: 6),
                SizedBox(
                  width: 70,
                  height: 32,
                  child: TextField(
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText: '0',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (v) {
                      final val = double.tryParse(v) ?? 0;
                      setState(() => _discount = val.clamp(0, maxDiscount));
                    },
                  ),
                ),
                const SizedBox(width: 4),
                const Text('ج.م', style: TextStyle(fontSize: 12, color: _C.textSecondary)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('الصافي', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(
                  '${_total.toStringAsFixed(2)} ج.م',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: _C.primary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _cart.isEmpty ? null : _clearCart,
                      icon: const Icon(Icons.delete_outline, size: 20),
                      label: const Text('إلغاء'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _C.danger,
                        side: const BorderSide(color: _C.danger),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _cart.isEmpty ? null : _showPaymentSheet,
                      icon: const Icon(Icons.payments, size: 20),
                      label: const Text('الدفع', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _C.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Sheets ───
  void _showCustomerPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('اختيار عميل', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _customers.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(_customers[i].name),
                  subtitle: Text(_customers[i].phone ?? ''),
                  onTap: () {
                    setState(() => _selectedCustomer = _customers[i]);
                    Navigator.pop(context);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PosPaymentSheet(
        cart: _cart,
        customer: _selectedCustomer,
        total: _total,
        discount: _discount,
        companyId: widget.companyId,
        branchId: widget.branchId,
        repo: _repo,
        onSuccess: () {
          setState(() {
            _cart.clear();
            _selectedCustomer = null;
            _discount = 0;
          });
        },
      ),
    );
  }

  void _showActionsSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.pause_circle_outline, color: _C.primary),
              title: const Text('تعليق الفاتورة'),
              subtitle: const Text('حفظ السلة مؤقتاً وبدء سلة جديدة'),
              enabled: _cart.isNotEmpty,
              onTap: () { Navigator.pop(context); _holdCart(); },
            ),
            ListTile(
              leading: const Icon(Icons.restore, color: _C.primary),
              title: const Text('استعادة السلة المعلقة'),
              subtitle: _heldCart != null ? Text('${_heldCart!.lines.length} صنف') : const Text('لا توجد سلة معلقة'),
              enabled: _heldCart != null,
              onTap: () { Navigator.pop(context); _restoreCart(); },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.assignment_return, color: _C.danger),
              title: const Text('إنشاء فاتورة مرتجع'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('قريباً: المرتجعات')));
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Components (Cart Line, Result Tile)
// ============================================================================

class _ResultTile extends StatelessWidget {
  final PosProduct product;
  final VoidCallback onTap;
  const _ResultTile({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: _C.primaryLight, borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.inventory_2, color: _C.primary, size: 20),
      ),
      title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text('${product.defaultPrice.toStringAsFixed(2)} ج.م'),
      trailing: const Icon(Icons.add_circle, color: _C.primary),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  final PosCartLine line;
  final VoidCallback onRemove;
  final ValueChanged<double> onQtyChanged;
  const _CartLineTile({required this.line, required this.onRemove, required this.onQtyChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(line.product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: _C.danger),
                onPressed: onRemove,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _QtyBtn(icon: Icons.remove, onTap: () => onQtyChanged(line.quantity - 1)),
              const SizedBox(width: 8),
              Text(line.quantity.toStringAsFixed(line.quantity == line.quantity.roundToDouble() ? 0 : 2), 
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(width: 8),
              _QtyBtn(icon: Icons.add, onTap: () => onQtyChanged(line.quantity + 1)),
              const Spacer(),
              Text('${line.lineTotal.toStringAsFixed(2)} ج.م', 
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: _C.primary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: _C.surfaceGray, borderRadius: BorderRadius.circular(6)),
        child: Icon(icon, size: 16, color: _C.text),
      ),
    );
  }
}

// ============================================================================
// Unit Selector Sheet
// ============================================================================

class _UnitSelectorSheet extends StatelessWidget {
  final PosProduct product;
  const _UnitSelectorSheet({required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('اختر وحدة البيع', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          Text('المنتج: ${product.name}', style: const TextStyle(color: _C.textSecondary)),
          const SizedBox(height: 16),
          ...product.allUnits.map((u) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => Navigator.pop(context, u),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: u.id == product.defaultUnit?.id ? _C.primaryLight : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: u.id == product.defaultUnit?.id ? _C.primary : _C.border, width: 1.5),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(u.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          if (u.id != product.defaultUnit?.id)
                            Text('معامل التحويل: ${u.conversionFactor}', style: const TextStyle(fontSize: 12, color: _C.textSecondary)),
                        ],
                      ),
                    ),
                    Text('${u.effectivePrice.toStringAsFixed(2)} ج.م', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: _C.primary)),
                  ],
                ),
              ),
            ),
          )),
        ],
      ),
    );
  }
}

// ============================================================================
// Payment Sheet (Multi-Payment Like Hesabi)
// ============================================================================

class _PaymentEntry {
  String method;
  double amount;
  final TextEditingController controller;
  _PaymentEntry({required this.method, required this.amount}) : controller = TextEditingController(text: amount == 0 ? '' : amount.toStringAsFixed(2));
}

class _PosPaymentSheet extends StatefulWidget {
  final List<PosCartLine> cart;
  final PosCustomer? customer;
  final double total;
  final double discount;
  final String companyId;
  final String branchId;
  final PosRepository repo;
  final VoidCallback onSuccess;

  const _PosPaymentSheet({
    required this.cart,
    this.customer,
    required this.total,
    required this.discount,
    required this.companyId,
    required this.branchId,
    required this.repo,
    required this.onSuccess,
  });

  @override
  State<_PosPaymentSheet> createState() => _PosPaymentSheetState();
}

class _PosPaymentSheetState extends State<_PosPaymentSheet> {
  late List<_PaymentEntry> _payments;
  bool _isCredit = false;
  bool _saving = false;
  String _method = 'cash'; // cash, card, instapay, bank_transfer

  @override
  void initState() {
    super.initState();
    _payments = [_PaymentEntry(method: 'cash', amount: widget.total)];
  }

  @override
  void dispose() {
    for (var p in _payments) { p.controller.dispose(); }
    super.dispose();
  }

  double get _totalPaid => _payments.fold(0.0, (s, p) => s + p.amount);
  double get _settlementTotal => widget.total + (widget.customer?.balance ?? 0);
  
  // Hesabi logic: Pay total, remaining goes to balance if customer exists.
  double get _appliedToSale => _isCredit ? 0 : (_totalPaid > widget.total ? widget.total : _totalPaid);
  double get _appliedToBalance => _isCredit ? widget.total : (_totalPaid > widget.total ? _totalPaid - widget.total : widget.total - _totalPaid);
  
  double get _remaining => _isCredit ? 0 : (_totalPaid < widget.total ? widget.total - _totalPaid : 0);
  double get _overpay => _totalPaid > _settlementTotal ? _totalPaid - _settlementTotal : 0;

  Future<void> _submit() async {
    if (!_isCredit && _appliedToBalance > 0 && widget.customer == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الدفع الجزئي يتطلب اختيار عميل'), backgroundColor: _C.danger));
      return;
    }
    if (_isCredit && widget.customer == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('البيع الآجل يتطلب اختيار عميل'), backgroundColor: _C.danger));
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.repo.createSale(
        companyId: widget.companyId,
        branchId: widget.branchId,
        customerId: widget.customer?.id,
        lines: widget.cart,
        payments: _isCredit ? [] : _payments.where((p) => p.amount > 0).map((p) => PaymentEntry(method: p.method, amount: p.amount)).toList(),
        discount: widget.discount,
        paidAmount: _appliedToSale,
        // Note: if repo handles overpay (adding to balance) via customer_id, we pass the total paid.
      );
      
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSuccess();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ تم إتمام البيع بنجاح'), backgroundColor: _C.success));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e'), backgroundColor: _C.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: const EdgeInsets.all(16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('الدفع', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            // Customer Bar
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _C.surfaceGray, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.person, color: _C.primary),
                  const SizedBox(width: 8),
                  Text(widget.customer?.name ?? 'عميل نقدي', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Totals
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('الإجمالي المطلوب:', style: TextStyle(fontSize: 16)),
                Text('${_settlementTotal.toStringAsFixed(2)} ج.م', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _C.primary)),
              ],
            ),
            const Divider(),
            // Toggle Pay/Credit
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('دفع'), icon: Icon(Icons.payments)),
                ButtonSegment(value: true, label: Text('آجل'), icon: Icon(Icons.schedule)),
              ],
              selected: {_isCredit},
              onSelectionChanged: (s) => setState(() => _isCredit = s.first),
            ),
            const SizedBox(height: 16),
            
            if (!_isCredit) ...[
              ..._payments.asMap().entries.map((e) {
                final i = e.key;
                final p = e.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      DropdownButton<String>(
                        value: p.method,
                        items: const [
                          DropdownMenuItem(value: 'cash', child: Text('نقدي')),
                          DropdownMenuItem(value: 'card', child: Text('بطاقة')),
                          DropdownMenuItem(value: 'instapay', child: Text('إنستاباي')),
                          DropdownMenuItem(value: 'bank_transfer', child: Text('تحويل')),
                        ],
                        onChanged: (v) => setState(() => p.method = v!),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: p.controller,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            suffixText: 'ج.م',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) => setState(() => p.amount = double.tryParse(v) ?? 0),
                        ),
                      ),
                      if (_payments.length > 1)
                        IconButton(icon: const Icon(Icons.close, color: _C.danger), onPressed: () => setState(() => _payments.removeAt(i))),
                    ],
                  ),
                );
              }),
              TextButton.icon(
                onPressed: () => setState(() => _payments.add(_PaymentEntry(method: 'cash', amount: 0))),
                icon: const Icon(Icons.add),
                label: const Text('إضافة طريقة دفع'),
              ),
              
              // Remaining indicator
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _remaining > 0 ? _C.dangerLight : _C.successLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_remaining > 0 ? 'المتبقي:' : 'المدفوع:', style: TextStyle(fontWeight: FontWeight.bold, color: _remaining > 0 ? _C.danger : _C.success)),
                    Text(_remaining > 0 ? '${_remaining.toStringAsFixed(2)} ج.م' : '${_totalPaid.toStringAsFixed(2)} ج.م', style: TextStyle(fontWeight: FontWeight.bold, color: _remaining > 0 ? _C.danger : _C.success)),
                  ],
                ),
              ),
            ] else ...[
              const Text('سيتم إضافة كامل قيمة الفاتورة إلى رصيد العميل.', textAlign: TextAlign.center, style: TextStyle(color: _C.textSecondary)),
            ],

            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _submit,
                style: ElevatedButton.styleFrom(backgroundColor: _C.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: _saving ? const CircularProgressIndicator(color: Colors.white) : const Text('إتمام البيع', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Mock Scanner (Replace with actual scanner if available)
// ============================================================================
class _MockScannerPage extends StatelessWidget {
  const _MockScannerPage();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مسح الباركود')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => Navigator.pop(context, '123456789'),
          child: const Text('محاكاة مسح باركود'),
        ),
      ),
    );
  }
}

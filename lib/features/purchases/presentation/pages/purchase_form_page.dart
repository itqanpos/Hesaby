// lib/features/purchases/presentation/pages/purchase_form_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../cash/domain/entities/cash_entities.dart';
import '../../../cash/presentation/providers/cash_providers.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/unit.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../../products/presentation/providers/unit_providers.dart';
import '../../domain/entities/purchase.dart';
import '../../domain/entities/purchase_cart.dart';
import '../../domain/entities/purchase_cart_line.dart';
import '../../domain/entities/purchase_item.dart';
import '../../domain/repositories/purchase_repository.dart';
import '../providers/purchase_providers.dart';
import '../state/purchase_cart_notifier.dart';
import '../state/purchase_providers.dart';
import 'purchase_mobile_layout.dart';

class PurchaseFormPage extends ConsumerStatefulWidget {
  const PurchaseFormPage({super.key, this.purchaseId});

  final String? purchaseId;

  @override
  ConsumerState<PurchaseFormPage> createState() =>
      _PurchaseFormPageState();
}

class _PurchaseFormPageState extends ConsumerState<PurchaseFormPage> {
  bool _isLoadingExisting = false;
  bool _isSubmitting = false;
  Object? _loadError;

  bool get _isEditMode => widget.purchaseId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      _isLoadingExisting = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadExisting();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final PurchaseCartNotifier cart =
            ref.read(purchaseCartProvider.notifier);
        cart.reset();
        cart.setPurchaseDate(DateTime.now());
      });
    }
  }

  CashAccountType _mapPaymentMethodToAccountType(String method) {
    switch (method) {
      case 'cash':
        return CashAccountType.cash;
      case 'card':
        return CashAccountType.card;
      case 'bank_transfer':
        return CashAccountType.bank;
      case 'instapay':
        return CashAccountType.instapay;
      default:
        return CashAccountType.other;
    }
  }

  Future<void> _loadExisting() async {
    final String? purchaseId = widget.purchaseId;
    if (purchaseId == null) {
      return;
    }

    try {
      final Purchase purchase = await ref
          .read(purchaseRepositoryProvider)
          .getPurchase(purchaseId);
      final List<PurchaseItem> items = await ref
          .read(purchaseRepositoryProvider)
          .listPurchaseItems(purchaseId);

      final List<Product> products =
          await ref.read(productsProvider.future);
      final List<Unit> units = await ref.read(unitsProvider.future);

      final Map<String, Product> productsById = <String, Product>{
        for (final Product p in products) p.id: p,
      };
      final Map<String, Unit> unitsById = <String, Unit>{
        for (final Unit u in units) u.id: u,
      };

      if (!mounted) return;

      final PurchaseCartNotifier cart =
          ref.read(purchaseCartProvider.notifier);
      cart.reset();

      cart.setPurchaseDate(purchase.purchaseDate);
      cart.setInvoiceNumber(purchase.invoiceNumber ?? '');
      cart.setNotes(purchase.notes ?? '');
      cart.setDiscount(purchase.discount);
      cart.setTaxAmount(purchase.taxAmount);
      cart.setSupplier(id: purchase.supplierId, name: '');

      for (final PurchaseItem item in items) {
        final Product? product = productsById[item.productId];
        final Unit? unit = unitsById[item.unitId];

        if (product == null || unit == null) continue;

        cart.addProduct(
          product: product,
          unit: unit,
          quantity: item.quantity,
          unitCost: item.unitCost,
        );
      }

      setState(() {
        _isLoadingExisting = false;
        _loadError = null;
      });
    } on PurchaseException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingExisting = false;
        _loadError = error;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingExisting = false;
        _loadError = error;
      });
    }
  }

  Future<void> _save({required bool andConfirm}) async {
    FocusScope.of(context).unfocus();

    final PurchaseCart cart = ref.read(purchaseCartProvider);

    if (!cart.hasSupplier || cart.supplierId == null) {
      _snack('اختر المورد أولًا.');
      return;
    }
    if (!cart.hasPurchaseDate || cart.purchaseDate == null) {
      _snack('اختر تاريخ الفاتورة.');
      return;
    }
    if (cart.isEmpty) {
      _snack('أضف بندًا واحدًا على الأقل.');
      return;
    }

    // ⬇️ التحقق من رصيد الخزنة قبل الحفظ
    if (cart.paidAmount > 0) {
      final overview = ref.read(cashOverviewProvider).valueOrNull;
      if (overview != null) {
        final targetType = _mapPaymentMethodToAccountType(cart.paymentMethod);
        double currentBalance = 0.0;
        
        for (final balance in overview.balances) {
          if (balance.account.type == targetType) {
            currentBalance = balance.balance;
            break;
          }
        }

        if (cart.paidAmount > currentBalance) {
          _snack('الرصيد غير كافٍ في الخزنة. المتاح: ${AppFormatters.money(currentBalance)}');
          return;
        }
      }
    }

    final CompanyContextState contextState =
        ref.read(companyContextProvider);
    final String? branchId = contextState.currentBranch?.id;
    if (branchId == null) {
      _snack('الفرع غير متاح. يرجى إعادة اختياره.');
      return;
    }

    setState(() => _isSubmitting = true);

    final PurchasesNotifier notifier =
        ref.read(purchasesProvider.notifier);

    try {
      final List<PurchaseItemDraft> items = <PurchaseItemDraft>[
        for (final PurchaseCartLine line in cart.lines)
          PurchaseItemDraft(
            productId: line.productId,
            unitId: line.unitId,
            quantity: line.quantity,
            unitCost: line.unitCost,
            notes: line.notes,
          ),
      ];

      Purchase saved;
      if (_isEditMode) {
        saved = await notifier.updateDraft(
          purchaseId: widget.purchaseId!,
          branchId: branchId,
          supplierId: cart.supplierId!,
          purchaseDate: cart.purchaseDate!,
          items: items,
          invoiceNumber: cart.invoiceNumber.trim().isEmpty
              ? null
              : cart.invoiceNumber.trim(),
          discount: cart.discount,
          taxAmount: cart.taxAmount,
          paidAmount: cart.paidAmount,          // ⬅️ إرسال المبلغ المدفوع
          paymentMethod: cart.paymentMethod,    // ⬅️ إرسال طريقة الدفع
          notes: cart.notes.trim().isEmpty ? null : cart.notes.trim(),
        );
      } else {
        saved = await notifier.createPurchase(
          branchId: branchId,
          supplierId: cart.supplierId!,
          purchaseDate: cart.purchaseDate!,
          items: items,
          invoiceNumber: cart.invoiceNumber.trim().isEmpty
              ? null
              : cart.invoiceNumber.trim(),
          discount: cart.discount,
          taxAmount: cart.taxAmount,
          paidAmount: cart.paidAmount,          // ⬅️ إرسال المبلغ المدفوع
          paymentMethod: cart.paymentMethod,    // ⬅️ إرسال طريقة الدفع
          notes: cart.notes.trim().isEmpty ? null : cart.notes.trim(),
        );
      }

      if (andConfirm) {
        await notifier.confirmPurchase(saved.id);
      }

      if (!mounted) return;

      ref.read(purchaseCartProvider.notifier).reset();
      ref.read(purchaseSearchProvider.notifier).clear();

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              andConfirm ? 'تم حفظ وتأكيد الفاتورة.' : 'تم حفظ المسودة.',
            ),
          ),
        );

      Navigator.of(context).pop(true);
    } on PurchaseException catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _snack(_failureMessage(error.type));
    } on Object {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _snack('تعذّر حفظ الفاتورة. حاول مرة أخرى.');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingExisting) {
      return AppShell(
        appBar: AppBar(title: const Text('تعديل فاتورة')),
        body: const AppLoader(),
      );
    }

    if (_loadError != null) {
      return AppShell(
        appBar: AppBar(title: const Text('تعديل فاتورة')),
        body: AppErrorView(
          title: 'تعذّر تحميل الفاتورة',
          message: _errorMessage(_loadError!),
          retryLabel: 'إعادة المحاولة',
          onRetry: () {
            setState(() {
              _isLoadingExisting = true;
              _loadError = null;
            });
            _loadExisting();
          },
        ),
      );
    }

    return AppShell(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(_isEditMode ? 'تعديل فاتورة' : 'فاتورة جديدة'),
      ),
      body: PurchaseMobileLayout(
        onSaveDraft: () => _save(andConfirm: false),
        onSaveAndConfirm: () => _save(andConfirm: true),
        isSubmitting: _isSubmitting,
      ),
    );
  }
}

String _errorMessage(Object error) {
  if (error is PurchaseException) {
    return _failureMessage(error.type);
  }
  return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
}

String _failureMessage(PurchaseFailureType type) => switch (type) {
      PurchaseFailureType.network =>
        'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.',
      PurchaseFailureType.unauthorized =>
        'انتهت صلاحية الجلسة أو لا تملك صلاحية. يرجى تسجيل الدخول مجددًا.',
      PurchaseFailureType.notFound =>
        'الفاتورة المطلوبة غير موجودة.',
      PurchaseFailureType.invalidStatusTransition =>
        'لا يمكن إجراء هذه العملية على الفاتورة في حالتها الحالية.',
      PurchaseFailureType.emptyPurchase =>
        'لا يمكن تأكيد فاتورة بدون بنود.',
      PurchaseFailureType.invoiceNumberConflict =>
        'يوجد فاتورة أخرى بنفس الرقم في هذه الشركة.',
      PurchaseFailureType.supplierNotFound =>
        'المورد المختار غير متاح. يرجى إعادة اختياره.',
      PurchaseFailureType.branchNotFound =>
        'الفرع المختار غير متاح. يرجى إعادة اختياره.',
      PurchaseFailureType.productNotFound =>
        'أحد المنتجات المختارة غير متاح.',
      PurchaseFailureType.unitNotFound =>
        'إحدى الوحدات المختارة غير متاحة.',
      PurchaseFailureType.insufficientStock =>
        'لا يمكن عكس الفاتورة؛ بعض الكميات استُهلكت بالفعل.',
      PurchaseFailureType.invalidResponse =>
        'القيم المُدخلة غير صحيحة. يرجى التحقق من الكميات والأسعار.',
      PurchaseFailureType.unknown =>
        'تعذّر حفظ الفاتورة. يرجى المحاولة مرة أخرى.',
    };

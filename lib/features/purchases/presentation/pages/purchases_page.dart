// lib/features/purchases/presentation/pages/purchases_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../suppliers/domain/entities/supplier.dart';
import '../../../suppliers/presentation/providers/supplier_providers.dart';
import '../../domain/entities/purchase.dart';
import '../../domain/repositories/purchase_repository.dart';
import '../providers/purchase_providers.dart';

/// Purchases list page.
///
/// Displays the purchase orders of the currently selected company, with
/// client-side filters on status and invoice number. Every mutation (create,
/// edit, confirm, cancel) is performed on dedicated pages or via contextual
/// actions; this page is read-mostly.
class PurchasesPage extends ConsumerStatefulWidget {
  const PurchasesPage({super.key});

  @override
  ConsumerState<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends ConsumerState<PurchasesPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  /// `null` means "all statuses".
  String? _statusFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CompanyContextState contextState =
        ref.watch(companyContextProvider);
    final String? branchId = contextState.currentBranch?.id;

    final AsyncValue<List<Purchase>> purchasesAsync =
        ref.watch(purchasesProvider);
    final AsyncValue<List<Supplier>> suppliersAsync =
        ref.watch(suppliersProvider);

    final bool anyLoading =
        purchasesAsync.isLoading || suppliersAsync.isLoading;
    final Object? firstError = purchasesAsync.error ?? suppliersAsync.error;

    return AppShell(
      appBar: AppBar(
        title: const Text('فواتير الشراء'),
        actions: <Widget>[
          IconButton(
            tooltip: 'إضافة فاتورة',
            onPressed: anyLoading || firstError != null || branchId == null
                ? null
                : () => context.pushNamed(AppRouter.purchaseNewName),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Builder(
        builder: (BuildContext context) {
          if (anyLoading) {
            return const AppLoader();
          }

          if (firstError != null) {
            return AppErrorView(
              title: 'تعذّر تحميل فواتير الشراء',
              message: _errorMessage(firstError),
              retryLabel: 'إعادة المحاولة',
              onRetry: () {
                ref.invalidate(purchasesProvider);
                ref.invalidate(suppliersProvider);
              },
            );
          }

          if (branchId == null) {
            return const AppEmptyView(
              icon: Icons.store_mall_directory_outlined,
              title: 'لم يتم اختيار فرع',
              message: 'اختر فرعًا من الصفحة الرئيسية لعرض فواتير الشراء.',
            );
          }

          final List<Purchase> allPurchases =
              purchasesAsync.value ?? const <Purchase>[];
          final List<Supplier> suppliers =
              suppliersAsync.value ?? const <Supplier>[];

          final Map<String, String> supplierNames = <String, String>{
            for (final Supplier supplier in suppliers)
              supplier.id: supplier.name,
          };

          final List<Purchase> filtered = _applyFilters(
            allPurchases,
            _statusFilter,
            _searchQuery,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: AppTextField(
                  controller: _searchController,
                  hint: 'ابحث برقم الفاتورة',
                  prefixIcon: Icons.search,
                  onChanged: (String value) {
                    setState(() => _searchQuery = value);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _StatusFilterChips(
                  selected: _statusFilter,
                  onChanged: (String? status) {
                    setState(() => _statusFilter = status);
                  },
                ),
              ),
              Expanded(
                child: allPurchases.isEmpty
                    ? AppEmptyView(
                        icon: Icons.receipt_long_outlined,
                        title: 'لا توجد فواتير شراء',
                        message:
                            'ابدأ بتسجيل أول فاتورة شراء من أحد الموردين.',
                        action: AppButton(
                          label: 'إضافة فاتورة',
                          icon: Icons.add,
                          onPressed: () =>
                              context.pushNamed(AppRouter.purchaseNewName),
                        ),
                      )
                    : filtered.isEmpty
                        ? const AppEmptyView(
                            icon: Icons.search_off_outlined,
                            title: 'لا نتائج',
                            message: 'لم تُطابق أي فاتورة معايير البحث.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder:
                                (BuildContext context, int index) {
                              final Purchase purchase = filtered[index];
                              final String supplierName =
                                  supplierNames[purchase.supplierId] ??
                                      'مورد محذوف';
                              return _PurchaseCard(
                                purchase: purchase,
                                supplierName: supplierName,
                                onTap: () => _openDetail(context, purchase),
                                onEdit: purchase.canEdit
                                    ? () => _openEdit(context, purchase)
                                    : null,
                                onConfirm: purchase.isDraft
                                    ? () => _confirmPurchase(
                                          context,
                                          purchase,
                                        )
                                    : null,
                                onCancel: purchase.canTransition
                                    ? () => _confirmCancel(
                                          context,
                                          purchase,
                                        )
                                    : null,
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Filtering
  // ---------------------------------------------------------------------------

  List<Purchase> _applyFilters(
    List<Purchase> purchases,
    String? status,
    String query,
  ) {
    final String trimmed = query.trim().toLowerCase();
    return purchases.where((Purchase purchase) {
      if (status != null && purchase.status != status) {
        return false;
      }
      if (trimmed.isEmpty) {
        return true;
      }
      final String invoice =
          (purchase.invoiceNumber ?? '').toLowerCase();
      return invoice.contains(trimmed);
    }).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _openDetail(BuildContext context, Purchase purchase) {
    context.pushNamed(
      AppRouter.purchaseDetailName,
      pathParameters: <String, String>{'id': purchase.id},
    );
  }

  void _openEdit(BuildContext context, Purchase purchase) {
    context.pushNamed(
      AppRouter.purchaseEditName,
      pathParameters: <String, String>{'id': purchase.id},
    );
  }

  Future<void> _confirmPurchase(
    BuildContext context,
    Purchase purchase,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('تأكيد الفاتورة'),
        content: Text(
          'سيتم تأكيد الفاتورة وإضافة الكميات إلى المخزون. '
          'لا يمكن التعديل بعد التأكيد.',
        ),
        actions: <Widget>[
          AppButton(
            label: 'إلغاء',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            label: 'تأكيد',
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      await ref
          .read(purchasesProvider.notifier)
          .confirmPurchase(purchase.id);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تأكيد الفاتورة')),
      );
    } on PurchaseException catch (error) {
      if (!context.mounted) {
        return;
      }
      _showError(context, error);
    }
  }

  Future<void> _confirmCancel(
    BuildContext context,
    Purchase purchase,
  ) async {
    final bool wasConfirmed = purchase.isConfirmed;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('إلغاء الفاتورة'),
        content: Text(
          wasConfirmed
              ? 'سيتم إلغاء الفاتورة وعكس كميات المخزون. '
                  'قد يفشل الإلغاء إذا استُهلكت الكميات.'
              : 'سيتم إلغاء الفاتورة. لا يمكن التراجع عن هذا الإجراء.',
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

    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      await ref
          .read(purchasesProvider.notifier)
          .cancelPurchase(purchase.id);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إلغاء الفاتورة')),
      );
    } on PurchaseException catch (error) {
      if (!context.mounted) {
        return;
      }
      _showError(context, error);
    }
  }
}

// -----------------------------------------------------------------------------
// Filter chips
// -----------------------------------------------------------------------------

class _StatusFilterChips extends StatelessWidget {
  const _StatusFilterChips({
    required this.selected,
    required this.onChanged,
  });

  /// Currently selected status, or `null` for "all".
  final String? selected;

  /// Called with the new selection (`null` means "all").
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _chip(context, 'الكل', null),
          const SizedBox(width: 8),
          _chip(context, 'مسودة', PurchaseStatus.draft),
          const SizedBox(width: 8),
          _chip(context, 'مؤكدة', PurchaseStatus.confirmed),
          const SizedBox(width: 8),
          _chip(context, 'ملغاة', PurchaseStatus.cancelled),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, String? value) {
    return ChoiceChip(
      label: Text(label),
      selected: selected == value,
      onSelected: (_) => onChanged(value),
    );
  }
}

// -----------------------------------------------------------------------------
// Purchase card
// -----------------------------------------------------------------------------

class _PurchaseCard extends StatelessWidget {
  const _PurchaseCard({
    required this.purchase,
    required this.supplierName,
    required this.onTap,
    required this.onEdit,
    required this.onConfirm,
    required this.onCancel,
  });

  final Purchase purchase;
  final String supplierName;
  final VoidCallback onTap;

  /// `null` when edit is not allowed (purchase is not in draft).
  final VoidCallback? onEdit;

  /// `null` when confirm is not allowed (purchase is not in draft).
  final VoidCallback? onConfirm;

  /// `null` when cancel is not allowed (already cancelled).
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final NumberFormat moneyFormat = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );
    final DateFormat dateFormat = DateFormat.yMd('ar_EG');

    final (Color badgeBg, Color badgeFg) = _statusColors(
      scheme,
      purchase.status,
    );
    final String statusLabel = _statusLabel(purchase.status);

    final String? invoice = purchase.invoiceNumber;
    final String headerTitle =
        (invoice != null && invoice.isNotEmpty) ? invoice : 'بدون رقم فاتورة';

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                backgroundColor: badgeBg,
                foregroundColor: badgeFg,
                child: const Icon(Icons.receipt_long_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            headerTitle,
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 2,
                            ),
                            child: Text(
                              statusLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: badgeFg,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      supplierName,
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Text(
                          dateFormat.format(purchase.purchaseDate),
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          moneyFormat.format(purchase.total),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _buildMenu(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    final List<PopupMenuEntry<_PurchaseAction>> items =
        <PopupMenuEntry<_PurchaseAction>>[];

    if (onEdit != null) {
      items.add(
        const PopupMenuItem<_PurchaseAction>(
          value: _PurchaseAction.edit,
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('تعديل'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      );
    }
    if (onConfirm != null) {
      items.add(
        const PopupMenuItem<_PurchaseAction>(
          value: _PurchaseAction.confirm,
          child: ListTile(
            leading: Icon(Icons.check_circle_outline),
            title: Text('تأكيد'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      );
    }
    if (onCancel != null) {
      items.add(
        const PopupMenuItem<_PurchaseAction>(
          value: _PurchaseAction.cancel,
          child: ListTile(
            leading: Icon(Icons.cancel_outlined),
            title: Text('إلغاء الفاتورة'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return const SizedBox(width: 24);
    }

    return PopupMenuButton<_PurchaseAction>(
      tooltip: 'خيارات',
      onSelected: (_PurchaseAction action) {
        switch (action) {
          case _PurchaseAction.edit:
            onEdit?.call();
          case _PurchaseAction.confirm:
            onConfirm?.call();
          case _PurchaseAction.cancel:
            onCancel?.call();
        }
      },
      itemBuilder: (BuildContext context) => items,
    );
  }
}

enum _PurchaseAction { edit, confirm, cancel }

// -----------------------------------------------------------------------------
// Localization helpers
// -----------------------------------------------------------------------------

String _statusLabel(String status) {
  switch (status) {
    case PurchaseStatus.draft:
      return 'مسودة';
    case PurchaseStatus.confirmed:
      return 'مؤكدة';
    case PurchaseStatus.cancelled:
      return 'ملغاة';
    default:
      return 'غير معروفة';
  }
}

(Color background, Color foreground) _statusColors(
  ColorScheme scheme,
  String status,
) {
  switch (status) {
    case PurchaseStatus.draft:
      return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
    case PurchaseStatus.confirmed:
      return (scheme.primaryContainer, scheme.onPrimaryContainer);
    case PurchaseStatus.cancelled:
      return (scheme.errorContainer, scheme.onErrorContainer);
    default:
      return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
  }
}

void _showError(BuildContext context, PurchaseException error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(_failureMessage(error.type))),
  );
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
        'الفاتورة المطلوبة غير موجودة أو تم حذفها.',
      PurchaseFailureType.invalidStatusTransition =>
        'لا يمكن إجراء هذه العملية على الفاتورة في حالتها الحالية.',
      PurchaseFailureType.emptyPurchase =>
        'لا يمكن تأكيد فاتورة بدون بنود. أضف منتجًا واحدًا على الأقل.',
      PurchaseFailureType.invoiceNumberConflict =>
        'يوجد فاتورة أخرى بنفس الرقم في هذه الشركة.',
      PurchaseFailureType.supplierNotFound =>
        'المورد المختار غير متاح. يرجى إعادة اختياره.',
      PurchaseFailureType.branchNotFound =>
        'الفرع المختار غير متاح. يرجى إعادة اختياره.',
      PurchaseFailureType.productNotFound =>
        'أحد المنتجات المختارة غير متاح. يرجى إعادة اختياره.',
      PurchaseFailureType.unitNotFound =>
        'إحدى الوحدات المختارة غير متاحة. يرجى إعادة اختيارها.',
      PurchaseFailureType.insufficientStock =>
        'لا يمكن عكس الفاتورة؛ بعض الكميات استُهلكت بالفعل.',
      PurchaseFailureType.invalidResponse =>
        'تعذّر قراءة بيانات الفواتير. يرجى المحاولة لاحقًا.',
      PurchaseFailureType.unknown =>
        'تعذّر إتمام العملية. يرجى المحاولة مرة أخرى.',
    };

// lib/features/companies/domain/entities/member_permission.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Every permission the app understands, grouped by domain.
///
/// The model is a **deny-list**: a member starts with all permissions, and
/// the manager revokes the ones they want to withhold. Hence we only ever
/// store *denied* codes — no "granted" column is needed.
///
/// Codes are `domain.action` strings. Adding a new permission later does
/// not require any database migration: it becomes automatically granted
/// to every existing member until a manager explicitly denies it.
abstract final class MemberPermission {
  // ---------------------------------------------------------------------------
  // POS
  // ---------------------------------------------------------------------------
  static const String posUse = 'pos.use';

  // ---------------------------------------------------------------------------
  // Sales
  // ---------------------------------------------------------------------------
  static const String salesView = 'sales.view';
  static const String salesCreate = 'sales.create';
  static const String salesEdit = 'sales.edit';
  static const String salesConfirm = 'sales.confirm';
  static const String salesCancel = 'sales.cancel';
  static const String salesDelete = 'sales.delete';
  static const String salesPrint = 'sales.print';

  // ---------------------------------------------------------------------------
  // Returns
  // ---------------------------------------------------------------------------
  static const String returnsView = 'returns.view';
  static const String returnsCreate = 'returns.create';
  static const String returnsCancel = 'returns.cancel';

  // ---------------------------------------------------------------------------
  // Products
  // ---------------------------------------------------------------------------
  static const String productsView = 'products.view';
  static const String productsCreate = 'products.create';
  static const String productsEdit = 'products.edit';
  static const String productsDelete = 'products.delete';
  static const String productsManageUnits = 'products.manage_units';

  // ---------------------------------------------------------------------------
  // Inventory
  // ---------------------------------------------------------------------------
  static const String inventoryView = 'inventory.view';
  static const String inventoryAdjust = 'inventory.adjust';

  // ---------------------------------------------------------------------------
  // Purchases
  // ---------------------------------------------------------------------------
  static const String purchasesView = 'purchases.view';
  static const String purchasesCreate = 'purchases.create';
  static const String purchasesConfirm = 'purchases.confirm';
  static const String purchasesCancel = 'purchases.cancel';
  static const String paymentsRecord = 'payments.record';

  // ---------------------------------------------------------------------------
  // Suppliers
  // ---------------------------------------------------------------------------
  static const String suppliersView = 'suppliers.view';
  static const String suppliersManage = 'suppliers.manage';

  // ---------------------------------------------------------------------------
  // Customers
  // ---------------------------------------------------------------------------
  static const String customersView = 'customers.view';
  static const String customersManage = 'customers.manage';
  static const String customersRecordPayment = 'customers.record_payment';

  // ---------------------------------------------------------------------------
  // Reports
  // ---------------------------------------------------------------------------
  static const String reportsView = 'reports.view';
  static const String reportsSales = 'reports.sales';
  static const String reportsInventory = 'reports.inventory';
  static const String reportsFinancial = 'reports.financial';
  static const String reportsExport = 'reports.export';

  // ---------------------------------------------------------------------------
  // Settings & members
  // ---------------------------------------------------------------------------
  static const String settingsCompany = 'settings.company';
  static const String settingsBranches = 'settings.branches';
  static const String settingsPrinter = 'settings.printer';
  static const String membersView = 'members.view';
  static const String membersManage = 'members.manage';

  // ---------------------------------------------------------------------------
  // Complete list
  // ---------------------------------------------------------------------------

  /// Every permission the app recognises. Used for validation only — the
  /// app never needs to iterate over this list to decide access, because
  /// access is computed from the deny-list.
  static const List<String> all = <String>[
    // POS
    posUse,
    // Sales
    salesView,
    salesCreate,
    salesEdit,
    salesConfirm,
    salesCancel,
    salesDelete,
    salesPrint,
    // Returns
    returnsView,
    returnsCreate,
    returnsCancel,
    // Products
    productsView,
    productsCreate,
    productsEdit,
    productsDelete,
    productsManageUnits,
    // Inventory
    inventoryView,
    inventoryAdjust,
    // Purchases
    purchasesView,
    purchasesCreate,
    purchasesConfirm,
    purchasesCancel,
    paymentsRecord,
    // Suppliers
    suppliersView,
    suppliersManage,
    // Customers
    customersView,
    customersManage,
    customersRecordPayment,
    // Reports
    reportsView,
    reportsSales,
    reportsInventory,
    reportsFinancial,
    reportsExport,
    // Settings & members
    settingsCompany,
    settingsBranches,
    settingsPrinter,
    membersView,
    membersManage,
  ];

  /// Arabic label for a single permission code. Falls back to the raw code
  /// when unknown, so an older client never crashes on a newer permission.
  static String label(String code) {
    switch (code) {
      // POS
      case posUse:
        return 'فتح نقطة البيع';

      // Sales
      case salesView:
        return 'عرض قائمة الفواتير';
      case salesCreate:
        return 'إنشاء فاتورة جديدة';
      case salesEdit:
        return 'تعديل مسودة فاتورة';
      case salesConfirm:
        return 'تأكيد الفاتورة';
      case salesCancel:
        return 'إلغاء فاتورة مؤكدة';
      case salesDelete:
        return 'حذف مسودة فاتورة';
      case salesPrint:
        return 'طباعة الإيصال';

      // Returns
      case returnsView:
        return 'عرض المرتجعات';
      case returnsCreate:
        return 'إنشاء مرتجع';
      case returnsCancel:
        return 'إلغاء مرتجع';

      // Products
      case productsView:
        return 'عرض المنتجات';
      case productsCreate:
        return 'إضافة منتج';
      case productsEdit:
        return 'تعديل منتج';
      case productsDelete:
        return 'حذف منتج';
      case productsManageUnits:
        return 'إدارة وحدات المنتج';

      // Inventory
      case inventoryView:
        return 'عرض المخزون';
      case inventoryAdjust:
        return 'تسوية المخزون يدويًا';

      // Purchases
      case purchasesView:
        return 'عرض فواتير الشراء';
      case purchasesCreate:
        return 'إنشاء فاتورة شراء';
      case purchasesConfirm:
        return 'تأكيد فاتورة الشراء';
      case purchasesCancel:
        return 'إلغاء فاتورة شراء';
      case paymentsRecord:
        return 'تسجيل دفعة للمورد';

      // Suppliers
      case suppliersView:
        return 'عرض الموردين';
      case suppliersManage:
        return 'إضافة وتعديل الموردين';

      // Customers
      case customersView:
        return 'عرض العملاء';
      case customersManage:
        return 'إضافة وتعديل العملاء';
      case customersRecordPayment:
        return 'تحصيل دفعة من العميل';

      // Reports
      case reportsView:
        return 'فتح قائمة التقارير';
      case reportsSales:
        return 'تقارير المبيعات';
      case reportsInventory:
        return 'تقارير المخزون';
      case reportsFinancial:
        return 'التقارير المالية';
      case reportsExport:
        return 'تصدير التقارير PDF';

      // Settings & members
      case settingsCompany:
        return 'إعدادات الشركة';
      case settingsBranches:
        return 'إدارة الفروع';
      case settingsPrinter:
        return 'إعدادات الطابعة';
      case membersView:
        return 'عرض الأعضاء';
      case membersManage:
        return 'تعديل صلاحيات الأعضاء';

      default:
        return code;
    }
  }
}

/// A group of permissions shown together in the management UI.
@immutable
class PermissionGroup extends Equatable {
  const PermissionGroup({
    required this.key,
    required this.label,
    required this.permissions,
  });

  /// Stable key (used for keys in the UI).
  final String key;

  /// Arabic display label.
  final String label;

  /// Permission codes belonging to this group, in display order.
  final List<String> permissions;

  @override
  List<Object?> get props => <Object?>[key, label, permissions];
}

/// The 9 groups displayed in the permissions editor. Order here is the
/// order rendered in the UI.
const List<PermissionGroup> kPermissionGroups = <PermissionGroup>[
  PermissionGroup(
    key: 'pos',
    label: 'نقطة البيع',
    permissions: <String>[MemberPermission.posUse],
  ),
  PermissionGroup(
    key: 'sales',
    label: 'المبيعات',
    permissions: <String>[
      MemberPermission.salesView,
      MemberPermission.salesCreate,
      MemberPermission.salesEdit,
      MemberPermission.salesConfirm,
      MemberPermission.salesCancel,
      MemberPermission.salesDelete,
      MemberPermission.salesPrint,
    ],
  ),
  PermissionGroup(
    key: 'returns',
    label: 'المرتجعات',
    permissions: <String>[
      MemberPermission.returnsView,
      MemberPermission.returnsCreate,
      MemberPermission.returnsCancel,
    ],
  ),
  PermissionGroup(
    key: 'products',
    label: 'المنتجات',
    permissions: <String>[
      MemberPermission.productsView,
      MemberPermission.productsCreate,
      MemberPermission.productsEdit,
      MemberPermission.productsDelete,
      MemberPermission.productsManageUnits,
    ],
  ),
  PermissionGroup(
    key: 'inventory',
    label: 'المخزون',
    permissions: <String>[
      MemberPermission.inventoryView,
      MemberPermission.inventoryAdjust,
    ],
  ),
  PermissionGroup(
    key: 'purchases',
    label: 'المشتريات',
    permissions: <String>[
      MemberPermission.purchasesView,
      MemberPermission.purchasesCreate,
      MemberPermission.purchasesConfirm,
      MemberPermission.purchasesCancel,
      MemberPermission.paymentsRecord,
    ],
  ),
  PermissionGroup(
    key: 'partners',
    label: 'الموردون والعملاء',
    permissions: <String>[
      MemberPermission.suppliersView,
      MemberPermission.suppliersManage,
      MemberPermission.customersView,
      MemberPermission.customersManage,
      MemberPermission.customersRecordPayment,
    ],
  ),
  PermissionGroup(
    key: 'reports',
    label: 'التقارير',
    permissions: <String>[
      MemberPermission.reportsView,
      MemberPermission.reportsSales,
      MemberPermission.reportsInventory,
      MemberPermission.reportsFinancial,
      MemberPermission.reportsExport,
    ],
  ),
  PermissionGroup(
    key: 'settings',
    label: 'الإعدادات والأعضاء',
    permissions: <String>[
      MemberPermission.settingsCompany,
      MemberPermission.settingsBranches,
      MemberPermission.settingsPrinter,
      MemberPermission.membersView,
      MemberPermission.membersManage,
    ],
  ),
];

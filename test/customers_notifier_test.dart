// test/customers_notifier_test.dart

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hesabi/data/local/app_database.dart';
import 'package:hesabi/data/local/daos/customers_dao.dart';
import 'package:hesabi/features/companies/domain/entities/branch.dart';
import 'package:hesabi/features/companies/presentation/providers/company_context_provider.dart';
import 'package:hesabi/features/companies/presentation/providers/company_context_state.dart';
import 'package:hesabi/features/sales/domain/entities/sale_entities.dart';
import 'package:hesabi/features/sales/domain/repositories/sales_repository.dart';
import 'package:hesabi/features/sales/presentation/providers/sales_providers.dart';

// ============================================================================
// Fake Customer Repository (فقط لمنع محاولة تهيئة Supabase أثناء الاختبار)
// ============================================================================
class _FakeCustomerRepository implements CustomerRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

// ============================================================================
// Fake Company Context Notifier
// ============================================================================
class _FakeCompanyContextNotifier extends CompanyContextNotifier {
  @override
  CompanyContextState build() {
    return const CompanyContextState(
      currentCompany: null,
      branches: <Branch>[],
      currentBranch: null,
    );
  }
}

// ============================================================================
// Helpers
// ============================================================================
ProviderContainer buildContainer(AppDatabase db) {
  return ProviderContainer(
    overrides: <Override>[
      // ✅ استخدام قاعدة بيانات وهمية في الذاكرة
      appDatabaseProvider.overrideWithValue(db),
      companyContextProvider.overrideWith(_FakeCompanyContextNotifier.new),
      customerRepositoryProvider.overrideWithValue(_FakeCustomerRepository()),
    ],
  );
}

// ============================================================================
// Tests
// ============================================================================
void main() {
  late AppDatabase db;
  late Customer activeCustomer;
  late Customer secondCustomer;

  setUp(() {
    // إنشاء قاعدة بيانات في الذاكرة لكل اختبار
    db = AppDatabase(NativeDatabase.memory());

    activeCustomer = Customer(
      id: 'c1',
      companyId: 'co1',
      name: 'أحمد محمد',
      balance: 500,
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    secondCustomer = Customer(
      id: 'c2',
      companyId: 'co1',
      name: 'علي',
      balance: 0,
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('CustomersNotifier — updateCustomer(isActive)', () {
    test('disables a customer successfully', () async {
      // 1. إدخال العميل في Drift
      await db.customersDao.createCustomer(
        customer: activeCustomer.toCompanion(),
        customerPayload: activeCustomer.toJsonPayload(),
      );
      await db.customersDao.createCustomer(
        customer: secondCustomer.toCompanion(),
        customerPayload: secondCustomer.toJsonPayload(),
      );

      final container = buildContainer(db);
      addTearDown(container.dispose);

      final notifier = container.read(customersProvider.notifier);
      
      // 2. تنفيذ التعديل
      final Customer result = await notifier.updateCustomer(
        customerId: 'c1',
        isActive: false,
      );

      expect(result.isActive, isFalse);

      // 3. التأكد من أن التعديل تم حفظه في Drift
      final dbCustomer = await db.customersDao.getCustomerById('c1');
      expect(dbCustomer?.isActive, isFalse);
    });

    test('re-enables a disabled customer successfully', () async {
      final disabledCustomer = activeCustomer.copyWith(isActive: false);
      await db.customersDao.createCustomer(
        customer: disabledCustomer.toCompanion(),
        customerPayload: disabledCustomer.toJsonPayload(),
      );

      final container = buildContainer(db);
      addTearDown(container.dispose);

      final notifier = container.read(customersProvider.notifier);
      final Customer result = await notifier.updateCustomer(
        customerId: 'c1',
        isActive: true,
      );

      expect(result.isActive, isTrue);

      final dbCustomer = await db.customersDao.getCustomerById('c1');
      expect(dbCustomer?.isActive, isTrue);
    });

    test('updating other fields does not alter isActive', () async {
      await db.customersDao.createCustomer(
        customer: activeCustomer.toCompanion(),
        customerPayload: activeCustomer.toJsonPayload(),
      );

      final container = buildContainer(db);
      addTearDown(container.dispose);

      final notifier = container.read(customersProvider.notifier);
      final Customer result = await notifier.updateCustomer(
        customerId: 'c1',
        phone: '01099999999',
      );

      expect(result.isActive, isTrue);

      final dbCustomer = await db.customersDao.getCustomerById('c1');
      expect(dbCustomer?.isActive, isTrue);
      expect(dbCustomer?.phone, '01099999999');
    });

    test('full disable → re-enable → disable cycle', () async {
      await db.customersDao.createCustomer(
        customer: activeCustomer.toCompanion(),
        customerPayload: activeCustomer.toJsonPayload(),
      );

      final container = buildContainer(db);
      addTearDown(container.dispose);

      final notifier = container.read(customersProvider.notifier);

      final Customer disabled = await notifier.updateCustomer(customerId: 'c1', isActive: false);
      expect(disabled.isActive, isFalse);

      final Customer reEnabled = await notifier.updateCustomer(customerId: 'c1', isActive: true);
      expect(reEnabled.isActive, isTrue);

      final Customer disabledAgain = await notifier.updateCustomer(customerId: 'c1', isActive: false);
      expect(disabledAgain.isActive, isFalse);

      final dbCustomer = await db.customersDao.getCustomerById('c1');
      expect(dbCustomer?.isActive, isFalse);
    });

    test('balance is preserved across disable/enable', () async {
      final richCustomer = activeCustomer.copyWith(balance: 1234.56);
      await db.customersDao.createCustomer(
        customer: richCustomer.toCompanion(),
        customerPayload: richCustomer.toJsonPayload(),
      );

      final container = buildContainer(db);
      addTearDown(container.dispose);

      final notifier = container.read(customersProvider.notifier);

      final Customer disabled = await notifier.updateCustomer(customerId: 'c1', isActive: false);
      expect(disabled.balance, 1234.56);

      final Customer reEnabled = await notifier.updateCustomer(customerId: 'c1', isActive: true);
      expect(reEnabled.balance, 1234.56);

      final dbCustomer = await db.customersDao.getCustomerById('c1');
      expect(dbCustomer?.balance, 1234.56);
    });
  });
}

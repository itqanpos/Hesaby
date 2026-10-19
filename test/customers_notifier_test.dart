// test/customers_notifier_test.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hesabi/features/companies/domain/entities/company.dart';
import 'package:hesabi/features/companies/presentation/providers/company_context_provider.dart';
import 'package:hesabi/features/companies/presentation/providers/company_context_state.dart';
import 'package:hesabi/features/sales/domain/entities/sale_entities.dart';
import 'package:hesabi/features/sales/domain/repositories/sales_repository.dart';
import 'package:hesabi/features/sales/presentation/providers/sales_providers.dart';

// ============================================================================
// Fake Customer Repository
// ============================================================================

class FakeCustomerRepository implements CustomerRepository {
  FakeCustomerRepository(this._initial);

  final List<Customer> _initial;

  /// عدد مرات استدعاء updateCustomer — للتحقق من حدوث التحديث.
  int updateCallCount = 0;

  /// آخر قيمة isActive تم إرسالها.
  bool? lastIsActive;

  @override
  Future<List<Customer>> listCustomers(String companyId, {bool includeInactive = false}) async {
    return _initial;
  }

  @override
  Future<Customer> updateCustomer({
    required String customerId,
    String? name,
    String? code,
    bool clearCode = false,
    String? phone,
    bool clearPhone = false,
    String? email,
    bool clearEmail = false,
    String? address,
    bool clearAddress = false,
    String? notes,
    bool clearNotes = false,
    bool? isActive,
  }) async {
    updateCallCount++;
    lastIsActive = isActive;

    final Customer old = _initial.firstWhere((c) => c.id == customerId);
    final Customer updated = old.copyWith(
      name: name,
      phone: phone,
      isActive: isActive,
    );

    // تحديث القائمة المحلية
    final int index = _initial.indexWhere((c) => c.id == customerId);
    _initial[index] = updated;

    return updated;
  }

  // ------------------------------------------------------------------------
  // Methods not used by these tests — throw UnimplementedError.
  // ------------------------------------------------------------------------
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        'FakeCustomerRepository.${invocation.memberName} is not implemented',
      );
}

// ============================================================================
// Helpers
// ============================================================================

/// يبني `ProviderContainer` مع تجاوزات آمنة (بدون الحاجة لكائنات حقيقية).
ProviderContainer buildContainer(FakeCustomerRepository repo) {
  // إنشاء شركة وهمية
  final fakeCompany = Company(
    id: 'co1',
    name: 'شركة وهمية',
    currency: 'EGP',
    timezone: 'Africa/Cairo',
    isActive: true,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  // إنشاء حالة سياق وهمية (سنحتاج للتأكد من الحقول المطلوبة في ملفك)
  // ملاحظة: إذا كان CompanyContextState يحتوي على حقول أخرى، أضفها هنا.
  final fakeContext = CompanyContextState(
    currentCompany: fakeCompany,
    branches: const [],
    currentBranch: null,
  );

  return ProviderContainer(
    overrides: <Override>[
      // نُجبر سياق الشركة على إرجاع الشركة الوهمية
      companyContextProvider.overrideWith((ref) => fakeContext),
      // نُغيّر customerRepositoryProvider ليعيد الـ fake.
      customerRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

// ============================================================================
// Tests
// ============================================================================

void main() {
  // ------------------------------------------------------------------------
  // Common test data
  // ------------------------------------------------------------------------
  final activeCustomer = Customer(
    id: 'c1',
    companyId: 'co1',
    name: 'أحمد محمد',
    balance: 500,
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  final secondCustomer = Customer(
    id: 'c2',
    companyId: 'co1',
    name: 'علي',
    balance: 0,
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  group('CustomersNotifier — updateCustomer(isActive)', () {
    // ----------------------------------------------------------------------
    // 1) تعطيل عميل
    // ----------------------------------------------------------------------
    test('disables a customer successfully', () async {
      final repo = FakeCustomerRepository(
        <Customer>[activeCustomer, secondCustomer],
      );

      final container = buildContainer(repo);
      addTearDown(container.dispose);

      final notifier = container.read(customersProvider.notifier);

      final Customer result = await notifier.updateCustomer(
        customerId: 'c1',
        isActive: false,
      );

      expect(result.isActive, isFalse);
      expect(repo.updateCallCount, 1);
      expect(repo.lastIsActive, isFalse);
    });

    // ----------------------------------------------------------------------
    // 2) إعادة تشغيل عميل
    // ----------------------------------------------------------------------
    test('re-enables a disabled customer successfully', () async {
      final disabledCustomer = activeCustomer.copyWith(isActive: false);
      final repo = FakeCustomerRepository(<Customer>[disabledCustomer]);

      final container = buildContainer(repo);
      addTearDown(container.dispose);

      final notifier = container.read(customersProvider.notifier);

      final Customer result = await notifier.updateCustomer(
        customerId: 'c1',
        isActive: true,
      );

      expect(result.isActive, isTrue);
      expect(repo.updateCallCount, 1);
      expect(repo.lastIsActive, isTrue);
    });

    // ----------------------------------------------------------------------
    // 3) تحديث بدون تغيير isActive (لا يتأثر)
    // ----------------------------------------------------------------------
    test('updating other fields does not alter isActive', () async {
      final repo = FakeCustomerRepository(<Customer>[activeCustomer]);

      final container = buildContainer(repo);
      addTearDown(container.dispose);

      final notifier = container.read(customersProvider.notifier);

      final Customer result = await notifier.updateCustomer(
        customerId: 'c1',
        phone: '01099999999',
        // isActive: لم يُمرر
      );

      expect(result.isActive, isTrue); // لم يتغير
      expect(repo.lastIsActive, isNull); // لم يُرسل
    });

    // ----------------------------------------------------------------------
    // 4) سيناريو كامل: تعطيل → إعادة تشغيل → تعطيل مرة أخرى
    // ----------------------------------------------------------------------
    test('full disable → re-enable → disable cycle', () async {
      final repo = FakeCustomerRepository(<Customer>[activeCustomer]);

      final container = buildContainer(repo);
      addTearDown(container.dispose);

      final notifier = container.read(customersProvider.notifier);

      // تعطيل
      final Customer disabled = await notifier.updateCustomer(
        customerId: 'c1',
        isActive: false,
      );
      expect(disabled.isActive, isFalse);
      expect(repo.updateCallCount, 1);

      // إعادة تشغيل
      final Customer reEnabled = await notifier.updateCustomer(
        customerId: 'c1',
        isActive: true,
      );
      expect(reEnabled.isActive, isTrue);
      expect(repo.updateCallCount, 2);

      // تعطيل ثالث
      final Customer disabledAgain = await notifier.updateCustomer(
        customerId: 'c1',
        isActive: false,
      );
      expect(disabledAgain.isActive, isFalse);
      expect(repo.updateCallCount, 3);
    });

    // ----------------------------------------------------------------------
    // 5) الرصيد لا يتأثر بالتعطيل
    // ----------------------------------------------------------------------
    test('balance is preserved across disable/enable', () async {
      final richCustomer = activeCustomer.copyWith(balance: 1234.56);
      final repo = FakeCustomerRepository(<Customer>[richCustomer]);

      final container = buildContainer(repo);
      addTearDown(container.dispose);

      final notifier = container.read(customersProvider.notifier);

      final Customer disabled = await notifier.updateCustomer(
        customerId: 'c1',
        isActive: false,
      );
      expect(disabled.balance, 1234.56);

      final Customer reEnabled = await notifier.updateCustomer(
        customerId: 'c1',
        isActive: true,
      );
      expect(reEnabled.balance, 1234.56);
    });
  });
}

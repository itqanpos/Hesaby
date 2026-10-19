// test/customers_notifier_test.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hesabi/features/companies/domain/entities/branch.dart'; // ⬅️ جديد
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
  int updateCallCount = 0;
  bool? lastIsActive;

  @override
  Future<List<Customer>> listCustomers(
    String companyId, {
    bool includeInactive = false,
  }) async {
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

    final int index = _initial.indexWhere((c) => c.id == customerId);
    _initial[index] = updated;
    return updated;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        'FakeCustomerRepository.${invocation.memberName} is not implemented',
      );
}

// ============================================================================
// Fake Company Context Notifier
// ============================================================================

class _FakeCompanyContextNotifier extends CompanyContextNotifier {
  _FakeCompanyContextNotifier();

  @override
  CompanyContextState build() {
    return const CompanyContextState(
      currentCompany: null,
      branches: <Branch>[], // ⬅️ تم التصحيح
      currentBranch: null,
    );
  }
}

// ============================================================================
// Helpers
// ============================================================================

ProviderContainer buildContainer(FakeCustomerRepository repo) {
  return ProviderContainer(
    overrides: <Override>[
      companyContextProvider.overrideWith(_FakeCompanyContextNotifier.new),
      customerRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

// ============================================================================
// Tests
// ============================================================================

void main() {
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

    test('updating other fields does not alter isActive', () async {
      final repo = FakeCustomerRepository(<Customer>[activeCustomer]);

      final container = buildContainer(repo);
      addTearDown(container.dispose);

      final notifier = container.read(customersProvider.notifier);
      final Customer result = await notifier.updateCustomer(
        customerId: 'c1',
        phone: '01099999999',
      );

      expect(result.isActive, isTrue);
      expect(repo.lastIsActive, isNull);
    });

    test('full disable → re-enable → disable cycle', () async {
      final repo = FakeCustomerRepository(<Customer>[activeCustomer]);

      final container = buildContainer(repo);
      addTearDown(container.dispose);

      final notifier = container.read(customersProvider.notifier);

      final Customer disabled = await notifier.updateCustomer(
        customerId: 'c1',
        isActive: false,
      );
      expect(disabled.isActive, isFalse);
      expect(repo.updateCallCount, 1);

      final Customer reEnabled = await notifier.updateCustomer(
        customerId: 'c1',
        isActive: true,
      );
      expect(reEnabled.isActive, isTrue);
      expect(repo.updateCallCount, 2);

      final Customer disabledAgain = await notifier.updateCustomer(
        customerId: 'c1',
        isActive: false,
      );
      expect(disabledAgain.isActive, isFalse);
      expect(repo.updateCallCount, 3);
    });

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

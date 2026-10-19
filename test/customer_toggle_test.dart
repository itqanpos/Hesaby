// test/customer_toggle_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/sales/domain/entities/sale_entities.dart';

void main() {
  // ==========================================================================
  // 1) اختبار الكيان (Customer Entity)
  // ==========================================================================
  group('Customer Entity - isActive toggle', () {
    final baseCustomer = Customer(
      id: 'c1',
      companyId: 'co1',
      name: 'أحمد محمد',
      balance: 500,
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      phone: '01012345678',
      email: 'ahmed@example.com',
    );

    test('default state is active', () {
      expect(baseCustomer.isActive, isTrue);
    });

    test('copyWith can disable a customer', () {
      final disabled = baseCustomer.copyWith(isActive: false);

      expect(disabled.isActive, isFalse);
      expect(disabled.id, baseCustomer.id); // id لم يتغير
      expect(disabled.name, baseCustomer.name); // name لم يتغير
      expect(disabled.balance, baseCustomer.balance); // balance لم يتغير
    });

    test('copyWith can re-enable a disabled customer', () {
      final disabled = baseCustomer.copyWith(isActive: false);
      final reEnabled = disabled.copyWith(isActive: true);

      expect(disabled.isActive, isFalse);
      expect(reEnabled.isActive, isTrue);
    });

    test('copyWith without isActive keeps current value', () {
      final updated = baseCustomer.copyWith(phone: '01099999999');

      expect(updated.isActive, isTrue); // لم يتغير
      expect(updated.phone, '01099999999');
    });

    test('Equatable detects isActive difference', () {
      final disabled = baseCustomer.copyWith(isActive: false);

      expect(baseCustomer == disabled, isFalse);
      expect(baseCustomer == baseCustomer.copyWith(), isTrue);
    });
  });

  // ==========================================================================
  // 2) اختبار منطق الفلترة (Filtering active customers)
  // ==========================================================================
  group('Active customers filtering', () {
    // نبني قائمة عملاء مختلطة
    final customers = <Customer>[
      Customer(
        id: 'c1',
        companyId: 'co1',
        name: 'أحمد',
        balance: 100,
        isActive: true,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
      Customer(
        id: 'c2',
        companyId: 'co1',
        name: 'محمد (معطل)',
        balance: 200,
        isActive: false, // ← معطل
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
      Customer(
        id: 'c3',
        companyId: 'co1',
        name: 'علي',
        balance: 0,
        isActive: true,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ];

    test('filters out disabled customers', () {
      final activeOnly = customers.where((c) => c.isActive).toList();

      expect(activeOnly.length, 2);
      expect(activeOnly.map((c) => c.id), containsAll(['c1', 'c3']));
      expect(activeOnly.map((c) => c.id), isNot(contains('c2')));
    });

    test('finds only disabled customers', () {
      final disabledOnly = customers.where((c) => !c.isActive).toList();

      expect(disabledOnly.length, 1);
      expect(disabledOnly.first.id, 'c2');
    });

    test('when all customers are disabled, active list is empty', () {
      final allDisabled = customers
          .map((c) => c.copyWith(isActive: false))
          .toList();
      final activeOnly = allDisabled.where((c) => c.isActive).toList();

      expect(activeOnly, isEmpty);
    });
  });

  // ==========================================================================
  // 3) اختبار سيناريو POS (العميل المعطل لا يظهر للاختيار)
  // ==========================================================================
  group('POS: disabled customer cannot be attached', () {
    test('cannot attach a disabled customer (guard simulation)', () {
      final disabledCustomer = Customer(
        id: 'c2',
        companyId: 'co1',
        name: 'محمد',
        balance: 200,
        isActive: false,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      // نحاكي منطق الواجهة: يجب ألا نسمح بإرفاق عميل معطل
      bool canAttach(Customer c) => c.isActive;

      expect(canAttach(disabledCustomer), isFalse);
    });

    test('can attach an active customer', () {
      final activeCustomer = Customer(
        id: 'c1',
        companyId: 'co1',
        name: 'أحمد',
        balance: 100,
        isActive: true,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      bool canAttach(Customer c) => c.isActive;

      expect(canAttach(activeCustomer), isTrue);
    });
  });

  // ==========================================================================
  // 4) اختبار السيناريو الكامل (تعطيل → تحقق → إعادة تشغيل → تحقق)
  // ==========================================================================
  group('Full disable/re-enable scenario', () {
    test('disable → verify → re-enable → verify', () {
      // 1. البداية: عميل نشط
      Customer customer = Customer(
        id: 'c1',
        companyId: 'co1',
        name: 'أحمد',
        balance: 500,
        isActive: true,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      // 2. تعطيل
      customer = customer.copyWith(isActive: false);
      expect(customer.isActive, isFalse, reason: 'بعد التعطيل');

      // 3. إعادة تشغيل
      customer = customer.copyWith(isActive: true);
      expect(customer.isActive, isTrue, reason: 'بعد إعادة التشغيل');

      // 4. البيانات الأخرى لم تتأثر
      expect(customer.id, 'c1');
      expect(customer.name, 'أحمد');
      expect(customer.balance, 500);
    });
  });

  // ==========================================================================
  // 5) اختبار الرصيد لا يتأثر بالتعطيل (مهم جداً للمحاسبة)
  // ==========================================================================
  group('Balance is not affected by disable/enable', () {
    test('balance stays the same across disable and re-enable', () {
      final original = Customer(
        id: 'c1',
        companyId: 'co1',
        name: 'أحمد',
        balance: 750.50,
        isActive: true,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      final disabled = original.copyWith(isActive: false);
      expect(disabled.balance, 750.50);

      final reEnabled = disabled.copyWith(isActive: true);
      expect(reEnabled.balance, 750.50);
    });

    test('negative balance (credit) is preserved', () {
      final creditCustomer = Customer(
        id: 'c1',
        companyId: 'co1',
        name: 'أحمد',
        balance: -150.00, // له عندنا
        isActive: true,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      final disabled = creditCustomer.copyWith(isActive: false);

      expect(disabled.balance, -150.00);
      expect(disabled.balance < 0, isTrue);
    });
  });
}

// test/features/suppliers/supplier_repository_contract_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/suppliers/domain/entities/supplier.dart';
import 'package:hesabi/features/suppliers/domain/repositories/supplier_repository.dart';

/// A minimal in-memory implementation of [SupplierRepository].
///
/// Its sole purpose is to prove, at compile time, that the interface can be
/// implemented outside the Supabase data layer. It is intentionally not a
/// behavioural fake: no test in this file exercises its methods. The
/// methods are kept minimal so that if the interface gains a member, this
/// file stops compiling and forces a deliberate update.
class _FakeSupplierRepository implements SupplierRepository {
  @override
  Future<List<Supplier>> listSuppliers(
    String companyId, {
    bool includeInactive = false,
  }) async =>
      const <Supplier>[];

  @override
  Future<Supplier> getSupplier(String supplierId) async =>
      throw UnimplementedError();

  @override
  Future<Supplier> createSupplier({
    required String companyId,
    required String name,
    String? code,
    String? phone,
    String? email,
    String? address,
    String? notes,
  }) async =>
      throw UnimplementedError();

  @override
  Future<Supplier> updateSupplier({
    required String supplierId,
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
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteSupplier(String supplierId) async =>
      throw UnimplementedError();
}

void main() {
  // ---------------------------------------------------------------------------
  // SupplierFailureType completeness
  // ---------------------------------------------------------------------------

  group('SupplierFailureType', () {
    test('declares the documented failure categories', () {
      // The list is intentionally explicit and hard-coded. Adding a new
      // value to the enum without also updating the presentation-layer
      // switch would leave a message unmapped; this test is the safety net
      // that forces a conscious decision at that point.
      const List<SupplierFailureType> expected = <SupplierFailureType>[
        SupplierFailureType.network,
        SupplierFailureType.unauthorized,
        SupplierFailureType.notFound,
        SupplierFailureType.nameConflict,
        SupplierFailureType.codeConflict,
        SupplierFailureType.phoneConflict,
        SupplierFailureType.inUse,
        SupplierFailureType.invalidResponse,
        SupplierFailureType.unknown,
      ];

      expect(SupplierFailureType.values.length, expected.length);
      for (final SupplierFailureType type in expected) {
        expect(
          SupplierFailureType.values,
          contains(type),
          reason: 'Missing failure type: ${type.name}',
        );
      }
    });

    test('each value has a unique name', () {
      final Set<String> names = <String>{
        for (final SupplierFailureType type in SupplierFailureType.values)
          type.name,
      };

      expect(names.length, SupplierFailureType.values.length);
    });
  });

  // ---------------------------------------------------------------------------
  // SupplierException equality
  // ---------------------------------------------------------------------------

  group('SupplierException', () {
    test('two instances with the same type are equal', () {
      const SupplierException a = SupplierException(
        type: SupplierFailureType.nameConflict,
      );
      const SupplierException b = SupplierException(
        type: SupplierFailureType.nameConflict,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('two instances with different types are not equal', () {
      const SupplierException a = SupplierException(
        type: SupplierFailureType.nameConflict,
      );
      const SupplierException b = SupplierException(
        type: SupplierFailureType.codeConflict,
      );

      expect(a, isNot(equals(b)));
    });

    test('cause and stackTrace do not affect equality', () {
      final StackTrace stackTrace = StackTrace.current;
      final SupplierException a = SupplierException(
        type: SupplierFailureType.unknown,
        cause: 'x',
        stackTrace: stackTrace,
      );
      final SupplierException b = SupplierException(
        type: SupplierFailureType.unknown,
        cause: 'y',
        stackTrace: stackTrace,
      );

      expect(a, equals(b));
    });

    test('implements Exception', () {
      const SupplierException exception = SupplierException(
        type: SupplierFailureType.network,
      );

      expect(exception, isA<Exception>());
    });

    test('toString exposes only the failure type', () {
      const SupplierException exception = SupplierException(
        type: SupplierFailureType.phoneConflict,
        cause: 'raw backend detail',
      );

      final String text = exception.toString();

      expect(text, contains('phoneConflict'));
      expect(text, isNot(contains('raw backend detail')));
    });
  });

  // ---------------------------------------------------------------------------
  // Interface implementability
  // ---------------------------------------------------------------------------

  group('SupplierRepository interface', () {
    test('can be implemented outside the Supabase data layer', () {
      // The mere assignment below is the test: if the interface gains a
      // member, _FakeSupplierRepository stops compiling and this file
      // forces a deliberate update.
      final SupplierRepository repository = _FakeSupplierRepository();

      expect(repository, isA<SupplierRepository>());
    });

    test('listSuppliers returns an empty list by default', () async {
      final SupplierRepository repository = _FakeSupplierRepository();

      final List<Supplier> suppliers =
          await repository.listSuppliers('company-1');

      expect(suppliers, isEmpty);
    });
  });
}

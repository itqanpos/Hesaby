// test/features/products/product_validation_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/features/products/data/models/product_model.dart';
import 'package:hesabi/features/products/data/models/product_unit_model.dart';
import 'package:hesabi/features/products/domain/entities/product.dart';
import 'package:hesabi/features/products/domain/entities/product_unit.dart';

void main() {
  // ---------------------------------------------------------------------------
  // ProductModel.fromMap
  // ---------------------------------------------------------------------------

  group('ProductModel.fromMap', () {
    test('parses a complete valid row', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'prod-1',
        'company_id': 'company-1',
        'category_id': 'cat-1',
        'default_unit_id': 'unit-1',
        'name': 'بيبسي 1 لتر',
        'sku': 'PEP-1L',
        'barcode': '6221031234567',
        'description': 'مشروب غازي',
        'cost_price': 8.5,
        'selling_price': 12.0,
        'min_selling_price': 10.0,
        'tax_rate': 14.0,
        'is_active': true,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:30:00.000Z',
      };

      final ProductModel model = ProductModel.fromMap(row);

      expect(model.id, 'prod-1');
      expect(model.companyId, 'company-1');
      expect(model.categoryId, 'cat-1');
      expect(model.defaultUnitId, 'unit-1');
      expect(model.name, 'بيبسي 1 لتر');
      expect(model.sku, 'PEP-1L');
      expect(model.barcode, '6221031234567');
      expect(model.description, 'مشروب غازي');
      expect(model.costPrice, 8.5);
      expect(model.sellingPrice, 12.0);
      expect(model.minSellingPrice, 10.0);
      expect(model.taxRate, 14.0);
      expect(model.isActive, isTrue);
      expect(model.createdAt.isUtc, isTrue);
    });

    test('parses prices delivered as numeric strings (PostgREST)', () {
      // PostgREST returns `numeric` columns as strings to preserve precision.
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'prod-2',
        'company_id': 'company-1',
        'default_unit_id': 'unit-1',
        'name': 'منتج',
        'cost_price': '10.5000',
        'selling_price': '15.7500',
        'min_selling_price': '12.0000',
        'tax_rate': '14.00',
        'is_active': true,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      final ProductModel model = ProductModel.fromMap(row);

      expect(model.costPrice, 10.5);
      expect(model.sellingPrice, 15.75);
      expect(model.minSellingPrice, 12.0);
      expect(model.taxRate, 14.0);
    });

    test('defaults cost and selling prices to 0 when absent', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'prod-3',
        'company_id': 'company-1',
        'default_unit_id': 'unit-1',
        'name': 'منتج',
        'is_active': true,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      final ProductModel model = ProductModel.fromMap(row);

      expect(model.costPrice, 0);
      expect(model.sellingPrice, 0);
      expect(model.minSellingPrice, isNull);
      expect(model.taxRate, isNull);
    });

    test('treats empty optional strings as null', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'prod-4',
        'company_id': 'company-1',
        'default_unit_id': 'unit-1',
        'name': 'منتج',
        'sku': '   ',
        'barcode': '',
        'description': '',
        'cost_price': 0,
        'selling_price': 0,
        'is_active': true,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      final ProductModel model = ProductModel.fromMap(row);

      expect(model.sku, isNull);
      expect(model.barcode, isNull);
      expect(model.description, isNull);
      expect(model.categoryId, isNull);
    });

    test('defaults isActive to true when absent', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'prod-5',
        'company_id': 'company-1',
        'default_unit_id': 'unit-1',
        'name': 'منتج',
        'cost_price': 0,
        'selling_price': 0,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      final ProductModel model = ProductModel.fromMap(row);

      expect(model.isActive, isTrue);
    });

    test('throws FormatException when a required string is missing', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': '',
        'company_id': 'company-1',
        'default_unit_id': 'unit-1',
        'name': 'منتج',
        'cost_price': 0,
        'selling_price': 0,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      expect(
        () => ProductModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when a timestamp is invalid', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'prod-6',
        'company_id': 'company-1',
        'default_unit_id': 'unit-1',
        'name': 'منتج',
        'cost_price': 0,
        'selling_price': 0,
        'created_at': 'not-a-date',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      expect(
        () => ProductModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // ProductModel.toEntity
  // ---------------------------------------------------------------------------

  group('ProductModel.toEntity', () {
    test('produces a Product with identical field values', () {
      final ProductModel model = ProductModel.fromMap(<String, dynamic>{
        'id': 'prod-1',
        'company_id': 'company-1',
        'category_id': 'cat-1',
        'default_unit_id': 'unit-1',
        'name': 'بيبسي',
        'sku': 'PEP',
        'barcode': '622',
        'description': 'وصف',
        'cost_price': 8.5,
        'selling_price': 12.0,
        'min_selling_price': 10.0,
        'tax_rate': 14.0,
        'is_active': true,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      });

      final Product entity = model.toEntity();

      expect(entity.id, model.id);
      expect(entity.companyId, model.companyId);
      expect(entity.categoryId, model.categoryId);
      expect(entity.defaultUnitId, model.defaultUnitId);
      expect(entity.name, model.name);
      expect(entity.sku, model.sku);
      expect(entity.barcode, model.barcode);
      expect(entity.description, model.description);
      expect(entity.costPrice, model.costPrice);
      expect(entity.sellingPrice, model.sellingPrice);
      expect(entity.minSellingPrice, model.minSellingPrice);
      expect(entity.taxRate, model.taxRate);
      expect(entity.isActive, model.isActive);
      expect(entity.createdAt, model.createdAt);
      expect(entity.updatedAt, model.updatedAt);
    });
  });

  // ---------------------------------------------------------------------------
  // Product getters
  // ---------------------------------------------------------------------------

  group('Product getters', () {
    final DateTime timestamp = DateTime.utc(2026, 10, 2);

    test('hasCategory is true when categoryId is non-null', () {
      final Product withCategory = Product(
        id: 'p',
        companyId: 'c',
        categoryId: 'cat',
        defaultUnitId: 'u',
        name: 'n',
        costPrice: 0,
        sellingPrice: 0,
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Product withoutCategory = Product(
        id: 'p',
        companyId: 'c',
        defaultUnitId: 'u',
        name: 'n',
        costPrice: 0,
        sellingPrice: 0,
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(withCategory.hasCategory, isTrue);
      expect(withoutCategory.hasCategory, isFalse);
    });

    test('hasSku / hasBarcode / hasDescription treat empty strings as absent',
        () {
      final Product product = Product(
        id: 'p',
        companyId: 'c',
        defaultUnitId: 'u',
        name: 'n',
        sku: '',
        barcode: '   ',
        description: '',
        costPrice: 0,
        sellingPrice: 0,
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(product.hasSku, isFalse);
      expect(product.hasBarcode, isFalse);
      expect(product.hasDescription, isFalse);
    });

    test('hasSku / hasBarcode / hasDescription treat non-empty strings as present',
        () {
      final Product product = Product(
        id: 'p',
        companyId: 'c',
        defaultUnitId: 'u',
        name: 'n',
        sku: 'SKU-1',
        barcode: '12345',
        description: 'desc',
        costPrice: 0,
        sellingPrice: 0,
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(product.hasSku, isTrue);
      expect(product.hasBarcode, isTrue);
      expect(product.hasDescription, isTrue);
    });

    test('hasMinSellingPrice / hasTaxRate reflect null-ness', () {
      final Product withExtras = Product(
        id: 'p',
        companyId: 'c',
        defaultUnitId: 'u',
        name: 'n',
        costPrice: 0,
        sellingPrice: 0,
        minSellingPrice: 5,
        taxRate: 14,
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Product withoutExtras = Product(
        id: 'p',
        companyId: 'c',
        defaultUnitId: 'u',
        name: 'n',
        costPrice: 0,
        sellingPrice: 0,
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(withExtras.hasMinSellingPrice, isTrue);
      expect(withExtras.hasTaxRate, isTrue);
      expect(withoutExtras.hasMinSellingPrice, isFalse);
      expect(withoutExtras.hasTaxRate, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // ProductUnitModel.fromMap
  // ---------------------------------------------------------------------------

  group('ProductUnitModel.fromMap', () {
    test('parses conversion_factor as a number', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pu-1',
        'company_id': 'company-1',
        'product_id': 'prod-1',
        'unit_id': 'unit-2',
        'conversion_factor': 24,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      final ProductUnitModel model = ProductUnitModel.fromMap(row);

      expect(model.conversionFactor, 24.0);
    });

    test('parses conversion_factor delivered as a numeric string', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pu-2',
        'company_id': 'company-1',
        'product_id': 'prod-1',
        'unit_id': 'unit-2',
        'conversion_factor': '12.500000',
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      final ProductUnitModel model = ProductUnitModel.fromMap(row);

      expect(model.conversionFactor, 12.5);
    });

    test('parses a fractional conversion_factor', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pu-3',
        'company_id': 'company-1',
        'product_id': 'prod-1',
        'unit_id': 'unit-2',
        'conversion_factor': '0.333333',
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      final ProductUnitModel model = ProductUnitModel.fromMap(row);

      expect(model.conversionFactor, closeTo(0.333333, 0.000001));
    });

    test('throws FormatException when conversion_factor is missing', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pu-4',
        'company_id': 'company-1',
        'product_id': 'prod-1',
        'unit_id': 'unit-2',
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      expect(
        () => ProductUnitModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when conversion_factor is not numeric', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pu-5',
        'company_id': 'company-1',
        'product_id': 'prod-1',
        'unit_id': 'unit-2',
        'conversion_factor': 'abc',
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      expect(
        () => ProductUnitModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when a required id is empty', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'pu-6',
        'company_id': 'company-1',
        'product_id': '',
        'unit_id': 'unit-2',
        'conversion_factor': 1,
        'created_at': '2026-10-02T12:00:00.000Z',
        'updated_at': '2026-10-02T12:00:00.000Z',
      };

      expect(
        () => ProductUnitModel.fromMap(row),
        throwsA(isA<FormatException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // ProductUnit.isMeaningfulConversion
  // ---------------------------------------------------------------------------

  group('ProductUnit.isMeaningfulConversion', () {
    final DateTime timestamp = DateTime.utc(2026, 10, 2);

    test('is true for a positive factor', () {
      final ProductUnit productUnit = ProductUnit(
        id: 'pu-1',
        companyId: 'c',
        productId: 'p',
        unitId: 'u',
        conversionFactor: 24,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(productUnit.isMeaningfulConversion, isTrue);
    });

    test('is false for a zero factor', () {
      final ProductUnit productUnit = ProductUnit(
        id: 'pu-1',
        companyId: 'c',
        productId: 'p',
        unitId: 'u',
        conversionFactor: 0,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(productUnit.isMeaningfulConversion, isFalse);
    });

    test('is false for a negative factor', () {
      final ProductUnit productUnit = ProductUnit(
        id: 'pu-1',
        companyId: 'c',
        productId: 'p',
        unitId: 'u',
        conversionFactor: -5,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(productUnit.isMeaningfulConversion, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Equatable semantics
  // ---------------------------------------------------------------------------

  group('Product equality', () {
    final DateTime timestamp = DateTime.utc(2026, 10, 2);

    test('two entities with the same fields are equal', () {
      final Product a = Product(
        id: 'p',
        companyId: 'c',
        defaultUnitId: 'u',
        name: 'n',
        costPrice: 10,
        sellingPrice: 20,
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Product b = Product(
        id: 'p',
        companyId: 'c',
        defaultUnitId: 'u',
        name: 'n',
        costPrice: 10,
        sellingPrice: 20,
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('price difference is significant', () {
      final Product a = Product(
        id: 'p',
        companyId: 'c',
        defaultUnitId: 'u',
        name: 'n',
        costPrice: 10,
        sellingPrice: 20,
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final Product b = Product(
        id: 'p',
        companyId: 'c',
        defaultUnitId: 'u',
        name: 'n',
        costPrice: 10,
        sellingPrice: 21,
        isActive: true,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(a, isNot(equals(b)));
    });
  });

  group('ProductUnit equality', () {
    final DateTime timestamp = DateTime.utc(2026, 10, 2);

    test('same fields are equal', () {
      final ProductUnit a = ProductUnit(
        id: 'pu',
        companyId: 'c',
        productId: 'p',
        unitId: 'u',
        conversionFactor: 24,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final ProductUnit b = ProductUnit(
        id: 'pu',
        companyId: 'c',
        productId: 'p',
        unitId: 'u',
        conversionFactor: 24,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(a, equals(b));
    });

    test('conversion factor difference is significant', () {
      final ProductUnit a = ProductUnit(
        id: 'pu',
        companyId: 'c',
        productId: 'p',
        unitId: 'u',
        conversionFactor: 24,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final ProductUnit b = ProductUnit(
        id: 'pu',
        companyId: 'c',
        productId: 'p',
        unitId: 'u',
        conversionFactor: 12,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(a, isNot(equals(b)));
    });
  });
}

// lib/features/suppliers/presentation/providers/supplier_statement_providers.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../data/repositories/supplier_statement_repository_impl.dart';
import '../../domain/entities/supplier_statement.dart';
import '../../domain/repositories/supplier_statement_repository.dart';

/// The statement repository.
final Provider<SupplierStatementRepository>
    supplierStatementRepositoryProvider =
    Provider<SupplierStatementRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return SupplierStatementRepositoryImpl(client);
});

/// Arguments for [supplierStatementProvider].
@immutable
class SupplierStatementArgs extends Equatable {
  const SupplierStatementArgs({
    required this.supplierId,
    this.fromDate,
    this.toDate,
  });

  final String supplierId;
  final DateTime? fromDate;
  final DateTime? toDate;

  @override
  List<Object?> get props => <Object?>[supplierId, fromDate, toDate];
}

/// Provides the statement for a given supplier + period.
final supplierStatementProvider =
    FutureProvider.family<SupplierStatement, SupplierStatementArgs>(
        (ref, SupplierStatementArgs args) async {
  return ref
      .read(supplierStatementRepositoryProvider)
      .buildStatement(
        supplierId: args.supplierId,
        fromDate: args.fromDate,
        toDate: args.toDate,
      );
});

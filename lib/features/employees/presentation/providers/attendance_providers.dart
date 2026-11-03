// lib/features/employees/presentation/providers/attendance_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../data/datasources/attendance_remote_datasource.dart';
import '../../data/repositories/attendance_repository_impl.dart';
import '../../domain/entities/attendance_record.dart';
import '../../domain/repositories/attendance_repository.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

final Provider<AttendanceRepository> attendanceRepositoryProvider =
    Provider<AttendanceRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return AttendanceRepositoryImpl(AttendanceRemoteDataSource(client));
});

// ---------------------------------------------------------------------------
// Selected Date
// ---------------------------------------------------------------------------

/// مزود يحمل التاريخ المحدد لعرض الحضور (يبدأ بتاريخ اليوم).
class AttendanceDateNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final DateTime now = DateTime.now();
    // نقوم بإرجاع التاريخ فقط بدون ساعات (منتصف الليل) لضمان الدقة
    return DateTime(now.year, now.month, now.day);
  }

  void setDate(DateTime date) {
    state = DateTime(date.year, date.month, date.day);
  }
}

final NotifierProvider<AttendanceDateNotifier, DateTime>
    attendanceDateProvider =
    NotifierProvider<AttendanceDateNotifier, DateTime>(
  AttendanceDateNotifier.new,
);

// ---------------------------------------------------------------------------
// Attendance List
// ---------------------------------------------------------------------------

class AttendanceNotifier
    extends AsyncNotifier<List<AttendanceRecord>> {
  @override
  Future<List<AttendanceRecord>> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    final DateTime selectedDate = ref.watch(attendanceDateProvider);

    if (companyId == null) return const <AttendanceRecord>[];

    return ref.read(attendanceRepositoryProvider).listAttendance(
          companyId: companyId,
          date: selectedDate,
        );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<AttendanceRecord> upsert({
    required String employeeId,
    required AttendanceStatus status,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    String? notes,
  }) async {
    final String companyId = _requireCompanyId();
    final DateTime selectedDate = ref.read(attendanceDateProvider);

    final AttendanceRecord record =
        await ref.read(attendanceRepositoryProvider).upsertAttendance(
              companyId: companyId,
              employeeId: employeeId,
              date: selectedDate,
              status: status,
              checkInTime: checkInTime,
              checkOutTime: checkOutTime,
              notes: notes,
            );

    await refresh();
    return record;
  }

  Future<void> delete(String attendanceId) async {
    await ref.read(attendanceRepositoryProvider).deleteAttendance(attendanceId);
    await refresh();
  }

  String _requireCompanyId() {
    final CompanyContextState ctx = ref.read(companyContextProvider);
    final String? id = ctx.currentCompany?.id;
    if (id == null) {
      throw const AttendanceException(
        type: AttendanceFailureType.unauthorized,
        cause: 'No company selected.',
      );
    }
    return id;
  }
}

final AsyncNotifierProvider<AttendanceNotifier, List<AttendanceRecord>>
    attendanceProvider =
    AsyncNotifierProvider<AttendanceNotifier, List<AttendanceRecord>>(
  AttendanceNotifier.new,
);

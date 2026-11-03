// lib/features/employees/domain/repositories/attendance_repository.dart

import 'package:equatable/equatable.dart';
import '../entities/attendance_record.dart';

/// أنواع الأخطاء المتوقعة في نظام الحضور
enum AttendanceFailureType {
  network,
  unauthorized,
  notFound,
  invalidInput,
  invalidResponse,
  unknown,
}

/// استثناء مخصص للحضور (لتغليف أخطاء الشبكة وقاعدة البيانات)
class AttendanceException extends Equatable implements Exception {
  const AttendanceException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  final AttendanceFailureType type;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'AttendanceException(${type.name})';
}

/// واجهة (عقد) مستودع الحضور.
abstract class AttendanceRepository {
  /// جلب سجلات الحضور لشركة معينة في تاريخ محدد.
  Future<List<AttendanceRecord>> listAttendance({
    required String companyId,
    required DateTime date,
  });

  /// تسجيل أو تعديل حضور موظف في يوم معين.
  /// (يستخدم Upsert لأن قاعدة البيانات تمنع تكرار الموظف في نفس اليوم).
  Future<AttendanceRecord> upsertAttendance({
    required String companyId,
    required String employeeId,
    required DateTime date,
    required AttendanceStatus status,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    String? notes,
  });

  /// حذف سجل حضور (في حال تم التسجيل بالخطأ).
  Future<void> deleteAttendance(String attendanceId);
}

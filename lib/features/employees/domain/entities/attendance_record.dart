// lib/features/employees/domain/entities/attendance_record.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// حالات الحضور الممكنة
enum AttendanceStatus {
  present('present', 'حاضر'),
  absent('absent', 'غائب'),
  late('late', 'متأخر'),
  leave('leave', 'إجازة');

  const AttendanceStatus(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static AttendanceStatus fromDb(String? value) {
    return AttendanceStatus.values.firstWhere(
      (e) => e.dbValue == value,
      orElse: () => AttendanceStatus.present,
    );
  }
}

@immutable
class AttendanceRecord extends Equatable {
  const AttendanceRecord({
    required this.id,
    required this.companyId,
    required this.employeeId,
    required this.date,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.employeeName, // لجلب اسم الموظف للعرض في الواجهة
    this.checkInTime,
    this.checkOutTime,
    this.notes,
  });

  final String id;
  final String companyId;
  final String employeeId;
  final DateTime date; // التاريخ فقط (بدون وقت)
  final AttendanceStatus status;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  /// اسم الموظف (يُجلب من جدول الموظفين عند القراءة)
  final String? employeeName;

  AttendanceRecord copyWith({
    AttendanceStatus? status,
    DateTime? checkInTime,
    bool clearCheckIn = false,
    DateTime? checkOutTime,
    bool clearCheckOut = false,
    String? notes,
    bool clearNotes = false,
    DateTime? updatedAt,
  }) {
    return AttendanceRecord(
      id: id,
      companyId: companyId,
      employeeId: employeeId,
      date: date,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      employeeName: employeeName,
      checkInTime: clearCheckIn ? null : (checkInTime ?? this.checkInTime),
      checkOutTime: clearCheckOut ? null : (checkOutTime ?? this.checkOutTime),
      notes: clearNotes ? null : (notes ?? this.notes),
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        employeeId,
        date,
        status,
        checkInTime,
        checkOutTime,
        notes,
        createdAt,
        updatedAt,
        employeeName,
      ];

  @override
  String toString() =>
      'AttendanceRecord(id: $id, employeeId: $employeeId, date: $date, status: ${status.name})';
}

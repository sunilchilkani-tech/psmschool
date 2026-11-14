import 'dart:convert';
import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

class SchoolExportBundle {
  const SchoolExportBundle({required this.bytes, required this.fileName});
  final Uint8List bytes;
  final String fileName;
}

/// Creates a multi-sheet workbook. Admin exports are school-scoped; teacher exports only
/// include assigned-class data. Sensitive student_private_details are opt-in and admin-only.
class SchoolExportService {
  SchoolExportService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  Future<SchoolExportBundle> exportForCurrentUser({bool includePrivateDetails = false}) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Please sign in again before exporting.');
    final teacherRow = await _client.from('school_teachers')
        .select('id,school_ref,teacher_name,role,allowed_classes,is_active')
        .eq('auth_user_id', user.id).maybeSingle();
    if (teacherRow == null || teacherRow['is_active'] != true) {
      throw StateError('The signed-in teacher is not active.');
    }
    final teacher = Map<String, dynamic>.from(teacherRow);
    final schoolRef = '${teacher['school_ref']}';
    final role = '${teacher['role']}'.toLowerCase();
    final isAdmin = const {'admin', 'developer'}.contains(role);
    final schoolRow = await _client.from('schools').select()
        .eq('id', schoolRef).maybeSingle();
    final classRows = await _client.from('school_classes').select()
        .eq('school_ref', schoolRef).order('sort_order');
    final allClasses = classRows.map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r)).toList();
    final allowed = (teacher['allowed_classes'] as List? ?? const []).map((v) => '$v').toSet();
    final classes = isAdmin ? allClasses : allClasses.where((c) =>
      allowed.contains('${c['id']}') || allowed.contains('${c['class_key']}') ||
      allowed.contains('${c['label']}') || allowed.contains('${c['sheet_name']}')
    ).toList();
    if (!isAdmin && classes.isEmpty) throw StateError('No assigned classes are available for export.');
    final classIds = classes.map((c) => '${c['id']}').toList();

    final workbook = Excel.createExcel();
    workbook.rename('Sheet1', 'School');
    _append(workbook['School'], [
      if (schoolRow != null) Map<String, dynamic>.from(schoolRow),
      {'exported_by': teacher['teacher_name'], 'role': role, 'exported_at': DateTime.now().toIso8601String()},
    ]);
    _append(workbook['Classes'], classes);
    _append(workbook['Students'], await _readClassTable('students', schoolRef, classIds));
    _append(workbook['AttendanceDays'], await _readClassTable('attendance_days', schoolRef, classIds));
    _append(workbook['StudentAttendance'], await _readClassTable('student_attendance', schoolRef, classIds));
    _append(workbook['Subjects'], await _readClassTable('class_subjects', schoolRef, classIds));
    _append(workbook['ResultSettings'], await _readClassTable('class_result_settings', schoolRef, classIds));
    _append(workbook['ResultProfiles'], await _readClassTable('student_result_profiles', schoolRef, classIds));
    _append(workbook['SubjectMarks'], await _readClassTable('student_subject_marks', schoolRef, classIds));
    _append(workbook['ReportSettings'], await _readClassTable('school_report_settings', schoolRef, classIds));

    if (isAdmin) {
      _append(workbook['Teachers'], await _readSchoolTable('school_teachers', schoolRef));
      _append(workbook['Holidays'], await _readSchoolTable('school_holidays', schoolRef));
      _append(workbook['AdminMessages'], await _readSchoolTable('school_admin_messages', schoolRef));
      _append(workbook['SchoolSettings'], await _readSchoolTable('school_settings', schoolRef));
      _append(workbook['CustomHeaders'], await _readSchoolTable('school_custom_headers', schoolRef));
      _append(workbook['TeacherLeaves'], await _readSchoolTable('teacher_leaves', schoolRef));
      if (includePrivateDetails) {
        _append(workbook['PrivateStudentDetails'], await _readSchoolTable('student_private_details', schoolRef));
      }
    }

    final bytes = workbook.encode();
    if (bytes == null) throw StateError('Excel workbook encoding failed.');
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    return SchoolExportBundle(
      bytes: Uint8List.fromList(bytes),
      fileName: 'PSM_${isAdmin ? 'School' : 'AssignedClasses'}_$stamp.xlsx',
    );
  }

  Future<List<Map<String, dynamic>>> _readClassTable(
    String table, String schoolRef, List<String> classIds,
  ) async {
    if (classIds.isEmpty) return [];
    try {
      final rows = await _client.from(table).select().eq('school_ref', schoolRef)
          .inFilter('class_id', classIds);
      return rows.map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r)).toList();
    } catch (error) {
      throw StateError('Could not export $table. Check this teacher\'s class permissions. $error');
    }
  }

  Future<List<Map<String, dynamic>>> _readSchoolTable(String table, String schoolRef) async {
    try {
      final rows = await _client.from(table).select().eq('school_ref', schoolRef);
      return rows.map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r)).toList();
    } catch (error) {
      // Private details are optional, but other admin sheets should not fail silently.
      if (table == 'student_private_details') return [];
      throw StateError('Could not export $table. $error');
    }
  }

  void _append(Sheet sheet, List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      sheet.appendRow([TextCellValue('No rows available')]);
      return;
    }
    final columns = <String>[];
    for (final row in rows) {
      for (final key in row.keys) {
        if (!columns.contains(key)) columns.add(key);
      }
    }
    sheet.appendRow(columns.map((k) => TextCellValue(k)).toList());
    for (final row in rows) {
      sheet.appendRow(columns.map((key) {
        final value = row[key];
        if (value == null) return TextCellValue('');
        if (value is Map || value is List) return TextCellValue(jsonEncode(value));
        return TextCellValue('$value');
      }).toList());
    }
  }
}

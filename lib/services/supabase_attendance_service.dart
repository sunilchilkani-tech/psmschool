import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import '../models/models.dart';

class SupabaseAttendanceService {
  final SupabaseClient _client;

  SupabaseAttendanceService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  SupabaseClient get client => _client;

  Future<String> getCurrentSchoolRef() async {
    final teacherId = _client.auth.currentUser?.id;

    if (teacherId == null) {
      throw Exception('Teacher is not logged in.');
    }

    final row = await _client
        .from('school_teachers')
        .select('school_ref')
        .eq('auth_user_id', teacherId)
        .maybeSingle();

    if (row == null || row['school_ref'] == null) {
      throw Exception('School not found for the logged-in teacher.');
    }

    return row['school_ref'].toString();
  }

  Future<String> getCurrentTeacherId() async {
    final authUserId = _client.auth.currentUser?.id;

    if (authUserId == null) {
      throw Exception('Teacher is not logged in.');
    }

    final row = await _client
        .from('school_teachers')
        .select('id')
        .eq('auth_user_id', authUserId)
        .maybeSingle();

    if (row == null || row['id'] == null) {
      throw Exception('Teacher record not found.');
    }

    return row['id'].toString();
  }

  Future<Map<String, dynamic>> getClassByName(String className) async {
    final schoolRef = await getCurrentSchoolRef();

    Map<String, dynamic>? row;

    final byKey = await _client
        .from('school_classes')
        .select('id, school_ref, class_key, label')
        .eq('school_ref', schoolRef)
        .eq('class_key', className)
        .eq('is_active', true)
        .maybeSingle();

    if (byKey != null) {
      row = Map<String, dynamic>.from(byKey);
    } else {
      final byLabel = await _client
          .from('school_classes')
          .select('id, school_ref, class_key, label')
          .eq('school_ref', schoolRef)
          .eq('label', className)
          .eq('is_active', true)
          .maybeSingle();

      if (byLabel != null) {
        row = Map<String, dynamic>.from(byLabel);
      }
    }

    if (row == null) {
      throw Exception('Class not found: $className');
    }

    return row;
  }

  Future<List<Map<String, dynamic>>> getStudents(String classId) async {
    final schoolRef = await getCurrentSchoolRef();

    final rows = await _client
        .from('students')
        .select('''
          id,
          school_ref,
          class_id,
          roll_number,
          gr,
          dd,
          mm,
          yyyy,
          name,
          caste,
          category,
          gender,
          enroll_school,
          enroll_class,
          mobile,
          mother_name,
          birth_place,
          dob_words,
          last_school,
          enroll_sch_class,
          enroll_sch_class_words,
          name_en,
          caste_en,
          category_en,
          mother_en,
          birth_place_en,
          dob_en,
          last_school_en,
          enroll_sch_class_en,
          enroll_sch_class_words_en,
          uid,
          pen,
          scholarship_done,
          scholarship_reason,
          scholarship_other,
          custom_fields,
          is_active
        ''')
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .eq('is_active', true)
        .order('roll_number');

    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>?> getAttendanceDay({
    required String classId,
    required String date,
  }) async {
    final schoolRef = await getCurrentSchoolRef();

    final row = await _client
        .from('attendance_days')
        .select()
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .eq('attendance_date', date)
        .maybeSingle();

    if (row == null) return null;

    return Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>> createAttendanceDay({
    required String classId,
    required String date,
  }) async {
    final schoolRef = await getCurrentSchoolRef();
    final teacherId = await getCurrentTeacherId();

    final inserted = await _client
        .from('attendance_days')
        .insert({
          'school_ref': schoolRef,
          'class_id': classId,
          'attendance_date': date,
          'updated_by_teacher': teacherId,
        })
        .select()
        .single();

    return Map<String, dynamic>.from(inserted);
  }

  Future<Map<String, dynamic>> getOrCreateAttendanceDay({
    required String classId,
    required String date,
  }) async {
    final existing = await getAttendanceDay(
      classId: classId,
      date: date,
    );

    if (existing != null) return existing;

    return createAttendanceDay(
      classId: classId,
      date: date,
    );
  }

  CategoryCounts _categoryCounts(dynamic value) {
    if (value is Map) {
      return CategoryCounts.fromJson(
        Map<String, dynamic>.from(value),
      );
    }

    return CategoryCounts();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  AttendanceRecord _attendanceFromDay(Map<String, dynamic> day) {
    return AttendanceRecord(
      present: _categoryCounts(day['present_counts']),
      mdm: _categoryCounts(day['mdm_counts']),
      breakfastTotal: _asInt(day['breakfast_total']),
      registered: _categoryCounts(day['registered_counts']),
      genderBreakdown: day['gender_breakdown'] is Map
          ? Map<String, dynamic>.from(day['gender_breakdown'])
          : const <String, dynamic>{},
    );
  }

  StudentRecord _studentFromDatabase(
    Map<String, dynamic> row, {
    bool present = false,
    bool mdm = false,
    bool breakfast = false,
  }) {
    return StudentRecord.fromJson({
      'id': row['id'] ?? '',
      'rollNumber': row['roll_number'] ?? '',
      'gr': row['gr'] ?? '',
      'dd': row['dd'] ?? '',
      'mm': row['mm'] ?? '',
      'yyyy': row['yyyy'] ?? '',
      'name': row['name'] ?? '',
      'caste': row['caste'] ?? '',
      'category': row['category'] ?? 'OTHER',
      'gender': row['gender'] ?? 'UNSPECIFIED',
      'enrollSchool': row['enroll_school'] ?? '',
      'enrollClass': row['enroll_class'] ?? '',
      'mobile': row['mobile'] ?? '',
      'motherName': row['mother_name'] ?? '',
      'birthPlace': row['birth_place'] ?? '',
      'dobWords': row['dob_words'] ?? '',
      'lastSchool': row['last_school'] ?? '',
      'enrollSchClass': row['enroll_sch_class'] ?? '',
      'enrollSchClassWords': row['enroll_sch_class_words'] ?? '',
      'nameEn': row['name_en'] ?? '',
      'casteEn': row['caste_en'] ?? '',
      'catEn': row['category_en'] ?? '',
      'motherEn': row['mother_en'] ?? '',
      'birthPlaceEn': row['birth_place_en'] ?? '',
      'dobEn': row['dob_en'] ?? '',
      'lastSchoolEn': row['last_school_en'] ?? '',
      'enrollSchClassEn': row['enroll_sch_class_en'] ?? '',
      'enrollSchClassWordsEn':
          row['enroll_sch_class_words_en'] ?? '',
      'uid': row['uid'] ?? '',
      'pen': row['pen'] ?? '',
      'scholarshipDone':
          row['scholarship_done'] ?? 'ના',
      'scholarshipReason':
          row['scholarship_reason'] ?? '',
      'scholarshipOther':
          row['scholarship_other'] ?? '',
      'customFields': row['custom_fields'] is Map
          ? Map<String, String>.from(
              (row['custom_fields'] as Map).map(
                (key, value) =>
                    MapEntry(key.toString(), value.toString()),
              ),
            )
          : <String, String>{},
      'present': present,
      'mdm': mdm,
      'breakfast': breakfast,
    });
  }

  Future<List<Map<String, dynamic>>> _getStudentAttendanceForDay(
    String schoolRef,
    String classId,
    String attendanceDayId,
  ) async {
    final rows = await _client
        .from('student_attendance')
        .select(
          'id, student_id, present, mdm, breakfast, attendance_day_id',
        )
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .eq('attendance_day_id', attendanceDayId);

    return List<Map<String, dynamic>>.from(rows);
  }

  CategoryCounts _registeredFromStudents(
    List<StudentRecord> students,
  ) {
    final result = CategoryCounts();

    for (final student in students) {
      result.set(
        student.category,
        result[student.category] + 1,
      );
    }

    return result;
  }

  /// Replacement for the old ApiService.getRowData().
  Future<RowData> getRowData(
    String className,
    String date,
  ) async {
    final schoolClass = await getClassByName(className);
    final classId = schoolClass['id'].toString();
    final schoolRef = schoolClass['school_ref'].toString();

    final rawStudents = await getStudents(classId);

    final day = await getAttendanceDay(
      classId: classId,
      date: date,
    );

    // No attendance row yet.
    if (day == null) {
      final students = rawStudents
          .map((row) => _studentFromDatabase(row))
          .toList();

      return RowData(
        registered: _registeredFromStudents(students),
        attendance: null,
        students: students,
        studentDetailsSaved: false,
        attendanceMode: 'none',
        genderBreakdown: const {},
      );
    }

    final attendanceDayId = day['id'].toString();

    final savedAttendance =
        await _getStudentAttendanceForDay(
      schoolRef,
      classId,
      attendanceDayId,
    );

    final attendanceByStudent = <String, Map<String, dynamic>>{
      for (final row in savedAttendance)
        row['student_id'].toString(): row,
    };

    final students = rawStudents.map((row) {
      final saved = attendanceByStudent[row['id'].toString()];

      return _studentFromDatabase(
        row,
        present: saved?['present'] == true,
        mdm: saved?['mdm'] == true,
        breakfast: saved?['breakfast'] == true,
      );
    }).toList();

    return RowData(
      registered: _categoryCounts(day['registered_counts']),
      attendance: _attendanceFromDay(day),
      students: students,
      studentDetailsSaved:
          day['student_details_saved'] == true,
      attendanceMode:
          (day['attendance_mode'] ?? 'none').toString(),
      genderBreakdown: day['gender_breakdown'] is Map
          ? Map<String, dynamic>.from(day['gender_breakdown'])
          : const {},
    );
  }

  /// Replacement for the old ApiService.saveAttendance().
  Future<Map<String, dynamic>> saveAttendance({
    required String className,
    required String date,
    required CategoryCounts registered,
    required CategoryCounts present,
    required CategoryCounts mdm,
    required int breakfastTotal,
    Map<String, dynamic>? genderBreakdown,
  }) async {
    final schoolClass = await getClassByName(className);
    final classId = schoolClass['id'].toString();

    final schoolRef = await getCurrentSchoolRef();
    final teacherId = await getCurrentTeacherId();

    final day = await getOrCreateAttendanceDay(
      classId: classId,
      date: date,
    );

    final updated = await _client
        .from('attendance_days')
        .update({
          'registered_counts': {
            'SC': registered[Category.sc],
            'ST': registered[Category.st],
            'OBC': registered[Category.obc],
            'OTHER': registered[Category.other],
          },
          'present_counts': {
            'SC': present[Category.sc],
            'ST': present[Category.st],
            'OBC': present[Category.obc],
            'OTHER': present[Category.other],
          },
          'mdm_counts': {
            'SC': mdm[Category.sc],
            'ST': mdm[Category.st],
            'OBC': mdm[Category.obc],
            'OTHER': mdm[Category.other],
          },
          'breakfast_total': breakfastTotal,
          'gender_breakdown':
              genderBreakdown ?? const <String, dynamic>{},
          'attendance_mode': 'direct',
          'student_details_saved': false,
          'updated_by_teacher': teacherId,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', day['id'])
        .eq('school_ref', schoolRef)
        .select()
        .single();

    return {
      'result': 'success',
      'data': Map<String, dynamic>.from(updated),
    };
  }

  /// Replacement for the old ApiService.saveStudentAttendance().
  Future<Map<String, dynamic>> saveStudentAttendance({
    required String className,
    required String date,
    required List<StudentRecord> students,
  }) async {
    final schoolClass = await getClassByName(className);
    final classId = schoolClass['id'].toString();

    final schoolRef = await getCurrentSchoolRef();
    final teacherId = await getCurrentTeacherId();

    final day = await getOrCreateAttendanceDay(
      classId: classId,
      date: date,
    );

    final attendanceDayId = day['id'].toString();

    final rows = students.map((student) {
      return {
        'school_ref': schoolRef,
        'class_id': classId,
        'attendance_day_id': attendanceDayId,
        'student_id': student.id,
        'present': student.present,
        'mdm': student.mdm,
        'breakfast': student.breakfast,
        'updated_by_teacher': teacherId,
      };
    }).toList();

    if (rows.isNotEmpty) {
      await _client
          .from('student_attendance')
          .upsert(
            rows,
            onConflict: 'attendance_day_id,student_id',
          );
    }

    // The RPC recalculates registered/present/MDM/breakfast
    // and canonical category × gender data.
    await refreshAttendanceDay(attendanceDayId);

    await _client
        .from('attendance_days')
        .update({
          'attendance_mode': 'student',
          'student_details_saved': true,
          'updated_by_teacher': teacherId,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', attendanceDayId)
        .eq('school_ref', schoolRef);

    return {
      'result': 'success',
      'message': 'Attendance saved successfully.',
    };
  }

  Future<void> refreshAttendanceDay(
    String attendanceDayId,
  ) async {
    await _client.rpc(
      'refresh_attendance_day_counts',
      params: {
        'p_attendance_day_id': attendanceDayId,
      },
    );
  }
}
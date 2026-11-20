import 'dart:convert';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import '../models/models.dart';
import 'api_service.dart';
import 'supabase_class_service.dart';
import 'student_management_service.dart';

/// Compatibility bridge for the existing ResultShell API surface.
/// All reads/writes go to Supabase; there is no Google Apps Script request here.
class SupabaseResultApiService extends ApiService {
  SupabaseResultApiService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client,
        super('supabase://result-adapter');

  final SupabaseClient _client;
  final SupabaseClassService _classes = SupabaseClassService();
  final StudentManagementService _students = StudentManagementService();

  Future<String> _schoolRef() async {
    final value = await _client.rpc('current_school_ref');
    if (value == null || '$value'.isEmpty) {
      throw StateError('No school is linked to this Supabase session.');
    }
    return '$value';
  }

  Future<String> _teacherName() async {
    final user = _client.auth.currentUser;
    if (user == null) return '';
    final row = await _client
        .from('school_teachers')
        .select('teacher_name')
        .eq('auth_user_id', user.id)
        .maybeSingle();
    return '${row?['teacher_name'] ?? ''}';
  }

  Future<String> _classTeacherName(Map<String, dynamic> classRow) async {
    final classTeacherId = '${classRow['class_teacher_id'] ?? ''}'.trim();
    if (classTeacherId.isEmpty) {
      return '${classRow['class_teacher_name'] ?? ''}'.trim();
    }
    try {
      // Security-definer RPC checks the signed-in school's class-access scope,
      // then returns only the assigned class-teacher display name.
      final value = await _client.rpc('psm_result_class_teacher_name', params: {
        'p_class_id': '${classRow['id'] ?? ''}',
      });
      final assignedName = '${value ?? ''}'.trim();
      if (assignedName.isNotEmpty) return assignedName;
    } catch (_) {}
    try {
      final schoolRef = '${classRow['school_ref'] ?? ''}'.trim();
      var query = _client
          .from('school_teachers')
          .select('teacher_name')
          .eq('id', classTeacherId);
      final row = schoolRef.isEmpty
          ? await query.maybeSingle()
          : await _client
              .from('school_teachers')
              .select('teacher_name')
              .eq('id', classTeacherId)
              .eq('school_ref', schoolRef)
              .maybeSingle();
      final assignedName = '${row?['teacher_name'] ?? ''}'.trim();
      if (assignedName.isNotEmpty) return assignedName;
    } catch (_) {
      // Never substitute the logged-in Admin/subject teacher for the actual
      // class teacher on a printed front page.
    }
    return '${classRow['class_teacher_name'] ?? ''}'.trim();
  }

  Future<String?> _currentTeacherId() async {
    final value = await _client.rpc('current_teacher_id');
    final id = '${value ?? ''}'.trim();
    return id.isEmpty ? null : id;
  }

  Future<bool> _isSchoolAdmin() async =>
      await _client.rpc('is_school_admin') == true;

  Future<bool> _isTeacherAssignedSubject(
      String classId, String subjectName) async {
    if (await _isSchoolAdmin()) return true;
    final teacherId = await _currentTeacherId();
    if (teacherId == null) return false;
    final classRow = await _client
        .from('school_classes')
        .select('class_teacher_id')
        .eq('id', classId)
        .maybeSingle();
    if ('${classRow?['class_teacher_id'] ?? ''}' == teacherId) {
      // Class teachers can enter marks for every active subject in their class.
      return true;
    }
    final master = await _client
        .from('school_subject_master')
        .select('id')
        .eq('subject_name', subjectName)
        .eq('is_active', true)
        .maybeSingle();
    if (master == null) return false;
    final activeSubject = await _client
        .from('class_subjects')
        .select('id')
        .eq('class_id', classId)
        .eq('subject_name', subjectName)
        .eq('is_active', true)
        .maybeSingle();
    if (activeSubject == null) return false;
    final row = await _client
        .from('teacher_subject_assignments')
        .select('subject_name')
        .eq('teacher_id', teacherId)
        .eq('class_id', classId)
        .eq('subject_name', subjectName)
        .maybeSingle();
    return row != null;
  }

  Future<Map<String, dynamic>> _classRow(String className) async {
    final id = await _classes.resolveClassId(className);
    final row =
        await _client.from('school_classes').select().eq('id', id).single();
    return Map<String, dynamic>.from(row);
  }

  int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  bool _bool(dynamic value) =>
      value == true ||
      '${value ?? ''}'.toLowerCase() == 'yes' ||
      '${value ?? ''}'.toLowerCase() == 'true' ||
      '${value ?? ''}' == '1';

  String _categoryLabel(dynamic value) {
    switch ('${value ?? ''}'.trim().toUpperCase()) {
      case 'SC':
        return 'અ.જા.';
      case 'ST':
        return 'અ.જ.જા.';
      case 'OBC':
        return 'બક્ષીપંચ';
      default:
        return 'અન્ય';
    }
  }

  String _categoryDb(dynamic value) {
    final text = '${value ?? ''}'.replaceAll(' ', '').toUpperCase();
    if (text == 'SC' || text.contains('અ.જા')) return 'SC';
    if (text == 'ST' || text.contains('અ.જ.જા')) return 'ST';
    if (text == 'OBC' || text.contains('બક્ષી')) return 'OBC';
    return 'OTHER';
  }

  List<int> _sentenceMarks(dynamic value) {
    if (value is List)
      return List<int>.generate(
        40,
        (i) => i < value.length ? _int(value[i]) : 0,
      );
    return List<int>.filled(40, 0);
  }

  Future<List<Map<String, dynamic>>> _activeRoster(String classId) async {
    final rows = await _client
        .from('students')
        .select()
        .eq('class_id', classId)
        .eq('is_active', true);
    final list = rows
        .map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r))
        .toList();
    list.sort((a, b) {
      final ar = int.tryParse('${a['roll_number'] ?? ''}');
      final br = int.tryParse('${b['roll_number'] ?? ''}');
      if (ar != null && br != null) return ar.compareTo(br);
      if (ar != null) return -1;
      if (br != null) return 1;
      return '${a['roll_number'] ?? ''}'.compareTo('${b['roll_number'] ?? ''}');
    });
    return list;
  }

  bool _isRosterSnapshotSchemaMissing(Object error) {
    final message = error.toString().toLowerCase();
    final mentionsRosterTable =
        message.contains('student_result_roster_snapshots') ||
            message.contains('student_result_roster_members');
    return mentionsRosterTable &&
        (message.contains('does not exist') ||
            message.contains('schema cache') ||
            message.contains('could not find the table') ||
            message.contains('42p01') ||
            message.contains('pgrst205'));
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<List<Map<String, dynamic>>> _snapshotRosterMembers(
      String snapshotId, String classId) async {
    final rows = await _client
        .from('student_result_roster_members')
        .select(
            'student_id,roll_number,student_name,category,gender,snapshot_order,student_data')
        .eq('snapshot_id', snapshotId)
        .order('snapshot_order');
    final ids = rows
        .map((row) => '${row['student_id']}')
        .where((id) => id.isNotEmpty)
        .toList();
    final liveById = <String, Map<String, dynamic>>{};
    if (ids.isNotEmpty) {
      final liveRows = await _client
          .from('students')
          .select(
              'id,roll_number,name,category,gender,gr,dd,mm,yyyy,uid,pen,mobile,father_name,mother_name,address,caste,birth_place,dob_words,last_school,is_active')
          .eq('class_id', classId)
          .inFilter('id', ids);
      for (final live in liveRows) {
        final map = Map<String, dynamic>.from(live);
        liveById['${map['id']}'] = map;
      }
    }
    final result = <Map<String, dynamic>>[];
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      final id = '${row['student_id']}';
      final dynamic rawData = row['student_data'];
      Map<String, dynamic> data = <String, dynamic>{};
      if (rawData is Map) {
        data = Map<String, dynamic>.from(
            rawData.map((key, value) => MapEntry('$key', value)));
      } else if (rawData is String && rawData.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawData);
          if (decoded is Map)
            data = Map<String, dynamic>.from(
                decoded.map((key, value) => MapEntry('$key', value)));
        } catch (_) {}
      }
      // Keep snapshot membership/order immutable, but use the existing student master fields
      // for rows that still exist so password-authorized detail edits remain visible after reload.
      final live = liveById[id];
      if (live != null) {
        // Student Management is the live source of truth. Archiving a student
        // hides them from the current Result view but does not delete the old
        // snapshot membership or the stored marks.
        if (live['is_active'] != true) continue;
        data.addAll(live);
      } else {
        data['roll_number'] =
            '${row['roll_number'] ?? data['roll_number'] ?? ''}';
        data['name'] = '${row['student_name'] ?? data['name'] ?? ''}';
        data['category'] = '${row['category'] ?? data['category'] ?? ''}';
        data['gender'] = '${row['gender'] ?? data['gender'] ?? 'UNSPECIFIED'}';
      }
      data['id'] = id;
      data['student_id'] = id;
      result.add(data);
    }
    return result;
  }

  Future<Map<String, dynamic>> getResultRosterStatus(String className) async {
    try {
      final schoolRef = await _schoolRef();
      final cls = await _classRow(className);
      final classId = '${cls['id']}';
      final year = await _academicYear(classId);
      final rows = await _client
          .from('student_result_roster_snapshots')
          .select(
              'id,semester,academic_year,source_date,roster_count,captured_at,is_current')
          .eq('school_ref', schoolRef)
          .eq('class_id', classId)
          .eq('academic_year', year)
          .order('captured_at', ascending: false);
      final allRows = rows
          .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
          .toList();
      final semesters = <String, dynamic>{};
      for (final semester in const [1, 2]) {
        final entries =
            allRows.where((row) => _int(row['semester']) == semester).toList();
        Map<String, dynamic>? current;
        for (final row in entries) {
          if (row['is_current'] == true) {
            current = row;
            break;
          }
        }
        semesters['$semester'] = <String, dynamic>{
          'current': current,
          'versionCount': entries.length,
          'priorVersionCount':
              entries.isEmpty ? 0 : entries.length - (current == null ? 0 : 1),
        };
      }
      return {
        'result': 'success',
        'academicYear': year,
        'semesters': semesters
      };
    } catch (error) {
      if (_isRosterSnapshotSchemaMissing(error)) {
        return {
          'result': 'schema_missing',
          'message':
              'Result roster migration is not applied. Run npx supabase db push before importing register snapshots.',
          'semesters': <String, dynamic>{
            '1': <String, dynamic>{
              'current': null,
              'versionCount': 0,
              'priorVersionCount': 0
            },
            '2': <String, dynamic>{
              'current': null,
              'versionCount': 0,
              'priorVersionCount': 0
            },
          },
        };
      }
      return {
        'result': 'error',
        'message': '$error',
        'semesters': <String, dynamic>{}
      };
    }
  }

  Future<Map<String, dynamic>> previewResultRosterFromRegister({
    required String className,
    required DateTime sourceDate,
  }) async {
    try {
      final schoolRef = await _schoolRef();
      final teacherId = await _client.rpc('current_teacher_id');
      final isAdmin = await _isSchoolAdmin();
      if ((teacherId == null || '$teacherId'.trim().isEmpty) && !isAdmin) {
        return {
          'result': 'error',
          'message':
              'Active teacher/admin session not found. Please sign in again.'
        };
      }
      final cls = await _classRow(className);
      final classId = '${cls['id']}';
      final dateString = _dateOnly(sourceDate);
      final dayRaw = await _client
          .from('attendance_days')
          .select('id,attendance_date,attendance_mode,student_details_saved')
          .eq('school_ref', schoolRef)
          .eq('class_id', classId)
          .eq('attendance_date', dateString)
          .maybeSingle();
      if (dayRaw == null) {
        return {
          'result': 'error',
          'message': 'આ વર્ગ માટે $dateString નો attendance register મળ્યો નથી.'
        };
      }
      final day = Map<String, dynamic>.from(dayRaw);
      final attendanceMode =
          '${day['attendance_mode'] ?? ''}'.trim().toLowerCase();
      final isDirectEntry = <String>{
        'direct',
        'direct_entry',
        'direct-entry',
        'direct entry',
        'aggregate',
      }.contains(attendanceMode);

      // Direct Entry stores class-level totals only. It intentionally has no
      // student_attendance rows, so the Result roster must come from the
      // active Student Database for this exact school/class. Never synthesize
      // per-student present/absent marks from aggregate counts.
      List<Map<String, dynamic>> students;
      if (isDirectEntry) {
        final studentRows = await _client
            .from('students')
            .select(
                'id,school_ref,class_id,roll_number,name,category,gender,gr,dd,mm,yyyy,uid,pen,mobile,father_name,mother_name,address,caste,birth_place,dob_words,last_school,is_active')
            .eq('school_ref', schoolRef)
            .eq('class_id', classId)
            .eq('is_active', true);
        students = studentRows
            .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
            .where((row) => '${row['id'] ?? ''}'.trim().isNotEmpty)
            .toList();
      } else {
        if (day['student_details_saved'] != true) {
          return {
            'result': 'error',
            'message':
                '$dateString એ student-wise attendance roster સેવ થયેલો નથી. Attendance mode ઓળખી શકાયો નથી; Student Entry mode માંથી ફરી સેવ કરો.'
          };
        }
        final attendanceRows = await _client
            .from('student_attendance')
            .select('student_id')
            .eq('school_ref', schoolRef)
            .eq('class_id', classId)
            .eq('attendance_day_id', '${day['id']}');
        final ids = attendanceRows
            .map((row) => '${row['student_id']}')
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
        if (ids.isEmpty) {
          return {
            'result': 'error',
            'message':
                '$dateString ના રજીસ્ટરમાં વિદ્યાર્થીની saved detail rows નથી.'
          };
        }
        final studentRows = await _client
            .from('students')
            .select(
                'id,school_ref,class_id,roll_number,name,category,gender,gr,dd,mm,yyyy,uid,pen,mobile,father_name,mother_name,address,caste,birth_place,dob_words,last_school,is_active')
            .eq('school_ref', schoolRef)
            .eq('class_id', classId)
            .eq('is_active', true)
            .inFilter('id', ids);
        students = studentRows
            .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
            .toList();
      }
      students.sort((a, b) {
        final ar = int.tryParse('${a['roll_number'] ?? ''}');
        final br = int.tryParse('${b['roll_number'] ?? ''}');
        if (ar != null && br != null) return ar.compareTo(br);
        if (ar != null) return -1;
        if (br != null) return 1;
        final rollCompare =
            '${a['roll_number'] ?? ''}'.compareTo('${b['roll_number'] ?? ''}');
        return rollCompare != 0
            ? rollCompare
            : '${a['name'] ?? ''}'.compareTo('${b['name'] ?? ''}');
      });
      if (students.isEmpty) {
        return {
          'result': 'error',
          'message':
              'રજીસ્ટરના student IDs માટે શાળામાં વિદ્યાર્થીઓના રેકોર્ડ મળ્યા નથી.'
        };
      }
      return {
        'result': 'success',
        'sourceDate': dateString,
        'attendanceDayId': '${day['id']}',
        'count': students.length,
        'sourceMode': isDirectEntry ? 'direct_entry' : 'student_wise',
        'rosterSource':
            isDirectEntry ? 'student_database' : 'student_attendance',
        'rosterNotice': isDirectEntry
            ? 'Direct Entry માં કુલ હાજરીનો આંકડો જ સેવ થાય છે. વિદ્યાર્થી યાદી વર્તમાન Student Database માંથી લેવામાં આવી છે; વ્યક્તિગત હાજરી ચિહ્નો બનાવવામાં આવ્યા નથી.'
            : '',
        'students': students,
      };
    } catch (error) {
      if (_isRosterSnapshotSchemaMissing(error)) {
        return {
          'result': 'error',
          'message':
              'Result roster migration લાગુ નથી. પહેલાં npx supabase db push ચલાવો.'
        };
      }
      return {'result': 'error', 'message': '$error'};
    }
  }

  Future<Map<String, dynamic>> replaceResultRosterFromRegister({
    required String className,
    required int semester,
    required DateTime sourceDate,
  }) async {
    try {
      if (semester != 1 && semester != 2) {
        return {'result': 'error', 'message': 'Semester must be 1 or 2.'};
      }
      final cls = await _classRow(className);
      final isAdmin = await _isSchoolAdmin();
      if (!isAdmin) {
        final lockRow = await _client
            .from('class_result_settings')
            .select('sem1_locked,sem2_locked')
            .eq('class_id', '${cls['id']}')
            .maybeSingle();
        final isSemLocked = semester == 1
            ? (lockRow?['sem1_locked'] == true)
            : (lockRow?['sem2_locked'] == true);
        if (isSemLocked) {
          return {
            'result': 'error',
            'message':
                '\u{1F512} \u0A86 \u0AB8\u0AA4\u0ACD\u0AB0\u0AA8\u0AC1\u0A82 \u0AAA\u0AB0\u0ABF\u0AA3\u0ABE\u0AAE \u0AB2\u0ACB\u0A95 \u0A95\u0AB0\u0AC7\u0AB2 \u0A9B\u0AC7. Admin \u0A85\u0AA8\u0AB2\u0ACB\u0A95 \u0A95\u0AB0\u0AC7 \u0AAA\u0A9B\u0AC0 \u0A9C \u0A97\u0AC1\u0AA3, \u0AB5\u0ACD\u0AAF\u0A95\u0ACD\u0AA4\u0ABF\u0AA4\u0ACD\u0AB5 \u0AB5\u0ABF\u0A95\u0ABE\u0AB8 \u0A95\u0AC7 \u0AB8\u0ACD\u0AA8\u0AC7\u0AAA\u0AB6\u0ACB\u0A9F \u0AAC\u0AA6\u0AB2\u0AC0 \u0AB6\u0A95\u0ABE\u0AB6\u0AC7.',
          };
        }
      }
      final response =
          await _client.rpc('replace_student_result_roster_snapshot', params: {
        'p_class_id': '${cls['id']}',
        'p_semester': semester,
        'p_source_date': _dateOnly(sourceDate),
      });
      if (response is Map)
        return Map<String, dynamic>.from(
            response.map((key, value) => MapEntry('$key', value)));
      return {
        'result': 'error',
        'message': 'Supabase did not return the snapshot result.'
      };
    } catch (error) {
      return {'result': 'error', 'message': '$error'};
    }
  }

  /// Adds a student by stable UUID to a new current-roster version. Previous
  /// snapshots and marks remain untouched.
  Future<Map<String, dynamic>> adminAddResultRosterMember({
    required String className,
    required int semester,
    required String studentId,
  }) async {
    try {
      if (!await _isSchoolAdmin()) {
        return {
          'result': 'error',
          'message':
              'Only the School Admin can add a student to the Result roster.'
        };
      }
      if (semester != 1 && semester != 2) {
        return {'result': 'error', 'message': 'Semester must be 1 or 2.'};
      }
      final cls = await _classRow(className);
      final response =
          await _client.rpc('psm_admin_add_result_roster_member', params: {
        'p_class_id': '${cls['id']}',
        'p_semester': semester,
        'p_student_id': studentId,
      });
      if (response is Map) {
        return Map<String, dynamic>.from(
            response.map((key, value) => MapEntry('$key', value)));
      }
      return {
        'result': 'error',
        'message': 'Supabase did not return the roster update result.'
      };
    } catch (error) {
      return {'result': 'error', 'message': '$error'};
    }
  }

  @override
  Future<ResultSheetData> getResultData(String className) =>
      getResultDataForSemester(className, rosterSemester: 1);

  Future<ResultSheetData> getResultDataForSemester(
    String className, {
    required int rosterSemester,
  }) async {
    final schoolRef = await _schoolRef();
    final cls = await _classRow(className);
    final classId = '${cls['id']}';
    final settingsRaw = await _client
        .from('class_result_settings')
        .select()
        .eq('class_id', classId)
        .maybeSingle();
    final settings = settingsRaw == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(settingsRaw);
    // Result Front Page fields (dates, academic year, district, education authority,
    // village, taluka, pay center, CRC) are shared across the entire school.
    // Only class name, class data, and class teacher name vary per class.
    const sharedFrontPageKeys = <String>[
      'first_sem_result_date',
      'second_sem_result_date',
      'result_date',
      'academic_year',
      'front_page_district',
      'front_page_education_authority',
      'front_page_village',
      'front_page_taluka',
      'front_page_pay_center',
      'front_page_crc',
    ];
    try {
      final cfgRow = await _client
          .from('school_settings')
          .select('config')
          .eq('school_ref', schoolRef)
          .maybeSingle();
      final cfg = cfgRow?['config'];
      if (cfg is Map) {
        final shared = cfg['result_front_page_settings'];
        if (shared is Map) {
          for (final k in sharedFrontPageKeys) {
            final v = '${shared[k] ?? ''}'.trim();
            if (v.isNotEmpty) {
              settings[k] = v;
            }
          }
        }
      }
    } catch (_) {}
    try {
      final schoolSettingsRows = await _client
          .from('class_result_settings')
          .select()
          .eq('school_ref', schoolRef);
      final sortedRows = schoolSettingsRows
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList()
        ..sort((a, b) => '${b['updated_at'] ?? ''}'.compareTo('${a['updated_at'] ?? ''}'));
      for (final r in sortedRows) {
        for (final k in sharedFrontPageKeys) {
          if ('${settings[k] ?? ''}'.trim().isEmpty &&
              '${r[k] ?? ''}'.trim().isNotEmpty) {
            settings[k] = r[k];
          }
        }
      }
    } catch (_) {}
    final year = '${settings['academic_year'] ?? '2026 - 27'}';

    final snapshotsBySemester = <int, Map<String, dynamic>>{};
    var snapshotsAvailable = true;
    try {
      final snapshotRows = await _client
          .from('student_result_roster_snapshots')
          .select('id,semester,source_date,roster_count,is_current,captured_at')
          .eq('school_ref', schoolRef)
          .eq('class_id', classId)
          .eq('academic_year', year)
          .eq('is_current', true);
      for (final raw in snapshotRows) {
        final row = Map<String, dynamic>.from(raw);
        snapshotsBySemester[_int(row['semester'])] = row;
      }
    } catch (error) {
      if (_isRosterSnapshotSchemaMissing(error)) {
        snapshotsAvailable =
            false; // Compatibility while the new migration is not installed.
      } else {
        rethrow;
      }
    }

    final activeRoster = await _activeRoster(classId);
    var roster1 = activeRoster;
    var roster2 = activeRoster;
    if (snapshotsAvailable) {
      final s1 = snapshotsBySemester[1];
      final s2 = snapshotsBySemester[2];
      if (s1 != null)
        roster1 = await _snapshotRosterMembers('${s1['id']}', classId);
      if (s2 != null)
        roster2 = await _snapshotRosterMembers('${s2['id']}', classId);
      // Until the teacher captures Sem-2, do not leak later active students into the roster.
      if (s1 != null && s2 == null) roster2 = roster1;
    }

    final hasSem1Snapshot = snapshotsBySemester.containsKey(1);
    final hasSem2Snapshot = snapshotsBySemester.containsKey(2);
    final preferredRoster = rosterSemester == 2 ? roster2 : roster1;
    final fallbackRoster = rosterSemester == 2 ? roster1 : roster2;
    final preferredById = <String, Map<String, dynamic>>{};
    final fallbackById = <String, Map<String, dynamic>>{};
    for (final student in preferredRoster) {
      final id = '${student['id'] ?? student['student_id'] ?? ''}';
      if (id.isNotEmpty) preferredById[id] = student;
    }
    for (final student in fallbackRoster) {
      final id = '${student['id'] ?? student['student_id'] ?? ''}';
      if (id.isNotEmpty) fallbackById[id] = student;
    }

    // Annual/combined output retains the Sem-1 members (including leavers), then appends
    // new members first seen in Sem-2. A leaver is never deleted from Sem-1 history.
    final unionIds = <String>[];
    for (final student in roster1) {
      final id = '${student['id'] ?? student['student_id'] ?? ''}';
      if (id.isNotEmpty && !unionIds.contains(id)) unionIds.add(id);
    }
    if (rosterSemester == 2) {
      for (final student in roster2) {
        final id = '${student['id'] ?? student['student_id'] ?? ''}';
        if (id.isNotEmpty && !unionIds.contains(id)) unionIds.add(id);
      }
    }
    final allRosterRows = <Map<String, dynamic>>[];
    final snapshotStudentIds = <String>{};
    for (final id in unionIds) {
      final student = preferredById[id] ?? fallbackById[id];
      if (student != null) {
        allRosterRows.add(student);
        snapshotStudentIds.add(id);
      }
    }

    // Keep snapshot versions immutable, but make active Student Database changes
    // visible in Result immediately. New active students are appended in database
    // roll order and receive blank marks because marks are keyed by student UUID.
    // Existing snapshot members retain their original order until ResultShell sorts
    // the display numerically. Inactive/archived students are not appended.
    for (final activeStudent in activeRoster) {
      final id = '${activeStudent['id'] ?? ''}'.trim();
      if (id.isEmpty || snapshotStudentIds.contains(id)) continue;
      allRosterRows.add(Map<String, dynamic>.from(activeStudent));
      snapshotStudentIds.add(id);
    }

    final profileRows = await _client
        .from('student_result_profiles')
        .select()
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .eq('academic_year', year);
    final profiles = <String, Map<String, dynamic>>{};
    for (final row in profileRows) {
      profiles['${row['student_id']}'] = Map<String, dynamic>.from(row);
    }

    // Student-master is the live source of truth for Divyang. A saved Result
    // roster snapshot may be older than an Admin's latest student edit.
    final resultStudentIds = allRosterRows
        .map((row) => '${row['id'] ?? row['student_id'] ?? ''}')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final divyangByStudentId = <String, bool>{};
    if (resultStudentIds.isNotEmpty) {
      final liveStudentRows = await _client
          .from('students')
          .select('id,is_divyang')
          .eq('school_ref', schoolRef)
          .inFilter('id', resultStudentIds);
      for (final row in liveStudentRows) {
        divyangByStudentId['${row['id']}'] = _bool(row['is_divyang']);
      }
    }

    final markRows = await _client
        .from('student_subject_marks')
        .select()
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .eq('academic_year', year);
    final marksByStudent = <String, Map<int, Map<String, SubjectMarks>>>{};
    final subjectsSeen = <String>[];
    for (final raw in markRows) {
      final row = Map<String, dynamic>.from(raw);
      final studentId = '${row['student_id']}';
      final semester = _int(row['semester']);
      final subject = '${row['subject_name'] ?? ''}';
      if (subject.isNotEmpty &&
          subject != 'વ્યક્તિત્વ વિકાસ' &&
          !subjectsSeen.contains(subject)) subjectsSeen.add(subject);
      final bySem = marksByStudent.putIfAbsent(studentId, () => {1: {}, 2: {}});
      final rawSatrant = row['satrant'];
      final isSatrantAb = row['satrant_absent'] == true ||
          '${rawSatrant ?? ""}'.trim().toUpperCase() == 'AB' ||
          _int(rawSatrant) < 0;
      bySem.putIfAbsent(semester, () => {})[subject] = SubjectMarks(
        patrakA: _int(row['patrak_a']),
        satrant: isSatrantAb ? 0 : _int(rawSatrant),
        swaAdhyayan: _int(row['swa_adhyayan']),
        directTotal:
            row['direct_total'] == null ? null : _int(row['direct_total']),
        directMode:
            row['direct_total_mode'] == true || row['direct_total'] != null,
        satrantAbsent: isSatrantAb,
      );
    }

    // Mark entry/reporting must be class-specific. The school-wide master is
    // only a catalogue; counting every school subject here inflated totals when
    // one class used 6 subjects in Sem-1 and 7 in Sem-2. Keep active subjects for
    // this class plus legacy subject names that already have saved marks.
    final subjectsRaw = await _client
        .from('class_subjects')
        .select('subject_name,sort_order')
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .eq('is_active', true)
        .order('sort_order');
    final activeClassSubjects = subjectsRaw
        .map((row) => '${row['subject_name']}')
        .where((name) => name.trim().isNotEmpty && name != 'વ્યક્તિત્વ વિકાસ')
        .toList();
    final subjects = <String>[];
    for (final name in <String>[
      ...activeClassSubjects,
      ...subjectsSeen,
    ]) {
      if (name.trim().isNotEmpty &&
          name != 'વ્યક્તિત્વ વિકાસ' &&
          !subjects.contains(name)) subjects.add(name);
    }
    final adminUser = await _isSchoolAdmin();
    final teacherId = await _currentTeacherId();
    final isClassTeacher = adminUser ||
        (teacherId != null && '${cls['class_teacher_id'] ?? ''}' == teacherId);
    final assignedSubjects = <String>[];
    if (adminUser) {
      // Admin may edit all existing class marks, including retained historical subjects.
      assignedSubjects.addAll(subjects);
    } else if (isClassTeacher) {
      // The class teacher enters every active subject of their own class.
      assignedSubjects.addAll(activeClassSubjects);
    } else if (teacherId != null) {
      // Subject teachers: only the subjects they teach in this class.
      final assignments = await _client
          .from('teacher_subject_assignments')
          .select('subject_name')
          .eq('school_ref', schoolRef)
          .eq('class_id', classId)
          .eq('teacher_id', teacherId);
      final allowedNames =
          assignments.map((row) => '${row['subject_name']}'.trim()).toSet();
      final activeNames =
          activeClassSubjects.map((name) => name.toLowerCase()).toSet();
      final allowedLower = allowedNames.map((n) => n.toLowerCase()).toSet();
      assignedSubjects.addAll(subjects.where((name) =>
          allowedLower.contains(name.toLowerCase()) &&
          activeNames.contains(name.toLowerCase())));
    }

    final sem2Ids = roster2
        .map((row) => '${row['id'] ?? row['student_id'] ?? ''}')
        .where((id) => id.isNotEmpty)
        .toSet();
    final resultStudents = <ResultStudentRow>[];
    for (var i = 0; i < allRosterRows.length; i++) {
      final student = allRosterRows[i];
      final id = '${student['id'] ?? student['student_id'] ?? ''}';
      final profile = profiles[id] ?? const <String, dynamic>{};
      final bySem = marksByStudent[id] ??
          {1: <String, SubjectMarks>{}, 2: <String, SubjectMarks>{}};
      final sem1 = Map<String, SubjectMarks>.from(bySem[1] ?? const {});
      final sem2 = Map<String, SubjectMarks>.from(bySem[2] ?? const {});
      // Importing a Semester-2 register automatically sets this profile flag from membership.
      // A later teacher override (the legacy M column: Yes / No / નામ કમી) remains respected
      // until the next roster import recalculates it from the chosen register date.
      final isLiveDatabaseAddition = !unionIds.contains(id);
      final studiedInSem2 = profile.containsKey('studied_in_sem2')
          ? _bool(profile['studied_in_sem2'])
          : isLiveDatabaseAddition
              ? true
              : hasSem2Snapshot
                  ? sem2Ids.contains(id)
                  : hasSem1Snapshot
                      ? true
                      : true;
      resultStudents.add(ResultStudentRow(
        sheetRow: i + 2,
        studentId: id,
        roll: '${student['roll_number'] ?? ''}',
        name: '${student['name'] ?? ''}',
        category: _categoryLabel(student['category']),
        gender: '${student['gender'] ?? 'UNSPECIFIED'}'.toUpperCase(),
        dd: '${student['dd'] ?? ''}',
        mm: '${student['mm'] ?? ''}',
        yyyy: '${student['yyyy'] ?? ''}',
        uid: '${student['uid'] ?? ''}',
        pen: '${student['pen'] ?? ''}',
        mobile: '${student['mobile'] ?? ''}',
        fatherName: '${student['father_name'] ?? student['fatherName'] ?? ''}',
        motherName: '${student['mother_name'] ?? student['motherName'] ?? ''}',
        address: '${student['address'] ?? ''}',
        studiedInSem2: studiedInSem2,
        gr: '${student['gr'] ?? ''}',
        caste: '${student['caste'] ?? ''}',
        birthPlace: '${student['birth_place'] ?? student['birthPlace'] ?? ''}',
        dobWords: '${student['dob_words'] ?? student['dobWords'] ?? ''}',
        lastSchool: '${student['last_school'] ?? student['lastSchool'] ?? ''}',
        presentDays: _int(profile['present_days_sem1']),
        presentDays2: _int(profile['present_days_sem2']),
        standard: '${profile['standard'] ?? cls['standard'] ?? ''}',
        isDivyang: divyangByStudentId.containsKey(id)
            ? divyangByStudentId[id]!
            : _bool(profile['is_divyang']),
        sem1: sem1,
        sem2: sem2,
        vv1: _int(profile['vv1']),
        vv2: _int(profile['vv2']),
        vv1Sentences: _sentenceMarks(profile['vv1_sentences']),
        vv2Sentences: _sentenceMarks(profile['vv2_sentences']),
      ));
    }

    final rawVv = settings['vv_sentences'];
    final vvSentences =
        rawVv is List ? rawVv.map((value) => '$value').toList() : <String>[];
    final defaultSem2Date = ResultSheetData.defaultSecondSemResultDateForNow();
    final defaultSem1Date = ResultSheetData.defaultFirstSemResultDateForNow();
    final rawSem2Date = '${settings['second_sem_result_date'] ?? settings['result_date'] ?? ''}'.trim();
    final rawSem1Date = '${settings['first_sem_result_date'] ?? ''}'.trim();
    return ResultSheetData(
      className: className,
      subjects: subjects,
      students: resultStudents,
      teacherName: await _classTeacherName(cls),
      firstSemResultDate: rawSem1Date.isNotEmpty ? rawSem1Date : defaultSem1Date,
      resultDate: rawSem2Date.isNotEmpty ? rawSem2Date : defaultSem2Date,
      academicYear: year,
      frontPageDistrict: '${settings['front_page_district'] ?? ''}',
      frontPageEducationAuthority:
          '${settings['front_page_education_authority'] ?? ''}',
      frontPageVillage: '${settings['front_page_village'] ?? ''}',
      frontPageTaluka: '${settings['front_page_taluka'] ?? ''}',
      frontPagePayCenter: '${settings['front_page_pay_center'] ?? ''}',
      frontPageCrc: '${settings['front_page_crc'] ?? ''}',
      vvSentences: vvSentences,
      sem1Locked: settings['sem1_locked'] == true,
      sem2Locked: settings['sem2_locked'] == true,
      isClassTeacher: isClassTeacher,
      assignedSubjects: assignedSubjects,
    );
  }

  Future<Map<String, dynamic>> saveFrontPageSettings({
    required String className,
    String firstSemResultDate = '',
    required String resultDate,
    required String academicYear,
    required String district,
    required String educationAuthority,
    required String village,
    required String taluka,
    required String payCenter,
    required String crc,
  }) async {
    try {
      if (!await _isSchoolAdmin()) {
        return {
          'result': 'error',
          'message':
              'ફ્રન્ટ પેજની વિગતો બદલવાનો અધિકાર માત્ર School Admin પાસે છે.',
        };
      }
      final effectiveSem2Date = resultDate.trim().isNotEmpty
          ? resultDate.trim()
          : ResultSheetData.defaultSecondSemResultDateForNow();
      final effectiveSem1Date = firstSemResultDate.trim().isNotEmpty
          ? firstSemResultDate.trim()
          : ResultSheetData.defaultFirstSemResultDateForNow();
      if (academicYear.trim().isEmpty) {
        return {
          'result': 'error',
          'message': 'પરિણામની તારીખ અને શૈક્ષણિક વર્ષ ખાલી રાખી શકાતાં નથી.',
        };
      }
      final schoolRef = await _schoolRef();
      final cls = await _classRow(className);
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final sharedPayload = <String, dynamic>{
        'first_sem_result_date': effectiveSem1Date,
        'second_sem_result_date': effectiveSem2Date,
        'result_date': effectiveSem2Date,
        'academic_year': academicYear.trim(),
        'front_page_district': district.trim(),
        'front_page_education_authority': educationAuthority.trim(),
        'front_page_village': village.trim(),
        'front_page_taluka': taluka.trim(),
        'front_page_pay_center': payCenter.trim(),
        'front_page_crc': crc.trim(),
        'updated_at': nowIso,
      };

      // 1. Save school-wide in school_settings.config so any future class inherits it too
      try {
        final cfgRow = await _client
            .from('school_settings')
            .select('config')
            .eq('school_ref', schoolRef)
            .maybeSingle();
        final existingCfg = cfgRow?['config'] is Map
            ? Map<String, dynamic>.from(cfgRow!['config'] as Map)
            : <String, dynamic>{};
        existingCfg['result_front_page_settings'] = sharedPayload;
        existingCfg['first_sem_result_date'] = effectiveSem1Date;
        existingCfg['second_sem_result_date'] = effectiveSem2Date;
        await _client.from('school_settings').upsert(<String, dynamic>{
          'school_ref': schoolRef,
          'config': existingCfg,
          'updated_at': nowIso,
        }, onConflict: 'school_ref');
      } catch (_) {}

      // 2. Auto-apply to ALL classes in the school (preserving each class's vv_sentences & lock flags)
      final allClassIds = <String>{'${cls['id']}'};
      try {
        final classRows = await _client
            .from('school_classes')
            .select('id')
            .eq('school_ref', schoolRef);
        for (final r in classRows) {
          if (r is Map && '${r['id'] ?? ''}'.trim().isNotEmpty) {
            allClassIds.add('${r['id']}'.trim());
          }
        }
      } catch (_) {}

      final existingByClassId = <String, Map<String, dynamic>>{};
      try {
        final existingRows = await _client
            .from('class_result_settings')
            .select()
            .eq('school_ref', schoolRef);
        for (final r in existingRows) {
          if (r is Map && '${r['class_id'] ?? ''}'.trim().isNotEmpty) {
            existingByClassId['${r['class_id']}'.trim()] =
                Map<String, dynamic>.from(r);
          }
        }
      } catch (_) {}

      for (final cid in allClassIds) {
        final old = existingByClassId[cid] ?? <String, dynamic>{};
        await _client.from('class_result_settings').upsert(<String, dynamic>{
          ...old,
          'school_ref': schoolRef,
          'class_id': cid,
          ...sharedPayload,
        }, onConflict: 'class_id,school_ref');
      }

      try {
        await _client.rpc(
          'psm_set_second_sem_result_date',
          params: <String, dynamic>{'p_result_date': effectiveSem2Date},
        );
      } catch (_) {}
      return {'result': 'success'};
    } catch (error) {
      return {'result': 'error', 'message': '$error'};
    }
  }

  @override
  Future<Map<String, dynamic>> saveVvSentences({
    required String className,
    required List<String> sentences,
  }) async {
    try {
      if (await _client.rpc('is_school_admin') != true) {
        return {
          'result': 'error',
          'message':
              'Only the school administrator can change shared V.V. sentence defaults.'
        };
      }
      final schoolRef = await _schoolRef();
      final cls = await _classRow(className);
      final existing = await _client
          .from('class_result_settings')
          .select()
          .eq('class_id', cls['id'])
          .maybeSingle();
      final old = existing == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(existing);
      await _client.from('class_result_settings').upsert({
        ...old,
        'school_ref': schoolRef,
        'class_id': cls['id'],
        'vv_sentences': sentences,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'class_id,school_ref');
      return {'result': 'success'};
    } catch (e) {
      return {'result': 'error', 'message': '$e'};
    }
  }

  @override
  Future<Map<String, dynamic>> saveClassSubjects({
    required String className,
    required List<String> subjects,
  }) async {
    try {
      if (await _client.rpc('is_school_admin') != true) {
        return {
          'result': 'error',
          'message':
              'Only the school administrator can edit the class subject list.'
        };
      }
      final schoolRef = await _schoolRef();
      final cls = await _classRow(className);
      final classId = '${cls['id']}';
      final standard = '${cls['standard'] ?? ''}'.trim();
      final names = subjects
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      if (names.any((name) => name == 'વ્યક્તિત્વ વિકાસ')) {
        return {
          'result': 'error',
          'message':
              'વ્યક્તિત્વ વિકાસ સામાન્ય subject નથી; તે ફક્ત વર્ગશિક્ષકનું વર્તન મૂલ્યાંકન છે.'
        };
      }
      if (names.isNotEmpty && standard.isEmpty) {
        return {
          'result': 'error',
          'message':
              'Set the class Standard in Admin → Classes before configuring subjects.'
        };
      }
      final existingRows = await _client
          .from('class_subjects')
          .select('id,subject_name')
          .eq('class_id', classId);
      final existingNames =
          existingRows.map((e) => '${e['subject_name']}').toSet();
      for (var i = 0; i < names.length; i++) {
        await _client.from('school_subject_catalog').upsert({
          'school_ref': schoolRef,
          'standard': standard,
          'subject_name': names[i],
          'sort_order': i,
          'is_active': true,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'school_ref,standard,subject_name');
        await _client.from('class_subjects').upsert({
          'school_ref': schoolRef,
          'class_id': classId,
          'subject_name': names[i],
          'sort_order': i,
          'is_active': true,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'school_ref,class_id,subject_name');
      }
      for (final oldName in existingNames.difference(names.toSet())) {
        await _client
            .from('class_subjects')
            .update({'is_active': false})
            .eq('class_id', classId)
            .eq('subject_name', oldName);
      }
      return {'result': 'success'};
    } catch (e) {
      return {'result': 'error', 'message': '$e'};
    }
  }

  @override
  Future<Map<String, dynamic>> addNewStudent({
    required String className,
    required Map<String, dynamic> studentData,
  }) async {
    try {
      if (!await _isSchoolAdmin()) {
        return {
          'result': 'error',
          'message': 'Only the School Admin can add a student from Result.'
        };
      }
      final schoolRef = await _schoolRef();
      final cls = await _classRow(className);
      final roll = int.tryParse('${studentData['roll'] ?? ''}');
      final result = await _students.addStudent(
        classId: '${cls['id']}',
        rollNumber: roll,
        student: {
          'name': '${studentData['name'] ?? ''}'.trim(),
          'gr': '${studentData['gr'] ?? ''}',
          'dd': '${studentData['dd'] ?? ''}',
          'mm': '${studentData['mm'] ?? ''}',
          'yyyy': '${studentData['yyyy'] ?? ''}',
          'uid': '${studentData['uid'] ?? ''}',
          'pen': '${studentData['pen'] ?? ''}',
          'mobile': '${studentData['mobile'] ?? ''}',
          'father_name': '${studentData['fatherName'] ?? ''}',
          'mother_name': '${studentData['motherName'] ?? ''}',
          'address': '${studentData['address'] ?? ''}',
          'category': _categoryDb(studentData['category']),
          'gender': '${studentData['gender'] ?? ''}'.toUpperCase(),
          'is_divyang': _bool(studentData['isDivyang']),
        },
      );
      final id = '${result['id']}';
      // Write to the student master explicitly so Result and Student Management share one value.
      await _client
          .from('students')
          .update({
            'is_divyang': _bool(studentData['isDivyang']),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id)
          .eq('school_ref', schoolRef)
          .eq('class_id', '${cls['id']}');
      final year = await _academicYear('${cls['id']}');
      await _client.from('student_result_profiles').upsert({
        'school_ref': schoolRef,
        'class_id': cls['id'],
        'student_id': id,
        'academic_year': year,
        'studied_in_sem2': _bool(studentData['studiedInSem2']),
        'present_days_sem1': _int(studentData['presentDays']),
        'present_days_sem2': _int(studentData['presentDays2']),
        'standard': '${studentData['standard'] ?? cls['standard'] ?? ''}',
        'is_divyang': _bool(studentData['isDivyang']),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'school_ref,class_id,student_id,academic_year');
      return {'result': 'success', 'studentId': id};
    } catch (e) {
      return {'result': 'error', 'message': '$e'};
    }
  }

  @override
  Future<Map<String, dynamic>> saveSubjectMarks({
    required String className,
    required String sem,
    required String subject,
    String entryCombo = 'all_3',
    required List<Map<String, dynamic>> payload,
  }) async {
    try {
      final schoolRef = await _schoolRef();
      final cls = await _classRow(className);
      final classId = '${cls['id']}';
      final year = await _academicYear(classId);
      final adminUser = await _isSchoolAdmin();
      bool sem1Locked = false;
      bool sem2Locked = false;
      if (!adminUser &&
          subject != '__STUDENT_PROFILES__' &&
          subject != '__DELETE_STUDENT__') {
        final lockRow = await _client
            .from('class_result_settings')
            .select('sem1_locked,sem2_locked')
            .eq('class_id', classId)
            .maybeSingle();
        sem1Locked = lockRow?['sem1_locked'] == true;
        sem2Locked = lockRow?['sem2_locked'] == true;
        const vvSubject = '\u0AB5\u0ACD\u0AAF\u0A95\u0ACD\u0AA4\u0ABF\u0AA4\u0ACD\u0AB5 \u0AB5\u0ABF\u0A95\u0ABE\u0AB8';
        if (subject == vvSubject) {
          if (sem == '1' && sem1Locked) {
            return {
              'result': 'error',
              'message':
                  '\u{1F512} \u0AAA\u0ACD\u0AB0\u0AA5\u0AAE \u0AB8\u0AA4\u0ACD\u0AB0\u0AA8\u0AC1\u0A82 \u0AAA\u0AB0\u0ABF\u0AA3\u0ABE\u0AAE \u0AB2\u0ACB\u0A95 \u0A95\u0AB0\u0AC7\u0AB2 \u0A9B\u0AC7. Admin \u0A85\u0AA8\u0AB2\u0ACB\u0A95 \u0A95\u0AB0\u0AC7 \u0AAA\u0A9B\u0AC0 \u0A9C \u0AAA\u0ACD\u0AB0\u0AA5\u0AAE \u0AB8\u0AA4\u0ACD\u0AB0\u0AA8\u0ABE \u0A97\u0AC1\u0AA3 \u0AAC\u0AA6\u0AB2\u0AC0 \u0AB6\u0A95\u0ABE\u0AB6\u0AC7.',
            };
          }
          if (sem != '1' && sem2Locked) {
            return {
              'result': 'error',
              'message':
                  '\u{1F512} \u0AA6\u0ACD\u0AB5\u0ABF\u0AA4\u0AC0\u0AAF \u0AB8\u0AA4\u0ACD\u0AB0\u0AA8\u0AC1\u0A82 \u0AAA\u0AB0\u0ABF\u0AA3\u0ABE\u0AAE \u0AB2\u0ACB\u0A95 \u0A95\u0AB0\u0AC7\u0AB2 \u0A9B\u0AC7. Admin \u0A85\u0AA8\u0AB2\u0ACB\u0A95 \u0A95\u0AB0\u0AC7 \u0AAA\u0A9B\u0AC0 \u0A9C \u0AA6\u0ACD\u0AB5\u0ABF\u0AA4\u0AC0\u0AAF \u0AB8\u0AA4\u0ACD\u0AB0\u0AA8\u0ABE \u0A97\u0AC1\u0AA3 \u0AAC\u0AA6\u0AB2\u0AC0 \u0AB6\u0A95\u0ABE\u0AB6\u0AC7.',
            };
          }
        } else if (entryCombo == 'both_sem_all_6') {
          if (sem2Locked) {
            return {
              'result': 'error',
              'message':
                  '\u{1F512} \u0AA6\u0ACD\u0AB5\u0ABF\u0AA4\u0AC0\u0AAF \u0AB8\u0AA4\u0ACD\u0AB0\u0AA8\u0AC1\u0A82 \u0AAA\u0AB0\u0ABF\u0AA3\u0ABE\u0AAE \u0AB2\u0ACB\u0A95 \u0A95\u0AB0\u0AC7\u0AB2 \u0A9B\u0AC7. Admin \u0A85\u0AA8\u0AB2\u0ACB\u0A95 \u0A95\u0AB0\u0AC7 \u0AAA\u0A9B\u0AC0 \u0A9C \u0AA6\u0ACD\u0AB5\u0ABF\u0AA4\u0AC0\u0AAF \u0AB8\u0AA4\u0ACD\u0AB0\u0AA8\u0ABE \u0A97\u0AC1\u0AA3 \u0AAC\u0AA6\u0AB2\u0AC0 \u0AB6\u0A95\u0ABE\u0AB6\u0AC7.',
            };
          }
        } else {
          final targetSemCheck = sem == '1' ? 1 : 2;
          if ((targetSemCheck == 1 && sem1Locked) ||
              (targetSemCheck == 2 && sem2Locked)) {
            return {
              'result': 'error',
              'message': targetSemCheck == 1
                  ? '\u{1F512} \u0AAA\u0ACD\u0AB0\u0AA5\u0AAE \u0AB8\u0AA4\u0ACD\u0AB0\u0AA8\u0AC1\u0A82 \u0AAA\u0AB0\u0ABF\u0AA3\u0ABE\u0AAE \u0AB2\u0ACB\u0A95 \u0A95\u0AB0\u0AC7\u0AB2 \u0A9B\u0AC7. Admin \u0A85\u0AA8\u0AB2\u0ACB\u0A95 \u0A95\u0AB0\u0AC7 \u0AAA\u0A9B\u0AC0 \u0A9C \u0AAA\u0ACD\u0AB0\u0AA5\u0AAE \u0AB8\u0AA4\u0ACD\u0AB0\u0AA8\u0ABE \u0A97\u0AC1\u0AA3 \u0AAC\u0AA6\u0AB2\u0AC0 \u0AB6\u0A95\u0ABE\u0AB6\u0AC7.'
                  : '\u{1F512} \u0AA6\u0ACD\u0AB5\u0ABF\u0AA4\u0AC0\u0AAF \u0AB8\u0AA4\u0ACD\u0AB0\u0AA8\u0AC1\u0A82 \u0AAA\u0AB0\u0ABF\u0AA3\u0ABE\u0AAE \u0AB2\u0ACB\u0A95 \u0A95\u0AB0\u0AC7\u0AB2 \u0A9B\u0AC7. Admin \u0A85\u0AA8\u0AB2\u0ACB\u0A95 \u0A95\u0AB0\u0AC7 \u0AAA\u0A9B\u0AC0 \u0A9C \u0AA6\u0ACD\u0AB5\u0ABF\u0AA4\u0AC0\u0AAF \u0AB8\u0AA4\u0ACD\u0AB0\u0AA8\u0ABE \u0A97\u0AC1\u0AA3 \u0AAC\u0AA6\u0AB2\u0AC0 \u0AB6\u0A95\u0ABE\u0AB6\u0AC7.',
            };
          }
        }
      }
      if (subject == 'વ્યક્તિત્વ વિકાસ') {
        final teacherId = await _currentTeacherId();
        if (!adminUser &&
            (teacherId == null ||
                '${cls['class_teacher_id'] ?? ''}' != teacherId)) {
          return {
            'result': 'error',
            'message':
                'વ્યક્તિગત વિકાસ વિષય નથી. આ વર્તન મૂલ્યાંકન ફક્ત નિમણૂક કરેલા વર્ગશિક્ષક જ સેવ કરી શકે.'
          };
        }
      } else if (subject != '__STUDENT_PROFILES__' &&
          subject != '__DELETE_STUDENT__') {
        if (!await _isTeacherAssignedSubject(classId, subject)) {
          return {
            'result': 'error',
            'message':
                'આ વર્ગના આ વિષયમાં ગુણ ભરવાની મંજૂરી તમને ફાળવેલ નથી. Admin પાસે subject assignment સુધરાવો.'
          };
        }
      }
      if (subject == '__DELETE_STUDENT__') {
        if (!adminUser) {
          return {
            'result': 'error',
            'message':
                'વિદ્યાર્થીને Result roster માંથી દૂર કરવાનો અધિકાર માત્ર School Admin પાસે છે.'
          };
        }
      }
      if (subject == '__STUDENT_PROFILES__' && !adminUser) {
        return {
          'result': 'error',
          'message':
              'વિદ્યાર્થીની મૂળ વિગતો Student Management માંથી સુધારો; Resultમાંથી student-master data edit કરવાની મંજૂરી નથી.'
        };
      }

      // Enforce the roster prerequisite at the API layer as well as in the UI, so an
      // old/offline draft cannot rewrite marks before a semester roster is captured.
      if (subject != '__STUDENT_PROFILES__') {
        final requiredSemesters =
            entryCombo == 'both_sem_all_6' && subject != '__DELETE_STUDENT__'
                ? const [1, 2]
                : [sem == '1' ? 1 : 2];
        for (final requiredSemester in requiredSemesters) {
          final currentRoster = await _client
              .from('student_result_roster_snapshots')
              .select('id')
              .eq('school_ref', schoolRef)
              .eq('class_id', classId)
              .eq('academic_year', year)
              .eq('semester', requiredSemester)
              .eq('is_current', true)
              .maybeSingle();
          if (currentRoster == null) {
            return {
              'result': 'error',
              'message':
                  'Import the attendance-register roster for the required semester before saving Result data. No data was changed.',
            };
          }
        }
      }

      if (subject == '__DELETE_STUDENT__') {
        if (payload.isEmpty)
          return {'result': 'error', 'message': 'No student was selected.'};
        var id = '${payload.first['studentId'] ?? ''}'.trim();
        if (id.isEmpty && payload.first.containsKey('idx')) {
          final currentData = await getResultDataForSemester(className,
              rosterSemester: sem == '1' ? 1 : 2);
          final idx = _int(payload.first['idx']);
          if (idx >= 0 && idx < currentData.students.length)
            id = currentData.students[idx].studentId;
        }
        if (id.isEmpty)
          return {
            'result': 'error',
            'message':
                'Student identity is missing; reload the class and try again.'
          };
        final student = await _client
            .from('students')
            .select('id')
            .eq('id', id)
            .eq('school_ref', schoolRef)
            .eq('class_id', classId)
            .maybeSingle();
        if (student == null)
          return {
            'result': 'error',
            'message': 'The selected student does not belong to this class.'
          };
        final removedRaw = await _client
            .rpc('psm_admin_remove_result_roster_student', params: {
          'p_class_id': classId,
          'p_student_id': id,
        });
        if (removedRaw is Map) {
          final removed = Map<String, dynamic>.from(
              removedRaw.map((k, v) => MapEntry('$k', v)));
          if (removed['result'] != 'success')
            return {
              'result': 'error',
              'message': '${removed['message'] ?? removed}'
            };
        }
        return {'result': 'success'};
      }

      if (subject == '__STUDENT_PROFILES__') {
        final rosterSemester = sem == '1' ? 1 : 2;
        final currentRoster = await _client
            .from('student_result_roster_snapshots')
            .select('id')
            .eq('school_ref', schoolRef)
            .eq('class_id', classId)
            .eq('academic_year', year)
            .eq('semester', rosterSemester)
            .eq('is_current', true)
            .maybeSingle();
        if (currentRoster == null) {
          return {
            'result': 'error',
            'message':
                'Import the attendance-register roster for this semester before saving student details. No data was changed.',
          };
        }
        for (final row in payload) {
          if (row['isMeta'] == true) {
            if (await _client.rpc('is_school_admin') == true) {
              final existing = await _client
                  .from('class_result_settings')
                  .select()
                  .eq('class_id', classId)
                  .maybeSingle();
              final old = existing == null
                  ? <String, dynamic>{}
                  : Map<String, dynamic>.from(existing);
              await _client.from('class_result_settings').upsert({
                ...old,
                'school_ref': schoolRef,
                'class_id': classId,
                'result_date':
                    '${row['resultDate'] ?? old['result_date'] ?? '30/04/2027'}',
                'academic_year':
                    '${row['academicYear'] ?? old['academic_year'] ?? '2026 - 27'}',
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              }, onConflict: 'class_id,school_ref');
            }
            continue;
          }
          final id = await _resolveStudentId(classId, row);
          if (id == null) continue;
          final roll = int.tryParse('${row['roll'] ?? ''}');
          if (roll != null && roll > 0) {
            final oldRow = await _client
                .from('students')
                .select('roll_number')
                .eq('id', id)
                .maybeSingle();
            if (oldRow != null && '${oldRow['roll_number']}' != '$roll') {
              await _client.rpc('psm_change_student_roll', params: {
                'p_student_id': id,
                'p_new_roll': roll,
              });
            }
          }
          final studentChanges = <String, dynamic>{
            'name': '${row['name'] ?? ''}'.trim(),
            'gr': '${row['gr'] ?? ''}',
            'dd': '${row['dd'] ?? ''}',
            'mm': '${row['mm'] ?? ''}',
            'yyyy': '${row['yyyy'] ?? ''}',
            'uid': '${row['uid'] ?? ''}',
            'pen': '${row['pen'] ?? ''}',
            'mobile': '${row['mobile'] ?? ''}',
            'father_name': '${row['fatherName'] ?? ''}',
            'mother_name': '${row['motherName'] ?? ''}',
            'address': '${row['address'] ?? ''}',
            'caste': '${row['caste'] ?? ''}',
            'birth_place': '${row['birthPlace'] ?? ''}',
            'dob_words': '${row['dobWords'] ?? ''}',
            'last_school': '${row['lastSchool'] ?? ''}',
            'category': _categoryDb(row['category']),
            'gender': '${row['gender'] ?? 'UNSPECIFIED'}'.toUpperCase(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          };
          studentChanges['is_divyang'] =
              '${row['isDivyang'] ?? ''}'.toUpperCase() == 'YES' ||
                  _bool(row['isDivyang']);
          await _client
              .from('students')
              .update(studentChanges)
              .eq('id', id)
              .eq('school_ref', schoolRef)
              .eq('class_id', classId);
          await _client.from('student_result_profiles').upsert({
            'school_ref': schoolRef,
            'class_id': classId,
            'student_id': id,
            'academic_year': year,
            'present_days_sem1': _int(row['presentDays']),
            'present_days_sem2': _int(row['presentDays2']),
            'studied_in_sem2': _bool(row['studiedInSem2']),
            'standard': '${row['standard'] ?? cls['standard'] ?? ''}',
            'is_divyang': _bool(row['isDivyang']),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }, onConflict: 'school_ref,class_id,student_id,academic_year');
        }
        return {'result': 'success'};
      }

      if (subject == 'વ્યક્તિત્વ વિકાસ') {
        for (final row in payload) {
          final id = await _resolveStudentId(classId, row);
          if (id == null) continue;
          final profileRaw = await _client
              .from('student_result_profiles')
              .select()
              .eq('student_id', id)
              .eq('academic_year', year)
              .maybeSingle();
          final old = profileRaw == null
              ? <String, dynamic>{}
              : Map<String, dynamic>.from(profileRaw);
          final useSem2 = sem != '1';
          final keepLockedSem1Vv = !adminUser && useSem2 && sem1Locked;
          final vv1 = keepLockedSem1Vv
              ? _int(old['vv1'])
              : (row.containsKey('vv1')
                  ? _int(row['vv1'])
                  : (useSem2 ? _int(old['vv1']) : _int(row['vv'])));
          final vv2 = row.containsKey('vv2')
              ? _int(row['vv2'])
              : (useSem2 ? _int(row['vv']) : _int(old['vv2']));
          final sentenceMarks =
              row['sentences'] is List ? row['sentences'] : null;
          final sentenceMarks1 = keepLockedSem1Vv
              ? null
              : (row['sentences1'] is List ? row['sentences1'] : null);
          await _client.from('student_result_profiles').upsert({
            'school_ref': schoolRef,
            'class_id': classId,
            'student_id': id,
            'academic_year': year,
            'vv1': vv1,
            'vv2': vv2,
            'vv1_sentences': useSem2
                ? (sentenceMarks1 ??
                    old['vv1_sentences'] ??
                    List<int>.filled(40, 0))
                : (sentenceMarks ??
                    old['vv1_sentences'] ??
                    List<int>.filled(40, 0)),
            'vv2_sentences': useSem2
                ? (sentenceMarks ??
                    old['vv2_sentences'] ??
                    List<int>.filled(40, 0))
                : (old['vv2_sentences'] ?? List<int>.filled(40, 0)),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }, onConflict: 'school_ref,class_id,student_id,academic_year');
        }
        return {'result': 'success'};
      }

      final bothSems = entryCombo == 'both_sem_all_6';
      final writes = <Map<String, dynamic>>[];
      for (final row in payload) {
        final id = await _resolveStudentId(classId, row);
        if (id == null) continue;
        if (bothSems) {
          for (final targetSem in [1, 2]) {
            if (!adminUser && targetSem == 1 && sem1Locked) continue;
            if (targetSem == 2) {
              final p = await _client
                  .from('student_result_profiles')
                  .select('studied_in_sem2')
                  .eq('student_id', id)
                  .eq('academic_year', year)
                  .maybeSingle();
              if (p != null && p['studied_in_sem2'] == false) continue;
            }
            writes.add(
                _markRow(schoolRef, classId, id, year, targetSem, subject, {
              'a': row[targetSem == 1 ? 'a1' : 'a2'],
              's': row[targetSem == 1 ? 's1' : 's2'],
              'sw': row[targetSem == 1 ? 'sw1' : 'sw2'],
              'satrantAbsent': row[targetSem == 1
                      ? 'satrantAbsent1'
                      : 'satrantAbsent2'] ==
                  true,
              'directTotal': targetSem == 1 ? row['directTotal1'] : null,
              'directMode': targetSem == 1 &&
                  (row['directMode1'] == true || row['directTotal1'] != null),
            }));
          }
        } else {
          final targetSem = sem == '1' ? 1 : 2;
          if (targetSem == 2) {
            final p = await _client
                .from('student_result_profiles')
                .select('studied_in_sem2')
                .eq('student_id', id)
                .eq('academic_year', year)
                .maybeSingle();
            if (p != null && p['studied_in_sem2'] == false) continue;
          }
          writes
              .add(_markRow(schoolRef, classId, id, year, targetSem, subject, {
            'a': row['a'],
            's': row['s'],
            'sw': row['sw'],
            'satrantAbsent': row['satrantAbsent'] == true,
            // Semester-1 direct-total mode is supported in both the normal Semester-1
            // save path and the combined Semester-2 entry path.
            'directTotal': row['directTotal'],
            'directMode':
                row['directMode'] == true || row['directTotal'] != null,
          }));
        }
      }
      if (writes.isNotEmpty) {
        await _client.from('student_subject_marks').upsert(
              writes,
              onConflict:
                  'school_ref,class_id,student_id,academic_year,semester,subject_name',
            );
      }
      return {'result': 'success'};
    } catch (e) {
      return {'result': 'error', 'message': '$e'};
    }
  }

  Map<String, dynamic> _markRow(
    String schoolRef,
    String classId,
    String studentId,
    String year,
    int semester,
    String subject,
    Map<String, dynamic> values,
  ) =>
      {
        'school_ref': schoolRef,
        'class_id': classId,
        'student_id': studentId,
        'academic_year': year,
        'semester': semester,
        'subject_name': subject,
        'patrak_a': _int(values['a']).clamp(0, 40),
        'satrant': values['satrantAbsent'] == true
            ? 0
            : _int(values['s']).clamp(0, 40),
        'satrant_absent': values['satrantAbsent'] == true ||
            '${values["s"] ?? ""}'.trim().toUpperCase() == 'AB',
        'swa_adhyayan': _int(values['sw']).clamp(0, 20),
        'direct_total': values['directTotal'] == null
            ? null
            : _int(values['directTotal']).clamp(0, 100),
        'direct_total_mode':
            values['directMode'] == true || values['directTotal'] != null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  Future<String?> _resolveStudentId(
      String classId, Map<String, dynamic> item) async {
    final supplied = '${item['studentId'] ?? ''}'.trim();
    if (supplied.isNotEmpty) {
      final verified = await _client
          .from('students')
          .select('id')
          .eq('id', supplied)
          .eq('class_id', classId)
          .maybeSingle();
      return verified == null ? null : '${verified['id']}';
    }
    final roster = await _activeRoster(classId);
    final idx = item.containsKey('idx')
        ? _int(item['idx'])
        : _int(item['sheetRow']) - 2;
    if (idx >= 0 && idx < roster.length) return '${roster[idx]['id']}';
    return null;
  }

  Future<String> _academicYear(String classId) async {
    final settings = await _client
        .from('class_result_settings')
        .select('academic_year')
        .eq('class_id', classId)
        .maybeSingle();
    return '${settings?['academic_year'] ?? '2026 - 27'}';
  }

  /// Returns every active class in the school with its Sem 1 & Sem 2 lock status.
  /// Uses cached school-scoped queries to keep Firebase reads minimal.
  Future<List<Map<String, dynamic>>> getSchoolResultLockStatus() async {
    final schoolRef = await _schoolRef();
    final classRows = await _client
        .from('school_classes')
        .select()
        .eq('school_ref', schoolRef);
    final settingsRows = await _client
        .from('class_result_settings')
        .select('class_id,sem1_locked,sem2_locked,updated_at')
        .eq('school_ref', schoolRef);

    final settingsByClassId = <String, Map<String, dynamic>>{};
    for (final raw in settingsRows) {
      final row = Map<String, dynamic>.from(raw);
      final cid = '${row['class_id'] ?? ''}'.trim();
      if (cid.isNotEmpty) settingsByClassId[cid] = row;
    }

    final items = <Map<String, dynamic>>[];
    for (final raw in classRows) {
      final row = Map<String, dynamic>.from(raw);
      if (row['is_active'] == false) continue;
      final cid = '${row['id'] ?? ''}'.trim();
      if (cid.isEmpty) continue;
      final classKey =
          '${row['class_key'] ?? row['key'] ?? row['class_name'] ?? ''}'.trim();
      final rawLabel =
          '${row['display_label'] ?? row['label'] ?? row['class_name'] ?? ''}'
              .trim();
      final displayLabel = rawLabel.isNotEmpty
          ? rawLabel
          : classKey.replaceAll('_', ' ');
      final st = settingsByClassId[cid];
      items.add(<String, dynamic>{
        'classId': cid,
        'classKey': classKey,
        'displayLabel': displayLabel.isNotEmpty ? displayLabel : classKey,
        'sortOrder': _int(row['sort_order']),
        'sem1Locked': st?['sem1_locked'] == true,
        'sem2Locked': st?['sem2_locked'] == true,
        'updatedAt': '${st?['updated_at'] ?? ''}'.trim(),
      });
    }
    items.sort((a, b) {
      final bySort = _int(a['sortOrder']).compareTo(_int(b['sortOrder']));
      if (bySort != 0) return bySort;
      return '${a['displayLabel']}'.compareTo('${b['displayLabel']}');
    });
    return items;
  }

  /// Admin-only semester-wise Result Lock / Unlock.
  /// - [classId] == null: applies to the whole school (skips unchanged classes to cut Firestore writes).
  /// - [classId] != null: applies to that single class only (1 Firestore write).
  Future<Map<String, dynamic>> setSchoolResultLock({
    required int semester,
    required bool isLocked,
    String? classId,
  }) async {
    try {
      if (!await _isSchoolAdmin()) {
        return {
          'result': 'error',
          'message':
              '\u0AAA\u0AB0\u0ABF\u0AA3\u0ABE\u0AAE \u0AB2\u0ACB\u0A95/\u0A85\u0AA8\u0AB2\u0ACB\u0A95 \u0A95\u0AB0\u0AB5\u0ABE\u0AA8\u0ACB \u0A85\u0AA7\u0ABF\u0A95\u0ABE\u0AB0 \u0AAE\u0ABE\u0AA4\u0ACD\u0AB0 School Admin \u0AAA\u0ABE\u0AB8\u0AC7 \u0A9B\u0AC7.',
        };
      }
      if (semester != 1 && semester != 2) {
        return {'result': 'error', 'message': 'Semester must be 1 or 2.'};
      }
      final schoolRef = await _schoolRef();
      final lockField = semester == 1 ? 'sem1_locked' : 'sem2_locked';
      final nowIso = DateTime.now().toUtc().toIso8601String();

      final targetIds = <String>{};
      final singleId = (classId ?? '').trim();
      if (singleId.isNotEmpty) {
        targetIds.add(singleId);
      } else {
        final classRows = await _client
            .from('school_classes')
            .select('id,is_active')
            .eq('school_ref', schoolRef);
        for (final raw in classRows) {
          if (raw['is_active'] == false) continue;
          final cid = '${raw['id'] ?? ''}'.trim();
          if (cid.isNotEmpty) targetIds.add(cid);
        }
      }
      if (targetIds.isEmpty) {
        return {'result': 'error', 'message': 'No active classes found.'};
      }

      final existingByClassId = <String, Map<String, dynamic>>{};
      if (singleId.isNotEmpty) {
        final row = await _client
            .from('class_result_settings')
            .select()
            .eq('class_id', singleId)
            .maybeSingle();
        if (row != null) existingByClassId[singleId] = Map<String, dynamic>.from(row);
      } else {
        final rows = await _client
            .from('class_result_settings')
            .select()
            .eq('school_ref', schoolRef);
        for (final raw in rows) {
          final map = Map<String, dynamic>.from(raw);
          final cid = '${map['class_id'] ?? ''}'.trim();
          if (cid.isNotEmpty) existingByClassId[cid] = map;
        }
      }

      var updatedCount = 0;
      for (final cid in targetIds) {
        final old = existingByClassId[cid] ?? <String, dynamic>{};
        final already = old[lockField] == true;
        if (already == isLocked && old.containsKey(lockField)) {
          continue; // Skip unchanged classes to minimize Firestore write cost
        }
        await _client.from('class_result_settings').upsert(<String, dynamic>{
          ...old,
          'school_ref': schoolRef,
          'class_id': cid,
          lockField: isLocked,
          'updated_at': nowIso,
        }, onConflict: 'class_id,school_ref');
        updatedCount++;
      }

      return {
        'result': 'success',
        'semester': semester,
        'isLocked': isLocked,
        'updatedCount': updatedCount,
        'totalClasses': targetIds.length,
      };
    } catch (error) {
      return {'result': 'error', 'message': '$error'};
    }
  }

  @override
  Future<Map<String, dynamic>> exportResultPdf({
    required String className,
    required String sem,
    required String pdfType,
    bool showParinam = true,
    String parinamMode = 'auto',
  }) async {
    // PDFs are rendered by ResultShell's existing Flutter PDF renderer. Never route to GAS.
    return {'result': 'supabase_local_pdf'};
  }
}

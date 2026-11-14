import 'package:pmshri_attendance/services/attendance_lifecycle.dart';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pmshri_attendance/services/firebase_backend_client.dart';
import 'school_type.dart';
import 'package:pmshri_attendance/services/class_label.dart';

/// Hajari Patrak is isolated from the DATEWISE/Daily report configuration.
/// It reads a selected month's roster and always prints blank daily cells.
class SupabaseHajariPatrakService {
  SupabaseHajariPatrakService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const List<String> monthNamesGujarati = <String>[
    'જાન્યુઆરી', 'ફેબ્રુઆરી', 'માર્ચ', 'એપ્રિલ', 'મે', 'જૂન',
    'જુલાઈ', 'ઓગસ્ટ', 'સપ્ટેમ્બર', 'ઓક્ટોબર', 'નવેમ્બર', 'ડિસેમ્બર',
  ];

  static const List<String> _weekdaysGujarati = <String>[
    'સોમ', 'મંગળ', 'બુધ', 'ગુરુ', 'શુક્ર', 'શનિ', 'રવિ',
  ];

  static const List<String> _categories = <String>['SC', 'ST', 'OBC', 'OTHER'];
  static const List<String> _categoryGujarati = <String>[
    'અ.જા.', 'અ.જ.જા.', 'બ.પં.', 'અન્ય',
  ];

  String _text(dynamic value) => (value ?? '').toString().trim();

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) return value.map((key, value) => MapEntry('$key', value));
    return <String, dynamic>{};
  }

  int _int(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(_text(value)) ?? 0;
  }

  Future<String> currentSchoolRef() async {
    if (_client.auth.currentUser == null) throw StateError('Please sign in again.');
    final ref = _text(await _client.rpc('current_school_ref'));
    if (ref.isEmpty) throw StateError('This login has no active school.');
    return ref;
  }

  Future<Map<String, dynamic>> getSchoolMetadata() async {
    final value = await _client.rpc('hajari_patrak_school_meta');
    return _map(value);
  }

  Future<List<Map<String, dynamic>>> getClasses() async {
    final schoolRef = await currentSchoolRef();
    final rows = await _client
        .from('school_classes')
        .select('id,school_ref,class_key,label,sheet_name,standard,section,report_group,sort_order,class_teacher_id,is_active')
        .eq('school_ref', schoolRef)
        .eq('is_active', true)
        .order('sort_order')
        .order('label');
    final classes = rows.map((row) => Map<String, dynamic>.from(row)).toList();
    classes.sort(_compareClassesAscending);
    return classes;
  }

  int _classStandardRank(Map<String, dynamic> row) {
    final raw = <String>[
      _text(row['standard']),
      _text(row['label']),
      _text(row['class_key']),
      _text(row['sheet_name']),
    ].where((value) => value.isNotEmpty).join(' ').toLowerCase();
    if (raw.contains('balvatika') || raw.contains('બાલવાટિકા') || raw.contains('બાલવાટીકા')) return 0;
    final match = RegExp(r'(?:std(?:andard)?\s*)?(\d{1,2})').firstMatch(raw);
    return match == null ? 99 : (int.tryParse(match.group(1)!) ?? 99);
  }

  String _classSectionKey(Map<String, dynamic> row) {
    final explicit = _text(row['section']);
    if (explicit.isNotEmpty) return explicit.toLowerCase();
    final raw = _text(row['label']).isNotEmpty ? _text(row['label']) : _text(row['class_key']);
    final match = RegExp(r'\d+\s*[-–/]\s*(.+)$').firstMatch(raw);
    return (match?.group(1) ?? '').trim().toLowerCase();
  }

  int _sectionRank(String value) {
    final text = value.trim().toLowerCase();
    if (text.isEmpty) return -1;
    if (text.length == 1 && RegExp(r'[a-z]').hasMatch(text)) return text.codeUnitAt(0) - 97;
    const gujaratiSections = <String>[
      'અ', 'આ', 'ઇ', 'ઈ', 'ઉ', 'ઊ', 'ઋ', 'એ', 'ઐ', 'ઓ', 'ઔ',
      'ક', 'ખ', 'ગ', 'ઘ', 'ઙ', 'ચ', 'છ', 'જ', 'ઝ', 'ઞ', 'ટ', 'ઠ',
      'ડ', 'ઢ', 'ણ', 'ત', 'થ', 'દ', 'ધ', 'ન', 'પ', 'ફ', 'બ', 'ભ', 'મ', 'ય', 'ર', 'લ', 'વ', 'શ', 'ષ', 'સ', 'હ',
    ];
    for (var i = 0; i < gujaratiSections.length; i++) {
      if (text.startsWith(gujaratiSections[i])) return i;
    }
    return 1000;
  }

  int _compareClassesAscending(Map<String, dynamic> a, Map<String, dynamic> b) {
    final standard = _classStandardRank(a).compareTo(_classStandardRank(b));
    if (standard != 0) return standard;
    final sectionA = _classSectionKey(a);
    final sectionB = _classSectionKey(b);
    final sectionRank = _sectionRank(sectionA).compareTo(_sectionRank(sectionB));
    if (sectionRank != 0) return sectionRank;
    final sectionText = sectionA.compareTo(sectionB);
    if (sectionText != 0) return sectionText;
    return _text(a['label']).compareTo(_text(b['label']));
  }

  Future<List<Map<String, dynamic>>> getTeachers() async {
    final value = await _client.rpc('hajari_patrak_teacher_directory');
    if (value is! List) return <Map<String, dynamic>>[];
    return value.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<bool> isCurrentUserAdmin() async {
    final value = await _client.rpc('is_school_admin');
    return value == true || const <String>{'true', 't', '1'}.contains(_text(value).toLowerCase());
  }

  Future<Map<String, dynamic>> getClassSettings(String classId) async {
    final schoolRef = await currentSchoolRef();
    final row = await _client
        .from('school_hajari_patrak_settings')
        .select('row_height,font_size,blank_rows,print_mode')
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .maybeSingle();
    return row == null ? <String, dynamic>{} : Map<String, dynamic>.from(row);
  }

  Future<void> saveClassSettings({
    required String classId,
    required int rowHeight,
    required int fontSize,
    required int blankRows,
    required String printMode,
  }) async {
    final schoolRef = await currentSchoolRef();
    await _client.from('school_hajari_patrak_settings').upsert(
      <String, dynamic>{
        'school_ref': schoolRef,
        'class_id': classId,
        'row_height': rowHeight,
        'font_size': fontSize,
        'blank_rows': blankRows,
        'print_mode': printMode,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'school_ref,class_id',
    );
  }

  Future<void> saveOfficialClassTeacher({
    required String classId,
    required String? teacherId,
  }) async {
    await _client.rpc('hajari_patrak_set_class_teacher', params: <String, dynamic>{
      'p_class_id': classId,
      'p_teacher_id': teacherId,
    });
  }

  Future<Map<String, dynamic>> getMonthData({
    required String classId,
    required int year,
    required int month,
  }) async {
    final schoolRef = await currentSchoolRef();
    final first = DateTime(year, month, 1);
    final last = DateTime(year, month + 1, 0);
    final firstIso = _iso(first);
    final lastIso = _iso(last);

    // Include inactive student rows and section-transferred student rows so a
    // past-month reprint reflects both the student's real entry/exit period and
    // their section before/after any mid-year section change (e.g., if changed
    // during March, up to March prints in old section A; from April in new section B).
    final queryResults = await Future.wait<dynamic>([
      _client
          .from('students')
          .select('id,class_id,roll_number,previous_roll_number,gr,dd,mm,yyyy,name,caste,category,gender,enroll_school,enroll_class,custom_fields,section_history,is_active,created_at,updated_at,leaving_date')
          .eq('school_ref', schoolRef)
          .order('roll_number'),
      _client
          .from('attendance_days')
          .select('id,attendance_date,attendance_mode,student_details_saved,registered_counts,present_counts,mdm_counts,breakfast_total')
          .eq('school_ref', schoolRef)
          .eq('class_id', classId)
          .gte('attendance_date', firstIso)
          .lte('attendance_date', lastIso)
          .order('attendance_date'),
      _client
          .from('school_holidays')
          .select('holiday_date,reason')
          .eq('school_ref', schoolRef)
          .gte('holiday_date', firstIso)
          .lte('holiday_date', lastIso),
    ]);
    final rawStudents = queryResults[0] as List;
    final rawAttendance = queryResults[1] as List;
    final rawHolidays = queryResults[2] as List;

    final studentsAll = rawStudents
        .map((row) => Map<String, dynamic>.from(row))
        .where((student) => _effectiveClassIdForRegisterMonth(student, first) == classId)
        .toList();
    final roster = studentsAll
        .where((student) => _belongsToMonth(student, first, last))
        .map((student) {
          final copy = Map<String, dynamic>.from(student);
          final histRoll = _historicalRollForRegisterMonth(copy, first, classId);
          if (histRoll.isNotEmpty) {
            copy['roll_number'] = histRoll;
          }
          return copy;
        })
        .toList();
    roster.sort((a, b) {
      final ar = _text(a['roll_number']).isNotEmpty
          ? _text(a['roll_number'])
          : _text(a['previous_roll_number']);
      final br = _text(b['roll_number']).isNotEmpty
          ? _text(b['roll_number'])
          : _text(b['previous_roll_number']);
      final an = int.tryParse(ar);
      final bn = int.tryParse(br);
      if (an != null && bn != null && an != bn) return an.compareTo(bn);
      if (an != null && bn == null) return -1;
      if (an == null && bn != null) return 1;
      return _text(a['name']).compareTo(_text(b['name']));
    });
    // Ensure roll numbers always start at 1 and continue 1..N without gaps
    for (var i = 0; i < roster.length; i++) {
      roster[i]['roll_number'] = '${i + 1}';
    }

    final holidays = <String>{
      for (final row in rawHolidays) _text(row['holiday_date']),
    };
    final attendance = rawAttendance.map((row) => Map<String, dynamic>.from(row)).toList();

    // Load student-wise daily marks (present, mdm, breakfast) for Admin Recorded Hajari Patrak PDF/Excel
    final dayNumByDayId = <String, int>{};
    final recordedDays = <int>{};
    for (final row in attendance) {
      final did = _text(row['id']);
      final dt = _parseDate(row['attendance_date']);
      if (did.isEmpty || dt == null) continue;
      final mode = _text(row['attendance_mode']).toLowerCase();
      final saved = row['student_details_saved'] == true ||
          const <String>{'true', 't', '1'}
              .contains(_text(row['student_details_saved']).toLowerCase());
      if (mode == 'student' || saved) {
        dayNumByDayId[did] = dt.day;
        recordedDays.add(dt.day);
      } else {
        dayNumByDayId[did] = dt.day;
      }
    }

    final studentDailyMarks = <String, Map<int, Map<String, bool>>>{};
    if (dayNumByDayId.isNotEmpty) {
      try {
        final dayIds = dayNumByDayId.keys.toList();
        final marks = await _client
            .from('student_attendance')
            .select('student_id,attendance_day_id,present,mdm,breakfast')
            .eq('school_ref', schoolRef)
            .inFilter('attendance_day_id', dayIds);
        for (final rawMark in marks) {
          final m = Map<String, dynamic>.from(rawMark);
          final sid = _text(m['student_id']);
          final did = _text(m['attendance_day_id']);
          final dayNum = dayNumByDayId[did];
          if (sid.isEmpty || dayNum == null) continue;
          recordedDays.add(dayNum);
          final isPres = m['present'] == true ||
              const <String>{'true', 't', '1'}
                  .contains(_text(m['present']).toLowerCase());
          final isMdm = isPres &&
              (m['mdm'] == true ||
                  const <String>{'true', 't', '1'}
                      .contains(_text(m['mdm']).toLowerCase()));
          final isBf = isPres &&
              (m['breakfast'] == true ||
                  const <String>{'true', 't', '1'}
                      .contains(_text(m['breakfast']).toLowerCase()));
          final byDay = studentDailyMarks.putIfAbsent(
            sid,
            () => <int, Map<String, bool>>{},
          );
          byDay[dayNum] = <String, bool>{
            'present': isPres,
            'mdm': isMdm,
            'breakfast': isBf,
          };
        }
      } catch (_) {}
    }

    return <String, dynamic>{
      'students': roster,
      // Students who joined during this month: not on the pre-printed
      // register, but they have recorded attendance, so the recorded
      // register lists them (after the regular roster).
      'mid_month_joiners': studentsAll.where((student) {
        final enrolled = AttendanceLifecycle.parseEnrollmentDate(student);
        return enrolled != null &&
            enrolled.year == first.year &&
            enrolled.month == first.month;
      }).map((student) => Map<String, dynamic>.from(student)).toList(),
      'attendance': attendance,
      'holidays': holidays,
      'student_daily_marks': studentDailyMarks,
      'recorded_days': recordedDays,
      'source_student_count': studentsAll.length,
      'missing_enrollment_date_count': studentsAll.where((student) => _parseDate(student['enroll_school']) == null).length,
      'first_date': firstIso,
      'last_date': lastIso,
    };
  }

  /// Calculates the previous-month present-days column for the June-May academic year.
  /// Any month after a student's last saved/manual baseline that contains Direct Entry
  /// (or no saved attendance days) is treated as incomplete and returns blank for that
  /// student until the teacher supplies an explicit value.
  Future<Map<String, dynamic>> getAcademicYearPresentDays({
    required String classId,
    required int year,
    required int month,
    required List<Map<String, dynamic>> students,
  }) async {
    final schoolRef = await currentSchoolRef();
    final academicYearStart = month >= 6 ? year : year - 1;
    final academicStart = DateTime(academicYearStart, 6, 1);
    final cutoff = DateTime(year, month, 0); // last day before the selected month
    final cutoffIso = _iso(cutoff);
    final blankResult = <String, dynamic>{
      'academic_year_start': academicYearStart,
      'through_date': cutoffIso,
      'no_prior_months': cutoff.isBefore(academicStart),
      'is_complete': true,
      'days_by_student_id': <String, int>{},
      'incomplete_months': <String>[],
    };
    if (cutoff.isBefore(academicStart) || students.isEmpty) return blankResult;

    final rawOverrides = await _client
        .from('hajari_student_present_day_overrides')
        .select('student_id,through_date,present_days')
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .eq('academic_year_start', academicYearStart)
        .gte('through_date', _iso(academicStart))
        .lte('through_date', cutoffIso)
        .order('through_date');
    final overrides = rawOverrides.map((row) => Map<String, dynamic>.from(row)).toList();
    final exactOverrides = <String, int>{};
    final latestBefore = <String, Map<String, dynamic>>{};
    for (final row in overrides) {
      final studentId = _text(row['student_id']);
      final through = _text(row['through_date']).substring(0, 10);
      final count = _int(row['present_days']);
      if (studentId.isEmpty) continue;
      if (through == cutoffIso) {
        exactOverrides[studentId] = count;
      } else if (through.compareTo(cutoffIso) < 0) {
        latestBefore[studentId] = row; // rows are ordered ascending; last row wins
      }
    }

    final sectionClassIds = <String>{
      classId,
      for (final st in students) ..._extractSectionHistoryClassIds(st),
    };
    final rawDays = await _client
        .from('attendance_days')
        .select('id,class_id,attendance_date,attendance_mode,student_details_saved')
        .eq('school_ref', schoolRef)
        .inFilter('class_id', sectionClassIds.toList())
        .gte('attendance_date', _iso(academicStart))
        .lte('attendance_date', cutoffIso)
        .order('attendance_date');
    final daysById = <String, Map<String, dynamic>>{};
    final daysByMonth = <String, List<Map<String, dynamic>>>{};
    final studentwiseDayIds = <String>[];
    for (final item in rawDays) {
      final row = Map<String, dynamic>.from(item);
      final id = _text(row['id']);
      final date = _parseDate(row['attendance_date']);
      if (id.isEmpty || date == null) continue;
      final mode = _text(row['attendance_mode']).toLowerCase();
      final detailsSaved = row['student_details_saved'] == true ||
          const <String>{'true', 't', '1'}.contains(_text(row['student_details_saved']).toLowerCase());
      final studentwise = mode == 'student' && detailsSaved;
      final normalized = <String, dynamic>{
        'id': id,
        'date': date,
        'date_iso': _iso(date),
        'studentwise': studentwise,
      };
      daysById[id] = normalized;
      final monthKey = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
      (daysByMonth[monthKey] ??= <Map<String, dynamic>>[]).add(normalized);
      if (studentwise) studentwiseDayIds.add(id);
    }

    // Supabase REST returns at most 1,000 rows per response by default. Fetch
    // attendance marks in small day-ID batches and paginate each batch safely.
    final marks = <Map<String, dynamic>>[];
    for (var offset = 0; offset < studentwiseDayIds.length; offset += 60) {
      final ids = studentwiseDayIds.skip(offset).take(60).toList();
      var pageStart = 0;
      while (true) {
        final page = await _client
            .from('student_attendance')
            .select('student_id,attendance_day_id,present')
            .eq('school_ref', schoolRef)
            .inFilter('attendance_day_id', ids)
            .range(pageStart, pageStart + 999);
        final pageRows = page.map((row) => Map<String, dynamic>.from(row)).toList();
        marks.addAll(pageRows);
        if (pageRows.length < 1000) break;
        pageStart += 1000;
      }
    }
    final presentByStudentAndDate = <String, Map<String, int>>{};
    for (final mark in marks) {
      final present = mark['present'] == true ||
          const <String>{'true', 't', '1'}.contains(_text(mark['present']).toLowerCase());
      if (!present) continue;
      final studentId = _text(mark['student_id']);
      final dayId = _text(mark['attendance_day_id']);
      final day = daysById[dayId];
      if (studentId.isEmpty || day == null) continue;
      final dateIso = _text(day['date_iso']);
      final counts = presentByStudentAndDate.putIfAbsent(studentId, () => <String, int>{});
      counts[dateIso] = (counts[dateIso] ?? 0) + 1;
    }

    final autoDays = <String, int>{};
    final incompleteMonths = <String>{};
    var anyIncomplete = false;
    for (final student in students) {
      final studentId = _text(student['id']);
      if (studentId.isEmpty) {
        anyIncomplete = true;
        continue;
      }
      final exact = exactOverrides[studentId];
      if (exact != null) {
        autoDays[studentId] = exact;
        continue;
      }

      final baseline = latestBefore[studentId];
      final baselineDate = baseline == null
          ? DateTime(academicStart.year, academicStart.month, 0)
          : (_parseDate(baseline['through_date']) ?? DateTime(academicStart.year, academicStart.month, 0));
      final baselineDays = baseline == null ? 0 : _int(baseline['present_days']);
      final enrolled = _effectiveEnrollmentDate(student);
      var firstDateToCheck = baselineDate.add(const Duration(days: 1));
      if (firstDateToCheck.isBefore(academicStart)) firstDateToCheck = academicStart;
      if (firstDateToCheck.isBefore(enrolled)) firstDateToCheck = enrolled;
      if (firstDateToCheck.isAfter(cutoff)) {
        autoDays[studentId] = baselineDays;
        continue;
      }

      var monthCursor = DateTime(firstDateToCheck.year, firstDateToCheck.month, 1);
      var studentIncomplete = false;
      while (!monthCursor.isAfter(DateTime(cutoff.year, cutoff.month, 1))) {
        final monthKey = '${monthCursor.year.toString().padLeft(4, '0')}-${monthCursor.month.toString().padLeft(2, '0')}';
        final monthDays = daysByMonth[monthKey] ?? <Map<String, dynamic>>[];
        final relevantDays = monthDays.where((day) {
          final date = day['date'] as DateTime;
          return !date.isBefore(firstDateToCheck) && !date.isAfter(cutoff);
        }).toList();
        final hasNoRecordedDay = relevantDays.isEmpty;
        final hasDirectOrMissingDetails = relevantDays.any((day) => day['studentwise'] != true);
        if (hasNoRecordedDay || hasDirectOrMissingDetails) {
          studentIncomplete = true;
          incompleteMonths.add('${monthNamesGujarati[monthCursor.month - 1]} ${monthCursor.year}');
        }
        monthCursor = DateTime(monthCursor.year, monthCursor.month + 1, 1);
      }
      if (studentIncomplete) {
        anyIncomplete = true;
        continue;
      }

      var count = baselineDays;
      final studentMarks = presentByStudentAndDate[studentId] ?? <String, int>{};
      for (final entry in studentMarks.entries) {
        final date = _parseDate(entry.key);
        if (date != null && date.isAfter(baselineDate) && !date.isBefore(firstDateToCheck) && !date.isAfter(cutoff)) {
          count += entry.value;
        }
      }
      autoDays[studentId] = count;
    }

    return <String, dynamic>{
      'academic_year_start': academicYearStart,
      'through_date': cutoffIso,
      'no_prior_months': false,
      'is_complete': !anyIncomplete,
      'days_by_student_id': autoDays,
      'incomplete_months': incompleteMonths.toList(),
    };
  }

  Future<void> saveAcademicYearPresentDays({
    required String classId,
    required int academicYearStart,
    required String throughDate,
    required List<Map<String, dynamic>> values,
  }) async {
    if (values.isEmpty) return;
    await _client.rpc('hajari_patrak_save_present_days', params: <String, dynamic>{
      'p_class_id': classId,
      'p_academic_year_start': academicYearStart,
      'p_through_date': throughDate,
      'p_values': values,
    });
  }

  /// Fetches student-wise present days for LC or Result printing over [fromDate]..[throughDate].
  /// Combines student-wise attendance records (and any saved Hajari Patrak overrides) with
  /// explicitly inserted student present_days; leaves students blank when neither is available.
  Future<Map<String, dynamic>> getPresentDaysForDateRange({
    required String classId,
    required DateTime fromDate,
    required DateTime throughDate,
    required List<Map<String, dynamic>> students,
    bool includeAcademicYearOverrides = true,
  }) async {
    final schoolRef = await currentSchoolRef();
    final startIso = _iso(fromDate);
    final cutoffIso = _iso(throughDate);
    final autoDays = <String, int>{};
    if (throughDate.isBefore(fromDate) || students.isEmpty) {
      return <String, dynamic>{
        'days_by_student_id': autoDays,
        'is_complete': false,
        'studentwise_days_count': 0,
        'direct_days_count': 0,
        'incomplete_months': <String>[],
      };
    }

    final academicYearStart =
        fromDate.month >= 6 ? fromDate.year : fromDate.year - 1;
    final exactOverrides = <String, int>{};
    final latestBefore = <String, Map<String, dynamic>>{};
    if (includeAcademicYearOverrides) {
      try {
        final rawOverrides = await _client
            .from('hajari_student_present_day_overrides')
            .select('student_id,through_date,present_days')
            .eq('school_ref', schoolRef)
            .eq('class_id', classId)
            .eq('academic_year_start', academicYearStart)
            .gte('through_date', startIso)
            .lte('through_date', cutoffIso)
            .order('through_date');
        for (final raw in rawOverrides) {
          final row = Map<String, dynamic>.from(raw);
          final sid = _text(row['student_id']);
          final through = _text(row['through_date']);
          final throughShort =
              through.length >= 10 ? through.substring(0, 10) : through;
          final count = _int(row['present_days']);
          if (sid.isEmpty || count <= 0) continue;
          if (throughShort == cutoffIso) {
            exactOverrides[sid] = count;
          } else if (throughShort.compareTo(cutoffIso) < 0) {
            latestBefore[sid] = row;
          }
        }
      } catch (_) {}
    }

    final rangeSectionClassIds = <String>{
      classId,
      for (final st in students) ..._extractSectionHistoryClassIds(st),
    };
    final rawDays = await _client
        .from('attendance_days')
        .select('id,class_id,attendance_date,attendance_mode,student_details_saved')
        .eq('school_ref', schoolRef)
        .inFilter('class_id', rangeSectionClassIds.toList())
        .gte('attendance_date', startIso)
        .lte('attendance_date', cutoffIso)
        .order('attendance_date');
    final daysById = <String, Map<String, dynamic>>{};
    final studentwiseDayIds = <String>[];
    var directDaysCount = 0;
    final incompleteMonths = <String>{};
    for (final item in rawDays) {
      final row = Map<String, dynamic>.from(item);
      final id = _text(row['id']);
      final date = _parseDate(row['attendance_date']);
      if (id.isEmpty || date == null) continue;
      final mode = _text(row['attendance_mode']).toLowerCase();
      final detailsSaved = row['student_details_saved'] == true ||
          const <String>{'true', 't', '1'}
              .contains(_text(row['student_details_saved']).toLowerCase());
      final studentwise = mode == 'student' && detailsSaved;
      final normalized = <String, dynamic>{
        'id': id,
        'date': date,
        'date_iso': _iso(date),
        'studentwise': studentwise,
      };
      daysById[id] = normalized;
      if (studentwise) {
        studentwiseDayIds.add(id);
      } else {
        directDaysCount++;
        incompleteMonths.add('${monthNamesGujarati[date.month - 1]} ${date.year}');
      }
    }

    final marks = <Map<String, dynamic>>[];
    for (var offset = 0; offset < studentwiseDayIds.length; offset += 60) {
      final ids = studentwiseDayIds.skip(offset).take(60).toList();
      var pageStart = 0;
      while (true) {
        final page = await _client
            .from('student_attendance')
            .select('student_id,attendance_day_id,present')
            .eq('school_ref', schoolRef)
            .inFilter('attendance_day_id', ids)
            .range(pageStart, pageStart + 999);
        final pageRows =
            page.map((row) => Map<String, dynamic>.from(row)).toList();
        marks.addAll(pageRows);
        if (pageRows.length < 1000) break;
        pageStart += 1000;
      }
    }

    final presentByStudentAndDate = <String, Map<String, int>>{};
    for (final mark in marks) {
      final present = mark['present'] == true ||
          const <String>{'true', 't', '1'}
              .contains(_text(mark['present']).toLowerCase());
      if (!present) continue;
      final studentId = _text(mark['student_id']);
      final dayId = _text(mark['attendance_day_id']);
      final day = daysById[dayId];
      if (studentId.isEmpty || day == null) continue;
      final dateIso = _text(day['date_iso']);
      final counts =
          presentByStudentAndDate.putIfAbsent(studentId, () => <String, int>{});
      counts[dateIso] = (counts[dateIso] ?? 0) + 1;
    }

    int extractInsertedDays(Map<String, dynamic> student) {
      final direct = _int(student['present_days'] ?? student['presentDays']);
      if (direct > 0) return direct;
      final custom = student['custom_fields'];
      if (custom is Map) {
        final cVal = _int(
          custom['present_days'] ??
              custom['presentDays'] ??
              custom['હાજર દિવસો'],
        );
        if (cVal > 0) return cVal;
      }
      return 0;
    }

    for (final student in students) {
      final studentId = _text(student['id'] ?? student['student_id']);
      if (studentId.isEmpty) continue;
      final inserted = extractInsertedDays(student);
      if (exactOverrides.containsKey(studentId)) {
        autoDays[studentId] = exactOverrides[studentId]!;
        continue;
      }
      final baseline = latestBefore[studentId];
      final baselineDate = baseline == null
          ? fromDate.subtract(const Duration(days: 1))
          : (_parseDate(baseline['through_date']) ??
              fromDate.subtract(const Duration(days: 1)));
      final baselineDays = baseline == null ? 0 : _int(baseline['present_days']);
      var counted = baselineDays;
      final studentMarks =
          presentByStudentAndDate[studentId] ?? <String, int>{};
      for (final entry in studentMarks.entries) {
        final date = _parseDate(entry.key);
        if (date != null &&
            date.isAfter(baselineDate) &&
            !date.isBefore(fromDate) &&
            !date.isAfter(throughDate)) {
          counted += entry.value;
        }
      }
      if (inserted > 0 && (directDaysCount > 0 || counted == 0)) {
        autoDays[studentId] = inserted;
      } else if (counted > 0) {
        autoDays[studentId] = counted;
      } else if (inserted > 0) {
        autoDays[studentId] = inserted;
      }
    }

    return <String, dynamic>{
      'days_by_student_id': autoDays,
      'is_complete': directDaysCount == 0 && studentwiseDayIds.isNotEmpty,
      'studentwise_days_count': studentwiseDayIds.length,
      'direct_days_count': directDaysCount,
      'incomplete_months': incompleteMonths.toList(),
    };
  }

  List<Map<String, dynamic>> _parseSectionHistory(Map<String, dynamic> student) {
    dynamic rawHist = student['section_history'];
    if (rawHist is! List && student['custom_fields'] is Map) {
      rawHist = (student['custom_fields'] as Map)['section_history'];
    }
    if (rawHist is! List || rawHist.isEmpty) return const <Map<String, dynamic>>[];
    final entries = rawHist
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) =>
            _text(e['from_class_id']).isNotEmpty &&
            _text(e['to_class_id']).isNotEmpty)
        .toList();
    entries.sort((a, b) {
      final da = _parseDate(a['effective_date']) ?? DateTime(1900, 1, 1);
      final db = _parseDate(b['effective_date']) ?? DateTime(1900, 1, 1);
      return da.compareTo(db);
    });
    return entries;
  }

  Set<String> _extractSectionHistoryClassIds(Map<String, dynamic> student) {
    final out = <String>{};
    final cid = _text(student['class_id']);
    if (cid.isNotEmpty) out.add(cid);
    for (final entry in _parseSectionHistory(student)) {
      final fromId = _text(entry['from_class_id']);
      final toId = _text(entry['to_class_id']);
      if (fromId.isNotEmpty) out.add(fromId);
      if (toId.isNotEmpty) out.add(toId);
    }
    return out;
  }

  /// Resolves which section (`class_id`) the student belongs to for a monthly Hajari Patrak.
  /// Rule: If a student changes section during month M (e.g., March), then up to and including
  /// month M (till March) the student is printed in the old section's Hajari Patrak;
  /// starting in month M + 1 (from April onward), the student is printed in the new section's Hajari Patrak.
  String _effectiveClassIdForRegisterMonth(
    Map<String, dynamic> student,
    DateTime registerMonthFirst,
  ) {
    final currentCid = _text(student['class_id']);
    final entries = _parseSectionHistory(student);
    if (entries.isEmpty) return currentCid;
    final targetMonth = DateTime(registerMonthFirst.year, registerMonthFirst.month, 1);
    var cid = _text(entries.first['from_class_id']);
    if (cid.isEmpty) cid = currentCid;
    for (final entry in entries) {
      final effDate = _parseDate(entry['effective_date']);
      if (effDate == null) continue;
      final transferMonth = DateTime(effDate.year, effDate.month, 1);
      if (targetMonth.isAfter(transferMonth)) {
        final nextCid = _text(entry['to_class_id']);
        if (nextCid.isNotEmpty) cid = nextCid;
      }
    }
    return cid.isEmpty ? currentCid : cid;
  }

  String _historicalRollForRegisterMonth(
    Map<String, dynamic> student,
    DateTime registerMonthFirst,
    String targetClassId,
  ) {
    final entries = _parseSectionHistory(student);
    if (entries.isEmpty) return '';
    final targetMonth = DateTime(registerMonthFirst.year, registerMonthFirst.month, 1);
    for (final entry in entries) {
      final effDate = _parseDate(entry['effective_date']);
      if (effDate == null) continue;
      final transferMonth = DateTime(effDate.year, effDate.month, 1);
      if (!targetMonth.isAfter(transferMonth) &&
          _text(entry['from_class_id']) == targetClassId) {
        final oldRoll = _text(entry['old_roll_number']);
        if (oldRoll.isNotEmpty) return oldRoll;
      }
    }
    return '';
  }

  bool _belongsToMonth(Map<String, dynamic> student, DateTime first, DateTime last) {
    final enrolled = AttendanceLifecycle.parseEnrollmentDate(student);
    final left = AttendanceLifecycle.parseLeavingDate(student);
    // Monthly register rule:
    // 1. Register for month M is printed BEFORE the 1st of month M.
    //    Therefore a student newly enrolled during month M (1st..last of month M)
    //    is excluded from month M's register and starts in month (M + 1).
    // 2. A student who left during month M (even on the 1st of month M) was on
    //    the roll when month M's register was printed, so they MUST remain in
    //    month M's register and are excluded starting in month (M + 1).
    if (enrolled != null) {
      return AttendanceLifecycle.includeInMonthlyRegister(
        registerMonth: first,
        enrolledOn: enrolled,
        leftOn: left,
      );
    }
    // Fallback if enrollment date was not entered on legacy rows: still enforce leaving month rule
    if (left != null && first.isAfter(DateTime(left.year, left.month, 1))) {
      return false;
    }
    return true;
  }

  DateTime _effectiveEnrollmentDate(Map<String, dynamic> student) {
    final entered = _parseDate(student['enroll_school']);
    if (entered != null) return _dateOnly(entered);
    return DateTime(1900, 1, 1);
  }

  DateTime? _parseDate(dynamic value) {
    if (value is DateTime) return _dateOnly(value);
    final raw = _text(value);
    if (raw.isEmpty) return null;
    final dmy = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$').firstMatch(raw);
    if (dmy != null) {
      final day = int.tryParse(dmy.group(1)!) ?? 0;
      final month = int.tryParse(dmy.group(2)!) ?? 0;
      final year = int.tryParse(dmy.group(3)!) ?? 0;
      if (day > 0 && month > 0 && month <= 12 && year >= 1900) {
        final date = DateTime(year, month, day);
        if (date.year == year && date.month == month && date.day == day) return date;
      }
    }
    final parsed = DateTime.tryParse(raw);
    return parsed == null ? null : _dateOnly(parsed);
  }

  DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  String _iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _dateDmy(dynamic value) {
    final date = _parseDate(value);
    if (date == null) return _text(value);
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _weekday(DateTime date) => _weekdaysGujarati[date.weekday - 1];

  String _category(dynamic value) {
    final raw = _text(value).toUpperCase().replaceAll(RegExp(r'\s+'), '');
    // Check ST before SC: 'અ.જ.જા.' starts with 'અ.જા.' as well.
    if (raw == 'ST' || raw.contains('અ.જ.જા')) return 'ST';
    if (raw == 'SC' || raw == 'અ.જા' || raw == 'અ.જા.') return 'SC';
    if (raw == 'OBC' || raw.contains('બ.પં') || raw.contains('બક્ષીપંચ')) return 'OBC';
    return 'OTHER';
  }

  String _gender(Map<String, dynamic> student, String schoolType) {
    final type = schoolType.toLowerCase().trim();
    if (type == 'boys' || type == 'boy') return 'BOYS';
    if (type == 'girls' || type == 'girl') return 'GIRLS';
    final raw = _text(student['gender']).toUpperCase();
    if (const <String>{'BOYS', 'BOY', 'MALE', 'M', 'KUMAR', 'કુમાર'}.contains(raw)) return 'BOYS';
    if (const <String>{'GIRLS', 'GIRL', 'FEMALE', 'F', 'KANYA', 'કન્યા'}.contains(raw)) return 'GIRLS';
    return 'UNSPECIFIED';
  }

  bool _isSingleGenderSchool(String schoolType) {
    final type = schoolType.toLowerCase().trim();
    return const <String>{
      'boys', 'boy', 'girls', 'girl', 'કુમાર શાળા', 'કન્યા શાળા',
    }.contains(type);
  }

  Map<String, int> _categoryCounts(List<Map<String, dynamic>> students, String schoolType, {String? gender}) {
    final out = <String, int>{'SC': 0, 'ST': 0, 'OBC': 0, 'OTHER': 0, 'TOTAL': 0};
    for (final student in students) {
      if (gender != null && _gender(student, schoolType) != gender) continue;
      final category = _category(student['category']);
      out[category] = (out[category] ?? 0) + 1;
      out['TOTAL'] = (out['TOTAL'] ?? 0) + 1;
    }
    return out;
  }

  Future<pw.Font> _loadPdfFont(List<String> candidates) async {
    for (final assetPath in candidates) {
      try {
        return pw.Font.ttf(await rootBundle.load(assetPath));
      } catch (_) {
        // Try the next installed font asset; no UI/network side effects.
      }
    }
    throw StateError('Gujarati PDF font missing. Keep assets/fonts/Lohit-Gujarati.ttf in pubspec.yaml.');
  }

  Future<Uint8List?> _tryLoadAssetBytes(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  // Lohit Gujarati is the preferred face for Gujarati script. It does not
  // reliably render every Latin-only school/teacher name in this PDF build,
  // so use an embedded standard Latin face for values containing no Gujarati.
  bool _containsGujarati(String value) => RegExp(r'[\u0A80-\u0AFF]').hasMatch(value);

  pw.Font _fontForText(String value, pw.Font gujaratiFont, pw.Font latinFont) =>
      _containsGujarati(value) ? gujaratiFont : latinFont;

  Future<Uint8List> buildMonthlyPdf({
    required String schoolName,
    required String schoolAddress,
    required String schoolType,
    required String academicYear,
    required String classLabel,
    required String teacherName,
    required int year,
    required int month,
    required List<Map<String, dynamic>> students,
    required List<Map<String, dynamic>> attendance,
    required Set<String> holidays,
    required int rowHeightPx,
    required int fontSize,
    required int blankRows,
    required bool colorMode,
    Uint8List? schoolLogoBytes,
    Map<String, int?> presentDaysByStudentId = const <String, int?>{},
    bool fillRecordedAttendance = false,
    Map<String, Map<int, Map<String, bool>>> studentDailyMarks =
        const <String, Map<int, Map<String, bool>>>{},
    Set<int> recordedDays = const <int>{},
  }) async {
    if (students.isEmpty) throw StateError('આ મહિના માટે કોઈ વિદ્યાર્થી મળ્યો નથી. Enrollment date અને leaving date તપાસો.');

    // The project explicitly includes Lohit Gujarati in assets/pubspec.
    // Prefer it first for the entire register so Gujarati glyphs stay consistent
    // between the cover, student rows, headers, footers and handwritten summaries.
    final font = await _loadPdfFont(<String>[
      'assets/fonts/Lohit-Gujarati.ttf',
      'assets/fonts/NotoSansGujarati-Regular.ttf',
      'assets/fonts/NotoSerifGujarati-Regular.ttf',
      'assets/fonts/NotoSerifGujarati[wght].ttf',
      'assets/fonts/NotoSerifGujarati.ttf',
    ]);
    final boldFont = await _loadPdfFont(<String>[
      'assets/fonts/Lohit-Gujarati.ttf',
      'assets/fonts/NotoSansGujarati-Bold.ttf',
      'assets/fonts/NotoSansGujarati-Regular.ttf',
      'assets/fonts/NotoSerifGujarati-Bold.ttf',
      'assets/fonts/NotoSerifGujarati[wght].ttf',
      'assets/fonts/NotoSerifGujarati-Regular.ttf',
      'assets/fonts/NotoSerifGujarati.ttf',
    ]);
    // Built-in PDF Helvetica faces cover ASCII/Latin-only school and teacher
    // names when the Gujarati font has no matching Latin glyph.
    final latinFont = pw.Font.helvetica();
    final latinBoldFont = pw.Font.helveticaBold();

    final pmShriBytes = await _tryLoadAssetBytes('assets/hajari_patrak/pm_shri_logo.png');
    final isPmShriSchool = schoolName.toLowerCase().contains('pm shri') || schoolName.contains('પીએમ શ્રી');
    // An Admin-uploaded logo takes priority. The supplied PM SHRI artwork is
    // used only for PM SHRI schools, so unrelated schools are not misbranded.
    final effectiveLogoBytes = schoolLogoBytes ?? (isPmShriSchool ? pmShriBytes : null);
    final schoolLogo = effectiveLogoBytes == null ? null : pw.MemoryImage(effectiveLogoBytes);
    final doc = pw.Document();
    final first = DateTime(year, month, 1);
    final last = DateTime(year, month + 1, 0);
    // The cover's first census row is the registered strength at the start of
    // the selected month. All other census and monthly-detail values are manual.
    final opening = students.where((student) {
      return _belongsToMonth(student, first, last);
    }).toList();
    final openingCategoryCounts = _categoryCounts(opening, schoolType);
    final openingGenderCounts = _genderCategoryCounts(opening, schoolType);

    // Front page follows the supplied Excel template: title, an intentionally
    // generous logo/identity area, school heading, class/teacher boxes, grouped
    // gender-category summary, blank month-end fields, and bottom signatures.
    const coverMargin = 8.0;
    const innerPadding = 7.0;
    final singleGenderSchool = _isSingleGenderSchool(schoolType);

    pw.Widget coverCell(
      String value, {
      required pw.Font cellFont,
      double fontSize = 7.5,
      double height = 24,
      bool bold = false,
      bool left = false,
      PdfColor background = PdfColors.white,
      int maxLines = 2,
    }) => pw.Container(
      height: height,
      padding: pw.EdgeInsets.symmetric(horizontal: left ? 3.5 : 1.6, vertical: 2.0),
      alignment: left ? pw.Alignment.centerLeft : pw.Alignment.center,
      decoration: pw.BoxDecoration(
        color: background,
        border: pw.Border.all(color: PdfColors.black, width: 0.45),
      ),
      child: pw.Text(
        value,
        maxLines: maxLines,
        overflow: pw.TextOverflow.clip,
        textAlign: left ? pw.TextAlign.left : pw.TextAlign.center,
        style: pw.TextStyle(font: bold ? boldFont : cellFont, fontSize: fontSize),
      ),
    );

    final singleFlex = <double>[3.8, 1, 1, 1, 1, 1, 1, 1, 1];
    final mixedFlex = <double>[4, ...List<double>.filled(14, 1)];
    final tableFlex = singleGenderSchool ? singleFlex : mixedFlex;
    final coverTableWidth = PdfPageFormat.a4.width - 2 * coverMargin - 6 - 2 * innerPadding - 2;
    final flexSum = tableFlex.fold<double>(0, (sum, value) => sum + value);
    final coverWidths = <int, pw.TableColumnWidth>{
      for (var i = 0; i < tableFlex.length; i++)
        i: pw.FixedColumnWidth(coverTableWidth * tableFlex[i] / flexSum),
    };

    // Only the registered/opening-strength row is populated on the cover.
    // Admissions, exits, continuous-absence removals and closing strength are
    // intentionally left blank for the teacher to complete at month-end.
    List<String> blankCoverMetricRow(String label) => <String>[
      label,
      ...List<String>.filled(singleGenderSchool ? 8 : 14, ''),
    ];
    final coverMetricRows = <List<String>>[
      singleGenderSchool
          ? _frontSingleMetricRow('ગયા માસને આખરે બાકી', openingGenderCounts, schoolType)
          : _frontMetricRow('ગયા માસને આખરે બાકી', openingGenderCounts, schoolType),
      blankCoverMetricRow('ચાલુ માસમાં નવા આવેલ'),
      blankCoverMetricRow('ચાલુ માસમાં લિ. સર્ટી. લઈ ગયેલ'),
      blankCoverMetricRow('સતત ગેરહાજરીથી નામ કમી કરેલ'),
      blankCoverMetricRow('ચાલુ માસને આખરે બાકી'),
    ];

    pw.Widget singleGenderCountTable() {
      final headers = <String>['વિગત', 'કુમાર', 'કન્યા', 'કુલ', 'અ.જા.', 'અ.જ.જા.', 'બ.પં.', 'અન્ય', 'કુલ'];
      final rows = <pw.TableRow>[
        pw.TableRow(children: <pw.Widget>[
          for (var i = 0; i < headers.length; i++)
            coverCell(headers[i], cellFont: font, bold: false, fontSize: 7.5,
              height: 27, background: PdfColors.grey300, left: i == 0),
        ]),
        for (final row in coverMetricRows)
          pw.TableRow(children: <pw.Widget>[
            for (var i = 0; i < row.length; i++)
              coverCell(row[i], cellFont: font, fontSize: 7.7, height: 35,
                left: i == 0, maxLines: 2),
          ]),
      ];
      return pw.Table(columnWidths: coverWidths, children: rows);
    }

    pw.Widget mixedGenderGroupedHeader() {
      pw.Widget mergedHeader(String value, int flex) => pw.Expanded(
        flex: flex,
        child: coverCell(value, cellFont: font, bold: false, fontSize: 6.8,
          height: 31, background: PdfColors.grey300, maxLines: 2),
      );

      pw.Widget categoryHeader(String value, {required int flex, required bool total}) => pw.Expanded(
        flex: flex,
        child: pw.Container(
          height: 31,
          decoration: pw.BoxDecoration(
            color: PdfColors.grey300,
            border: pw.Border.all(color: PdfColors.black, width: 0.45),
          ),
          child: pw.Column(children: <pw.Widget>[
            pw.Container(
              height: 14,
              alignment: pw.Alignment.center,
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.45)),
              ),
              child: pw.Text(value, maxLines: 1, overflow: pw.TextOverflow.clip,
                style: pw.TextStyle(font: font, fontSize: 6.7)),
            ),
            pw.Expanded(child: pw.Row(children: <pw.Widget>[
              pw.Expanded(child: pw.Container(
                alignment: pw.Alignment.center,
                decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(color: PdfColors.black, width: 0.3))),
                child: pw.Text('કુમાર', maxLines: 1, overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(font: font, fontSize: 5.7)),
              )),
              pw.Expanded(child: pw.Container(
                alignment: pw.Alignment.center,
                decoration: total ? const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(color: PdfColors.black, width: 0.3))) : null,
                child: pw.Text('કન્યા', maxLines: 1, overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(font: font, fontSize: 5.7)),
              )),
              if (total)
                pw.Expanded(child: pw.Container(
                  alignment: pw.Alignment.center,
                  child: pw.Text('કુલ', maxLines: 1, overflow: pw.TextOverflow.clip,
                    style: pw.TextStyle(font: font, fontSize: 5.7)),
                )),
            ])),
          ]),
        ),
      );

      return pw.Row(children: <pw.Widget>[
        mergedHeader('વિગત', 4),
        mergedHeader('કુમાર', 1),
        mergedHeader('કન્યા', 1),
        mergedHeader('કુલ', 1),
        categoryHeader('અ.જા.', flex: 2, total: false),
        categoryHeader('અ.જ.જા.', flex: 2, total: false),
        categoryHeader('બ.પં.', flex: 2, total: false),
        categoryHeader('અન્ય', flex: 2, total: false),
        categoryHeader('કુલ', flex: 3, total: true),
      ]);
    }

    pw.Widget mixedGenderCountTable() {
      final rows = <pw.TableRow>[
        for (final row in coverMetricRows)
          pw.TableRow(children: <pw.Widget>[
            for (var i = 0; i < row.length; i++)
              coverCell(row[i], cellFont: font, fontSize: 7.0, height: 35,
                left: i == 0, maxLines: 2),
          ]),
      ];
      return pw.Column(children: <pw.Widget>[
        mixedGenderGroupedHeader(),
        pw.Table(columnWidths: coverWidths, children: rows),
      ]);
    }

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(coverMargin),
      theme: pw.ThemeData.withFont(base: font, bold: boldFont),
      build: (context) => pw.Container(
        width: double.infinity,
        height: PdfPageFormat.a4.height - coverMargin * 2,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 1.0),
        ),
        padding: const pw.EdgeInsets.all(3),
        child: pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black, width: 0.45)),
          padding: const pw.EdgeInsets.fromLTRB(innerPadding, 7, innerPadding, 7),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: <pw.Widget>[
              pw.Center(child: pw.Text('શૈક્ષણિક વર્ષ $academicYear',
                style: pw.TextStyle(font: font, fontSize: 11))),
              pw.SizedBox(height: 3),
              pw.Center(child: pw.Text('વિદ્યાર્થીઓનું હાજરીપત્રક',
                style: pw.TextStyle(font: font, fontSize: 19))),
              pw.SizedBox(height: 5),
              pw.Center(child: pw.Text('માસ: ${monthNamesGujarati[month - 1]} - $year',
                style: pw.TextStyle(font: font, fontSize: 16.5))),
              // The reference worksheet reserves a tall blank/logo area between
              // the month line and school name. Keep this on purpose.
              pw.SizedBox(
                height: 205,
                child: schoolLogo == null
                    ? pw.SizedBox.expand()
                    : pw.Center(child: pw.Image(schoolLogo, fit: pw.BoxFit.contain, width: 170, height: 110)),
              ),
              pw.Center(child: pw.Text(
                schoolName,
                textAlign: pw.TextAlign.center,
                maxLines: 2,
                overflow: pw.TextOverflow.clip,
                style: pw.TextStyle(font: _fontForText(schoolName, boldFont, latinBoldFont), fontSize: schoolName.length > 34 ? 18 : 22),
              )),
              if (schoolAddress.trim().isNotEmpty) ...<pw.Widget>[
                pw.SizedBox(height: 3),
                pw.Center(child: pw.Text(schoolAddress, textAlign: pw.TextAlign.center, maxLines: 2,
                  overflow: pw.TextOverflow.clip, style: pw.TextStyle(font: _fontForText(schoolAddress, font, latinFont), fontSize: 8.5))),
              ],
              pw.SizedBox(height: 4),
              pw.Row(children: <pw.Widget>[
                pw.Expanded(flex: 2, child: _infoBox('ધોરણ', _classValue(classLabel), font, latinFont: latinFont, height: 25)),
                pw.SizedBox(width: 7),
                pw.Expanded(flex: 5, child: _infoBox('વર્ગ શિક્ષક', teacherName, font, latinFont: latinFont, height: 25)),
              ]),
              pw.Container(
                alignment: pw.Alignment.center,
                padding: const pw.EdgeInsets.symmetric(vertical: 4.5),
                decoration: pw.BoxDecoration(
                  border: pw.Border(top: pw.BorderSide(width: 0.7), bottom: pw.BorderSide(width: 0.7)),
                ),
                child: pw.Text('વિદ્યાર્થીઓની સંખ્યાની તારિજ',
                  style: pw.TextStyle(font: font, fontSize: 11.5)),
              ),
              singleGenderSchool ? singleGenderCountTable() : mixedGenderCountTable(),
              pw.SizedBox(height: 5),
              pw.Table.fromTextArray(
                data: const <List<String>>[
                  <String>['ગયા માસનાં અંત સુધીનાં કુલ કામનાં દિવસો:-', '', 'હાજરીની ટકાવારી :–', ''],
                  <String>['ચાલુ માસને અંતે કુલ હાજર દિવસો', '', 'ચાલુ માસની સરાસરી હાજરી :-', ''],
                  <String>['ચાલુ માસનાં કામનાં દિવસોઃ-', '', 'માસને અંતે કુલ કામનાં દિવસો :-', ''],
                ],
                columnWidths: <int, pw.TableColumnWidth>{
                  // Match the merged-column proportions in the Excel master template:
                  // label, writing cell, label, writing cell.
                  0: const pw.FlexColumnWidth(3.0), 1: const pw.FlexColumnWidth(1.0),
                  2: const pw.FlexColumnWidth(1.5), 3: const pw.FlexColumnWidth(2.5),
                },
                cellStyle: pw.TextStyle(font: font, fontSize: 7.8),
                border: pw.TableBorder.all(color: PdfColors.black, width: 0.55),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 8.5),
                cellAlignments: <int, pw.Alignment>{0: pw.Alignment.centerLeft, 2: pw.Alignment.centerLeft},
              ),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: <pw.Widget>[
                  pw.Expanded(child: pw.Column(children: <pw.Widget>[
                    pw.Text('વર્ગ શિક્ષક', style: pw.TextStyle(font: boldFont, fontSize: 9.5)),
                    pw.SizedBox(height: 4),
                    pw.Text(teacherName, textAlign: pw.TextAlign.center, maxLines: 1,
                      style: pw.TextStyle(font: _fontForText(teacherName, font, latinFont), fontSize: 8)),
                    pw.SizedBox(height: 4),
                    pw.Text(schoolName, textAlign: pw.TextAlign.center, maxLines: 1,
                      style: pw.TextStyle(font: _fontForText(schoolName, font, latinFont), fontSize: 7.5)),
                  ])),
                  pw.Expanded(child: pw.Column(children: <pw.Widget>[
                    pw.Text('મુખ્ય શિક્ષક', style: pw.TextStyle(font: boldFont, fontSize: 9.5)),
                    pw.SizedBox(height: 4),
                    pw.Text(schoolName, textAlign: pw.TextAlign.center, maxLines: 1,
                      style: pw.TextStyle(font: _fontForText(schoolName, font, latinFont), fontSize: 8)),
                    // Signature is intentionally left blank for the principal.
                  ])),
                ],
              ),
            ],
          ),
        ),
      ),
    ));

    // Allow rowHeight and fontSize to scale freely when the teacher chooses a
    // larger row height (up to 36px+) or larger font size (up to 12pt+), and
    // automatically paginate students + blank rows across as many A4 pages as needed!
    var effectiveFontSize = (fontSize + 0.4).clamp(4.0, 13.0).toDouble();
    if (rowHeightPx <= 14 && effectiveFontSize > 6.5) {
      effectiveFontSize = 6.5;
    } else if (rowHeightPx <= 18 && effectiveFontSize > 8.0) {
      effectiveFontSize = 8.0;
    }
    final minHeightForFont = effectiveFontSize * 1.55;
    final desiredRowHeight = rowHeightPx * 0.86;
    final rowHeight = (desiredRowHeight > minHeightForFont
            ? desiredRowHeight
            : minHeightForFont)
        .clamp(7.5, 34.0)
        .toDouble();
    if (blankRows < 0 || blankRows > 1997) {
      throw StateError('ખાલી લાઇનની સંખ્યા 0 થી 1997 વચ્ચે હોવી જોઈએ.');
    }
    final effectiveBlankRows =
        (fillRecordedAttendance && blankRows < 1) ? 1 : blankRows;
    const pageMarginsAndTitle = 34.0;
    const tableHeaderHeight = 39.0;
    const finalSummaryReserve = 86.0;

    // Full page capacity (for intermediate pages without the bottom summary)
    // vs. final page capacity (which also holds the bottom summary block).
    final fullPageAvailable =
        PdfPageFormat.a4.height - pageMarginsAndTitle - tableHeaderHeight - 8.0;
    final lastPageAvailable = PdfPageFormat.a4.height -
        pageMarginsAndTitle -
        tableHeaderHeight -
        finalSummaryReserve;
    final rowsPerFullPage =
        (fullPageAvailable / rowHeight).floor().clamp(6, 48).toInt();
    final rowsPerLastPage =
        (lastPageAvailable / rowHeight).floor().clamp(4, 42).toInt();

    // Combine student rows and blank rows into a single stream so large font sizes,
    // tall row heights, or many blank rows gracefully span across multiple pages.
    // When fillRecordedAttendance is true, the very last blank row carries the P/A colour code legend.
    final combinedRows = <Map<String, dynamic>>[
      ...students,
      for (var i = 0; i < effectiveBlankRows; i++)
        <String, dynamic>{
          '_is_blank_row': true,
          if (fillRecordedAttendance && i == effectiveBlankRows - 1)
            '_is_color_legend_row': true,
        },
    ];

    final chunks = <List<Map<String, dynamic>>>[];
    var cursor = 0;
    while (cursor < combinedRows.length) {
      final remaining = combinedRows.length - cursor;
      if (remaining <= rowsPerLastPage) {
        chunks.add(combinedRows.sublist(cursor));
        break;
      } else if (remaining <= rowsPerFullPage) {
        // Split so the final page has plenty of room for the summary footer
        final takeCount =
            (remaining - (rowsPerLastPage ~/ 2)).clamp(1, rowsPerFullPage);
        chunks.add(combinedRows.sublist(cursor, cursor + takeCount));
        cursor += takeCount;
      } else {
        chunks.add(combinedRows.sublist(cursor, cursor + rowsPerFullPage));
        cursor += rowsPerFullPage;
      }
    }
    if (chunks.isEmpty) {
      chunks.add(const <Map<String, dynamic>>[]);
    }

    final holidaysExpanded = <String>{...holidays};
    for (var day = 1; day <= last.day; day++) {
      final date = DateTime(year, month, day);
      if (date.weekday == DateTime.sunday) holidaysExpanded.add(_iso(date));
    }

    // Keep matching student batches together: first the 1–8 page, then its
    // 9–31 continuation.
    for (final chunk in chunks) {
      doc.addPage(_buildRegisterPage(
        font: font,
        boldFont: boldFont,
        latinFont: latinFont,
        latinBoldFont: latinBoldFont,
        classLabel: classLabel,
        year: year,
        month: month,
        students: chunk,
        allStudents: students,
        openingCounts: openingCategoryCounts,
        schoolType: schoolType,
        holidays: holidaysExpanded,
        rowHeight: rowHeight,
        fontSize: effectiveFontSize,
        blankRows: 0,
        colorMode: colorMode,
        firstHalf: true,
        isFinalChunk: identical(chunk, chunks.last),
        presentDaysByStudentId: presentDaysByStudentId,
        fillRecordedAttendance: fillRecordedAttendance,
        studentDailyMarks: studentDailyMarks,
        recordedDays: recordedDays,
      ));
      doc.addPage(_buildRegisterPage(
        font: font,
        boldFont: boldFont,
        latinFont: latinFont,
        latinBoldFont: latinBoldFont,
        classLabel: classLabel,
        year: year,
        month: month,
        students: chunk,
        allStudents: students,
        openingCounts: openingCategoryCounts,
        schoolType: schoolType,
        holidays: holidaysExpanded,
        rowHeight: rowHeight,
        fontSize: effectiveFontSize,
        blankRows: 0,
        colorMode: colorMode,
        firstHalf: false,
        isFinalChunk: identical(chunk, chunks.last),
        presentDaysByStudentId: presentDaysByStudentId,
        fillRecordedAttendance: fillRecordedAttendance,
        studentDailyMarks: studentDailyMarks,
        recordedDays: recordedDays,
      ));
    }

    return Uint8List.fromList(await doc.save());
  }

  Map<String, int> _genderCategoryCounts(List<Map<String, dynamic>> students, String schoolType) {
    final out = <String, int>{};
    for (final student in students) {
      final gender = _gender(student, schoolType);
      final category = _category(student['category']);
      final key = '${gender}_$category';
      out[key] = (out[key] ?? 0) + 1;
      out['${gender}_TOTAL'] = (out['${gender}_TOTAL'] ?? 0) + 1;
      out['TOTAL_$category'] = (out['TOTAL_$category'] ?? 0) + 1;
      out['TOTAL'] = (out['TOTAL'] ?? 0) + 1;
    }
    return out;
  }

  List<String> _frontSingleMetricRow(
    String label,
    Map<String, int> counts,
    String schoolType, {
    bool unknown = false,
  }) {
    if (unknown) return <String>[label, '—', '—', '—', '—', '—', '—', '—', '—'];
    final type = schoolType.toLowerCase().trim();
    final gender = type == 'girls' || type == 'girl' || type.contains('કન્યા') ? 'GIRLS' : 'BOYS';
    int n(String category) => counts['${gender}_$category'] ?? 0;
    final total = counts['${gender}_TOTAL'] ?? 0;
    return <String>[
      label,
      gender == 'BOYS' ? '$total' : '---',
      gender == 'GIRLS' ? '$total' : '---',
      '$total',
      '${n('SC')}', '${n('ST')}', '${n('OBC')}', '${n('OTHER')}', '$total',
    ];
  }

  List<String> _frontMetricRow(
    String label,
    Map<String, int> counts,
    String schoolType, {
    bool unknown = false,
  }) {
    if (unknown) return <String>[label, ...List<String>.filled(14, '—')];
    int n(String gender, String category) => counts['${gender}_$category'] ?? 0;
    int totalGender(String gender) => counts['${gender}_TOTAL'] ?? 0;
    final boysSchool = SchoolType.isBoys(schoolType);
    final girlsSchool = SchoolType.isGirls(schoolType);
    final boys = totalGender('BOYS');
    final girls = totalGender('GIRLS');
    final total = counts['TOTAL'] ?? 0;
    return <String>[
      label,
      boysSchool ? '$boys' : girlsSchool ? '---' : '$boys',
      girlsSchool ? '$girls' : boysSchool ? '---' : '$girls',
      '$total',
      boysSchool ? '${n('BOYS', 'SC')}' : girlsSchool ? '---' : '${n('BOYS', 'SC')}',
      girlsSchool ? '${n('GIRLS', 'SC')}' : boysSchool ? '---' : '${n('GIRLS', 'SC')}',
      boysSchool ? '${n('BOYS', 'ST')}' : girlsSchool ? '---' : '${n('BOYS', 'ST')}',
      girlsSchool ? '${n('GIRLS', 'ST')}' : boysSchool ? '---' : '${n('GIRLS', 'ST')}',
      boysSchool ? '${n('BOYS', 'OBC')}' : girlsSchool ? '---' : '${n('BOYS', 'OBC')}',
      girlsSchool ? '${n('GIRLS', 'OBC')}' : boysSchool ? '---' : '${n('GIRLS', 'OBC')}',
      boysSchool ? '${n('BOYS', 'OTHER')}' : girlsSchool ? '---' : '${n('BOYS', 'OTHER')}',
      girlsSchool ? '${n('GIRLS', 'OTHER')}' : boysSchool ? '---' : '${n('GIRLS', 'OTHER')}',
      boysSchool ? '$boys' : girlsSchool ? '---' : '$boys',
      girlsSchool ? '$girls' : boysSchool ? '---' : '$girls',
      '$total',
    ];
  }

  String _classValue(String value) => ClassLabel.bare(value);

  pw.Widget _infoBox(String label, String value, pw.Font font, {required pw.Font latinFont, required double height}) => pw.Container(
        height: height,
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black, width: 0.6)),
        child: pw.Row(children: <pw.Widget>[
          pw.Text('$label: ', style: pw.TextStyle(font: font, fontSize: 7)),
          pw.Expanded(child: pw.Text(value, maxLines: 1, overflow: pw.TextOverflow.clip, style: pw.TextStyle(font: _fontForText(value, font, latinFont), fontSize: 7))),
        ]),
      );

  pw.Page _buildRegisterPage({
    required pw.Font font,
    required pw.Font boldFont,
    required pw.Font latinFont,
    required pw.Font latinBoldFont,
    required String classLabel,
    required int year,
    required int month,
    required List<Map<String, dynamic>> students,
    required List<Map<String, dynamic>> allStudents,
    required Map<String, int> openingCounts,
    required String schoolType,
    required Set<String> holidays,
    required double rowHeight,
    required double fontSize,
    required int blankRows,
    required bool colorMode,
    required bool firstHalf,
    required bool isFinalChunk,
    Map<String, int?> presentDaysByStudentId = const <String, int?>{},
    bool fillRecordedAttendance = false,
    Map<String, Map<int, Map<String, bool>>> studentDailyMarks =
        const <String, Map<int, Map<String, bool>>>{},
    Set<int> recordedDays = const <int>{},
  }) {
    final lastDay = DateTime(year, month + 1, 0).day;
    final singleGender = _isSingleGenderSchool(schoolType);
    final firstHalfDayCount = singleGender ? 8 : 7;
    final days = firstHalf
        ? List<int>.generate(lastDay < firstHalfDayCount ? lastDay : firstHalfDayCount, (i) => i + 1)
        : List<int>.generate(lastDay - firstHalfDayCount, (i) => i + firstHalfDayCount + 1);

    // These relative widths are derived from the supplied workbook structure:
    // single-gender identity has no gender column; mixed schools add gender
    // directly after the student's name. The two empty S/T spacer columns in
    // Excel are represented by the separate first-half / continuation pages.
    final columns = firstHalf
        ? (singleGender
            ? <double>[20, 24, 12, 12, 16, 99, 28, 25, 38, 44, ...List<double>.filled(days.length, 16)]
            : <double>[18, 23, 11, 11, 15, 82, 22, 26, 24, 37, 44, ...List<double>.filled(days.length, 16.5)])
        : <double>[25, ...List<double>.filled(days.length, 13), 31, 31, 31, 30];
    // Binding gutter alternates between the two register sheets: extra white
    // space on the right for the identity/1-8 page, and on the left for the
    // 9-end attendance continuation page.
    final availableWidth = PdfPageFormat.a4.width - 32;
    final widthSum = columns.fold<double>(0, (sum, width) => sum + width);
    final widths = <int, pw.TableColumnWidth>{
      for (var i = 0; i < columns.length; i++)
        i: pw.FixedColumnWidth(columns[i] * availableWidth / widthSum),
    };

    final headerOne = <pw.Widget>[];
    final headerTwo = <pw.Widget>[];
    if (firstHalf) {
      final labels = singleGender
          ? <String>['રોલ નંબર', 'જી. આર. નંબર', 'જન્મ તારીખ', '', '', 'વિદ્યાર્થીનું નામ', 'જાતિ', 'કેટેગરી', 'શાળામાં દાખલ તારીખ', 'વર્ગમાં દાખલ તારીખ']
          : <String>['રોલ નંબર', 'જી. આર. નંબર', 'જન્મ તારીખ', '', '', 'વિદ્યાર્થીનું નામ', 'જાતિ / Gender', 'જ્ઞાતિ', 'કેટેગરી', 'શાળામાં દાખલ તારીખ', 'વર્ગમાં દાખલ તારીખ'];
      final subLabels = <String>['', '', 'DD', 'MM', 'YYYY'];
      for (var index = 0; index < labels.length; index++) {
        headerOne.add(_gridCell(labels[index], font, height: 25, fontSize: fontSize - 0.8, background: PdfColors.grey300));
        headerTwo.add(_gridCell(index < subLabels.length ? subLabels[index] : '', font, height: 13, fontSize: fontSize - 0.8, background: PdfColors.grey200));
      }
    } else {
      headerOne.add(_gridCell('રોલ નંબર', font, height: 25, fontSize: fontSize - 0.4, background: PdfColors.grey300));
      headerTwo.add(_gridCell('', font, height: 13, fontSize: fontSize - 0.4, background: PdfColors.grey200));
    }
    for (final day in days) {
      final date = DateTime(year, month, day);
      final isGrey = holidays.contains(_iso(date));
      final grey = isGrey ? PdfColors.grey400 : PdfColors.grey200;
      headerOne.add(_gridCell(_weekday(date), font, height: 25, fontSize: fontSize - 0.8, background: grey));
      headerTwo.add(_gridCell('$day', font, height: 13, fontSize: fontSize - 0.3, background: grey));
    }
    if (!firstHalf) {
      for (final label in <String>['ચાલુ માસનાં હાજર દિવસો', 'ગયા માસ સુધીના હાજર દિવસો', 'કુલ હાજર દિવસો', 'રીમાર્ક']) {
        headerOne.add(_gridCell(label, font, height: 25, fontSize: fontSize - 1.0, background: PdfColors.grey300));
        headerTwo.add(_gridCell('', font, height: 13, fontSize: fontSize - 0.8, background: PdfColors.grey200));
      }
    }

    final rows = <pw.TableRow>[
      pw.TableRow(children: headerOne),
      pw.TableRow(children: headerTwo),
    ];
    final identityColumnCount = singleGender ? 10 : 11;
    for (var index = 0; index < students.length; index++) {
      final student = students[index];
      if (student['_is_blank_row'] == true) {
        final isLegendRow = student['_is_color_legend_row'] == true;
        final emptyCells = <pw.Widget>[];
        const blueP = PdfColor.fromInt(0xFF1D4ED8);
        const pinkP = PdfColor.fromInt(0xFFDB2777);
        const redP = PdfColor.fromInt(0xFFDC2626);
        for (var column = 0; column < columns.length; column++) {
          var background = isLegendRow ? PdfColor.fromInt(0xFFFFFBEB) : PdfColors.white;
          final dayIndex = firstHalf ? column - identityColumnCount : column - 1;
          if (!isLegendRow && dayIndex >= 0 && dayIndex < days.length) {
            if (holidays.contains(_iso(DateTime(year, month, days[dayIndex])))) {
              background = PdfColors.grey400;
            }
          }
          if (isLegendRow && firstHalf && column == 5) {
            emptyCells.add(
              pw.Container(
                height: rowHeight,
                padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 0.5),
                decoration: pw.BoxDecoration(
                  color: background,
                  border: pw.Border.all(color: PdfColors.black, width: 0.35),
                ),
                alignment: pw.Alignment.centerLeft,
                child: pw.Wrap(
                  spacing: 2,
                  crossAxisAlignment: pw.WrapCrossAlignment.center,
                  children: <pw.Widget>[
                    pw.Text('રંગ કોડ: A=ગેરહાજર', style: pw.TextStyle(font: font, fontSize: (fontSize - 1.2).clamp(4.2, 6.2), color: PdfColors.black)),
                    pw.Text('P=ફક્ત હાજર', style: pw.TextStyle(font: font, fontSize: (fontSize - 1.2).clamp(4.2, 6.2), color: PdfColors.black)),
                    pw.Text('P=ફક્ત MDM', style: pw.TextStyle(font: font, fontSize: (fontSize - 1.2).clamp(4.2, 6.2), color: blueP)),
                    pw.Text('P=ફક્ત નાસ્તો', style: pw.TextStyle(font: font, fontSize: (fontSize - 1.2).clamp(4.2, 6.2), color: pinkP)),
                    pw.Text('P=બંને', style: pw.TextStyle(font: font, fontSize: (fontSize - 1.2).clamp(4.2, 6.2), color: redP)),
                  ],
                ),
              ),
            );
            continue;
          }
          if (isLegendRow && dayIndex >= 0 && dayIndex < 5) {
            final samples = <(String, PdfColor)>[
              ('A', PdfColors.black),
              ('P', PdfColors.black),
              ('P', blueP),
              ('P', pinkP),
              ('P', redP),
            ];
            final sample = samples[dayIndex];
            emptyCells.add(_gridCell(
              sample.$1,
              latinBoldFont,
              height: rowHeight,
              fontSize: fontSize,
              background: background,
              textColor: sample.$2,
            ));
            continue;
          }
          if (isLegendRow && !firstHalf && column >= columns.length - 4) {
            final extraIdx = column - (columns.length - 4);
            final legendLabels = <(String, PdfColor)>[
              ('P(કાળો):હાજર', PdfColors.black),
              ('P(વાદળી):MDM', blueP),
              ('P(ગુલાબી):નાસ્તો', pinkP),
              ('P(લાલ):બંને', redP),
            ];
            final item = legendLabels[extraIdx];
            emptyCells.add(_gridCell(
              item.$1,
              font,
              height: rowHeight,
              fontSize: (fontSize - 1.1).clamp(4.2, 6.2),
              background: background,
              textColor: item.$2,
            ));
            continue;
          }
          emptyCells.add(_gridCell('', font,
              height: rowHeight, fontSize: fontSize, background: background));
        }
        rows.add(pw.TableRow(children: emptyCells));
        continue;
      }
      final category = _category(student['category']);
      final globalIndex = allStudents.indexWhere((value) => _text(value['id']) == _text(student['id']));
      final hasNext = globalIndex >= 0 && globalIndex + 1 < allStudents.length;
      final nextCategory = hasNext ? _category(allStudents[globalIndex + 1]['category']) : null;
      final doubleBottom = globalIndex == allStudents.length - 1 || (nextCategory != null && nextCategory != category);
      final gender = _gender(student, schoolType);
      final genderColor = colorMode && !singleGender
          ? (gender == 'BOYS' ? PdfColors.lightBlue100 : gender == 'GIRLS' ? PdfColors.pink100 : PdfColors.white)
          : PdfColors.white;
      final textColor = colorMode ? _categoryColor(category) : PdfColors.black;
      final cells = <pw.Widget>[];
      if (firstHalf) {
        final identity = <String>[
          _text(student['roll_number']),
          _text(student['gr']),
          _text(student['dd']),
          _text(student['mm']),
          _text(student['yyyy']),
          _text(student['name']),
        ];
        if (!singleGender) {
          identity.add(gender == 'BOYS' ? 'કુમાર' : gender == 'GIRLS' ? 'કન્યા' : '');
        }
        identity.addAll(<String>[
          _text(student['caste']),
          _categoryLabel(category),
          _dateDmy(student['enroll_school']),
          _dateDmy(student['enroll_class']),
        ]);
        for (var column = 0; column < identity.length; column++) {
          final isStudentName = column == 5;
          final isEnrollmentDate = column >= identity.length - 2;
          final visibleNameUnits = identity[column].runes.length;
          final nameFontSize = visibleNameUnits > 42
              ? (fontSize - 1.4).clamp(4.4, fontSize).toDouble()
              : visibleNameUnits > 35
                  ? (fontSize - 0.9).clamp(4.6, fontSize).toDouble()
                  : visibleNameUnits > 29
                      ? (fontSize - 0.4).clamp(4.8, fontSize).toDouble()
                      : fontSize;
          final cellFontSize = isEnrollmentDate
              ? (fontSize * 0.78).clamp(4.6, 7.2).toDouble()
              : isStudentName ? nameFontSize : fontSize;
          cells.add(_gridCell(
            identity[column],
            font,
            height: rowHeight,
            fontSize: cellFontSize,
            background: singleGender ? PdfColors.white : genderColor,
            textColor: textColor,
            doubleBottom: doubleBottom,
            alignLeft: isStudentName,
            singleLine: isStudentName || isEnrollmentDate,
          ));
        }
      } else {
        // The continuation sheet has one roll-number column, with one row for
        // each student in the exact same order as the roster on the first page.
        cells.add(_gridCell(_text(student['roll_number']), font, height: rowHeight,
            fontSize: fontSize, background: genderColor, textColor: textColor, doubleBottom: doubleBottom));
      }
      final stuId = _text(student['id']);
      final stuMarks = stuId.isEmpty ? null : studentDailyMarks[stuId];
      for (final day in days) {
        final date = DateTime(year, month, day);
        final isGrey = holidays.contains(_iso(date));
        final background = isGrey ? PdfColors.grey400 : genderColor;
        String markText = '';
        PdfColor markColor = textColor;
        pw.Font cellFont = font;
        if (fillRecordedAttendance && !isGrey && recordedDays.contains(day)) {
          final dayMark = stuMarks?[day];
          final isPres = dayMark != null && dayMark['present'] == true;
          final isMdm = isPres && dayMark['mdm'] == true;
          final isBf = isPres && dayMark['breakfast'] == true;
          cellFont = latinBoldFont;
          if (!isPres) {
            markText = 'A';
            markColor = PdfColors.black;
          } else {
            markText = 'P';
            if (isMdm && isBf) {
              markColor = const PdfColor.fromInt(0xFFDC2626); // Red = Both PM POSHAN & Breakfast
            } else if (isMdm) {
              markColor = const PdfColor.fromInt(0xFF1D4ED8); // Blue = Only PM POSHAN
            } else if (isBf) {
              markColor = const PdfColor.fromInt(0xFFDB2777); // Pink = Only Breakfast
            } else {
              markColor = PdfColors.black; // Black = Present only (neither MDM nor Breakfast)
            }
          }
        }
        cells.add(_gridCell(markText, cellFont, height: rowHeight, fontSize: fontSize,
            background: background, textColor: markColor, doubleBottom: doubleBottom));
      }
      if (!firstHalf) {
        final priorPresent = stuId.isEmpty ? null : presentDaysByStudentId[stuId];
        int monthPresentCount = 0;
        int monthMdmCount = 0;
        int monthBfCount = 0;
        if (fillRecordedAttendance && stuMarks != null) {
          for (final entry in stuMarks.entries) {
            final d = entry.key;
            final dt = DateTime(year, month, d);
            if (holidays.contains(_iso(dt))) continue;
            if (entry.value['present'] == true) monthPresentCount++;
            if (entry.value['mdm'] == true) monthMdmCount++;
            if (entry.value['breakfast'] == true) monthBfCount++;
          }
        }
        for (var extra = 0; extra < 4; extra++) {
          String cellText = '';
          if (fillRecordedAttendance) {
            if (extra == 0) {
              cellText = recordedDays.isNotEmpty ? '$monthPresentCount' : '';
            } else if (extra == 1) {
              cellText = priorPresent != null ? '$priorPresent' : '';
            } else if (extra == 2) {
              cellText = recordedDays.isNotEmpty
                  ? '${monthPresentCount + (priorPresent ?? 0)}'
                  : (priorPresent != null ? '$priorPresent' : '');
            } else if (extra == 3 && recordedDays.isNotEmpty) {
              cellText = 'M:$monthMdmCount B:$monthBfCount';
            }
          } else {
            cellText = (extra == 1 && priorPresent != null) ? '$priorPresent' : '';
          }
          cells.add(_gridCell(cellText, font, height: rowHeight,
            fontSize: extra == 3 && fillRecordedAttendance ? (fontSize - 1.0).clamp(4.2, 6.8) : fontSize,
            background: genderColor, textColor: textColor, doubleBottom: doubleBottom));
        }
      }
      rows.add(pw.TableRow(children: cells));
    }

    if (isFinalChunk) {
      for (var i = 0; i < blankRows; i++) {
        final emptyCells = <pw.Widget>[];
        for (var column = 0; column < columns.length; column++) {
          var background = PdfColors.white;
          final dayIndex = firstHalf ? column - identityColumnCount : column - 1;
          if (firstHalf && dayIndex >= 0 && dayIndex < days.length) {
            if (holidays.contains(_iso(DateTime(year, month, days[dayIndex])))) background = PdfColors.grey400;
          } else if (!firstHalf && dayIndex >= 0 && dayIndex < days.length) {
            if (holidays.contains(_iso(DateTime(year, month, days[dayIndex])))) background = PdfColors.grey400;
          }
          emptyCells.add(_gridCell('', font, height: rowHeight, fontSize: fontSize, background: background));
        }
        rows.add(pw.TableRow(children: emptyCells));
      }
    }

    final countFooter = () {
      pw.Widget sectionTitle(String label) => pw.Container(
        height: 11,
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(horizontal: 1),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey300,
          border: pw.Border.all(color: PdfColors.black, width: 0.4),
        ),
        child: pw.Text(label, maxLines: 1,
          style: pw.TextStyle(font: font, fontSize: 6.2)),
      );

      pw.Widget summaryCell(String value, {bool emphasized = false, bool left = false}) => pw.Container(
        height: 8.2,
        alignment: left ? pw.Alignment.centerLeft : pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 0.2),
        child: pw.Text(value, maxLines: 1,
          textAlign: left ? pw.TextAlign.left : pw.TextAlign.center,
          style: pw.TextStyle(font: emphasized ? boldFont : font, fontSize: 6.1)),
      );

      pw.Widget categoryBlock({required bool opening}) {
        final labels = <String>['અ.જા.', 'અ.જ.જા.', 'બ.પં.', 'અન્ય', 'કુલ', opening ? '' : 'ગેરહાજર'];
        final keys = <String>['SC', 'ST', 'OBC', 'OTHER', 'TOTAL', ''];
        final rows = <pw.TableRow>[];
        for (var i = 0; i < labels.length; i++) {
          final value = opening && keys[i].isNotEmpty ? '${openingCounts[keys[i]] ?? 0}' : '';
          rows.add(pw.TableRow(children: <pw.Widget>[
            summaryCell(labels[i], emphasized: i == 4, left: true),
            summaryCell(value, emphasized: i == 4),
          ]));
        }
        return pw.Table(
          columnWidths: <int, pw.TableColumnWidth>{
            0: const pw.FlexColumnWidth(1.45),
            1: const pw.FlexColumnWidth(0.65),
          },
          border: pw.TableBorder.all(color: PdfColors.black, width: 0.35),
          children: rows,
        );
      }

      pw.Widget mealLine(String label) => pw.Table(
        columnWidths: <int, pw.TableColumnWidth>{
          0: const pw.FlexColumnWidth(3.0),
          1: const pw.FlexColumnWidth(2.0),
        },
        border: pw.TableBorder.all(color: PdfColors.black, width: 0.35),
        children: <pw.TableRow>[
          pw.TableRow(children: <pw.Widget>[
            pw.Container(height: 11, padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              alignment: pw.Alignment.centerLeft,
              child: pw.Text(label, maxLines: 1, style: pw.TextStyle(font: font, fontSize: 6.0))),
            pw.Container(height: 11, alignment: pw.Alignment.center,
              child: pw.Text('____________________', maxLines: 1,
                style: pw.TextStyle(font: font, fontSize: 5.8))),
          ]),
        ],
      );

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Expanded(child: pw.Column(children: <pw.Widget>[
                sectionTitle('માસની શરૂઆતમાં વિદ્યાર્થીઓની રજીસ્ટર સંખ્યા'),
                categoryBlock(opening: true),
              ])),
              pw.SizedBox(width: 4),
              pw.Expanded(child: pw.Column(children: <pw.Widget>[
                sectionTitle('હાજર વિદ્યાર્થીઓની સંખ્યા'),
                categoryBlock(opening: false),
              ])),
            ],
          ),
          pw.SizedBox(height: 2),
          mealLine('મધ્યાહ્ન ભોજનમાં ભાગ લીધેલ વિદ્યાર્થીઓની સંખ્યા'),
          mealLine('અલ્પાહારમાં ભાગ લીધેલ વિદ્યાર્થીઓની સંખ્યા'),
        ],
      );
    };
    final attendanceFooter = pw.Table(
      columnWidths: <int, pw.TableColumnWidth>{
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(3),
      },
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.45),
      children: <pw.TableRow>[
        pw.TableRow(children: <pw.Widget>[
          pw.Container(height: 22, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.centerLeft,
            child: pw.Text('હાજરી સરાસરી =', style: pw.TextStyle(font: font, fontSize: 7))),
          pw.Container(height: 22, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center,
            child: pw.Text('____________ = ____________', style: pw.TextStyle(font: font, fontSize: 7))),
        ]),
        pw.TableRow(children: <pw.Widget>[
          pw.Container(height: 22, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.centerLeft,
            child: pw.Text('માધ્યાહ્ન ભોજન સરાસરી =', style: pw.TextStyle(font: font, fontSize: 7))),
          pw.Container(height: 22, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center,
            child: pw.Text('____________ = ____________', style: pw.TextStyle(font: font, fontSize: 7))),
        ]),
      ],
    );

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: firstHalf
          ? const pw.EdgeInsets.fromLTRB(10, 9, 22, 9)
          : const pw.EdgeInsets.fromLTRB(22, 9, 10, 9),
      theme: pw.ThemeData.withFont(base: font, bold: boldFont),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          pw.Center(child: pw.Text(firstHalf
              ? 'ધોરણ - ${_classValue(classLabel)}     ${monthNamesGujarati[month - 1]} - $year માસનું'
              : 'વિદ્યાર્થીઓનું હાજરી પત્રક',
            style: pw.TextStyle(font: font, fontSize: firstHalf ? 9 : 10))),
          pw.SizedBox(height: 4),
          pw.Table(columnWidths: widths, children: rows),
          if (isFinalChunk) ...<pw.Widget>[
            pw.SizedBox(height: 4),
            if (firstHalf) countFooter() else attendanceFooter,
          ],
        ],
      ),
    );
  }

  pw.Widget _gridCell(
    String value,
    pw.Font font, {
    required double height,
    required double fontSize,
    PdfColor background = PdfColors.white,
    PdfColor textColor = PdfColors.black,
    bool doubleBottom = false,
    bool alignLeft = false,
    bool singleLine = false,
  }) {
    return pw.Container(
      height: height,
      padding: pw.EdgeInsets.symmetric(horizontal: alignLeft ? 2.2 : 0.8, vertical: 0.6),
      decoration: pw.BoxDecoration(
        color: background,
        border: pw.Border.all(color: PdfColors.black, width: 0.35),
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Align(
              alignment: alignLeft ? pw.Alignment.centerLeft : pw.Alignment.center,
              child: pw.Text(
                value,
                maxLines: singleLine ? 1 : 2,
                overflow: pw.TextOverflow.clip,
                textAlign: alignLeft ? pw.TextAlign.left : pw.TextAlign.center,
                style: pw.TextStyle(font: font, fontSize: fontSize, color: textColor),
              ),
            ),
          ),
          if (doubleBottom) ...<pw.Widget>[
            pw.Container(height: 0.45, color: PdfColors.black),
            pw.SizedBox(height: 0.7),
            pw.Container(height: 0.45, color: PdfColors.black),
          ],
        ],
      ),
    );
  }

  PdfColor _categoryColor(String category) {
    switch (category) {
      case 'SC': return PdfColors.red;
      case 'ST': return PdfColors.brown;
      case 'OBC': return PdfColors.black;
      default: return PdfColors.blue;
    }
  }

  String _categoryLabel(String category) {
    final index = _categories.indexOf(category);
    return index < 0 ? _categoryGujarati.last : _categoryGujarati[index];
  }
}

import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import '../models/models.dart';
import 'datewise_report_columns.dart';
import 'school_class_order.dart';
import 'supabase_school_settings_service.dart';
import 'school_type.dart';

/// Read-only attendance report adapter for the Supabase-backed app.
/// It does not create attendance rows while opening a report.
class SupabaseAttendanceReportService {
  SupabaseAttendanceReportService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<String> _schoolRef() async {
    if (_client.auth.currentUser == null) {
      throw StateError('Please sign in again.');
    }
    // This existing SECURITY DEFINER RPC resolves the tenant from auth.uid().
    // It avoids directly selecting school_teachers, which is intentionally
    // restricted by RLS in this multi-school application.
    final value = await _client.rpc('current_school_ref');
    if (value == null || '$value'.trim().isEmpty) {
      throw StateError('The signed-in teacher has no active school.');
    }
    return '$value';
  }

  /// Read-only schoolwide aggregate rows for reporting. The SECURITY DEFINER
  /// RPC returns no student names, IDs, mobile numbers, or private details; it
  /// does not change the class-scoped policies used for roster/attendance edits.
  Future<List<Map<String, dynamic>>> getSchoolwideAttendanceRows({
    String? fromDate,
    String? toDate,
  }) async {
    await _schoolRef();
    final response = await _client.rpc(
      'schoolwide_attendance_report_rows',
      params: <String, dynamic>{'p_from_date': fromDate, 'p_to_date': toDate},
    );
    if (response is! List) {
      throw StateError(
        'Supabase returned an invalid schoolwide report response.',
      );
    }
    return response
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  String _clean(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<List<Map<String, dynamic>>> _classes(String schoolRef) async {
    final rows = await _client
        .from('school_classes')
        .select(
          'id,school_ref,class_key,label,sheet_name,standard,section,report_group,is_active,sort_order',
        )
        .eq('school_ref', schoolRef)
        .eq('is_active', true)
        .order('sort_order');
    return SchoolClassOrder.sorted(
      rows.map((row) => Map<String, dynamic>.from(row)),
    );
  }

  Future<Map<String, dynamic>> _findClass(String classKey) async {
    final schoolRef = await _schoolRef();
    final classes = await _classes(schoolRef);
    final wanted = _clean(classKey);
    for (final row in classes) {
      final options = <String>[
        '${row['id'] ?? ''}',
        '${row['class_key'] ?? ''}',
        '${row['label'] ?? ''}',
        '${row['sheet_name'] ?? ''}',
      ];
      if (options.any((v) => _clean(v) == wanted)) return row;
    }
    throw StateError(
      'Class not found or not assigned to this teacher: $classKey',
    );
  }

  Map<String, dynamic> _asJsonMap(dynamic value) {
    if (value is Map) return value.map((key, value) => MapEntry('$key', value));
    return <String, dynamic>{};
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  CategoryCounts _counts(dynamic value) {
    final map = _asJsonMap(value);
    return CategoryCounts.fromJson(map);
  }

  Map<String, dynamic> _buildGenderBreakdown(
    List<Map<String, dynamic>> students,
    List<Map<String, dynamic>> marks,
  ) {
    const genders = <String>['BOYS', 'GIRLS', 'UNSPECIFIED'];
    const categories = <String>['SC', 'ST', 'OBC', 'OTHER'];
    const metrics = <String>['registered', 'present', 'mdm', 'breakfast'];
    final out = <String, dynamic>{};
    final markByStudent = <String, Map<String, dynamic>>{
      for (final mark in marks) '${mark['student_id'] ?? ''}': mark,
    };

    for (final gender in genders) {
      final byCategory = <String, dynamic>{};
      final overall = <String, int>{for (final metric in metrics) metric: 0};
      for (final category in categories) {
        byCategory[category] = <String, int>{
          for (final metric in metrics) metric: 0,
        };
      }
      out[gender] = byCategory;
      (out[gender] as Map<String, dynamic>)['_OVERALL'] = overall;
    }

    for (final student in students) {
      final rawCategory = '${student['category'] ?? 'OTHER'}'
          .trim()
          .toUpperCase();
      final category = categories.contains(rawCategory) ? rawCategory : 'OTHER';
      final rawGender = '${student['gender'] ?? 'UNSPECIFIED'}'
          .trim()
          .toUpperCase();
      final gender = genders.contains(rawGender) ? rawGender : 'UNSPECIFIED';
      final mark =
          markByStudent['${student['id']}'] ?? const <String, dynamic>{};
      final values = <String, int>{
        'registered': 1,
        'present': mark['present'] == true ? 1 : 0,
        'mdm': mark['mdm'] == true ? 1 : 0,
        'breakfast': mark['breakfast'] == true ? 1 : 0,
      };
      final group =
          (out[gender] as Map<String, dynamic>)[category]
              as Map<String, dynamic>;
      final overall =
          (out[gender] as Map<String, dynamic>)['_OVERALL']
              as Map<String, dynamic>;
      for (final metric in metrics) {
        group[metric] = _asInt(group[metric]) + values[metric]!;
        overall[metric] = _asInt(overall[metric]) + values[metric]!;
      }
    }
    return out;
  }

  Future<RowData> getRowData(String classKey, String date) async {
    final schoolRef = await _schoolRef();
    final classRow = await _findClass(classKey);
    final classId = '${classRow['id']}';

    final studentsRaw = await _client
        .from('students')
        .select('id,roll_number,name,category,gender,is_active')
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .eq('is_active', true)
        .order('roll_number');
    final students = studentsRaw
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    final dayRaw = await _client
        .from('attendance_days')
        .select('*')
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .eq('attendance_date', date)
        .maybeSingle();

    final CategoryCounts rosterCounts;
    final rosterJson = <String, int>{'SC': 0, 'ST': 0, 'OBC': 0, 'OTHER': 0};
    for (final student in students) {
      final raw = '${student['category'] ?? 'OTHER'}'.trim().toUpperCase();
      rosterJson[rosterJson.containsKey(raw) ? raw : 'OTHER'] =
          (rosterJson[rosterJson.containsKey(raw) ? raw : 'OTHER'] ?? 0) + 1;
    }
    rosterCounts = CategoryCounts.fromJson(rosterJson);

    if (dayRaw == null) {
      return RowData(
        registered: rosterCounts,
        attendance: null,
        genderBreakdown: _buildGenderBreakdown(students, const []),
      );
    }

    final day = Map<String, dynamic>.from(dayRaw);
    final registered = day['registered_counts'] == null
        ? rosterCounts
        : _counts(day['registered_counts']);
    final present = _counts(day['present_counts']);
    final mdm = _counts(day['mdm_counts']);
    final savedGender = _asJsonMap(day['gender_breakdown']);
    List<Map<String, dynamic>> marks = const <Map<String, dynamic>>[];
    if (savedGender.isEmpty) {
      final marksRaw = await _client
          .from('student_attendance')
          .select('student_id,present,mdm,breakfast')
          .eq('school_ref', schoolRef)
          .eq('class_id', classId)
          .eq('attendance_day_id', '${day['id']}');
      marks = marksRaw
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    final genderBreakdown = savedGender.isNotEmpty
        ? savedGender
        : _buildGenderBreakdown(students, marks);
    final attendance = AttendanceRecord(
      registered: registered,
      present: present,
      mdm: mdm,
      breakfastTotal: _asInt(day['breakfast_total']),
      genderBreakdown: genderBreakdown,
    );

    return RowData(
      registered: registered,
      attendance: attendance,
      students: const [],
      studentDetailsSaved: day['student_details_saved'] == true,
      attendanceMode: '${day['attendance_mode'] ?? 'none'}',
      genderBreakdown: genderBreakdown,
    );
  }

  Future<Map<String, AttendanceRecord>> getAttendanceHistory(
    String classKey,
  ) async {
    final schoolRef = await _schoolRef();
    final classRow = await _findClass(classKey);
    final rows = await _client
        .from('attendance_days')
        .select(
          'attendance_date,registered_counts,present_counts,mdm_counts,breakfast_total,gender_breakdown',
        )
        .eq('school_ref', schoolRef)
        .eq('class_id', '${classRow['id']}')
        .order('attendance_date');

    final out = <String, AttendanceRecord>{};
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      final date = '${row['attendance_date'] ?? ''}';
      if (date.isEmpty) continue;
      final registered = _counts(row['registered_counts']);
      out[date] = AttendanceRecord(
        registered: registered,
        present: _counts(row['present_counts']),
        mdm: _counts(row['mdm_counts']),
        breakfastTotal: _asInt(row['breakfast_total']),
        genderBreakdown: _asJsonMap(row['gender_breakdown']),
      );
    }
    return out;
  }

  /// Returns a dated, school/class-scoped table payload for the existing RawGridTable.
  /// Only dates already saved in attendance_days are shown; opening a report never
  /// inserts a day or copies another date's statuses.
  int _dateWiseValue(
    Map<String, dynamic> breakdown,
    DateWiseReportColumn column,
  ) {
    const genders = <String>['BOYS', 'GIRLS', 'UNSPECIFIED'];
    const categories = <String>['SC', 'ST', 'OBC', 'OTHER'];

    int getValue(String gender, String category, String metric) {
      final group = _asJsonMap(breakdown[gender]);
      if (category == 'CATEGORY_TOTAL') {
        final overall = _asJsonMap(group['_OVERALL']);
        if (overall.containsKey(metric)) return _asInt(overall[metric]);
        return categories.fold<int>(
          0,
          (sum, key) => sum + getValue(gender, key, metric),
        );
      }
      final categoryMap = _asJsonMap(group[category]);
      return _asInt(categoryMap[metric]);
    }

    if (column.gender == 'TOTAL') {
      // Official school total is Boys + Girls, not an inferred total that
      // silently includes students whose gender was never recorded.
      return getValue('BOYS', column.category, column.metric) +
          getValue('GIRLS', column.category, column.metric);
    }
    return getValue(column.gender, column.category, column.metric);
  }

  /// Loads the school's saved DATE WISE data-column selection.
  /// This delegates to the same settings service used by Admin Setup so the
  /// Admin dialog and report renderer share one school-wide source of truth.
  Future<List<String>> getDateWiseSelectedColumnKeys() {
    return SupabaseSchoolSettingsService(client: _client)
        .visibleDateWiseColumns();
  }

  /// Saves the school-wide DATE WISE column selection. The settings service
  /// verifies the caller is a School Admin, merges the config (preserving
  /// attendance_lock_time and other settings), and relies on database RLS.
  Future<void> saveDateWiseSelectedColumnKeys(Iterable<String> keys) async {
    await SupabaseSchoolSettingsService(client: _client)
        .saveVisibleDateWiseColumns(keys);
  }

  Future<List<String>> getTarijSelectedColumnKeys() {
    return SupabaseSchoolSettingsService(client: _client)
        .visibleTarijColumnKeys();
  }

  Future<void> saveTarijSelectedColumnKeys(Iterable<String> keys) async {
    await SupabaseSchoolSettingsService(client: _client)
        .saveVisibleTarijColumns(keys);
  }

  /// Read-only monthly demographic movement aggregates. No student identity
  /// fields are returned; use only for TARIJ calculations.
  Future<List<Map<String, dynamic>>> getSchoolwideTarijStudentCounts({
    required String monthStart,
    required String monthEnd,
  }) async {
    await _schoolRef();
    final response = await _client.rpc(
      'schoolwide_tarij_student_counts',
      params: <String, dynamic>{
        'p_month_start': monthStart,
        'p_month_end': monthEnd,
      },
    );
    if (response is! List) {
      throw StateError('Supabase returned an invalid TARIJ response.');
    }
    return response
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  /// Daily-only reader. For single-gender schools, roster counts with no saved
  /// student gender are attributed to the school's configured gender. Mixed
  /// schools continue to leave UNSPECIFIED students out of Boys/Girls totals.
  int _dailyReportValue(
    Map<String, dynamic> row,
    Map<String, dynamic> breakdown,
    DateWiseReportColumn column,
  ) {
    // Direct Entry stores class/category totals, not individual student marks.
    // Use those authoritative aggregates for attendance/MDM/breakfast while
    // the RPC still supplies a roster-derived gender split for registration.
    if (column.metric != 'registered' &&
        '${row['attendance_mode'] ?? ''}'.trim().toLowerCase() == 'direct') {
      return _schoolwideDateWiseValue(row, <String, dynamic>{}, column);
    }

    final schoolType = SchoolType.canonical(row['school_type']);
    if (breakdown.isEmpty || (schoolType != 'boys' && schoolType != 'girls')) {
      return _schoolwideDateWiseValue(row, breakdown, column);
    }

    final targetGender = schoolType == 'boys' ? 'BOYS' : 'GIRLS';
    final adjusted = Map<String, dynamic>.from(breakdown);
    final targetPayload = _asJsonMap(adjusted[targetGender]);
    final unspecifiedPayload = _asJsonMap(adjusted['UNSPECIFIED']);
    for (final key in <String>['SC', 'ST', 'OBC', 'OTHER', '_OVERALL']) {
      final targetCounts = _asJsonMap(targetPayload[key]);
      final unspecifiedCounts = _asJsonMap(unspecifiedPayload[key]);
      for (final metric in <String>[
        'registered',
        'present',
        'mdm',
        'breakfast',
      ]) {
        targetCounts[metric] =
            _asInt(targetCounts[metric]) + _asInt(unspecifiedCounts[metric]);
      }
      targetPayload[key] = targetCounts;
    }
    adjusted[targetGender] = targetPayload;
    return _schoolwideDateWiseValue(row, adjusted, column);
  }

  Future<Map<String, dynamic>> getDailyReportRowsByDate(
    String date, {
    String classGroup = SchoolClassOrder.all,
  }) async {
    final schoolRef = await _schoolRef();
    final response = await _client.rpc(
      'schoolwide_daily_report_rows',
      params: <String, dynamic>{'p_date': date},
    );
    if (response is! List) {
      throw StateError('Supabase returned an invalid Daily DATEWISE response.');
    }
    final allClasses = SchoolClassOrder.sorted(
      response
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .where((row) => SchoolClassOrder.matches(row, classGroup))
          .toList(),
    );

    final settingsRow = await _client
        .from('school_settings')
        .select('config')
        .eq('school_ref', schoolRef)
        .maybeSingle();
    final config = _asJsonMap(settingsRow?['config']);
    final selectedKeys = await getDateWiseSelectedColumnKeys();
    final effectiveSelectedKeys = selectedKeys.isEmpty
        ? DateWiseReportColumn.allKeys
        : selectedKeys.toSet().intersection(DateWiseReportColumn.allKeys);
    final columns = DateWiseReportColumn.all
        .where((column) => effectiveSelectedKeys.contains(column.key))
        .toList();

    bool hasSavedDay(Map<String, dynamic> row) =>
        '${row['attendance_date'] ?? ''}' == date;

    final values = <List<String>>[
      <String>['વર્ગ', ...columns.map((column) => column.label)],
    ];
    void addClass(Map<String, dynamic> classRow) {
      final saved = hasSavedDay(classRow);
      final breakdown = _asJsonMap(classRow['gender_breakdown']);
      values.add(<String>[
        '${classRow['class_label'] ?? classRow['label'] ?? classRow['class_key'] ?? ''}',
        for (final column in columns)
          column.metric != 'registered' && !saved
              ? ''
              : '${_dailyReportValue(classRow, breakdown, column)}',
      ]);
    }

    void addTotal(String label, List<Map<String, dynamic>> included) {
      if (included.isEmpty) return;
      final totalValues = <String>[label];
      for (final column in columns) {
        final eligible = column.metric == 'registered'
            ? included
            : included.where(hasSavedDay).toList();
        if (eligible.isEmpty) {
          totalValues.add('');
        } else {
          final total = eligible.fold<int>(
            0,
            (sum, row) =>
                sum +
                _dailyReportValue(
                  row,
                  _asJsonMap(row['gender_breakdown']),
                  column,
                ),
          );
          totalValues.add('$total');
        }
      }
      values.add(totalValues);
    }

    final balvatika = allClasses
        .where(
          (row) => SchoolClassOrder.groupOf(row) == SchoolClassOrder.balvatika,
        )
        .toList();
    final std1to5 = allClasses
        .where(
          (row) =>
              SchoolClassOrder.groupOf(row) == SchoolClassOrder.standards1to5,
        )
        .toList();
    final std6to8 = allClasses
        .where(
          (row) =>
              SchoolClassOrder.groupOf(row) == SchoolClassOrder.standards6to8,
        )
        .toList();
    final other = allClasses.where((row) {
      final group = SchoolClassOrder.groupOf(row);
      return group != SchoolClassOrder.balvatika &&
          group != SchoolClassOrder.standards1to5 &&
          group != SchoolClassOrder.standards6to8;
    }).toList();

    for (final row in balvatika) {
      addClass(row);
    }
    if (balvatika.length > 1) addTotal('કુલ બાલવાટિકા', balvatika);
    for (final row in std1to5) {
      addClass(row);
    }
    addTotal('કુલ ધોરણ 1 થી 5', std1to5);
    addTotal('કુલ બાલવાટિકા થી ધોરણ 5', <Map<String, dynamic>>[
      ...balvatika,
      ...std1to5,
    ]);
    for (final row in std6to8) {
      addClass(row);
    }
    addTotal('કુલ ધોરણ 6 થી 8', std6to8);
    addTotal('કુલ ધોરણ 1 થી 8', <Map<String, dynamic>>[...std1to5, ...std6to8]);
    for (final row in other) {
      addClass(row);
    }
    addTotal('કુલ શાળા', allClasses);
    if (allClasses.isEmpty) {
      values.add(<String>[
        'કોઈ સક્રિય વર્ગ ઉપલબ્ધ નથી',
        for (var i = 0; i < columns.length; i++) '',
      ]);
    }

    // Serial is the ordinal of this distinct recorded attendance date for
    // the school. A date counts once when any class has a saved attendance day.
    // If no class has saved attendance for this selected date, leave it blank.
    final rawSerial = await _client.rpc(
      'school_attendance_day_serial',
      params: <String, dynamic>{'p_date': date},
    );
    final parsedSerial = rawSerial is num
        ? rawSerial.toInt()
        : int.tryParse('${rawSerial ?? ''}') ?? 0;

    return <String, dynamic>{
      'result': 'success',
      'serial': parsedSerial > 0 ? '$parsedSerial' : '',
      'date': date,
      'class_group': classGroup,
      'saved_class_count': allClasses.where(hasSavedDay).length,
      'classRows': allClasses,
      'school_address': '${config['school_address'] ?? ''}',
      'values': values,
    };
  }

  Future<void> saveSchoolAddress(String address) async {
    final schoolRef = await _schoolRef();
    final existing = await _client
        .from('school_settings')
        .select('config')
        .eq('school_ref', schoolRef)
        .maybeSingle();
    final config = _asJsonMap(existing?['config']);
    config['school_address'] = address.trim();
    await _client.from('school_settings').upsert(<String, dynamic>{
      'school_ref': schoolRef,
      'config': config,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Returns the full school DATE WISE data, narrowed by the requested
  /// report group and the school's saved flat 60-column selection.
  /// It only includes attendance_days rows that already exist for this date;
  /// opening a report never inserts a day or copies a previous day's statuses.
  Future<Map<String, dynamic>> getDateWiseReportByDate(
    String date, {
    String classGroup = SchoolClassOrder.all,
  }) async {
    final allRows = await getSchoolwideAttendanceRows(
      fromDate: date,
      toDate: date,
    );
    final classes = SchoolClassOrder.sorted(allRows)
        .where((row) => SchoolClassOrder.matches(row, classGroup))
        .toList();
    final selectedKeys = await getDateWiseSelectedColumnKeys();
    final effectiveSelectedKeys = selectedKeys.isEmpty
        ? DateWiseReportColumn.allKeys
        : selectedKeys.toSet();
    final columns = DateWiseReportColumn.all
        .where((column) => effectiveSelectedKeys.contains(column.key))
        .toList();

    final values = <List<String>>[
      <String>['વર્ગ', ...columns.map((column) => column.label)],
    ];
    final columnTotals = List<int>.filled(columns.length, 0);
    var savedClassCount = 0;

    for (final classRow in classes) {
      final label =
          '${classRow['class_label'] ?? classRow['label'] ?? classRow['class_key'] ?? ''}';
      final hasSavedDay = '${classRow['attendance_date'] ?? ''}' == date;
      if (!hasSavedDay) {
        // Keep the class on the school-wide report, but don't invent counts
        // when that teacher hasn't saved attendance for this date.
        values.add(<String>[
          label,
          for (var i = 0; i < columns.length; i++) '',
        ]);
        continue;
      }

      final breakdown = _asJsonMap(classRow['gender_breakdown']);
      final rowValues = <String>[label];
      for (var i = 0; i < columns.length; i++) {
        final value = _schoolwideDateWiseValue(classRow, breakdown, columns[i]);
        rowValues.add('$value');
        columnTotals[i] += value;
      }
      savedClassCount++;
      values.add(rowValues);
    }

    if (savedClassCount == 0) {
      values.add(<String>[
        'આ તારીખે કોઈ વર્ગની હાજરી સેવ થયેલી નથી.',
        for (var i = 0; i < columns.length; i++) '',
      ]);
    } else {
      values.add(<String>['કુલ', for (final value in columnTotals) '$value']);
    }

    return <String, dynamic>{
      'result': 'success',
      'serial': '',
      'date': date,
      'class_group': classGroup,
      'saved_class_count': savedClassCount,
      'values': values,
    };
  }

  int _schoolwideDateWiseValue(
    Map<String, dynamic> row,
    Map<String, dynamic> breakdown,
    DateWiseReportColumn column,
  ) {
    // Whole-class Direct Entry stores breakfast_total without inventing a caste/gender split.
    // Always show that authoritative value in the school TOTAL column.
    if (column.metric == 'breakfast' &&
        column.category == 'CATEGORY_TOTAL' &&
        column.gender == 'TOTAL') {
      return _asInt(row['breakfast_total']);
    }

    const categories = <String>['SC', 'ST', 'OBC', 'OTHER'];

    int readCategory(Map<String, dynamic> genderData, String category) =>
        _asInt(_asJsonMap(genderData[category])[column.metric]);

    int readMetric(String gender, String category) {
      final genderData = _asJsonMap(breakdown[gender]);
      if (category == 'CATEGORY_TOTAL') {
        final overall = _asJsonMap(genderData['_OVERALL']);
        if (overall.containsKey(column.metric))
          return _asInt(overall[column.metric]);
        return categories.fold<int>(
          0,
          (sum, categoryKey) => sum + readCategory(genderData, categoryKey),
        );
      }
      return readCategory(genderData, category);
    }

    final schoolType = SchoolType.canonical(row["school_type"]);
    final isBoysSchool = schoolType == SchoolType.boys;
    final isGirlsSchool = schoolType == SchoolType.girls;
    final isBreakdownEmpty = breakdown.isEmpty;
    if (!isBreakdownEmpty) {
      final boysVal = readMetric('BOYS', column.category) +
          (isBoysSchool ? readMetric('UNSPECIFIED', column.category) : 0);
      final girlsVal = readMetric('GIRLS', column.category) +
          (isGirlsSchool ? readMetric('UNSPECIFIED', column.category) : 0);
      final unspecVal = (!isBoysSchool && !isGirlsSchool)
          ? readMetric('UNSPECIFIED', column.category)
          : 0;
      final sumBreakdown = boysVal + girlsVal + unspecVal;
      final overallBreakdown = readMetric('BOYS', 'CATEGORY_TOTAL') +
          readMetric('GIRLS', 'CATEGORY_TOTAL') +
          readMetric('UNSPECIFIED', 'CATEGORY_TOTAL');
      if (overallBreakdown > 0 || sumBreakdown > 0) {
        if (column.gender == 'TOTAL') {
          return boysVal + girlsVal + unspecVal;
        }
        if (column.gender == 'BOYS') return boysVal;
        if (column.gender == 'GIRLS') return girlsVal;
        return readMetric(column.gender, column.category);
      }
    }

    // Fallback for older saved rows without a gender_breakdown snapshot.
    // Category totals are authoritative. Gender is only attributed when the
    // school's declared type is single-gender; mixed-school counts are never
    // guessed into Boys or Girls.
    final sourceKey = switch (column.metric) {
      'registered' => 'registered_counts',
      'present' => 'present_counts',
      'mdm' => 'mdm_counts',
      _ => '',
    };
    int categoryTotal() {
      if (column.metric == 'breakfast') {
        return column.category == 'CATEGORY_TOTAL'
            ? _asInt(row['breakfast_total'])
            : 0;
      }
      final map = _asJsonMap(row[sourceKey]);
      if (column.category == 'CATEGORY_TOTAL') {
        return categories.fold<int>(0, (sum, key) => sum + _asInt(map[key]));
      }
      return _asInt(map[column.category]);
    }

    final total = categoryTotal();
    if (column.gender == 'TOTAL') return total;
    if (isBoysSchool && column.gender == 'BOYS') return total;
    if (isGirlsSchool && column.gender == 'GIRLS') return total;
    return 0;
  }
}

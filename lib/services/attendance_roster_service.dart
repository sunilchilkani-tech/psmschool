import 'package:pmshri_attendance/services/firebase_backend_client.dart';

/// Roster-driven attendance service. An empty/new date never copies yesterday's status values.
class AttendanceRosterService {
  AttendanceRosterService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<String> _schoolRef() async {
    final value = await _client.rpc('current_school_ref');
    if (value == null || '$value'.isEmpty) throw StateError('No active school is linked to this login.');
    return '$value';
  }

  Future<String> _teacherId() async {
    final value = await _client.rpc('current_teacher_id');
    if (value == null || '$value'.isEmpty) throw StateError('No active teacher is linked to this login.');
    return '$value';
  }

  Future<List<Map<String, dynamic>>> loadActiveRoster(String classId) async {
    final rows = await _client.from('students').select(
      'id,school_ref,class_id,roll_number,name,category,gender,is_active'
    ).eq('class_id', classId).eq('is_active', true).order('roll_number');
    return rows.map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<Map<String, dynamic>?> loadDay(String classId, DateTime date) async {
    final row = await _client.from('attendance_days')
        .select()
        .eq('class_id', classId)
        .eq('attendance_date', _dateOnly(date))
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<AttendanceDayBundle> loadForEntry(String classId, DateTime date) async {
    final roster = await loadActiveRoster(classId);
    final day = await loadDay(classId, date);
    if (day == null) {
      return AttendanceDayBundle(
        attendanceDay: null,
        roster: roster,
        statusesByStudentId: const {},
      );
    }
    final marks = await _client.from('student_attendance')
        .select('student_id,present,mdm,breakfast')
        .eq('attendance_day_id', day['id']);
    final statuses = <String, Map<String, dynamic>>{};
    for (final row in marks) {
      statuses['${row['student_id']}'] = Map<String, dynamic>.from(row);
    }
    return AttendanceDayBundle(
      attendanceDay: day,
      roster: roster,
      statusesByStudentId: statuses,
    );
  }

  /// Save one date's roster statuses and refresh all summary/gender/category counts on the DB.
  /// Each status item must contain student_id (or id), present, mdm, and breakfast booleans.
  Future<Map<String, dynamic>> saveStudentAttendance({
    required String classId,
    required DateTime date,
    required List<Map<String, dynamic>> statuses,
    String attendanceMode = 'student',
    bool studentDetailsSaved = true,
  }) async {
    final schoolRef = await _schoolRef();
    final teacherId = await _teacherId();
    final dayDate = _dateOnly(date);
    final row = await _client.from('attendance_days').upsert({
      'school_ref': schoolRef,
      'class_id': classId,
      'attendance_date': dayDate,
      'attendance_mode': attendanceMode,
      'student_details_saved': studentDetailsSaved,
      'updated_by_teacher': teacherId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'school_ref,class_id,attendance_date').select().single();
    final day = Map<String, dynamic>.from(row);

    final roster = await loadActiveRoster(classId);
    final validStudentIds = roster.map((s) => '${s['id']}').toSet();
    final statusRows = <Map<String, dynamic>>[];
    for (final status in statuses) {
      final studentId = '${status['student_id'] ?? status['id'] ?? ''}';
      if (!validStudentIds.contains(studentId)) continue;
      final present = status['present'] == true || status['mdm'] == true || status['breakfast'] == true;
      statusRows.add({
        'school_ref': schoolRef,
        'class_id': classId,
        'attendance_day_id': day['id'],
        'student_id': studentId,
        'present': present,
        'mdm': present && status['mdm'] == true,
        'breakfast': present && status['breakfast'] == true,
        'updated_by_teacher': teacherId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
    if (statusRows.isNotEmpty) {
      await _client.from('student_attendance').upsert(
        statusRows,
        onConflict: 'attendance_day_id,student_id',
      );
    }

    // The migration function recalculates registered/present/MDM/breakfast totals and gender breakdown.
    await _client.rpc('refresh_attendance_day_counts', params: {
      'p_attendance_day_id': day['id'],
    });
    final refreshed = await _client.from('attendance_days').select()
        .eq('id', day['id']).single();
    return Map<String, dynamic>.from(refreshed);
  }

  /// A direct-entry aggregate save for schools that do not use individual student statuses.
  /// Values use the current Dart model's category JSON keys: SC, ST, OBC, OTHER.
  Future<Map<String, dynamic>> saveAggregateAttendance({
    required String classId,
    required DateTime date,
    required Map<String, int> registeredCounts,
    required Map<String, int> presentCounts,
    required Map<String, int> mdmCounts,
    required int breakfastTotal,
    required Map<String, dynamic> genderBreakdown,
    String attendanceMode = 'direct',
    bool studentDetailsSaved = false,
  }) async {
    final schoolRef = await _schoolRef();
    final teacherId = await _teacherId();
    final totals = [
      ...registeredCounts.values,
      ...presentCounts.values,
      ...mdmCounts.values,
      breakfastTotal,
    ];
    if (totals.any((v) => v < 0)) throw ArgumentError('Attendance counts cannot be negative.');
    final presentTotal = presentCounts.values.fold<int>(0, (a, b) => a + b);
    final registeredTotal = registeredCounts.values.fold<int>(0, (a, b) => a + b);
    final mdmTotal = mdmCounts.values.fold<int>(0, (a, b) => a + b);
    if (presentTotal > registeredTotal) {
      throw ArgumentError('Present total cannot exceed the registered total.');
    }
    for (final category in const ['SC', 'ST', 'OBC', 'OTHER']) {
      if ((presentCounts[category] ?? 0) > (registeredCounts[category] ?? 0)) {
        throw ArgumentError('$category present count cannot exceed registered count.');
      }
      if ((mdmCounts[category] ?? 0) > (presentCounts[category] ?? 0)) {
        throw ArgumentError('$category PM POSHAN count cannot exceed present count.');
      }
    }
    if (mdmTotal > presentTotal || breakfastTotal > presentTotal) {
      throw ArgumentError('PM POSHAN and breakfast totals cannot exceed present count.');
    }
    final row = await _client.from('attendance_days').upsert({
      'school_ref': schoolRef,
      'class_id': classId,
      'attendance_date': _dateOnly(date),
      'registered_counts': _normalizedCounts(registeredCounts),
      'present_counts': _normalizedCounts(presentCounts),
      'mdm_counts': _normalizedCounts(mdmCounts),
      'breakfast_total': breakfastTotal,
      'gender_breakdown': genderBreakdown,
      'attendance_mode': attendanceMode,
      'student_details_saved': studentDetailsSaved,
      'updated_by_teacher': teacherId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'school_ref,class_id,attendance_date').select().single();
    return Map<String, dynamic>.from(row);
  }

  Map<String, int> _normalizedCounts(Map<String, int> source) => {
    for (final key in const ['SC', 'ST', 'OBC', 'OTHER']) key: source[key] ?? 0,
  };

  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class AttendanceDayBundle {
  const AttendanceDayBundle({
    required this.attendanceDay,
    required this.roster,
    required this.statusesByStudentId,
  });

  final Map<String, dynamic>? attendanceDay;
  final List<Map<String, dynamic>> roster;
  final Map<String, Map<String, dynamic>> statusesByStudentId;
}

/// Attendance lifecycle and monthly register inclusion rules.
///
/// Business rules:
/// 1. Because a monthly attendance register (Hajari Patrak) is printed BEFORE
///    the 1st day of the new month, a student newly enrolled during month M
///    (from day 1 through the last day of month M) is excluded from month M's
///    printed register and first appears in month (M + 1)'s register.
///    (Exception: June is the start of the new academic year in Gujarat schools;
///    students enrolled on or before June 1st or promoted into the class at the
///    start of the academic year are included from June.)
/// 2. A student who leaves school during month M (even on the 1st of month M)
///    was on the roll when month M's register was printed, so they MUST remain
///    on month M's register and are excluded starting in month (M + 1).
/// 3. Within a student's leaving month M, their attendance calculation window
///    runs from day 1 of month M through `leaving_date` (inclusive). Dates after
///    `leaving_date` are never counted as absent or open instructional days for
///    that student.
class AttendanceLifecycle {
  static const String reasonLeavingCertificate = 'lc';
  static const String reasonContinuousAbsence = 'continuous_absence';

  static const String labelLeavingCertificate =
      'ચાલુ માસમાં લિ. સર્ટી. લઈ ગયેલ';
  static const String labelContinuousAbsence =
      'સતત ગેરહાજરીથી નામ કમી કરેલ';

  static DateTime day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime firstOfMonth(DateTime value) =>
      DateTime(value.year, value.month, 1);

  static DateTime lastOfMonth(DateTime value) =>
      DateTime(value.year, value.month + 1, 0);

  /// First register month is the month AFTER admission/enrolment, except for
  /// June (month == 6), which is the start of the new academic year in Gujarat
  /// schools so students admitted in June are included from June's register.
  static DateTime firstRegisterMonth(DateTime enrolledOn) =>
      enrolledOn.month == 6
          ? DateTime(enrolledOn.year, 6, 1)
          : DateTime(enrolledOn.year, enrolledOn.month + 1, 1);

  /// Student remains on the register through the whole leaving month.
  static DateTime? lastRegisterMonth(DateTime? leftOn) =>
      leftOn == null ? null : DateTime(leftOn.year, leftOn.month, 1);

  /// Evaluates whether a student belongs on the printed monthly attendance
  /// register for [registerMonth].
  static bool includeInMonthlyRegister({
    required DateTime registerMonth,
    required DateTime enrolledOn,
    DateTime? leftOn,
  }) {
    final month = firstOfMonth(registerMonth);
    final first = firstRegisterMonth(enrolledOn);
    final last = lastRegisterMonth(leftOn);
    if (month.isBefore(first)) return false;
    if (last != null && month.isAfter(last)) return false;
    return true;
  }

  /// Attendance calculation window for a student within one month.
  /// Joining month is not counted on the pre-printed register, so start is
  /// always day 1 of the first eligible register month. Leaving date itself is
  /// counted; dates after leaving_date are excluded.
  static ({DateTime start, DateTime end})? calculationWindow({
    required DateTime registerMonth,
    required DateTime enrolledOn,
    DateTime? leftOn,
  }) {
    if (!includeInMonthlyRegister(
      registerMonth: registerMonth,
      enrolledOn: enrolledOn,
      leftOn: leftOn,
    )) {
      return null;
    }

    final monthStart = firstOfMonth(registerMonth);
    final monthEnd = lastOfMonth(registerMonth);
    final end = leftOn == null || day(leftOn).isAfter(monthEnd)
        ? monthEnd
        : day(leftOn);
    return (start: monthStart, end: end);
  }

  /// Checks whether a student is eligible on a specific calendar [targetDate]
  /// for daily/date-range attendance and historical reports.
  /// For daily attendance entry & Tarij/Daily reports, a student is active from
  /// their actual enrollment date through their leaving date (inclusive).
  static bool isActiveOnDate({
    required DateTime targetDate,
    DateTime? enrolledOn,
    DateTime? leftOn,
    bool delayedRegisterRule = false,
  }) {
    final d = day(targetDate);
    if (enrolledOn != null) {
      final start = delayedRegisterRule
          ? firstRegisterMonth(enrolledOn)
          : day(enrolledOn);
      if (d.isBefore(start)) return false;
    }
    if (leftOn != null && !d.isBefore(day(leftOn))) {
      return false;
    }
    return true;
  }

  /// Denominator must contain only instructional/open days in the student's
  /// calculation window. Holidays, Sundays and closed days are excluded.
  static double percentage({
    required int presentDays,
    required int eligibleOpenDays,
  }) =>
      eligibleOpenDays <= 0
          ? 0
          : (presentDays * 100.0 / eligibleOpenDays).clamp(0, 100);

  static double average({
    required int presentDays,
    required int eligibleOpenDays,
  }) =>
      eligibleOpenDays <= 0 ? 0 : presentDays / eligibleOpenDays;

  /// Parses `dd/mm/yyyy`, `dd-mm-yyyy`, `yyyy-mm-dd`, or ISO timestamps into a
  /// date-only [DateTime], converting any Gujarati digits first.
  static DateTime? parseDate(dynamic rawValue) {
    if (rawValue is DateTime) return day(rawValue);
    var raw = (rawValue ?? '').toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return null;
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    for (var i = 0; i < guj.length; i++) {
      raw = raw.replaceAll(guj[i], '$i');
    }
    final dmy =
        RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$').firstMatch(raw);
    if (dmy != null) {
      final d = int.tryParse(dmy.group(1)!) ?? 0;
      final m = int.tryParse(dmy.group(2)!) ?? 0;
      final y = int.tryParse(dmy.group(3)!) ?? 0;
      if (d >= 1 && d <= 31 && m >= 1 && m <= 12 && y >= 1900) {
        final dt = DateTime(y, m, d);
        if (dt.year == y && dt.month == m && dt.day == d) return dt;
      }
    }
    final ymd =
        RegExp(r'^(\d{4})[./-](\d{1,2})[./-](\d{1,2})').firstMatch(raw);
    if (ymd != null) {
      final y = int.tryParse(ymd.group(1)!) ?? 0;
      final m = int.tryParse(ymd.group(2)!) ?? 0;
      final d = int.tryParse(ymd.group(3)!) ?? 0;
      if (d >= 1 && d <= 31 && m >= 1 && m <= 12 && y >= 1900) {
        final dt = DateTime(y, m, d);
        if (dt.year == y && dt.month == m && dt.day == d) return dt;
      }
    }
    final parsed = DateTime.tryParse(raw);
    return parsed == null ? null : day(parsed);
  }

  /// Extracts canonical enrollment date from a student map without fabricating
  /// from `created_at` or `updated_at`.
  static DateTime? parseEnrollmentDate(Map<String, dynamic> student) {
    const keys = <String>[
      'enroll_school',
      'enrollment_date',
      'admission_date',
      'enroll_class',
    ];
    for (final key in keys) {
      final dt = parseDate(student[key]);
      if (dt != null) return dt;
    }
    final cf = student['custom_fields'];
    if (cf is Map) {
      for (final key in keys) {
        final dt = parseDate(cf[key]);
        if (dt != null) return dt;
      }
    }
    return null;
  }

  /// Extracts canonical leaving date from a student map, checking top-level
  /// and `custom_fields`, and falling back to `updated_at` only if the student
  /// is explicitly marked inactive (`is_active == false`) without a date.
  static DateTime? parseLeavingDate(Map<String, dynamic> student) {
    const keys = <String>[
      'leaving_date',
      'exit_date',
      'left_date',
    ];
    for (final key in keys) {
      final dt = parseDate(student[key]);
      if (dt != null) return dt;
    }
    final cf = student['custom_fields'];
    if (cf is Map) {
      for (final key in keys) {
        final dt = parseDate(cf[key]);
        if (dt != null) return dt;
      }
    }
    if (student['is_active'] == false) {
      return parseDate(student['updated_at']);
    }
    return null;
  }

  /// Extracts raw exit reason from top-level fields or `custom_fields`.
  static String parseExitReason(Map<String, dynamic> student) {
    for (final key in const <String>[
      'exit_reason',
      'leaving_reason',
      'reason_for_leaving',
      'archive_reason',
    ]) {
      final val = (student[key] ?? '').toString().trim();
      if (val.isNotEmpty && val.toLowerCase() != 'null') return val;
    }
    final cf = student['custom_fields'];
    if (cf is Map) {
      for (final entry in cf.entries) {
        final k = '${entry.key}'
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9\u0A80-\u0AFF]'), '');
        if (const <String>{
          'exitreason',
          'leavingreason',
          'reasonforleaving',
          'archivereason',
          'inactivereason',
          'removalreason',
          'reason',
          'નામકમીકારણ',
          'ગેરહાજરીનાકારણ',
          'કારણ',
        }.contains(k)) {
          final v = (entry.value ?? '').toString().trim();
          if (v.isNotEmpty && v.toLowerCase() != 'null') return v;
        }
      }
    }
    return '';
  }

  static bool isContinuousAbsenceReason(String rawReason) {
    final text = rawReason.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    return text == reasonContinuousAbsence ||
        text == 'long_absence' ||
        text == 'removed_for_absence' ||
        (text.contains('continuous') && text.contains('absence')) ||
        (text.contains('long') && text.contains('absence')) ||
        (text.contains('સતત') && text.contains('ગેરહાજ')) ||
        (text.contains('ગેરહાજરી') && text.contains('કમી'));
  }

  static bool isLeavingCertificateReason(String rawReason) {
    if (isContinuousAbsenceReason(rawReason)) return false;
    final text = rawReason.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (text == 'promoted_graduated') return false;
    return true;
  }

  static String hajariFrontPageReasonLabel(String rawReason) {
    final r = rawReason.trim();
    if (r.isEmpty) return '';
    if (r.toLowerCase() == 'promoted_graduated') {
      return 'ધોરણ 8 પૂર્ણ -> બઢતી (Promoted)';
    }
    if (isContinuousAbsenceReason(r)) {
      return labelContinuousAbsence;
    }
    return labelLeavingCertificate;
  }
}

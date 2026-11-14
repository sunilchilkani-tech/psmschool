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
  static DateTime day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime firstOfMonth(DateTime value) =>
      DateTime(value.year, value.month, 1);

  static DateTime lastOfMonth(DateTime value) =>
      DateTime(value.year, value.month + 1, 0);

  /// First register month is the month AFTER admission/enrolment.
  static DateTime firstRegisterMonth(DateTime enrolledOn) =>
      DateTime(enrolledOn.year, enrolledOn.month + 1, 1);

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
    if (leftOn != null && d.isAfter(day(leftOn))) {
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
    for (final key in const <String>[
      'enroll_school',
      'enrollment_date',
      'admission_date',
      'enroll_class',
    ]) {
      final dt = parseDate(student[key]);
      if (dt != null) return dt;
    }
    return null;
  }

  /// Extracts canonical leaving date from a student map without fabricating
  /// from `updated_at`.
  static DateTime? parseLeavingDate(Map<String, dynamic> student) {
    for (final key in const <String>[
      'leaving_date',
      'exit_date',
      'left_date',
    ]) {
      final dt = parseDate(student[key]);
      if (dt != null) return dt;
    }
    return null;
  }
}

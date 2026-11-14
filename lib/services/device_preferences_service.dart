import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/report_preferences.dart';

/// Device-local preferences only. Never write passwords, PINs, refresh tokens or keys here.
class DevicePreferencesService {
  static const _reportKey = 'psm.report.preferences.v2';
  static const _breakfastKey = 'psm.attendance.breakfast.entry_type.v1';
  static const _lastClassKey = 'psm.attendance.last_class.v1';
  static const _entryModeKey = 'psm.attendance.entry_mode.v1';

  Future<ReportPreferences> loadReportPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_reportKey);
    if (encoded == null || encoded.isEmpty) return const ReportPreferences();
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is Map) {
        return ReportPreferences.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {
      // An invalid old preference should not block app startup.
    }
    return const ReportPreferences();
  }

  Future<void> saveReportPreferences(ReportPreferences preferences) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_reportKey, jsonEncode(preferences.ensuringValidColumns().toJson()));
  }

  Future<String> loadBreakfastEntryType() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_breakfastKey) ?? 'same_as_present';
    return const {'total', 'gender', 'same_as_present'}.contains(value)
        ? value
        : 'same_as_present';
  }

  Future<void> saveBreakfastEntryType(String value) async {
    if (!const {'total', 'gender', 'same_as_present'}.contains(value)) {
      throw ArgumentError.value(value, 'value', 'Unsupported breakfast entry type.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_breakfastKey, value);
  }

  Future<String?> loadLastClass() async =>
      (await SharedPreferences.getInstance()).getString(_lastClassKey);

  Future<void> saveLastClass(String classIdOrKey) async =>
      (await SharedPreferences.getInstance()).setString(_lastClassKey, classIdOrKey);

  Future<String> loadEntryMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_entryModeKey) == 'direct' ? 'direct' : 'student';
  }

  Future<void> saveEntryMode(String value) async {
    if (!const {'direct', 'student'}.contains(value)) {
      throw ArgumentError.value(value, 'value', 'Entry mode must be direct or student.');
    }
    await (await SharedPreferences.getInstance()).setString(_entryModeKey, value);
  }
}

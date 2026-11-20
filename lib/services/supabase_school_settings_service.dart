import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import 'datewise_report_columns.dart';

/// School-wide settings stored in school_settings.config.
/// Reads are available to authenticated members of the school; writes are
/// Admin-only through RLS and the existing school write guard.
class SupabaseSchoolSettingsService {
  SupabaseSchoolSettingsService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const String defaultAttendanceLockTime = '12:01';

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) return value.map((key, value) => MapEntry('$key', value));
    return <String, dynamic>{};
  }

  Future<String> currentSchoolRef() async {
    if (_client.auth.currentUser == null) throw StateError('Sign in again.');
    final result = await _client.rpc('current_school_ref');
    final value = (result ?? '').toString().trim();
    if (value.isEmpty) throw StateError('No active school is linked to this login.');
    return value;
  }

  Future<Map<String, dynamic>> loadConfig({String? schoolRef}) async {
    final ref = schoolRef ?? await currentSchoolRef();
    final row = await _client
        .from('school_settings')
        .select('config')
        .eq('school_ref', ref)
        .maybeSingle();
    return _map(row?['config']);
  }

  bool isValidLockTime(String value) =>
      RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(value.trim());

  Future<void> saveConfigPatch(Map<String, dynamic> patch) async {
    if (_client.auth.currentUser == null) throw StateError('Sign in again.');
    final isAdmin = await _client.rpc('is_school_admin');
    if (isAdmin != true) throw StateError('Only the School Admin can change school settings.');
    final schoolRef = await currentSchoolRef();
    // The database's psm_school_write_guard trigger is authoritative for
    // inactive, expired, and blocked schools; do not rely on client-only checks.
    final config = await loadConfig(schoolRef: schoolRef);
    config.addAll(patch);
    await _client.from('school_settings').upsert(<String, dynamic>{
      'school_ref': schoolRef,
      'config': config,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'school_ref');
  }

  Future<void> saveAttendanceLockTime(String value) async {
    final normalized = value.trim();
    if (!isValidLockTime(normalized)) throw ArgumentError('Choose a valid lock time.');
    await saveConfigPatch(<String, dynamic>{'attendance_lock_time': normalized});
  }

  Future<String> loadSchoolType({String? schoolRef}) async {
    final ref = schoolRef ?? await currentSchoolRef();
    try {
      final row = await _client
          .from('schools')
          .select('school_type')
          .eq('id', ref)
          .maybeSingle();
      final fromSchool = (row?['school_type'] ?? '').toString().trim();
      if (fromSchool.isNotEmpty) {
        return DateWiseReportColumn.normalizeSchoolType(fromSchool);
      }
    } catch (_) {}
    try {
      final ctx = await _client.rpc('psm_library_school_context');
      if (ctx is Map && (ctx['school_type'] ?? '').toString().trim().isNotEmpty) {
        return DateWiseReportColumn.normalizeSchoolType(ctx['school_type']);
      }
    } catch (_) {}
    final config = await loadConfig(schoolRef: ref);
    return DateWiseReportColumn.normalizeSchoolType(
      config['school_type'] ?? config['schoolType'],
    );
  }

  Future<List<String>> visibleDateWiseColumns() async {
    final ref = await currentSchoolRef();
    final schoolType = await loadSchoolType(schoolRef: ref);
    final config = await loadConfig(schoolRef: ref);
    final raw = config['datewise_visible_columns'];
    if (raw is! List) {
      return DateWiseReportColumn.columnsForSchoolType(schoolType)
          .map((column) => column.key)
          .toList();
    }
    final values = raw
        .map((value) => value.toString())
        .where(DateWiseReportColumn.allKeys.contains)
        .toSet();
    return DateWiseReportColumn.filterColumnKeysForSchoolType(
      values,
      schoolType,
    );
  }

  Future<void> saveVisibleDateWiseColumns(Iterable<String> keys) async {
    final ref = await currentSchoolRef();
    final schoolType = await loadSchoolType(schoolRef: ref);
    final filtered = DateWiseReportColumn.filterColumnKeysForSchoolType(
      keys,
      schoolType,
    );
    if (filtered.isEmpty) {
      throw ArgumentError('Select at least one DATE WISE column.');
    }
    await saveConfigPatch(<String, dynamic>{
      'datewise_visible_columns': filtered,
    });
  }

  /// Returns the selected TARIJ column keys in the exact custom order configured
  /// by the School Admin (so column header numbers 1..N match Admin's setting).
  Future<List<String>> visibleTarijColumns() async {
    final config = await loadConfig();
    final raw = config['tarij_visible_columns'];
    if (raw is! List) {
      return TarijReportColumn.all.map((column) => column.key).toList();
    }
    final ordered = <String>[];
    final seen = <String>{};
    for (final value in raw) {
      final key = value.toString().trim();
      if (TarijReportColumn.allKeys.contains(key) && seen.add(key)) {
        ordered.add(key);
      }
    }
    if (ordered.isEmpty) {
      return TarijReportColumn.all.map((column) => column.key).toList();
    }
    return ordered;
  }

  /// Ordered TARIJ printed-column keys chosen by the admin (e.g.
  /// `closing:SC:BOYS`). Falls back to the older section-level selection.
  Future<List<String>> visibleTarijColumnKeys() async {
    final config = await loadConfig();
    final raw = config['tarij_column_specs'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList();
    }
    return visibleTarijColumns();
  }

  Future<void> saveTarijColumnKeys(Iterable<String> keys) async {
    final ordered = <String>[];
    final seen = <String>{};
    for (final k in keys) {
      final clean = k.trim();
      if (TarijColumnSpec.parse(clean) != null && seen.add(clean)) ordered.add(clean);
    }
    if (ordered.isEmpty) throw ArgumentError('Select at least one TARIJ column.');
    await saveConfigPatch(<String, dynamic>{'tarij_column_specs': ordered});
  }

  /// Saves the selected TARIJ column keys in the exact order configured by the
  /// School Admin.
  Future<void> saveVisibleTarijColumns(Iterable<String> keys) async {
    final ordered = <String>[];
    final seen = <String>{};
    for (final key in keys) {
      final clean = key.trim();
      if (TarijReportColumn.allKeys.contains(clean) && seen.add(clean)) {
        ordered.add(clean);
      }
    }
    if (ordered.isEmpty) {
      throw ArgumentError('Select at least one TARIJ column.');
    }
    await saveConfigPatch(<String, dynamic>{
      'tarij_visible_columns': ordered,
    });
  }

  Future<bool> loadThreeStepAttendanceSaveMode({String? schoolRef}) async {
    final config = await loadConfig(schoolRef: schoolRef);
    return config['three_step_attendance_save_mode'] == true;
  }

  Future<void> saveThreeStepAttendanceSaveMode(bool enabled) async {
    await saveConfigPatch(<String, dynamic>{
      'three_step_attendance_save_mode': enabled,
    });
  }

  Future<bool> loadDirectAttendanceEntryEnabled({String? schoolRef}) async {
    final config = await loadConfig(schoolRef: schoolRef);
    if (config['direct_attendance_entry_enabled'] == null) return true;
    return config['direct_attendance_entry_enabled'] == true;
  }

  Future<void> saveDirectAttendanceEntryEnabled(bool enabled) async {
    await saveConfigPatch(<String, dynamic>{
      'direct_attendance_entry_enabled': enabled,
    });
  }
}

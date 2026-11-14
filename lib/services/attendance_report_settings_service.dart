import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import '../models/report_preferences.dart';

class AttendanceReportSettingsService {
  AttendanceReportSettingsService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<ReportPreferences> loadSchoolDefault({required String classId}) async {
    final row = await _client.from('school_report_settings')
        .select('settings')
        .eq('class_id', classId)
        .eq('report_key', 'attendance_display')
        .maybeSingle();
    final settings = row?['settings'];
    if (settings is Map) {
      return ReportPreferences.fromJson(settings.cast<String, dynamic>());
    }
    return const ReportPreferences();
  }

  /// Shared defaults are class-specific and RLS allows only admins to save them.
  Future<void> saveSchoolDefault({
    required String classId,
    required ReportPreferences preferences,
  }) async {
    final value = await _client.rpc('current_school_ref');
    if (value == null || '$value'.isEmpty) {
      throw StateError('No active school is linked to this session.');
    }
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Sign in before saving report defaults.');
    final teacher = await _client.from('school_teachers')
        .select('role')
        .eq('auth_user_id', user.id)
        .maybeSingle();
    if (teacher == null || !const {'admin', 'developer'}
        .contains('${teacher['role']}'.toLowerCase())) {
      throw StateError('Only a school administrator can change shared defaults.');
    }
    await _client.from('school_report_settings').upsert({
      'school_ref': '$value',
      'class_id': classId,
      'report_key': 'attendance_display',
      'settings': preferences.ensuringValidColumns().toJson(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'school_ref,class_id,report_key');
  }
}

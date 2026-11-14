import 'package:pmshri_attendance/services/firebase_backend_client.dart';

/// Supabase data access for the existing result models/tables. Result PDF rendering remains a UI concern.
class ResultService {
  ResultService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  Future<Map<String, dynamic>?> getClassSettings(String classId) async {
    final row = await _client.from('class_result_settings')
        .select().eq('class_id', classId).maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<List<Map<String, dynamic>>> getStudentProfiles({
    required String classId,
    String? academicYear,
  }) async {
    dynamic query = _client.from('student_result_profiles').select().eq('class_id', classId);
    if (academicYear != null && academicYear.isNotEmpty) query = query.eq('academic_year', academicYear);
    final rows = await query;
    return rows.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> getSubjectMarks({
    required String classId,
    required int semester,
    String? academicYear,
  }) async {
    dynamic query = _client.from('student_subject_marks').select()
        .eq('class_id', classId).eq('semester', semester);
    if (academicYear != null && academicYear.isNotEmpty) query = query.eq('academic_year', academicYear);
    final rows = await query;
    return rows.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> getSubjects(String classId) async {
    final rows = await _client.from('class_subjects').select()
        .eq('class_id', classId).eq('is_active', true).order('sort_order');
    return rows.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> saveStudentProfile(Map<String, dynamic> profile) async {
    final payload = Map<String, dynamic>.from(profile);
    payload.putIfAbsent('school_ref', () => null);
    if (payload['school_ref'] == null) payload['school_ref'] = await _currentSchoolRef();
    payload['updated_at'] = DateTime.now().toUtc().toIso8601String();
    await _client.from('student_result_profiles').upsert(
      payload,
      onConflict: 'school_ref,class_id,student_id,academic_year',
    );
  }

  Future<void> saveSubjectMark(Map<String, dynamic> mark) async {
    final payload = Map<String, dynamic>.from(mark);
    payload.putIfAbsent('school_ref', () => null);
    if (payload['school_ref'] == null) payload['school_ref'] = await _currentSchoolRef();
    payload['updated_at'] = DateTime.now().toUtc().toIso8601String();
    await _client.from('student_subject_marks').upsert(
      payload,
      onConflict: 'school_ref,class_id,student_id,academic_year,semester,subject_name',
    );
  }

  Future<void> saveManyMarks(List<Map<String, dynamic>> marks) async {
    if (marks.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final schoolRef = await _currentSchoolRef();
    final payload = marks.map((row) => {
      ...row,
      'school_ref': row['school_ref'] ?? schoolRef,
      'updated_at': now,
    }).toList();
    await _client.from('student_subject_marks').upsert(
      payload,
      onConflict: 'school_ref,class_id,student_id,academic_year,semester,subject_name',
    );
  }

  Future<String> _currentSchoolRef() async {
    final value = await _client.rpc('current_school_ref');
    if (value == null || '$value'.isEmpty) throw StateError('No active school is linked to this session.');
    return '$value';
  }

  /// Shared class settings are administrator-managed by RLS; teachers can read them.
  Future<void> saveClassSettings(Map<String, dynamic> settings) async {
    final payload = Map<String, dynamic>.from(settings);
    payload.putIfAbsent('school_ref', () => null);
    if (payload['school_ref'] == null) payload['school_ref'] = await _currentSchoolRef();
    payload['updated_at'] = DateTime.now().toUtc().toIso8601String();
    await _client.from('class_result_settings').upsert(
      payload,
      onConflict: 'class_id,school_ref',
    );
  }
}

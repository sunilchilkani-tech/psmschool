import 'package:pmshri_attendance/services/firebase_backend_client.dart';

/// Student directory operations for the current school/class. RLS remains the final gate.
class StudentManagementService {
  StudentManagementService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> listStudents(
    String classId, {
    bool includeArchived = false,
  }) async {
    dynamic query = _client.from('students').select().eq('class_id', classId);
    if (!includeArchived) query = query.eq('is_active', true);
    final rows = await query.order('roll_number');
    return rows.map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Roll number is allocated by the database; a supplied roll inserts there and shifts
  /// every active numeric roll at or after it, atomically.
  Future<Map<String, dynamic>> addStudent({
    required String classId,
    required Map<String, dynamic> student,
    int? rollNumber,
  }) async {
    final payload = Map<String, dynamic>.from(student)
      ..remove('id')
      ..remove('school_ref')
      ..remove('class_id')
      ..remove('is_active')
      ..remove('created_at')
      ..remove('updated_at')
      ..remove('roll_number');
    payload['name'] = (payload['name'] ?? '').toString().trim();
    if ((payload['name'] as String).isEmpty) throw ArgumentError('Student name is required.');
    final result = await _client.rpc('psm_add_student_with_roll', params: {
      'p_class_id': classId,
      'p_student': payload,
      'p_roll_number': rollNumber,
    });
    if (result is Map) return Map<String, dynamic>.from(result);
    throw StateError('Supabase did not return the newly created student.');
  }

  /// Normal fields can be edited directly. Roll changes always use the atomic roll RPC.
  Future<Map<String, dynamic>> updateStudent({
    required String studentId,
    required Map<String, dynamic> changes,
  }) async {
    final safe = Map<String, dynamic>.from(changes)
      ..remove('id')
      ..remove('school_ref')
      ..remove('class_id')
      ..remove('created_at')
      ..remove('is_active')
      ..remove('updated_at');

    final requestedRoll = safe.remove('roll_number');
    Map<String, dynamic>? moved;
    if (requestedRoll != null && '$requestedRoll'.trim().isNotEmpty) {
      final roll = int.tryParse('$requestedRoll');
      if (roll == null || roll < 1) throw ArgumentError('Roll number must be a positive integer.');
      moved = await changeRoll(studentId: studentId, newRollNumber: roll);
    }
    if (safe.isEmpty) {
      if (moved != null) return moved;
      final row = await _client.from('students').select().eq('id', studentId).single();
      return Map<String, dynamic>.from(row);
    }
    safe['updated_at'] = DateTime.now().toUtc().toIso8601String();
    final row = await _client.from('students').update(safe).eq('id', studentId).select().single();
    return Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>> changeRoll({
    required String studentId,
    required int newRollNumber,
  }) async {
    final result = await _client.rpc('psm_change_student_roll', params: {
      'p_student_id': studentId,
      'p_new_roll': newRollNumber,
    });
    if (result is Map) return Map<String, dynamic>.from(result);
    throw StateError('Supabase did not return the updated student.');
  }

  /// Soft-delete preserves linked attendance and result history.
  Future<void> archiveStudent(String studentId) async {
    await _client.rpc('psm_archive_student', params: {'p_student_id': studentId});
  }

  /// Restore an archived student only when its former roll is unused; callers pass the roll.
  Future<void> restoreStudent({
    required String studentId,
    required String classId,
    required int rollNumber,
  }) async {
    if (rollNumber < 1) throw ArgumentError('Roll number must be positive.');
    final collision = await _client.from('students').select('id')
        .eq('class_id', classId).eq('is_active', true)
        .eq('roll_number', '$rollNumber').maybeSingle();
    if (collision != null) throw StateError('Roll $rollNumber is already in use.');
    await _client.from('students').update({
      'is_active': true,
      'roll_number': '$rollNumber',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', studentId).eq('class_id', classId).eq('is_active', false);
  }
}

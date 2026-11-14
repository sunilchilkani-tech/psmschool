import 'package:pmshri_attendance/services/firebase_backend_client.dart';

/// Calls the trusted Edge Function. Service-role credentials never enter Flutter.
class AdminSchoolManagementService {
  AdminSchoolManagementService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final response = await _client.functions.invoke(
      'admin-school-management',
      body: body,
    );
    final data = response.data;
    if (response.status < 200 || response.status >= 300) {
      final message = data is Map ? data['error'] : data;
      throw StateError('$message');
    }
    if (data is Map) return Map<String, dynamic>.from(data);
    throw StateError('Unexpected response from school management service.');
  }

  Future<Map<String, dynamic>> createTeacher({
    required String teacherName,
    required String temporaryPassword,
    List<String> allowedClasses = const [],
    String role = 'teacher',
  }) => _invoke({
    'action': 'create_teacher',
    'teacher_name': teacherName.trim(),
    'temporary_password': temporaryPassword,
    'allowed_classes': allowedClasses,
    'role': role,
  });

  Future<void> changeTeacherPassword({
    required String teacherId,
    required String newPassword,
  }) async {
    await _invoke({
      'action': 'change_teacher_password',
      'teacher_id': teacherId,
      'new_password': newPassword,
    });
  }

  Future<Map<String, dynamic>> createClass({
    required String classKey,
    required String label,
    String sheetName = '',
    String standard = '',
    String section = '',
    String reportGroup = '',
    int sortOrder = 0,
  }) => _invoke({
    'action': 'create_class',
    'class_key': classKey.trim(),
    'label': label.trim(),
    'sheet_name': sheetName.trim(),
    'standard': standard.trim(),
    'section': section.trim(),
    'report_group': reportGroup.trim(),
    'sort_order': sortOrder,
  });

  Future<void> setTeacherClasses({
    required String teacherId,
    required List<String> allowedClasses,
  }) async {
    await _invoke({
      'action': 'set_teacher_classes',
      'teacher_id': teacherId,
      'allowed_classes': allowedClasses,
    });
  }

  Future<void> setTeacherActive({
    required String teacherId,
    required bool isActive,
  }) async {
    await _invoke({
      'action': 'set_teacher_active',
      'teacher_id': teacherId,
      'is_active': isActive,
    });
  }
}

import 'dart:convert';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

/// Supabase-only access layer for the Developer -> School -> Admin workflow.
/// It never sends a service-role key to Flutter; all privileged work is done in
/// the psm-platform-admin Edge Function.
class SupabaseSchoolAccessService {
  SupabaseSchoolAccessService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map)
      return value.map((key, value) => MapEntry(key.toString(), value));
    return <String, dynamic>{};
  }

  /// Edge Function versions can return the payload directly or inside a
  /// `data`, `context`, `result`, or `payload` object. Resolve either shape.
  Map<String, dynamic> _payloadWithKey(
      Map<String, dynamic> source, String key) {
    var current = Map<String, dynamic>.from(source);
    for (var depth = 0; depth < 4; depth++) {
      if (current.containsKey(key)) return current;
      Map<String, dynamic>? next;
      for (final wrapper in const ['data', 'context', 'result', 'payload']) {
        final candidate = _asMap(current[wrapper]);
        if (candidate.isEmpty) continue;
        if (candidate.containsKey(key)) return candidate;
        next ??= candidate;
      }
      if (next == null) return current;
      current = next;
    }
    return current;
  }

  bool? _nullableBool(dynamic value) {
    if (value is bool) return value;
    final text = value?.toString().trim().toLowerCase();
    if (text == 'true' || text == '1' || text == 't') return true;
    if (text == 'false' || text == '0' || text == 'f') return false;
    return null;
  }

  String _todayIso() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _messageFrom(Object error) {
    if (error is FunctionException) {
      final details = error.details;
      if (details is Map) {
        final message = details['error'] ?? details['message'];
        if (message != null && message.toString().trim().isNotEmpty)
          return message.toString();
      }
      if ((error.reasonPhrase ?? '').trim().isNotEmpty)
        return error.reasonPhrase ?? 'Request failed.';
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  Future<Map<String, dynamic>> _invoke(
    String functionName,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _client.functions.invoke(functionName, body: body);
      dynamic rawData = response.data;
      // Most Supabase responses are already decoded Maps. Some proxies or older
      // deployments return a JSON string, so decode that form before parsing.
      if (rawData is String) {
        try {
          rawData = jsonDecode(rawData);
        } on FormatException {
          // Leave non-JSON strings untouched; the status/error handler below
          // will report a useful response failure without hiding the cause.
        }
      }
      final data = _asMap(rawData);
      if (response.status < 200 || response.status >= 300) {
        throw Exception(data['error'] ??
            data['message'] ??
            'Request failed (${response.status}).');
      }
      if (data['error'] != null) throw Exception(data['error'].toString());
      return data;
    } catch (error) {
      throw Exception(_messageFrom(error));
    }
  }

  Future<Map<String, dynamic>> loadLoginOptions(String schoolId) =>
      _invoke('psm-school-directory-v2', <String, dynamic>{
        'schoolId': schoolId.trim(),
      });

  Future<List<Map<String, dynamic>>> loadLoginDirectory(String schoolId) async {
    final result = await loadLoginOptions(schoolId);
    final raw = result['teachers'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((row) => row.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  Future<Map<String, dynamic>> loadSchoolDirectoryInfo(String schoolId) async {
    final result = await loadLoginOptions(schoolId);
    return _asMap(result['school']);
  }

  /// Signs in by calling the server-side school login function, then imports its
  /// short-lived session into supabase_flutter so existing RLS rules apply.
  Future<Map<String, dynamic>> signInSchoolUser({
    required String schoolId,
    required String teacherId,
    required String password,
  }) async {
    final result = await _invoke('psm-school-login-v2', <String, dynamic>{
      'schoolId': schoolId.trim(),
      'teacherId': teacherId.trim(),
      'password': password,
    });
    final refreshToken = (result['refresh_token'] ?? '').toString();
    if (refreshToken.isEmpty)
      throw Exception(
          'Login succeeded without a session. Please contact the Developer.');
    await _client.auth.setSession(refreshToken);
    return _asMap(result['profile']);
  }

  /// Login screen: sends a new-school registration request to the developer.
  Future<void> submitSchoolRegistrationRequest(Map<String, dynamic> form) async {
    await _invoke('psm-platform-admin', <String, dynamic>{
      ...form,
      'action': 'public.submit_school_registration',
    });
  }

  Future<List<Map<String, dynamic>>> developerListRegistrationRequests(
    String developerKey, {
    bool includeClosed = false,
  }) async {
    final result = await _invoke('psm-platform-admin', <String, dynamic>{
      'action': 'developer.list_registration_requests',
      'developerKey': developerKey,
      'includeClosed': includeClosed,
    });
    final raw = result['requests'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw.whereType<Map>().map((r) => r.map((k, v) => MapEntry(k.toString(), v))).toList();
  }

  Future<void> developerUpdateRegistrationRequest({
    required String developerKey,
    required String requestId,
    required Map<String, dynamic> fields,
  }) async {
    await _invoke('psm-platform-admin', <String, dynamic>{
      ...fields,
      'action': 'developer.update_registration_request',
      'developerKey': developerKey,
      'requestId': requestId,
    });
  }

  Future<void> developerApproveRegistrationRequest({
    required String developerKey,
    required String requestId,
    required String validityDate,
  }) async {
    await _invoke('psm-platform-admin', <String, dynamic>{
      'action': 'developer.approve_registration_request',
      'developerKey': developerKey,
      'requestId': requestId,
      'validityDate': validityDate,
    });
  }

  Future<void> developerRejectRegistrationRequest({
    required String developerKey,
    required String requestId,
    String reason = '',
  }) async {
    await _invoke('psm-platform-admin', <String, dynamic>{
      'action': 'developer.reject_registration_request',
      'developerKey': developerKey,
      'requestId': requestId,
      'reason': reason,
    });
  }

  Future<List<Map<String, dynamic>>> developerListSchools(
      String developerKey) async {
    final result = await _invoke('psm-platform-admin', <String, dynamic>{
      'action': 'developer.list_schools',
      'developerKey': developerKey,
    });
    final payload = _payloadWithKey(result, 'schools');
    final raw = payload['schools'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((row) => row.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  Future<Map<String, dynamic>> developerCreateSchool({
    required String developerKey,
    required String schoolName,
    String schoolNameGu = '',
    String schoolAddressEn = '',
    String schoolAddressGu = '',
    required String diseNumber,
    required String adminName,
    required String adminMobile,
    required String adminPassword,
    required String schoolType,
    required String validityDate,
  }) {
    return _invoke('psm-platform-admin', <String, dynamic>{
      'action': 'developer.create_school',
      'developerKey': developerKey,
      'schoolName': schoolName.trim(),
      'schoolNameEn': schoolName.trim(),
      'schoolNameGu': schoolNameGu.trim(),
      'schoolAddressEn': schoolAddressEn.trim(),
      'schoolAddressGu': schoolAddressGu.trim(),
      'diseNumber': diseNumber.trim(),
      'adminName': adminName.trim(),
      'adminMobile': adminMobile.trim(),
      'adminPassword': adminPassword,
      'schoolType': schoolType,
      'validityDate': validityDate,
    });
  }

  Future<Map<String, dynamic>> developerBulkCreateSchools({
    required String developerKey,
    required List<Map<String, dynamic>> rows,
  }) =>
      _invoke('psm-platform-admin', <String, dynamic>{
        'action': 'developer.bulk_create_schools',
        'developerKey': developerKey,
        'rows': rows,
      });

  Future<List<Map<String, dynamic>>> developerListMessages(
      String developerKey) async {
    final result = await _invoke('psm-platform-admin', <String, dynamic>{
      'action': 'developer.list_messages',
      'developerKey': developerKey,
    });
    final payload = _payloadWithKey(result, 'messages');
    final raw = payload['messages'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((row) => row.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  Future<Map<String, dynamic>> developerCreateMessage({
    required String developerKey,
    required String message,
    required String recipientScope,
    required String displayDate,
  }) =>
      _invoke('psm-platform-admin', <String, dynamic>{
        'action': 'developer.create_message',
        'developerKey': developerKey,
        'message': message.trim(),
        'recipientScope': recipientScope,
        'displayDate': displayDate,
      });

  Future<Map<String, dynamic>> developerBulkCreateMessages({
    required String developerKey,
    required List<Map<String, dynamic>> messages,
    required String recipientScope,
  }) =>
      _invoke('psm-platform-admin', <String, dynamic>{
        'action': 'developer.bulk_create_messages',
        'developerKey': developerKey,
        'messages': messages,
        'recipientScope': recipientScope,
      });

  Future<void> developerSetMessageActive({
    required String developerKey,
    required String messageId,
    required bool isActive,
  }) async {
    await _invoke('psm-platform-admin', <String, dynamic>{
      'action': 'developer.set_message_active',
      'developerKey': developerKey,
      'messageId': messageId,
      'isActive': isActive,
    });
  }

  Future<List<Map<String, dynamic>>> developerListSharedFiles(
    String developerKey,
  ) async {
    final result = await _invoke('psm-platform-admin', <String, dynamic>{
      'action': 'developer.list_shared_files',
      'developerKey': developerKey,
    });
    final payload = _payloadWithKey(result, 'files');
    final raw = payload['files'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((row) => row.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  Future<Map<String, dynamic>> developerUploadSharedFile({
    required String developerKey,
    required String fileName,
    required String title,
    required String description,
    required String mimeType,
    required String base64Data,
    required int sizeBytes,
    String? displayDate,
  }) =>
      _invoke('psm-platform-admin', <String, dynamic>{
        'action': 'developer.upload_shared_file',
        'developerKey': developerKey,
        'fileName': fileName,
        'title': title,
        'description': description,
        'mimeType': mimeType,
        'base64Data': base64Data,
        'sizeBytes': sizeBytes,
        if (displayDate != null && displayDate.trim().isNotEmpty)
          'displayDate': displayDate.trim(),
      });

  Future<Map<String, dynamic>> developerPurgeExpiredCloudData({
    required String developerKey,
    bool deleteAllSharedFiles = false,
  }) =>
      _invoke('psm-platform-admin', <String, dynamic>{
        'action': 'developer.purge_expired_cloud_data',
        'developerKey': developerKey,
        'deleteAllSharedFiles': deleteAllSharedFiles,
      });

  Future<void> developerDeleteSharedFile({
    required String developerKey,
    required String fileId,
  }) async {
    await _invoke('psm-platform-admin', <String, dynamic>{
      'action': 'developer.delete_shared_file',
      'developerKey': developerKey,
      'fileId': fileId,
    });
  }

  Future<Map<String, dynamic>> developerGetUsage(String developerKey) async {
    final result = await _invoke('psm-platform-admin', <String, dynamic>{
      'action': 'developer.get_usage',
      'developerKey': developerKey,
    });
    final payload = _payloadWithKey(result, 'usage');
    return _asMap(payload['usage']);
  }

  /// Loads due notices for the signed-in school user. The Edge Function applies
  /// role checks, India-date logic, and server-side dismissals before returning them.
  Future<List<Map<String, dynamic>>> loadDuePopups() async {
    final result = await _invoke('psm-platform-admin', <String, dynamic>{
      'action': 'admin.get_due_popups',
    });
    final payload = _payloadWithKey(result, 'popups');
    final raw = payload['popups'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((row) => row.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  Future<void> dismissDuePopup(Map<String, dynamic> popup) async {
    final kind = (popup['kind'] ?? '').toString();
    if (kind == 'developer_message') {
      await _invoke('psm-platform-admin', <String, dynamic>{
        'action': 'admin.dismiss_developer_message',
        'messageId': popup['messageId'],
      });
      return;
    }
    if (kind == 'validity_reminder') {
      await _invoke('psm-platform-admin', <String, dynamic>{
        'action': 'admin.dismiss_validity_reminder',
        'reminderDate': popup['reminderDate'],
      });
      return;
    }
    if (kind == 'admin_pending_leaves') {
      // Do not permanently dismiss: Admin should see this on every start until
      // all pending leave requests are approved or rejected.
      return;
    }
    if (kind == 'teacher_leave_decision') {
      await _invoke('psm-platform-admin', <String, dynamic>{
        'action': 'admin.dismiss_teacher_leave_decision',
        'leaveId': popup['leaveId'],
      });
      return;
    }
    if (kind == 'daily_meal_menu') {
      await _invoke('psm-platform-admin', <String, dynamic>{
        'action': 'admin.dismiss_daily_meal_menu',
        'menuDate': popup['menuDate'],
      });
      return;
    }
    if (kind == 'absence_milestone_alert') {
      await _invoke('psm-platform-admin', <String, dynamic>{
        'action': 'admin.dismiss_absence_milestone_alert',
        'ackKeys': popup['ackKeys'] ?? const <String>[],
      });
      return;
    }
    throw Exception('Unknown popup type. Refresh and try again.');
  }

  Future<List<Map<String, dynamic>>> developerExportDirectory(
      String developerKey) async {
    final result = await _invoke('psm-platform-admin', <String, dynamic>{
      'action': 'developer.export_directory',
      'developerKey': developerKey,
    });
    final payload = _payloadWithKey(result, 'records');
    final raw = payload['records'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((row) => row.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  Future<void> developerDeleteSchool({
    required String developerKey,
    required String schoolRef,
    required String confirmSchoolId,
  }) async {
    await _invoke('psm-platform-admin', <String, dynamic>{
      'action': 'developer.delete_school',
      'developerKey': developerKey,
      'schoolRef': schoolRef,
      'confirmSchoolId': confirmSchoolId.trim(),
    });
  }

  Future<Map<String, dynamic>> developerDeleteAllLibraryBooks({
    required String developerKey,
    required String schoolRef,
    required String confirmSchoolId,
  }) async =>
      _invoke('psm-platform-admin', <String, dynamic>{
        'action': 'developer.delete_all_library_books',
        'developerKey': developerKey,
        'schoolRef': schoolRef,
        'confirmSchoolId': confirmSchoolId.trim(),
        'confirmPhrase': 'DELETE ALL BOOKS',
      });

  Future<Map<String, dynamic>> developerSetPrevAttendanceUpload({
    required String developerKey,
    required String schoolRef,
    required bool enabled,
  }) async =>
      _invoke('psm-platform-admin', <String, dynamic>{
        'action': 'developer.set_prev_attendance_upload',
        'developerKey': developerKey,
        'schoolRef': schoolRef,
        'enabled': enabled,
      });

  Future<Map<String, dynamic>> developerSetSchoolModules({
    required String developerKey,
    required String schoolRef,
    required List<String> disabledModules,
  }) async =>
      _invoke('psm-platform-admin', <String, dynamic>{
        'action': 'developer.set_school_modules',
        'developerKey': developerKey,
        'schoolRef': schoolRef,
        'disabledModules': disabledModules,
      });

  Future<Map<String, dynamic>> developerImpersonateSchoolAdmin({
    required String developerKey,
    required String schoolRef,
  }) async {
    final result = await _invoke('psm-platform-admin', <String, dynamic>{
      'action': 'developer.impersonate_school_admin',
      'developerKey': developerKey,
      'schoolRef': schoolRef,
    });
    _client.activateDeveloperSchoolAdminSession(result);
    return _asMap(result['profile']);
  }

  void endDeveloperImpersonation() {
    _client.deactivateDeveloperSchoolAdminSession();
  }

  Future<Map<String, dynamic>> developerGetLibraryBooksBackupData({
    required String developerKey,
    required String schoolRef,
  }) async =>
      _invoke('psm-platform-admin', <String, dynamic>{
        'action': 'developer.get_library_books_backup_data',
        'developerKey': developerKey,
        'schoolRef': schoolRef,
      });

  Future<Map<String, dynamic>> developerGetAttendanceBackupData({
    required String developerKey,
    required String schoolRef,
    String? fromDate,
    String? toDate,
  }) async =>
      _invoke('psm-platform-admin', <String, dynamic>{
        'action': 'developer.get_attendance_backup_data',
        'developerKey': developerKey,
        'schoolRef': schoolRef,
        if (fromDate != null && fromDate.trim().isNotEmpty)
          'fromDate': fromDate.trim(),
        if (toDate != null && toDate.trim().isNotEmpty)
          'toDate': toDate.trim(),
      });

  Future<Map<String, dynamic>> developerDeleteAllAttendanceRecords({
    required String developerKey,
    required String schoolRef,
    required String confirmSchoolId,
    String? fromDate,
    String? toDate,
  }) async =>
      _invoke('psm-platform-admin', <String, dynamic>{
        'action': 'developer.delete_all_attendance_records',
        'developerKey': developerKey,
        'schoolRef': schoolRef,
        'confirmSchoolId': confirmSchoolId.trim(),
        'confirmPhrase': 'DELETE ATTENDANCE',
        if (fromDate != null && fromDate.trim().isNotEmpty)
          'fromDate': fromDate.trim(),
        if (toDate != null && toDate.trim().isNotEmpty)
          'toDate': toDate.trim(),
      });

  Future<void> developerUpdateSchool({
    required String developerKey,
    required String schoolRef,
    String? schoolName,
    String? schoolNameGu,
    String? schoolAddressEn,
    String? schoolAddressGu,
    String? schoolType,
    String? validityDate,
    String? adminName,
    String? adminMobile,
    String? adminPassword,
  }) async {
    final body = <String, dynamic>{
      'action': 'developer.update_school',
      'developerKey': developerKey,
      'schoolRef': schoolRef,
    };
    if (schoolName != null) {
      body['schoolName'] = schoolName.trim();
      body['schoolNameEn'] = schoolName.trim();
    }
    if (schoolNameGu != null) body['schoolNameGu'] = schoolNameGu.trim();
    if (schoolAddressEn != null)
      body['schoolAddressEn'] = schoolAddressEn.trim();
    if (schoolAddressGu != null)
      body['schoolAddressGu'] = schoolAddressGu.trim();
    if (schoolType != null) body['schoolType'] = schoolType;
    if (validityDate != null) body['validityDate'] = validityDate;
    if (adminName != null) body['adminName'] = adminName.trim();
    if (adminMobile != null && adminMobile.trim().isNotEmpty)
      body['adminMobile'] = adminMobile.trim();
    if (adminPassword != null && adminPassword.isNotEmpty)
      body['adminPassword'] = adminPassword;
    await _invoke('psm-platform-admin', body);
  }

  Future<Map<String, dynamic>> requestPasswordResetOtp({
    required String schoolId,
    required String teacherId,
  }) =>
      _invoke('psm-password-reset-otp', <String, dynamic>{
        'action': 'request',
        'schoolId': schoolId.trim(),
        'teacherId': teacherId,
      });

  Future<void> completePasswordResetOtp({
    required String schoolId,
    required String teacherId,
    required String challengeId,
    required String otp,
    required String newPassword,
  }) async {
    await _invoke('psm-password-reset-otp', <String, dynamic>{
      'action': 'verify_and_reset',
      'schoolId': schoolId.trim(),
      'teacherId': teacherId,
      'challengeId': challengeId,
      'otp': otp.trim(),
      'newPassword': newPassword,
    });
  }

  Future<void> developerSetActive({
    required String developerKey,
    required String schoolRef,
    required bool isActive,
  }) async {
    await _invoke('psm-platform-admin', <String, dynamic>{
      'action': 'developer.set_active',
      'developerKey': developerKey,
      'schoolRef': schoolRef,
      'isActive': isActive,
    });
  }

  Future<void> developerSetBlocked({
    required String developerKey,
    required String schoolRef,
    required bool isBlocked,
    String blockReason = '',
  }) async {
    await _invoke('psm-platform-admin', <String, dynamic>{
      'action': 'developer.set_blocked',
      'developerKey': developerKey,
      'schoolRef': schoolRef,
      'isBlocked': isBlocked,
      'blockReason': blockReason,
    });
  }

  Future<void> developerUpdateValidity({
    required String developerKey,
    required String schoolRef,
    required String validityDate,
  }) async {
    await _invoke('psm-platform-admin', <String, dynamic>{
      'action': 'developer.update_school',
      'developerKey': developerKey,
      'schoolRef': schoolRef,
      'validityDate': validityDate,
    });
  }

  bool _looksLikeSchoolMap(Map<String, dynamic> value) {
    return const [
      'school_id',
      'schoolId',
      'school_name',
      'schoolName',
      'school_name_en',
      'schoolNameEn',
      'school_type',
      'schoolType',
    ].any(value.containsKey);
  }

  Map<String, dynamic> _findSchoolMap(dynamic value, [int depth = 0]) {
    if (depth > 7) return <String, dynamic>{};
    final map = _asMap(value);
    if (map.isEmpty) return <String, dynamic>{};

    for (final key in const [
      'school',
      'schoolInfo',
      'school_info',
      'schoolDetails',
      'school_details'
    ]) {
      final candidate = _asMap(map[key]);
      if (_looksLikeSchoolMap(candidate)) return candidate;
    }
    if (_looksLikeSchoolMap(map) && !map.containsKey('teacher')) return map;

    for (final key in const [
      'data',
      'context',
      'result',
      'payload',
      'details',
      'adminContext',
      'admin_context'
    ]) {
      final candidate = map[key];
      if (candidate is Map || candidate is List) {
        final found = _findSchoolMap(candidate, depth + 1);
        if (found.isNotEmpty) return found;
      }
    }
    // Handle wrappers that use a different property name without trusting scalar values.
    for (final entry in map.entries) {
      if (entry.value is Map || entry.value is List) {
        final found = _findSchoolMap(entry.value, depth + 1);
        if (found.isNotEmpty) return found;
      }
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _findContextMap(dynamic value, [int depth = 0]) {
    if (depth > 7) return <String, dynamic>{};
    final map = _asMap(value);
    if (map.isEmpty) return <String, dynamic>{};
    final directSchool = _findSchoolMap(map);
    if (directSchool.isNotEmpty &&
        (map.containsKey('teacher') ||
            map.containsKey('can_edit') ||
            map.containsKey('canEdit'))) {
      return map;
    }
    for (final entry in map.entries) {
      if (entry.value is Map || entry.value is List) {
        final found = _findContextMap(entry.value, depth + 1);
        if (found.isNotEmpty) return found;
      }
    }
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> adminGetContext() async {
    final result = await _invoke(
      'psm-platform-admin',
      <String, dynamic>{'action': 'admin.get_context'},
    );

    final context = _findContextMap(result);
    final school = _findSchoolMap(result);
    if (school.isEmpty) {
      throw Exception(
        'The Admin context response did not contain a recognizable school object. '
        'Response keys: ${result.keys.join(', ')}. Refresh and retry; if this persists, '
        'verify the deployed psm-platform-admin function version.',
      );
    }

    final normalized =
        Map<String, dynamic>.from(context.isNotEmpty ? context : result);
    normalized['school'] = Map<String, dynamic>.from(school);
    final normalizedSchool = normalized['school'] as Map<String, dynamic>;

    // Normalize common camelCase/snake_case response variants before the UI
    // decides whether edit controls should be available.
    normalizedSchool['school_name'] ??=
        normalizedSchool['schoolName'] ?? normalizedSchool['name'];
    normalizedSchool['school_id'] ??=
        normalizedSchool['schoolId'] ?? normalizedSchool['diseNumber'];
    normalizedSchool['school_type'] ??= normalizedSchool['schoolType'];
    normalizedSchool['is_active'] ??= normalizedSchool['isActive'];
    normalizedSchool['is_blocked'] ??= normalizedSchool['isBlocked'];
    normalizedSchool['validity_date'] ??= normalizedSchool['validityDate'];
    normalizedSchool['block_reason'] ??= normalizedSchool['blockReason'];

    final canEditValue = normalized['can_edit'] ??
        normalized['canEdit'] ??
        result['can_edit'] ??
        result['canEdit'];
    if (canEditValue != null) {
      normalized['can_edit'] = _nullableBool(canEditValue) == true;
    } else {
      final active = _nullableBool(normalizedSchool['is_active']);
      final blocked = _nullableBool(normalizedSchool['is_blocked']);
      if (active == null || blocked == null) {
        throw Exception(
          'The school details were received, but school edit permissions are missing. '
          'Redeploy psm-platform-admin and refresh.',
        );
      }
      final validity =
          (normalizedSchool['validity_date'] ?? '').toString().trim();
      final validityIso =
          validity.length >= 10 ? validity.substring(0, 10) : validity;
      bool dateValid = validityIso.isEmpty;
      if (validityIso.isNotEmpty) {
        try {
          final expiryDate = DateTime.parse(validityIso);
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final expiryDay =
              DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
          dateValid = !expiryDay.isBefore(today);
        } on FormatException {
          dateValid = false;
        }
      }
      normalized['can_edit'] = active && !blocked && dateValid;
    }
    normalized['can_download_reports'] ??= normalized['canDownloadReports'] ??
        result['can_download_reports'] ??
        result['canDownloadReports'] ??
        true;
    return normalized;
  }

  Future<List<Map<String, dynamic>>> adminListClasses() async {
    final result = await _invoke('psm-platform-admin',
        <String, dynamic>{'action': 'admin.list_classes'});
    final payload = _payloadWithKey(result, 'classes');
    final raw = payload['classes'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((row) => row.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  Future<List<Map<String, dynamic>>> adminListTeachers() async {
    final result = await _invoke('psm-platform-admin',
        <String, dynamic>{'action': 'admin.list_teachers'});
    final payload = _payloadWithKey(result, 'teachers');
    final raw = payload['teachers'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((row) => row.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  Future<void> adminCreateClass({
    required String classKey,
    required String label,
    String sheetName = '',
    String standard = '',
    String section = '',
    String reportGroup = '',
    int sortOrder = 0,
  }) async {
    await _invoke('psm-platform-admin', <String, dynamic>{
      'action': 'admin.create_class',
      'classKey': classKey.trim(),
      'label': label.trim(),
      'sheetName': sheetName.trim(),
      'standard': standard.trim(),
      'section': section.trim(),
      'reportGroup': reportGroup.trim(),
      'sortOrder': sortOrder,
    });
  }

  Future<void> adminSetClassActive(
      {required String classId, required bool isActive}) async {
    await _invoke('psm-platform-admin', <String, dynamic>{
      'action': 'admin.set_class_status',
      'classId': classId,
      'isActive': isActive,
    });
  }

  Future<void> adminCreateTeacher({
    required String teacherName,
    String mobile = '',
    required String password,
    required List<String> allowedClasses,
    List<Map<String, dynamic>> classSubjectAssignments =
        const <Map<String, dynamic>>[],
  }) async {
    final body = <String, dynamic>{
      'action': 'admin.create_teacher',
      'teacherName': teacherName.trim(),
      'password': password,
      'allowedClasses': allowedClasses,
      'classSubjectAssignments': classSubjectAssignments,
    };
    if (mobile.trim().isNotEmpty) body['mobile'] = mobile.trim();
    await _invoke('psm-platform-admin', body);
  }

  Future<void> adminUpdateTeacher({
    required String teacherId,
    bool? isActive,
    List<String>? allowedClasses,
    String? teacherName,
    String? mobile,
    String? newPassword,
    List<Map<String, dynamic>>? classSubjectAssignments,
  }) async {
    final body = <String, dynamic>{
      'action': 'admin.update_teacher',
      'teacherId': teacherId,
    };
    if (isActive != null) body['isActive'] = isActive;
    if (allowedClasses != null) body['allowedClasses'] = allowedClasses;
    if (teacherName != null) body['teacherName'] = teacherName.trim();
    if (mobile != null && mobile.trim().isNotEmpty)
      body['mobile'] = mobile.trim();
    if (newPassword != null && newPassword.isNotEmpty)
      body['newPassword'] = newPassword;
    if (classSubjectAssignments != null)
      body['classSubjectAssignments'] = classSubjectAssignments;
    await _invoke('psm-platform-admin', body);
  }
}

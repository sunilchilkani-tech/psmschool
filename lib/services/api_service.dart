import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart'; // આ નવું ઉમેર્યું
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class ApiService {
  final String baseUrl;
  String? schoolCode;
  String? sessionToken;

  /// Called when the server rejects an authenticated request. The owner clears
  /// the stale session and routes the user back to the login screen.
  final void Function(String? failedToken)? onAuthExpired;
  ApiService(this.baseUrl,
      {this.schoolCode, this.sessionToken, this.onAuthExpired});

  void setContext({String? schoolCode, String? sessionToken}) {
    this.schoolCode = schoolCode;
    this.sessionToken = sessionToken;
  }

  Uri _uri(String action, [Map<String, String>? extra]) {
    final params = <String, String>{
      'action': action,
      if ((schoolCode ?? '').trim().isNotEmpty)
        'schoolCode': schoolCode!.trim(),
      ...?extra,
      '_t': DateTime.now().millisecondsSinceEpoch.toString(),
    };
    return Uri.parse(baseUrl).replace(queryParameters: params);
  }

  Future<Map<String, dynamic>> _getJson(
    String action, {
    Map<String, String>? params,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    late final http.Response resp;
    // Snapshot the token for this request so a late response from an older
    // request cannot clear a newer login session.
    final requestToken = (sessionToken ?? '').trim();
    final requestData = <String, dynamic>{
      'action': action,
      if ((schoolCode ?? '').trim().isNotEmpty)
        'schoolCode': schoolCode!.trim(),
      if (requestToken.isNotEmpty) 'sessionToken': requestToken,
      ...?params,
      '_t': DateTime.now().millisecondsSinceEpoch.toString(),
    };

    // Apps Script ContentService redirects its response to script.googleusercontent.com.
    // In Flutter Web, that redirect can make fetch-based POST requests fail with
    // ClientException: Failed to fetch, even when the Apps Script endpoint itself
    // is healthy. Use GET for compact API requests in the browser; the same server
    // router and session validation still run. Keep POST for large/binary payloads.
    // Native Flutter platforms retain the POST behavior for authenticated requests.
    final queryData =
        requestData.map((key, value) => MapEntry(key, value.toString()));
    final webGetUri = Uri.parse(baseUrl).replace(queryParameters: queryData);
    const postOnlyActions = <String>{
      'createSchool',
      'uploadSchoolLogo',
      'bulkUploadRoster',
      'importAdminRecords',
    };
    final longRequest = webGetUri.toString().length > 6500;
    final usePost = kIsWeb
        ? (postOnlyActions.contains(action) || longRequest)
        : (requestToken.isNotEmpty ||
            action == 'login' ||
            action == 'createSchool' ||
            action == 'uploadSchoolLogo');

    try {
      if (kIsWeb && !usePost) {
        // All query values are URL-encoded by Uri. Avoid including the URL in any
        // error message because it may contain a session token or PIN.
        resp = await http.get(webGetUri).timeout(timeout);
      } else if (usePost) {
        resp = await http
            .post(
              Uri.parse(baseUrl),
              headers: const {'Content-Type': 'text/plain; charset=utf-8'},
              body: jsonEncode(requestData),
            )
            .timeout(timeout);
      } else {
        final query = <String, String>{
          'action': action,
          '_t': requestData['_t'].toString(),
        };
        if ((schoolCode ?? '').trim().isNotEmpty) {
          query['schoolCode'] = schoolCode!.trim();
        }
        if (params != null) query.addAll(params);
        resp = await http
            .get(
              Uri.parse(baseUrl).replace(queryParameters: query),
            )
            .timeout(timeout);
      }
    } catch (e) {
      throw ApiException(
        'સર્વર સાથે જોડાણ થઈ શક્યું નથી. URL અને ઇન્ટરનેટ તપાસો. '
        '(API: $action, ${e.runtimeType})',
      );
    }

    if (resp.statusCode != 200) {
      throw ApiException('સર્વર ભૂલ (HTTP ${resp.statusCode}; API: $action)');
    }
    try {
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        if (decoded['code'] == 'AUTH_REQUIRED') {
          // Keep the request usable for its caller, but clear the expired session
          // asynchronously so the root gate can display LoginScreen.
          onAuthExpired?.call(requestToken.isEmpty ? null : requestToken);
        }
        return decoded;
      }
      throw ApiException('અનપેક્ષિત જવાબ મળ્યો. (API: $action)');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('જવાબ સમજી શકાયો નહીં (Invalid JSON; API: $action).');
    }
  }

  Future<bool> ping() async {
    try {
      await _getJson('platformPing', timeout: const Duration(seconds: 12));
      return true;
    } catch (_) {
      return false;
    }
  }

  // ==========================================================
  // TENANT / SESSION / SCHOOL CONFIGURATION
  // ==========================================================

  Future<Map<String, dynamic>> getSchoolInfo() => _getJson('getSchoolInfo');

  Future<Map<String, dynamic>> loginTeacher(String teacherName, String pin) {
    return _getJson('login', params: {'teacherName': teacherName, 'pin': pin});
  }

  Future<Map<String, dynamic>> validateSession() => _getJson('validateSession');

  Future<Map<String, dynamic>> getSchoolConfig() => _getJson('getSchoolConfig');

  Future<Map<String, dynamic>> updateSchoolConfig(Map<String, String> values) =>
      _getJson('updateSchoolConfig', params: values);

  Future<Map<String, dynamic>> createClass(
          {required String label,
          String? standard,
          String? section,
          String? reportGroup}) =>
      _getJson('createClass', params: {
        'label': label,
        if (standard != null) 'standard': standard,
        if (section != null) 'section': section,
        if (reportGroup != null) 'reportGroup': reportGroup,
      });

  Future<Map<String, dynamic>> createTeacher(
          {required String name,
          required String pin,
          required List<String> classes,
          String role = 'teacher',
          String email = ''}) =>
      _getJson('createTeacher', params: {
        'name': name,
        'pin': pin,
        'classes': classes.join(','),
        'role': role,
        'email': email,
      });

  Future<Map<String, dynamic>> deactivateTeacher(String name) =>
      _getJson('deactivateTeacher', params: {'name': name});

  Future<Map<String, dynamic>> uploadSchoolLogo(
          {required String base64,
          required String mimeType,
          required String fileName}) =>
      _getJson('uploadSchoolLogo',
          params: {
            'base64': base64,
            'mimeType': mimeType,
            'fileName': fileName,
          },
          timeout: const Duration(seconds: 50));

  Future<Map<String, dynamic>> setStudentGender(
          {required String className,
          required String rollNumber,
          required String name,
          required String gender}) =>
      _getJson('setStudentGender', params: {
        'className': className,
        'rollNumber': rollNumber,
        'name': name,
        'gender': gender,
      });

  Future<Map<String, dynamic>> getGenderSummary(
          {required String month, String group = 'ALL'}) =>
      _getJson('getGenderSummary', params: {'month': month, 'group': group});

  Future<Map<String, dynamic>> getGenderSummaryPdf(
          {required String month, String group = 'ALL'}) =>
      _getJson('getGenderSummaryPDF',
          params: {'month': month, 'group': group},
          timeout: const Duration(seconds: 60));

  Future<void> logoutSession() async {
    if (sessionToken == null || sessionToken!.isEmpty) return;
    try {
      await _getJson('logout');
    } finally {
      sessionToken = null;
    }
  }

  // ==========================================================
  // TEACHERS / LOGIN
  // ==========================================================

  Future<List<Teacher>> getTeachers() async {
    final json = await _getJson('getTeachers');
    if (json['result'] != 'success') {
      throw ApiException(
          (json['message'] ?? json['error'] ?? 'Teachers લોડ કરી શકાયા નહીં.')
              .toString());
    }
    final list = (json['teachers'] as List? ?? []);
    return list
        .whereType<Map>()
        .map((e) => Teacher.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<Map<String, dynamic>> changePassword(
      String teacherName, String newPin) {
    return _getJson('changePassword', params: {
      'teacherName': teacherName,
      'newPin': newPin,
    });
  }

  // ==========================================================
  // ATTENDANCE
  // ==========================================================

  Future<RowData> getRowData(String className, String date) async {
    final json = await _getJson('getRowData', params: {
      'className': className,
      'date': date,
    });
    if (json['error'] != null) {
      throw ApiException(json['error'].toString());
    }
    final registered =
        CategoryCounts.fromJson(json['registered'] as Map<String, dynamic>?);
    final attJson = json['attendance'];
    final attendance = (attJson is Map<String, dynamic>)
        ? AttendanceRecord.fromJson(attJson)
        : null;

    final rawStudents = json['students'];
    final students = rawStudents is List
        ? rawStudents
            .whereType<Map>()
            .map((e) => StudentRecord.fromJson(e.cast<String, dynamic>()))
            .toList()
        : const <StudentRecord>[];

    return RowData(
      registered: registered,
      attendance: attendance,
      students: students,
      studentDetailsSaved: json['studentDetailsSaved'] == true,
      attendanceMode: (json['attendanceMode'] ?? 'none').toString(),
      genderBreakdown: json['genderBreakdown'] is Map
          ? (json['genderBreakdown'] as Map).cast<String, dynamic>()
          : const {},
    );
  }

  Future<Map<String, dynamic>> saveStudentAttendance({
    required String className,
    required String date,
    required List<StudentRecord> students,
  }) {
    final presentIds =
        students.where((s) => s.present).map((s) => s.id).join(',');
    final mdmIds =
        students.where((s) => s.present && s.mdm).map((s) => s.id).join(',');
    final breakfastIds = students
        .where((s) => s.present && s.breakfast)
        .map((s) => s.id)
        .join(',');

    return _getJson('saveStudentAttendance', params: {
      'className': className,
      'date': date,
      'presentIds': presentIds,
      'mdmIds': mdmIds,
      'breakfastIds': breakfastIds,
    });
  }

  Future<Map<String, AttendanceRecord>> getAttendance(String className) async {
    final json =
        await _getJson('getAttendance', params: {'className': className});
    if (json['error'] != null) throw ApiException(json['error'].toString());
    return json.map((date, value) => MapEntry(
        date, AttendanceRecord.fromJson(value as Map<String, dynamic>)));
  }

  Future<Map<String, dynamic>> saveAttendance({
    required String className,
    required String date,
    required CategoryCounts present,
    required CategoryCounts mdm,
    required int breakfastTotal,
    CategoryCounts? registered,
    Map<String, dynamic>? genderBreakdown,
  }) {
    final params = <String, String>{
      'className': className,
      'date': date,
      ...present.toApiParams('pres').map((k, v) => MapEntry(k, v.toString())),
      ...mdm.toApiParams('mdm').map((k, v) => MapEntry(k, v.toString())),
      'breakfastTotal': breakfastTotal.toString(),
      if (registered != null)
        ...registered
            .toApiParams('reg')
            .map((k, v) => MapEntry(k, v.toString())),
      if (genderBreakdown != null)
        'genderBreakdown': jsonEncode(genderBreakdown),
    };
    return _getJson('saveAttendance', params: params);
  }

  // ==========================================================
  // TODAY MESSAGE
  // ==========================================================

  Future<String> getTodayMessage(String date) async {
    final json = await _getJson('getTodayMessage', params: {'date': date});
    return (json['message'] ?? '').toString();
  }

  // ==========================================================
  // HOLIDAYS
  // ==========================================================

  Future<Map<String, String>> getHolidays() async {
    final json = await _getJson('getHolidays');
    return json.map((k, v) => MapEntry(k, v.toString()));
  }

  Future<Map<String, dynamic>> saveHoliday(String date, String reason) {
    return _getJson('saveHoliday', params: {'date': date, 'reason': reason});
  }

  Future<Map<String, dynamic>> deleteHoliday(String date) {
    return _getJson('deleteHoliday', params: {'date': date});
  }

  // ==========================================================
  // ADMIN MESSAGES
  // ==========================================================

  Future<Map<String, dynamic>> saveMessage(String date, String message) {
    return _getJson('saveMessage', params: {'date': date, 'message': message});
  }

  Future<List<AdminMessage>> getMessages() async {
    final json = await _getJson('getMessages');
    final list = (json['messages'] as List? ?? []);
    return list
        .whereType<Map>()
        .map((e) => AdminMessage.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<Map<String, dynamic>> deleteMessage(String date) {
    return _getJson('deleteMessage', params: {'date': date});
  }

  /// Imports Admin Messages or Holidays by date. Existing dates are updated;
  /// records omitted from the file are left untouched. Server access is admin-only.
  Future<Map<String, dynamic>> importAdminRecords({
    required String kind,
    required List<Map<String, dynamic>> records,
  }) {
    return _getJson(
      'importAdminRecords',
      params: {'kind': kind, 'recordsJson': jsonEncode(records)},
      timeout: const Duration(seconds: 60),
    );
  }

  /// Returns all teacher leave records for the Admin Panel export.
  Future<Map<String, dynamic>> getAllTeacherLeaveRecords() => _getJson(
        'getAllTeacherLeaveRecords',
        timeout: const Duration(seconds: 45),
      );

  // ==========================================================
  // DATE WISE REPORT / PDF
  // ==========================================================

  Future<Map<String, dynamic>> getDateWiseReport(String serial) {
    return _getJson('getDateWiseReport', params: {'serial': serial});
  }

  Future<Map<String, dynamic>> getDateWiseReportByDate(String date) {
    return _getJson('getDateWiseReportByDate', params: {'date': date});
  }

  Future<Map<String, dynamic>> saveDateWisePDF(String serial) {
    return _getJson(
      'saveDateWisePDF',
      params: {'serial': serial},
      timeout: const Duration(seconds: 45),
    );
  }

  Future<Map<String, dynamic>> saveDateWisePDFByDate(String date) {
    return _getJson(
      'saveDateWisePDFByDate',
      params: {'date': date},
      timeout: const Duration(seconds: 55),
    );
  }

  // ==========================================================
  // MONTHLY AREA PDFs
  // ==========================================================

  Future<Map<String, dynamic>> getBalvatikaEkandarPDF(String month) => _getJson(
        'getBalvatikaEkandarPDF',
        params: {'month': month},
        timeout: const Duration(seconds: 45),
      );

  Future<Map<String, dynamic>> getStd1to5EkandarPDF(String month) => _getJson(
        'getStd1to5EkandarPDF',
        params: {'month': month},
        timeout: const Duration(seconds: 45),
      );

  Future<Map<String, dynamic>> getStd6to8EkandarPDF(String month) => _getJson(
        'getStd6to8EkandarPDF',
        params: {'month': month},
        timeout: const Duration(seconds: 45),
      );

  Future<Map<String, dynamic>> getTarijPDF(String month) => _getJson(
        'getTarijPDF',
        params: {'month': month},
        timeout: const Duration(seconds: 45),
      );

  // ==========================================================
  // TARIJ CLASS-WISE (on-screen)
  // ==========================================================

  Future<List<String>> getTarijClassNames() async {
    final json = await _getJson('getTarijClassNames');
    return (json['classes'] as List? ?? []).map((e) => e.toString()).toList();
  }

  Future<Map<String, dynamic>> getTarijClassData(
      String className, String month) {
    return _getJson('getTarijClassData', params: {
      'className': className,
      'month': month,
    });
  }

  // ==========================================================
  // RESULT SHEET (પરિણામ પત્રક)
  // ==========================================================

  Future<ResultSheetData> getResultData(String className) async {
    final json =
        await _getJson('getResultData', params: {'className': className});
    if (json['result'] != 'success') {
      throw ApiException(
          (json['message'] ?? json['error'] ?? 'Result data load error')
              .toString());
    }
    final subjects =
        (json['subjects'] as List? ?? []).map((e) => e.toString()).toList();
    final vvSentences =
        (json['vvSentences'] as List? ?? []).map((e) => e.toString()).toList();
    final students = (json['students'] as List? ?? [])
        .whereType<Map>()
        .map((e) => ResultStudentRow.fromJson(e.cast<String, dynamic>()))
        .toList();
    return ResultSheetData(
      className: className,
      subjects: subjects,
      students: students,
      teacherName: (json['teacherName'] ?? '').toString(),
      resultDate: (json['resultDate'] ?? '30/04/2027').toString(),
      academicYear: (json['academicYear'] ?? '2026 - 27').toString(),
      vvSentences: vvSentences,
      sem1Locked: json['sem1Locked'] == true, // નવું
      sem2Locked: json['sem2Locked'] == true, // નવું
    );
  }

  Future<Map<String, dynamic>> saveSubjectMarks({
    required String className,
    required String sem,
    required String subject,
    String entryCombo = 'all_3',
    required List<Map<String, dynamic>> payload,
  }) {
    return _getJson(
      'saveSubjectMarks',
      params: {
        'className': className,
        'sem': sem,
        'subject': subject,
        'entryCombo': entryCombo,
        'payload': jsonEncode(payload),
      },
      timeout: const Duration(seconds: 40),
    );
  }

  Future<Map<String, dynamic>> addNewStudent({
    required String className,
    required Map<String, dynamic> studentData,
  }) {
    return _getJson(
      'addNewStudent',
      params: {
        'className': className,
        'studentJson': jsonEncode(studentData),
      },
      timeout: const Duration(seconds: 35),
    );
  }

  Future<Map<String, dynamic>> exportResultPdf({
    required String className,
    required String sem,
    required String pdfType,
    bool showParinam = true,
    String parinamMode = 'auto',
  }) {
    return _getJson(
      'exportResultPdf',
      params: {
        'className': className,
        'sem': sem,
        'pdfType': pdfType,
        'showParinam': showParinam ? 'true' : 'false',
        'parinamMode': parinamMode,
      },
      timeout: const Duration(seconds: 55),
    );
  }

  Future<Map<String, dynamic>> saveVvSentences({
    required String className,
    required List<String> sentences,
  }) {
    return _getJson(
      'saveVvSentences',
      params: {
        'className': className,
        'sentencesJson': jsonEncode(sentences),
      },
      timeout: const Duration(seconds: 35),
    );
  }

  Future<Map<String, dynamic>> saveClassSubjects({
    required String className,
    required List<String> subjects,
  }) {
    return _getJson(
      'saveClassSubjects',
      params: {
        'className': className,
        'subjectsJson': jsonEncode(subjects),
      },
      timeout: const Duration(seconds: 40),
    );
  }

  // ==========================================================
  // STUDENT PROFILES & REGISTRATION
  // ==========================================================

  Future<Map<String, dynamic>> saveRegistrationCounts({
    required String className,
    required String date,
    required int sc,
    required int st,
    required int obc,
    required int other,
    Map<String, dynamic>? genderBreakdown,
  }) {
    return _getJson('saveRegistrationCounts', params: {
      'className': className,
      'date': date,
      'sc': sc.toString(),
      'st': st.toString(),
      'obc': obc.toString(),
      'other': other.toString(),
      if (genderBreakdown != null)
        'genderBreakdown': jsonEncode(genderBreakdown),
    });
  }

  Future<Map<String, dynamic>> manageStudentProfile({
    required String className,
    required String actionType,
    required Map<String, dynamic> studentJson,
  }) {
    return _getJson('manageStudentProfile', params: {
      'className': className,
      'actionType': actionType,
      'studentJson': jsonEncode(studentJson),
    });
  }

  Future<Map<String, dynamic>> getHajariFrontPagePDF(
      String month, String className) {
    return _getJson('getHajariFrontPagePDF',
        params: {
          'month': month,
          'className': className,
        },
        timeout: const Duration(seconds: 45));
  }

  Future<Map<String, dynamic>> getSavedPdfSettings(String className) {
    return _getJson('getSavedPdfSettings', params: {
      'className': className,
    });
  }

  // ==========================================================
  // BULK EXPORT TO EXCEL
  // ==========================================================
  Future<Map<String, dynamic>> exportStudentDataExcel({
    required String classFilter,
    required String catFilter,
    required String schFilter,
    required List<String> columns,
  }) {
    return _getJson(
      'exportStudentDataExcel',
      params: {
        'classFilter': classFilter,
        'catFilter': catFilter,
        'schFilter': schFilter,
        'columns': columns.join(','),
      },
      timeout: const Duration(seconds: 60),
    );
  }

  Future<List<String>> getCustomHeaders() async {
    final json = await _getJson('getCustomHeaders');
    return (json['headers'] as List? ?? []).map((e) => e.toString()).toList();
  }

  Future<Map<String, dynamic>> saveCustomHeaders(List<String> headers) {
    return _getJson('saveCustomHeaders',
        params: {'headers': jsonEncode(headers)});
  }

  Future<Map<String, dynamic>> getHajariPatrakPDF(
      String month, String className,
      {String? rowHeight, String? fontSize}) {
    final params = {
      'month': month,
      'className': className,
    };
    if (rowHeight != null && rowHeight.isNotEmpty)
      params['customRowHeight'] = rowHeight;
    if (fontSize != null && fontSize.isNotEmpty)
      params['customFontSize'] = fontSize;

    return _getJson('getHajariPatrakPDF',
        params: params, timeout: const Duration(seconds: 55));
  }

  Future<Map<String, dynamic>> toggleResultLock(
      {required String className,
      required String sem,
      required bool isLocked}) {
    return _getJson('toggleResultLock', params: {
      'className': className,
      'sem': sem,
      'locked': isLocked.toString()
    });
  }

  Future<Map<String, dynamic>> submitLeave(Map<String, dynamic> params) {
    return _getJson('submitLeave',
        params: params.map((k, v) => MapEntry(k, v.toString())));
  }

  Future<Map<String, dynamic>> getPendingLeaves() {
    return _getJson('getPendingLeaves');
  }

  Future<Map<String, dynamic>> approveLeave(String id, String status) {
    return _getJson('approveLeave', params: {'id': id, 'status': status});
  }

  Future<List<Map<String, dynamic>>> getTeachersRaw() async {
    final json = await _getJson('getTeachersRaw'); // હવે નવું API કોલ કરશે
    final list = json['teachers'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> getUtilizedLeaves(String teacherName) {
    return _getJson('getUtilizedLeaves', params: {'teacher': teacherName});
  }

  // ==========================================================
  // BULK EXCEL UPLOAD & DOWNLOAD TEMPLATE
  // ==========================================================

  Future<void> downloadExcelTemplate() async {
    final response = await exportStudentDataExcel(
      classFilter: 'BLANK_TEMPLATE',
      catFilter: 'ALL',
      schFilter: 'ALL',
      columns: const [
        'className',
        'rollNumber',
        'gr',
        'dd',
        'mm',
        'yyyy',
        'name',
        'gender',
        'caste',
        'category',
        'enrollSchool',
        'enrollClass',
        'mobile',
        'fatherName',
        'motherName',
        'birthPlace',
        'dobWords',
        'lastSchool',
        'enrollSchClass',
        'enrollSchClassWords',
        'presentDays',
        'nameEn',
        'casteEn',
        'catEn',
        'motherEn',
        'birthPlaceEn',
        'dobEn',
        'lastSchoolEn',
        'enrollSchClassEn',
        'enrollSchClassWordsEn',
        'apaarId',
        'scholarshipDone',
        'scholarshipReason',
        'uid',
        'pen',
        'bankName',
        'bankBranch',
        'nameAsPassbook',
        'accountNumber',
        'ifscCode',
        'nativePlace',
        'nativePlaceEn',
      ],
    );

    if (response['result'] == 'success' && response['base64'] != null) {
      final bytes = base64Decode(response['base64'].toString());
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            name: 'Blank_Template.xlsx',
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          )
        ],
        text:
            'આ ખાલી ટેમ્પલેટ છે. ધોરણ, કેટેગરી, જાતિ અને શિષ્યવૃત્તિના dropdown પ્રમાણે માહિતી ભરીને અપલોડ કરો.',
      );
    } else {
      throw ApiException(
          response['message'] ?? 'ટેમ્પલેટ ડાઉનલોડ કરવામાં ભૂલ આવી.');
    }
  }

  Future<Map<String, dynamic>> uploadWholeSchoolData(
    Map<String, List<List<dynamic>>> dataByClass, {
    List<String>? headers,
  }) async {
    // Bulk upload is an authenticated, school-scoped operation. Always send the
    // same tenant and session context as every other protected API request.
    final code = (schoolCode ?? '').trim();
    final token = (sessionToken ?? '').trim();
    if (code.isEmpty) {
      return {
        'result': 'error',
        'message':
            'School code is missing. Please select your school and sign in again.',
      };
    }
    if (token.isEmpty) {
      return {
        'result': 'error',
        'message': 'Login session is missing or expired. Please sign in again.',
      };
    }

    try {
      final response = await http
          .post(
            Uri.parse(baseUrl),
            headers: const {'Content-Type': 'text/plain; charset=utf-8'},
            body: jsonEncode({
              'action': 'bulkUploadRoster',
              'schoolCode': code,
              'sessionToken': token,
              '_t': DateTime.now().millisecondsSinceEpoch.toString(),
              'headers': headers ?? const <String>[],
              'data': dataByClass,
            }),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {
          'result': 'error',
          'message': 'HTTP Error: ${response.statusCode}',
        };
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        if (decoded['code'] == 'AUTH_REQUIRED') onAuthExpired?.call(token);
        return decoded;
      }
      return {
        'result': 'error',
        'message': 'Unexpected response received from the server.',
      };
    } catch (e) {
      return {'result': 'error', 'message': e.toString()};
    }
  }

// વિદ્યાર્થીઓના બર્થડે ચેક કરવા
  Future<String> getStudentBirthdays(List<String> classes) async {
    final json = await _getJson('getStudentBirthdays',
        params: {'classes': classes.join(',')});
    return (json['message'] ?? '').toString();
  }
}

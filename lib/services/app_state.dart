import 'dart:convert';

import 'package:flutter/foundation.dart' hide Category;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import '../data/app_config.dart';
import '../models/models.dart';
import 'api_service.dart';
import 'supabase_result_api_service.dart';
import 'school_type.dart';

class AppState extends ChangeNotifier {
  late SharedPreferences _prefs;

  String? backendUrl;
  ApiService? api;
  // The professional platform uses one routed Web App for both attendance and results.
  String? resultBackendUrl;
  ApiService? resultApi;

  String? schoolCode;
  String? sessionToken;
  Map<String, dynamic> schoolConfig = <String, dynamic>{};
  List<SchoolClass> schoolClasses = <SchoolClass>[];
  bool schoolConfigLoaded = false;

  Teacher? currentTeacher;
  bool restoringSession = true;
  Map<String, String> holidays = {};
  String? lastSelectedClass;
  String preferredEntryMode = 'student';
  bool quickPickMode = true;
  String activeModule = 'menu';
  String lastSemester = '1';
  String? lastSubject;
  bool _handlingAuthExpired = false;
  List<Teacher> _availableLoginTeachers = <Teacher>[];

  bool get isLoggedIn =>
      currentTeacher != null && (sessionToken ?? '').isNotEmpty;
  bool get isAdmin => currentTeacher?.isAdmin ?? false;
  Map<String, dynamic> get school => schoolConfig['school'] is Map
      ? (schoolConfig['school'] as Map).cast<String, dynamic>()
      : schoolConfig;
  String get schoolNameLanguageRef {
    final s = school;
    for (final value in <dynamic>[
      s['school_ref'],
      s['schoolRef'],
      s['school_id'],
      s['schoolId'],
      s['id'],
      schoolCode,
    ]) {
      final ref = (value ?? '').toString().trim();
      if (ref.isNotEmpty && ref.toLowerCase() != 'null') return ref;
    }
    return '';
  }

  String get schoolNameLanguage {
    try {
      return _prefs.getString(
                'hajari_patrak_school_name_language_$schoolNameLanguageRef',
              ) ==
              'en'
          ? 'en'
          : 'gu';
    } catch (_) {
      return 'gu';
    }
  }

  String get schoolName {
    final s = school;
    String first(Iterable<dynamic> candidates) {
      for (final candidate in candidates) {
        final value = (candidate ?? '').toString().trim();
        if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
      }
      return '';
    }

    final gu = first(<dynamic>[
      s['schoolNameGu'],
      s['school_name_gu'],
      s['gujaratiSchoolName'],
      s['name_gu'],
    ]);
    final en = first(<dynamic>[
      s['schoolNameEn'],
      s['school_name_en'],
      s['schoolName'],
      s['school_name'],
      s['name'],
      'School Management',
    ]);
    if (schoolNameLanguage == 'gu' && gu.isNotEmpty) return gu;
    return en.isNotEmpty ? en : (gu.isNotEmpty ? gu : 'School Management');
  }

  /// 'boys', 'girls' or 'coed' — always normalised (stored values may be
  /// 'mixed', 'Boys', Gujarati labels, ...).
  String get schoolType => SchoolType.coedCompat(school['schoolType']);
  String get logoUrl => (school['logoUrl'] ?? '').toString();

  List<SchoolClass> get allSchoolClasses {
    // Never leak one school's predefined class list into another school's account.
    // Keep database keys intact, but do not expose generated class_<timestamp>
    // identifiers as user-facing classes.
    final visible = schoolClasses
        .where((klass) => klass.displayLabel.trim().isNotEmpty)
        .toList(growable: false);
    final stableDisplayLabels = visible
        .where((klass) => !SchoolClass.isSyntheticClassId(klass.key))
        .map((klass) => klass.displayLabel.trim().toLowerCase())
        .toSet();
    return List<SchoolClass>.unmodifiable(
      visible.where((klass) {
        if (!SchoolClass.isSyntheticClassId(klass.key)) return true;
        return !stableDisplayLabels.contains(
          klass.displayLabel.trim().toLowerCase(),
        );
      }),
    );
  }

  List<SchoolClass> get allowedClasses {
    if (currentTeacher == null) return const [];
    final source = allSchoolClasses;
    final allowed = currentTeacher!.classes ?? const <String>[];
    final visible = currentTeacher!.isAdmin
        ? source
        : source
              .where(
                (c) => allowed.any(
                  (a) =>
                      _sameClass(a, c.key) ||
                      _sameClass(a, c.label) ||
                      _sameClass(a, c.sheetName),
                ),
              )
              .toList();

    // Some school imports can contain duplicate class rows/labels. A
    // DropdownButton requires exactly one item for its selected value.
    // Keep the first active class for each normalized class key.
    final seenKeys = <String>{};
    return visible
        .where((c) {
          final normalizedKey = c.key.trim().toLowerCase().replaceAll(
            RegExp(r'\s+'),
            '',
          );
          return normalizedKey.isNotEmpty && seenKeys.add(normalizedKey);
        })
        .toList(growable: false);
  }

  bool _sameClass(String a, String b) {
    String clean(String v) => v
        .replaceFirst(RegExp(r'^Class\s+', caseSensitive: false), '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '');
    return clean(a) == clean(b);
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    // Supabase Auth owns the session. Do not restore or call a legacy Apps Script /
    // Firebase backend URL during the Supabase migration.
    backendUrl = '';
    api = null;
    resultBackendUrl = 'supabase';
    resultApi = SupabaseResultApiService();
    schoolCode = (_prefs.getString(AppConfig.prefsKeySchoolCode) ?? '')
        .trim()
        .toUpperCase();
    sessionToken = null;

    lastSelectedClass = _prefs.getString(AppConfig.prefsKeyLastClass);
    preferredEntryMode =
        _prefs.getString(AppConfig.prefsKeyEntryMode) ?? 'student';
    quickPickMode = _prefs.getBool(AppConfig.prefsKeyQuickPick) ?? true;
    activeModule = _prefs.getString(AppConfig.prefsKeyLastModule) ?? 'menu';
    lastSemester = _prefs.getString(AppConfig.prefsKeyLastSemester) ?? '1';
    lastSubject = _prefs.getString(AppConfig.prefsKeyLastSubject);

    final cachedConfig = _prefs.getString(AppConfig.prefsKeySchoolConfig);
    if (cachedConfig != null && cachedConfig.isNotEmpty) {
      try {
        _applySchoolConfig(
          jsonDecode(cachedConfig) as Map<String, dynamic>,
          persist: false,
        );
      } catch (_) {}
    }

    try {
      final client = Supabase.instance.client;
      final session = client.auth.currentSession;
      if (session != null && client.auth.currentUser != null) {
        sessionToken = session.accessToken;
        try {
          await _loadSupabaseIdentity(expectedSchoolCode: schoolCode);
          await _loadSupabaseHolidays();
        } catch (_) {
          // Do not trust a cached teacher record when the server cannot validate it.
          // Supabase keeps its session storage; the teacher must be revalidated on
          // the next login attempt rather than falling back to the old backend.
          currentTeacher = null;
          sessionToken = null;
          schoolClasses = <SchoolClass>[];
          schoolConfigLoaded = false;
        }
      }
    } catch (_) {
      currentTeacher = null;
      sessionToken = null;
    }

    _ensureDefaultClassSelected();
    restoringSession = false;
    notifyListeners();
  }

  /// Prepares the existing ResultShell for the already-authenticated Supabase school.
  /// Identity is checked with authenticated RPCs; class visibility is filtered by RLS.
  /// This deliberately avoids re-running init(), which would attempt a direct teacher-table read.
  Future<void> prepareResultModuleForSupabaseProfile(
    Map<String, dynamic> profile,
  ) async {
    _prefs = await SharedPreferences.getInstance();
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    if (session == null || client.auth.currentUser == null) {
      throw ApiException('તમારું Supabase session મળ્યું નથી. ફરી લૉગ ઇન કરો.');
    }

    final rawSchoolRef = await client.rpc('current_school_ref');
    final rawTeacherId = await client.rpc('current_teacher_id');
    final activeSchoolRef = '${rawSchoolRef ?? ''}'.trim();
    final activeTeacherId = '${rawTeacherId ?? ''}'.trim();
    if (activeSchoolRef.isEmpty || activeTeacherId.isEmpty) {
      throw ApiException('આ લૉગિન સાથે સક્રિય શાળા અથવા શિક્ષક જોડાયેલા નથી.');
    }

    final suppliedSchoolRef =
        '${profile['school_ref'] ?? profile['schoolRef'] ?? ''}'.trim();
    final suppliedTeacherId =
        '${profile['teacher_id'] ?? profile['teacherId'] ?? ''}'.trim();
    if (suppliedSchoolRef.isNotEmpty && suppliedSchoolRef != activeSchoolRef) {
      throw ApiException(
        'લૉગિન શાળા અને વર્તમાન Supabase શાળા મેળ ખાતા નથી. ફરી લૉગ ઇન કરો.',
      );
    }
    if (suppliedTeacherId.isNotEmpty && suppliedTeacherId != activeTeacherId) {
      throw ApiException(
        'લૉગિન શિક્ષક અને વર્તમાન Supabase ખાતું મેળ ખાતાં નથી. ફરી લૉગ ઇન કરો.',
      );
    }

    final roleFromProfile = '${profile['role'] ?? 'teacher'}'
        .trim()
        .toLowerCase();
    if (roleFromProfile == 'developer' ||
        profile['is_blocked'] == true ||
        profile['can_edit'] == false) {
      throw ApiException('આ ખાતા માટે Result ઉપલબ્ધ નથી.');
    }

    // This query is still protected by school_classes RLS. It returns only classes
    // that the authenticated user can access, even if the client profile is stale.
    final isAdminValue = await client.rpc('is_school_admin');
    final isAdminSession = isAdminValue == true;
    final rawRows = await client
        .from('school_classes')
        .select(
          'id,school_ref,class_key,label,sheet_name,standard,section,report_group,sort_order,is_active',
        )
        .eq('school_ref', activeSchoolRef)
        .eq('is_active', true)
        .order('sort_order', ascending: true)
        .order('label', ascending: true);

    final classConfig = <Map<String, dynamic>>[];
    final seenClassKeys = <String>{};
    for (final raw in rawRows) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final key = '${row['class_key'] ?? row['label'] ?? ''}'.trim();
      final normalizedKey = key.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      if (key.isEmpty || !seenClassKeys.add(normalizedKey)) continue;
      classConfig.add(<String, dynamic>{
        'id': '${row['id'] ?? ''}',
        'key': key,
        'label': '${row['label'] ?? key}',
        'sheetName': '${row['sheet_name'] ?? row['label'] ?? key}',
        'standard': '${row['standard'] ?? ''}',
        'section': '${row['section'] ?? ''}',
        'reportGroup': '${row['report_group'] ?? ''}',
      });
    }

    final classKeysVisibleToThisUser = classConfig
        .map((row) => '${row['key']}')
        .where((value) => value.trim().isNotEmpty)
        .toList();
    final rawAllowed = profile['allowed_classes'] ?? profile['allowedClasses'];
    final profileAllowedClasses = rawAllowed is List
        ? rawAllowed
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toList()
        : <String>[];
    // If profile data has no class list, use the classes returned by the RLS-filtered
    // query. An empty allowed_classes list on the server still yields no rows via RLS.
    final effectiveAllowedClasses = isAdminSession
        ? classKeysVisibleToThisUser
        : (profileAllowedClasses.isNotEmpty
              ? profileAllowedClasses
              : classKeysVisibleToThisUser);

    final teacherName =
        <Object?>[
              profile['teacher_name'],
              profile['teacherName'],
              profile['name'],
            ]
            .map((value) => '${value ?? ''}'.trim())
            .firstWhere(
              (value) => value.isNotEmpty && value.toLowerCase() != 'null',
              orElse: () => '',
            );
    if (teacherName.isEmpty) {
      throw ApiException(
        'સાઇન-ઇન પ્રોફાઇલમાં શિક્ષકનું નામ નથી. ફરી લૉગ ઇન કરો.',
      );
    }

    final schoolCodeValue =
        <Object?>[
              profile['school_id'],
              profile['school_code'],
              profile['schoolId'],
              profile['schoolCode'],
              profile['dise_number'],
              profile['diseNumber'],
            ]
            .map((value) => '${value ?? ''}'.trim())
            .firstWhere(
              (value) => value.isNotEmpty && value.toLowerCase() != 'null',
              orElse: () => '',
            );

    final loginEmail = <Object?>[profile['login_email'], profile['loginEmail']]
        .map((value) => '${value ?? ''}'.trim())
        .firstWhere(
          (value) => value.isNotEmpty && value.toLowerCase() != 'null',
          orElse: () =>
              'teacher-${activeTeacherId.toLowerCase()}@login.psm.example.com',
        );

    currentTeacher = Teacher(
      id: activeTeacherId,
      name: teacherName,
      pin: '',
      classes: effectiveAllowedClasses,
      role: isAdminSession ? 'admin' : 'teacher',
      loginEmail: loginEmail,
    );
    sessionToken = session.accessToken;
    schoolCode = schoolCodeValue.isNotEmpty
        ? schoolCodeValue.toUpperCase()
        : activeSchoolRef;
    backendUrl = '';
    api = null;
    resultBackendUrl = 'supabase';
    resultApi = SupabaseResultApiService(client: client);

    lastSelectedClass = _prefs.getString(AppConfig.prefsKeyLastClass);
    preferredEntryMode =
        _prefs.getString(AppConfig.prefsKeyEntryMode) ?? 'student';
    quickPickMode = _prefs.getBool(AppConfig.prefsKeyQuickPick) ?? true;
    lastSemester = _prefs.getString(AppConfig.prefsKeyLastSemester) ?? '1';
    lastSubject = _prefs.getString(AppConfig.prefsKeyLastSubject);
    activeModule = 'result';
    if (schoolCodeValue.isNotEmpty) {
      await _prefs.setString(
        AppConfig.prefsKeySchoolCode,
        schoolCodeValue.toUpperCase(),
      );
    }

    final schoolName =
        <Object?>[
              profile['school_name'],
              profile['schoolName'],
              profile['school_name_en'],
              profile['schoolNameEn'],
              profile['name'],
            ]
            .map((value) => '${value ?? ''}'.trim())
            .firstWhere(
              (value) => value.isNotEmpty && value.toLowerCase() != 'null',
              orElse: () => 'School Management',
            );
    final schoolDetails = <String, dynamic>{
      ...profile,
      'school_ref': activeSchoolRef,
      'schoolRef': activeSchoolRef,
      'schoolId': schoolCode,
      'schoolName': schoolName,
      'schoolNameGu':
          profile['school_name_gu'] ?? profile['schoolNameGu'] ?? '',
      'schoolNameEn':
          profile['school_name_en'] ?? profile['schoolNameEn'] ?? schoolName,
      'schoolType': profile['school_type'] ?? profile['schoolType'] ?? 'coed',
    };
    _applySchoolConfig(<String, dynamic>{
      'result': 'success',
      'school': schoolDetails,
      'classes': classConfig,
    });
    _ensureDefaultClassSelected();
    restoringSession = false;
    notifyListeners();
  }

  void _createApi() {
    final url = (backendUrl ?? '').trim();
    api = url.isEmpty
        ? null
        : ApiService(
            url,
            schoolCode: schoolCode,
            sessionToken: sessionToken,
            onAuthExpired: _handleApiAuthExpired,
          );
    resultBackendUrl = 'supabase';
    resultApi = SupabaseResultApiService();
  }

  void _setApiContext() {
    api?.setContext(schoolCode: schoolCode, sessionToken: sessionToken);
    resultApi = SupabaseResultApiService();
    resultBackendUrl = 'supabase';
  }

  /// Protected API calls can be rejected after the backend's 12-hour session
  /// expiry. Do not leave the app looking logged in with empty class/report data.
  /// Ignore late responses belonging to a previous token if the user has already
  /// signed in again in the meantime.
  void _handleApiAuthExpired(String? failedToken) {
    final failed = (failedToken ?? '').trim();
    final current = (sessionToken ?? '').trim();
    if (failed != current || _handlingAuthExpired) return;
    _handlingAuthExpired = true;
    Future.microtask(() async {
      // A fresh login may have completed while the callback was queued.
      if ((sessionToken ?? '').trim() != failed) {
        _handlingAuthExpired = false;
        return;
      }
      try {
        currentTeacher = null;
        sessionToken = null;
        schoolClasses = <SchoolClass>[];
        schoolConfigLoaded = false;
        holidays = <String, String>{};
        lastSelectedClass = null;
        await _prefs.remove(AppConfig.prefsKeySessionToken);
        await _prefs.remove(AppConfig.prefsKeySession);
        await _prefs.remove(AppConfig.prefsKeySessionJson);
        _setApiContext();
      } finally {
        _handlingAuthExpired = false;
        notifyListeners();
      }
    });
  }

  void _ensureDefaultClassSelected() {
    final allowed = allowedClasses;
    if (allowed.isEmpty) {
      lastSelectedClass = null;
      return;
    }
    if (lastSelectedClass == null ||
        !allowed.any((c) => c.key == lastSelectedClass)) {
      lastSelectedClass = allowed.first.key;
      _prefs.setString(AppConfig.prefsKeyLastClass, lastSelectedClass!);
    }
  }

  void _applySchoolConfig(Map<String, dynamic> json, {bool persist = true}) {
    schoolConfig = json;
    final rawClasses = json['classes'];
    schoolClasses = rawClasses is List
        ? rawClasses
              .whereType<Map>()
              .map((e) => SchoolClass.fromJson(e.cast<String, dynamic>()))
              .where((c) => c.key.trim().isNotEmpty)
              .toList()
        : <SchoolClass>[];
    schoolConfigLoaded = json.containsKey('classes');
    if (persist)
      _prefs.setString(AppConfig.prefsKeySchoolConfig, jsonEncode(json));
  }

  Future<void> refreshSchoolConfig() async {
    if (!isLoggedIn) return;
    try {
      await _loadSupabaseIdentity(expectedSchoolCode: schoolCode);
      _ensureDefaultClassSelected();
      notifyListeners();
    } catch (_) {
      // Keep the last known configuration visible during a temporary outage.
    }
  }

  Future<void> setBackendUrl(String url) async {
    backendUrl = url.trim().replaceFirst(RegExp(r'/+$'), '');
    await _prefs.setString(AppConfig.prefsKeyBackendUrl, backendUrl!);
    _createApi();
    _setApiContext();
    notifyListeners();
  }

  Future<void> setResultBackendUrl(String url) async {
    // Kept for older UI call sites; both modules now use the same shared API.
    await setBackendUrl(url);
  }

  Future<void> setSchoolCode(String code) async {
    final next = code.trim().toUpperCase();
    if (next == (schoolCode ?? '').trim().toUpperCase()) return;

    // Changing the tenant while an Auth session is active must not leave that
    // user attached to a different school's login screen.
    if (Supabase.instance.client.auth.currentSession != null) {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
    }
    schoolCode = next;
    sessionToken = null;
    currentTeacher = null;
    holidays = <String, String>{};
    schoolClasses = <SchoolClass>[];
    schoolConfig = <String, dynamic>{};
    schoolConfigLoaded = false;
    _availableLoginTeachers = <Teacher>[];
    await _prefs.setString(AppConfig.prefsKeySchoolCode, next);
    await _prefs.remove(AppConfig.prefsKeySessionToken);
    await _prefs.remove(AppConfig.prefsKeySession);
    await _prefs.remove(AppConfig.prefsKeySessionJson);
    _setApiContext();
    notifyListeners();
  }

  /// Loads the public pre-login teacher list from the rate-limited Edge Function.
  /// The dropdown displays names but stores each teacher's UUID as its value.
  Future<List<Teacher>> loadTeachers(String code) async {
    final next = code.trim().toUpperCase();
    if (next.isEmpty) throw ApiException('School Code દાખલ કરો.');
    await setSchoolCode(next);

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'list-school-teachers',
        body: <String, dynamic>{'schoolId': next},
      );
      final payload = response.data;
      if (payload is! Map) {
        throw ApiException(
          'શાળાની માહિતી યોગ્ય રીતે મળી નથી. ફરી પ્રયત્ન કરો.',
        );
      }
      final data = payload.cast<String, dynamic>();
      if (data['error'] != null) {
        throw ApiException(data['error'].toString());
      }
      final schoolData = data['school'];
      if (schoolData is! Map) {
        throw ApiException('આ School Code માટે શાળાની માહિતી મળી નથી.');
      }
      final school = schoolData.cast<String, dynamic>();
      final returnedSchoolCode = (school['schoolId'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      if (returnedSchoolCode != next) {
        throw ApiException('School Code ચકાસી શકાયો નથી.');
      }

      final rows = data['teachers'];
      final teachers = rows is List
          ? rows
                .whereType<Map>()
                .map((row) => Teacher.fromJson(row.cast<String, dynamic>()))
                .where(
                  (teacher) =>
                      (teacher.id ?? '').trim().isNotEmpty &&
                      (teacher.loginEmail ?? '').trim().isNotEmpty,
                )
                .toList()
          : <Teacher>[];
      if (teachers.isEmpty) {
        throw ApiException(
          'આ શાળામાં સક્રિય teacher login બનાવેલ નથી. Developer ને સંપર્ક કરો.',
        );
      }

      _availableLoginTeachers = teachers;
      final previousSchool = schoolConfig['school'];
      final previousSchoolMap = previousSchool is Map
          ? previousSchool.cast<String, dynamic>()
          : <String, dynamic>{};
      schoolConfig = <String, dynamic>{
        'result': 'success',
        'school': <String, dynamic>{
          ...previousSchoolMap,
          'schoolId': returnedSchoolCode,
          'schoolName': (school['schoolName'] ?? 'School Management')
              .toString(),
        },
        'classes': <dynamic>[],
      };
      schoolClasses = <SchoolClass>[];
      schoolConfigLoaded = false;
      notifyListeners();
      return List<Teacher>.unmodifiable(teachers);
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException(
        'Teacher list લોડ થઈ શકી નથી. Internet અને Supabase Edge Function તપાસો. (${error.runtimeType})',
      );
    }
  }

  Map<String, dynamic> _mapOf(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  /// Validates the Supabase Auth user against the active school_teachers row,
  /// then loads only the classes and school data permitted by RLS.
  Future<void> _loadSupabaseIdentity({
    String? expectedSchoolCode,
    String? expectedTeacherId,
    String? selectedLoginEmail,
  }) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    final session = client.auth.currentSession;
    if (user == null || session == null) {
      throw ApiException('Supabase session મળ્યો નથી. ફરી લૉગ ઇન કરો.');
    }

    final metadata = user.appMetadata;
    final metadataSchoolCode = (metadata['psm_school_id'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    final normalizedExpectedCode = (expectedSchoolCode ?? '')
        .trim()
        .toUpperCase();
    if (normalizedExpectedCode.isNotEmpty &&
        metadataSchoolCode.isNotEmpty &&
        metadataSchoolCode != normalizedExpectedCode) {
      throw ApiException('આ teacher બીજા School Code સાથે જોડાયેલ છે.');
    }

    final profile = await client
        .from('school_teachers')
        .select(
          'id, school_ref, auth_user_id, teacher_name, role, allowed_classes, is_active',
        )
        .eq('auth_user_id', user.id)
        .eq('is_active', true)
        .maybeSingle();
    if (profile == null) {
      throw ApiException(
        'આ login માટે સક્રિય teacher profile મળ્યું નથી. Developer ને સંપર્ક કરો.',
      );
    }

    final teacherId = (profile['id'] ?? '').toString();
    final metadataTeacherId = (metadata['psm_teacher_id'] ?? '').toString();
    if ((expectedTeacherId != null && teacherId != expectedTeacherId) ||
        (metadataTeacherId.isNotEmpty && metadataTeacherId != teacherId)) {
      throw ApiException('પસંદ કરેલો teacher અને login account મેળ ખાતા નથી.');
    }

    final schoolRef = (profile['school_ref'] ?? '').toString();
    final schoolRow = await client
        .from('schools')
        .select(
          'id, school_id, school_name, school_name_en, school_name_gu, is_active',
        )
        .eq('id', schoolRef)
        .maybeSingle();
    if (schoolRow == null || schoolRow['is_active'] != true) {
      throw ApiException('આ શાળા સક્રિય નથી અથવા મળી નથી.');
    }
    final verifiedSchoolCode = (schoolRow['school_id'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    final legacySchoolName = (schoolRow['school_name'] ?? '').toString().trim();
    if (normalizedExpectedCode.isNotEmpty &&
        verifiedSchoolCode != normalizedExpectedCode) {
      throw ApiException('School Code અને teacher account મેળ ખાતા નથી.');
    }

    final rawClasses = await client
        .from('school_classes')
        .select(
          'class_key, label, sheet_name, standard, section, report_group, sort_order',
        )
        .eq('school_ref', schoolRef)
        .eq('is_active', true)
        .order('sort_order', ascending: true);
    final classes = (rawClasses as List).whereType<Map>().map((row) {
      final item = row.cast<String, dynamic>();
      return <String, dynamic>{
        'key': (item['class_key'] ?? item['label'] ?? '').toString(),
        'label': (item['label'] ?? item['class_key'] ?? '').toString(),
        'sheetName':
            (item['sheet_name'] ?? item['label'] ?? item['class_key'] ?? '')
                .toString(),
        'standard': (item['standard'] ?? '').toString(),
        'section': (item['section'] ?? '').toString(),
        'reportGroup': (item['report_group'] ?? '').toString(),
      };
    }).toList();

    final settingsRow = await client
        .from('school_settings')
        .select('config, logo_path')
        .eq('school_ref', schoolRef)
        .maybeSingle();
    final settingsConfig = _mapOf(settingsRow?['config']);
    final oldSchoolData = _mapOf(settingsConfig['school']);
    final directEnglishName = (schoolRow['school_name_en'] ?? '')
        .toString()
        .trim();
    final configuredEnglishName =
        (oldSchoolData['schoolNameEn'] ??
                oldSchoolData['school_name_en'] ??
                settingsConfig['school_name_en'] ??
                '')
            .toString()
            .trim();
    final schoolNameEn = directEnglishName.isNotEmpty
        ? directEnglishName
        : configuredEnglishName.isNotEmpty
        ? configuredEnglishName
        : legacySchoolName;
    final schoolNameGu =
        (schoolRow['school_name_gu'] ??
                oldSchoolData['schoolNameGu'] ??
                oldSchoolData['school_name_gu'] ??
                settingsConfig['school_name_gu'] ??
                '')
            .toString()
            .trim();
    final schoolName = schoolNameEn.isNotEmpty
        ? schoolNameEn
        : schoolNameGu.isNotEmpty
        ? schoolNameGu
        : 'School Management';
    final logo = (settingsConfig['logoUrl'] ?? oldSchoolData['logoUrl'] ?? '')
        .toString();
    final mergedSchoolData = <String, dynamic>{
      ...oldSchoolData,
      'schoolRef': schoolRef,
      'school_ref': schoolRef,
      'schoolId': verifiedSchoolCode,
      'schoolName': schoolName,
      'schoolNameEn': schoolNameEn,
      'schoolNameGu': schoolNameGu,
      'school_name_en': schoolNameEn,
      'school_name_gu': schoolNameGu,
      if ((settingsConfig['schoolType'] ?? oldSchoolData['schoolType']) != null)
        'schoolType':
            (settingsConfig['schoolType'] ?? oldSchoolData['schoolType'])
                .toString(),
      if (logo.startsWith('http://') || logo.startsWith('https://'))
        'logoUrl': logo,
    };
    final mergedConfig = <String, dynamic>{
      ...settingsConfig,
      'result': 'success',
      'school': mergedSchoolData,
      'classes': classes,
    };

    final rawAllowedClasses = profile['allowed_classes'];
    final allowedClasses = rawAllowedClasses is List
        ? rawAllowedClasses.map((value) => value.toString()).toList()
        : <String>[];
    final loginEmail =
        (selectedLoginEmail ??
                'teacher-${teacherId.toLowerCase()}@login.psm.example.com')
            .trim();

    currentTeacher = Teacher(
      id: teacherId,
      name: (profile['teacher_name'] ?? '').toString(),
      pin: '',
      classes: allowedClasses,
      role: (profile['role'] ?? 'teacher').toString(),
      loginEmail: loginEmail,
    );
    sessionToken = session.accessToken;
    schoolCode = verifiedSchoolCode;
    await _prefs.setString(AppConfig.prefsKeySchoolCode, verifiedSchoolCode);
    await _prefs.remove(
      AppConfig.prefsKeySessionToken,
    ); // Supabase SDK persists its own session securely.
    await _prefs.setString(AppConfig.prefsKeySession, currentTeacher!.name);
    await _prefs.setString(
      AppConfig.prefsKeySessionJson,
      jsonEncode(currentTeacher!.toJson()),
    );
    _applySchoolConfig(mergedConfig);
    _ensureDefaultClassSelected();
  }

  Future<String?> login(String teacherId, String password) async {
    if ((schoolCode ?? '').trim().isEmpty) return 'School Code દાખલ કરો.';
    if (password.length < 4 || password.length > 15) {
      return 'Password 4 થી 15 અક્ષરનો હોવો જોઈએ.';
    }
    Teacher? selected;
    for (final teacher in _availableLoginTeachers) {
      if (teacher.id == teacherId) {
        selected = teacher;
        break;
      }
    }
    if (selected == null || (selected.loginEmail ?? '').trim().isEmpty) {
      return 'Teacher list ફરી લોડ કરીને teacher પસંદ કરો.';
    }

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: selected.loginEmail!,
        password: password,
      );
      if (response.user == null || response.session == null) {
        return 'લૉગ ઇન નિષ્ફળ. Teacher name અને password તપાસો.';
      }

      await _loadSupabaseIdentity(
        expectedSchoolCode: schoolCode,
        expectedTeacherId: selected.id,
        selectedLoginEmail: selected.loginEmail,
      );
      await _loadSupabaseHolidays();
      _ensureDefaultClassSelected();
      notifyListeners();
      return null;
    } on AuthException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('invalid') ||
          message.contains('credentials') ||
          message.contains('password')) {
        return 'ખોટો password છે. ફરી તપાસીને દાખલ કરો.';
      }
      return 'લૉગ ઇન નિષ્ફળ: ${error.message}';
    } on ApiException catch (error) {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
      currentTeacher = null;
      sessionToken = null;
      return error.message;
    } catch (error) {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
      currentTeacher = null;
      sessionToken = null;
      return 'લૉગ ઇન નિષ્ફળ: ${error.runtimeType}. Supabase table અને RLS policies તપાસો.';
    }
  }

  Future<void> logout() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    currentTeacher = null;
    sessionToken = null;
    _availableLoginTeachers = <Teacher>[];
    schoolClasses = <SchoolClass>[];
    schoolConfigLoaded = false;
    holidays = <String, String>{};
    await _prefs.remove(AppConfig.prefsKeySessionToken);
    await _prefs.remove(AppConfig.prefsKeySession);
    await _prefs.remove(AppConfig.prefsKeySessionJson);
    _setApiContext();
    notifyListeners();
  }

  Future<void> setActiveModule(String module) async {
    activeModule = module;
    await _prefs.setString(AppConfig.prefsKeyLastModule, module);
    notifyListeners();
  }

  Future<void> setLastSelectedClass(String classKey) async {
    lastSelectedClass = classKey;
    await _prefs.setString(AppConfig.prefsKeyLastClass, classKey);
    notifyListeners();
  }

  Future<void> setPreferredEntryMode(String mode) async {
    preferredEntryMode = mode;
    await _prefs.setString(AppConfig.prefsKeyEntryMode, mode);
    notifyListeners();
  }

  Future<void> setQuickPickMode(bool enabled) async {
    quickPickMode = enabled;
    await _prefs.setBool(AppConfig.prefsKeyQuickPick, enabled);
    notifyListeners();
  }

  Future<void> setLastSemester(String sem) async {
    lastSemester = sem;
    await _prefs.setString(AppConfig.prefsKeyLastSemester, sem);
    notifyListeners();
  }

  Future<void> setLastSubject(String subject) async {
    lastSubject = subject;
    await _prefs.setString(AppConfig.prefsKeyLastSubject, subject);
    notifyListeners();
  }

  Future<void> refreshHolidays() async {
    if (!isLoggedIn) return;
    try {
      await _loadSupabaseHolidays();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadSupabaseHolidays() async {
    if (!isLoggedIn) return;
    final rows = await Supabase.instance.client
        .from('school_holidays')
        .select('holiday_date, reason')
        .order('holiday_date', ascending: true);
    final next = <String, String>{};
    for (final value in rows as List) {
      if (value is! Map) continue;
      final row = value.cast<String, dynamic>();
      final date = (row['holiday_date'] ?? '').toString();
      if (date.isNotEmpty)
        next[date.length >= 10 ? date.substring(0, 10) : date] =
            (row['reason'] ?? '').toString();
    }
    holidays = next;
  }

  bool isMessageRead(String teacherName, String date) =>
      _prefs.getBool('msg_read_${teacherName}_$date') ?? false;
  Future<void> markMessageRead(String teacherName, String date) async =>
      _prefs.setBool('msg_read_${teacherName}_$date', true);
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:pmshri_attendance/services/firebase_backend_client.dart';
import 'school_type.dart';

/// Loads the signed-in school's directory and feeds the Timetable Studio,
/// Exam Planning, and File Share screens. All reads are tenant-scoped;
/// every save persists to `school_settings.config`.
class SupabaseSchoolPlanningService {
  SupabaseSchoolPlanningService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  // Cache the synthesized planning payload briefly for smoother tab navigation.
  // The school reference returned by current_school_ref remains the tenant key.
  static final Map<String, Map<String, dynamic>> _sessionPlanningCache =
      <String, Map<String, dynamic>>{};
  static final Map<String, DateTime> _sessionPlanningCacheAt =
      <String, DateTime>{};
  static const Duration _planningCacheTtl = Duration(seconds: 45);

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value.whereType<Map>().map(_map).toList();
  }

  List<Map<String, dynamic>> _sortSubjects(List<Map<String, dynamic>> rows) {
    rows.sort((a, b) {
      final aOrder = int.tryParse(_text(a['sort_order'])) ?? 2147483647;
      final bOrder = int.tryParse(_text(b['sort_order'])) ?? 2147483647;
      final orderCompare = aOrder.compareTo(bOrder);
      if (orderCompare != 0) return orderCompare;
      return _text(a['subject_name'])
          .toLowerCase()
          .compareTo(_text(b['subject_name']).toLowerCase());
    });
    return rows;
  }

  List<Map<String, dynamic>> _withRequiredSubjects(
    List<Map<String, dynamic>> rows, {
    Set<String> knownNames = const <String>{},
  }) {
    final result = rows.map(_map).toList();
    final names = <String>{
      ...knownNames.map((name) => name.toLowerCase()),
      ...result
          .map((row) => _text(row['subject_name']).toLowerCase())
          .where((name) => name.isNotEmpty),
    };
    const required = <(String, int)>[('FLN', 15), ('શા. શિ.', 16)];
    for (final item in required) {
      if (names.contains(item.$1.toLowerCase())) continue;
      result.add(<String, dynamic>{
        'subject_name': item.$1,
        'sort_order': item.$2,
        'is_active': true,
      });
    }
    return _sortSubjects(result);
  }

  String _text(dynamic value, [String fallback = '']) {
    final valueText = (value ?? '').toString().trim();
    if (valueText.isEmpty || valueText.toLowerCase() == 'null') {
      return fallback;
    }
    return valueText;
  }

  String _first(Iterable<dynamic> values, [String fallback = '']) {
    for (final value in values) {
      final candidate = _text(value);
      if (candidate.isNotEmpty) return candidate;
    }
    return fallback;
  }

  String _englishDigits(String value) {
    const gujarati = '૦૧૨૩૪૫૬૭૮૯';
    var result = value;
    for (var i = 0; i < gujarati.length; i++) {
      result = result.replaceAll(gujarati[i], '$i');
    }
    return result;
  }

  String _detectSchoolType({
    required Iterable<dynamic> typeCandidates,
    required Iterable<dynamic> nameCandidates,
    required Map<String, Map<String, int>> studentCounts,
  }) {
    // 1. The registered school_type (boys / girls / mixed) always wins.
    for (final raw in typeCandidates) {
      final value = _text(raw);
      if (value.isEmpty || value.toLowerCase() == 'null') continue;
      return SchoolType.canonical(value);
    }

    // 2. Old schools without a type: infer from the school name.
    final byName = nameCandidates.map(_text).join(' ').toLowerCase();
    if (byName.contains('kumar') || byName.contains('કુમાર') || byName.contains('boys')) {
      return 'boys';
    }
    if (byName.contains('kanya') || byName.contains('કન્યા') || byName.contains('girls')) {
      return 'girls';
    }

    // 4. Fallback to student gender counts if available
    int totalBoys = 0;
    int totalGirls = 0;
    for (final c in studentCounts.values) {
      totalBoys += c['boys'] ?? 0;
      totalGirls += c['girls'] ?? 0;
    }
    if (totalBoys > 0 && totalGirls == 0) return 'boys';
    if (totalGirls > 0 && totalBoys == 0) return 'girls';

    return 'mixed';
  }

  String _standardFor(Map<String, dynamic> row) {
    var standard = _first([
      row['standard'],
      row['grade'],
      row['class_standard'],
    ]);
    if (standard.isEmpty) {
      final key = _first([row['label'], row['class_key']]);
      final normalized = _englishDigits(key);
      final match = RegExp(
        r'(BALVATIKA|BAL|બાલવાટિકા|[1-8])',
        caseSensitive: false,
      ).firstMatch(normalized);
      standard = match?.group(0) ?? '';
    }
    final normalized = _englishDigits(standard).trim();
    if (normalized.toUpperCase().contains('BAL') ||
        normalized.contains('બાલ')) {
      return 'BALVATIKA';
    }
    final number = RegExp(r'[1-8]').firstMatch(normalized)?.group(0);
    return number ?? standard;
  }

  String _sectionFor(Map<String, dynamic> row) {
    final section = _first([row['section']]);
    if (section.isNotEmpty) return section.toUpperCase();
    final key = _first([row['label'], row['class_key']]);
    final match = RegExp(r'[_-\s]([A-Za-zઅ-હ])$').firstMatch(key);
    return (match?.group(1) ?? 'A').toUpperCase();
  }

  String _legacyTimetableClassName(Map<String, dynamic> row) {
    final std = _standardFor(row);
    final sec = _sectionFor(row);
    if (std.isNotEmpty) {
      return '$std-${sec.isEmpty ? 'A' : sec}';
    }
    final rawKey = _first([row['class_key'], row['label']]);
    return rawKey.isEmpty ? '6-A' : rawKey;
  }

  String _initials(String fullName, String teacherId, Set<String> used) {
    final cleaned = fullName.replaceAll(RegExp(r'\([^)]*\)'), ' ').trim();
    final words = cleaned
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .toList();
    String takeFirst(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return '';
      return String.fromCharCode(trimmed.runes.first).toUpperCase();
    }

    var initials = '';
    if (words.length >= 2) {
      initials = '${takeFirst(words.first)}${takeFirst(words.last)}';
    } else if (words.isNotEmpty) {
      final runes = words.first.runes.toList();
      initials = String.fromCharCodes(runes.take(2)).toUpperCase();
    }
    if (initials.trim().isEmpty) {
      final safeId = teacherId.replaceAll('-', '');
      initials = safeId.isEmpty
          ? 'T'
          : safeId.substring(0, safeId.length >= 2 ? 2 : 1).toUpperCase();
    }

    final base = initials;
    var suffix = 2;
    while (used.contains(initials)) {
      initials = '$base$suffix';
      suffix++;
    }
    used.add(initials);
    return initials;
  }

  bool _isBoy(dynamic raw) {
    final value = _text(raw).toLowerCase();
    return const {
      'boys',
      'boy',
      'male',
      'm',
      'કુમાર',
      'છોકરો',
      'છોકરા',
    }.contains(value);
  }

  bool _isGirl(dynamic raw) {
    final value = _text(raw).toLowerCase();
    return const {
      'girls',
      'girl',
      'female',
      'f',
      'કન્યા',
      'છોકરી',
      'છોકરીઓ',
    }.contains(value);
  }

  Future<String> _currentSchoolRef() async {
    if (_client.auth.currentUser == null) {
      throw StateError('Please sign in again.');
    }
    final result = await _client.rpc('current_school_ref');
    final ref = _text(result);
    if (ref.isEmpty) {
      throw StateError('No active school is linked to this login.');
    }
    return ref;
  }

  Future<Map<String, dynamic>> _loadSchoolRow(String schoolRef) async {
    try {
      final row = await _client
          .from('schools')
          .select()
          .eq('id', schoolRef)
          .maybeSingle();
      return _map(row);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<Map<String, dynamic>> _loadSchoolContext() async {
    try {
      final value = await _client.rpc('psm_library_school_context');
      if (value is List && value.isNotEmpty) return _map(value.first);
      return _map(value);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<Map<String, dynamic>> _loadHajariSchoolMeta() async {
    try {
      final value = await _client.rpc('hajari_patrak_school_meta');
      if (value is List && value.isNotEmpty) return _map(value.first);
      return _map(value);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<Map<String, dynamic>> _loadFrontPageResultMeta(
    String schoolRef,
  ) async {
    try {
      final rows = await _client
          .from('class_result_settings')
          .select(
            'front_page_district,front_page_education_authority,front_page_village,front_page_taluka,front_page_pay_center,front_page_crc',
          )
          .eq('school_ref', schoolRef);
      for (final row in _rows(rows)) {
        if (_first([
          row['front_page_district'],
          row['front_page_taluka'],
          row['front_page_village'],
          row['front_page_pay_center'],
          row['front_page_crc'],
        ]).isNotEmpty) {
          return row;
        }
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _loadSettingsRow(String schoolRef) async {
    try {
      final row = await _client
          .from('school_settings')
          .select('config,logo_path,logo_data_uri')
          .eq('school_ref', schoolRef)
          .maybeSingle();
      return _map(row);
    } catch (_) {
      try {
        final row = await _client
            .from('school_settings')
            .select('config')
            .eq('school_ref', schoolRef)
            .maybeSingle();
        return _map(row);
      } catch (_) {
        return <String, dynamic>{};
      }
    }
  }

  Future<(Uint8List?, String)> _resolveSchoolLogo(
    Map<String, dynamic> settingsRow,
  ) async {
    final dataUri = _text(settingsRow['logo_data_uri']);
    if (dataUri.startsWith('data:')) {
      final comma = dataUri.indexOf(',');
      if (comma >= 0) {
        try {
          return (base64Decode(dataUri.substring(comma + 1)), dataUri);
        } catch (_) {}
      }
    }
    final logoPath = _text(settingsRow['logo_path']);
    if (logoPath.isNotEmpty) {
      try {
        final bytes = await _client.storage
            .from('school-assets')
            .download(logoPath);
        if (bytes.isNotEmpty) {
          final ext = logoPath.split('.').last.toLowerCase();
          final mime = (ext == 'jpg' || ext == 'jpeg')
              ? 'image/jpeg'
              : 'image/png';
          final uri = 'data:$mime;base64,${base64Encode(bytes)}';
          return (bytes, uri);
        }
      } catch (_) {}
    }
    return (null, '');
  }

  Future<List<Map<String, dynamic>>> _loadClasses(String schoolRef) async {
    try {
      final result = await _client
          .from('school_classes')
          .select(
            'id,school_ref,class_key,label,standard,section,report_group,sort_order,is_active,class_teacher_id',
          )
          .eq('school_ref', schoolRef)
          .eq('is_active', true)
          .order('sort_order')
          .order('label');
      return _rows(result);
    } catch (_) {
      final result = await _client
          .from('school_classes')
          .select(
            'id,school_ref,class_key,label,standard,section,report_group,sort_order,is_active',
          )
          .eq('school_ref', schoolRef)
          .eq('is_active', true)
          .order('sort_order')
          .order('label');
      return _rows(result);
    }
  }

  Future<String> _loadRegisteredAdminName(String schoolRef) async {
    try {
      final result = await _client
          .from('school_teachers')
          .select('teacher_name,role,is_active')
          .eq('school_ref', schoolRef);
      for (final row in _rows(result)) {
        if (_text(row['role']).toLowerCase() == 'admin') {
          final name = _text(row['teacher_name']);
          if (name.isNotEmpty) return name;
        }
      }
    } catch (_) {}
    return '';
  }

  Future<List<Map<String, dynamic>>> _loadTeachers(String schoolRef) async {
    try {
      final result = await _client
          .from('school_teachers')
          .select('id,school_ref,teacher_name,role,allowed_classes,is_active')
          .eq('school_ref', schoolRef)
          .eq('is_active', true)
          .order('teacher_name');
      final allActive = _rows(result);
      final teachersOnly = allActive
          .where((r) => _text(r['role']).toLowerCase() == 'teacher')
          .toList();
      final admins = allActive
          .where((r) => _text(r['role']).toLowerCase() == 'admin')
          .toList();
      if (teachersOnly.isNotEmpty) {
        return teachersOnly;
      }
      return <Map<String, dynamic>>[...teachersOnly, ...admins];
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _loadSubjects(String schoolRef) async {
    // Admins backfill the two new core subjects into existing school masters.
    // The Firebase RPC is tenant-scoped and no-ops for teacher sessions.
    try {
      await _client.rpc('ensure_school_planning_core_subjects');
    } catch (_) {}
    try {
      final result = await _client
          .from('school_subject_master')
          .select('subject_name,sort_order,is_active')
          .eq('school_ref', schoolRef)
          .order('sort_order')
          .order('subject_name');
      final allRows = _rows(result);
      final knownNames = allRows
          .map((row) => _text(row['subject_name']).toLowerCase())
          .where((name) => name.isNotEmpty)
          .toSet();
      final activeRows = allRows
          .where((row) => row['is_active'] != false)
          .toList();
      final sorted = _withRequiredSubjects(activeRows, knownNames: knownNames);
      if (sorted.isNotEmpty) return sorted;
    } catch (_) {}
    try {
      final result = await _client
          .from('school_subject_catalog')
          .select('standard,subject_name,sort_order,is_active')
          .eq('school_ref', schoolRef)
          .order('sort_order')
          .order('subject_name');
      final allRows = _rows(result);
      final knownNames = allRows
          .map((row) => _text(row['subject_name']).toLowerCase())
          .where((name) => name.isNotEmpty)
          .toSet();
      final activeRows = allRows
          .where((row) => row['is_active'] != false)
          .toList();
      final sorted = _withRequiredSubjects(activeRows, knownNames: knownNames);
      if (sorted.isNotEmpty) return sorted;
    } catch (_) {}
    try {
      final result = await _client
          .from('class_subjects')
          .select('subject_name,sort_order,is_active')
          .eq('school_ref', schoolRef)
          .order('sort_order')
          .order('subject_name');
      final allRows = _rows(result);
      final knownNames = allRows
          .map((row) => _text(row['subject_name']).toLowerCase())
          .where((name) => name.isNotEmpty)
          .toSet();
      final activeRows = allRows
          .where((row) => row['is_active'] != false)
          .toList();
      return _withRequiredSubjects(activeRows, knownNames: knownNames);
    } catch (_) {
      return _withRequiredSubjects(<Map<String, dynamic>>[]);
    }
  }

  Future<List<Map<String, dynamic>>> _loadTeacherSubjectAssignments(
    String schoolRef,
  ) async {
    try {
      final result = await _client
          .from('teacher_subject_assignments')
          .select('teacher_id,class_id,subject_name,max_periods')
          .eq('school_ref', schoolRef)
          .order('subject_name');
      return _rows(result);
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, List<String>>> _loadClassSubjectsMap(
    String schoolRef,
  ) async {
    final byClassId = <String, List<String>>{};
    try {
      final result = await _client
          .from('class_subjects')
          .select('class_id,subject_name,sort_order,is_active')
          .eq('school_ref', schoolRef)
          .order('sort_order')
          .order('subject_name');
      for (final row in _rows(result)) {
        if (row['is_active'] == false) continue;
        final cid = _text(row['class_id']);
        final sub = _text(row['subject_name']);
        if (cid.isEmpty || sub.isEmpty) continue;
        final list = byClassId.putIfAbsent(cid, () => <String>[]);
        if (!list.contains(sub)) list.add(sub);
      }
    } catch (_) {}
    return byClassId;
  }

  Future<Map<String, Map<String, int>>> _loadStudentCounts(
    String schoolRef,
  ) async {
    final counts = <String, Map<String, int>>{};
    try {
      final result = await _client
          .from('students')
          .select('class_id,gender,is_active')
          .eq('school_ref', schoolRef)
          .eq('is_active', true);
      for (final row in _rows(result)) {
        final classId = _text(row['class_id']);
        if (classId.isEmpty) continue;
        final current = counts.putIfAbsent(
          classId,
          () => <String, int>{'boys': 0, 'girls': 0, 'total': 0},
        );
        current['total'] = (current['total'] ?? 0) + 1;
        if (_isBoy(row['gender'])) {
          current['boys'] = (current['boys'] ?? 0) + 1;
        } else if (_isGirl(row['gender'])) {
          current['girls'] = (current['girls'] ?? 0) + 1;
        }
      }
    } catch (_) {}
    return counts;
  }

  List<String> _coreSubjectsForStandard(
    int? stdNumber,
    List<String> masterSubjects,
  ) {
    List<String> preferred;
    if (stdNumber != null && stdNumber <= 2) {
      preferred = <String>[
        'ગુજરાતી',
        'ગણિત',
        'અંગ્રેજી',
        'હિન્દી',
        'FLN',
        'શા. શિ.',
        'ચિત્ર',
        'સંગીત',
        'રમત',
      ];
    } else if (stdNumber != null && stdNumber <= 5) {
      preferred = <String>[
        'ગુજરાતી',
        'ગણિત',
        'પર્યાવરણ',
        'અંગ્રેજી',
        'હિન્દી',
        'FLN',
        'શા. શિ.',
        'ચિત્ર',
        'કોમ્પ્યુટર',
      ];
    } else {
      preferred = <String>[
        'ગુજરાતી',
        'ગણિત',
        'વિજ્ઞાન',
        'સામાજિક વિજ્ઞાન',
        'અંગ્રેજી',
        'હિન્દી',
        'સંસ્કૃત',
        'FLN',
        'શા. શિ.',
        'ચિત્ર',
      ];
    }

    final matched = <String>[];
    for (final p in preferred) {
      final found = masterSubjects.firstWhere(
        (s) => s == p || s.contains(p) || p.contains(s),
        orElse: () => p,
      );
      if (!matched.contains(found)) matched.add(found);
    }
    return matched;
  }

  List<int> _distributeWeeklyPeriods(int totalPeriods, int subjectCount) {
    if (subjectCount <= 0) return const <int>[];
    final base = totalPeriods ~/ subjectCount;
    var rem = totalPeriods % subjectCount;
    return List<int>.generate(subjectCount, (index) {
      final extra = rem > 0 ? 1 : 0;
      if (rem > 0) rem--;
      return (base + extra).clamp(1, 14);
    });
  }

  /// Loads and synthesizes complete, ready-to-use data for Timetable Studio,
  /// Exam Planning, and File Share.
  Future<Map<String, dynamic>> loadPlanningData({
    required Map<String, dynamic> profile,
    bool forceRefresh = false,
  }) async {
    final schoolRef = await _currentSchoolRef().timeout(
      const Duration(seconds: 8),
    );
    // Rely on FirestoreQueryBuilder's table-level invalidated cache so teacher,
    // subject, class-teacher, and logo updates in Admin Setup reflect immediately.
    if (forceRefresh) {
      _sessionPlanningCache.remove(schoolRef);
      _sessionPlanningCacheAt.remove(schoolRef);
    }
    final results = await Future.wait<dynamic>([
      _loadSettingsRow(schoolRef),
      _loadSchoolContext(),
      _loadClasses(schoolRef),
      _loadTeachers(schoolRef),
      _loadSubjects(schoolRef),
      _loadTeacherSubjectAssignments(schoolRef),
      _loadStudentCounts(schoolRef),
      _loadHajariSchoolMeta(),
      _loadFrontPageResultMeta(schoolRef),
      _loadSchoolRow(schoolRef),
      _loadClassSubjectsMap(schoolRef),
      _loadRegisteredAdminName(schoolRef),
    ]);

    final settingsRow = _map(results[0]);
    final config = _map(settingsRow['config']);
    final schoolContext = _map(results[1]);
    final rawClasses = _rows(results[2]);
    final rawTeachers = _rows(results[3]);
    final rawSubjectRows = _rows(results[4]);
    final assignmentRows = _rows(results[5]);
    final studentCounts = results[6] as Map<String, Map<String, int>>;
    final hajariMeta = _map(results[7]);
    final frontPageMeta = _map(results[8]);
    final schoolRow = _map(results[9]);
    final classSubjectsByClassId = results[10] as Map<String, List<String>>;
    final registeredAdminName = _text(results[11]);

    final (schoolLogoBytes, schoolLogoDataUri) = await _resolveSchoolLogo(
      settingsRow,
    );

    final schoolNameGu = _first([
      schoolRow['school_name_gu'],
      schoolContext['school_name_gu'],
      profile['school_name_gu'],
      config['school_name_gu'],
      hajariMeta['school_name_gu'],
    ]);
    final schoolNameEn = _first([
      schoolRow['school_name_en'],
      schoolContext['school_name_en'],
      profile['school_name_en'],
      schoolRow['school_name'],
      schoolContext['school_name'],
      hajariMeta['school_name'],
      profile['school_name'],
      profile['schoolName'],
    ]);
    final schoolName = _first([
      schoolNameGu,
      schoolNameEn,
      config['school_name'],
      config['schoolName'],
    ]);

    final schoolType = _detectSchoolType(
      typeCandidates: [
        schoolRow['school_type'],
        schoolContext['school_type'],
        profile['school_type'],
        hajariMeta['school_type'],
      ],
      nameCandidates: [
        schoolName,
        schoolRow['school_name_en'],
        schoolRow['school_name_gu'],
        schoolContext['school_name_en'],
        schoolContext['school_name_gu'],
        profile['school_name_en'],
        profile['school_name_gu'],
      ],
      studentCounts: studentCounts,
    );

    final subjects = <String>[];
    for (final row in rawSubjectRows) {
      final name = _text(row['subject_name']);
      if (name.isNotEmpty && !subjects.contains(name)) subjects.add(name);
    }
    for (final row in assignmentRows) {
      final name = _text(row['subject_name']);
      if (name.isNotEmpty && !subjects.contains(name)) subjects.add(name);
    }
    if (subjects.isEmpty) {
      subjects.addAll(const <String>[
        'ગુજરાતી',
        'ગણિત',
        'પર્યાવરણ',
        'વિજ્ઞાન',
        'સામાજિક વિજ્ઞાન',
        'અંગ્રેજી',
        'હિન્દી',
        'સંસ્કૃત',
        'ચિત્ર',
        'કોમ્પ્યુટર',
        'રમત',
        'FLN',
        'શા. શિ.',
      ]);
    }

    final classes = <Map<String, dynamic>>[];
    final classesById = <String, Map<String, dynamic>>{};
    final classAliasesToLabel = <String, String>{};

    for (final row in rawClasses) {
      final id = _text(row['id']);
      final key = _text(row['class_key']);
      if (id.isEmpty && key.isEmpty) continue;
      final standard = _standardFor(row);
      final section = _sectionFor(row);
      // Always use the entered Display Name (label) as the primary class name!
      final displayLabel = _first([row['label'], row['class_key']]);
      final legacyTtName = _legacyTimetableClassName(row);
      final count =
          studentCounts[id] ?? <String, int>{'boys': 0, 'girls': 0, 'total': 0};
      final rawTotal = count['total'] ?? 0;
      final rawBoys = count['boys'] ?? 0;
      final rawGirls = count['girls'] ?? 0;

      int boysCount = rawBoys;
      int girlsCount = rawGirls;
      if (schoolType == 'boys') {
        boysCount = rawTotal > 0 ? rawTotal : rawBoys;
        girlsCount = 0;
      } else if (schoolType == 'girls') {
        girlsCount = rawTotal > 0 ? rawTotal : rawGirls;
        boysCount = 0;
      } else if (rawTotal > 0 && rawBoys == 0 && rawGirls == 0) {
        boysCount = (rawTotal + 1) ~/ 2;
        girlsCount = rawTotal - boysCount;
      }
      final totalCount = schoolType == 'boys'
          ? boysCount
          : schoolType == 'girls'
          ? girlsCount
          : (boysCount + girlsCount > 0 ? boysCount + girlsCount : rawTotal);

      final entry = <String, dynamic>{
        'id': id,
        'classKey': key,
        'label': displayLabel,
        'className': displayLabel,
        'timetableClassName': displayLabel,
        'legacyTimetableClassName': legacyTtName,
        'standard': standard,
        'section': section,
        'reportGroup': _text(row['report_group']),
        'classTeacherId': _text(row['class_teacher_id']),
        'boys': boysCount,
        'girls': girlsCount,
        'total': totalCount,
      };
      classes.add(entry);
      if (id.isNotEmpty) {
        classesById[id] = entry;
        classAliasesToLabel[id] = displayLabel;
      }
      if (key.isNotEmpty) {
        classAliasesToLabel[key] = displayLabel;
        classAliasesToLabel[key.toUpperCase()] = displayLabel;
      }
      if (legacyTtName.isNotEmpty) {
        classAliasesToLabel[legacyTtName] = displayLabel;
        classAliasesToLabel[legacyTtName.toUpperCase()] = displayLabel;
      }
      if (displayLabel.isNotEmpty) {
        classAliasesToLabel[displayLabel] = displayLabel;
      }
    }

    final savedTtMap = _map(config['planning_timetable_studio']);
    final savedInitialsById = <String, String>{
      for (final e in _map(config['teacher_initials']).entries)
        e.key.trim(): _text(e.value).toUpperCase(),
      for (final e in _map(savedTtMap['teacherInitialsById']).entries)
        e.key.trim(): _text(e.value).toUpperCase(),
    };
    final savedInitialsByName = <String, String>{
      for (final e in _map(savedTtMap['teacherInitialsByName']).entries)
        e.key.trim().toLowerCase(): _text(e.value).toUpperCase(),
    };
    final savedTtTeachers = _rows(savedTtMap['teachers']);
    for (final st in savedTtTeachers) {
      final tid = _text(st['teacherId']);
      final tName = _text(st['f']);
      final tInit = _text(st['i']).toUpperCase();
      if (tInit.isNotEmpty) {
        if (tid.isNotEmpty) savedInitialsById[tid] = tInit;
        if (tName.isNotEmpty) savedInitialsByName[tName.toLowerCase()] = tInit;
      }
    }

    final usedInitials = <String>{};
    final teachers = <Map<String, dynamic>>[];
    final teachersById = <String, Map<String, dynamic>>{};
    for (final row in rawTeachers) {
      final id = _text(row['id']);
      final fullName = _text(row['teacher_name']);
      if (id.isEmpty || fullName.isEmpty) continue;
      final customInit = _first([
        savedInitialsById[id],
        savedInitialsByName[fullName.toLowerCase()],
        row['initial'],
        row['short_name'],
      ]).toUpperCase();
      String initial;
      if (customInit.isNotEmpty && !usedInitials.contains(customInit)) {
        initial = customInit;
        usedInitials.add(initial);
      } else {
        initial = _initials(fullName, id, usedInitials);
      }
      final rawAllowed = row['allowed_classes'];
      final allowed = rawAllowed is List
          ? rawAllowed
                .map((value) => _text(value))
                .where((value) => value.isNotEmpty)
                .toList()
          : <String>[];
      final teacher = <String, dynamic>{
        'id': id,
        'fullName': fullName,
        'name': fullName,
        'initial': initial,
        'role': _text(row['role'], 'teacher'),
        'allowedClasses': allowed,
        'subjects': <String>[],
        'group': 'a',
      };
      teachers.add(teacher);
      teachersById[id] = teacher;
    }

    // First, collect all explicit taught subjects per teacher directly from teacher_subject_assignments!
    final explicitSubjectsByTeacher = <String, Set<String>>{};
    final explicitClassIdsByTeacher = <String, Set<String>>{};
    for (final row in assignmentRows) {
      final teacherId = _text(row['teacher_id']);
      final classId = _text(row['class_id']);
      final subject = _text(row['subject_name']);
      if (teacherId.isEmpty || subject.isEmpty) continue;
      if (teachersById.containsKey(teacherId)) {
        explicitSubjectsByTeacher
            .putIfAbsent(teacherId, () => <String>{})
            .add(subject);
        if (classId.isNotEmpty) {
          explicitClassIdsByTeacher
              .putIfAbsent(teacherId, () => <String>{})
              .add(classId);
        }
      }
    }

    final assignmentData = <Map<String, dynamic>>[];
    final fallbackSubjectsByTeacher = <String, Set<String>>{};

    final activeAssignmentRows = assignmentRows.where((row) {
      final teacherId = _text(row['teacher_id']);
      final classId = _text(row['class_id']);
      final subject = _text(row['subject_name']);
      return teachersById.containsKey(teacherId) &&
          classesById.containsKey(classId) &&
          subject.isNotEmpty;
    }).toList();

    final existingByClassId = <String, List<Map<String, dynamic>>>{};
    for (final row in activeAssignmentRows) {
      final classId = _text(row['class_id']);
      (existingByClassId[classId] ??= <Map<String, dynamic>>[]).add(row);
    }

    const weeklySlots = 46;
    final usedClassTeacherIds = <String>{};

    // Process each class: use explicit DB assignments if present, or synthesize smart defaults using Display Name (label)!
    for (var cIdx = 0; cIdx < classes.length; cIdx++) {
      final klass = classes[cIdx];
      final classId = _text(klass['id']);
      final classKey = _text(klass['classKey']);
      final classDisplayLabel = _text(klass['label'], classKey);
      final stdStr = _text(klass['standard']);
      final stdNum = int.tryParse(_englishDigits(stdStr));
      final explicitRows =
          existingByClassId[classId] ?? <Map<String, dynamic>>[];

      String designatedCtId = _text(klass['classTeacherId']);
      if (designatedCtId.isEmpty || !teachersById.containsKey(designatedCtId)) {
        final eligible = teachers.where((t) {
          final tid = _text(t['id']);
          final allowed = (t['allowedClasses'] as List?) ?? const [];
          return !usedClassTeacherIds.contains(tid) &&
              (allowed.isEmpty ||
                  allowed.contains(classKey) ||
                  allowed.contains(classId) ||
                  allowed.contains(classDisplayLabel));
        }).toList();
        if (eligible.isNotEmpty) {
          designatedCtId = _text(eligible.first['id']);
        } else if (teachers.isNotEmpty) {
          designatedCtId = _text(teachers[cIdx % teachers.length]['id']);
        }
      }
      if (designatedCtId.isNotEmpty) {
        usedClassTeacherIds.add(designatedCtId);
      }

      if (explicitRows.isNotEmpty) {
        final rawDist = _distributeWeeklyPeriods(weeklySlots, explicitRows.length);
        // Apply per-subject max_periods caps set during Teacher Account Creation!
        final explicitCaps = <int?>[
          for (final r in explicitRows)
            int.tryParse(_text(r['max_periods'])),
        ];
        final dist = List<int>.from(rawDist);
        int reservedByCapped = 0;
        final uncappedIndices = <int>[];
        for (var i = 0; i < explicitRows.length; i++) {
          final cap = explicitCaps[i];
          if (cap != null && cap > 0) {
            dist[i] = cap.clamp(1, 48);
            reservedByCapped += dist[i];
          } else {
            uncappedIndices.add(i);
          }
        }
        if (uncappedIndices.isNotEmpty && reservedByCapped > 0) {
          final remainingSlots = (weeklySlots - reservedByCapped).clamp(
            uncappedIndices.length,
            weeklySlots,
          );
          final subDist = _distributeWeeklyPeriods(
            remainingSlots,
            uncappedIndices.length,
          );
          for (var j = 0; j < uncappedIndices.length; j++) {
            dist[uncappedIndices[j]] = subDist[j];
          }
        }

        bool ctAssignedInClass = false;
        for (var i = 0; i < explicitRows.length; i++) {
          final row = explicitRows[i];
          final teacherId = _text(row['teacher_id']);
          final subject = _text(row['subject_name']);
          final cap = explicitCaps[i];
          final teacher = teachersById[teacherId]!;
          if (!subjects.contains(subject)) subjects.add(subject);

          final isCt =
              !ctAssignedInClass &&
              (teacherId == designatedCtId || i == explicitRows.length - 1);
          if (isCt) ctAssignedInClass = true;

          final id = '${teacherId}_${classId}_${Uri.encodeComponent(subject)}';
          assignmentData.add(<String, dynamic>{
            'id': id,
            'teacherId': teacherId,
            'teacherInitial': _text(teacher['initial']),
            'teacherFullName': _text(teacher['fullName']),
            'subject': subject,
            'classId': classId,
            'className': classDisplayLabel,
            'classKey': classKey,
            'classLabel': classDisplayLabel,
            'standard': stdStr,
            'section': _text(klass['section']),
            'isClassTeacher': isCt,
            'requiredPeriods': dist[i],
            if (cap != null && cap > 0) 'maxPeriods': cap,
            'isDoublePeriod': i < 2 && dist[i] >= 6,
            'roomOrLab': null,
          });
        }
      } else if (teachers.isNotEmpty) {
        final dbClassSubs = classSubjectsByClassId[classId] ?? const <String>[];
        final classSubjects = dbClassSubs.isNotEmpty
            ? List<String>.from(dbClassSubs)
            : _coreSubjectsForStandard(stdNum, subjects);
        final dist = _distributeWeeklyPeriods(
          weeklySlots,
          classSubjects.length,
        );
        // Find teachers allowed for this class
        final classAllowedTeachers = teachers.where((t) {
          final allowed = (t['allowedClasses'] as List?) ?? const [];
          return allowed.contains(classKey) ||
              allowed.contains(classId) ||
              allowed.contains(classDisplayLabel);
        }).toList();
        final pool = classAllowedTeachers.isNotEmpty
            ? classAllowedTeachers
            : teachers;

        for (var sIdx = 0; sIdx < classSubjects.length; sIdx++) {
          final subject = classSubjects[sIdx];
          Map<String, dynamic> chosenTeacher;
          if (sIdx == 0 &&
              designatedCtId.isNotEmpty &&
              teachersById.containsKey(designatedCtId)) {
            chosenTeacher = teachersById[designatedCtId]!;
          } else {
            // Prefer a teacher in pool who already teaches this subject in DB
            final subjectTeacher = pool.where((t) {
              final tid = _text(t['id']);
              return (explicitSubjectsByTeacher[tid] ?? const <String>{})
                  .contains(subject);
            }).firstOrNull;
            chosenTeacher = subjectTeacher ?? pool[(cIdx + sIdx) % pool.length];
          }
          final teacherId = _text(chosenTeacher['id']);
          fallbackSubjectsByTeacher
              .putIfAbsent(teacherId, () => <String>{})
              .add(subject);
          final isCt = sIdx == 0;
          final id = 'auto_${classId}_${sIdx}_${Uri.encodeComponent(subject)}';
          assignmentData.add(<String, dynamic>{
            'id': id,
            'teacherId': teacherId,
            'teacherInitial': _text(chosenTeacher['initial']),
            'teacherFullName': _text(chosenTeacher['fullName']),
            'subject': subject,
            'classId': classId,
            'className': classDisplayLabel,
            'classKey': classKey,
            'classLabel': classDisplayLabel,
            'standard': stdStr,
            'section': _text(klass['section']),
            'isClassTeacher': isCt,
            'requiredPeriods': dist[sIdx],
            'isDoublePeriod': sIdx < 2 && dist[sIdx] >= 6,
            'roomOrLab': null,
          });
        }
      }
    }

    // Populate each teacher's taught classes, class-teacher status, taught subjects & group from DB
    for (var tIdx = 0; tIdx < teachers.length; tIdx++) {
      final teacher = teachers[tIdx];
      final id = _text(teacher['id']);
      final assignedClassLabels = <String>[];
      final assignedClassIds = <String>[];
      final classTeacherOf = <String>[];

      void addClassByEntry(Map<String, dynamic> cls, {bool isCt = false}) {
        final cid = _text(cls['id']);
        final lbl = _text(cls['label'], _text(cls['classKey']));
        if (cid.isNotEmpty && !assignedClassIds.contains(cid)) {
          assignedClassIds.add(cid);
        }
        if (lbl.isNotEmpty && !assignedClassLabels.contains(lbl)) {
          assignedClassLabels.add(lbl);
        }
        if (isCt && lbl.isNotEmpty && !classTeacherOf.contains(lbl)) {
          classTeacherOf.add(lbl);
        }
      }

      // 1. Classes where this teacher is designated class_teacher_id in school_classes
      for (final cls in classes) {
        if (_text(cls['classTeacherId']) == id) {
          addClassByEntry(cls, isCt: true);
        }
      }
      // 2. Classes from teacher_subject_assignments
      for (final cid in (explicitClassIdsByTeacher[id] ?? const <String>{})) {
        final cls = classesById[cid];
        if (cls != null) addClassByEntry(cls);
      }
      // 3. Classes from school_teachers.allowed_classes
      final allowedTokens = (teacher['allowedClasses'] as List?) ?? const [];
      for (final rawToken in allowedTokens) {
        final token = _text(rawToken);
        if (token.isEmpty) continue;
        if (classesById.containsKey(token)) {
          addClassByEntry(classesById[token]!);
          continue;
        }
        final mappedLabel = classAliasesToLabel[token] ?? classAliasesToLabel[token.toUpperCase()];
        if (mappedLabel != null && mappedLabel.isNotEmpty) {
          final matchedCls = classes.where((c) => _text(c['label']) == mappedLabel).firstOrNull;
          if (matchedCls != null) {
            addClassByEntry(matchedCls);
          } else if (!assignedClassLabels.contains(mappedLabel)) {
            assignedClassLabels.add(mappedLabel);
          }
        } else if (!assignedClassLabels.contains(token)) {
          assignedClassLabels.add(token);
        }
      }

      // Gather subjects from teacher_subject_assignments and class_subjects of assigned classes
      final explicitSet = explicitSubjectsByTeacher[id];
      final dbClassSubSet = <String>{};
      for (final cid in assignedClassIds) {
        for (final sub in (classSubjectsByClassId[cid] ?? const <String>[])) {
          if (sub.isNotEmpty) dbClassSubSet.add(sub);
        }
      }
      var names = (explicitSet != null && explicitSet.isNotEmpty)
          ? (explicitSet.toList()..sort())
          : dbClassSubSet.isNotEmpty
              ? dbClassSubSet.toList()
              : ((fallbackSubjectsByTeacher[id] ?? <String>{}).toList()..sort());
      if (names.isEmpty && subjects.isNotEmpty) {
        names = <String>[
          subjects[tIdx % subjects.length],
          if (subjects.length > 1) subjects[(tIdx + 1) % subjects.length],
        ];
      }
      teacher['subjects'] = names;
      teacher['explicitSubjects'] = (explicitSet != null && explicitSet.isNotEmpty)
          ? (explicitSet.toList()..sort())
          : dbClassSubSet.toList();
      teacher['assignedClasses'] = assignedClassLabels;
      teacher['classTeacherOf'] = classTeacherOf;

      // Determine group ('a' vs 'b') from explicit assigned classes or allowed_classes
      final gradeNumbers = <int>[];
      final explicitCids = explicitClassIdsByTeacher[id] ?? const <String>{};
      for (final cid in explicitCids) {
        final cls = classesById[cid];
        if (cls != null) {
          final n = int.tryParse(_englishDigits(_text(cls['standard'])));
          if (n != null) gradeNumbers.add(n);
        }
      }
      if (gradeNumbers.isEmpty) {
        final allowed = (teacher['allowedClasses'] as List?) ?? const [];
        for (final token in allowed) {
          final n = int.tryParse(
            RegExp(r'[1-8]').firstMatch(_englishDigits('$token'))?.group(0) ??
                '',
          );
          if (n != null) gradeNumbers.add(n);
        }
      }
      if (gradeNumbers.isEmpty) {
        gradeNumbers.addAll(
          assignmentData
              .where((row) => _text(row['teacherId']) == id)
              .map(
                (row) => int.tryParse(_englishDigits(_text(row['standard']))),
              )
              .whereType<int>(),
        );
      }
      if (gradeNumbers.isNotEmpty) {
        final earlyCount = gradeNumbers.where((n) => n >= 1 && n <= 5).length;
        final laterCount = gradeNumbers.where((n) => n >= 6 && n <= 8).length;
        teacher['group'] = laterCount > earlyCount ? 'b' : 'a';
      } else {
        teacher['group'] = tIdx >= (teachers.length ~/ 2) ? 'b' : 'a';
      }
    }

    final standards = <String>{
      '૩ થી ૫',
      '૬ થી ૮',
      '3 થી 5',
      '6 થી 8',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
    };
    for (final klass in classes) {
      final standard = _text(klass['standard']);
      if (standard.isNotEmpty && standard != 'BALVATIKA') {
        standards.add(standard);
      }
    }

    final examRows = _buildSmartExamRows(classes, subjects);

    // Prioritize school registration form address (school_address_gu / school_address_en)
    final schoolAddressGu = _first([
      schoolRow['school_address_gu'],
      schoolContext['school_address_gu'],
      profile['school_address_gu'],
      hajariMeta['address'],
      config['address'],
      config['school_address'],
      frontPageMeta['front_page_village'],
      hajariMeta['village_name'],
    ]);
    final schoolAddressEn = _first([
      schoolRow['school_address_en'],
      schoolContext['school_address_en'],
      profile['school_address_en'],
      schoolContext['address'],
      profile['address'],
      profile['school_address'],
    ]);
    final schoolAddress = _first([
      schoolAddressGu,
      schoolAddressEn,
      config['village'],
      schoolContext['village'],
      schoolContext['village_name'],
      profile['village'],
    ]);

    var taluka = _first([
      config['taluka'],
      frontPageMeta['front_page_taluka'],
      hajariMeta['taluka_name'],
      schoolRow['taluka'],
      schoolContext['taluka'],
      profile['taluka'],
    ]);
    var district = _first([
      config['district'],
      frontPageMeta['front_page_district'],
      hajariMeta['district_name'],
      schoolRow['district'],
      schoolContext['district'],
      profile['district'],
    ]);
    // Try extracting taluka/district from schoolAddress if not explicitly stored
    if (taluka.isEmpty && schoolAddress.isNotEmpty) {
      final m = RegExp(r'(?:તા\.?|તાલુકો\s*:?)\s*([^,|]+)')
          .firstMatch(schoolAddress);
      if (m != null) taluka = m.group(1)!.trim();
    }
    if (district.isEmpty && schoolAddress.isNotEmpty) {
      final m = RegExp(r'(?:જિ\.?|જી\.?|જિલ્લો\s*:?)\s*([^,|]+)')
          .firstMatch(schoolAddress);
      if (m != null) district = m.group(1)!.trim();
    }

    final payCenter = _first([
      config['pay_center'],
      config['center_name'],
      config['payCenter'],
      frontPageMeta['front_page_pay_center'],
      hajariMeta['pay_center_name'],
      schoolContext['pay_center'],
      schoolContext['center_name'],
      schoolContext['pay_center_name'],
      profile['pay_center'],
      profile['pay_center_name'],
    ]);
    final crcName = _first([
      config['crc_name'],
      config['crcName'],
      frontPageMeta['front_page_crc'],
      hajariMeta['crc_name'],
      schoolContext['crc_name'],
      profile['crc_name'],
    ]);
    final principalName = _first([
      registeredAdminName,
      schoolRow['admin_name'],
      schoolRow['principal_name'],
      schoolContext['admin_name'],
      schoolContext['principal_name'],
      config['principal_name'],
      config['principalName'],
      config['admin_name'],
      hajariMeta['principal_name'],
      if (_text(profile['role']).toLowerCase() == 'admin') profile['teacher_name'],
      profile['principal_name'],
      profile['admin_name'],
      profile['teacher_name'],
    ]);
    final academicYear = _first([
      config['academic_year'],
      config['academicYear'],
      hajariMeta['academic_year'],
      schoolContext['academic_year'],
      profile['academic_year'],
    ], '૨૦૨૬-૨૭');
    final genderMode = schoolType == 'boys'
        ? 'boys'
        : schoolType == 'girls'
        ? 'girls'
        : 'both';

    final savedTimetable = _map(config['planning_timetable_studio']);
    final savedExam = _map(config['planning_exam_planning']);

    final finalPayload = <String, dynamic>{
      'schoolRef': schoolRef,
      'schoolName': schoolName,
      'schoolNameGu': schoolNameGu.isNotEmpty ? schoolNameGu : schoolName,
      'schoolNameEn': schoolNameEn.isNotEmpty ? schoolNameEn : schoolName,
      'schoolAddress': schoolAddress,
      'schoolAddressGu': schoolAddressGu.isNotEmpty ? schoolAddressGu : schoolAddress,
      'schoolAddressEn': schoolAddressEn.isNotEmpty ? schoolAddressEn : schoolAddress,
      'taluka': taluka,
      'district': district,
      'payCenter': payCenter,
      'crcName': crcName,
      'principalName': principalName,
      'academicYear': academicYear,
      'schoolType': schoolType,
      'genderMode': genderMode,
      'schoolLogoBytes': schoolLogoBytes,
      'schoolLogoDataUri': schoolLogoDataUri,
      'teachers': teachers,
      'subjects': subjects,
      'classes': classes,
      'classAliasesToLabel': classAliasesToLabel,
      'assignments': assignmentData,
      'hasExplicitAssignments': activeAssignmentRows.isNotEmpty,
      'examRows': examRows,
      'standardOptions': standards.toList(),
      'savedTimetable': savedTimetable,
      'savedExam': savedExam,
      'schoolConfig': config,
    };
    _sessionPlanningCache[schoolRef] = Map<String, dynamic>.from(finalPayload);
    _sessionPlanningCacheAt[schoolRef] = DateTime.now();
    return Map<String, dynamic>.from(finalPayload);
  }

  List<Map<String, dynamic>> _buildSmartExamRows(
    List<Map<String, dynamic>> classes,
    List<String> masterSubjects,
  ) {
    const gujDays = <int, String>{
      DateTime.monday: 'સોમવાર',
      DateTime.tuesday: 'મંગળવાર',
      DateTime.wednesday: 'બુધવાર',
      DateTime.thursday: 'ગુરુવાર',
      DateTime.friday: 'શુક્રવાર',
      DateTime.saturday: 'શનિવાર',
      DateTime.sunday: 'રવિવાર',
    };

    var cursor = DateTime.now().add(const Duration(days: 1));
    while (cursor.weekday == DateTime.sunday) {
      cursor = cursor.add(const Duration(days: 1));
    }

    final workingDates = <DateTime>[];
    var d = cursor;
    while (workingDates.length < 10) {
      if (d.weekday != DateTime.sunday) {
        workingDates.add(d);
      }
      d = d.add(const Duration(days: 1));
    }

    String fmtDate(DateTime dt) =>
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

    final has3to5 =
        classes.isEmpty ||
        classes.any((c) {
          final n = int.tryParse(_englishDigits(_text(c['standard'])));
          return n != null && n >= 3 && n <= 5;
        });
    final has6to8 =
        classes.isEmpty ||
        classes.any((c) {
          final n = int.tryParse(_englishDigits(_text(c['standard'])));
          return n != null && n >= 6 && n <= 8;
        });

    final rows = <Map<String, dynamic>>[];
    if (has3to5) {
      const sub35 = <({String std, String sub})>[
        (std: '૩ થી ૫', sub: 'ગુજરાતી'),
        (std: '૩ થી ૫', sub: 'ગણિત'),
        (std: '૫', sub: 'હિન્દી'),
        (std: '૩ થી ૫', sub: 'પર્યાવરણ'),
        (std: '૩ થી ૫', sub: 'અંગ્રેજી'),
      ];
      for (var i = 0; i < sub35.length; i++) {
        final dt = workingDates[i];
        rows.add(<String, dynamic>{
          'date': fmtDate(dt),
          'day': gujDays[dt.weekday] ?? 'સોમવાર',
          'stdLabel': sub35[i].std,
          'subject': sub35[i].sub,
          'time': '11:00 થી 1:00',
          'marks': '40',
        });
      }
    }
    if (has6to8) {
      const sub68 = <String>[
        'ગુજરાતી',
        'ગણિત',
        'સંસ્કૃત',
        'હિન્દી',
        'વિજ્ઞાન',
        'અંગ્રેજી',
        'સા. વિજ્ઞાન',
      ];
      for (var i = 0; i < sub68.length; i++) {
        final dt = workingDates[i];
        final isSat = dt.weekday == DateTime.saturday;
        rows.add(<String, dynamic>{
          'date': fmtDate(dt),
          'day': gujDays[dt.weekday] ?? 'સોમવાર',
          'stdLabel': '૬ થી ૮',
          'subject': sub68[i],
          'time': isSat ? '8:00 થી 11:00' : '2:00 થી 5:00',
          'marks': '80',
        });
      }
    }
    return rows;
  }

  Future<void> savePlanningData({
    required String key,
    required Map<String, dynamic> value,
  }) async {
    const supportedKeys = <String>{
      'planning_timetable_studio',
      'planning_exam_planning',
      'planning_file_share',
    };
    if (!supportedKeys.contains(key)) {
      throw ArgumentError.value(key, 'key', 'Unsupported planning setting.');
    }
    final schoolRef = await _currentSchoolRef();
    final row = await _client
        .from('school_settings')
        .select('config')
        .eq('school_ref', schoolRef)
        .maybeSingle();
    final config = _map(row?['config']);
    config[key] = value;
    if (key == 'planning_timetable_studio' &&
        value['teacherInitialsById'] is Map) {
      config['teacher_initials'] = _map(value['teacherInitialsById']);
    }
    await _client.from('school_settings').upsert(<String, dynamic>{
      'school_ref': schoolRef,
      'config': config,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'school_ref');
    _sessionPlanningCache.remove(schoolRef);
    _sessionPlanningCacheAt.remove(schoolRef);
  }
}

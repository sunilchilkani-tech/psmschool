import 'package:pmshri_attendance/services/firebase_backend_client.dart';
import 'school_type.dart';

/// Supabase-only student data adapter. Tenant and class boundaries are enforced
/// by current_school_ref(), can_access_class(), and database RLS policies.
class SupabaseStudentService {
  SupabaseStudentService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const publicTextFields = <String>[
    'roll_number',
    'gr',
    'dd',
    'mm',
    'yyyy',
    'name',
    'religion',
    'religion_en',
    'caste',
    'category',
    'gender',
    'enroll_school',
    'enroll_class',
    'mobile',
    'father_name',
    'mother_name',
    'address',
    'birth_place',
    'dob_words',
    'last_school',
    'enroll_sch_class',
    'enroll_sch_class_words',
    'name_en',
    'caste_en',
    'category_en',
    'mother_en',
    'birth_place_en',
    'dob_en',
    'last_school_en',
    'enroll_sch_class_en',
    'enroll_sch_class_words_en',
    'uid',
    'pen',
    'is_divyang',
    'scholarship_done',
    'scholarship_reason',
    'scholarship_other',
    'has_aadhaar',
    'ration_card_kyc',
  ];

  static const privateTextFields = <String>[
    'bank_name',
    'bank_branch',
    'name_as_passbook',
    'account_number',
    'ifsc_code',
  ];

  static const customFields = <String>[
    'apaar_id',
    'present_days',
    'native_place',
    'native_place_en',
    'religion',
    'religion_en',
    'has_aadhaar',
    'ration_card_kyc',
  ];

  static const allTemplateFields = <String>[
    'serial',
    'class_label',
    'roll_number',
    'gr',
    'dd',
    'mm',
    'yyyy',
    'name',
    'gender',
    'religion',
    'caste',
    'category',
    'enroll_school',
    'enroll_class',
    'mobile',
    'father_name',
    'mother_name',
    'birth_place',
    'dob_words',
    'last_school',
    'enroll_sch_class',
    'enroll_sch_class_words',
    'present_days',
    'name_en',
    'religion_en',
    'caste_en',
    'category_en',
    'mother_en',
    'birth_place_en',
    'dob_en',
    'last_school_en',
    'enroll_sch_class_en',
    'enroll_sch_class_words_en',
    'apaar_id',
    'has_aadhaar',
    'ration_card_kyc',
    'scholarship_done',
    'scholarship_reason',
    'uid',
    'pen',
    'is_divyang',
    'bank_name',
    'bank_branch',
    'name_as_passbook',
    'account_number',
    'ifsc_code',
    'native_place',
    'native_place_en',
  ];

  String _str(dynamic value) => (value ?? '').toString().trim();

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) return value.map((key, value) => MapEntry('$key', value));
    return <String, dynamic>{};
  }

  static const Set<String> _restrictedStudentKeys = <String>{
    'aadhaar',
    'name_as_aadhaar',
    'nameasaadhaar',
    'dob_as_aadhaar',
    'dobasaadhaar',
    'ration_card_type',
    'rationcardtype',
    'ration_card_no',
    'rationcardno',
    'ration_card_member_no',
    'rationcardmemberno',
    'member_number',
    'membernumber',
  };

  static bool _isAllowedAadhaarOrKycKey(String key) {
    final k = key.trim().toLowerCase();
    return k == 'has_aadhaar' ||
        k == 'hasaadhaar' ||
        k == 'ration_card_kyc' ||
        k == 'rationcardkyc';
  }

  Map<String, dynamic> _withoutRestrictedKeys(dynamic raw) {
    final output = _map(raw);
    output.removeWhere((key, value) {
      if (_isAllowedAadhaarOrKycKey(key)) return false;
      final normalized =
          key.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '').toLowerCase();
      return _restrictedStudentKeys.contains(normalized) ||
          normalized.contains('aadhaar') ||
          normalized.contains('aadhar') ||
          normalized.contains('ration') ||
          key.contains('આધાર') ||
          key.contains('રેશન');
    });
    return output;
  }

  String normalizeYesNo(dynamic raw, {String defaultValue = 'NO'}) {
    final v = _str(raw).toUpperCase();
    if (v.isEmpty) return defaultValue;
    if (const <String>{'YES', 'Y', 'TRUE', '1', 'હા'}.contains(v) ||
        v.startsWith('YES') ||
        v.startsWith('હા')) {
      return 'YES';
    }
    return 'NO';
  }

  bool _divyangValue(dynamic value) {
    if (value is bool) return value;
    final normalized = _str(value).toUpperCase();
    return const <String>{'YES', 'TRUE', '1', 'T', 'હા'}.contains(normalized) ||
        normalized.startsWith('હા ') ||
        normalized.contains('YES');
  }

  Future<String> currentSchoolRef() async {
    if (_client.auth.currentUser == null) {
      throw StateError('Please sign in again.');
    }
    final value = await _client.rpc('current_school_ref');
    final ref = _str(value);
    if (ref.isEmpty) {
      throw StateError('This login is not linked to an active school.');
    }
    return ref;
  }

  Future<bool> isCurrentUserAdmin() async {
    final value = await _client.rpc('is_school_admin');
    if (value is bool) return value;
    return const <String>{'true', 't', '1'}.contains(_str(value).toLowerCase());
  }

  String normalizeCategory(dynamic raw) {
    final value = _str(raw).toUpperCase();
    if (value == 'SC' ||
        value.contains('અ. જા') ||
        value.contains('SCHEDULED CASTE')) return 'SC';
    if (value == 'ST' ||
        value.contains('અ. જ. જા') ||
        value.contains('SCHEDULED TRIBE')) return 'ST';
    if (value == 'OBC' ||
        value.contains('બક્ષી') ||
        value.contains('BAKSHIPANCH')) return 'OBC';
    return 'OTHER';
  }

  String normalizeGender(dynamic raw, String schoolType) {
    final type = SchoolType.canonical(schoolType);
    if (type == SchoolType.boys) return 'BOYS';
    if (type == SchoolType.girls) return 'GIRLS';
    final value = _str(raw).toUpperCase();
    if (const <String>{'BOYS', 'BOY', 'MALE', 'M', 'KUMAR', 'કુમાર'}
        .contains(value)) return 'BOYS';
    if (const <String>{'GIRLS', 'GIRL', 'FEMALE', 'F', 'KANYA', 'કન્યા'}
        .contains(value)) return 'GIRLS';
    return 'UNSPECIFIED';
  }

  bool isMixedSchool(String schoolType) => SchoolType.isMixed(schoolType);

  Future<Map<String, dynamic>> getPrivateDetails(String studentId) async {
    final id = studentId.trim();
    if (id.isEmpty || !await isCurrentUserAdmin()) {
      return <String, dynamic>{};
    }
    final schoolRef = await currentSchoolRef();
    final row = await _client
        .from('student_private_details')
        .select()
        .eq('school_ref', schoolRef)
        .eq('student_id', id)
        .maybeSingle();
    return row == null ? <String, dynamic>{} : Map<String, dynamic>.from(row);
  }

  Future<List<Map<String, dynamic>>> listStudents({
    required String classId,
  }) async {
    final schoolRef = await currentSchoolRef();
    var query = _client
        .from('students')
        .select(
          'id,school_ref,class_id,roll_number,gr,dd,mm,yyyy,name,religion,religion_en,caste,category,gender,enroll_school,enroll_class,mobile,father_name,mother_name,address,birth_place,dob_words,last_school,enroll_sch_class,enroll_sch_class_words,name_en,caste_en,category_en,mother_en,birth_place_en,dob_en,last_school_en,enroll_sch_class_en,enroll_sch_class_words_en,uid,pen,is_divyang,has_aadhaar,ration_card_kyc,scholarship_done,scholarship_reason,scholarship_other,custom_fields,is_active,created_at,updated_at',
        )
        .eq('school_ref', schoolRef)
        .eq('is_active', true);
    if (classId.trim().isNotEmpty && classId.trim() != '__ALL__') {
      query = query.eq('class_id', classId.trim());
    }
    final rows = await query;
    final result = rows.map((row) => Map<String, dynamic>.from(row)).toList();
    result.sort((a, b) {
      final ca = _str(a['class_id']).compareTo(_str(b['class_id']));
      if (classId.trim().isEmpty || classId.trim() == '__ALL__') {
        if (ca != 0) return ca;
      }
      final ar = int.tryParse(_str(a['roll_number']));
      final br = int.tryParse(_str(b['roll_number']));
      if (ar != null && br != null) return ar.compareTo(br);
      return _str(a['roll_number']).compareTo(_str(b['roll_number']));
    });

    if (await isCurrentUserAdmin() && result.isNotEmpty) {
      final ids = result
          .map((row) => _str(row['id']))
          .where((id) => id.isNotEmpty)
          .toList();
      final privateRows = await _client
          .from('student_private_details')
          .select(
              'student_id,bank_name,bank_branch,name_as_passbook,account_number,ifsc_code')
          .eq('school_ref', schoolRef)
          .inFilter('student_id', ids);
      final byStudent = <String, Map<String, dynamic>>{
        for (final raw in privateRows)
          _str(raw['student_id']): Map<String, dynamic>.from(raw),
      };
      for (final row in result) {
        final fields = _withoutRestrictedKeys(row['custom_fields']);
        row.addAll(fields);
        row.removeWhere((key, value) {
          if (_isAllowedAadhaarOrKycKey(key)) return false;
          final normalized =
              key.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '').toLowerCase();
          return _restrictedStudentKeys.contains(normalized) ||
              normalized.contains('aadhaar') ||
              normalized.contains('aadhar') ||
              normalized.contains('ration') ||
              key.contains('આધાર') ||
              key.contains('રેશન');
        });
        final private = byStudent[_str(row['id'])];
        if (private != null) row.addAll(private);
      }
    } else {
      for (final row in result) {
        row.addAll(_withoutRestrictedKeys(row['custom_fields']));
        row.removeWhere((key, value) {
          if (_isAllowedAadhaarOrKycKey(key)) return false;
          final normalized =
              key.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '').toLowerCase();
          return _restrictedStudentKeys.contains(normalized) ||
              normalized.contains('aadhaar') ||
              normalized.contains('aadhar') ||
              normalized.contains('ration') ||
              key.contains('આધાર') ||
              key.contains('રેશન');
        });
      }
    }
    return result;
  }

  Future<String> _nextRollNumber(
      {required String schoolRef, required String classId}) async {
    final rows = await _client
        .from('students')
        .select('roll_number')
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .eq('is_active', true);
    var max = 0;
    for (final row in rows) {
      final n = int.tryParse(_str(row['roll_number']));
      if (n != null && n > max) max = n;
    }
    return '${max + 1}';
  }

  Map<String, dynamic> _buildPublicPayload({
    required Map<String, dynamic> values,
    required String schoolRef,
    required String classId,
    required String schoolType,
  }) {
    final isActive = values['is_active'] is bool ? values['is_active'] as bool : true;
    final custom = <String, dynamic>{
      ..._withoutRestrictedKeys(values['_custom_fields']),
      ..._withoutRestrictedKeys(values['custom_fields']),
      'apaar_id': _str(values['apaar_id']),
      'present_days': _str(values['present_days']),
      'native_place': _str(values['native_place']),
      'native_place_en': _str(values['native_place_en']),
      'religion': _str(values['religion']),
      'religion_en': _str(values['religion_en']),
      'has_aadhaar': normalizeYesNo(values['has_aadhaar'], defaultValue: 'NO'),
      'ration_card_kyc': normalizeYesNo(values['ration_card_kyc'], defaultValue: 'NO'),
    };
    custom.removeWhere((key, value) => _str(value).isEmpty);
    final normScholarship = normalizeYesNo(values['scholarship_done'], defaultValue: 'NO');
    final normScholarshipReason = normScholarship == 'YES'
        ? ''
        : _str(values['scholarship_reason']);
    final payload = <String, dynamic>{
      'school_ref': schoolRef,
      'class_id': classId,
      'roll_number': _str(values['roll_number']),
      'gr': _str(values['gr']),
      'dd': _str(values['dd']),
      'mm': _str(values['mm']),
      'yyyy': _str(values['yyyy']),
      'name': _str(values['name']),
      'religion': _str(values['religion']),
      'religion_en': _str(values['religion_en']),
      'caste': _str(values['caste']),
      'category': normalizeCategory(values['category']),
      'gender': normalizeGender(values['gender'], schoolType),
      'enroll_school': _str(values['enroll_school']),
      'enroll_class': _str(values['enroll_class']),
      'mobile': _str(values['mobile']),
      'father_name': _str(values['father_name']),
      'mother_name': _str(values['mother_name']),
      'address': _str(values['address']),
      'birth_place': _str(values['birth_place']),
      'dob_words': _str(values['dob_words']),
      'last_school': _str(values['last_school']),
      'enroll_sch_class': _str(values['enroll_sch_class']),
      'enroll_sch_class_words': _str(values['enroll_sch_class_words']),
      'name_en': _str(values['name_en']),
      'caste_en': _str(values['caste_en']),
      'category_en': _str(values['category_en']),
      'mother_en': _str(values['mother_en']),
      'birth_place_en': _str(values['birth_place_en']),
      'dob_en': _str(values['dob_en']),
      'last_school_en': _str(values['last_school_en']),
      'enroll_sch_class_en': _str(values['enroll_sch_class_en']),
      'enroll_sch_class_words_en': _str(values['enroll_sch_class_words_en']),
      'uid': _str(values['uid']),
      'pen': _str(values['pen']),
      'is_divyang': _divyangValue(values['is_divyang']),
      'has_aadhaar': normalizeYesNo(values['has_aadhaar'], defaultValue: 'NO'),
      'ration_card_kyc': normalizeYesNo(values['ration_card_kyc'], defaultValue: 'NO'),
      'scholarship_done': normScholarship,
      'scholarship_reason': normScholarshipReason,
      'scholarship_other': _str(values['scholarship_other']),
      'custom_fields': custom,
      'is_active': isActive,
      if (isActive) 'leaving_date': null,
      if (isActive) 'exit_date': null,
      if (isActive) 'exit_reason': '',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    return payload;
  }

  Map<String, dynamic> _buildPrivatePayload({
    required Map<String, dynamic> values,
    required String studentId,
    required String schoolRef,
  }) =>
      <String, dynamic>{
        'student_id': studentId,
        'school_ref': schoolRef,
        'bank_name': _str(values['bank_name']),
        'bank_branch': _str(values['bank_branch']),
        'name_as_passbook': _str(values['name_as_passbook']),
        'account_number': _str(values['account_number']),
        'ifsc_code': _str(values['ifsc_code']),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  Future<void> saveStudent({
    required String classId,
    required String schoolType,
    required Map<String, dynamic> values,
    String? studentId,
  }) async {
    final schoolRef = await currentSchoolRef();
    final admin = await isCurrentUserAdmin();
    final name = _str(values['name']);
    if (name.isEmpty) throw const FormatException('Student name is required.');
    var roll = _str(values['roll_number']);
    if (roll.isEmpty) {
      if ((studentId ?? '').isNotEmpty) {
        roll = _str(values['roll_number']);
      } else {
        roll = await _nextRollNumber(schoolRef: schoolRef, classId: classId);
      }
    }
    final existing = await _client
        .from('students')
        .select('id,roll_number')
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .eq('is_active', true);
    final duplicate = existing.any((row) =>
        _str(row['id']) != (studentId ?? '') &&
        _str(row['roll_number']).toUpperCase() == roll.toUpperCase());
    if (duplicate) {
      throw FormatException('Roll number $roll already exists in this class.');
    }

    final payload = _buildPublicPayload(
      values: <String, dynamic>{...values, 'roll_number': roll},
      schoolRef: schoolRef,
      classId: classId,
      schoolType: schoolType,
    );
    late final String savedId;
    if ((studentId ?? '').trim().isNotEmpty) {
      final row = await _client
          .from('students')
          .update(payload)
          .eq('id', studentId!.trim())
          .eq('school_ref', schoolRef)
          .select('id')
          .single();
      savedId = _str(row['id']);
    } else {
      payload['created_at'] = DateTime.now().toUtc().toIso8601String();
      final row =
          await _client.from('students').insert(payload).select('id').single();
      savedId = _str(row['id']);
    }

    if (admin) {
      final privatePayload = _buildPrivatePayload(
        values: values,
        studentId: savedId,
        schoolRef: schoolRef,
      );
      await _client.from('student_private_details').upsert(
            privatePayload,
            onConflict: 'student_id',
          );
    }
  }

  Future<void> archiveStudent({
    required String classId,
    required String studentId,
    String? leavingDate,
  }) async {
    await _client.rpc(
      'psm_archive_student_and_shift_rolls',
      params: <String, dynamic>{
        'p_student_id': studentId,
        if (leavingDate != null && leavingDate.trim().isNotEmpty)
          'p_exit_date': leavingDate.trim(),
        'p_exit_reason': 'lc',
      },
    );
  }

  static String _normGr(dynamic raw) {
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    var s = '${raw ?? ''}'.trim();
    for (var i = 0; i < guj.length; i++) {
      s = s.replaceAll(guj[i], '$i');
    }
    return s.toUpperCase().replaceAll(RegExp(r'\s+'), '');
  }

  static bool isGenericSheetName(String raw) {
    final s = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
    if (s.isEmpty) return true;
    if (RegExp(r'^sheet\d*$').hasMatch(s)) return true;
    return const <String>{
      'students',
      'student',
      'data',
      'export',
      'grpartialupdate',
      'wholeschoolstudents',
      'exporttempforsinglegender',
      'exporttempforcoed',
      'instructions',
      'સૂચનાઓ',
    }.contains(s);
  }

  static String _normClassKey(String raw) {
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    var s = raw.trim().toLowerCase();
    for (var i = 0; i < guj.length; i++) {
      s = s.replaceAll(guj[i], '$i');
    }
    if (s.contains('બાલ') ||
        s.contains('વાટિકા') ||
        s.contains('balvatika') ||
        s.contains('balwatika') ||
        s.contains('ankur') ||
        s == 'bv' ||
        s == 'kg') {
      return 'balvatika';
    }
    return s
        .replaceAll('ધોરણ', '')
        .replaceAll('વર્ગ', '')
        .replaceAll('standard', '')
        .replaceAll('std', '')
        .replaceAll('class', '')
        .replaceAll('અ', 'a')
        .replaceAll('બ', 'b')
        .replaceAll('ક', 'c')
        .replaceAll('ડ', 'd')
        .replaceAll(RegExp(r'[^a-z0-9\u0a80-\u0aff]+'), '');
  }

  Future<Map<String, dynamic>> importRows({
    required String classId,
    required String schoolType,
    required List<Map<String, dynamic>> rows,
  }) async {
    final schoolRef = await currentSchoolRef();
    final admin = await isCurrentUserAdmin();
    final defaultClassId =
        (classId.trim() == '__ALL__') ? '' : classId.trim();

    // Load all active classes in the school for Whole-School multi-class routing
    final classRows = await _client
        .from('school_classes')
        .select('id,label,class_key,standard,section,sheet_name,is_active')
        .eq('school_ref', schoolRef)
        .eq('is_active', true);
    final schoolClasses =
        classRows.map((c) => Map<String, dynamic>.from(c)).toList();

    String resolveTargetClassId(String classHint) {
      final hint = classHint.trim();
      if (hint.isEmpty || isGenericSheetName(hint)) return defaultClassId;
      final normHint = _normClassKey(hint);
      for (final c in schoolClasses) {
        final cid = _str(c['id']);
        final candidates = <String>[
          _str(c['label']),
          _str(c['class_key']),
          _str(c['sheet_name']),
          _str(c['standard']),
          if (_str(c['standard']).isNotEmpty && _str(c['section']).isNotEmpty)
            '${_str(c['standard'])}-${_str(c['section'])}',
          if (_str(c['standard']).isNotEmpty && _str(c['section']).isNotEmpty)
            '${_str(c['standard'])} ${_str(c['section'])}',
        ];
        for (final cand in candidates) {
          if (cand.isEmpty) continue;
          if (cand.toLowerCase() == hint.toLowerCase() ||
              (normHint.isNotEmpty && _normClassKey(cand) == normHint)) {
            return cid;
          }
        }
      }
      // Digit match if only one class of that standard exists
      final m = RegExp(r'[1-8]').firstMatch(normHint);
      if (m != null) {
        final digit = m.group(0)!;
        final matches = schoolClasses.where((c) {
          final cNorm = _normClassKey(
            '${_str(c['standard'])} ${_str(c['label'])} ${_str(c['class_key'])}',
          );
          return cNorm.contains(digit);
        }).toList();
        if (matches.length == 1) {
          return _str(matches.first['id']);
        }
      }
      return defaultClassId;
    }

    // Load all existing students across the entire school so GR Number uniquely identifies any student
    final existingSchoolStudents = await _client
        .from('students')
        .select('*')
        .eq('school_ref', schoolRef);

    final byGr = <String, Map<String, dynamic>>{};
    final byClassAndRoll = <String, Map<String, dynamic>>{};
    final byClassAndName = <String, Map<String, dynamic>>{};
    final nextRollByClass = <String, int>{};

    for (final raw in existingSchoolStudents) {
      final s = Map<String, dynamic>.from(raw);
      final grKey = _normGr(s['gr']);
      if (grKey.isNotEmpty) {
        if (!byGr.containsKey(grKey) || s['is_active'] == true) {
          byGr[grKey] = s;
        }
      }
      final cid = _str(s['class_id']);
      final roll = _str(s['roll_number']).isNotEmpty
          ? _str(s['roll_number']).toUpperCase()
          : _str(s['previous_roll_number']).toUpperCase();
      final nameLower = _str(s['name']).toLowerCase();
      if (cid.isNotEmpty && roll.isNotEmpty) {
        if (!byClassAndRoll.containsKey('$cid|$roll') || s['is_active'] == true) {
          byClassAndRoll['$cid|$roll'] = s;
        }
        if (s['is_active'] == true) {
          final rNum = int.tryParse(roll);
          if (rNum != null) {
            final cur = nextRollByClass[cid] ?? 1;
            if (rNum >= cur) nextRollByClass[cid] = rNum + 1;
          }
        }
      }
      if (cid.isNotEmpty && nameLower.isNotEmpty) {
        if (!byClassAndName.containsKey('$cid|$nameLower') ||
            s['is_active'] == true) {
          byClassAndName['$cid|$nameLower'] = s;
        }
      }
    }

    var imported = 0;
    var updated = 0;
    var restored = 0;
    final errors = <String>[];
    final warnings = <String>[];
    final affectedClasses = <String>{};

    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final line =
          int.tryParse('${row['_excel_row'] ?? (index + 2)}') ?? (index + 2);
      final grRaw = _str(row['gr']);
      final grKey = _normGr(grRaw);
      final name = _str(row['name']);
      final rawClassLabel = _str(row['class_label']);
      final rawSheetName = _str(row['_sheet_name']);
      final classHint = rawClassLabel.isNotEmpty
          ? rawClassLabel
          : (isGenericSheetName(rawSheetName) ? '' : rawSheetName);
      final targetClassId = resolveTargetClassId(classHint);
      final rawRoll = _str(row['roll_number']).toUpperCase();

      // 1. Match existing student:
      //    Priority A: Unique GR Number across the entire school (active or archived)
      //    Priority B: (targetClassId, roll_number) when name matches or is omitted
      //    Priority C: (targetClassId, name)
      Map<String, dynamic>? existingMatch;
      if (grKey.isNotEmpty && byGr.containsKey(grKey)) {
        existingMatch = byGr[grKey];
      } else if (targetClassId.isNotEmpty &&
          rawRoll.isNotEmpty &&
          byClassAndRoll.containsKey('$targetClassId|$rawRoll')) {
        final cand = byClassAndRoll['$targetClassId|$rawRoll']!;
        if (name.isEmpty ||
            _str(cand['name']).toLowerCase() == name.toLowerCase()) {
          existingMatch = cand;
        }
      } else if (targetClassId.isNotEmpty &&
          name.isNotEmpty &&
          byClassAndName.containsKey('$targetClassId|${name.toLowerCase()}')) {
        existingMatch = byClassAndName['$targetClassId|${name.toLowerCase()}'];
      }

      try {
        late final String studentId;
        if (existingMatch != null && _str(existingMatch['id']).isNotEmpty) {
          // SMART PARTIAL-COLUMN MERGE + AUTOMATIC REACTIVATION:
          // Merge incoming non-empty cells onto existing student record so omitted/blank columns NEVER erase existing data,
          // and if the student was archived/graduated or misrouted by Sheet1, reactivate and assign to targetClassId!
          studentId = _str(existingMatch['id']);
          final wasInactive = existingMatch['is_active'] != true ||
              _str(existingMatch['leaving_date']).isNotEmpty ||
              _str(existingMatch['exit_date']).isNotEmpty;
          final existingClassId = _str(existingMatch['class_id']);
          final effectiveClassId =
              (classHint.isNotEmpty && targetClassId.isNotEmpty)
                  ? targetClassId
                  : (defaultClassId.isNotEmpty
                      ? defaultClassId
                      : (existingClassId.isNotEmpty
                          ? existingClassId
                          : targetClassId));

          final mergedValues = <String, dynamic>{
            ...existingMatch,
            'is_active': true,
            'leaving_date': null,
            'exit_date': null,
            'exit_reason': '',
          };
          for (final entry in row.entries) {
            final k = entry.key;
            if (k.startsWith('_') || k == 'serial' || k == 'class_label') {
              continue;
            }
            final vStr = _str(entry.value);
            if (vStr.isNotEmpty) {
              mergedValues[k] = vStr;
            }
          }
          if (_str(mergedValues['roll_number']).isEmpty) {
            final oldRoll = _str(existingMatch['roll_number']).isNotEmpty
                ? _str(existingMatch['roll_number'])
                : _str(existingMatch['previous_roll_number']);
            if (oldRoll.isNotEmpty) {
              mergedValues['roll_number'] = oldRoll;
            } else {
              final nextR = nextRollByClass[effectiveClassId] ?? 1;
              mergedValues['roll_number'] = '$nextR';
              nextRollByClass[effectiveClassId] = nextR + 1;
            }
          }
          if (_str(mergedValues['name']).isEmpty) {
            mergedValues['name'] = _str(existingMatch['name']);
          }

          final payload = _buildPublicPayload(
            values: mergedValues,
            schoolRef: schoolRef,
            classId: effectiveClassId,
            schoolType: schoolType,
          );
          // Preserve custom_fields if any custom headers were passed
          final oldCustom = existingMatch['custom_fields'] is Map
              ? Map<String, dynamic>.from(
                  (existingMatch['custom_fields'] as Map)
                      .map((k, v) => MapEntry('$k', v)),
                )
              : <String, dynamic>{};
          if (payload['custom_fields'] is Map) {
            oldCustom.addAll(
              Map<String, dynamic>.from(payload['custom_fields'] as Map),
            );
          }
          if (row['custom_fields'] is Map) {
            for (final ce in (row['custom_fields'] as Map).entries) {
              final cv = _str(ce.value);
              if (cv.isNotEmpty) oldCustom['${ce.key}'] = cv;
            }
          }
          payload['custom_fields'] = _withoutRestrictedKeys(oldCustom);

          await _client
              .from('students')
              .update(payload)
              .eq('id', studentId)
              .eq('school_ref', schoolRef);

          final updatedRecord = <String, dynamic>{
            ...existingMatch,
            ...payload,
            'id': studentId,
          };
          if (grKey.isNotEmpty) byGr[grKey] = updatedRecord;
          affectedClasses.add(effectiveClassId);
          if (existingClassId.isNotEmpty) affectedClasses.add(existingClassId);
          imported++;
          updated++;
          if (wasInactive) restored++;
        } else {
          // Brand-new student insertion
          if (name.isEmpty) {
            errors.add(
              grKey.isNotEmpty
                  ? 'Row $line: GR નંબર "$grRaw" ડેટાબેઝમાં મળ્યો નથી અને નવા વિદ્યાર્થી માટે નામ ( વિદ્યાર્થીનું નામ ) આપેલ નથી.'
                  : 'Row $line: વિદ્યાર્થીનું નામ અથવા GR નંબર જરૂરી છે.',
            );
            continue;
          }
          if (targetClassId.isEmpty) {
            errors.add(
              'Row $line ($name): વર્ગ (Class) ઓળખી શકાયો નથી. કૃપા કરીને ધોરણ કૉલમ ભરો અથવા ઉપરથી વર્ગ પસંદ કરો.',
            );
            continue;
          }
          var effectiveGender = normalizeGender(row['gender'], schoolType);
          if (isMixedSchool(schoolType) && effectiveGender == 'UNSPECIFIED') {
            effectiveGender = 'BOYS';
            warnings.add(
              'Row $line ($name): જાતિ (Gender) ખાલી હોવાથી ડિફોલ્ટ BOYS રાખેલ છે.',
            );
          }
          var roll = _str(row['roll_number']);
          if (roll.isEmpty) {
            final nextR = nextRollByClass[targetClassId] ?? 1;
            roll = '$nextR';
            nextRollByClass[targetClassId] = nextR + 1;
          }
          final payload = _buildPublicPayload(
            values: <String, dynamic>{
              ...row,
              'roll_number': roll,
              'name': name,
              'gender': effectiveGender,
            },
            schoolRef: schoolRef,
            classId: targetClassId,
            schoolType: schoolType,
          );
          if (row['custom_fields'] is Map) {
            final mergedCustom = <String, dynamic>{
              if (payload['custom_fields'] is Map)
                ...Map<String, dynamic>.from(payload['custom_fields'] as Map),
              ...Map<String, dynamic>.from(
                (row['custom_fields'] as Map).map((k, v) => MapEntry('$k', v)),
              ),
            };
            payload['custom_fields'] = _withoutRestrictedKeys(mergedCustom);
          }
          payload['created_at'] = DateTime.now().toUtc().toIso8601String();
          final created = await _client
              .from('students')
              .insert(payload)
              .select('id')
              .single();
          studentId = _str(created['id']);
          final createdRecord = <String, dynamic>{...payload, 'id': studentId};
          if (grKey.isNotEmpty) byGr[grKey] = createdRecord;
          byClassAndRoll['$targetClassId|${roll.toUpperCase()}'] = createdRecord;
          byClassAndName['$targetClassId|${name.toLowerCase()}'] = createdRecord;
          affectedClasses.add(targetClassId);
          imported++;
        }

        // Save private bank fields if provided (partial merge for existing private details)
        if (admin) {
          final suppliedPrivate =
              privateTextFields.any((key) => _str(row[key]).isNotEmpty);
          if (suppliedPrivate) {
            try {
              final existingPriv = await getPrivateDetails(studentId);
              final mergedPrivInput = <String, dynamic>{
                ...existingPriv,
                for (final k in privateTextFields)
                  if (_str(row[k]).isNotEmpty) k: _str(row[k]),
              };
              final privatePayload = _buildPrivatePayload(
                values: mergedPrivInput,
                studentId: studentId,
                schoolRef: schoolRef,
              );
              await _client
                  .from('student_private_details')
                  .upsert(privatePayload, onConflict: 'student_id');
            } catch (privateError) {
              warnings.add(
                'Row $line: વિદ્યાર્થી સેવ થયો પરંતુ બેંક વિગત સેવ થઈ શકી નથી: ${privateError.toString().replaceFirst('Exception: ', '')}',
              );
            }
          }
        }
      } catch (error) {
        errors.add(
          'Row $line (${name.isNotEmpty ? name : grRaw}): ${error.toString().replaceFirst('Exception: ', '')}',
        );
      }
    }

    for (final cid in affectedClasses) {
      if (cid.isNotEmpty) {
        try {
          await _client.rpc(
            'psm_renumber_class_rolls',
            params: <String, dynamic>{'p_class_id': cid},
          );
        } catch (_) {}
      }
    }

    return <String, dynamic>{
      'imported': imported,
      'updated': updated,
      'restored': restored,
      'failed': errors.length,
      'errors': errors,
      'warnings': warnings,
    };
  }
}

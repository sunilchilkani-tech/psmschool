library;

import 'dart:math' as math;

class Teacher {
  final String? id;
  final String name;
  final String pin;
  final List<String>? classes;
  final String role;
  final String? loginEmail;

  const Teacher({
    this.id,
    required this.name,
    this.pin = '',
    required this.classes,
    this.role = 'teacher',
    this.loginEmail,
  });

  bool get isAdmin =>
      role.toLowerCase() == 'admin' ||
      role.toLowerCase() == 'developer' ||
      classes == null;

  bool canAccessClass(String classKey) {
    String clean(String value) => value
        .replaceFirst(RegExp(r'^Class\s+', caseSensitive: false), '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '');
    return isAdmin ||
        (classes ?? const <String>[])
            .any((value) => clean(value) == clean(classKey));
  }

  factory Teacher.fromJson(Map<String, dynamic> json) {
    final rawClasses = json['classes'] ?? json['allowed_classes'];
    List<String>? parsed;
    if (rawClasses == '__ALL__') {
      parsed = null;
    } else if (rawClasses is List) {
      parsed = rawClasses.map((e) => e.toString()).toList();
    } else {
      parsed = const [];
    }
    return Teacher(
      id: (json['id'] ?? json['teacherId'] ?? '').toString().trim().isEmpty
          ? null
          : (json['id'] ?? json['teacherId']).toString(),
      name: (json['name'] ?? json['teacher_name'] ?? '').toString(),
      pin: (json['pin'] ?? '').toString(),
      classes: parsed,
      role: (json['role'] ?? (parsed == null ? 'admin' : 'teacher')).toString(),
      loginEmail: (json['loginEmail'] ?? json['login_email'] ?? '')
              .toString()
              .trim()
              .isEmpty
          ? null
          : (json['loginEmail'] ?? json['login_email']).toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        'pin': pin,
        'classes': classes ?? '__ALL__',
        'role': role,
        if (loginEmail != null) 'loginEmail': loginEmail,
      };
}

enum Category { sc, st, obc, other }

extension CategoryX on Category {
  String get apiKey {
    switch (this) {
      case Category.sc:
        return 'SC';
      case Category.st:
        return 'ST';
      case Category.obc:
        return 'OBC';
      case Category.other:
        return 'OTHER';
    }
  }

  String get shortLabel {
    switch (this) {
      case Category.sc:
        return '\u0A85. \u0A9C\u0ABE.'; // અ. જા.
      case Category.st:
        return '\u0A85. \u0A9C. \u0A9C\u0ABE.'; // અ. જ. જા.
      case Category.obc:
        return '\u0AAC\u0A95\u0ACD\u0AB7\u0AC0\u0AAA\u0A82\u0A9A'; // બક્ષીપંચ
      case Category.other:
        return '\u0A85\u0AA8\u0ACD\u0AAF'; // અન્ય
    }
  }
}

class CategoryCounts {
  final Map<Category, int> _values;

  CategoryCounts([Map<Category, int>? values])
      : _values = values ?? {for (final c in Category.values) c: 0};

  int operator [](Category c) => _values[c] ?? 0;
  void set(Category c, int v) => _values[c] = v;

  int get total => Category.values.fold(0, (sum, c) => sum + this[c]);

  factory CategoryCounts.fromJson(Map<String, dynamic>? json) {
    if (json == null) return CategoryCounts();
    return CategoryCounts({
      for (final c in Category.values) c: _asInt(json[c.apiKey]),
    });
  }

  Map<String, int> toApiParams(String prefix) =>
      {for (final c in Category.values) '$prefix${c.apiKey}': this[c]};

  CategoryCounts copy() => CategoryCounts(Map.of(_values));
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

class AttendanceRecord {
  final CategoryCounts present;
  final CategoryCounts mdm;
  final int breakfastTotal;
  // Optional because legacy APIs/records may not have registration or gender data.
  final CategoryCounts? registered;
  final Map<String, dynamic> genderBreakdown;

  const AttendanceRecord({
    required this.present,
    required this.mdm,
    required this.breakfastTotal,
    this.registered,
    this.genderBreakdown = const <String, dynamic>{},
  });

  factory AttendanceRecord.empty() => AttendanceRecord(
        present: CategoryCounts(),
        mdm: CategoryCounts(),
        breakfastTotal: 0,
        registered: CategoryCounts(),
      );

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      present:
          CategoryCounts.fromJson(json['present'] as Map<String, dynamic>?),
      mdm: CategoryCounts.fromJson(json['mdm'] as Map<String, dynamic>?),
      breakfastTotal: _asInt(json['breakfastTotal']),
      registered: json['registered'] is Map
          ? CategoryCounts.fromJson(
              (json['registered'] as Map).cast<String, dynamic>())
          : null,
      genderBreakdown: json['genderBreakdown'] is Map
          ? (json['genderBreakdown'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{},
    );
  }

  bool get isAllZero =>
      present.total == 0 && mdm.total == 0 && breakfastTotal == 0;
}

class StudentRecord {
  final String id;
  final String rollNumber;
  final String gr;
  final String dd;
  final String mm;
  final String yyyy;
  final String name;
  final String caste;
  final Category category;
  final String gender;
  final String enrollSchool;
  final String enrollClass;
  final String mobile;
  final bool present;
  final bool mdm;
  final bool breakfast;
  final int sheetRow;

  final String motherName;
  final String birthPlace;
  final String dobWords;
  final String lastSchool;
  final String enrollSchClass;
  final String enrollSchClassWords;
  final String nameEn;
  final String casteEn;
  final String catEn;
  final String motherEn;
  final String birthPlaceEn;
  final String dobEn;
  final String lastSchoolEn;
  final String enrollSchClassEn;
  final String enrollSchClassWordsEn;

  final String uid;
  final String pen;
  final String scholarshipDone;
  final String scholarshipReason;
  final String scholarshipOther;
  final String isDivyang;
  final String aadhaar;
  final String nameAsAadhaar;
  final String dobAsAadhaar;
  final String bankName;
  final String bankBranch;
  final String nameAsPassbook;
  final String accountNumber;
  final String ifscCode;
  final String rationCardType;
  final String rationCardNo;
  final Map<String, String> customFields;

  const StudentRecord({
    required this.id,
    required this.rollNumber,
    this.gr = '',
    this.dd = '',
    this.mm = '',
    this.yyyy = '',
    required this.name,
    this.caste = '',
    required this.category,
    this.gender = 'UNSPECIFIED',
    this.enrollSchool = '',
    this.enrollClass = '',
    required this.mobile,
    this.present = false,
    this.mdm = false,
    this.breakfast = false,
    this.sheetRow = 0,
    this.motherName = '',
    this.birthPlace = '',
    this.dobWords = '',
    this.lastSchool = '',
    this.enrollSchClass = '',
    this.enrollSchClassWords = '',
    this.nameEn = '',
    this.casteEn = '',
    this.catEn = '',
    this.motherEn = '',
    this.birthPlaceEn = '',
    this.dobEn = '',
    this.lastSchoolEn = '',
    this.enrollSchClassEn = '',
    this.enrollSchClassWordsEn = '',
    this.uid = '',
    this.pen = '',
    this.scholarshipDone = 'ના',
    this.scholarshipReason = '',
    this.scholarshipOther = '',
    this.isDivyang = 'ના',
    this.aadhaar = '',
    this.nameAsAadhaar = '',
    this.dobAsAadhaar = '',
    this.bankName = '',
    this.bankBranch = '',
    this.nameAsPassbook = '',
    this.accountNumber = '',
    this.ifscCode = '',
    this.rationCardType = '',
    this.rationCardNo = '',
    this.customFields = const {},
  });

  StudentRecord copyWith({
    String? id,
    String? rollNumber,
    String? gr,
    String? dd,
    String? mm,
    String? yyyy,
    String? name,
    String? caste,
    Category? category,
    String? gender,
    String? enrollSchool,
    String? enrollClass,
    String? mobile,
    bool? present,
    bool? mdm,
    bool? breakfast,
    int? sheetRow,
    String? motherName,
    String? birthPlace,
    String? dobWords,
    String? lastSchool,
    String? enrollSchClass,
    String? enrollSchClassWords,
    String? nameEn,
    String? casteEn,
    String? catEn,
    String? motherEn,
    String? birthPlaceEn,
    String? dobEn,
    String? lastSchoolEn,
    String? enrollSchClassEn,
    String? enrollSchClassWordsEn,
    String? uid,
    String? pen,
    String? scholarshipDone,
    String? scholarshipReason,
    String? scholarshipOther,
    String? isDivyang,
    String? aadhaar,
    String? nameAsAadhaar,
    String? dobAsAadhaar,
    String? bankName,
    String? bankBranch,
    String? nameAsPassbook,
    String? accountNumber,
    String? ifscCode,
    String? rationCardType,
    String? rationCardNo,
    Map<String, String>? customFields,
  }) {
    return StudentRecord(
      id: id ?? this.id,
      rollNumber: rollNumber ?? this.rollNumber,
      gr: gr ?? this.gr,
      dd: dd ?? this.dd,
      mm: mm ?? this.mm,
      yyyy: yyyy ?? this.yyyy,
      name: name ?? this.name,
      caste: caste ?? this.caste,
      category: category ?? this.category,
      gender: gender ?? this.gender,
      enrollSchool: enrollSchool ?? this.enrollSchool,
      enrollClass: enrollClass ?? this.enrollClass,
      mobile: mobile ?? this.mobile,
      present: present ?? this.present,
      mdm: mdm ?? this.mdm,
      breakfast: breakfast ?? this.breakfast,
      sheetRow: sheetRow ?? this.sheetRow,
      motherName: motherName ?? this.motherName,
      birthPlace: birthPlace ?? this.birthPlace,
      dobWords: dobWords ?? this.dobWords,
      lastSchool: lastSchool ?? this.lastSchool,
      enrollSchClass: enrollSchClass ?? this.enrollSchClass,
      enrollSchClassWords: enrollSchClassWords ?? this.enrollSchClassWords,
      nameEn: nameEn ?? this.nameEn,
      casteEn: casteEn ?? this.casteEn,
      catEn: catEn ?? this.catEn,
      motherEn: motherEn ?? this.motherEn,
      birthPlaceEn: birthPlaceEn ?? this.birthPlaceEn,
      dobEn: dobEn ?? this.dobEn,
      lastSchoolEn: lastSchoolEn ?? this.lastSchoolEn,
      enrollSchClassEn: enrollSchClassEn ?? this.enrollSchClassEn,
      enrollSchClassWordsEn:
          enrollSchClassWordsEn ?? this.enrollSchClassWordsEn,
      uid: uid ?? this.uid,
      pen: pen ?? this.pen,
      scholarshipDone: scholarshipDone ?? this.scholarshipDone,
      scholarshipReason: scholarshipReason ?? this.scholarshipReason,
      scholarshipOther: scholarshipOther ?? this.scholarshipOther,
      isDivyang: isDivyang ?? this.isDivyang,
      aadhaar: aadhaar ?? this.aadhaar,
      nameAsAadhaar: nameAsAadhaar ?? this.nameAsAadhaar,
      dobAsAadhaar: dobAsAadhaar ?? this.dobAsAadhaar,
      bankName: bankName ?? this.bankName,
      bankBranch: bankBranch ?? this.bankBranch,
      nameAsPassbook: nameAsPassbook ?? this.nameAsPassbook,
      accountNumber: accountNumber ?? this.accountNumber,
      ifscCode: ifscCode ?? this.ifscCode,
      rationCardType: rationCardType ?? this.rationCardType,
      rationCardNo: rationCardNo ?? this.rationCardNo,
      customFields: customFields ?? this.customFields,
    );
  }

  factory StudentRecord.fromJson(Map<String, dynamic> json) {
    final rawCategory = (json['category'] ?? 'OTHER').toString().toUpperCase();
    Category cat = Category.other;
    if (rawCategory == 'SC')
      cat = Category.sc;
    else if (rawCategory == 'ST')
      cat = Category.st;
    else if (rawCategory == 'OBC') cat = Category.obc;

    Map<String, String> cFields = {};
    if (json['customFields'] is Map) {
      (json['customFields'] as Map).forEach((key, value) {
        cFields[key.toString()] = value.toString();
      });
    }

    return StudentRecord(
      id: (json['id'] ?? '').toString(),
      rollNumber: (json['rollNumber'] ?? '').toString(),
      gr: (json['gr'] ?? '').toString(),
      dd: (json['dd'] ?? '').toString(),
      mm: (json['mm'] ?? '').toString(),
      yyyy: (json['yyyy'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      caste: (json['caste'] ?? '').toString(),
      category: cat,
      gender: (json['gender'] ?? 'UNSPECIFIED').toString().toUpperCase(),
      enrollSchool: (json['enrollSchool'] ?? '').toString(),
      enrollClass: (json['enrollClass'] ?? '').toString(),
      mobile: (json['mobile'] ?? '').toString(),
      present: json['present'] == true,
      mdm: json['mdm'] == true,
      breakfast: json['breakfast'] == true,
      sheetRow: _asInt(json['sheetRow']),
      motherName: (json['motherName'] ?? '').toString(),
      birthPlace: (json['birthPlace'] ?? '').toString(),
      dobWords: (json['dobWords'] ?? '').toString(),
      lastSchool: (json['lastSchool'] ?? '').toString(),
      enrollSchClass: (json['enrollSchClass'] ?? '').toString(),
      enrollSchClassWords: (json['enrollSchClassWords'] ?? '').toString(),
      nameEn: (json['nameEn'] ?? '').toString(),
      casteEn: (json['casteEn'] ?? '').toString(),
      catEn: (json['catEn'] ?? '').toString(),
      motherEn: (json['motherEn'] ?? '').toString(),
      birthPlaceEn: (json['birthPlaceEn'] ?? '').toString(),
      dobEn: (json['dobEn'] ?? '').toString(),
      lastSchoolEn: (json['lastSchoolEn'] ?? '').toString(),
      enrollSchClassEn: (json['enrollSchClassEn'] ?? '').toString(),
      enrollSchClassWordsEn: (json['enrollSchClassWordsEn'] ?? '').toString(),
      uid: (json['uid'] ?? '').toString(),
      pen: (json['pen'] ?? '').toString(),
      scholarshipDone: (json['scholarshipDone'] ?? 'ના').toString(),
      scholarshipReason: (json['scholarshipReason'] ?? '').toString(),
      scholarshipOther: (json['scholarshipOther'] ?? '').toString(),
      isDivyang: const {'TRUE', 'YES', '1', 'T', 'હા'}.contains(
              '${json['isDivyang'] ?? json['is_divyang'] ?? 'ના'}'
                  .trim()
                  .toUpperCase())
          ? 'હા'
          : 'ના',
      aadhaar: '',
      nameAsAadhaar: '',
      dobAsAadhaar: '',
      bankName: (json['bankName'] ?? '').toString(),
      bankBranch: (json['bankBranch'] ?? '').toString(),
      nameAsPassbook: (json['nameAsPassbook'] ?? '').toString(),
      accountNumber: (json['accountNumber'] ?? '').toString(),
      ifscCode: (json['ifscCode'] ?? '').toString(),
      rationCardType: '',
      rationCardNo: '',
      customFields: cFields,
    );
  }

  Map<String, dynamic> toJson() => {
        'sheetRow': sheetRow,
        'rollNumber': rollNumber,
        'gr': gr,
        'dd': dd,
        'mm': mm,
        'yyyy': yyyy,
        'name': name,
        'caste': caste,
        'category': category.apiKey,
        'gender': gender,
        'enrollSchool': enrollSchool,
        'enrollClass': enrollClass,
        'mobile': mobile,
        'motherName': motherName,
        'birthPlace': birthPlace,
        'dobWords': dobWords,
        'lastSchool': lastSchool,
        'enrollSchClass': enrollSchClass,
        'enrollSchClassWords': enrollSchClassWords,
        'nameEn': nameEn,
        'casteEn': casteEn,
        'catEn': catEn,
        'motherEn': motherEn,
        'birthPlaceEn': birthPlaceEn,
        'dobEn': dobEn,
        'lastSchoolEn': lastSchoolEn,
        'enrollSchClassEn': enrollSchClassEn,
        'enrollSchClassWordsEn': enrollSchClassWordsEn,
        'uid': uid,
        'pen': pen,
        'scholarshipDone': scholarshipDone,
        'scholarshipReason': scholarshipReason,
        'scholarshipOther': scholarshipOther,
        'isDivyang': isDivyang,
        'bankName': bankName,
        'bankBranch': bankBranch,
        'nameAsPassbook': nameAsPassbook,
        'accountNumber': accountNumber,
        'ifscCode': ifscCode,
        'customFields': customFields,
      };
}

class RowData {
  final CategoryCounts registered;
  final AttendanceRecord? attendance;
  final List<StudentRecord> students;
  final bool studentDetailsSaved;
  final String attendanceMode;
  final Map<String, dynamic> genderBreakdown;

  const RowData({
    required this.registered,
    required this.attendance,
    this.students = const [],
    this.studentDetailsSaved = false,
    this.attendanceMode = 'none',
    this.genderBreakdown = const {},
  });
}

class Holiday {
  final String date;
  final String reason;
  const Holiday({required this.date, required this.reason});
}

class AdminMessage {
  final String date;
  final String message;
  const AdminMessage({required this.date, required this.message});

  factory AdminMessage.fromJson(Map<String, dynamic> json) => AdminMessage(
        date: (json['date'] ?? '').toString(),
        message: (json['message'] ?? '').toString(),
      );
}

// ============================================================
// RESULT SHEET MODELS (પરિણામ પત્રક)
// ============================================================

class SubjectMarks {
  final int patrakA; // પત્રક A સતત / રચનાત્મક મૂલ્યાંકન (out of 40)
  final int satrant; // સત્રાંત મૂલ્યાંકન (out of 40)
  final int swaAdhyayan; // સ્વ-અધ્યયન (out of 20)
  /// Optional Semester-1 total entered directly out of 100 when the school
  /// does not maintain the 40/40/20 breakup. Null means component entry.
  final int? directTotal;

  /// True when this subject uses a single first-semester score out of 100.
  /// Kept even before a mark is entered so empty students' result cells can
  /// still be merged consistently in Excel/PDF output.
  final bool directMode;

  /// True when the student was absent ("AB") in the Satrant examination.
  /// Only applies to Satrant exam marks, not Rachnatmak or Swa-Adhyayan.
  final bool satrantAbsent;

  const SubjectMarks({
    this.patrakA = 0,
    this.satrant = 0,
    this.swaAdhyayan = 0,
    this.directTotal,
    this.directMode = false,
    this.satrantAbsent = false,
  });

  bool get usesDirectTotal => directMode || directTotal != null;
  int get total => usesDirectTotal
      ? (directTotal ?? 0)
      : (patrakA + (satrantAbsent ? 0 : satrant) + swaAdhyayan);

  SubjectMarks copyWith({
    int? patrakA,
    int? satrant,
    int? swaAdhyayan,
    int? directTotal,
    bool? directMode,
    bool? satrantAbsent,
    bool clearDirectTotal = false,
  }) {
    return SubjectMarks(
      patrakA: patrakA ?? this.patrakA,
      satrant: satrant ?? this.satrant,
      swaAdhyayan: swaAdhyayan ?? this.swaAdhyayan,
      directTotal: clearDirectTotal ? null : (directTotal ?? this.directTotal),
      directMode: clearDirectTotal
          ? false
          : (directMode ?? (this.directMode || directTotal != null)),
      satrantAbsent: satrantAbsent ?? this.satrantAbsent,
    );
  }

  factory SubjectMarks.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SubjectMarks();
    final rawDirect = json['directTotal'] ?? json['direct_total'];
    final rawS = json['s'];
    final isAb = json['satrantAbsent'] == true ||
        json['satrant_absent'] == true ||
        '${rawS ?? ""}'.trim().toUpperCase() == 'AB' ||
        _asInt(rawS) < 0;
    return SubjectMarks(
      patrakA: _asInt(json['a']),
      satrant: isAb ? 0 : _asInt(rawS),
      swaAdhyayan: _asInt(json['sw']),
      directTotal: rawDirect == null ? null : _asInt(rawDirect),
      directMode: json['directMode'] == true ||
          json['direct_mode'] == true ||
          rawDirect != null,
      satrantAbsent: isAb,
    );
  }
}

/// Randomly distributes [totalMarks] across 40 sentences (each 0..[maxPerSentence])
/// ensuring Sentences 15 to 18 (indices 14..17: "ક્ષેત્ર-૩: સાહિત્ય") always get
/// lower marks than the other 36 sentences while summing to [totalMarks].
List<int> generateRandom40Sentences(int totalMarks, int maxPerSentence) {
  const count = 40;
  final maxTotal = count * maxPerSentence;
  final target = totalMarks.clamp(0, maxTotal);

  if (target == 0) return List<int>.filled(count, 0);
  if (target == maxTotal) return List<int>.filled(count, maxPerSentence);

  final rng = math.Random();
  final avg = target / count;

  // Sentences 15 to 18 (0-based indices 14, 15, 16, 17 -> ક્ષેત્ર-૩: સાહિત્ય)
  // get lower marks than the remaining 36 sentences:
  // - For Std 6-8 (max 10): typically 5..7 when others are 8..9
  // - For Std 3-5 (max 5) : typically 2..3 when others are 4..5
  final int litDrop = maxPerSentence == 10 ? 2 : 1;
  final int litMax = math.max(1, math.min(maxPerSentence - 1, avg.floor() - 1));
  final int litMin = math.max(1, litMax - litDrop);

  final list = List<int>.filled(count, 0);
  int litSum = 0;
  for (int i = 14; i <= 17; i++) {
    list[i] = litMin + rng.nextInt(litMax - litMin + 1);
    litSum += list[i];
  }

  // Remaining 36 sentences make up the rest of the total with higher marks
  final remTarget = (target - litSum).clamp(0, 36 * maxPerSentence);
  final otherAvg = remTarget / 36.0;
  final spread = maxPerSentence == 10 ? 1 : 1;
  final int otherMin =
      math.max(litMax + 1, otherAvg.floor() - spread).clamp(1, maxPerSentence);
  final int otherMax =
      math.min(maxPerSentence, math.max(otherMin, otherAvg.ceil() + spread));

  for (int i = 0; i < count; i++) {
    if (i >= 14 && i <= 17) continue;
    list[i] = otherMin + rng.nextInt(otherMax - otherMin + 1);
  }

  int sum = list.fold(0, (a, b) => a + b);

  // 1. First adjust only the other 36 sentences so 15..18 stay strictly lower
  int guard = 0;
  while (sum != target && guard < 3000) {
    guard++;
    int idx = rng.nextInt(count);
    if (idx >= 14 && idx <= 17) continue; // Keep sentences 15..18 lower

    if (sum < target) {
      final cap = guard < 1800 ? otherMax : maxPerSentence;
      if (list[idx] < cap) {
        list[idx]++;
        sum++;
      }
    } else {
      final floor =
          guard < 1800 ? otherMin : (litMax + 1).clamp(0, maxPerSentence);
      if (list[idx] > floor) {
        list[idx]--;
        sum--;
      }
    }
  }

  // 2. Fallback for extreme totals (e.g. near 0 or near 400/200)
  guard = 0;
  while (sum != target && guard < 2000) {
    guard++;
    final idx = rng.nextInt(count);
    if (sum < target && list[idx] < maxPerSentence) {
      list[idx]++;
      sum++;
    } else if (sum > target && list[idx] > 0) {
      list[idx]--;
      sum--;
    }
  }

  return list;
}

class ResultStudentRow {
  int sheetRow;
  String studentId;
  String roll; // Col A
  String name; // Col B
  String category; // Col C
  String
      gender; // Stored in tenant StudentGender metadata, not shifted into legacy columns
  String dd; // Col D
  String mm; // Col E
  String yyyy; // Col F
  String uid; // Col G
  String pen; // Col H
  String mobile; // Col I
  String fatherName; // Col J
  String motherName; // Col K
  String address; // Col L
  bool studiedInSem2; // Col M (true = Yes, false = No -> "નામ કમી" in Sem 2)
  String gr; // Col N

  // નવા ઉમેરેલા ચલો (સર્ટિફિકેટ માટે)
  String caste;
  String birthPlace;
  String dobWords;
  String lastSchool;
  int presentDays; // Col O (Sem 1 Present Days)
  int presentDays2; // Col P (Sem 2 Present Days)
  String standard; // Col Q (Class Standard)
  bool isDivyang; // Col R (YES = 20% Passing, NO = 35% Passing)
  final Map<String, SubjectMarks> sem1;
  final Map<String, SubjectMarks> sem2;
  int vv1;
  int vv2;
  List<int> vv1Sentences;
  List<int> vv2Sentences;

  ResultStudentRow({
    required this.sheetRow,
    this.studentId = '',
    required this.roll,
    required this.name,
    required this.gr,
    required this.dd,
    required this.mm,
    required this.yyyy,
    required this.category,
    this.gender = 'UNSPECIFIED',
    required this.presentDays,
    this.presentDays2 = 0,
    this.standard = '',
    this.isDivyang = false,
    this.uid = '',
    this.pen = '',
    this.mobile = '',
    this.fatherName = '',
    this.motherName = '',
    this.address = '',
    this.studiedInSem2 = true,
    this.caste = '',
    this.birthPlace = '',
    this.dobWords = '',
    this.lastSchool = '',
    required this.sem1,
    required this.sem2,
    this.vv1 = 0,
    this.vv2 = 0,
    List<int>? vv1Sentences,
    List<int>? vv2Sentences,
  })  : vv1Sentences = vv1Sentences ?? List<int>.filled(40, 0),
        vv2Sentences = vv2Sentences ?? List<int>.filled(40, 0);

  int get vvAvgBothSem {
    if (!studiedInSem2) return vv1;
    if (vv1 == 0 && vv2 == 0) return 0;
    return ((vv1 + vv2) / 2).round();
  }

  String get dobFormatted {
    if (dd.isEmpty && mm.isEmpty && yyyy.isEmpty) return '';
    return '${dd.padLeft(2, '0')}/${mm.padLeft(2, '0')}/$yyyy';
  }

  factory ResultStudentRow.fromJson(Map<String, dynamic> json) {
    Map<String, SubjectMarks> parseSem(dynamic raw) {
      if (raw is! Map) return {};
      return raw.map((k, v) => MapEntry(
            k.toString(),
            SubjectMarks.fromJson(v is Map ? v.cast<String, dynamic>() : null),
          ));
    }

    List<int>? parseSentences(dynamic raw) {
      if (raw is! List || raw.length != 40) return null;
      return raw.map((e) => _asInt(e)).toList();
    }

    final rawSem2Flag = json['studiedInSem2'];
    final studiedSem2 = rawSem2Flag == null
        ? true
        : (rawSem2Flag == true ||
            rawSem2Flag.toString().toLowerCase() == 'yes' ||
            rawSem2Flag.toString().toLowerCase() == 'true');

    return ResultStudentRow(
      sheetRow: _asInt(json['sheetRow']),
      studentId: (json['studentId'] ?? json['id'] ?? '').toString(),
      roll: (json['roll'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      gr: (json['gr'] ?? '').toString(),
      dd: (json['dd'] ?? '').toString(),
      mm: (json['mm'] ?? '').toString(),
      yyyy: (json['yyyy'] ?? '').toString(),
      category: (json['category'] ?? 'બક્ષીપંચ').toString(),
      gender: (json['gender'] ?? 'UNSPECIFIED').toString().toUpperCase(),
      presentDays: _asInt(json['presentDays']),
      presentDays2: _asInt(json['presentDays2']),
      standard: (json['standard'] ?? '').toString(),
      isDivyang: json['isDivyang'] == true ||
          json['isDivyang'].toString().toLowerCase() == 'yes' ||
          json['isDivyang'].toString().toLowerCase() == 'true',
      uid: (json['uid'] ?? '').toString(),
      pen: (json['pen'] ?? '').toString(),
      mobile: (json['mobile'] ?? '').toString(),
      fatherName: (json['fatherName'] ?? '').toString(),
      motherName: (json['motherName'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      studiedInSem2: studiedSem2,
      caste: (json['caste'] ?? '').toString(),
      birthPlace: (json['birthPlace'] ?? '').toString(),
      dobWords: (json['dobWords'] ?? '').toString(),
      lastSchool: (json['lastSchool'] ?? '').toString(),
      sem1: parseSem(json['sem1']),
      sem2: parseSem(json['sem2']),
      vv1: _asInt(json['vv1']),
      vv2: _asInt(json['vv2']),
      vv1Sentences: parseSentences(json['vv1Sentences']),
      vv2Sentences: parseSentences(json['vv2Sentences']),
    );
  }
}

class ResultSheetData {
  final String className;
  final List<String> subjects;
  final List<ResultStudentRow> students;
  final String teacherName;
  final String firstSemResultDate;
  final String resultDate;
  final String academicYear;
  final String frontPageDistrict;
  final String frontPageEducationAuthority;
  final String frontPageVillage;
  final String frontPageTaluka;
  final String frontPagePayCenter;
  final String frontPageCrc;
  final List<String> vvSentences;
  final bool sem1Locked; // નવું
  final bool sem2Locked; // નવું
  final bool isClassTeacher;
  final List<String> assignedSubjects;

  static String defaultSecondSemResultDateForNow([DateTime? now]) {
    final dt = now ?? DateTime.now();
    final endYear = dt.month >= 6 ? dt.year + 1 : dt.year;
    return '30/04/$endYear';
  }

  static String defaultFirstSemResultDateForNow([DateTime? now]) {
    final dt = now ?? DateTime.now();
    final startYear = dt.month >= 6 ? dt.year : dt.year - 1;
    return '15/11/$startYear';
  }

  const ResultSheetData({
    required this.className,
    required this.subjects,
    required this.students,
    this.teacherName = '',
    this.firstSemResultDate = '15/11/2026',
    this.resultDate = '30/04/2027',
    this.academicYear = '2026 - 27',
    this.frontPageDistrict = '',
    this.frontPageEducationAuthority = '',
    this.frontPageVillage = '',
    this.frontPageTaluka = '',
    this.frontPagePayCenter = '',
    this.frontPageCrc = '',
    this.vvSentences = const [],
    this.sem1Locked = false, // નવું
    this.sem2Locked = false, // નવું
    this.isClassTeacher = false,
    this.assignedSubjects = const <String>[],
  });
}

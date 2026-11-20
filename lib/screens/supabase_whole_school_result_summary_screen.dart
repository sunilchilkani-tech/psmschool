import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:excel_community/excel_community.dart' as ec;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pmshri_attendance/services/firebase_backend_client.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/class_label.dart';
import '../services/rojmel_html_printer.dart';
import '../services/school_class_order.dart';
import '../services/school_type.dart';
import '../services/template_print/school_logo_loader.dart';
import '../services/xlsx_sanitizer.dart';

class _StudentEvalSummary {
  const _StudentEvalSummary({
    required this.category, // 'SC', 'ST', 'OBC', 'OTHER'
    required this.gender, // 'BOYS', 'GIRLS'
    required this.appeared,
    required this.passed,
    required this.grade, // 'A', 'B', 'C', 'D', 'E', or ''
  });

  final String category;
  final String gender;
  final bool appeared;
  final bool passed;
  final String grade;
}

class _RankerStudentEntry {
  _RankerStudentEntry({
    required this.entryKey,
    required this.studentId,
    required this.studentName,
    required this.rollNo,
    required this.classId,
    required this.standardKey,
    required this.standardNum,
    required this.standardDisplay,
    required this.sectionDisplay,
    required this.classWithSection,
    required this.totalMarks,
    required this.obtainedMarks,
    required this.percentage,
    required this.rank,
    required this.passed,
  });

  final String entryKey;
  final String studentId;
  String studentName;
  final int rollNo;
  final String classId;
  final String standardKey;
  final int standardNum;
  final String standardDisplay;
  final String sectionDisplay;
  String classWithSection;
  int totalMarks;
  int obtainedMarks;
  double percentage;
  int rank; // 1, 2, or 3
  final bool passed;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'entryKey': entryKey,
        'studentId': studentId,
        'studentName': studentName,
        'rollNo': rollNo,
        'classId': classId,
        'standardKey': standardKey,
        'standardNum': standardNum,
        'standardDisplay': standardDisplay,
        'sectionDisplay': sectionDisplay,
        'classWithSection': classWithSection,
        'totalMarks': totalMarks,
        'obtainedMarks': obtainedMarks,
        'percentage': percentage,
        'rank': rank,
        'passed': passed,
      };

  factory _RankerStudentEntry.fromJson(Map<String, dynamic> json) {
    final tot = int.tryParse('${json['totalMarks'] ?? 0}') ?? 0;
    final obt = int.tryParse('${json['obtainedMarks'] ?? 0}') ?? 0;
    final pct = double.tryParse('${json['percentage'] ?? ''}') ??
        (tot > 0 ? (obt * 100.0) / tot : 0.0);
    return _RankerStudentEntry(
      entryKey: '${json['entryKey'] ?? ''}',
      studentId: '${json['studentId'] ?? ''}',
      studentName: '${json['studentName'] ?? ''}'.trim(),
      rollNo: int.tryParse('${json['rollNo'] ?? 0}') ?? 0,
      classId: '${json['classId'] ?? ''}',
      standardKey: '${json['standardKey'] ?? ''}',
      standardNum: int.tryParse('${json['standardNum'] ?? 0}') ?? 0,
      standardDisplay: '${json['standardDisplay'] ?? ''}',
      sectionDisplay: '${json['sectionDisplay'] ?? ''}',
      classWithSection: '${json['classWithSection'] ?? ''}'.trim(),
      totalMarks: tot,
      obtainedMarks: obt,
      percentage: pct,
      rank: (int.tryParse('${json['rank'] ?? 1}') ?? 1).clamp(1, 3),
      passed: json['passed'] != false,
    );
  }
}

class _ClassSectionResultSummary {
  _ClassSectionResultSummary({
    required this.classId,
    required this.classLabel,
    required this.standardKey,
    required this.standardNum,
    required this.standardDisplay,
    required this.sectionDisplay,
    required this.sortOrder,
  });

  final String classId;
  final String classLabel;
  final String standardKey;
  final int standardNum; // 1..8 (0 for Balvatika)
  final String standardDisplay;
  final String sectionDisplay;
  final int sortOrder;

  bool hasMarksInserted = false;
  bool hasAdminOverride = false;
  String remarks = '';

  final Map<String, int> catRegistered = <String, int>{
    'SC': 0,
    'ST': 0,
    'OBC': 0,
    'OTHER': 0,
  };

  final Map<String, Map<String, int>> catGenderRegistered =
      <String, Map<String, int>>{
    for (final c in const <String>['SC', 'ST', 'OBC', 'OTHER'])
      c: <String, int>{'BOYS': 0, 'GIRLS': 0},
  };

  final Map<String, int> gradeCounts = <String, int>{
    'A': 0,
    'B': 0,
    'C': 0,
    'D': 0,
    'E': 0,
  };

  final Map<String, Map<String, Map<String, int>>> catGradeGenderCounts =
      <String, Map<String, Map<String, int>>>{
    for (final c in const <String>['SC', 'ST', 'OBC', 'OTHER'])
      c: <String, Map<String, int>>{
        for (final g in const <String>['A', 'B', 'C', 'D', 'E'])
          g: <String, int>{'BOYS': 0, 'GIRLS': 0},
      },
  };

  int registeredTotal = 0;
  int appearedTotal = 0;
  int absentTotal = 0;
  int passedTotal = 0;
  int failedTotal = 0;

  double get resultPercent =>
      appearedTotal > 0 ? (passedTotal * 100.0) / appearedTotal : 0.0;

  void addStudent(_StudentEvalSummary s) {
    final c = catRegistered.containsKey(s.category) ? s.category : 'OTHER';
    final gen = s.gender == 'GIRLS' ? 'GIRLS' : 'BOYS';
    catRegistered[c] = (catRegistered[c] ?? 0) + 1;
    catGenderRegistered[c]![gen] = (catGenderRegistered[c]![gen] ?? 0) + 1;
    registeredTotal++;

    if (s.appeared) {
      appearedTotal++;
      if (s.passed) {
        passedTotal++;
      } else {
        failedTotal++;
      }
      final g = gradeCounts.containsKey(s.grade) ? s.grade : 'E';
      gradeCounts[g] = (gradeCounts[g] ?? 0) + 1;
      catGradeGenderCounts[c]![g]![gen] =
          (catGradeGenderCounts[c]![g]![gen] ?? 0) + 1;
    } else {
      absentTotal++;
    }
  }

  void applyAdminOverride(Map<String, dynamic> ov, String schoolType) {
    hasAdminOverride = true;
    hasMarksInserted = true;
    if (ov['catRegistered'] is Map) {
      final m = Map<String, dynamic>.from(ov['catRegistered'] as Map);
      int sumReg = 0;
      for (final c in const <String>['SC', 'ST', 'OBC', 'OTHER']) {
        final v = int.tryParse('${m[c] ?? catRegistered[c] ?? 0}') ?? 0;
        catRegistered[c] = v;
        sumReg += v;
        final curB = catGenderRegistered[c]!['BOYS'] ?? 0;
        final curG = catGenderRegistered[c]!['GIRLS'] ?? 0;
        if (curB + curG != v) {
          if (schoolType == 'girls') {
            catGenderRegistered[c]!['BOYS'] = 0;
            catGenderRegistered[c]!['GIRLS'] = v;
          } else if (schoolType == 'boys' || curG == 0) {
            catGenderRegistered[c]!['BOYS'] = v;
            catGenderRegistered[c]!['GIRLS'] = 0;
          } else {
            final b = ((v * curB) / (curB + curG)).round().clamp(0, v);
            catGenderRegistered[c]!['BOYS'] = b;
            catGenderRegistered[c]!['GIRLS'] = v - b;
          }
        }
      }
      registeredTotal = sumReg;
    }
    if (ov.containsKey('registeredTotal')) {
      registeredTotal =
          int.tryParse('${ov['registeredTotal']}') ?? registeredTotal;
    }
    if (ov.containsKey('appearedTotal')) {
      appearedTotal = int.tryParse('${ov['appearedTotal']}') ?? appearedTotal;
    }
    if (ov.containsKey('absentTotal')) {
      absentTotal = int.tryParse('${ov['absentTotal']}') ?? absentTotal;
    } else {
      absentTotal = math.max(0, registeredTotal - appearedTotal);
    }
    if (ov.containsKey('passedTotal')) {
      passedTotal = int.tryParse('${ov['passedTotal']}') ?? passedTotal;
    }
    if (ov.containsKey('failedTotal')) {
      failedTotal = int.tryParse('${ov['failedTotal']}') ?? failedTotal;
    } else {
      failedTotal = math.max(0, appearedTotal - passedTotal);
    }
    if (ov['gradeCounts'] is Map) {
      final gm = Map<String, dynamic>.from(ov['gradeCounts'] as Map);
      for (final g in const <String>['A', 'B', 'C', 'D', 'E']) {
        if (gm.containsKey(g)) {
          final gv = int.tryParse('${gm[g]}') ?? 0;
          gradeCounts[g] = gv;
        }
      }
      for (final g in const <String>['A', 'B', 'C', 'D', 'E']) {
        final targetG = gradeCounts[g] ?? 0;
        int curSum = 0;
        for (final c in const <String>['SC', 'ST', 'OBC', 'OTHER']) {
          curSum += (catGradeGenderCounts[c]![g]!['BOYS'] ?? 0) +
              (catGradeGenderCounts[c]![g]!['GIRLS'] ?? 0);
        }
        if (curSum != targetG) {
          for (final c in const <String>['SC', 'ST', 'OBC', 'OTHER']) {
            catGradeGenderCounts[c]![g]!['BOYS'] = 0;
            catGradeGenderCounts[c]![g]!['GIRLS'] = 0;
          }
          int rem = targetG;
          final totReg = registeredTotal > 0 ? registeredTotal : 1;
          for (final c in const <String>['SC', 'ST', 'OBC', 'OTHER']) {
            if (rem <= 0) break;
            final cReg = catRegistered[c] ?? 0;
            if (cReg <= 0) continue;
            final share = c == 'OTHER'
                ? rem
                : ((targetG * cReg) / totReg).round().clamp(0, rem);
            final bReg = catGenderRegistered[c]!['BOYS'] ?? 0;
            final gReg = catGenderRegistered[c]!['GIRLS'] ?? 0;
            if (schoolType == 'girls') {
              catGradeGenderCounts[c]![g]!['GIRLS'] = share;
            } else if (schoolType == 'boys' || gReg == 0) {
              catGradeGenderCounts[c]![g]!['BOYS'] = share;
            } else {
              final bShare =
                  ((share * bReg) / (bReg + gReg)).round().clamp(0, share);
              catGradeGenderCounts[c]![g]!['BOYS'] = bShare;
              catGradeGenderCounts[c]![g]!['GIRLS'] = share - bShare;
            }
            rem -= share;
          }
          if (rem > 0) {
            final defGen = schoolType == 'girls' ? 'GIRLS' : 'BOYS';
            String bestCat = 'OTHER';
            int bestVal = -1;
            for (final c in const <String>['SC', 'ST', 'OBC', 'OTHER']) {
              if ((catRegistered[c] ?? 0) > bestVal) {
                bestVal = catRegistered[c] ?? 0;
                bestCat = c;
              }
            }
            catGradeGenderCounts[bestCat]![g]![defGen] =
                (catGradeGenderCounts[bestCat]![g]![defGen] ?? 0) + rem;
          }
        }
      }
    }
    if (ov.containsKey('remarks')) {
      remarks = '${ov['remarks'] ?? ''}'.trim();
    }
  }

  void mergeFrom(_ClassSectionResultSummary other) {
    if (other.hasMarksInserted) hasMarksInserted = true;
    if (other.hasAdminOverride) hasAdminOverride = true;
    for (final c in const <String>['SC', 'ST', 'OBC', 'OTHER']) {
      catRegistered[c] = (catRegistered[c] ?? 0) + (other.catRegistered[c] ?? 0);
      for (final gen in const <String>['BOYS', 'GIRLS']) {
        catGenderRegistered[c]![gen] =
            (catGenderRegistered[c]![gen] ?? 0) +
                (other.catGenderRegistered[c]?[gen] ?? 0);
      }
      for (final g in const <String>['A', 'B', 'C', 'D', 'E']) {
        for (final gen in const <String>['BOYS', 'GIRLS']) {
          catGradeGenderCounts[c]![g]![gen] =
              (catGradeGenderCounts[c]![g]![gen] ?? 0) +
                  (other.catGradeGenderCounts[c]?[g]?[gen] ?? 0);
        }
      }
    }
    for (final g in const <String>['A', 'B', 'C', 'D', 'E']) {
      gradeCounts[g] = (gradeCounts[g] ?? 0) + (other.gradeCounts[g] ?? 0);
    }
    registeredTotal += other.registeredTotal;
    appearedTotal += other.appearedTotal;
    absentTotal += other.absentTotal;
    passedTotal += other.passedTotal;
    failedTotal += other.failedTotal;
  }
}

class SupabaseWholeSchoolResultSummaryScreen extends StatefulWidget {
  const SupabaseWholeSchoolResultSummaryScreen({
    super.key,
    this.profile = const <String, dynamic>{},
    this.initialSemester = '1',
  });

  final Map<String, dynamic> profile;
  final String initialSemester; // '1', '2', or 'Annual'

  @override
  State<SupabaseWholeSchoolResultSummaryScreen> createState() =>
      _SupabaseWholeSchoolResultSummaryScreenState();
}

class _SupabaseWholeSchoolResultSummaryScreenState
    extends State<SupabaseWholeSchoolResultSummaryScreen> {
  final SupabaseClient _client = Supabase.instance.client;

  bool _loading = true;
  bool _exporting = false;
  bool _generatingPdf = false;
  String? _error;

  String _selectedSemester = '1'; // '1' = પ્રથમ સત્ર, '2' = દ્વિતીય સત્ર, 'Annual' = વાર્ષિક
  String _selectedClassIdForDetail = '__ALL__';
  bool _includeAllClassesInFormat2Print = false;
  bool _onlyMarksInsertedClasses = true; // Default: only marks-inserted classes in 1..8 order

  String _schoolRef = '';
  String _schoolType = 'mixed';
  Uint8List? _schoolLogoBytes;

  // Locked (non-editable) official school fields
  String _lockedSchoolName = '';
  String _lockedUdiseCode = '';

  final TextEditingController _authorityCtrl = TextEditingController();
  final TextEditingController _schoolNameCtrl = TextEditingController();
  final TextEditingController _schoolAddressCtrl = TextEditingController();
  final TextEditingController _academicYearCtrl = TextEditingController();
  final TextEditingController _examNameCtrl = TextEditingController();
  final TextEditingController _resultDateCtrl = TextEditingController();
  final TextEditingController _udiseCtrl = TextEditingController();

  String _sem1DateDefault = '30/10/2026';
  String _sem2DateDefault = '30/04/2027';

  List<Map<String, dynamic>> _gradeRules = <Map<String, dynamic>>[
    <String, dynamic>{'grade_label': 'A', 'minimum_percent': 80.0},
    <String, dynamic>{'grade_label': 'B', 'minimum_percent': 65.0},
    <String, dynamic>{'grade_label': 'C', 'minimum_percent': 50.0},
    <String, dynamic>{'grade_label': 'D', 'minimum_percent': 35.0},
    <String, dynamic>{'grade_label': 'E', 'minimum_percent': 0.0},
  ];

  // Raw loaded school data for instant semester switching
  List<Map<String, dynamic>> _rawClasses = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _rawStudents = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _rawProfiles = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _rawSubjects = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _rawMarks = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _rawSnapshots = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _rawSnapshotMembers = <Map<String, dynamic>>[];

  // Admin manual overrides: key = '$semester|$classId' or '__RANKERS_SEC__|$semester' or '__RANKERS_STD__|$semester'
  Map<String, Map<String, dynamic>> _adminOverrides =
      <String, Map<String, dynamic>>{};

  List<_ClassSectionResultSummary> _allComputedClassSummaries =
      <_ClassSectionResultSummary>[];
  List<_ClassSectionResultSummary> _classSummaries =
      <_ClassSectionResultSummary>[];
  Map<String, List<_ClassSectionResultSummary>> _byStandard =
      <String, List<_ClassSectionResultSummary>>{};
  Map<String, _ClassSectionResultSummary> _standardTotals =
      <String, _ClassSectionResultSummary>{};
  _ClassSectionResultSummary _wholeSchoolTotal = _ClassSectionResultSummary(
    classId: '__TOTAL__',
    classLabel: 'સમગ્ર શાળાનો કુલ',
    standardKey: '__TOTAL__',
    standardNum: 99,
    standardDisplay: 'સમગ્ર શાળાનો કુલ',
    sectionDisplay: '',
    sortOrder: 9999,
  );

  // Format 4 (Section-Wise Top 3 Rankers) & Format 5 (Class-Wise Top 3 Rankers)
  List<_RankerStudentEntry> _sectionWiseRankers = <_RankerStudentEntry>[];
  List<_RankerStudentEntry> _classWiseRankers = <_RankerStudentEntry>[];

  Timer? _headerOverrideSaveTimer;
  static bool _pdfRasterFontLoaded = false;
  static const String _pdfRasterFontFamily = 'NotoSansGujaratiResultPdf';

  @override
  void initState() {
    super.initState();
    _selectedSemester =
        const <String>{'1', '2', 'Annual'}.contains(widget.initialSemester)
            ? widget.initialSemester
            : '1';
    _updateExamLabelAndDateForSemester();
    _loadAllSchoolResultData();
  }

  @override
  void dispose() {
    if (_headerOverrideSaveTimer?.isActive == true) {
      _headerOverrideSaveTimer!.cancel();
      unawaited(_saveAdminOverrides());
    }
    _authorityCtrl.dispose();
    _schoolNameCtrl.dispose();
    _schoolAddressCtrl.dispose();
    _academicYearCtrl.dispose();
    _examNameCtrl.dispose();
    _resultDateCtrl.dispose();
    _udiseCtrl.dispose();
    super.dispose();
  }

  String _text(dynamic v) => '${v ?? ''}'.trim();

  int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    var s = _text(v);
    for (var i = 0; i < guj.length; i++) {
      s = s.replaceAll(guj[i], '$i');
    }
    return int.tryParse(s) ?? 0;
  }

  double _double(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    var s = _text(v);
    for (var i = 0; i < guj.length; i++) {
      s = s.replaceAll(guj[i], '$i');
    }
    return double.tryParse(s) ?? 0.0;
  }

  bool _bool(dynamic v) =>
      v == true ||
      const <String>{'true', '1', 'yes', 't'}.contains(_text(v).toLowerCase());

  String _toGujDigits(String input) {
    const guj = <String>['૦', '૧', '૨', '૩', '૪', '૫', '૬', '૭', '૮', '૯'];
    final sb = StringBuffer();
    for (final r in input.runes) {
      final ch = String.fromCharCode(r);
      final d = int.tryParse(ch);
      sb.write(d != null ? guj[d] : ch);
    }
    return sb.toString();
  }

  void _updateExamLabelAndDateForSemester() {
    final hdrOv = _adminOverrides['__HEADER__|$_selectedSemester'];
    if (hdrOv != null) {
      if (_text(hdrOv['examName']).isNotEmpty) {
        _examNameCtrl.text = _text(hdrOv['examName']);
      }
      if (_text(hdrOv['resultDate']).isNotEmpty) {
        _resultDateCtrl.text = _text(hdrOv['resultDate']);
      }
      if (_text(hdrOv['authority']).isNotEmpty) {
        _authorityCtrl.text = _text(hdrOv['authority']);
      }
      if (_text(hdrOv['schoolAddress']).isNotEmpty) {
        _schoolAddressCtrl.text = _text(hdrOv['schoolAddress']);
      }
      if (_text(hdrOv['academicYear']).isNotEmpty) {
        _academicYearCtrl.text = _text(hdrOv['academicYear']);
      }
      // Always enforce locked School Name & DISE Code
      if (_lockedSchoolName.isNotEmpty) {
        _schoolNameCtrl.text = _lockedSchoolName;
      }
      if (_lockedUdiseCode.isNotEmpty) {
        _udiseCtrl.text = _lockedUdiseCode;
      }
      return;
    }

    if (_selectedSemester == '1') {
      _examNameCtrl.text = 'પ્રથમ સત્રાંત પરીક્ષા';
      if (_sem1DateDefault.isNotEmpty) {
        _resultDateCtrl.text = _toGujDigits(_sem1DateDefault);
      }
    } else if (_selectedSemester == '2') {
      _examNameCtrl.text = 'દ્વિતીય સત્રાંત પરીક્ષા';
      if (_sem2DateDefault.isNotEmpty) {
        _resultDateCtrl.text = _toGujDigits(_sem2DateDefault);
      }
    } else {
      _examNameCtrl.text = 'વાર્ષિક પરીક્ષા (સત્ર ૧ + ૨)';
      if (_sem2DateDefault.isNotEmpty) {
        _resultDateCtrl.text = _toGujDigits(_sem2DateDefault);
      }
    }
    if (_lockedSchoolName.isNotEmpty) {
      _schoolNameCtrl.text = _lockedSchoolName;
    }
    if (_lockedUdiseCode.isNotEmpty) {
      _udiseCtrl.text = _lockedUdiseCode;
    }
  }

  void _recordEditableHeaderOverride() {
    // Enforce locked School Name and DISE Code
    _schoolNameCtrl.text = _lockedSchoolName;
    _udiseCtrl.text = _lockedUdiseCode;
    _adminOverrides['__HEADER__|$_selectedSemester'] = <String, dynamic>{
      'authority': _authorityCtrl.text.trim(),
      'schoolAddress': _schoolAddressCtrl.text.trim(),
      'academicYear': _academicYearCtrl.text.trim(),
      'examName': _examNameCtrl.text.trim(),
      'resultDate': _resultDateCtrl.text.trim(),
    };
    _headerOverrideSaveTimer?.cancel();
    _headerOverrideSaveTimer = Timer(
      const Duration(milliseconds: 900),
      () => unawaited(_saveAdminOverrides()),
    );
  }

  String get _overridePrefsKey =>
      'psm_result_summary_overrides_${_schoolRef.isEmpty ? "default" : _schoolRef}';

  Future<void> _saveAdminOverrides() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_overridePrefsKey, jsonEncode(_adminOverrides));
    } catch (_) {}
    if (_schoolRef.isNotEmpty) {
      try {
        final row = await _client
            .from('school_settings')
            .select('config')
            .eq('school_ref', _schoolRef)
            .maybeSingle();
        final cfg = row?['config'] is Map
            ? Map<String, dynamic>.from(row!['config'] as Map)
            : <String, dynamic>{};
        cfg['result_summary_admin_overrides'] = _adminOverrides;
        await _client.from('school_settings').upsert(<String, dynamic>{
          'school_ref': _schoolRef,
          'config': cfg,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'school_ref');
      } catch (_) {}
    }
  }

  Future<void> _loadAllSchoolResultData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final refVal = await _client.rpc('current_school_ref');
      final schoolRef = _text(refVal);
      if (schoolRef.isEmpty) {
        throw StateError('શાળાનું સેશન મળ્યું નથી. ફરીથી લૉગિન કરો.');
      }
      _schoolRef = schoolRef;

      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        _client.from('schools').select().eq('id', schoolRef).maybeSingle(),
        _client
            .from('school_settings')
            .select()
            .eq('school_ref', schoolRef)
            .maybeSingle(),
        _client
            .from('school_classes')
            .select()
            .eq('school_ref', schoolRef)
            .eq('is_active', true)
            .order('sort_order'),
        _client.from('students').select().eq('school_ref', schoolRef),
        _client
            .from('student_result_profiles')
            .select()
            .eq('school_ref', schoolRef),
        _client
            .from('class_subjects')
            .select()
            .eq('school_ref', schoolRef)
            .eq('is_active', true)
            .order('sort_order'),
        _client
            .from('student_subject_marks')
            .select()
            .eq('school_ref', schoolRef),
        _client
            .from('class_result_settings')
            .select()
            .eq('school_ref', schoolRef),
        _safeQuery('school_result_grade_settings', schoolRef),
        _safeQuery('student_result_roster_snapshots', schoolRef),
        loadSchoolLogoBytes(_client, schoolRef),
      ]);

      final schoolRow = results[0] is Map
          ? Map<String, dynamic>.from(results[0] as Map)
          : <String, dynamic>{};
      final settingsRow = results[1] is Map
          ? Map<String, dynamic>.from(results[1] as Map)
          : <String, dynamic>{};
      final classesRaw = (results[2] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final studentsRaw = (results[3] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final profilesRaw = (results[4] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final subjectsRaw = (results[5] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final marksRaw = (results[6] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final classResultSettingsRaw = (results[7] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final gradeSettingsRaw = (results[8] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final snapshotsRaw = (results[9] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      Uint8List? logoBytes = results[10] as Uint8List?;

      final currentSnapshotIds = snapshotsRaw
          .where((s) => s['is_current'] == true && _text(s['id']).isNotEmpty)
          .map((s) => _text(s['id']))
          .toList();
      var snapshotMembersRaw = <Map<String, dynamic>>[];
      if (currentSnapshotIds.isNotEmpty) {
        try {
          final memRows = await _client
              .from('student_result_roster_members')
              .select()
              .inFilter('snapshot_id', currentSnapshotIds);
          snapshotMembersRaw = memRows
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } catch (_) {}
      }

      final cfg = settingsRow['config'] is Map
          ? Map<String, dynamic>.from(settingsRow['config'] as Map)
          : <String, dynamic>{};
      final sharedFp = cfg['result_front_page_settings'] is Map
          ? Map<String, dynamic>.from(cfg['result_front_page_settings'] as Map)
          : <String, dynamic>{};

      // Load saved Admin overrides from cloud config + SharedPreferences
      final loadedOverrides = <String, Map<String, dynamic>>{};
      if (cfg['result_summary_admin_overrides'] is Map) {
        final m = Map<String, dynamic>.from(
            cfg['result_summary_admin_overrides'] as Map);
        for (final entry in m.entries) {
          if (entry.value is Map) {
            loadedOverrides[entry.key] =
                Map<String, dynamic>.from(entry.value as Map);
          }
        }
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        final rawOv = prefs.getString(_overridePrefsKey);
        if (rawOv != null && rawOv.isNotEmpty) {
          final decoded = jsonDecode(rawOv);
          if (decoded is Map) {
            for (final entry in decoded.entries) {
              if (entry.value is Map) {
                loadedOverrides['${entry.key}'] =
                    Map<String, dynamic>.from(entry.value as Map);
              }
            }
          }
        }
      } catch (_) {}
      _adminOverrides = loadedOverrides;

      String pickSetting(List<String> keys) {
        for (final k in keys) {
          final v1 = _text(sharedFp[k]);
          if (v1.isNotEmpty) return v1;
          final v2 = _text(cfg[k]);
          if (v2.isNotEmpty) return v2;
          for (final crs in classResultSettingsRaw) {
            final v3 = _text(crs[k]);
            if (v3.isNotEmpty) return v3;
          }
          final v4 = _text(schoolRow[k]);
          if (v4.isNotEmpty) return v4;
        }
        return '';
      }

      final sName = _firstNonEmpty(<String>[
        _text(schoolRow['school_name_gu']),
        _text(schoolRow['school_name']),
        _text(widget.profile['school_name']),
        'પીએમ શ્રી દરેડ કુમાર શાળા',
      ]);

      if (logoBytes == null &&
          (sName.toLowerCase().contains('pm shri') ||
              sName.contains('પીએમ શ્રી'))) {
        try {
          final bd =
              await rootBundle.load('assets/hajari_patrak/pm_shri_logo.png');
          logoBytes = bd.buffer.asUint8List();
        } catch (_) {}
      }

      final district = _firstNonEmpty(<String>[
        pickSetting(<String>['front_page_district', 'district']),
        'જામનગર',
      ]);
      final authority = _firstNonEmpty(<String>[
        pickSetting(<String>['front_page_education_authority']),
        'જિલ્લા પંચાયત શિક્ષણ સમિતિ – $district',
      ]);
      final village = pickSetting(<String>['front_page_village', 'village']);
      final taluka = pickSetting(<String>['front_page_taluka', 'taluka']);
      final rawAddr = _firstNonEmpty(<String>[
        _text(schoolRow['school_address']),
        _text(schoolRow['address']),
        _text(cfg['school_address']),
      ]);
      final address = rawAddr.isNotEmpty
          ? rawAddr
          : (village.isNotEmpty || taluka.isNotEmpty)
              ? 'ગામ $village, તાલુકો $taluka, જિલ્લો $district'
              : 'ગામ દરેડ, તાલુકો અને જિલ્લો જામનગર – ૩૬૧૦૧૨';

      final acadYear = _firstNonEmpty(<String>[
        pickSetting(<String>['academic_year']),
        '૨૦૨૬–૨૭',
      ]);
      final udise = _firstNonEmpty(<String>[
        _text(schoolRow['udise_code']),
        _text(schoolRow['dise_code']),
        _text(schoolRow['school_id']),
        _text(widget.profile['school_id']),
      ]);

      final s1Date = pickSetting(<String>['first_sem_result_date']);
      final s2Date =
          pickSetting(<String>['second_sem_result_date', 'result_date']);
      if (s1Date.isNotEmpty) _sem1DateDefault = s1Date;
      if (s2Date.isNotEmpty) _sem2DateDefault = s2Date;

      if (gradeSettingsRaw.isNotEmpty) {
        final activeRules = gradeSettingsRaw
            .where((r) =>
                r['is_active'] != false &&
                _text(r['grade_label']).isNotEmpty)
            .toList()
          ..sort((a, b) =>
              _double(b['minimum_percent']).compareTo(_double(a['minimum_percent'])));
        if (activeRules.isNotEmpty) {
          _gradeRules = activeRules;
        }
      }

      _schoolType = SchoolType.resolve(
        <dynamic>[schoolRow['school_type'], cfg['school_type']],
        nameCandidates: <dynamic>[
          schoolRow['school_name_gu'],
          schoolRow['school_name'],
          schoolRow['school_name_en'],
        ],
      );

      _schoolLogoBytes = logoBytes;
      _lockedSchoolName = sName;
      _lockedUdiseCode = _toGujDigits(udise);
      _authorityCtrl.text = authority;
      _schoolNameCtrl.text = _lockedSchoolName;
      _schoolAddressCtrl.text = address;
      _academicYearCtrl.text = _toGujDigits(acadYear);
      _udiseCtrl.text = _lockedUdiseCode;
      _updateExamLabelAndDateForSemester();

      _rawClasses = SchoolClassOrder.sorted(classesRaw);
      _rawStudents = studentsRaw;
      _rawProfiles = profilesRaw;
      _rawSubjects = subjectsRaw;
      _rawMarks = marksRaw;
      _rawSnapshots = snapshotsRaw;
      _rawSnapshotMembers = snapshotMembersRaw;

      _recomputeSummaries();
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<List<dynamic>> _safeQuery(String table, String schoolRef) async {
    try {
      return await _client.from(table).select().eq('school_ref', schoolRef);
    } catch (_) {
      return const <dynamic>[];
    }
  }

  String _firstNonEmpty(List<String> values) {
    for (final v in values) {
      if (v.trim().isNotEmpty && v.trim().toLowerCase() != 'null') {
        return v.trim();
      }
    }
    return '';
  }

  String _normalizeCategory(dynamic raw) {
    final t = _text(raw).toUpperCase().replaceAll(' ', '');
    if (t == 'ST' || t.contains('અ.જ.જા') || t.contains('અનુ.જ.જા')) return 'ST';
    if (t == 'SC' || t.contains('અ.જા') || t.contains('અનુ.જા')) return 'SC';
    if (t == 'OBC' ||
        t == 'SEBC' ||
        t.contains('બ.પં') ||
        t.contains('બક્ષી')) {
      return 'OBC';
    }
    return 'OTHER';
  }

  String _normalizeGender(dynamic raw) {
    if (_schoolType == 'boys') return 'BOYS';
    if (_schoolType == 'girls') return 'GIRLS';
    final t = _text(raw).toUpperCase();
    if (const <String>{
      'GIRLS',
      'GIRL',
      'FEMALE',
      'F',
      'KANYA',
      'કન્યા',
      'છોકરી'
    }.contains(t)) {
      return 'GIRLS';
    }
    return 'BOYS';
  }

  String _gradeForPercent(double pct) {
    for (final r in _gradeRules) {
      final minPct = _double(r['minimum_percent']);
      if (pct >= minPct) {
        final lbl = _text(r['grade_label']).toUpperCase();
        if (const <String>{'A', 'B', 'C', 'D', 'E'}.contains(lbl)) return lbl;
        if (lbl.startsWith('A')) return 'A';
        if (lbl.startsWith('B')) return 'B';
        if (lbl.startsWith('C')) return 'C';
        if (lbl.startsWith('D')) return 'D';
        return 'E';
      }
    }
    return 'E';
  }

  (String stdKey, int stdNum, String stdDisplay, String sectionDisplay)
      _parseStandardAndSection(Map<String, dynamic> classRow) {
    final group = SchoolClassOrder.groupOf(classRow);
    final rawLabel = _firstNonEmpty(<String>[
      _text(classRow['standard']),
      _text(classRow['label']),
      _text(classRow['class_key']),
    ]);
    final bare = ClassLabel.bare(
      _firstNonEmpty(
          <String>[_text(classRow['label']), _text(classRow['class_key'])]),
    );

    const guj = '૦૧૨૩૪૫૬૭૮૯';
    var norm = '$rawLabel $bare';
    for (var i = 0; i < guj.length; i++) {
      norm = norm.replaceAll(guj[i], '$i');
    }
    final m = RegExp(r'([1-8])').firstMatch(norm);
    if (m != null) {
      final numVal = int.parse(m.group(1)!);
      final sec = _extractSectionLetter(bare, _text(classRow['section']));
      return ('$numVal', numVal, '$numVal', sec.isEmpty ? 'અ' : sec);
    }

    if (group == SchoolClassOrder.balvatika ||
        bare.contains('બાલ') ||
        bare.toLowerCase().contains('bal')) {
      final sec = _extractSectionLetter(bare, _text(classRow['section']));
      return ('0', 0, 'બાલવાટિકા', sec.isEmpty ? 'અ' : sec);
    }

    final sec = _extractSectionLetter(bare, _text(classRow['section']));
    return (bare, 99, bare, sec.isEmpty ? 'અ' : sec);
  }

  String _extractSectionLetter(String label, String explicitSection) {
    if (explicitSection.isNotEmpty) {
      return _toGujSection(explicitSection);
    }
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    var norm = label;
    for (var i = 0; i < guj.length; i++) {
      norm = norm.replaceAll(guj[i], '$i');
    }
    final stripped = norm
        .replaceAll(
            RegExp(r'ધોરણ|ધો\.?|std\.?|class', caseSensitive: false), '')
        .replaceAll(RegExp(r'[0-9\-_()/.,:]'), ' ')
        .trim();
    if (stripped.isEmpty) return 'અ';
    return _toGujSection(stripped);
  }

  String _toGujSection(String raw) {
    final u = raw.trim().toUpperCase();
    return switch (u) {
      'A' || 'અ' => 'અ',
      'B' || 'બ' => 'બ',
      'C' || 'ક' => 'ક',
      'D' || 'ડ' => 'ડ',
      'E' || 'ઈ' => 'ઈ',
      _ => raw.trim(),
    };
  }

  int _sectionSortRank(String sec) {
    return switch (sec.trim()) {
      'અ' || 'A' => 1,
      'બ' || 'B' => 2,
      'ક' || 'C' => 3,
      'ડ' || 'D' => 4,
      'ઈ' || 'E' => 5,
      _ => 9,
    };
  }

  String _formatClassWithSection(String stdDisp, String secDisp) {
    final gujStd = _toGujDigits(stdDisp);
    if (secDisp.trim().isEmpty || secDisp == 'ધોરણ કુલ') {
      return 'ધોરણ $gujStd';
    }
    return 'ધોરણ $gujStd - $secDisp';
  }

  /// Computes Top 3 Rankers (dense ranks 1, 2, 3) for a list of scored students.
  /// If 2 or more students tie at Rank 1, Rank 2, or Rank 3, ALL tied students
  /// in Ranks 1..3 are included (e.g. if 2 students tie in Rank 2, 4 students
  /// are returned for that class/section).
  List<_RankerStudentEntry> _computeTop3RankersForGroup(
    List<_RankerStudentEntry> candidates, {
    required String scopePrefix,
  }) {
    final eligible = candidates
        .where((c) => c.obtainedMarks > 0 && c.totalMarks > 0)
        .toList();
    if (eligible.isEmpty) return <_RankerStudentEntry>[];

    // Prefer passed students; if none passed, fall back to all appeared students
    final passedList = eligible.where((c) => c.passed).toList();
    final pool = passedList.isNotEmpty ? passedList : eligible;

    pool.sort((a, b) {
      // Compare by percentage (rounded to 2 decimal places) descending, then obtainedMarks descending
      final aPctKey = (a.percentage * 100).round();
      final bPctKey = (b.percentage * 100).round();
      if (bPctKey != aPctKey) return bPctKey.compareTo(aPctKey);
      if (b.obtainedMarks != a.obtainedMarks) {
        return b.obtainedMarks.compareTo(a.obtainedMarks);
      }
      final secCmp = _sectionSortRank(a.sectionDisplay)
          .compareTo(_sectionSortRank(b.sectionDisplay));
      if (secCmp != 0) return secCmp;
      if (a.rollNo != b.rollNo) return a.rollNo.compareTo(b.rollNo);
      return a.studentName.compareTo(b.studentName);
    });

    final out = <_RankerStudentEntry>[];
    int currentRank = 0;
    int? prevPctKey;
    int? prevObtained;
    int? prevTotal;

    for (var i = 0; i < pool.length; i++) {
      final item = pool[i];
      final pctKey = (item.percentage * 100).round();
      final isTie = prevPctKey != null &&
          pctKey == prevPctKey &&
          (item.totalMarks != prevTotal || item.obtainedMarks == prevObtained);

      if (!isTie) {
        currentRank++;
        if (currentRank > 3) {
          break; // Only Ranks 1, 2, and 3
        }
        prevPctKey = pctKey;
        prevObtained = item.obtainedMarks;
        prevTotal = item.totalMarks;
      }

      out.add(
        _RankerStudentEntry(
          entryKey: '$scopePrefix|${item.classId}|${item.studentId}|$i',
          studentId: item.studentId,
          studentName: item.studentName,
          rollNo: item.rollNo,
          classId: item.classId,
          standardKey: item.standardKey,
          standardNum: item.standardNum,
          standardDisplay: item.standardDisplay,
          sectionDisplay: item.sectionDisplay,
          classWithSection: item.classWithSection,
          totalMarks: item.totalMarks,
          obtainedMarks: item.obtainedMarks,
          percentage: item.percentage,
          rank: currentRank,
          passed: item.passed,
        ),
      );
    }

    return out;
  }

  void _recomputeSummaries() {
    final isSem1 = _selectedSemester == '1';
    final isSem2 = _selectedSemester == '2';
    final isAnnual = _selectedSemester == 'Annual';

    final profileByClassAndStudent = <String, Map<String, dynamic>>{};
    for (final p in _rawProfiles) {
      final cid = _text(p['class_id']);
      final sid = _text(p['student_id']);
      if (cid.isNotEmpty && sid.isNotEmpty) {
        profileByClassAndStudent['$cid|$sid'] = p;
      }
    }

    int subjectMarkTotal(Map<String, dynamic>? row) {
      if (row == null) return 0;
      if (row['direct_total_mode'] == true || row['direct_total'] != null) {
        return _int(row['direct_total']);
      }
      final satAb = row['satrant_absent'] == true ||
          _text(row['satrant']).toUpperCase() == 'AB' ||
          _int(row['satrant']) < 0;
      final pA = _int(row['patrak_a']);
      final sat = satAb ? 0 : _int(row['satrant']);
      final swa = _int(row['swa_adhyayan']);
      return pA + sat + swa;
    }

    bool isSubjectRowEntered(Map<String, dynamic>? row) {
      if (row == null) return false;
      final satAb = row['satrant_absent'] == true ||
          _text(row['satrant']).toUpperCase() == 'AB' ||
          _int(row['satrant']) < 0;
      return satAb || subjectMarkTotal(row) > 0;
    }

    final marksByClassStudentSem =
        <String, Map<int, Map<String, Map<String, dynamic>>>>{};
    final subjectsSeenByClass = <String, Set<String>>{};
    for (final m in _rawMarks) {
      final cid = _text(m['class_id']);
      final sid = _text(m['student_id']);
      final sem = _int(m['semester']);
      final sub = _text(m['subject_name']);
      if (cid.isEmpty || sid.isEmpty || sub.isEmpty) continue;
      if (sub != 'વ્યક્તિત્વ વિકાસ') {
        subjectsSeenByClass.putIfAbsent(cid, () => <String>{}).add(sub);
      }
      final bySem = marksByClassStudentSem.putIfAbsent(
        '$cid|$sid',
        () => <int, Map<String, Map<String, dynamic>>>{
          1: <String, Map<String, dynamic>>{},
          2: <String, Map<String, dynamic>>{},
        },
      );
      bySem.putIfAbsent(sem, () => <String, Map<String, dynamic>>{})[sub] = m;
    }

    final subjectsByClass = <String, List<String>>{};
    for (final s in _rawSubjects) {
      final cid = _text(s['class_id']);
      final sub = _text(s['subject_name']);
      if (cid.isEmpty || sub.isEmpty || sub == 'વ્યક્તિત્વ વિકાસ') continue;
      final list = subjectsByClass.putIfAbsent(cid, () => <String>[]);
      if (!list.contains(sub)) list.add(sub);
    }
    for (final entry in subjectsSeenByClass.entries) {
      final list = subjectsByClass.putIfAbsent(entry.key, () => <String>[]);
      for (final sub in entry.value) {
        if (!list.contains(sub)) list.add(sub);
      }
    }

    final snapIdByClassSem = <String, String>{};
    for (final s in _rawSnapshots) {
      if (s['is_current'] != true) continue;
      final cid = _text(s['class_id']);
      final sem = _int(s['semester']);
      final id = _text(s['id']);
      if (cid.isNotEmpty && id.isNotEmpty) {
        snapIdByClassSem['$cid|$sem'] = id;
      }
    }
    final membersBySnapId = <String, List<Map<String, dynamic>>>{};
    for (final m in _rawSnapshotMembers) {
      final snapId = _text(m['snapshot_id']);
      if (snapId.isNotEmpty) {
        membersBySnapId
            .putIfAbsent(snapId, () => <Map<String, dynamic>>[])
            .add(m);
      }
    }

    final activeStudentsByClass = <String, List<Map<String, dynamic>>>{};
    final liveStudentById = <String, Map<String, dynamic>>{};
    for (final s in _rawStudents) {
      final sid = _text(s['id']);
      final cid = _text(s['class_id']);
      if (sid.isNotEmpty) liveStudentById[sid] = s;
      final isAct = s['is_active'] == true &&
          _text(s['leaving_date']).isEmpty &&
          _text(s['exit_date']).isEmpty;
      if (isAct && cid.isNotEmpty) {
        activeStudentsByClass
            .putIfAbsent(cid, () => <Map<String, dynamic>>[])
            .add(s);
      }
    }

    final allSummaries = <_ClassSectionResultSummary>[];
    final scoredStudentsByClassId = <String, List<_RankerStudentEntry>>{};

    for (var idx = 0; idx < _rawClasses.length; idx++) {
      final cls = _rawClasses[idx];
      final cid = _text(cls['id']);
      if (cid.isEmpty) continue;
      final (stdKey, stdNum, stdDisp, secDisp) = _parseStandardAndSection(cls);
      final classLabel = _firstNonEmpty(
          <String>[_text(cls['label']), _text(cls['class_key']), cid]);

      final summary = _ClassSectionResultSummary(
        classId: cid,
        classLabel: classLabel,
        standardKey: stdKey,
        standardNum: stdNum,
        standardDisplay: stdDisp,
        sectionDisplay: secDisp,
        sortOrder: idx,
      );

      final targetSnapSem = isSem1 ? 1 : 2;
      final snapId = snapIdByClassSem['$cid|$targetSnapSem'] ??
          snapIdByClassSem['$cid|1'] ??
          '';
      final roster = <Map<String, dynamic>>[];
      final seenIds = <String>{};

      if (snapId.isNotEmpty && membersBySnapId.containsKey(snapId)) {
        for (final mem in membersBySnapId[snapId]!) {
          final sid = _text(mem['student_id']);
          if (sid.isEmpty) continue;
          final live = liveStudentById[sid];
          if (live != null) {
            if (live['is_active'] != true) continue;
            roster.add(live);
            seenIds.add(sid);
          }
        }
      }
      for (final live
          in (activeStudentsByClass[cid] ?? const <Map<String, dynamic>>[])) {
        final sid = _text(live['id']);
        if (sid.isEmpty || seenIds.contains(sid)) continue;
        roster.add(live);
        seenIds.add(sid);
      }

      final classSubjects = subjectsByClass[cid] ?? const <String>[];

      final subjectsWithSem1 = <String>{};
      final subjectsWithSem2 = <String>{};
      final sem1MaxBySub = <String, int>{};
      final sem2MaxBySub = <String, int>{};

      for (final sub in classSubjects) {
        bool s1Any = false,
            s1HasA = false,
            s1HasS = false,
            s1HasSw = false,
            s1HasDirect = false;
        bool s2Any = false,
            s2HasA = false,
            s2HasS = false,
            s2HasSw = false,
            s2HasDirect = false;
        for (final st in roster) {
          final sid = _text(st['id']);
          final mMap = marksByClassStudentSem['$cid|$sid'];
          final r1 = mMap?[1]?[sub];
          if (isSubjectRowEntered(r1)) {
            s1Any = true;
            if (r1!['direct_total_mode'] == true || r1['direct_total'] != null) {
              s1HasDirect = true;
            }
            if (_int(r1['patrak_a']) > 0) s1HasA = true;
            if (_int(r1['satrant']) > 0 || r1['satrant_absent'] == true) {
              s1HasS = true;
            }
            if (_int(r1['swa_adhyayan']) > 0) s1HasSw = true;
          }
          final r2 = mMap?[2]?[sub];
          if (isSubjectRowEntered(r2)) {
            s2Any = true;
            if (r2!['direct_total_mode'] == true || r2['direct_total'] != null) {
              s2HasDirect = true;
            }
            if (_int(r2['patrak_a']) > 0) s2HasA = true;
            if (_int(r2['satrant']) > 0 || r2['satrant_absent'] == true) {
              s2HasS = true;
            }
            if (_int(r2['swa_adhyayan']) > 0) s2HasSw = true;
          }
        }
        if (s1Any) {
          subjectsWithSem1.add(sub);
          final calcMax = s1HasDirect
              ? 100
              : ((s1HasA ? 40 : 0) + (s1HasS ? 40 : 0) + (s1HasSw ? 20 : 0));
          sem1MaxBySub[sub] = calcMax > 0 ? calcMax : 100;
        }
        if (s2Any) {
          subjectsWithSem2.add(sub);
          final calcMax = s2HasDirect
              ? 100
              : ((s2HasA ? 40 : 0) + (s2HasS ? 40 : 0) + (s2HasSw ? 20 : 0));
          sem2MaxBySub[sub] = calcMax > 0 ? calcMax : 100;
        }
      }

      bool classHasAnyMark = false;
      if (isSem1 && subjectsWithSem1.isNotEmpty) classHasAnyMark = true;
      if (isSem2 && subjectsWithSem2.isNotEmpty) classHasAnyMark = true;
      if (isAnnual &&
          (subjectsWithSem1.isNotEmpty || subjectsWithSem2.isNotEmpty)) {
        classHasAnyMark = true;
      }

      final classScoredList = <_RankerStudentEntry>[];

      for (final st in roster) {
        final sid = _text(st['id']);
        final prof =
            profileByClassAndStudent['$cid|$sid'] ?? const <String, dynamic>{};
        final studiedSem2 = prof.containsKey('studied_in_sem2')
            ? _bool(prof['studied_in_sem2'])
            : true;
        if (!isSem1 && !studiedSem2) {
          continue;
        }

        final cat = _normalizeCategory(st['category']);
        final gen = _normalizeGender(st['gender']);
        final isDivyang = st.containsKey('is_divyang')
            ? _bool(st['is_divyang'])
            : _bool(prof['is_divyang']);
        final passThreshold = isDivyang ? 20.0 : 35.0;

        final mMap = marksByClassStudentSem['$cid|$sid'];
        final s1Map = mMap?[1] ?? const <String, Map<String, dynamic>>{};
        final s2Map = mMap?[2] ?? const <String, Map<String, dynamic>>{};

        int obtainedSum = 0;
        int maxSum = 0;
        int failedSubjectsCount = 0;

        for (final sub in classSubjects) {
          final hasS1 = subjectsWithSem1.contains(sub);
          final hasS2 = subjectsWithSem2.contains(sub);
          final r1 = s1Map[sub];
          final r2 = s2Map[sub];
          final m1 = subjectMarkTotal(r1);
          final m2 = subjectMarkTotal(r2);

          if (isSem1) {
            if (!hasS1 || !isSubjectRowEntered(r1)) continue;
            final sMax = sem1MaxBySub[sub] ?? 100;
            maxSum += sMax;
            obtainedSum += m1;
            final subPct = sMax > 0 ? (m1 * 100.0) / sMax : 0.0;
            if (subPct < passThreshold) failedSubjectsCount++;
          } else if (isSem2) {
            if (!hasS2 || !isSubjectRowEntered(r2)) continue;
            final sMax = sem2MaxBySub[sub] ?? 100;
            maxSum += sMax;
            obtainedSum += m2;
            final subPct = sMax > 0 ? (m2 * 100.0) / sMax : 0.0;
            if (subPct < passThreshold) failedSubjectsCount++;
          } else if (isAnnual) {
            final ent1 = hasS1 && isSubjectRowEntered(r1);
            final ent2 = hasS2 && isSubjectRowEntered(r2);
            if (!ent1 && !ent2) continue;
            final subMax = (ent1 ? (sem1MaxBySub[sub] ?? 100) : 0) +
                (ent2 ? (sem2MaxBySub[sub] ?? 100) : 0);
            final subObt = (ent1 ? m1 : 0) + (ent2 ? m2 : 0);
            maxSum += subMax;
            obtainedSum += subObt;
            final subPct = subMax > 0 ? (subObt * 100.0) / subMax : 0.0;
            if (subPct < passThreshold) failedSubjectsCount++;
          }
        }

        final vv1 = _int(prof['vv1']);
        final vv2 = _int(prof['vv2']);
        if (isSem1 && vv1 > 0) {
          obtainedSum += vv1;
          maxSum += 100;
          classHasAnyMark = true;
        } else if (isSem2 && vv2 > 0) {
          obtainedSum += vv2;
          maxSum += 100;
          classHasAnyMark = true;
        } else if (isAnnual && (vv1 > 0 || vv2 > 0)) {
          obtainedSum += (vv1 + vv2);
          maxSum += (vv1 > 0 ? 100 : 0) + (vv2 > 0 ? 100 : 0);
          classHasAnyMark = true;
        }

        final appeared = obtainedSum > 0 && maxSum > 0;
        String grade = '';
        bool passed = false;
        double pct = 0.0;
        if (appeared) {
          classHasAnyMark = true;
          pct = (obtainedSum * 100.0) / maxSum;
          grade = _gradeForPercent(pct);
          passed = grade != 'E' && failedSubjectsCount < 2;
          if (!passed && grade != 'E') {
            grade = 'E';
          }

          final studentName = _firstNonEmpty(<String>[
            _text(st['full_name']),
            _text(st['student_name']),
            _text(st['name']),
            'વિદ્યાર્થી',
          ]);
          final rollNo = _int(st['roll_no'] ?? st['roll_number']);
          classScoredList.add(
            _RankerStudentEntry(
              entryKey: '$cid|$sid',
              studentId: sid,
              studentName: studentName,
              rollNo: rollNo,
              classId: cid,
              standardKey: stdKey,
              standardNum: stdNum,
              standardDisplay: stdDisp,
              sectionDisplay: secDisp,
              classWithSection: _formatClassWithSection(stdDisp, secDisp),
              totalMarks: maxSum,
              obtainedMarks: obtainedSum,
              percentage: pct,
              rank: 1,
              passed: passed,
            ),
          );
        }

        summary.addStudent(
          _StudentEvalSummary(
            category: cat,
            gender: gen,
            appeared: appeared,
            passed: passed,
            grade: grade,
          ),
        );
      }

      scoredStudentsByClassId[cid] = classScoredList;
      summary.hasMarksInserted = classHasAnyMark || summary.appearedTotal > 0;

      // Apply Admin Override if saved for this semester & class
      final ovKey = '$_selectedSemester|$cid';
      final ov = _adminOverrides[ovKey];
      if (ov != null) {
        summary.applyAdminOverride(ov, _schoolType);
      }

      allSummaries.add(summary);
    }

    // Sort strictly by Standard 1, 2, 3, 4, 5, 6, 7, 8 (and Section અ, બ, ક, ડ)
    allSummaries.sort((a, b) {
      final aRank = (a.standardNum >= 1 && a.standardNum <= 8)
          ? a.standardNum
          : (a.standardNum == 0 ? 90 : 95);
      final bRank = (b.standardNum >= 1 && b.standardNum <= 8)
          ? b.standardNum
          : (b.standardNum == 0 ? 90 : 95);
      if (aRank != bRank) return aRank.compareTo(bRank);
      final secCmp = _sectionSortRank(a.sectionDisplay)
          .compareTo(_sectionSortRank(b.sectionDisplay));
      if (secCmp != 0) return secCmp;
      return a.sortOrder.compareTo(b.sortOrder);
    });

    _allComputedClassSummaries = allSummaries;

    // Filter to only marks-inserted classes (in 1..8 sequence) when _onlyMarksInsertedClasses is true
    final withMarks = allSummaries
        .where((s) =>
            s.hasMarksInserted && s.standardNum >= 1 && s.standardNum <= 8)
        .toList();
    final filtered = _onlyMarksInsertedClasses
        ? (withMarks.isNotEmpty
            ? withMarks
            : allSummaries
                .where((s) => s.standardNum >= 1 && s.standardNum <= 8)
                .toList())
        : allSummaries;

    final byStd = <String, List<_ClassSectionResultSummary>>{};
    final stdTotals = <String, _ClassSectionResultSummary>{};
    final schoolTotal = _ClassSectionResultSummary(
      classId: '__TOTAL__',
      classLabel: 'સમગ્ર શાળાનો કુલ',
      standardKey: '__TOTAL__',
      standardNum: 99,
      standardDisplay: 'સમગ્ર શાળાનો કુલ',
      sectionDisplay: '',
      sortOrder: 9999,
    );

    for (final summary in filtered) {
      final stdKey = summary.standardKey;
      byStd
          .putIfAbsent(stdKey, () => <_ClassSectionResultSummary>[])
          .add(summary);
      final stdTot = stdTotals.putIfAbsent(
        stdKey,
        () => _ClassSectionResultSummary(
          classId: '__STD_$stdKey',
          classLabel: '${summary.standardDisplay} ધોરણ કુલ',
          standardKey: stdKey,
          standardNum: summary.standardNum,
          standardDisplay: summary.standardDisplay,
          sectionDisplay: 'ધોરણ કુલ',
          sortOrder: summary.sortOrder,
        ),
      );
      stdTot.mergeFrom(summary);
      schoolTotal.mergeFrom(summary);
    }

    _classSummaries = filtered;
    _byStandard = byStd;
    _standardTotals = stdTotals;
    _wholeSchoolTotal = schoolTotal;
    if (_selectedClassIdForDetail != '__ALL__' &&
        !_classSummaries.any((c) => c.classId == _selectedClassIdForDetail)) {
      _selectedClassIdForDetail = '__ALL__';
    }

    // -------------------------------------------------------------------------
    // Compute Format 4 (Section-Wise Top 3 Rankers) & Format 5 (Class-Wise Top 3 Rankers)
    // in strictly increasing class order (1..8) and section order (અ, બ, ક, ડ).
    // -------------------------------------------------------------------------
    final computedSecRankers = <_RankerStudentEntry>[];
    final computedStdRankers = <_RankerStudentEntry>[];

    for (final entry in byStd.entries) {
      final stdKey = entry.key;
      final sections = entry.value;
      final stdPool = <_RankerStudentEntry>[];

      for (final secSummary in sections) {
        final cid = secSummary.classId;
        final candidates =
            scoredStudentsByClassId[cid] ?? const <_RankerStudentEntry>[];
        stdPool.addAll(candidates);

        // Check if Admin saved custom section-wise rankers for this classId
        final secOvKey = '__RANKERS_SEC__|$_selectedSemester|$cid';
        final secOv = _adminOverrides[secOvKey];
        if (secOv != null && secOv['items'] is List) {
          final customList = (secOv['items'] as List)
              .whereType<Map>()
              .map((m) =>
                  _RankerStudentEntry.fromJson(Map<String, dynamic>.from(m)))
              .toList();
          computedSecRankers.addAll(customList);
        } else {
          computedSecRankers.addAll(
            _computeTop3RankersForGroup(candidates, scopePrefix: 'SEC|$cid'),
          );
        }
      }

      // Check if Admin saved custom class-wise (standard-wise) rankers for this standard
      final stdOvKey = '__RANKERS_STD__|$_selectedSemester|$stdKey';
      final stdOv = _adminOverrides[stdOvKey];
      if (stdOv != null && stdOv['items'] is List) {
        final customList = (stdOv['items'] as List)
            .whereType<Map>()
            .map((m) =>
                _RankerStudentEntry.fromJson(Map<String, dynamic>.from(m)))
            .toList();
        computedStdRankers.addAll(customList);
      } else {
        computedStdRankers.addAll(
          _computeTop3RankersForGroup(stdPool, scopePrefix: 'STD|$stdKey'),
        );
      }
    }

    _sectionWiseRankers = computedSecRankers;
    _classWiseRankers = computedStdRankers;
  }

  _ClassSectionResultSummary get _selectedDetailSummary {
    if (_selectedClassIdForDetail == '__ALL__') {
      return _wholeSchoolTotal;
    }
    for (final c in _classSummaries) {
      if (c.classId == _selectedClassIdForDetail) return c;
    }
    return _wholeSchoolTotal;
  }

  String _rankDisplayLabel(int rank) {
    return switch (rank) {
      1 => '1 (પ્રથમ)',
      2 => '2 (દ્વિતીય)',
      3 => '3 (તૃતીય)',
      _ => '$rank',
    };
  }

  // ===========================================================================
  // ADMIN EDIT RANKER ENTRY DIALOG (EDIT OR ADD TOP-3 RANKER ROW)
  // ===========================================================================

  Future<void> _openAdminEditRankerDialog({
    required bool isSectionWise,
    _RankerStudentEntry? existingEntry,
  }) async {
    if (_classSummaries.isEmpty && _allComputedClassSummaries.isEmpty) return;
    final availableClasses = _classSummaries.isNotEmpty
        ? _classSummaries
        : _allComputedClassSummaries;

    var selectedClass = existingEntry != null
        ? availableClasses.firstWhere(
            (c) => c.classId == existingEntry.classId,
            orElse: () => availableClasses.first,
          )
        : availableClasses.first;

    final nameCtrl =
        TextEditingController(text: existingEntry?.studentName ?? '');
    final classSecCtrl = TextEditingController(
      text: existingEntry?.classWithSection ??
          _formatClassWithSection(
              selectedClass.standardDisplay, selectedClass.sectionDisplay),
    );
    final totalMarksCtrl = TextEditingController(
        text: '${existingEntry?.totalMarks ?? 500}');
    final obtainedMarksCtrl = TextEditingController(
        text: '${existingEntry?.obtainedMarks ?? 450}');
    final pctCtrl = TextEditingController(
      text: (existingEntry?.percentage ?? 90.0).toStringAsFixed(2),
    );
    var selectedRank = (existingEntry?.rank ?? 1).clamp(1, 3);

    void recalcPercent() {
      final tot = _int(totalMarksCtrl.text);
      final obt = _int(obtainedMarksCtrl.text);
      if (tot > 0) {
        pctCtrl.text = ((obt * 100.0) / tot).toStringAsFixed(2);
      }
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final scopeKey = isSectionWise
              ? '__RANKERS_SEC__|$_selectedSemester|${selectedClass.classId}'
              : '__RANKERS_STD__|$_selectedSemester|${selectedClass.standardKey}';

          List<_RankerStudentEntry> currentGroupItems() {
            final source =
                isSectionWise ? _sectionWiseRankers : _classWiseRankers;
            return source
                .where((e) => isSectionWise
                    ? e.classId == selectedClass.classId
                    : e.standardKey == selectedClass.standardKey)
                .map((e) => _RankerStudentEntry.fromJson(e.toJson()))
                .toList();
          }

          return AlertDialog(
            title: Text(
              isSectionWise
                  ? '✏️ વિભાગવાર પ્રથમ ૩ ક્રમાંકિત વિદ્યાર્થી સુધારો / ઉમેરો (Section-Wise Ranker Edit)'
                  : '✏️ ધોરણવાર પ્રથમ ૩ ક્રમાંકિત વિદ્યાર્થી સુધારો / ઉમેરો (Class-Wise Ranker Edit)',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                color: Color(0xFF0B2D5B),
              ),
            ),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedClass.classId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'ધોરણ અને વર્ગ પસંદ કરો (Select Class & Section)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: availableClasses
                          .map(
                            (c) => DropdownMenuItem<String>(
                              value: c.classId,
                              child: Text(
                                '${_formatClassWithSection(c.standardDisplay, c.sectionDisplay)} (${c.classLabel})',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: existingEntry != null
                          ? null
                          : (val) {
                              if (val == null) return;
                              final next = availableClasses
                                  .firstWhere((c) => c.classId == val);
                              setDialogState(() {
                                selectedClass = next;
                                classSecCtrl.text = _formatClassWithSection(
                                  next.standardDisplay,
                                  next.sectionDisplay,
                                );
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'વિદ્યાર્થીનું નામ (Student Name)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: classSecCtrl,
                            decoration: const InputDecoration(
                              labelText: 'ધોરણ - વર્ગ (Class with Section)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 170,
                          child: DropdownButtonFormField<int>(
                            initialValue: selectedRank,
                            decoration: const InputDecoration(
                              labelText: 'ક્રમાંક (Rank 1–3)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const <DropdownMenuItem<int>>[
                              DropdownMenuItem(
                                  value: 1, child: Text('1 (પ્રથમ)')),
                              DropdownMenuItem(
                                  value: 2, child: Text('2 (દ્વિતીય)')),
                              DropdownMenuItem(
                                  value: 3, child: Text('3 (તૃતીય)')),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() => selectedRank = v);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: totalMarksCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setDialogState(recalcPercent),
                            decoration: const InputDecoration(
                              labelText: 'કુલ ગુણ (Total Marks)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: obtainedMarksCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setDialogState(recalcPercent),
                            decoration: const InputDecoration(
                              labelText: 'મેળવેલ ગુણ (Obtained Marks)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: pctCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'ટકાવારી % (Percentage)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  _adminOverrides.remove(scopeKey);
                  await _saveAdminOverrides();
                  if (!mounted) return;
                  setState(() => _recomputeSummaries());
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.restore),
                label: const Text('ઓટો-ફેચ રીસેટ (Reset Class Auto-Rank)'),
              ),
              if (existingEntry != null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade700),
                  onPressed: () async {
                    final list = currentGroupItems()
                      ..removeWhere(
                          (e) => e.entryKey == existingEntry.entryKey);
                    _adminOverrides[scopeKey] = <String, dynamic>{
                      'items': list.map((e) => e.toJson()).toList(),
                    };
                    await _saveAdminOverrides();
                    if (!mounted) return;
                    setState(() => _recomputeSummaries());
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('દૂર કરો (Remove Row)'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('રદ કરો (Cancel)'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0B2D5B),
                ),
                onPressed: () async {
                  final list = currentGroupItems();
                  final tot = _int(totalMarksCtrl.text);
                  final obt = _int(obtainedMarksCtrl.text);
                  final pct = _double(pctCtrl.text) > 0
                      ? _double(pctCtrl.text)
                      : (tot > 0 ? (obt * 100.0) / tot : 0.0);

                  if (existingEntry != null) {
                    final idx = list.indexWhere(
                        (e) => e.entryKey == existingEntry.entryKey);
                    final updated = _RankerStudentEntry(
                      entryKey: existingEntry.entryKey,
                      studentId: existingEntry.studentId,
                      studentName: nameCtrl.text.trim().isEmpty
                          ? existingEntry.studentName
                          : nameCtrl.text.trim(),
                      rollNo: existingEntry.rollNo,
                      classId: selectedClass.classId,
                      standardKey: selectedClass.standardKey,
                      standardNum: selectedClass.standardNum,
                      standardDisplay: selectedClass.standardDisplay,
                      sectionDisplay: selectedClass.sectionDisplay,
                      classWithSection: classSecCtrl.text.trim().isEmpty
                          ? _formatClassWithSection(
                              selectedClass.standardDisplay,
                              selectedClass.sectionDisplay,
                            )
                          : classSecCtrl.text.trim(),
                      totalMarks: tot,
                      obtainedMarks: obt,
                      percentage: pct,
                      rank: selectedRank,
                      passed: true,
                    );
                    if (idx >= 0) {
                      list[idx] = updated;
                    } else {
                      list.add(updated);
                    }
                  } else {
                    list.add(
                      _RankerStudentEntry(
                        entryKey:
                            'MANUAL|${selectedClass.classId}|${DateTime.now().millisecondsSinceEpoch}',
                        studentId:
                            'manual_${DateTime.now().millisecondsSinceEpoch}',
                        studentName: nameCtrl.text.trim().isEmpty
                            ? 'વિદ્યાર્થી'
                            : nameCtrl.text.trim(),
                        rollNo: list.length + 1,
                        classId: selectedClass.classId,
                        standardKey: selectedClass.standardKey,
                        standardNum: selectedClass.standardNum,
                        standardDisplay: selectedClass.standardDisplay,
                        sectionDisplay: selectedClass.sectionDisplay,
                        classWithSection: classSecCtrl.text.trim().isEmpty
                            ? _formatClassWithSection(
                                selectedClass.standardDisplay,
                                selectedClass.sectionDisplay,
                              )
                            : classSecCtrl.text.trim(),
                        totalMarks: tot,
                        obtainedMarks: obt,
                        percentage: pct,
                        rank: selectedRank,
                        passed: true,
                      ),
                    );
                  }

                  list.sort((a, b) {
                    if (a.rank != b.rank) return a.rank.compareTo(b.rank);
                    return b.obtainedMarks.compareTo(a.obtainedMarks);
                  });

                  _adminOverrides[scopeKey] = <String, dynamic>{
                    'items': list.map((e) => e.toJson()).toList(),
                  };
                  await _saveAdminOverrides();
                  if (!mounted) return;
                  setState(() => _recomputeSummaries());
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('સેવ કરો (Save)'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ===========================================================================
  // ADMIN EDIT DIALOG (EDIT REGISTERED, PRESENT, ABSENT, PASS, FAIL, GRADES)
  // ===========================================================================

  Future<void> _openAdminEditClassDialog(
      [_ClassSectionResultSummary? initialTarget]) async {
    if (_allComputedClassSummaries.isEmpty) return;
    var currentTarget = initialTarget ??
        (_classSummaries.isNotEmpty
            ? _classSummaries.first
            : _allComputedClassSummaries.first);

    final scCtrl = TextEditingController();
    final stCtrl = TextEditingController();
    final obcCtrl = TextEditingController();
    final otherCtrl = TextEditingController();
    final regCtrl = TextEditingController();
    final presCtrl = TextEditingController();
    final absCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final failCtrl = TextEditingController();
    final gACtrl = TextEditingController();
    final gBCtrl = TextEditingController();
    final gCCtrl = TextEditingController();
    final gDCtrl = TextEditingController();
    final gECtrl = TextEditingController();
    final remCtrl = TextEditingController();

    void loadTargetFields(_ClassSectionResultSummary t) {
      scCtrl.text = '${t.catRegistered['SC'] ?? 0}';
      stCtrl.text = '${t.catRegistered['ST'] ?? 0}';
      obcCtrl.text = '${t.catRegistered['OBC'] ?? 0}';
      otherCtrl.text = '${t.catRegistered['OTHER'] ?? 0}';
      regCtrl.text = '${t.registeredTotal}';
      presCtrl.text = '${t.appearedTotal}';
      absCtrl.text = '${t.absentTotal}';
      passCtrl.text = '${t.passedTotal}';
      failCtrl.text = '${t.failedTotal}';
      gACtrl.text = '${t.gradeCounts['A'] ?? 0}';
      gBCtrl.text = '${t.gradeCounts['B'] ?? 0}';
      gCCtrl.text = '${t.gradeCounts['C'] ?? 0}';
      gDCtrl.text = '${t.gradeCounts['D'] ?? 0}';
      gECtrl.text = '${t.gradeCounts['E'] ?? 0}';
      remCtrl.text = t.remarks;
    }

    loadTargetFields(currentTarget);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void syncFromCategories() {
            final sc = _int(scCtrl.text);
            final st = _int(stCtrl.text);
            final obc = _int(obcCtrl.text);
            final oth = _int(otherCtrl.text);
            final tot = sc + st + obc + oth;
            regCtrl.text = '$tot';
            final pres = _int(presCtrl.text).clamp(0, tot);
            absCtrl.text = '${math.max(0, tot - pres)}';
            setDialogState(() {});
          }

          void syncFromPresent() {
            final tot = _int(regCtrl.text);
            final pres = _int(presCtrl.text);
            absCtrl.text = '${math.max(0, tot - pres)}';
            final pass = _int(passCtrl.text);
            failCtrl.text = '${math.max(0, pres - pass)}';
            setDialogState(() {});
          }

          void syncFromGrades() {
            final a = _int(gACtrl.text);
            final b = _int(gBCtrl.text);
            final c = _int(gCCtrl.text);
            final d = _int(gDCtrl.text);
            final e = _int(gECtrl.text);
            final pres = a + b + c + d + e;
            final pass = a + b + c + d;
            final tot = _int(regCtrl.text);
            presCtrl.text = '$pres';
            absCtrl.text = '${math.max(0, tot - pres)}';
            passCtrl.text = '$pass';
            failCtrl.text = '$e';
            setDialogState(() {});
          }

          Widget numField(
            String label,
            TextEditingController ctrl, {
            VoidCallback? onChanged,
            double width = 105,
          }) =>
              SizedBox(
                width: width,
                child: TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => onChanged?.call(),
                  decoration: InputDecoration(
                    labelText: label,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              );

          return AlertDialog(
            title: const Text(
              '✏️ વર્ગવાર પરિણામ આંકડા સુધારો (Admin Edit Present / Absent / Pass / Fail / Grades)',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15.5,
                color: Color(0xFF0B2D5B),
              ),
            ),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: currentTarget.classId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'વર્ગ પસંદ કરો (Select Class to Edit)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _allComputedClassSummaries
                          .map(
                            (c) => DropdownMenuItem<String>(
                              value: c.classId,
                              child: Text(
                                'ધોરણ ${_toGujDigits(c.standardDisplay)} - વિભાગ ${c.sectionDisplay} (${c.classLabel}) ${c.hasMarksInserted ? "✅" : "(ગુણ બાકી)"}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        final next = _allComputedClassSummaries
                            .firstWhere((c) => c.classId == v);
                        setDialogState(() {
                          currentTarget = next;
                          loadTargetFields(next);
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '૧. જાતિવાર નોંધાયેલ સંખ્યા (Registered by Category):',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0B2D5B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        numField('અનુ. જાતિ (SC)', scCtrl,
                            onChanged: syncFromCategories, width: 120),
                        numField('અનુ. જ. જાતિ (ST)', stCtrl,
                            onChanged: syncFromCategories, width: 130),
                        numField('બક્ષીપંચ (OBC)', obcCtrl,
                            onChanged: syncFromCategories, width: 120),
                        numField('અન્ય (Other)', otherCtrl,
                            onChanged: syncFromCategories, width: 115),
                        numField('કુલ નોંધાયેલા', regCtrl,
                            onChanged: syncFromPresent, width: 120),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '૨. ગ્રેડ વિતરણ (A, B, C, D, E) — બદલતાં હાજર/ઉત્તીર્ણ આપોઆપ ગણાશે:',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0B2D5B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        numField('Grade A', gACtrl,
                            onChanged: syncFromGrades, width: 100),
                        numField('Grade B', gBCtrl,
                            onChanged: syncFromGrades, width: 100),
                        numField('Grade C', gCCtrl,
                            onChanged: syncFromGrades, width: 100),
                        numField('Grade D', gDCtrl,
                            onChanged: syncFromGrades, width: 100),
                        numField('Grade E (નાપાસ)', gECtrl,
                            onChanged: syncFromGrades, width: 125),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '૩. હાજર / ગેરહાજર / ઉત્તીર્ણ / અનુત્તીર્ણ (Present / Absent / Pass / Fail):',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0B2D5B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        numField('હાજર (Present)', presCtrl,
                            onChanged: syncFromPresent, width: 130),
                        numField('ગેરહાજર (Absent)', absCtrl, width: 130),
                        numField(
                          'ઉત્તીર્ણ (Passed)',
                          passCtrl,
                          onChanged: () {
                            final pres = _int(presCtrl.text);
                            final pass = _int(passCtrl.text);
                            failCtrl.text = '${math.max(0, pres - pass)}';
                            setDialogState(() {});
                          },
                          width: 130,
                        ),
                        numField('અનુત્તીર્ણ (Failed)', failCtrl, width: 135),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: remCtrl,
                      decoration: const InputDecoration(
                        labelText: 'નોંધ / Remarks (વૈકલ્પિક)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  final ovKey = '$_selectedSemester|${currentTarget.classId}';
                  _adminOverrides.remove(ovKey);
                  await _saveAdminOverrides();
                  if (!mounted) return;
                  setState(() => _recomputeSummaries());
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.restore),
                label: const Text('ઓટો-ફેચ રીસેટ (Reset Auto-Fetch)'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('રદ કરો (Cancel)'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0B2D5B),
                ),
                onPressed: () async {
                  final ovKey = '$_selectedSemester|${currentTarget.classId}';
                  _adminOverrides[ovKey] = <String, dynamic>{
                    'catRegistered': <String, int>{
                      'SC': _int(scCtrl.text),
                      'ST': _int(stCtrl.text),
                      'OBC': _int(obcCtrl.text),
                      'OTHER': _int(otherCtrl.text),
                    },
                    'registeredTotal': _int(regCtrl.text),
                    'appearedTotal': _int(presCtrl.text),
                    'absentTotal': _int(absCtrl.text),
                    'passedTotal': _int(passCtrl.text),
                    'failedTotal': _int(failCtrl.text),
                    'gradeCounts': <String, int>{
                      'A': _int(gACtrl.text),
                      'B': _int(gBCtrl.text),
                      'C': _int(gCCtrl.text),
                      'D': _int(gDCtrl.text),
                      'E': _int(gECtrl.text),
                    },
                    'remarks': remCtrl.text.trim(),
                  };
                  await _saveAdminOverrides();
                  if (!mounted) return;
                  setState(() => _recomputeSummaries());
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('સેવ કરો (Save Changes)'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ===========================================================================
  // DIRECT PDF GENERATION & DOWNLOAD (PACKAGE:PDF WITH RASTERIZED GUJARATI & LOGO)
  // ===========================================================================

  Future<void> _ensurePdfRasterFontLoaded() async {
    if (_pdfRasterFontLoaded) return;
    for (final path in const <String>[
      'assets/fonts/NotoSansGujarati-Regular.ttf',
      'assets/fonts/Lohit-Gujarati.ttf',
      'assets/fonts/NotoSerifGujarati-Regular.ttf',
    ]) {
      try {
        final data = await rootBundle.load(path);
        final loader = FontLoader(_pdfRasterFontFamily)
          ..addFont(Future.value(data));
        await loader.load();
        _pdfRasterFontLoaded = true;
        return;
      } catch (_) {}
    }
  }

  Future<pw.Widget> _pdfText(
    String text, {
    double fontSizePt = 9.5,
    bool bold = false,
    Color color = const Color(0xFF0F172A),
    TextAlign align = TextAlign.center,
    double maxWidthPt = 350,
    int maxLines = 2,
    required Map<String, ({pw.MemoryImage image, double wPt, double hPt})> cache,
  }) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) {
      return pw.SizedBox(height: fontSizePt + 2);
    }
    const dpr = 2.6;
    final safeMaxW = maxWidthPt.clamp(14.0, 900.0).toDouble();
    final key =
        '$cleaned|${fontSizePt.toStringAsFixed(1)}|$bold|${color.toARGB32()}|${align.name}|${safeMaxW.toStringAsFixed(0)}|$maxLines';
    final hit = cache[key];
    if (hit != null) {
      return pw.Align(
        alignment: switch (align) {
          TextAlign.left => pw.Alignment.centerLeft,
          TextAlign.right => pw.Alignment.centerRight,
          _ => pw.Alignment.center,
        },
        child: pw.Image(hit.image, width: hit.wPt, height: hit.hPt),
      );
    }

    final painter = TextPainter(
      text: TextSpan(
        text: cleaned,
        style: TextStyle(
          fontFamily: _pdfRasterFontFamily,
          fontFamilyFallback: const <String>[
            'NotoSansGujaratiLocal',
            'Noto Sans Gujarati',
            'Nirmala UI',
            'Shruti',
            'sans-serif',
          ],
          fontSize: fontSizePt * dpr,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          color: color,
          height: 1.15,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: align,
      maxLines: maxLines,
    )..layout(minWidth: 0, maxWidth: safeMaxW * dpr);

    final imgW = (painter.width.ceil() + 4).clamp(1, 4000).toInt();
    final imgH = (painter.height.ceil() + 4).clamp(1, 1200).toInt();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble()),
    );
    painter.paint(canvas, const ui.Offset(2, 2));
    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(imgW, imgH);
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    uiImage.dispose();
    picture.dispose();
    if (byteData == null) {
      return pw.SizedBox(height: fontSizePt + 2);
    }
    final memImg = pw.MemoryImage(byteData.buffer.asUint8List());
    final wPt = imgW / dpr;
    final hPt = imgH / dpr;
    cache[key] = (image: memImg, wPt: wPt, hPt: hPt);
    return pw.Align(
      alignment: switch (align) {
        TextAlign.left => pw.Alignment.centerLeft,
        TextAlign.right => pw.Alignment.centerRight,
        _ => pw.Alignment.center,
      },
      child: pw.Image(memImg, width: wPt, height: hPt),
    );
  }

  Future<void> _downloadPdf({String mode = 'all_5'}) async {
    if (_generatingPdf) return;
    setState(() => _generatingPdf = true);
    try {
      await _ensurePdfRasterFontLoaded();
      final doc = pw.Document();
      final cache =
          <String, ({pw.MemoryImage image, double wPt, double hPt})>{};
      final logoImg =
          (_schoolLogoBytes != null && _schoolLogoBytes!.isNotEmpty)
              ? pw.MemoryImage(_schoolLogoBytes!)
              : null;

      final includeAll = mode == 'all_5' || mode == 'all_3';

      Future<pw.Widget> buildPdfHeader({
        required String title,
        required String subtitle,
        required List<String> metaItems,
        required double widthPt,
      }) async {
        final authW = await _pdfText(
          _authorityCtrl.text,
          fontSizePt: 11,
          bold: true,
          color: const Color(0xFF0B2D5B),
          maxWidthPt: widthPt - 80,
          cache: cache,
        );
        final schoolW = await _pdfText(
          _lockedSchoolName.isNotEmpty
              ? _lockedSchoolName
              : _schoolNameCtrl.text,
          fontSizePt: 16.5,
          bold: true,
          color: const Color(0xFF0B2D5B),
          maxWidthPt: widthPt - 80,
          cache: cache,
        );
        final addrW = await _pdfText(
          _schoolAddressCtrl.text,
          fontSizePt: 9.5,
          bold: true,
          color: const Color(0xFF0B2D5B),
          maxWidthPt: widthPt - 80,
          cache: cache,
        );
        final titleW = await _pdfText(
          title,
          fontSizePt: 13,
          bold: true,
          color: Colors.white,
          maxWidthPt: widthPt - 16,
          cache: cache,
        );
        final subW = subtitle.isEmpty
            ? null
            : await _pdfText(
                subtitle,
                fontSizePt: 9.5,
                bold: true,
                color: const Color(0xFF0B2D5B),
                maxWidthPt: widthPt - 16,
                cache: cache,
              );
        final metaWidgets = <pw.Widget>[];
        for (final m in metaItems) {
          metaWidgets.add(
            await _pdfText(
              m,
              fontSizePt: 9.5,
              bold: true,
              color: const Color(0xFF0B2D5B),
              maxWidthPt: (widthPt / metaItems.length) - 8,
              cache: cache,
            ),
          );
        }

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logoImg != null)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(right: 10),
                    child: pw.Image(logoImg, width: 44, height: 44),
                  ),
                pw.Column(
                  children: [authW, pw.SizedBox(height: 1), schoolW, addrW],
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Container(
              color: PdfColor.fromInt(0xFF0B2D5B),
              padding:
                  const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              child: titleW,
            ),
            if (subW != null)
              pw.Container(
                color: PdfColor.fromInt(0xFFCFF7EF),
                padding:
                    const pw.EdgeInsets.symmetric(vertical: 2.5, horizontal: 6),
                child: subW,
              ),
            pw.Container(
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF4F8FB),
                border: pw.Border.all(color: PdfColor.fromInt(0xFFCBD5E1)),
              ),
              padding:
                  const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 8),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: metaWidgets,
              ),
            ),
            pw.SizedBox(height: 5),
          ],
        );
      }

      Future<pw.Widget> buildPdfTable({
        required List<String> headers,
        required List<(List<String> cells, PdfColor? bg, Color fg, bool bold)>
            dataRows,
        required double widthPt,
        double fontSizePt = 8.5,
      }) async {
        final colCount = headers.length;
        final colW = widthPt / colCount;
        final tableRows = <pw.TableRow>[];

        final hCells = <pw.Widget>[];
        for (final h in headers) {
          hCells.add(
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 2),
              child: await _pdfText(
                h,
                fontSizePt: fontSizePt,
                bold: true,
                color: Colors.white,
                maxWidthPt: colW - 4,
                cache: cache,
              ),
            ),
          );
        }
        tableRows.add(
          pw.TableRow(
            decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFF0B2D5B)),
            children: hCells,
          ),
        );

        for (final (cells, bg, fg, bold) in dataRows) {
          final rCells = <pw.Widget>[];
          for (var c = 0; c < colCount; c++) {
            final txt = c < cells.length ? cells[c] : '';
            rCells.add(
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(vertical: 2.8, horizontal: 2),
                child: await _pdfText(
                  txt,
                  fontSizePt: fontSizePt,
                  bold: bold,
                  color: fg,
                  maxWidthPt: colW - 4,
                  cache: cache,
                ),
              ),
            );
          }
          tableRows.add(
            pw.TableRow(
              decoration: bg != null ? pw.BoxDecoration(color: bg) : null,
              children: rCells,
            ),
          );
        }

        return pw.Table(
          border: pw.TableBorder.all(
              color: PdfColor.fromInt(0xFF334155), width: 0.6),
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: tableRows,
        );
      }

      final signLeft = await _pdfText(
        'ચકાસણી કરનાર: __________________',
        fontSizePt: 9.5,
        bold: true,
        color: const Color(0xFF0B2D5B),
        cache: cache,
      );
      final signRight = await _pdfText(
        'આચાર્યશ્રી: __________________',
        fontSizePt: 9.5,
        bold: true,
        color: const Color(0xFF0B2D5B),
        cache: cache,
      );

      // Page 1: Format 1 (Class-Section Summary) — A4 Portrait, 1-page fit
      if (includeAll || mode == '1') {
        const pageFmt = PdfPageFormat.a4;
        final wPt = pageFmt.width - 28;
        final hPt = pageFmt.height - 28;
        final hdr = await buildPdfHeader(
          title: 'શાળાનું સંકલિત પરિણામ પત્રક',
          subtitle: 'Category-wise • Class & Section Consolidation',
          metaItems: <String>[
            'શૈક્ષણિક વર્ષ: ${_academicYearCtrl.text}',
            'પરીક્ષા: ${_examNameCtrl.text}',
            'પરિણામ તારીખ: ${_resultDateCtrl.text}',
            'UDISE: $_lockedUdiseCode',
          ],
          widthPt: wPt,
        );
        final f1Rows = <(List<String>, PdfColor?, Color, bool)>[];
        for (final entry in _byStandard.entries) {
          final stdTot = _standardTotals[entry.key]!;
          for (final s in entry.value) {
            f1Rows.add((
              <String>[
                _toGujDigits(s.standardDisplay),
                s.sectionDisplay,
                '${s.catRegistered['SC'] ?? 0}',
                '${s.catRegistered['ST'] ?? 0}',
                '${s.catRegistered['OBC'] ?? 0}',
                '${s.catRegistered['OTHER'] ?? 0}',
                '${s.registeredTotal}',
                '${s.gradeCounts['A'] ?? 0}',
                '${s.gradeCounts['B'] ?? 0}',
                '${s.gradeCounts['C'] ?? 0}',
                '${s.gradeCounts['D'] ?? 0}',
                '${s.gradeCounts['E'] ?? 0}',
              ],
              null,
              const Color(0xFF0F172A),
              false,
            ));
          }
          f1Rows.add((
            <String>[
              _toGujDigits(stdTot.standardDisplay),
              'ધોરણ કુલ',
              '${stdTot.catRegistered['SC'] ?? 0}',
              '${stdTot.catRegistered['ST'] ?? 0}',
              '${stdTot.catRegistered['OBC'] ?? 0}',
              '${stdTot.catRegistered['OTHER'] ?? 0}',
              '${stdTot.registeredTotal}',
              '${stdTot.gradeCounts['A'] ?? 0}',
              '${stdTot.gradeCounts['B'] ?? 0}',
              '${stdTot.gradeCounts['C'] ?? 0}',
              '${stdTot.gradeCounts['D'] ?? 0}',
              '${stdTot.gradeCounts['E'] ?? 0}',
            ],
            PdfColor.fromInt(0xFFCFF7EF),
            const Color(0xFF0B2D5B),
            true,
          ));
        }
        final tot = _wholeSchoolTotal;
        f1Rows.add((
          <String>[
            'સમગ્ર શાળાનો કુલ',
            '—',
            '${tot.catRegistered['SC'] ?? 0}',
            '${tot.catRegistered['ST'] ?? 0}',
            '${tot.catRegistered['OBC'] ?? 0}',
            '${tot.catRegistered['OTHER'] ?? 0}',
            '${tot.registeredTotal}',
            '${tot.gradeCounts['A'] ?? 0}',
            '${tot.gradeCounts['B'] ?? 0}',
            '${tot.gradeCounts['C'] ?? 0}',
            '${tot.gradeCounts['D'] ?? 0}',
            '${tot.gradeCounts['E'] ?? 0}',
          ],
          PdfColor.fromInt(0xFF0B2D5B),
          Colors.white,
          true,
        ));
        final tbl = await buildPdfTable(
          headers: const <String>[
            'ધોરણ',
            'વિભાગ',
            'અનુ. જાતિ',
            'અનુ. જ. જાતિ',
            'બક્ષીપંચ',
            'અન્ય',
            'કુલ',
            'A',
            'B',
            'C',
            'D',
            'E',
          ],
          dataRows: f1Rows,
          widthPt: wPt,
          fontSizePt: 8.5,
        );
        doc.addPage(
          pw.Page(
            pageFormat: pageFmt,
            margin: const pw.EdgeInsets.all(14),
            build: (_) => pw.SizedBox(
              width: wPt,
              height: hPt,
              child: pw.FittedBox(
                fit: pw.BoxFit.scaleDown,
                alignment: pw.Alignment.topCenter,
                child: pw.SizedBox(
                  width: wPt,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      hdr,
                      tbl,
                      pw.SizedBox(height: 16),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [signLeft, signRight],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }

      // Page 2: Format 2 (Category-Grade Detail) — A4 Landscape, 1-page fit
      if (includeAll || mode == '2') {
        final pageFmt = PdfPageFormat.a4.landscape;
        final wPt = pageFmt.width - 28;
        final hPt = pageFmt.height - 28;
        final det = _selectedDetailSummary;
        final hdr = await buildPdfHeader(
          title: 'શાળાનું વર્ગવાર વિગતવાર પરિણામ પત્રક',
          subtitle: '',
          metaItems: <String>[
            'શૈક્ષણિક વર્ષ: ${_academicYearCtrl.text}',
            'ધોરણ: ${_selectedClassIdForDetail == '__ALL__' ? 'તમામ' : _toGujDigits(det.standardDisplay)}',
            'વિભાગ: ${_selectedClassIdForDetail == '__ALL__' ? 'તમામ' : det.sectionDisplay}',
            'પરિણામ તારીખ: ${_resultDateCtrl.text}',
          ],
          widthPt: wPt,
        );

        Future<pw.Widget> buildCatGradePdfTable(
            _ClassSectionResultSummary sumObj) async {
          const cats = <(String, String)>[
            ('SC', 'અનુ. જાતિ'),
            ('ST', 'અનુ. જ. જાતિ'),
            ('OBC', 'બક્ષીપંચ'),
            ('OTHER', 'અન્ય'),
          ];
          const grades = <String>['A', 'B', 'C', 'D', 'E'];
          final totCols = List<int>.filled(18, 0);
          final rows = <(List<String>, PdfColor?, Color, bool)>[];
          for (final (cKey, cLbl) in cats) {
            final rB = sumObj.catGenderRegistered[cKey]?['BOYS'] ?? 0;
            final rG = sumObj.catGenderRegistered[cKey]?['GIRLS'] ?? 0;
            final rT = rB + rG;
            totCols[0] += rB;
            totCols[1] += rG;
            totCols[2] += rT;
            final cells = <String>[cLbl, '$rB', '$rG', '$rT'];
            for (var gIdx = 0; gIdx < grades.length; gIdx++) {
              final g = grades[gIdx];
              final gB = sumObj.catGradeGenderCounts[cKey]?[g]?['BOYS'] ?? 0;
              final gG = sumObj.catGradeGenderCounts[cKey]?[g]?['GIRLS'] ?? 0;
              final gT = gB + gG;
              totCols[3 + gIdx * 3] += gB;
              totCols[3 + gIdx * 3 + 1] += gG;
              totCols[3 + gIdx * 3 + 2] += gT;
              cells.addAll(<String>['$gB', '$gG', '$gT']);
            }
            cells.add(sumObj.remarks);
            rows.add((cells, null, const Color(0xFF0F172A), false));
          }
          rows.add((
            <String>['કુલ', ...totCols.map((v) => '$v'), ''],
            PdfColor.fromInt(0xFFCFF7EF),
            const Color(0xFF0B2D5B),
            true,
          ));
          return buildPdfTable(
            headers: <String>[
              'જાતિ',
              'રજી. કુમાર',
              'રજી. કન્યા',
              'રજી. કુલ',
              for (final g in grades) ...<String>[
                '$g કુમાર',
                '$g કન્યા',
                '$g કુલ'
              ],
              'નોંધ',
            ],
            dataRows: rows,
            widthPt: wPt,
            fontSizePt: 7.5,
          );
        }

        final tblTop = await buildCatGradePdfTable(det);
        final wholeBanner = await _pdfText(
          'સમગ્ર શાળાનો કુલ સારાંશ | તમામ ધોરણો અને વિભાગો',
          fontSizePt: 11,
          bold: true,
          color: Colors.white,
          maxWidthPt: wPt - 16,
          cache: cache,
        );
        final tblBottom = await buildCatGradePdfTable(_wholeSchoolTotal);

        doc.addPage(
          pw.Page(
            pageFormat: pageFmt,
            margin: const pw.EdgeInsets.all(14),
            build: (_) => pw.SizedBox(
              width: wPt,
              height: hPt,
              child: pw.FittedBox(
                fit: pw.BoxFit.scaleDown,
                alignment: pw.Alignment.topCenter,
                child: pw.SizedBox(
                  width: wPt,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      hdr,
                      tblTop,
                      pw.SizedBox(height: 8),
                      pw.Container(
                        color: PdfColor.fromInt(0xFF0B2D5B),
                        padding: const pw.EdgeInsets.symmetric(
                            vertical: 4, horizontal: 6),
                        child: wholeBanner,
                      ),
                      pw.SizedBox(height: 3),
                      tblBottom,
                      pw.SizedBox(height: 14),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [signLeft, signRight],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }

      // Page 3: Format 3 (Whole School Performance) — A4 Landscape, 1-page fit
      if (includeAll || mode == '3') {
        final pageFmt = PdfPageFormat.a4.landscape;
        final wPt = pageFmt.width - 28;
        final hPt = pageFmt.height - 28;
        final hdr = await buildPdfHeader(
          title: 'સમગ્ર શાળાનું પરિણામ સારાંશ',
          subtitle: 'ધોરણવાર અને વિભાગવાર સંકલિત અહેવાલ',
          metaItems: <String>[
            'શૈક્ષણિક વર્ષ: ${_academicYearCtrl.text}',
            'પરીક્ષા: ${_examNameCtrl.text}',
            'પરિણામ તારીખ: ${_resultDateCtrl.text}',
            'UDISE: $_lockedUdiseCode',
          ],
          widthPt: wPt,
        );
        final tot = _wholeSchoolTotal;
        final kpiTbl = await buildPdfTable(
          headers: const <String>[
            'કુલ નોંધાયેલા',
            'કુલ હાજર',
            'કુલ ઉત્તીર્ણ',
            'શાળા પરિણામ %',
          ],
          dataRows: <(List<String>, PdfColor?, Color, bool)>[
            (
              <String>[
                '${tot.registeredTotal}',
                '${tot.appearedTotal}',
                '${tot.passedTotal}',
                '${tot.resultPercent.toStringAsFixed(2)}%',
              ],
              PdfColor.fromInt(0xFFFFFFFF),
              const Color(0xFF0B2D5B),
              true,
            ),
          ],
          widthPt: wPt,
          fontSizePt: 10,
        );

        final f3Rows = <(List<String>, PdfColor?, Color, bool)>[];
        for (final entry in _byStandard.entries) {
          final stdTot = _standardTotals[entry.key]!;
          for (final s in entry.value) {
            f3Rows.add((
              <String>[
                _toGujDigits(s.standardDisplay),
                s.sectionDisplay,
                '${s.registeredTotal}',
                '${s.appearedTotal}',
                '${s.absentTotal}',
                '${s.passedTotal}',
                '${s.failedTotal}',
                '${s.resultPercent.toStringAsFixed(2)}%',
                '${s.gradeCounts['A'] ?? 0}',
                '${s.gradeCounts['B'] ?? 0}',
                '${s.gradeCounts['C'] ?? 0}',
                '${s.gradeCounts['D'] ?? 0}',
                '${s.gradeCounts['E'] ?? 0}',
                s.remarks,
              ],
              null,
              const Color(0xFF0F172A),
              false,
            ));
          }
          f3Rows.add((
            <String>[
              _toGujDigits(stdTot.standardDisplay),
              'ધોરણ કુલ',
              '${stdTot.registeredTotal}',
              '${stdTot.appearedTotal}',
              '${stdTot.absentTotal}',
              '${stdTot.passedTotal}',
              '${stdTot.failedTotal}',
              '${stdTot.resultPercent.toStringAsFixed(2)}%',
              '${stdTot.gradeCounts['A'] ?? 0}',
              '${stdTot.gradeCounts['B'] ?? 0}',
              '${stdTot.gradeCounts['C'] ?? 0}',
              '${stdTot.gradeCounts['D'] ?? 0}',
              '${stdTot.gradeCounts['E'] ?? 0}',
              '',
            ],
            PdfColor.fromInt(0xFFCFF7EF),
            const Color(0xFF0B2D5B),
            true,
          ));
        }
        f3Rows.add((
          <String>[
            'સમગ્ર શાળાનો કુલ',
            '—',
            '${tot.registeredTotal}',
            '${tot.appearedTotal}',
            '${tot.absentTotal}',
            '${tot.passedTotal}',
            '${tot.failedTotal}',
            '${tot.resultPercent.toStringAsFixed(2)}%',
            '${tot.gradeCounts['A'] ?? 0}',
            '${tot.gradeCounts['B'] ?? 0}',
            '${tot.gradeCounts['C'] ?? 0}',
            '${tot.gradeCounts['D'] ?? 0}',
            '${tot.gradeCounts['E'] ?? 0}',
            '',
          ],
          PdfColor.fromInt(0xFF0B2D5B),
          Colors.white,
          true,
        ));
        final tbl = await buildPdfTable(
          headers: const <String>[
            'ધોરણ',
            'વિભાગ',
            'નોંધાયેલા',
            'હાજર',
            'ગેરહાજર',
            'ઉત્તીર્ણ',
            'અનુત્તીર્ણ',
            'પરિણામ %',
            'A',
            'B',
            'C',
            'D',
            'E',
            'નોંધ',
          ],
          dataRows: f3Rows,
          widthPt: wPt,
          fontSizePt: 8.5,
        );

        doc.addPage(
          pw.Page(
            pageFormat: pageFmt,
            margin: const pw.EdgeInsets.all(14),
            build: (_) => pw.SizedBox(
              width: wPt,
              height: hPt,
              child: pw.FittedBox(
                fit: pw.BoxFit.scaleDown,
                alignment: pw.Alignment.topCenter,
                child: pw.SizedBox(
                  width: wPt,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      hdr,
                      kpiTbl,
                      pw.SizedBox(height: 6),
                      tbl,
                      pw.SizedBox(height: 14),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [signLeft, signRight],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }

      Future<void> addRankersPdfPage({
        required String subtitle,
        required List<_RankerStudentEntry> entries,
      }) async {
        const pageFmt = PdfPageFormat.a4;
        final wPt = pageFmt.width - 28;
        final hPt = pageFmt.height - 28;
        final hdr = await buildPdfHeader(
          title: 'શાળાનું સંકલિત પરિણામ પત્રક',
          subtitle: subtitle,
          metaItems: <String>[
            'શૈક્ષણિક વર્ષ: ${_academicYearCtrl.text}',
            'પરીક્ષા: ${_examNameCtrl.text}',
            'પરિણામ તારીખ: ${_resultDateCtrl.text}',
            'UDISE: $_lockedUdiseCode',
          ],
          widthPt: wPt,
        );

        final dataRows = <(List<String>, PdfColor?, Color, bool)>[];
        if (entries.isEmpty) {
          dataRows.add((
            const <String>[
              '—',
              'કોઈ ગુણ દાખલ થયેલ નથી',
              '—',
              '0',
              '0',
              '0.00%',
              '—',
            ],
            null,
            const Color(0xFF0F172A),
            false,
          ));
        } else {
          for (var i = 0; i < entries.length; i++) {
            final e = entries[i];
            final bg = e.rank == 1
                ? PdfColor.fromInt(0xFFFEF9C3)
                : (e.rank == 2 ? PdfColor.fromInt(0xFFF0FDF4) : null);
            dataRows.add((
              <String>[
                '${i + 1}',
                e.studentName,
                e.classWithSection,
                '${e.totalMarks}',
                '${e.obtainedMarks}',
                '${e.percentage.toStringAsFixed(2)}%',
                _rankDisplayLabel(e.rank),
              ],
              bg,
              const Color(0xFF0F172A),
              e.rank == 1,
            ));
          }
        }

        final tbl = await buildPdfTable(
          headers: const <String>[
            'ક્રમ',
            'વિદ્યાર્થીનું નામ',
            'ધોરણ - વર્ગ',
            'કુલ ગુણ',
            'મેળવેલ ગુણ',
            'ટકાવારી %',
            'ક્રમાંક (Rank)',
          ],
          dataRows: dataRows,
          widthPt: wPt,
          fontSizePt: 8.5,
        );

        doc.addPage(
          pw.Page(
            pageFormat: pageFmt,
            margin: const pw.EdgeInsets.all(14),
            build: (_) => pw.SizedBox(
              width: wPt,
              height: hPt,
              child: pw.FittedBox(
                fit: pw.BoxFit.scaleDown,
                alignment: pw.Alignment.topCenter,
                child: pw.SizedBox(
                  width: wPt,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      hdr,
                      tbl,
                      pw.SizedBox(height: 16),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [signLeft, signRight],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }

      // Page 4: Format 4 (Section-Wise Top 3 Rankers)
      if (includeAll || mode == '4') {
        await addRankersPdfPage(
          subtitle:
              'વર્ગ અને વિભાગવાર પ્રથમ ૩ ક્રમાંકિત વિદ્યાર્થીઓની યાદી (Section-Wise Top 3 Rankers)',
          entries: _sectionWiseRankers,
        );
      }

      // Page 5: Format 5 (Class-Wise Top 3 Rankers)
      if (includeAll || mode == '5') {
        await addRankersPdfPage(
          subtitle:
              'ધોરણવાર પ્રથમ ૩ ક્રમાંકિત વિદ્યાર્થીઓની યાદી (Class-Wise Top 3 Rankers)',
          entries: _classWiseRankers,
        );
      }

      final bytes = await doc.save();
      final fileName =
          'Whole_School_Result_Summary_Sem_${_selectedSemester}_$mode.pdf';
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile.fromData(
              Uint8List.fromList(bytes),
              mimeType: 'application/pdf',
              name: fileName,
            ),
          ],
          text: fileName,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF સફળતાપૂર્વક ડાઉનલોડ થઈ: $fileName')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text('PDF generation failed: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  // ===========================================================================
  // 1-CLICK PRINT VIA HIDDEN IFRAME (NO about:blank TAB, PROPER 1-PAGE SETUP)
  // ===========================================================================

  Future<void> _printResultSummaries({String mode = 'all_5'}) async {
    String? logoDataUri;
    if (_schoolLogoBytes != null && _schoolLogoBytes!.isNotEmpty) {
      logoDataUri = 'data:image/png;base64,${base64Encode(_schoolLogoBytes!)}';
    }
    final htmlDoc = _buildPrintHtml(mode: mode, logoDataUri: logoDataUri);
    final win = openRojmelPrintWindow();
    if (win != null) {
      writeRojmelPrintDocument(win, htmlDoc);
    }
  }

  String _esc(String v) => const HtmlEscape().convert(v);

  String _buildSchoolHeaderHtml({
    required String reportTitle,
    required String reportSubtitle,
    required String? logoDataUri,
    required List<String> metaItems,
  }) {
    final displaySchoolName = _lockedSchoolName.isNotEmpty
        ? _lockedSchoolName
        : _schoolNameCtrl.text;
    final logoHtml = (logoDataUri != null && logoDataUri.isNotEmpty)
        ? '<img src="$logoDataUri" style="width:54px;height:54px;object-fit:contain;margin-right:12px;" />'
        : '';
    final metaCells = metaItems
        .map((m) =>
            '<td style="padding:4px 8px;font-weight:700;color:#0B2D5B;font-size:9.8pt;">${_esc(m)}</td>')
        .join();
    return '''
      <div style="display:flex;align-items:center;justify-content:center;margin-bottom:4px;">
        $logoHtml
        <div style="text-align:center;">
          <div style="font-size:11pt;font-weight:800;color:#0B2D5B;">${_esc(_authorityCtrl.text)}</div>
          <div style="font-size:17.5pt;font-weight:900;color:#0B2D5B;line-height:1.12;">${_esc(displaySchoolName)}</div>
          <div style="font-size:10pt;font-weight:700;color:#0B2D5B;">${_esc(_schoolAddressCtrl.text)}</div>
        </div>
      </div>
      <div style="background:#0B2D5B;color:#FFFFFF;text-align:center;font-size:13.5pt;font-weight:900;padding:4px 8px;letter-spacing:0.2px;">
        ${_esc(reportTitle)}
      </div>
      ${reportSubtitle.isNotEmpty ? '<div style="background:#CFF7EF;color:#0B2D5B;text-align:center;font-size:10pt;font-weight:800;padding:2.5px 8px;">${_esc(reportSubtitle)}</div>' : ''}
      <table style="width:100%;border-collapse:collapse;background:#F4F8FB;border:1px solid #CBD5E1;margin-bottom:6px;">
        <tr>$metaCells</tr>
      </table>
    ''';
  }

  String _buildFormat1Html(String? logoDataUri) {
    final rowsHtml = StringBuffer();
    for (final entry in _byStandard.entries) {
      final stdKey = entry.key;
      final sections = entry.value;
      final stdTot = _standardTotals[stdKey]!;
      for (final s in sections) {
        rowsHtml.writeln('''
          <tr>
            <td>${_esc(_toGujDigits(s.standardDisplay))}</td>
            <td>${_esc(s.sectionDisplay)}</td>
            <td>${s.catRegistered['SC'] ?? 0}</td>
            <td>${s.catRegistered['ST'] ?? 0}</td>
            <td>${s.catRegistered['OBC'] ?? 0}</td>
            <td>${s.catRegistered['OTHER'] ?? 0}</td>
            <td style="font-weight:800;">${s.registeredTotal}</td>
            <td>${s.gradeCounts['A'] ?? 0}</td>
            <td>${s.gradeCounts['B'] ?? 0}</td>
            <td>${s.gradeCounts['C'] ?? 0}</td>
            <td>${s.gradeCounts['D'] ?? 0}</td>
            <td>${s.gradeCounts['E'] ?? 0}</td>
          </tr>
        ''');
      }
      rowsHtml.writeln('''
        <tr style="background:#CFF7EF;font-weight:800;color:#0B2D5B;">
          <td>${_esc(_toGujDigits(stdTot.standardDisplay))}</td>
          <td>ધોરણ કુલ</td>
          <td>${stdTot.catRegistered['SC'] ?? 0}</td>
          <td>${stdTot.catRegistered['ST'] ?? 0}</td>
          <td>${stdTot.catRegistered['OBC'] ?? 0}</td>
          <td>${stdTot.catRegistered['OTHER'] ?? 0}</td>
          <td>${stdTot.registeredTotal}</td>
          <td>${stdTot.gradeCounts['A'] ?? 0}</td>
          <td>${stdTot.gradeCounts['B'] ?? 0}</td>
          <td>${stdTot.gradeCounts['C'] ?? 0}</td>
          <td>${stdTot.gradeCounts['D'] ?? 0}</td>
          <td>${stdTot.gradeCounts['E'] ?? 0}</td>
        </tr>
      ''');
    }

    final tot = _wholeSchoolTotal;
    rowsHtml.writeln('''
      <tr style="background:#0B2D5B;color:#FFFFFF;font-weight:900;">
        <td colspan="2">સમગ્ર શાળાનો કુલ</td>
        <td>${tot.catRegistered['SC'] ?? 0}</td>
        <td>${tot.catRegistered['ST'] ?? 0}</td>
        <td>${tot.catRegistered['OBC'] ?? 0}</td>
        <td>${tot.catRegistered['OTHER'] ?? 0}</td>
        <td>${tot.registeredTotal}</td>
        <td>${tot.gradeCounts['A'] ?? 0}</td>
        <td>${tot.gradeCounts['B'] ?? 0}</td>
        <td>${tot.gradeCounts['C'] ?? 0}</td>
        <td>${tot.gradeCounts['D'] ?? 0}</td>
        <td>${tot.gradeCounts['E'] ?? 0}</td>
      </tr>
    ''');

    return '''
      <div class="summary-page"><div class="summary-page-inner">
        ${_buildSchoolHeaderHtml(
          reportTitle: 'શાળાનું સંકલિત પરિણામ પત્રક',
          reportSubtitle: 'Category-wise • Class & Section Consolidation',
          logoDataUri: logoDataUri,
          metaItems: <String>[
            'શૈક્ષણિક વર્ષ: ${_academicYearCtrl.text}',
            'પરીક્ષા: ${_examNameCtrl.text}',
            'પરિણામ તારીખ: ${_resultDateCtrl.text}',
            'UDISE: $_lockedUdiseCode',
          ],
        )}
        <table class="grid-table">
          <thead>
            <tr style="background:#0B2D5B;color:#FFFFFF;font-weight:800;">
              <th rowspan="2">ધોરણ</th>
              <th rowspan="2">વિભાગ</th>
              <th colspan="4">જાતિવાર વિદ્યાર્થી સંખ્યા</th>
              <th rowspan="2">કુલ</th>
              <th colspan="5">ગ્રેડ વિતરણ</th>
            </tr>
            <tr style="background:#0B2D5B;color:#FFFFFF;font-weight:800;">
              <th>અનુ. જાતિ</th>
              <th>અનુ. જ. જાતિ</th>
              <th>બક્ષીપંચ</th>
              <th>અન્ય</th>
              <th>A</th>
              <th>B</th>
              <th>C</th>
              <th>D</th>
              <th>E</th>
            </tr>
          </thead>
          <tbody>
            $rowsHtml
          </tbody>
        </table>
        <div class="sign-row">
          <div>ચકાસણી કરનાર: __________________</div>
          <div>આચાર્યશ્રી: __________________</div>
        </div>
      </div></div>
    ''';
  }

  String _buildCategoryGradeTableHtml(_ClassSectionResultSummary summary) {
    const cats = <(String, String)>[
      ('SC', 'અનુ. જાતિ'),
      ('ST', 'અનુ. જ. જાતિ'),
      ('OBC', 'બક્ષીપંચ'),
      ('OTHER', 'અન્ય'),
    ];
    const grades = <String>['A', 'B', 'C', 'D', 'E'];

    final rowsHtml = StringBuffer();
    int totRegB = 0, totRegG = 0;
    final totGradeB = <String, int>{for (final g in grades) g: 0};
    final totGradeG = <String, int>{for (final g in grades) g: 0};

    for (final (cKey, cLabel) in cats) {
      final rB = summary.catGenderRegistered[cKey]?['BOYS'] ?? 0;
      final rG = summary.catGenderRegistered[cKey]?['GIRLS'] ?? 0;
      final rT = rB + rG;
      totRegB += rB;
      totRegG += rG;

      final gradeCells = StringBuffer();
      for (final g in grades) {
        final gB = summary.catGradeGenderCounts[cKey]?[g]?['BOYS'] ?? 0;
        final gG = summary.catGradeGenderCounts[cKey]?[g]?['GIRLS'] ?? 0;
        final gT = gB + gG;
        totGradeB[g] = (totGradeB[g] ?? 0) + gB;
        totGradeG[g] = (totGradeG[g] ?? 0) + gG;
        gradeCells.write(
            '<td>$gB</td><td>$gG</td><td style="font-weight:700;">$gT</td>');
      }

      rowsHtml.writeln('''
        <tr>
          <td style="text-align:left;padding-left:6px;font-weight:700;">$cLabel</td>
          <td>$rB</td>
          <td>$rG</td>
          <td style="font-weight:700;">$rT</td>
          $gradeCells
          <td>${_esc(summary.remarks)}</td>
        </tr>
      ''');
    }

    final totGradeCells = StringBuffer();
    for (final g in grades) {
      final b = totGradeB[g] ?? 0;
      final gr = totGradeG[g] ?? 0;
      totGradeCells.write('<td>$b</td><td>$gr</td><td>${b + gr}</td>');
    }

    rowsHtml.writeln('''
      <tr style="background:#CFF7EF;font-weight:900;color:#0B2D5B;">
        <td style="text-align:left;padding-left:6px;">કુલ</td>
        <td>$totRegB</td>
        <td>$totRegG</td>
        <td>${totRegB + totRegG}</td>
        $totGradeCells
        <td></td>
      </tr>
    ''');

    return '''
      <table class="grid-table" style="margin-bottom:8px;">
        <thead>
          <tr style="background:#E8EEF3;color:#0B2D5B;font-weight:800;">
            <th rowspan="3">જાતિ</th>
            <th colspan="3" rowspan="2">રજી. સંખ્યા</th>
            <th colspan="15">મેળવેલ એકંદર ગ્રેડ</th>
            <th rowspan="3">નોંધ</th>
          </tr>
          <tr style="background:#E8EEF3;color:#0B2D5B;font-weight:800;">
            <th colspan="3">A</th>
            <th colspan="3">B</th>
            <th colspan="3">C</th>
            <th colspan="3">D</th>
            <th colspan="3">E</th>
          </tr>
          <tr style="background:#E8EEF3;color:#0B2D5B;font-weight:800;">
            <th>કુમાર</th><th>કન્યા</th><th>કુલ</th>
            <th>કુમાર</th><th>કન્યા</th><th>કુલ</th>
            <th>કુમાર</th><th>કન્યા</th><th>કુલ</th>
            <th>કુમાર</th><th>કન્યા</th><th>કુલ</th>
            <th>કુમાર</th><th>કન્યા</th><th>કુલ</th>
            <th>કુમાર</th><th>કન્યા</th><th>કુલ</th>
          </tr>
        </thead>
        <tbody>
          $rowsHtml
        </tbody>
      </table>
    ''';
  }

  String _buildFormat2Html(String? logoDataUri) {
    final topSummary = _selectedDetailSummary;
    final stdLabel = _selectedClassIdForDetail == '__ALL__'
        ? 'તમામ ધોરણો'
        : _toGujDigits(topSummary.standardDisplay);
    final secLabel = _selectedClassIdForDetail == '__ALL__'
        ? 'તમામ વિભાગો'
        : topSummary.sectionDisplay;

    final extraClassesHtml = StringBuffer();
    if (_includeAllClassesInFormat2Print) {
      for (final c in _classSummaries) {
        extraClassesHtml.writeln('''
          <div style="background:#0B2D5B;color:#FFFFFF;font-weight:800;padding:3px 8px;margin-top:6px;">
            ધોરણ: ${_esc(_toGujDigits(c.standardDisplay))} | વિભાગ: ${_esc(c.sectionDisplay)} (${_esc(c.classLabel)})
          </div>
          ${_buildCategoryGradeTableHtml(c)}
        ''');
      }
    } else {
      extraClassesHtml.writeln(_buildCategoryGradeTableHtml(topSummary));
    }

    return '''
      <div class="summary-page"><div class="summary-page-inner">
        ${_buildSchoolHeaderHtml(
          reportTitle: 'શાળાનું વર્ગવાર વિગતવાર પરિણામ પત્રક',
          reportSubtitle: '',
          logoDataUri: logoDataUri,
          metaItems: <String>[
            'શૈક્ષણિક વર્ષ: ${_academicYearCtrl.text}',
            'ધોરણ: $stdLabel',
            'વિભાગ: $secLabel',
            'પરિણામ તારીખ: ${_resultDateCtrl.text}',
          ],
        )}
        $extraClassesHtml
        <div style="background:#0B2D5B;color:#FFFFFF;text-align:center;font-size:11.5pt;font-weight:900;padding:4px 8px;margin-top:6px;">
          સમગ્ર શાળાનો કુલ સારાંશ | તમામ ધોરણો અને વિભાગો
        </div>
        ${_buildCategoryGradeTableHtml(_wholeSchoolTotal)}
        <div class="sign-row">
          <div>વર્ગ શિક્ષક / ચકાસણી કરનાર: __________________</div>
          <div>આચાર્યશ્રી: __________________</div>
        </div>
      </div></div>
    ''';
  }

  String _buildFormat3Html(String? logoDataUri) {
    final tot = _wholeSchoolTotal;
    final rowsHtml = StringBuffer();
    for (final entry in _byStandard.entries) {
      final stdKey = entry.key;
      final sections = entry.value;
      final stdTot = _standardTotals[stdKey]!;
      for (final s in sections) {
        rowsHtml.writeln('''
          <tr>
            <td>${_esc(_toGujDigits(s.standardDisplay))}</td>
            <td>${_esc(s.sectionDisplay)}</td>
            <td>${s.registeredTotal}</td>
            <td>${s.appearedTotal}</td>
            <td>${s.absentTotal}</td>
            <td>${s.passedTotal}</td>
            <td>${s.failedTotal}</td>
            <td style="font-weight:700;">${s.resultPercent.toStringAsFixed(2)}%</td>
            <td>${s.gradeCounts['A'] ?? 0}</td>
            <td>${s.gradeCounts['B'] ?? 0}</td>
            <td>${s.gradeCounts['C'] ?? 0}</td>
            <td>${s.gradeCounts['D'] ?? 0}</td>
            <td>${s.gradeCounts['E'] ?? 0}</td>
            <td>${_esc(s.remarks)}</td>
          </tr>
        ''');
      }
      rowsHtml.writeln('''
        <tr style="background:#CFF7EF;font-weight:800;color:#0B2D5B;">
          <td>${_esc(_toGujDigits(stdTot.standardDisplay))}</td>
          <td>ધોરણ કુલ</td>
          <td>${stdTot.registeredTotal}</td>
          <td>${stdTot.appearedTotal}</td>
          <td>${stdTot.absentTotal}</td>
          <td>${stdTot.passedTotal}</td>
          <td>${stdTot.failedTotal}</td>
          <td>${stdTot.resultPercent.toStringAsFixed(2)}%</td>
          <td>${stdTot.gradeCounts['A'] ?? 0}</td>
          <td>${stdTot.gradeCounts['B'] ?? 0}</td>
          <td>${stdTot.gradeCounts['C'] ?? 0}</td>
          <td>${stdTot.gradeCounts['D'] ?? 0}</td>
          <td>${stdTot.gradeCounts['E'] ?? 0}</td>
          <td></td>
        </tr>
      ''');
    }

    rowsHtml.writeln('''
      <tr style="background:#0B2D5B;color:#FFFFFF;font-weight:900;">
        <td colspan="2">સમગ્ર શાળાનો કુલ</td>
        <td>${tot.registeredTotal}</td>
        <td>${tot.appearedTotal}</td>
        <td>${tot.absentTotal}</td>
        <td>${tot.passedTotal}</td>
        <td>${tot.failedTotal}</td>
        <td>${tot.resultPercent.toStringAsFixed(2)}%</td>
        <td>${tot.gradeCounts['A'] ?? 0}</td>
        <td>${tot.gradeCounts['B'] ?? 0}</td>
        <td>${tot.gradeCounts['C'] ?? 0}</td>
        <td>${tot.gradeCounts['D'] ?? 0}</td>
        <td>${tot.gradeCounts['E'] ?? 0}</td>
        <td></td>
      </tr>
    ''');

    return '''
      <div class="summary-page"><div class="summary-page-inner">
        ${_buildSchoolHeaderHtml(
          reportTitle: 'સમગ્ર શાળાનું પરિણામ સારાંશ',
          reportSubtitle: 'ધોરણવાર અને વિભાગવાર સંકલિત અહેવાલ',
          logoDataUri: logoDataUri,
          metaItems: <String>[
            'શૈક્ષણિક વર્ષ: ${_academicYearCtrl.text}',
            'પરીક્ષા: ${_examNameCtrl.text}',
            'પરિણામ તારીખ: ${_resultDateCtrl.text}',
            'UDISE: $_lockedUdiseCode',
          ],
        )}
        <table style="width:100%;border-collapse:collapse;margin-bottom:6px;text-align:center;">
          <tr style="background:#087F7A;color:#FFFFFF;font-weight:800;font-size:9.5pt;">
            <td style="border:1px solid #0B2D5B;padding:3.5px;width:25%;">કુલ નોંધાયેલા</td>
            <td style="border:1px solid #0B2D5B;padding:3.5px;width:25%;">કુલ હાજર</td>
            <td style="border:1px solid #0B2D5B;padding:3.5px;width:25%;">કુલ ઉત્તીર્ણ</td>
            <td style="border:1px solid #0B2D5B;padding:3.5px;width:25%;">શાળા પરિણામ %</td>
          </tr>
          <tr style="background:#FFFFFF;color:#0B2D5B;font-weight:900;font-size:12pt;">
            <td style="border:1px solid #0B2D5B;padding:4px;">${tot.registeredTotal}</td>
            <td style="border:1px solid #0B2D5B;padding:4px;">${tot.appearedTotal}</td>
            <td style="border:1px solid #0B2D5B;padding:4px;">${tot.passedTotal}</td>
            <td style="border:1px solid #0B2D5B;padding:4px;">${tot.resultPercent.toStringAsFixed(2)}%</td>
          </tr>
        </table>
        <table class="grid-table">
          <thead>
            <tr style="background:#0B2D5B;color:#FFFFFF;font-weight:800;">
              <th rowspan="2">ધોરણ</th>
              <th rowspan="2">વિભાગ</th>
              <th rowspan="2">નોંધાયેલા</th>
              <th rowspan="2">હાજર</th>
              <th rowspan="2">ગેરહાજર</th>
              <th rowspan="2">ઉત્તીર્ણ</th>
              <th rowspan="2">અનુત્તીર્ણ</th>
              <th rowspan="2">પરિણામ %</th>
              <th colspan="5">ગ્રેડ વિતરણ</th>
              <th rowspan="2">નોંધ</th>
            </tr>
            <tr style="background:#0B2D5B;color:#FFFFFF;font-weight:800;">
              <th>A</th>
              <th>B</th>
              <th>C</th>
              <th>D</th>
              <th>E</th>
            </tr>
          </thead>
          <tbody>
            $rowsHtml
          </tbody>
        </table>
        <div class="sign-row">
          <div>ચકાસણી કરનાર: __________________</div>
          <div>આચાર્યશ્રી: __________________</div>
        </div>
      </div></div>
    ''';
  }

  String _buildRankersHtml({
    required String? logoDataUri,
    required String reportSubtitle,
    required List<_RankerStudentEntry> entries,
  }) {
    final rowsHtml = StringBuffer();
    if (entries.isEmpty) {
      rowsHtml.writeln('''
        <tr>
          <td colspan="7" style="padding:10px;font-weight:700;">આ સત્રમાં હજુ કોઈ વર્ગના ગુણ દાખલ થયેલ નથી.</td>
        </tr>
      ''');
    } else {
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        final bgStyle = e.rank == 1
            ? 'background:#FEF9C3;font-weight:800;'
            : (e.rank == 2 ? 'background:#F0FDF4;font-weight:700;' : '');
        rowsHtml.writeln('''
          <tr style="$bgStyle">
            <td>${i + 1}</td>
            <td style="text-align:left;padding-left:8px;font-weight:700;">${_esc(e.studentName)}</td>
            <td>${_esc(e.classWithSection)}</td>
            <td>${e.totalMarks}</td>
            <td style="font-weight:800;">${e.obtainedMarks}</td>
            <td style="font-weight:800;">${e.percentage.toStringAsFixed(2)}%</td>
            <td style="font-weight:900;color:#0B2D5B;">${_esc(_rankDisplayLabel(e.rank))}</td>
          </tr>
        ''');
      }
    }

    return '''
      <div class="summary-page"><div class="summary-page-inner">
        ${_buildSchoolHeaderHtml(
          reportTitle: 'શાળાનું સંકલિત પરિણામ પત્રક',
          reportSubtitle: reportSubtitle,
          logoDataUri: logoDataUri,
          metaItems: <String>[
            'શૈક્ષણિક વર્ષ: ${_academicYearCtrl.text}',
            'પરીક્ષા: ${_examNameCtrl.text}',
            'પરિણામ તારીખ: ${_resultDateCtrl.text}',
            'UDISE: $_lockedUdiseCode',
          ],
        )}
        <table class="grid-table">
          <thead>
            <tr style="background:#0B2D5B;color:#FFFFFF;font-weight:800;">
              <th style="width:7%;">ક્રમ</th>
              <th style="width:33%;">વિદ્યાર્થીનું નામ</th>
              <th style="width:16%;">ધોરણ - વર્ગ</th>
              <th style="width:11%;">કુલ ગુણ</th>
              <th style="width:11%;">મેળવેલ ગુણ</th>
              <th style="width:11%;">ટકાવારી %</th>
              <th style="width:11%;">ક્રમાંક (Rank)</th>
            </tr>
          </thead>
          <tbody>
            $rowsHtml
          </tbody>
        </table>
        <div class="sign-row">
          <div>ચકાસણી કરનાર: __________________</div>
          <div>આચાર્યશ્રી: __________________</div>
        </div>
      </div></div>
    ''';
  }

  String _buildPrintHtml({
    required String mode,
    required String? logoDataUri,
  }) {
    final includeAll = mode == 'all_5' || mode == 'all_3';
    final pages = <String>[];
    if (includeAll || mode == '1') {
      pages.add(_buildFormat1Html(logoDataUri));
    }
    if (includeAll || mode == '2') {
      pages.add(_buildFormat2Html(logoDataUri));
    }
    if (includeAll || mode == '3') {
      pages.add(_buildFormat3Html(logoDataUri));
    }
    if (includeAll || mode == '4') {
      pages.add(
        _buildRankersHtml(
          logoDataUri: logoDataUri,
          reportSubtitle:
              'વર્ગ અને વિભાગવાર પ્રથમ ૩ ક્રમાંકિત વિદ્યાર્થીઓની યાદી (Section-Wise Top 3 Rankers)',
          entries: _sectionWiseRankers,
        ),
      );
    }
    if (includeAll || mode == '5') {
      pages.add(
        _buildRankersHtml(
          logoDataUri: logoDataUri,
          reportSubtitle:
              'ધોરણવાર પ્રથમ ૩ ક્રમાંકિત વિદ્યાર્થીઓની યાદી (Class-Wise Top 3 Rankers)',
          entries: _classWiseRankers,
        ),
      );
    }

    final isLandscape = mode == '2' || mode == '3';
    return '''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8" />
<title>Whole School Result Summary</title>
<style>
  @page {
    size: A4 ${isLandscape ? 'landscape' : 'portrait'};
    margin: 6mm;
  }
  * {
    box-sizing: border-box;
    -webkit-print-color-adjust: exact !important;
    print-color-adjust: exact !important;
  }
  body {
    font-family: "Noto Sans Gujarati", "Shruti", "Nirmala UI", sans-serif;
    margin: 0;
    padding: 0;
    color: #0F172A;
    background: #FFFFFF;
  }
  .summary-page {
    page-break-after: always;
    break-after: page;
    width: 100%;
    overflow: hidden;
  }
  .summary-page:last-child {
    page-break-after: auto;
    break-after: auto;
  }
  .summary-page-inner {
    transform-origin: top center;
    width: 100%;
  }
  .grid-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 9pt;
  }
  .grid-table th, .grid-table td {
    border: 1px solid #334155;
    padding: 2.8px 4px;
    text-align: center;
  }
  .sign-row {
    display: flex;
    justify-content: space-between;
    margin-top: 14px;
    font-weight: 800;
    color: #0B2D5B;
    font-size: 10pt;
  }
</style>
</head>
<body>
${pages.join('\n')}
<script>
  window.addEventListener("load", function() {
    var maxH = ${isLandscape ? 690 : 980};
    var pages = document.querySelectorAll(".summary-page-inner");
    for (var i = 0; i < pages.length; i++) {
      var el = pages[i];
      var h = el.scrollHeight;
      if (h > maxH) {
        var scale = (maxH / h).toFixed(3);
        el.style.transform = "scale(" + scale + ")";
      }
    }
    setTimeout(function() { window.focus(); window.print(); }, 250);
  });
</script>
</body>
</html>''';
  }

  // ===========================================================================
  // 1-CLICK EXCEL (.XLSX) EXPORT (ALL 5 SHEETS INCLUDING RANKERS)
  // ===========================================================================

  Future<void> _exportAll3FormatsExcel() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final wb = ec.Excel.createExcel();
      final defSheet = wb.getDefaultSheet() ?? 'Sheet1';
      if (defSheet != 'Class-Section Summary') {
        wb.rename(defSheet, 'Class-Section Summary');
      }
      final s1 = wb['Class-Section Summary'];
      final s2 = wb['Category-Grade Detail'];
      final s3 = wb['Whole School Performance'];
      final s4 = wb['Section-Wise Top 3 Rankers'];
      final s5 = wb['Class-Wise Top 3 Rankers'];

      final displaySchoolName = _lockedSchoolName.isNotEmpty
          ? _lockedSchoolName
          : _schoolNameCtrl.text;

      void setCell(
        ec.Sheet sheet,
        int r,
        int c,
        dynamic val, {
        bool bold = false,
        String? bgHex,
        String? fgHex,
      }) {
        final cell = sheet.cell(
          ec.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
        );
        if (val is int) {
          cell.value = ec.IntCellValue(val);
        } else if (val is double) {
          cell.value = ec.DoubleCellValue(double.parse(val.toStringAsFixed(2)));
        } else {
          cell.value = ec.TextCellValue('${val ?? ''}');
        }
        cell.cellStyle = ec.CellStyle(
          bold: bold,
          fontColorHex: fgHex != null
              ? ec.ExcelColor.fromHexString(fgHex)
              : ec.ExcelColor.fromHexString('#0B2D5B'),
          backgroundColorHex: bgHex != null
              ? ec.ExcelColor.fromHexString(bgHex)
              : ec.ExcelColor.none,
          horizontalAlign: ec.HorizontalAlign.Center,
          verticalAlign: ec.VerticalAlign.Center,
        );
      }

      // --- Sheet 1: Class-Section Summary ---
      setCell(s1, 0, 0, _authorityCtrl.text, bold: true);
      setCell(s1, 1, 0, displaySchoolName, bold: true);
      setCell(s1, 2, 0, _schoolAddressCtrl.text, bold: true);
      setCell(s1, 3, 0, 'શાળાનું સંકલિત પરિણામ પત્રક',
          bold: true, bgHex: '#0B2D5B', fgHex: '#FFFFFF');
      setCell(s1, 4, 0, 'Category-wise • Class & Section Consolidation',
          bold: true, bgHex: '#CFF7EF');
      setCell(s1, 5, 0, 'શૈક્ષણિક વર્ષ: ${_academicYearCtrl.text}', bold: true);
      setCell(s1, 5, 3, 'પરીક્ષા: ${_examNameCtrl.text}', bold: true);
      setCell(s1, 5, 6, 'પરિણામ તારીખ: ${_resultDateCtrl.text}', bold: true);
      setCell(s1, 5, 9, 'UDISE: $_lockedUdiseCode', bold: true);

      final s1H1 = <String>[
        'ધોરણ',
        'વિભાગ',
        'જાતિવાર વિદ્યાર્થી સંખ્યા',
        '',
        '',
        '',
        'કુલ',
        'ગ્રેડ વિતરણ',
        '',
        '',
        '',
        '',
      ];
      final s1H2 = <String>[
        '',
        '',
        'અનુ. જાતિ',
        'અનુ. જ. જાતિ',
        'બક્ષીપંચ',
        'અન્ય',
        'કુલ',
        'A',
        'B',
        'C',
        'D',
        'E',
      ];
      for (var c = 0; c < s1H1.length; c++) {
        setCell(s1, 7, c, s1H1[c],
            bold: true, bgHex: '#0B2D5B', fgHex: '#FFFFFF');
        setCell(s1, 8, c, s1H2[c],
            bold: true, bgHex: '#0B2D5B', fgHex: '#FFFFFF');
      }

      var r1 = 9;
      for (final entry in _byStandard.entries) {
        final stdTot = _standardTotals[entry.key]!;
        for (final sec in entry.value) {
          final rowVals = <dynamic>[
            sec.standardDisplay,
            sec.sectionDisplay,
            sec.catRegistered['SC'] ?? 0,
            sec.catRegistered['ST'] ?? 0,
            sec.catRegistered['OBC'] ?? 0,
            sec.catRegistered['OTHER'] ?? 0,
            sec.registeredTotal,
            sec.gradeCounts['A'] ?? 0,
            sec.gradeCounts['B'] ?? 0,
            sec.gradeCounts['C'] ?? 0,
            sec.gradeCounts['D'] ?? 0,
            sec.gradeCounts['E'] ?? 0,
          ];
          for (var c = 0; c < rowVals.length; c++) {
            setCell(s1, r1, c, rowVals[c], bold: c == 6);
          }
          r1++;
        }
        final totVals = <dynamic>[
          stdTot.standardDisplay,
          'ધોરણ કુલ',
          stdTot.catRegistered['SC'] ?? 0,
          stdTot.catRegistered['ST'] ?? 0,
          stdTot.catRegistered['OBC'] ?? 0,
          stdTot.catRegistered['OTHER'] ?? 0,
          stdTot.registeredTotal,
          stdTot.gradeCounts['A'] ?? 0,
          stdTot.gradeCounts['B'] ?? 0,
          stdTot.gradeCounts['C'] ?? 0,
          stdTot.gradeCounts['D'] ?? 0,
          stdTot.gradeCounts['E'] ?? 0,
        ];
        for (var c = 0; c < totVals.length; c++) {
          setCell(s1, r1, c, totVals[c], bold: true, bgHex: '#CFF7EF');
        }
        r1++;
      }
      final g1Vals = <dynamic>[
        'સમગ્ર શાળાનો કુલ',
        '',
        _wholeSchoolTotal.catRegistered['SC'] ?? 0,
        _wholeSchoolTotal.catRegistered['ST'] ?? 0,
        _wholeSchoolTotal.catRegistered['OBC'] ?? 0,
        _wholeSchoolTotal.catRegistered['OTHER'] ?? 0,
        _wholeSchoolTotal.registeredTotal,
        _wholeSchoolTotal.gradeCounts['A'] ?? 0,
        _wholeSchoolTotal.gradeCounts['B'] ?? 0,
        _wholeSchoolTotal.gradeCounts['C'] ?? 0,
        _wholeSchoolTotal.gradeCounts['D'] ?? 0,
        _wholeSchoolTotal.gradeCounts['E'] ?? 0,
      ];
      for (var c = 0; c < g1Vals.length; c++) {
        setCell(s1, r1, c, g1Vals[c],
            bold: true, bgHex: '#0B2D5B', fgHex: '#FFFFFF');
      }
      setCell(s1, r1 + 3, 0, 'ચકાસણી કરનાર: __________________', bold: true);
      setCell(s1, r1 + 3, 8, 'આચાર્યશ્રી: __________________', bold: true);

      // --- Sheet 2: Category-Grade Detail ---
      setCell(s2, 0, 0, _authorityCtrl.text, bold: true);
      setCell(s2, 1, 0, displaySchoolName, bold: true);
      setCell(s2, 2, 0, _schoolAddressCtrl.text, bold: true);
      setCell(s2, 3, 0, 'શાળાનું વર્ગવાર વિગતવાર પરિણામ પત્રક',
          bold: true, bgHex: '#0B2D5B', fgHex: '#FFFFFF');
      final det = _selectedDetailSummary;
      setCell(s2, 4, 0, 'શૈક્ષણિક વર્ષ: ${_academicYearCtrl.text}', bold: true);
      setCell(
          s2,
          4,
          5,
          'ધોરણ: ${_selectedClassIdForDetail == '__ALL__' ? 'તમામ' : det.standardDisplay}',
          bold: true);
      setCell(
          s2,
          4,
          10,
          'વિભાગ: ${_selectedClassIdForDetail == '__ALL__' ? 'તમામ' : det.sectionDisplay}',
          bold: true);
      setCell(s2, 4, 15, 'પરિણામ તારીખ: ${_resultDateCtrl.text}', bold: true);

      void writeCatGradeBlock(
          int startRow, _ClassSectionResultSummary sumObj) {
        final h1 = <String>[
          'જાતિ',
          'રજી. સંખ્યા',
          '',
          '',
          'મેળવેલ એકંદર ગ્રેડ',
          ...List<String>.filled(14, ''),
          'નોંધ',
        ];
        final h2 = <String>[
          '',
          '',
          '',
          '',
          'A',
          '',
          '',
          'B',
          '',
          '',
          'C',
          '',
          '',
          'D',
          '',
          '',
          'E',
          '',
          '',
          '',
        ];
        final h3 = <String>[
          '',
          'કુમાર',
          'કન્યા',
          'કુલ',
          for (var i = 0; i < 5; i++) ...<String>['કુમાર', 'કન્યા', 'કુલ'],
          '',
        ];
        for (var c = 0; c < 20; c++) {
          setCell(s2, startRow, c, h1[c], bold: true, bgHex: '#E8EEF3');
          setCell(s2, startRow + 1, c, h2[c], bold: true, bgHex: '#E8EEF3');
          setCell(s2, startRow + 2, c, h3[c], bold: true, bgHex: '#E8EEF3');
        }
        const cats = <(String, String)>[
          ('SC', 'અનુ. જાતિ'),
          ('ST', 'અનુ. જ. જાતિ'),
          ('OBC', 'બક્ષીપંચ'),
          ('OTHER', 'અન્ય'),
        ];
        const grades = <String>['A', 'B', 'C', 'D', 'E'];
        final totCols = List<int>.filled(18, 0);
        for (var idx = 0; idx < cats.length; idx++) {
          final (cKey, cLbl) = cats[idx];
          final rIdx = startRow + 3 + idx;
          setCell(s2, rIdx, 0, cLbl, bold: true);
          final rB = sumObj.catGenderRegistered[cKey]?['BOYS'] ?? 0;
          final rG = sumObj.catGenderRegistered[cKey]?['GIRLS'] ?? 0;
          final rT = rB + rG;
          totCols[0] += rB;
          totCols[1] += rG;
          totCols[2] += rT;
          setCell(s2, rIdx, 1, rB);
          setCell(s2, rIdx, 2, rG);
          setCell(s2, rIdx, 3, rT, bold: true);
          for (var gIdx = 0; gIdx < grades.length; gIdx++) {
            final g = grades[gIdx];
            final gB = sumObj.catGradeGenderCounts[cKey]?[g]?['BOYS'] ?? 0;
            final gG = sumObj.catGradeGenderCounts[cKey]?[g]?['GIRLS'] ?? 0;
            final gT = gB + gG;
            final baseC = 4 + gIdx * 3;
            totCols[3 + gIdx * 3] += gB;
            totCols[3 + gIdx * 3 + 1] += gG;
            totCols[3 + gIdx * 3 + 2] += gT;
            setCell(s2, rIdx, baseC, gB);
            setCell(s2, rIdx, baseC + 1, gG);
            setCell(s2, rIdx, baseC + 2, gT, bold: true);
          }
          setCell(s2, rIdx, 19, sumObj.remarks);
        }
        final totRowIdx = startRow + 7;
        setCell(s2, totRowIdx, 0, 'કુલ', bold: true, bgHex: '#CFF7EF');
        for (var i = 0; i < 18; i++) {
          setCell(s2, totRowIdx, 1 + i, totCols[i],
              bold: true, bgHex: '#CFF7EF');
        }
        setCell(s2, totRowIdx, 19, '', bold: true, bgHex: '#CFF7EF');
      }

      writeCatGradeBlock(6, det);
      setCell(s2, 16, 0, 'સમગ્ર શાળાનો કુલ સારાંશ | તમામ ધોરણો અને વિભાગો',
          bold: true, bgHex: '#0B2D5B', fgHex: '#FFFFFF');
      writeCatGradeBlock(17, _wholeSchoolTotal);

      // --- Sheet 3: Whole School Performance ---
      setCell(s3, 0, 0, _authorityCtrl.text, bold: true);
      setCell(s3, 1, 0, displaySchoolName, bold: true);
      setCell(s3, 2, 0, _schoolAddressCtrl.text, bold: true);
      setCell(s3, 3, 0, 'સમગ્ર શાળાનું પરિણામ સારાંશ',
          bold: true, bgHex: '#0B2D5B', fgHex: '#FFFFFF');
      setCell(s3, 4, 0, 'ધોરણવાર અને વિભાગવાર સંકલિત અહેવાલ',
          bold: true, bgHex: '#CFF7EF');
      setCell(s3, 5, 0, 'શૈક્ષણિક વર્ષ: ${_academicYearCtrl.text}', bold: true);
      setCell(s3, 5, 3, 'પરીક્ષા: ${_examNameCtrl.text}', bold: true);
      setCell(s3, 5, 7, 'પરિણામ તારીખ: ${_resultDateCtrl.text}', bold: true);
      setCell(s3, 5, 11, 'UDISE: $_lockedUdiseCode', bold: true);

      setCell(s3, 7, 0, 'કુલ નોંધાયેલા',
          bold: true, bgHex: '#087F7A', fgHex: '#FFFFFF');
      setCell(s3, 7, 3, 'કુલ હાજર',
          bold: true, bgHex: '#087F7A', fgHex: '#FFFFFF');
      setCell(s3, 7, 6, 'કુલ ઉત્તીર્ણ',
          bold: true, bgHex: '#087F7A', fgHex: '#FFFFFF');
      setCell(s3, 7, 9, 'શાળા પરિણામ %',
          bold: true, bgHex: '#087F7A', fgHex: '#FFFFFF');

      setCell(s3, 8, 0, _wholeSchoolTotal.registeredTotal, bold: true);
      setCell(s3, 8, 3, _wholeSchoolTotal.appearedTotal, bold: true);
      setCell(s3, 8, 6, _wholeSchoolTotal.passedTotal, bold: true);
      setCell(s3, 8, 9, _wholeSchoolTotal.resultPercent, bold: true);

      final s3H1 = <String>[
        'ધોરણ',
        'વિભાગ',
        'નોંધાયેલા',
        'હાજર',
        'ગેરહાજર',
        'ઉત્તીર્ણ',
        'અનુત્તીર્ણ',
        'પરિણામ %',
        'ગ્રેડ વિતરણ',
        '',
        '',
        '',
        '',
        'નોંધ',
      ];
      final s3H2 = <String>[
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        'A',
        'B',
        'C',
        'D',
        'E',
        '',
      ];
      for (var c = 0; c < s3H1.length; c++) {
        setCell(s3, 10, c, s3H1[c],
            bold: true, bgHex: '#0B2D5B', fgHex: '#FFFFFF');
        setCell(s3, 11, c, s3H2[c],
            bold: true, bgHex: '#0B2D5B', fgHex: '#FFFFFF');
      }

      var r3 = 12;
      for (final entry in _byStandard.entries) {
        final stdTot = _standardTotals[entry.key]!;
        for (final sec in entry.value) {
          final vals = <dynamic>[
            sec.standardDisplay,
            sec.sectionDisplay,
            sec.registeredTotal,
            sec.appearedTotal,
            sec.absentTotal,
            sec.passedTotal,
            sec.failedTotal,
            sec.resultPercent,
            sec.gradeCounts['A'] ?? 0,
            sec.gradeCounts['B'] ?? 0,
            sec.gradeCounts['C'] ?? 0,
            sec.gradeCounts['D'] ?? 0,
            sec.gradeCounts['E'] ?? 0,
            sec.remarks,
          ];
          for (var c = 0; c < vals.length; c++) {
            setCell(s3, r3, c, vals[c]);
          }
          r3++;
        }
        final totVals = <dynamic>[
          stdTot.standardDisplay,
          'ધોરણ કુલ',
          stdTot.registeredTotal,
          stdTot.appearedTotal,
          stdTot.absentTotal,
          stdTot.passedTotal,
          stdTot.failedTotal,
          stdTot.resultPercent,
          stdTot.gradeCounts['A'] ?? 0,
          stdTot.gradeCounts['B'] ?? 0,
          stdTot.gradeCounts['C'] ?? 0,
          stdTot.gradeCounts['D'] ?? 0,
          stdTot.gradeCounts['E'] ?? 0,
          '',
        ];
        for (var c = 0; c < totVals.length; c++) {
          setCell(s3, r3, c, totVals[c], bold: true, bgHex: '#CFF7EF');
        }
        r3++;
      }
      final g3Vals = <dynamic>[
        'સમગ્ર શાળાનો કુલ',
        '',
        _wholeSchoolTotal.registeredTotal,
        _wholeSchoolTotal.appearedTotal,
        _wholeSchoolTotal.absentTotal,
        _wholeSchoolTotal.passedTotal,
        _wholeSchoolTotal.failedTotal,
        _wholeSchoolTotal.resultPercent,
        _wholeSchoolTotal.gradeCounts['A'] ?? 0,
        _wholeSchoolTotal.gradeCounts['B'] ?? 0,
        _wholeSchoolTotal.gradeCounts['C'] ?? 0,
        _wholeSchoolTotal.gradeCounts['D'] ?? 0,
        _wholeSchoolTotal.gradeCounts['E'] ?? 0,
        '',
      ];
      for (var c = 0; c < g3Vals.length; c++) {
        setCell(s3, r3, c, g3Vals[c],
            bold: true, bgHex: '#0B2D5B', fgHex: '#FFFFFF');
      }

      // --- Helper to populate Sheet 4 (Section-Wise Rankers) & Sheet 5 (Class-Wise Rankers) ---
      void writeRankersSheet(
        ec.Sheet sheet,
        String subtitle,
        List<_RankerStudentEntry> entries,
      ) {
        setCell(sheet, 0, 0, _authorityCtrl.text, bold: true);
        setCell(sheet, 1, 0, displaySchoolName, bold: true);
        setCell(sheet, 2, 0, _schoolAddressCtrl.text, bold: true);
        setCell(sheet, 3, 0, 'શાળાનું સંકલિત પરિણામ પત્રક',
            bold: true, bgHex: '#0B2D5B', fgHex: '#FFFFFF');
        setCell(sheet, 4, 0, subtitle, bold: true, bgHex: '#CFF7EF');
        setCell(sheet, 5, 0, 'શૈક્ષણિક વર્ષ: ${_academicYearCtrl.text}',
            bold: true);
        setCell(sheet, 5, 2, 'પરીક્ષા: ${_examNameCtrl.text}', bold: true);
        setCell(sheet, 5, 4, 'પરિણામ તારીખ: ${_resultDateCtrl.text}',
            bold: true);
        setCell(sheet, 5, 6, 'UDISE: $_lockedUdiseCode', bold: true);

        const headers = <String>[
          'ક્રમ (Sr. No.)',
          'વિદ્યાર્થીનું નામ (Student Name)',
          'ધોરણ - વર્ગ (Class & Section)',
          'કુલ ગુણ (Total Marks)',
          'મેળવેલ ગુણ (Obtained Marks)',
          'ટકાવારી % (Percentage)',
          'ક્રમાંક (Rank 1 to 3)',
        ];
        for (var c = 0; c < headers.length; c++) {
          setCell(sheet, 7, c, headers[c],
              bold: true, bgHex: '#0B2D5B', fgHex: '#FFFFFF');
        }
        var rowIdx = 8;
        for (var i = 0; i < entries.length; i++) {
          final e = entries[i];
          final bg = e.rank == 1 ? '#FEF9C3' : (e.rank == 2 ? '#F0FDF4' : null);
          setCell(sheet, rowIdx, 0, i + 1, bold: e.rank == 1, bgHex: bg);
          setCell(sheet, rowIdx, 1, e.studentName,
              bold: e.rank == 1, bgHex: bg);
          setCell(sheet, rowIdx, 2, e.classWithSection,
              bold: e.rank == 1, bgHex: bg);
          setCell(sheet, rowIdx, 3, e.totalMarks, bold: e.rank == 1, bgHex: bg);
          setCell(sheet, rowIdx, 4, e.obtainedMarks, bold: true, bgHex: bg);
          setCell(sheet, rowIdx, 5, e.percentage, bold: true, bgHex: bg);
          setCell(sheet, rowIdx, 6, _rankDisplayLabel(e.rank),
              bold: true, bgHex: bg);
          rowIdx++;
        }
        setCell(sheet, rowIdx + 2, 0, 'ચકાસણી કરનાર: __________________',
            bold: true);
        setCell(sheet, rowIdx + 2, 5, 'આચાર્યશ્રી: __________________',
            bold: true);
      }

      writeRankersSheet(
        s4,
        'વર્ગ અને વિભાગવાર પ્રથમ ૩ ક્રમાંકિત વિદ્યાર્થીઓની યાદી (Section-Wise Top 3 Rankers)',
        _sectionWiseRankers,
      );
      writeRankersSheet(
        s5,
        'ધોરણવાર પ્રથમ ૩ ક્રમાંકિત વિદ્યાર્થીઓની યાદી (Class-Wise Top 3 Rankers)',
        _classWiseRankers,
      );

      final bytes = wb.encode();
      if (bytes == null) throw StateError('Excel encoding failed.');
      final cleanBytes = XlsxSanitizer.clean(Uint8List.fromList(bytes));
      final fileName =
          'Whole_School_Result_Summary_Sem_${_selectedSemester}.xlsx';
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile.fromData(
              cleanBytes,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              name: fileName,
            ),
          ],
          text: fileName,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('તમામ ૫ પરિણામ પત્રકો Excel માં ડાઉનલોડ થયા: $fileName')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text('Excel export failed: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ===========================================================================
  // UI WIDGETS
  // ===========================================================================

  Widget _buildHeaderBannerWidget({
    required String title,
    required String subtitle,
    required List<String> metaLabels,
  }) {
    final displaySchoolName = _lockedSchoolName.isNotEmpty
        ? _lockedSchoolName
        : _schoolNameCtrl.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_schoolLogoBytes != null && _schoolLogoBytes!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Image.memory(
                    _schoolLogoBytes!,
                    width: 60,
                    height: 60,
                    fit: BoxFit.contain,
                  ),
                ),
              Flexible(
                child: Column(
                  children: [
                    Text(
                      _authorityCtrl.text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0B2D5B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displaySchoolName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0B2D5B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _schoolAddressCtrl.text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0B2D5B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          color: const Color(0xFF0B2D5B),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (subtitle.isNotEmpty)
          Container(
            color: const Color(0xFFCFF7EF),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF0B2D5B),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        Container(
          color: const Color(0xFFF4F8FB),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 6,
            children: metaLabels
                .map(
                  (m) => Text(
                    m,
                    style: const TextStyle(
                      color: Color(0xFF0B2D5B),
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildFormat1Card() {
    final rows = <TableRow>[
      TableRow(
        decoration: const BoxDecoration(color: Color(0xFF0B2D5B)),
        children: [
          for (final h in const <String>[
            'ધોરણ',
            'વિભાગ',
            'અનુ. જાતિ',
            'અનુ. જ. જાતિ',
            'બક્ષીપંચ',
            'અન્ય',
            'કુલ',
            'A',
            'B',
            'C',
            'D',
            'E',
            'સુધારો',
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
              child: Text(
                h,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                ),
              ),
            ),
        ],
      ),
    ];

    TableRow buildDataRow(
      List<String> cells, {
      Color? bg,
      Color fg = const Color(0xFF0F172A),
      bool bold = false,
      VoidCallback? onEdit,
    }) {
      return TableRow(
        decoration: bg != null ? BoxDecoration(color: bg) : null,
        children: [
          ...cells.map(
            (c) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
              child: Text(
                c,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: fg,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 11.5,
                ),
              ),
            ),
          ),
          onEdit != null
              ? IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'આ વર્ગના આંકડા સુધારો (Admin Edit)',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined,
                      size: 16, color: Color(0xFF0B2D5B)),
                )
              : const SizedBox.shrink(),
        ],
      );
    }

    for (final entry in _byStandard.entries) {
      final stdTot = _standardTotals[entry.key]!;
      for (final s in entry.value) {
        rows.add(
          buildDataRow(
            <String>[
              _toGujDigits(s.standardDisplay),
              s.sectionDisplay,
              '${s.catRegistered['SC'] ?? 0}',
              '${s.catRegistered['ST'] ?? 0}',
              '${s.catRegistered['OBC'] ?? 0}',
              '${s.catRegistered['OTHER'] ?? 0}',
              '${s.registeredTotal}',
              '${s.gradeCounts['A'] ?? 0}',
              '${s.gradeCounts['B'] ?? 0}',
              '${s.gradeCounts['C'] ?? 0}',
              '${s.gradeCounts['D'] ?? 0}',
              '${s.gradeCounts['E'] ?? 0}',
            ],
            onEdit: () => _openAdminEditClassDialog(s),
          ),
        );
      }
      rows.add(
        buildDataRow(
          <String>[
            _toGujDigits(stdTot.standardDisplay),
            'ધોરણ કુલ',
            '${stdTot.catRegistered['SC'] ?? 0}',
            '${stdTot.catRegistered['ST'] ?? 0}',
            '${stdTot.catRegistered['OBC'] ?? 0}',
            '${stdTot.catRegistered['OTHER'] ?? 0}',
            '${stdTot.registeredTotal}',
            '${stdTot.gradeCounts['A'] ?? 0}',
            '${stdTot.gradeCounts['B'] ?? 0}',
            '${stdTot.gradeCounts['C'] ?? 0}',
            '${stdTot.gradeCounts['D'] ?? 0}',
            '${stdTot.gradeCounts['E'] ?? 0}',
          ],
          bg: const Color(0xFFCFF7EF),
          fg: const Color(0xFF0B2D5B),
          bold: true,
        ),
      );
    }

    final tot = _wholeSchoolTotal;
    rows.add(
      buildDataRow(
        <String>[
          'સમગ્ર શાળાનો કુલ',
          '—',
          '${tot.catRegistered['SC'] ?? 0}',
          '${tot.catRegistered['ST'] ?? 0}',
          '${tot.catRegistered['OBC'] ?? 0}',
          '${tot.catRegistered['OTHER'] ?? 0}',
          '${tot.registeredTotal}',
          '${tot.gradeCounts['A'] ?? 0}',
          '${tot.gradeCounts['B'] ?? 0}',
          '${tot.gradeCounts['C'] ?? 0}',
          '${tot.gradeCounts['D'] ?? 0}',
          '${tot.gradeCounts['E'] ?? 0}',
        ],
        bg: const Color(0xFF0B2D5B),
        fg: Colors.white,
        bold: true,
      ),
    );

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                const Text(
                  'પત્રક ૧ : ધોરણ અને વિભાગવાર જાતિ અને ગ્રેડ સંકલન (Class-Section Summary)',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: Color(0xFF0B2D5B),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _generatingPdf
                          ? null
                          : () => _downloadPdf(mode: '1'),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
                      label: const Text('PDF પત્રક ૧'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _printResultSummaries(mode: '1'),
                      icon: const Icon(Icons.print_outlined, size: 17),
                      label: const Text('પ્રિન્ટ પત્રક ૧'),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(),
            _buildHeaderBannerWidget(
              title: 'શાળાનું સંકલિત પરિણામ પત્રક',
              subtitle: 'Category-wise • Class & Section Consolidation',
              metaLabels: <String>[
                'શૈક્ષણિક વર્ષ: ${_academicYearCtrl.text}',
                'પરીક્ષા: ${_examNameCtrl.text}',
                'પરિણામ તારીખ: ${_resultDateCtrl.text}',
                'UDISE: $_lockedUdiseCode',
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 960),
                child: Table(
                  border: TableBorder.all(color: const Color(0xFF475569)),
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: rows,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleCatGradeWidget(_ClassSectionResultSummary sumObj) {
    const cats = <(String, String)>[
      ('SC', 'અનુ. જાતિ'),
      ('ST', 'અનુ. જ. જાતિ'),
      ('OBC', 'બક્ષીપંચ'),
      ('OTHER', 'અન્ય'),
    ];
    const grades = <String>['A', 'B', 'C', 'D', 'E'];

    final headers = <String>[
      'જાતિ',
      'રજી.\nકુમાર',
      'રજી.\nકન્યા',
      'રજી.\nકુલ',
      for (final g in grades) ...<String>['$g\nકુમાર', '$g\nકન્યા', '$g\nકુલ'],
      'નોંધ',
    ];

    final rows = <TableRow>[
      TableRow(
        decoration: const BoxDecoration(color: Color(0xFFE8EEF3)),
        children: headers
            .map(
              (h) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
                child: Text(
                  h,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF0B2D5B),
                    fontWeight: FontWeight.w800,
                    fontSize: 10.5,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    ];

    final totCols = List<int>.filled(18, 0);
    for (final (cKey, cLbl) in cats) {
      final rB = sumObj.catGenderRegistered[cKey]?['BOYS'] ?? 0;
      final rG = sumObj.catGenderRegistered[cKey]?['GIRLS'] ?? 0;
      final rT = rB + rG;
      totCols[0] += rB;
      totCols[1] += rG;
      totCols[2] += rT;

      final cells = <String>[cLbl, '$rB', '$rG', '$rT'];
      for (var gIdx = 0; gIdx < grades.length; gIdx++) {
        final g = grades[gIdx];
        final gB = sumObj.catGradeGenderCounts[cKey]?[g]?['BOYS'] ?? 0;
        final gG = sumObj.catGradeGenderCounts[cKey]?[g]?['GIRLS'] ?? 0;
        final gT = gB + gG;
        totCols[3 + gIdx * 3] += gB;
        totCols[3 + gIdx * 3 + 1] += gG;
        totCols[3 + gIdx * 3 + 2] += gT;
        cells.addAll(<String>['$gB', '$gG', '$gT']);
      }
      cells.add(sumObj.remarks);

      rows.add(
        TableRow(
          children: cells.asMap().entries.map((e) {
            final idx = e.key;
            final isTotalCol =
                idx == 3 || (idx > 3 && idx < 19 && idx % 3 == 0);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 3),
              child: Text(
                e.value,
                textAlign: idx == 0 ? TextAlign.left : TextAlign.center,
                style: TextStyle(
                  fontWeight: idx == 0 || isTotalCol
                      ? FontWeight.w800
                      : FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    rows.add(
      TableRow(
        decoration: const BoxDecoration(color: Color(0xFFCFF7EF)),
        children: <String>['કુલ', ...totCols.map((v) => '$v'), '']
            .map(
              (t) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
                child: Text(
                  t,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF0B2D5B),
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 980),
        child: Table(
          border: TableBorder.all(color: const Color(0xFF475569)),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: rows,
        ),
      ),
    );
  }

  Widget _buildFormat2Card() {
    final det = _selectedDetailSummary;
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                const Text(
                  'પત્રક ૨ : જાતિવાર અને કુમાર/કન્યા ગ્રેડ વિગતવાર પત્રક (Category-Grade Detail)',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: Color(0xFF0B2D5B),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 240,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedClassIdForDetail,
                        isExpanded: true,
                        isDense: true,
                        decoration: const InputDecoration(
                          labelText: 'વર્ગ પસંદ કરો (Class)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: <DropdownMenuItem<String>>[
                          const DropdownMenuItem<String>(
                            value: '__ALL__',
                            child: Text(
                              'સમગ્ર શાળા (All Classes)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          ..._classSummaries.map(
                            (c) => DropdownMenuItem<String>(
                              value: c.classId,
                              child: Text(
                                'ધો. ${_toGujDigits(c.standardDisplay)} - ${c.sectionDisplay} (${c.classLabel})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _selectedClassIdForDetail = v);
                          }
                        },
                      ),
                    ),
                    FilterChip(
                      selected: _includeAllClassesInFormat2Print,
                      label: const Text('પ્રિન્ટમાં બધા વર્ગો અલગ-અલગ છાપો'),
                      onSelected: (v) =>
                          setState(() => _includeAllClassesInFormat2Print = v),
                    ),
                    OutlinedButton.icon(
                      onPressed: _generatingPdf
                          ? null
                          : () => _downloadPdf(mode: '2'),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
                      label: const Text('PDF પત્રક ૨'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _printResultSummaries(mode: '2'),
                      icon: const Icon(Icons.print_outlined, size: 17),
                      label: const Text('પ્રિન્ટ પત્રક ૨'),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(),
            _buildHeaderBannerWidget(
              title: 'શાળાનું વર્ગવાર વિગતવાર પરિણામ પત્રક',
              subtitle: '',
              metaLabels: <String>[
                'શૈક્ષણિક વર્ષ: ${_academicYearCtrl.text}',
                'ધોરણ: ${_selectedClassIdForDetail == '__ALL__' ? 'તમામ' : _toGujDigits(det.standardDisplay)}',
                'વિભાગ: ${_selectedClassIdForDetail == '__ALL__' ? 'તમામ' : det.sectionDisplay}',
                'પરિણામ તારીખ: ${_resultDateCtrl.text}',
              ],
            ),
            const SizedBox(height: 8),
            _buildSingleCatGradeWidget(det),
            const SizedBox(height: 14),
            Container(
              color: const Color(0xFF0B2D5B),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              child: const Text(
                'સમગ્ર શાળાનો કુલ સારાંશ | તમામ ધોરણો અને વિભાગો',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                ),
              ),
            ),
            const SizedBox(height: 6),
            _buildSingleCatGradeWidget(_wholeSchoolTotal),
          ],
        ),
      ),
    );
  }

  Widget _buildFormat3Card() {
    final tot = _wholeSchoolTotal;
    final rows = <TableRow>[
      TableRow(
        decoration: const BoxDecoration(color: Color(0xFF0B2D5B)),
        children: [
          for (final h in const <String>[
            'ધોરણ',
            'વિભાગ',
            'નોંધાયેલા',
            'હાજર',
            'ગેરહાજર',
            'ઉત્તીર્ણ',
            'અનુત્તીર્ણ',
            'પરિણામ %',
            'A',
            'B',
            'C',
            'D',
            'E',
            'નોંધ',
            'સુધારો',
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
              child: Text(
                h,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                ),
              ),
            ),
        ],
      ),
    ];

    TableRow buildRow(
      List<String> cells, {
      Color? bg,
      Color fg = const Color(0xFF0F172A),
      bool bold = false,
      VoidCallback? onEdit,
    }) {
      return TableRow(
        decoration: bg != null ? BoxDecoration(color: bg) : null,
        children: [
          ...cells.map(
            (c) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
              child: Text(
                c,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: fg,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 11.5,
                ),
              ),
            ),
          ),
          onEdit != null
              ? IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'હાજર / ગેરહાજર / ઉત્તીર્ણ / ગ્રેડ સુધારો (Admin Edit)',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined,
                      size: 16, color: Color(0xFF0B2D5B)),
                )
              : const SizedBox.shrink(),
        ],
      );
    }

    for (final entry in _byStandard.entries) {
      final stdTot = _standardTotals[entry.key]!;
      for (final s in entry.value) {
        rows.add(
          buildRow(
            <String>[
              _toGujDigits(s.standardDisplay),
              s.sectionDisplay,
              '${s.registeredTotal}',
              '${s.appearedTotal}',
              '${s.absentTotal}',
              '${s.passedTotal}',
              '${s.failedTotal}',
              '${s.resultPercent.toStringAsFixed(2)}%',
              '${s.gradeCounts['A'] ?? 0}',
              '${s.gradeCounts['B'] ?? 0}',
              '${s.gradeCounts['C'] ?? 0}',
              '${s.gradeCounts['D'] ?? 0}',
              '${s.gradeCounts['E'] ?? 0}',
              s.remarks,
            ],
            onEdit: () => _openAdminEditClassDialog(s),
          ),
        );
      }
      rows.add(
        buildRow(
          <String>[
            _toGujDigits(stdTot.standardDisplay),
            'ધોરણ કુલ',
            '${stdTot.registeredTotal}',
            '${stdTot.appearedTotal}',
            '${stdTot.absentTotal}',
            '${stdTot.passedTotal}',
            '${stdTot.failedTotal}',
            '${stdTot.resultPercent.toStringAsFixed(2)}%',
            '${stdTot.gradeCounts['A'] ?? 0}',
            '${stdTot.gradeCounts['B'] ?? 0}',
            '${stdTot.gradeCounts['C'] ?? 0}',
            '${stdTot.gradeCounts['D'] ?? 0}',
            '${stdTot.gradeCounts['E'] ?? 0}',
            '',
          ],
          bg: const Color(0xFFCFF7EF),
          fg: const Color(0xFF0B2D5B),
          bold: true,
        ),
      );
    }

    rows.add(
      buildRow(
        <String>[
          'સમગ્ર શાળાનો કુલ',
          '—',
          '${tot.registeredTotal}',
          '${tot.appearedTotal}',
          '${tot.absentTotal}',
          '${tot.passedTotal}',
          '${tot.failedTotal}',
          '${tot.resultPercent.toStringAsFixed(2)}%',
          '${tot.gradeCounts['A'] ?? 0}',
          '${tot.gradeCounts['B'] ?? 0}',
          '${tot.gradeCounts['C'] ?? 0}',
          '${tot.gradeCounts['D'] ?? 0}',
          '${tot.gradeCounts['E'] ?? 0}',
          '',
        ],
        bg: const Color(0xFF0B2D5B),
        fg: Colors.white,
        bold: true,
      ),
    );

    Widget kpiCard(String label, String val) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF0B2D5B)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  color: const Color(0xFF087F7A),
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    val,
                    style: const TextStyle(
                      color: Color(0xFF0B2D5B),
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                const Text(
                  'પત્રક ૩ : સમગ્ર શાળાનું પરિણામ સારાંશ (Whole School Performance)',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: Color(0xFF0B2D5B),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _generatingPdf
                          ? null
                          : () => _downloadPdf(mode: '3'),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
                      label: const Text('PDF પત્રક ૩'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _printResultSummaries(mode: '3'),
                      icon: const Icon(Icons.print_outlined, size: 17),
                      label: const Text('પ્રિન્ટ પત્રક ૩'),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(),
            _buildHeaderBannerWidget(
              title: 'સમગ્ર શાળાનું પરિણામ સારાંશ',
              subtitle: 'ધોરણવાર અને વિભાગવાર સંકલિત અહેવાલ',
              metaLabels: <String>[
                'શૈક્ષણિક વર્ષ: ${_academicYearCtrl.text}',
                'પરીક્ષા: ${_examNameCtrl.text}',
                'પરિણામ તારીખ: ${_resultDateCtrl.text}',
                'UDISE: $_lockedUdiseCode',
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                kpiCard('કુલ નોંધાયેલા', '${tot.registeredTotal}'),
                kpiCard('કુલ હાજર', '${tot.appearedTotal}'),
                kpiCard('કુલ ઉત્તીર્ણ', '${tot.passedTotal}'),
                kpiCard(
                    'શાળા પરિણામ %', '${tot.resultPercent.toStringAsFixed(2)}%'),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 1020),
                child: Table(
                  border: TableBorder.all(color: const Color(0xFF475569)),
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: rows,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRankersCard({
    required bool isSectionWise,
    required String cardHeading,
    required String bannerSubtitle,
    required String modeCode,
    required List<_RankerStudentEntry> entries,
  }) {
    final rows = <TableRow>[
      TableRow(
        decoration: const BoxDecoration(color: Color(0xFF0B2D5B)),
        children: [
          for (final h in const <String>[
            'ક્રમ',
            'વિદ્યાર્થીનું નામ',
            'ધોરણ - વર્ગ',
            'કુલ ગુણ',
            'મેળવેલ ગુણ',
            'ટકાવારી %',
            'ક્રમાંક (Rank)',
            'સુધારો',
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
              child: Text(
                h,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                ),
              ),
            ),
        ],
      ),
    ];

    if (entries.isEmpty) {
      rows.add(
        TableRow(
          children: [
            for (final txt in const <String>[
              '—',
              'આ સત્રમાં હજુ કોઈ વર્ગના ગુણ દાખલ થયેલ નથી (✏️ બટનથી ઉમેરી શકાય)',
              '—',
              '0',
              '0',
              '0.00%',
              '—',
              '',
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                child: Text(
                  txt,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                  ),
                ),
              ),
          ],
        ),
      );
    } else {
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        final bg = e.rank == 1
            ? const Color(0xFFFEF9C3)
            : (e.rank == 2 ? const Color(0xFFF0FDF4) : null);
        rows.add(
          TableRow(
            decoration: bg != null ? BoxDecoration(color: bg) : null,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                child: Text(
                  '${i + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: e.rank == 1 ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 11.5,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                child: Text(
                  e.studentName,
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                child: Text(
                  e.classWithSection,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                child: Text(
                  '${e.totalMarks}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                child: Text(
                  '${e.obtainedMarks}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                child: Text(
                  '${e.percentage.toStringAsFixed(2)}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                child: Text(
                  _rankDisplayLabel(e.rank),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 11.5,
                    color: Color(0xFF0B2D5B),
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'આ વિદ્યાર્થીની વિગત સુધારો (Admin Edit)',
                onPressed: () => _openAdminEditRankerDialog(
                  isSectionWise: isSectionWise,
                  existingEntry: e,
                ),
                icon: const Icon(Icons.edit_outlined,
                    size: 16, color: Color(0xFF0B2D5B)),
              ),
            ],
          ),
        );
      }
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                Text(
                  cardHeading,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: Color(0xFF0B2D5B),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _openAdminEditRankerDialog(
                        isSectionWise: isSectionWise,
                      ),
                      icon: const Icon(Icons.person_add_alt_1_outlined, size: 17),
                      label: const Text('✏️ ક્રમાંકિત વિદ્યાર્થી ઉમેરો / સુધારો'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _generatingPdf
                          ? null
                          : () => _downloadPdf(mode: modeCode),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
                      label: Text('PDF પત્રક ${_toGujDigits(modeCode)}'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _printResultSummaries(mode: modeCode),
                      icon: const Icon(Icons.print_outlined, size: 17),
                      label: Text('પ્રિન્ટ પત્રક ${_toGujDigits(modeCode)}'),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(),
            _buildHeaderBannerWidget(
              title: 'શાળાનું સંકલિત પરિણામ પત્રક',
              subtitle: bannerSubtitle,
              metaLabels: <String>[
                'શૈક્ષણિક વર્ષ: ${_academicYearCtrl.text}',
                'પરીક્ષા: ${_examNameCtrl.text}',
                'પરિણામ તારીખ: ${_resultDateCtrl.text}',
                'UDISE: $_lockedUdiseCode',
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 960),
                child: Table(
                  columnWidths: const <int, TableColumnWidth>{
                    0: FlexColumnWidth(0.7),
                    1: FlexColumnWidth(2.6),
                    2: FlexColumnWidth(1.4),
                    3: FlexColumnWidth(1.0),
                    4: FlexColumnWidth(1.0),
                    5: FlexColumnWidth(1.0),
                    6: FlexColumnWidth(1.2),
                    7: FlexColumnWidth(0.7),
                  },
                  border: TableBorder.all(color: const Color(0xFF475569)),
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: rows,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final marksInsertedCount = _allComputedClassSummaries
        .where((s) =>
            s.hasMarksInserted && s.standardNum >= 1 && s.standardNum <= 8)
        .length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B2D5B),
        foregroundColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'સમગ્ર શાળાનું સત્રવાર પરિણામ સારાંશ અને પ્રથમ ૩ ક્રમાંકિત યાદી (All 5 Formats)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            Text(
              'Admin Whole-School Result Summary + Section-Wise & Class-Wise Top 3 Rankers • લોગો સાથે',
              style: TextStyle(fontSize: 11.5, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Data',
            onPressed: _loading ? null : _loadAllSchoolResultData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _loadAllSchoolResultData,
                          icon: const Icon(Icons.refresh),
                          label: const Text('ફરી પ્રયાસ કરો (Retry)'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    Card(
                      elevation: 2,
                      color: const Color(0xFFF8FAFC),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(
                            color: Color(0xFF0B2D5B), width: 1.2),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 12,
                              runSpacing: 10,
                              children: [
                                SegmentedButton<String>(
                                  segments: const <ButtonSegment<String>>[
                                    ButtonSegment<String>(
                                      value: '1',
                                      icon: Icon(Icons.looks_one_outlined),
                                      label: Text('૧. પ્રથમ સત્ર (Sem 1)'),
                                    ),
                                    ButtonSegment<String>(
                                      value: '2',
                                      icon: Icon(Icons.looks_two_outlined),
                                      label: Text('૨. દ્વિતીય સત્ર (Sem 2)'),
                                    ),
                                    ButtonSegment<String>(
                                      value: 'Annual',
                                      icon: Icon(
                                          Icons.workspace_premium_outlined),
                                      label: Text('૩. વાર્ષિક (Annual)'),
                                    ),
                                  ],
                                  selected: <String>{_selectedSemester},
                                  onSelectionChanged: (vals) {
                                    setState(() {
                                      _selectedSemester = vals.first;
                                      _updateExamLabelAndDateForSemester();
                                      _recomputeSummaries();
                                    });
                                  },
                                ),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFFDC2626),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 11,
                                        ),
                                      ),
                                      onPressed: _generatingPdf
                                          ? null
                                          : () => _downloadPdf(mode: 'all_5'),
                                      icon: _generatingPdf
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.picture_as_pdf_rounded),
                                      label: const Text(
                                        '📥 ૧-ક્લિક PDF ડાઉનલોડ (તમામ ૫ પત્રકો લોગો સાથે)',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF0B2D5B),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 11,
                                        ),
                                      ),
                                      onPressed: () =>
                                          _printResultSummaries(mode: 'all_5'),
                                      icon: const Icon(Icons.print_rounded),
                                      label: const Text(
                                        '🖨️ ૧-ક્લિક પ્રિન્ટ (All 5 Formats)',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF087F7A),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 11,
                                        ),
                                      ),
                                      onPressed: _exporting
                                          ? null
                                          : _exportAll3FormatsExcel,
                                      icon:
                                          const Icon(Icons.table_view_rounded),
                                      label: const Text(
                                        '📊 ૧-ક્લિક Excel (.xlsx) ડાઉનલોડ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            const Color(0xFF0B2D5B),
                                        side: const BorderSide(
                                          color: Color(0xFF0B2D5B),
                                          width: 1.4,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 11,
                                        ),
                                      ),
                                      onPressed: () =>
                                          _openAdminEditClassDialog(),
                                      icon: const Icon(Icons.edit_note_rounded),
                                      label: const Text(
                                        '✏️ હાજર / ગેરહાજર / ઉત્તીર્ણ / ગ્રેડ સુધારો (Admin Edit)',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                FilterChip(
                                  selected: _onlyMarksInsertedClasses,
                                  label: Text(
                                    '✅ માત્ર ગુણ દાખલ કરેલ વર્ગો જ બતાવો (ધોરણ 1 થી 8 ક્રમમાં — $marksInsertedCount વર્ગો)',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                  onSelected: (v) {
                                    setState(() {
                                      _onlyMarksInsertedClasses = v;
                                      _recomputeSummaries();
                                    });
                                  },
                                ),
                                if (marksInsertedCount == 0 &&
                                    _onlyMarksInsertedClasses)
                                  const Text(
                                    'ℹ️ આ સત્રમાં હજુ કોઈ વર્ગના ગુણ દાખલ થયેલ નથી — ધોરણ 1 થી 8 ના વર્ગો દર્શાવેલ છે (✏️ બટનથી સીધા આંકડા ઉમેરી શકાશે).',
                                    style: TextStyle(
                                      color: Color(0xFFB45309),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: const Text(
                                '⚙️ પત્રક હેડર વિગતો (શાળાનું નામ અને DISE કોડ લોક છે — બાકીની વિગતો Admin સુધારી શકશે)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                  color: Color(0xFF0B2D5B),
                                ),
                              ),
                              children: [
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    SizedBox(
                                      width: 280,
                                      child: TextField(
                                        controller: _schoolNameCtrl,
                                        readOnly: true,
                                        enabled: false,
                                        decoration: InputDecoration(
                                          labelText:
                                              '🔒 શાળાનું નામ (Locked - Not Editable)',
                                          filled: true,
                                          fillColor: Colors.grey.shade200,
                                          suffixIcon: const Icon(
                                              Icons.lock_outline,
                                              size: 17),
                                          border: const OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 190,
                                      child: TextField(
                                        controller: _udiseCtrl,
                                        readOnly: true,
                                        enabled: false,
                                        decoration: InputDecoration(
                                          labelText:
                                              '🔒 DISE / UDISE Code (Locked)',
                                          filled: true,
                                          fillColor: Colors.grey.shade200,
                                          suffixIcon: const Icon(
                                              Icons.lock_outline,
                                              size: 17),
                                          border: const OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 280,
                                      child: TextField(
                                        controller: _authorityCtrl,
                                        onChanged: (_) => setState(
                                            _recordEditableHeaderOverride),
                                        decoration: const InputDecoration(
                                          labelText: 'શિક્ષણ સમિતિ / Authority',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 320,
                                      child: TextField(
                                        controller: _schoolAddressCtrl,
                                        onChanged: (_) => setState(
                                            _recordEditableHeaderOverride),
                                        decoration: const InputDecoration(
                                          labelText: 'શાળાનું સરનામું',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 150,
                                      child: TextField(
                                        controller: _academicYearCtrl,
                                        onChanged: (_) => setState(
                                            _recordEditableHeaderOverride),
                                        decoration: const InputDecoration(
                                          labelText: 'શૈક્ષણિક વર્ષ',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 220,
                                      child: TextField(
                                        controller: _examNameCtrl,
                                        onChanged: (_) => setState(
                                            _recordEditableHeaderOverride),
                                        decoration: const InputDecoration(
                                          labelText: 'પરીક્ષા',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 160,
                                      child: TextField(
                                        controller: _resultDateCtrl,
                                        onChanged: (_) => setState(
                                            _recordEditableHeaderOverride),
                                        decoration: const InputDecoration(
                                          labelText: 'પરિણામ તારીખ',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildFormat1Card(),
                    _buildFormat2Card(),
                    _buildFormat3Card(),
                    _buildRankersCard(
                      isSectionWise: true,
                      cardHeading:
                          'પત્રક ૪ : વર્ગ અને વિભાગવાર પ્રથમ ૩ ક્રમાંકિત વિદ્યાર્થીઓની યાદી (Section-Wise Top 3 Rankers — ધોરણ 1 થી 8 ચઢતા ક્રમમાં)',
                      bannerSubtitle:
                          'વર્ગ અને વિભાગવાર પ્રથમ ૩ ક્રમાંકિત વિદ્યાર્થીઓની યાદી (Section-Wise Top 3 Rankers — Rank 1 to 3)',
                      modeCode: '4',
                      entries: _sectionWiseRankers,
                    ),
                    _buildRankersCard(
                      isSectionWise: false,
                      cardHeading:
                          'પત્રક ૫ : ધોરણવાર પ્રથમ ૩ ક્રમાંકિત વિદ્યાર્થીઓની યાદી (Class-Wise Top 3 Rankers — ધોરણ 1 થી 8 ચઢતા ક્રમમાં)',
                      bannerSubtitle:
                          'ધોરણવાર પ્રથમ ૩ ક્રમાંકિત વિદ્યાર્થીઓની યાદી (Class-Wise Top 3 Rankers — Rank 1 to 3)',
                      modeCode: '5',
                      entries: _classWiseRankers,
                    ),
                  ],
                ),
    );
  }
}

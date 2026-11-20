// ============================================================================
// પરીક્ષા આયોજન ફાઈલ - સંપૂર્ણ કંટ્રોલ (Flutter / Dart Version)
// ============================================================================
// Pure Flutter Material implementation (zero external package dependencies).
// Drop this file into your Flutter project's `lib/` folder (e.g.
// `lib/exam_planning_screen.dart`) and navigate to `const ExamPlanningScreen()`
// or run `runApp(const ExamPlanningApp());` directly.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/psm_file_export_helper.dart';
import '../services/rojmel_html_printer.dart';
import '../services/school_type.dart';
import 'package:pmshri_attendance/services/class_label.dart';

// ============================================================================
// Data Models
// ============================================================================
// PSM_EXAM_EARLY_TEACHER_FILTER_20261031_V2

class SchoolMeta {
  String schoolName;
  String address;
  String taluka;
  String district;
  String payCenter;
  String academicYear;
  String examName;
  String bundleMonth;
  String principalName;
  String crcName;
  String logoShape; // 'round', 'square', 'rectangle', 'oval'

  SchoolMeta({
    this.schoolName = 'ગાંધી સુંદરલાલ પ્રાથમિક કન્યા શાળા, પાટણ',
    this.address = 'શાળાનું સરનામું અહીં લખો',
    this.taluka = 'પાટણ',
    this.district = 'પાટણ',
    this.payCenter = 'બગવાડા',
    this.academicYear = '2026–27',
    this.examName = 'પ્રથમ સત્રાંત પરીક્ષા',
    this.bundleMonth = 'ઓક્ટોબર - 2026',
    this.principalName = '________',
    this.crcName = '________',
    this.logoShape = 'original',
  });

  Map<String, dynamic> toJson() => {
        'schoolName': schoolName,
        'address': address,
        'taluka': taluka,
        'district': district,
        'payCenter': payCenter,
        'academicYear': academicYear,
        'examName': examName,
        'bundleMonth': bundleMonth,
        'principalName': principalName,
        'crcName': crcName,
        'logoShape': logoShape,
      };

  void applyJson(Map<String, dynamic> m) {
    schoolName = m['schoolName']?.toString() ?? schoolName;
    address = m['address']?.toString() ?? address;
    taluka = m['taluka']?.toString() ?? taluka;
    district = m['district']?.toString() ?? district;
    payCenter = m['payCenter']?.toString() ?? payCenter;
    academicYear = m['academicYear']?.toString() ?? academicYear;
    examName = m['examName']?.toString() ?? examName;
    bundleMonth = m['bundleMonth']?.toString() ?? bundleMonth;
    principalName = m['principalName']?.toString() ?? principalName;
    crcName = m['crcName']?.toString() ?? crcName;
    final rawShape = m['logoShape']?.toString() ?? logoShape;
    logoShape = rawShape == 'round' ? 'original' : rawShape;
  }
}

class TeacherRecord {
  String id;
  String name;
  String group; // 'a' (3-5) or 'b' (6-8)
  List<String> subjects;
  List<String> assignedClasses;
  List<String> allowedClasses;

  TeacherRecord({
    this.id = '',
    required this.name,
    required this.group,
    required List<String> subjects,
    List<String> assignedClasses = const <String>[],
    List<String> allowedClasses = const <String>[],
  })  : subjects = List<String>.from(subjects),
        assignedClasses = List<String>.from(assignedClasses),
        allowedClasses = List<String>.from(allowedClasses);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'group': group,
        'subjects': subjects,
        'assignedClasses': assignedClasses,
        'allowedClasses': allowedClasses,
      };

  factory TeacherRecord.fromJson(Map<String, dynamic> m) => TeacherRecord(
        id: m['id']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        group: m['group']?.toString() ?? 'a',
        subjects:
            (m['subjects'] as List?)?.map((e) => e.toString()).toList() ?? [],
        assignedClasses: (m['assignedClasses'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[],
        allowedClasses: (m['allowedClasses'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[],
      );
}

class CommitteeRow {
  String teacherName;
  String roleOrDuty;
  String sign;

  CommitteeRow({
    this.teacherName = '',
    this.roleOrDuty = '',
    this.sign = '',
  });
}

class RegisterRow {
  String className;
  String group; // 'a' or 'b'
  int boys;
  int girls;
  int? databaseTotal;
  String teacherSign;
  String remarks;

  RegisterRow({
    required this.className,
    required this.group,
    this.boys = 15,
    this.girls = 15,
    this.databaseTotal,
    this.teacherSign = '',
    this.remarks = '',
  });

  int total(String genderMode) {
    if (genderMode == 'boys') return boys > 0 ? boys : (databaseTotal ?? 0);
    if (genderMode == 'girls') return girls > 0 ? girls : (databaseTotal ?? 0);
    final sum = boys + girls;
    return sum > 0 ? sum : (databaseTotal ?? 0);
  }
}

class TimetableRow {
  String date;
  String day;
  String stdLabel;
  String subject;
  String time;
  String marks;

  TimetableRow({
    required this.date,
    required this.day,
    required this.stdLabel,
    required this.subject,
    required this.time,
    required this.marks,
  });

  static Set<int> parseGrades(String raw) {
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    var norm = raw;
    for (int i = 0; i < 10; i++) {
      norm = norm.replaceAll(guj[i], '$i');
    }
    final grades = <int>{};
    final rangeRegex = RegExp(r'([1-8])\s*(?:થી|to|[-–])\s*([1-8])', caseSensitive: false);
    for (final m in rangeRegex.allMatches(norm)) {
      final start = int.tryParse(m.group(1)!) ?? 0;
      final end = int.tryParse(m.group(2)!) ?? 0;
      if (start > 0 && end >= start) {
        for (int g = start; g <= end; g++) {
          grades.add(g);
        }
      }
    }
    final remaining = norm.replaceAll(rangeRegex, ' ');
    for (final m in RegExp(r'[1-8]').allMatches(remaining)) {
      final g = int.tryParse(m.group(0)!);
      if (g != null) grades.add(g);
    }
    return grades;
  }

  Set<int> get parsedGrades => parseGrades(stdLabel);

  bool matchesGroup(String g) {
    final grades = parsedGrades;
    if (grades.isEmpty) {
      return group == g;
    }
    if (g == 'a') {
      return grades.any((x) => x >= 1 && x <= 5);
    }
    return grades.any((x) => x >= 6 && x <= 8);
  }

  String get group {
    final grades = parsedGrades;
    if (grades.isNotEmpty) {
      final hasA = grades.any((x) => x >= 1 && x <= 5);
      final hasB = grades.any((x) => x >= 6 && x <= 8);
      if (hasB && !hasA) return 'b';
      if (hasA && !hasB) return 'a';
    }
    final s = stdLabel.replaceAll(' ', '');
    if (RegExp(r'[૬-૮678]').hasMatch(s) && !RegExp(r'[૧-૫1-5]').hasMatch(s)) {
      return 'b';
    }
    return 'a';
  }
}

class SeatingRow {
  int blockNo;
  String className;
  String fromRoll;
  String toRoll;
  String totalCount;
  String remarks;

  SeatingRow({
    required this.blockNo,
    this.className = '',
    this.fromRoll = '',
    this.toRoll = '',
    this.totalCount = '',
    this.remarks = '',
  });
}

class AbsentBlockRow {
  int blockNo;
  String allotted; // Pre-filled from Seating Arrangement
  String present; // Blank by default for manual entry after print
  Map<String, String>
      classAbsent; // Blank by default for manual entry after print
  String totalAbsent; // Blank by default unless filled
  String sign;

  AbsentBlockRow({
    required this.blockNo,
    this.allotted = '',
    this.present = '',
    Map<String, String>? classAbsent,
    this.totalAbsent = '',
    this.sign = '',
  }) : classAbsent = classAbsent ?? {};
}

class AbsentStudentEntry {
  int srNo;
  String blockNo; // બ્લોક નંબર column (auto-looked up if roll+std entered)
  String studentName;
  String rollNo;
  String className;

  AbsentStudentEntry({
    required this.srNo,
    this.blockNo = '',
    this.studentName = '',
    this.rollNo = '',
    this.className = '',
  });
}

class AbsentPageSheet {
  String key;
  String group; // 'a' or 'b'
  String stdLabel;
  String date;
  String day;
  String subject;
  List<AbsentBlockRow> blockRows;
  List<AbsentStudentEntry> studentList;

  AbsentPageSheet({
    required this.key,
    required this.group,
    required this.stdLabel,
    required this.date,
    required this.day,
    required this.subject,
    required this.blockRows,
    required this.studentList,
  });
}

class SupervisionRow {
  String date;
  String day;
  String subject;
  int blockNo;
  String invigilatorName;
  String sign;

  SupervisionRow({
    required this.date,
    required this.day,
    required this.subject,
    required this.blockNo,
    this.invigilatorName = '',
    this.sign = '',
  });
}

class CheckingRow {
  String date;
  String subject;
  String className;
  String paperCount;
  String examinerName;
  String examinerSignDate;
  String returnDate;
  String principalSign;
  String group;

  CheckingRow({
    required this.date,
    required this.subject,
    required this.className,
    required this.paperCount,
    this.examinerName = '',
    this.examinerSignDate = '',
    this.returnDate = '',
    this.principalSign = '',
    required this.group,
  });
}

class BundleSubjectRow {
  int srNo;
  String date;
  String subject;
  String regCount;
  String presentCount;
  String absentCount;
  String absentRollNos;

  BundleSubjectRow({
    required this.srNo,
    required this.date,
    required this.subject,
    required this.regCount,
    this.presentCount = '',
    this.absentCount = '',
    this.absentRollNos = '',
  });
}

class BundleCardData {
  String className;
  String group;
  List<BundleSubjectRow> rows;
  String manualTotalScripts;

  BundleCardData({
    required this.className,
    required this.group,
    required this.rows,
    this.manualTotalScripts = '',
  });
}

class ExamExtraDetailRow {
  String label;
  String value;

  ExamExtraDetailRow({this.label = 'નવી વિગત', this.value = ''});
}

class _ExamRowDeleteOption {
  final String label;
  final VoidCallback remove;

  const _ExamRowDeleteOption(this.label, this.remove);
}

class NavPageItem {
  final String id;
  final String title;
  final String icon;
  final bool isLandscape;
  final String category;
  final int subIndex;

  const NavPageItem({
    required this.id,
    required this.title,
    required this.icon,
    this.isLandscape = false,
    required this.category,
    this.subIndex = 0,
  });
}

// ============================================================================
// Main Screen Widget
// ============================================================================

class ExamPlanningScreen extends StatefulWidget {
  const ExamPlanningScreen({
    super.key,
    this.useDatabaseData = false,
    this.databaseData = const <String, dynamic>{},
    this.savedData = const <String, dynamic>{},
    this.onSaveData,
    this.embedded = false,
  });

  final bool useDatabaseData;
  final Map<String, dynamic> databaseData;
  final Map<String, dynamic> savedData;
  final Future<void> Function(Map<String, dynamic>)? onSaveData;
  final bool embedded;

  @override
  State<ExamPlanningScreen> createState() => _ExamPlanningScreenState();
}

class _ExamPlanningScreenState extends State<ExamPlanningScreen> {
  // Colors matching the original Gujarati Exam Planning design
  static const Color kNavy = Color(0xFF0B2A5B);
  static const Color kNavyDark = Color(0xFF06143A);
  static const Color kSaffron = Color(0xFFFF9933);
  static const Color kGreen = Color(0xFF138808);
  static const Color kRed = Color(0xFFB3261E);

  final SchoolMeta meta = SchoolMeta();

  // Block counts for 3-5 ('a') and 6-8 ('b')
  int blocksA = 5;
  int blocksB = 5;
  String genderMode = 'both'; // 'both', 'boys', 'girls'
  String superMode = 'same'; // 'same' or 'change'
  int superRowsPerPageA = 27;
  int superRowsPerPageB = 27;
  int checkRowsPerPage = 27;
  int bundlesPerPage = 4; // 4, 2, or 1
  int doorsPerPage = 4; // 4, 2, or 1

  // Per-page Font Size Control (% scale, default 100%)
  final Map<String, int> pageFontScales = {};
  final Map<String, double> pageRowHeights = {};
  final Map<String, List<ExamExtraDetailRow>> extraPageRows =
      <String, List<ExamExtraDetailRow>>{};
  final Map<String, String> indexCellOverrides = <String, String>{};
  final Map<String, String> customTextOverrides = <String, String>{};
  final Map<String, Offset> customTextOffsets = <String, Offset>{};
  Offset coverLogoOffset = Offset.zero;
  Offset headerLogoOffset = Offset.zero;
  double coverLogoSize = 140.0;
  double headerLogoSize = 42.0;
  String schoolNameLang = 'gu';

  String get _resolvedRegisteredExamSchoolName {
    final data = widget.databaseData;
    final gu = _planningText(data['schoolNameGu'], _planningText(data['schoolName']));
    final en = _planningText(data['schoolNameEn'], _planningText(data['schoolName']));
    if (schoolNameLang == 'en') {
      return en.isNotEmpty ? en : (gu.isNotEmpty ? gu : meta.schoolName);
    }
    return gu.isNotEmpty ? gu : (en.isNotEmpty ? en : meta.schoolName);
  }

  String get _resolvedRegisteredExamSchoolAddress {
    final data = widget.databaseData;
    final gu = _planningText(data['schoolAddressGu'], _planningText(data['schoolAddress']));
    final en = _planningText(data['schoolAddressEn'], _planningText(data['schoolAddress']));
    if (schoolNameLang == 'en') {
      return en.isNotEmpty ? en : (gu.isNotEmpty ? gu : meta.address);
    }
    return gu.isNotEmpty ? gu : (en.isNotEmpty ? en : meta.address);
  }

  void _setExamSchoolNameLanguage(String lang) {
    setState(() {
      schoolNameLang = lang == 'en' ? 'en' : 'gu';
      final regName = _resolvedRegisteredExamSchoolName;
      if (regName.isNotEmpty) meta.schoolName = regName;
      final regAddr = _resolvedRegisteredExamSchoolAddress;
      if (regAddr.isNotEmpty) meta.address = regAddr;
      customTextOverrides.remove('hdr_school_name');
      customTextOverrides.remove('cover_school_name');
      customTextOverrides.remove('ftr_school_left');
      customTextOverrides.remove('hdr_address');
      customTextOverrides.remove('cover_address');
    });
    _scheduleExamDeviceAutoSave();
  }
  Set<String> classesWithAnswersInQuestionPaper = <String>{};
  bool include5PercentReserveInStationery = true;
  String? _selectedRowSection;
  int? _selectedRowIndex;
  int? _selectedBlockNo;
  int? _selectedBundleCardIndex;
  List<String> editableInstructions = <String>[];
  String? certificateStatementOverride;

  // PSM_EXAM_UNIVERSAL_ROW_EDIT_CONTROLS_20261031_V3

  // Active Navigation Page ID
  String activePageId = 'cover';

  /// Wraps the on-screen A4 page so PDF export captures exactly what is shown.
  final GlobalKey _a4PageCaptureKey = GlobalKey();
  bool _capturingForPdf = false;
  final ScrollController _toolsScrollCtrl = ScrollController();
  final ScrollController _pageScrollCtrl = ScrollController();
  final ScrollController _pageHScrollCtrl = ScrollController();

  // Live Clock
  late Timer _clockTimer;
  String _clockText = '';
  String _dateText = '';
  Uint8List? _schoolLogoBytes;
  String _schoolLogoDataUri = '';

  // Exam Class Range & Subject Selection State
  String examClassRangeMode = '3to8'; // '3to5', '6to8', '3to8', or 'custom'
  // PSM_EARLY_TEACHER_EXAM_FILTER_20261031_V2
  // Opt-in / per-teacher selection: Balvatika / Std. 1 / Std. 2 class teachers join or skip exam supervision.
  bool includeBalvatikaAndStd12Teachers = false;
  Set<String> customIncludedEarlyTeacherNames = <String>{};
  Set<String> customExcludedEarlyTeacherNames = <String>{};
  List<RegisterRow> allInsertedClassRows = <RegisterRow>[];
  Set<String> selectedExamClasses = <String>{};
  List<String> allAvailableExamSubjects = <String>[
    'ગુજરાતી',
    'ગણિત',
    'હિન્દી',
    'પર્યાવરણ',
    'અંગ્રેજી',
    'સંસ્કૃત',
    'વિજ્ઞાન',
    'સા. વિજ્ઞાન',
    'FLN',
    'શા. શિ.',
  ];
  Set<String> selectedSubjects35 = <String>{
    'ગુજરાતી',
    'ગણિત',
    'હિન્દી',
    'પર્યાવરણ',
    'અંગ્રેજી',
  };
  Set<String> selectedSubjects68 = <String>{
    'ગુજરાતી',
    'ગણિત',
    'સંસ્કૃત',
    'હિન્દી',
    'વિજ્ઞાન',
    'અંગ્રેજી',
    'સા. વિજ્ઞાન',
  };
  final Map<String, List<String>> _dbTeacherRawSubjects = <String, List<String>>{};
  final Map<String, bool> _earlyTeacherClassCache = <String, bool>{};
  Timer? _deviceAutoSaveTimer;

  bool get hasGroupA => registerRows.any((r) => r.group == 'a');
  bool get hasGroupB => registerRows.any((r) => r.group == 'b');

  List<String> get activeSelectedSubjects {
    final set = <String>{
      if (hasGroupA) ...selectedSubjects35,
      if (hasGroupB) ...selectedSubjects68,
    };
    if (set.isEmpty) {
      set.addAll(selectedSubjects35);
      set.addAll(selectedSubjects68);
    }
    return allAvailableExamSubjects.where((s) => set.contains(s)).toList()
      ..addAll(set.where((s) => !allAvailableExamSubjects.contains(s)));
  }

  // Data Collections
  late List<TeacherRecord> teachers;
  late List<CommitteeRow> committeeRows;
  late List<CommitteeRow> workDutyRows;
  late List<RegisterRow> registerRows;
  late List<TimetableRow> timetableRows;
  late List<SeatingRow> seatingA;
  late List<SeatingRow> seatingB;
  late List<AbsentPageSheet> absentSheets;
  late List<SupervisionRow> supervisionA;
  late List<SupervisionRow> supervisionB;
  late List<CheckingRow> checkingRows;
  late List<BundleCardData> bundleCards;
  late List<List<String>> bellScheduleRows;
  late List<List<String>> qpRegisterRows;
  late List<List<String>> stationeryRows;

  static const List<String> kInstructions = [
    'પરીક્ષા સમિતિના સભ્યોએ પરીક્ષા આયોજન સુવ્યવસ્થિત રીતે થાય તથા બાળકોને ભયમુક્ત વાતાવરણ પૂરું પાડવાના પ્રયત્નો કરવા.',
    'પરીક્ષાનાં પ્રશ્નપત્રોની ગોપનીયતા જળવાય એ સૌની સહિયારી જવાબદારી રહેશે.',
    'પરીક્ષા સમયગાળા દરમિયાન બાળક ગેરહાજર રહે તો તેનાં કારણો જાણી બાળકને શાળામાં આવવા પ્રેરાય તેવા યોગ્ય પ્રયત્નો કરવા.',
    'પ્રજ્ઞા ધોરણોના શિક્ષકોએ તાલીમમાં જણાવેલ કાર્યપદ્ધતિથી યોગ્ય કામગીરી કરવી તથા જરૂરી પત્રકો અને આધારોની ચકાસણી અને સાચવણી કરવાની રહેશે.',
    'આકસ્મિક કારણો સિવાય શિક્ષકે રજાનો આગ્રહ રાખવો નહીં. જો કોઈ શિક્ષકને પરીક્ષા દરમિયાન રજાની જરૂર જણાય તો શક્ય હોય ત્યાં સુધી અગાઉથી જાણ કરવી.',
    'ખંડ નિરીક્ષણની જવાબદારી સોંપેલ શિક્ષકે ખંડના ધોરણ પ્રમાણે હાજર અને ગેરહાજર વિદ્યાર્થીઓની સંખ્યાનું સરવૈયું કરી આપવાનું રહેશે. તથા તે મુજબ રોજ રોજકામ પત્રક ભરી સહીઓ કરવાની રહેશે.',
    'વર્ગશિક્ષકે જવાબવહીઓની સંખ્યા ગણીને તે મુજબ જ રોજકામ પત્રક બંડલ સાથે બાંધવાનું રહેશે.',
    'ધોરણ અને વિષય મુજબ ફાળવેલ જવાબવહીઓની યોગ્ય રીતે ચકાસણી કરી સમયસર પરત જમા કરાવવાની રહેશે.',
    'પરીક્ષાના ગુણ અંગે ઉપલી કચેરી દ્વારા જાણ કરવામાં આવે ત્યારે ઓનલાઈન એન્ટ્રી કરવાની જવાબદારી ધોરણ મુજબના વિષયશિક્ષકની રહેશે. તેથી ગુણપત્રક તૈયાર કરી આચાર્યશ્રીની સહી કરાવવાની રહેશે.',
    'પરીક્ષા શરૂ થાય તે પહેલાં પરીક્ષાના સમયપત્રકની તમામ વર્ગો અને વિષયોના શિક્ષકોને જાણ કરવામાં આવે તથા સમયપત્રક મુજબ પરીક્ષા યોજાય તેની ખાતરી કરવાની રહેશે.',
    'પરીક્ષા માટે જરૂરી સ્ટેશનરી, હાજરીપત્રક, બેઠક વ્યવસ્થા અને અન્ય સામગ્રીની અગાઉથી તૈયારી કરી લેવાની રહેશે.',
    'પરીક્ષા ખંડમાં પૂરતો પ્રકાશ, હવા-ઉજાસ, સ્વચ્છતા અને શાંતિ જળવાય તેની યોગ્ય વ્યવસ્થા કરવાની રહેશે.',
    'પરીક્ષા શરૂ થાય તે પહેલાં વિદ્યાર્થીઓને પરીક્ષાના નિયમો, સમયમર્યાદા અને જવાબવહીમાં જરૂરી વિગતો ભરવા અંગે સ્પષ્ટ સૂચનાઓ આપવાની રહેશે.',
    'પરીક્ષા દરમિયાન વિદ્યાર્થીઓને કોઈપણ પ્રકારની શારીરિક કે માનસિક અસ્વસ્થતા ન થાય અને તેઓ શાંતિપૂર્ણ વાતાવરણમાં પરીક્ષા આપી શકે તે માટે સંવેદનશીલ અભિગમ રાખવાનો રહેશે.',
    'પરીક્ષા ખંડમાં બેઠક વ્યવસ્થા એવી રીતે ગોઠવવાની રહેશે કે વિદ્યાર્થીઓને પ્રશ્નપત્ર ઉકેલવામાં પૂરતી જગ્યા મળે અને પરીક્ષાની નિષ્પક્ષતા જળવાય.',
    'પરીક્ષા દરમિયાન સમયાંતરે બેલ અથવા અન્ય સૂચન વ્યવસ્થા દ્વારા પરીક્ષાના પ્રારંભ, બાકી રહેલા સમય અને પૂર્ણતાની જાણ વિદ્યાર્થીઓને થાય તેવી વ્યવસ્થા કરવાની રહેશે.',
    'પરીક્ષા દરમિયાન કોઈ વિદ્યાર્થીને પ્રશ્ન સમજવામાં મુશ્કેલી પડે તો પરીક્ષાના નિયમોને અનુરૂપ સ્પષ્ટતા કરવી, પરંતુ જવાબ મેળવવામાં મદદરૂપ થાય તેવું માર્ગદર્શન આપવું નહીં.',
    'પરીક્ષા દરમિયાન વીજળી, પીવાના પાણી, પંખા અથવા અન્ય પાયાની સુવિધાઓમાં વિક્ષેપ ન પડે તેની અગાઉથી ચકાસણી કરવાની રહેશે.',
    'આગ, કુદરતી આફત અથવા અન્ય આકસ્મિક પરિસ્થિતિ ઊભી થાય તો વિદ્યાર્થીઓની સલામતીને પ્રાથમિકતા આપી શાળાની આપત્તિ વ્યવસ્થાપન પ્રક્રિયા મુજબ કામગીરી કરવાની રહેશે.',
    'પરીક્ષા દરમિયાન શાળાના અન્ય કાર્યક્રમો, બિનજરૂરી અવરજવર અને ઘોંઘાટને નિયંત્રિત કરી પરીક્ષાનું શાંતિપૂર્ણ વાતાવરણ જળવાય તેની કાળજી રાખવાની રહેશે.',
  ];

  @override
  void initState() {
    super.initState();
    editableInstructions = List<String>.from(kInstructions);
    if (widget.useDatabaseData) {
      _initDatabaseData();
      _applySavedDatabasePlan(widget.savedData);
    } else {
      _initDefaultData();
    }
    _loadExamPlanFromDeviceAutoSave();
    _updateClock();
    _clockTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _updateClock());
  }

  @override
  void dispose() {
    _deviceAutoSaveTimer?.cancel();
    _clockTimer.cancel();
    super.dispose();
  }

  String get _examDeviceSaveKey {
    final schoolRef = (widget.databaseData['schoolRef'] ?? '').toString().trim();
    return schoolRef.isNotEmpty
        ? 'psm_exam_planning_autosave_$schoolRef'
        : 'psm_exam_planning_autosave_v1';
  }

  void _scheduleExamDeviceAutoSave() {
    _deviceAutoSaveTimer?.cancel();
    _deviceAutoSaveTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final jsonStr = exportBackupJsonString();
        await prefs.setString(_examDeviceSaveKey, jsonStr);
      } catch (_) {}
    });
  }

  Future<void> _loadExamPlanFromDeviceAutoSave() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final schoolRef = (widget.databaseData['schoolRef'] ?? '').toString().trim();
      final raw = schoolRef.isNotEmpty
          ? prefs.getString(_examDeviceSaveKey)
          : (prefs.getString(_examDeviceSaveKey) ??
              prefs.getString('psm_exam_planning_autosave_v1'));
      if (raw != null && raw.isNotEmpty) {
        final map = _planningMap(jsonDecode(raw));
        // Use the on-device copy when there is no database copy or when the
        // device copy is newer (all page settings are restored either way).
        final dbAt = '${widget.savedData['savedAt'] ?? ''}';
        final devAt = '${map['savedAt'] ?? ''}';
        final deviceIsNewer = widget.savedData.isEmpty ||
            dbAt.isEmpty ||
            (devAt.isNotEmpty && devAt.compareTo(dbAt) > 0);
        if (map.isNotEmpty && mounted && deviceIsNewer) {
          setState(() {
            _applySavedDatabasePlan(map);
          });
        }
      }
    } catch (_) {}
  }

  int? _standardNumOfClassName(String className) {
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    var norm = className;
    for (int i = 0; i < guj.length; i++) {
      norm = norm.replaceAll(guj[i], '$i');
    }
    if (norm.toUpperCase().contains('BAL') || norm.contains('બાલ')) {
      return 0;
    }
    final m = RegExp(r'\d+').firstMatch(norm);
    return m != null ? int.tryParse(m.group(0)!) : null;
  }

  /// Directly sets genderMode ('boys', 'girls', or 'both') from school data & exam class student counts.
  void _autoDetectDirectGenderMode() {
    final typeText = _planningText(
      widget.databaseData['schoolType'],
      _planningText(widget.databaseData['genderMode']),
    );
    // Registered type wins; the school name is used only when no type exists.
    final rawType = typeText.isEmpty ? '' : SchoolType.canonical(typeText);
    final sName = typeText.isEmpty ? meta.schoolName.toLowerCase() : '';

    int sumBoys = 0;
    int sumGirls = 0;
    for (final r in registerRows) {
      sumBoys += r.boys;
      sumGirls += r.girls;
    }

    if (rawType == 'boys' ||
        sName.contains('કુમાર') ||
        sName.contains('kumar') ||
        (sumBoys > 0 && sumGirls == 0)) {
      genderMode = 'boys';
      for (final r in registerRows) {
        final tot = r.databaseTotal ?? (r.boys + r.girls);
        if (r.boys == 0 && tot > 0) r.boys = tot;
        r.girls = 0;
      }
    } else if (rawType == 'girls' ||
        sName.contains('કન્યા') ||
        sName.contains('kanya') ||
        (sumGirls > 0 && sumBoys == 0)) {
      genderMode = 'girls';
      for (final r in registerRows) {
        final tot = r.databaseTotal ?? (r.boys + r.girls);
        if (r.girls == 0 && tot > 0) r.girls = tot;
        r.boys = 0;
      }
    } else {
      genderMode = 'both';
    }
  }

  /// Applies class range preset ('3to5', '6to8', '3to8') and updates Register, Subjects, Teachers & all Patraks!
  void _applyExamClassRangePreset(String mode, {bool notify = true}) {
    final matched = <String>{};
    for (final r in allInsertedClassRows) {
      final std = _standardNumOfClassName(r.className);
      if (mode == '3to5') {
        if ((std != null && std >= 3 && std <= 5) ||
            (std == null && r.group == 'a')) {
          matched.add(r.className);
        }
      } else if (mode == '6to8') {
        if ((std != null && std >= 6 && std <= 8) ||
            (std == null && r.group == 'b')) {
          matched.add(r.className);
        }
      } else {
        // '3to8': only exam classes (standards 3 to 8)
        if ((std != null && std >= 3 && std <= 8) || std == null) {
          matched.add(r.className);
        }
      }
    }
    setState(() {
      examClassRangeMode = mode;
      if (matched.isNotEmpty) {
        selectedExamClasses = matched;
      } else {
        selectedExamClasses =
            allInsertedClassRows.map((r) => r.className).toSet();
      }
      _syncExamSelectionToPatraks(rebuildTimetable: true);
    });
    if (notify) {
      final lbl = mode == '3to5'
          ? 'ધોરણ ૩ થી ૫'
          : mode == '6to8'
              ? 'ધોરણ ૬ થી ૮'
              : 'ધોરણ ૩ થી ૮';
      _showSnack(
          '🎯 $lbl (${registerRows.length} વર્ગો) અને પસંદ કરેલ વિષયો મુજબ સંપૂર્ણ પરીક્ષા આયોજન તૈયાર!');
    }
  }

  /// Syncs selectedExamClasses & selectedSubjects35/68 into Register, Teachers, Timetable, and all 18 Patraks.
  void _syncExamSelectionToPatraks({bool rebuildTimetable = true}) {
    // 1. Rebuild registerRows ONLY for selectedExamClasses with registered student counts
    if (allInsertedClassRows.isNotEmpty) {
      final prevByClass = <String, RegisterRow>{
        for (final r in registerRows) r.className: r,
      };
      final filtered = <RegisterRow>[];
      for (final src in allInsertedClassRows) {
        if (!selectedExamClasses.contains(src.className)) continue;
        final prev = prevByClass[src.className];
        filtered.add(RegisterRow(
          className: src.className,
          group: src.group,
          boys: prev?.boys ?? src.boys,
          girls: prev?.girls ?? src.girls,
          databaseTotal: prev?.databaseTotal ?? src.databaseTotal,
          teacherSign: prev?.teacherSign ?? src.teacherSign,
          remarks: prev?.remarks ?? src.remarks,
        ));
      }
      if (filtered.isNotEmpty) {
        registerRows = filtered;
      }
    }

    // 2. Directly apply boys / girls / both logic
    _autoDetectDirectGenderMode();

    // 3. Filter each teacher's taught subjects to ONLY include from activeSelectedSubjects
    final allowedSubjSet = activeSelectedSubjects.toSet();
    for (final t in teachers) {
      final rawDbSubs = _dbTeacherRawSubjects[t.name] ?? t.subjects;
      final filteredSubs =
          rawDbSubs.where((s) => allowedSubjSet.contains(s)).toList();
      t.subjects = filteredSubs;
    }

    // 4. Rebuild Timetable to include ONLY selected subjects for active groups
    if (rebuildTimetable) {
      _rebuildTimetableForSelectedScopeAndSubjects();
    }

    // 4B. Ensure excluded Balvatika / Class 1 & 2 teachers are not in Committee or Work Duty rows
    final activeDutyNames = _examDutyTeachers.map((t) => t.name.trim()).toSet();
    final earlyExcludedNames = teachers
        .where((t) => !_isEarlyTeacherIncludedInDuty(t))
        .map((t) => t.name.trim())
        .toSet();
    if (earlyExcludedNames.isNotEmpty && _examDutyTeachers.isNotEmpty) {
      for (int i = 0; i < committeeRows.length; i++) {
        if (i == 0 &&
            meta.principalName.trim().isNotEmpty &&
            meta.principalName != '________' &&
            committeeRows[i].teacherName == meta.principalName) {
          continue;
        }
        if (earlyExcludedNames.contains(committeeRows[i].teacherName.trim())) {
          committeeRows[i].teacherName =
              _examDutyTeachers[i % _examDutyTeachers.length].name;
        }
      }
      for (int i = 0; i < workDutyRows.length; i++) {
        if (earlyExcludedNames.contains(workDutyRows[i].teacherName.trim())) {
          workDutyRows[i].teacherName =
              _examDutyTeachers[(i + 2) % _examDutyTeachers.length].name;
        }
      }
    }

    // 5. Rebuild all downstream patraks
    autoAllocateSeatingFromRegister(notify: false);
    rebuildAbsentPages(notify: false);
    generateSupervision(notify: false);
    rebuildCheckingRows(notify: false);
    rebuildBundles(notify: false);
    rebuildQpRegister(notify: false);
    rebuildStationerySheet(false);
    _scheduleExamDeviceAutoSave();
  }

  void _rebuildTimetableForSelectedScopeAndSubjects() {
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
    while (workingDates.length < 30) {
      if (d.weekday != DateTime.sunday) workingDates.add(d);
      d = d.add(const Duration(days: 1));
    }
    String fmtDate(DateTime dt) =>
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

    final existingA = <String, TimetableRow>{
      for (final r in timetableRows.where((x) => x.group == 'a')) r.subject: r,
    };
    final existingB = <String, TimetableRow>{
      for (final r in timetableRows.where((x) => x.group == 'b')) r.subject: r,
    };

    final newRows = <TimetableRow>[];
    if (hasGroupA) {
      final subs35 = allAvailableExamSubjects
          .where((s) => selectedSubjects35.contains(s))
          .toList()
        ..addAll(selectedSubjects35
            .where((s) => !allAvailableExamSubjects.contains(s)));
      for (int i = 0; i < subs35.length; i++) {
        final sub = subs35[i];
        final prev = existingA[sub];
        final dt = workingDates[i % workingDates.length];
        newRows.add(TimetableRow(
          date: (prev != null && prev.date.isNotEmpty) ? prev.date : fmtDate(dt),
          day: (prev != null && prev.day.isNotEmpty)
              ? prev.day
              : (gujDays[dt.weekday] ?? 'સોમવાર'),
          stdLabel: (prev != null && prev.stdLabel.isNotEmpty)
              ? prev.stdLabel
              : (sub == 'હિન્દી' ? '૫' : '૩ થી ૫'),
          subject: sub,
          time: (prev != null && prev.time.isNotEmpty)
              ? prev.time
              : '11:00 થી 1:00',
          marks: (prev != null && prev.marks.isNotEmpty) ? prev.marks : '40',
        ));
      }
    }

    if (hasGroupB) {
      final subs68 = allAvailableExamSubjects
          .where((s) => selectedSubjects68.contains(s))
          .toList()
        ..addAll(selectedSubjects68
            .where((s) => !allAvailableExamSubjects.contains(s)));
      for (int i = 0; i < subs68.length; i++) {
        final sub = subs68[i];
        final prev = existingB[sub];
        final dt = workingDates[i % workingDates.length];
        final isSat = dt.weekday == DateTime.saturday;
        newRows.add(TimetableRow(
          date: (prev != null && prev.date.isNotEmpty) ? prev.date : fmtDate(dt),
          day: (prev != null && prev.day.isNotEmpty)
              ? prev.day
              : (gujDays[dt.weekday] ?? 'સોમવાર'),
          stdLabel: (prev != null && prev.stdLabel.isNotEmpty)
              ? prev.stdLabel
              : '૬ થી ૮',
          subject: sub,
          time: (prev != null && prev.time.isNotEmpty)
              ? prev.time
              : (isSat ? '8:00 થી 11:00' : '2:00 થી 5:00'),
          marks: (prev != null && prev.marks.isNotEmpty) ? prev.marks : '80',
        ));
      }
    }

    if (newRows.isNotEmpty) {
      timetableRows = newRows;
    }
  }

  void _updateClock() {
    final now = DateTime.now();
    int h = now.hour;
    final ap = h >= 12 ? 'PM' : 'AM';
    h = h % 12;
    if (h == 0) h = 12;
    final days = [
      'રવિવાર',
      'સોમવાર',
      'મંગળવાર',
      'બુધવાર',
      'ગુરુવાર',
      'શુક્રવાર',
      'શનિવાર'
    ];
    final clk =
        '🕒 ${h.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} $ap';
    final cdt =
        '📅 ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} · ${days[now.weekday % 7]}';
    if (mounted) {
      setState(() {
        _clockText = clk;
        _dateText = cdt;
      });
    }
  }

  // Convert English digits to Gujarati digits
  String gn(Object? input) {
    const guj = ['૦', '૧', '૨', '૩', '૪', '૫', '૬', '૭', '૮', '૯'];
    return input
        .toString()
        .replaceAllMapped(RegExp(r'\d'), (m) => guj[int.parse(m.group(0)!)]);
  }

  // Parse Gujarati or English number string
  int? parseNum(String? val) {
    if (val == null || val.trim().isEmpty) return null;
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    String norm = val.split('').map((ch) {
      final idx = guj.indexOf(ch);
      return idx >= 0 ? idx.toString() : ch;
    }).join();
    norm = norm.replaceAll(RegExp(r'[^\d-]'), '').trim();
    if (norm.isEmpty) return null;
    return int.tryParse(norm);
  }

  Map<String, dynamic> _planningMap(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map)
      return value.map((key, value) => MapEntry(key.toString(), value));
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _planningList(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value.whereType<Map>().map(_planningMap).toList();
  }

  List<String> _planningStringList(dynamic value) {
    if (value is! List) return <String>[];
    return value
        .map((entry) => _planningText(entry))
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  String _planningText(dynamic value, [String fallback = '']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty || text.toLowerCase() == 'null' ? fallback : text;
  }

  int _planningInt(dynamic value, [int fallback = 0]) {
    if (value is num) return value.round();
    return int.tryParse((value ?? '').toString()) ?? fallback;
  }

  String _planningStandard(Map<String, dynamic> row) {
    final raw = _planningText(row['standard']);
    if (raw.isNotEmpty) return raw;
    final key = _planningText(row['classKey'], _planningText(row['label']));
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    var normal = key;
    for (var i = 0; i < guj.length; i++) {
      normal = normal.replaceAll(guj[i], '$i');
    }
    return RegExp(r'[1-8]').firstMatch(normal)?.group(0) ?? '';
  }

  String _examClassMatchKey(String value) => value.trim().toLowerCase();

  // Deliberately stricter than _standardNumOfClassName: this classifier must
  // never interpret a UUID or arbitrary class ID's digits as a grade number.
  int? _examTeacherGradeFromClassToken(String raw) {
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    var value = raw.trim();
    for (var i = 0; i < guj.length; i++) {
      value = value.replaceAll(guj[i], '$i');
    }
    final upper = value.toUpperCase();
    if (upper.contains('BAL') || value.contains('બાલ')) return 0;

    final match = RegExp(
      r'^(?:(?:ધોરણ|ધો\.?|CLASS|STD\.?|STANDARD|GRADE)\s*)?([0-8])(?:\s*[-_/ ]\s*[A-Z0-9]+)?$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  bool _teacherIsBalvatikaOrStd12(TeacherRecord teacher) {
    final cacheKey = teacher.id.trim().isNotEmpty
        ? 'id:${teacher.id.trim()}'
        : 'name:${teacher.name.trim().toLowerCase()}';
    final cached = _earlyTeacherClassCache[cacheKey];
    if (cached != null) return cached;
    final result = _calculateEarlyTeacherClass(teacher);
    _earlyTeacherClassCache[cacheKey] = result;
    return result;
  }

  bool _calculateEarlyTeacherClass(TeacherRecord teacher) {
    final tokens = <String>{
      ...teacher.assignedClasses,
      ...teacher.allowedClasses,
    }.where((value) => value.trim().isNotEmpty).toSet();
    final normalizedTokens = tokens.map(_examClassMatchKey).toSet();
    final matchedTokenKeys = <String>{};
    final linkedStandards = <int>{};
    var hasUnknownClassLink = false;
    final classRows = _planningList(widget.databaseData['classes']);

    // Prefer authoritative class records. If a teacher is linked to both an
    // early class and an exam class (3-8), keep that teacher eligible.
    for (final row in classRows) {
      final candidates = <String>{
        _planningText(row['id']),
        _planningText(row['classKey']),
        _planningText(row['label']),
        _planningText(row['className']),
        _planningText(row['timetableClassName']),
        _planningText(row['legacyTimetableClassName']),
      }.where((value) => value.isNotEmpty).map(_examClassMatchKey).toSet();
      final classTeacherId = _planningText(row['classTeacherId']);
      final linkedAsClassTeacher = teacher.id.isNotEmpty &&
          classTeacherId.isNotEmpty &&
          classTeacherId == teacher.id;
      final matchedTokens = candidates.intersection(normalizedTokens);
      final linkedByAssignment = matchedTokens.isNotEmpty;
      if (!linkedAsClassTeacher && !linkedByAssignment) continue;
      matchedTokenKeys.addAll(matchedTokens);

      final standardText = _planningText(
        row['standard'],
        _planningText(row['label'], _planningText(row['classKey'])),
      );
      final standard = _examTeacherGradeFromClassToken(standardText);
      if (standard == null) {
        hasUnknownClassLink = true;
      } else {
        linkedStandards.add(standard);
      }
    }

    // Some schools store allowed classes as human-readable standards instead
    // of class IDs/keys. Unknown IDs are deliberately treated as unclassified
    // so a teacher is never excluded just because the mapping is incomplete.
    for (final token in tokens) {
      final key = _examClassMatchKey(token);
      if (matchedTokenKeys.contains(key)) continue;
      final standard = _examTeacherGradeFromClassToken(token);
      if (standard == null) {
        hasUnknownClassLink = true;
      } else {
        linkedStandards.add(standard);
      }
    }

    return linkedStandards.isNotEmpty &&
        !hasUnknownClassLink &&
        linkedStandards.every((grade) => grade >= 0 && grade <= 2);
  }

  bool _isEarlyTeacherIncludedInDuty(TeacherRecord teacher) {
    if (!_teacherIsBalvatikaOrStd12(teacher)) return true;
    final key = teacher.name.trim();
    if (customIncludedEarlyTeacherNames.contains(key)) return true;
    if (customExcludedEarlyTeacherNames.contains(key)) return false;
    return includeBalvatikaAndStd12Teachers;
  }

  List<TeacherRecord> get _examDutyTeachers =>
      teachers.where(_isEarlyTeacherIncludedInDuty).toList(growable: false);

  int get _identifiedEarlyClassTeacherCount =>
      teachers.where(_teacherIsBalvatikaOrStd12).length;

  Future<void> _showEarlyTeachersSupervisionDialog({bool generateAfter = false}) async {
    final earlyTeachers = teachers.where(_teacherIsBalvatikaOrStd12).toList();
    if (earlyTeachers.isEmpty) {
      if (generateAfter) generateSupervision(notify: true);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text(
            '👩‍🏫 બાલવાટિકા તથા ધોરણ ૧ અને ૨ ના વર્ગ શિક્ષકો — સુપરવિઝન પસંદગી',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: kNavy),
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'બાલવાટિકા તથા ધોરણ ૧ અને ૨ ના વર્ગ શિક્ષકોને પરીક્ષા ન હોય તેવા વિદ્યાર્થીઓને ભણાવવાના હોવાથી અથવા ક્યારેક સુપરવિઝન દરમિયાન ફ્રી હોવાથી, પરીક્ષા સુપરવિઝનમાં કોને સામેલ કરવા છે તે પસંદ કરો:',
                    style: TextStyle(fontSize: 13, color: Color(0xFF334155)),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () {
                          setDialogState(() {
                            includeBalvatikaAndStd12Teachers = true;
                            customExcludedEarlyTeacherNames.clear();
                            customIncludedEarlyTeacherNames = earlyTeachers
                                .map((t) => t.name.trim())
                                .toSet();
                          });
                        },
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('હા, બધાને સામેલ કરો'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          setDialogState(() {
                            includeBalvatikaAndStd12Teachers = false;
                            customIncludedEarlyTeacherNames.clear();
                            customExcludedEarlyTeacherNames = earlyTeachers
                                .map((t) => t.name.trim())
                                .toSet();
                          });
                        },
                        icon: const Icon(Icons.block_outlined, size: 18),
                        label: const Text('ના, બધાને બાકાત રાખો'),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  for (final t in earlyTeachers)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _isEarlyTeacherIncludedInDuty(t),
                      title: Text(
                        t.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        t.assignedClasses.isNotEmpty
                            ? 'વર્ગ: ${t.assignedClasses.join(", ")}'
                            : 'બાલવાટિકા / ધોરણ ૧–૨ શિક્ષક',
                      ),
                      onChanged: (checked) {
                        setDialogState(() {
                          final key = t.name.trim();
                          if (checked == true) {
                            customExcludedEarlyTeacherNames.remove(key);
                            customIncludedEarlyTeacherNames.add(key);
                          } else {
                            customIncludedEarlyTeacherNames.remove(key);
                            customExcludedEarlyTeacherNames.add(key);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('રદ કરો'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {});
                _syncExamSelectionToPatraks(rebuildTimetable: false);
                if (generateAfter) {
                  generateSupervision(notify: true);
                }
              },
              icon: const Icon(Icons.done_all, size: 18),
              label: Text(generateAfter
                  ? 'લાગુ કરો અને સુપરવિઝન બનાવો'
                  : 'લાગુ કરો'),
            ),
          ],
        ),
      ),
    );
  }

  String _normalizeExamClassName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final aliasMap = widget.databaseData['classAliasesToLabel'];
    if (aliasMap is Map) {
      final direct = aliasMap[trimmed] ?? aliasMap[trimmed.toUpperCase()];
      if (direct != null && direct.toString().trim().isNotEmpty) {
        return direct.toString().trim();
      }
    }
    for (final row in _planningList(widget.databaseData['classes'])) {
      final label = _planningText(row['label'], _planningText(row['classKey']));
      if (label.isEmpty) continue;
      final candidates = <String>{
        label,
        _planningText(row['classKey']),
        _planningText(row['id']),
        _planningText(row['timetableClassName']),
        _planningText(row['legacyTimetableClassName']),
      };
      if (candidates.any((c) => c.isNotEmpty && c.toLowerCase() == trimmed.toLowerCase())) {
        return label;
      }
    }
    return trimmed;
  }

  void _initDatabaseData() {
    final data = widget.databaseData;
    final rawLogo = data['schoolLogoBytes'];
    if (rawLogo is Uint8List && rawLogo.isNotEmpty) {
      _schoolLogoBytes = rawLogo;
    }
    _schoolLogoDataUri = _planningText(data['schoolLogoDataUri']);
    if (_schoolLogoBytes == null && _schoolLogoDataUri.startsWith('data:')) {
      final comma = _schoolLogoDataUri.indexOf(',');
      if (comma >= 0) {
        try {
          _schoolLogoBytes = base64Decode(_schoolLogoDataUri.substring(comma + 1));
        } catch (_) {}
      }
    }
    final initLang = _planningText(data['schoolNameLanguage'], 'gu').toLowerCase();
    schoolNameLang = initLang == 'en' ? 'en' : 'gu';
    meta.schoolName = _resolvedRegisteredExamSchoolName;
    meta.address = _resolvedRegisteredExamSchoolAddress;
    meta.taluka = _planningText(data['taluka'], '');
    meta.district = _planningText(data['district'], '');
    meta.payCenter = _planningText(data['payCenter'], '');
    meta.academicYear = _planningText(data['academicYear'], meta.academicYear);
    meta.crcName = _planningText(data['crcName'], '________');
    meta.principalName = _planningText(
      data['principalName'],
      _planningText(data['adminName'], '________'),
    );
    meta.examName = _planningText(data['savedExamName'], 'દ્વિતીય સત્રાંત / વાર્ષિક પરીક્ષા આયોજન');
    meta.bundleMonth = _planningText(data['bundleMonth'], meta.bundleMonth);

    teachers = _planningList(data['teachers'])
        .map((row) {
          final group = _planningText(row['group'], 'a') == 'b' ? 'b' : 'a';
          final rowSubjects = (row['subjects'] is List
                  ? row['subjects'] as List
                  : const <dynamic>[])
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toList();
          return TeacherRecord(
            id: _planningText(row['id']),
            name: _planningText(row['fullName'], _planningText(row['name'])),
            group: group,
            subjects: rowSubjects,
            assignedClasses: _planningStringList(row['assignedClasses']),
            allowedClasses: _planningStringList(row['allowedClasses']),
          );
        })
        .where((teacher) => teacher.name.isNotEmpty)
        .toList();

    if (teachers.isEmpty) {
      teachers = [
        TeacherRecord(name: 'પટેલ રમેશભાઈ કે.', group: 'a', subjects: ['ગુજરાતી', 'પર્યાવરણ']),
        TeacherRecord(name: 'શાહ મીનાબેન આર.', group: 'a', subjects: ['ગણિત', 'અંગ્રેજી']),
        TeacherRecord(name: 'જોષી કિરણબેન એમ.', group: 'a', subjects: ['હિન્દી', 'ગુજરાતી']),
        TeacherRecord(name: 'પંચાલ નિલેશભાઈ વી.', group: 'b', subjects: ['ગણિત', 'વિજ્ઞાન']),
        TeacherRecord(name: 'ત્રિવેદી કવિતાબેન એન.', group: 'b', subjects: ['ગુજરાતી', 'સંસ્કૃત']),
        TeacherRecord(name: 'રાવલ અશોકભાઈ ડી.', group: 'b', subjects: ['સા. વિજ્ઞાન', 'હિન્દી']),
      ];
    }

    const roles = <String>[
      'અધ્યક્ષ (આચાર્યશ્રી)',
      'પરીક્ષા મંત્રી',
      'સહ પરીક્ષા મંત્રી',
      'સભ્ય (ધો. ૩ થી ૫ સંયોજક)',
      'સભ્ય (ધો. ૬ થી ૮ સંયોજક)',
      'સભ્ય (મૂલ્યાંકન અને ચકાસણી)',
      'સભ્ય (સ્ટેશનરી અને સાહિત્ય)',
      'સભ્ય (બેઠક અને શિસ્ત વ્યવસ્થા)',
    ];
    const duties = <String>[
      'સમયપત્રક અને બેઠક વ્યવસ્થા આયોજન',
      'પ્રશ્નપત્ર પેકેટ સીલ ચકાસણી અને વિતરણ',
      'ઉત્તરવહી અને સ્ટેશનરી વિતરણ હિસાબ',
      'દૈનિક હાજર-ગેરહાજર રિપોર્ટ સંકલન',
      'ખંડ નિરીક્ષક ફાળવણી અને સંચાલન',
      'ઉત્તરવહી બંડલ સ્ટીકર અને સીલિંગ કામગીરી',
      'પેપર ચકાસણી વિતરણ અને પરત જમા નોંધ',
      'બેલ વ્યવસ્થા, પીવાનું પાણી અને સ્વચ્છતા',
    ];
    final dutyTeachersInit = _examDutyTeachers;
    String teacherAt(int i, [int offset = 0]) => dutyTeachersInit.isEmpty
        ? ''
        : dutyTeachersInit[(i + offset) % dutyTeachersInit.length].name;
    committeeRows = List.generate(
        roles.length,
        (i) => CommitteeRow(
              teacherName: (i == 0 &&
                      meta.principalName.trim().isNotEmpty &&
                      meta.principalName != '________')
                  ? meta.principalName
                  : teacherAt(i),
              roleOrDuty: roles[i],
            ));
    workDutyRows = List.generate(
        duties.length,
        (i) => CommitteeRow(
              teacherName: teacherAt(i, 2),
              roleOrDuty: duties[i],
            ));



    // Collect all taught subjects from DB and teachers
    final subjectPool = <String>[
      'ગુજરાતી',
      'ગણિત',
      'હિન્દી',
      'પર્યાવરણ',
      'અંગ્રેજી',
      'સંસ્કૃત',
      'વિજ્ઞાન',
      'સા. વિજ્ઞાન',
    ];
    if (data['subjects'] is List) {
      for (final s in (data['subjects'] as List)) {
        final clean = s.toString().trim();
        if (clean.isNotEmpty && !subjectPool.contains(clean)) {
          subjectPool.add(clean);
        }
      }
    }
    _dbTeacherRawSubjects.clear();
    for (final t in teachers) {
      _dbTeacherRawSubjects[t.name] = List<String>.from(t.subjects);
      for (final s in t.subjects) {
        final clean = s.trim();
        if (clean.isNotEmpty && !subjectPool.contains(clean)) {
          subjectPool.add(clean);
        }
      }
    }
    allAvailableExamSubjects = subjectPool;

    final rawGender = _planningText(data['genderMode'], 'both').toLowerCase();
    genderMode = const {'boys', 'girls', 'both'}.contains(rawGender)
        ? rawGender
        : 'both';

    final dbClasses = _planningList(data['classes']);
    allInsertedClassRows = dbClasses
        .map((row) {
          final standard = _planningStandard(row);
          final englishStandard = standard.replaceAll(RegExp(r'[^0-9]'), '');
          final standardNumber = int.tryParse(englishStandard) ?? 0;
          final group = standardNumber >= 6 ? 'b' : 'a';
          final displayLabel =
              _planningText(row['label'], _planningText(row['classKey']));
          var b = _planningInt(row['boys']);
          var g = _planningInt(row['girls']);
          final tot = _planningInt(row['total']);
          if (genderMode == 'boys') {
            if (b == 0 && tot > 0) b = tot;
            g = 0;
          } else if (genderMode == 'girls') {
            if (g == 0 && tot > 0) g = tot;
            b = 0;
          } else if (b == 0 && g == 0 && tot > 0) {
            b = (tot + 1) ~/ 2;
            g = tot - b;
          }
          return RegisterRow(
            className: displayLabel,
            group: group,
            boys: b,
            girls: g,
            databaseTotal: tot,
          );
        })
        .where((row) => row.className.isNotEmpty)
        .toList();

    if (allInsertedClassRows.isEmpty) {
      allInsertedClassRows = [
        for (final c in ['3A', '4A', '5A'])
          RegisterRow(className: c, group: 'a', boys: 15, girls: 15),
        for (final c in ['6A', '7A', '8A'])
          RegisterRow(className: c, group: 'b', boys: 15, girls: 15),
      ];
    }

    // By default, select only exam classes (standards 3 to 8)
    final examOnlyRows = allInsertedClassRows.where((r) {
      final std = _standardNumOfClassName(r.className);
      return std == null || (std >= 3 && std <= 8);
    }).toList();
    final initialExamRows =
        examOnlyRows.isNotEmpty ? examOnlyRows : allInsertedClassRows;
    selectedExamClasses = initialExamRows.map((r) => r.className).toSet();
    registerRows = initialExamRows
        .map((r) => RegisterRow(
              className: r.className,
              group: r.group,
              boys: r.boys,
              girls: r.girls,
              databaseTotal: r.databaseTotal,
            ))
        .toList();

    final has35 = registerRows.any((r) => r.group == 'a');
    final has68 = registerRows.any((r) => r.group == 'b');
    if (has35 && !has68) {
      examClassRangeMode = '3to5';
    } else if (!has35 && has68) {
      examClassRangeMode = '6to8';
    } else {
      examClassRangeMode = '3to8';
    }

    timetableRows = _planningList(data['examRows'])
        .map((row) => TimetableRow(
              date: _planningText(row['date']),
              day: _planningText(row['day']),
              stdLabel: _planningText(row['stdLabel']),
              subject: _planningText(row['subject']),
              time: _planningText(row['time']),
              marks: _planningText(row['marks'], '40'),
            ))
        .where((row) => row.stdLabel.isNotEmpty && row.subject.isNotEmpty)
        .toList();

    if (timetableRows.isEmpty) {
      timetableRows = [
        TimetableRow(date: '22/10/2026', day: 'ગુરુવાર', stdLabel: '૩ થી ૫', subject: 'ગુજરાતી', time: '11:00 થી 1:00', marks: '40'),
        TimetableRow(date: '23/10/2026', day: 'શુક્રવાર', stdLabel: '૩ થી ૫', subject: 'ગણિત', time: '11:00 થી 1:00', marks: '40'),
        TimetableRow(date: '26/10/2026', day: 'સોમવાર', stdLabel: '૫', subject: 'હિન્દી', time: '11:00 થી 1:00', marks: '40'),
        TimetableRow(date: '27/10/2026', day: 'મંગળવાર', stdLabel: '૩ થી ૫', subject: 'પર્યાવરણ', time: '11:00 થી 1:00', marks: '40'),
        TimetableRow(date: '28/10/2026', day: 'બુધવાર', stdLabel: '૩ થી ૫', subject: 'અંગ્રેજી', time: '11:00 થી 1:00', marks: '40'),
        TimetableRow(date: '22/10/2026', day: 'ગુરુવાર', stdLabel: '૬ થી ૮', subject: 'ગુજરાતી', time: '2:00 થી 5:00', marks: '80'),
        TimetableRow(date: '23/10/2026', day: 'શુક્રવાર', stdLabel: '૬ થી ૮', subject: 'ગણિત', time: '2:00 થી 5:00', marks: '80'),
        TimetableRow(date: '24/10/2026', day: 'શનિવાર', stdLabel: '૬ થી ૮', subject: 'સંસ્કૃત', time: '8:00 થી 11:00', marks: '80'),
        TimetableRow(date: '26/10/2026', day: 'સોમવાર', stdLabel: '૬ થી ૮', subject: 'હિન્દી', time: '2:00 થી 5:00', marks: '80'),
        TimetableRow(date: '27/10/2026', day: 'મંગળવાર', stdLabel: '૬ થી ૮', subject: 'વિજ્ઞાન', time: '2:00 થી 5:00', marks: '80'),
        TimetableRow(date: '28/10/2026', day: 'બુધવાર', stdLabel: '૬ થી ૮', subject: 'અંગ્રેજી', time: '2:00 થી 5:00', marks: '80'),
        TimetableRow(date: '29/10/2026', day: 'ગુરુવાર', stdLabel: '૬ થી ૮', subject: 'સા. વિજ્ઞાન', time: '2:00 થી 5:00', marks: '80'),
      ];
    }


    seatingA = <SeatingRow>[];
    seatingB = <SeatingRow>[];
    absentSheets = <AbsentPageSheet>[];
    supervisionA = <SupervisionRow>[];
    supervisionB = <SupervisionRow>[];
    checkingRows = <CheckingRow>[];
    bundleCards = <BundleCardData>[];
    bellScheduleRows = <List<String>>[
      [
        '1',
        'પ્રથમ બેલ (પરીક્ષા ખંડમાં પ્રવેશ)',
        '10:45 AM',
        '01:45 PM',
        'વિદ્યાર્થીઓની બેઠક ચકાસણી'
      ],
      [
        '2',
        'બીજો બેલ (ઉત્તરવહી / પ્રશ્નપત્ર વિતરણ)',
        '10:55 AM',
        '01:55 PM',
        'જરૂરી વિગતો ભરાવવી'
      ],
      [
        '3',
        'ત્રીજો બેલ (લેખન કાર્ય શરૂ)',
        '11:00 AM',
        '02:00 PM',
        'પરીક્ષાનો મુખ્ય સમય શરૂ'
      ],
      [
        '4',
        'મધ્ય બેલ (૧ કલાક / અડધો સમય પૂર્ણ)',
        '12:00 PM',
        '03:30 PM',
        'સમયની જાણકારી'
      ],
      [
        '5',
        'ચેતવણી બેલ (અંતિમ ૧૦ મિનિટ બાકી)',
        '12:50 PM',
        '04:50 PM',
        'પુરવણી બાંધવા સૂચના'
      ],
      [
        '6',
        'અંતિમ બેલ (પરીક્ષા પૂર્ણ — ઉત્તરવહી સંકલન)',
        '01:00 PM',
        '05:00 PM',
        'ક્રમવાર ઉત્તરવહી ગણતરી'
      ],
    ];
    qpRegisterRows = <List<String>>[];
    stationeryRows = <List<String>>[];
    _syncExamSelectionToPatraks(rebuildTimetable: true);
  }

  void _applySavedDatabasePlan(Map<String, dynamic> saved) {
    if (saved.isEmpty) return;
    final dbSchoolName = meta.schoolName;
    final dbAddress = meta.address;
    final dbTaluka = meta.taluka;
    final dbDistrict = meta.district;
    final dbPayCenter = meta.payCenter;
    final dbPrincipal = meta.principalName;
    final dbCrc = meta.crcName;
    final dbGenderMode = genderMode;
    try {
      if (saved['schoolNameLang'] is String) {
        final sl = saved['schoolNameLang'].toString().trim().toLowerCase();
        if (sl == 'en' || sl == 'gu') schoolNameLang = sl;
      }
      if (widget.databaseData['schoolNameLanguage'] is String) {
        final dl = widget.databaseData['schoolNameLanguage'].toString().trim().toLowerCase();
        if (dl == 'en' || dl == 'gu') schoolNameLang = dl;
      }
      if (saved['meta'] is Map) {
        final savedMeta = _planningMap(saved['meta']);
        meta.applyJson(savedMeta);
        final authName = _resolvedRegisteredExamSchoolName;
        if (authName.isNotEmpty) {
          meta.schoolName = authName;
        } else if (dbSchoolName.isNotEmpty) {
          meta.schoolName = dbSchoolName;
        }
        final authAddr = _resolvedRegisteredExamSchoolAddress;
        if (authAddr.isNotEmpty) {
          meta.address = authAddr;
        } else if (dbAddress.isNotEmpty) {
          meta.address = dbAddress;
        }
        if (dbTaluka.isNotEmpty &&
            (meta.taluka.trim().isEmpty || meta.taluka == 'પાટણ')) {
          meta.taluka = dbTaluka;
        }
        if (dbDistrict.isNotEmpty &&
            (meta.district.trim().isEmpty || meta.district == 'પાટણ')) {
          meta.district = dbDistrict;
        }
        if (dbPayCenter.isNotEmpty &&
            (meta.payCenter.trim().isEmpty || meta.payCenter == 'બગવાડા')) {
          meta.payCenter = dbPayCenter;
        }
        if (dbPrincipal.isNotEmpty &&
            dbPrincipal != '________' &&
            (meta.principalName.trim().isEmpty ||
                meta.principalName == '________')) {
          meta.principalName = dbPrincipal;
        }
        if (dbCrc.isNotEmpty &&
            dbCrc != '________' &&
            (meta.crcName.trim().isEmpty || meta.crcName == '________')) {
          meta.crcName = dbCrc;
        }
      }
      blocksA = _planningInt(saved['blocksA'], blocksA).clamp(1, 30);
      blocksB = _planningInt(saved['blocksB'], blocksB).clamp(1, 30);
      superMode = _planningText(saved['superMode'], superMode);
      if (dbGenderMode == 'boys' || dbGenderMode == 'girls') {
        genderMode = dbGenderMode;
      } else if (saved['genderMode'] is String &&
          const {'boys', 'girls', 'both'}.contains(saved['genderMode'])) {
        genderMode = saved['genderMode'] as String;
      }
      if (saved['pageFontScales'] is Map) {
        pageFontScales
          ..clear()
          ..addAll(_planningMap(saved['pageFontScales'])
              .map((key, value) => MapEntry(key, _planningInt(value, 100))));
      }
      if (saved['pageRowHeights'] is Map) {
        pageRowHeights
          ..clear()
          ..addAll(_planningMap(saved['pageRowHeights']).map((key, value) =>
              MapEntry(
                  key,
                  value is num
                      ? value.toDouble()
                      : double.tryParse('$value') ?? 0)));
      }
      if (saved['extraPageRows'] is Map) {
        extraPageRows.clear();
        final rawPages = _planningMap(saved['extraPageRows']);
        for (final entry in rawPages.entries) {
          final rows = _planningList(entry.value)
              .map((row) => ExamExtraDetailRow(
                    label: _planningText(row['label'], 'નવી વિગત'),
                    value: _planningText(row['value']),
                  ))
              .toList();
          if (rows.isNotEmpty) extraPageRows[entry.key] = rows;
        }
      }
      if (saved['indexCellOverrides'] is Map) {
        indexCellOverrides
          ..clear()
          ..addAll(_planningMap(saved['indexCellOverrides']).map(
              (key, value) => MapEntry(key, value.toString())));
      }
      if (saved['editableInstructions'] is List) {
        final restoredInstructions = (saved['editableInstructions'] as List)
            .map((value) => value.toString())
            .toList();
        if (restoredInstructions.isNotEmpty) {
          editableInstructions = restoredInstructions;
        }
      }
      if (saved['certificateStatementOverride'] is String) {
        certificateStatementOverride =
            saved['certificateStatementOverride'] as String;
      }
      if (saved['customTextOverrides'] is Map) {
        customTextOverrides
          ..clear()
          ..addAll(_planningMap(saved['customTextOverrides'])
              .map((k, v) => MapEntry(k.toString(), v.toString())));
        customTextOverrides.remove('hdr_school_name');
        customTextOverrides.remove('cover_school_name');
        customTextOverrides.remove('ftr_school_left');
        customTextOverrides.remove('hdr_address');
        customTextOverrides.remove('cover_address');
      }
      if (saved['customTextOffsets'] is Map) {
        customTextOffsets.clear();
        _planningMap(saved['customTextOffsets']).forEach((k, v) {
          if (v is Map) {
            final dx = (v['dx'] is num) ? (v['dx'] as num).toDouble() : 0.0;
            final dy = (v['dy'] is num) ? (v['dy'] as num).toDouble() : 0.0;
            customTextOffsets[k.toString()] = Offset(dx, dy);
          }
        });
      }
      if (saved['coverLogoOffset'] is Map) {
        final m = _planningMap(saved['coverLogoOffset']);
        coverLogoOffset = Offset(
          (m['dx'] is num) ? (m['dx'] as num).toDouble() : 0.0,
          (m['dy'] is num) ? (m['dy'] as num).toDouble() : 0.0,
        );
      }
      if (saved['headerLogoOffset'] is Map) {
        final m = _planningMap(saved['headerLogoOffset']);
        headerLogoOffset = Offset(
          (m['dx'] is num) ? (m['dx'] as num).toDouble() : 0.0,
          (m['dy'] is num) ? (m['dy'] as num).toDouble() : 0.0,
        );
      }
      if (saved['coverLogoSize'] is num) {
        coverLogoSize =
            (saved['coverLogoSize'] as num).toDouble().clamp(60.0, 260.0);
      }
      if (saved['headerLogoSize'] is num) {
        headerLogoSize =
            (saved['headerLogoSize'] as num).toDouble().clamp(24.0, 140.0);
      }
      final savedLogoUri = (saved['customSchoolLogoDataUri'] ?? '').toString().trim();
      if (savedLogoUri.startsWith('data:')) {
        final comma = savedLogoUri.indexOf(',');
        if (comma >= 0) {
          try {
            _schoolLogoBytes = base64Decode(savedLogoUri.substring(comma + 1));
            _schoolLogoDataUri = savedLogoUri;
          } catch (_) {}
        }
      }
      const demoTeacherNames = <String>{
        'પટેલ રમેશભાઈ કે.',
        'શાહ મીનાબેન આર.',
        'જોષી કિરણબેન એમ.',
        'પંચાલ નિલેશભાઈ વી.',
        'ત્રિવેદી કવિતાબેન એન.',
        'રાવલ અશોકભાઈ ડી.',
      };
      final hasDbTeachers = _planningList(widget.databaseData['teachers']).isNotEmpty;
      final savedTeachers = _planningList(saved['teachers']);
      if (savedTeachers.isNotEmpty) {
        final dbByName = <String, TeacherRecord>{
          for (final t in teachers) t.name: t,
        };
        final restored = savedTeachers
            .map((row) => TeacherRecord.fromJson(row))
            .where((t) =>
                t.name.trim().isNotEmpty &&
                (!hasDbTeachers || !demoTeacherNames.contains(t.name.trim())))
            .map((t) {
              final dbMatch = dbByName[t.name];
              if (dbMatch != null) {
                final hasExplicit =
                    widget.databaseData['hasExplicitAssignments'] == true &&
                        dbMatch.subjects.isNotEmpty;
                final mergedSubs = hasExplicit
                    ? List<String>.from(dbMatch.subjects)
                    : <String>{...dbMatch.subjects, ...t.subjects}.toList();
                return TeacherRecord(
                  id: dbMatch.id.isNotEmpty ? dbMatch.id : t.id,
                  name: t.name,
                  group: dbMatch.assignedClasses.isNotEmpty
                      ? dbMatch.group
                      : t.group,
                  subjects: mergedSubs,
                  assignedClasses: dbMatch.assignedClasses.isNotEmpty
                      ? dbMatch.assignedClasses
                      : t.assignedClasses,
                  allowedClasses: dbMatch.allowedClasses.isNotEmpty
                      ? dbMatch.allowedClasses
                      : t.allowedClasses,
                );
              }
              return t;
            })
            .toList();
        if (restored.isNotEmpty) {
          _earlyTeacherClassCache.clear();
          final existingNames = restored.map((t) => t.name).toSet();
          for (final dbT in teachers) {
            if (!existingNames.contains(dbT.name)) {
              restored.add(dbT);
            }
          }
          teachers = restored;
        }
      }
      final savedTimetable = _planningList(saved['timetableRows']);
      if (savedTimetable.isNotEmpty) {
        final restoredTt = savedTimetable
            .map((row) => TimetableRow(
                  date: _planningText(row['date']),
                  day: _planningText(row['day']),
                  stdLabel: _planningText(row['stdLabel']),
                  subject: _planningText(row['subject']),
                  time: _planningText(row['time']),
                  marks: _planningText(row['marks'], '40'),
                ))
            .where((r) => r.subject.isNotEmpty || r.stdLabel.isNotEmpty)
            .toList();
        if (restoredTt.isNotEmpty) {
          timetableRows = restoredTt;
        }
      }
      final savedRegister = _planningList(saved['registerRows']);
      if (savedRegister.isNotEmpty) {
        final savedByClass = <String, Map<String, dynamic>>{};
        for (final row in savedRegister) {
          final normName = _normalizeExamClassName(_planningText(row['className']));
          if (normName.isNotEmpty) {
            savedByClass[normName] = row;
          }
        }
        final updatedReg = <RegisterRow>[];
        final seenClasses = <String>{};
        for (final row in registerRows) {
          seenClasses.add(row.className);
          final old = savedByClass[row.className];
          if (old == null) {
            updatedReg.add(row);
          } else {
            var savedBoys = old.containsKey('boys') ? _planningInt(old['boys'], row.boys) : row.boys;
            var savedGirls = old.containsKey('girls') ? _planningInt(old['girls'], row.girls) : row.girls;
            if (genderMode == 'boys') {
              savedGirls = 0;
            } else if (genderMode == 'girls') {
              savedBoys = 0;
            }
            updatedReg.add(RegisterRow(
              className: row.className,
              group: _planningText(old['group'], row.group),
              boys: savedBoys > 0 || row.boys == 0 ? savedBoys : row.boys,
              girls: savedGirls > 0 || row.girls == 0 ? savedGirls : row.girls,
              databaseTotal: (old.containsKey('boys') || old.containsKey('girls'))
                  ? null
                  : row.databaseTotal,
              teacherSign: _planningText(old['teacherSign']),
              remarks: _planningText(old['remarks']),
            ));
          }
        }
        if (updatedReg.isNotEmpty) registerRows = updatedReg;
      }
      void restoreCommittee(String key, List<CommitteeRow> current) {
        final raw = _planningList(saved[key]);
        if (raw.isEmpty) return;
        for (var i = 0; i < current.length && i < raw.length; i++) {
          final old = raw[i];
          final tName = _planningText(old['teacherName']);
          if (tName.isNotEmpty) {
            current[i].teacherName = tName;
          }
          current[i].roleOrDuty =
              _planningText(old['roleOrDuty'], current[i].roleOrDuty);
          current[i].sign = _planningText(old['sign'], current[i].sign);
        }
      }

      restoreCommittee('committeeRows', committeeRows);
      restoreCommittee('workDutyRows', workDutyRows);

      if (saved['examClassRangeMode'] is String) {
        examClassRangeMode = saved['examClassRangeMode'].toString();
      }
      if (saved['includeBalvatikaAndStd12Teachers'] is bool) {
        includeBalvatikaAndStd12Teachers =
            saved['includeBalvatikaAndStd12Teachers'] as bool;
      }
      if (saved['include5PercentReserveInStationery'] is bool) {
        include5PercentReserveInStationery =
            saved['include5PercentReserveInStationery'] as bool;
      }
      if (saved['classesWithAnswersInQuestionPaper'] is List) {
        classesWithAnswersInQuestionPaper =
            (saved['classesWithAnswersInQuestionPaper'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toSet();
      }
      if (saved['selectedExamClasses'] is List) {
        final sel = (saved['selectedExamClasses'] as List)
            .map((e) => _normalizeExamClassName(e.toString()))
            .where((e) => e.isNotEmpty)
            .toSet();
        final validInserted =
            allInsertedClassRows.map((r) => r.className).toSet();
        final matched = sel.where((c) => validInserted.contains(c)).toSet();
        if (matched.isNotEmpty) {
          selectedExamClasses = matched;
        }
      }
      if (saved['selectedSubjects35'] is List) {
        final s35 = (saved['selectedSubjects35'] as List)
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toSet();
        if (s35.isNotEmpty) selectedSubjects35 = s35;
      }
      if (saved['selectedSubjects68'] is List) {
        final s68 = (saved['selectedSubjects68'] as List)
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toSet();
        if (s68.isNotEmpty) selectedSubjects68 = s68;
      }
      if (saved['bellScheduleRows'] is List) {
        final rawBell = (saved['bellScheduleRows'] as List)
            .whereType<List>()
            .map((r) => r.map((e) => e.toString()).toList())
            .where((r) => r.length >= 5)
            .toList();
        if (rawBell.isNotEmpty) bellScheduleRows = rawBell;
      }
    } catch (_) {
      // Ignore only malformed/stale optional saved settings; directory data remains loaded.
    }
    _syncExamSelectionToPatraks(rebuildTimetable: false);
  }

  void _autoScheduleTimetableDates() {
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
    while (workingDates.length < 25) {
      if (d.weekday != DateTime.sunday) workingDates.add(d);
      d = d.add(const Duration(days: 1));
    }
    String fmtDate(DateTime dt) =>
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

    int idxA = 0;
    int idxB = 0;
    setState(() {
      for (final row in timetableRows) {
        final dt = row.group == 'a'
            ? workingDates[(idxA++) % workingDates.length]
            : workingDates[(idxB++) % workingDates.length];
        row.date = fmtDate(dt);
        row.day = gujDays[dt.weekday] ?? 'સોમવાર';
        if (row.time.trim().isEmpty) {
          row.time = row.group == 'a'
              ? '11:00 થી 1:00'
              : (dt.weekday == DateTime.saturday ? '8:00 થી 11:00' : '2:00 થી 5:00');
        }
      }
    });
    _refreshDerivedPagesFromTimetable();
    _showSnack('📅 બધા પેપરની તારીખ અને વાર (રવિવાર સિવાય) આપોઆપ ગોઠવાઈ ગયા!');
  }

  Future<void> _saveToSchoolDatabase() async {
    final callback = widget.onSaveData;
    if (callback == null) {
      _showSnack('Database save is not configured.', isError: true);
      return;
    }
    try {
      final encoded = exportBackupJsonString();
      final value = jsonDecode(encoded) as Map<String, dynamic>;
      await callback(value);
      _scheduleExamDeviceAutoSave();
      _showSnack('✅ પરીક્ષા આયોજન અને બધા પેજ સેટિંગ ડેટાબેઝમાં સેવ થયા — આગલી વખતે એ જ રીતે ખુલશે.');
    } catch (error) {
      _showSnack('❌ ડેટાબેઝમાં સેવ થઈ શક્યું નથી: $error', isError: true);
    }
  }

  void _initDefaultData() {
    teachers = [
      TeacherRecord(
          name: 'પટેલ રમેશભાઈ કે.',
          group: 'a',
          subjects: ['ગુજરાતી', 'પર્યાવરણ']),
      TeacherRecord(
          name: 'શાહ મીનાબેન આર.', group: 'a', subjects: ['ગણિત', 'અંગ્રેજી']),
      TeacherRecord(
          name: 'જોષી કિરણબેન એમ.',
          group: 'a',
          subjects: ['હિન્દી', 'ગુજરાતી']),
      TeacherRecord(
          name: 'ચૌધરી દિનેશભાઈ પી.',
          group: 'a',
          subjects: ['ગણિત', 'પર્યાવરણ']),
      TeacherRecord(
          name: 'દેસાઈ ભાવનાબેન એસ.',
          group: 'a',
          subjects: ['અંગ્રેજી', 'હિન્દી']),
      TeacherRecord(
          name: 'સોલંકી મહેશભાઈ જી.',
          group: 'a',
          subjects: ['પર્યાવરણ', 'ગુજરાતી']),
      TeacherRecord(
          name: 'પંચાલ નિલેશભાઈ વી.',
          group: 'b',
          subjects: ['ગણિત', 'વિજ્ઞાન']),
      TeacherRecord(
          name: 'ત્રિવેદી કવિતાબેન એન.',
          group: 'b',
          subjects: ['ગુજરાતી', 'સંસ્કૃત']),
      TeacherRecord(
          name: 'રાવલ અશોકભાઈ ડી.',
          group: 'b',
          subjects: ['સા. વિજ્ઞાન', 'હિન્દી']),
      TeacherRecord(
          name: 'મહેતા પૂજાબેન બી.',
          group: 'b',
          subjects: ['અંગ્રેજી', 'ગુજરાતી']),
      TeacherRecord(
          name: 'પરમાર સંજયભાઈ એલ.', group: 'b', subjects: ['વિજ્ઞાન', 'ગણિત']),
      TeacherRecord(
          name: 'ઠાકોર રેખાબેન સી.',
          group: 'b',
          subjects: ['સંસ્કૃત', 'સા. વિજ્ઞાન']),
    ];

    final roles = [
      'અધ્યક્ષ (આચાર્યશ્રી)',
      'પરીક્ષા મંત્રી',
      'સહ પરીક્ષા મંત્રી',
      'સભ્ય (ધો. ૩ થી ૫ સંયોજક)',
      'સભ્ય (ધો. ૬ થી ૮ સંયોજક)',
      'સભ્ય (મૂલ્યાંકન અને ચકાસણી)',
      'સભ્ય (સ્ટેશનરી અને સાહિત્ય)',
      'સભ્ય (બેઠક અને શિસ્ત વ્યવસ્થા)',
    ];
    committeeRows = List.generate(
      8,
      (i) => CommitteeRow(
        teacherName: teachers[i % teachers.length].name,
        roleOrDuty: roles[i],
      ),
    );

    final duties = [
      'સમયપત્રક અને બેઠક વ્યવસ્થા આયોજન',
      'પ્રશ્નપત્ર પેકેટ સીલ ચકાસણી અને વિતરણ',
      'ઉત્તરવહી અને સ્ટેશનરી વિતરણ હિસાબ',
      'દૈનિક હાજર-ગેરહાજર રિપોર્ટ સંકલન',
      'ખંડ નિરીક્ષક ફાળવણી અને સંચાલન',
      'ઉત્તરવહી બંડલ સ્ટીકર અને સીલિંગ કામગીરી',
      'પેપર ચકાસણી વિતરણ અને પરત જમા નોંધ',
      'બેલ વ્યવસ્થા, પીવાનું પાણી અને સ્વચ્છતા',
    ];
    workDutyRows = List.generate(
      8,
      (i) => CommitteeRow(
        teacherName: teachers[(i + 2) % teachers.length].name,
        roleOrDuty: duties[i],
      ),
    );

    _dbTeacherRawSubjects.clear();
    for (final t in teachers) {
      _dbTeacherRawSubjects[t.name] = List<String>.from(t.subjects);
    }
    allInsertedClassRows = [
      for (final c in ['3A', '3B', '4A', '4B', '5A', '5B'])
        RegisterRow(className: c, group: 'a', boys: 15, girls: 15),
      for (final c in ['6A', '6B', '7A', '7B', '8A', '8B'])
        RegisterRow(className: c, group: 'b', boys: 15, girls: 15),
    ];
    selectedExamClasses = allInsertedClassRows.map((r) => r.className).toSet();
    registerRows = allInsertedClassRows
        .map((r) => RegisterRow(
              className: r.className,
              group: r.group,
              boys: r.boys,
              girls: r.girls,
            ))
        .toList();

    timetableRows = [
      TimetableRow(
          date: '22/10/2026',
          day: 'ગુરુવાર',
          stdLabel: '૩ થી ૫',
          subject: 'ગુજરાતી',
          time: '11:00 થી 1:00',
          marks: '40'),
      TimetableRow(
          date: '23/10/2026',
          day: 'શુક્રવાર',
          stdLabel: '૩ થી ૫',
          subject: 'ગણિત',
          time: '11:00 થી 1:00',
          marks: '40'),
      TimetableRow(
          date: '26/10/2026',
          day: 'સોમવાર',
          stdLabel: '૫',
          subject: 'હિન્દી',
          time: '11:00 થી 1:00',
          marks: '40'),
      TimetableRow(
          date: '27/10/2026',
          day: 'મંગળવાર',
          stdLabel: '૩ થી ૫',
          subject: 'પર્યાવરણ',
          time: '11:00 થી 1:00',
          marks: '40'),
      TimetableRow(
          date: '28/10/2026',
          day: 'બુધવાર',
          stdLabel: '૩ થી ૫',
          subject: 'અંગ્રેજી',
          time: '11:00 થી 1:00',
          marks: '40'),
      TimetableRow(
          date: '22/10/2026',
          day: 'ગુરુવાર',
          stdLabel: '૬ થી ૮',
          subject: 'ગુજરાતી',
          time: '2:00 થી 5:00',
          marks: '80'),
      TimetableRow(
          date: '23/10/2026',
          day: 'શુક્રવાર',
          stdLabel: '૬ થી ૮',
          subject: 'ગણિત',
          time: '2:00 થી 5:00',
          marks: '80'),
      TimetableRow(
          date: '24/10/2026',
          day: 'શનિવાર',
          stdLabel: '૬ થી ૮',
          subject: 'સંસ્કૃત',
          time: '8:00 થી 11:00',
          marks: '80'),
      TimetableRow(
          date: '26/10/2026',
          day: 'સોમવાર',
          stdLabel: '૬ થી ૮',
          subject: 'હિન્દી',
          time: '2:00 થી 5:00',
          marks: '80'),
      TimetableRow(
          date: '27/10/2026',
          day: 'મંગળવાર',
          stdLabel: '૬ થી ૮',
          subject: 'વિજ્ઞાન',
          time: '2:00 થી 5:00',
          marks: '80'),
      TimetableRow(
          date: '28/10/2026',
          day: 'બુધવાર',
          stdLabel: '૬ થી ૮',
          subject: 'અંગ્રેજી',
          time: '2:00 થી 5:00',
          marks: '80'),
      TimetableRow(
          date: '29/10/2026',
          day: 'ગુરુવાર',
          stdLabel: '૬ થી ૮',
          subject: 'સા. વિજ્ઞાન',
          time: '2:00 થી 5:00',
          marks: '80'),
    ];

    bellScheduleRows = [
      [
        '1',
        'પ્રથમ બેલ (પરીક્ષા ખંડમાં પ્રવેશ)',
        '10:45 AM',
        '01:45 PM',
        'વિદ્યાર્થીઓની બેઠક ચકાસણી'
      ],
      [
        '2',
        'બીજો બેલ (ઉત્તરવહી / પ્રશ્નપત્ર વિતરણ)',
        '10:55 AM',
        '01:55 PM',
        'જરૂરી વિગતો ભરાવવી'
      ],
      [
        '3',
        'ત્રીજો બેલ (લેખન કાર્ય શરૂ)',
        '11:00 AM',
        '02:00 PM',
        'પરીક્ષાનો મુખ્ય સમય શરૂ'
      ],
      [
        '4',
        'મધ્ય બેલ (૧ કલાક / અડધો સમય પૂર્ણ)',
        '12:00 PM',
        '03:30 PM',
        'સમયની જાણકારી'
      ],
      [
        '5',
        'ચેતવણી બેલ (અંતિમ ૧૦ મિનિટ બાકી)',
        '12:50 PM',
        '04:50 PM',
        'પુરવણી બાંધવા સૂચના'
      ],
      [
        '6',
        'અંતિમ બેલ (પરીક્ષા પૂર્ણ — ઉત્તરવહી સંકલન)',
        '01:00 PM',
        '05:00 PM',
        'ક્રમવાર ઉત્તરવહી ગણતરી'
      ],
    ];

    seatingA = [];
    seatingB = [];
    absentSheets = [];
    supervisionA = [];
    supervisionB = [];
    checkingRows = [];
    bundleCards = [];
    qpRegisterRows = [];
    stationeryRows = [];

    autoAllocateSeatingFromRegister(notify: false);
    rebuildAbsentPages(notify: false);
    generateSupervision(notify: false);
    rebuildCheckingRows(notify: false);
    rebuildBundles(notify: false);
    rebuildQpRegister(notify: false);
    rebuildStationerySheet();
  }

  // ============================================================================
  // Smart Auto-Calculation & Sync Methods
  // ============================================================================

  List<String> getClassesForGroup(String g) {
    final list = registerRows
        .where((r) => r.group == g && r.className.trim().isNotEmpty)
        .map((r) => r.className.trim())
        .toList();
    if (list.isNotEmpty) return list;
    return g == 'a'
        ? ['3A', '3B', '4A', '4B', '5A', '5B']
        : ['6A', '6B', '7A', '7B', '8A', '8B'];
  }

  Map<String, int> getClassTotalsMap() {
    final map = <String, int>{};
    for (final r in registerRows) {
      if (r.className.trim().isNotEmpty) {
        map[r.className.trim()] = r.total(genderMode);
      }
    }
    return map;
  }

  /// Section of a class name: A / B / C ... (also અ / બ / ક). Classes without
  /// a section count as A.
  static int _sectionRank(String className) {
    final t = className.trim().toUpperCase();
    const guj = <String, int>{'અ': 0, 'બ': 1, 'ક': 2, 'ડ': 3};
    for (final e in guj.entries) {
      if (t.endsWith(e.key) || RegExp('[-\\s(]${e.key}\\)?\$').hasMatch(t)) return e.value;
    }
    final m = RegExp(r'([A-Z])\)?\s*$').firstMatch(t);
    if (m != null) return m.group(1)!.codeUnitAt(0) - 65;
    return 0;
  }

  /// Block-wise seating: all section-A classes first (3A, 4A, 5A ...), then
  /// section B, then C. Students are split equally across [blocksA] /
  /// [blocksB]; a block contains two sections only where one section's
  /// students run out. Every row stays editable afterwards.
  void autoAllocateSeatingFromRegister(
      {String? targetGroup, bool notify = true}) {
    final groups = targetGroup != null ? [targetGroup] : ['a', 'b'];
    for (final g in groups) {
      final nb = math.max(1, g == 'a' ? blocksA : blocksB);
      final classes = registerRows
          .where((r) => r.group == g && r.total(genderMode) > 0)
          .toList()
        ..sort((x, y) {
          final sx = _sectionRank(x.className), sy = _sectionRank(y.className);
          if (sx != sy) return sx.compareTo(sy);
          final ax = _standardNumOfClassName(x.className) ?? 99;
          final ay = _standardNumOfClassName(y.className) ?? 99;
          if (ax != ay) return ax.compareTo(ay);
          return x.className.compareTo(y.className);
        });
      final total = classes.fold<int>(0, (t, r) => t + r.total(genderMode));
      final base = total ~/ nb;
      var rem = total % nb;
      final flat = <SeatingRow>[];
      var ci = 0;
      var nextRoll = 1;
      for (var b = 0; b < nb; b++) {
        var need = base + (rem > 0 ? 1 : 0);
        if (rem > 0) rem--;
        final before = flat.length;
        while (need > 0 && ci < classes.length) {
          final c = classes[ci];
          final maxRoll = c.total(genderMode);
          final avail = maxRoll - nextRoll + 1;
          if (avail <= 0) {
            ci++;
            nextRoll = 1;
            continue;
          }
          final take = math.min(need, avail);
          flat.add(SeatingRow(
            blockNo: b + 1,
            className: c.className,
            fromRoll: '$nextRoll',
            toRoll: '${nextRoll + take - 1}',
            totalCount: '$take',
          ));
          nextRoll += take;
          need -= take;
          if (nextRoll > maxRoll) {
            ci++;
            nextRoll = 1;
          }
        }
        if (flat.length == before) flat.add(SeatingRow(blockNo: b + 1));
      }
      if (g == 'a') {
        seatingA = flat;
      } else {
        seatingB = flat;
      }
    }
    syncAllottedFromSeating();
    _scheduleExamDeviceAutoSave();
    if (notify) {
      _showSnack(
          '🪑 બેઠક વ્યવસ્થા ગોઠવાઈ: પહેલાં બધા વર્ગના વિભાગ A, પછી B — દરેક બ્લોકમાં સરખા વિદ્યાર્થી. જરૂર હોય તો બેઠક પેજમાં સુધારો કરી શકો.');
    }
  }

  /// Block-count stepper used on the class & subject selection page.
  Widget _blockCountStepper(String g) {
    final isA = g == 'a';
    final count = isA ? blocksA : blocksB;
    final students = registerRows
        .where((r) => r.group == g)
        .fold<int>(0, (t, r) => t + r.total(genderMode));
    void setCount(int v) {
      setState(() {
        if (isA) {
          blocksA = v.clamp(1, 30);
        } else {
          blocksB = v.clamp(1, 30);
        }
      });
      autoAllocateSeatingFromRegister(targetGroup: g, notify: false);
      rebuildAbsentPages();
    }

    final perBlock = count > 0 ? (students / count).ceil() : 0;
    return Container(
      width: 330,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF93C5FD), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isA ? 'ધોરણ ૩ થી ૫ — કેટલા બ્લોક બનાવવા છે?' : 'ધોરણ ૬ થી ૮ — કેટલા બ્લોક બનાવવા છે?',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: kNavy),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: count > 1 ? () => setCount(count - 1) : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 54,
                child: Text('$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
              ),
              IconButton.filledTonal(
                onPressed: count < 30 ? () => setCount(count + 1) : null,
                icon: const Icon(Icons.add),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$students વિદ્યાર્થી • બ્લોક દીઠ ~$perBlock',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF475569)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Computes block-wise allotted student counts from Seating Arrangement (`seatingA` / `seatingB`).
  Set<int>? _specificGradesForGroup(String g, String rawStdFilter) {
    final parsed = TimetableRow.parseGrades(rawStdFilter);
    if (parsed.isEmpty) return null;
    final groupGrades = g == 'a'
        ? parsed.where((x) => x >= 1 && x <= 5).toSet()
        : parsed.where((x) => x >= 6 && x <= 8).toSet();
    return groupGrades.isEmpty ? null : groupGrades;
  }

  bool _classMatchesGradeSet(String className, Set<int>? grades) {
    if (grades == null || grades.isEmpty) return true;
    final std = _standardNumOfClassName(className);
    if (std != null) return grades.contains(std);
    return grades.any((gr) => className.contains('$gr'));
  }

  Map<int, int> getSeatingBlockAllottedMap(String g, String rawStdFilter) {
    final rows = g == 'a' ? seatingA : seatingB;
    final map = <int, int>{};
    final specificGrades = _specificGradesForGroup(g, rawStdFilter);

    for (final r in rows) {
      if (!_classMatchesGradeSet(r.className, specificGrades)) continue;
      final cnt = parseNum(r.totalCount);
      if (cnt != null) {
        map[r.blockNo] = (map[r.blockNo] ?? 0) + cnt;
      }
    }
    return map;
  }

  /// Builds Absent Report pages for all days/subjects from Timetable.
  /// ONLY Allotted Numbers (`ફાળવાયેલ સંખ્યા`) are pre-filled; all other columns remain blank for manual entry after printing!
  void rebuildAbsentPages({bool notify = false}) {
    final oldByKey = {for (final s in absentSheets) s.key: s};
    final newSheets = <AbsentPageSheet>[];

    for (final g in ['a', 'b']) {
      final exams = timetableRows.where((t) => t.matchesGroup(g)).toList();
      final nb = g == 'a' ? blocksA : blocksB;
      final classes = getClassesForGroup(g);

      for (final ex in exams) {
        final key = '$g|${ex.date}|${ex.subject}';
        final allottedMap = getSeatingBlockAllottedMap(g, ex.stdLabel);
        if (oldByKey.containsKey(key)) {
          final existing = oldByKey[key]!;
          for (final br in existing.blockRows) {
            if (allottedMap.containsKey(br.blockNo)) {
              br.allotted = allottedMap[br.blockNo].toString();
            }
          }
          newSheets.add(existing);
        } else {
          final blockRows = List.generate(nb, (i) {
            final bNo = i + 1;
            final allotted = allottedMap[bNo]?.toString() ?? '';
            return AbsentBlockRow(
              blockNo: bNo,
              allotted: allotted,
              present: '', // Blank for manual entry after print
              classAbsent: {
                for (final c in classes) c: ''
              }, // Blank for manual entry after print
              totalAbsent: '', // Blank for manual entry after print
              sign: '',
            );
          });
          final studentList = List.generate(
            5,
            (i) => AbsentStudentEntry(srNo: i + 1),
          );
          newSheets.add(AbsentPageSheet(
            key: key,
            group: g,
            stdLabel: ex.stdLabel,
            date: ex.date,
            day: ex.day,
            subject: ex.subject,
            blockRows: blockRows,
            studentList: studentList,
          ));
        }
      }
    }
    setState(() {
      absentSheets = newSheets;
    });
    if (notify)
      _showSnack(
          '✅ બધા જ ગેરહાજર પેજ (માત્ર ફાળવાયેલ સંખ્યા સાથે) અપડેટ થઈ ગયા!');
  }

  void syncAllottedFromSeating({bool notify = false}) {
    for (final sheet in absentSheets) {
      final allottedMap =
          getSeatingBlockAllottedMap(sheet.group, sheet.stdLabel);
      for (final br in sheet.blockRows) {
        br.allotted = allottedMap[br.blockNo]?.toString() ?? '';
      }
    }
    setState(() {});
    if (notify)
      _showSnack('🪑 બેઠક વ્યવસ્થા પરથી ફાળવાયેલ સંખ્યા અપડેટ થઈ ગઈ!');
  }

  void clearManualAbsentEntries(AbsentPageSheet sheet) {
    final classes = getClassesForGroup(sheet.group);
    final allottedMap = getSeatingBlockAllottedMap(sheet.group, sheet.stdLabel);
    setState(() {
      for (final br in sheet.blockRows) {
        br.allotted = allottedMap[br.blockNo]?.toString() ?? br.allotted;
        br.present = '';
        br.classAbsent = {for (final c in classes) c: ''};
        br.totalAbsent = '';
        br.sign = '';
      }
      for (int i = 0; i < sheet.studentList.length; i++) {
        sheet.studentList[i] = AbsentStudentEntry(srNo: i + 1);
      }
    });
    _showSnack(
        '🧹 માત્ર ફાળવાયેલ સંખ્યા જ રાખવામાં આવી (બાકીના ખાના ખાલી કર્યા).');
  }

  /// Auto-lookup Block Number from Seating Arrangement when Roll No & Class Name are entered
  String lookupSeatingBlock(String clsName, String rollNo, String groupHint) {
    final normCls = clsName.trim().toUpperCase().replaceAll(' ', '');
    final rNum = parseNum(rollNo);
    final rows = groupHint == 'b' ? seatingB : seatingA;
    for (final r in rows) {
      final rowCls = r.className.trim().toUpperCase().replaceAll(' ', '');
      if (rowCls.isEmpty) continue;
      if (normCls.isNotEmpty &&
          (rowCls == normCls ||
              rowCls.contains(normCls) ||
              normCls.contains(rowCls))) {
        final fromR = parseNum(r.fromRoll);
        final toR = parseNum(r.toRoll);
        if (rNum != null && fromR != null && toR != null) {
          if (rNum >= fromR && rNum <= toR) return r.blockNo.toString();
        } else if (rNum == null) {
          return r.blockNo.toString();
        }
      }
    }
    return '';
  }

  void generateSupervision({bool notify = true}) {
    final activeTeachers = _examDutyTeachers
        .where((t) => t.name.trim().isNotEmpty)
        .toList(growable: false);
    if (activeTeachers.isEmpty) {
      setState(() {
        supervisionA = <SupervisionRow>[];
        supervisionB = <SupervisionRow>[];
      });
      if (notify) {
        _showSnack(
          '⚠️ પરીક્ષા ડ્યુટી માટે કોઈ શિક્ષક ઉપલબ્ધ નથી. બાલવાટિકા / ધોરણ ૧–૨ શિક્ષકોનો સમાવેશ ચાલુ કરો અથવા અન્ય શિક્ષક ઉમેરો.',
          isError: true,
        );
      }
      return;
    }
    final counts = <String, int>{for (final t in activeTeachers) t.name: 0};
    final blockUse = <String, int>{};

    for (final g in ['a', 'b']) {
      final nb = g == 'a' ? blocksA : blocksB;
      final exams = timetableRows.where((t) => t.matchesGroup(g)).toList();
      final list = <SupervisionRow>[];

      for (final ex in exams) {
        final usedToday = <String>{};
        for (int b = 1; b <= nb; b++) {
          var eligible = activeTeachers
              .where((t) =>
                  !t.subjects.contains(ex.subject) &&
                  !usedToday.contains(t.name))
              .toList();
          if (eligible.isEmpty) {
            eligible = activeTeachers
                .where((t) => !t.subjects.contains(ex.subject))
                .toList();
          }
          final preferred = superMode == 'same' ? g : (g == 'a' ? 'b' : 'a');
          var pool = eligible.where((t) => t.group == preferred).toList();
          if (pool.isEmpty)
            pool = eligible.where((t) => t.group != preferred).toList();
          if (pool.isEmpty) pool = activeTeachers;

          pool.sort((x, y) {
            final xb = blockUse['${x.name}|$g|$b'] ?? 0;
            final yb = blockUse['${y.name}|$g|$b'] ?? 0;
            if (xb != yb) return xb - yb;
            final xc = counts[x.name] ?? 0;
            final yc = counts[y.name] ?? 0;
            return xc - yc;
          });

          final pick = pool.first;
          usedToday.add(pick.name);
          counts[pick.name] = (counts[pick.name] ?? 0) + 1;
          blockUse['${pick.name}|$g|$b'] =
              (blockUse['${pick.name}|$g|$b'] ?? 0) + 1;

          list.add(SupervisionRow(
            date: ex.date,
            day: ex.day,
            subject: ex.subject,
            blockNo: b,
            invigilatorName: pick.name,
            sign: '',
          ));
        }
      }
      if (g == 'a') {
        supervisionA = list;
      } else {
        supervisionB = list;
      }
    }
    setState(() {});
    if (notify) _showSnack('⚙️ ઓટો સુપરવિઝન રોસ્ટર તૈયાર થઈ ગયું!');
  }

  String _addDaysToDateStr(String dateStr, int daysToAdd) {
    final parts = dateStr.split(RegExp(r'[\/\-.]'));
    if (parts.length != 3) return '';
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return '';
    var dt = DateTime.utc(y, m, d).add(Duration(days: daysToAdd));
    if (dt.weekday == DateTime.sunday) dt = dt.add(const Duration(days: 1));
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  bool _subjectMatches(String a, String b) {
    final s1 = a.trim().toLowerCase();
    final s2 = b.trim().toLowerCase();
    if (s1.isEmpty || s2.isEmpty) return false;
    if (s1 == s2 || s1.contains(s2) || s2.contains(s1)) return true;
    if ((s1.contains('સા. વિ') || s1.contains('સામાજિક')) &&
        (s2.contains('સા. વિ') || s2.contains('સામાજિક'))) {
      return true;
    }
    if ((s1.contains('શા. શિ') || s1.contains('શારીરિક')) &&
        (s2.contains('શા. શિ') || s2.contains('શારીરિક'))) {
      return true;
    }
    return false;
  }

  String _findSubjectTeacherForClassAndSubject(
    String className,
    String group,
    String subject,
    int rotationIndex,
  ) {
    final dutyPool = _examDutyTeachers;
    final dutyNames = dutyPool.map((t) => t.name.trim()).toSet();
    final normClass = _normalizeExamClassName(className).toLowerCase();

    // 1. Check explicit teacher_subject_assignments from databaseData['assignments'] for this exact class & subject
    final dbAssignments = _planningList(widget.databaseData['assignments']);
    final exactDbTeachers = <String>[];
    for (final row in dbAssignments) {
      final id = _planningText(row['id']);
      if (id.startsWith('auto_')) continue;
      final rowCls = _normalizeExamClassName(
        _planningText(row['className'], _planningText(row['classLabel'])),
      ).toLowerCase();
      final rowSub = _planningText(row['subject']);
      final tName = _planningText(row['teacherFullName']);
      if (rowCls == normClass &&
          _subjectMatches(rowSub, subject) &&
          dutyNames.contains(tName) &&
          !exactDbTeachers.contains(tName)) {
        exactDbTeachers.add(tName);
      }
    }
    if (exactDbTeachers.isNotEmpty) {
      return exactDbTeachers[rotationIndex % exactDbTeachers.length];
    }

    // 2. Check teachers in _examDutyTeachers who are assigned to this exact class AND teach this subject
    final classSubjectTeachers = dutyPool.where((t) {
      final teachesClass = t.assignedClasses
          .any((ac) => _normalizeExamClassName(ac).toLowerCase() == normClass);
      final rawSubs = <String>{
        ...t.subjects,
        ...(_dbTeacherRawSubjects[t.name] ?? const <String>[]),
      };
      final teachesSub = rawSubs.any((s) => _subjectMatches(s, subject));
      return teachesClass && teachesSub;
    }).toList();
    if (classSubjectTeachers.isNotEmpty) {
      return classSubjectTeachers[rotationIndex % classSubjectTeachers.length]
          .name;
    }

    // 3. Check teachers in _examDutyTeachers in the same group who teach this subject
    final groupSubjectTeachers = dutyPool.where((t) {
      final rawSubs = <String>{
        ...t.subjects,
        ...(_dbTeacherRawSubjects[t.name] ?? const <String>[]),
      };
      return t.group == group && rawSubs.any((s) => _subjectMatches(s, subject));
    }).toList();
    if (groupSubjectTeachers.isNotEmpty) {
      return groupSubjectTeachers[rotationIndex % groupSubjectTeachers.length]
          .name;
    }

    // 4. Check ANY teacher in _examDutyTeachers who teaches this subject
    final anySubjectTeachers = dutyPool.where((t) {
      final rawSubs = <String>{
        ...t.subjects,
        ...(_dbTeacherRawSubjects[t.name] ?? const <String>[]),
      };
      return rawSubs.any((s) => _subjectMatches(s, subject));
    }).toList();
    if (anySubjectTeachers.isNotEmpty) {
      return anySubjectTeachers[rotationIndex % anySubjectTeachers.length].name;
    }

    // Strictly do NOT assign a non-subject teacher
    return '';
  }

  void rebuildCheckingRows({bool notify = false}) {
    final clsMap = getClassTotalsMap();
    final newRows = <CheckingRow>[];
    int counter = 0;

    for (final g in ['a', 'b']) {
      final classes = getClassesForGroup(g);
      final exams = timetableRows.where((t) => t.matchesGroup(g)).toList();
      for (final ex in exams) {
        final specificGrades = _specificGradesForGroup(g, ex.stdLabel);

        for (final c in classes) {
          if (!_classMatchesGradeSet(c, specificGrades)) continue;
          final examiner = _findSubjectTeacherForClassAndSubject(
            c,
            g,
            ex.subject,
            counter++,
          );

          newRows.add(CheckingRow(
            date: ex.date,
            subject: ex.subject,
            className: c,
            paperCount: (clsMap[c] ?? 30).toString(),
            examinerName: examiner,
            examinerSignDate: '',
            returnDate: '', // Always blank as requested!
            principalSign: '',
            group: g,
          ));
        }
      }
    }
    setState(() {
      checkingRows = newRows;
    });
    if (notify) _showSnack('✅ પેપર ચકાસણી પત્રકો (વિષય શિક્ષક મુજબ) અપડેટ થઈ ગયા!');
  }

  List<TimetableRow> getSubjectsForClass(String clsName, String groupHint) {
    final stdNum = _standardNumOfClassName(clsName);
    return timetableRows.where((ex) {
      if (!ex.matchesGroup(groupHint)) return false;
      final grades = ex.parsedGrades;
      if (grades.isNotEmpty && stdNum != null) {
        return grades.contains(stdNum);
      }
      return true;
    }).toList();
  }

  void rebuildBundles({bool notify = false}) {
    final cards = <BundleCardData>[];
    for (final r in registerRows) {
      final cls = r.className.trim();
      if (cls.isEmpty) continue;
      final regCnt = r.total(genderMode).toString();
      final subs = getSubjectsForClass(cls, r.group);
      cards.add(BundleCardData(
        className: cls,
        group: r.group,
        rows: List.generate(
          subs.length,
          (i) => BundleSubjectRow(
            srNo: i + 1,
            date: subs[i].date,
            subject: subs[i].subject,
            regCount: regCnt,
          ),
        ),
      ));
    }
    setState(() {
      bundleCards = cards;
    });
    if (notify)
      _showSnack('📦 રજીસ્ટરના બધા વર્ગોના બંડલ સ્ટીકર તૈયાર થઈ ગયા!');
  }

  int getStudentCountForExam(String g, String rawStdFilter) {
    final specificGrades = _specificGradesForGroup(g, rawStdFilter);
    int sum = 0;
    for (final r in registerRows) {
      if (r.group != g) continue;
      if (!_classMatchesGradeSet(r.className, specificGrades)) continue;
      sum += r.total(genderMode);
    }
    return sum;
  }

  void rebuildQpRegister({bool notify = false}) {
    final rows = <List<String>>[];
    for (int i = 0; i < timetableRows.length; i++) {
      final ex = timetableRows[i];
      int studCnt = 0;
      int blkCnt = 0;
      if (ex.matchesGroup('a')) {
        studCnt += getStudentCountForExam('a', ex.stdLabel);
        blkCnt += blocksA;
      }
      if (ex.matchesGroup('b')) {
        studCnt += getStudentCountForExam('b', ex.stdLabel);
        blkCnt += blocksB;
      }
      final openTime = ex.time.contains('11:00')
          ? '10:45 AM'
          : (ex.time.contains('2:00') ? '01:45 PM' : '07:45 AM');
      final dutyPool = _examDutyTeachers;
      final witness =
          dutyPool.isNotEmpty ? dutyPool[i % dutyPool.length].name : '';
      rows.add([
        (i + 1).toString(),
        ex.date,
        ex.day,
        'ધો. ${ex.stdLabel}',
        ex.subject,
        ex.time,
        studCnt.toString(),
        blkCnt.toString(),
        openTime,
        witness,
        '',
      ]);
    }
    setState(() {
      qpRegisterRows = rows;
    });
    if (notify)
      _showSnack('🔐 પ્રશ્નપત્ર પેકેટ સીલ અને વિતરણ રજીસ્ટર તૈયાર થઈ ગયું!');
  }

  bool _classHasAnswersInQuestionPaper(String className) {
    final clean = className.trim();
    if (classesWithAnswersInQuestionPaper.contains(clean)) return true;
    final std = _standardNumOfClassName(clean);
    if (std != null && classesWithAnswersInQuestionPaper.contains('std_$std')) {
      return true;
    }
    return false;
  }

  void _recalculateStationeryTotalsInPlace() {
    final dataRows = stationeryRows
        .where((r) => r.isNotEmpty && !r.first.contains('કુલ'))
        .toList();
    int sumRegA = 0, sumMainA = 0, sumResA = 0, sumTotA = 0, sumSupA = 0, sumBunA = 0;
    int sumRegB = 0, sumMainB = 0, sumResB = 0, sumTotB = 0, sumSupB = 0, sumBunB = 0;
    final rowsA = <List<String>>[];
    final rowsB = <List<String>>[];

    for (final row in dataRows) {
      while (row.length < 9) {
        row.add('');
      }
      final cls = row[0].trim();
      final std = _standardNumOfClassName(cls);
      final isB = (std != null && std >= 6) ||
          registerRows.any((rr) => rr.className.trim() == cls && rr.group == 'b');
      final reg = parseNum(row[1]) ?? 0;
      final subCnt = parseNum(row[2]) ?? 0;
      final inQp = _classHasAnswersInQuestionPaper(cls);
      final mainAns = inQp ? 0 : (parseNum(row[3]) ?? (reg * subCnt));
      final reserve = inQp
          ? 0
          : (include5PercentReserveInStationery
              ? (mainAns * 0.05).ceil()
              : 0);
      final totalAns = mainAns + reserve;
      final supp = inQp ? 0 : (mainAns * 0.25).ceil();
      row[3] = '$mainAns';
      row[4] = '$reserve';
      row[5] = '$totalAns';
      row[6] = '$supp';
      if (row[7].trim().isEmpty) row[7] = '$subCnt નંગ';
      if (inQp && row[8].trim().isEmpty) {
        row[8] = 'પ્રશ્નપત્રમાં જ જવાબ';
      } else if (!inQp && row[8].trim() == 'પ્રશ્નપત્રમાં જ જવાબ') {
        row[8] = '';
      }
      if (!isB) {
        sumRegA += reg;
        sumMainA += mainAns;
        sumResA += reserve;
        sumTotA += totalAns;
        sumSupA += supp;
        sumBunA += subCnt;
        rowsA.add(row);
      } else {
        sumRegB += reg;
        sumMainB += mainAns;
        sumResB += reserve;
        sumTotB += totalAns;
        sumSupB += supp;
        sumBunB += subCnt;
        rowsB.add(row);
      }
    }

    final rebuilt = <List<String>>[];
    if (rowsA.isNotEmpty) {
      rebuilt.addAll(rowsA);
      rebuilt.add([
        'ધોરણ ૩ થી ૫ કુલ',
        '$sumRegA',
        '-',
        '$sumMainA',
        '$sumResA',
        '$sumTotA',
        '$sumSupA',
        '$sumBunA નંગ',
        '',
      ]);
    }
    if (rowsB.isNotEmpty) {
      rebuilt.addAll(rowsB);
      rebuilt.add([
        'ધોરણ ૬ થી ૮ કુલ',
        '$sumRegB',
        '-',
        '$sumMainB',
        '$sumResB',
        '$sumTotB',
        '$sumSupB',
        '$sumBunB નંગ',
        '',
      ]);
    }
    rebuilt.add([
      'શાળા એકંદર કુલ',
      '${sumRegA + sumRegB}',
      '-',
      '${sumMainA + sumMainB}',
      '${sumResA + sumResB}',
      '${sumTotA + sumTotB}',
      '${sumSupA + sumSupB}',
      '${sumBunA + sumBunB} નંગ',
      '',
    ]);
    stationeryRows = rebuilt;
  }

  void rebuildStationerySheet([bool notify = false]) {
    final rows = <List<String>>[];
    int sumRegA = 0, sumMainA = 0, sumResA = 0, sumTotA = 0, sumSupA = 0, sumBunA = 0;
    int sumRegB = 0, sumMainB = 0, sumResB = 0, sumTotB = 0, sumSupB = 0, sumBunB = 0;

    for (final g in ['a', 'b']) {
      final gRows = registerRows
          .where((r) => r.group == g && r.className.trim().isNotEmpty)
          .toList();
      if (gRows.isEmpty) continue;
      for (final r in gRows) {
        final cls = r.className.trim();
        final subs = getSubjectsForClass(cls, r.group);
        final subCnt = subs.isNotEmpty ? subs.length : (r.group == 'a' ? 5 : 7);
        final reg = r.total(genderMode);
        final inQp = _classHasAnswersInQuestionPaper(cls);
        final mainAns = inQp ? 0 : (reg * subCnt);
        final reserve = inQp
            ? 0
            : (include5PercentReserveInStationery
                ? (mainAns * 0.05).ceil()
                : 0);
        final totalAns = mainAns + reserve;
        final supp = inQp ? 0 : (mainAns * 0.25).ceil();
        if (g == 'a') {
          sumRegA += reg;
          sumMainA += mainAns;
          sumResA += reserve;
          sumTotA += totalAns;
          sumSupA += supp;
          sumBunA += subCnt;
        } else {
          sumRegB += reg;
          sumMainB += mainAns;
          sumResB += reserve;
          sumTotB += totalAns;
          sumSupB += supp;
          sumBunB += subCnt;
        }
        rows.add([
          cls,
          reg.toString(),
          subCnt.toString(),
          mainAns.toString(),
          reserve.toString(),
          totalAns.toString(),
          supp.toString(),
          '$subCnt નંગ',
          inQp ? 'પ્રશ્નપત્રમાં જ જવાબ' : '',
        ]);
      }
      final isA = g == 'a';
      rows.add([
        isA ? 'ધોરણ ૩ થી ૫ કુલ' : 'ધોરણ ૬ થી ૮ કુલ',
        '${isA ? sumRegA : sumRegB}',
        '-',
        '${isA ? sumMainA : sumMainB}',
        '${isA ? sumResA : sumResB}',
        '${isA ? sumTotA : sumTotB}',
        '${isA ? sumSupA : sumSupB}',
        '${isA ? sumBunA : sumBunB} નંગ',
        '',
      ]);
    }
    rows.add([
      'શાળા એકંદર કુલ',
      '${sumRegA + sumRegB}',
      '-',
      '${sumMainA + sumMainB}',
      '${sumResA + sumResB}',
      '${sumTotA + sumTotB}',
      '${sumSupA + sumSupB}',
      '${sumBunA + sumBunB} નંગ',
      '',
    ]);
    setState(() {
      stationeryRows = rows;
    });
    if (notify) {
      _showSnack('🧮 ઉત્તરવહી અને સ્ટેશનરી જરૂરિયાત પત્રક તૈયાર થઈ ગયું!');
    }
  }

  void runMasterAutoFill() {
    autoAllocateSeatingFromRegister(notify: false);
    rebuildAbsentPages(notify: false);
    for (final s in absentSheets) {
      clearManualAbsentEntries(s);
    }
    generateSupervision(notify: false);
    rebuildCheckingRows(notify: false);
    rebuildBundles(notify: false);
    rebuildQpRegister(notify: false);
    rebuildStationerySheet();
    _showSnack(
        '⚡ ૧-ક્લિક સ્માર્ટ ઓટો-ફિલ પૂર્ણ! બધા જ પત્રકો આપોઆપ ભરાઈ ગયા છે.');
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : kNavy,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ============================================================================
  // Navigation Items Builder (All 38 Dynamic & Static Pages)
  // ============================================================================

  static List<String> _matchingKeysForPrefix(String keyOrCategory) {
    switch (keyOrCategory) {
      case 'super_a':
      case 'sup_a':
        return const <String>['super_a', 'sup_a'];
      case 'super_b':
      case 'sup_b':
        return const <String>['super_b', 'sup_b'];
      case 'check_a':
      case 'chk_a':
        return const <String>['check_a', 'chk_a'];
      case 'check_b':
      case 'chk_b':
        return const <String>['check_b', 'chk_b'];
      case 'bundle':
      case 'bun':
        return const <String>['bundle', 'bun'];
      case 'door':
        return const <String>['door'];
      default:
        return <String>[keyOrCategory];
    }
  }

  double _rowHeightForPrefix(String? pageIdPrefix, {String? fallbackPageId}) {
    if (fallbackPageId != null && pageRowHeights.containsKey(fallbackPageId)) {
      return pageRowHeights[fallbackPageId]!.clamp(2.0, 35.0).toDouble();
    }
    if (pageIdPrefix != null) {
      if (pageRowHeights.containsKey(pageIdPrefix)) {
        return pageRowHeights[pageIdPrefix]!.clamp(2.0, 35.0).toDouble();
      }
      final prefixes = _matchingKeysForPrefix(pageIdPrefix);
      for (final p in prefixes) {
        if (pageRowHeights.containsKey(p)) {
          return pageRowHeights[p]!.clamp(2.0, 35.0).toDouble();
        }
      }
      for (final entry in pageRowHeights.entries) {
        for (final p in prefixes) {
          if (entry.key == p || entry.key.startsWith('${p}_')) {
            return entry.value.clamp(2.0, 35.0).toDouble();
          }
        }
      }
    }
    return 6.0;
  }

  int _fontPctForPrefix(String? pageIdPrefix, {String? fallbackPageId}) {
    if (fallbackPageId != null && pageFontScales.containsKey(fallbackPageId)) {
      return pageFontScales[fallbackPageId]!.clamp(75, 150);
    }
    if (pageIdPrefix != null) {
      if (pageFontScales.containsKey(pageIdPrefix)) {
        return pageFontScales[pageIdPrefix]!.clamp(75, 150);
      }
      final prefixes = _matchingKeysForPrefix(pageIdPrefix);
      for (final p in prefixes) {
        if (pageFontScales.containsKey(p)) {
          return pageFontScales[p]!.clamp(75, 150);
        }
      }
      for (final entry in pageFontScales.entries) {
        for (final p in prefixes) {
          if (entry.key == p || entry.key.startsWith('${p}_')) {
            return entry.value.clamp(75, 150);
          }
        }
      }
    }
    return 100;
  }

  int _effectiveRowsPerPage(int baseCapacity, {String? pageIdPrefix}) {
    final double rh = pageIdPrefix != null
        ? _rowHeightForPrefix(pageIdPrefix)
        : activeRowHeight;
    final int fsPct = pageIdPrefix != null
        ? _fontPctForPrefix(pageIdPrefix)
        : activeFontPct;
    final double fsScale = fsPct.clamp(75, 150) / 100.0;
    // Full printable body height on A4 Portrait (~790px on the 1040px preview sheet, ~645pt in PDF)
    // Ensures Page 1 is completely filled from top to bottom before creating Page 2.
    const double availBodyPx = 795.0;
    final bool isMultiLineSection =
        pageIdPrefix == 'instructions' || pageIdPrefix == 'teachers';
    final double baseTextPx = isMultiLineSection ? 21.0 : 15.0;
    final double rowPx = (2.0 * rh) + (baseTextPx * fsScale) + 1.2;
    final int maxFit = ((availBodyPx - rowPx) / rowPx).floor();
    final int upperCap = math.max(baseCapacity, 28);
    return maxFit.clamp(4, upperCap);
  }

  int _totalRegisterDisplayRowCount() {
    final hasA = registerRows.any((r) => r.group == 'a');
    final hasB = registerRows.any((r) => r.group == 'b');
    return registerRows.length + (hasA ? 1 : 0) + (hasB ? 1 : 0) + 1;
  }

  int _totalSeatingDisplayRowCount(String g) {
    final list = g == 'a' ? seatingA : seatingB;
    final nb = g == 'a' ? blocksA : blocksB;
    return list.length + nb + 1;
  }

  int _effectiveBundlesPerPage() {
    final rh = _rowHeightForPrefix('bundle');
    if (rh >= 16) return 1;
    if (rh >= 10) return math.min(2, bundlesPerPage);
    return bundlesPerPage;
  }

  int _effectiveDoorsPerPage() {
    final rh = _rowHeightForPrefix('door');
    if (rh >= 16) return 1;
    if (rh >= 10) return math.min(2, doorsPerPage);
    return doorsPerPage;
  }

  List<NavPageItem> get allNavPages {
    final items = <NavPageItem>[
      const NavPageItem(
        id: 'exam_setup',
        title: 'વર્ગ અને વિષય પસંદગી',
        icon: '🎯',
        category: 'exam_setup',
      ),
      const NavPageItem(
          id: 'cover', title: 'કવર', icon: '📘', category: 'cover'),
      const NavPageItem(
          id: 'index', title: 'અનુક્રમણિકા', icon: '📑', category: 'index'),
      const NavPageItem(
          id: 'dashboard', title: 'એક નજરે', icon: '📊', category: 'dashboard'),
    ];

    // Paginated Teachers Pages
    final teachCap = _effectiveRowsPerPage(26, pageIdPrefix: 'teachers');
    final teachChunks =
        (_examDutyTeachers.length / teachCap).ceil().clamp(1, 99);
    for (int p = 0; p < teachChunks; p++) {
      items.add(NavPageItem(
        id: p == 0 ? 'teachers' : 'teachers_$p',
        title: 'શિક્ષક માહિતી${teachChunks > 1 ? ' (પેજ ${p + 1})' : ''}',
        icon: '👨‍🏫',
        category: 'teachers',
        subIndex: p,
      ));
    }

    items.add(const NavPageItem(
        id: 'committee', title: 'સમિતિ', icon: '👥', category: 'committee'));

    // Paginated Register Pages (includes group total & grand total rows)
    final regCap = _effectiveRowsPerPage(27, pageIdPrefix: 'register');
    final regChunks =
        (_totalRegisterDisplayRowCount() / regCap).ceil().clamp(1, 99);
    for (int p = 0; p < regChunks; p++) {
      items.add(NavPageItem(
        id: p == 0 ? 'register' : 'register_$p',
        title: 'રજીસ્ટર${regChunks > 1 ? ' (પેજ ${p + 1})' : ''}',
        icon: '📒',
        category: 'register',
        subIndex: p,
      ));
    }

    // Paginated Timetable Pages
    final ttCap = _effectiveRowsPerPage(27, pageIdPrefix: 'timetable');
    final ttChunks = (timetableRows.length / ttCap).ceil().clamp(1, 99);
    for (int p = 0; p < ttChunks; p++) {
      items.add(NavPageItem(
        id: p == 0 ? 'timetable' : 'timetable_$p',
        title: 'સમયપત્રક${ttChunks > 1 ? ' (પેજ ${p + 1})' : ''}',
        icon: '🗓️',
        category: 'timetable',
        subIndex: p,
      ));
    }

    // Paginated Seating Arrangement Pages (3-5 and 6-8)
    if (hasGroupA) {
      final seatACap = _effectiveRowsPerPage(27, pageIdPrefix: 'seat_a');
      final seatAChunks =
          (_totalSeatingDisplayRowCount('a') / seatACap).ceil().clamp(1, 99);
      for (int p = 0; p < seatAChunks; p++) {
        items.add(NavPageItem(
          id: p == 0 ? 'seat_a' : 'seat_a_$p',
          title: 'બેઠક ૩–૫${seatAChunks > 1 ? ' (પેજ ${p + 1})' : ''}',
          icon: '🪑',
          category: 'seat_a',
          subIndex: p,
        ));
      }
    }
    if (hasGroupB) {
      final seatBCap = _effectiveRowsPerPage(27, pageIdPrefix: 'seat_b');
      final seatBChunks =
          (_totalSeatingDisplayRowCount('b') / seatBCap).ceil().clamp(1, 99);
      for (int p = 0; p < seatBChunks; p++) {
        items.add(NavPageItem(
          id: p == 0 ? 'seat_b' : 'seat_b_$p',
          title: 'બેઠક ૬–૮${seatBChunks > 1 ? ' (પેજ ${p + 1})' : ''}',
          icon: '🪑',
          category: 'seat_b',
          subIndex: p,
        ));
      }
    }

    // All Day-wise & Subject-wise Absent Pages (Landscape)
    for (int i = 0; i < absentSheets.length; i++) {
      final s = absentSheets[i];
      if (s.group == 'a' && !hasGroupA) continue;
      if (s.group == 'b' && !hasGroupB) continue;
      final gLbl = s.group == 'a' ? '૩–૫' : '૬–૮';
      final shortDate = s.date.length >= 5 ? s.date.substring(0, 5) : s.date;
      items.add(NavPageItem(
        id: 'abs_$i',
        title: 'ગેરહાજર $gLbl · ${s.subject} ($shortDate)',
        icon: '🚫',
        isLandscape: true,
        category: 'absent',
        subIndex: i,
      ));
    }

    // Paginated Supervision Pages
    if (hasGroupA) {
      final effSupA =
          _effectiveRowsPerPage(superRowsPerPageA, pageIdPrefix: 'super_a');
      final supChunksA = (supervisionA.length / effSupA).ceil().clamp(1, 99);
      for (int p = 0; p < supChunksA; p++) {
        items.add(NavPageItem(
          id: 'sup_a_$p',
          title: 'નિરીક્ષણ ૩–૫${supChunksA > 1 ? ' (પેજ ${p + 1})' : ''}',
          icon: '🔍',
          category: 'super_a',
          subIndex: p,
        ));
      }
    }
    if (hasGroupB) {
      final effSupB =
          _effectiveRowsPerPage(superRowsPerPageB, pageIdPrefix: 'super_b');
      final supChunksB = (supervisionB.length / effSupB).ceil().clamp(1, 99);
      for (int p = 0; p < supChunksB; p++) {
        items.add(NavPageItem(
          id: 'sup_b_$p',
          title: 'નિરીક્ષણ ૬–૮${supChunksB > 1 ? ' (પેજ ${p + 1})' : ''}',
          icon: '🔍',
          category: 'super_b',
          subIndex: p,
        ));
      }
    }

    // Paginated Paper Checking Pages
    if (hasGroupA) {
      final chkA = checkingRows.where((r) => r.group == 'a').toList();
      final effChkA =
          _effectiveRowsPerPage(checkRowsPerPage, pageIdPrefix: 'check_a');
      final chkChunksA = (chkA.length / effChkA).ceil().clamp(1, 99);
      for (int p = 0; p < chkChunksA; p++) {
        items.add(NavPageItem(
          id: 'chk_a_$p',
          title: 'ચકાસણી ૩ થી ૫${chkChunksA > 1 ? ' (પેજ ${p + 1})' : ''}',
          icon: '✅',
          category: 'check_a',
          subIndex: p,
        ));
      }
    }
    if (hasGroupB) {
      final chkB = checkingRows.where((r) => r.group == 'b').toList();
      final effChkB =
          _effectiveRowsPerPage(checkRowsPerPage, pageIdPrefix: 'check_b');
      final chkChunksB = (chkB.length / effChkB).ceil().clamp(1, 99);
      for (int p = 0; p < chkChunksB; p++) {
        items.add(NavPageItem(
          id: 'chk_b_$p',
          title: 'ચકાસણી ૬ થી ૮${chkChunksB > 1 ? ' (પેજ ${p + 1})' : ''}',
          icon: '✅',
          category: 'check_b',
          subIndex: p,
        ));
      }
    }

    // Paginated Class Bundle Sticker Pages (auto-reduces per page if row height is large)
    final effBundlesPerPage = _effectiveBundlesPerPage();
    final bunChunks =
        (bundleCards.length / effBundlesPerPage).ceil().clamp(1, 99);
    for (int p = 0; p < bunChunks; p++) {
      final start = p * effBundlesPerPage;
      final end = math.min(bundleCards.length, start + effBundlesPerPage) - 1;
      final range = (start <= end && bundleCards.isNotEmpty)
          ? (start == end
              ? bundleCards[start].className
              : '${bundleCards[start].className}–${bundleCards[end].className}')
          : '${p + 1}';
      items.add(NavPageItem(
        id: 'bun_$p',
        title: 'બંડલ ($range)',
        icon: '📦',
        category: 'bundle',
        subIndex: p,
      ));
    }

    // Paginated Block Door Sticker Pages
    final totalBlocks = (hasGroupA ? blocksA : 0) + (hasGroupB ? blocksB : 0);
    final effDoorsPerPage = _effectiveDoorsPerPage();
    final doorChunks = (totalBlocks / effDoorsPerPage).ceil().clamp(1, 99);
    for (int p = 0; p < doorChunks; p++) {
      final sNo = p * effDoorsPerPage + 1;
      final eNo = math.min(totalBlocks, sNo + effDoorsPerPage - 1);
      items.add(NavPageItem(
        id: 'door_$p',
        title: 'બ્લોક સ્ટીકર ($sNo–$eNo)',
        icon: '🚪',
        category: 'door',
        subIndex: p,
      ));
    }

    // Paginated QP Register Pages
    final qpCap = _effectiveRowsPerPage(27, pageIdPrefix: 'qp_reg');
    final qpChunks = (qpRegisterRows.length / qpCap).ceil().clamp(1, 99);
    for (int p = 0; p < qpChunks; p++) {
      items.add(NavPageItem(
        id: p == 0 ? 'qp_reg' : 'qp_reg_$p',
        title: 'પ્રશ્નપત્ર હિસાબ${qpChunks > 1 ? ' (પેજ ${p + 1})' : ''}',
        icon: '🔐',
        category: 'qp_reg',
        subIndex: p,
      ));
    }

    // Paginated Stationery Pages
    final stCap = _effectiveRowsPerPage(27, pageIdPrefix: 'stationery');
    final stChunks = (stationeryRows.length / stCap).ceil().clamp(1, 99);
    for (int p = 0; p < stChunks; p++) {
      items.add(NavPageItem(
        id: p == 0 ? 'stationery' : 'stationery_$p',
        title: 'સ્ટેશનરી હિસાબ${stChunks > 1 ? ' (પેજ ${p + 1})' : ''}',
        icon: '🧮',
        category: 'stationery',
        subIndex: p,
      ));
    }

    // Paginated Instructions Pages
    final instCap = _effectiveRowsPerPage(20, pageIdPrefix: 'instructions');
    final instChunks =
        (editableInstructions.length / instCap).ceil().clamp(1, 99);
    for (int p = 0; p < instChunks; p++) {
      items.add(NavPageItem(
        id: p == 0 ? 'instructions' : 'instructions_$p',
        title: 'સૂચનાઓ${instChunks > 1 ? ' (પેજ ${p + 1})' : ''}',
        icon: '📋',
        category: 'instructions',
        subIndex: p,
      ));
    }

    return items;
  }

  NavPageItem get currentNavPage {
    final pages = allNavPages;
    return pages.firstWhere(
      (p) => p.id == activePageId,
      orElse: () => pages.first,
    );
  }

  double get activeFontScale => activeFontPct / 100.0;
  int get activeFontPct =>
      _fontPctForPrefix(currentNavPage.category, fallbackPageId: activePageId);

  void setPageFont(int pct) {
    final clamped = pct.clamp(75, 150);
    final cat = currentNavPage.category;
    setState(() {
      pageFontScales[activePageId] = clamped;
      pageFontScales[cat] = clamped;
      for (final p in _matchingKeysForPrefix(cat)) {
        pageFontScales[p] = clamped;
      }
      for (final key in pageFontScales.keys.toList()) {
        for (final p in _matchingKeysForPrefix(cat)) {
          if (key == p || key.startsWith('${p}_')) {
            pageFontScales[key] = clamped;
          }
        }
      }
    });
    _scheduleExamDeviceAutoSave();
    _showSnack('🔤 આ પેજની ફોન્ટ સાઈઝ $clamped% સેટ થઈ');
  }

  void applyFontToAllPages() {
    final pct = activeFontPct;
    setState(() {
      for (final p in allNavPages) {
        pageFontScales[p.id] = pct;
      }
    });
    _showSnack('✅ બધા જ પેજમાં ફોન્ટ સાઈઝ $pct% લાગુ થઈ ગઈ!');
  }

  // ============================================================================
  // UI Building Blocks
  // ============================================================================

  void _centerAlignExamLogosAndTexts() {
    setState(() {
      coverLogoOffset = Offset.zero;
      headerLogoOffset = Offset.zero;
      meta.logoShape = 'original';
    });
    _scheduleExamDeviceAutoSave();
    _showSnack('⚖️ Ctrl+E: લોગો સેન્ટરમાં બરાબર ગોઠવાઈ ગયો!');
  }

  Future<void> _pickCustomExamLogo() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) return;
      final ext = (file.extension ?? 'png').toLowerCase();
      final mime =
          (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/$ext';
      final uri = 'data:$mime;base64,${base64Encode(bytes)}';
      setState(() {
        _schoolLogoBytes = bytes;
        _schoolLogoDataUri = uri;
        meta.logoShape = 'original';
      });
      _scheduleExamDeviceAutoSave();
      _showSnack('✅ પરીક્ષા આયોજન માટે લોગો (મૂળ આકારમાં) અપલોડ થઈ ગયો!');
    } catch (e) {
      _showSnack('લોગો અપલોડ કરવામાં ભૂલ: $e', isError: true);
    }
  }

  static const Set<String> _lockedSchoolIdentityKeys = <String>{
    'hdr_school_name',
    'cover_school_name',
    'ftr_school_left',
    'hdr_address',
    'cover_address',
  };

  Widget _movableEditableText({
    required String textKey,
    required String defaultText,
    required TextStyle style,
    TextAlign textAlign = TextAlign.center,
    ValueChanged<String>? onCustomSave,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    Widget Function(String displayText)? customBuilder,
  }) {
    final isLockedIdentity = _lockedSchoolIdentityKeys.contains(textKey);
    final displayText = isLockedIdentity
        ? defaultText
        : (customTextOverrides[textKey] ?? defaultText);
    final offset = customTextOffsets[textKey] ?? Offset.zero;
    return Transform.translate(
      offset: offset,
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: _PageDragDetector(
 pageKey: _a4PageCaptureKey,
 hideSelection: _capturingForPdf,

          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (isLockedIdentity) {
              final nextLang = schoolNameLang == 'gu' ? 'en' : 'gu';
              _setExamSchoolNameLanguage(nextLang);
              _showSnack(
                '🌐 શાળાનું નામ રજીસ્ટ્રેશન મુજબ લોક છે — ભાષા ${nextLang == "gu" ? "ગુજરાતી" : "English"} કરવામાં આવી!',
              );
              return;
            }
            _editMetaField(
              'લખાણ સુધારો (Edit Text)',
              displayText,
              (val) {
                if (onCustomSave != null) {
                  onCustomSave(val);
                }
                customTextOverrides[textKey] = val;
              },
            );
          },
          onPanUpdate: (details) {
            setState(() {
              final cur = customTextOffsets[textKey] ?? Offset.zero;
              customTextOffsets[textKey] = cur + details.delta;
            });
            _scheduleExamDeviceAutoSave();
          },
          child: customBuilder != null
              ? customBuilder(displayText)
              : Padding(
                  padding: padding,
                  child: Text(
                    displayText,
                    textAlign: textAlign,
                    style: style,
                  ),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = allNavPages;
    final cur = currentNavPage;
    final isWide = MediaQuery.of(context).size.width >= 960;
    // Tools move to a right-side panel when there is room for it.
    final toolsOnRight = MediaQuery.of(context).size.width >= 1280;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyE, control: true):
            _centerAlignExamLogosAndTexts,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          drawer: isWide
              ? null
              : Drawer(width: 295, child: _buildSidebar(pages, cur)),
          appBar: (widget.embedded || isWide)
              ? null
              : AppBar(
                  backgroundColor: kNavy,
                  foregroundColor: Colors.white,
                  title: Text(cur.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  actions: [
                    IconButton(
                      tooltip: '૧-ક્લિક સ્માર્ટ ઓટો-ફિલ',
                      icon: const Icon(Icons.bolt, color: Colors.amber),
                      onPressed: runMasterAutoFill,
                    ),
                  ],
                ),
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isWide)
                SizedBox(width: 285, child: _buildSidebar(pages, cur)),
              Expanded(
                child: Scrollbar(
                  controller: _pageScrollCtrl,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _pageScrollCtrl,
                    primary: false,
                    scrollDirection: Axis.vertical,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!toolsOnRight) ...[
                          _buildTopActionBar(cur),
                          _buildPerPageToolbar(cur),
                        ],
                        Scrollbar(
                          controller: _pageHScrollCtrl,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _pageHScrollCtrl,
                            primary: false,
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.all(12),
                            child: Center(
                              child: RepaintBoundary(
                                key: _a4PageCaptureKey,
                                child: _buildA4FramedPage(cur),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Tools panel on the right (pages list is on the left).
              if (toolsOnRight)
                Container(
                  width: 340,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5FB),
                    border: Border(left: BorderSide(color: Color(0xFFD8E2F0))),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        color: kNavy,
                        child: const Text(
                          '🧰 સાધનો / Tools',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                      ),
                      Expanded(
                        child: Scrollbar(
                          controller: _toolsScrollCtrl,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _toolsScrollCtrl,
                            primary: false,
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildTopActionBar(cur),
                                _buildPerPageToolbar(cur),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(List<NavPageItem> pages, NavPageItem current) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kNavy, kNavyDark],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
              child: Row(
                children: [
                  if (Navigator.of(context).canPop())
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: IconButton(
                        tooltip: 'પાછા જાઓ / Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                      ),
                    ),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFFFB066),
                          Colors.white,
                          Color(0xFF4CC04A)
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'પઆ',
                      style: TextStyle(
                          color: kNavy,
                          fontWeight: FontWeight.w900,
                          fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'પરીક્ષા આયોજન ફાઈલ',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15),
                        ),
                        Text(
                          '${meta.examName} · ${meta.academicYear}',
                          style: const TextStyle(
                              color: Color(0xFFC9D6F0),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white24, height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                itemCount: pages.length,
                itemBuilder: (ctx, idx) {
                  final p = pages[idx];
                  final isSelected = p.id == current.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Material(
                      color: isSelected ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          setState(() => activePageId = p.id);
                          if (Scaffold.maybeOf(ctx)?.isDrawerOpen ?? false) {
                            Navigator.of(ctx).pop();
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          child: Row(
                            children: [
                              Text(p.icon,
                                  style: const TextStyle(fontSize: 16)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  p.title,
                                  style: TextStyle(
                                    color: isSelected ? kNavy : Colors.white,
                                    fontWeight: isSelected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? kNavy
                                      : Colors.white.withOpacity(0.16),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  p.isLandscape ? 'L' : 'P',
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFFFFD599),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              child: const Text(
                '💡 સ્માર્ટ ઓટોમેટિક સુવિધાઓ:\n'
                '• દરેક પેજમાં 🔤 ફોન્ટ સાઈઝ કંટ્રોલ ટેબ\n'
                '• ગેરહાજર પેજમાં માત્ર ફાળવાયેલ સંખ્યા જ ઓટો-ભરાશે (બાકીની વિગત પ્રિન્ટ બાદ ભરી શકાશે)\n'
                '• રજીસ્ટર ➔ બેઠક ➔ ગેરહાજર ➔ બંડલ ૧૦૦% ઓટોમેટિક',
                style: TextStyle(
                    color: Color(0xFFDBEAFE), fontSize: 11, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopActionBar(NavPageItem cur) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD8E2F0)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (Navigator.of(context).canPop())
                _actionButton(
                  label: '⬅ પાછા (Back)',
                  color: kNavy,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              _actionButton(
                label: '🖨️ આ જ પેજ ડાયરેક્ટ PDF ડાઉનલોડ',
                color: const Color(0xFF1D4ED8),
                onTap: () => _showPrintExportDialog(onlyCurrent: true),
              ),
              _actionButton(
                label: '🖨️ સંપૂર્ણ ફાઈલ ડાયરેક્ટ PDF (All Pages)',
                color: kRed,
                onTap: () => _showPrintExportDialog(onlyCurrent: false),
              ),
              _actionButton(
                label: '⚖️ લોગો સેન્ટર (Ctrl+E)',
                color: const Color(0xFFD97706),
                onTap: _centerAlignExamLogosAndTexts,
              ),
              _actionButton(
                label: '🎯 વર્ગ અને વિષય પસંદગી (3–5 / 6–8 / 3–8)',
                color: const Color(0xFF0F766E),
                onTap: () => setState(() => activePageId = 'exam_setup'),
              ),
              _actionButton(
                label: '⚡ ૧-ક્લિક સ્માર્ટ ઓટો-ફિલ',
                color: const Color(0xFF6D28D9),
                onTap: runMasterAutoFill,
              ),
              _actionButton(
                label: '💾 JSON બેકઅપ / રિસ્ટોર',
                color: const Color(0xFF0369A1),
                onTap: _showBackupRestoreDialog,
              ),
              if (widget.onSaveData != null)
                _actionButton(
                  label: '☁️ Database માં સેવ કરો',
                  color: kGreen,
                  onTap: _saveToSchoolDatabase,
                ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: kGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle,
                        color: Colors.white, size: 15),
                    const SizedBox(width: 5),
                    Flexible(child: Text(
                      widget.onSaveData == null
                          ? 'ઓટો સેવ સક્રિય'
                          : 'આ ઉપકરણ પર ઓટો સેવ ચાલુ',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5),
                    )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              _infoPill(_clockText, const Color(0xFF143C82), Colors.white),
              _infoPill(_dateText, kRed, Colors.white),
              _infoPill(
                cur.isLandscape
                    ? '📐 પેજ માપ: Landscape (આડું A4)'
                    : '📄 પેજ માપ: Portrait (ઊભું A4)',
                cur.isLandscape ? const Color(0xFF9A3412) : kNavy,
                cur.isLandscape
                    ? const Color(0xFFFFEDD5)
                    : const Color(0xFFE0ECFF),
              ),
              _infoPill(
                '🔤 પેજ ફોન્ટ: $activeFontPct%',
                const Color(0xFF312E81),
                const Color(0xFFE0E7FF),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Universal Per-Page Toolbar with Font Size Control Tab (`🔤 ફોન્ટ સાઈઝ`) on EVERY page
  Widget _buildPerPageToolbar(NavPageItem cur) {
    final pctOptions = [
      75,
      80,
      85,
      90,
      95,
      100,
      105,
      110,
      115,
      120,
      125,
      135,
      150
    ];
    final currentPct = pctOptions.contains(activeFontPct) ? activeFontPct : 100;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC9D3E3)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Font Size Control Tab (Present on EVERY page)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF4FF),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0xFF6366F1), width: 1.5),
            ),
            child: Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('🔤 ફોન્ટ સાઈઝ:',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E1B4B),
                        fontSize: 12.5)),
                _miniToolBtn('A−', const Color(0xFF312E81),
                    () => setPageFont(activeFontPct - 5)),
                DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: currentPct,
                    isDense: true,
                    style: const TextStyle(
                        color: Color(0xFF1E1B4B),
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5),
                    items: pctOptions
                        .map((p) =>
                            DropdownMenuItem(value: p, child: Text('$p%')))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setPageFont(v);
                    },
                  ),
                ),
                _miniToolBtn('A+', const Color(0xFF312E81),
                    () => setPageFont(activeFontPct + 5)),
                _miniToolBtn(
                    'રીસેટ', const Color(0xFF64748B), () => setPageFont(100)),
                _miniToolBtn(
                    'બધા પેજમાં', const Color(0xFF0F766E), applyFontToAllPages),
              ],
            ),
          ),
          // Universal data-row and row-height tools available on EVERY page.
          _miniToolBtn(
            _selectedRowIndex != null
                ? '➕ પસંદ કરેલ રો (#${_selectedRowIndex! + 1}) પછી ઉમેરો'
                : '➕ રો ઉમેરો',
            kGreen,
            _addRowToActivePage,
          ),
          _miniToolBtn(
            _selectedRowIndex != null
                ? '🗑️ પસંદ કરેલ રો (#${_selectedRowIndex! + 1}) કાઢો'
                : '🗑️ રો કાઢો',
            kRed,
            _deleteSelectedOrPromptRow,
          ),
          if (_selectedRowIndex != null)
            _infoPill(
              '📍 સિલેક્ટેડ રો: #${_selectedRowIndex! + 1}${_selectedBlockNo != null ? " (બ્લોક $_selectedBlockNo)" : ""}',
              const Color(0xFF9A3412),
              const Color(0xFFFFEDD5),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kNavy, width: 1.4),
            ),
            child: Wrap(
              spacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  '↕ રો ઊંચાઈ:',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: kNavy,
                  ),
                ),
                _miniToolBtn('−', const Color(0xFF475569),
                    () => _adjustActiveRowHeight(-1)),
                DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: activeRowHeight.round().clamp(2, 35),
                    isDense: true,
                    style: const TextStyle(
                      color: kNavy,
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                    ),
                    items: [
                      for (int h = 2; h <= 35; h++)
                        DropdownMenuItem<int>(
                          value: h,
                          child: Text('$h'),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) _setActiveRowHeight(v.toDouble());
                    },
                  ),
                ),
                _miniToolBtn('+', const Color(0xFF475569),
                    () => _adjustActiveRowHeight(1)),
                _miniToolBtn('રીસેટ', const Color(0xFF64748B),
                    () => _setActiveRowHeight(6.0)),
                _miniToolBtn('બધા પેજમાં', const Color(0xFF0F766E),
                    _applyRowHeightToAllPages),
              ],
            ),
          ),
          // School Name Language Selector (School Name is locked to Registration; only language switches)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kGreen, width: 1.4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '🌐 શાળા નામ ભાષા: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: Color(0xFF065F46),
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: schoolNameLang,
                    isDense: true,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      color: kNavy,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'gu', child: Text('ગુજરાતી')),
                      DropdownMenuItem(value: 'en', child: Text('English')),
                    ],
                    onChanged: (v) {
                      if (v != null) _setExamSchoolNameLanguage(v);
                    },
                  ),
                ),
              ],
            ),
          ),
          // Universal Logo Size & Placement Controls on EVERY Page
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kSaffron, width: 1.4),
            ),
            child: Wrap(
              spacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  '🛡️ લોગો:',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: kNavy,
                  ),
                ),
                _miniToolBtn('📤 અપલોડ', kNavy, _pickCustomExamLogo),
                _miniToolBtn('નાનો −', const Color(0xFF475569), () {
                  setState(() {
                    if (cur.category == 'cover') {
                      coverLogoSize = (coverLogoSize - 10).clamp(60.0, 260.0);
                    } else {
                      headerLogoSize = (headerLogoSize - 4).clamp(24.0, 140.0);
                    }
                  });
                  _scheduleExamDeviceAutoSave();
                }),
                _miniToolBtn('મોટો +', const Color(0xFF475569), () {
                  setState(() {
                    if (cur.category == 'cover') {
                      coverLogoSize = (coverLogoSize + 10).clamp(60.0, 260.0);
                    } else {
                      headerLogoSize = (headerLogoSize + 4).clamp(24.0, 140.0);
                    }
                  });
                  _scheduleExamDeviceAutoSave();
                }),
                _miniToolBtn('←', const Color(0xFF0369A1), () {
                  setState(() {
                    if (cur.category == 'cover') {
                      coverLogoOffset += const Offset(-10, 0);
                    } else {
                      headerLogoOffset += const Offset(-10, 0);
                    }
                  });
                  _scheduleExamDeviceAutoSave();
                }),
                _miniToolBtn('→', const Color(0xFF0369A1), () {
                  setState(() {
                    if (cur.category == 'cover') {
                      coverLogoOffset += const Offset(10, 0);
                    } else {
                      headerLogoOffset += const Offset(10, 0);
                    }
                  });
                  _scheduleExamDeviceAutoSave();
                }),
                _miniToolBtn('↑', const Color(0xFF0369A1), () {
                  setState(() {
                    if (cur.category == 'cover') {
                      coverLogoOffset += const Offset(0, -6);
                    } else {
                      headerLogoOffset += const Offset(0, -6);
                    }
                  });
                  _scheduleExamDeviceAutoSave();
                }),
                _miniToolBtn('↓', const Color(0xFF0369A1), () {
                  setState(() {
                    if (cur.category == 'cover') {
                      coverLogoOffset += const Offset(0, 6);
                    } else {
                      headerLogoOffset += const Offset(0, 6);
                    }
                  });
                  _scheduleExamDeviceAutoSave();
                }),
              ],
            ),
          ),
          _infoPill(
            '🖨️ પ્રિન્ટ પ્રિવ્યુ (Print Preview): સ્ક્રીન પર દેખાતું પેજ અને PDF 100% સમાન રહેશે',
            const Color(0xFF0F766E),
            const Color(0xFFD1FAE5),
          ),
          if (customTextOffsets.isNotEmpty ||
              coverLogoOffset != Offset.zero ||
              headerLogoOffset != Offset.zero)
            _miniToolBtn('🔄 ખસેડેલી જગ્યા રીસેટ કરો', const Color(0xFF0369A1), () {
              setState(() {
                customTextOffsets.clear();
                coverLogoOffset = Offset.zero;
                headerLogoOffset = Offset.zero;
              });
              _scheduleExamDeviceAutoSave();
              _showSnack('🔄 બધા લખાણ અને લોગોની જગ્યા મૂળ સ્થિતિમાં રીસેટ થઈ ગઈ!');
            }),
          // Page-specific quick controls
          ..._buildContextSpecificTools(cur),
        ],
      ),
    );
  }

  double get activeRowHeight =>
      _rowHeightForPrefix(currentNavPage.category, fallbackPageId: activePageId);

  void _setActiveRowHeight(double newHeight) {
    final clamped = newHeight.clamp(2.0, 35.0).toDouble();
    final cat = currentNavPage.category;
    setState(() {
      pageRowHeights[activePageId] = clamped;
      pageRowHeights[cat] = clamped;
      for (final p in _matchingKeysForPrefix(cat)) {
        pageRowHeights[p] = clamped;
      }
      for (final key in pageRowHeights.keys.toList()) {
        for (final p in _matchingKeysForPrefix(cat)) {
          if (key == p || key.startsWith('${p}_')) {
            pageRowHeights[key] = clamped;
          }
        }
      }
      final updatedPages = allNavPages;
      if (!updatedPages.any((p) => p.id == activePageId)) {
        final sameCat = updatedPages.where((p) => p.category == cat).toList();
        if (sameCat.isNotEmpty) {
          activePageId = sameCat.last.id;
        }
      }
    });
    _scheduleExamDeviceAutoSave();
  }

  void _adjustActiveRowHeight(double amount) {
    _setActiveRowHeight(activeRowHeight + amount);
  }

  void _applyRowHeightToAllPages() {
    final rh = activeRowHeight;
    setState(() {
      for (final p in allNavPages) {
        pageRowHeights[p.id] = rh;
        pageRowHeights[p.category] = rh;
      }
    });
    _scheduleExamDeviceAutoSave();
    _showSnack('✅ બધા જ પેજમાં રો ઊંચાઈ ${rh.toStringAsFixed(0)} લાગુ થઈ ગઈ!');
  }

  Widget _buildExtraPageRows(NavPageItem page) {
    final rows = extraPageRows[page.id] ?? const <ExamExtraDetailRow>[];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFF94A3B8)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'વધારાની વિગતો — કોઈપણ કોષ પર ક્લિક કરીને સુધારો',
            style: TextStyle(
              color: kNavy,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          for (int i = 0; i < rows.length; i++)
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _editableCell(rows[i].label, (value) {
                    rows[i].label = value;
                  }),
                ),
                Expanded(
                  flex: 4,
                  child: _editableCell(rows[i].value, (value) {
                    rows[i].value = value;
                  }),
                ),
                IconButton(
                  tooltip: 'આ રો કાઢો',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline,
                      color: kRed, size: 18),
                  onPressed: () {
                    setState(() => rows.removeAt(i));
                    _scheduleExamDeviceAutoSave();
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _markRowSelected({
    required String section,
    required int index,
    int? blockNo,
    int? bundleCardIndex,
  }) {
    if (_selectedRowSection == section &&
        _selectedRowIndex == index &&
        _selectedBlockNo == blockNo &&
        _selectedBundleCardIndex == bundleCardIndex) {
      return;
    }
    setState(() {
      _selectedRowSection = section;
      _selectedRowIndex = index;
      _selectedBlockNo = blockNo;
      _selectedBundleCardIndex = bundleCardIndex;
    });
  }

  void _addRowToActivePage() {
    final page = currentNavPage;
    var refreshTimetableDerived = false;
    var refreshRegisterDerived = false;
    var refreshSeatingDerived = false;
    var refreshStationeryTotals = false;
    setState(() {
      switch (page.category) {
        case 'teachers':
          final idx = (_selectedRowSection == 'teachers' &&
                  _selectedRowIndex != null &&
                  _selectedRowIndex! >= 0 &&
                  _selectedRowIndex! < teachers.length)
              ? _selectedRowIndex! + 1
              : teachers.length;
          teachers.insert(
              idx, TeacherRecord(name: '', group: 'a', subjects: <String>[]));
          _selectedRowIndex = idx;
          break;
        case 'committee':
          if (_selectedRowSection == 'work_duty' &&
              _selectedRowIndex != null &&
              _selectedRowIndex! >= 0 &&
              _selectedRowIndex! < workDutyRows.length) {
            final idx = _selectedRowIndex! + 1;
            workDutyRows.insert(idx, CommitteeRow());
            _selectedRowIndex = idx;
          } else {
            final idx = (_selectedRowSection == 'committee' &&
                    _selectedRowIndex != null &&
                    _selectedRowIndex! >= 0 &&
                    _selectedRowIndex! < committeeRows.length)
                ? _selectedRowIndex! + 1
                : committeeRows.length;
            committeeRows.insert(idx, CommitteeRow());
            _selectedRowIndex = idx;
          }
          break;
        case 'dashboard':
          final idx = (_selectedRowSection == 'bell' &&
                  _selectedRowIndex != null &&
                  _selectedRowIndex! >= 0 &&
                  _selectedRowIndex! < bellScheduleRows.length)
              ? _selectedRowIndex! + 1
              : bellScheduleRows.length;
          bellScheduleRows.insert(
              idx, <String>['${idx + 1}', '', '', '', '']);
          _selectedRowIndex = idx;
          break;
        case 'exam_setup':
        case 'register':
          final hasSel = (_selectedRowSection == 'register' &&
              _selectedRowIndex != null &&
              _selectedRowIndex! >= 0 &&
              _selectedRowIndex! < registerRows.length);
          final registerGroup = hasSel
              ? registerRows[_selectedRowIndex!].group
              : (examClassRangeMode == '6to8' || !hasGroupA ? 'b' : 'a');
          final nextName = 'નવો વર્ગ ${registerRows.length + 1}';
          final row = RegisterRow(
              className: nextName,
              group: registerGroup,
              boys: 0,
              girls: 0,
              databaseTotal: 0);
          final insertIdx = hasSel ? _selectedRowIndex! + 1 : registerRows.length;
          registerRows.insert(insertIdx, row);
          allInsertedClassRows.add(RegisterRow(
              className: nextName,
              group: registerGroup,
              boys: 0,
              girls: 0,
              databaseTotal: 0));
          selectedExamClasses.add(nextName);
          _selectedRowIndex = insertIdx;
          refreshRegisterDerived = true;
          break;
        case 'timetable':
          final hasSel = (_selectedRowSection == 'timetable' &&
              _selectedRowIndex != null &&
              _selectedRowIndex! >= 0 &&
              _selectedRowIndex! < timetableRows.length);
          final prevRow = hasSel ? timetableRows[_selectedRowIndex!] : null;
          final timetableGroup = prevRow?.group ?? (hasGroupA ? 'a' : 'b');
          final newTt = TimetableRow(
            date: prevRow?.date ?? '',
            day: prevRow?.day ?? '',
            stdLabel: prevRow?.stdLabel ??
                (timetableGroup == 'a' ? '૩ થી ૫' : '૬ થી ૮'),
            subject: '',
            time: prevRow?.time ??
                (timetableGroup == 'a' ? '11:00 થી 1:00' : '2:00 થી 5:00'),
            marks: prevRow?.marks ?? (timetableGroup == 'a' ? '40' : '80'),
          );
          final insertIdx = hasSel ? _selectedRowIndex! + 1 : timetableRows.length;
          timetableRows.insert(insertIdx, newTt);
          _selectedRowIndex = insertIdx;
          refreshTimetableDerived = true;
          break;
        case 'seat_a':
        case 'seat_b':
          final isA = page.category == 'seat_a';
          final list = isA ? seatingA : seatingB;
          final secKey = isA ? 'seat_a' : 'seat_b';
          final hasSel = (_selectedRowSection == secKey &&
              _selectedRowIndex != null &&
              _selectedRowIndex! >= 0 &&
              _selectedRowIndex! < list.length);
          final targetBlock = hasSel
              ? list[_selectedRowIndex!].blockNo
              : (_selectedBlockNo ?? (list.isEmpty ? 1 : list.last.blockNo));
          final insertIdx = hasSel ? _selectedRowIndex! + 1 : list.length;
          list.insert(
            insertIdx,
            SeatingRow(
              blockNo: targetBlock,
              className: hasSel ? list[_selectedRowIndex!].className : '',
              fromRoll: '',
              toRoll: '',
              totalCount: '0',
            ),
          );
          _selectedRowIndex = insertIdx;
          _selectedBlockNo = targetBlock;
          refreshSeatingDerived = true;
          break;
        case 'absent':
          if (page.subIndex < absentSheets.length) {
            final sheet = absentSheets[page.subIndex];
            if (_selectedRowSection == 'absent_block' &&
                _selectedRowIndex != null &&
                _selectedRowIndex! >= 0 &&
                _selectedRowIndex! < sheet.blockRows.length) {
              final ins = _selectedRowIndex! + 1;
              sheet.blockRows.insert(
                ins,
                AbsentBlockRow(blockNo: sheet.blockRows[_selectedRowIndex!].blockNo),
              );
              _selectedRowIndex = ins;
            } else {
              final hasSel = (_selectedRowSection == 'absent_student' &&
                  _selectedRowIndex != null &&
                  _selectedRowIndex! >= 0 &&
                  _selectedRowIndex! < sheet.studentList.length);
              final ins = hasSel ? _selectedRowIndex! + 1 : sheet.studentList.length;
              sheet.studentList.insert(
                  ins, AbsentStudentEntry(srNo: ins + 1));
              for (int i = 0; i < sheet.studentList.length; i++) {
                sheet.studentList[i].srNo = i + 1;
              }
              _selectedRowIndex = ins;
            }
          }
          break;
        case 'super_a':
        case 'super_b':
          final isSuperGroupA = page.category == 'super_a';
          final supervisionList = isSuperGroupA ? supervisionA : supervisionB;
          final secKey = isSuperGroupA ? 'super_a' : 'super_b';
          final hasSel = (_selectedRowSection == secKey &&
              _selectedRowIndex != null &&
              _selectedRowIndex! >= 0 &&
              _selectedRowIndex! < supervisionList.length);
          final prev = hasSel ? supervisionList[_selectedRowIndex!] : null;
          final ins = hasSel ? _selectedRowIndex! + 1 : supervisionList.length;
          supervisionList.insert(
            ins,
            SupervisionRow(
              date: prev?.date ?? '',
              day: prev?.day ?? '',
              subject: prev?.subject ?? '',
              blockNo: prev?.blockNo ?? (_selectedBlockNo ?? 1),
            ),
          );
          _selectedRowIndex = ins;
          break;
        case 'check_a':
        case 'check_b':
          final checkGroup = page.category == 'check_a' ? 'a' : 'b';
          final secKey = page.category;
          final hasSel = (_selectedRowSection == secKey &&
              _selectedRowIndex != null &&
              _selectedRowIndex! >= 0 &&
              _selectedRowIndex! < checkingRows.length);
          final prev = hasSel ? checkingRows[_selectedRowIndex!] : null;
          final ins = hasSel ? _selectedRowIndex! + 1 : checkingRows.length;
          checkingRows.insert(
            ins,
            CheckingRow(
              date: prev?.date ?? '',
              subject: prev?.subject ?? '',
              className: prev?.className ?? '',
              paperCount: prev?.paperCount ?? '',
              examinerName: prev?.examinerName ?? '',
              returnDate: '',
              group: checkGroup,
            ),
          );
          _selectedRowIndex = ins;
          break;
        case 'bundle':
          final targetCardIdx = (_selectedBundleCardIndex != null &&
                  _selectedBundleCardIndex! >= 0 &&
                  _selectedBundleCardIndex! < bundleCards.length)
              ? _selectedBundleCardIndex!
              : page.subIndex * bundlesPerPage;
          if (targetCardIdx < bundleCards.length) {
            final card = bundleCards[targetCardIdx];
            final hasSel = (_selectedRowSection == 'bundle' &&
                _selectedRowIndex != null &&
                _selectedRowIndex! >= 0 &&
                _selectedRowIndex! < card.rows.length);
            final ins = hasSel ? _selectedRowIndex! + 1 : card.rows.length;
            final defaultReg = card.rows.isNotEmpty ? card.rows.first.regCount : '';
            card.rows.insert(
              ins,
              BundleSubjectRow(
                srNo: ins + 1,
                date: '',
                subject: '',
                regCount: defaultReg,
              ),
            );
            for (int i = 0; i < card.rows.length; i++) {
              card.rows[i].srNo = i + 1;
            }
            _selectedRowIndex = ins;
          }
          break;
        case 'door':
          final doorTarget = _doorPageFirstBlock(page.subIndex);
          if (doorTarget != null) {
            final doorGroupIsA = doorTarget['group'] == 'a';
            final list = doorGroupIsA ? seatingA : seatingB;
            final targetBlk = _selectedBlockNo ?? (doorTarget['block'] as int);
            list.add(SeatingRow(
              blockNo: targetBlk,
              className: '',
              fromRoll: '',
              toRoll: '',
              totalCount: '0',
            ));
            refreshSeatingDerived = true;
          }
          break;
        case 'qp_reg':
          final hasSel = (_selectedRowSection == 'qp_reg' &&
              _selectedRowIndex != null &&
              _selectedRowIndex! >= 0 &&
              _selectedRowIndex! < qpRegisterRows.length);
          final ins = hasSel ? _selectedRowIndex! + 1 : qpRegisterRows.length;
          qpRegisterRows.insert(
              ins, <String>['${ins + 1}', '', '', '', '', '', '', '', '', '', '']);
          for (int i = 0; i < qpRegisterRows.length; i++) {
            if (qpRegisterRows[i].isNotEmpty) qpRegisterRows[i][0] = '${i + 1}';
          }
          _selectedRowIndex = ins;
          break;
        case 'stationery':
          final hasSel = (_selectedRowSection == 'stationery' &&
              _selectedRowIndex != null &&
              _selectedRowIndex! >= 0 &&
              _selectedRowIndex! < stationeryRows.length &&
              !stationeryRows[_selectedRowIndex!].first.contains('કુલ'));
          final ins = hasSel
              ? _selectedRowIndex! + 1
              : math.max(0, stationeryRows.length - 1);
          stationeryRows.insert(
              ins, <String>['નવો વર્ગ', '0', '5', '0', '0', '0', '0', '5 નંગ', '']);
          _selectedRowIndex = ins;
          refreshStationeryTotals = true;
          break;
        case 'instructions':
          final hasSel = (_selectedRowSection == 'instructions' &&
              _selectedRowIndex != null &&
              _selectedRowIndex! >= 0 &&
              _selectedRowIndex! < editableInstructions.length);
          final ins = hasSel ? _selectedRowIndex! + 1 : editableInstructions.length;
          editableInstructions.insert(ins, 'નવી સૂચના');
          _selectedRowIndex = ins;
          break;
        default:
          extraPageRows.putIfAbsent(page.id, () => <ExamExtraDetailRow>[])
              .add(ExamExtraDetailRow());
          break;
      }
    });
    if (refreshSeatingDerived) {
      syncAllottedFromSeating(notify: false);
    }
    if (refreshStationeryTotals) {
      setState(_recalculateStationeryTotalsInPlace);
    }
    if (refreshRegisterDerived) {
      autoAllocateSeatingFromRegister(notify: false);
      _refreshDerivedPagesFromTimetable();
    }
    if (refreshTimetableDerived) _refreshDerivedPagesFromTimetable();
    _scheduleExamDeviceAutoSave();
    _showSnack('➕ ${page.title}: પસંદ કરેલ રો પછી નવી રો ઉમેરાઈ અને કુલ સરવાળો ઓટો-અપડેટ થયો!');
  }

  Future<void> _deleteSelectedOrPromptRow() async {
    final page = currentNavPage;
    bool deletedDirect = false;
    String deletedLabel = '';

    setState(() {
      if (page.category == 'seat_a' || page.category == 'seat_b') {
        final isA = page.category == 'seat_a';
        final list = isA ? seatingA : seatingB;
        final secKey = isA ? 'seat_a' : 'seat_b';
        if (_selectedRowSection == secKey &&
            _selectedRowIndex != null &&
            _selectedRowIndex! >= 0 &&
            _selectedRowIndex! < list.length) {
          final r = list.removeAt(_selectedRowIndex!);
          deletedLabel = 'બ્લોક ${r.blockNo} (${r.className})';
          _selectedRowIndex = null;
          deletedDirect = true;
        }
      } else if (page.category == 'timetable' &&
          _selectedRowSection == 'timetable' &&
          _selectedRowIndex != null &&
          _selectedRowIndex! >= 0 &&
          _selectedRowIndex! < timetableRows.length) {
        final r = timetableRows.removeAt(_selectedRowIndex!);
        deletedLabel = '${r.date} - ${r.subject} (${r.stdLabel})';
        _selectedRowIndex = null;
        deletedDirect = true;
      } else if ((page.category == 'register' || page.category == 'exam_setup') &&
          _selectedRowSection == 'register' &&
          _selectedRowIndex != null &&
          _selectedRowIndex! >= 0 &&
          _selectedRowIndex! < registerRows.length &&
          registerRows.length > 1) {
        final r = registerRows.removeAt(_selectedRowIndex!);
        selectedExamClasses.remove(r.className);
        allInsertedClassRows.removeWhere((x) => x.className == r.className);
        deletedLabel = 'વર્ગ ${r.className}';
        _selectedRowIndex = null;
        deletedDirect = true;
      } else if (page.category == 'teachers' &&
          _selectedRowSection == 'teachers' &&
          _selectedRowIndex != null &&
          _selectedRowIndex! >= 0 &&
          _selectedRowIndex! < teachers.length) {
        final r = teachers.removeAt(_selectedRowIndex!);
        deletedLabel = r.name;
        _selectedRowIndex = null;
        deletedDirect = true;
      } else if (page.category == 'committee') {
        if (_selectedRowSection == 'work_duty' &&
            _selectedRowIndex != null &&
            _selectedRowIndex! >= 0 &&
            _selectedRowIndex! < workDutyRows.length) {
          final r = workDutyRows.removeAt(_selectedRowIndex!);
          deletedLabel = r.roleOrDuty;
          _selectedRowIndex = null;
          deletedDirect = true;
        } else if (_selectedRowSection == 'committee' &&
            _selectedRowIndex != null &&
            _selectedRowIndex! >= 0 &&
            _selectedRowIndex! < committeeRows.length) {
          final r = committeeRows.removeAt(_selectedRowIndex!);
          deletedLabel = r.roleOrDuty;
          _selectedRowIndex = null;
          deletedDirect = true;
        }
      } else if (page.category == 'absent' && page.subIndex < absentSheets.length) {
        final sh = absentSheets[page.subIndex];
        if (_selectedRowSection == 'absent_block' &&
            _selectedRowIndex != null &&
            _selectedRowIndex! >= 0 &&
            _selectedRowIndex! < sh.blockRows.length) {
          final r = sh.blockRows.removeAt(_selectedRowIndex!);
          deletedLabel = 'બ્લોક ${r.blockNo}';
          _selectedRowIndex = null;
          deletedDirect = true;
        } else if (_selectedRowSection == 'absent_student' &&
            _selectedRowIndex != null &&
            _selectedRowIndex! >= 0 &&
            _selectedRowIndex! < sh.studentList.length) {
          final r = sh.studentList.removeAt(_selectedRowIndex!);
          for (int i = 0; i < sh.studentList.length; i++) {
            sh.studentList[i].srNo = i + 1;
          }
          deletedLabel = 'ક્રમ ${r.srNo}';
          _selectedRowIndex = null;
          deletedDirect = true;
        }
      } else if ((page.category == 'super_a' || page.category == 'super_b') &&
          _selectedRowSection == page.category &&
          _selectedRowIndex != null) {
        final list = page.category == 'super_a' ? supervisionA : supervisionB;
        if (_selectedRowIndex! >= 0 && _selectedRowIndex! < list.length) {
          final r = list.removeAt(_selectedRowIndex!);
          deletedLabel = '${r.date} - બ્લોક ${r.blockNo}';
          _selectedRowIndex = null;
          deletedDirect = true;
        }
      } else if ((page.category == 'check_a' || page.category == 'check_b') &&
          _selectedRowSection == page.category &&
          _selectedRowIndex != null &&
          _selectedRowIndex! >= 0 &&
          _selectedRowIndex! < checkingRows.length) {
        final r = checkingRows.removeAt(_selectedRowIndex!);
        deletedLabel = '${r.className} - ${r.subject}';
        _selectedRowIndex = null;
        deletedDirect = true;
      } else if (page.category == 'bundle' &&
          _selectedRowSection == 'bundle' &&
          _selectedBundleCardIndex != null &&
          _selectedBundleCardIndex! >= 0 &&
          _selectedBundleCardIndex! < bundleCards.length &&
          _selectedRowIndex != null) {
        final card = bundleCards[_selectedBundleCardIndex!];
        if (_selectedRowIndex! >= 0 && _selectedRowIndex! < card.rows.length) {
          final r = card.rows.removeAt(_selectedRowIndex!);
          for (int i = 0; i < card.rows.length; i++) {
            card.rows[i].srNo = i + 1;
          }
          deletedLabel = '${card.className} - ${r.subject}';
          _selectedRowIndex = null;
          deletedDirect = true;
        }
      } else if (page.category == 'qp_reg' &&
          _selectedRowSection == 'qp_reg' &&
          _selectedRowIndex != null &&
          _selectedRowIndex! >= 0 &&
          _selectedRowIndex! < qpRegisterRows.length) {
        qpRegisterRows.removeAt(_selectedRowIndex!);
        for (int i = 0; i < qpRegisterRows.length; i++) {
          if (qpRegisterRows[i].isNotEmpty) qpRegisterRows[i][0] = '${i + 1}';
        }
        deletedLabel = 'પ્રશ્નપત્ર રો';
        _selectedRowIndex = null;
        deletedDirect = true;
      } else if (page.category == 'stationery' &&
          _selectedRowSection == 'stationery' &&
          _selectedRowIndex != null &&
          _selectedRowIndex! >= 0 &&
          _selectedRowIndex! < stationeryRows.length &&
          !stationeryRows[_selectedRowIndex!].first.contains('કુલ')) {
        final r = stationeryRows.removeAt(_selectedRowIndex!);
        _recalculateStationeryTotalsInPlace();
        deletedLabel = r.first;
        _selectedRowIndex = null;
        deletedDirect = true;
      } else if (page.category == 'instructions' &&
          _selectedRowSection == 'instructions' &&
          _selectedRowIndex != null &&
          _selectedRowIndex! >= 0 &&
          _selectedRowIndex! < editableInstructions.length) {
        editableInstructions.removeAt(_selectedRowIndex!);
        deletedLabel = 'સૂચના';
        _selectedRowIndex = null;
        deletedDirect = true;
      }
    });

    if (deletedDirect) {
      if (page.category == 'timetable') _refreshDerivedPagesFromTimetable();
      if (page.category == 'register' || page.category == 'exam_setup') {
        autoAllocateSeatingFromRegister(notify: false);
        _refreshDerivedPagesFromTimetable();
      }
      if (page.category == 'seat_a' ||
          page.category == 'seat_b' ||
          page.category == 'door') {
        syncAllottedFromSeating(notify: false);
      }
      if (page.category == 'teachers') {
        generateSupervision(notify: false);
        rebuildCheckingRows(notify: false);
      }
      _scheduleExamDeviceAutoSave();
      _showSnack('🗑️ પસંદ કરેલી રો ($deletedLabel) કાઢી નાખવામાં આવી અને કુલ સરવાળો અપડેટ થયો!');
      return;
    }

    await _showDeleteRowDialog();
  }

  List<Map<String, dynamic>> _doorPageBlocks(int pageIndex) {
    final result = <Map<String, dynamic>>[];
    final countA = hasGroupA ? blocksA : 0;
    final countB = hasGroupB ? blocksB : 0;
    final start = pageIndex * doorsPerPage;
    for (var offset = 0; offset < doorsPerPage; offset++) {
      final absoluteIndex = start + offset;
      if (absoluteIndex < countA) {
        result.add(<String, dynamic>{'group': 'a', 'block': absoluteIndex + 1});
      } else {
        final bIndex = absoluteIndex - countA;
        if (bIndex < countB) {
          result.add(<String, dynamic>{'group': 'b', 'block': bIndex + 1});
        }
      }
    }
    return result;
  }

  Map<String, dynamic>? _doorPageFirstBlock(int pageIndex) {
    final blocks = _doorPageBlocks(pageIndex);
    return blocks.isEmpty ? null : blocks.first;
  }

  List<_ExamRowDeleteOption> _activePageDeleteOptions() {
    final page = currentNavPage;
    final options = <_ExamRowDeleteOption>[];
    void addExtraRows() {
      final rows = extraPageRows[page.id] ?? <ExamExtraDetailRow>[];
      for (var i = 0; i < rows.length; i++) {
        final index = i;
        options.add(_ExamRowDeleteOption(
          'વધારાની વિગત: ${rows[index].label}',
          () => rows.removeAt(index),
        ));
      }
    }

    switch (page.category) {
      case 'teachers':
        for (var i = 0; i < teachers.length; i++) {
          final row = teachers[i];
          options.add(_ExamRowDeleteOption(
              'શિક્ષક: ${row.name.isEmpty ? 'નામ વગર' : row.name}',
              () => teachers.remove(row)));
        }
        break;
      case 'committee':
        for (var i = 0; i < committeeRows.length; i++) {
          final row = committeeRows[i];
          options.add(_ExamRowDeleteOption(
              'સમિતિ: ${row.teacherName} — ${row.roleOrDuty}',
              () => committeeRows.remove(row)));
        }
        for (var i = 0; i < workDutyRows.length; i++) {
          final row = workDutyRows[i];
          options.add(_ExamRowDeleteOption(
              'કાર્ય ફાળવણી: ${row.teacherName} — ${row.roleOrDuty}',
              () => workDutyRows.remove(row)));
        }
        break;
      case 'dashboard':
        for (final row in bellScheduleRows.toList()) {
          options.add(_ExamRowDeleteOption(
              'બેલ સમયપત્રક: ${row.length > 1 ? row[1] : 'ખાલી રો'}',
              () => bellScheduleRows.remove(row)));
        }
        break;
      case 'exam_setup':
        for (final row in registerRows) {
          options.add(_ExamRowDeleteOption('પરીક્ષા વર્ગ: ${row.className}', () {
            registerRows.remove(row);
            selectedExamClasses.remove(row.className);
            allInsertedClassRows.removeWhere((item) =>
                item.className == row.className && item.group == row.group);
          }));
        }
        break;
      case 'register':
        for (final row in registerRows) {
          options.add(_ExamRowDeleteOption(
              'વર્ગ: ${row.className}', () {
            registerRows.remove(row);
            selectedExamClasses.remove(row.className);
            allInsertedClassRows.removeWhere((item) => item.className == row.className);
          }));
        }
        break;
      case 'timetable':
        for (final row in timetableRows) {
          options.add(_ExamRowDeleteOption(
              'સમયપત્રક: ${row.date} — ${row.subject} (${row.stdLabel})',
              () => timetableRows.remove(row)));
        }
        break;
      case 'seat_a':
      case 'seat_b':
        final rows = page.category == 'seat_a' ? seatingA : seatingB;
        for (final row in rows) {
          options.add(_ExamRowDeleteOption(
              'બ્લોક ${row.blockNo}: ${row.className} ${row.fromRoll}-${row.toRoll}',
              () => rows.remove(row)));
        }
        break;
      case 'absent':
        if (page.subIndex < absentSheets.length) {
          final sheet = absentSheets[page.subIndex];
          for (final row in sheet.blockRows) {
            options.add(_ExamRowDeleteOption(
                'બ્લોક રો: ${row.blockNo}', () => sheet.blockRows.remove(row)));
          }
          for (final row in sheet.studentList) {
            options.add(_ExamRowDeleteOption(
                'વિદ્યાર્થી: ${row.studentName.isEmpty ? 'નામ વગર' : row.studentName}',
                () => sheet.studentList.remove(row)));
          }
        }
        break;
      case 'super_a':
      case 'super_b':
        final isA = page.category == 'super_a';
        final list = isA ? supervisionA : supervisionB;
        final perPage = _effectiveRowsPerPage(
          isA ? superRowsPerPageA : superRowsPerPageB,
          pageIdPrefix: page.category,
        );
        final supervisionChunk =
            list.skip(page.subIndex * perPage).take(perPage).toList();
        for (final row in supervisionChunk) {
          options.add(_ExamRowDeleteOption(
              'નિરીક્ષણ: ${row.date} — ${row.subject} — બ્લોક ${row.blockNo}',
              () => list.remove(row)));
        }
        break;
      case 'check_a':
      case 'check_b':
        final group = page.category == 'check_a' ? 'a' : 'b';
        final groupRows = checkingRows.where((row) => row.group == group).toList();
        final effCheckCap = _effectiveRowsPerPage(
          checkRowsPerPage,
          pageIdPrefix: page.category,
        );
        final checkingChunk = groupRows
            .skip(page.subIndex * effCheckCap)
            .take(effCheckCap);
        for (final row in checkingChunk) {
          options.add(_ExamRowDeleteOption(
              'ચકાસણી: ${row.className} — ${row.subject} — ${row.examinerName}',
              () => checkingRows.remove(row)));
        }
        break;
      case 'bundle':
        final cards = bundleCards
            .skip(page.subIndex * bundlesPerPage)
            .take(bundlesPerPage);
        for (final card in cards) {
          for (final row in card.rows) {
            options.add(_ExamRowDeleteOption(
                'બંડલ ${card.className}: ${row.date} — ${row.subject}',
                () => card.rows.remove(row)));
          }
        }
        break;
      case 'door':
        for (final target in _doorPageBlocks(page.subIndex)) {
          final isA = target['group'] == 'a';
          final block = target['block'] as int;
          final sourceRows = isA ? seatingA : seatingB;
          final rows = sourceRows.where((row) => row.blockNo == block).toList();
          for (final row in rows) {
            options.add(_ExamRowDeleteOption(
                'ડોર સ્ટીકર બ્લોક $block: ${row.className}',
                () => sourceRows.remove(row)));
          }
        }
        break;
      case 'qp_reg':
        for (final row in qpRegisterRows) {
          options.add(_ExamRowDeleteOption(
              'પ્રશ્નપત્ર રો: ${row.length > 4 ? row[4] : ''} (${row.length > 1 ? row[1] : ''})',
              () => qpRegisterRows.remove(row)));
        }
        break;
      case 'stationery':
        for (final row in stationeryRows.where((row) =>
            row.isNotEmpty && !row.first.contains('કુલ')).toList()) {
          options.add(_ExamRowDeleteOption(
              'સ્ટેશનરી: ${row.isNotEmpty ? row.first : ''}',
              () => stationeryRows.remove(row)));
        }
        break;
      case 'instructions':
        for (var i = 0; i < editableInstructions.length; i++) {
          final index = i;
          final row = editableInstructions[index];
          options.add(_ExamRowDeleteOption(
              'સૂચના: ${row.isEmpty ? 'ખાલી' : row}',
              () => editableInstructions.removeAt(index)));
        }
        break;
      default:
        addExtraRows();
        break;
    }
    if (page.category != 'cover' && page.category != 'index' &&
        page.category != 'dashboard' && page.category != 'exam_setup' &&
        page.category != 'instructions') {
      addExtraRows();
    } else if (page.category == 'dashboard' || page.category == 'exam_setup') {
      addExtraRows();
    }
    return options;
  }

  Future<void> _showDeleteRowDialog() async {
    final options = _activePageDeleteOptions();
    if (options.isEmpty) {
      _showSnack('આ પેજમાં કાઢવા માટે કોઈ રો નથી.', isError: true);
      return;
    }
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('કઈ રો કાઢવી છે?'),
        content: SizedBox(
          width: 520,
          height: math.min(460.0, 72.0 * options.length).toDouble(),
          child: ListView.builder(
            itemCount: options.length,
            itemBuilder: (context, index) => ListTile(
              dense: true,
              leading: const Icon(Icons.delete_outline, color: kRed),
              title: Text(options[index].label,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(ctx, index),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('રદ કરો')),
        ],
      ),
    );
    if (selected == null || selected < 0 || selected >= options.length) return;
    final category = currentNavPage.category;
    setState(options[selected].remove);
    if (category == 'timetable') _refreshDerivedPagesFromTimetable();
    if (category == 'register' || category == 'exam_setup') {
      autoAllocateSeatingFromRegister(notify: false);
      _refreshDerivedPagesFromTimetable();
    }
    if (category == 'seat_a' || category == 'seat_b' || category == 'door') {
      syncAllottedFromSeating(notify: false);
    }
    if (category == 'teachers') {
      generateSupervision(notify: false);
      rebuildCheckingRows(notify: false);
    }
    _scheduleExamDeviceAutoSave();
    _showSnack('🗑️ પસંદ કરેલી રો કાઢી નાખવામાં આવી.');
  }

  List<Widget> _buildContextSpecificTools(NavPageItem cur) {
    switch (cur.category) {
      case 'cover':
        return [
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _miniToolBtn('📤 લોગો અપલોડ / બદલો', kNavy, _pickCustomExamLogo),
              _miniToolBtn('⚖️ લોગો સેન્ટર (Ctrl+E)', kSaffron,
                  _centerAlignExamLogosAndTexts),
              _miniToolBtn('લોગો નાનો −', const Color(0xFF475569), () {
                setState(() =>
                    coverLogoSize = (coverLogoSize - 10).clamp(60.0, 260.0));
                _scheduleExamDeviceAutoSave();
              }),
              _miniToolBtn('લોગો મોટો +', const Color(0xFF475569), () {
                setState(() =>
                    coverLogoSize = (coverLogoSize + 10).clamp(60.0, 260.0));
                _scheduleExamDeviceAutoSave();
              }),
            ],
          ),
        ];
      case 'committee':
        return [
          _miniToolBtn('➕ કામગીરી રો', kGreen, () {
            setState(() => workDutyRows.add(CommitteeRow()));
            _scheduleExamDeviceAutoSave();
          }),
        ];
      case 'teachers':
        return [
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: superMode,
              isDense: true,
              items: const [
                DropdownMenuItem(
                  value: 'same',
                  child: Text('સુપરવિઝન: પોતાના જૂથમાં', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                ),
                DropdownMenuItem(
                  value: 'change',
                  child: Text('સુપરવિઝન: જૂથ બદલીને', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => superMode = v);
              },
            ),
          ),
          _miniToolBtn('📋 Excel પેસ્ટ કરો', const Color(0xFF107C41),
              _showExcelPasteDialog),
          _miniToolBtn(
              '👩‍🏫 બાલવાટિકા/ધો.૧–૨ પસંદગી',
              kSaffron,
              () => _showEarlyTeachersSupervisionDialog(generateAfter: false)),
          _miniToolBtn(
              '⚙️ ઓટો સુપરવિઝન બનાવો',
              kNavy,
              () => _identifiedEarlyClassTeacherCount > 0
                  ? _showEarlyTeachersSupervisionDialog(generateAfter: true)
                  : generateSupervision(notify: true)),
        ];
      case 'timetable':
        return [
          _miniToolBtn('📅 ઓટો-તારીખ ગોઠવો', kNavy, _autoScheduleTimetableDates),
          _miniToolBtn('➕ પેપર રો ઉમેરો (૩–૫)', kGreen, () {
            setState(() {
              timetableRows.add(TimetableRow(
                date: '',
                day: '',
                stdLabel: '૩ થી ૫',
                subject: 'નવો વિષય',
                time: '11:00 થી 1:00',
                marks: '40',
              ));
            });
            _refreshDerivedPagesFromTimetable();
            _scheduleExamDeviceAutoSave();
          }),
          _miniToolBtn('➕ પેપર રો ઉમેરો (૬–૮)', kGreen, () {
            setState(() {
              timetableRows.add(TimetableRow(
                date: '',
                day: '',
                stdLabel: '૬ થી ૮',
                subject: 'નવો વિષય',
                time: '2:00 થી 5:00',
                marks: '80',
              ));
            });
            _refreshDerivedPagesFromTimetable();
            _scheduleExamDeviceAutoSave();
          }),
        ];
      case 'register':
        return [
          DropdownButton<String>(
            value: genderMode,
            isDense: true,
            items: const [
              DropdownMenuItem(
                  value: 'both', child: Text('કુમાર અને કન્યા બંને')),
              DropdownMenuItem(value: 'boys', child: Text('ફક્ત કુમાર')),
              DropdownMenuItem(value: 'girls', child: Text('ફક્ત કન્યા')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => genderMode = v);
            },
          ),
          _miniToolBtn('➕ ધો. ૩–૫ વર્ગ ઉમેરો', kGreen, () {
            setState(() => registerRows.insert(
                  registerRows.where((r) => r.group == 'a').length,
                  RegisterRow(className: '', group: 'a', boys: 15, girls: 15),
                ));
          }),
          _miniToolBtn('➕ ધો. ૬–૮ વર્ગ ઉમેરો', kGreen, () {
            setState(() => registerRows.add(
                RegisterRow(className: '', group: 'b', boys: 15, girls: 15)));
          }),
        ];
      case 'seat_a':
      case 'seat_b':
        final isA = cur.category == 'seat_a';
        final curBlocks = isA ? blocksA : blocksB;
        return [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('બ્લોક સંખ્યા: ',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: kNavy,
                      fontSize: 12.5)),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 18),
                onPressed: () {
                  if (curBlocks > 1) {
                    setState(() {
                      if (isA) {
                        blocksA--;
                      } else {
                        blocksB--;
                      }
                    });
                    autoAllocateSeatingFromRegister(
                        targetGroup: isA ? 'a' : 'b');
                    rebuildAbsentPages();
                  }
                },
              ),
              Text('$curBlocks',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 14)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 18),
                onPressed: () {
                  setState(() {
                    if (isA) {
                      blocksA++;
                    } else {
                      blocksB++;
                    }
                  });
                  autoAllocateSeatingFromRegister(targetGroup: isA ? 'a' : 'b');
                  rebuildAbsentPages();
                },
              ),
            ],
          ),
          _miniToolBtn(
            '🪑 રજીસ્ટર પરથી ઓટો-બેઠક ફાળવો',
            kNavy,
            () => autoAllocateSeatingFromRegister(
                targetGroup: isA ? 'a' : 'b', notify: true),
          ),
        ];
      case 'absent':
        final sheet = absentSheets[cur.subIndex];
        return [
          _miniToolBtn('🪑 બેઠકમાંથી ફાળવાયેલ સંખ્યા લાવો', kNavy,
              () => syncAllottedFromSeating(notify: true)),
          _miniToolBtn('🧹 માત્ર ફાળવાયેલ સંખ્યા રાખો (બાકી ખાલી)', kRed,
              () => clearManualAbsentEntries(sheet)),
          _miniToolBtn('➕ બ્લોક રો ઉમેરો', kGreen, () {
            setState(() => sheet.blockRows.add(
                AbsentBlockRow(blockNo: sheet.blockRows.length + 1)));
            _scheduleExamDeviceAutoSave();
          }),
        ];
      case 'bundle':
        return [
          const Text('એક પેજમાં બંડલ:',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: kNavy, fontSize: 12.5)),
          for (final cnt in [4, 2, 1])
            _miniToolBtn(
              '$cnt બંડલ',
              bundlesPerPage == cnt ? kSaffron : kNavy,
              () => setState(() {
                bundlesPerPage = cnt;
                activePageId = 'bun_0';
              }),
            ),
          _miniToolBtn('🔄 રજીસ્ટરથી બંડલ રીફ્રેશ', kGreen,
              () => rebuildBundles(notify: true)),
        ];
      case 'door':
        return [
          const Text('એક પેજમાં સ્ટીકર:',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: kNavy, fontSize: 12.5)),
          for (final cnt in [4, 2, 1])
            _miniToolBtn(
              '$cnt સ્ટીકર',
              doorsPerPage == cnt ? kSaffron : kNavy,
              () => setState(() {
                doorsPerPage = cnt;
                activePageId = 'door_0';
              }),
            ),
        ];
      case 'stationery':
        return [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: include5PercentReserveInStationery,
                activeColor: kGreen,
                onChanged: (v) {
                  setState(() {
                    include5PercentReserveInStationery = v ?? true;
                  });
                  rebuildStationerySheet(true);
                  _scheduleExamDeviceAutoSave();
                },
              ),
              const Text(
                '૫% અનામત ઉત્તરવહી',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: Color(0xFF065F46),
                ),
              ),
            ],
          ),
          _miniToolBtn('ધો. ૩–૫ (પ્રશ્નપત્રમાં જવાબ)', kNavy, () {
            setState(() {
              classesWithAnswersInQuestionPaper
                ..clear()
                ..addAll(['std_3', 'std_4', 'std_5']);
              for (final r in registerRows.where((x) => x.group == 'a')) {
                classesWithAnswersInQuestionPaper.add(r.className.trim());
              }
            });
            rebuildStationerySheet(true);
            _scheduleExamDeviceAutoSave();
          }),
          _miniToolBtn('બધા વર્ગોને અલગ ઉત્તરવહી', kGreen, () {
            setState(() {
              classesWithAnswersInQuestionPaper.clear();
            });
            rebuildStationerySheet(true);
            _scheduleExamDeviceAutoSave();
          }),
        ];
      default:
        return [];
    }
  }

  // ============================================================================
  // A4 Framed Page Container & Page Renderers
  // ============================================================================

  Widget _buildA4FramedPage(NavPageItem cur) {
    final double pageWidth = cur.isLandscape ? 1050 : 780;
    final double minPageHeight = cur.isLandscape ? 720 : 1040;

    return Container(
      width: pageWidth,
      constraints: BoxConstraints(minHeight: minPageHeight),
      decoration: BoxDecoration(
        color: Colors.white,
        // No shadow / outer grey line while capturing for the PDF.
        boxShadow: _capturingForPdf
            ? null
            : const [
                BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 6))
              ],
        border: _capturingForPdf ? null : Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tricolor top accent bar
          SizedBox(
            height: 8,
            child: Row(
              children: const [
                Expanded(child: ColoredBox(color: kSaffron)),
                Expanded(child: ColoredBox(color: kNavy)),
                Expanded(child: ColoredBox(color: kGreen)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Container(
              constraints: BoxConstraints(minHeight: minPageHeight - 48),
              decoration: BoxDecoration(
                border: Border.all(color: kNavy, width: 2),
              ),
              padding: const EdgeInsets.all(4),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: kSaffron, width: 1.2),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(activeFontScale),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildPageContent(cur),
                          if ((extraPageRows[cur.id] ?? const <ExamExtraDetailRow>[])
                              .isNotEmpty)
                            _buildExtraPageRows(cur),
                        ],
                      ),
                    ),
                    if (cur.category != 'cover') _buildPageFooter(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageHeader(String title, {String? subtitle}) {
    return Column(
      children: [
        _movableEditableText(
          textKey: 'hdr_title_${activePageId}',
          defaultText: title,
          style: const TextStyle(
              color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
          customBuilder: (displayTitle) => Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kNavy, Color(0xFF143C82)]),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kSaffron, width: 2),
            ),
            child: Text(
              displayTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(bottom: 3),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: kSaffron, width: 2.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_schoolLogoBytes != null && _schoolLogoBytes!.isNotEmpty) ...[
                Transform.translate(
                  offset: headerLogoOffset,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: _PageDragDetector(
 pageKey: _a4PageCaptureKey,
 hideSelection: _capturingForPdf,

                      onTap: _pickCustomExamLogo,
                      onPanUpdate: (d) {
                        setState(() => headerLogoOffset += d.delta);
                        _scheduleExamDeviceAutoSave();
                      },
                      child: Image.memory(
                        _schoolLogoBytes!,
                        width: headerLogoSize,
                        height: headerLogoSize,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: _movableEditableText(
                  textKey: 'hdr_school_name',
                  defaultText: meta.schoolName,
                  onCustomSave: (v) => meta.schoolName = v,
                  style: const TextStyle(
                      color: kNavy, fontSize: 19, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        _movableEditableText(
          textKey: 'hdr_address',
          defaultText: meta.address,
          onCustomSave: (v) => meta.address = v,
          style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12.5,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 3),
        _movableEditableText(
          textKey: 'hdr_taluka_dist_exam',
          defaultText:
              'તાલુકો: ${meta.taluka}  |  જિલ્લો: ${meta.district}  |  ${meta.examName} ${meta.academicYear}',
          onCustomSave: (v) {
            customTextOverrides['hdr_taluka_dist_exam'] = v;
          },
          style: const TextStyle(
              color: kGreen, fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          _movableEditableText(
            textKey: 'hdr_sub_${activePageId}',
            defaultText: subtitle,
            style: const TextStyle(
                color: kNavy, fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildPageFooter() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.only(top: 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFC9D3E3))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: _movableEditableText(
              textKey: 'ftr_school_left',
              defaultText: meta.schoolName,
              onCustomSave: (v) => meta.schoolName = v,
              textAlign: TextAlign.left,
              style: const TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600),
            ),
          ),
          _movableEditableText(
            textKey: 'ftr_principal_sign_right',
            defaultText: 'આચાર્યની સહી / સિક્કો: ____________',
            textAlign: TextAlign.right,
            style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 11.5,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildPageContent(NavPageItem cur) {
    switch (cur.category) {
      case 'exam_setup':
        return _buildExamSetupPage();
      case 'cover':
        return _buildCoverPage();
      case 'index':
        return _buildIndexPage();
      case 'dashboard':
        return _buildDashboardPage();
      case 'teachers':
        return _buildTeachersPage(pageIdx: cur.subIndex);
      case 'committee':
        return _buildCommitteePage();
      case 'register':
        return _buildRegisterPage(pageIdx: cur.subIndex);
      case 'timetable':
        return _buildTimetablePage(pageIdx: cur.subIndex);
      case 'seat_a':
        return _buildSeatingPage('a', '૩ થી ૫', seatingA, pageIdx: cur.subIndex);
      case 'seat_b':
        return _buildSeatingPage('b', '૬ થી ૮', seatingB, pageIdx: cur.subIndex);
      case 'absent':
        return _buildAbsentPage(absentSheets[cur.subIndex]);
      case 'super_a':
        return _buildSupervisionPage(
          'a',
          '૩ થી ૫',
          supervisionA,
          _effectiveRowsPerPage(superRowsPerPageA, pageIdPrefix: 'sup_a'),
          cur.subIndex,
        );
      case 'super_b':
        return _buildSupervisionPage(
          'b',
          '૬ થી ૮',
          supervisionB,
          _effectiveRowsPerPage(superRowsPerPageB, pageIdPrefix: 'sup_b'),
          cur.subIndex,
        );
      case 'check_a':
        return _buildCheckingPage('a', '૩ થી ૫', cur.subIndex);
      case 'check_b':
        return _buildCheckingPage('b', '૬ થી ૮', cur.subIndex);
      case 'bundle':
        return _buildBundlePage(cur.subIndex);
      case 'door':
        return _buildDoorStickerPage(cur.subIndex);
      case 'qp_reg':
        return _buildQpRegisterPage(pageIdx: cur.subIndex);
      case 'stationery':
        return _buildStationeryPage(pageIdx: cur.subIndex);
      case 'instructions':
        return _buildInstructionsPage(pageIdx: cur.subIndex);
      default:
        return _buildCoverPage();
    }
  }

  void _renameRegisterRow(RegisterRow row, String value) {
    final oldName = row.className;
    row.className = value;
    for (final linked in allInsertedClassRows) {
      if (linked.className == oldName && linked.group == row.group) {
        linked.className = value;
      }
    }
    if (selectedExamClasses.remove(oldName)) selectedExamClasses.add(value);
    autoAllocateSeatingFromRegister(notify: false);
    _refreshDerivedPagesFromTimetable();
  }

  void _changeRegisterRowGroup(RegisterRow row, String group) {
    final oldGroup = row.group;
    row.group = group;
    for (final linked in allInsertedClassRows) {
      if (linked.className == row.className && linked.group == oldGroup) {
        linked.group = group;
      }
    }
    autoAllocateSeatingFromRegister(notify: false);
    _refreshDerivedPagesFromTimetable();
  }

  // 0. Exam Classes (3 to 5, 6 to 8, 3 to 8 + Selectable All Inserted Classes) & Selectable Subjects Setup Tab
  Widget _buildExamSetupPage() {
    final totalExamStudents =
        registerRows.fold<int>(0, (s, r) => s + r.total(genderMode));
    final genderBadgeText = genderMode == 'boys'
        ? 'ફક્ત કુમાર (Only Boys — Auto Set)'
        : genderMode == 'girls'
            ? 'ફક્ત કન્યા (Only Girls — Auto Set)'
            : 'કુમાર અને કન્યા બંને (B + G = T — Auto Set)';

    Widget rangeModeBtn(String modeKey, String title, String sub) {
      final isSelected = examClassRangeMode == modeKey;
      return InkWell(
        onTap: () => _applyExamClassRangePreset(modeKey, notify: true),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 215,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? kNavy : const Color(0xFFF4F7FD),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? kSaffron : const Color(0xFF93C5FD),
              width: isSelected ? 2.5 : 1.5,
            ),
          ),
          child: Column(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: isSelected ? Colors.white : kNavy,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                  color:
                      isSelected ? const Color(0xFFFFD599) : const Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPageHeader(
          '🎯 પરીક્ષા વર્ગો (3 થી 5, 6 થી 8, 3 થી 8) અને વિષય પસંદગી',
          subtitle:
              'શાળાનું નામ, સરનામું, શિક્ષકો, ભણાવતા વિષયો અને પરીક્ષાના વર્ગોની વિદ્યાર્થી સંખ્યા ડેટાબેઝમાંથી ઓટો-ફેચ થયેલ છે',
        ),

        // Auto-Fetched School & Database Summary Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(child: const Text(
                    '🏫 ડેટાબેઝમાંથી ઓટો-ફેચ થયેલ શાળા અને પરીક્ષા વિગત:',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: Color(0xFF065F46)),
                  )),
                  _miniToolBtn(
                    '⚡ ૧-ક્લિક બધા ૧૮ પત્રકો ઓટો-ફિલ',
                    kNavy,
                    () {
                      _syncExamSelectionToPatraks(rebuildTimetable: true);
                      runMasterAutoFill();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _infoPill('શાળા: ${meta.schoolName}', kNavy, Colors.white),
                  if (meta.address.isNotEmpty)
                    _infoPill('સરનામું: ${meta.address}',
                        const Color(0xFF1E40AF), Colors.white),
                  _infoPill(
                      'પરીક્ષા ડ્યુટી શિક્ષકો: ${_examDutyTeachers.length}', kGreen, Colors.white),
                  _infoPill(
                      'પરીક્ષા વર્ગો: ${registerRows.length} / ${allInsertedClassRows.length}',
                      kNavy,
                      Colors.white),
                  _infoPill('કુલ પરીક્ષાર્થી: $totalExamStudents', kRed,
                      Colors.white),
                  _infoPill(genderBadgeText, const Color(0xFF9A3412),
                      const Color(0xFFFFEDD5)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Block counts → automatic block-wise seating (editable later).
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFC7D2FE), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🪑 બ્લોક અને બેઠક વ્યવસ્થા — પહેલાં બધા વર્ગનો વિભાગ A, પછી B; દરેક બ્લોકમાં સરખા વિદ્યાર્થી (બેઠક પેજમાં સુધારી શકાય)',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: kNavy),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  if (registerRows.any((r) => r.group == 'a')) _blockCountStepper('a'),
                  if (registerRows.any((r) => r.group == 'b')) _blockCountStepper('b'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // PSM_EARLY_TEACHER_EXAM_FILTER_20261031_V2
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kSaffron, width: 1.4),
          ),
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            activeColor: kGreen,
            title: const Text(
              'શું બાલવાટિકા તથા ધોરણ ૧ અને ૨ ના શિક્ષકોને પરીક્ષા કામગીરીમાં સામેલ કરવા છે?',
              style: TextStyle(
                color: kNavy,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: Text(
              'ઓટો સુપરવિઝન, પેપર ચકાસણી અને પ્રશ્નપત્ર સાક્ષી માટે લાગુ પડશે. '
              'ડેટાબેઝમાં વર્ગ સાથે જોડાયેલા આવા શિક્ષકો: $_identifiedEarlyClassTeacherCount. '
              'વર્ગની કડી ન હોય તે શિક્ષકો હાલ સમાવેશમાં રહેશે.',
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
            ),
            value: includeBalvatikaAndStd12Teachers,
            onChanged: (value) {
              setState(() {
                includeBalvatikaAndStd12Teachers = value;
              });
              _syncExamSelectionToPatraks(rebuildTimetable: false);
              _showSnack(value
                  ? '✅ બાલવાટિકા અને ધોરણ ૧–૨ ના શિક્ષકો પરીક્ષા ડ્યુટીમાં સામેલ થશે.'
                  : '✅ બાલવાટિકા અને ધોરણ ૧–૨ ના ઓળખાયેલા શિક્ષકો ઓટો પરીક્ષા ડ્યુટીમાંથી બાકાત રહેશે.');
            },
          ),
        ),
        const SizedBox(height: 12),

        // Section 1: 3 to 5, 6 to 8, or 3 to 8 + All Inserted Classes Selectable
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kNavy, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '૧. કયા ધોરણનું પરીક્ષા આયોજન કરવું છે? (Select Exam Class Group: 3 to 5, 6 to 8, or 3 to 8)',
                style: TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 14.5, color: kNavy),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  rangeModeBtn(
                      '3to5', 'ધોરણ ૩ થી ૫ (3 to 5)', 'ફક્ત ધો. ૩ થી ૫ ના વર્ગો'),
                  rangeModeBtn(
                      '6to8', 'ધોરણ ૬ થી ૮ (6 to 8)', 'ફક્ત ધો. ૬ થી ૮ ના વર્ગો'),
                  rangeModeBtn(
                      '3to8', 'ધોરણ ૩ થી ૮ (3 to 8)', 'ધો. ૩ થી ૮ ના તમામ વર્ગો'),
                ],
              ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(child: Text(
                    '✅ શાળામાં દાખલ કરેલ તમામ વર્ગો (All Inserted Classes — પસંદ કરેલ: ${selectedExamClasses.length}/${allInsertedClassRows.length}):',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: kNavy),
                  )),
                  Wrap(
                    spacing: 6,
                    children: [
                      _miniToolBtn('બધા પસંદ કરો', kGreen, () {
                        setState(() {
                          examClassRangeMode = 'custom';
                          selectedExamClasses = allInsertedClassRows
                              .map((r) => r.className)
                              .toSet();
                          _syncExamSelectionToPatraks(rebuildTimetable: true);
                        });
                      }),
                      _miniToolBtn('ફક્ત ૩ થી ૮', kNavy,
                          () => _applyExamClassRangePreset('3to8')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: allInsertedClassRows.map((r) {
                  final isSelected = selectedExamClasses.contains(r.className);
                  final cnt = r.total(genderMode);
                  return FilterChip(
                    label: Text(
                      '${r.className} ($cnt વિદ્યાર્થી)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: isSelected ? Colors.white : kNavy,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: kNavy,
                    checkmarkColor: kSaffron,
                    backgroundColor: Colors.white,
                    onSelected: (val) {
                      setState(() {
                        examClassRangeMode = 'custom';
                        if (val) {
                          selectedExamClasses.add(r.className);
                        } else if (selectedExamClasses.length > 1) {
                          selectedExamClasses.remove(r.className);
                        } else {
                          _showSnack('ઓછામાં ઓછો ૧ વર્ગ પસંદ રાખવો જરૂરી છે.',
                              isError: true);
                        }
                        _syncExamSelectionToPatraks(rebuildTimetable: true);
                      });
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Section 2: Selectable Exam Subjects (Fetched from Database Taught Subjects)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFAF2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kSaffron, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '૨. કયા વિષયોની પરીક્ષા લેવાની છે? (Selectable Subjects — માત્ર પસંદ કરેલ વિષયો જ સમયપત્રક અને શિક્ષક વિષયમાં આવશે)',
                style: TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 14, color: kNavy),
              ),
              const SizedBox(height: 10),
              if (hasGroupA) ...[
                const Text(
                  '📘 ધોરણ ૩ થી ૫ ના પરીક્ષા વિષયો (Subjects for 3 to 5):',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Color(0xFF143C82)),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: allAvailableExamSubjects.map((sub) {
                    final sel = selectedSubjects35.contains(sub);
                    return FilterChip(
                      label: Text(
                        sub,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: sel ? Colors.white : kNavy,
                        ),
                      ),
                      selected: sel,
                      selectedColor: const Color(0xFF143C82),
                      checkmarkColor: Colors.amberAccent,
                      backgroundColor: Colors.white,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            selectedSubjects35.add(sub);
                          } else if (selectedSubjects35.length > 1) {
                            selectedSubjects35.remove(sub);
                          }
                          _syncExamSelectionToPatraks(rebuildTimetable: true);
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
              ],
              if (hasGroupB) ...[
                const Text(
                  '📗 ધોરણ ૬ થી ૮ ના પરીક્ષા વિષયો (Subjects for 6 to 8):',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: kGreen),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: allAvailableExamSubjects.map((sub) {
                    final sel = selectedSubjects68.contains(sub);
                    return FilterChip(
                      label: Text(
                        sub,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: sel ? Colors.white : kNavy,
                        ),
                      ),
                      selected: sel,
                      selectedColor: kGreen,
                      checkmarkColor: Colors.white,
                      backgroundColor: Colors.white,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            selectedSubjects68.add(sub);
                          } else if (selectedSubjects68.length > 1) {
                            selectedSubjects68.remove(sub);
                          }
                          _syncExamSelectionToPatraks(rebuildTimetable: true);
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Quick Preview of Auto-Filled Exam Classes & Student Counts
        const Text(
          '📊 પસંદ કરેલ પરીક્ષા વર્ગો અને ઓટો-ફિલ વિદ્યાર્થી સંખ્યા (Auto-Filled Exam Register Preview):',
          style: TextStyle(
              fontWeight: FontWeight.w900, fontSize: 13.5, color: kNavy),
        ),
        const SizedBox(height: 6),
        Table(
          border: TableBorder.all(color: kNavy, width: 1.2),
          children: [
            _tableHeaderRow(
              genderMode == 'boys'
                  ? ['ક્રમ', 'ધોરણ / વર્ગ', 'જૂથ', 'કુમાર સંખ્યા']
                  : genderMode == 'girls'
                      ? ['ક્રમ', 'ધોરણ / વર્ગ', 'જૂથ', 'કન્યા સંખ્યા']
                      : [
                          'ક્રમ',
                          'ધોરણ / વર્ગ',
                          'જૂથ',
                          'કુમાર',
                          'કન્યા',
                          'કુલ સંખ્યા'
                        ],
            ),
            for (int i = 0; i < registerRows.length; i++)
              TableRow(
                decoration: BoxDecoration(
                    color: i.isEven ? Colors.white : const Color(0xFFF4F7FD)),
                children: [
                  _cellText('${i + 1}', bold: true),
                  _editableCell(registerRows[i].className,
                      (value) => _renameRegisterRow(registerRows[i], value)),
                  _cellText(
                    registerRows[i].group == 'a' ? 'ધો. ૩ થી ૫' : 'ધો. ૬ થી ૮',
                    onChanged: (value) {
                      final normalized = value.toLowerCase();
                      _changeRegisterRowGroup(
                        registerRows[i],
                        normalized.contains('૬') || normalized.contains('6')
                            ? 'b'
                            : 'a',
                      );
                    },
                  ),
                  if (genderMode != 'girls')
                    _editableCell('${registerRows[i].boys}', (value) {
                      registerRows[i].boys = parseNum(value) ?? registerRows[i].boys;
                      registerRows[i].databaseTotal = null;
                    }),
                  if (genderMode != 'boys')
                    _editableCell('${registerRows[i].girls}', (value) {
                      registerRows[i].girls = parseNum(value) ?? registerRows[i].girls;
                      registerRows[i].databaseTotal = null;
                    }),
                  if (genderMode == 'both')
                    _cellText('${registerRows[i].total(genderMode)}',
                        bold: true, color: kGreen),
                ],
              ),
          ],
        ),
      ],
    );
  }

  // 1. Cover Page (Logo As Uploaded, Movable Logo & Movable/Editable All Texts)
  Widget _buildCoverPage() {
    final hasLogo = _schoolLogoBytes != null && _schoolLogoBytes!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _movableEditableText(
            textKey: 'cover_mangalacharan',
            defaultText: '॥ શ્રી ગણેશાય નમઃ ॥  •  તમસો મા જ્યોતિર્ગમય',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: kSaffron,
            ),
          ),
          const SizedBox(height: 12),
          Transform.translate(
            offset: coverLogoOffset,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: _PageDragDetector(
 pageKey: _a4PageCaptureKey,
 hideSelection: _capturingForPdf,

                behavior: HitTestBehavior.opaque,
                onTap: _pickCustomExamLogo,
                onPanUpdate: (details) {
                  setState(() {
                    coverLogoOffset += details.delta;
                  });
                  _scheduleExamDeviceAutoSave();
                },
                child: hasLogo
                    ? Image.memory(
                        _schoolLogoBytes!,
                        width: coverLogoSize,
                        height: coverLogoSize,
                        fit: BoxFit.contain,
                      )
                    : Container(
                        width: coverLogoSize,
                        height: coverLogoSize,
                        alignment: Alignment.center,
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_rounded,
                                size: 46, color: kNavy),
                            SizedBox(height: 4),
                            Text(
                              'શાળાનો લોગો (અપલોડ કરવા ક્લિક કરો / ડ્રેગ કરી ખસેડો)',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: kNavy,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          _movableEditableText(
            textKey: 'cover_main_heading',
            defaultText: 'પરીક્ષા આયોજન ફાઈલ',
            style: const TextStyle(
                fontSize: 38, fontWeight: FontWeight.w900, color: kNavy),
          ),
          const SizedBox(height: 6),
          _movableEditableText(
            textKey: 'cover_sub_heading',
            defaultText: 'સંપૂર્ણ ઓટોમેટિક પરીક્ષા સંચાલન અને રજીસ્ટર દસ્તાવેજ',
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F766E)),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: 360,
            height: 6,
            child: Row(
              children: const [
                Expanded(child: ColoredBox(color: kSaffron)),
                Expanded(child: ColoredBox(color: kNavy)),
                Expanded(child: ColoredBox(color: kGreen)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _editableCoverField('શાળાનું નામ', meta.schoolName, 26, kNavy,
              (v) => meta.schoolName = v,
              textKey: 'cover_school_name'),
          const SizedBox(height: 8),
          _editableCoverField('સરનામું', meta.address, 17,
              const Color(0xFF143C82), (v) => meta.address = v,
              textKey: 'cover_address'),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              _editableCoverField(
                  'તાલુકો',
                  'તાલુકો: ${meta.taluka}',
                  17,
                  const Color(0xFF143C82),
                  (v) => meta.taluka = v.replaceAll('તાલુકો:', '').trim(),
                  textKey: 'cover_taluka'),
              const Text('   |   ',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              _editableCoverField(
                  'જિલ્લો',
                  'જિલ્લો: ${meta.district}',
                  17,
                  const Color(0xFF143C82),
                  (v) => meta.district = v.replaceAll('જિલ્લો:', '').trim(),
                  textKey: 'cover_district'),
            ],
          ),
          const SizedBox(height: 22),
          _movableEditableText(
            textKey: 'cover_exam_name_pill',
            defaultText: meta.examName,
            onCustomSave: (v) => meta.examName = v,
            style: const TextStyle(
                fontSize: 25, fontWeight: FontWeight.w900, color: kNavy),
            customBuilder: (displayVal) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
                border: const Border.symmetric(
                    horizontal: BorderSide(color: kSaffron, width: 3)),
              ),
              child: Text(
                displayVal,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 25, fontWeight: FontWeight.w900, color: kNavy),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _movableEditableText(
            textKey: 'cover_academic_year_pill',
            defaultText: 'શૈક્ષણિક વર્ષ: ${meta.academicYear}',
            onCustomSave: (v) =>
                meta.academicYear = v.replaceAll('શૈક્ષણિક વર્ષ:', '').trim(),
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: kNavy),
            customBuilder: (displayVal) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE6EDFA),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Text(
                displayVal,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: kNavy),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _editableCoverField(
              'પગારકેન્દ્ર',
              'પગારકેન્દ્ર: ${meta.payCenter}',
              19,
              kGreen,
              (v) => meta.payCenter = v.replaceAll('પગારકેન્દ્ર:', '').trim(),
              textKey: 'cover_pay_center'),
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.only(top: 14),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFC9D3E3)))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: _editableCoverField(
                      'આચાર્યનું નામ',
                      'આચાર્યનું નામ: ${meta.principalName}',
                      15,
                      kNavy,
                      (v) => meta.principalName =
                          v.replaceAll('આચાર્યનું નામ:', '').trim(),
                      textKey: 'cover_principal'),
                ),
                Flexible(
                  child: _editableCoverField(
                      'સી.આર.સી. કો-ઓર્ડિનેટર',
                      'સી.આર.સી. કો-ઓર્ડિનેટર: ${meta.crcName}',
                      15,
                      kNavy,
                      (v) => meta.crcName =
                          v.replaceAll('સી.આર.સી. કો-ઓર્ડિનેટર:', '').trim(),
                      textKey: 'cover_crc'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _editableCoverField(
    String label,
    String text,
    double size,
    Color color,
    ValueChanged<String> onSave, {
    String? textKey,
  }) {
    final key = textKey ?? 'cover_fld_$label';
    final isLockedIdentity = _lockedSchoolIdentityKeys.contains(key);
    final offset = customTextOffsets[key] ?? Offset.zero;
    final display = isLockedIdentity ? text : (customTextOverrides[key] ?? text);
    return Transform.translate(
      offset: offset,
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: _PageDragDetector(
 pageKey: _a4PageCaptureKey,
 hideSelection: _capturingForPdf,

          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (isLockedIdentity) {
              final nextLang = schoolNameLang == 'gu' ? 'en' : 'gu';
              _setExamSchoolNameLanguage(nextLang);
              _showSnack(
                '🌐 શાળાનું નામ રજીસ્ટ્રેશન મુજબ લોક છે — ભાષા ${nextLang == "gu" ? "ગુજરાતી" : "English"} કરવામાં આવી!',
              );
              return;
            }
            _editMetaField(label, display, (v) {
              onSave(v);
              customTextOverrides[key] = v;
            });
          },
          onPanUpdate: (details) {
            setState(() {
              customTextOffsets[key] =
                  (customTextOffsets[key] ?? Offset.zero) + details.delta;
            });
            _scheduleExamDeviceAutoSave();
          },
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: 6,
                vertical: math.max(1.0, activeRowHeight / 3).toDouble()),
            child: Text(
              display,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: size, fontWeight: FontWeight.w800, color: color),
            ),
          ),
        ),
      ),
    );
  }

  String get _certificateStatement => certificateStatementOverride ??
      '📋 આયોજન પ્રમાણપત્ર: આથી પ્રમાણિત કરવામાં આવે છે કે ${meta.schoolName} (તા. ${meta.taluka}, જિ. ${meta.district}) ખાતે યોજાનાર ${meta.examName} (${meta.academicYear}) માટે ધોરણ ૩ થી ૮ ના કુલ ${gn(registerRows.length)} વર્ગોના કુલ ${gn(registerRows.fold<int>(0, (s, r) => s + r.total(genderMode)))} વિદ્યાર્થીઓ (કુમાર: ${gn(registerRows.fold<int>(0, (s, r) => s + r.boys))}, કન્યા: ${gn(registerRows.fold<int>(0, (s, r) => s + r.girls))}) માટે કુલ ${gn(blocksA + blocksB)} પરીક્ષા બ્લોકમાં બેઠક વ્યવસ્થા, ${gn(_examDutyTeachers.length)} શિક્ષકોનું નિરીક્ષણ રોસ્ટર, દૈનિક ગેરહાજર રિપોર્ટ, બંડલ સ્ટીકર તથા પેપર ચકાસણીનું સંપૂર્ણ આયોજન નિયમાનુસાર કરવામાં આવેલ છે.';

  // 2. Index & Certificate Page
  Widget _buildIndexPage() {
    final totalClasses = registerRows.length;
    final boysTotal = registerRows.fold<int>(0, (s, r) => s + r.boys);
    final girlsTotal = registerRows.fold<int>(0, (s, r) => s + r.girls);
    final totalStudents =
        registerRows.fold<int>(0, (s, r) => s + r.total(genderMode));
    final std35Total = registerRows
        .where((r) => r.group == 'a')
        .fold<int>(0, (s, r) => s + r.total(genderMode));
    final std68Total = registerRows
        .where((r) => r.group == 'b')
        .fold<int>(0, (s, r) => s + r.total(genderMode));
    final absCountA = absentSheets.where((s) => s.group == 'a').length;
    final absCountB = absentSheets.where((s) => s.group == 'b').length;

    final rows = [
      [
        '૧',
        'કવર પેજ (શાળા અને પરીક્ષાની મુખ્ય વિગત)',
        'ધોરણ ૩ થી ૮',
        'Portrait (P)',
        '૧ પેજ',
        '✓ તૈયાર',
        'cover'
      ],
      [
        '૨',
        'અનુક્રમણિકા અને આયોજન પ્રમાણપત્ર',
        'ધોરણ ૩ થી ૮',
        'Portrait (P)',
        '૧ પેજ',
        '✓ ઓટો-લિંક',
        'index'
      ],
      [
        '૩',
        'પરીક્ષા આયોજન — એક નજરે (આચાર્ય ડેશબોર્ડ)',
        'ધોરણ ૩ થી ૮',
        'Portrait (P)',
        '૧ પેજ',
        '$totalStudents વિદ્યાર્થી',
        'dashboard'
      ],
      [
        '૪',
        'શિક્ષક માહિતી અને ઓટો-સુપરવિઝન સેટઅપ',
        'ધોરણ ૩ થી ૮',
        'Portrait (P)',
        '૧ પેજ',
        '${_examDutyTeachers.length} શિક્ષકો',
        'teachers'
      ],
      [
        '૫',
        'પરીક્ષા સમિતિ અને કામગીરીની ફાળવણી',
        'ધોરણ ૩ થી ૮',
        'Portrait (P)',
        '૧ પેજ',
        '૮ સભ્યો / કામગીરી',
        'committee'
      ],
      [
        '૬',
        'ધોરણવાર રજીસ્ટર સંખ્યા પત્રક',
        'ધોરણ ૩ થી ૮',
        'Portrait (P)',
        '૧ પેજ',
        '$totalClasses વર્ગો ($totalStudents)',
        'register'
      ],
      [
        '૭',
        'પરીક્ષાનું વિસ્તૃત સમયપત્રક',
        'ધોરણ ૩ થી ૮',
        'Portrait (P)',
        '૧ પેજ',
        '${timetableRows.length} પેપર',
        'timetable'
      ],
      [
        '૮',
        'બ્લોકવાર બેઠક વ્યવસ્થા (ધોરણ ૩ થી ૫)',
        'ધોરણ ૩ થી ૫',
        'Portrait (P)',
        '૧ પેજ',
        '$blocksA બ્લોક ($std35Total)',
        'seat_a'
      ],
      [
        '૯',
        'બ્લોકવાર બેઠક વ્યવસ્થા (ધોરણ ૬ થી ૮)',
        'ધોરણ ૬ થી ૮',
        'Portrait (P)',
        '૧ પેજ',
        '$blocksB બ્લોક ($std68Total)',
        'seat_b'
      ],
      [
        '૧૦',
        'દૈનિક ગેરહાજર વિદ્યાર્થી રિપોર્ટ (૩ થી ૫)',
        'ધોરણ ૩ થી ૫',
        'Landscape (L)',
        '$absCountA પેજ',
        '✓ માત્ર ફાળવાયેલ સંખ્યા',
        'abs_0'
      ],
      [
        '૧૧',
        'દૈનિક ગેરહાજર વિદ્યાર્થી રિપોર્ટ (૬ થી ૮)',
        'ધોરણ ૬ થી ૮',
        'Landscape (L)',
        '$absCountB પેજ',
        '✓ માત્ર ફાળવાયેલ સંખ્યા',
        'abs_$absCountA'
      ],
      [
        '૧૨',
        'ખંડ નિરીક્ષણ (સુપરવિઝન) કાર્યનું આયોજન',
        'ધોરણ ૩ થી ૮',
        'Portrait (P)',
        '૨+ પેજ',
        '✓ ઓટો-ફાળવણી',
        'sup_a_0'
      ],
      [
        '૧૩',
        'ઉત્તરવહી (પેપર) ચકાસણી આયોજન પત્રક',
        'ધોરણ ૩ થી ૮',
        'Portrait (P)',
        '૨+ પેજ',
        '✓ પરીક્ષક ઓટો-ફિલ',
        'chk_a_0'
      ],
      [
        '૧૪',
        'ઉત્તરવહી બંડલ પર ચોંટાડવાના વર્ગવાર સ્ટીકર',
        'ધોરણ ૩ થી ૮',
        'Portrait (P)',
        '$totalClasses વર્ગ',
        '✓ રજીસ્ટર ઓટો-લિંક',
        'bun_0'
      ],
      [
        '૧૫',
        'ખંડ બહાર ચોંટાડવાના બ્લોક ડોર સ્ટીકર',
        'ધોરણ ૩ થી ૮',
        'Portrait (P)',
        '${blocksA + blocksB} બ્લોક',
        '✓ બેઠક ઓટો-લિંક',
        'door_0'
      ],
      [
        '૧૬',
        'પ્રશ્નપત્ર પેકેટ સીલ અને વિતરણ રજીસ્ટર',
        'ધોરણ ૩ થી ૮',
        'Portrait (P)',
        '૧ પેજ',
        '${timetableRows.length} પેપર હિસાબ',
        'qp_reg'
      ],
      [
        '૧૭',
        'ઉત્તરવહી અને સ્ટેશનરી જરૂરિયાત પત્રક',
        'ધોરણ ૩ થી ૮',
        'Portrait (P)',
        '૧ પેજ',
        '૫% અનામત સહિત',
        'stationery'
      ],
      [
        '૧૮',
        'પરીક્ષાલક્ષી અગત્યની સૂચનાઓ',
        'ધોરણ ૩ થી ૮',
        'Portrait (P)',
        '૧ પેજ',
        '૨૦ નિયમો',
        'instructions'
      ],
    ];

    return Column(
      children: [
        _buildPageHeader(
          'અનુક્રમણિકા અને પ્રમાણપત્ર',
          subtitle:
              'સંપૂર્ણ પરીક્ષા આયોજન ફાઈલની વિભાગવાર અનુક્રમણિકા (કોઈપણ હરોળ પર ક્લિક કરતા સીધું તે પેજ ખુલશે)',
        ),
        Table(
          border: TableBorder.all(color: kNavy, width: 1.2),
          columnWidths: const {
            0: FlexColumnWidth(0.8),
            1: FlexColumnWidth(3.8),
            2: FlexColumnWidth(1.4),
            3: FlexColumnWidth(1.3),
            4: FlexColumnWidth(1.6),
            5: FlexColumnWidth(1.8),
          },
          children: [
            _tableHeaderRow([
              'ક્રમ',
              'પત્રક / વિભાગનું નામ',
              'ધોરણ / જૂથ',
              'પેજ માપ',
              'વિગત / સંખ્યા',
              'ઓટો-સિંક સ્થિતિ',
            ]),
            for (int i = 0; i < rows.length; i++)
              TableRow(
                decoration: BoxDecoration(
                    color: i.isEven ? Colors.white : const Color(0xFFF4F7FD)),
                children: [
                  _cellText(
                    indexCellOverrides['$i:0'] ?? rows[i][0],
                    bold: true,
                    onSelectRow: () => setState(() => activePageId = rows[i][6]),
                    onChanged: (value) => indexCellOverrides['$i:0'] = value,
                  ),
                  _cellText(
                    indexCellOverrides['$i:1'] ?? rows[i][1],
                    align: TextAlign.left,
                    onSelectRow: () => setState(() => activePageId = rows[i][6]),
                    onChanged: (value) => indexCellOverrides['$i:1'] = value,
                  ),
                  _cellText(
                    indexCellOverrides['$i:2'] ?? rows[i][2],
                    onSelectRow: () => setState(() => activePageId = rows[i][6]),
                    onChanged: (value) => indexCellOverrides['$i:2'] = value,
                  ),
                  _cellText(
                    indexCellOverrides['$i:3'] ?? rows[i][3],
                    onSelectRow: () => setState(() => activePageId = rows[i][6]),
                    onChanged: (value) => indexCellOverrides['$i:3'] = value,
                  ),
                  _cellText(
                    indexCellOverrides['$i:4'] ?? rows[i][4],
                    onSelectRow: () => setState(() => activePageId = rows[i][6]),
                    onChanged: (value) => indexCellOverrides['$i:4'] = value,
                  ),
                  _cellText(
                    indexCellOverrides['$i:5'] ?? rows[i][5],
                    color: kGreen,
                    bold: true,
                    onSelectRow: () => setState(() => activePageId = rows[i][6]),
                    onChanged: (value) => indexCellOverrides['$i:5'] = value,
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFAF2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kNavy, width: 2),
          ),
          child: InkWell(
            onTap: () => _editMetaField(
              'આયોજન પ્રમાણપત્ર સુધારો',
              _certificateStatement,
              (value) => certificateStatementOverride = value,
              maxLines: 6,
            ),
            child: Text(
              _certificateStatement,
              style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B)),
            ),
          ),
        ),
      ],
    );
  }

  // 3. Executive Dashboard & Bell Schedule Page (Exact match to code_artifact.html)
  TableRow _buildDailyExamSummaryRow(String dtStr, int blkA, int blkB) {
    final dayExams = timetableRows.where((x) => x.date == dtStr).toList();
    final dayName = dayExams.isNotEmpty ? dayExams.first.day : '';
    final exA = dayExams.where((x) => x.group == 'a').firstOrNull;
    final exB = dayExams.where((x) => x.group == 'b').firstOrNull;
    final cntA = exA != null ? getStudentCountForExam('a', exA.stdLabel) : 0;
    final cntB = exB != null ? getStudentCountForExam('b', exB.stdLabel) : 0;
    final neededBlocks =
        (exA != null && hasGroupA ? blkA : 0) + (exB != null && hasGroupB ? blkB : 0);
    return TableRow(
      children: [
        _cellText(dtStr, bold: true, onChanged: (value) {
          for (final row in timetableRows.where((r) => r.date == dtStr)) {
            row.date = value;
          }
          _refreshDerivedPagesFromTimetable();
        }),
        _cellText(dayName, onChanged: (value) {
          for (final row in timetableRows.where((r) => r.date == dtStr)) {
            row.day = value;
          }
          _refreshDerivedPagesFromTimetable();
        }),
        _cellText(
          exA != null ? '${exA.subject} (ધો. ${exA.stdLabel}) — $cntA' : '—',
          onChanged: exA == null ? null : (value) => exA.subject = value,
        ),
        _cellText(
          exB != null ? '${exB.subject} (ધો. ${exB.stdLabel}) — $cntB' : '—',
          onChanged: exB == null ? null : (value) => exB.subject = value,
        ),
        _cellText('${cntA + cntB}', bold: true),
        _cellText('$neededBlocks બ્લોક'),
        _cellText('$neededBlocks નિરીક્ષક'),
      ],
    );
  }

  Widget _buildDashboardPage() {
    final totalClasses = registerRows.length;
    final boysTotal = registerRows.fold<int>(0, (s, r) => s + r.boys);
    final girlsTotal = registerRows.fold<int>(0, (s, r) => s + r.girls);
    final totalStudents =
        registerRows.fold<int>(0, (s, r) => s + r.total(genderMode));
    final std35Total = registerRows
        .where((r) => r.group == 'a')
        .fold<int>(0, (s, r) => s + r.total(genderMode));
    final std68Total = registerRows
        .where((r) => r.group == 'b')
        .fold<int>(0, (s, r) => s + r.total(genderMode));
    final uniqueDates = timetableRows.map((e) => e.date).toSet().toList();
    final totalBlocks = (hasGroupA ? blocksA : 0) + (hasGroupB ? blocksB : 0);

    int totalAnsSheets = 0;
    for (final r in registerRows) {
      if (_classHasAnswersInQuestionPaper(r.className)) continue;
      final subs = getSubjectsForClass(r.className, r.group);
      totalAnsSheets +=
          r.total(genderMode) * (subs.isNotEmpty ? subs.length : 5);
    }
    final totalAnsWithReserve = include5PercentReserveInStationery
        ? (totalAnsSheets * 1.05).ceil()
        : totalAnsSheets;

    final studentSubText = genderMode == 'boys'
        ? 'કુલ ${gn(totalClasses)} વર્ગો (કુમાર: ${gn(totalStudents)})'
        : genderMode == 'girls'
            ? 'કુલ ${gn(totalClasses)} વર્ગો (કન્યા: ${gn(totalStudents)})'
            : 'કુલ ${gn(totalClasses)} વર્ગો (કુમાર: ${gn(boysTotal)} | કન્યા: ${gn(girlsTotal)})';

    return Column(
      children: [
        _buildPageHeader(
          'પરીક્ષા આયોજન — એક નજરે (આચાર્ય ડેશબોર્ડ)',
          subtitle:
              'રજીસ્ટર, બેઠક વ્યવસ્થા, સમયપત્રક અને શિક્ષક માહિતી પરથી આપોઆપ તૈયાર થતો સંકલિત સારાંશ',
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _kpiCard(
                '🏫 કુલ વર્ગો અને વિદ્યાર્થીઓ',
                '${gn(totalStudents)} પરીક્ષાર્થી',
                studentSubText,
                kNavy),
            _kpiCard(
                '🪑 કુલ પરીક્ષા બ્લોક (ખંડ)',
                '${gn(totalBlocks)} બ્લોક',
                'ધો. ૩–૫: ${gn(hasGroupA ? blocksA : 0)} બ્લોક (${gn(std35Total)}) | ધો. ૬–૮: ${gn(hasGroupB ? blocksB : 0)} બ્લોક (${gn(std68Total)})',
                kSaffron),
            _kpiCard(
                '👨‍🏫 કુલ શિક્ષક અને સુપરવિઝન',
                '${gn(_examDutyTeachers.length)} શિક્ષકો',
                'વિષય-મુક્ત ઓટોમેટિક સુપરવિઝન રોસ્ટર',
                kGreen),
            _kpiCard(
                '🗓️ પરીક્ષા દિવસો અને પેપર',
                '${gn(uniqueDates.length)} દિવસ / ${gn(timetableRows.length)} પેપર',
                'ધો. ૩–૫ (11:00–1:00) | ધો. ૬–૮ (2:00–5:00)',
                kNavy),
            _kpiCard(
                '📦 કુલ ઉત્તરવહી બંડલ',
                '${gn(totalClasses)} વર્ગ બંડલ',
                'દરેક વર્ગ અને બ્લોકના સ્ટીકર તૈયાર',
                kSaffron),
            _kpiCard(
                '🧮 કુલ ઉત્તરવહી જરૂરિયાત',
                '${gn(totalAnsWithReserve)} નંગ',
                'મુખ્ય: ${gn(totalAnsSheets)} + ૫% અનામત જથ્થો',
                kGreen),
          ],
        ),
        const SizedBox(height: 12),
        const Text('તારીખવાર પરીક્ષા સંચાલન અને સંખ્યા સારાંશ',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: kNavy)),
        const SizedBox(height: 6),
        Table(
          border: TableBorder.all(color: kNavy, width: 1.2),
          children: [
            _tableHeaderRow([
              'તારીખ',
              'વાર',
              'ધોરણ ૩ થી ૫ (વિષય / સંખ્યા)',
              'ધોરણ ૬ થી ૮ (વિષય / સંખ્યા)',
              'દૈનિક કુલ પરીક્ષાર્થી',
              'જરૂરી બ્લોક',
              'જરૂરી નિરીક્ષક',
            ]),
            for (final dtStr in uniqueDates)
              _buildDailyExamSummaryRow(dtStr, blocksA, blocksB),
          ],
        ),
        const SizedBox(height: 12),
        const Text('પરીક્ષા સમય દરમિયાન બેલ (ઘંટ) વગાડવાનું સમયપત્રક',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: kNavy)),
        const SizedBox(height: 6),
        Table(
          border: TableBorder.all(color: kNavy, width: 1.2),
          columnWidths: const {
            0: FlexColumnWidth(0.7),
            1: FlexColumnWidth(2.8),
            2: FlexColumnWidth(1.6),
            3: FlexColumnWidth(1.6),
            4: FlexColumnWidth(2.0),
          },
          children: [
            _tableHeaderRow([
              'ક્રમ',
              'બેલનો પ્રકાર / સૂચના',
              'સવાર / બપોર પાળી (ધો. ૩ થી ૫)',
              'બપોર પાળી (ધો. ૬ થી ૮)',
              'નોંધ / સૂચના'
            ]),
            for (int i = 0; i < bellScheduleRows.length; i++)
              TableRow(
                children: [
                  for (int j = 0; j < 5; j++)
                    _editableCell(bellScheduleRows[i][j],
                        (v) => setState(() => bellScheduleRows[i][j] = v)),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _kpiCard(String label, String value, String sub, Color accent) {
    return Container(
      width: 235,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: accent, width: 5)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF475569))),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w900, color: kNavy)),
          Text(sub,
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E40AF))),
        ],
      ),
    );
  }

  // Progressive side-by-side subject dropdown chain (Exact match to code_artifact.html .subject-chain)
  Widget _buildProgressiveSubjectChain(
      TeacherRecord teacher, List<String> allowedSubjects) {
    final currentSubs = teacher.subjects
        .where((s) => allowedSubjects.contains(s))
        .toList();
    final maxSlots = math.max(1, allowedSubjects.length);
    final slotCount = math.min(maxSlots, currentSubs.length + 1);

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: List.generate(slotCount, (slotIdx) {
        final curVal = slotIdx < currentSubs.length
            ? currentSubs[slotIdx]
            : (slotIdx > 0 ? '__NONE__' : '');
        final usedByOthers = <String>{
          for (int j = 0; j < currentSubs.length; j++)
            if (j != slotIdx) currentSubs[j],
        };
        final availableForSlot = allowedSubjects
            .where((s) => s == curVal || !usedByOthers.contains(s))
            .toList();

        return Container(
          height: (30 + (activeRowHeight - 6) * 2).clamp(22.0, 54.0).toDouble(),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: kNavy, width: 1.4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: (curVal.isEmpty ||
                      curVal == '__NONE__' ||
                      availableForSlot.contains(curVal))
                  ? curVal
                  : '',
              isDense: true,
              style: const TextStyle(
                color: kNavy,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              items: [
                if (slotIdx == 0)
                  const DropdownMenuItem(
                    value: '',
                    child: Text('-- વિષય પસંદ કરો --'),
                  )
                else
                  const DropdownMenuItem(
                    value: '__NONE__',
                    child: Text('કોઈ નહીં'),
                  ),
                for (final s in availableForSlot)
                  DropdownMenuItem(
                    value: s,
                    child: Text(s),
                  ),
              ],
              onChanged: (val) {
                if (val == null) return;
                setState(() {
                  final updated = List<String>.from(currentSubs);
                  if (val.isEmpty || val == '__NONE__') {
                    if (slotIdx < updated.length) {
                      updated.removeRange(slotIdx, updated.length);
                    }
                  } else {
                    if (slotIdx < updated.length) {
                      updated[slotIdx] = val;
                    } else {
                      updated.add(val);
                    }
                  }
                  final seen = <String>{};
                  teacher.subjects =
                      updated.where((x) => seen.add(x)).toList();
                  _dbTeacherRawSubjects[teacher.name] =
                      List<String>.from(teacher.subjects);
                });
                generateSupervision(notify: false);
                rebuildCheckingRows(notify: false);
                _scheduleExamDeviceAutoSave();
              },
            ),
          ),
        );
      }),
    );
  }

  // 4. Teacher Information & Auto-Supervision Setup Page
  Widget _buildTeachersPage({int pageIdx = 0}) {
    final allSubjects = activeSelectedSubjects;
    final dutyTeachers = _examDutyTeachers;
    final perPage = _effectiveRowsPerPage(26, pageIdPrefix: 'teachers');
    final totalPages = (dutyTeachers.length / perPage).ceil().clamp(1, 99);
    final chunk = dutyTeachers.skip(pageIdx * perPage).take(perPage).toList();
    final excludedCount = teachers.length - dutyTeachers.length;

    return Column(
      children: [
        _buildPageHeader(
          'શિક્ષક માહિતી અને ઓટો સુપરવિઝન',
          subtitle:
              'સમયપત્રકના વિષય પ્રમાણે બ્લોકવાર નિરીક્ષક, સમિતિ અને પેપર ચકાસણીની આપમેળે ફાળવણી${totalPages > 1 ? " (પેજ ${pageIdx + 1} / $totalPages)" : ""}',
        ),
        if (excludedCount > 0)
          const SizedBox.shrink(),
        Table(
          border: TableBorder.all(color: kNavy, width: 1.2),
          columnWidths: const {
            0: FlexColumnWidth(0.7),
            1: FlexColumnWidth(2.6),
            2: FlexColumnWidth(1.3),
            3: FlexColumnWidth(4.0),
          },
          children: [
            _tableHeaderRow([
              'ક્રમ',
              'શિક્ષકનું નામ',
              'ભણાવતું જૂથ',
              'ભણાવેલા વિષયો (ક્લિક કરી ઉમેરો/કાઢો)'
            ]),
            for (int localIdx = 0; localIdx < chunk.length; localIdx++)
              (() {
                final t = chunk[localIdx];
                final globalIdx = teachers.indexOf(t);
                final displayNo = (pageIdx * perPage) + localIdx + 1;
                final isSel = _selectedRowSection == 'teachers' &&
                    _selectedRowIndex == globalIdx;
                return TableRow(
                  decoration: BoxDecoration(
                    color: isSel
                        ? const Color(0xFFFEF08A)
                        : (localIdx.isEven
                            ? Colors.white
                            : const Color(0xFFF4F7FD)),
                  ),
                  children: [
                    _cellText(
                      '$displayNo',
                      bold: true,
                      onSelectRow: () => _markRowSelected(
                          section: 'teachers', index: globalIdx),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _editableCell(
                          t.name,
                          (v) => setState(() => t.name = v),
                          onSelectRow: () => _markRowSelected(
                              section: 'teachers', index: globalIdx),
                        ),
                        if (t.assignedClasses.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(
                                left: 6, right: 6, bottom: 4),
                            child: Text(
                              '🏫 વર્ગ: ${t.assignedClasses.join(", ")}',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF065F46),
                              ),
                            ),
                          ),
                      ],
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 4, vertical: activeRowHeight / 2),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: t.group,
                          isDense: true,
                          items: const [
                            DropdownMenuItem(value: 'a', child: Text('૩ થી ૫')),
                            DropdownMenuItem(value: 'b', child: Text('૬ થી ૮')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              _markRowSelected(
                                  section: 'teachers', index: globalIdx);
                              setState(() => t.group = v);
                              _scheduleExamDeviceAutoSave();
                            }
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(
                          math.max(1.0, activeRowHeight / 2).toDouble()),
                      child: _buildProgressiveSubjectChain(t, allSubjects),
                    ),
                  ],
                );
              })(),
          ],
        ),
      ],
    );
  }

  // 5. Committee & Work Duties Page (Excludes Balvatika and Class 1 & 2 teachers when not included in exam)
  Widget _buildCommitteePage() {
    final teacherNames = <String>{
      if (meta.principalName.trim().isNotEmpty &&
          meta.principalName != '________')
        meta.principalName.trim(),
      ..._examDutyTeachers.map((t) => t.name).where((n) => n.isNotEmpty),
    }.toList();
    return Column(
      children: [
        _buildPageHeader('પરીક્ષા સમિતિ'),
        Table(
          border: TableBorder.all(color: kNavy, width: 1.2),
          columnWidths: const {
            0: FlexColumnWidth(0.8),
            1: FlexColumnWidth(3.0),
            2: FlexColumnWidth(2.6),
            3: FlexColumnWidth(1.8),
          },
          children: [
            _tableHeaderRow(['અ.નં.', 'શિક્ષકનું નામ', 'હોદ્દો', 'સહી']),
            for (int i = 0; i < committeeRows.length; i++)
              TableRow(
                decoration: BoxDecoration(
                  color: (_selectedRowSection == 'committee' &&
                          _selectedRowIndex == i)
                      ? const Color(0xFFFEF08A)
                      : Colors.white,
                ),
                children: [
                  _cellText(
                    '${i + 1}',
                    onSelectRow: () =>
                        _markRowSelected(section: 'committee', index: i),
                  ),
                  _teacherDropdownCell(
                    committeeRows[i].teacherName,
                    teacherNames,
                    (v) {
                      _markRowSelected(section: 'committee', index: i);
                      setState(() => committeeRows[i].teacherName = v);
                    },
                  ),
                  _editableCell(
                    committeeRows[i].roleOrDuty,
                    (v) => setState(() => committeeRows[i].roleOrDuty = v),
                    onSelectRow: () =>
                        _markRowSelected(section: 'committee', index: i),
                  ),
                  _editableCell(
                    committeeRows[i].sign,
                    (v) => setState(() => committeeRows[i].sign = v),
                    onSelectRow: () =>
                        _markRowSelected(section: 'committee', index: i),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('પરીક્ષાલક્ષી કામગીરીની ફાળવણી',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800, color: kNavy)),
        const SizedBox(height: 6),
        Table(
          border: TableBorder.all(color: kNavy, width: 1.2),
          columnWidths: const {
            0: FlexColumnWidth(0.8),
            1: FlexColumnWidth(3.0),
            2: FlexColumnWidth(2.6),
            3: FlexColumnWidth(1.8),
          },
          children: [
            _tableHeaderRow(
                ['અ.નં.', 'શિક્ષકનું નામ', 'સોંપેલ કામગીરી', 'સહી']),
            for (int i = 0; i < workDutyRows.length; i++)
              TableRow(
                decoration: BoxDecoration(
                  color: (_selectedRowSection == 'work_duty' &&
                          _selectedRowIndex == i)
                      ? const Color(0xFFFEF08A)
                      : Colors.white,
                ),
                children: [
                  _cellText(
                    '${i + 1}',
                    onSelectRow: () =>
                        _markRowSelected(section: 'work_duty', index: i),
                  ),
                  _teacherDropdownCell(
                    workDutyRows[i].teacherName,
                    teacherNames,
                    (v) {
                      _markRowSelected(section: 'work_duty', index: i);
                      setState(() => workDutyRows[i].teacherName = v);
                    },
                  ),
                  _editableCell(
                    workDutyRows[i].roleOrDuty,
                    (v) => setState(() => workDutyRows[i].roleOrDuty = v),
                    onSelectRow: () =>
                        _markRowSelected(section: 'work_duty', index: i),
                  ),
                  _editableCell(
                    workDutyRows[i].sign,
                    (v) => setState(() => workDutyRows[i].sign = v),
                    onSelectRow: () =>
                        _markRowSelected(section: 'work_duty', index: i),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _teacherDropdownCell(
      String currentVal, List<String> names, ValueChanged<String> onChanged) {
    final options = ['', ...names];
    if (currentVal.isNotEmpty && !options.contains(currentVal)) {
      options.add(currentVal);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentVal,
          isExpanded: true,
          isDense: true,
          items: options
              .map((n) => DropdownMenuItem(
                  value: n,
                  child: Text(n.isEmpty ? 'શિક્ષક પસંદ કરો' : n,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600))))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  // 6. Standard-wise Register Page
  Widget _buildRegisterPage({int pageIdx = 0}) {
    final rowsA = registerRows.where((r) => r.group == 'a').toList();
    final rowsB = registerRows.where((r) => r.group == 'b').toList();
    final boysA = rowsA.fold<int>(0, (s, r) => s + r.boys);
    final girlsA = rowsA.fold<int>(0, (s, r) => s + r.girls);
    final totA = rowsA.fold<int>(0, (s, r) => s + r.total(genderMode));
    final boysB = rowsB.fold<int>(0, (s, r) => s + r.boys);
    final girlsB = rowsB.fold<int>(0, (s, r) => s + r.girls);
    final totB = rowsB.fold<int>(0, (s, r) => s + r.total(genderMode));

    final isBoysOnly = genderMode == 'boys';
    final isGirlsOnly = genderMode == 'girls';

    final headers = isBoysOnly
        ? ['ધોરણ', 'કુમાર', 'વર્ગ શિક્ષકની સહી', 'રીમાર્કસ']
        : isGirlsOnly
            ? ['ધોરણ', 'કન્યા', 'વર્ગ શિક્ષકની સહી', 'રીમાર્કસ']
            : [
                'ધોરણ',
                'કુમાર',
                'કન્યા',
                'કુલ',
                'વર્ગ શિક્ષકની સહી',
                'રીમાર્કસ'
              ];

    List<String> buildTotalCells(String label, int bSum, int gSum, int tSum) {
      if (isBoysOnly) return [label, '$tSum', '', ''];
      if (isGirlsOnly) return [label, '$tSum', '', ''];
      return [label, '$bSum', '$gSum', '$tSum', '', ''];
    }

    final modeSubtitle = isBoysOnly
        ? 'શાળા પ્રકાર: ફક્ત કુમાર (Only Boys)'
        : isGirlsOnly
            ? 'શાળા પ્રકાર: ફક્ત કન્યા (Only Girls)'
            : 'શાળા પ્રકાર: કુમાર અને કન્યા બંને (Boys + Girls = Total)';

    final allRegTableRows = <TableRow>[
      if (rowsA.isNotEmpty) ...[
        for (final r in rowsA) _registerTableRow(r),
        _totalRow(buildTotalCells('૩ થી ૫ કુલ', boysA, girlsA, totA)),
      ],
      if (rowsB.isNotEmpty) ...[
        for (final r in rowsB) _registerTableRow(r),
        _totalRow(buildTotalCells('૬ થી ૮ કુલ', boysB, girlsB, totB)),
      ],
      _totalRow(buildTotalCells(
        'એકંદર કુલ',
        boysA + boysB,
        girlsA + girlsB,
        totA + totB,
      )),
    ];
    final perPage = _effectiveRowsPerPage(27, pageIdPrefix: 'register');
    final totalPages = (allRegTableRows.length / perPage).ceil().clamp(1, 99);
    final chunkRows =
        allRegTableRows.skip(pageIdx * perPage).take(perPage).toList();

    return Column(
      children: [
        _buildPageHeader(
          'ધોરણવાર રજીસ્ટર સંખ્યા',
          subtitle: totalPages > 1
              ? '$modeSubtitle — પેજ ${pageIdx + 1} / $totalPages'
              : modeSubtitle,
        ),
        Table(
          border: TableBorder.all(color: kNavy, width: 1.2),
          children: [
            _tableHeaderRow(headers),
            ...chunkRows,
          ],
        ),
      ],
    );
  }

  TableRow _registerTableRow(RegisterRow r) {
    final isBoysOnly = genderMode == 'boys';
    final isGirlsOnly = genderMode == 'girls';
    final idx = registerRows.indexOf(r);
    final isSel = _selectedRowSection == 'register' && _selectedRowIndex == idx;
    void sel() => _markRowSelected(section: 'register', index: idx);

    return TableRow(
      decoration: BoxDecoration(
        color: isSel ? const Color(0xFFFEF08A) : Colors.white,
      ),
      children: [
        _editableCell(r.className, (v) => _renameRegisterRow(r, v),
            onSelectRow: sel),
        if (isBoysOnly)
          _editableCell(r.total(genderMode).toString(), (v) {
            setState(() {
              r.boys = parseNum(v) ?? 0;
              r.girls = 0;
              r.databaseTotal = null;
            });
            autoAllocateSeatingFromRegister(notify: false);
            _refreshDerivedPagesFromTimetable();
            _scheduleExamDeviceAutoSave();
          }, onSelectRow: sel)
        else if (isGirlsOnly)
          _editableCell(r.total(genderMode).toString(), (v) {
            setState(() {
              r.girls = parseNum(v) ?? 0;
              r.boys = 0;
              r.databaseTotal = null;
            });
            autoAllocateSeatingFromRegister(notify: false);
            _refreshDerivedPagesFromTimetable();
            _scheduleExamDeviceAutoSave();
          }, onSelectRow: sel)
        else ...[
          _editableCell(r.boys.toString(), (v) {
            setState(() {
              r.boys = parseNum(v) ?? 0;
              r.databaseTotal = null;
            });
            autoAllocateSeatingFromRegister(notify: false);
            _refreshDerivedPagesFromTimetable();
            _scheduleExamDeviceAutoSave();
          }, onSelectRow: sel),
          _editableCell(r.girls.toString(), (v) {
            setState(() {
              r.girls = parseNum(v) ?? 0;
              r.databaseTotal = null;
            });
            autoAllocateSeatingFromRegister(notify: false);
            _refreshDerivedPagesFromTimetable();
            _scheduleExamDeviceAutoSave();
          }, onSelectRow: sel),
          _cellText('${r.total(genderMode)}', bold: true, onSelectRow: sel),
        ],
        _editableCell(r.teacherSign, (v) => setState(() => r.teacherSign = v),
            onSelectRow: sel),
        _editableCell(r.remarks, (v) => setState(() => r.remarks = v),
            onSelectRow: sel),
      ],
    );
  }

  // 7. Timetable Page (Full Multi-Standard Selection up to All Options)
  void _refreshDerivedPagesFromTimetable() {
    rebuildAbsentPages(notify: false);
    generateSupervision(notify: false);
    rebuildCheckingRows(notify: false);
    rebuildBundles(notify: false);
    rebuildQpRegister(notify: false);
    rebuildStationerySheet();
  }

  String _formatGradesSetToGujaratiLabel(Set<int> grades) {
    if (grades.isEmpty) return '૩ થી ૮';
    final sorted = grades.toList()..sort();
    if (sorted.length == 6 && sorted.first == 3 && sorted.last == 8) {
      return '૩ થી ૮';
    }
    if (sorted.length == 3 && sorted.first == 3 && sorted.last == 5) {
      return '૩ થી ૫';
    }
    if (sorted.length == 3 && sorted.first == 6 && sorted.last == 8) {
      return '૬ થી ૮';
    }
    if (sorted.length == 8 && sorted.first == 1 && sorted.last == 8) {
      return '૧ થી ૮';
    }
    final has678 =
        grades.contains(6) && grades.contains(7) && grades.contains(8);
    final lower = sorted.where((g) => g < 6).toList();
    if (has678 && lower.isNotEmpty && grades.length == lower.length + 3) {
      if (lower.length == 3 && lower.first == 3 && lower.last == 5) {
        return '૩ થી ૮';
      }
      return '${lower.map(gn).join(", ")} અને ૬ થી ૮';
    }
    return sorted.map(gn).join(', ');
  }

  Future<void> _showMultiStandardPickerDialog(TimetableRow row) async {
    final selectedGrades = TimetableRow.parseGrades(row.stdLabel).toSet();
    if (selectedGrades.isEmpty) {
      selectedGrades.addAll(<int>[3, 4, 5]);
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text(
            '☑️ સમયપત્રક માટે ધોરણ પસંદ કરો (બધા જ વિકલ્પો / Multi-Select)',
            style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: 15.5, color: kNavy),
          ),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'એક અથવા વધુ ધોરણ પસંદ કરો (દા.ત. ધોરણ ૩ અને ૬ થી ૮):',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF334155)),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in <(String, Set<int>)>[
                      ('ધો. ૩ થી ૫', <int>{3, 4, 5}),
                      ('ધો. ૬ થી ૮', <int>{6, 7, 8}),
                      ('ધો. ૩ થી ૮ (બધા)', <int>{3, 4, 5, 6, 7, 8}),
                      ('ધો. ૩ અને ૬ થી ૮', <int>{3, 6, 7, 8}),
                      ('ધો. ૪ અને ૬ થી ૮', <int>{4, 6, 7, 8}),
                      ('ધો. ૫ અને ૬ થી ૮', <int>{5, 6, 7, 8}),
                      ('ધો. ૪ થી ૫', <int>{4, 5}),
                      ('ધો. ૧ થી ૮', <int>{1, 2, 3, 4, 5, 6, 7, 8}),
                    ])
                      ActionChip(
                        backgroundColor: const Color(0xFFEEF2FF),
                        label: Text(
                          preset.$1,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: kNavy),
                        ),
                        onPressed: () {
                          setDialogState(() {
                            selectedGrades
                              ..clear()
                              ..addAll(preset.$2);
                          });
                        },
                      ),
                  ],
                ),
                const Divider(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(8, (idx) {
                    final std = idx + 1;
                    final isChecked = selectedGrades.contains(std);
                    return FilterChip(
                      label: Text(
                        'ધોરણ ${gn(std)} ($std)',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: isChecked ? Colors.white : kNavy,
                        ),
                      ),
                      selected: isChecked,
                      selectedColor: kNavy,
                      checkmarkColor: kSaffron,
                      onSelected: (v) {
                        setDialogState(() {
                          if (v) {
                            selectedGrades.add(std);
                          } else if (selectedGrades.length > 1) {
                            selectedGrades.remove(std);
                          }
                        });
                      },
                    );
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('રદ કરો'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kGreen),
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  row.stdLabel = _formatGradesSetToGujaratiLabel(selectedGrades);
                });
                _refreshDerivedPagesFromTimetable();
                _scheduleExamDeviceAutoSave();
              },
              icon: const Icon(Icons.check, size: 18),
              label: const Text('લાગુ કરો'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _standardEditableCell(TimetableRow row, {VoidCallback? onSelectRow}) {
    final configured = widget.databaseData['standardOptions'];
    final options = <String>{
      '૧',
      '૨',
      '૩',
      '૪',
      '૫',
      '૬',
      '૭',
      '૮',
      '૩ થી ૫',
      '૬ થી ૮',
      '૩ થી ૮',
      '૩ અને ૬ થી ૮',
      '૪ અને ૬ થી ૮',
      '૫ અને ૬ થી ૮',
      '૪ થી ૫',
      '૩ થી ૪',
      '૬ થી ૭',
      '૭ થી ૮',
      '૧ થી ૫',
      '૧ થી ૮',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '3 થી 5',
      '6 થી 8',
      '3 થી 8',
      ...allInsertedClassRows.map((r) => r.className.trim()).where((s) => s.isNotEmpty),
      if (configured is List)
        ...configured
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty),
    }.toList();
    final current = row.stdLabel.trim();
    if (current.isNotEmpty && !options.contains(current)) options.add(current);
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: 3, vertical: math.max(1.0, activeRowHeight / 3).toDouble()),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                isDense: true,
                value: current.isNotEmpty && options.contains(current)
                    ? current
                    : null,
                hint: Text(current.isEmpty ? 'ધોરણ' : current,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: kNavy)),
                items: options
                    .map((value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(value,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700)),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  if (onSelectRow != null) onSelectRow();
                  setState(() => row.stdLabel = value);
                  _refreshDerivedPagesFromTimetable();
                  _scheduleExamDeviceAutoSave();
                },
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            tooltip: 'બહુવિધ ધોરણ પસંદ કરો (દા.ત. ૩ અને ૬ થી ૮)',
            icon: const Icon(Icons.checklist_rtl_rounded,
                size: 15, color: kGreen),
            onPressed: () {
              if (onSelectRow != null) onSelectRow();
              _showMultiStandardPickerDialog(row);
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            tooltip: 'અન્ય ધોરણ લખો',
            icon: const Icon(Icons.edit_outlined, size: 14),
            onPressed: () async {
              if (onSelectRow != null) onSelectRow();
              await _editMetaField('ધોરણ સુધારો', row.stdLabel, (value) {
                setState(() => row.stdLabel = value);
              });
              if (mounted) _refreshDerivedPagesFromTimetable();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTimetablePage({int pageIdx = 0}) {
    final perPage = _effectiveRowsPerPage(27, pageIdPrefix: 'timetable');
    final totalPages = (timetableRows.length / perPage).ceil().clamp(1, 99);
    final chunk = timetableRows.skip(pageIdx * perPage).take(perPage).toList();

    return Column(
      children: [
        _buildPageHeader(
          'ધોરણ ૩ થી ૮ (સમયપત્રક)',
          subtitle: totalPages > 1 ? 'પેજ ${pageIdx + 1} / $totalPages' : null,
        ),
        Table(
          border: TableBorder.all(color: kNavy, width: 1.2),
          children: [
            _tableHeaderRow(['તારીખ', 'વાર', 'ધોરણ', 'વિષય', 'સમય', 'ગુણ']),
            for (int localIdx = 0; localIdx < chunk.length; localIdx++)
              (() {
                final r = chunk[localIdx];
                final i = timetableRows.indexOf(r);
                final isSel =
                    _selectedRowSection == 'timetable' && _selectedRowIndex == i;
                void sel() => _markRowSelected(section: 'timetable', index: i);
                return TableRow(
                  decoration: BoxDecoration(
                    color: isSel
                        ? const Color(0xFFFEF08A)
                        : (localIdx.isEven
                            ? Colors.white
                            : const Color(0xFFF4F7FD)),
                  ),
                  children: [
                    _editableCell(r.date, (v) {
                      setState(() {
                        r.date = v;
                        final parts = v.split(RegExp(r'[/\-.]'));
                        if (parts.length == 3) {
                          final d = int.tryParse(parts[0]);
                          final m = int.tryParse(parts[1]);
                          final y = int.tryParse(parts[2]);
                          if (d != null && m != null && y != null && y > 2000) {
                            final dt = DateTime(y, m, d);
                            const days = [
                              'સોમવાર',
                              'મંગળવાર',
                              'બુધવાર',
                              'ગુરુવાર',
                              'શુક્રવાર',
                              'શનિવાર',
                              'રવિવાર'
                            ];
                            r.day = days[dt.weekday - 1];
                          }
                        }
                      });
                      _refreshDerivedPagesFromTimetable();
                    }, onSelectRow: sel),
                    _editableCell(r.day, (v) {
                      setState(() => r.day = v);
                      _refreshDerivedPagesFromTimetable();
                    }, onSelectRow: sel),
                    _standardEditableCell(r, onSelectRow: sel),
                    _editableCell(r.subject, (v) {
                      setState(() => r.subject = v);
                      _refreshDerivedPagesFromTimetable();
                    }, onSelectRow: sel),
                    _editableCell(r.time, (v) {
                      setState(() => r.time = v);
                      _refreshDerivedPagesFromTimetable();
                    }, onSelectRow: sel),
                    _editableCell(r.marks, (v) {
                      setState(() => r.marks = v);
                      _refreshDerivedPagesFromTimetable();
                    }, onSelectRow: sel),
                  ],
                );
              })(),
          ],
        ),
      ],
    );
  }

  // 8-9. Seating Arrangement Page (With Block-wise & Grand Total Auto-Formula + Selected Row Add/Delete)
  Widget _buildSeatingPage(String g, String label, List<SeatingRow> rows,
      {int pageIdx = 0}) {
    final nb = g == 'a' ? blocksA : blocksB;
    final secKey = g == 'a' ? 'seat_a' : 'seat_b';
    final tableRows = <TableRow>[
      _tableHeaderRow(['બ્લોક', 'ધોરણ', 'ક્રમ', '', 'ક્રમ', 'કુલ', 'રીમાર્કસ']),
    ];

    int grandTotal = 0;
    for (int b = 1; b <= nb; b++) {
      final bRows = rows.where((r) => r.blockNo == b).toList();
      int blockSum = 0;
      for (int i = 0; i < bRows.length; i++) {
        final r = bRows[i];
        final globalIdx = rows.indexOf(r);
        final isSel = _selectedRowSection == secKey &&
            _selectedRowIndex == globalIdx;
        void sel() => _markRowSelected(
            section: secKey, index: globalIdx, blockNo: b);

        final rowCnt = parseNum(r.totalCount) ??
            (() {
              final f = parseNum(r.fromRoll);
              final t = parseNum(r.toRoll);
              return (f != null && t != null && t >= f) ? (t - f + 1) : 0;
            })();
        blockSum += rowCnt;
        grandTotal += rowCnt;

        tableRows.add(TableRow(
          decoration: BoxDecoration(
            color: isSel
                ? const Color(0xFFFEF08A)
                : (b.isOdd ? const Color(0xFFEAF0FB) : Colors.white),
          ),
          children: [
            _cellText(
              i == 0 ? '$b' : '',
              bold: true,
              onSelectRow: sel,
              onChanged: i == 0
                  ? (value) {
                      final parsed = parseNum(value);
                      if (parsed != null && parsed > 0) {
                        for (final item in rows.where((x) => x.blockNo == b)) {
                          item.blockNo = parsed;
                        }
                      }
                    }
                  : null,
            ),
            _editableCell(
              r.className,
              (v) {
                setState(() => r.className = v);
                syncAllottedFromSeating();
              },
              onSelectRow: sel,
            ),
            _editableCell(r.fromRoll, (v) {
              setState(() {
                r.fromRoll = v;
                final f = parseNum(r.fromRoll);
                final t = parseNum(r.toRoll);
                if (f != null && t != null && t >= f) {
                  r.totalCount = '${t - f + 1}';
                }
              });
              syncAllottedFromSeating();
            }, onSelectRow: sel),
            _cellText('થી', onSelectRow: sel),
            _editableCell(r.toRoll, (v) {
              setState(() {
                r.toRoll = v;
                final f = parseNum(r.fromRoll);
                final t = parseNum(r.toRoll);
                if (f != null && t != null && t >= f) {
                  r.totalCount = '${t - f + 1}';
                }
              });
              syncAllottedFromSeating();
            }, onSelectRow: sel),
            _editableCell(r.totalCount, (v) {
              setState(() => r.totalCount = v);
              syncAllottedFromSeating();
            }, onSelectRow: sel),
            _editableCell(r.remarks, (v) => setState(() => r.remarks = v),
                onSelectRow: sel),
          ],
        ));
      }
      tableRows.add(_totalRow(
          ['બ્લોક $b', 'કુલ', '', '', '', blockSum > 0 ? '$blockSum' : '0', '']));
    }
    tableRows.add(_totalRow([
      'એકંદર',
      'કુલ બેઠક સંખ્યા',
      '',
      '',
      '',
      grandTotal > 0 ? '$grandTotal' : '0',
      ''
    ]));

    final headerRow = tableRows.first;
    final bodyRows = tableRows.sublist(1);
    final perPage = _effectiveRowsPerPage(27, pageIdPrefix: secKey);
    final totalPages = (bodyRows.length / perPage).ceil().clamp(1, 99);
    final chunkRows = bodyRows.skip(pageIdx * perPage).take(perPage).toList();

    return Column(
      children: [
        _buildPageHeader(
          'પરીક્ષાની બેઠક વ્યવસ્થા',
          subtitle: totalPages > 1
              ? 'ધોરણ $label — પેજ ${pageIdx + 1} / $totalPages'
              : 'ધોરણ $label',
        ),
        Table(
          border: TableBorder.all(color: kNavy, width: 1.2),
          children: [
            headerRow,
            ...chunkRows,
          ],
        ),
      ],
    );
  }

  // 10. Absent Report Page (Landscape - ONLY Allotted Numbers pre-filled; other cells blank for teacher after print)
  Widget _buildAbsentPage(AbsentPageSheet sheet) {
    final classes = getClassesForGroup(sheet.group);
    int allottedTotal = 0;
    bool hasAllotted = false;
    int presentTotal = 0;
    bool hasPresent = false;
    int absGrandTotal = 0;
    bool hasAbsGrand = false;
    final classTotals = <String, int>{for (final c in classes) c: 0};
    final classHasVal = <String, bool>{for (final c in classes) c: false};

    for (final br in sheet.blockRows) {
      final a = parseNum(br.allotted);
      if (a != null) {
        allottedTotal += a;
        hasAllotted = true;
      }
      final p = parseNum(br.present);
      if (p != null) {
        presentTotal += p;
        hasPresent = true;
      }
      final ta = parseNum(br.totalAbsent);
      if (ta != null) {
        absGrandTotal += ta;
        hasAbsGrand = true;
      }
      for (final c in classes) {
        final ca = parseNum(br.classAbsent[c]);
        if (ca != null) {
          classTotals[c] = (classTotals[c] ?? 0) + ca;
          classHasVal[c] = true;
        }
      }
    }

    return Column(
      children: [
        _buildPageHeader(
          'પરીક્ષામાં ગેરહાજર બાળકોની માહિતી',
          subtitle:
              'ધોરણ ${sheet.stdLabel}  |  તારીખ: ${sheet.date}  |  વાર: ${sheet.day}  |  વિષય: ${sheet.subject}',
        ),

        // Top Block-wise Table (Only Allotted filled by default)
        Table(
          border: TableBorder.all(color: kNavy, width: 1.2),
          children: [
            _tableHeaderRow([
              'બ્લોક',
              'ફાળવાયેલ સંખ્યા',
              'હાજર સંખ્યા',
              ...classes,
              'કુલ ગે.હા.',
              'નિરીક્ષકની સહી'
            ]),
            for (int bIdx = 0; bIdx < sheet.blockRows.length; bIdx++)
              (() {
                final br = sheet.blockRows[bIdx];
                final isSel = _selectedRowSection == 'absent_block' &&
                    _selectedRowIndex == bIdx;
                void sel() => _markRowSelected(
                    section: 'absent_block', index: bIdx, blockNo: br.blockNo);
                return TableRow(
                  decoration: BoxDecoration(
                    color: isSel ? const Color(0xFFFEF08A) : Colors.white,
                  ),
                  children: [
                    _cellText('${br.blockNo}', bold: true, onSelectRow: sel,
                        onChanged: (value) {
                      final parsed = parseNum(value);
                      if (parsed != null && parsed > 0) br.blockNo = parsed;
                    }),
                    _editableCell(br.allotted,
                        (v) => setState(() => br.allotted = v),
                        onSelectRow: sel),
                    _editableCell(br.present,
                        (v) => setState(() => br.present = v),
                        onSelectRow: sel),
                    for (final c in classes)
                      _editableCell(br.classAbsent[c] ?? '', (v) {
                        setState(() {
                          br.classAbsent[c] = v;
                          int sum = 0;
                          bool any = false;
                          for (final cl in classes) {
                            final n = parseNum(br.classAbsent[cl]);
                            if (n != null) {
                              sum += n;
                              any = true;
                            }
                          }
                          br.totalAbsent = any ? '$sum' : '';
                        });
                      }, onSelectRow: sel),
                    _editableCell(br.totalAbsent,
                        (v) => setState(() => br.totalAbsent = v),
                        onSelectRow: sel),
                    _editableCell(br.sign, (v) => setState(() => br.sign = v),
                        onSelectRow: sel),
                  ],
                );
              })(),
            _totalRow([
              'કુલ',
              hasAllotted ? '$allottedTotal' : '',
              hasPresent ? '$presentTotal' : '',
              for (final c in classes)
                (classHasVal[c] == true ? '${classTotals[c]}' : ''),
              hasAbsGrand ? '$absGrandTotal' : '',
              '',
            ]),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
          decoration: BoxDecoration(
              color: kNavy, borderRadius: BorderRadius.circular(6)),
          child: Text(
            'ગેરહાજર વિદ્યાર્થીઓની નામાવલી (${sheet.subject} - ${sheet.date})',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13.5),
          ),
        ),
        const SizedBox(height: 4),
        // Bottom 5-Column Absent Student List (Includes "બ્લોક નંબર" Column!)
        Table(
          border: TableBorder.all(color: kNavy, width: 1.2),
          columnWidths: const {
            0: FlexColumnWidth(0.9),
            1: FlexColumnWidth(1.3),
            2: FlexColumnWidth(4.4),
            3: FlexColumnWidth(1.6),
            4: FlexColumnWidth(1.8),
          },
          children: [
            _tableHeaderRow([
              'ક્રમ નંબર',
              'બ્લોક નંબર',
              'વિદ્યાર્થીનું નામ',
              'રોલ નંબર',
              'ધોરણ'
            ]),
            for (int stIdx = 0; stIdx < sheet.studentList.length; stIdx++)
              (() {
                final st = sheet.studentList[stIdx];
                final isSel = _selectedRowSection == 'absent_student' &&
                    _selectedRowIndex == stIdx;
                void sel() =>
                    _markRowSelected(section: 'absent_student', index: stIdx);
                return TableRow(
                  decoration: BoxDecoration(
                    color: isSel ? const Color(0xFFFEF08A) : Colors.white,
                  ),
                  children: [
                    _cellText('${st.srNo}', bold: true, onSelectRow: sel,
                        onChanged: (value) {
                      final parsed = parseNum(value);
                      if (parsed != null && parsed > 0) st.srNo = parsed;
                    }),
                    _editableCell(st.blockNo,
                        (v) => setState(() => st.blockNo = v),
                        onSelectRow: sel),
                    _editableCell(st.studentName,
                        (v) => setState(() => st.studentName = v),
                        onSelectRow: sel),
                    _editableCell(st.rollNo, (v) {
                      setState(() {
                        st.rollNo = v;
                        if (st.className.isNotEmpty &&
                            st.rollNo.isNotEmpty &&
                            st.blockNo.isEmpty) {
                          st.blockNo = lookupSeatingBlock(
                              st.className, st.rollNo, sheet.group);
                        }
                      });
                    }, onSelectRow: sel),
                    _editableCell(st.className, (v) {
                      setState(() {
                        st.className = v;
                        if (st.className.isNotEmpty &&
                            st.rollNo.isNotEmpty &&
                            st.blockNo.isEmpty) {
                          st.blockNo = lookupSeatingBlock(
                              st.className, st.rollNo, sheet.group);
                        }
                      });
                    }, onSelectRow: sel),
                  ],
                );
              })(),
          ],
        ),
      ],
    );
  }

  // 11. Supervision Page
  Widget _buildSupervisionPage(String g, String label,
      List<SupervisionRow> allRows, int perPage, int pageIdx) {
    final secKey = g == 'a' ? 'super_a' : 'super_b';
    final totalPages = (allRows.length / perPage).ceil().clamp(1, 99);
    final start = pageIdx * perPage;
    final chunk = allRows.skip(start).take(perPage).toList();

    return Column(
      children: [
        _buildPageHeader('નિરીક્ષણ કાર્યનું આયોજન',
            subtitle: 'ધોરણ $label — પેજ ${pageIdx + 1} / $totalPages'),
        Table(
          border: TableBorder.all(color: kNavy, width: 1.2),
          children: [
            _tableHeaderRow(
                ['તારીખ', 'વાર', 'વિષય', 'બ્લોક', 'નિરીક્ષકનું નામ', 'સહી']),
            for (final r in chunk)
              (() {
                final idx = allRows.indexOf(r);
                final isSel =
                    _selectedRowSection == secKey && _selectedRowIndex == idx;
                void sel() => _markRowSelected(
                    section: secKey, index: idx, blockNo: r.blockNo);
                return TableRow(
                  decoration: BoxDecoration(
                    color: isSel ? const Color(0xFFFEF08A) : Colors.white,
                  ),
                  children: [
                    _editableCell(r.date, (v) => setState(() => r.date = v),
                        onSelectRow: sel),
                    _editableCell(r.day, (v) => setState(() => r.day = v),
                        onSelectRow: sel),
                    _editableCell(
                        r.subject, (v) => setState(() => r.subject = v),
                        onSelectRow: sel),
                    _cellText('${r.blockNo}', bold: true, onSelectRow: sel,
                        onChanged: (value) {
                      final parsed = parseNum(value);
                      if (parsed != null && parsed > 0) r.blockNo = parsed;
                    }),
                    _editableCell(r.invigilatorName,
                        (v) => setState(() => r.invigilatorName = v),
                        onSelectRow: sel),
                    _editableCell(r.sign, (v) => setState(() => r.sign = v),
                        onSelectRow: sel),
                  ],
                );
              })(),
          ],
        ),
      ],
    );
  }

  // 12. Paper Checking Page
  Widget _buildCheckingPage(String g, String label, int pageIdx) {
    final secKey = g == 'a' ? 'check_a' : 'check_b';
    final effCap = _effectiveRowsPerPage(checkRowsPerPage,
        pageIdPrefix: g == 'a' ? 'chk_a' : 'chk_b');
    final groupRows = checkingRows.where((r) => r.group == g).toList();
    final totalPages = (groupRows.length / effCap).ceil().clamp(1, 99);
    final chunk = groupRows.skip(pageIdx * effCap).take(effCap).toList();

    return Column(
      children: [
        _buildPageHeader(
          'પેપર ચકાસણી આયોજન',
          subtitle:
              'ધોરણ $label — સમયપત્રક, રજીસ્ટર અને વિષય શિક્ષક મુજબ આપમેળે (પેજ ${pageIdx + 1} / $totalPages)',
        ),
        Table(
          border: TableBorder.all(color: kNavy, width: 1.2),
          children: [
            _tableHeaderRow([
              'તારીખ',
              'વિષય',
              'ધોરણ / વર્ગ',
              'પેપર સંખ્યા',
              'પરીક્ષકનું નામ (વિષય શિક્ષક)',
              'પરીક્ષકની સહી / તારીખ',
              'પેપર પરત તારીખ',
              'આચાર્યની સહી'
            ]),
            for (final r in chunk)
              (() {
                final idx = checkingRows.indexOf(r);
                final isSel =
                    _selectedRowSection == secKey && _selectedRowIndex == idx;
                void sel() => _markRowSelected(section: secKey, index: idx);
                return TableRow(
                  decoration: BoxDecoration(
                    color: isSel ? const Color(0xFFFEF08A) : Colors.white,
                  ),
                  children: [
                    _editableCell(r.date, (v) => setState(() => r.date = v),
                        onSelectRow: sel),
                    _editableCell(
                        r.subject, (v) => setState(() => r.subject = v),
                        onSelectRow: sel),
                    _editableCell(
                        r.className, (v) => setState(() => r.className = v),
                        onSelectRow: sel),
                    _editableCell(
                        r.paperCount, (v) => setState(() => r.paperCount = v),
                        onSelectRow: sel),
                    _editableCell(r.examinerName,
                        (v) => setState(() => r.examinerName = v),
                        onSelectRow: sel),
                    _editableCell(r.examinerSignDate,
                        (v) => setState(() => r.examinerSignDate = v),
                        onSelectRow: sel),
                    _editableCell(
                        r.returnDate, (v) => setState(() => r.returnDate = v),
                        onSelectRow: sel),
                    _editableCell(r.principalSign,
                        (v) => setState(() => r.principalSign = v),
                        onSelectRow: sel),
                  ],
                );
              })(),
          ],
        ),
      ],
    );
  }

  // 13. Class Bundle Stickers Page
  Widget _buildBundlePage(int pageIdx) {
    final effBundles = _effectiveBundlesPerPage();
    final chunk = bundleCards
        .skip(pageIdx * effBundles)
        .take(effBundles)
        .toList();
    if (effBundles == 4) {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: chunk
            .map((c) => SizedBox(width: 350, child: _buildSingleBundleCard(c)))
            .toList(),
      );
    }
    return Column(
      children: chunk
          .map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildSingleBundleCard(c),
              ))
          .toList(),
    );
  }

  Widget _buildSingleBundleCard(BundleCardData card) {
    int regSum = 0;
    int presSum = 0;
    bool hasPres = false;
    int absSum = 0;
    bool hasAbs = false;
    for (final r in card.rows) {
      regSum += parseNum(r.regCount) ?? 0;
      final p = parseNum(r.presentCount);
      if (p != null) {
        presSum += p;
        hasPres = true;
      }
      final a = parseNum(r.absentCount);
      if (a != null) {
        absSum += a;
        hasAbs = true;
      }
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF475569), width: 1.5),
      ),
      child: Column(
        children: [
          Text('${meta.examName} - ${meta.bundleMonth}',
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: kNavy, fontSize: 13)),
          Text('શાળાનું નામ: ${meta.schoolName}',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          Text('તા: ${meta.taluka}   જિ: ${meta.district}',
              style: const TextStyle(fontSize: 11.5)),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: const Text(
              'બંડલ પર બાંધવાનો વર્ગવાર હાજરી રીપોર્ટ',
              style: TextStyle(
                  color: kGreen, fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF4FF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: InkWell(
              onTap: () => _editMetaField(
                'બંડલનો વર્ગ / ધોરણ સુધારો',
                card.className,
                (value) => card.className = value,
              ),
              child: Text(
                'ધોરણ / વર્ગ: ${ClassLabel.bare(card.className)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w900, color: kRed, fontSize: 13.5),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Table(
            border: TableBorder.all(color: kNavy, width: 1),
            children: [
              _tableHeaderRow([
                'ક્રમ',
                'તારીખ',
                'વિષય',
                'રજીસ્ટર',
                'હાજર',
                'ગેરહાજર',
                'ગેરહાજર નં.'
              ]),
              for (int rIdx = 0; rIdx < card.rows.length; rIdx++)
                (() {
                  final r = card.rows[rIdx];
                  final cardIdx = bundleCards.indexOf(card);
                  final isSel = _selectedRowSection == 'bundle' &&
                      _selectedBundleCardIndex == cardIdx &&
                      _selectedRowIndex == rIdx;
                  void sel() => _markRowSelected(
                      section: 'bundle',
                      index: rIdx,
                      bundleCardIndex: cardIdx);
                  return TableRow(
                    decoration: BoxDecoration(
                      color: isSel ? const Color(0xFFFEF08A) : Colors.white,
                    ),
                    children: [
                      _cellText('${r.srNo}', onSelectRow: sel),
                      _editableCell(r.date, (v) => setState(() => r.date = v),
                          onSelectRow: sel),
                      _editableCell(
                          r.subject, (v) => setState(() => r.subject = v),
                          onSelectRow: sel),
                      _editableCell(
                          r.regCount, (v) => setState(() => r.regCount = v),
                          onSelectRow: sel),
                      _editableCell(r.presentCount, (v) {
                        setState(() {
                          r.presentCount = v;
                          final reg = parseNum(r.regCount);
                          final pr = parseNum(v);
                          if (reg != null && pr != null) {
                            r.absentCount = '${math.max(0, reg - pr)}';
                          }
                        });
                      }, onSelectRow: sel),
                      _editableCell(r.absentCount,
                          (v) => setState(() => r.absentCount = v),
                          onSelectRow: sel),
                      _editableCell(r.absentRollNos,
                          (v) => setState(() => r.absentRollNos = v),
                          onSelectRow: sel),
                    ],
                  );
                })(),
              _totalRow([
                '',
                '',
                'કુલ',
                '$regSum',
                hasPres ? '$presSum' : '',
                hasAbs ? '$absSum' : '',
                '',
              ]),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: Text(
              'આ બંડલમાં કુલ ${hasPres ? presSum : "______"} ઉત્તરવહી મુકવામાં આવેલ છે.',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
            ),
          ),
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text('વર્ગ શિક્ષકની સહી: ________',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold, color: kNavy))),
              Flexible(child: Text('આચાર્યની સહી/સિક્કો: ________',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold, color: kNavy))),
            ],
          ),
        ],
      ),
    );
  }

  // 14. Block Door Stickers Page
  Widget _buildDoorStickerPage(int pageIdx) {
    final allDoors = <Map<String, dynamic>>[];
    if (hasGroupA) {
      for (int b = 1; b <= blocksA; b++) {
        final rows = seatingA.where((r) => r.blockNo == b).toList();
        final tot =
            rows.fold<int>(0, (s, r) => s + (parseNum(r.totalCount) ?? 0));
        allDoors.add({
          'groupLabel': 'ધોરણ ૩ થી ૫',
          'blockNo': b,
          'roomNo': b,
          'rows': rows,
          'tot': tot
        });
      }
    }
    if (hasGroupB) {
      final roomOffset = hasGroupA ? blocksA : 0;
      for (int b = 1; b <= blocksB; b++) {
        final rows = seatingB.where((r) => r.blockNo == b).toList();
        final tot =
            rows.fold<int>(0, (s, r) => s + (parseNum(r.totalCount) ?? 0));
        allDoors.add({
          'groupLabel': 'ધોરણ ૬ થી ૮',
          'blockNo': b,
          'roomNo': roomOffset + b,
          'rows': rows,
          'tot': tot
        });
      }
    }

    final effDoors = _effectiveDoorsPerPage();
    final chunk = allDoors.skip(pageIdx * effDoors).take(effDoors).toList();
    if (effDoors == 4) {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: chunk
            .map((d) => SizedBox(width: 350, child: _buildSingleDoorCard(d)))
            .toList(),
      );
    }
    return Column(
      children: chunk
          .map((d) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildSingleDoorCard(d),
              ))
          .toList(),
    );
  }

  Widget _buildSingleDoorCard(Map<String, dynamic> d) {
    final rows = d['rows'] as List<SeatingRow>;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kNavy, width: 2),
      ),
      child: Column(
        children: [
          Text(meta.schoolName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: kNavy, fontSize: 13)),
          Text('${meta.examName} — ${meta.academicYear}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: kGreen, fontSize: 12)),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: kNavy,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kSaffron, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: Text('🚪 બ્લોક નંબર : ${gn(d['blockNo'])} (${d['groupLabel']})',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13))),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(5)),
                  child: Text('રૂમ નં: ${gn(d['roomNo'])}',
                      style: const TextStyle(
                          color: kNavy,
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5)),
                ),
              ],
            ),
          ),
          Table(
            border: TableBorder.all(color: kNavy, width: 1),
            children: [
              _tableHeaderRow([
                'ધોરણ / વર્ગ',
                'બેઠક રોલ નંબર (થી — સુધી)',
                'કુલ પરીક્ષાર્થી'
              ]),
              for (final r in rows)
                TableRow(
                  children: [
                    _editableCell(
                      r.className,
                      (value) => setState(() => r.className = value),
                      onSelectRow: () => _markRowSelected(
                        section: 'door',
                        index: 0,
                        blockNo: r.blockNo,
                      ),
                    ),
                    _editableCell('${r.fromRoll} થી ${r.toRoll}', (value) {
                      setState(() {
                        final parts =
                            value.split(RegExp(r'\s*(?:થી|[-–])\s*'));
                        if (parts.length >= 2) {
                          r.fromRoll = parts.first.trim();
                          r.toRoll = parts.sublist(1).join(' થી ').trim();
                          final f = parseNum(r.fromRoll);
                          final t = parseNum(r.toRoll);
                          if (f != null && t != null && t >= f) {
                            r.totalCount = '${t - f + 1}';
                          }
                        } else {
                          r.fromRoll = value.trim();
                        }
                      });
                      syncAllottedFromSeating();
                    }),
                    _editableCell(r.totalCount, (value) {
                      setState(() => r.totalCount = value);
                      syncAllottedFromSeating();
                    }),
                  ],
                ),
              _totalRow(['', 'બ્લોકમાં કુલ બેઠક સંખ્યા', '${d['tot']}']),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text('ખંડ નિરીક્ષક સહી: ________',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold, color: kNavy))),
              Flexible(child: Text('આચાર્યની સહી / સિક્કો: ________',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold, color: kNavy))),
            ],
          ),
        ],
      ),
    );
  }

  // 15. Question Paper Register Page
  Widget _buildQpRegisterPage({int pageIdx = 0}) {
    final perPage = _effectiveRowsPerPage(27, pageIdPrefix: 'qp_reg');
    final totalPages = (qpRegisterRows.length / perPage).ceil().clamp(1, 99);
    final start = pageIdx * perPage;
    final chunk = qpRegisterRows.skip(start).take(perPage).toList();

    return Column(
      children: [
        _buildPageHeader(
          'પ્રશ્નપત્ર પેકેટ સીલ અને વિતરણ રજીસ્ટર',
          subtitle:
              'સમયપત્રક, રજીસ્ટર સંખ્યા અને શિક્ષક યાદી મુજબ પ્રશ્નપત્ર પેકેટ ખોલ્યાનું તથા વિતરણનું રજીસ્ટર${totalPages > 1 ? " (પેજ ${pageIdx + 1} / $totalPages)" : ""}',
        ),
        Table(
          border: TableBorder.all(color: kNavy, width: 1.2),
          children: [
            _tableHeaderRow([
              'ક્રમ',
              'તારીખ',
              'વાર',
              'ધોરણ જૂથ',
              'વિષય',
              'પરીક્ષા સમય',
              'કુલ પરીક્ષાર્થી',
              'બ્લોક સંખ્યા',
              'સીલ ખોલ્યા સમય',
              'સાક્ષી શિક્ષકનું નામ',
              'સહી'
            ]),
            for (int localIdx = 0; localIdx < chunk.length; localIdx++)
              (() {
                final i = start + localIdx;
                final isSel =
                    _selectedRowSection == 'qp_reg' && _selectedRowIndex == i;
                return TableRow(
                  decoration: BoxDecoration(
                    color: isSel ? const Color(0xFFFEF08A) : Colors.white,
                  ),
                  children: [
                    for (int j = 0; j < qpRegisterRows[i].length; j++)
                      _editableCell(
                        qpRegisterRows[i][j],
                        (v) => setState(() => qpRegisterRows[i][j] = v),
                        onSelectRow: () =>
                            _markRowSelected(section: 'qp_reg', index: i),
                      ),
                  ],
                );
              })(),
          ],
        ),
      ],
    );
  }

  // 16. Stationery & Answer Sheet Account Page (With Question-Paper Answer Option & Optional 5% Reserve)
  Widget _buildStationeryPage({int pageIdx = 0}) {
    final perPage = _effectiveRowsPerPage(27, pageIdPrefix: 'stationery');
    final totalPages = (stationeryRows.length / perPage).ceil().clamp(1, 99);
    final start = pageIdx * perPage;
    final chunk = stationeryRows.skip(start).take(perPage).toList();

    return Column(
      children: [
        _buildPageHeader(
          'ઉત્તરવહી અને સ્ટેશનરી જરૂરિયાત પત્રક',
          subtitle:
              'ધોરણવાર રજીસ્ટર સંખ્યા અને વિષયો મુજબ ઉત્તરવહી, પુરવણી અને સ્ટેશનરીનો આપોઆપ હિસાબ${totalPages > 1 ? " (પેજ ${pageIdx + 1} / $totalPages)" : ""}',
        ),

        Table(
          border: TableBorder.all(color: kNavy, width: 1.2),
          children: [
            _tableHeaderRow([
              'ધોરણ / વર્ગ',
              'રજીસ્ટર સંખ્યા',
              'કુલ પેપર',
              'જરૂરી મુખ્ય ઉત્તરવહી',
              include5PercentReserveInStationery
                  ? '૫% અનામત'
                  : 'અનામત (0%)',
              'કુલ ઉત્તરવહી',
              'અંદાજિત પુરવણી (25%)',
              'બંડલ કાપલી',
              'વર્ગ શિક્ષક સહી / નોંધ'
            ]),
            for (int localIdx = 0; localIdx < chunk.length; localIdx++)
              (() {
                final i = start + localIdx;
                final row = stationeryRows[i];
                final isTotalRow = row.isNotEmpty && row.first.contains('કુલ');
                if (isTotalRow) {
                  return _totalRow(row);
                }
                final isSel = _selectedRowSection == 'stationery' &&
                    _selectedRowIndex == i;
                return TableRow(
                  decoration: BoxDecoration(
                    color: isSel ? const Color(0xFFFEF08A) : Colors.white,
                  ),
                  children: [
                    for (int j = 0; j < row.length; j++)
                      _editableCell(
                        row[j],
                        (v) {
                          setState(() {
                            row[j] = v;
                            if (j == 1 || j == 2) {
                              final reg = parseNum(row[1]) ?? 0;
                              final subCnt = parseNum(row[2]) ?? 0;
                              if (!_classHasAnswersInQuestionPaper(row[0])) {
                                row[3] = '${reg * subCnt}';
                              }
                            }
                            _recalculateStationeryTotalsInPlace();
                          });
                        },
                        onSelectRow: () =>
                            _markRowSelected(section: 'stationery', index: i),
                      ),
                  ],
                );
              })(),
          ],
        ),
      ],
    );
  }

  // 17. Instructions Page
  Widget _buildInstructionsPage({int pageIdx = 0}) {
    final perPage = _effectiveRowsPerPage(20, pageIdPrefix: 'instructions');
    final totalPages =
        (editableInstructions.length / perPage).ceil().clamp(1, 99);
    final start = pageIdx * perPage;
    final chunk = editableInstructions.skip(start).take(perPage).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPageHeader(
          'પરીક્ષાલક્ષી સૂચનાઓ',
          subtitle: totalPages > 1 ? 'પેજ ${pageIdx + 1} / $totalPages' : null,
        ),
        for (int localIdx = 0; localIdx < chunk.length; localIdx++)
          Builder(builder: (_) {
            final i = start + localIdx;
            final isSel = _selectedRowSection == 'instructions' &&
                _selectedRowIndex == i;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: isSel ? const Color(0xFFFEF08A) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.only(top: 2, right: 8),
                    decoration: const BoxDecoration(
                        color: kNavy, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text(
                      gn(i + 1),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        _markRowSelected(section: 'instructions', index: i);
                        _editMetaField(
                          'સૂચના સુધારો',
                          editableInstructions[i],
                          (value) {
                            editableInstructions[i] = value;
                            _scheduleExamDeviceAutoSave();
                          },
                        );
                      },
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: activeRowHeight / 2,
                        ),
                        child: Text(
                          editableInstructions[i],
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  // ============================================================================
  // Table & Dialog Helpers
  // ============================================================================

  TableRow _tableHeaderRow(List<String> headers) {
    return TableRow(
      decoration: const BoxDecoration(color: kNavy),
      children: headers.asMap().entries.map((entry) {
        final colIdx = entry.key;
        final h = entry.value;
        final key = 'th_${activePageId}_${colIdx}_$h';
        final display = customTextOverrides[key] ?? h;
        final offset = customTextOffsets[key] ?? Offset.zero;
        return Transform.translate(
          offset: offset,
          child: _PageDragDetector(
 pageKey: _a4PageCaptureKey,
 hideSelection: _capturingForPdf,

            behavior: HitTestBehavior.opaque,
            onTap: () => _editMetaField(
              'હેડર લખાણ સુધારો',
              display,
              (val) => customTextOverrides[key] = val,
            ),
            onPanUpdate: (d) {
              setState(() {
                customTextOffsets[key] =
                    (customTextOffsets[key] ?? Offset.zero) + d.delta;
              });
              _scheduleExamDeviceAutoSave();
            },
            child: Padding(
              padding: EdgeInsets.symmetric(
                  vertical: activeRowHeight, horizontal: 4),
              child: Text(
                display,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  TableRow _totalRow(List<String> cells) {
    return TableRow(
      decoration: const BoxDecoration(color: Color(0xFFFFF1DD)),
      children: cells.asMap().entries.map((entry) {
        final colIdx = entry.key;
        final c = entry.value;
        final key = 'tot_${activePageId}_${colIdx}_$c';
        final display = customTextOverrides[key] ?? c;
        final offset = customTextOffsets[key] ?? Offset.zero;
        return Transform.translate(
          offset: offset,
          child: _PageDragDetector(
 pageKey: _a4PageCaptureKey,
 hideSelection: _capturingForPdf,

            behavior: HitTestBehavior.opaque,
            onTap: () => _editMetaField(
              'કુલ હરોળ સુધારો',
              display,
              (val) => customTextOverrides[key] = val,
            ),
            onPanUpdate: (d) {
              setState(() {
                customTextOffsets[key] =
                    (customTextOffsets[key] ?? Offset.zero) + d.delta;
              });
              _scheduleExamDeviceAutoSave();
            },
            child: Padding(
              padding: EdgeInsets.symmetric(
                  vertical: activeRowHeight, horizontal: 4),
              child: Text(
                display,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: kNavy,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _cellText(
    String text, {
    bool bold = false,
    Color color = const Color(0xFF1B2433),
    TextAlign align = TextAlign.center,
    ValueChanged<String>? onChanged,
    VoidCallback? onSelectRow,
  }) {
    final key = 'cell_${activePageId}_$text';
    final display = customTextOverrides[key] ?? text;
    final offset = customTextOffsets[key] ?? Offset.zero;
    return Transform.translate(
      offset: offset,
      child: _PageDragDetector(
 pageKey: _a4PageCaptureKey,
 hideSelection: _capturingForPdf,

        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (onSelectRow != null) onSelectRow();
          _editMetaField(
            'વિગત સુધારો',
            display,
            (val) {
              if (onChanged != null) {
                onChanged(val);
              } else {
                customTextOverrides[key] = val;
              }
            },
          );
        },
        onPanUpdate: (d) {
          setState(() {
            customTextOffsets[key] =
                (customTextOffsets[key] ?? Offset.zero) + d.delta;
          });
          _scheduleExamDeviceAutoSave();
        },
        child: Padding(
          padding:
              EdgeInsets.symmetric(vertical: activeRowHeight, horizontal: 4),
          child: _fitCellText(
            display,
            align,
            TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }

  /// Short values (dates, times, numbers, short names) stay on one line and
  /// shrink to the cell width; long descriptions wrap normally.
  Widget _fitCellText(String text, TextAlign align, TextStyle style) {
    final t = text.isEmpty ? ' ' : text;
    final singleLine = t.trim().length <= 18;
    if (!singleLine) {
      return Text(t, textAlign: align, style: style);
    }
    final alignment = align == TextAlign.left || align == TextAlign.start
        ? Alignment.centerLeft
        : align == TextAlign.right || align == TextAlign.end
            ? Alignment.centerRight
            : Alignment.center;
    return Align(
      alignment: alignment,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: Text(t, maxLines: 1, softWrap: false, textAlign: align, style: style),
      ),
    );
  }

  Widget _editableCell(
    String initialValue,
    ValueChanged<String> onChanged, {
    VoidCallback? onSelectRow,
  }) {
    final key = 'edcell_${activePageId}_${initialValue.hashCode}';
    final offset = customTextOffsets[key] ?? Offset.zero;
    return Transform.translate(
      offset: offset,
      child: _PageDragDetector(
 pageKey: _a4PageCaptureKey,
 hideSelection: _capturingForPdf,

        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (onSelectRow != null) onSelectRow();
          _editMetaField('વિગત સુધારો', initialValue, onChanged);
        },
        onPanUpdate: (d) {
          setState(() {
            customTextOffsets[key] =
                (customTextOffsets[key] ?? Offset.zero) + d.delta;
          });
          _scheduleExamDeviceAutoSave();
        },
        child: Padding(
          padding:
              EdgeInsets.symmetric(vertical: activeRowHeight, horizontal: 4),
          child: _fitCellText(
            initialValue,
            TextAlign.center,
            const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
                color: Color(0xFF1B2433)),
          ),
        ),
      ),
    );
  }

  Widget _actionButton(
      {required String label,
      required Color color,
      required VoidCallback onTap}) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onTap,
      child: Text(label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  Widget _miniToolBtn(String label, Color bg, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12)),
      ),
    );
  }

  Widget _infoPill(String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(text,
          style:
              TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }

  Future<void> _editMetaField(
    String title,
    String currentVal,
    ValueChanged<String> onSave, {
    int maxLines = 1,
  }) async {
    final ctrl = TextEditingController(text: currentVal);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, color: kNavy)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: maxLines > 1 ? 2 : 1,
          maxLines: maxLines,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('રદ કરો')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kGreen, foregroundColor: Colors.white),
            onPressed: () {
              setState(() => onSave(ctrl.text));
              _scheduleExamDeviceAutoSave();
              Navigator.pop(ctx);
            },
            child: const Text('સેવ કરો'),
          ),
        ],
      ),
    );
  }

  Future<void> _showExcelPasteDialog() async {
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('📋 Excel માંથી શિક્ષક માહિતી પેસ્ટ કરો',
            style: TextStyle(fontWeight: FontWeight.bold, color: kNavy)),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Excel માંથી કોલમ કોપી કરી અહીં પેસ્ટ કરો:\n'
                '• ૧ કોલમ: ફક્ત શિક્ષકનું નામ\n'
                '• ૨ કોલમ: શિક્ષકનું નામ | જૂથ (૩ થી ૫ અથવા ૬ થી ૮)\n'
                '• ૩ કોલમ: શિક્ષકનું નામ | જૂથ | વિષયો (અલ્પવિરામથી અલગ)',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                maxLines: 7,
                decoration: const InputDecoration(
                  hintText: 'રમેશભાઈ પટેલ\t૩ થી ૫\tગુજરાતી, ગણિત',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('રદ કરો')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kGreen, foregroundColor: Colors.white),
            onPressed: () {
              _applyExcelPaste(ctrl.text, replace: false);
              Navigator.pop(ctx);
            },
            child: const Text('➕ હાલના લિસ્ટમાં ઉમેરો'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kRed, foregroundColor: Colors.white),
            onPressed: () {
              _applyExcelPaste(ctrl.text, replace: true);
              Navigator.pop(ctx);
            },
            child: const Text('🔄 જૂના કાઢી નવું લિસ્ટ મૂકો'),
          ),
        ],
      ),
    );
  }

  void _applyExcelPaste(String raw, {required bool replace}) {
    final lines = raw
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return;
    final parsed = <TeacherRecord>[];
    for (final line in lines) {
      final cols = line.split('\t').map((c) => c.trim()).toList();
      final name = cols[0];
      String grp = 'a';
      if (cols.length >= 2 &&
          RegExp(r'[૬-૮678]|b', caseSensitive: false).hasMatch(cols[1])) {
        grp = 'b';
      }
      final subs = cols.length >= 3
          ? cols
              .sublist(2)
              .join(',')
              .split(RegExp(r'[,;/|]+'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList()
          : <String>[];
      if (name.isNotEmpty) {
        parsed.add(TeacherRecord(name: name, group: grp, subjects: subs));
      }
    }
    if (parsed.isEmpty) return;
    setState(() {
      if (replace) {
        teachers = parsed;
      } else {
        teachers.addAll(parsed);
      }
      _earlyTeacherClassCache.clear();
    });
    _showSnack('✅ ${parsed.length} શિક્ષકોની માહિતી ઉમેરાઈ ગઈ!');
  }

  String exportBackupJsonString() {
    return const JsonEncoder.withIndent('  ').convert({
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'meta': meta.toJson(),
      'examClassRangeMode': examClassRangeMode,
      'includeBalvatikaAndStd12Teachers': includeBalvatikaAndStd12Teachers,
      'include5PercentReserveInStationery': include5PercentReserveInStationery,
      'classesWithAnswersInQuestionPaper':
          classesWithAnswersInQuestionPaper.toList(),
      'selectedExamClasses': selectedExamClasses.toList(),
      'selectedSubjects35': selectedSubjects35.toList(),
      'selectedSubjects68': selectedSubjects68.toList(),
      'blocksA': blocksA,
      'blocksB': blocksB,
      'genderMode': genderMode,
      'superMode': superMode,
      'pageFontScales': pageFontScales,
      'pageRowHeights': pageRowHeights,
      'extraPageRows': extraPageRows.map((pageId, rows) => MapEntry(
            pageId,
            rows
                .map((row) => <String, dynamic>{
                      'label': row.label,
                      'value': row.value,
                    })
                .toList(),
          )),
      'indexCellOverrides': indexCellOverrides,
      'customTextOverrides': customTextOverrides,
      'customTextOffsets': customTextOffsets.map(
          (k, v) => MapEntry(k, <String, double>{'dx': v.dx, 'dy': v.dy})),
      'coverLogoOffset': <String, double>{
        'dx': coverLogoOffset.dx,
        'dy': coverLogoOffset.dy,
      },
      'headerLogoOffset': <String, double>{
        'dx': headerLogoOffset.dx,
        'dy': headerLogoOffset.dy,
      },
      'coverLogoSize': coverLogoSize,
      'headerLogoSize': headerLogoSize,
      'schoolNameLang': schoolNameLang,
      if (_schoolLogoDataUri.isNotEmpty)
        'customSchoolLogoDataUri': _schoolLogoDataUri,
      'editableInstructions': editableInstructions,
      'certificateStatementOverride': certificateStatementOverride,
      'teachers': teachers.map((t) => t.toJson()).toList(),
      'registerRows': registerRows
          .map((r) => <String, dynamic>{
                'className': r.className,
                'group': r.group,
                'boys': r.boys,
                'girls': r.girls,
                'teacherSign': r.teacherSign,
                'remarks': r.remarks,
              })
          .toList(),
      'bellScheduleRows': bellScheduleRows,
      'timetableRows': timetableRows
          .map((r) => <String, dynamic>{
                'date': r.date,
                'day': r.day,
                'stdLabel': r.stdLabel,
                'subject': r.subject,
                'time': r.time,
                'marks': r.marks,
              })
          .toList(),
      'committeeRows': committeeRows
          .map((r) => <String, dynamic>{
                'teacherName': r.teacherName,
                'roleOrDuty': r.roleOrDuty,
                'sign': r.sign,
              })
          .toList(),
      'workDutyRows': workDutyRows
          .map((r) => <String, dynamic>{
                'teacherName': r.teacherName,
                'roleOrDuty': r.roleOrDuty,
                'sign': r.sign,
              })
          .toList(),
    });
  }

  Future<void> _showBackupRestoreDialog() async {
    final ctrl = TextEditingController(text: exportBackupJsonString());
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('💾 JSON બેકઅપ કોપી / રિસ્ટોર',
            style: TextStyle(fontWeight: FontWeight.bold, color: kNavy)),
        content: SizedBox(
          width: 540,
          child: TextField(
            controller: ctrl,
            maxLines: 12,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('બંધ કરો')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kNavy, foregroundColor: Colors.white),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: ctrl.text));
              _showSnack('📋 JSON બેકઅપ ક્લિપબોર્ડમાં કોપી થઈ ગયો!');
            },
            child: const Text('📋 કોપી કરો'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kGreen, foregroundColor: Colors.white),
            onPressed: () {
              try {
                final m = jsonDecode(ctrl.text) as Map<String, dynamic>;
                setState(() {
                  if (m['meta'] is Map<String, dynamic>) {
                    meta.applyJson(m['meta'] as Map<String, dynamic>);
                  }
                  blocksA = (m['blocksA'] as int?) ?? blocksA;
                  blocksB = (m['blocksB'] as int?) ?? blocksB;
                  genderMode = m['genderMode']?.toString() ?? genderMode;
                  superMode = m['superMode']?.toString() ?? superMode;
                  if (m['pageRowHeights'] is Map) {
                    pageRowHeights
                      ..clear()
                      ..addAll((m['pageRowHeights'] as Map).map((key, value) =>
                          MapEntry(
                            key.toString(),
                            value is num
                                ? value.toDouble()
                                : double.tryParse('$value') ?? 6.0,
                          )));
                  }
                  if (m['extraPageRows'] is Map) {
                    extraPageRows.clear();
                    (m['extraPageRows'] as Map).forEach((key, value) {
                      if (value is List) {
                        extraPageRows[key.toString()] = value
                            .whereType<Map>()
                            .map((row) => ExamExtraDetailRow(
                                  label: row['label']?.toString() ?? 'નવી વિગત',
                                  value: row['value']?.toString() ?? '',
                                ))
                            .toList();
                      }
                    });
                  }
                  if (m['indexCellOverrides'] is Map) {
                    indexCellOverrides
                      ..clear()
                      ..addAll((m['indexCellOverrides'] as Map).map(
                          (key, value) => MapEntry(key.toString(), value.toString())));
                  }
                  if (m['editableInstructions'] is List) {
                    final restored = (m['editableInstructions'] as List)
                        .map((value) => value.toString())
                        .toList();
                    if (restored.isNotEmpty) editableInstructions = restored;
                  }
                  if (m['certificateStatementOverride'] is String) {
                    certificateStatementOverride =
                        m['certificateStatementOverride'] as String;
                  }
                  if (m['includeBalvatikaAndStd12Teachers'] is bool) {
                    includeBalvatikaAndStd12Teachers =
                        m['includeBalvatikaAndStd12Teachers'] as bool;
                  }
                  if (m['teachers'] is List) {
                    final dbTeachersByName = <String, TeacherRecord>{
                      for (final teacher in teachers)
                        teacher.name.trim().toLowerCase(): teacher,
                    };
                    final restoredTeachers = (m['teachers'] as List)
                        .map((e) =>
                            TeacherRecord.fromJson(e as Map<String, dynamic>))
                        .toList();
                    teachers = restoredTeachers.map((teacher) {
                      final dbTeacher = dbTeachersByName[
                          teacher.name.trim().toLowerCase()];
                      if (dbTeacher == null) return teacher;
                      return TeacherRecord(
                        id: dbTeacher.id.isNotEmpty ? dbTeacher.id : teacher.id,
                        name: teacher.name,
                        group: teacher.group,
                        subjects: teacher.subjects,
                        assignedClasses: dbTeacher.assignedClasses.isNotEmpty
                            ? dbTeacher.assignedClasses
                            : teacher.assignedClasses,
                        allowedClasses: dbTeacher.allowedClasses.isNotEmpty
                            ? dbTeacher.allowedClasses
                            : teacher.allowedClasses,
                      );
                    }).toList();
                    _earlyTeacherClassCache.clear();
                  }
                });
                Navigator.pop(ctx);
                _syncExamSelectionToPatraks(rebuildTimetable: false);
                _scheduleExamDeviceAutoSave();
                _showSnack('✅ ડેટા સફળતાપૂર્વક રિસ્ટોર થઈ ગયો!');
              } catch (_) {
                _showSnack('⚠️ અમાન્ય JSON ફોર્મેટ!');
              }
            },
            child: const Text('📂 રિસ્ટોર કરો'),
          ),
        ],
      ),
    );
  }

  String _escExamHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  String _buildExamPageHtml(NavPageItem page) {
    final logoImgSmall = _schoolLogoDataUri.isNotEmpty
        ? '<img src="$_schoolLogoDataUri" style="width:42px;height:42px;object-fit:contain;vertical-align:middle;margin-right:8px;border-radius:6px;" />'
        : '';
    final logoImgCover = _schoolLogoDataUri.isNotEmpty
        ? '<img src="$_schoolLogoDataUri" style="width:125px;height:125px;object-fit:contain;margin:10px auto;display:block;${meta.logoShape == 'round' ? 'border-radius:50%;border:2px solid #ff9933;' : ''}" />'
        : '';
    final hdr = '''
      <div class="hdr">
        <div class="hdr-school">$logoImgSmall${_escExamHtml(meta.schoolName)}</div>
        <div class="hdr-sub">${_escExamHtml(meta.address)} | તા: ${_escExamHtml(meta.taluka)} | જિ: ${_escExamHtml(meta.district)} | પગારકેન્દ્ર: ${_escExamHtml(meta.payCenter)}</div>
        <div class="hdr-exam">${_escExamHtml(meta.examName)} — વર્ષ: ${_escExamHtml(meta.academicYear)}</div>
      </div>
    ''';

    switch (page.category) {
      case 'cover':
        return '''
        <div class="sheet portrait">
          <div style="border:4px double #0b2a5b;padding:28px;text-align:center;height:100%;display:flex;flex-direction:column;justify-content:space-between;">
            <div>
              <div style="font-size:15px;font-weight:800;color:#FF9933;">॥ શ્રી ગણેશાય નમઃ ॥ &nbsp;•&nbsp; તમસો મા જ્યોતિર્ગમય</div>
              $logoImgCover
              <h1 style="font-size:36px;color:#0b2a5b;margin:14px 0 8px;">પરીક્ષા આયોજન ફાઈલ</h1>
              <div style="font-size:18px;font-weight:800;color:#0f766e;">સંપૂર્ણ ઓટોમેટિક પરીક્ષા સંચાલન અને રજીસ્ટર દસ્તાવેજ</div>
            </div>
            <div style="margin:28px 0;padding:20px;background:#f4f7fd;border:2px solid #0b2a5b;border-radius:12px;">
              <div style="font-size:26px;font-weight:900;color:#0b2a5b;">${_escExamHtml(meta.schoolName)}</div>
              <div style="font-size:16px;font-weight:700;margin-top:6px;">${_escExamHtml(meta.address)}</div>
              <div style="font-size:16px;font-weight:700;margin-top:4px;">તાલુકો: ${_escExamHtml(meta.taluka)} &nbsp;|&nbsp; જિલ્લો: ${_escExamHtml(meta.district)}</div>
              <div style="font-size:22px;font-weight:900;color:#b91c1c;margin-top:16px;padding:8px;border-top:2px solid #ff9933;border-bottom:2px solid #ff9933;">${_escExamHtml(meta.examName)}</div>
              <div style="font-size:17px;font-weight:800;margin-top:10px;">શૈક્ષણિક વર્ષ: ${_escExamHtml(meta.academicYear)} &nbsp;|&nbsp; પગારકેન્દ્ર: ${_escExamHtml(meta.payCenter)}</div>
            </div>
            <div style="display:flex;justify-content:space-between;font-weight:800;font-size:15px;padding-top:20px;border-top:1px solid #94a3b8;">
              <span>આચાર્યશ્રી: ${_escExamHtml(meta.principalName)}</span>
              <span>સી.આર.સી. કો-ઓર્ડિનેટર: ${_escExamHtml(meta.crcName)}</span>
            </div>
          </div>
        </div>''';

      case 'index':
        return '<div class="sheet portrait">$hdr<h3>અનુક્રમણિકા અને આયોજન પ્રમાણપત્ર</h3><p style="text-align:left;line-height:1.6;font-weight:700;">${_escExamHtml(_certificateStatement)}</p></div>';

      case 'teachers':
        final rows = _examDutyTeachers.asMap().entries.map((e) =>
          '<tr><td>${e.key + 1}</td><td style="text-align:left;font-weight:800;">${_escExamHtml(e.value.name)}</td><td>${e.value.group == "a" ? "ધો. ૩ થી ૫" : "ધો. ૬ થી ૮"}</td><td style="text-align:left;">${_escExamHtml(e.value.subjects.join(", "))}</td></tr>'
        ).join();
        return '<div class="sheet portrait">$hdr<h3>શિક્ષક માહિતી અને વિષય યાદી</h3><table><thead><tr><th>ક્રમ</th><th>શિક્ષકનું નામ</th><th>જૂથ</th><th>વિષયો</th></tr></thead><tbody>$rows</tbody></table></div>';

      case 'committee':
        final cRows = committeeRows.asMap().entries.map((e) =>
          '<tr><td>${e.key + 1}</td><td style="text-align:left;font-weight:800;">${_escExamHtml(e.value.teacherName)}</td><td style="text-align:left;">${_escExamHtml(e.value.roleOrDuty)}</td><td>${_escExamHtml(e.value.sign)}</td></tr>'
        ).join();
        final wRows = workDutyRows.asMap().entries.map((e) =>
          '<tr><td>${e.key + 1}</td><td style="text-align:left;font-weight:800;">${_escExamHtml(e.value.teacherName)}</td><td style="text-align:left;">${_escExamHtml(e.value.roleOrDuty)}</td><td>${_escExamHtml(e.value.sign)}</td></tr>'
        ).join();
        return '<div class="sheet portrait">$hdr<h3>પરીક્ષા સમિતિ</h3><table><thead><tr><th>અ.નં.</th><th>શિક્ષકનું નામ</th><th>હોદ્દો</th><th>સહી</th></tr></thead><tbody>$cRows</tbody></table><h3 style="margin-top:14px;">પરીક્ષાલક્ષી કામગીરીની ફાળવણી</h3><table><thead><tr><th>અ.નં.</th><th>શિક્ષકનું નામ</th><th>સોંપેલ કામગીરી</th><th>સહી</th></tr></thead><tbody>$wRows</tbody></table></div>';

      case 'register':
        final isBoysOnly = genderMode == 'boys';
        final isGirlsOnly = genderMode == 'girls';
        final thCols = isBoysOnly
            ? '<th>ધોરણ</th><th>કુમાર</th><th>વર્ગ શિક્ષકની સહી</th><th>રીમાર્કસ</th>'
            : isGirlsOnly
                ? '<th>ધોરણ</th><th>કન્યા</th><th>વર્ગ શિક્ષકની સહી</th><th>રીમાર્કસ</th>'
                : '<th>ધોરણ</th><th>કુમાર</th><th>કન્યા</th><th>કુલ</th><th>વર્ગ શિક્ષકની સહી</th><th>રીમાર્કસ</th>';
        final rRows = registerRows.map((r) {
          final midCols = isBoysOnly
              ? '<td style="font-weight:800;">${r.total(genderMode)}</td>'
              : isGirlsOnly
                  ? '<td style="font-weight:800;">${r.total(genderMode)}</td>'
                  : '<td>${r.boys}</td><td>${r.girls}</td><td style="font-weight:800;">${r.total(genderMode)}</td>';
          return '<tr><td style="font-weight:800;">${_escExamHtml(r.className)}</td>$midCols<td>${_escExamHtml(r.teacherSign)}</td><td>${_escExamHtml(r.remarks)}</td></tr>';
        }).join();
        return '<div class="sheet portrait">$hdr<h3>ધોરણવાર રજીસ્ટર સંખ્યા પત્રક</h3><table><thead><tr>$thCols</tr></thead><tbody>$rRows</tbody></table></div>';

      case 'timetable':
        final tRows = timetableRows.map((r) =>
          '<tr><td>${_escExamHtml(r.date)}</td><td>${_escExamHtml(r.day)}</td><td style="font-weight:800;">${_escExamHtml(r.stdLabel)}</td><td style="font-weight:800;">${_escExamHtml(r.subject)}</td><td>${_escExamHtml(r.time)}</td><td>${_escExamHtml(r.marks)}</td></tr>'
        ).join();
        return '<div class="sheet portrait">$hdr<h3>પરીક્ષાનું વિસ્તૃત સમયપત્રક (ધોરણ ૩ થી ૮)</h3><table><thead><tr><th>તારીખ</th><th>વાર</th><th>ધોરણ</th><th>વિષય</th><th>સમય</th><th>ગુણ</th></tr></thead><tbody>$tRows</tbody></table></div>';

      case 'seat_a':
      case 'seat_b':
        final isA = page.category == 'seat_a';
        final list = isA ? seatingA : seatingB;
        final sRows = list.map((r) =>
          '<tr><td style="font-weight:800;">બ્લોક ${r.blockNo}</td><td style="font-weight:800;">${_escExamHtml(r.className)}</td><td>${_escExamHtml(r.fromRoll)}</td><td>થી</td><td>${_escExamHtml(r.toRoll)}</td><td style="font-weight:800;">${_escExamHtml(r.totalCount)}</td><td>${_escExamHtml(r.remarks)}</td></tr>'
        ).join();
        return '<div class="sheet portrait">$hdr<h3>બ્લોકવાર બેઠક વ્યવસ્થા (${isA ? "ધોરણ ૩ થી ૫" : "ધોરણ ૬ થી ૮"})</h3><table><thead><tr><th>બ્લોક</th><th>ધોરણ</th><th>રોલ નં. થી</th><th></th><th>રોલ નં. સુધી</th><th>કુલ</th><th>રીમાર્કસ</th></tr></thead><tbody>$sRows</tbody></table></div>';

      case 'absent':
        if (page.subIndex >= absentSheets.length) return '';
        final sh = absentSheets[page.subIndex];
        final classes = getClassesForGroup(sh.group);
        final bRows = sh.blockRows.map((br) =>
          '<tr><td style="font-weight:800;">બ્લોક ${br.blockNo}</td><td>${_escExamHtml(br.allotted)}</td><td>${_escExamHtml(br.present)}</td>${classes.map((c) => "<td>${_escExamHtml(br.classAbsent[c] ?? '')}</td>").join()}<td>${_escExamHtml(br.totalAbsent)}</td><td>${_escExamHtml(br.sign)}</td></tr>'
        ).join();
        return '<div class="sheet landscape">$hdr<h3>દૈનિક ગેરહાજર વિદ્યાર્થી રિપોર્ટ — ધોરણ ${_escExamHtml(sh.stdLabel)} | તારીખ: ${_escExamHtml(sh.date)} (${_escExamHtml(sh.day)}) | વિષય: ${_escExamHtml(sh.subject)}</h3><table><thead><tr><th>બ્લોક</th><th>ફાળવાયેલ</th><th>હાજર</th>${classes.map((c) => "<th>${_escExamHtml(c)}</th>").join()}<th>કુલ ગે.હા.</th><th>સહી</th></tr></thead><tbody>$bRows</tbody></table></div>';

      case 'super_a':
      case 'super_b':
        final isA = page.category == 'super_a';
        final allRows = isA ? supervisionA : supervisionB;
        final perPage = isA ? superRowsPerPageA : superRowsPerPageB;
        final chunk = allRows.skip(page.subIndex * perPage).take(perPage);
        final supRows = chunk.map((r) =>
          '<tr><td>${_escExamHtml(r.date)}</td><td>${_escExamHtml(r.day)}</td><td style="font-weight:800;">${_escExamHtml(r.subject)}</td><td>બ્લોક ${r.blockNo}</td><td style="text-align:left;font-weight:800;">${_escExamHtml(r.invigilatorName)}</td><td>${_escExamHtml(r.sign)}</td></tr>'
        ).join();
        return '<div class="sheet portrait">$hdr<h3>ખંડ નિરીક્ષણ (સુપરવિઝન) આયોજન (${isA ? "ધોરણ ૩ થી ૫" : "ધોરણ ૬ થી ૮"})</h3><table><thead><tr><th>તારીખ</th><th>વાર</th><th>વિષય</th><th>બ્લોક</th><th>નિરીક્ષકનું નામ</th><th>સહી</th></tr></thead><tbody>$supRows</tbody></table></div>';

      case 'check_a':
      case 'check_b':
        final g = page.category == 'check_a' ? 'a' : 'b';
        final chunk = checkingRows.where((r) => r.group == g).skip(page.subIndex * checkRowsPerPage).take(checkRowsPerPage);
        final ckRows = chunk.map((r) =>
          '<tr><td>${_escExamHtml(r.date)}</td><td style="font-weight:800;">${_escExamHtml(r.subject)}</td><td>${_escExamHtml(r.className)}</td><td>${_escExamHtml(r.paperCount)}</td><td style="text-align:left;font-weight:800;">${_escExamHtml(r.examinerName)}</td><td>${_escExamHtml(r.examinerSignDate)}</td><td>${_escExamHtml(r.returnDate)}</td><td>${_escExamHtml(r.principalSign)}</td></tr>'
        ).join();
        return '<div class="sheet portrait">$hdr<h3>ઉત્તરવહી (પેપર) ચકાસણી આયોજન (${g == "a" ? "ધોરણ ૩ થી ૫" : "ધોરણ ૬ થી ૮"})</h3><table><thead><tr><th>તારીખ</th><th>વિષય</th><th>વર્ગ</th><th>સંખ્યા</th><th>પરીક્ષકનું નામ</th><th>સહી/તારીખ</th><th>પરત તારીખ</th><th>આચાર્ય સહી</th></tr></thead><tbody>$ckRows</tbody></table></div>';

      case 'qp_reg':
        final qRows = qpRegisterRows.map((r) =>
          '<tr>${r.map((c) => "<td>${_escExamHtml(c)}</td>").join()}</tr>'
        ).join();
        return '<div class="sheet portrait">$hdr<h3>પ્રશ્નપત્ર પેકેટ સીલ અને વિતરણ રજીસ્ટર</h3><table><thead><tr><th>ક્રમ</th><th>તારીખ</th><th>ધોરણ</th><th>વિષય</th><th>પેકેટ સંખ્યા</th><th>સીલ સ્થિતિ</th><th>ખોલ્યા સમય</th><th>સાક્ષી ૧ નામ/સહી</th><th>સાક્ષી ૨ નામ/સહી</th><th>આચાર્ય સહી</th></tr></thead><tbody>$qRows</tbody></table></div>';

      case 'stationery':
        final stRows = stationeryRows.map((r) =>
          '<tr>${r.map((c) => "<td>${_escExamHtml(c)}</td>").join()}</tr>'
        ).join();
        return '<div class="sheet portrait">$hdr<h3>ઉત્તરવહી અને સ્ટેશનરી જરૂરિયાત પત્રક</h3><table><thead><tr><th>ધોરણ / વર્ગ</th><th>રજીસ્ટર સંખ્યા</th><th>કુલ પેપર (વિષય)</th><th>જરૂરી ઉત્તરવહી</th><th>૫% અનામત સહિત</th><th>પુરવણી અંદાજ</th><th>નકશા / આલેખ</th><th>રીમાર્કસ</th></tr></thead><tbody>$stRows</tbody></table></div>';

      case 'instructions':
        final instructionRows = editableInstructions.asMap().entries.map((entry) =>
          '<tr><td>${entry.key + 1}</td><td style="text-align:left;">${_escExamHtml(entry.value)}</td></tr>'
        ).join();
        return '<div class="sheet portrait">$hdr<h3>પરીક્ષાલક્ષી સૂચનાઓ</h3><table><thead><tr><th>ક્રમ</th><th>સૂચના</th></tr></thead><tbody>$instructionRows</tbody></table></div>';

      default:
        return '<div class="sheet portrait">$hdr<h3>${_escExamHtml(page.title)}</h3><p style="text-align:center;font-weight:700;">આ પેજ પ્રિન્ટ માટે તૈયાર છે.</p></div>';
    }
  }

  Future<void> _showPrintExportDialog({required bool onlyCurrent}) async {
    final pages = onlyCurrent ? <NavPageItem>[currentNavPage] : allNavPages;
    if (_capturingForPdf) return;
    _showSnack(
      '⏳ PDF તૈયાર થઈ રહી છે (${pages.length} પેજ) — સ્ક્રીન પર દેખાય છે તે જ રીતે...',
    );
    try {
      Uint8List pdfBytes;
      try {
        pdfBytes = await _captureDisplayedPagesAsPdf(pages);
      } catch (_) {
        // Fallback: the older vector generator (e.g. when the page is not
        // attached to the screen on this platform).
        pdfBytes = await _generateDirectExamPlanningPdfBytes(pages);
      }
      await PsmFileExportHelper.saveOrShare(
        bytes: pdfBytes,
        filename: onlyCurrent
            ? 'exam_page_${currentNavPage.id}.pdf'
            : 'exam_planning_complete.pdf',
        title: 'Exam Planning PDF',
        mimeType: 'application/pdf',
      );
      _showSnack('🖨️ પરીક્ષા આયોજન PDF ડાઉનલોડ થઈ ગયું — સ્ક્રીન જેવું જ!');
    } catch (e) {
      _showSnack('PDF બનાવવામાં ભૂલ: $e', isError: true);
    }
  }

  /// Renders every requested page in the on-screen A4 frame and places the
  /// captured image on an A4 sheet of the page's own orientation, so the
  /// printout is identical to the preview (fonts, row heights, moved text,
  /// font scale and extra rows included).
  Future<Uint8List> _captureDisplayedPagesAsPdf(List<NavPageItem> pages) async {
    final originalPage = activePageId;
    final doc = pw.Document(title: '${meta.schoolName} — ${meta.examName}');
    setState(() => _capturingForPdf = true);
    try {
      for (final page in pages) {
        if (!mounted) break;
        setState(() => activePageId = page.id);
        await WidgetsBinding.instance.endOfFrame;
        // Second frame lets images/logo and layout settle.
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await WidgetsBinding.instance.endOfFrame;
        final boundary = _a4PageCaptureKey.currentContext?.findRenderObject();
        if (boundary is! RenderRepaintBoundary) {
          throw StateError('Page preview is not available for capture.');
        }
        final logicalWidth = boundary.size.width;
        // ~200 DPI on A4 width: sharp text, reasonable file size.
        final targetPx = page.isLandscape ? 2300.0 : 1650.0;
        final ratio = (targetPx / math.max(1.0, logicalWidth)).clamp(1.5, 3.0);
        final image = await boundary.toImage(pixelRatio: ratio);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (data == null) throw StateError('Could not capture page ${page.title}.');
        final png = pw.MemoryImage(data.buffer.asUint8List());
        final format = page.isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
        doc.addPage(pw.Page(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(12),
          build: (_) => pw.Center(child: pw.Image(png, fit: pw.BoxFit.contain)),
        ));
      }
    } finally {
      if (mounted) {
        setState(() {
          _capturingForPdf = false;
          activePageId = originalPage;
        });
      }
    }
    return doc.save();
  }

  static bool _examGujaratiFontLoaded = false;

  static Future<void> _ensureExamGujaratiFontLoaded() async {
    if (_examGujaratiFontLoaded) return;
    try {
      final loader = FontLoader('NotoSansGujaratiLocal');
      loader.addFont(rootBundle.load('assets/fonts/NotoSansGujarati-Regular.ttf'));
      loader.addFont(rootBundle.load('assets/fonts/NotoSansGujarati-Bold.ttf'));
      await loader.load();
    } catch (_) {}
    try {
      final fallback = FontLoader('LohitGujaratiLocal');
      fallback.addFont(rootBundle.load('assets/fonts/Lohit-Gujarati.ttf'));
      await fallback.load();
    } catch (_) {}
    _examGujaratiFontLoaded = true;
  }

  final Map<String, pw.MemoryImage> _examPdfTextCache =
      <String, pw.MemoryImage>{};
  final Map<pw.MemoryImage, double> _examPdfTextHeightPt =
      <pw.MemoryImage, double>{};

  pw.Widget _pdfImg(pw.MemoryImage? img, {double fallbackHeight = 13.0}) {
    if (img == null) return pw.SizedBox();
    final h = _examPdfTextHeightPt[img] ?? fallbackHeight;
    return pw.Image(img, height: h, fit: pw.BoxFit.contain);
  }

  Future<pw.MemoryImage?> _renderExamTextImage(
    String text, {
    double fontSize = 11.5,
    bool bold = true,
    Color color = const Color(0xFF0B2A5B),
    double maxWidth = 420,
    TextAlign textAlign = TextAlign.center,
  }) async {
    await _ensureExamGujaratiFontLoaded();
    final clean = text
        .replaceAll('★', '*')
        .replaceAll(RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]', unicode: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.isEmpty) return null;
    final cacheKey =
        'v3|$clean|${fontSize.toStringAsFixed(2)}|$bold|${color.toARGB32()}|${maxWidth.toStringAsFixed(1)}|${textAlign.index}';
    final cached = _examPdfTextCache[cacheKey];
    if (cached != null) return cached;
    try {
      const scale = 2.4;
      final span = TextSpan(
        text: clean,
        style: TextStyle(
          fontFamily: 'NotoSansGujaratiLocal',
          fontFamilyFallback: const <String>['LohitGujaratiLocal'],
          fontSize: fontSize * scale,
          fontWeight: bold ? FontWeight.bold : FontWeight.w500,
          color: color,
          height: 1.25,
        ),
      );
      final painter = TextPainter(
        text: span,
        textAlign: textAlign,
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: maxWidth * scale);

      final w = math.max(4, painter.width.ceil() + 6);
      final h = math.max(4, painter.height.ceil() + 4);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      );
      painter.paint(canvas, const Offset(3, 2));
      final picture = recorder.endRecording();
      final img = await picture.toImage(w, h);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      picture.dispose();
      if (byteData == null) return null;
      final memImg = pw.MemoryImage(byteData.buffer.asUint8List());
      if (_examPdfTextCache.length > 3000) {
        _examPdfTextCache.clear();
        _examPdfTextHeightPt.clear();
      }
      _examPdfTextCache[cacheKey] = memImg;
      _examPdfTextHeightPt[memImg] = (h / scale).clamp(8.0, 260.0);
      return memImg;
    } catch (_) {
      return null;
    }
  }

  Future<pw.Widget> _buildExamPdfTable({
    required List<String> headers,
    required List<List<String>> rows,
    double cellMaxWidth = 110,
    double rowHeight = 6.0,
    double fontScale = 1.0,
    Set<int> leftAlignCols = const <int>{},
    Map<int, double>? colMaxWidths,
    Map<int, pw.TableColumnWidth>? columnWidths,
  }) async {
    final double vPad = (rowHeight * 0.78).clamp(1.5, 28.0);
    final double fs = fontScale.clamp(0.75, 1.50);
    final headerWidgets = <pw.Widget>[];
    for (int cIdx = 0; cIdx < headers.length; cIdx++) {
      final h = headers[cIdx];
      final maxW = colMaxWidths?[cIdx] ?? cellMaxWidth;
      final hImg = await _renderExamTextImage(
        h,
        fontSize: 9.8 * fs,
        bold: true,
        color: Colors.white,
        maxWidth: maxW,
      );
      headerWidgets.add(
        pw.Container(
          padding: pw.EdgeInsets.symmetric(vertical: vPad, horizontal: 4),
          alignment: pw.Alignment.center,
          color: PdfColor.fromInt(0xFF0B2A5B),
          child: hImg != null
              ? _pdfImg(hImg, fallbackHeight: 13.5 * fs)
              : pw.Text(h,
                  style: pw.TextStyle(fontSize: 8.5 * fs, color: PdfColors.white)),
        ),
      );
    }

    final tableRows = <pw.TableRow>[
      pw.TableRow(children: headerWidgets),
    ];

    for (int rIdx = 0; rIdx < rows.length; rIdx++) {
      final r = rows[rIdx];
      final isTotalRow = r.any((cell) =>
          cell.contains('કુલ') || cell.contains('એકંદર'));
      final rowCells = <pw.Widget>[];
      for (int cIdx = 0; cIdx < headers.length; cIdx++) {
        final cellText = cIdx < r.length ? r[cIdx] : '';
        final isLeft = leftAlignCols.contains(cIdx) && !isTotalRow;
        final maxW = colMaxWidths?[cIdx] ?? cellMaxWidth;
        final cImg = await _renderExamTextImage(
          cellText.isEmpty ? '-' : cellText,
          fontSize: (isTotalRow ? 9.8 : 9.4) * fs,
          bold: isTotalRow || cIdx == 0,
          color: isTotalRow
              ? const Color(0xFF0B2A5B)
              : const Color(0xFF0F172A),
          maxWidth: maxW,
          textAlign: isLeft ? TextAlign.left : TextAlign.center,
        );
        rowCells.add(
          pw.Container(
            padding: pw.EdgeInsets.symmetric(vertical: vPad, horizontal: 4),
            alignment:
                isLeft ? pw.Alignment.centerLeft : pw.Alignment.center,
            color: isTotalRow
                ? PdfColor.fromInt(0xFFFFF1DD)
                : (rIdx.isEven
                    ? PdfColors.white
                    : PdfColor.fromInt(0xFFF4F7FD)),
            child: cImg != null
                ? _pdfImg(cImg, fallbackHeight: 13.0 * fs)
                : pw.Text(cellText,
                    style: pw.TextStyle(fontSize: 8.0 * fs)),
          ),
        );
      }
      tableRows.add(pw.TableRow(children: rowCells));
    }

    return pw.Table(
      columnWidths: columnWidths,
      border: pw.TableBorder.all(
        color: PdfColor.fromInt(0xFF0B2A5B),
        width: 0.9,
      ),
      children: tableRows,
    );
  }

  pw.Widget _buildExamPdfTricolorBar() {
    return pw.Row(
      children: [
        pw.Expanded(
          child: pw.Container(height: 5, color: PdfColor.fromInt(0xFFFF9933)),
        ),
        pw.Expanded(
          child: pw.Container(height: 5, color: PdfColor.fromInt(0xFF0B2A5B)),
        ),
        pw.Expanded(
          child: pw.Container(height: 5, color: PdfColor.fromInt(0xFF138808)),
        ),
      ],
    );
  }

  (String, String?) _pdfHeaderTitleAndSubtitle(NavPageItem page) {
    switch (page.category) {
      case 'index':
        return ('અનુક્રમણિકા અને પ્રમાણપત્ર', null);
      case 'dashboard':
        return (
          'પરીક્ષા આયોજન — એક નજરે (આચાર્ય ડેશબોર્ડ)',
          'રજીસ્ટર, બેઠક વ્યવસ્થા, સમયપત્રક અને શિક્ષક માહિતી પરથી આપોઆપ તૈયાર થતો સંકલિત સારાંશ'
        );
      case 'teachers':
        final perPage = _effectiveRowsPerPage(26, pageIdPrefix: 'teachers');
        final totalPages = (_examDutyTeachers.length / perPage).ceil().clamp(1, 99);
        return (
          'શિક્ષક માહિતી અને ઓટો સુપરવિઝન',
          'સમયપત્રકના વિષય પ્રમાણે બ્લોકવાર નિરીક્ષક, સમિતિ અને પેપર ચકાસણીની આપમેળે ફાળવણી${totalPages > 1 ? " (પેજ ${page.subIndex + 1} / $totalPages)" : ""}'
        );
      case 'committee':
        return ('પરીક્ષા સમિતિ', null);
      case 'register':
        final isBoysOnly = genderMode == 'boys';
        final isGirlsOnly = genderMode == 'girls';
        final modeSub = isBoysOnly
            ? 'શાળા પ્રકાર: ફક્ત કુમાર (Only Boys)'
            : isGirlsOnly
                ? 'શાળા પ્રકાર: ફક્ત કન્યા (Only Girls)'
                : 'શાળા પ્રકાર: કુમાર અને કન્યા બંને (Boys + Girls = Total)';
        final perPage = _effectiveRowsPerPage(27, pageIdPrefix: 'register');
        final totalPages =
            (_totalRegisterDisplayRowCount() / perPage).ceil().clamp(1, 99);
        return (
          'ધોરણવાર રજીસ્ટર સંખ્યા',
          totalPages > 1 ? '$modeSub — પેજ ${page.subIndex + 1} / $totalPages' : modeSub
        );
      case 'timetable':
        final perPage = _effectiveRowsPerPage(27, pageIdPrefix: 'timetable');
        final totalPages = (timetableRows.length / perPage).ceil().clamp(1, 99);
        return (
          'ધોરણ ૩ થી ૮ (સમયપત્રક)',
          totalPages > 1 ? 'પેજ ${page.subIndex + 1} / $totalPages' : null
        );
      case 'seat_a':
      case 'seat_b':
        final isA = page.category == 'seat_a';
        final label = isA ? '૩ થી ૫' : '૬ થી ૮';
        final perPage = _effectiveRowsPerPage(27, pageIdPrefix: page.category);
        final totalPages =
            (_totalSeatingDisplayRowCount(isA ? 'a' : 'b') / perPage)
                .ceil()
                .clamp(1, 99);
        return (
          'પરીક્ષાની બેઠક વ્યવસ્થા',
          totalPages > 1
              ? 'ધોરણ $label — પેજ ${page.subIndex + 1} / $totalPages'
              : 'ધોરણ $label'
        );
      case 'absent':
        if (page.subIndex < absentSheets.length) {
          final sh = absentSheets[page.subIndex];
          return (
            'પરીક્ષામાં ગેરહાજર બાળકોની માહિતી',
            'ધોરણ ${sh.stdLabel}  |  તારીખ: ${sh.date}  |  વાર: ${sh.day}  |  વિષય: ${sh.subject}'
          );
        }
        return (page.title, null);
      case 'super_a':
      case 'super_b':
        final isA = page.category == 'super_a';
        final label = isA ? '૩ થી ૫' : '૬ થી ૮';
        final allRows = isA ? supervisionA : supervisionB;
        final baseCap = isA ? superRowsPerPageA : superRowsPerPageB;
        final perPage = _effectiveRowsPerPage(baseCap, pageIdPrefix: page.category);
        final totalPages = (allRows.length / perPage).ceil().clamp(1, 99);
        return (
          'નિરીક્ષણ કાર્યનું આયોજન',
          'ધોરણ $label — પેજ ${page.subIndex + 1} / $totalPages'
        );
      case 'check_a':
      case 'check_b':
        final isA = page.category == 'check_a';
        final label = isA ? '૩ થી ૫' : '૬ થી ૮';
        final groupRows =
            checkingRows.where((r) => r.group == (isA ? 'a' : 'b')).toList();
        final perPage =
            _effectiveRowsPerPage(checkRowsPerPage, pageIdPrefix: page.category);
        final totalPages = (groupRows.length / perPage).ceil().clamp(1, 99);
        return (
          'પેપર ચકાસણી આયોજન',
          'ધોરણ $label — સમયપત્રક, રજીસ્ટર અને વિષય શિક્ષક મુજબ આપમેળે (પેજ ${page.subIndex + 1} / $totalPages)'
        );
      case 'qp_reg':
        final perPage = _effectiveRowsPerPage(27, pageIdPrefix: 'qp_reg');
        final totalPages = (qpRegisterRows.length / perPage).ceil().clamp(1, 99);
        return (
          'પ્રશ્નપત્ર પેકેટ સીલ અને વિતરણ રજીસ્ટર',
          'સમયપત્રક, રજીસ્ટર સંખ્યા અને શિક્ષક યાદી મુજબ પ્રશ્નપત્ર પેકેટ ખોલ્યાનું તથા વિતરણનું રજીસ્ટર${totalPages > 1 ? " (પેજ ${page.subIndex + 1} / $totalPages)" : ""}'
        );
      case 'stationery':
        final perPage = _effectiveRowsPerPage(27, pageIdPrefix: 'stationery');
        final totalPages = (stationeryRows.length / perPage).ceil().clamp(1, 99);
        return (
          'ઉત્તરવહી અને સ્ટેશનરી જરૂરિયાત પત્રક',
          'ધોરણવાર રજીસ્ટર સંખ્યા અને વિષયો મુજબ ઉત્તરવહી, પુરવણી અને સ્ટેશનરીનો આપોઆપ હિસાબ${totalPages > 1 ? " (પેજ ${page.subIndex + 1} / $totalPages)" : ""}'
        );
      case 'instructions':
        final perPage = _effectiveRowsPerPage(20, pageIdPrefix: 'instructions');
        final totalPages =
            (editableInstructions.length / perPage).ceil().clamp(1, 99);
        return (
          'પરીક્ષાલક્ષી સૂચનાઓ',
          totalPages > 1 ? 'પેજ ${page.subIndex + 1} / $totalPages' : null
        );
      default:
        return (page.title, null);
    }
  }

  Future<Uint8List> _generateDirectExamPlanningPdfBytes(
    List<NavPageItem> pages,
  ) async {
    final doc = pw.Document();
    final logoImg = (_schoolLogoBytes != null && _schoolLogoBytes!.isNotEmpty)
        ? pw.MemoryImage(_schoolLogoBytes!)
        : null;

    final schoolNameImg = await _renderExamTextImage(
      meta.schoolName,
      fontSize: 15.5,
      bold: true,
      color: const Color(0xFF0B2A5B),
      maxWidth: 480,
    );
    final schoolSubImg = await _renderExamTextImage(
      meta.address,
      fontSize: 10.5,
      bold: true,
      color: const Color(0xFF475569),
      maxWidth: 500,
    );
    final talDistExamImg = await _renderExamTextImage(
      customTextOverrides['hdr_taluka_dist_exam'] ??
          'તાલુકો: ${meta.taluka}  |  જિલ્લો: ${meta.district}  |  ${meta.examName} ${meta.academicYear}',
      fontSize: 11.2,
      bold: true,
      color: const Color(0xFF138808),
      maxWidth: 500,
    );
    final footerLeftImg = await _renderExamTextImage(
      meta.schoolName,
      fontSize: 9.8,
      bold: true,
      color: const Color(0xFF475569),
      maxWidth: 260,
      textAlign: TextAlign.left,
    );
    final footerRightImg = await _renderExamTextImage(
      customTextOverrides['ftr_principal_sign_right'] ??
          'આચાર્યની સહી / સિક્કો: ____________',
      fontSize: 9.8,
      bold: true,
      color: const Color(0xFF475569),
      maxWidth: 260,
      textAlign: TextAlign.right,
    );

    for (final page in pages) {
      if (page.category == 'exam_setup') continue;
      final double pageRh =
          _rowHeightForPrefix(page.category, fallbackPageId: page.id);
      final double pageFs =
          _fontPctForPrefix(page.category, fallbackPageId: page.id) / 100.0;

      if (page.category == 'cover') {
        final mangalImg = await _renderExamTextImage(
          customTextOverrides['cover_mangalacharan'] ??
              '॥ શ્રી ગણેશાય નમઃ ॥  •  તમસો મા જ્યોતિર્ગમય',
          fontSize: 12 * pageFs,
          bold: true,
          color: const Color(0xFFD97706),
          maxWidth: 460,
        );
        final mainTitleImg = await _renderExamTextImage(
          customTextOverrides['cover_main_heading'] ?? 'પરીક્ષા આયોજન ફાઈલ',
          fontSize: 26 * pageFs,
          bold: true,
          color: const Color(0xFF0B2A5B),
          maxWidth: 480,
        );
        final subHeadingImg = await _renderExamTextImage(
          customTextOverrides['cover_sub_heading'] ??
              'સંપૂર્ણ ઓટોમેટિક પરીક્ષા સંચાલન અને રજીસ્ટર દસ્તાવેજ',
          fontSize: 13 * pageFs,
          bold: true,
          color: const Color(0xFF0F766E),
          maxWidth: 480,
        );
        final coverSchoolImg = await _renderExamTextImage(
          meta.schoolName,
          fontSize: 20 * pageFs,
          bold: true,
          color: const Color(0xFF0B2A5B),
          maxWidth: 480,
        );
        final coverAddrImg = await _renderExamTextImage(
          meta.address,
          fontSize: 13 * pageFs,
          bold: true,
          color: const Color(0xFF143C82),
          maxWidth: 480,
        );
        final coverTalDistImg = await _renderExamTextImage(
          'તાલુકો: ${meta.taluka}   |   જિલ્લો: ${meta.district}',
          fontSize: 13 * pageFs,
          bold: true,
          color: const Color(0xFF143C82),
          maxWidth: 460,
        );
        final coverExamImg = await _renderExamTextImage(
          customTextOverrides['cover_exam_name_pill'] ?? meta.examName,
          fontSize: 18 * pageFs,
          bold: true,
          color: const Color(0xFFB91C1C),
          maxWidth: 440,
        );
        final coverYearPayImg = await _renderExamTextImage(
          'શૈક્ષણિક વર્ષ: ${meta.academicYear}   |   પગારકેન્દ્ર: ${meta.payCenter}',
          fontSize: 13.5 * pageFs,
          bold: true,
          color: const Color(0xFF138808),
          maxWidth: 480,
        );
        final coverPrinImg = await _renderExamTextImage(
          customTextOverrides['cover_principal'] ??
              'આચાર્યનું નામ: ${meta.principalName}',
          fontSize: 12 * pageFs,
          bold: true,
          color: const Color(0xFF0B2A5B),
          maxWidth: 240,
        );
        final coverCrcImg = await _renderExamTextImage(
          customTextOverrides['cover_crc'] ??
              'સી.આર.સી. કો-ઓર્ડિનેટર: ${meta.crcName}',
          fontSize: 12 * pageFs,
          bold: true,
          color: const Color(0xFF0B2A5B),
          maxWidth: 240,
        );

        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(16),
            build: (ctx) => pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                  color: PdfColor.fromInt(0xFF0B2A5B),
                  width: 2.5,
                ),
                borderRadius: pw.BorderRadius.circular(10),
              ),
              padding: const pw.EdgeInsets.all(4),
              child: pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                    color: PdfColor.fromInt(0xFFFF9933),
                    width: 1.2,
                  ),
                  borderRadius: pw.BorderRadius.circular(7),
                ),
                padding: const pw.EdgeInsets.all(20),
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Column(
                      children: [
                        _buildExamPdfTricolorBar(),
                        pw.SizedBox(height: 10),
                        if (mangalImg != null) _pdfImg(mangalImg),
                        pw.SizedBox(height: 14),
                        if (logoImg != null)
                          pw.Transform.translate(
                            offset: PdfPoint(coverLogoOffset.dx * 0.76, -coverLogoOffset.dy * 0.76),
                            child: pw.SizedBox(
                              width: (coverLogoSize * 0.80).clamp(45.0, 220.0),
                              height: (coverLogoSize * 0.80).clamp(45.0, 220.0),
                              child: pw.Image(logoImg, fit: pw.BoxFit.contain),
                            ),
                          ),
                        pw.SizedBox(height: 14),
                        if (mainTitleImg != null) _pdfImg(mainTitleImg),
                        pw.SizedBox(height: 6),
                        if (subHeadingImg != null) _pdfImg(subHeadingImg),
                      ],
                    ),
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.all(18),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFFF4F7FD),
                        border: pw.Border.all(
                          color: PdfColor.fromInt(0xFF0B2A5B),
                          width: 1.5,
                        ),
                        borderRadius: pw.BorderRadius.circular(10),
                      ),
                      child: pw.Column(
                        children: [
                          if (coverSchoolImg != null) _pdfImg(coverSchoolImg),
                          pw.SizedBox(height: 6),
                          if (coverAddrImg != null) _pdfImg(coverAddrImg),
                          pw.SizedBox(height: 4),
                          if (coverTalDistImg != null) _pdfImg(coverTalDistImg),
                          pw.SizedBox(height: 12),
                          if (coverExamImg != null)
                            pw.Container(
                              padding: const pw.EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 6),
                              decoration: pw.BoxDecoration(
                                color: PdfColor.fromInt(0xFFFFF3E0),
                                borderRadius: pw.BorderRadius.circular(6),
                              ),
                              child: _pdfImg(coverExamImg),
                            ),
                          pw.SizedBox(height: 10),
                          if (coverYearPayImg != null) _pdfImg(coverYearPayImg),
                        ],
                      ),
                    ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        if (coverPrinImg != null) _pdfImg(coverPrinImg),
                        if (coverCrcImg != null) _pdfImg(coverCrcImg),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        continue;
      }

      final (defaultHdrTitle, defaultHdrSubtitle) = _pdfHeaderTitleAndSubtitle(page);
      final pageTitleImg = await _renderExamTextImage(
        customTextOverrides['hdr_title_${page.id}'] ?? defaultHdrTitle,
        fontSize: 15.5,
        bold: true,
        color: Colors.white,
        maxWidth: page.isLandscape ? 680 : 460,
      );
      final pageSubtitleText =
          customTextOverrides['hdr_sub_${page.id}'] ?? defaultHdrSubtitle;
      final pageSubtitleImg = (pageSubtitleText != null && pageSubtitleText.isNotEmpty)
          ? await _renderExamTextImage(
              pageSubtitleText,
              fontSize: 10.2,
              bold: true,
              color: const Color(0xFF0B2A5B),
              maxWidth: page.isLandscape ? 700 : 480,
            )
          : null;

      pw.Widget bodyWidget;
      switch (page.category) {
        case 'dashboard':
          final totalClasses = registerRows.length;
          final totalStudents = registerRows.fold<int>(
              0, (s, r) => s + r.total(genderMode));
          final uniqueDates = timetableRows.map((e) => e.date).toSet().toList();
          final totalBlocks = (hasGroupA ? blocksA : 0) + (hasGroupB ? blocksB : 0);
          int totalAnsSheets = 0;
          for (final r in registerRows) {
            if (_classHasAnswersInQuestionPaper(r.className)) continue;
            final subs = getSubjectsForClass(r.className, r.group);
            totalAnsSheets +=
                r.total(genderMode) * (subs.isNotEmpty ? subs.length : 5);
          }
          final totalAnsWithReserve = include5PercentReserveInStationery
              ? (totalAnsSheets * 1.05).ceil()
              : totalAnsSheets;

          final kpiSummaryTable = await _buildExamPdfTable(
            headers: [
              'કુલ વર્ગો / વિદ્યાર્થીઓ',
              'કુલ પરીક્ષા બ્લોક',
              'કુલ શિક્ષકો',
              'દિવસો / પેપર',
              'ઉત્તરવહી બંડલ',
              'કુલ ઉત્તરવહી જરૂરિયાત',
            ],
            rows: [
              [
                '${gn(totalClasses)} વર્ગો (${gn(totalStudents)})',
                '${gn(totalBlocks)} બ્લોક',
                '${gn(_examDutyTeachers.length)} શિક્ષકો',
                '${gn(uniqueDates.length)} દિવસ / ${gn(timetableRows.length)} પેપર',
                '${gn(totalClasses)} બંડલ',
                '${gn(totalAnsWithReserve)} નંગ',
              ],
            ],
            cellMaxWidth: 95,
            rowHeight: pageRh,
            fontScale: pageFs,
          );

          final dailySummaryRows = <List<String>>[];
          for (final dtStr in uniqueDates) {
            final dayExams = timetableRows.where((x) => x.date == dtStr).toList();
            final dayName = dayExams.isNotEmpty ? dayExams.first.day : '';
            final exA = dayExams.where((x) => x.group == 'a').firstOrNull;
            final exB = dayExams.where((x) => x.group == 'b').firstOrNull;
            final cntA = exA != null ? getStudentCountForExam('a', exA.stdLabel) : 0;
            final cntB = exB != null ? getStudentCountForExam('b', exB.stdLabel) : 0;
            final neededBlocks =
                (exA != null && hasGroupA ? blocksA : 0) + (exB != null && hasGroupB ? blocksB : 0);
            dailySummaryRows.add([
              dtStr,
              dayName,
              exA != null ? '${exA.subject} (ધો. ${exA.stdLabel}) — $cntA' : '—',
              exB != null ? '${exB.subject} (ધો. ${exB.stdLabel}) — $cntB' : '—',
              '${cntA + cntB}',
              '$neededBlocks બ્લોક',
              '$neededBlocks નિરીક્ષક',
            ]);
          }
          final dailyTable = await _buildExamPdfTable(
            headers: [
              'તારીખ',
              'વાર',
              'ધોરણ ૩ થી ૫ (વિષય / સંખ્યા)',
              'ધોરણ ૬ થી ૮ (વિષય / સંખ્યા)',
              'દૈનિક કુલ',
              'જરૂરી બ્લોક',
              'જરૂરી નિરીક્ષક',
            ],
            rows: dailySummaryRows,
            cellMaxWidth: 115,
            rowHeight: pageRh,
            fontScale: pageFs,
          );
          final bellTable = await _buildExamPdfTable(
            headers: [
              'ક્રમ',
              'બેલનો પ્રકાર / સૂચના',
              'સવાર / બપોર પાળી (૩–૫)',
              'બપોર પાળી (૬–૮)',
              'નોંધ / સૂચના',
            ],
            rows: bellScheduleRows,
            cellMaxWidth: 135,
            rowHeight: pageRh,
            fontScale: pageFs,
          );
          bodyWidget = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              kpiSummaryTable,
              pw.SizedBox(height: 8),
              dailyTable,
              pw.SizedBox(height: 8),
              bellTable,
            ],
          );
          break;
        case 'index':
          final totalClasses = registerRows.length;
          final totalStudents =
              registerRows.fold<int>(0, (s, r) => s + r.total(genderMode));
          final std35Total = registerRows
              .where((r) => r.group == 'a')
              .fold<int>(0, (s, r) => s + r.total(genderMode));
          final std68Total = registerRows
              .where((r) => r.group == 'b')
              .fold<int>(0, (s, r) => s + r.total(genderMode));
          final absCountA = absentSheets.where((s) => s.group == 'a').length;
          final absCountB = absentSheets.where((s) => s.group == 'b').length;
          final defaultIdxRows = [
            ['૧', 'કવર પેજ (શાળા અને પરીક્ષાની મુખ્ય વિગત)', 'ધોરણ ૩ થી ૮', 'Portrait (P)', '૧ પેજ', '✓ તૈયાર'],
            ['૨', 'અનુક્રમણિકા અને આયોજન પ્રમાણપત્ર', 'ધોરણ ૩ થી ૮', 'Portrait (P)', '૧ પેજ', '✓ ઓટો-લિંક'],
            ['૩', 'પરીક્ષા આયોજન — એક નજરે (આચાર્ય ડેશબોર્ડ)', 'ધોરણ ૩ થી ૮', 'Portrait (P)', '૧ પેજ', '$totalStudents વિદ્યાર્થી'],
            ['૪', 'શિક્ષક માહિતી અને ઓટો-સુપરવિઝન સેટઅપ', 'ધોરણ ૩ થી ૮', 'Portrait (P)', '૧ પેજ', '${_examDutyTeachers.length} શિક્ષકો'],
            ['૫', 'પરીક્ષા સમિતિ અને કામગીરીની ફાળવણી', 'ધોરણ ૩ થી ૮', 'Portrait (P)', '૧ પેજ', '૮ સભ્યો / કામગીરી'],
            ['૬', 'ધોરણવાર રજીસ્ટર સંખ્યા પત્રક', 'ધોરણ ૩ થી ૮', 'Portrait (P)', '૧ પેજ', '$totalClasses વર્ગો ($totalStudents)'],
            ['૭', 'પરીક્ષાનું વિસ્તૃત સમયપત્રક', 'ધોરણ ૩ થી ૮', 'Portrait (P)', '૧ પેજ', '${timetableRows.length} પેપર'],
            ['૮', 'બ્લોકવાર બેઠક વ્યવસ્થા (ધોરણ ૩ થી ૫)', 'ધોરણ ૩ થી ૫', 'Portrait (P)', '૧ પેજ', '$blocksA બ્લોક ($std35Total)'],
            ['૯', 'બ્લોકવાર બેઠક વ્યવસ્થા (ધોરણ ૬ થી ૮)', 'ધોરણ ૬ થી ૮', 'Portrait (P)', '૧ પેજ', '$blocksB બ્લોક ($std68Total)'],
            ['૧૦', 'દૈનિક ગેરહાજર વિદ્યાર્થી રિપોર્ટ (૩ થી ૫)', 'ધોરણ ૩ થી ૫', 'Landscape (L)', '$absCountA પેજ', '✓ માત્ર ફાળવાયેલ સંખ્યા'],
            ['૧૧', 'દૈનિક ગેરહાજર વિદ્યાર્થી રિપોર્ટ (૬ થી ૮)', 'ધોરણ ૬ થી ૮', 'Landscape (L)', '$absCountB પેજ', '✓ માત્ર ફાળવાયેલ સંખ્યા'],
            ['૧૨', 'ખંડ નિરીક્ષણ (સુપરવિઝન) કાર્યનું આયોજન', 'ધોરણ ૩ થી ૮', 'Portrait (P)', '૨+ પેજ', '✓ ઓટો-ફાળવણી'],
            ['૧૩', 'ઉત્તરવહી (પેપર) ચકાસણી આયોજન પત્રક', 'ધોરણ ૩ થી ૮', 'Portrait (P)', '૨+ પેજ', '✓ પરીક્ષક ઓટો-ફિલ'],
            ['૧૪', 'ઉત્તરવહી બંડલ પર ચોંટાડવાના વર્ગવાર સ્ટીકર', 'ધોરણ ૩ થી ૮', 'Portrait (P)', '$totalClasses વર્ગ', '✓ રજીસ્ટર ઓટો-લિંક'],
            ['૧૫', 'ખંડ બહાર ચોંટાડવાના બ્લોક ડોર સ્ટીકર', 'ધોરણ ૩ થી ૮', 'Portrait (P)', '${blocksA + blocksB} બ્લોક', '✓ બેઠક ઓટો-લિંક'],
            ['૧૬', 'પ્રશ્નપત્ર પેકેટ સીલ અને વિતરણ રજીસ્ટર', 'ધોરણ ૩ થી ૮', 'Portrait (P)', '૧ પેજ', '${timetableRows.length} પેપર હિસાબ'],
            ['૧૭', 'ઉત્તરવહી અને સ્ટેશનરી જરૂરિયાત પત્રક', 'ધોરણ ૩ થી ૮', 'Portrait (P)', '૧ પેજ', '૫% અનામત સહિત'],
            ['૧૮', 'પરીક્ષાલક્ષી અગત્યની સૂચનાઓ', 'ધોરણ ૩ થી ૮', 'Portrait (P)', '૧ પેજ', '૨૦ નિયમો'],
          ];
          final idxRowsOut = <List<String>>[
            for (int i = 0; i < defaultIdxRows.length; i++)
              [
                for (int c = 0; c < 6; c++)
                  indexCellOverrides['$i:$c'] ?? defaultIdxRows[i][c],
              ],
          ];
          final certImg = await _renderExamTextImage(
            _certificateStatement,
            fontSize: 10.2 * pageFs,
            bold: true,
            color: const Color(0xFF0F172A),
            maxWidth: 480,
            textAlign: TextAlign.left,
          );
          final idxTable = await _buildExamPdfTable(
            headers: [
              'ક્રમ',
              'પત્રક / વિભાગનું નામ',
              'ધોરણ / જૂથ',
              'પેજ માપ',
              'વિગત / સંખ્યા',
              'ઓટો-સિંક સ્થિતિ',
            ],
            rows: idxRowsOut,
            cellMaxWidth: 185,
            rowHeight: pageRh,
            fontScale: pageFs,
            leftAlignCols: const <int>{1},
          );
          bodyWidget = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              idxTable,
              if (certImg != null) ...[
                pw.SizedBox(height: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFFFFAF2),
                    border: pw.Border.all(
                      color: PdfColor.fromInt(0xFF0B2A5B),
                      width: 1.5,
                    ),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: _pdfImg(certImg),
                ),
              ],
            ],
          );
          break;
        case 'teachers':
          final dutyList = _examDutyTeachers;
          final perPage = _effectiveRowsPerPage(26, pageIdPrefix: 'teachers');
          final start = page.subIndex * perPage;
          final chunk = dutyList.skip(start).take(perPage).toList();
          bodyWidget = await _buildExamPdfTable(
            headers: ['ક્રમ', 'શિક્ષકનું નામ', 'ભણાવતું જૂથ', 'ભણાવેલા વિષયો'],
            rows: [
              for (int i = 0; i < chunk.length; i++)
                [
                  '${start + i + 1}',
                  chunk[i].assignedClasses.isNotEmpty
                      ? '${chunk[i].name} (વર્ગ: ${chunk[i].assignedClasses.join(", ")})'
                      : chunk[i].name,
                  chunk[i].group == 'a' ? 'ધો. ૩ થી ૫' : 'ધો. ૬ થી ૮',
                  chunk[i].subjects.join(', '),
                ],
            ],
            cellMaxWidth: 180,
            rowHeight: pageRh,
            fontScale: pageFs,
            leftAlignCols: const <int>{1},
          );
          break;
        case 'committee':
          final t1 = await _buildExamPdfTable(
            headers: ['અ.નં.', 'શિક્ષકનું નામ', 'હોદ્દો', 'સહી'],
            rows: committeeRows
                .asMap()
                .entries
                .map((e) => [
                      '${e.key + 1}',
                      e.value.teacherName,
                      e.value.roleOrDuty,
                      e.value.sign,
                    ])
                .toList(),
            cellMaxWidth: 165,
            rowHeight: pageRh,
            fontScale: pageFs,
          );
          final subHdrImg = await _renderExamTextImage(
            'પરીક્ષાલક્ષી કામગીરીની ફાળવણી',
            fontSize: 12.5 * pageFs,
            bold: true,
            color: const Color(0xFF0B2A5B),
            maxWidth: 420,
          );
          final t2 = await _buildExamPdfTable(
            headers: ['અ.નં.', 'શિક્ષકનું નામ', 'સોંપેલ કામગીરી', 'સહી'],
            rows: workDutyRows
                .asMap()
                .entries
                .map((e) => [
                      '${e.key + 1}',
                      e.value.teacherName,
                      e.value.roleOrDuty,
                      e.value.sign,
                    ])
                .toList(),
            cellMaxWidth: 165,
            rowHeight: pageRh,
            fontScale: pageFs,
          );
          bodyWidget = pw.Column(
            children: [
              t1,
              pw.SizedBox(height: 8),
              if (subHdrImg != null) ...[
                _pdfImg(subHdrImg),
                pw.SizedBox(height: 4),
              ],
              t2,
            ],
          );
          break;
        case 'register':
          final isBoysOnly = genderMode == 'boys';
          final isGirlsOnly = genderMode == 'girls';
          final rowsA = registerRows.where((r) => r.group == 'a').toList();
          final rowsB = registerRows.where((r) => r.group == 'b').toList();
          final boysA = rowsA.fold<int>(0, (s, r) => s + r.boys);
          final girlsA = rowsA.fold<int>(0, (s, r) => s + r.girls);
          final totA = rowsA.fold<int>(0, (s, r) => s + r.total(genderMode));
          final boysB = rowsB.fold<int>(0, (s, r) => s + r.boys);
          final girlsB = rowsB.fold<int>(0, (s, r) => s + r.girls);
          final totB = rowsB.fold<int>(0, (s, r) => s + r.total(genderMode));

          List<String> regRowCells(RegisterRow r) {
            if (isBoysOnly || isGirlsOnly) {
              return [r.className, '${r.total(genderMode)}', r.teacherSign, r.remarks];
            }
            return [r.className, '${r.boys}', '${r.girls}', '${r.total(genderMode)}', r.teacherSign, r.remarks];
          }
          List<String> regTotalCells(String lbl, int bSum, int gSum, int tSum) {
            if (isBoysOnly || isGirlsOnly) return [lbl, '$tSum', '', ''];
            return [lbl, '$bSum', '$gSum', '$tSum', '', ''];
          }
          final allRowsOut = <List<String>>[
            if (rowsA.isNotEmpty) ...[
              for (final r in rowsA) regRowCells(r),
              regTotalCells('૩ થી ૫ કુલ', boysA, girlsA, totA),
            ],
            if (rowsB.isNotEmpty) ...[
              for (final r in rowsB) regRowCells(r),
              regTotalCells('૬ થી ૮ કુલ', boysB, girlsB, totB),
            ],
            regTotalCells('એકંદર કુલ', boysA + boysB, girlsA + girlsB, totA + totB),
          ];
          final perPage = _effectiveRowsPerPage(27, pageIdPrefix: 'register');
          final chunk =
              allRowsOut.skip(page.subIndex * perPage).take(perPage).toList();
          bodyWidget = await _buildExamPdfTable(
            headers: isBoysOnly
                ? ['ધોરણ', 'કુમાર', 'વર્ગ શિક્ષકની સહી', 'રીમાર્કસ']
                : isGirlsOnly
                    ? ['ધોરણ', 'કન્યા', 'વર્ગ શિક્ષકની સહી', 'રીમાર્કસ']
                    : [
                        'ધોરણ',
                        'કુમાર',
                        'કન્યા',
                        'કુલ',
                        'વર્ગ શિક્ષકની સહી',
                        'રીમાર્કસ'
                      ],
            rows: chunk,
            rowHeight: pageRh,
            fontScale: pageFs,
          );
          break;
        case 'timetable':
          final perPage = _effectiveRowsPerPage(27, pageIdPrefix: 'timetable');
          final start = page.subIndex * perPage;
          final chunk = timetableRows.skip(start).take(perPage).toList();
          bodyWidget = await _buildExamPdfTable(
            headers: ['તારીખ', 'વાર', 'ધોરણ', 'વિષય', 'સમય', 'ગુણ'],
            rows: chunk
                .map((r) => [
                      r.date,
                      r.day,
                      r.stdLabel,
                      r.subject,
                      r.time,
                      r.marks,
                    ])
                .toList(),
            rowHeight: pageRh,
            fontScale: pageFs,
          );
          break;
        case 'seat_a':
        case 'seat_b':
          final isA = page.category == 'seat_a';
          final list = isA ? seatingA : seatingB;
          final nb = isA ? blocksA : blocksB;
          final allRowsOut = <List<String>>[];
          int grandTotal = 0;
          for (int b = 1; b <= nb; b++) {
            final bRows = list.where((r) => r.blockNo == b).toList();
            int blockSum = 0;
            for (int i = 0; i < bRows.length; i++) {
              final r = bRows[i];
              final rowCnt = parseNum(r.totalCount) ??
                  (() {
                    final f = parseNum(r.fromRoll);
                    final t = parseNum(r.toRoll);
                    return (f != null && t != null && t >= f) ? (t - f + 1) : 0;
                  })();
              blockSum += rowCnt;
              grandTotal += rowCnt;
              allRowsOut.add([
                i == 0 ? '$b' : '',
                r.className,
                r.fromRoll,
                'થી',
                r.toRoll,
                r.totalCount,
                r.remarks,
              ]);
            }
            allRowsOut.add([
              'બ્લોક $b',
              'કુલ',
              '',
              '',
              '',
              blockSum > 0 ? '$blockSum' : '0',
              '',
            ]);
          }
          allRowsOut.add([
            'એકંદર',
            'કુલ બેઠક સંખ્યા',
            '',
            '',
            '',
            grandTotal > 0 ? '$grandTotal' : '0',
            '',
          ]);
          final perPage = _effectiveRowsPerPage(27, pageIdPrefix: page.category);
          final chunk =
              allRowsOut.skip(page.subIndex * perPage).take(perPage).toList();
          bodyWidget = await _buildExamPdfTable(
            headers: [
              'બ્લોક',
              'ધોરણ',
              'ક્રમ',
              '',
              'ક્રમ',
              'કુલ',
              'રીમાર્કસ'
            ],
            rows: chunk,
            rowHeight: pageRh,
            fontScale: pageFs,
          );
          break;
        case 'absent':
          if (page.subIndex >= absentSheets.length) continue;
          final sh = absentSheets[page.subIndex];
          final classes = getClassesForGroup(sh.group);
          int totAllotted = 0;
          int totPres = 0;
          bool anyPres = false;
          int totAbs = 0;
          bool anyAbs = false;
          for (final br in sh.blockRows) {
            totAllotted += parseNum(br.allotted) ?? 0;
            final p = parseNum(br.present);
            if (p != null) {
              totPres += p;
              anyPres = true;
            }
            final a = parseNum(br.totalAbsent);
            if (a != null) {
              totAbs += a;
              anyAbs = true;
            }
          }
          final topRows = sh.blockRows
              .map((br) => [
                    '${br.blockNo}',
                    br.allotted,
                    br.present,
                    ...classes.map((c) => br.classAbsent[c] ?? ''),
                    br.totalAbsent,
                    br.sign,
                  ])
              .toList();
          topRows.add([
            'કુલ',
            '$totAllotted',
            anyPres ? '$totPres' : '',
            ...classes.map((c) {
              int cSum = 0;
              bool hasC = false;
              for (final br in sh.blockRows) {
                final v = parseNum(br.classAbsent[c] ?? '');
                if (v != null) {
                  cSum += v;
                  hasC = true;
                }
              }
              return hasC ? '$cSum' : '';
            }),
            anyAbs ? '$totAbs' : '',
            '',
          ]);
          final topTable = await _buildExamPdfTable(
            headers: [
              'બ્લોક',
              'ફાળવાયેલ સંખ્યા',
              'હાજર સંખ્યા',
              ...classes,
              'કુલ ગે.હા.',
              'નિરીક્ષકની સહી'
            ],
            rows: topRows,
            cellMaxWidth: 85,
            rowHeight: pageRh,
            fontScale: pageFs,
          );
          final absMidBannerImg = await _renderExamTextImage(
            'ગેરહાજર વિદ્યાર્થીઓની નામાવલી (${sh.subject} - ${sh.date})',
            fontSize: 10.5 * pageFs,
            bold: true,
            color: Colors.white,
            maxWidth: 620,
          );
          final bottomTable = await _buildExamPdfTable(
            headers: [
              'ક્રમ નંબર',
              'બ્લોક નંબર',
              'વિદ્યાર્થીનું નામ',
              'રોલ નંબર',
              'ધોરણ'
            ],
            rows: sh.studentList
                .map((st) => [
                      '${st.srNo}',
                      st.blockNo,
                      st.studentName,
                      st.rollNo,
                      st.className,
                    ])
                .toList(),
            cellMaxWidth: 160,
            rowHeight: pageRh,
            fontScale: pageFs,
          );
          bodyWidget = pw.Column(
            children: [
              topTable,
              pw.SizedBox(height: 6),
              if (absMidBannerImg != null) ...[
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFF0B2A5B),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  alignment: pw.Alignment.center,
                  child: _pdfImg(absMidBannerImg),
                ),
                pw.SizedBox(height: 4),
              ],
              bottomTable,
            ],
          );
          break;
        case 'super_a':
        case 'super_b':
          final isA = page.category == 'super_a';
          final allRows = isA ? supervisionA : supervisionB;
          final basePerPage = isA ? superRowsPerPageA : superRowsPerPageB;
          final perPage =
              _effectiveRowsPerPage(basePerPage, pageIdPrefix: page.category);
          final chunk =
              allRows.skip(page.subIndex * perPage).take(perPage).toList();
          bodyWidget = await _buildExamPdfTable(
            headers: [
              'તારીખ',
              'વાર',
              'વિષય',
              'બ્લોક',
              'નિરીક્ષકનું નામ',
              'સહી'
            ],
            rows: chunk
                .map((r) => [
                      r.date,
                      r.day,
                      r.subject,
                      '${r.blockNo}',
                      r.invigilatorName,
                      r.sign,
                    ])
                .toList(),
            rowHeight: pageRh,
            fontScale: pageFs,
          );
          break;
        case 'check_a':
        case 'check_b':
          final g = page.category == 'check_a' ? 'a' : 'b';
          final perPage =
              _effectiveRowsPerPage(checkRowsPerPage, pageIdPrefix: page.category);
          final chunk = checkingRows
              .where((r) => r.group == g)
              .skip(page.subIndex * perPage)
              .take(perPage)
              .toList();
          bodyWidget = await _buildExamPdfTable(
            headers: [
              'તારીખ',
              'વિષય',
              'ધોરણ / વર્ગ',
              'પેપર સંખ્યા',
              'પરીક્ષકનું નામ (વિષય શિક્ષક)',
              'પરીક્ષકની સહી / તારીખ',
              'પેપર પરત તારીખ',
              'આચાર્યની સહી'
            ],
            rows: chunk
                .map((r) => [
                      r.date,
                      r.subject,
                      r.className,
                      r.paperCount,
                      r.examinerName,
                      r.examinerSignDate,
                      r.returnDate,
                      r.principalSign,
                    ])
                .toList(),
            cellMaxWidth: 105,
            rowHeight: pageRh,
            fontScale: pageFs,
          );
          break;
        case 'bundle':
          final effBundles = _effectiveBundlesPerPage();
          final chunk = bundleCards
              .skip(page.subIndex * effBundles)
              .take(effBundles)
              .toList();
          final cardWidgets = <pw.Widget>[];
          for (final card in chunk) {
            final cardTop1 = await _renderExamTextImage(
              '${meta.examName} - ${meta.bundleMonth}',
              fontSize: 10.2 * pageFs,
              bold: true,
              color: const Color(0xFF0B2A5B),
              maxWidth: 230,
            );
            final cardTop2 = await _renderExamTextImage(
              'શાળાનું નામ: ${meta.schoolName}',
              fontSize: 9.6 * pageFs,
              bold: true,
              color: const Color(0xFF0F172A),
              maxWidth: 235,
            );
            final cardTop3 = await _renderExamTextImage(
              'તા: ${meta.taluka}   જિ: ${meta.district}',
              fontSize: 9.0 * pageFs,
              bold: true,
              color: const Color(0xFF334155),
              maxWidth: 230,
            );
            final cardBadge = await _renderExamTextImage(
              'બંડલ પર બાંધવાનો વર્ગવાર હાજરી રીપોર્ટ',
              fontSize: 9.4 * pageFs,
              bold: true,
              color: const Color(0xFF138808),
              maxWidth: 230,
            );
            final cardHdrImg = await _renderExamTextImage(
              'ધોરણ / વર્ગ: ${ClassLabel.bare(card.className)}',
              fontSize: 10.6 * pageFs,
              bold: true,
              color: const Color(0xFFB3261E),
              maxWidth: 230,
            );
            int regSum = 0;
            int presSum = 0;
            bool hasPres = false;
            int absSum = 0;
            bool hasAbs = false;
            for (final r in card.rows) {
              regSum += parseNum(r.regCount) ?? 0;
              final p = parseNum(r.presentCount);
              if (p != null) {
                presSum += p;
                hasPres = true;
              }
              final a = parseNum(r.absentCount);
              if (a != null) {
                absSum += a;
                hasAbs = true;
              }
            }
            final bRows = card.rows
                .map((r) => [
                      '${r.srNo}',
                      r.date,
                      r.subject,
                      r.regCount,
                      r.presentCount,
                      r.absentCount,
                      r.absentRollNos,
                    ])
                .toList();
            bRows.add([
              '',
              '',
              'કુલ',
              '$regSum',
              hasPres ? '$presSum' : '',
              hasAbs ? '$absSum' : '',
              '',
            ]);
            final bTable = await _buildExamPdfTable(
              headers: [
                'ક્રમ',
                'તારીખ',
                'વિષય',
                'રજીસ્ટર',
                'હાજર',
                'ગેરહાજર',
                'ગેરહાજર નં.'
              ],
              rows: bRows,
              cellMaxWidth: 75,
              rowHeight: math.min(pageRh, 9.0),
              fontScale: pageFs * 0.94,
            );
            final cardSummary = await _renderExamTextImage(
              'આ બંડલમાં કુલ ${hasPres ? presSum : "______"} ઉત્તરવહી મુકવામાં આવેલ છે.',
              fontSize: 9.0 * pageFs,
              bold: true,
              color: const Color(0xFF0F172A),
              maxWidth: 235,
            );
            final cardSign = await _renderExamTextImage(
              'વર્ગ શિક્ષકની સહી: ________      આચાર્યની સહી/સિક્કો: ________',
              fontSize: 8.6 * pageFs,
              bold: true,
              color: const Color(0xFF0B2A5B),
              maxWidth: 240,
            );
            cardWidgets.add(
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 8),
                padding: const pw.EdgeInsets.all(7),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                      color: PdfColor.fromInt(0xFF475569), width: 1.2),
                  borderRadius: pw.BorderRadius.circular(7),
                ),
                child: pw.Column(
                  children: [
                    if (cardTop1 != null) _pdfImg(cardTop1),
                    if (cardTop2 != null) _pdfImg(cardTop2),
                    if (cardTop3 != null) _pdfImg(cardTop3),
                    if (cardBadge != null) ...[
                      pw.SizedBox(height: 2),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromInt(0xFFF0FDF4),
                          borderRadius: pw.BorderRadius.circular(10),
                          border: pw.Border.all(
                              color: PdfColor.fromInt(0xFFBBF7D0)),
                        ),
                        child: _pdfImg(cardBadge),
                      ),
                    ],
                    if (cardHdrImg != null) ...[
                      pw.SizedBox(height: 2),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromInt(0xFFEEF4FF),
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: _pdfImg(cardHdrImg),
                      ),
                    ],
                    pw.SizedBox(height: 4),
                    bTable,
                    if (cardSummary != null) ...[
                      pw.SizedBox(height: 4),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(3),
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromInt(0xFFFFF7ED),
                          borderRadius: pw.BorderRadius.circular(4),
                          border: pw.Border.all(
                              color: PdfColor.fromInt(0xFFFED7AA)),
                        ),
                        child: _pdfImg(cardSummary),
                      ),
                    ],
                    if (cardSign != null) ...[
                      pw.SizedBox(height: 4),
                      _pdfImg(cardSign),
                    ],
                  ],
                ),
              ),
            );
          }
          bodyWidget = effBundles == 4
              ? pw.Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: cardWidgets
                      .map((w) => pw.SizedBox(width: 255, child: w))
                      .toList(),
                )
              : pw.Column(children: cardWidgets);
          break;
        case 'door':
          final allDoors = <Map<String, dynamic>>[];
          if (hasGroupA) {
            for (int b = 1; b <= blocksA; b++) {
              final rows = seatingA.where((r) => r.blockNo == b).toList();
              final tot = rows.fold<int>(
                  0, (s, r) => s + (parseNum(r.totalCount) ?? 0));
              allDoors.add({
                'groupLabel': 'ધોરણ ૩ થી ૫',
                'blockNo': b,
                'roomNo': b,
                'rows': rows,
                'tot': tot,
              });
            }
          }
          if (hasGroupB) {
            final roomOffset = hasGroupA ? blocksA : 0;
            for (int b = 1; b <= blocksB; b++) {
              final rows = seatingB.where((r) => r.blockNo == b).toList();
              final tot = rows.fold<int>(
                  0, (s, r) => s + (parseNum(r.totalCount) ?? 0));
              allDoors.add({
                'groupLabel': 'ધોરણ ૬ થી ૮',
                'blockNo': b,
                'roomNo': roomOffset + b,
                'rows': rows,
                'tot': tot,
              });
            }
          }
          final effDoors = _effectiveDoorsPerPage();
          final chunk =
              allDoors.skip(page.subIndex * effDoors).take(effDoors).toList();
          final doorWidgets = <pw.Widget>[];
          for (final d in chunk) {
            final dSchoolImg = await _renderExamTextImage(
              meta.schoolName,
              fontSize: 10.2 * pageFs,
              bold: true,
              color: const Color(0xFF0B2A5B),
              maxWidth: 235,
            );
            final dExamImg = await _renderExamTextImage(
              '${meta.examName} — ${meta.academicYear}',
              fontSize: 9.4 * pageFs,
              bold: true,
              color: const Color(0xFF138808),
              maxWidth: 235,
            );
            final dHdrImg = await _renderExamTextImage(
              'બ્લોક નંબર : ${gn(d['blockNo'])} (${d['groupLabel']}) — રૂમ નં: ${gn(d['roomNo'])}',
              fontSize: 10.0 * pageFs,
              bold: true,
              color: Colors.white,
              maxWidth: 235,
            );
            final sRows = (d['rows'] as List<SeatingRow>)
                .map((r) => [
                      r.className,
                      '${r.fromRoll} થી ${r.toRoll}',
                      r.totalCount,
                    ])
                .toList();
            sRows.add(['', 'બ્લોકમાં કુલ બેઠક સંખ્યા', '${d['tot']}']);
            final dTable = await _buildExamPdfTable(
              headers: [
                'ધોરણ / વર્ગ',
                'બેઠક રોલ નંબર (થી — સુધી)',
                'કુલ પરીક્ષાર્થી'
              ],
              rows: sRows,
              cellMaxWidth: 115,
              rowHeight: math.min(pageRh, 10.0),
              fontScale: pageFs * 0.95,
            );
            final dSignImg = await _renderExamTextImage(
              'ખંડ નિરીક્ષક સહી: ________      આચાર્યની સહી / સિક્કો: ________',
              fontSize: 8.6 * pageFs,
              bold: true,
              color: const Color(0xFF0B2A5B),
              maxWidth: 240,
            );
            doorWidgets.add(
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 8),
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                      color: PdfColor.fromInt(0xFF0B2A5B), width: 1.5),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  children: [
                    if (dSchoolImg != null) _pdfImg(dSchoolImg),
                    if (dExamImg != null) _pdfImg(dExamImg),
                    if (dHdrImg != null) ...[
                      pw.SizedBox(height: 3),
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromInt(0xFF0B2A5B),
                          borderRadius: pw.BorderRadius.circular(6),
                          border: pw.Border.all(
                              color: PdfColor.fromInt(0xFFFF9933), width: 1.2),
                        ),
                        alignment: pw.Alignment.center,
                        child: _pdfImg(dHdrImg),
                      ),
                    ],
                    pw.SizedBox(height: 4),
                    dTable,
                    if (dSignImg != null) ...[
                      pw.SizedBox(height: 5),
                      _pdfImg(dSignImg),
                    ],
                  ],
                ),
              ),
            );
          }
          bodyWidget = effDoors == 4
              ? pw.Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: doorWidgets
                      .map((w) => pw.SizedBox(width: 255, child: w))
                      .toList(),
                )
              : pw.Column(children: doorWidgets);
          break;
        case 'qp_reg':
          final perPage = _effectiveRowsPerPage(27, pageIdPrefix: 'qp_reg');
          final chunk = qpRegisterRows
              .skip(page.subIndex * perPage)
              .take(perPage)
              .toList();
          bodyWidget = await _buildExamPdfTable(
            headers: [
              'ક્રમ',
              'તારીખ',
              'વાર',
              'ધોરણ જૂથ',
              'વિષય',
              'પરીક્ષા સમય',
              'કુલ પરીક્ષાર્થી',
              'બ્લોક સંખ્યા',
              'સીલ ખોલ્યા સમય',
              'સાક્ષી શિક્ષકનું નામ',
              'સહી'
            ],
            rows: chunk,
            cellMaxWidth: 95,
            rowHeight: pageRh,
            fontScale: pageFs,
          );
          break;
        case 'stationery':
          final perPage = _effectiveRowsPerPage(27, pageIdPrefix: 'stationery');
          final chunk = stationeryRows
              .skip(page.subIndex * perPage)
              .take(perPage)
              .toList();
          bodyWidget = await _buildExamPdfTable(
            headers: [
              'ધોરણ / વર્ગ',
              'રજીસ્ટર સંખ્યા',
              'કુલ પેપર',
              'જરૂરી મુખ્ય ઉત્તરવહી',
              include5PercentReserveInStationery ? '૫% અનામત' : 'અનામત (0%)',
              'કુલ ઉત્તરવહી',
              'અંદાજિત પુરવણી (25%)',
              'બંડલ કાપલી',
              'વર્ગ શિક્ષક સહી / નોંધ'
            ],
            rows: chunk,
            cellMaxWidth: 85,
            rowHeight: pageRh,
            fontScale: pageFs,
          );
          break;
        case 'instructions':
          final perPage =
              _effectiveRowsPerPage(20, pageIdPrefix: 'instructions');
          final start = page.subIndex * perPage;
          final chunk =
              editableInstructions.skip(start).take(perPage).toList();
          final instWidgets = <pw.Widget>[];
          final double vPad = (pageRh * 0.42).clamp(1.5, 16.0);
          for (int i = 0; i < chunk.length; i++) {
            final numImg = await _renderExamTextImage(
              gn(start + i + 1),
              fontSize: 9.2 * pageFs,
              bold: true,
              color: Colors.white,
              maxWidth: 26,
            );
            final txtImg = await _renderExamTextImage(
              chunk[i],
              fontSize: 10.6 * pageFs,
              bold: false,
              color: const Color(0xFF0F172A),
              maxWidth: 465,
              textAlign: TextAlign.left,
            );
            instWidgets.add(
              pw.Padding(
                padding: pw.EdgeInsets.symmetric(vertical: vPad),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 19,
                      height: 19,
                      margin: const pw.EdgeInsets.only(right: 7, top: 1),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFF0B2A5B),
                        shape: pw.BoxShape.circle,
                      ),
                      alignment: pw.Alignment.center,
                      child: numImg != null ? _pdfImg(numImg) : pw.SizedBox(),
                    ),
                    pw.Expanded(
                      child: txtImg != null
                          ? pw.Align(
                              alignment: pw.Alignment.centerLeft,
                              child: _pdfImg(txtImg),
                            )
                          : pw.SizedBox(),
                    ),
                  ],
                ),
              ),
            );
          }
          bodyWidget = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: instWidgets,
          );
          break;
        default:
          final infoImg = await _renderExamTextImage(
            page.title,
            fontSize: 13 * pageFs,
            bold: true,
            maxWidth: 420,
          );
          bodyWidget = infoImg != null ? _pdfImg(infoImg) : pw.SizedBox();
          break;
      }

      final bool isStickerOnlyPage =
          page.category == 'bundle' || page.category == 'door';

      doc.addPage(
        pw.Page(
          pageFormat:
              page.isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(14),
          build: (ctx) => pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(
                color: PdfColor.fromInt(0xFF0B2A5B),
                width: 2.0,
              ),
            ),
            padding: const pw.EdgeInsets.all(3),
            child: pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                  color: PdfColor.fromInt(0xFFFF9933),
                  width: 1.1,
                ),
              ),
              padding: const pw.EdgeInsets.all(12),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      _buildExamPdfTricolorBar(),
                      pw.SizedBox(height: 6),
                      if (!isStickerOnlyPage) ...[
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                              vertical: 6, horizontal: 12),
                          decoration: pw.BoxDecoration(
                            color: PdfColor.fromInt(0xFF0B2A5B),
                            borderRadius: pw.BorderRadius.circular(8),
                            border: pw.Border.all(
                              color: PdfColor.fromInt(0xFFFF9933),
                              width: 1.6,
                            ),
                          ),
                          alignment: pw.Alignment.center,
                          child: pageTitleImg != null
                              ? _pdfImg(pageTitleImg)
                              : pw.SizedBox(),
                        ),
                        pw.SizedBox(height: 5),
                        pw.Container(
                          padding: const pw.EdgeInsets.only(bottom: 3),
                          decoration: pw.BoxDecoration(
                            border: pw.Border(
                              bottom: pw.BorderSide(
                                color: PdfColor.fromInt(0xFFFF9933),
                                width: 2.0,
                              ),
                            ),
                          ),
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            children: [
                              if (logoImg != null) ...[
                                pw.Transform.translate(
                                  offset: PdfPoint(headerLogoOffset.dx * 0.76, -headerLogoOffset.dy * 0.76),
                                  child: pw.SizedBox(
                                    width: (headerLogoSize * 0.78).clamp(18.0, 105.0),
                                    height: (headerLogoSize * 0.78).clamp(18.0, 105.0),
                                    child: pw.Image(logoImg, fit: pw.BoxFit.contain),
                                  ),
                                ),
                                pw.SizedBox(width: 8),
                              ],
                              if (schoolNameImg != null) _pdfImg(schoolNameImg),
                            ],
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        if (schoolSubImg != null)
                          pw.Center(child: _pdfImg(schoolSubImg)),
                        pw.SizedBox(height: 2),
                        if (talDistExamImg != null)
                          pw.Center(child: _pdfImg(talDistExamImg)),
                        if (pageSubtitleImg != null) ...[
                          pw.SizedBox(height: 3),
                          pw.Center(child: _pdfImg(pageSubtitleImg)),
                        ],
                        pw.SizedBox(height: 7),
                      ],
                      bodyWidget,
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.only(top: 5),
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        top: pw.BorderSide(
                          color: PdfColor.fromInt(0xFFC9D3E3),
                          width: 0.8,
                        ),
                      ),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        if (footerLeftImg != null) _pdfImg(footerLeftImg),
                        if (footerRightImg != null) _pdfImg(footerRightImg),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return doc.save();
  }
}


/// Drag/selection wrapper for movable texts and logos on the A4 page:
/// single click selects (orange outline, never printed), double click runs
/// [onTap] (edit / change), and dragging is clamped so the object can never
/// leave the printable page area.
class _PageDragDetector extends StatefulWidget {
  const _PageDragDetector({
    required this.pageKey,
    required this.child,
    this.onTap,
    this.onPanUpdate,
    this.behavior,
    this.hideSelection = false,
  });

  final GlobalKey pageKey;
  final Widget child;
  final VoidCallback? onTap;
  final GestureDragUpdateCallback? onPanUpdate;
  final HitTestBehavior? behavior;
  final bool hideSelection;

  static final ValueNotifier<Object?> selected = ValueNotifier<Object?>(null);

  @override
  State<_PageDragDetector> createState() => _PageDragDetectorState();
}

class _PageDragDetectorState extends State<_PageDragDetector> {
  /// Inner margin of the printable area inside the A4 frame (outer padding,
  /// double border and inner padding).
  static const double _safeInset = 24;

  Offset _clamp(Offset delta) {
    final box = context.findRenderObject();
    final page = widget.pageKey.currentContext?.findRenderObject();
    if (box is! RenderBox || page is! RenderBox || !box.hasSize || !page.hasSize) {
      return delta;
    }
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final area = (page.localToGlobal(Offset.zero) & page.size).deflate(_safeInset);
    double axis(double d, double lo, double hi) {
      // lo/hi: how far the object may still move left/up (negative) and
      // right/down (positive) without leaving the page.
      if (lo > hi) return 0; // larger than the page area: do not move outward
      return d.clamp(math.min(0.0, lo), math.max(0.0, hi)).toDouble();
    }
    return Offset(
      axis(delta.dx, area.left - rect.left, area.right - rect.right),
      axis(delta.dy, area.top - rect.top, area.bottom - rect.bottom),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Object?>(
      valueListenable: _PageDragDetector.selected,
      builder: (context, sel, child) {
        final isSel = identical(sel, this) && !widget.hideSelection;
        return GestureDetector(
          behavior: widget.behavior ?? HitTestBehavior.opaque,
          onTap: () => _PageDragDetector.selected.value = this,
          onDoubleTap: widget.onTap,
          onPanStart: (_) => _PageDragDetector.selected.value = this,
          onPanUpdate: widget.onPanUpdate == null
              ? null
              : (d) {
                  final c = _clamp(d.delta);
                  if (c == Offset.zero) return;
                  widget.onPanUpdate!(DragUpdateDetails(
                    sourceTimeStamp: d.sourceTimeStamp,
                    delta: c,
                    primaryDelta: null,
                    globalPosition: d.globalPosition,
                    localPosition: d.localPosition,
                  ));
                },
          child: Container(
            foregroundDecoration: isSel
                ? BoxDecoration(
                    border: Border.all(color: const Color(0xFFF59E0B), width: 1.6),
                    borderRadius: BorderRadius.circular(3),
                  )
                : null,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

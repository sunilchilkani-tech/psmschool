import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pmshri_attendance/services/class_label.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/school_class_order.dart';
import '../services/school_name_language_service.dart';
import '../services/school_type.dart';
import '../services/principal_daily_summary_service.dart';
import '../services/supabase_attendance_report_service.dart';

/// Full-screen wrapper for the Admin Live Daily Attendance, PM POSHAN &
/// Breakfast Dashboard with 1-tap Gujarati WhatsApp Teacher Gentle Reminders.
class SupabaseAdminDailyDashboardScreen extends StatelessWidget {
  const SupabaseAdminDailyDashboardScreen({
    super.key,
    this.profile = const <String, dynamic>{},
  });

  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'દૈનિક હાજરી, પીએમ પોષણ અને અલ્પાહાર લાઈવ ડેશબોર્ડ',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          AdminDailyAttendanceDashboard(
            profile: profile,
            initiallyExpanded: true,
            isFullScreen: true,
          ),
        ],
      ),
    );
  }
}

/// Live Gujarati Admin Dashboard showing:
/// 1. School-wide live Daily Report totals (Registered, Present, Absent,
///    PM POSHAN / MDM, and Breakfast — Boys, Girls, Total) without generating a report.
/// 2. Class-wise live completion status for:
///    - ૧. હાજરી (Attendance)
///    - ૨. પીએમ પોષણ (PM POSHAN / MDM)
///    - ૩. અલ્પાહાર (Breakfast)
/// 3. 1-Tap Gujarati WhatsApp Gentle Reminder button (`📲 રીમાઈન્ડર મોકલો`) for
///    each class teacher (plus bulk queue and school group summary share).
/// 4. Live Daily Report table (both Compact Boys/Girls/Total and Full Category-wise
///    SC/ST/OBC/General table) directly on screen without generating PDF/Excel.
class AdminDailyAttendanceDashboard extends StatefulWidget {
  const AdminDailyAttendanceDashboard({
    super.key,
    this.profile = const <String, dynamic>{},
    this.initiallyExpanded = true,
    this.isFullScreen = false,
  });

  final Map<String, dynamic> profile;
  final bool initiallyExpanded;
  final bool isFullScreen;

  @override
  State<AdminDailyAttendanceDashboard> createState() =>
      _AdminDailyAttendanceDashboardState();
}

class _ClassDailyStatusItem {
  _ClassDailyStatusItem({
    required this.classId,
    required this.classKey,
    required this.classLabel,
    required this.reportGroup,
    required this.sortOrder,
    required this.hasDayRecord,
    required this.attendanceMode,
    required this.presentSaved,
    required this.mdmSaved,
    required this.breakfastSaved,
    required this.presentFrozen,
    required this.mdmFrozen,
    required this.breakfastFrozen,
    required this.regBoys,
    required this.regGirls,
    required this.regTotal,
    required this.presBoys,
    required this.presGirls,
    required this.presTotal,
    required this.mdmBoys,
    required this.mdmGirls,
    required this.mdmTotal,
    required this.bfBoys,
    required this.bfGirls,
    required this.bfTotal,
    required this.teacherId,
    required this.teacherName,
    required this.teacherMobile,
    required this.allMatchedTeachers,
  });

  final String classId;
  final String classKey;
  final String classLabel;
  final String reportGroup;
  final int sortOrder;
  final bool hasDayRecord;
  final String attendanceMode;
  final bool presentSaved;
  final bool mdmSaved;
  final bool breakfastSaved;
  final bool presentFrozen;
  final bool mdmFrozen;
  final bool breakfastFrozen;

  final int regBoys;
  final int regGirls;
  final int regTotal;

  final int presBoys;
  final int presGirls;
  final int presTotal;

  final int mdmBoys;
  final int mdmGirls;
  final int mdmTotal;

  final int bfBoys;
  final int bfGirls;
  final int bfTotal;

  String teacherId;
  String teacherName;
  String teacherMobile;
  final List<Map<String, dynamic>> allMatchedTeachers;

  int get absentTotal =>
      presentSaved ? (regTotal - presTotal).clamp(0, 999999) : 0;

  /// Attendance is complete if present_saved is true.
  bool get isAttendanceDone => hasDayRecord && presentSaved;

  /// PM POSHAN is complete if mdm_saved is true AND either mdmTotal > 0 or presTotal == 0.
  /// If presTotal > 0 and mdmTotal == 0, we flag it as remaining/0 so Admin can remind the teacher.
  bool get isMdmDone =>
      hasDayRecord && mdmSaved && (presTotal == 0 || mdmTotal > 0);

  /// True when mdm_saved was set (e.g. in single-button save) but count is 0 while students are present.
  bool get isMdmZeroWarning =>
      hasDayRecord && mdmSaved && presTotal > 0 && mdmTotal == 0;

  /// Breakfast is complete if breakfast_saved is true AND either bfTotal > 0 or presTotal == 0.
  bool get isBreakfastDone =>
      hasDayRecord && breakfastSaved && (presTotal == 0 || bfTotal > 0);

  /// True when breakfast_saved was set but count is 0 while students are present.
  bool get isBreakfastZeroWarning =>
      hasDayRecord && breakfastSaved && presTotal > 0 && bfTotal == 0;

  bool get isAllThreeDone =>
      isAttendanceDone && isMdmDone && isBreakfastDone;

  bool get hasAnyPending => !isAllThreeDone;

  List<String> get pendingItemsGu {
    final items = <String>[];
    if (!isAttendanceDone) {
      items.add('હાજરી (Attendance)');
    }
    if (!isMdmDone) {
      items.add('પીએમ પોષણ (PM POSHAN)');
    }
    if (!isBreakfastDone) {
      items.add('અલ્પાહાર (Breakfast)');
    }
    return items;
  }
}

class _AdminDailyAttendanceDashboardState
    extends State<AdminDailyAttendanceDashboard> {
  final SupabaseClient _client = Supabase.instance.client;
  final SupabaseAttendanceReportService _reportService =
      SupabaseAttendanceReportService();
  final DateFormat _dmyFormat = DateFormat('dd-MM-yyyy');

  late DateTime _selectedDate;
  late bool _expanded;
  bool _loading = true;
  String? _error;

  String _schoolRef = '';
  String _schoolName = '';
  String _schoolType = 'mixed';
  String _dailySerial = '';
  bool _threeStepMode = false;

  /// Filter: 'pending' | 'all' | 'completed' | 'att_pending' | 'mdm_pending' | 'bf_pending'
  String _filter = 'all';

  /// Live report table view: 'compact' | 'category' | 'hidden'
  String _reportTableMode = 'compact';

  List<_ClassDailyStatusItem> _items = <_ClassDailyStatusItem>[];
  List<Map<String, dynamic>> _allTeachers = <Map<String, dynamic>>[];
  List<List<String>> _categoryReportGrid = <List<String>>[];
  Map<String, String> _localTeacherMobileOverrides = <String, String>{};
  Map<String, String> _localClassTeacherNameOverrides = <String, String>{};

  int _queueIndex = 0;

  DateTime _indiaNow() =>
      DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _dmy(DateTime d) => _dmyFormat.format(d);

  String _text(dynamic v) => (v ?? '').toString().trim();

  int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(_text(v)) ?? 0;
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return Map<String, dynamic>.from(v);
    if (v is Map) return v.map((k, val) => MapEntry('$k', val));
    return <String, dynamic>{};
  }

  String _normalizeWhatsAppPhone(dynamic raw) {
    var digits = _text(raw).replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.length == 10) {
      digits = '91$digits';
    }
    if (digits.length < 11 || digits.length > 15) return '';
    return digits;
  }

  String _displayMobile10(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      return digits.substring(2);
    }
    if (digits.length == 11 && digits.startsWith('0')) {
      return digits.substring(1);
    }
    return digits;
  }

  @override
  void initState() {
    super.initState();
    final now = _indiaNow();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _expanded = widget.initiallyExpanded;
    _loadDashboard();
  }

  Future<void> _loadLocalOverrides(String schoolRef) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mobRaw =
          prefs.getString('psm_admin_dash_mob_v1_$schoolRef') ?? '{}';
      final nameRaw =
          prefs.getString('psm_admin_dash_tname_v1_$schoolRef') ?? '{}';
      final mobMap = jsonDecode(mobRaw);
      final nameMap = jsonDecode(nameRaw);
      if (mobMap is Map) {
        _localTeacherMobileOverrides =
            mobMap.map((k, v) => MapEntry('$k', '$v'));
      }
      if (nameMap is Map) {
        _localClassTeacherNameOverrides =
            nameMap.map((k, v) => MapEntry('$k', '$v'));
      }
    } catch (_) {}
  }

  Future<void> _saveLocalOverride({
    required String keyId,
    required String mobile,
    String? teacherName,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mobile.isNotEmpty) {
        _localTeacherMobileOverrides[keyId] = mobile;
      }
      if (teacherName != null && teacherName.trim().isNotEmpty) {
        _localClassTeacherNameOverrides[keyId] = teacherName.trim();
      }
      await prefs.setString(
        'psm_admin_dash_mob_v1_$_schoolRef',
        jsonEncode(_localTeacherMobileOverrides),
      );
      await prefs.setString(
        'psm_admin_dash_tname_v1_$_schoolRef',
        jsonEncode(_localClassTeacherNameOverrides),
      );
    } catch (_) {}
  }

  Future<void> _pickDate() async {
    final now = _indiaNow();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(today) ? today : _selectedDate,
      firstDate: DateTime(2020),
      lastDate: today.add(const Duration(days: 1)),
      helpText: 'દૈનિક ડેશબોર્ડ માટે તારીખ પસંદ કરો',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedDate = DateTime(picked.year, picked.month, picked.day);
      _queueIndex = 0;
    });
    await _loadDashboard();
  }

  Future<void> _shiftDate(int deltaDays) async {
    final now = _indiaNow();
    final today = DateTime(now.year, now.month, now.day);
    final next = _selectedDate.add(Duration(days: deltaDays));
    if (next.isAfter(today)) return;
    setState(() {
      _selectedDate = next;
      _queueIndex = 0;
    });
    await _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final refRaw = await _client.rpc('current_school_ref');
      final schoolRef = _text(refRaw);
      if (schoolRef.isEmpty) {
        throw StateError('શાળાનું એકાઉન્ટ મળ્યું નથી. ફરી લોગિન કરો.');
      }
      _schoolRef = schoolRef;
      await _loadLocalOverrides(schoolRef);

      final dateIso = _iso(_selectedDate);

      final language =
          await SchoolNameLanguageService.loadLanguage(schoolRef: schoolRef);
      final schoolContext =
          await SchoolNameLanguageService.loadCurrentSchoolContext(_client);

      final settingsRow = await _client
          .from('school_settings')
          .select('config')
          .eq('school_ref', schoolRef)
          .maybeSingle();
      final cfg = _asMap(settingsRow?['config']);
      final threeStep = cfg['three_step_attendance_save_mode'] == true;

      final resolvedSchoolName = SchoolNameLanguageService.resolveSchoolName(
        language: language,
        profile: widget.profile,
        schoolContext: schoolContext,
        schoolConfig: cfg,
        fallbackEnglish: _text(
          widget.profile['school_name_gu'] ??
              widget.profile['school_name'] ??
              schoolContext['school_name_gu'] ??
              schoolContext['school_name'] ??
              'શાળા',
        ),
      );
      final resolvedSchoolType = SchoolType.resolve(<dynamic>[
        schoolContext['school_type'],
        widget.profile['school_type'],
        widget.profile['schoolType'],
      ]);

      // Fetch classes, teachers, attendance_days, and daily report rows in parallel
      final results = await Future.wait<dynamic>([
        _client
            .from('school_classes')
            .select(
              'id,school_ref,class_key,label,sheet_name,standard,section,report_group,sort_order,is_active,class_teacher_id',
            )
            .eq('school_ref', schoolRef)
            .eq('is_active', true)
            .order('sort_order'),
        _client
            .from('school_teachers')
            .select(
              'id,school_ref,teacher_name,mobile,role,allowed_classes,is_active',
            )
            .eq('school_ref', schoolRef),
        _client
            .from('attendance_days')
            .select('*')
            .eq('school_ref', schoolRef)
            .eq('attendance_date', dateIso),
        _reportService.getDailyReportRowsByDate(dateIso),
      ]);

      final rawClasses = results[0] is List ? results[0] as List : const [];
      final classes = SchoolClassOrder.sorted(
        rawClasses
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .toList(),
      );

      final rawTeachers = results[1] is List ? results[1] as List : const [];
      final teachers = rawTeachers
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .where((t) {
            if (t['is_active'] == false) return false;
            final role = _text(t['role']).toLowerCase();
            return role != 'developer';
          })
          .toList();

      final rawDays = results[2] is List ? results[2] as List : const [];
      final dayByClassId = <String, Map<String, dynamic>>{};
      for (final d in rawDays) {
        if (d is Map) {
          final map = Map<String, dynamic>.from(d);
          final cid = _text(map['class_id']);
          if (cid.isNotEmpty) {
            dayByClassId[cid] = map;
          }
        }
      }

      final dailyReportMap = _asMap(results[3]);
      final dailySerial = _text(dailyReportMap['serial']);
      final rawReportClassRows = dailyReportMap['classRows'] is List
          ? (dailyReportMap['classRows'] as List)
              .whereType<Map>()
              .map((r) => Map<String, dynamic>.from(r))
              .toList()
          : <Map<String, dynamic>>[];
      final reportRowByClassId = <String, Map<String, dynamic>>{
        for (final r in rawReportClassRows)
          if (_text(r['class_id']).isNotEmpty) _text(r['class_id']): r,
      };
      final rawValues = dailyReportMap['values'];
      final categoryGrid = rawValues is List
          ? rawValues
              .map(
                (row) => row is List
                    ? row.map((cell) => '$cell').toList()
                    : <String>[],
              )
              .toList()
          : <List<String>>[];

      // Build teacher lookup helpers
      final teacherById = <String, Map<String, dynamic>>{
        for (final t in teachers)
          if (_text(t['id']).isNotEmpty) _text(t['id']): t,
      };

      final items = <_ClassDailyStatusItem>[];
      for (final c in classes) {
        final cid = _text(c['id']);
        final cKey = _text(c['class_key']);
        final cLabel = _text(c['label'].toString().isNotEmpty ? c['label'] : cKey);
        final sheetName = _text(c['sheet_name']);
        final rGroup = _text(c['report_group']);
        final sOrder = _int(c['sort_order']);

        final day = dayByClassId[cid];
        final repRow = reportRowByClassId[cid];

        final hasDay = day != null;
        final hasStepFlags = day != null &&
            (day['present_saved'] != null ||
                day['mdm_saved'] != null ||
                day['breakfast_saved'] != null ||
                day['present_frozen'] != null ||
                day['mdm_frozen'] != null ||
                day['breakfast_frozen'] != null);
        final legacyFrozen = day != null &&
            (day['is_frozen'] == true ||
                (day['is_frozen'] == null &&
                    day['unfrozen_by_admin'] != true));

        final pSaved = day != null &&
            (hasStepFlags
                ? (day['present_saved'] == true || day['present_frozen'] == true)
                : true);
        final mSaved = day != null &&
            (hasStepFlags
                ? (day['mdm_saved'] == true || day['mdm_frozen'] == true)
                : true);
        final bSaved = day != null &&
            (hasStepFlags
                ? (day['breakfast_saved'] == true ||
                    day['breakfast_frozen'] == true)
                : true);

        final pFrozen = day != null &&
            (hasStepFlags ? day['present_frozen'] == true : legacyFrozen);
        final mFrozen = day != null &&
            (hasStepFlags ? day['mdm_frozen'] == true : legacyFrozen);
        final bFrozen = day != null &&
            (hasStepFlags ? day['breakfast_frozen'] == true : legacyFrozen);

        // Extract counts from repRow / day
        final breakdown = _asMap(repRow?['gender_breakdown'] ?? day?['gender_breakdown']);
        final mode = _text(day?['attendance_mode'] ?? repRow?['attendance_mode'] ?? 'student')
            .toLowerCase();

        int metricForGender(String gender, String metric) {
          final gMap = _asMap(breakdown[gender]);
          final overall = _asMap(gMap['_OVERALL']);
          if (overall.containsKey(metric)) {
            return _int(overall[metric]);
          }
          var sum = 0;
          for (final cat in const ['SC', 'ST', 'OBC', 'OTHER']) {
            sum += _int(_asMap(gMap[cat])[metric]);
          }
          return sum;
        }

        int sumCategoryMap(dynamic raw) {
          final m = _asMap(raw);
          var sum = 0;
          for (final cat in const ['SC', 'ST', 'OBC', 'OTHER']) {
            sum += _int(m[cat]);
          }
          return sum;
        }

        var regBoys = metricForGender('BOYS', 'registered');
        var regGirls = metricForGender('GIRLS', 'registered');
        final regUnspec = metricForGender('UNSPECIFIED', 'registered');
        if (resolvedSchoolType == 'boys') {
          regBoys += regUnspec;
        } else if (resolvedSchoolType == 'girls') {
          regGirls += regUnspec;
        }
        var regTotal = regBoys + regGirls +
            (resolvedSchoolType == 'boys' || resolvedSchoolType == 'girls'
                ? 0
                : regUnspec);
        final fallbackRegTotal =
            sumCategoryMap(repRow?['registered_counts'] ?? day?['registered_counts']);
        if (regTotal == 0 && fallbackRegTotal > 0) {
          regTotal = fallbackRegTotal;
          if (resolvedSchoolType == 'boys') regBoys = regTotal;
          if (resolvedSchoolType == 'girls') regGirls = regTotal;
        }

        var presBoys = hasDay ? metricForGender('BOYS', 'present') : 0;
        var presGirls = hasDay ? metricForGender('GIRLS', 'present') : 0;
        final presUnspec = hasDay ? metricForGender('UNSPECIFIED', 'present') : 0;
        if (resolvedSchoolType == 'boys') presBoys += presUnspec;
        if (resolvedSchoolType == 'girls') presGirls += presUnspec;
        var presTotal = hasDay
            ? (presBoys +
                presGirls +
                (resolvedSchoolType == 'boys' || resolvedSchoolType == 'girls'
                    ? 0
                    : presUnspec))
            : 0;
        final fallbackPresTotal =
            hasDay ? sumCategoryMap(day['present_counts'] ?? repRow?['present_counts']) : 0;
        if (presTotal == 0 && fallbackPresTotal > 0) {
          presTotal = fallbackPresTotal;
          if (resolvedSchoolType == 'boys') presBoys = presTotal;
          if (resolvedSchoolType == 'girls') presGirls = presTotal;
        }

        var mdmBoys = hasDay ? metricForGender('BOYS', 'mdm') : 0;
        var mdmGirls = hasDay ? metricForGender('GIRLS', 'mdm') : 0;
        final mdmUnspec = hasDay ? metricForGender('UNSPECIFIED', 'mdm') : 0;
        if (resolvedSchoolType == 'boys') mdmBoys += mdmUnspec;
        if (resolvedSchoolType == 'girls') mdmGirls += mdmUnspec;
        var mdmTotal = hasDay
            ? (mdmBoys +
                mdmGirls +
                (resolvedSchoolType == 'boys' || resolvedSchoolType == 'girls'
                    ? 0
                    : mdmUnspec))
            : 0;
        final fallbackMdmTotal =
            hasDay ? sumCategoryMap(day['mdm_counts'] ?? repRow?['mdm_counts']) : 0;
        if (mdmTotal == 0 && fallbackMdmTotal > 0) {
          mdmTotal = fallbackMdmTotal;
          if (resolvedSchoolType == 'boys') mdmBoys = mdmTotal;
          if (resolvedSchoolType == 'girls') mdmGirls = mdmTotal;
        }

        var bfBoys = hasDay ? metricForGender('BOYS', 'breakfast') : 0;
        var bfGirls = hasDay ? metricForGender('GIRLS', 'breakfast') : 0;
        final bfUnspec = hasDay ? metricForGender('UNSPECIFIED', 'breakfast') : 0;
        if (resolvedSchoolType == 'boys') bfBoys += bfUnspec;
        if (resolvedSchoolType == 'girls') bfGirls += bfUnspec;
        var bfTotal = hasDay
            ? (bfBoys +
                bfGirls +
                (resolvedSchoolType == 'boys' || resolvedSchoolType == 'girls'
                    ? 0
                    : bfUnspec))
            : 0;
        final savedBfTotal =
            hasDay ? _int(day['breakfast_total'] ?? repRow?['breakfast_total']) : 0;
        if (savedBfTotal > bfTotal) {
          bfTotal = savedBfTotal;
          if (bfBoys == 0 && bfGirls == 0) {
            if (resolvedSchoolType == 'boys') bfBoys = bfTotal;
            if (resolvedSchoolType == 'girls') bfGirls = bfTotal;
          }
        }

        // Match teacher(s) for this class
        final matchedTeachers = <Map<String, dynamic>>[];
        final officialTeacherId = _text(c['class_teacher_id']);
        if (officialTeacherId.isNotEmpty &&
            teacherById.containsKey(officialTeacherId)) {
          matchedTeachers.add(teacherById[officialTeacherId]!);
        }

        final matchTokens = <String>{
          cid.toLowerCase(),
          cKey.toLowerCase(),
          cLabel.toLowerCase(),
          sheetName.toLowerCase(),
          ClassLabel.bare(cLabel).toLowerCase(),
        }..removeWhere((e) => e.isEmpty);

        for (final t in teachers) {
          final tid = _text(t['id']);
          if (matchedTeachers.any((m) => _text(m['id']) == tid)) continue;
          final role = _text(t['role']).toLowerCase();
          if (role == 'admin') continue;
          final allowed = t['allowed_classes'];
          if (allowed is List) {
            final allowedTokens = allowed
                .map((e) => _text(e).toLowerCase())
                .where((e) => e.isNotEmpty)
                .toSet();
            if (allowedTokens.intersection(matchTokens).isNotEmpty) {
              matchedTeachers.add(t);
            }
          }
        }

        final primaryTeacher =
            matchedTeachers.isNotEmpty ? matchedTeachers.first : null;
        final tId = _text(primaryTeacher?['id']);
        var tName = _text(primaryTeacher?['teacher_name']);
        var tMobile = _text(primaryTeacher?['mobile']);

        // Apply any saved local override if missing
        if (tName.isEmpty &&
            _localClassTeacherNameOverrides.containsKey(cid)) {
          tName = _localClassTeacherNameOverrides[cid]!;
        }
        if (tMobile.isEmpty) {
          if (tId.isNotEmpty &&
              _localTeacherMobileOverrides.containsKey(tId)) {
            tMobile = _localTeacherMobileOverrides[tId]!;
          } else if (_localTeacherMobileOverrides.containsKey(cid)) {
            tMobile = _localTeacherMobileOverrides[cid]!;
          }
        }

        items.add(
          _ClassDailyStatusItem(
            classId: cid,
            classKey: cKey,
            classLabel: cLabel,
            reportGroup: rGroup,
            sortOrder: sOrder,
            hasDayRecord: hasDay,
            attendanceMode: mode,
            presentSaved: pSaved,
            mdmSaved: mSaved,
            breakfastSaved: bSaved,
            presentFrozen: pFrozen,
            mdmFrozen: mFrozen,
            breakfastFrozen: bFrozen,
            regBoys: regBoys,
            regGirls: regGirls,
            regTotal: regTotal,
            presBoys: presBoys,
            presGirls: presGirls,
            presTotal: presTotal,
            mdmBoys: mdmBoys,
            mdmGirls: mdmGirls,
            mdmTotal: mdmTotal,
            bfBoys: bfBoys,
            bfGirls: bfGirls,
            bfTotal: bfTotal,
            teacherId: tId,
            teacherName: tName,
            teacherMobile: tMobile,
            allMatchedTeachers: matchedTeachers,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _schoolName = resolvedSchoolName;
        _schoolType = resolvedSchoolType;
        _dailySerial = dailySerial;
        _threeStepMode = threeStep;
        _allTeachers = teachers;
        _items = items;
        _categoryReportGrid = categoryGrid;
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

  String _buildGentleReminderMessage(
    _ClassDailyStatusItem item, {
    List<String>? customPendingItems,
  }) {
    final pending = customPendingItems ?? item.pendingItemsGu;
    final dateStr = _dmy(_selectedDate);
    final teacherGreeting = item.teacherName.trim().isNotEmpty
        ? 'આદરણીય ${item.teacherName.trim()} સાહેબશ્રી / બહેનશ્રી'
        : 'આદરણીય વર્ગ શિક્ષકશ્રી (${item.classLabel})';
    final schoolHeader =
        _schoolName.trim().isNotEmpty ? '🏫 *$_schoolName*\n' : '';

    final pendingBullets = pending.isEmpty
        ? '✅ *હાજરી, પીએમ પોષણ અને અલ્પાહાર ત્રણેય એન્ટ્રી પૂર્ણ થયેલ છે.*'
        : pending.asMap().entries.map((e) => '⏳ *${e.key + 1}. ${e.value}*').join('\n');

    final completedSummary = <String>[
      if (item.isAttendanceDone)
        '✅ હાજરી: હાજર ${item.presTotal} / ${item.regTotal}',
      if (item.isMdmDone) '✅ પીએમ પોષણ: ${item.mdmTotal}',
      if (item.isBreakfastDone) '✅ અલ્પાહાર: ${item.bfTotal}',
    ];

    final completedLine = completedSummary.isNotEmpty
        ? '\n📊 *નોંધાયેલ વિગત:* ${completedSummary.join('  |  ')}\n'
        : '';

    if (pending.isEmpty) {
      return '🙏 *નમસ્તે $teacherGreeting,*\n'
          '$schoolHeader'
          '📅 *તારીખ:* $dateStr\n'
          '🏷️ *ધોરણ / વર્ગ:* ${item.classLabel}\n'
          '$completedLine\n'
          'આજની આપના વર્ગની દૈનિક હાજરી, પીએમ પોષણ અને અલ્પાહારની ઓનલાઈન એન્ટ્રી સમયસર પૂર્ણ કરવા બદલ આપનો ખૂબ ખૂબ આભાર. 🙏\n\n'
          '– *આચાર્યશ્રી / શાળા એડમિન*';
    }

    return '🙏 *નમસ્તે $teacherGreeting,*\n'
        '$schoolHeader'
        '📅 *તારીખ:* $dateStr\n'
        '🏷️ *ધોરણ / વર્ગ:* ${item.classLabel}\n'
        '$completedLine\n'
        'આજની દૈનિક ઓનલાઈન નોંધણીમાં આપના વર્ગની નીચે મુજબની ડેટા એન્ટ્રી બાકી જણાય છે:\n'
        '$pendingBullets\n\n'
        'કૃપા કરીને અનુકૂળતાએ સત્વરે શાળા એપ્લિકેશનમાં આપના વર્ગની બાકી એન્ટ્રી પૂર્ણ કરવા નમ્ર વિનંતી છે. 🙏\n\n'
        '– *આચાર્યશ્રી / શાળા એડમિન*';
  }

  String _buildSchoolGroupPendingSummaryMessage() {
    final dateStr = _dmy(_selectedDate);
    final pendingClasses = _items.where((i) => i.hasAnyPending).toList();
    final schoolHeader =
        _schoolName.trim().isNotEmpty ? '🏫 *$_schoolName*\n' : '';

    if (pendingClasses.isEmpty) {
      return '🙏 *નમસ્તે સર્વે શિક્ષક મિત્રો,*\n'
          '$schoolHeader'
          '📅 *તારીખ:* $dateStr\n\n'
          '✅ આજે શાળાના તમામ *${_items.length} વર્ગો* ની દૈનિક હાજરી, પીએમ પોષણ અને અલ્પાહારની ઓનલાઈન એન્ટ્રી ૧૦૦% પૂર્ણ થઈ ગઈ છે.\n'
          '📊 *આજની કુલ હાજરી:* $_totalPresent / $_totalRegistered (${_fmtPct(_totalPresent, _totalRegistered)})  |  *પીએમ પોષણ:* $_totalMdm (${_fmtPct(_totalMdm, _totalPresent)})  |  *અલ્પાહાર:* $_totalBreakfast (${_fmtPct(_totalBreakfast, _totalPresent)})\n\n'
          'સમયસર કામગીરી બદલ સર્વે શિક્ષક મિત્રોનો ખૂબ ખૂબ આભાર! 🙏';
    }

    final lines = <String>[];
    for (var i = 0; i < pendingClasses.length; i++) {
      final item = pendingClasses[i];
      final tLabel =
          item.teacherName.isNotEmpty ? ' (${item.teacherName})' : '';
      lines.add(
        '${i + 1}. *${item.classLabel}*$tLabel ➔ બાકી: ${item.pendingItemsGu.join(', ')}',
      );
    }

    return '🙏 *નમ્ર યાદી (Gentle Reminder) — સર્વે શિક્ષક મિત્રો,*\n'
        '$schoolHeader'
        '📅 *તારીખ:* $dateStr\n\n'
        'આજની દૈનિક ઓનલાઈન એન્ટ્રીમાં નીચે મુજબના વર્ગોમાં *હાજરી / પીએમ પોષણ / અલ્પાહાર* ની એન્ટ્રી બાકી જણાય છે:\n\n'
        '${lines.join('\n')}\n\n'
        'કૃપા કરીને સંબંધિત વર્ગ શિક્ષકશ્રીઓને સત્વરે બાકી એન્ટ્રી પૂર્ણ કરવા નમ્ર વિનંતી છે. 🙏\n\n'
        '– *આચાર્યશ્રી / શાળા એડમિન*';
  }

  Future<bool> _promptEditTeacherAndMobile(_ClassDailyStatusItem item) async {
    String selectedTeacherId = item.teacherId;
    final nameCtrl = TextEditingController(text: item.teacherName);
    final mobCtrl =
        TextEditingController(text: _displayMobile10(item.teacherMobile));
    String? errText;
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setD) {
          return AlertDialog(
            title: Text('👩‍🏫 વર્ગ શિક્ષક અને WhatsApp નંબર • ${item.classLabel}'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_allTeachers.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        value: _allTeachers
                                .any((t) => _text(t['id']) == selectedTeacherId)
                            ? selectedTeacherId
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'શાળાના શિક્ષક પસંદ કરો (વૈકલ્પિક)',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final t in _allTeachers)
                            DropdownMenuItem<String>(
                              value: _text(t['id']),
                              child: Text(
                                '${_text(t['teacher_name'])}${_text(t['mobile']).isNotEmpty ? ' (${_displayMobile10(_text(t['mobile']))})' : ''}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (val) {
                          if (val == null) return;
                          final found = _allTeachers.firstWhere(
                            (t) => _text(t['id']) == val,
                            orElse: () => <String, dynamic>{},
                          );
                          setD(() {
                            selectedTeacherId = val;
                            if (_text(found['teacher_name']).isNotEmpty) {
                              nameCtrl.text = _text(found['teacher_name']);
                            }
                            final m = _displayMobile10(_text(found['mobile']));
                            if (m.isNotEmpty) {
                              mobCtrl.text = m;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'શિક્ષકનું નામ (Teacher Name)',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: mobCtrl,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      decoration: const InputDecoration(
                        labelText: '10 અંકનો WhatsApp મોબાઈલ નંબર',
                        hintText: 'દા.ત. 9876543210',
                        prefixIcon: Icon(Icons.phone_android),
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                    if (errText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errText!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.of(dialogCtx).pop(false),
                child: const Text('રદ કરો'),
              ),
              FilledButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        final rawMob =
                            mobCtrl.text.replaceAll(RegExp(r'\D'), '');
                        if (rawMob.length != 10) {
                          setD(() => errText =
                              'કૃપા કરીને માન્ય 10 અંકનો મોબાઈલ નંબર દાખલ કરો.');
                          return;
                        }
                        setD(() {
                          saving = true;
                          errText = null;
                        });
                        final tName = nameCtrl.text.trim();
                        try {
                          if (selectedTeacherId.isNotEmpty) {
                            await _client
                                .from('school_teachers')
                                .update(<String, dynamic>{
                                  'mobile': rawMob,
                                  if (tName.isNotEmpty) 'teacher_name': tName,
                                  'updated_at':
                                      DateTime.now().toUtc().toIso8601String(),
                                })
                                .eq('id', selectedTeacherId);
                            await _client.rpc(
                              'hajari_patrak_set_class_teacher',
                              params: <String, dynamic>{
                                'p_class_id': item.classId,
                                'p_teacher_id': selectedTeacherId,
                              },
                            );
                          }
                        } catch (_) {}

                        await _saveLocalOverride(
                          keyId: selectedTeacherId.isNotEmpty
                              ? selectedTeacherId
                              : item.classId,
                          mobile: rawMob,
                          teacherName: tName,
                        );
                        await _saveLocalOverride(
                          keyId: item.classId,
                          mobile: rawMob,
                          teacherName: tName,
                        );

                        item.teacherId = selectedTeacherId;
                        if (tName.isNotEmpty) item.teacherName = tName;
                        item.teacherMobile = rawMob;

                        if (dialogCtx.mounted) {
                          Navigator.of(dialogCtx).pop(true);
                        }
                      },
                icon: const Icon(Icons.save_outlined),
                label: Text(saving ? 'સેવ થાય છે...' : 'સેવ કરો'),
              ),
            ],
          );
        },
      ),
    );

    nameCtrl.dispose();
    mobCtrl.dispose();
    if (saved == true && mounted) {
      setState(() {});
      return true;
    }
    return false;
  }

  Future<void> _sendWhatsAppReminder(
    _ClassDailyStatusItem item, {
    bool customizeFirst = false,
  }) async {
    var phone = _normalizeWhatsAppPhone(item.teacherMobile);
    if (phone.isEmpty) {
      final ok = await _promptEditTeacherAndMobile(item);
      if (!ok || !mounted) return;
      phone = _normalizeWhatsAppPhone(item.teacherMobile);
      if (phone.isEmpty) return;
    }

    var message = _buildGentleReminderMessage(item);

    if (customizeFirst) {
      bool remAtt = !item.isAttendanceDone;
      bool remMdm = !item.isMdmDone;
      bool remBf = !item.isBreakfastDone;
      if (!remAtt && !remMdm && !remBf) {
        remAtt = true;
        remMdm = true;
        remBf = true;
      }
      final msgCtrl = TextEditingController(
        text: _buildGentleReminderMessage(
          item,
          customPendingItems: [
            if (remAtt) 'હાજરી (Attendance)',
            if (remMdm) 'પીએમ પોષણ (PM POSHAN)',
            if (remBf) 'અલ્પાહાર (Breakfast)',
          ],
        ),
      );

      final confirmedMessage = await showDialog<String>(
        context: context,
        builder: (dialogCtx) => StatefulBuilder(
          builder: (ctx, setD) {
            void rebuildText() {
              msgCtrl.text = _buildGentleReminderMessage(
                item,
                customPendingItems: [
                  if (remAtt) 'હાજરી (Attendance)',
                  if (remMdm) 'પીએમ પોષણ (PM POSHAN)',
                  if (remBf) 'અલ્પાહાર (Breakfast)',
                ],
              );
            }

            return AlertDialog(
              title: Text(
                '📲 WhatsApp નમ્ર રીમાઈન્ડર • ${item.classLabel}',
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'શિક્ષક: ${item.teacherName.isEmpty ? "વર્ગ શિક્ષક" : item.teacherName} (📞 ${_displayMobile10(phone)})',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'રીમાઈન્ડરમાં સામેલ કરવાની બાકી બાબતો:',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('૧. હાજરી'),
                            selected: remAtt,
                            onSelected: (v) {
                              setD(() {
                                remAtt = v;
                                rebuildText();
                              });
                            },
                          ),
                          FilterChip(
                            label: const Text('૨. પીએમ પોષણ'),
                            selected: remMdm,
                            onSelected: (v) {
                              setD(() {
                                remMdm = v;
                                rebuildText();
                              });
                            },
                          ),
                          FilterChip(
                            label: const Text('૩. અલ્પાહાર'),
                            selected: remBf,
                            onSelected: (v) {
                              setD(() {
                                remBf = v;
                                rebuildText();
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: msgCtrl,
                        minLines: 7,
                        maxLines: 14,
                        decoration: const InputDecoration(
                          labelText: 'ગુજરાતી WhatsApp રીમાઈન્ડર સંદેશ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(null),
                  child: const Text('રદ કરો'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: msgCtrl.text));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ ગુજરાતી સંદેશ કોપી થઈ ગયો!'),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('સંદેશ કોપી કરો'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF15803D),
                  ),
                  onPressed: () =>
                      Navigator.of(dialogCtx).pop(msgCtrl.text.trim()),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('WhatsApp ખોલો'),
                ),
              ],
            );
          },
        ),
      );
      msgCtrl.dispose();
      if (confirmedMessage == null || confirmedMessage.isEmpty) return;
      message = confirmedMessage;
    }

    final uri = Uri.https(
      'wa.me',
      '/$phone',
      <String, String>{'text': message},
    );
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw StateError('WhatsApp ખોલી શકાયું નથી.');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('WhatsApp ખોલવામાં ભૂલ: $e')),
      );
    }
  }

  Future<void> _sendNextPendingInQueue() async {
    final pendingWithPhone = _items
        .where(
          (i) =>
              i.hasAnyPending &&
              _normalizeWhatsAppPhone(i.teacherMobile).isNotEmpty,
        )
        .toList();
    if (pendingWithPhone.isEmpty) {
      final anyPending = _items.where((i) => i.hasAnyPending).toList();
      if (anyPending.isNotEmpty) {
        await _sendWhatsAppReminder(anyPending.first);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ તમામ વર્ગોની એન્ટ્રી પૂર્ણ થઈ ગઈ છે!'),
        ),
      );
      return;
    }
    if (_queueIndex >= pendingWithPhone.length) {
      _queueIndex = 0;
    }
    final target = pendingWithPhone[_queueIndex];
    setState(() {
      _queueIndex = (_queueIndex + 1) % pendingWithPhone.length;
    });
    await _sendWhatsAppReminder(target);
  }

  Future<void> _shareGroupPendingSummaryOnWhatsApp() async {
    final msg = _buildSchoolGroupPendingSummaryMessage();
    final uri = Uri.https('wa.me', '/', <String, String>{'text': msg});
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        await Clipboard.setData(ClipboardData(text: msg));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ સંયુક્ત રીમાઈન્ડર સંદેશ કોપી થઈ ગયો!'),
            ),
          );
        }
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: msg));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ સંયુક્ત રીમાઈન્ડર સંદેશ કોપી થઈ ગયો!'),
          ),
        );
      }
    }
  }

  // Aggregate getters
  int get _totalClasses => _items.length;
  int get _completedClasses => _items.where((i) => i.isAllThreeDone).length;
  int get _pendingClasses => _items.where((i) => i.hasAnyPending).length;
  int get _attPendingCount => _items.where((i) => !i.isAttendanceDone).length;
  int get _mdmPendingCount => _items.where((i) => !i.isMdmDone).length;
  int get _bfPendingCount => _items.where((i) => !i.isBreakfastDone).length;

  int get _totalRegBoys => _items.fold<int>(0, (s, i) => s + i.regBoys);
  int get _totalRegGirls => _items.fold<int>(0, (s, i) => s + i.regGirls);
  int get _totalRegistered => _items.fold<int>(0, (s, i) => s + i.regTotal);

  int get _totalPresBoys => _items.fold<int>(0, (s, i) => s + i.presBoys);
  int get _totalPresGirls => _items.fold<int>(0, (s, i) => s + i.presGirls);
  int get _totalPresent => _items.fold<int>(0, (s, i) => s + i.presTotal);

  int get _totalAbsent =>
      _items.fold<int>(0, (s, i) => s + i.absentTotal);

  int get _totalMdmBoys => _items.fold<int>(0, (s, i) => s + i.mdmBoys);
  int get _totalMdmGirls => _items.fold<int>(0, (s, i) => s + i.mdmGirls);
  int get _totalMdm => _items.fold<int>(0, (s, i) => s + i.mdmTotal);

  int get _totalBfBoys => _items.fold<int>(0, (s, i) => s + i.bfBoys);
  int get _totalBfGirls => _items.fold<int>(0, (s, i) => s + i.bfGirls);
  int get _totalBreakfast => _items.fold<int>(0, (s, i) => s + i.bfTotal);

  String _fmtPct(int numerator, int denominator) {
    if (denominator <= 0 || numerator <= 0) return '0.0%';
    return '${(numerator * 100.0 / denominator).toStringAsFixed(1)}%';
  }

  List<_ClassDailyStatusItem> get _filteredItems {
    switch (_filter) {
      case 'pending':
        return _items.where((i) => i.hasAnyPending).toList();
      case 'completed':
        return _items.where((i) => i.isAllThreeDone).toList();
      case 'att_pending':
        return _items.where((i) => !i.isAttendanceDone).toList();
      case 'mdm_pending':
        return _items.where((i) => !i.isMdmDone).toList();
      case 'bf_pending':
        return _items.where((i) => !i.isBreakfastDone).toList();
      default:
        return _items;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _dmy(_selectedDate);
    final dateIso = _iso(_selectedDate);
    final pendingCount = _pendingClasses;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: pendingCount > 0
              ? const Color(0xFFF59E0B).withValues(alpha: 0.55)
              : const Color(0xFF10B981).withValues(alpha: 0.55),
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Banner Header
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F2942),
                  Color(0xFF154360),
                  Color(0xFF0E6251),
                ],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.dashboard_customize_rounded,
                        color: Color(0xFFFFD166),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '📊 આજનો લાઈવ દૈનિક અહેવાલ અને હાજરી / પીએમ પોષણ / અલ્પાહાર ડેશબોર્ડ',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'રિપોર્ટ જનરેટ કર્યા વગર સીધો જ દૈનિક અહેવાલ જુઓ અને બાકી એન્ટ્રીવાળા વર્ગ શિક્ષકને ૧ ક્લિકથી WhatsApp રીમાઈન્ડર મોકલો',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!widget.isFullScreen)
                      IconButton(
                        tooltip: 'મોટી સ્ક્રીનમાં ખોલો (Full Screen)',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SupabaseAdminDailyDashboardScreen(
                                profile: widget.profile,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.open_in_full_rounded,
                          color: Colors.white,
                        ),
                      ),
                    if (!widget.isFullScreen)
                      IconButton(
                        tooltip: _expanded ? 'સંકોચો (Collapse)' : 'વિસ્તૃત કરો (Expand)',
                        onPressed: () => setState(() => _expanded = !_expanded),
                        icon: Icon(
                          _expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0F2942),
                      ),
                      onPressed: _loading ? null : _pickDate,
                      icon: const Icon(Icons.calendar_month_rounded, size: 18),
                      label: Text(
                        'તારીખ: $dateLabel ($dateIso)',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'ગઈકાલ (Previous Day)',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _loading ? null : () => _shiftDate(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                      ),
                      onPressed: _loading
                          ? null
                          : () {
                              final now = _indiaNow();
                              setState(() {
                                _selectedDate =
                                    DateTime(now.year, now.month, now.day);
                              });
                              _loadDashboard();
                            },
                      child: const Text(
                        'આજની તારીખ (Today)',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'આગળનો દિવસ (Next Day)',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _loading ? null : () => _shiftDate(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD166),
                        foregroundColor: const Color(0xFF0F2942),
                      ),
                      onPressed: _loading ? null : _loadDashboard,
                      icon: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text(
                        'તાજું કરો (Refresh)',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (_dailySerial.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'હાજરી ક્રમાંક: $_dailySerial',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _threeStepMode
                            ? 'મોડ: ૩-તબક્કા સેવ (હાજરી • પીએમ પોષણ • અલ્પાહાર)'
                            : 'મોડ: સિંગલ સેવ',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (!_expanded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Text(
                    'કુલ વર્ગો: $_totalClasses  |  ✅ પૂર્ણ: $_completedClasses (${_fmtPct(_completedClasses, _totalClasses)})  |  ⏳ બાકી: $_pendingClasses  |  હાજર: $_totalPresent / $_totalRegistered (${_fmtPct(_totalPresent, _totalRegistered)})  |  પીએમ પોષણ: $_totalMdm (${_fmtPct(_totalMdm, _totalPresent)})  |  અલ્પાહાર: $_totalBreakfast (${_fmtPct(_totalBreakfast, _totalPresent)})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _expanded = true),
                    icon: const Icon(Icons.visibility_rounded),
                    label: const Text('ડેશબોર્ડ અને WhatsApp રીમાઈન્ડર ખોલો'),
                  ),
                ],
              ),
            )
          else if (_loading)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 10),
                    Text(
                      'આજનો લાઈવ દૈનિક અહેવાલ અને વર્ગવાર સ્થિતિ લોડ થઈ રહી છે...',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '❌ $_error',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _loadDashboard,
                    icon: const Icon(Icons.refresh),
                    label: const Text('ફરી પ્રયાસ કરો'),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Live KPI Summary Cards (in Gujarati)
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _SummaryKpiTile(
                        title: 'કુલ વર્ગો અને એન્ટ્રી સ્થિતિ',
                        primaryValue:
                            'પૂર્ણ: $_completedClasses / $_totalClasses (${_fmtPct(_completedClasses, _totalClasses)})',
                        subtitle: _pendingClasses == 0
                            ? '🎉 તમામ વર્ગોની એન્ટ્રી પૂર્ણ!'
                            : 'બાકી વર્ગો: $_pendingClasses (હાજરી: $_attPendingCount • પોષણ: $_mdmPendingCount • અલ્પાહાર: $_bfPendingCount)',
                        icon: Icons.fact_check_rounded,
                        color: _pendingClasses == 0
                            ? const Color(0xFF059669)
                            : const Color(0xFFD97706),
                      ),
                      _SummaryKpiTile(
                        title: '૧. આજની કુલ હાજરી (Present)',
                        primaryValue:
                            'હાજર: $_totalPresent / $_totalRegistered (${_fmtPct(_totalPresent, _totalRegistered)})',
                        subtitle:
                            'કુમાર: $_totalPresBoys/$_totalRegBoys (${_fmtPct(_totalPresBoys, _totalRegBoys)}) • કન્યા: $_totalPresGirls/$_totalRegGirls (${_fmtPct(_totalPresGirls, _totalRegGirls)}) • ગેરહાજર: $_totalAbsent',
                        icon: Icons.groups_rounded,
                        color: const Color(0xFF1D4ED8),
                      ),
                      _SummaryKpiTile(
                        title: '૨. આજનું પીએમ પોષણ (MDM)',
                        primaryValue:
                            'લાભાર્થી: $_totalMdm (${_fmtPct(_totalMdm, _totalPresent)})',
                        subtitle:
                            'હાજરના: ${_fmtPct(_totalMdm, _totalPresent)} • કુમાર: $_totalMdmBoys • કન્યા: $_totalMdmGirls (બાકી વર્ગો: $_mdmPendingCount)',
                        icon: Icons.restaurant_rounded,
                        color: const Color(0xFF0F766E),
                      ),
                      _SummaryKpiTile(
                        title: '૩. આજનો અલ્પાહાર (Breakfast)',
                        primaryValue:
                            'લાભાર્થી: $_totalBreakfast (${_fmtPct(_totalBreakfast, _totalPresent)})',
                        subtitle:
                            'હાજરના: ${_fmtPct(_totalBreakfast, _totalPresent)} • કુમાર: $_totalBfBoys • કન્યા: $_totalBfGirls (બાકી વર્ગો: $_bfPendingCount)',
                        icon: Icons.free_breakfast_rounded,
                        color: const Color(0xFF7C3AED),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // 2. Quick Bulk WhatsApp Reminder Bar & Filter Chips
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Icon(
                              Icons.notifications_active_rounded,
                              color: Color(0xFF15803D),
                              size: 20,
                            ),
                            const Text(
                              'વર્ગવાર બાકી એન્ટ્રી તપાસો અને WhatsApp રીમાઈન્ડર મોકલો:',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            if (_pendingClasses > 0)
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF15803D),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _sendNextPendingInQueue,
                                icon: const Icon(Icons.send_to_mobile_rounded,
                                    size: 18),
                                label: Text(
                                  'બાકી વર્ગના શિક્ષકને વારાફરતી રીમાઈન્ડર (${_queueIndex + 1}/$_pendingClasses)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF0F766E),
                                side: const BorderSide(
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                              onPressed: _shareGroupPendingSummaryOnWhatsApp,
                              icon: const Icon(Icons.share_rounded, size: 17),
                              label: const Text(
                                'શાળા WhatsApp ગ્રુપમાં સંયુક્ત યાદી મોકલો',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                            FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFDBEAFE),
                                foregroundColor: const Color(0xFF1E3A8A),
                              ),
                              onPressed: _schoolRef.isEmpty
                                  ? null
                                  : () => PrincipalDailySummaryService.openSummaryDialog(
                                        context,
                                        schoolRef: _schoolRef,
                                        schoolName: _schoolName.isEmpty
                                            ? 'શાળા'
                                            : _schoolName,
                                        schoolType: _schoolType,
                                        date: _selectedDate,
                                      ),
                              icon: const Icon(Icons.summarize_rounded, size: 17),
                              label: const Text(
                                '📋 આજનો સારાંશ (CRC/BRC WhatsApp & A4)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildFilterChip(
                                'all',
                                '📋 બધા વર્ગો (${_items.length})',
                              ),
                              const SizedBox(width: 6),
                              _buildFilterChip(
                                'pending',
                                '🔴 બાકી વર્ગો ($_pendingClasses)',
                              ),
                              const SizedBox(width: 6),
                              _buildFilterChip(
                                'att_pending',
                                '⏳ હાજરી બાકી ($_attPendingCount)',
                              ),
                              const SizedBox(width: 6),
                              _buildFilterChip(
                                'mdm_pending',
                                '🍛 પીએમ પોષણ બાકી ($_mdmPendingCount)',
                              ),
                              const SizedBox(width: 6),
                              _buildFilterChip(
                                'bf_pending',
                                '🥣 અલ્પાહાર બાકી ($_bfPendingCount)',
                              ),
                              const SizedBox(width: 6),
                              _buildFilterChip(
                                'completed',
                                '🟢 સંપૂર્ણ પૂર્ણ ($_completedClasses)',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 3. Class-wise Cards with 1-Tap Gujarati WhatsApp Gentle Reminder
                  if (_filteredItems.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF059669),
                            size: 28,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '🎉 ખૂબ સરસ! પસંદ કરેલા ફિલ્ટર મુજબ કોઈ વર્ગમાં એન્ટ્રી બાકી નથી.',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF065F46),
                                fontSize: 14.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Column(
                      children: [
                        for (final item in _filteredItems)
                          _buildClassRowCard(item),
                      ],
                    ),

                  const SizedBox(height: 16),

                  // 4. Live Daily Report Table (Without Generating Report!)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(13),
                            ),
                          ),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.table_chart_rounded,
                                    color: Color(0xFF1E3A8A),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '📋 લાઈવ દૈનિક અહેવાલ પત્રક (તારીખ: $dateLabel) — રિપોર્ટ જનરેટ કર્યા વગર',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14.5,
                                      color: Color(0xFF1E3A8A),
                                    ),
                                  ),
                                ],
                              ),
                              Wrap(
                                spacing: 6,
                                children: [
                                  ChoiceChip(
                                    label: const Text(
                                      'સંક્ષિપ્ત પત્રક (કુમાર/કન્યા/કુલ)',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    selected: _reportTableMode == 'compact',
                                    onSelected: (_) => setState(
                                        () => _reportTableMode = 'compact'),
                                  ),
                                  ChoiceChip(
                                    label: const Text(
                                      'સંપૂર્ણ જ્ઞાતિવાર પત્રક (SC/ST/OBC/Gen)',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    selected: _reportTableMode == 'category',
                                    onSelected: (_) => setState(
                                        () => _reportTableMode = 'category'),
                                  ),
                                  ChoiceChip(
                                    label: const Text(
                                      'પત્રક છુપાવો',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    selected: _reportTableMode == 'hidden',
                                    onSelected: (_) => setState(
                                        () => _reportTableMode = 'hidden'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (_reportTableMode == 'compact')
                          _buildCompactLiveDailyReportTable()
                        else if (_reportTableMode == 'category')
                          _buildCategoryWiseLiveDailyReportTable(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final selected = _filter == key;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          fontSize: 12.5,
        ),
      ),
      selected: selected,
      onSelected: (_) => setState(() => _filter = key),
    );
  }

  Widget _buildClassRowCard(_ClassDailyStatusItem item) {
    final isDone = item.isAllThreeDone;
    final mobile10 = _displayMobile10(item.teacherMobile);
    final hasMobile = _normalizeWhatsAppPhone(item.teacherMobile).isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDone ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDone
              ? const Color(0xFF86EFAC)
              : const Color(0xFFFCD34D),
          width: 1.3,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Class Name + Teacher Info
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDone
                          ? const Color(0xFF15803D)
                          : const Color(0xFFB45309),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      item.classLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.person_pin_rounded,
                              size: 17,
                              color: Color(0xFF334155),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                item.teacherName.isNotEmpty
                                    ? 'શિક્ષક: ${item.teacherName}'
                                    : 'શિક્ષક સેટ કરેલ નથી (અહીં ક્લિક કરો)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                  color: item.teacherName.isNotEmpty
                                      ? const Color(0xFF0F172A)
                                      : const Color(0xFFB91C1C),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => _promptEditTeacherAndMobile(item),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFFCBD5E1),
                                  ),
                                ),
                                child: Text(
                                  hasMobile
                                      ? '📞 $mobile10 ✏️'
                                      : '📞 નંબર ઉમેરો ✏️',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: hasMobile
                                        ? const Color(0xFF0F766E)
                                        : const Color(0xFFDC2626),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'રજીસ્ટર સંખ્યા: કુલ ${item.regTotal} (કુમાર: ${item.regBoys} • કન્યા: ${item.regGirls})',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF475569),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // WhatsApp Gentle Reminder Action Buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: item.hasAnyPending
                          ? const Color(0xFF15803D)
                          : const Color(0xFF0D9488),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onPressed: () => _sendWhatsAppReminder(item),
                    icon: const Icon(Icons.chat_rounded, size: 17),
                    label: Text(
                      item.hasAnyPending
                          ? '📲 રીમાઈન્ડર મોકલો (Send Reminder)'
                          : '📲 WhatsApp સંદેશ',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.outlined(
                    tooltip: 'સંદેશ જુઓ / સુધારીને મોકલો (Preview & Edit)',
                    onPressed: () =>
                        _sendWhatsAppReminder(item, customizeFirst: true),
                    icon: const Icon(Icons.edit_note_rounded, size: 20),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 10),

          // 3 Status Badges: 1. Attendance, 2. PM POSHAN, 3. Breakfast
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusStepBadge(
                stepTitle: '૧. હાજરી (Attendance)',
                isDone: item.isAttendanceDone,
                isWarning: false,
                statusText: item.isAttendanceDone
                    ? '✅ પૂર્ણ (હાજર: ${item.presTotal}/${item.regTotal} (${_fmtPct(item.presTotal, item.regTotal)}) • ગેરહાજર: ${item.absentTotal})'
                    : '⏳ બાકી (Pending)',
              ),
              _StatusStepBadge(
                stepTitle: '૨. પીએમ પોષણ (PM POSHAN)',
                isDone: item.isMdmDone,
                isWarning: item.isMdmZeroWarning,
                statusText: item.isMdmDone
                    ? '✅ પૂર્ણ (લાભાર્થી: ${item.mdmTotal} (${_fmtPct(item.mdmTotal, item.presTotal)}) • કુ:${item.mdmBoys} ક:${item.mdmGirls})'
                    : (item.isMdmZeroWarning
                        ? '⚠️ 0 એન્ટ્રી (બાકી)'
                        : '⏳ બાકી (Pending)'),
              ),
              _StatusStepBadge(
                stepTitle: '૩. અલ્પાહાર (Breakfast)',
                isDone: item.isBreakfastDone,
                isWarning: item.isBreakfastZeroWarning,
                statusText: item.isBreakfastDone
                    ? '✅ પૂર્ણ (લાભાર્થી: ${item.bfTotal} (${_fmtPct(item.bfTotal, item.presTotal)}) • કુ:${item.bfBoys} ક:${item.bfGirls})'
                    : (item.isBreakfastZeroWarning
                        ? '⚠️ 0 એન્ટ્રી (બાકી)'
                        : '⏳ બાકી (Pending)'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactLiveDailyReportTable() {
    if (_items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('કોઈ સક્રિય વર્ગ ઉપલબ્ધ નથી.'),
      );
    }

    final balvatika = _items
        .where((i) =>
            i.reportGroup.toLowerCase().contains('balvatika') ||
            i.classLabel.contains('બાલવાટિકા'))
        .toList();
    final std1to5 = _items
        .where((i) =>
            !balvatika.contains(i) &&
            (i.reportGroup.toLowerCase().contains('1to5') ||
                RegExp(r'\b[1-5]\b').hasMatch(i.classLabel) ||
                RegExp(r'[૧-૫]').hasMatch(i.classLabel)))
        .toList();
    final std6to8 = _items
        .where((i) =>
            !balvatika.contains(i) &&
            !std1to5.contains(i) &&
            (i.reportGroup.toLowerCase().contains('6to8') ||
                RegExp(r'\b[6-8]\b').hasMatch(i.classLabel) ||
                RegExp(r'[૬-૮]').hasMatch(i.classLabel)))
        .toList();
    final others = _items
        .where((i) =>
            !balvatika.contains(i) &&
            !std1to5.contains(i) &&
            !std6to8.contains(i))
        .toList();

    DataRow buildClassDataRow(_ClassDailyStatusItem item) {
      return DataRow(
        color: WidgetStatePropertyAll(
          item.isAllThreeDone
              ? Colors.white
              : const Color(0xFFFFFBEB),
        ),
        cells: [
          DataCell(
            Text(
              item.classLabel,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          DataCell(
            Text(
              item.teacherName.isEmpty ? '—' : item.teacherName,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          DataCell(
            Text(
              '${item.regBoys} + ${item.regGirls} = ${item.regTotal}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          DataCell(
            Text(
              item.isAttendanceDone
                  ? '${item.presBoys} + ${item.presGirls} = ${item.presTotal} (${_fmtPct(item.presTotal, item.regTotal)})'
                  : '⏳ બાકી',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: item.isAttendanceDone
                    ? const Color(0xFF1E3A8A)
                    : const Color(0xFFDC2626),
              ),
            ),
          ),
          DataCell(
            Text(
              item.isAttendanceDone ? '${item.absentTotal}' : '—',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          DataCell(
            Text(
              item.isMdmDone
                  ? '${item.mdmBoys} + ${item.mdmGirls} = ${item.mdmTotal}'
                  : (item.isMdmZeroWarning ? '⚠️ 0 (બાકી)' : '⏳ બાકી'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: item.isMdmDone
                    ? const Color(0xFF0F766E)
                    : const Color(0xFFD97706),
              ),
            ),
          ),
          DataCell(
            Text(
              item.isBreakfastDone
                  ? '${item.bfBoys} + ${item.bfGirls} = ${item.bfTotal}'
                  : (item.isBreakfastZeroWarning ? '⚠️ 0 (બાકી)' : '⏳ બાકી'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: item.isBreakfastDone
                    ? const Color(0xFF6D28D9)
                    : const Color(0xFFD97706),
              ),
            ),
          ),
          DataCell(
            item.isAllThreeDone
                ? const Text(
                    '✅ સંપૂર્ણ પૂર્ણ',
                    style: TextStyle(
                      color: Color(0xFF15803D),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  )
                : FilledButton.tonalIcon(
                    onPressed: () => _sendWhatsAppReminder(item),
                    icon: const Icon(Icons.chat_rounded, size: 15),
                    label: const Text(
                      '📲 રીમાઈન્ડર',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
          ),
        ],
      );
    }

    DataRow buildTotalRow(String label, List<_ClassDailyStatusItem> group) {
      final rB = group.fold<int>(0, (s, i) => s + i.regBoys);
      final rG = group.fold<int>(0, (s, i) => s + i.regGirls);
      final rT = group.fold<int>(0, (s, i) => s + i.regTotal);

      final pB = group.fold<int>(0, (s, i) => s + i.presBoys);
      final pG = group.fold<int>(0, (s, i) => s + i.presGirls);
      final pT = group.fold<int>(0, (s, i) => s + i.presTotal);

      final absT = group.fold<int>(0, (s, i) => s + i.absentTotal);

      final mB = group.fold<int>(0, (s, i) => s + i.mdmBoys);
      final mG = group.fold<int>(0, (s, i) => s + i.mdmGirls);
      final mT = group.fold<int>(0, (s, i) => s + i.mdmTotal);

      final bB = group.fold<int>(0, (s, i) => s + i.bfBoys);
      final bG = group.fold<int>(0, (s, i) => s + i.bfGirls);
      final bT = group.fold<int>(0, (s, i) => s + i.bfTotal);

      final doneCnt = group.where((i) => i.isAllThreeDone).length;

      return DataRow(
        color: const WidgetStatePropertyAll(Color(0xFFE2E8F0)),
        cells: [
          DataCell(
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          DataCell(
            Text(
              'પૂર્ણ: $doneCnt/${group.length}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          DataCell(
            Text(
              '$rB + $rG = $rT',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          DataCell(
            Text(
              '$pB + $pG = $pT (${_fmtPct(pT, rT)})',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Color(0xFF1E3A8A),
              ),
            ),
          ),
          DataCell(
            Text(
              '$absT',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          DataCell(
            Text(
              '$mB + $mG = $mT',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F766E),
              ),
            ),
          ),
          DataCell(
            Text(
              '$bB + $bG = $bT',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Color(0xFF6D28D9),
              ),
            ),
          ),
          DataCell(
            Text(
              doneCnt == group.length
                  ? '✅ ૧૦૦% પૂર્ણ'
                  : '⏳ ${group.length - doneCnt} બાકી',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                color: doneCnt == group.length
                    ? const Color(0xFF15803D)
                    : const Color(0xFFB45309),
              ),
            ),
          ),
        ],
      );
    }

    final rows = <DataRow>[];
    for (final item in balvatika) {
      rows.add(buildClassDataRow(item));
    }
    if (balvatika.length > 1) {
      rows.add(buildTotalRow('કુલ બાલવાટિકા', balvatika));
    }
    for (final item in std1to5) {
      rows.add(buildClassDataRow(item));
    }
    if (std1to5.isNotEmpty) {
      rows.add(buildTotalRow('કુલ ધોરણ 1 થી 5', std1to5));
    }
    if (balvatika.isNotEmpty && std1to5.isNotEmpty) {
      rows.add(
        buildTotalRow(
          'કુલ બાલવાટિકા થી ધોરણ 5',
          [...balvatika, ...std1to5],
        ),
      );
    }
    for (final item in std6to8) {
      rows.add(buildClassDataRow(item));
    }
    if (std6to8.isNotEmpty) {
      rows.add(buildTotalRow('કુલ ધોરણ 6 થી 8', std6to8));
    }
    if (std1to5.isNotEmpty && std6to8.isNotEmpty) {
      rows.add(
        buildTotalRow('કુલ ધોરણ 1 થી 8', [...std1to5, ...std6to8]),
      );
    }
    for (final item in others) {
      rows.add(buildClassDataRow(item));
    }
    rows.add(buildTotalRow('કુલ સમગ્ર શાળા (Grand Total)', _items));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: const WidgetStatePropertyAll(Color(0xFF1E293B)),
        headingTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12.5,
        ),
        dataRowMinHeight: 42,
        dataRowMaxHeight: 52,
        columnSpacing: 18,
        columns: const [
          DataColumn(label: Text('ધોરણ / વર્ગ')),
          DataColumn(label: Text('વર્ગ શિક્ષક')),
          DataColumn(label: Text('રજીસ્ટર (કુ+ક=કુલ)')),
          DataColumn(label: Text('૧. હાજર (કુ+ક=કુલ)')),
          DataColumn(label: Text('ગેરહાજર')),
          DataColumn(label: Text('૨. પીએમ પોષણ (કુ+ક=કુલ)')),
          DataColumn(label: Text('૩. અલ્પાહાર (કુ+ક=કુલ)')),
          DataColumn(label: Text('સ્થિતિ / રીમાઈન્ડર')),
        ],
        rows: rows,
      ),
    );
  }

  Widget _buildCategoryWiseLiveDailyReportTable() {
    if (_categoryReportGrid.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('કોઈ દૈનિક અહેવાલ ડેટા ઉપલબ્ધ નથી.'),
      );
    }
    final headers = _categoryReportGrid.first;
    final bodyRows = _categoryReportGrid.skip(1).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: const WidgetStatePropertyAll(Color(0xFF0F2942)),
        headingTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
        columnSpacing: 14,
        dataRowMinHeight: 38,
        dataRowMaxHeight: 46,
        columns: [
          for (final h in headers) DataColumn(label: Text(h)),
        ],
        rows: [
          for (final row in bodyRows)
            DataRow(
              color: WidgetStatePropertyAll(
                row.isNotEmpty && row.first.startsWith('કુલ')
                    ? const Color(0xFFE2E8F0)
                    : Colors.white,
              ),
              cells: [
                for (var i = 0; i < headers.length; i++)
                  DataCell(
                    Text(
                      i < row.length
                          ? (row[i].isEmpty && i > 0 ? '⏳' : row[i])
                          : '',
                      style: TextStyle(
                        fontWeight: (i == 0 ||
                                (row.isNotEmpty && row.first.startsWith('કુલ')))
                            ? FontWeight.w800
                            : FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SummaryKpiTile extends StatelessWidget {
  const _SummaryKpiTile({
    required this.title,
    required this.primaryValue,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String primaryValue;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 265,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  primaryValue,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusStepBadge extends StatelessWidget {
  const _StatusStepBadge({
    required this.stepTitle,
    required this.isDone,
    required this.isWarning,
    required this.statusText,
  });

  final String stepTitle;
  final bool isDone;
  final bool isWarning;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    final bgColor = isDone
        ? const Color(0xFFDCFCE7)
        : (isWarning ? const Color(0xFFFEF3C7) : const Color(0xFFFEE2E2));
    final borderColor = isDone
        ? const Color(0xFF4ADE80)
        : (isWarning ? const Color(0xFFFBBF24) : const Color(0xFFF87171));
    final textColor = isDone
        ? const Color(0xFF14532D)
        : (isWarning ? const Color(0xFF78350F) : const Color(0xFF7F1D1D));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$stepTitle: ',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: textColor,
            ),
          ),
          Text(
            statusText,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

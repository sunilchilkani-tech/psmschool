import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/school_class_order.dart';
import '../services/school_name_language_service.dart';
import '../services/supabase_student_service.dart';
import '../widgets/school_name_language_selector.dart';
import '../services/school_type.dart';
import 'package:pmshri_attendance/services/class_label.dart';

/// Supabase-native attendance entry. This screen intentionally does not use the
/// legacy Apps Script AppState session. RLS and database guards remain the
/// authority for which school/classes may be read or written.
class SupabaseAttendanceEntryScreen extends StatefulWidget {
  const SupabaseAttendanceEntryScreen({
    super.key,
    required this.profile,
    this.readOnly = false,
    this.showAppBar = true,
  });

  final Map<String, dynamic> profile;
  final bool readOnly;
  final bool showAppBar;

  @override
  State<SupabaseAttendanceEntryScreen> createState() =>
      _SupabaseAttendanceEntryScreenState();
}

class _SupabaseAttendanceEntryScreenState
    extends State<SupabaseAttendanceEntryScreen>
    with WidgetsBindingObserver {
  final SupabaseClient _client = Supabase.instance.client;
  static const List<String> _categories = <String>['SC', 'ST', 'OBC', 'OTHER'];
  static const List<String> _allGenders = <String>['BOYS', 'GIRLS', 'UNSPECIFIED'];
  static const List<String> _metrics = <String>['present', 'mdm', 'breakfast'];

  final Map<String, TextEditingController> _directControllers =
      <String, TextEditingController>{};
  final TextEditingController _breakfastTotalController = TextEditingController();

  bool _useDropdowns = true;
  String _breakfastEntryMode = 'category'; // category-wise or whole-class total
  String? _validationMessage;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _schoolRef;
  String _schoolNameLanguage = SchoolNameLanguageService.gujarati;
  Map<String, dynamic> _schoolNameContext = <String, dynamic>{};
  String? _selectedClassId;
  String _date = _today();
  String _mode = 'student';
  List<Map<String, dynamic>> _classes = <Map<String, dynamic>>[];
  List<_AttendanceStudent> _students = <_AttendanceStudent>[];
  Map<String, dynamic>? _day;
  String? _statusMessage;
  String _attendanceLockTime = '12:01';
  bool _isHoliday = false;
  bool _holidayCheckFailed = false;
  String _holidayReason = '';
  bool _adminOverrideAuthorized = false;
  String _adminOverrideForIndiaDay = '';

  bool _waitingForWhatsAppReturn = false;
  Completer<void>? _whatsAppResumeCompleter;

  bool get _isAdmin => '${widget.profile['role'] ?? ''}'.trim().toLowerCase() == 'admin';

  DateTime _indiaNow() => DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

  String _indiaToday() {
    final now = _indiaNow();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  bool get _isFutureDate => _date.compareTo(_indiaToday()) > 0;
  bool get _isPastDate => _date.compareTo(_indiaToday()) < 0;

  bool get _isSunday => DateTime.tryParse('${_date}T00:00:00')?.weekday == DateTime.sunday;
  bool get _isNonSchoolDay => _isSunday || _isHoliday;
  bool get _dateNeedsAdminPassword => _isNonSchoolDay || _isPastDate;
  bool get _adminOverrideIsCurrent =>
      _adminOverrideAuthorized && _adminOverrideForIndiaDay == _indiaToday();

  String get _nonSchoolDayMessage {
    if (_holidayCheckFailed) {
      return 'રજાની યાદી ચકાસી શકાઈ નથી. Refresh કર્યા પછી જ હાજરી નોંધાવી શકાશે.';
    }
    if (_isHoliday && _isSunday) {
      return 'આજે રવિવાર અને જાહેર કરેલી રજા છે. હાજરી નોંધાવી શકાતી નથી.';
    }
    if (_isHoliday) {
      final reason = _holidayReason.trim();
      return 'આજે શાળામાં રજા છે${reason.isEmpty ? '' : ': $reason'} — હાજરી નોંધાવી શકાતી નથી.';
    }
    if (_isSunday) return 'આજે રવિવાર છે. રવિવારે હાજરી નોંધાવી શકાતી નથી.';
    return '';
  }

  final SupabaseStudentService _studentService = SupabaseStudentService();
  bool _threeStepSaveMode = false;
  bool _directEntryEnabled = true;

  // Attendance can be recorded once at any time during the day; once recorded it freezes automatically.
  bool get _isTimeLocked => false;

  bool get _hasStepFlags =>
      _day != null &&
      (_day!['present_saved'] != null ||
          _day!['mdm_saved'] != null ||
          _day!['breakfast_saved'] != null ||
          _day!['present_frozen'] != null ||
          _day!['mdm_frozen'] != null ||
          _day!['breakfast_frozen'] != null);

  bool get _legacyDayFrozen =>
      _day != null &&
      (_day!['is_frozen'] == true ||
          (_day!['is_frozen'] == null && _day!['unfrozen_by_admin'] != true));

  bool get _presentSaved =>
      _day != null && (_hasStepFlags ? _day!['present_saved'] == true : true);

  bool get _mdmSaved =>
      _day != null && (_hasStepFlags ? _day!['mdm_saved'] == true : true);

  bool get _breakfastSaved =>
      _day != null &&
      (_hasStepFlags ? _day!['breakfast_saved'] == true : true);

  bool get _presentFrozen =>
      _day != null &&
      (_hasStepFlags ? _day!['present_frozen'] == true : _legacyDayFrozen);

  bool get _mdmFrozen =>
      _day != null &&
      (_hasStepFlags ? _day!['mdm_frozen'] == true : _legacyDayFrozen);

  bool get _breakfastFrozen =>
      _day != null &&
      (_hasStepFlags ? _day!['breakfast_frozen'] == true : _legacyDayFrozen);

  bool get _isAttendanceFrozen => _threeStepSaveMode
      ? (_day != null && _presentFrozen && _mdmFrozen && _breakfastFrozen)
      : _legacyDayFrozen;

  bool get _isAnyStepFrozen =>
      _day != null && (_presentFrozen || _mdmFrozen || _breakfastFrozen);

  bool get _isUnfrozenByAdmin =>
      _day != null &&
      _day!['unfrozen_by_admin'] == true &&
      !_isAttendanceFrozen;

  bool get _canEditDateBase =>
      !widget.readOnly &&
      !_isFutureDate &&
      !_holidayCheckFailed &&
      (_isAdmin ||
          _isUnfrozenByAdmin ||
          (!_isPastDate && !_isNonSchoolDay));

  bool get _canEditPresent => _threeStepSaveMode
      ? (_canEditDateBase && !_presentFrozen)
      : (_canEditDateBase && !_isAttendanceFrozen);

  bool get _canEditMdm => _threeStepSaveMode
      ? (_canEditDateBase && _presentSaved && !_mdmFrozen)
      : (_canEditDateBase && !_isAttendanceFrozen);

  bool get _canEditBreakfast => _threeStepSaveMode
      ? (_canEditDateBase && _presentSaved && !_breakfastFrozen)
      : (_canEditDateBase && !_isAttendanceFrozen);

  bool get _canEditAttendance => _threeStepSaveMode
      ? (_canEditPresent || _canEditMdm || _canEditBreakfast)
      : (_canEditDateBase && !_isAttendanceFrozen);

  Future<void> _toggleAttendanceFreeze(
    bool freeze, {
    String section = 'all',
  }) async {
    if (!_isAdmin || _day == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
      _statusMessage = null;
    });
    try {
      final updated = await _client.rpc(
        'psm_set_attendance_freeze_status',
        params: <String, dynamic>{
          'p_day_id': '${_day!['id'] ?? ''}',
          'p_class_id': _selectedClassId ?? '',
          'p_attendance_date': _date,
          'p_is_frozen': freeze,
          'p_section': section,
        },
      );
      if (!mounted) return;
      final secLabel = switch (section) {
        'present' => 'હાજર-ગેરહાજર (Present/Absent)',
        'mdm' => 'PM POSHAN',
        'breakfast' => 'અલ્પાહાર (Breakfast)',
        _ => 'હાજરી (Attendance)',
      };
      setState(() {
        if (updated is Map) {
          _day = Map<String, dynamic>.from(updated);
        } else {
          bool pF = _presentFrozen;
          bool mF = _mdmFrozen;
          bool bF = _breakfastFrozen;
          if (section == 'present') {
            pF = freeze;
          } else if (section == 'mdm') {
            mF = freeze;
          } else if (section == 'breakfast') {
            bF = freeze;
          } else {
            pF = freeze;
            mF = freeze;
            bF = freeze;
          }
          final allF = pF && mF && bF;
          _day = <String, dynamic>{
            ...?_day,
            'present_frozen': pF,
            'mdm_frozen': mF,
            'breakfast_frozen': bF,
            'is_frozen': allF,
            'unfrozen_by_admin': !allF,
          };
        }
        _statusMessage = freeze
            ? '$secLabel ફ્રીઝ કરવામાં આવેલ છે (Frozen).'
            : '$secLabel અનફ્રીઝ કરવામાં આવેલ છે — હવે શિક્ષક સુધારો કરીને સેવ કરી શકશે.';
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _cleanError(error);
        _saving = false;
      });
    }
  }

  static String _today() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInitial();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed &&
        _waitingForWhatsAppReturn &&
        _whatsAppResumeCompleter != null &&
        !_whatsAppResumeCompleter!.isCompleted) {
      _whatsAppResumeCompleter!.complete();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    if (_whatsAppResumeCompleter != null &&
        !_whatsAppResumeCompleter!.isCompleted) {
      _whatsAppResumeCompleter!.complete();
    }

    for (final controller in _directControllers.values) {
      controller.dispose();
    }

    _breakfastTotalController.dispose();
    super.dispose();
  }

  String _entryKey(String gender, String category, String metric) =>
      '${gender}_${category}_$metric';

  TextEditingController _controllerFor(String gender, String category, String metric) {
    final key = _entryKey(gender, category, metric);
    return _directControllers.putIfAbsent(key, TextEditingController.new);
  }

  String _text(dynamic value) => (value ?? '').toString().trim();

  int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(_text(value)) ?? 0;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  String _category(dynamic raw) {
    final value = _text(raw).toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    if (value == 'SC' || value.contains('SCHEDULED CASTE')) return 'SC';
    if (value == 'ST' || value.contains('SCHEDULED TRIBE')) return 'ST';
    if (value == 'OBC' || value.contains('BAKSHIPANCH') || value.contains('બક્ષી')) return 'OBC';
    return 'OTHER';
  }

  String get _schoolType {
    final raw = _text(
      _schoolNameContext['school_type'] ??
          _schoolNameContext['schoolType'] ??
          widget.profile['school_type'] ??
          widget.profile['schoolType'],
    );
    return SchoolType.canonical(raw);
  }

  String _gender(dynamic raw) {
    if (_schoolType == 'boys') return 'BOYS';
    if (_schoolType == 'girls') return 'GIRLS';
    final value = _text(raw).toUpperCase();
    if (const <String>{'BOYS', 'BOY', 'MALE', 'M', 'KUMAR', 'કુમાર'}.contains(value)) return 'BOYS';
    if (const <String>{'GIRLS', 'GIRL', 'FEMALE', 'F', 'KANYA', 'કન્યા'}.contains(value)) return 'GIRLS';
    return 'UNSPECIFIED';
  }

  List<String> get _entryGenders {
    final List<String> genders;
    if (_schoolType == 'boys' || _schoolType == 'boy') {
      genders = <String>['BOYS'];
    } else if (_schoolType == 'girls' || _schoolType == 'girl') {
      genders = <String>['GIRLS'];
    } else {
      genders = <String>['BOYS', 'GIRLS'];
    }
    if (_students.any((s) => _gender(s.raw['gender']) == 'UNSPECIFIED')) {
      genders.add('UNSPECIFIED');
    }
    return genders;
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
      _statusMessage = null;
      _validationMessage = null;
    });
    try {
      if (_client.auth.currentUser == null) {
        throw StateError('Your Supabase session is missing. Sign in again.');
      }
      final schoolRefValue = await _client.rpc('current_school_ref');
      final schoolRef = _text(schoolRefValue);
      if (schoolRef.isEmpty) throw StateError('No active school is linked to this login.');
      final schoolNameLanguage = await SchoolNameLanguageService.loadLanguage(schoolRef: schoolRef);
      final schoolNameContext = await SchoolNameLanguageService.loadCurrentSchoolContext(_client);

      // Restore the last class and Student/Direct Entry mode; attendance opens on today's date.
      final prefs = await SharedPreferences.getInstance();
      final classPrefKey = 'psm.attendance.$schoolRef.class';
      final modePrefKey = 'psm.attendance.$schoolRef.mode';
      final savedClassId = prefs.getString(classPrefKey);
      final savedMode = prefs.getString(modePrefKey);
      final dateToUse = _indiaToday();
      final modeToUse = savedMode == 'direct' ? 'direct' : 'student';

      FirestoreQueryBuilder.invalidateCache('school_settings');
      final settingsRow = await _client
          .from('school_settings')
          .select('config')
          .eq('school_ref', schoolRef)
          .maybeSingle();
      final settingsConfig = _asMap(settingsRow?['config']);
      final configuredLock = _text(settingsConfig['attendance_lock_time']);
      final lockTime = RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(configuredLock)
          ? configuredLock
          : '12:01';
      final threeStepMode = settingsConfig['three_step_attendance_save_mode'] == true;
      final directEntryEnabled = settingsConfig['direct_attendance_entry_enabled'] != false;
      final effectiveInitialMode = !directEntryEnabled ? 'student' : modeToUse;

      final rows = await _client
          .from('school_classes')
          .select('id,school_ref,class_key,label,sheet_name,standard,section,report_group,sort_order,is_active')
          .eq('school_ref', schoolRef)
          .eq('is_active', true)
          .order('sort_order')
          .order('label');
      var classes = SchoolClassOrder.sorted(
        rows.map((row) => Map<String, dynamic>.from(row)),
      );
      // Teachers: only their own standard (all sections). Admin: whole school.
      try {
        final allowedIds = await _client.rpc('psm_attendance_class_ids');
        if (allowedIds is List) {
          final set = allowedIds.map((e) => '$e').toSet();
          classes = classes.where((c) => set.contains('${c['id']}')).toList();
        }
      } catch (_) {}
      if (!mounted) return;
      final preferredClass = classes.any((row) => '${row['id']}' == (savedClassId ?? ''))
          ? savedClassId
          : (classes.isEmpty ? null : '${classes.first['id']}');
      setState(() {
        _schoolRef = schoolRef;
        _schoolNameLanguage = schoolNameLanguage;
        _schoolNameContext = schoolNameContext;
        _classes = classes;
        _selectedClassId = preferredClass;
        _date = dateToUse;
        _mode = effectiveInitialMode;
        _attendanceLockTime = lockTime;
        _threeStepSaveMode = threeStepMode;
        _directEntryEnabled = directEntryEnabled;
        _loading = false;
      });
      if (preferredClass != null) {
        await prefs.setString(classPrefKey, preferredClass);
        await prefs.setString(modePrefKey, effectiveInitialMode);
        await prefs.setBool('psm.attendance.$schoolRef.direct_enabled', directEntryEnabled);
        await _loadClassDate();
      } else {
        setState(() => _statusMessage = 'No active or assigned classes are available for this account. Ask the School Admin to create or assign a class.');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _cleanError(error);
        _loading = false;
      });
    }
  }

  String _cleanError(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('PostgrestException(message: ', 'Database error: ');

  Future<void> _loadClassDate() async {
    final schoolRef = _schoolRef;
    final classId = _selectedClassId;
    if (schoolRef == null || classId == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _statusMessage = null;
      _validationMessage = null;
      _isHoliday = false;
      _holidayReason = '';
      _holidayCheckFailed = true;
    });
    try {
      // Resolve the school's holiday first. If it cannot be checked, fail closed
      // so an app/network error never silently allows attendance on a holiday.
      final holidayRow = await _client
          .from('school_holidays')
          .select('reason')
          .eq('school_ref', schoolRef)
          .eq('holiday_date', _date)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _isHoliday = holidayRow != null;
        _holidayReason = _text(holidayRow?['reason']);
        _holidayCheckFailed = false;
      });

      final studentRows = await _client
          .from('students')
          .select('id,class_id,roll_number,gr,name,father_name,mobile,category,gender,is_active,leaving_date')
          .eq('school_ref', schoolRef)
          .eq('class_id', classId)
          .eq('is_active', true)
          .order('roll_number');
      final students = studentRows
          .map((row) => Map<String, dynamic>.from(row))
          .where((row) {
            final leaving = _text(row['leaving_date']);
            if (leaving.length >= 10 &&
                leaving.substring(0, 10).compareTo(_date) <= 0) {
              return false;
            }
            return true;
          })
          .map(_AttendanceStudent.new)
          .toList();
      // roll_number is stored as text. Sort numerically and ensure continuous 1..N roll numbers
      students.sort((a, b) {
        final ar = int.tryParse(_text(a.raw['roll_number']));
        final br = int.tryParse(_text(b.raw['roll_number']));
        if (ar != null && br != null) return ar.compareTo(br);
        if (ar != null) return -1;
        if (br != null) return 1;
        return _text(a.raw['roll_number']).compareTo(_text(b.raw['roll_number']));
      });
      for (var i = 0; i < students.length; i++) {
        students[i].raw['roll_number'] = '${i + 1}';
      }

      FirestoreQueryBuilder.invalidateCache('school_settings');
      final latestSettingsRow = await _client
          .from('school_settings')
          .select('config')
          .eq('school_ref', schoolRef)
          .maybeSingle();
      final latestSettingsConfig = _asMap(latestSettingsRow?['config']);
      final latestThreeStepMode =
          latestSettingsConfig['three_step_attendance_save_mode'] == true;
      final latestDirectEntryEnabled =
          latestSettingsConfig['direct_attendance_entry_enabled'] != false;

      final rawDay = await _client
          .from('attendance_days')
          .select('id,attendance_mode,gender_breakdown,breakfast_total,is_frozen,unfrozen_by_admin,present_saved,mdm_saved,breakfast_saved,present_frozen,mdm_frozen,breakfast_frozen')
          .eq('school_ref', schoolRef)
          .eq('class_id', classId)
          .eq('attendance_date', _date)
          .maybeSingle();

      final Map<String, dynamic>? day = rawDay == null
          ? null
          : Map<String, dynamic>.from(rawDay);
      final String? dayId = day == null ? null : '${day['id']}';
      final Map<String, Map<String, dynamic>> marksByStudent =
          <String, Map<String, dynamic>>{};
      if (dayId != null && day?['attendance_mode'] != 'direct') {
        final markRows = await _client
            .from('student_attendance')
            .select('student_id,present,mdm,breakfast')
            .eq('school_ref', schoolRef)
            .eq('class_id', classId)
            .eq('attendance_day_id', dayId);
        for (final row in markRows) {
          final mark = Map<String, dynamic>.from(row);
          marksByStudent['${mark['student_id']}'] = mark;
        }
      }

      if (!mounted) return;
      _threeStepSaveMode = latestThreeStepMode;
      _directEntryEnabled = latestDirectEntryEnabled;
      _day = day;

      for (final student in students) {
        final mark = marksByStudent['${student.raw['id']}'];
        if (day == null || day['attendance_mode'] == 'direct') {
          student.present = _canEditPresent; // New editable entries default to Present; read-only/locked dates are not pre-marked.
          student.mdm = false;
          student.breakfast = false;
        } else {
          student.present = mark?['present'] == true;
          student.mdm = mark?['mdm'] == true;
          student.breakfast = mark?['breakfast'] == true;
        }
      }

      setState(() {
        _students = students;
        // Preserve the device's saved Student/Direct Entry preference for a
        // date with no saved attendance. A saved day remains authoritative.
        final rawEffectiveMode = day == null
            ? _mode
            : (day['attendance_mode'] ?? 'student').toString();
        _mode = (!_directEntryEnabled)
            ? 'student'
            : (rawEffectiveMode == 'direct' ? 'direct' : 'student');
        _loading = false;
      });
      _loadDirectControllers(day);
      if (students.isEmpty) {
        setState(() => _statusMessage = 'No active students found in this class. Add students before marking attendance.');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _cleanError(error);
        _loading = false;
      });
    }
  }

  void _loadDirectControllers(Map<String, dynamic>? day) {
    final saved = _asMap(day?['gender_breakdown']);
    var savedCategoryBreakfast = 0;
    for (final gender in _allGenders) {
      for (final category in _categories) {
        final catMap = _asMap(_asMap(saved[gender])[category]);
        savedCategoryBreakfast += _valueInt(catMap['breakfast']);
      }
    }
    final savedTotalBreakfast = _valueInt(day?['breakfast_total']);
    final savedAsTotal = day != null &&
        day['attendance_mode'] == 'direct' &&
        savedTotalBreakfast > 0 &&
        savedCategoryBreakfast == 0;
    _breakfastTotalController.text = savedAsTotal ? '$savedTotalBreakfast' : '';
    for (final gender in _allGenders) {
      for (final category in _categories) {
        for (final metric in _metrics) {
          final controller = _controllerFor(gender, category, metric);
          final catMap = _asMap(_asMap(saved[gender])[category]);
          final value = catMap[metric];
          controller.text = (day != null && day['attendance_mode'] == 'direct' && value != null)
              ? '${_valueInt(value)}'
              : '';
        }
      }
    }
    if (mounted) {
      setState(() {
        _breakfastEntryMode = savedAsTotal ? 'total' : 'category';
        _validationMessage = null;
      });
    }
  }

  int _valueInt(dynamic value) => _int(value);

  Future<void> _chooseDate() async {
    final parts = _date.split('-').map((p) => int.tryParse(p) ?? 1).toList();
    final current = DateTime(parts[0], parts[1], parts[2]);
    final chosen = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2018),
      lastDate: _indiaNow(),
    );
    if (chosen == null || !mounted) return;
    final dateValue = '${chosen.year.toString().padLeft(4, '0')}-${chosen.month.toString().padLeft(2, '0')}-${chosen.day.toString().padLeft(2, '0')}';
    if (dateValue.compareTo(_indiaToday()) > 0) {
      setState(() => _error = 'Future-date attendance is not allowed.');
      return;
    }
    setState(() {
      _date = dateValue;
      _error = null;
      _adminOverrideAuthorized = false;
      _adminOverrideForIndiaDay = '';
    });
    await _loadClassDate();
  }

  Future<bool> _requestAdminAttendanceAuthorization() async {
    if (!_isAdmin || !_dateNeedsAdminPassword) return true;
    if (_adminOverrideIsCurrent) return true;

    // A prior successful authorization is stored server-side until the end of
    // the India calendar day. Check that record first so refresh/reopen does
    // not force the Admin to enter the password again for the same date.
    try {
      final checkResponse = await _client.functions.invoke(
        'psm-attendance-admin-override',
        body: <String, dynamic>{
          'action': 'check',
          'attendanceDate': _date,
        },
      );
      final checkData = checkResponse.data is Map
          ? Map<String, dynamic>.from(
              (checkResponse.data as Map).map((key, value) => MapEntry('$key', value)),
            )
          : <String, dynamic>{};
      if (checkResponse.status < 200 ||
          checkResponse.status >= 300 ||
          checkData['error'] != null) {
        throw StateError(
          '${checkData['error'] ?? checkData['message'] ?? 'Could not check Admin attendance authorization.'}',
        );
      }
      if (checkData['authorized'] == true) {
        if (!mounted) return false;
        setState(() {
          _adminOverrideAuthorized = true;
          _adminOverrideForIndiaDay = _indiaToday();
          _error = null;
        });
        return true;
      }
    } catch (error) {
      if (mounted) setState(() => _error = _cleanError(error));
      return false;
    }

    final passwordController = TextEditingController();
    String? dialogError;
    bool submitting = false;

    if (!mounted) return false;
    final authorized = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> verify() async {
            final password = passwordController.text;
            if (password.isEmpty) {
              setDialogState(() => dialogError = 'Enter the Admin login password.');
              return;
            }
            setDialogState(() {
              submitting = true;
              dialogError = null;
            });
            try {
              final response = await _client.functions.invoke(
                'psm-attendance-admin-override',
                body: <String, dynamic>{
                  'action': 'authorize',
                  'attendanceDate': _date,
                  'password': password,
                },
              );
              final data = response.data is Map
                  ? Map<String, dynamic>.from(
                      (response.data as Map).map((key, value) => MapEntry('$key', value)),
                    )
                  : <String, dynamic>{};
              if (response.status < 200 ||
                  response.status >= 300 ||
                  data['error'] != null ||
                  data['authorized'] != true) {
                throw StateError(
                  '${data['error'] ?? data['message'] ?? 'Admin password verification failed.'}',
                );
              }
              if (!mounted) return;
              setState(() {
                _adminOverrideAuthorized = true;
                _adminOverrideForIndiaDay = _indiaToday();
                _error = null;
              });
              if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
            } catch (error) {
              setDialogState(() {
                submitting = false;
                dialogError = _cleanError(error);
              });
            }
          }

          return AlertDialog(
            title: const Text('Admin authorization required'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isNonSchoolDay
                      ? 'Sunday / school holiday attendance can be recorded only by the School Admin after entering the Admin login password.'
                      : 'Attendance for a previous date can be changed only by the School Admin after entering the Admin login password.',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  autofocus: true,
                  enabled: !submitting,
                  onSubmitted: (_) => verify(),
                  decoration: const InputDecoration(
                    labelText: 'Admin login password',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 10),
                  Text(dialogError!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: submitting ? null : verify,
                icon: submitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.lock_open),
                label: Text(submitting ? 'Checking…' : 'Authorize'),
              ),
            ],
          );
        },
      ),
    );
    passwordController.dispose();
    return authorized == true;
  }

  Map<String, int> _emptyCounts() => <String, int>{for (final category in _categories) category: 0};

  Map<String, Map<String, dynamic>> _emptyGenderBreakdown() {
    final out = <String, Map<String, dynamic>>{};
    for (final gender in _allGenders) {
      final groups = <String, dynamic>{};
      for (final category in _categories) {
        groups[category] = <String, int>{
          'registered': 0,
          'present': 0,
          'mdm': 0,
          'breakfast': 0,
        };
      }
      groups['_OVERALL'] = <String, int>{
        'registered': 0,
        'present': 0,
        'mdm': 0,
        'breakfast': 0,
      };
      out[gender] = groups;
    }
    return out;
  }

  void _increment(Map<String, dynamic> group, String metric) {
    group[metric] = _int(group[metric]) + 1;
  }

  Map<String, dynamic> _studentGenderBreakdown() {
    final result = _emptyGenderBreakdown();
    for (final student in _students) {
      final gender = _gender(student.raw['gender']);
      final category = _category(student.raw['category']);
      final byCategory = _asMap(result[gender]);
      final group = _asMap(byCategory[category]);
      final overall = _asMap(byCategory['_OVERALL']);
      _increment(group, 'registered');
      _increment(overall, 'registered');
      if (student.present) {
        _increment(group, 'present');
        _increment(overall, 'present');
      }
      if (student.present && student.mdm) {
        _increment(group, 'mdm');
        _increment(overall, 'mdm');
      }
      if (student.present && student.breakfast) {
        _increment(group, 'breakfast');
        _increment(overall, 'breakfast');
      }
      byCategory[category] = group;
      byCategory['_OVERALL'] = overall;
      result[gender] = byCategory;
    }
    return result;
  }

  Map<String, dynamic> _directGenderBreakdown() {
    final result = _emptyGenderBreakdown();
    for (final student in _students) {
      final gender = _gender(student.raw['gender']);
      final category = _category(student.raw['category']);
      final byCategory = _asMap(result[gender]);
      final group = _asMap(byCategory[category]);
      _increment(group, 'registered');
      byCategory[category] = group;
      result[gender] = byCategory;
    }

    for (final gender in _allGenders) {
      final byCategory = _asMap(result[gender]);
      final overall = _asMap(byCategory['_OVERALL']);
      var registeredTotal = 0;
      var presentTotal = 0;
      var mdmTotal = 0;
      var breakfastTotal = 0;
      for (final category in _categories) {
        final group = _asMap(byCategory[category]);
        registeredTotal += _int(group['registered']);
        final activeInEntry = _entryGenders.contains(gender);
        final present = activeInEntry ? _directCount(gender, category, 'present') : 0;
        final mdm = activeInEntry ? _directCount(gender, category, 'mdm') : 0;
        final breakfast = activeInEntry && _breakfastEntryMode == 'category'
            ? _directCount(gender, category, 'breakfast')
            : 0;
        group['present'] = present;
        group['mdm'] = mdm;
        group['breakfast'] = breakfast;
        presentTotal += present;
        mdmTotal += mdm;
        breakfastTotal += breakfast;
        byCategory[category] = group;
      }
      overall['registered'] = registeredTotal;
      overall['present'] = presentTotal;
      overall['mdm'] = mdmTotal;
      overall['breakfast'] = breakfastTotal;
      byCategory['_OVERALL'] = overall;
      result[gender] = byCategory;
    }

    // In whole-class-total mode, keep breakfast_total in its dedicated column.
    // Do not fabricate a caste/gender breakdown for that aggregate value.
    return result;
  }

  int _directCount(String gender, String category, String metric) =>
      _int(_controllerFor(gender, category, metric).text);

  Map<String, int> _registeredCounts() {
    final counts = _emptyCounts();
    for (final student in _students) {
      final category = _category(student.raw['category']);
      counts[category] = _int(counts[category]) + 1;
    }
    return counts;
  }

  Map<String, int> _directCounts(String metric) {
    final counts = _emptyCounts();
    for (final gender in _entryGenders) {
      for (final category in _categories) {
        counts[category] = _int(counts[category]) +
            ((metric == 'breakfast' && _breakfastEntryMode == 'total')
                ? 0
                : _directCount(gender, category, metric));
      }
    }
    return counts;
  }

  int _directPresentTotal() => _directCounts('present').values.fold<int>(0, (sum, n) => sum + n);

  int _directBreakfastTotal() {
    if (_breakfastEntryMode == 'total') return _int(_breakfastTotalController.text);
    var total = 0;
    for (final gender in _entryGenders) {
      for (final category in _categories) {
        total += _directCount(gender, category, 'breakfast');
      }
    }
    return total;
  }

  int _registeredFor(String gender, String category) => _students
      .where((student) => _gender(student.raw['gender']) == gender && _category(student.raw['category']) == category)
      .length;

  int _currentMetricFor(String metric, String gender, String category) {
    if (metric == 'registered') return _registeredFor(gender, category);
    if (_mode == 'direct') {
      if (metric == 'breakfast' && _breakfastEntryMode == 'total') return 0;
      return _directCount(gender, category, metric);
    }
    var total = 0;
    for (final student in _students) {
      if (_gender(student.raw['gender']) != gender || _category(student.raw['category']) != category) continue;
      if (metric == 'present' && student.present) total++;
      if (metric == 'mdm' && student.present && student.mdm) total++;
      if (metric == 'breakfast' && student.present && student.breakfast) total++;
    }
    return total;
  }

  int _currentCategoryTotal(String metric, String category) {
    if (metric == 'breakfast' && _mode == 'direct' && _breakfastEntryMode == 'total') return 0;
    return _entryGenders.fold<int>(0, (sum, gender) => sum + _currentMetricFor(metric, gender, category));
  }

  int _currentOverall(String metric, {String? gender}) {
    if (metric == 'breakfast' && _mode == 'direct' && _breakfastEntryMode == 'total') {
      return gender == null ? _directBreakfastTotal() : 0;
    }
    return _categories.fold<int>(0, (sum, category) =>
        sum + (gender == null
            ? _currentCategoryTotal(metric, category)
            : _currentMetricFor(metric, gender, category)));
  }

  String? _validateDirectEntry({String section = 'all'}) {
    final checkPresent = section == 'all' || section == 'present';
    final checkMdm = section == 'all' || section == 'mdm';
    final checkBreakfast = section == 'all' || section == 'breakfast';
    for (final gender in _entryGenders) {
      for (final category in _categories) {
        final registered = _registeredFor(gender, category);
        final present = _directCount(gender, category, 'present');
        final mdm = _directCount(gender, category, 'mdm');
        final breakfast = _directCount(gender, category, 'breakfast');
        if (present < 0 || mdm < 0 || breakfast < 0) return 'Counts cannot be negative.';
        if (checkPresent && present > registered) {
          return '$gender $category present ($present) exceeds registered ($registered).';
        }
        if (checkMdm && mdm > present) {
          return '$gender $category PM POSHAN ($mdm) cannot exceed present ($present).';
        }
        if (checkBreakfast && _breakfastEntryMode == 'category' && breakfast > present) {
          return '$gender $category breakfast ($breakfast) cannot exceed present ($present).';
        }
      }
    }
    if (checkBreakfast && _breakfastEntryMode == 'total') {
      final totalBreakfast = _directBreakfastTotal();
      final totalPresent = _directPresentTotal();
      if (totalBreakfast < 0) return 'Breakfast total cannot be negative.';
      if (totalBreakfast > totalPresent) {
        return 'Breakfast total ($totalBreakfast) cannot exceed total present ($totalPresent).';
      }
    }
    return null;
  }

  Future<void> _save({String section = 'all'}) async {
    if (_holidayCheckFailed) {
      setState(() => _error = _nonSchoolDayMessage);
      return;
    }
    if (_isFutureDate) {
      setState(() => _error = 'Future-date attendance is not allowed.');
      return;
    }
    if (_threeStepSaveMode &&
        (section == 'mdm' || section == 'breakfast') &&
        !_presentSaved) {
      setState(() {
        _validationMessage =
            'પહેલા "1. હાજર-ગેરહાજર (Present/Absent)" સેવ કરવું ફરજિયાત છે. ત્યારબાદ જ અલ્પાહાર (Breakfast) અથવા PM POSHAN સેવ કરી શકાશે.';
      });
      return;
    }
    final sectionFrozen = switch (section) {
      'present' => _presentFrozen,
      'mdm' => _mdmFrozen,
      'breakfast' => _breakfastFrozen,
      _ => _isAttendanceFrozen,
    };
    if (sectionFrozen) {
      setState(() => _error = _isAdmin
          ? 'આ વિભાગ સબમિટ થઈ ગયો છે અને ફ્રીઝ (Freeze) છે. સુધારો કરવા માટે ઉપર "Unfreeze" બટન દબાવો.'
          : 'આ વિભાગ સબમિટ થઈ ગયો છે અને ફ્રીઝ (Freeze) છે. સુધારો કરવા માટે School Admin પાસેથી Unfreeze કરાવો.');
      return;
    }
    if (!_isAdmin && !_isUnfrozenByAdmin && _isPastDate) {
      setState(() => _error = 'Teachers cannot change attendance for a previous date. Contact the School Admin.');
      return;
    }
    if (!_isAdmin && !_isUnfrozenByAdmin && _isNonSchoolDay) {
      setState(() => _error = _nonSchoolDayMessage);
      return;
    }
    if (!_canEditAttendance) {
      setState(() => _error = !_isAdmin && _isPastDate && !_isUnfrozenByAdmin
          ? 'Previous-date attendance is locked. Ask the School Admin to unfreeze it.'
          : 'This account has view-only access.');
      return;
    }
    if (_isAdmin && _dateNeedsAdminPassword && !_adminOverrideIsCurrent) {
      final authorized = await _requestAdminAttendanceAuthorization();
      if (!authorized || !mounted) return;
    }
    final schoolRef = _schoolRef;
    final classId = _selectedClassId;
    if (schoolRef == null || classId == null || _students.isEmpty) return;
    final validation = _mode == 'direct' ? _validateDirectEntry(section: section) : null;
    if (validation != null) {
      setState(() => _validationMessage = validation);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _validationMessage = null;
      _statusMessage = null;
    });
    try {
      final registered = _registeredCounts();
      final present = _mode == 'direct'
          ? _directCounts('present')
          : _emptyCounts();
      final mdm = _mode == 'direct'
          ? _directCounts('mdm')
          : _emptyCounts();
      var breakfastTotal = 0;
      final Map<String, dynamic> genderBreakdown;
      if (_mode == 'student') {
        for (final student in _students) {
          if (!student.present) {
            student.mdm = false;
            student.breakfast = false;
          }
          final category = _category(student.raw['category']);
          if (student.present) present[category] = _int(present[category]) + 1;
          if (student.present && student.mdm) mdm[category] = _int(mdm[category]) + 1;
          if (student.present && student.breakfast) breakfastTotal++;
        }
        genderBreakdown = _studentGenderBreakdown();
      } else {
        breakfastTotal = _directBreakfastTotal();
        genderBreakdown = _directGenderBreakdown();
      }

      final bool nextPresentSaved =
          section == 'all' || section == 'present' ? true : _presentSaved;
      final bool nextMdmSaved =
          section == 'all' || section == 'mdm' ? true : _mdmSaved;
      final bool nextBreakfastSaved =
          section == 'all' || section == 'breakfast' ? true : _breakfastSaved;

      final bool nextPresentFrozen =
          section == 'all' || section == 'present' ? true : _presentFrozen;
      final bool nextMdmFrozen =
          section == 'all' || section == 'mdm' ? true : _mdmFrozen;
      final bool nextBreakfastFrozen =
          section == 'all' || section == 'breakfast' ? true : _breakfastFrozen;

      final bool allFrozenNow = !_threeStepSaveMode
          ? true
          : (nextPresentFrozen && nextMdmFrozen && nextBreakfastFrozen);

      final updatedBy = _text(widget.profile['teacher_id']);
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final dayPayload = <String, dynamic>{
        'school_ref': schoolRef,
        'class_id': classId,
        'attendance_date': _date,
        'registered_counts': registered,
        'present_counts': present,
        'mdm_counts': mdm,
        'breakfast_total': breakfastTotal,
        'gender_breakdown': genderBreakdown,
        'attendance_mode': _mode,
        'student_details_saved': _mode == 'student',
        'present_saved': nextPresentSaved,
        'mdm_saved': nextMdmSaved,
        'breakfast_saved': nextBreakfastSaved,
        'present_frozen': nextPresentFrozen,
        'mdm_frozen': nextMdmFrozen,
        'breakfast_frozen': nextBreakfastFrozen,
        'is_frozen': _mode != 'student' ? allFrozenNow : false,
        'unfrozen_by_admin': allFrozenNow ? false : _isUnfrozenByAdmin,
        'updated_at': nowIso,
      };
      if (updatedBy.isNotEmpty) dayPayload['updated_by_teacher'] = updatedBy;
      final saved = await _client
          .from('attendance_days')
          .upsert(dayPayload, onConflict: 'school_ref,class_id,attendance_date')
          .select('id')
          .single();
      final dayId = '${saved['id']}';

      if (_mode == 'student') {
        final markRows = _students.map((student) {
          final row = <String, dynamic>{
            'school_ref': schoolRef,
            'class_id': classId,
            'attendance_day_id': dayId,
            'student_id': '${student.raw['id']}',
            'present': student.present,
            'mdm': student.present && student.mdm,
            'breakfast': student.present && student.breakfast,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          };
          if (updatedBy.isNotEmpty) row['updated_by_teacher'] = updatedBy;
          return row;
        }).toList();
        if (markRows.isNotEmpty) {
          await _client.from('student_attendance').upsert(
                markRows,
                onConflict: 'attendance_day_id,student_id',
              );
        }
        await _client
            .from('attendance_days')
            .update(<String, dynamic>{
              'present_saved': nextPresentSaved,
              'mdm_saved': nextMdmSaved,
              'breakfast_saved': nextBreakfastSaved,
              'present_frozen': nextPresentFrozen,
              'mdm_frozen': nextMdmFrozen,
              'breakfast_frozen': nextBreakfastFrozen,
              'is_frozen': allFrozenNow,
              'unfrozen_by_admin': allFrozenNow ? false : _isUnfrozenByAdmin,
              if (allFrozenNow)
                'frozen_at': DateTime.now().toUtc().toIso8601String(),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', dayId)
            .eq('school_ref', schoolRef);
      }

      if (!mounted) return;
      final shouldOfferAbsentWhatsApp =
          (section == 'all' || section == 'present') &&
              _mode == 'student' &&
              _date == _indiaToday() &&
              _students.any((student) => !student.present);
      final savedStepMsg = switch (section) {
        'present' =>
          '1️⃣ હાજર-ગેરહાજર (Present/Absent) સફળતાપૂર્વક સેવ અને ફ્રીઝ થઈ ગઈ છે! હવે આપ અલ્પાહાર (Breakfast) અથવા PM POSHAN સેવ કરી શકો છો.',
        'mdm' =>
          '2️⃣ PM POSHAN (મધ્યાહ્ન ભોજન) સંખ્યા સફળતાપૂર્વક સેવ અને ફ્રીઝ થઈ ગઈ છે!',
        'breakfast' =>
          '3️⃣ અલ્પાહાર (Breakfast) સંખ્યા સફળતાપૂર્વક સેવ અને ફ્રીઝ થઈ ગઈ છે!',
        _ =>
          'હાજરી સફળતાપૂર્વક સેવ અને ફ્રીઝ થઈ ગઈ છે (Attendance saved & frozen for $_date).',
      };
      setState(() {
        _day = <String, dynamic>{
          ...?_day,
          'id': dayId,
          'attendance_mode': _mode,
          'gender_breakdown': genderBreakdown,
          'breakfast_total': breakfastTotal,
          'present_saved': nextPresentSaved,
          'mdm_saved': nextMdmSaved,
          'breakfast_saved': nextBreakfastSaved,
          'present_frozen': nextPresentFrozen,
          'mdm_frozen': nextMdmFrozen,
          'breakfast_frozen': nextBreakfastFrozen,
          'is_frozen': allFrozenNow,
          'unfrozen_by_admin': allFrozenNow ? false : _isUnfrozenByAdmin,
        };
        _statusMessage = savedStepMsg;
        _saving = false;
      });
      if (shouldOfferAbsentWhatsApp && mounted) {
        await _sendWhatsAppToAllAbsent();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeClass(String? value) async {
    if (value == null || value == _selectedClassId) return;
    setState(() {
      _selectedClassId = value;
      _students = <_AttendanceStudent>[];
    });
    final schoolRef = _schoolRef;
    if (schoolRef != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('psm.attendance.$schoolRef.class', value);
    }
    await _loadClassDate();
  }

  Future<void> _changeMode(String mode) async {
    if (!_canEditAttendance || mode == _mode) return;
    if (_day != null && _mode != mode) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Change entry mode?'),
          content: Text(mode == 'direct'
              ? 'Saving Direct Entry will replace any saved student-level attendance for this class/date with summary totals.'
              : 'Student Selection records individual student statuses for this class/date.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Continue')),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }
    setState(() {
      _mode = mode;
      _error = null;
      _statusMessage = null;
      _validationMessage = null;
      if (mode == 'student' && _day?['attendance_mode'] == 'direct') {
        for (final student in _students) {
          student.present = true;
          student.mdm = false;
          student.breakfast = false;
        }
      }
    });
    final schoolRef = _schoolRef;
    if (schoolRef != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('psm.attendance.$schoolRef.mode', mode);
    }
    if (mode == 'direct') {
      _loadDirectControllers(_day);
    }
  }

  Widget _buildModeToggle() {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_directEntryEnabled)
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(
                value: 'student',
                label: Text('Student Selection'),
                icon: Icon(Icons.checklist),
              ),
              ButtonSegment<String>(
                value: 'direct',
                label: Text('Direct Entry'),
                icon: Icon(Icons.numbers),
              ),
            ],
            selected: <String>{_mode},
            onSelectionChanged:
                !_canEditPresent ? null : (values) => _changeMode(values.first),
          )
        else
          Chip(
            avatar: const Icon(Icons.checklist, size: 18),
            label: const Text(
              'વિદ્યાર્થીવાર હાજરી (Student Selection)',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        if (!widget.readOnly && _selectedClassId != null)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            onPressed: _saving ? null : () => _openStudentEditorInAttendance(),
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 17),
            label: const Text(
              '➕ નવો વિદ્યાર્થી ઉમેરો',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
          ),
      ],
    );
  }

  String _categoryGujaratiShort(String cat) => switch (cat) {
        'SC' => 'અ. જા.',
        'ST' => 'અ. જ. જા.',
        'OBC' => 'બક્ષીપંચ',
        _ => 'અન્ય',
      };

  Future<void> _sendSingleAbsentWhatsApp(_AttendanceStudent student) async {
    final number = _normalizeWhatsAppNumber(_text(student.raw['mobile']));
    if (number == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('આ વિદ્યાર્થીનો માન્ય મોબાઈલ નંબર નોંધાયેલ નથી.'),
        ),
      );
      return;
    }
    final msg = _defaultAbsentMessage(student).replaceAll(
      '{student_name}',
      _studentMessageName(student),
    );
    final uri = Uri.https('wa.me', '/$number', <String, String>{'text': msg});
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _refreshStudentsPreservingMarks() async {
    final schoolRef = _schoolRef;
    final classId = _selectedClassId;
    if (schoolRef == null || classId == null) return;
    final prevMarks = <String, (bool, bool, bool)>{
      for (final st in _students)
        _text(st.raw['id']): (st.present, st.mdm, st.breakfast),
    };
    final studentRows = await _client
        .from('students')
        .select('id,class_id,roll_number,gr,name,father_name,mobile,category,gender,is_active,leaving_date')
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .eq('is_active', true)
        .order('roll_number');
    final nextStudents = studentRows
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) {
          final leaving = _text(row['leaving_date']);
          if (leaving.length >= 10 &&
              leaving.substring(0, 10).compareTo(_date) <= 0) {
            return false;
          }
          return true;
        })
        .map(_AttendanceStudent.new)
        .toList();
    nextStudents.sort((a, b) {
      final ar = int.tryParse(_text(a.raw['roll_number']));
      final br = int.tryParse(_text(b.raw['roll_number']));
      if (ar != null && br != null) return ar.compareTo(br);
      if (ar != null) return -1;
      if (br != null) return 1;
      return _text(a.raw['roll_number']).compareTo(_text(b.raw['roll_number']));
    });
    for (var i = 0; i < nextStudents.length; i++) {
      nextStudents[i].raw['roll_number'] = '${i + 1}';
      final sid = _text(nextStudents[i].raw['id']);
      final savedTuple = prevMarks[sid];
      if (savedTuple != null) {
        nextStudents[i].present = savedTuple.$1;
        nextStudents[i].mdm = savedTuple.$2;
        nextStudents[i].breakfast = savedTuple.$3;
      } else {
        nextStudents[i].present = _canEditPresent;
        nextStudents[i].mdm = false;
        nextStudents[i].breakfast = false;
      }
    }
    if (!mounted) return;
    setState(() {
      _students = nextStudents;
    });
  }

  Future<void> _deactivateStudentInAttendance(_AttendanceStudent target) async {
    if (widget.readOnly || _saving) return;
    final classId = _selectedClassId;
    final studentId = _text(target.raw['id']);
    final studentName = _text(target.raw['name']);
    if (classId == null || studentId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Deactive Student? / વિદ્યાર્થીને નિષ્ક્રિય (Deactive) કરો'),
        content: Text(
          'શું તમે ખરેખર "$studentName" ને નિષ્ક્રિય (Deactive) કરવા માંગો છો?\n\n'
          '• માત્ર આ ૧ જ વિદ્યાર્થી Deactive થશે અને રોલ નંબર આપોઆપ ગોઠવાઈ જશે.\n'
          '• બાકીના વિદ્યાર્થીઓની હાજરી પસંદગી યથાવત રહેશે.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel / રદ કરો'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Deactive / નિષ્ક્રિય કરો'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _studentService.archiveStudent(
        classId: classId,
        studentId: studentId,
      );
      await _refreshStudentsPreservingMarks();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '"$studentName" ને નિષ્ક્રિય (Deactive) કરવામાં આવેલ છે. હાજરી સ્ક્રીન પર બાકીના વિદ્યાર્થીઓ અપડેટ થઈ ગયા છે.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = _cleanError(e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openStudentEditorInAttendance([_AttendanceStudent? target]) async {
    if (widget.readOnly || _saving) return;
    final classId = _selectedClassId;
    final schoolRef = _schoolRef;
    if (classId == null || schoolRef == null) return;

    Map<String, dynamic> row = <String, dynamic>{};
    if (target != null) {
      final sid = _text(target.raw['id']);
      try {
        final fullRow = await _client
            .from('students')
            .select()
            .eq('school_ref', schoolRef)
            .eq('id', sid)
            .maybeSingle();
        if (fullRow != null) {
          row = Map<String, dynamic>.from(fullRow);
          final cf = row['custom_fields'];
          if (cf is Map) {
            row.addAll(cf.map((k, v) => MapEntry('$k', v)));
          }
        } else {
          row = Map<String, dynamic>.from(target.raw);
        }
        if (_isAdmin) {
          final priv = await _studentService.getPrivateDetails(sid);
          row.addAll(priv);
        }
      } catch (_) {
        row = Map<String, dynamic>.from(target.raw);
      }
    }

    if (!mounted) return;
    final mixed = _studentService.isMixedSchool(_schoolType);
    final controllers = <String, TextEditingController>{};
    const textKeys = <String>[
      'roll_number',
      'gr',
      'dd',
      'mm',
      'yyyy',
      'name',
      'religion',
      'religion_en',
      'caste',
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
      'apaar_id',
      'present_days',
      'scholarship_reason',
      'uid',
      'pen',
      'bank_name',
      'bank_branch',
      'name_as_passbook',
      'account_number',
      'ifsc_code',
      'native_place',
      'native_place_en',
    ];
    for (final key in textKeys) {
      controllers[key] = TextEditingController(text: '${row[key] ?? ''}');
    }
    var category = _category(row['category']);
    String? gender = _gender(row['gender']);
    String normYesNo(dynamic v) {
      final s = '${v ?? ''}'.trim().toUpperCase();
      if (const <String>{'YES', 'Y', 'TRUE', '1', 'હા'}.contains(s) ||
          s.startsWith('YES') ||
          s.startsWith('હા')) {
        return 'YES';
      }
      return 'NO';
    }
    var hasAadhaar = normYesNo(row['has_aadhaar']);
    var rationCardKyc = normYesNo(row['ration_card_kyc']);
    var scholarshipDone = normYesNo(row['scholarship_done']);
    if (scholarshipDone == 'YES') {
      controllers['scholarship_reason']?.clear();
    }
    var formError = '';

    Widget field(String key, String label, {bool numeric = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: controllers[key],
            keyboardType: numeric ? TextInputType.number : TextInputType.text,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        );

    Widget grid(List<Widget> children) => LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final itemWidth = width < 520 ? width : (width - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 0,
              children: children
                  .map((child) => SizedBox(width: itemWidth, child: child))
                  .toList(),
            );
          },
        );

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            insetPadding: const EdgeInsets.all(14),
            title: Text(
              target == null
                  ? '➕ નવો વિદ્યાર્થી ઉમેરો'
                  : '✏️ વિદ્યાર્થીની વિગત સુધારો (${_text(row['name'])})',
            ),
            content: SizedBox(
              width: 740,
              height: MediaQuery.of(dialogContext).size.height * 0.72,
              child: ListView(
                children: [
                  Text(
                    'વર્ગ: ${_selectedClassLabel()}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  ExpansionTile(
                    initiallyExpanded: true,
                    title: const Text('Basic Details / મૂળભૂત વિગતો'),
                    children: [
                      grid(<Widget>[
                        field('roll_number', 'Roll Number', numeric: true),
                        field('gr', 'GR નંબર'),
                        field('dd', 'DD', numeric: true),
                        field('mm', 'MM', numeric: true),
                        field('yyyy', 'YYYY', numeric: true),
                        field('name', 'વિદ્યાર્થીનું નામ *'),
                        field('religion', 'ધર્મ (Religion in Gujarati)'),
                        field('caste', 'પેટા જ્ઞાતિ'),
                      ]),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: category,
                        decoration: const InputDecoration(
                          labelText: 'કેટેગરી',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem(value: 'SC', child: Text('અ. જા. / SC')),
                          DropdownMenuItem(value: 'ST', child: Text('અ. જ. જા. / ST')),
                          DropdownMenuItem(value: 'OBC', child: Text('બક્ષીપંચ / OBC')),
                          DropdownMenuItem(value: 'OTHER', child: Text('અન્ય / OTHER')),
                        ],
                        onChanged: (value) =>
                            setDialogState(() => category = value ?? 'OTHER'),
                      ),
                      if (mixed) ...[
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: (gender == 'BOYS' || gender == 'GIRLS')
                              ? gender
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'જાતિ / Gender',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem(value: 'BOYS', child: Text('કુમાર / BOYS')),
                            DropdownMenuItem(value: 'GIRLS', child: Text('કન્યા / GIRLS')),
                          ],
                          onChanged: (value) =>
                              setDialogState(() => gender = value),
                        ),
                      ],
                      const SizedBox(height: 10),
                      grid(<Widget>[
                        field('enroll_school', 'શાળામાં દાખલ તારીખ'),
                        field('enroll_class', 'વર્ગમાં દાખલ તારીખ'),
                        field('mobile', 'મોબાઈલ નંબર', numeric: true),
                        field('father_name', 'પિતાનું નામ'),
                        field('mother_name', 'માતાનું નામ'),
                        field('birth_place', 'જન્મ સ્થળ'),
                        field('dob_words', 'જન્મ તારીખ શબ્દોમાં'),
                        field('last_school', 'પૂર્વ શાળાનું નામ'),
                        field('enroll_sch_class', 'શાળામાં દાખલ ધોરણ'),
                        field('enroll_sch_class_words', 'શાળામાં દાખલ ધોરણ શબ્દોમાં'),
                        field('address', 'સરનામું (optional)'),
                      ]),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text('English Details / અંગ્રેજી વિગતો'),
                    children: [
                      grid(<Widget>[
                        field('name_en', 'NAME IN ENGLISH'),
                        field('religion_en', 'RELIGION IN ENGLISH'),
                        field('caste_en', 'CASTE IN ENGLISH'),
                        field('category_en', 'CATEGORY IN ENG'),
                        field('mother_en', "MOTHER'S NAME IN ENGLISH"),
                        field('birth_place_en', 'BIRTH PLACE IN ENGLISH'),
                        field('dob_en', 'DOB IN ENGLISH WORDS'),
                        field('last_school_en', 'LAST SCHOOL IN ENGLISH'),
                        field('enroll_sch_class_en', 'ENROLL CLASS IN ENGLISH'),
                        field('enroll_sch_class_words_en', 'ENROLL CLASS IN ENGLISH WORDS'),
                      ]),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text('IDs / Aadhaar / KYC / Scholarship'),
                    children: [
                      grid(<Widget>[
                        field('apaar_id', 'APAAR ID'),
                        field('present_days', 'હાજર દિવસો (initial data)', numeric: true),
                        field('uid', 'UID નંબર'),
                        field('pen', 'PEN નંબર'),
                        field('native_place', 'વતન'),
                        field('native_place_en', 'વતન (English)'),
                      ]),
                      const SizedBox(height: 6),
                      grid(<Widget>[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: hasAadhaar,
                            decoration: const InputDecoration(
                              labelText: 'આધાર કાર્ડ છે? (Has Student Aadhaar)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const <DropdownMenuItem<String>>[
                              DropdownMenuItem(value: 'YES', child: Text('YES (હા)')),
                              DropdownMenuItem(value: 'NO', child: Text('NO (ના)')),
                            ],
                            onChanged: (value) => setDialogState(() {
                              hasAadhaar = value ?? 'NO';
                            }),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: rationCardKyc,
                            decoration: const InputDecoration(
                              labelText: 'રેશન કાર્ડ KYC (Ration Card KYC)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const <DropdownMenuItem<String>>[
                              DropdownMenuItem(value: 'YES', child: Text('YES (હા)')),
                              DropdownMenuItem(value: 'NO', child: Text('NO (ના)')),
                            ],
                            onChanged: (value) => setDialogState(() {
                              rationCardKyc = value ?? 'NO';
                            }),
                          ),
                        ),
                      ]),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: scholarshipDone,
                        decoration: const InputDecoration(
                          labelText: 'શિષ્યવૃત્તિ થઈ ગઈ છે? (Scholarship Done)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem(value: 'YES', child: Text('YES (હા — શિષ્યવૃત્તિ થયેલ)')),
                          DropdownMenuItem(value: 'NO', child: Text('NO (ના — શિષ્યવૃત્તિ બાકી)')),
                        ],
                        onChanged: (value) => setDialogState(() {
                          scholarshipDone = value ?? 'NO';
                          if (scholarshipDone == 'YES') {
                            controllers['scholarship_reason']!.clear();
                          }
                        }),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
                          controller: controllers['scholarship_reason'],
                          enabled: scholarshipDone == 'NO',
                          readOnly: scholarshipDone == 'YES',
                          decoration: InputDecoration(
                            labelText: scholarshipDone == 'YES'
                                ? 'શિષ્યવૃત્તિ કારણ (Scholarship YES હોવાથી બંધ છે)'
                                : 'શિષ્યવૃત્તિ બાકી હોવાનું કારણ (Reason why Scholarship is NO)',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            filled: scholarshipDone == 'YES',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_isAdmin)
                    ExpansionTile(
                      title: const Text('Bank Details / બેંક વિગતો (Admin only)'),
                      children: [
                        grid(<Widget>[
                          field('bank_name', 'બેંકનું નામ'),
                          field('bank_branch', 'બેંક બ્રાન્ચ'),
                          field('name_as_passbook', 'પાસબુક મુજબ નામ'),
                          field('account_number', 'એકાઉન્ટ નંબર', numeric: true),
                          field('ifsc_code', 'IFSC કોડ'),
                        ]),
                      ],
                    ),
                  if (formError.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        formError,
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('રદ કરો (Cancel)'),
              ),
              FilledButton.icon(
                onPressed: () {
                  if ((controllers['name']?.text ?? '').trim().isEmpty) {
                    setDialogState(() => formError = 'વિદ્યાર્થીનું નામ લખવું ફરજિયાત છે.');
                    return;
                  }
                  if (mixed && !const <String>{'BOYS', 'GIRLS'}.contains(gender)) {
                    setDialogState(() => formError = 'કુમાર (BOYS) અથવા કન્યા (GIRLS) પસંદ કરો.');
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('💾 સેવ કરો (Save & Return to Attendance)'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true && mounted) {
      setState(() {
        _saving = true;
        _error = null;
      });
      try {
        final values = <String, dynamic>{
          for (final entry in controllers.entries)
            entry.key: entry.value.text.trim(),
          'category': category,
          'gender': gender ?? 'UNSPECIFIED',
          'has_aadhaar': hasAadhaar,
          'ration_card_kyc': rationCardKyc,
          'scholarship_done': scholarshipDone,
          'scholarship_reason': scholarshipDone == 'YES'
              ? ''
              : (controllers['scholarship_reason']?.text ?? '').trim(),
        };
        await _studentService.saveStudent(
          classId: classId,
          schoolType: _schoolType,
          values: values,
          studentId: target == null ? null : _text(target.raw['id']),
        );
        await _refreshStudentsPreservingMarks();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                target == null
                    ? '✅ નવો વિદ્યાર્થી ઉમેરાઈ ગયો છે.'
                    : '✅ વિદ્યાર્થીની વિગત સુધારાઈ ગઈ છે (હાજરી પસંદગી યથાવત છે).',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _error = _cleanError(e));
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
    for (final c in controllers.values) {
      c.dispose();
    }
  }

  Widget _attendanceActionTab({
    required String label,
    required bool selected,
    required bool enabled,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6.5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? activeColor : const Color(0xFFF1F5F9),
          border: Border.all(
            color: selected ? activeColor : const Color(0xFFCBD5E1),
            width: 1.25,
          ),
          borderRadius: BorderRadius.circular(7),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: selected
                  ? Colors.white
                  : (enabled ? const Color(0xFF0F172A) : const Color(0xFF94A3B8)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStudentCard(_AttendanceStudent student, int index) {
    final name = _text(student.raw['name']);
    final roll = _text(student.raw['roll_number']);
    final category = _category(student.raw['category']);
    final catShort = _categoryGujaratiShort(category);
    final gender = _gender(student.raw['gender']);
    final genderText = gender == 'BOYS'
        ? 'Boys'
        : gender == 'GIRLS'
            ? 'Girls'
            : 'Other';
    final mobile = _text(student.raw['mobile']);
    final absent = !student.present;

    Widget rollBadge() => Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: absent ? const Color(0xFFFFE4E6) : const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            roll.isEmpty ? '${index + 1}' : roll,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
        );

    Widget nameAndMeta() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 1.5),
            Text(
              '$catShort • $genderText${mobile.isEmpty ? '' : '  •  📱 $mobile'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475569),
              ),
            ),
          ],
        );

    Widget editBtn() => IconButton(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          tooltip: 'વિદ્યાર્થીની વિગત સુધારો (Edit Student)',
          onPressed: (!widget.readOnly && !_saving)
              ? () => _openStudentEditorInAttendance(student)
              : null,
          icon: Icon(
            Icons.edit,
            size: 18,
            color: (!widget.readOnly && !_saving)
                ? const Color(0xFF0D9488)
                : const Color(0xFFCBD5E1),
          ),
        );

    Widget delBtn() => IconButton(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          tooltip: 'નિષ્ક્રિય કરો (Deactive Student)',
          onPressed: (!widget.readOnly && !_saving)
              ? () => _deactivateStudentInAttendance(student)
              : null,
          icon: Icon(
            Icons.delete,
            size: 18,
            color: (!widget.readOnly && !_saving)
                ? const Color(0xFFE11D48)
                : const Color(0xFFCBD5E1),
          ),
        );

    Widget whatsAppBtn() => IconButton(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.only(left: 4),
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          tooltip: 'WhatsApp',
          onPressed: (absent && !_saving && mobile.isNotEmpty)
              ? () => _sendSingleAbsentWhatsApp(student)
              : null,
          icon: Icon(
            Icons.chat,
            size: 19,
            color: (absent && !_saving && mobile.isNotEmpty)
                ? const Color(0xFF15803D)
                : const Color(0xFFCBD5E1),
          ),
        );

    List<Widget> buildTabs({required bool expandEach}) {
      final tabs = <Widget>[
        _attendanceActionTab(
          label: '✅ Present',
          selected: student.present,
          enabled: _canEditPresent && !_saving,
          activeColor: const Color(0xFF15803D),
          onTap: () => setState(() {
            student.present = true;
          }),
        ),
        _attendanceActionTab(
          label: '❌ Absent',
          selected: !student.present,
          enabled: _canEditPresent && !_saving,
          activeColor: const Color(0xFFE11D48),
          onTap: () {
            if (student.present) _markAbsent(student);
          },
        ),
        _attendanceActionTab(
          label: '🍽️ PM Poshan',
          selected: student.present && student.mdm,
          enabled: _canEditMdm && student.present && !_saving,
          activeColor: const Color(0xFFD97706),
          onTap: () => setState(() => student.mdm = !student.mdm),
        ),
        _attendanceActionTab(
          label: '🥐 Breakfast',
          selected: student.present && student.breakfast,
          enabled: _canEditBreakfast && student.present && !_saving,
          activeColor: const Color(0xFF0D9488),
          onTap: () => setState(() => student.breakfast = !student.breakfast),
        ),
      ];
      if (!expandEach) return tabs;
      return <Widget>[
        for (int i = 0; i < tabs.length; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(child: tabs[i]),
        ],
      ];
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: absent
              ? const Color(0xFFE11D48).withValues(alpha: 0.30)
              : const Color(0xFFCBD5E1),
          width: 1.35,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 620;
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                rollBadge(),
                const SizedBox(width: 10),
                Expanded(child: nameAndMeta()),
                const SizedBox(width: 6),
                editBtn(),
                delBtn(),
                const SizedBox(width: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: buildTabs(expandEach: false),
                ),
                whatsAppBtn(),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  rollBadge(),
                  const SizedBox(width: 8),
                  Expanded(child: nameAndMeta()),
                  editBtn(),
                  delBtn(),
                  whatsAppBtn(),
                ],
              ),
              const SizedBox(height: 6),
              Row(children: buildTabs(expandEach: true)),
            ],
          );
        },
      ),
    );
  }

  void _markAbsent(_AttendanceStudent student) {
    setState(() {
      student.present = false;
      student.mdm = false;
      student.breakfast = false;
    });
  }

  String _studentMessageName(_AttendanceStudent student) {
    final name = _text(student.raw['name']);
    final father = _text(student.raw['father_name']);
    if (name.isEmpty || father.isEmpty || name.toLowerCase().contains(father.toLowerCase())) {
      return name;
    }
    final parts = name.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.length > 1) {
      return <String>[parts.first, father, ...parts.skip(1)].join(' ');
    }
    return '$name $father';
  }

  String _formatAttendanceDate(String isoDate) {
    final parts = isoDate.split('-');
    if (parts.length != 3) return isoDate;
    return '${parts[2]}-${parts[1]}-${parts[0]}';
  }

  String _selectedClassLabel() {
    for (final row in _classes) {
      if ('${row['id']}' == _selectedClassId) {
        return _text(row['label'] ?? row['class_key']);
      }
    }
    return '';
  }

  String _defaultAbsentMessage(_AttendanceStudent student) {
  final schoolName = SchoolNameLanguageService.resolveSchoolName(
    language: _schoolNameLanguage,
    profile: widget.profile,
    schoolContext: _schoolNameContext,
    fallbackEnglish: _text(
      widget.profile['school_name_en'] ??
          widget.profile['school_name'] ??
          widget.profile['schoolName'] ??
          'PM SHRI DARED KUMAR SHALA',
    ),
  );

  return 'આજનો આપના બાળકનો હાજરી રિપોર્ટ\n\n'
      'શાળા: $schoolName\n'
      'ધોરણ: ${ClassLabel.bare(_selectedClassLabel())}\n'
      'તારીખ: ${_formatAttendanceDate(_date)}\n'
      'વિદ્યાર્થી: {student_name}\n\n'
      'આજે આપનું સંતાન શાળામાં ગેરહાજર છે. '
      'નિયમિત અભ્યાસ માટે આપના સંતાનને શાળામાં નિયમિત મોકલવા '
      'આપશ્રીને વિનંતી છે.';
}

  String? _normalizeWhatsAppNumber(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.length == 10) return '91$digits';
    if (digits.length == 11 && digits.startsWith('0')) return '91${digits.substring(1)}';
    if (digits.length == 12 && digits.startsWith('91')) return digits;
    if (digits.length >= 11 && digits.length <= 15) return digits;
    return null;
  }

  Future<void> _waitForWhatsAppReturn() async {
    if (!mounted) return;

    _waitingForWhatsAppReturn = true;
    _whatsAppResumeCompleter = Completer<void>();

    try {
      await Future.any<void>([
        _whatsAppResumeCompleter!.future,
        Future<void>.delayed(const Duration(minutes: 5)),
      ]);
    } finally {
      _waitingForWhatsAppReturn = false;

      final completer = _whatsAppResumeCompleter;
      _whatsAppResumeCompleter = null;

      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    }
  }

  Future<void> _sendWhatsAppToAllAbsent() async {
    final absent =
        _students.where((student) => !student.present).toList();

    if (absent.isEmpty || !mounted) {
      return;
    }

    // ------------------------------------------------------------
    // STEP 1:
    // Find students with valid mobile numbers.
    // ------------------------------------------------------------
    final recipients = <_AttendanceStudent>[];
    final skipped = <_AttendanceStudent>[];

    for (final student in absent) {
      final number =
          _normalizeWhatsAppNumber(_text(student.raw['mobile']));

      if (number == null) {
        skipped.add(student);
      } else {
        recipients.add(student);
      }
    }

    if (recipients.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('WhatsApp messages'),
          content: Text(
            'There are ${absent.length} absent student(s), '
            'but none have a valid mobile number.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      return;
    }

    // ------------------------------------------------------------
    // STEP 2:
    // Ask whether the teacher wants to send WhatsApp messages.
    // ------------------------------------------------------------
    final sendWhatsApp = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Attendance saved successfully'),
        content: Text(
          'Attendance has been saved successfully.\n\n'
          'Do you want to send WhatsApp messages to '
          '${recipients.length} absent student(s)?'
          '${skipped.isEmpty ? '' : '\n\n'
              '${skipped.length} absent student(s) will be skipped '
              'because their mobile number is missing or invalid.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('NO'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.chat),
            label: const Text('YES, SEND'),
          ),
        ],
      ),
    );

    if (sendWhatsApp != true || !mounted) {
      return;
    }

    // ------------------------------------------------------------
    // STEP 3:
    // Create ONE common message.
    //
    // {student_name} is automatically replaced for every student.
    // ------------------------------------------------------------
    final firstStudent = recipients.first;

    final messageController = TextEditingController(
      text: _defaultAbsentMessage(firstStudent),
    );

    bool startSending = false;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('WhatsApp message'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 600,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Edit this message once. '
                    'The same message will be used for all absent students.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),

                  const SizedBox(height: 12),

                  const Text(
                    'Use {student_name} where you want the student '
                    'name to appear.',
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: messageController,
                    minLines: 8,
                    maxLines: 14,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      labelText: 'WhatsApp message',
                      hintText:
                          'Enter the common message for all absent students',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    'Recipients: ${recipients.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (messageController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Message cannot be empty.'),
                    ),
                  );
                  return;
                }

                startSending = true;
                Navigator.pop(dialogContext);
              },
              icon: const Icon(Icons.send),
              label: const Text('START SENDING'),
            ),
          ],
        ),
      );

      if (!startSending || !mounted) {
        return;
      }

      // ------------------------------------------------------------
      // STEP 4:
      // Sequential WhatsApp queue.
      //
      // Open WhatsApp
      //       ↓
      // Teacher taps SEND
      //       ↓
      // Teacher returns to PSM
      //       ↓
      // Next student opens automatically
      // ------------------------------------------------------------
      final commonMessage = messageController.text.trim();

      var openedCount = 0;

      for (var index = 0; index < recipients.length; index++) {
        if (!mounted) return;

        final student = recipients[index];

        final number =
            _normalizeWhatsAppNumber(_text(student.raw['mobile']));

        if (number == null) {
          continue;
        }

        final personalizedMessage = commonMessage.replaceAll(
          '{student_name}',
          _studentMessageName(student),
        );

        final uri = Uri.https(
          'wa.me',
          '/$number',
          <String, String>{
            'text': personalizedMessage,
          },
        );

        // ----------------------------------------------------------
        // Show progress BEFORE leaving the app.
        // ----------------------------------------------------------
        final continueSending = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              'WhatsApp ${index + 1}/${recipients.length}',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _studentMessageName(student),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  'Mobile: ${_text(student.raw['mobile'])}',
                ),

                const SizedBox(height: 14),

                const Text(
                  'WhatsApp will open with the message already filled.',
                ),

                const SizedBox(height: 8),

                const Text(
                  'Tap SEND in WhatsApp. '
                  'When you return to this app, the next student '
                  'will open automatically.',
                ),

                const SizedBox(height: 14),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .outline,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    personalizedMessage,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext, false);
                },
                child: const Text('STOP'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext, true);
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('OPEN WHATSAPP'),
              ),
            ],
          ),
        );

        if (continueSending != true || !mounted) {
          break;
        }

        // ----------------------------------------------------------
        // Open WhatsApp and wait until the teacher returns to PSM.
        // _waitForWhatsAppReturn() creates and manages the lifecycle
        // completer.
        // ----------------------------------------------------------

        try {
          final opened = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );

          if (!opened) {
            _waitingForWhatsAppReturn = false;

            final completer = _whatsAppResumeCompleter;
            _whatsAppResumeCompleter = null;

            if (completer != null && !completer.isCompleted) {
              completer.complete();
            }

            if (!mounted) return;

            await showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Could not open WhatsApp'),
                content: const Text(
                  'WhatsApp could not be opened.\n\n'
                  'Please check that WhatsApp is installed or '
                  'available on this device.',
                ),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );

            break;
          }

          openedCount++;

          // --------------------------------------------------------
          // IMPORTANT:
          // Do NOT continue to the next student yet.
          //
          // Wait until the teacher returns to PSM.
          // --------------------------------------------------------
          await _waitForWhatsAppReturn();
        } catch (error) {
          _waitingForWhatsAppReturn = false;

          final completer = _whatsAppResumeCompleter;
          _whatsAppResumeCompleter = null;

          if (completer != null && !completer.isCompleted) {
            completer.complete();
          }

          if (!mounted) return;

          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('WhatsApp error'),
              content: Text(
                'Could not open WhatsApp.\n\n$error',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('OK'),
                ),
              ],
            ),
          );

          break;
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'WhatsApp queue completed. '
            'Opened $openedCount of ${recipients.length} message(s).'
            '${skipped.isEmpty ? '' : ' '
                'Skipped ${skipped.length} student(s) with '
                'invalid/missing mobile numbers.'}',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      messageController.dispose();
    }
  }

  int _maximumFor(String gender, String category, String metric) {
    if (metric == 'present') return _registeredFor(gender, category);
    if (metric == 'mdm' || metric == 'breakfast') return _directCount(gender, category, 'present');
    return 0;
  }

  void _changeDirectValue(String gender, String category, String metric, int value) {
    final maxAllowed = _maximumFor(gender, category, metric);
    final clamped = value.clamp(0, maxAllowed).toInt();
    final ctrl = _controllerFor(gender, category, metric);
    if (ctrl.text != '$clamped') {
      ctrl.value = TextEditingValue(
        text: '$clamped',
        selection: TextSelection.collapsed(offset: '$clamped'.length),
      );
    }
    if (metric == 'present') {
      final mdm = _directCount(gender, category, 'mdm');
      if (mdm > clamped) {
        _controllerFor(gender, category, 'mdm').text = '$clamped';
      }
      if (_breakfastEntryMode == 'category') {
        final breakfast = _directCount(gender, category, 'breakfast');
        if (breakfast > clamped) {
          _controllerFor(gender, category, 'breakfast').text = '$clamped';
        }
      } else {
        final classPresent = _directPresentTotal();
        if (_int(_breakfastTotalController.text) > classPresent) {
          _breakfastTotalController.text = '$classPresent';
        }
      }
    }
    setState(() => _validationMessage = null);
  }

  TextInputFormatter _capFormatter(int maxVal) {
    return TextInputFormatter.withFunction((oldValue, newValue) {
      final raw = newValue.text.trim();
      if (raw.isEmpty) return newValue;
      if (maxVal <= 0) {
        return const TextEditingValue(
          text: '0',
          selection: TextSelection.collapsed(offset: 1),
        );
      }
      final parsed = int.tryParse(raw);
      if (parsed == null) return oldValue;
      if (parsed > maxVal) {
        final capped = '$maxVal';
        return TextEditingValue(
          text: capped,
          selection: TextSelection.collapsed(offset: capped.length),
        );
      }
      final normalized = '$parsed';
      if (normalized != raw) {
        return TextEditingValue(
          text: normalized,
          selection: TextSelection.collapsed(offset: normalized.length),
        );
      }
      return newValue;
    });
  }

  Widget _countField(String gender, String category, String metric, String label) {
    final controller = _controllerFor(gender, category, metric);
    final maximum = _maximumFor(gender, category, metric);
    final current = _int(controller.text);
    final displayValue = current.clamp(0, maximum).toInt();
    final canEditMetric = (metric == 'present'
            ? _canEditPresent
            : metric == 'mdm'
                ? _canEditMdm
                : _canEditBreakfast) &&
        maximum > 0;
    const labelStyle = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600);
    if (_useDropdowns) {
      final dropKey = ValueKey(
        'direct-drop-$gender-$category-$metric-$maximum-$canEditMetric',
      );
      return DropdownButtonFormField<int>(
        key: dropKey,
        initialValue: displayValue,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: labelStyle,
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        ),
        items: List<DropdownMenuItem<int>>.generate(
          maximum + 1,
          (index) => DropdownMenuItem<int>(
            value: index,
            child: Text('$index', style: const TextStyle(fontSize: 13.5)),
          ),
        ),
        onChanged: !canEditMetric
            ? null
            : (value) {
                if (value != null) {
                  _changeDirectValue(gender, category, metric, value);
                }
              },
      );
    }
    final numKey = ValueKey('direct-num-$gender-$category-$metric');
    return TextFormField(
      key: numKey,
      controller: controller,
      readOnly: !canEditMetric,
      enabled: canEditMetric,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
        _capFormatter(maximum),
      ],
      decoration: InputDecoration(
        labelText: '$label (≤$maximum)',
        labelStyle: labelStyle,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
      onChanged: !canEditMetric
          ? null
          : (raw) {
              final parsed = int.tryParse(raw.trim()) ?? 0;
              final clamped = parsed.clamp(0, maximum).toInt();
              if (metric == 'present') {
                final mdm = _directCount(gender, category, 'mdm');
                if (mdm > clamped) {
                  _controllerFor(gender, category, 'mdm').text = '$clamped';
                }
                if (_breakfastEntryMode == 'category') {
                  final bf = _directCount(gender, category, 'breakfast');
                  if (bf > clamped) {
                    _controllerFor(gender, category, 'breakfast').text = '$clamped';
                  }
                } else {
                  final classPresent = _directPresentTotal();
                  if (_int(_breakfastTotalController.text) > classPresent) {
                    _breakfastTotalController.text = '$classPresent';
                  }
                }
              }
              setState(() => _validationMessage = null);
            },
    );
  }

  Widget _breakfastTotalField() {
    final maximum = _directPresentTotal();
    final value = _int(_breakfastTotalController.text).clamp(0, maximum).toInt();
    final canEdit = _canEditBreakfast && maximum > 0;
    if (_useDropdowns) {
      final key = ValueKey(
        'breakfast-total-drop-$_selectedClassId-$_date-$maximum-$canEdit',
      );
      return SizedBox(
        width: 170,
        child: DropdownButtonFormField<int>(
          key: key,
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Breakfast total',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: List<DropdownMenuItem<int>>.generate(
            maximum + 1,
            (index) => DropdownMenuItem<int>(value: index, child: Text('$index')),
          ),
          onChanged: !canEdit
              ? null
              : (v) {
                  if (v == null) return;
                  setState(() {
                    _breakfastTotalController.text = '$v';
                    _validationMessage = null;
                  });
                },
        ),
      );
    }
    final key = ValueKey('breakfast-total-num-$_selectedClassId-$_date');
    return SizedBox(
      width: 190,
      child: TextFormField(
        key: key,
        controller: _breakfastTotalController,
        readOnly: !canEdit,
        enabled: canEdit,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
          _capFormatter(maximum),
        ],
        decoration: InputDecoration(
          labelText: 'Breakfast total (≤$maximum)',
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: !canEdit
            ? null
            : (_) => setState(() => _validationMessage = null),
      ),
    );
  }

  void _clampDirectValuesToDropdowns() {
    for (final gender in _entryGenders) {
      for (final category in _categories) {
        final registered = _registeredFor(gender, category);
        final present = _directCount(gender, category, 'present').clamp(0, registered).toInt();
        _controllerFor(gender, category, 'present').text = '$present';
        final mdm = _directCount(gender, category, 'mdm').clamp(0, present).toInt();
        _controllerFor(gender, category, 'mdm').text = '$mdm';
        if (_breakfastEntryMode == 'category') {
          final breakfast = _directCount(gender, category, 'breakfast').clamp(0, present).toInt();
          _controllerFor(gender, category, 'breakfast').text = '$breakfast';
        }
      }
    }
    if (_breakfastEntryMode == 'total') {
      final totalPresent = _directPresentTotal();
      _breakfastTotalController.text = '${_int(_breakfastTotalController.text).clamp(0, totalPresent).toInt()}';
    }
  }

  Widget _buildDirectEntryToggle() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SegmentedButton<bool>(
        segments: const <ButtonSegment<bool>>[
          ButtonSegment<bool>(value: true, label: Text('Dropdown'), icon: Icon(Icons.arrow_drop_down_circle_outlined)),
          ButtonSegment<bool>(value: false, label: Text('Numeric Entry'), icon: Icon(Icons.keyboard_outlined)),
        ],
        selected: <bool>{_useDropdowns},
        onSelectionChanged: !_canEditAttendance ? null : (values) => setState(() {
          _useDropdowns = values.first;
          _validationMessage = null;
          if (_useDropdowns) _clampDirectValuesToDropdowns();
        }),
      ),
      const SizedBox(height: 10),
      SegmentedButton<String>(
        segments: const <ButtonSegment<String>>[
          ButtonSegment<String>(value: 'category', label: Text('Breakfast by gender/category')),
          ButtonSegment<String>(value: 'total', label: Text('Whole-class breakfast total')),
        ],
        selected: <String>{_breakfastEntryMode},
        onSelectionChanged: !_canEditBreakfast ? null : (values) => setState(() {
          _breakfastEntryMode = values.first;
          _validationMessage = null;
          if (_breakfastEntryMode == 'total' && _breakfastTotalController.text.isEmpty) {
            _breakfastTotalController.text = '${_directBreakfastTotalFromCategories().clamp(0, _directPresentTotal()).toInt()}';
          } else if (_breakfastEntryMode == 'category') {
            _breakfastTotalController.clear();
          }
        }),
      ),
      const SizedBox(height: 6),
      Text(
        _useDropdowns
            ? 'Dropdown limits: Present ≤ Registered • PM POSHAN ≤ Present • Breakfast ≤ Present.'
            : 'Numeric Entry: type the totals directly. The same limits are checked before saving.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );

  int _directBreakfastTotalFromCategories() {
    var total = 0;
    for (final gender in _entryGenders) {
      for (final category in _categories) {
        total += _directCount(gender, category, 'breakfast');
      }
    }
    return total;
  }

  List<String> get _summaryGenders => _entryGenders;

  Widget _buildClassSummary() {
    Map<String, dynamic>? selected;
    for (final row in _classes) {
      if ('${row['id']}' == _selectedClassId) { selected = row; break; }
    }
    final className = selected == null ? '' : '${selected['label'] ?? selected['class_key']}';
    const metrics = <(String, String)>[
      ('registered', 'Reg'),
      ('present', 'Present'),
      ('mdm', 'PM POSHAN'),
      ('breakfast', 'Breakfast'),
    ];
    final showMetricTotalCol =
        _schoolType == 'mixed' && _summaryGenders.length > 1;
    final columns = <DataColumn>[const DataColumn(label: Text('Category'))];
    for (final metric in metrics) {
      for (final gender in _summaryGenders) {
        columns.add(
          DataColumn(label: Text('${metric.$2} ${_genderShort(gender)}')),
        );
      }
      if (showMetricTotalCol) {
        columns.add(DataColumn(label: Text('${metric.$2} Total')));
      }
    }

    String cellValue(
      String metric,
      String category,
      String? gender, {
      bool grandTotal = false,
    }) {
      if (metric == 'breakfast' &&
          _mode == 'direct' &&
          _breakfastEntryMode == 'total') {
        if (!grandTotal) return '—';
        if (!showMetricTotalCol) return '${_directBreakfastTotal()}';
        return gender == null ? '${_directBreakfastTotal()}' : '—';
      }
      if (grandTotal) {
        return '${_currentOverall(metric, gender: gender)}';
      }
      if (gender != null) return '${_currentMetricFor(metric, gender, category)}';
      return '${_currentCategoryTotal(metric, category)}';
    }

    final rows = <DataRow>[];
    for (final category in _categories) {
      rows.add(DataRow(cells: <DataCell>[
        DataCell(Text(category)),
        for (final metric in metrics) ...[
          for (final gender in _summaryGenders)
            DataCell(Text(cellValue(metric.$1, category, gender))),
          if (showMetricTotalCol)
            DataCell(Text(cellValue(metric.$1, category, null))),
        ],
      ]));
    }
    rows.add(DataRow(
      color: WidgetStatePropertyAll(
        Theme.of(context).colorScheme.secondaryContainer,
      ),
      cells: <DataCell>[
        const DataCell(
          Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        for (final metric in metrics) ...[
          for (final gender in _summaryGenders)
            DataCell(
              Text(
                cellValue(metric.$1, '', gender, grandTotal: true),
                style: TextStyle(
                  fontWeight:
                      showMetricTotalCol ? FontWeight.normal : FontWeight.bold,
                ),
              ),
            ),
          if (showMetricTotalCol)
            DataCell(
              Text(
                cellValue(metric.$1, '', null, grandTotal: true),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ],
    ));

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.summarize_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text('Class Summary • $className • $_date', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
            ]),
            if (_mode == 'direct' && _breakfastEntryMode == 'total')
              const Padding(
                padding: EdgeInsets.only(top: 2, bottom: 2),
                child: Text('Breakfast is entered as one class total, so it is not split into caste/gender rows.', style: TextStyle(fontSize: 10)),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                horizontalMargin: 8,
                columnSpacing: 12,
                headingRowHeight: 30,
                dataRowMinHeight: 26,
                dataRowMaxHeight: 30,
                columns: columns,
                rows: rows,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _genderShort(String gender) => switch (gender) {
        'BOYS' => 'Boys',
        'GIRLS' => 'Girls',
        _ => 'Other',
      };

  Widget _buildDirectEntry() {
    final genders = _entryGenders;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Registered counts come from the active class roster. Enter Present, PM POSHAN and Breakfast for each gender/category, or choose a whole-class Breakfast total. Saving Direct Entry stores class totals, not student-level marks.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        _buildDirectEntryToggle(),
        if (_validationMessage != null) ...[
          const SizedBox(height: 8),
          Text(_validationMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 10),
        for (final gender in genders)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_genderLabel(gender), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final category in _categories)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: LayoutBuilder(
                        builder: (context, rowConstraints) {
                          final hasCatBf = _breakfastEntryMode == 'category';
                          final isCompactMobile =
                              hasCatBf && rowConstraints.maxWidth < 430;
                          if (isCompactMobile) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '$category  •  Reg: ${_registeredFor(gender, category)}',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _countField(
                                        gender,
                                        category,
                                        'present',
                                        'Present',
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: _countField(
                                        gender,
                                        category,
                                        'mdm',
                                        'PM POSHAN',
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: _countField(
                                        gender,
                                        category,
                                        'breakfast',
                                        'Breakfast',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 64,
                                child: Text(
                                  '$category\nReg: ${_registeredFor(gender, category)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _countField(
                                  gender,
                                  category,
                                  'present',
                                  'Present',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _countField(
                                  gender,
                                  category,
                                  'mdm',
                                  'PM POSHAN',
                                ),
                              ),
                              if (hasCatBf) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _countField(
                                    gender,
                                    category,
                                    'breakfast',
                                    'Breakfast',
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (_breakfastEntryMode == 'total') ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _breakfastTotalField(),
                Text('Maximum: total Present ${_directPresentTotal()}', style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Manual total: Present ${_directPresentTotal()} • PM POSHAN ${_directCounts('mdm').values.fold<int>(0, (sum, n) => sum + n)} • Breakfast ${_directBreakfastTotal()}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  String _genderLabel(String gender) => switch (gender) {
        'BOYS' => 'Boys / કુમાર',
        'GIRLS' => 'Girls / કન્યા',
        _ => 'Unspecified gender',
      };

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: _loadInitial, icon: const Icon(Icons.refresh), label: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_classes.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_statusMessage ?? 'તમને હજુ કોઈ વર્ગ ફાળવાયો નથી. School Admin પાસે તમારો વર્ગ (વર્ગ શિક્ષક) સેટ કરાવો — પછી તમારા ધોરણના બધા વિભાગની હાજરી પૂરી શકશો.', textAlign: TextAlign.center)));
    }
    Map<String, dynamic>? selectedClass;
    for (final row in _classes) {
      if ('${row['id']}' == _selectedClassId) {
        selectedClass = row;
        break;
      }
    }
    final headerSection = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SchoolNameLanguageSelector(
            schoolRef: _schoolRef,
            label:
                'School name in absent messages / ગેરહાજરી સંદેશમાં શાળાનું નામ',
            onChanged: (language) =>
                setState(() => _schoolNameLanguage = language),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedClassId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Class',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _classes
                      .map((row) => DropdownMenuItem<String>(
                            value: '${row['id']}',
                            child: Text(
                              '${row['label'] ?? row['class_key']} • ${SchoolClassOrder.labelFor(SchoolClassOrder.groupOf(row))}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: _changeClass,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _chooseDate,
                icon: const Icon(Icons.calendar_month),
                label: Text(_date),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildModeToggle(),
          if (widget.readOnly) ...[
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('View-only access: saving and editing are disabled.'),
            ),
          ] else if (_isFutureDate) ...[
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Future-date attendance is not allowed.',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ] else if (_holidayCheckFailed || _isNonSchoolDay) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _isAdmin
                    ? '${_nonSchoolDayMessage.replaceFirst('હાજરી નોંધાવી શકાતી નથી.', 'હાજરી નોંધાવવા માટે Admin password જરૂરી છે.')} Tap Save to authorize.'
                    : _nonSchoolDayMessage,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ] else if (_isPastDate && _isAdmin) ...[
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Previous-date attendance: Admin password is required before saving. After authorization, further changes today do not require the password again.',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ] else if (_isPastDate && !_isAdmin && !_isUnfrozenByAdmin) ...[
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Teachers cannot change attendance for a previous date unless unfrozen by the School Admin.',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
          if (_day != null) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _isAttendanceFrozen
                    ? Colors.amber.shade50
                    : (_isAnyStepFrozen
                        ? Colors.indigo.shade50
                        : Colors.green.shade50),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isAttendanceFrozen
                      ? Colors.amber.shade700
                      : (_isAnyStepFrozen
                          ? Colors.indigo.shade400
                          : Colors.green.shade700),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isAttendanceFrozen
                                ? Icons.lock
                                : (_isAnyStepFrozen
                                    ? Icons.lock_clock
                                    : Icons.lock_open),
                            size: 18,
                            color: _isAttendanceFrozen
                                ? Colors.amber.shade900
                                : (_isAnyStepFrozen
                                    ? Colors.indigo.shade900
                                    : Colors.green.shade800),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _isAttendanceFrozen
                                  ? (_isAdmin
                                      ? 'આ તારીખની સંપૂર્ણ હાજરી સબમિટ થઈ ગઈ છે અને ફ્રીઝ (Frozen) છે.'
                                      : 'હાજરી સબમિટ થઈ ગઈ છે (Frozen). ફરી સુધારો કરવા માટે Admin પાસેથી Unfreeze કરાવો.')
                                  : (_isAnyStepFrozen
                                      ? 'સેવ કરેલ વિભાગ ફ્રીઝ (Frozen) છે — બાકીના વિભાગ (PM POSHAN / Breakfast) સેવ કરવા માટે ખુલ્લા છે.'
                                      : 'હાજરી અનફ્રીઝ (Unfrozen) છે — શિક્ષક સુધારો કરીને સબમિટ કરી શકે છે.'),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _isAttendanceFrozen
                                    ? Colors.amber.shade900
                                    : (_isAnyStepFrozen
                                        ? Colors.indigo.shade900
                                        : Colors.green.shade900),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_isAdmin && !widget.readOnly)
                        FilledButton.tonalIcon(
                          onPressed: _saving
                              ? null
                              : () => _toggleAttendanceFreeze(
                                    !_isAnyStepFrozen,
                                    section: 'all',
                                  ),
                          icon: Icon(
                            _isAnyStepFrozen ? Icons.lock_open : Icons.lock,
                            size: 18,
                          ),
                          label: Text(
                            _isAnyStepFrozen
                                ? 'Unfreeze All (બધું અનફ્રીઝ)'
                                : 'Freeze All (બધું ફ્રીઝ)',
                          ),
                        ),
                    ],
                  ),
                  if (_threeStepSaveMode || _hasStepFlags) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final item in <(String, String, bool, bool)>[
                          ('present', '1. Present/Absent', _presentSaved, _presentFrozen),
                          ('mdm', '2. PM POSHAN', _mdmSaved, _mdmFrozen),
                          ('breakfast', '3. Breakfast', _breakfastSaved, _breakfastFrozen),
                        ])
                          _isAdmin && !widget.readOnly
                              ? ActionChip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: Icon(
                                    item.$4 ? Icons.lock : Icons.lock_open,
                                    size: 15,
                                    color: item.$4
                                        ? Colors.amber.shade900
                                        : Colors.green.shade800,
                                  ),
                                  backgroundColor: item.$4
                                      ? Colors.amber.shade100
                                      : Colors.white,
                                  label: Text(
                                    '${item.$2}: ${item.$4 ? "Frozen (Unfreeze)" : (item.$3 ? "Saved (Unfrozen)" : "Pending")}',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  onPressed: _saving
                                      ? null
                                      : () => _toggleAttendanceFreeze(
                                            !item.$4,
                                            section: item.$1,
                                          ),
                                )
                              : Chip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: Icon(
                                    item.$4
                                        ? Icons.lock
                                        : (item.$3
                                            ? Icons.check_circle_outline
                                            : Icons.pending_outlined),
                                    size: 15,
                                    color: item.$4
                                        ? Colors.amber.shade900
                                        : Colors.indigo,
                                  ),
                                  label: Text(
                                    '${item.$2}: ${item.$4 ? "Saved & Frozen" : (item.$3 ? "Saved" : " બાકી (Pending)")}',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (_statusMessage != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _statusMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (_validationMessage != null && _mode == 'student') ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _validationMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if (_mode == 'student' &&
              _students.isNotEmpty &&
              (_canEditMdm || _canEditBreakfast)) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (_canEditMdm)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () {
                      final allChecked = _students
                          .where((st) => st.present)
                          .every((st) => st.mdm);
                      setState(() {
                        for (final st in _students) {
                          st.mdm = st.present ? !allChecked : false;
                        }
                      });
                    },
                    icon: const Icon(Icons.restaurant_menu, size: 16),
                    label: Text(
                      _students.where((st) => st.present).every((st) => st.mdm)
                          ? 'PM POSHAN: બધા કાઢો (Clear All)'
                          : 'બધા હાજરને PM POSHAN ટીક કરો',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                if (_canEditBreakfast)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () {
                      final allChecked = _students
                          .where((st) => st.present)
                          .every((st) => st.breakfast);
                      setState(() {
                        for (final st in _students) {
                          st.breakfast = st.present ? !allChecked : false;
                        }
                      });
                    },
                    icon: const Icon(Icons.free_breakfast_outlined, size: 16),
                    label: Text(
                      _students.where((st) => st.present).every((st) => st.breakfast)
                          ? 'અલ્પાહાર: બધા કાઢો (Clear All)'
                          : 'બધા હાજરને અલ્પાહાર (Breakfast) ટીક કરો',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ],
          if (selectedClass != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${selectedClass['label'] ?? selectedClass['class_key']} • ${_students.length} active students',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
          const Divider(height: 12),
        ],
      ),
    );

    return Column(
      children: [
        Expanded(
          child: _students.isEmpty
              ? ListView(
                  children: [
                    headerSection,
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          _statusMessage ?? 'No active students in this class.',
                        ),
                      ),
                    ),
                  ],
                )
              : (!_canEditAttendance && _day == null)
                  ? ListView(
                      children: [
                        headerSection,
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              'No attendance record is saved for this class and date, and entry is currently disabled. Use History or Daily Report to review saved attendance.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    )
                  : _mode == 'direct'
                      ? ListView(
                          padding: const EdgeInsets.only(bottom: 16),
                          children: <Widget>[
                            headerSection,
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: _buildDirectEntry(),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: _buildClassSummary(),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: _students.length + 2,
                          itemBuilder: (context, index) {
                            if (index == 0) return headerSection;
                            final studentIndex = index - 1;
                            if (studentIndex < _students.length) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: _buildStudentCard(
                                  _students[studentIndex],
                                  studentIndex,
                                ),
                              );
                            }
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                              child: _buildClassSummary(),
                            );
                          },
                        ),
        ),
        if (_students.isNotEmpty && _canEditAttendance)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: !_threeStepSaveMode
                  ? SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : () => _save(section: 'all'),
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save),
                        label: Text(
                          _saving ? 'Saving attendance…' : 'Save Attendance',
                        ),
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!_presentSaved)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 4),
                            child: Text(
                              '1️⃣ પહેલા હાજર-ગેરહાજર (Present/Absent) સેવ કરો, ત્યારબાદ અલ્પાહાર અથવા PM POSHAN કોઈપણ ક્રમમાં સેવ કરી શકાશે:',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.indigo,
                              ),
                            ),
                          ),
                        LayoutBuilder(
                          builder: (context, btnConstraints) {
                            final btn1 = FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: _presentFrozen
                                    ? Colors.green.shade700
                                    : null,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10),
                              ),
                              onPressed: (_saving || !_canEditPresent)
                                  ? null
                                  : () => _save(section: 'present'),
                              icon: Icon(
                                _presentFrozen
                                    ? Icons.lock_rounded
                                    : Icons.how_to_reg_rounded,
                                size: 17,
                              ),
                              label: Text(
                                _presentFrozen
                                    ? '1. હાજરી સેવ (Frozen)'
                                    : '1. Save Present / Absent',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                            final btn2 = FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: _mdmFrozen
                                    ? Colors.green.shade700
                                    : Colors.deepOrange.shade700,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10),
                              ),
                              onPressed: (_saving || !_canEditMdm)
                                  ? null
                                  : () => _save(section: 'mdm'),
                              icon: Icon(
                                _mdmFrozen
                                    ? Icons.lock_rounded
                                    : Icons.restaurant_rounded,
                                size: 17,
                              ),
                              label: Text(
                                _mdmFrozen
                                    ? '2. PM POSHAN (Frozen)'
                                    : '2. Save PM POSHAN',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                            final btn3 = FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: _breakfastFrozen
                                    ? Colors.green.shade700
                                    : Colors.teal.shade700,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10),
                              ),
                              onPressed: (_saving || !_canEditBreakfast)
                                  ? null
                                  : () => _save(section: 'breakfast'),
                              icon: Icon(
                                _breakfastFrozen
                                    ? Icons.lock_rounded
                                    : Icons.free_breakfast_rounded,
                                size: 17,
                              ),
                              label: Text(
                                _breakfastFrozen
                                    ? '3. Breakfast (Frozen)'
                                    : '3. Save Breakfast',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                            if (btnConstraints.maxWidth < 520) {
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  btn1,
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(child: btn2),
                                      const SizedBox(width: 6),
                                      Expanded(child: btn3),
                                    ],
                                  ),
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(child: btn1),
                                const SizedBox(width: 6),
                                Expanded(child: btn2),
                                const SizedBox(width: 6),
                                Expanded(child: btn3),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar ? AppBar(
        title: const Text('Attendance / હાજરી નોંધણી'),
        actions: [IconButton(tooltip: 'Refresh', onPressed: _loadInitial, icon: const Icon(Icons.refresh))],
      ) : null,
      body: _buildBody(),
    );
  }
}

class _AttendanceStudent {
  _AttendanceStudent(this.raw);

  final Map<String, dynamic> raw;
  bool present = false;
  bool mdm = false;
  bool breakfast = false;
}

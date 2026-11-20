import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import '../services/supabase_leave_pdf_service.dart';
import '../services/school_name_language_service.dart';
import '../widgets/school_name_language_selector.dart';
import 'supabase_leave_report_pdf_screen.dart';
import 'package:pmshri_attendance/services/class_label.dart';

/// Supabase-backed teacher leave requests. RLS keeps teachers to their own
/// requests and lets School Admin see school-wide requests.
class SupabaseTeacherLeaveScreen extends StatefulWidget {
  const SupabaseTeacherLeaveScreen({super.key, required this.profile, this.readOnly = false});

  final Map<String, dynamic> profile;
  final bool readOnly;

  @override
  State<SupabaseTeacherLeaveScreen> createState() => _SupabaseTeacherLeaveScreenState();
}

class _SupabaseTeacherLeaveScreenState extends State<SupabaseTeacherLeaveScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _manualReason = TextEditingController();
  final DateFormat _format = DateFormat('dd/MM/yyyy');

  static const List<String> _reasonOptions = <String>[
    'સામાજિક કારણસર',
    'ધાર્મિક કારણસર',
    'તબિયત ખરાબ હોવાથી',
    'કુટુંબમાં પ્રસંગ હોવાથી',
    'સરકારી / શૈક્ષણિક કામગીરી',
    'વ્યક્તિગત કારણસર',
    'અન્ય (જાતે લખો)',
  ];

  static const List<String> _leaveTypes = <String>[
    'પ્રાસંગિક રજા (CL)',
    'મરજિયાત રજા',
    'વળતર રજા',
    'તબીબી રજા (ML)',
    'અર્ધ પગારી રજા (HPL)',
    'પ્રસુતિ રજા',
    'અન્ય',
  ];

  bool _loading = true;
  bool _saving = false;
  bool _halfDay = false;
  bool _valtarEnabled = false;
  String _halfDayPeriod = 'સવાર';
  String _selectedReason = _reasonOptions.first;
  String? _selectedChargeTeacherId;
  String? _error;
  String? _schoolRef;
  String? _teacherId;
  String _schoolName = 'શાળા';
  Map<String, dynamic> _schoolContext = <String, dynamic>{};
  Map<String, dynamic> _schoolConfig = <String, dynamic>{};
  String _leaveType = _leaveTypes.first;
  DateTime _start = _todayDate();
  DateTime _end = _todayDate();
  List<Map<String, dynamic>> _requests = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _schoolActiveLeaves = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _teacherRoster = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _classRoster = <Map<String, dynamic>>[];
  Map<String, dynamic> _leaveRules = <String, dynamic>{
    'cl_max_days': 12, 'cl_year_start_month': 6, 'cl_year_end_month': 5,
    'marajiyat_max_days': 2, 'marajiyat_year_start_month': 1, 'marajiyat_year_end_month': 12,
    'valtar_max_days': 0, 'valtar_start_month': 1, 'valtar_end_month': 12,
  };
  final Set<String> _selectedIds = <String>{};

  static DateTime _todayDate() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    return DateTime(now.year, now.month, now.day);
  }

  String _iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _text(dynamic value, [String fallback = '']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty || text.toLowerCase() == 'null' ? fallback : text;
  }

  bool get _isAdmin {
    final role = _text(widget.profile['role']).toLowerCase();
    return role == 'admin' || role == 'developer';
  }

  Map<String, dynamic>? _findTeacher(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final row in _teacherRoster) {
      if (_teacherRowId(row) == id) return row;
    }
    return null;
  }

  List<Map<String, dynamic>> _classesForTeacher(String? teacherId) {
    if (teacherId == null || teacherId.isEmpty) return <Map<String, dynamic>>[];
    return _classRoster.where((row) => _text(row['class_teacher_id']) == teacherId &&
        _text(row['is_active'], 'true').toLowerCase() != 'false').toList();
  }

  String _labelForClass(Map<String, dynamic> row) => _text(row['label'], _text(row['class_key'], 'ધોરણ'));

  String _teacherClassesLabel(String? teacherId, [Map<String, dynamic>? teacher]) {
    final mapped = _classesForTeacher(teacherId).map(_labelForClass).toList();
    if (mapped.isNotEmpty) return mapped.join(' / ');

    final allowed = teacher?['allowed_classes'];
    if (allowed is List) {
      final labels = <String>[];
      for (final item in allowed) {
        final name = _text(item);
        if (name.isEmpty) continue;
        Map<String, dynamic>? matched;
        for (final classRow in _classRoster) {
          final tokens = <String>{
            _text(classRow['label']).toLowerCase(),
            _text(classRow['class_key']).toLowerCase(),
            _text(classRow['sheet_name']).toLowerCase(),
          };
          if (tokens.contains(name.toLowerCase())) { matched = classRow; break; }
        }
        final label = matched == null ? name : _labelForClass(matched);
        if (!labels.contains(label)) labels.add(label);
      }
      if (labels.isNotEmpty) return labels.join(' / ');
    }
    return '—';
  }

  String get _teacherName {
    final record = _findTeacher(_teacherId);
    return _teacherRowName(record, _text(
        widget.profile['teacher_name'] ?? widget.profile['name'] ??
        widget.profile['full_name'] ?? widget.profile['display_name'], 'શિક્ષક'));
  }

  String get _teacherClass {
    final mapped = _teacherClassesLabel(_teacherId, _findTeacher(_teacherId));
    if (mapped != '—') return mapped;
    return _text(widget.profile['assigned_class'] ?? widget.profile['assignedClass'] ??
        widget.profile['class_label'] ?? widget.profile['class_name'], '—');
  }

  Map<String, dynamic>? get _selectedChargeTeacher => _findTeacher(_selectedChargeTeacherId);
  String get _chargeTeacherName => _teacherRowName(_selectedChargeTeacher, '');
  String get _chargeTeacherClass => _teacherClassesLabel(_selectedChargeTeacherId, _selectedChargeTeacher);

  String get _finalReason => _selectedReason == 'અન્ય (જાતે લખો)'
      ? 'અન્ય: ${_manualReason.text.trim()}'
      : _selectedReason;

  List<Map<String, dynamic>> _rowsFromRpc(dynamic value) {
    dynamic current = value;
    if (current is String) {
      try { current = jsonDecode(current); } catch (_) { return <Map<String, dynamic>>[]; }
    }
    if (current is Map) {
      final map = current.map((key, value) => MapEntry(key.toString(), value));
      if (map.containsKey('id') &&
          (map.containsKey('teacher_name') || map.containsKey('teacherName') || map.containsKey('name'))) {
        return <Map<String, dynamic>>[Map<String, dynamic>.from(map)];
      }
      for (final key in const [
        'teachers', 'classes', 'data', 'result', 'payload', 'rows', 'records',
        'current_school_teacher_roster', 'current_school_class_roster',
        'psm_leave_teacher_roster_v2',
      ]) {
        final candidate = map[key];
        if (candidate is List || candidate is String) {
          final parsed = _rowsFromRpc(candidate);
          if (parsed.isNotEmpty || candidate is List && candidate.isEmpty) return parsed;
        }
      }
      for (final candidate in map.values) {
        if (candidate is List || candidate is String) {
          final parsed = _rowsFromRpc(candidate);
          if (parsed.isNotEmpty) return parsed;
        }
      }
    }
    if (current is! List) return <Map<String, dynamic>>[];
    return current.whereType<Map>().map((row) => row.map((key, value) => MapEntry(key.toString(), value))).toList();
  }

  String _teacherRowId(Map<String, dynamic> row) =>
      _text(row['id'] ?? row['teacher_id'] ?? row['teacherId']);

  String _teacherRowName(Map<String, dynamic>? row, [String fallback = 'શિક્ષક']) =>
      _text(row?['teacher_name'] ?? row?['teacherName'] ?? row?['name'] ?? row?['full_name'], fallback);

  List<Map<String, dynamic>> get _overlappingSchoolLeaves {
    final startIso = _iso(_start);
    final endIso = _iso(_end);
    return _schoolActiveLeaves.where((row) {
      final status = _text(row['status'], 'pending').toLowerCase();
      if (status != 'pending' && status != 'approved') return false;
      final lStart = _text(row['start_date']);
      final lEnd = _text(row['end_date'], lStart);
      if (lStart.isEmpty || lEnd.isEmpty) return false;
      return lStart.compareTo(endIso) <= 0 && lEnd.compareTo(startIso) >= 0;
    }).toList();
  }

  String _resolveLeaveChargeTeacherId(Map<String, dynamic> row) {
    final data = _leaveData(row);
    final cid = _text(row['charge_teacher_id'], _text(data['charge_teacher_id']));
    if (cid.isNotEmpty) return cid;
    final cname = _text(
      row['charge_teacher_name'],
      _text(data['charge_teacher_name']),
    ).toLowerCase();
    if (cname.isEmpty) return '';
    for (final t in _teacherRoster) {
      if (_teacherRowName(t, '').toLowerCase() == cname) {
        return _teacherRowId(t);
      }
    }
    return '';
  }

  /// Returns all teachers whose class charge is held (directly or transitively)
  /// by the current teacher [_teacherId] during the selected [_start.._end] range.
  List<Map<String, dynamic>> get _incomingChargeLeavesForMe {
    final myId = _text(_teacherId);
    if (myId.isEmpty) return const <Map<String, dynamic>>[];
    final overlapping = _overlappingSchoolLeaves;
    final byChargeTid = <String, List<Map<String, dynamic>>>{};
    for (final l in overlapping) {
      final onLeaveTid = _text(l['teacher_id']);
      final chargeTid = _resolveLeaveChargeTeacherId(l);
      if (onLeaveTid.isEmpty || chargeTid.isEmpty || onLeaveTid == chargeTid) {
        continue;
      }
      byChargeTid.putIfAbsent(chargeTid, () => <Map<String, dynamic>>[]).add(l);
    }
    final result = <Map<String, dynamic>>[];
    final visited = <String>{myId};
    final queue = <String>[myId];
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      final incoming = byChargeTid[cur] ?? const <Map<String, dynamic>>[];
      for (final l in incoming) {
        final onLeaveTid = _text(l['teacher_id']);
        if (onLeaveTid.isEmpty || !visited.add(onLeaveTid)) continue;
        result.add(l);
        queue.add(onLeaveTid);
      }
    }
    return result;
  }

  /// Maps teacherId -> reason why that teacher cannot be chosen as In-Charge
  /// during the selected [_start.._end] period (already on leave or gave charge to me).
  Map<String, String> get _unavailableChargeTeacherReasons {
    final reasons = <String, String>{};
    final incomingIds = <String>{
      for (final l in _incomingChargeLeavesForMe) _text(l['teacher_id']),
    };
    for (final l in _overlappingSchoolLeaves) {
      final tid = _text(l['teacher_id']);
      if (tid.isEmpty || tid == _teacherId) continue;
      if (incomingIds.contains(tid)) {
        reasons[tid] = 'આ તારીખે રજા પર છે અને તેમનો ચાર્જ તમારી પાસે છે';
      } else {
        reasons[tid] =
            'આ તારીખે રજા પર છે (${_text(l['start_date'])} થી ${_text(l['end_date'])})';
      }
    }
    return reasons;
  }

  List<Map<String, dynamic>> get _chargeTeacherOptions {
    final unavailable = _unavailableChargeTeacherReasons;
    final eligible = _teacherRoster.where((row) {
      final id = _teacherRowId(row);
      final role = _text(row['role']).toLowerCase();
      final active = _text(row['is_active'] ?? row['active'], 'true').toLowerCase();
      return id.isNotEmpty &&
          _teacherRowName(row, '').isNotEmpty &&
          !const ['admin', 'developer'].contains(role) &&
          !const ['false', '0', 'inactive', 'blocked'].contains(active);
    }).toList();
    final otherTeachers = eligible
        .where(
          (row) =>
              _teacherRowId(row) != _teacherId &&
              !unavailable.containsKey(_teacherRowId(row)),
        )
        .toList();
    return otherTeachers;
  }

  bool get _isCl => _leaveType.toLowerCase() == 'cl' || _leaveType.toLowerCase().contains('(cl)') || _leaveType.contains('પ્રાસંગિક');

  List<String> get _availableLeaveTypes => _valtarEnabled
      ? _leaveTypes
      : _leaveTypes.where((type) => type != 'વળતર રજા').toList();

  int get _calendarDays => _end.difference(_start).inDays + 1;

  double get _totalDays => (_isCl && _halfDay) ? _calendarDays - 0.5 : _calendarDays.toDouble();

  bool get _isMarajiyat => _leaveType.toLowerCase().contains('મરજિયાત') || _leaveType.toLowerCase().contains('marajiyat');
  bool get _isValtar => _leaveType.toLowerCase().contains('વળતર') || _leaveType.toLowerCase().contains('valtar');

  int _ruleInt(String key, int fallback) => _leaveRules[key] is int ? _leaveRules[key] as int : int.tryParse('${_leaveRules[key]}') ?? fallback;
  double _ruleDouble(String key, double fallback) => _leaveRules[key] is num ? (_leaveRules[key] as num).toDouble() : double.tryParse('${_leaveRules[key]}') ?? fallback;

  DateTime _periodStart(DateTime date, int startMonth) => DateTime(date.month < startMonth ? date.year - 1 : date.year, startMonth, 1);

  bool _monthInWindow(int month, int start, int end) => start <= end ? month >= start && month <= end : month >= start || month <= end;

  double _rowDays(Map<String, dynamic> row) {
    final data = _leaveData(row);
    final parsed = double.tryParse('${data['total_days'] ?? ''}');
    if (parsed != null && parsed > 0) return parsed;
    final start = DateTime.tryParse(_text(row['start_date']));
    final end = DateTime.tryParse(_text(row['end_date']));
    return start == null || end == null || end.isBefore(start) ? 0 : end.difference(start).inDays + 1;
  }

  String? _leaveLimitError(double requestedDays) {
    final nowStart = _start;
    String category;
    int startMonth;
    int endMonth;
    double cap;
    if (_isCl) {
      category = 'cl'; startMonth = _ruleInt('cl_year_start_month', 6); endMonth = _ruleInt('cl_year_end_month', 5); cap = _ruleDouble('cl_max_days', 12);
    } else if (_isMarajiyat) {
      category = 'marajiyat'; startMonth = _ruleInt('marajiyat_year_start_month', 1); endMonth = _ruleInt('marajiyat_year_end_month', 12); cap = _ruleDouble('marajiyat_max_days', 2);
    } else if (_isValtar) {
      category = 'valtar'; startMonth = _ruleInt('valtar_start_month', 1); endMonth = _ruleInt('valtar_end_month', 12); cap = _ruleDouble('valtar_max_days', 0);
      if (cap <= 0) return 'Admin એ વળતર રજા માટે વાર્ષિક મહત્તમ દિવસોની મર્યાદા સેટ કરી નથી.';
      var cursor = DateTime(_start.year, _start.month, 1);
      final end = DateTime(_end.year, _end.month, 1);
      while (!cursor.isAfter(end)) {
        if (!_monthInWindow(cursor.month, startMonth, endMonth)) return 'વળતર રજા માટે મંજૂર મહિના ${_monthName(startMonth)} થી ${_monthName(endMonth)} છે.';
        cursor = DateTime(cursor.year, cursor.month + 1, 1);
      }
    } else {
      return null;
    }
    if (_periodStart(_end, startMonth) != _periodStart(nowStart, startMonth)) {
      return 'એક રજા અરજી એક જ વાર્ષિક સમયગાળામાં હોવી જોઈએ. વર્ષ બદલાતું હોય તો અલગ અરજી કરો.';
    }
    final period = _periodStart(nowStart, startMonth);
    double used = 0;
    for (final row in _requests) {
      final status = _text(row['status']).toLowerCase();
      if (!const <String>{'pending', 'approved'}.contains(status) || _text(row['teacher_id']) != _teacherId) continue;
      final type = _text(row['leave_type']).toLowerCase();
      final matches = category == 'cl'
          ? (type.contains('(cl)') || type == 'cl' || type.contains('પ્રાસંગિક'))
          : category == 'marajiyat'
              ? (type.contains('મરજિયાત') || type.contains('marajiyat'))
              : (type.contains('વળતર') || type.contains('valtar'));
      if (!matches) continue;
      final rowStart = DateTime.tryParse(_text(row['start_date']));
      if (rowStart == null || _periodStart(rowStart, startMonth) != period) continue;
      used += _rowDays(row);
    }
    if (used + requestedDays > cap) {
      return 'આ સમયગાળામાં $category રજાની મર્યાદા $cap દિવસ છે. હાલની પેન્ડિંગ/મંજૂર નોંધો $used દિવસ છે; નવી અરજી મંજૂર નહીં થાય.';
    }
    return null;
  }

  String _monthName(int month) => const <String>['જાન્યુઆરી', 'ફેબ્રુઆરી', 'માર્ચ', 'એપ્રિલ', 'મે', 'જૂન', 'જુલાઈ', 'ઑગસ્ટ', 'સપ્ટેમ્બર', 'ઑક્ટોબર', 'નવેમ્બર', 'ડિસેમ્બર'][month - 1];

  String _daysLabel(double days) => days == days.roundToDouble() ? days.toInt().toString() : days.toStringAsFixed(1);

  Map<String, dynamic> _leaveData(Map<String, dynamic> row) {
    final value = row['leave_data'];
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  String _statusLabel(dynamic status) => switch (_text(status).toLowerCase()) {
        'approved' => 'મંજૂર',
        'rejected' => 'નામંજૂર',
        'cancelled' => 'રદ',
        _ => 'મંજૂરી બાકી',
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _manualReason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      if (_client.auth.currentUser == null) throw StateError('ફરી login કરો.');
      final school = _text(await _client.rpc('current_school_ref'));
      final teacher = _text(await _client.rpc('current_teacher_id'));
      if (school.isEmpty || teacher.isEmpty) throw StateError('સક્રિય શાળા/શિક્ષક login મળ્યું નથી.');
      var valtarEnabled = false;
      try {
        final valtarRule = await _client.rpc('psm_leave_my_valtar_rule');
        if (valtarRule is Map) {
          final enabledValue = valtarRule['enabled'];
          valtarEnabled = enabledValue == true || const <String>{'true', 't', '1'}.contains('$enabledValue'.toLowerCase());
        }
      } catch (_) {
        // Fail closed until the teacher-specific setting RPC is installed.
        valtarEnabled = false;
      }
      // These school-scoped RPCs expose only the same school's active teacher
      // names/classes; direct access to private school_teachers remains blocked.
      List<Map<String, dynamic>> roster = <Map<String, dynamic>>[];
      try { roster = _rowsFromRpc(await _client.rpc('psm_leave_teacher_roster_v2')); } catch (_) {}
      if (roster.isEmpty) {
        try { roster = _rowsFromRpc(await _client.rpc('current_school_teacher_roster')); } catch (_) {}
      }
      final classes = _rowsFromRpc(await _client.rpc('current_school_class_roster'));
      final raw = await _client
          .from('teacher_leaves')
          .select('id,school_ref,teacher_id,start_date,end_date,leave_type,reason,status,decision_note,leave_data,record_source,recorded_by,created_at,updated_at')
          .eq('school_ref', school)
          .order('start_date', ascending: false);
      List<Map<String, dynamic>> schoolActiveLeaves = <Map<String, dynamic>>[];
      try {
        schoolActiveLeaves = _rowsFromRpc(
          await _client.rpc('psm_school_active_leave_charges'),
        );
      } catch (_) {}
      Map<String, dynamic> rules = Map<String, dynamic>.from(_leaveRules);
      try {
        final ruleRow = await _client.from('school_leave_settings').select(
          'cl_max_days,cl_year_start_month,cl_year_end_month,marajiyat_max_days,marajiyat_year_start_month,marajiyat_year_end_month,valtar_max_days,valtar_start_month,valtar_end_month'
        ).eq('school_ref', school).maybeSingle();
        if (ruleRow != null) rules = <String, dynamic>{...rules, ...Map<String, dynamic>.from(ruleRow)};
      } catch (_) {
        // Older school deployments can still open the form; the server trigger is authoritative after migration.
      }
      Map<String, dynamic> schoolContext = <String, dynamic>{};
      Map<String, dynamic> schoolConfig = <String, dynamic>{};
      try {
        final value = await _client.rpc('psm_library_school_context');
        if (value is Map) schoolContext = Map<String, dynamic>.from(value);
      } catch (_) {
        // Legacy projects may not expose the school-context RPC yet.
      }
      try {
        final setting = await _client.from('school_settings').select('config').eq('school_ref', school).maybeSingle();
        final configValue = setting?['config'];
        if (configValue is Map) schoolConfig = Map<String, dynamic>.from(configValue);
      } catch (_) {
        // Registered school context remains the primary source.
      }
      final schoolNameLanguage = await SchoolNameLanguageService.loadLanguage(schoolRef: school);
      final schoolName = SchoolNameLanguageService.resolveSchoolName(
        language: schoolNameLanguage,
        profile: widget.profile,
        schoolContext: schoolContext,
        schoolConfig: schoolConfig,
        fallbackEnglish: _text(widget.profile['school_name_en'] ?? widget.profile['school_name'] ?? widget.profile['schoolName']),
      );
      if (!mounted) return;
      setState(() {
        _schoolRef = school;
        _teacherId = teacher;
        _schoolContext = schoolContext;
        _schoolConfig = schoolConfig;
        _schoolName = schoolName;
        _valtarEnabled = valtarEnabled;
        if (!valtarEnabled && _leaveType == 'વળતર રજા') _leaveType = _leaveTypes.first;
        _teacherRoster = roster;
        _classRoster = classes;
        _leaveRules = rules;
        _requests = raw.map((row) => Map<String, dynamic>.from(row)).toList();
        _schoolActiveLeaves = schoolActiveLeaves.isNotEmpty
            ? schoolActiveLeaves
            : _requests;
        if (!_chargeTeacherOptions.any(
          (row) => _teacherRowId(row) == _selectedChargeTeacherId,
        )) {
          _selectedChargeTeacherId = null;
        }
        _selectedIds.removeWhere((id) => !_requests.any((row) => _text(row['id']) == id));
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { _error = _cleanError(error); _loading = false; });
    }
  }

  String _cleanError(Object error) => '$error'.replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '');

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: isStart ? 'રજાની શરૂઆતની તારીખ' : 'રજાની અંતિમ તારીખ',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _start = picked;
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = picked;
        if (_end.isBefore(_start)) _start = _end;
      }
      if (!_chargeTeacherOptions.any(
        (row) => _teacherRowId(row) == _selectedChargeTeacherId,
      )) {
        _selectedChargeTeacherId = null;
      }
    });
  }

  Future<void> _submit({bool printAfterSubmit = false}) async {
    final school = _schoolRef;
    final teacher = _teacherId;
    if (widget.readOnly || _isAdmin || school == null || teacher == null) return;
    if (_end.isBefore(_start)) {
      setState(() => _error = 'રજાની અંતિમ તારીખ શરૂઆતની તારીખથી પહેલાં ન હોઈ શકે.');
      return;
    }
    if (_selectedChargeTeacherId == null || _chargeTeacherName.isEmpty) {
      setState(() => _error = 'કૃપા કરીને ચાર્જ શિક્ષક પસંદ કરો.');
      return;
    }
    if (_selectedReason == 'અન્ય (જાતે લખો)' && _manualReason.text.trim().isEmpty) {
      setState(() => _error = 'કૃપા કરીને રજાનું કારણ જાતે લખો.');
      return;
    }
    if (_calendarDays < 1 || (_isCl && _halfDay && _totalDays < 0.5)) {
      setState(() => _error = 'રજાના દિવસોની સંખ્યા યોગ્ય નથી.');
      return;
    }
    if (_requests.any((row) => _text(row['teacher_id']) == teacher && _text(row['status']).toLowerCase() == 'pending' && _text(row['record_source'], 'teacher_application') == 'teacher_application')) {
      setState(() => _error = 'તમારી અગાઉની રજા અરજી મંજૂર અથવા નામંજૂર થાય પછી જ નવી અરજી કરી શકશો.');
      return;
    }
    final limitError = _leaveLimitError(_totalDays);
    if (limitError != null) {
      setState(() => _error = limitError);
      return;
    }
    // Fractional leave is deliberately supported only for CL. Other leave
    // types always save a whole-calendar-day count.
    final double savedDays = _isCl && _halfDay ? _calendarDays - 0.5 : _calendarDays.toDouble();
    setState(() { _saving = true; _error = null; });
    try {
      final inserted = await _client.from('teacher_leaves').insert(<String, dynamic>{
        'school_ref': school,
        'teacher_id': teacher,
        'start_date': _iso(_start),
        'end_date': _iso(_end),
        'leave_type': _leaveType,
        'reason': _finalReason,
        'status': 'pending',
        'teacher_decision_notified': false,
        'leave_data': <String, dynamic>{
          'teacher_name': _teacherName,
          'teacher_class': _teacherClass,
          'charge_teacher_id': _selectedChargeTeacherId,
          'charge_teacher_name': _chargeTeacherName,
          'charge_teacher_class': _chargeTeacherClass,
          if (_incomingChargeLeavesForMe.isNotEmpty)
            'delegated_from_teacher_ids': _incomingChargeLeavesForMe
                .map((l) => _text(l['teacher_id']))
                .where((s) => s.isNotEmpty)
                .toList(),
          if (_incomingChargeLeavesForMe.isNotEmpty)
            'delegated_from_teacher_names': _incomingChargeLeavesForMe
                .map((l) {
                  final tid = _text(l['teacher_id']);
                  return _text(
                    l['teacher_name'],
                    _teacherRowName(_findTeacher(tid)),
                  );
                })
                .where((s) => s.isNotEmpty)
                .toList(),
          'class_teacher_name': _classesForTeacher(teacher).isNotEmpty ? _teacherName : '',
          'class_teacher_class': _classesForTeacher(teacher).isNotEmpty ? _teacherClass : '',
          'reason_preset': _selectedReason,
          'total_days': savedDays,
          'half_day': _isCl && _halfDay,
          'half_day_period': _isCl && _halfDay ? _halfDayPeriod : '',
          'days_calculation': _isCl && _halfDay ? 'inclusive_range_minus_half_day' : 'inclusive_calendar_days',
          'submitted_from': 'teacher_leave_screen',
        },
      }).select('id,school_ref,teacher_id,start_date,end_date,leave_type,reason,status,decision_note,leave_data,record_source,recorded_by,created_at,updated_at').single();
      final newRow = Map<String, dynamic>.from(inserted);
      _manualReason.clear();
      setState(() {
        _halfDay = false;
        _halfDayPeriod = 'સવાર';
        _selectedReason = _reasonOptions.first;
        _selectedChargeTeacherId = null;
      });
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('રજાની અરજી મંજૂરી માટે મોકલાઈ.')));
      if (printAfterSubmit && mounted) {
        await SupabaseLeavePdfService.printRequests(
          records: <Map<String, dynamic>>[_resolveClassSnapshot(newRow)],
          history: _requests.map(_resolveClassSnapshot).toList(),
          schoolName: _schoolName,
          perPage: 1,
          fileName: 'Leave_Application_${_teacherName.replaceAll(' ', '_')}.pdf',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic> _resolveClassSnapshot(Map<String, dynamic> row) {
    final resolved = Map<String, dynamic>.from(row);
    final data = _leaveData(row);
    final applicantId = _text(row['teacher_id']);
    final applicant = _findTeacher(applicantId);
    final applicantName = _text(applicant?['teacher_name'] ?? applicant?['teacherName']);
    if (applicantName.isNotEmpty) data['teacher_name'] = applicantName;
    final applicantClass = _teacherClassesLabel(applicantId, applicant);
    if (applicantClass != '—' || _classRoster.isNotEmpty) {
      data['teacher_class'] = applicantClass;
    }
    final chargeId = _text(data['charge_teacher_id']);
    if (chargeId.isNotEmpty) {
      final chargeTeacher = _findTeacher(chargeId);
      final chargeName = _text(chargeTeacher?['teacher_name'] ?? chargeTeacher?['teacherName']);
      if (chargeName.isNotEmpty) data['charge_teacher_name'] = chargeName;
      final chargeClass = _teacherClassesLabel(chargeId, chargeTeacher);
      if (chargeClass != '—' || _classRoster.isNotEmpty) {
        data['charge_teacher_class'] = chargeClass;
      }
    }
    resolved['leave_data'] = data;
    return resolved;
  }

  Future<void> _adminDeleteLeaveWithPassword(
    Map<String, dynamic> request,
  ) async {
    final id = _text(request['id']);
    if (!_isAdmin || widget.readOnly || id.isEmpty) return;
    final data = _leaveData(request);
    final teacherName = _text(
      data['teacher_name'],
      _teacherRowName(_findTeacher(_text(request['teacher_id']))),
    );
    final leaveType = _text(request['leave_type'], 'રજા');
    final startDate = _text(request['start_date']);
    final endDate = _text(request['end_date'], startDate);
    final days = _daysLabel(SupabaseLeavePdfService.totalDays(request));
    final statusText = _statusLabel(request['status']);

    final pwdCtrl = TextEditingController();
    var obscure = true;
    var submitting = false;
    String? dialogError;

    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> confirmDelete() async {
            final pwd = pwdCtrl.text.trim();
            if (pwd.isEmpty) {
              setDialogState(
                () => dialogError = 'કૃપા કરીને School Admin પાસવર્ડ દાખલ કરો.',
              );
              return;
            }
            setDialogState(() {
              submitting = true;
              dialogError = null;
            });
            try {
              await _client.rpc(
                'psm_admin_delete_leave_with_password',
                params: <String, dynamic>{
                  'p_leave_id': id,
                  'p_admin_password': pwd,
                },
              );
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop(true);
              }
            } catch (e) {
              setDialogState(() {
                submitting = false;
                dialogError = _cleanError(e);
              });
            }
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('રજા રેકોર્ડ કાયમ માટે કાઢી નાખવો?'),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'શિક્ષક: $teacherName\n'
                      'રજા: $leaveType ($statusText)\n'
                      'તારીખ: $startDate થી $endDate ($days દિવસ)',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Text(
                        '⚠️ મહત્વપૂર્ણ ચેતવણી (Important Warning):\n'
                        '• આ રજા તમામ રેકોર્ડ અને રિપોર્ટમાંથી કાયમ માટે દૂર થશે.\n'
                        '• આ રજા શિક્ષકની વપરાયેલી રજા (Utilised Leave — C.L. / મરજિયાત / વળતર) માંથી પણ બાદ થઈ જશે (એટલે કે વપરાયેલી રજામાં ગણાશે નહીં).\n'
                        '• આ ક્રિયા પાછી ફેરવી શકાશે નહીં.',
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: pwdCtrl,
                      obscureText: obscure,
                      autofocus: true,
                      enabled: !submitting,
                      decoration: InputDecoration(
                        labelText: 'School Admin પાસવર્ડ દાખલ કરો',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        errorText: dialogError,
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setDialogState(() => obscure = !obscure),
                          icon: Icon(
                            obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      onSubmitted: (_) => confirmDelete(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting
                    ? null
                    : () => Navigator.of(dialogContext).pop(false),
                child: const Text('રદ કરો'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: submitting ? null : confirmDelete,
                icon: submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.delete_forever_outlined),
                label: Text(
                  submitting ? 'કાઢી રહ્યું છે…' : 'પાસવર્ડથી રજા કાઢી નાખો',
                ),
              ),
            ],
          );
        },
      ),
    );
    pwdCtrl.dispose();
    if (deleted == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'રજાનો રેકોર્ડ તમામ રજીસ્ટર અને વપરાયેલી રજામાંથી કાયમ માટે કાઢી નાખવામાં આવ્યો છે.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _deletePendingRequest(Map<String, dynamic> request) async {
    final id = _text(request['id']);
    if (_isAdmin || widget.readOnly || id.isEmpty ||
        _text(request['teacher_id']) != _teacherId ||
        _text(request['status']).toLowerCase() != 'pending') return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('રજાની અરજી કાઢી નાખવી?'),
        content: const Text('મંજૂરી અથવા નામંજૂરી ન મળેલી આ અરજી કાઢી નાખવામાં આવશે. આ ક્રિયા પાછી ફેરવી શકાશે નહીં.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('રદ કરો')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('અરજી કાઢી નાખો')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _client.rpc('psm_teacher_delete_pending_leave', params: <String, dynamic>{'p_leave_id': id});
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('મંજૂરી બાકી અરજી કાઢી નાખી.')));
    } catch (error) {
      if (mounted) setState(() => _error = _cleanError(error));
    }
  }

  Future<void> _printRows(List<Map<String, dynamic>> rows, {required int perPage}) async {
    try {
      await SupabaseLeavePdfService.printRequests(
        records: rows.map(_resolveClassSnapshot).toList(),
        history: _requests.map(_resolveClassSnapshot).toList(),
        schoolName: _schoolName,
        perPage: perPage,
        fileName: perPage == 2 ? 'Teacher_Leave_Two_Per_Page.pdf' : 'Teacher_Leave_Applications.pdf',
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF: ${_cleanError(error)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(title: const Text('રજા અરજી અને રિપોર્ટ')), body: const Center(child: CircularProgressIndicator()));
    final visibleRequests = _requests.where((row) => _isAdmin || _text(row['teacher_id']) == _teacherId).toList();
    final selectedRows = visibleRequests.where((row) => _selectedIds.contains(_text(row['id']))).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('રજા અરજી અને રિપોર્ટ'),
        actions: [
          IconButton(
            tooltip: 'Leave PDF report',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SupabaseLeaveReportPdfScreen())),
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
          IconButton(onPressed: _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SchoolNameLanguageSelector(
            schoolRef: (_schoolRef ?? '').isEmpty ? null : _schoolRef,
            label: 'School name on leave forms / રજા અરજીમાં શાળાનું નામ',
            onChanged: (language) {
              setState(() {
                  _schoolName = SchoolNameLanguageService.resolveSchoolName(
                  language: language,
                  profile: widget.profile,
                  schoolContext: _schoolContext,
                  schoolConfig: _schoolConfig,
                  fallbackEnglish: _text(widget.profile['school_name_en'] ?? widget.profile['school_name'] ?? widget.profile['schoolName']),
                );
              });
            },
          ),
          const SizedBox(height: 10),
          if (!widget.readOnly && !_isAdmin) ...[
            Text('નવી રજાની અરજી', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('અરજદાર: $_teacherName   •   ધોરણ: ${ClassLabel.bare(_teacherClass)}', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _leaveType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'રજાનો પ્રકાર', border: OutlineInputBorder()),
              items: _availableLeaveTypes.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _leaveType = value;
                  if (!_isCl) _halfDay = false;
                });
              },
            ),
            if (!_valtarEnabled) ...[
              const SizedBox(height: 5),
              Text('વળતર રજા માટે School Admin દ્વારા Leave Settings માં તમારા નામ સામે checkbox ચાલુ કરાવવો જરૂરી છે.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, children: [
              OutlinedButton.icon(onPressed: () => _pickDate(isStart: true), icon: const Icon(Icons.calendar_month), label: Text('થી: ${_format.format(_start)}')),
              OutlinedButton.icon(onPressed: () => _pickDate(isStart: false), icon: const Icon(Icons.calendar_month), label: Text('સુધી: ${_format.format(_end)}')),
            ]),
            if (_isCl) ...[
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('અડધી C.L. ગણવી (0.5 દિવસ ઘટાડો)'),
                subtitle: const Text('CL માટે જ 0.5, 1.5, 2.5, 3.5, 4.5, 5.5 વગેરે માન્ય છે.'),
                value: _halfDay,
                onChanged: (value) => setState(() => _halfDay = value),
              ),
              if (_halfDay)
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _halfDayPeriod,
                  decoration: const InputDecoration(labelText: 'અડધી C.L. નો સમય', border: OutlineInputBorder()),
                  items: const [DropdownMenuItem(value: 'સવાર', child: Text('સવાર')), DropdownMenuItem(value: 'બપોર', child: Text('બપોર'))],
                  onChanged: (value) { if (value != null) setState(() => _halfDayPeriod = value); },
                ),
            ] else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('મરજિયાત, વળતર અને અન્ય રજાઓ માટે માત્ર પૂર્ણ દિવસ ગણાશે.'),
              ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.event_available_outlined),
                title: Text('કુલ રજાના દિવસો: ${_calendarDays > 0 ? _daysLabel(_totalDays) : '0'}'),
                subtitle: Text(_isCl && _halfDay ? 'સમાવેશક તારીખો: $_calendarDays − 0.5' : 'સમાવેશક કુલ દિવસો: $_calendarDays'),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _selectedReason,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'રજાનું કારણ પસંદ કરો', border: OutlineInputBorder()),
              items: _reasonOptions.map((reason) => DropdownMenuItem<String>(value: reason, child: Text(reason))).toList(),
              onChanged: (value) { if (value != null) setState(() { _selectedReason = value; _error = null; }); },
            ),
            if (_selectedReason == 'અન્ય (જાતે લખો)') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _manualReason,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'રજાનું કારણ જાતે લખો', border: OutlineInputBorder()),
              ),
            ],
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _chargeTeacherOptions.any((row) => _teacherRowId(row) == _selectedChargeTeacherId)
                  ? _selectedChargeTeacherId : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'વર્ગ સંભાળનાર / ચાર્જ શિક્ષક', border: OutlineInputBorder()),
              items: _chargeTeacherOptions.map((row) {
                final id = _teacherRowId(row);
                final name = _teacherRowName(row);
                final assigned = _teacherClassesLabel(id, row);
                final isApplicant = id == _teacherId;
                final label = assigned == '—' ? name : '$name • $assigned';
                return DropdownMenuItem<String>(
                  value: id,
                  child: Text(isApplicant ? '$label (અરજદાર)' : label, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: _chargeTeacherOptions.isEmpty ? null : (value) => setState(() { _selectedChargeTeacherId = value; _error = null; }),
            ),
            if (_incomingChargeLeavesForMe.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF93C5FD)),
                  ),
                  child: Text(
                    '🔗 ચાર્જ ટ્રાન્સફર નોંધ (Chain In-Charge): આ તારીખે તમારી પાસે ${_incomingChargeLeavesForMe.map((l) { final tid = _text(l['teacher_id']); final tName = _text(l['teacher_name'], _teacherRowName(_findTeacher(tid))); final tCls = _teacherClassesLabel(tid, _findTeacher(tid)); return '$tName ($tCls)'; }).join(', ')} નો વર્ગ ચાર્જ છે. તમે રજા પર જઈને જે શિક્ષકને ચાર્જ સોંપશો, તેમને તમારા વર્ગ ($_teacherClass) ઉપરાંત તે વર્ગની હાજરી પૂરવાનો અધિકાર પણ આપોઆપ મળી જશે.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E3A8A),
                    ),
                  ),
                ),
              ),
            if (_unavailableChargeTeacherReasons.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFCD34D)),
                  ),
                  child: Text(
                    '🚫 આ તારીખે રજા પર હોવાથી ચાર્જ આપી શકાશે નહીં: ${_unavailableChargeTeacherReasons.entries.map((e) { final t = _findTeacher(e.key); final name = _teacherRowName(t); final cls = _teacherClassesLabel(e.key, t); return '$name ($cls — ${e.value})'; }).join(' • ')}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF92400E),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            if (_chargeTeacherOptions.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _unavailableChargeTeacherReasons.isNotEmpty
                      ? 'આ તારીખે અન્ય તમામ શિક્ષકો રજા પર હોવાથી ચાર્જ સોંપવા માટે કોઈ શિક્ષક ઉપલબ્ધ નથી.'
                      : 'સક્રિય શિક્ષક યાદી મળી નથી. Admin Setup માં શિક્ષક ખાતાં સક્રિય છે કે નહીં તપાસી રિફ્રેશ કરો.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'ચાર્જ શિક્ષકનું ધોરણ (ઓટોમેટિક)', border: OutlineInputBorder()),
              child: Text(_selectedChargeTeacherId == null ? 'શિક્ષક પસંદ કરો' : _chargeTeacherClass),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              FilledButton.icon(
                onPressed: _saving ? null : () => _submit(),
                icon: const Icon(Icons.send),
                label: Text(_saving ? 'મોકલાઈ રહ્યું છે…' : 'મંજૂરી માટે મોકલો'),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : () => _submit(printAfterSubmit: true),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('મોકલો અને PDF બનાવો'),
              ),
            ]),
            const SizedBox(height: 22),
          ],
          if (widget.readOnly) const Text('શાળા blocked છે. રજા અરજીઓ માત્ર વાંચી શકાય છે.'),
          Text(_isAdmin ? 'શાળાની રજા અરજીઓ' : 'મારી રજા અરજીઓ', style: Theme.of(context).textTheme.titleMedium),
          if (visibleRequests.isNotEmpty && !_isAdmin) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton(onPressed: () => setState(() => _selectedIds.addAll(visibleRequests.map((r) => _text(r['id'])))), child: const Text('બધી પસંદ કરો')),
              OutlinedButton(onPressed: () => setState(_selectedIds.clear), child: const Text('પસંદગી દૂર કરો')),
              FilledButton.tonalIcon(onPressed: selectedRows.isEmpty ? null : () => _printRows(selectedRows, perPage: 1), icon: const Icon(Icons.picture_as_pdf), label: const Text('પસંદ કરેલી PDF')),
              FilledButton.tonalIcon(onPressed: selectedRows.isEmpty ? null : () => _printRows(selectedRows, perPage: 2), icon: const Icon(Icons.view_agenda_outlined), label: const Text('બે અરજી એક પેજ')),
            ]),
          ],
          const SizedBox(height: 8),
          if (visibleRequests.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('હજુ કોઈ રજા અરજી ઉપલબ્ધ નથી.'))),
          for (final request in visibleRequests)
            Card(
              child: CheckboxListTile(
                value: _selectedIds.contains(_text(request['id'])),
                onChanged: (value) => setState(() {
                  final id = _text(request['id']);
                  if (value == true) { _selectedIds.add(id); } else { _selectedIds.remove(id); }
                }),
                controlAffinity: ListTileControlAffinity.leading,
                secondary: IconButton(
                  tooltip: 'PDF બનાવો',
                  onPressed: () => _printRows(<Map<String, dynamic>>[request], perPage: 1),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                ),
                title: Row(
                  children: [
                    Expanded(child: Text('${request['leave_type'] ?? ''} • ${_statusLabel(request['status'])}')),
                    if (_isAdmin && !widget.readOnly)
                      IconButton(
                        tooltip: 'Admin પાસવર્ડથી રજા રેકોર્ડ કાઢી નાખો',
                        onPressed: () => _adminDeleteLeaveWithPassword(request),
                        icon: Icon(
                          Icons.delete_forever_outlined,
                          color: Colors.red.shade700,
                        ),
                      )
                    else if (!_isAdmin && !widget.readOnly && _text(request['status']).toLowerCase() == 'pending')
                      IconButton(
                        tooltip: 'મંજૂરી બાકી અરજી કાઢી નાખો',
                        onPressed: () => _deletePendingRequest(request),
                        icon: const Icon(Icons.delete_outline),
                      ),
                  ],
                ),
                subtitle: Text(
                  '${request['start_date']} થી ${request['end_date']} • ${_daysLabel(SupabaseLeavePdfService.totalDays(request))} દિવસ\n'
                  '${request['reason'] ?? ''}${_text(request['decision_note']).isEmpty ? '' : '\nનોંધ: ${request['decision_note']}'}',
                ),
                isThreeLine: true,
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('રિપોર્ટ રિફ્રેશ કરો')),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:typed_data';
import 'package:excel_community/excel_community.dart' as ec;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, TextInputFormatter;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import '../services/psm_file_export_helper.dart';
import '../services/supabase_hajari_patrak_service.dart';
import '../services/hajari_patrak_xlsx_template_exporter.dart';
import '../services/template_print/school_logo_loader.dart';
import '../services/template_print/template_print_plans.dart';
import '../services/template_print/template_print_service.dart';
import '../services/school_type.dart';

/// Separate monthly Hajari Patrak workflow. It does not read or write the
/// existing DATEWISE/Daily report preferences or report-settings table.
class SupabaseHajariPatrakScreen extends StatefulWidget {
  const SupabaseHajariPatrakScreen({
    super.key,
    required this.profile,
    this.readOnly = false,
  });

  final Map<String, dynamic> profile;
  final bool readOnly;

  @override
  State<SupabaseHajariPatrakScreen> createState() =>
      _SupabaseHajariPatrakScreenState();
}

class _SupabaseHajariPatrakScreenState
    extends State<SupabaseHajariPatrakScreen> {
  final SupabaseHajariPatrakService _service = SupabaseHajariPatrakService();
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _blankRowsController =
      TextEditingController(text: '4');

  List<Map<String, dynamic>> _classes = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _teachers = <Map<String, dynamic>>[];
  Map<String, dynamic> _schoolMeta = <String, dynamic>{};
  String? _schoolRef;
  String _schoolNameLanguage = 'gu';
  String? _classId;
  String? _selectedTeacherId;
  String? _officialTeacherId;
  bool _loading = true;
  bool _generating = false;
  bool _saving = false;
  bool _isAdmin = false;
  String? _error;
  int _month = DateTime.now().month;
  int _year = DateTime.now().year;
  int _rowHeight = 22;
  int _fontSize = 7;
  int _blankRows = 4;
  String? _blankRowsError;
  String _printMode = 'color';
  Timer? _settingsSaveTimer;

  String _text(dynamic value) => (value ?? '').toString().trim();

  /// yyyy-mm-dd holidays declared by the admin for the month.
  Set<String> _holidayDates(Map<String, dynamic> monthData) {
    final out = <String>{};
    final raw = monthData['holidays'];
    if (raw is Iterable) {
      for (final h in raw) {
        final d = h is Map ? _text(h['holiday_date'] ?? h['date']) : _text(h);
        if (d.length >= 10) out.add(d.substring(0, 10));
      }
    }
    return out;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) return value.map((key, value) => MapEntry('$key', value));
    return <String, dynamic>{};
  }

  bool get _canSave => !widget.readOnly && !_loading && !_saving;

  Map<String, dynamic>? get _selectedClass {
    for (final row in _classes) {
      if (_text(row['id']) == _classId) return row;
    }
    return null;
  }

  String get _classLabel {
    final row = _selectedClass;
    return _text(row?['label']).isNotEmpty
        ? _text(row?['label'])
        : _text(row?['class_key']).isNotEmpty
            ? _text(row?['class_key'])
            : _text(row?['sheet_name']);
  }

  String get _schoolNameEnglish {
    final metaEnglish = _text(_schoolMeta['school_name_en']);
    if (metaEnglish.isNotEmpty) return metaEnglish;
    final legacyMetaName = _text(_schoolMeta['school_name']);
    if (legacyMetaName.isNotEmpty) return legacyMetaName;
    final profileEnglish = _text(widget.profile['school_name_en']);
    if (profileEnglish.isNotEmpty) return profileEnglish;
    return _text(widget.profile['school_name']);
  }

  String get _schoolNameGujarati {
    final metaGujarati = _text(_schoolMeta['school_name_gu']);
    if (metaGujarati.isNotEmpty) return metaGujarati;
    return _text(widget.profile['school_name_gu']);
  }

  String get _schoolName =>
      _schoolNameLanguage == 'gu' && _schoolNameGujarati.isNotEmpty
          ? _schoolNameGujarati
          : _schoolNameEnglish.isNotEmpty
              ? _schoolNameEnglish
              : 'School';

  String _schoolNameLanguageKey(String schoolRef) =>
      'hajari_patrak_school_name_language_$schoolRef';

  Future<void> _changeSchoolNameLanguage(String? value) async {
    if (value == null || !const <String>{'gu', 'en'}.contains(value)) return;
    setState(() => _schoolNameLanguage = value);
    final schoolRef = _schoolRef;
    if (schoolRef != null && schoolRef.isNotEmpty) {
      try {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(_schoolNameLanguageKey(schoolRef), value);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'પસંદગી હાલ લાગુ છે, પરંતુ આ browser માં save થઈ શકી નથી.'),
          ));
        }
      }
    }
    if (mounted && value == 'gu' && _schoolNameGujarati.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'આ શાળાનું ગુજરાતી નામ નોંધાયેલું નથી. હાલ English નામ વપરાશે; Developer Panel માં ગુજરાતી નામ ઉમેરો.'),
        duration: Duration(seconds: 6),
      ));
    }
  }

  String get _schoolType => SchoolType.coedCompat(SchoolType.resolve(<dynamic>[
        _schoolMeta['school_type'],
        widget.profile['school_type'],
        widget.profile['schoolType'],
      ]));

  String get _academicYear {
    final configured = _text(_schoolMeta['academic_year']);
    if (configured.isNotEmpty) return configured;
    final startYear = _month >= 6 ? _year : _year - 1;
    return '$startYear - ${(startYear + 1).toString().substring(2)}';
  }

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _settingsSaveTimer?.cancel();
    _blankRowsController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        _service.getClasses(),
        _service.getTeachers(),
        _service.getSchoolMetadata(),
        _service.isCurrentUserAdmin(),
        _service.currentSchoolRef(),
      ]);
      final classes = results[0] as List<Map<String, dynamic>>;
      final teachers = results[1] as List<Map<String, dynamic>>;
      final metadata = results[2] as Map<String, dynamic>;
      final admin = results[3] as bool;
      final schoolRef = _text(results[4]);
      final preferences = await SharedPreferences.getInstance();
      final savedLanguage =
          preferences.getString(_schoolNameLanguageKey(schoolRef)) ?? 'gu';
      if (!mounted) return;
      setState(() {
        _classes = classes;
        _teachers = teachers;
        _schoolMeta = metadata;
        _schoolRef = schoolRef;
        _schoolNameLanguage = savedLanguage == 'en' ? 'en' : 'gu';
        _isAdmin = admin;
        _classId = classes.isEmpty ? null : _text(classes.first['id']);
        _officialTeacherId = classes.isEmpty
            ? null
            : _optionalId(classes.first['class_teacher_id']);
        _selectedTeacherId =
            _defaultTeacher(classes.isEmpty ? null : classes.first, teachers);
        _loading = false;
      });
      if (_classId != null) await _loadClassSettings(_classId!);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _cleanError(error);
        _loading = false;
      });
    }
  }

  String? _optionalId(dynamic value) {
    final text = _text(value);
    return text.isEmpty ? null : text;
  }

  String? _defaultTeacher(
      Map<String, dynamic>? klass, List<Map<String, dynamic>> teachers) {
    final official = _optionalId(klass?['class_teacher_id']);
    if (official != null && teachers.any((row) => _text(row['id']) == official))
      return official;
    final profileTeacher = _text(widget.profile['teacher_id']);
    if (profileTeacher.isNotEmpty &&
        teachers.any((row) => _text(row['id']) == profileTeacher))
      return profileTeacher;
    return teachers.isEmpty ? null : _text(teachers.first['id']);
  }

  Future<void> _loadClassSettings(String id) async {
    try {
      final settings = await _service.getClassSettings(id);
      if (!mounted || _classId != id) return;
      final klass = _selectedClass;
      setState(() {
        _rowHeight = _clampInt(settings['row_height'], 22, 12, 36);
        _fontSize = _clampInt(settings['font_size'], 7, 4, 12);
        _blankRows = _clampInt(settings['blank_rows'], 4, 0, 1997);
        final blankRowsText = _blankRows.toString();
        _blankRowsController.value = TextEditingValue(
          text: blankRowsText,
          selection: TextSelection.collapsed(offset: blankRowsText.length),
        );
        _blankRowsError = null;
        final mode = _text(settings['print_mode']);
        _printMode = mode == 'bw' ? 'bw' : 'color';
        _officialTeacherId = _optionalId(klass?['class_teacher_id']);
        _selectedTeacherId = _defaultTeacher(klass, _teachers);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _cleanError(error));
    }
  }

  int _clampInt(dynamic value, int fallback, int minimum, int maximum) {
    int parsed;
    if (value is num) {
      parsed = value.round();
    } else {
      parsed = int.tryParse(_text(value)) ?? fallback;
    }
    return parsed.clamp(minimum, maximum).toInt();
  }

  void _onBlankRowsChanged(String raw) {
    final trimmed = raw.trim();
    final value = int.tryParse(trimmed);
    if (trimmed.isEmpty) {
      _settingsSaveTimer?.cancel();
      _settingsSaveTimer = null;
      setState(() => _blankRowsError = 'ખાલી લાઇનની સંખ્યા દાખલ કરો.');
      return;
    }
    if (value == null || value < 0) {
      _settingsSaveTimer?.cancel();
      _settingsSaveTimer = null;
      setState(
          () => _blankRowsError = '0 અથવા તેથી મોટી પૂર્ણ સંખ્યા દાખલ કરો.');
      return;
    }
    if (value > 1997) {
      _settingsSaveTimer?.cancel();
      _settingsSaveTimer = null;
      setState(() =>
          _blankRowsError = 'આ template માં મહત્તમ 1997 ખાલી લાઇનની જગ્યા છે.');
      return;
    }
    setState(() {
      _blankRows = value;
      _blankRowsError = null;
      _error = null;
    });
    _scheduleSettingsSave();
  }

  bool _validateBlankRowsInput() {
    final value = int.tryParse(_blankRowsController.text.trim());
    if (value == null || value < 0 || value > 1997) {
      _settingsSaveTimer?.cancel();
      _settingsSaveTimer = null;
      setState(
          () => _blankRowsError = '0 થી 1997 વચ્ચેની પૂર્ણ સંખ્યા દાખલ કરો.');
      return false;
    }
    _blankRows = value;
    _blankRowsError = null;
    return true;
  }

  String _cleanError(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('PostgrestException(message: ', 'Database error: ');

  void _scheduleSettingsSave() {
    if (widget.readOnly || _loading || _classId == null) return;
    _settingsSaveTimer?.cancel();
    final classId = _classId!;
    final rowHeight = _rowHeight;
    final fontSize = _fontSize;
    final blankRows = _blankRows;
    final printMode = _printMode;
    _settingsSaveTimer = Timer(const Duration(milliseconds: 750), () async {
      _settingsSaveTimer = null;
      try {
        await _service.saveClassSettings(
          classId: classId,
          rowHeight: rowHeight,
          fontSize: fontSize,
          blankRows: blankRows,
          printMode: printMode,
        );
      } catch (error) {
        if (mounted && _classId == classId)
          setState(() => _error = _cleanError(error));
      }
    });
  }

  Future<void> _flushScheduledSettingsSave() async {
    final classId = _classId;
    final timer = _settingsSaveTimer;
    if (widget.readOnly || classId == null || timer == null) return;
    timer.cancel();
    _settingsSaveTimer = null;
    try {
      await _service.saveClassSettings(
        classId: classId,
        rowHeight: _rowHeight,
        fontSize: _fontSize,
        blankRows: _blankRows,
        printMode: _printMode,
      );
    } catch (error) {
      if (mounted && _classId == classId)
        setState(() => _error = _cleanError(error));
    }
  }

  Future<void> _saveSettings({bool showMessage = true}) async {
    if (!_canSave || _classId == null || !_validateBlankRowsInput()) return;
    _settingsSaveTimer?.cancel();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.saveClassSettings(
        classId: _classId!,
        rowHeight: _rowHeight,
        fontSize: _fontSize,
        blankRows: _blankRows,
        printMode: _printMode,
      );
      if (showMessage && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Hajari Patrak settings saved for this class.')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveOfficialTeacher() async {
    if (!_canSave || !_isAdmin || _classId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.saveOfficialClassTeacher(
          classId: _classId!, teacherId: _selectedTeacherId);
      final classes = await _service.getClasses();
      if (!mounted) return;
      setState(() {
        _classes = classes;
        _officialTeacherId = _selectedTeacherId;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Official class teacher saved.')));
    } catch (error) {
      if (mounted) setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _safeName(String value) => value
      .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '_');

  Future<Map<String, int?>?> _askAndPreparePresentDays(
      List<Map<String, dynamic>> students) async {
    final shouldAutoFill = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ગત માસ સુધીના હાજર દિવસો'),
        content: const Text('તમારે ગત માસ સુધીના હાજર દિવસો ઓટોમેટિક લખવા છે?'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('રદ કરો')),
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ના, ખાલી રાખો')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('હા, આગળ વધો')),
        ],
      ),
    );
    if (shouldAutoFill == null) return null;
    if (!shouldAutoFill) return <String, int?>{};

    final data = await _service.getAcademicYearPresentDays(
      classId: _classId!,
      year: _year,
      month: _month,
      students: students,
    );
    final academicYearStart = _clampInt(data['academic_year_start'],
        _month >= 6 ? _year : _year - 1, 2000, 2100);
    final throughDate = _text(data['through_date']);
    final rawDays = data['days_by_student_id'];
    final defaults = <String, int?>{};
    if (rawDays is Map) {
      for (final entry in rawDays.entries) {
        final value = entry.value;
        if (value is num)
          defaults['${entry.key}'] = value.toInt();
        else if (value != null)
          defaults['${entry.key}'] = int.tryParse('$value');
      }
    }
    if (data['no_prior_months'] == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'જૂનથી શૈક્ષણિક વર્ષ શરૂ થાય છે, તેથી ગત માસ સુધીના દિવસો અહીં ખાલી રહેશે.'),
        ));
      }
      return <String, int?>{};
    }

    final complete = data['is_complete'] == true;
    var incompleteMonths = <String>[];
    if (data['incomplete_months'] is List) {
      incompleteMonths = (data['incomplete_months'] as List)
          .map((value) => '$value')
          .toSet()
          .toList();
      incompleteMonths.sort();
    }
    final warning = complete
        ? 'જૂનથી ગત માસ સુધીના Student-wise records પરથી ગણતરી થઈ છે. જરૂર હોય તો Days સુધારીને સાચવો.'
        : 'એક અથવા વધુ અગાઉના મહિનામાં Direct Entry અથવા અધૂરા Student-wise records છે${incompleteMonths.isEmpty ? '' : ' (${incompleteMonths.join(', ')})'}. આંકડા હાથના રજીસ્ટરથી અલગ હોઈ શકે છે. પ્રિન્ટ પહેલાં દરેક વિદ્યાર્થીના Days ચકાસો અને સુધારો.';

    if (widget.readOnly) {
      if (!complete && mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('હાજર દિવસોની ગણતરી અધૂરી છે'),
            content: Text(
                '$warning આ સ્કૂલ read-only છે, તેથી અહીં ફેરફાર કરી શકાતો નથી. અજ્ઞાત આંકડા ખાલી રહેશે.'),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('ચાલુ રાખો'))
            ],
          ),
        );
      }
      return defaults;
    }

    final controllers = <TextEditingController>[];
    for (final student in students) {
      final id = _text(student['id']);
      controllers
          .add(TextEditingController(text: defaults[id]?.toString() ?? ''));
    }
    String? validationError;
    Map<String, int?>? edited;
    try {
      if (!mounted) return null;
      edited = await showDialog<Map<String, int?>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final viewport = MediaQuery.sizeOf(context);
            return AlertDialog(
              title: const Text('ગત માસ સુધીના હાજર દિવસો સુધારો'),
              content: SizedBox(
                width: viewport.width < 760 ? viewport.width * 0.78 : 700,
                height: viewport.height * 0.62,
                child: Column(
                  children: <Widget>[
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Text(warning,
                            style: TextStyle(
                                color: complete
                                    ? Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                    : Theme.of(context).colorScheme.error))),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: const <Widget>[
                        SizedBox(
                            width: 76,
                            child: Text('રોલ નંબર',
                                style: TextStyle(fontWeight: FontWeight.bold))),
                        SizedBox(width: 12),
                        Expanded(
                            child: Text('વિદ્યાર્થીનું નામ',
                                style: TextStyle(fontWeight: FontWeight.bold))),
                        SizedBox(
                            width: 112,
                            child: Text('Days',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.bold))),
                      ]),
                    ),
                    const Divider(height: 1),
                    if (validationError != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Align(
                          alignment: Alignment.centerLeft,
                          child: Text(validationError!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    ],
                    Expanded(
                      child: ListView.separated(
                        itemCount: students.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final student = students[index];
                          final roll = _text(student['roll_number']).isEmpty
                              ? '${index + 1}'
                              : _text(student['roll_number']);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(children: <Widget>[
                              SizedBox(width: 76, child: Text(roll)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Text(_text(student['name']),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 102,
                                child: TextField(
                                  controller: controllers[index],
                                  enabled: !widget.readOnly,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: <TextInputFormatter>[
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  textAlign: TextAlign.center,
                                  decoration: const InputDecoration(
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                      hintText: 'ખાલી'),
                                ),
                              ),
                            ]),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(null),
                    child: const Text('રદ કરો')),
                FilledButton.icon(
                  onPressed: widget.readOnly
                      ? null
                      : () {
                          final candidate = <String, int?>{};
                          for (var index = 0;
                              index < students.length;
                              index++) {
                            final id = _text(students[index]['id']);
                            if (id.isEmpty) continue;
                            final raw = controllers[index].text.trim();
                            if (raw.isEmpty) {
                              candidate[id] = null;
                              continue;
                            }
                            final value = int.tryParse(raw);
                            if (value == null || value < 0 || value > 366) {
                              setDialogState(() => validationError =
                                  'દરેક Days 0 થી 366 વચ્ચેની પૂર્ણ સંખ્યા હોવી જોઈએ અથવા ખાલી રાખો.');
                              return;
                            }
                            candidate[id] = value;
                          }
                          Navigator.of(dialogContext).pop(candidate);
                        },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('સાચવો અને આગળ વધો'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      for (final controller in controllers) {
        controller.dispose();
      }
    }
    if (edited == null) return null;

    final rpcValues = <Map<String, dynamic>>[
      for (final student in students)
        if (_text(student['id']).isNotEmpty)
          <String, dynamic>{
            'student_id': _text(student['id']),
            'present_days': edited[_text(student['id'])],
          },
    ];
    await _service.saveAcademicYearPresentDays(
      classId: _classId!,
      academicYearStart: academicYearStart,
      throughDate: throughDate,
      values: rpcValues,
    );
    return edited;
  }

  Future<void> _exportExcel() async {
    if (!_validateBlankRowsInput()) return;
    if (_classId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('કૃપા કરીને ધોરણ પસંદ કરો.')));
      return;
    }
    if (_selectedTeacherId == null ||
        !_teachers.any((row) => _text(row['id']) == _selectedTeacherId)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('કૃપા કરીને વર્ગ શિક્ષક પસંદ કરો.')));
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final monthData = await _service.getMonthData(
          classId: _classId!, year: _year, month: _month);
      final teacher =
          _teachers.firstWhere((row) => _text(row['id']) == _selectedTeacherId);
      final students =
          (monthData['students'] as List).cast<Map<String, dynamic>>();
      final presentDays = await _askAndPreparePresentDays(students);
      if (presentDays == null) return;
      final bytes = await HajariPatrakXlsxTemplateExporter().build(
        schoolName: _schoolName,
        schoolAddress: _text(_schoolMeta['address']),
        schoolType: _schoolType,
        academicYear: _academicYear,
        classLabel: _classLabel,
        teacherName: _text(teacher['teacher_name']),
        year: _year,
        month: _month,
        students: students,
        blankRows: _blankRows,
        presentDaysByStudentId: presentDays,
        holidayIsoDates: _holidayDates(monthData),
      );
      final fileName =
          'HAJARI_PATRAK_${_safeName(_classLabel)}_${_year}_${_month.toString().padLeft(2, '0')}.xlsx';
      await PsmFileExportHelper.saveOrShare(
        bytes: bytes,
        filename: fileName,
        title: 'Hajari Patrak Excel / હાજરીપત્રક',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Excel તૈયાર છે. પ્રિન્ટ સેટિંગ ટેમ્પ્લેટમાંથી જાળવ્યાં છે; હાજરીના ખાના મહિના અંતે હાથથી ભરવા માટે ખાલી છે.'),
      ));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted)
        setState(() {
          _generating = false;
        });
    }
  }

  Uint8List? _logoBytes;
  bool _logoLoaded = false;

  /// Prints the filled Hajari Patrak workbook with the template layout.
  Future<void> _printHajariWorkbook(Uint8List workbookBytes,
      {required String title}) async {
    if (!_logoLoaded) {
      _logoBytes = await loadSchoolLogoBytes(_client, _schoolRef ?? '');
      _logoLoaded = true;
    }
    // Let the progress indicator paint before the workbook is laid out.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final job = TemplatePrintPlans.hajari(
      workbookBytes: workbookBytes,
      schoolType: _schoolType,
      year: _year,
      month: _month,
      rowHeightPx: _rowHeight,
      fontPt: _fontSize,
      logoBytes: _logoBytes,
      title: title,
    );
    if (!mounted) return;
    await TemplatePrintService.printJob(context, job);
  }

  Future<void> _generatePdf() async {
    if (!_validateBlankRowsInput()) return;
    if (_classId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('કૃપા કરીને ધોરણ પસંદ કરો.')));
      return;
    }
    if (_selectedTeacherId == null ||
        !_teachers.any((row) => _text(row['id']) == _selectedTeacherId)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('કૃપા કરીને વર્ગ શિક્ષક પસંદ કરો.')));
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      // Build the same workbook as the Excel export, then print its cover and
      // register pages (browser print, or PDF through Google Apps Script).
      final monthData = await _service.getMonthData(
          classId: _classId!, year: _year, month: _month);
      final teacher =
          _teachers.firstWhere((row) => _text(row['id']) == _selectedTeacherId);
      final students =
          (monthData['students'] as List).cast<Map<String, dynamic>>();
      final presentDays = await _askAndPreparePresentDays(students);
      if (presentDays == null) return;
      final workbookBytes = await HajariPatrakXlsxTemplateExporter().build(
        schoolName: _schoolName,
        schoolAddress: _text(_schoolMeta['address']),
        schoolType: _schoolType,
        academicYear: _academicYear,
        classLabel: _classLabel,
        teacherName: _text(teacher['teacher_name']),
        year: _year,
        month: _month,
        students: students,
        blankRows: _blankRows,
        presentDaysByStudentId: presentDays,
        holidayIsoDates: _holidayDates(monthData),
      );
      await _printHajariWorkbook(workbookBytes,
          title:
              'HAJARI_PATRAK_${_safeName(_classLabel)}_${_year}_${_month.toString().padLeft(2, '0')}');
      if (!widget.readOnly) {
        // Keep per-class blank-row settings and legacy saved preferences in sync.
        await _service.saveClassSettings(
          classId: _classId!,
          rowHeight: _rowHeight,
          fontSize: _fontSize,
          blankRows: _blankRows,
          printMode: _printMode,
        );
      }
      if (!mounted) return;
      final missingDates =
          _clampInt(monthData['missing_enrollment_date_count'], 0, 0, 999999);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(missingDates > 0
            ? 'હાજરીપત્રક ટેમ્પ્લેટમાંથી પ્રિન્ટ માટે તૈયાર છે. નોંધ: $missingDates વિદ્યાર્થીઓની શાળા પ્રવેશ તારીખ વાંચી શકાઈ નથી; જૂના મહિનાની ફરી પ્રિન્ટ માટે તારીખ સુધારો.'
            : 'Hajari Patrak ટેમ્પ્લેટમાંથી પ્રિન્ટ માટે તૈયાર છે.'),
        duration: const Duration(seconds: 6),
      ));
    } catch (error) {
      if (mounted) setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }


  Future<void> _generateRecordedColorHajariPdf({bool asExcel = false}) async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('આ સુવિધા માત્ર School Admin માટે જ છે.')),
      );
      return;
    }
    if (!_validateBlankRowsInput()) return;
    if (_classId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('કૃપા કરીને ધોરણ પસંદ કરો.')),
      );
      return;
    }
    if (_selectedTeacherId == null ||
        !_teachers.any((row) => _text(row['id']) == _selectedTeacherId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('કૃપા કરીને વર્ગ શિક્ષક પસંદ કરો.')),
      );
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final monthData = await _service.getMonthData(
        classId: _classId!,
        year: _year,
        month: _month,
      );
      final teacher = _teachers.firstWhere(
        (row) => _text(row['id']) == _selectedTeacherId,
      );
      final regular =
          (monthData['students'] as List).cast<Map<String, dynamic>>();
      final presentDays = await _askAndPreparePresentDays(regular);
      if (presentDays == null) return;
      // Mid-month joiners follow the regular roster with the next roll numbers.
      final regularIds = regular.map((s) => _text(s['id'])).toSet();
      final joiners = ((monthData['mid_month_joiners'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .where((s) => !regularIds.contains(_text(s['id'])))
          .toList();
      final students = <Map<String, dynamic>>[
        ...regular,
        for (var i = 0; i < joiners.length; i++)
          <String, dynamic>{...joiners[i], 'roll_number': '${regular.length + i + 1}'},
      ];

      final parsedMarks = <String, Map<int, Map<String, bool>>>{};
      final rawMarksMap = monthData['student_daily_marks'];
      if (rawMarksMap is Map) {
        for (final stEntry in rawMarksMap.entries) {
          final sid = '${stEntry.key}'.trim();
          final dMapRaw = stEntry.value;
          if (sid.isEmpty || dMapRaw is! Map) continue;
          final dayMap = <int, Map<String, bool>>{};
          for (final dEntry in dMapRaw.entries) {
            final dayNum = dEntry.key is int
                ? dEntry.key as int
                : int.tryParse('${dEntry.key}');
            final flagsRaw = dEntry.value;
            if (dayNum == null || flagsRaw is! Map) continue;
            dayMap[dayNum] = <String, bool>{
              'present': flagsRaw['present'] == true,
              'mdm': flagsRaw['mdm'] == true,
              'breakfast': flagsRaw['breakfast'] == true,
            };
          }
          parsedMarks[sid] = dayMap;
        }
      }
      final parsedRecordedDays = <int>{};
      final rawRecList = monthData['recorded_days'];
      if (rawRecList is Iterable) {
        for (final item in rawRecList) {
          final d = item is int ? item : int.tryParse('$item');
          if (d != null && d > 0) parsedRecordedDays.add(d);
        }
      }
      final parsedHolidays = <String>{};
      final rawHol = monthData['holidays'];
      if (rawHol is Iterable) {
        for (final h in rawHol) {
          if (h is Map) {
            final d = _text(h['holiday_date'] ?? h['date']);
            if (d.isNotEmpty) parsedHolidays.add(d);
          } else {
            final d = _text(h);
            if (d.isNotEmpty) parsedHolidays.add(d);
          }
        }
      }
      final parsedAttendance = <Map<String, dynamic>>[];
      final rawAtt = monthData['attendance'];
      if (rawAtt is Iterable) {
        for (final a in rawAtt) {
          if (a is Map) parsedAttendance.add(Map<String, dynamic>.from(a));
        }
      }

      // Same Excel template as the blank register (correct Gujarati shaping
      // via the cloud LibreOffice renderer), filled with P/A marks and the
      // daily present / absent / PM POSHAN / breakfast totals at the bottom.
      final workbookBytes = await HajariPatrakXlsxTemplateExporter().build(
        schoolName: _schoolName,
        schoolAddress: _text(_schoolMeta['address']),
        schoolType: _schoolType,
        academicYear: _academicYear,
        classLabel: _classLabel,
        teacherName: _text(teacher['teacher_name']),
        year: _year,
        month: _month,
        students: students,
        blankRows: _blankRows,
        presentDaysByStudentId: presentDays,
        recorded: HajariRecordedData(
          studentDailyMarks: parsedMarks,
          recordedDays: parsedRecordedDays,
          holidayIsoDates: parsedHolidays,
          attendanceDays: parsedAttendance,
        ),
      );
      if (asExcel) {
        await PsmFileExportHelper.saveOrShare(
          bytes: workbookBytes,
          filename:
              'RECORDED_HAJARI_PATRAK_${_safeName(_classLabel)}_${_year}_${_month.toString().padLeft(2, '0')}.xlsx',
          title: 'Recorded Hajari Patrak Excel / ભરેલ હાજરીપત્રક',
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('ભરેલ હાજરીપત્રક Excel (ટેમ્પ્લેટ) તૈયાર છે.'),
          ));
        }
        return;
      }
      final printTitle =
          'RECORDED_HAJARI_PATRAK_${_safeName(_classLabel)}_${_year}_${_month.toString().padLeft(2, '0')}';
      try {
        await _printHajariWorkbook(workbookBytes, title: printTitle);
      } catch (error) {
        // No print service reachable (for example the mobile app without a
        // Google Apps Script URL): build the PDF on this device instead.
        final bytes = await _service.buildMonthlyPdf(
          schoolName: _schoolName,
          schoolAddress: _text(_schoolMeta['address']),
          schoolType: _schoolType,
          academicYear: _academicYear,
          classLabel: _classLabel,
          teacherName: _text(teacher['teacher_name']),
          year: _year,
          month: _month,
          students: students,
          attendance: parsedAttendance,
          holidays: parsedHolidays,
          rowHeightPx: _rowHeight,
          fontSize: _fontSize,
          blankRows: _blankRows < 1 ? 1 : _blankRows,
          colorMode: true,
          presentDaysByStudentId: presentDays,
          fillRecordedAttendance: true,
          studentDailyMarks: parsedMarks,
          recordedDays: parsedRecordedDays,
        );
        await PsmFileExportHelper.saveOrShare(
          bytes: bytes,
          filename: '$printTitle.pdf',
          title: 'Recorded Hajari Patrak / ભરેલ હાજરીપત્રક',
          mimeType: 'application/pdf',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('ટેમ્પ્લેટ પ્રિન્ટ ઉપલબ્ધ નથી ($error) — આ ઉપકરણ પર PDF બનાવી છે.'),
            duration: const Duration(seconds: 7),
          ));
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ભરેલ હાજરીપત્રક પ્રિન્ટ માટે તૈયાર છે — એ જ ટેમ્પ્લેટ, P/A તથા નીચે રોજની હાજર / ગેરહાજર / PM POSHAN / નાસ્તાની સંખ્યા સાથે.',
          ),
          duration: Duration(seconds: 6),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _exportAdminRecordedStudentWiseExcel() async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('આ સુવિધા માત્ર School Admin માટે જ છે.')),
      );
      return;
    }
    if (_classId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('કૃપા કરીને ધોરણ પસંદ કરો.')),
      );
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final monthData = await _service.getMonthData(
        classId: _classId!,
        year: _year,
        month: _month,
      );
      final students =
          (monthData['students'] as List).cast<Map<String, dynamic>>();
      final rawMarks = monthData['student_daily_marks'] is Map
          ? Map<String, dynamic>.from(monthData['student_daily_marks'] as Map)
          : <String, dynamic>{};
      final rawRecDays = monthData['recorded_days'] is List
          ? (monthData['recorded_days'] as List)
          : const <dynamic>[];
      final recordedDaySet = <int>{
        for (final d in rawRecDays)
          if ((d is num ? d.toInt() : int.tryParse('$d') ?? 0) > 0)
            (d is num ? d.toInt() : int.tryParse('$d') ?? 0),
      };
      final lastDay = DateTime(_year, _month + 1, 0).day;

      final wb = ec.Excel.createExcel();
      final defSheet = wb.getDefaultSheet() ?? 'Sheet1';
      const s1Name = 'Recorded Attendance';
      if (defSheet != s1Name) {
        wb.rename(defSheet, s1Name);
      }
      final s1 = wb[s1Name];
      final s2 = wb['PM POSHAN & Breakfast'];

      void setCell(
        ec.Sheet sheet,
        int row,
        int col,
        String text, {
        String? fontColorHex,
        bool bold = false,
      }) {
        final cell = sheet.cell(
          ec.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
        );
        cell.value = ec.TextCellValue(text);
        if (fontColorHex != null || bold) {
          cell.cellStyle = ec.CellStyle(
            bold: bold,
            fontColorHex: fontColorHex != null
                ? ec.ExcelColor.fromHexString(fontColorHex)
                : ec.ExcelColor.black,
          );
        }
      }

      setCell(
        s1,
        0,
        0,
        '$_schoolName — $_classLabel — ${SupabaseHajariPatrakService.monthNamesGujarati[_month - 1]} $_year (Admin Recorded Attendance Register)',
        bold: true,
      );
      setCell(
        s2,
        0,
        0,
        '$_schoolName — $_classLabel — ${SupabaseHajariPatrakService.monthNamesGujarati[_month - 1]} $_year (Student-wise PM POSHAN & Breakfast Register)',
        bold: true,
      );

      final headers = <String>[
        'Roll No',
        'GR No',
        'Student Name / વિદ્યાર્થીનું નામ',
        'Gender',
        'Category',
        for (var d = 1; d <= lastDay; d++) '$d',
        'હાજર (Present)',
        'ગેરહાજર (Absent)',
        'PM POSHAN દિવસો',
        'નાસ્તો (Breakfast) દિવસો',
      ];
      for (var c = 0; c < headers.length; c++) {
        setCell(s1, 1, c, headers[c], bold: true);
        setCell(s2, 1, c, headers[c], bold: true);
      }

      for (var i = 0; i < students.length; i++) {
        final st = students[i];
        final sid = _text(st['id']);
        final stMarks = rawMarks[sid] is Map
            ? (rawMarks[sid] as Map).map((k, v) => MapEntry('$k', v))
            : <String, dynamic>{};
        final rowIdx = i + 2;
        final baseCols = <String>[
          _text(st['roll_number']).isEmpty ? '${i + 1}' : _text(st['roll_number']),
          _text(st['gr']),
          _text(st['name']),
          _text(st['gender']),
          _text(st['category']),
        ];
        for (var c = 0; c < baseCols.length; c++) {
          setCell(s1, rowIdx, c, baseCols[c]);
          setCell(s2, rowIdx, c, baseCols[c]);
        }

        var pCount = 0;
        var aCount = 0;
        var mdmCount = 0;
        var bfCount = 0;
        for (var d = 1; d <= lastDay; d++) {
          final dmRaw = stMarks['$d'];
          Map<String, dynamic>? dm;
          if (dmRaw is Map) {
            dm = Map<String, dynamic>.from(dmRaw);
          }
          if (dm == null && !recordedDaySet.contains(d)) {
            setCell(s1, rowIdx, 4 + d, '');
            setCell(s2, rowIdx, 4 + d, '');
            continue;
          }
          final isPresent = dm != null && dm['present'] == true;
          final isMdm = isPresent && dm['mdm'] == true;
          final isBf = isPresent && dm['breakfast'] == true;
          if (isPresent) {
            pCount++;
            if (isMdm) mdmCount++;
            if (isBf) bfCount++;
            String hex = '#000000';
            String s2Code = 'NONE';
            if (isMdm && isBf) {
              hex = '#DC2626'; // Red: Both
              s2Code = 'BOTH (P)';
            } else if (isMdm) {
              hex = '#1D4ED8'; // Blue: Only PM POSHAN
              s2Code = 'MDM (P)';
            } else if (isBf) {
              hex = '#DB2777'; // Pink: Only Breakfast
              s2Code = 'BF (P)';
            } else {
              hex = '#000000'; // Black: Neither
              s2Code = 'P (No Meal)';
            }
            setCell(s1, rowIdx, 4 + d, 'P', fontColorHex: hex, bold: true);
            setCell(s2, rowIdx, 4 + d, s2Code, fontColorHex: hex, bold: true);
          } else {
            aCount++;
            setCell(s1, rowIdx, 4 + d, 'A');
            setCell(s2, rowIdx, 4 + d, 'A');
          }
        }
        final tailOffset = 5 + lastDay;
        setCell(s1, rowIdx, tailOffset, '$pCount', bold: true);
        setCell(s1, rowIdx, tailOffset + 1, '$aCount');
        setCell(s1, rowIdx, tailOffset + 2, '$mdmCount', fontColorHex: '#1D4ED8', bold: true);
        setCell(s1, rowIdx, tailOffset + 3, '$bfCount', fontColorHex: '#DB2777', bold: true);

        setCell(s2, rowIdx, tailOffset, '$pCount', bold: true);
        setCell(s2, rowIdx, tailOffset + 1, '$aCount');
        setCell(s2, rowIdx, tailOffset + 2, '$mdmCount', fontColorHex: '#1D4ED8', bold: true);
        setCell(s2, rowIdx, tailOffset + 3, '$bfCount', fontColorHex: '#DB2777', bold: true);
      }

      final legendRow = students.length + 3;
      const legendText =
          'COLOUR CODE FOR P:  P (Black #000000) = હાજર (PM POSHAN કે નાસ્તો લીધેલ નથી)  |  P (Blue #1D4ED8) = માત્ર PM POSHAN  |  P (Pink #DB2777) = માત્ર નાસ્તો (Breakfast)  |  P (Red #DC2626) = PM POSHAN + નાસ્તો બંને  |  A = ગેરહાજર (Absent)';
      setCell(s1, legendRow, 0, legendText, bold: true);
      setCell(s2, legendRow, 0, legendText, bold: true);

      final encoded = wb.encode();
      if (encoded == null || encoded.isEmpty) {
        throw StateError('Excel બની શકી નથી.');
      }
      final fileName =
          'RECORDED_STUDENT_ATTENDANCE_MDM_BF_${_safeName(_classLabel)}_${_year}_${_month.toString().padLeft(2, '0')}.xlsx';
      await PsmFileExportHelper.saveOrShare(
        bytes: Uint8List.fromList(encoded),
        filename: fileName,
        title: 'Student-wise Recorded Attendance & MDM/Breakfast',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Student-wise Recorded Attendance + PM POSHAN & Breakfast Excel તૈયાર છે.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final years =
        List<int>.generate(DateTime.now().year - 2014, (index) => 2015 + index)
            .reversed
            .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hajari Patrak / હાજરીપત્રક'),
        actions: <Widget>[
          IconButton(
              tooltip: 'Refresh',
              onPressed: _loading || _generating ? null : _loadInitial,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Text(_schoolName,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _schoolNameLanguage,
                  decoration: InputDecoration(
                    labelText:
                        'School name on Hajari Patrak / હાજરીપત્રકમાં શાળાનું નામ',
                    helperText: _schoolNameLanguage == 'gu' &&
                            _schoolNameGujarati.isEmpty
                        ? 'ગુજરાતી નામ મળ્યું નથી; હાલ English નામ વપરાશે. Developer Panel માં ગુજરાતી નામ ઉમેરો.'
                        : 'છેલ્લી પસંદગી આ શાળા માટે આ browser માં સાચવાશે.',
                    border: const OutlineInputBorder(),
                  ),
                  isExpanded: true,
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(
                        value: 'gu', child: Text('ગુજરાતી')),
                    DropdownMenuItem<String>(
                        value: 'en', child: Text('English')),
                  ],
                  onChanged: _generating ? null : _changeSchoolNameLanguage,
                ),
                const SizedBox(height: 8),
                const Text(
                    'એક PDF માં Front Page અને હાજરી પત્રકના બધા પાનાં મળશે.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 14),
                if (_classes.isEmpty)
                  const Card(
                      child: Padding(
                          padding: EdgeInsets.all(14),
                          child: Text(
                              'આ login માટે કોઈ active/assigned class ઉપલબ્ધ નથી.')))
                else ...<Widget>[
                  DropdownButtonFormField<String>(
                    initialValue: _classId,
                    decoration: InputDecoration(
                      labelText: 'ધોરણ / Class',
                      labelStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    isExpanded: true,
                    dropdownColor: Colors.white,
                    itemHeight: 56,
                    alignment: Alignment.center,
                    style: TextStyle(
                        fontSize: 17,
                        color: Theme.of(context).colorScheme.onSurface),
                    items: _classes
                        .map((row) => DropdownMenuItem<String>(
                              value: _text(row['id']),
                              child: Center(
                                child: Text(
                                  _text(row['label']).isEmpty
                                      ? _text(row['class_key'])
                                      : _text(row['label']),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 17,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ))
                        .toList(),
                    onChanged: _generating || _saving
                        ? null
                        : (value) async {
                            if (value == null) return;
                            await _flushScheduledSettingsSave();
                            if (!mounted) return;
                            _settingsSaveTimer?.cancel();
                            setState(() {
                              _classId = value;
                              final klass = _selectedClass;
                              _officialTeacherId =
                                  _optionalId(klass?['class_teacher_id']);
                              _selectedTeacherId =
                                  _defaultTeacher(klass, _teachers);
                            });
                            await _loadClassSettings(value);
                          },
                  ),
                  const SizedBox(height: 12),
                  Row(children: <Widget>[
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        isExpanded: true,
                        initialValue: _month,
                        decoration: const InputDecoration(
                            labelText: 'માસ / Month',
                            border: OutlineInputBorder()),
                        items: List<DropdownMenuItem<int>>.generate(
                            12,
                            (index) => DropdownMenuItem<int>(
                                value: index + 1,
                                child: Text(SupabaseHajariPatrakService
                                    .monthNamesGujarati[index]))),
                        onChanged: _generating
                            ? null
                            : (value) =>
                                setState(() => _month = value ?? _month),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        isExpanded: true,
                        initialValue:
                            years.contains(_year) ? _year : years.first,
                        decoration: const InputDecoration(
                            labelText: 'વર્ષ / Year',
                            border: OutlineInputBorder()),
                        items: years
                            .map((value) => DropdownMenuItem<int>(
                                value: value, child: Text('$value')))
                            .toList(),
                        onChanged: _generating
                            ? null
                            : (value) => setState(() => _year = value ?? _year),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedTeacherId,
                    decoration: const InputDecoration(
                        labelText: 'PDF પર દર્શાવવાના વર્ગ શિક્ષક',
                        border: OutlineInputBorder(),
                        helperText:
                            'અહીં substitute teacher પસંદ કરવાથી official assignment બદલાતી નથી.'),
                    items: _teachers
                        .map((row) => DropdownMenuItem<String>(
                            value: _text(row['id']),
                            child: Text(_text(row['teacher_name']))))
                        .toList(),
                    onChanged: _generating
                        ? null
                        : (value) => setState(() => _selectedTeacherId = value),
                  ),
                  if (_isAdmin && !widget.readOnly) ...<Widget>[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _saving || _generating
                            ? null
                            : _saveOfficialTeacher,
                        icon: const Icon(Icons.assignment_ind_outlined),
                        label: const Text(
                            'પસંદ કરેલા શિક્ષકને Official Class Teacher તરીકે સેટ કરો'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: const Text(
                        'Row height અને font size ના વિકલ્પો પાછા ઉમેર્યા છે. આ બે સેટિંગ્સ માત્ર Cloud Run થી બનતા PDF ના વિદ્યાર્થી/ખાલી-row ભાગને બદલે છે. Excel export તમારા મૂળ template નું formatting અને print setup યથાવત્ રાખે છે.',
                      ),
                    ),
                  ),
                  _slider(
                    label: 'Row height / વિદ્યાર્થીની લાઇન ઊંચાઈ',
                    value: _rowHeight.toDouble(),
                    min: 12,
                    max: 36,
                    divisions: 24,
                    valueLabel: '$_rowHeight px',
                    onChanged: (value) {
                      setState(() => _rowHeight = value.round());
                      _scheduleSettingsSave();
                    },
                  ),
                  _slider(
                    label: 'Font size / અક્ષરનું માપ',
                    value: _fontSize.toDouble(),
                    min: 4,
                    max: 12,
                    divisions: 8,
                    valueLabel: '$_fontSize pt',
                    onChanged: (value) {
                      setState(() => _fontSize = value.round());
                      _scheduleSettingsSave();
                    },
                  ),
                  TextField(
                    controller: _blankRowsController,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    enabled: !_generating && !_saving && !widget.readOnly,
                    decoration: InputDecoration(
                      labelText:
                          'Blank rows after last student / છેલ્લે ખાલી લાઇન',
                      helperText:
                          'કોઈપણ સંખ્યા દાખલ કરો (જેમ કે 1, 7, 13). Excel summary rows 2001–2008 સ્થિર રહેશે; ઘણી ખાલી લાઇન પસંદ કરવાથી PDFમાં વધારાના પાના આવી શકે.',
                      errorText: _blankRowsError,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: _onBlankRowsChanged,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                      'ખાલી લાઇનની કોઈપણ પૂર્ણ સંખ્યા આ વર્ગ માટે save થશે. PDFમાં પસંદ કરેલી row height અને font size લાગુ પડશે; દિવસના ન હોતા columns છુપાશે અને મહિના અંતે હાથથી ભરવાના fields ખાલી રહેશે. Excel export મૂળ template મુજબ રહેશે.'),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                    FilledButton.icon(
                      onPressed: _generating || _saving ? null : _generatePdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(_generating
                          ? 'બનાવી રહ્યા છીએ…'
                          : 'Generate Hajari Patrak PDF'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _generating || _saving ? null : _exportExcel,
                      icon: const Icon(Icons.table_view_outlined),
                      label: Text(_generating
                          ? 'Excel બનાવી રહ્યા છીએ…'
                          : 'Export Hajari Patrak Excel'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _canSave ? _saveSettings : null,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save Hajari settings'),
                    ),
                  ]),
                  if (_isAdmin) ...<Widget>[
                    const SizedBox(height: 14),
                    Card(
                      color: Colors.indigo.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.indigo.shade400, width: 1.4),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Icon(Icons.verified_user_outlined,
                                    color: Colors.indigo.shade900),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'ફક્ત Admin માટે: ભરેલ હાજરીપત્રક (એ જ ટેમ્પ્લેટ) અને Student-wise હાજરી / PM POSHAN / નાસ્તો ડાઉનલોડ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      color: Colors.indigo.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'ભરેલ હાજરીપત્રક હવે સામાન્ય હાજરીપત્રકના એ જ ટેમ્પ્લેટમાં બને છે (ગુજરાતી ફોન્ટ સાચો). દરેક દિવસ માટે P = હાજર, A = ગેરહાજર; નીચેની લાઇનોમાં રોજની કેટેગરી પ્રમાણે હાજર, કુલ હાજર, ગેરહાજર, PM POSHAN અને નાસ્તાની સંખ્યા તથા માસિક સરાસરી આપમેળે ભરાય છે. રિમાર્કમાં "ભો./ના." = વિદ્યાર્થીએ ભોજન / નાસ્તો લીધેલ દિવસો.',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: <Widget>[
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.indigo.shade800,
                                  ),
                                  onPressed: _generating || _saving
                                      ? null
                                      : _generateRecordedColorHajariPdf,
                                  icon: const Icon(Icons.picture_as_pdf),
                                  label: const Text(
                                    'ભરેલ હાજરીપત્રક PDF (ટેમ્પ્લેટ + રોજનો સરવાળો)',
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _generating || _saving
                                      ? null
                                      : () => _generateRecordedColorHajariPdf(
                                          asExcel: true),
                                  icon: const Icon(Icons.table_view_outlined),
                                  label: const Text('ભરેલ હાજરીપત્રક Excel'),
                                ),
                                FilledButton.tonalIcon(
                                  onPressed: _generating || _saving
                                      ? null
                                      : _exportAdminRecordedStudentWiseExcel,
                                  icon: const Icon(Icons.grid_on_outlined),
                                  label: const Text(
                                    'Student-wise હાજરી + PM POSHAN + નાસ્તો Excel (.xlsx)',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!)),
                  ),
                ],
                if (_generating || _saving) ...<Widget>[
                  const SizedBox(height: 14),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: 14),
                const Text(
                    'Historical reprints use the student’s School Entry date and leaving date. Existing DATEWISE/Daily report settings are not used or changed by this screen.'),
              ],
            ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String valueLabel,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(label)),
              Text(valueLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: _generating || widget.readOnly ? null : onChanged,
          ),
        ],
      ),
    );
  }
}

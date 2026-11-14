import '../services/supabase_school_settings_service.dart';
import 'dart:async';



import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import 'package:provider/provider.dart';



import '../data/app_config.dart';

import '../models/models.dart';

import '../services/supabase_attendance_service.dart';
import '../services/device_preferences_service.dart';

import '../services/app_state.dart';

import '../theme/app_theme.dart';

import '../widgets/common_widgets.dart';

import '../widgets/dialogs.dart';

import '../widgets/number_field.dart';

import '../widgets/student_selection_panel.dart';
import '../widgets/breakfast_entry_type_selector.dart';

import 'admin_panel.dart';



class EntryPanel extends StatefulWidget {

  const EntryPanel({super.key});



  @override

  State<EntryPanel> createState() => _EntryPanelState();

}



class _EntryPanelState extends State<EntryPanel> {

  bool _quickPickMode = true;

  String? _selectedClass;

  DateTime _selectedDate = DateTime.now();



  bool _loading = false;

  String? _lockMessage; // Sunday / holiday / future / no-row / zero-reg message

  CategoryCounts _registered = CategoryCounts();

  AttendanceRecord _original = AttendanceRecord.empty();

  bool _formVisible = false;

  int _reloadTick = 0;



  // Time-lock state, mirroring the website's isSubmitted / isLocked.

  bool _isSubmitted = false;

  bool _isLocked = false;



  CategoryCounts _presentEdit = CategoryCounts();

  CategoryCounts _mdmEdit = CategoryCounts();

  int _breakfastEdit = 0;

  String _breakfastEntryType = 'same_as_present';
  final Map<String, int> _singleBreakfastByCategory = {'SC': 0, 'ST': 0, 'OBC': 0, 'OTHER': 0};

  Map<String, Map<String, Map<String, int>>> _genderValues = _emptyGenderValues();

  bool _genderNeedsEntry = false;

  Map<String, int> _genderBreakfast = {'BOYS': 0, 'GIRLS': 0};



  static Map<String, Map<String, Map<String, int>>> _emptyGenderValues() => {

    for (final gender in ['BOYS', 'GIRLS']) gender: {

      for (final cat in ['SC', 'ST', 'OBC', 'OTHER']) cat: {'registered': 0, 'present': 0, 'mdm': 0, 'breakfast': 0},

    },

  };



  Map<String, Map<String, Map<String, int>>> _makeGenderValues(Map<String, dynamic> raw, CategoryCounts registered, AttendanceRecord original, List<StudentRecord> students, String schoolType) {

    final out = _emptyGenderValues();

    bool storedSplit = false;

    for (final gender in ['BOYS', 'GIRLS']) {

      final gm = raw[gender];

      for (final cat in ['SC', 'ST', 'OBC', 'OTHER']) {

        final v = gm is Map ? gm[cat] : null;

        if (v is Map) {

          for (final metric in ['registered', 'present', 'mdm', 'breakfast']) {

            final parsed = int.tryParse('${v[metric] ?? 0}') ?? 0;

            out[gender]![cat]![metric] = parsed;

            // Only real nonzero class-sheet counts make the split authoritative.

            // An empty zero map must not hide counts derived from a gendered roster.

            if (parsed > 0 && metric != 'breakfast') storedSplit = true;

          }

        }

      }

    }

    if (!storedSplit) {

      // Registration can be derived only from explicit roster genders or single-sex school type.

      for (final c in AppConfig.categories) {

        final cat = c.apiKey;

        if (schoolType == 'boys' || schoolType == 'girls') {

          final g = schoolType == 'boys' ? 'BOYS' : 'GIRLS';

          out[g]![cat]!['registered'] = registered[c];

          if (original.present[c] >= 0) out[g]![cat]!['present'] = original.present[c];

          if (original.mdm[c] >= 0) out[g]![cat]!['mdm'] = original.mdm[c];

        } else {

          final genderCounts = <String, int>{'BOYS': 0, 'GIRLS': 0};

          for (final student in students) {

            if (student.category == c && (student.gender == 'BOYS' || student.gender == 'GIRLS')) genderCounts[student.gender] = (genderCounts[student.gender] ?? 0) + 1;

          }

          out['BOYS']![cat]!['registered'] = genderCounts['BOYS'] ?? 0;

          out['GIRLS']![cat]!['registered'] = genderCounts['GIRLS'] ?? 0;

        }

      }

    }

    return out;

  }



  Map<String, int> _makeGenderBreakfast(Map<String, dynamic> raw, AttendanceRecord original, String schoolType) {

    final out = <String, int>{'BOYS': 0, 'GIRLS': 0};

    for (final gender in ['BOYS', 'GIRLS']) {

      final group = raw[gender];

      if (group is Map) {

        final overall = group['_OVERALL'];

        if (overall is Map && overall.containsKey('breakfast')) {

          out[gender] = int.tryParse('${overall['breakfast'] ?? 0}') ?? 0;

        } else {

          // Compatibility with an older saved gender breakdown that placed

          // breakfast under each category.

          out[gender] = ['SC', 'ST', 'OBC', 'OTHER'].fold<int>(0, (n, cat) {

            final value = group[cat];

            return n + (value is Map ? (int.tryParse('${value['breakfast'] ?? 0}') ?? 0) : 0);

          });

        }

      }

    }

    if (schoolType == 'boys') return {'BOYS': original.breakfastTotal, 'GIRLS': 0};

    if (schoolType == 'girls') return {'BOYS': 0, 'GIRLS': original.breakfastTotal};

    if (out.values.every((v) => v == 0) && original.breakfastTotal > 0) {

      // A co-ed legacy aggregate cannot be allocated to either gender.

      return {'BOYS': 0, 'GIRLS': 0};

    }

    return out;

  }



  Map<String, dynamic> _genderBreakdownPayload() {
    final schoolType = context.read<AppState>().schoolType.toLowerCase();
    final sameAsPresent = _breakfastEntryType == 'same_as_present';
    final genderWise = _breakfastEntryType == 'gender';
    int categoryBreakfast(String gender, String category) =>
        sameAsPresent ? (_genderValues[gender]?[category]?['breakfast'] ?? 0) : 0;
    int genderCategoryBreakfastTotal(String gender) => AppConfig.categories.fold<int>(
      0, (n, c) => n + categoryBreakfast(gender, c.apiKey));

    if (schoolType == 'coed') {
      final result = <String, dynamic>{
        for (final gender in ['BOYS', 'GIRLS']) gender: {
          for (final c in AppConfig.categories) c.apiKey: {
            ..._genderValues[gender]![c.apiKey]!,
            'breakfast': categoryBreakfast(gender, c.apiKey),
          },
          '_OVERALL': {
            'registered': AppConfig.categories.fold<int>(0, (n, c) => n + _genderValues[gender]![c.apiKey]!['registered']!),
            'present': AppConfig.categories.fold<int>(0, (n, c) => n + _genderValues[gender]![c.apiKey]!['present']!),
            'mdm': AppConfig.categories.fold<int>(0, (n, c) => n + _genderValues[gender]![c.apiKey]!['mdm']!),
            'breakfast': sameAsPresent
                ? genderCategoryBreakfastTotal(gender)
                : (genderWise ? (_genderBreakfast[gender] ?? 0) : 0),
          },
        },
      };
      if (!genderWise && !sameAsPresent) {
        result['UNSPECIFIED'] = {
          for (final c in AppConfig.categories) c.apiKey: {
            'registered': 0, 'present': 0, 'mdm': 0, 'breakfast': 0,
          },
          '_OVERALL': {'registered': 0, 'present': 0, 'mdm': 0, 'breakfast': _breakfastEdit},
        };
      }
      return result;
    }

    // Boys-only / girls-only schools keep category-based present/PM POSHAN counts.
    // A Total-mode breakfast is stored as UNSPECIFIED rather than guessed into a gender.
    final selected = schoolType == 'boys' ? 'BOYS' : 'GIRLS';
    final other = selected == 'BOYS' ? 'GIRLS' : 'BOYS';
    Map<String, dynamic> genderMap(String gender) {
      final isSelected = gender == selected;
      return {
        for (final c in AppConfig.categories) c.apiKey: {
          'registered': isSelected ? _registered[c] : 0,
          'present': isSelected ? _presentEdit[c] : 0,
          'mdm': isSelected ? _mdmEdit[c] : 0,
          'breakfast': isSelected && sameAsPresent ? (_singleBreakfastByCategory[c.apiKey] ?? 0) : 0,
        },
        '_OVERALL': {
          'registered': isSelected ? _registered.total : 0,
          'present': isSelected ? _presentEdit.total : 0,
          'mdm': isSelected ? _mdmEdit.total : 0,
          'breakfast': isSelected && genderWise ? _breakfastEdit :
              (isSelected && sameAsPresent ? _singleBreakfastByCategory.values.fold<int>(0, (a, b) => a + b) : 0),
        },
      };
    }
    final result = <String, dynamic>{selected: genderMap(selected), other: genderMap(other)};
    if (!genderWise && !sameAsPresent) {
      result['UNSPECIFIED'] = {
        for (final c in AppConfig.categories) c.apiKey: {
          'registered': 0, 'present': 0, 'mdm': 0, 'breakfast': 0,
        },
        '_OVERALL': {'registered': 0, 'present': 0, 'mdm': 0, 'breakfast': _breakfastEdit},
      };
    }
    return result;
  }

  void _syncAggregateFromGender() {

    final registered = CategoryCounts();

    final present = CategoryCounts();

    final mdm = CategoryCounts();

    var breakfast = 0;

    for (final c in AppConfig.categories) {

      final key = c.apiKey;

      registered.set(c, _genderValues['BOYS']![key]!['registered']! + _genderValues['GIRLS']![key]!['registered']!);

      present.set(c, _genderValues['BOYS']![key]!['present']! + _genderValues['GIRLS']![key]!['present']!);

      mdm.set(c, _genderValues['BOYS']![key]!['mdm']! + _genderValues['GIRLS']![key]!['mdm']!);

      // Breakfast is stored as one overall Boys/Girls figure, not by social category.

    }

    _registered = registered;

    _presentEdit = present;

    _mdmEdit = mdm;

    if (_breakfastEntryType == 'gender') {
      _breakfastEdit = (_genderBreakfast['BOYS'] ?? 0) + (_genderBreakfast['GIRLS'] ?? 0);
    } else if (_breakfastEntryType == 'same_as_present') {
      _breakfastEdit = AppConfig.categories.fold<int>(0, (n, c) => n +
        (_genderValues['BOYS']![c.apiKey]!['breakfast'] ?? 0) +
        (_genderValues['GIRLS']![c.apiKey]!['breakfast'] ?? 0));
    }

  }

  Future<void> _setBreakfastEntryType(String value) async {
    setState(() {
      _breakfastEntryType = value;
      if (value == 'gender') {
        final schoolType = context.read<AppState>().schoolType.toLowerCase();
        if (schoolType == 'boys') _genderBreakfast['BOYS'] ??= _breakfastEdit;
        else if (schoolType == 'girls') _genderBreakfast['GIRLS'] ??= _breakfastEdit;
        _breakfastEdit = schoolType == 'coed'
            ? (_genderBreakfast['BOYS'] ?? 0) + (_genderBreakfast['GIRLS'] ?? 0)
            : (schoolType == 'boys' ? (_genderBreakfast['BOYS'] ?? 0) : (_genderBreakfast['GIRLS'] ?? 0));
      } else if (value == 'same_as_present') {
        final schoolType = context.read<AppState>().schoolType.toLowerCase();
        if (schoolType == 'coed') {
          _breakfastEdit = AppConfig.categories.fold<int>(0, (n, c) => n +
            (_genderValues['BOYS']![c.apiKey]!['breakfast'] ?? 0) +
            (_genderValues['GIRLS']![c.apiKey]!['breakfast'] ?? 0));
        } else {
          _breakfastEdit = _singleBreakfastByCategory.values.fold<int>(0, (a, b) => a + b);
        }
      }
    });
    await DevicePreferencesService().saveBreakfastEntryType(value);
  }

  Widget _breakfastTypeSelector() => BreakfastEntryTypeSelector(
    value: _breakfastEntryType,
    onChanged: (value) { _setBreakfastEntryType(value); },
  );

  Widget _buildTotalBreakfastInput({bool coed = false}) {
    final schoolType = context.read<AppState>().schoolType.toLowerCase();
    final String label = _breakfastEntryType == 'gender' && !coed
        ? (schoolType == 'boys' ? '👦 Boys' : '👧 Girls')
        : (coed ? 'Total' : 'Breakfast');
    return SizedBox(
      width: 180,
      child: QuickNumberField(
        key: ValueKey('bf-total-$_selectedClass-$_dateStr-$_reloadTick-$_breakfastEntryType-$_isLocked'),
        label: label,
        initialValue: _breakfastEdit > _presentEdit.total ? 0 : _breakfastEdit,
        max: _presentEdit.total,
        quickPickMode: _quickPickMode,
        enabled: !_isLocked,
        onChanged: (v) => setState(() {
          _breakfastEdit = v;
          if (_breakfastEntryType == 'gender') {
            final type = context.read<AppState>().schoolType.toLowerCase();
            if (type == 'boys') _genderBreakfast['BOYS'] = v;
            if (type == 'girls') _genderBreakfast['GIRLS'] = v;
          }
        }),
      ),
    );
  }

  Widget _buildCategoryBreakfastInputs({required bool coed}) {
    final schoolType = context.read<AppState>().schoolType.toLowerCase();
    final genders = coed ? const ['BOYS', 'GIRLS'] : const <String>[];
    final categoryWidgets = <Widget>[];
    for (final c in AppConfig.categories) {
      final fields = <Widget>[];
      if (coed) {
        for (final gender in genders) {
          final presentMax = _genderValues[gender]![c.apiKey]!['present'] ?? 0;
          fields.add(SizedBox(
            width: 148,
            child: QuickNumberField(
              key: ValueKey('bf-cat-$_selectedClass-$_dateStr-$_reloadTick-$gender-${c.apiKey}'),
              label: '${gender == 'BOYS' ? '👦 Boys' : '👧 Girls'} ${c.apiKey}',
              initialValue: _genderValues[gender]![c.apiKey]!['breakfast'] ?? 0,
              max: presentMax,
              quickPickMode: _quickPickMode,
              enabled: !_isLocked,
              onChanged: (v) => setState(() {
                _genderValues[gender]![c.apiKey]!['breakfast'] = v;
                _breakfastEdit = AppConfig.categories.fold<int>(0, (n, cat) => n +
                  (_genderValues['BOYS']![cat.apiKey]!['breakfast'] ?? 0) +
                  (_genderValues['GIRLS']![cat.apiKey]!['breakfast'] ?? 0));
              }),
            ),
          ));
        }
      } else {
        fields.add(SizedBox(
          width: 180,
          child: QuickNumberField(
            key: ValueKey('bf-single-cat-$_selectedClass-$_dateStr-$_reloadTick-${c.apiKey}'),
            label: c.shortLabel,
            initialValue: _singleBreakfastByCategory[c.apiKey] ?? 0,
            max: _presentEdit[c],
            quickPickMode: _quickPickMode,
            enabled: !_isLocked,
            onChanged: (v) => setState(() {
              _singleBreakfastByCategory[c.apiKey] = v;
              final gender = schoolType == 'boys' ? 'BOYS' : 'GIRLS';
              _genderValues[gender]![c.apiKey]!['breakfast'] = v;
              _breakfastEdit = _singleBreakfastByCategory.values.fold<int>(0, (a, b) => a + b);
            }),
          ),
        ));
      }
      categoryWidgets.add(Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.shortLabel, style: guFont(fontWeight: FontWeight.w900, color: AppColors.navy)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: fields),
          ]),
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: categoryWidgets);
  }





  void _setGenderValue(String gender, Category category, String metric, int value) {

    setState(() {

      _genderValues[gender]![category.apiKey]![metric] = value;

      _genderNeedsEntry = false;

      _syncAggregateFromGender();

    });

  }



  void _setGenderBreakfast(String gender, int value) {

    setState(() {

      _genderBreakfast[gender] = value;

      _genderNeedsEntry = false;

      _breakfastEdit = (_genderBreakfast['BOYS'] ?? 0) + (_genderBreakfast['GIRLS'] ?? 0);

    });

  }



  bool _saving = false;

  String? _saveAlert;

  bool _saveAlertIsError = false;



  bool _didInit = false;

  Timer? _lockTimer;

  bool _studentSelectionMode = false;
  bool _directEntryEnabled = true;

  List<StudentRecord> _students = const <StudentRecord>[];



  @override

  void didChangeDependencies() {

    super.didChangeDependencies();

    if (!_didInit) {

      _didInit = true;

      final state = context.read<AppState>();

      _quickPickMode = state.quickPickMode;

      _studentSelectionMode = state.preferredEntryMode == 'student';



      final allowed = state.allowedClasses;

      if (allowed.isNotEmpty) {

        final last = state.lastSelectedClass;

        _selectedClass = allowed.any((c) => c.key == last) ? last : allowed.first.key;

        if (_selectedClass != null && _selectedClass != last) {

          state.setLastSelectedClass(_selectedClass!);

        }

      }

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final savedBreakfastType = await DevicePreferencesService().loadBreakfastEntryType();
        if (!mounted) return;
        setState(() => _breakfastEntryType = savedBreakfastType);
        await _loadRow();
        _startLockTimer();
      });

    }

  }



  String get _dateStr => DateFormat('yyyy-MM-dd').format(_selectedDate);



  /// 12:01 PM lock, ported 1:1 from the website's isEditAllowed():

  /// only \*today's\* row is editable, and only up to 12:01 PM.

  bool _isEditAllowed(DateTime date) {

    final now = DateTime.now();

    final d = DateTime(date.year, date.month, date.day);

    final t = DateTime(now.year, now.month, now.day);

    if (d != t) return false;

    if (now.hour < 12) return true;

    if (now.hour == 12 && now.minute <= 1) return true;

    return false;

  }



  void _startLockTimer() {

    _lockTimer?.cancel();

    _lockTimer = Timer.periodic(const Duration(seconds: 5), (_) {

      if (!mounted || !_isSubmitted || _isLocked) return;

      if (!_isEditAllowed(_selectedDate)) {

        setState(() => _isLocked = true);

      }

    });

  }



  @override

  void dispose() {

    _lockTimer?.cancel();

    super.dispose();

  }



  Future<void> _loadRow() async {

    if (_selectedClass == null) return;

    final state = context.read<AppState>();

    setState(() {

      _loading = true;

      _lockMessage = null;

      _formVisible = false;

      _saveAlert = null;

      _isLocked = false;

      _isSubmitted = false;

    });



    // Future date is blocked, same as the website.

    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);

    final sel = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);

    if (sel.isAfter(today)) {

      setState(() {

        _loading = false;

        _lockMessage = '❌ ભવિષ્યની તારીખ: તમે આવનારા દિવસો માટે ડેટા દાખલ કરી શકશો નહીં.';

      });

      return;

    }



    // Sunday is locked client-side, same as the original UI.

    if (_selectedDate.weekday == DateTime.sunday) {

      setState(() {

        _loading = false;

        _lockMessage = '❌ રવિવાર: રવિવારની રજા હોવાથી ડેટા એન્ટ્રી બંધ છે.';

      });

      return;

    }



    final holidayReason = state.holidays[_dateStr];

    if (holidayReason != null) {

      setState(() {

        _loading = false;

        _lockMessage = '🏖️ જાહેર રજા: આ તારીખે આચાર્યશ્રી દ્વારા રજા જાહેર કરવામાં આવી છે ($holidayReason).';

      });

      return;

    }



    try {
      final directAllowed = await SupabaseSchoolSettingsService().loadDirectAttendanceEntryEnabled();
      if (mounted) {
        setState(() {
          _directEntryEnabled = directAllowed;
          if (!_directEntryEnabled) _studentSelectionMode = true;
        });
      }
    } catch (_) {}

    final attendanceService = SupabaseAttendanceService();



    try {

      final row = await attendanceService.getRowData(

  _selectedClass!,

  _dateStr,

);

      if (!mounted) return;



      // A new class may start with zero registered pupils. Keep the form visible so

      // authorized staff can enter the registration totals instead of creating a dead end.

      if (row.registered.total == 0 && row.students.isEmpty) {

        setState(() {

          _loading = false;

          _registered = row.registered;

          _original = row.attendance ?? AttendanceRecord.empty();

          _presentEdit = _original.present.copy();

          _mdmEdit = _original.mdm.copy();

          _breakfastEdit = _original.breakfastTotal;

          _students = row.students;

          _genderValues = _emptyGenderValues();

          _genderBreakfast = {'BOYS': 0, 'GIRLS': 0};

          _genderNeedsEntry = true;

          _formVisible = true;

          _reloadTick++;

          _lockMessage = 'ℹ️ રજીસ્ટર્ડ સંખ્યા 0 છે. પહેલાં રજીસ્ટર્ડ સંખ્યા દાખલ કરો.';

        });

        return;

      }



      final original = row.attendance ?? AttendanceRecord.empty();

      final hasSaved = row.attendance != null;

      final loadedStudents = row.students;

      final studentStates = row.studentDetailsSaved

          ? loadedStudents

          : loadedStudents

              .map((s) => s.copyWith(present: true, mdm: false, breakfast: false))

              .toList();

      final genderValues = _makeGenderValues(row.genderBreakdown, row.registered, original, loadedStudents, state.schoolType);

      final genderBreakfast = _makeGenderBreakfast(row.genderBreakdown, original, state.schoolType);

      final splitPresent = ['BOYS','GIRLS'].any((g) => ['SC','ST','OBC','OTHER'].any((cat) {

        final group = row.genderBreakdown[g];

        final value = group is Map ? group[cat] : null;

        if (value is! Map) return false;

        return ['registered','present','mdm'].any((metric) => (int.tryParse('${value[metric] ?? 0}') ?? 0) > 0);

      }));

      setState(() {

        _loading = false;

        _registered = row.registered;

        _original = original;

        _presentEdit = original.present.copy();

        _mdmEdit = original.mdm.copy();

        _breakfastEdit = original.breakfastTotal;

        _students = studentStates;

        _genderValues = genderValues;

        _genderBreakfast = genderBreakfast;
        for (final c in AppConfig.categories) {
          final singleGender = state.schoolType.toLowerCase() == 'boys' ? 'BOYS' : 'GIRLS';
          _singleBreakfastByCategory[c.apiKey] = _genderValues[singleGender]![c.apiKey]!['breakfast'] ?? 0;
        }
        if (_breakfastEntryType == 'same_as_present') {
          if (state.schoolType.toLowerCase() == 'coed') {
            _breakfastEdit = AppConfig.categories.fold<int>(0, (n, c) => n +
              (_genderValues['BOYS']![c.apiKey]!['breakfast'] ?? 0) +
              (_genderValues['GIRLS']![c.apiKey]!['breakfast'] ?? 0));
          } else {
            _breakfastEdit = _singleBreakfastByCategory.values.fold<int>(0, (a, b) => a + b);
          }
        } else if (_breakfastEntryType == 'gender') {
          _breakfastEdit = state.schoolType.toLowerCase() == 'coed'
              ? (genderBreakfast['BOYS'] ?? 0) + (genderBreakfast['GIRLS'] ?? 0)
              : (state.schoolType.toLowerCase() == 'boys' ? (genderBreakfast['BOYS'] ?? 0) : (genderBreakfast['GIRLS'] ?? 0));
        }

        final hasRosterGender = loadedStudents.any((s) => s.gender == 'BOYS' || s.gender == 'GIRLS');

        _genderNeedsEntry = state.schoolType == 'coed' && (hasSaved && !splitPresent || !splitPresent && !hasRosterGender && row.registered.total > 0);

        if (state.schoolType == 'coed' && splitPresent) {

          _syncAggregateFromGender();

        }

        // Existing saved rows follow the 12:01 lock; brand-new rows stay editable.

        _isSubmitted = hasSaved;

        _isLocked = hasSaved ? !_isEditAllowed(_selectedDate) : false;

        _formVisible = true;

        _reloadTick++;

      });

    } on Exception catch (e) {

      if (!mounted) return;

      setState(() {

        _loading = false;

        _lockMessage = '❌ ${e.toString()}';

      });

    } catch (e) {

      if (!mounted) return;

      setState(() {

        _loading = false;

        _lockMessage = '❌ ડેટા લોડ કરવામાં ભૂલ: $e';

      });

    }

  }



  void _changeDate(DateTime d) {

    setState(() => _selectedDate = DateTime(d.year, d.month, d.day));

    _loadRow();

  }



  Future<void> _pickDate() async {

    final picked = await showDatePicker(

      context: context,

      initialDate: _selectedDate,

      firstDate: DateTime(2020),

      lastDate: DateTime(2035),

    );

    if (picked != null) _changeDate(picked);

  }



  void _onClassChanged(String? key) {

    if (key == null) return;

    setState(() => _selectedClass = key);

    context.read<AppState>().setLastSelectedClass(key);

    showSnack(context, '📌 છેલ્લી પસંદ: $key');

    _loadRow();

  }



  List<String> _validationIssues() {

    final issues = <String>[];

    final coed = context.read<AppState>().schoolType.toLowerCase() == 'coed';

    if (coed && _genderNeedsEntry) {

      issues.add('આ કો-એડ શાળામાં આ તારીખની નોંધણી/હાજરીનો Boys-Girls split અધૂરો છે. સાચા Boys અને Girls આંકડા દાખલ કરો.');

    }

    for (final c in AppConfig.categories) {

      if (_presentEdit[c] > _registered[c]) {

        issues.add('${c.shortLabel}: હાજર (${_presentEdit[c]}) > રજિસ્ટર્ડ (${_registered[c]})');

      }

      if (_mdmEdit[c] > _presentEdit[c]) {

        issues.add('${c.shortLabel}: પીએમ પોષણ (${_mdmEdit[c]}) > હાજર (${_presentEdit[c]})');

      }

    }

    if (_breakfastEdit > _presentEdit.total) {
      issues.add('અલ્પાહાર ($_breakfastEdit) > કુલ હાજર (${_presentEdit.total})');
    }
    if (!coed && _breakfastEntryType == 'same_as_present') {
      for (final c in AppConfig.categories) {
        final value = _singleBreakfastByCategory[c.apiKey] ?? 0;
        if (value > _presentEdit[c]) issues.add('${c.shortLabel}: breakfast cannot exceed present.');
      }
    }

    if (coed) {

      for (final c in AppConfig.categories) {

        final cat = c.apiKey;

        final b = _genderValues['BOYS']![cat]!;

        final g = _genderValues['GIRLS']![cat]!;

        if (b['present']! > b['registered']! || g['present']! > g['registered']!) {

          issues.add('$cat: gender-wise present cannot exceed registered.');

        }

        if (b['mdm']! > b['present']! || g['mdm']! > g['present']!) {

          issues.add('$cat: gender-wise PM Poshan cannot exceed present.');

        }

      }

      final boysPresent = AppConfig.categories.fold<int>(0, (n, c) => n + _genderValues['BOYS']![c.apiKey]!['present']!);

      final girlsPresent = AppConfig.categories.fold<int>(0, (n, c) => n + _genderValues['GIRLS']![c.apiKey]!['present']!);

      if (_breakfastEntryType == 'gender') {
        if ((_genderBreakfast['BOYS'] ?? 0) > boysPresent) issues.add('Boys breakfast cannot exceed Boys present.');
        if ((_genderBreakfast['GIRLS'] ?? 0) > girlsPresent) issues.add('Girls breakfast cannot exceed Girls present.');
      }
      if (_breakfastEntryType == 'same_as_present') {
        for (final c in AppConfig.categories) {
          for (final gender in ['BOYS', 'GIRLS']) {
            final value = _genderValues[gender]![c.apiKey]!['breakfast'] ?? 0;
            final maxPresent = _genderValues[gender]![c.apiKey]!['present'] ?? 0;
            if (value > maxPresent) issues.add('$gender ${c.apiKey} breakfast cannot exceed present.');
          }
        }
      }

    }

    return issues;

  }





  Future<void> _submit() async {

    setState(() => _saveAlert = null);

    final issues = _validationIssues();

    if (issues.isNotEmpty) {

      setState(() {

        _saveAlertIsError = true;

        _saveAlert = '⚠️ સુધારો જરૂરી:\n• ${issues.join('\n• ')}';

      });

      return;

    }



    if (_presentEdit.total == 0 && _mdmEdit.total == 0 && _breakfastEdit == 0) {

      final ok = await showAllZeroConfirm(context);

      if (!ok) return;

    } else if (_presentEdit.total > 0 && (_mdmEdit.total == 0 || _breakfastEdit == 0)) {

      final ok = await showMdmBfZeroConfirm(context);

      if (!ok) return;

    }



    if (!mounted) return;

    setState(() => _saving = true);

    final state = context.read<AppState>();

    try {

      final attendanceService = SupabaseAttendanceService();



final res = await attendanceService.saveAttendance(

  className: _selectedClass!,

  date: _dateStr,

  registered: _registered,

  present: _presentEdit,

  mdm: _mdmEdit,

  breakfastTotal: _breakfastEdit,

  genderBreakdown: _genderBreakdownPayload(),

);

      if (!mounted) return;

      if (res['result'] == 'success') {

        setState(() {

          _saving = false;

          _saveAlertIsError = false;

          _saveAlert = '✅ $_selectedClass – $_dateStr ની હાજરી સફળતાપૂર્વક સાચવી!';

          _original = AttendanceRecord(present: _presentEdit.copy(), mdm: _mdmEdit.copy(), breakfastTotal: _breakfastEdit);

          _isSubmitted = true;

          // Re-evaluate the 12:01 lock after saving (locks the form if

          // the save happened after the cutoff), matching the website.

          _isLocked = !_isEditAllowed(_selectedDate);

          _reloadTick++;

        });

      } else {

        setState(() {

          _saving = false;

          _saveAlertIsError = true;

          _saveAlert = '❌ ${res['message'] ?? 'સેવ કરવામાં ભૂલ.'}';

        });

      }

    } catch (e) {

      if (!mounted) return;

      setState(() {

        _saving = false;

        _saveAlertIsError = true;

        _saveAlert = '❌ સાચવી શકાયું નહી: $e';

      });

    }

  }



  Future<Map<String, dynamic>> _saveStudentSelection(List<StudentRecord> students) async {

    final state = context.read<AppState>();

    if (_selectedClass == null) {

      return {'result': 'error', 'message': 'ધોરણ પસંદ કરો.'};

    }

    if (!state.currentTeacher!.canAccessClass(_selectedClass!)) {

      return {'result': 'error', 'message': 'તમને આ વર્ગ માટે સબમિટ કરવાની પરવાનગી નથી.'};

    }

    if (_isSubmitted && !_isEditAllowed(_selectedDate)) {

      return {'result': 'error', 'message': '🔒 આ તારીખની attendance lock થઈ ગઈ છે. 12:01 PM પછી અથવા જૂની તારીખમાં સેવ/અપડેટ કરી શકાશે નહીં.'};

    }



    final regFromAh = CategoryCounts();

    final present = CategoryCounts();

    final mdm = CategoryCounts();

    var breakfast = 0;

    for (final s in students) {

      regFromAh.set(s.category, regFromAh[s.category] + 1);

      if (s.present) present.set(s.category, present[s.category] + 1);

      if (s.present && s.mdm) mdm.set(s.category, mdm[s.category] + 1);

      if (s.present && s.breakfast) breakfast++;

    }

    for (final c in AppConfig.categories) {

      if (present[c] > regFromAh[c]) {

        return {'result': 'error', 'message': '${c.shortLabel}: હાજર (${present[c]}) > રજિસ્ટર્ડ (${regFromAh[c]})'};

      }

      if (mdm[c] > present[c]) {

        return {'result': 'error', 'message': '${c.shortLabel}: પીએમ પોષણ (${mdm[c]}) > હાજર (${present[c]})'};

      }

    }

    if (breakfast > present.total) {

      return {'result': 'error', 'message': 'અલ્પાહાર ($breakfast) > કુલ હાજર (${present.total})'};

    }



    final attendanceService = SupabaseAttendanceService();



final res = await attendanceService.saveStudentAttendance(

  className: _selectedClass!,

  date: _dateStr,

  students: students,

);

    if (res['result'] == 'success') {

      if (!mounted) return res;

      setState(() {

        _students = List<StudentRecord>.from(students);

        _presentEdit = present;

        _mdmEdit = mdm;

        _breakfastEdit = breakfast;

        _original = AttendanceRecord(

          present: present.copy(),

          mdm: mdm.copy(),

          breakfastTotal: breakfast,

        );

        _isSubmitted = true;

        _isLocked = !_isEditAllowed(_selectedDate);

      });

    }

    return res;

  }



  void _resetForm() {

    setState(() {

      _presentEdit = _original.present.copy();

      _mdmEdit = _original.mdm.copy();

      _breakfastEdit = _original.breakfastTotal;

      if (context.read<AppState>().schoolType.toLowerCase() == 'coed') {

        _genderValues = _makeGenderValues(const {}, _registered, _original, _students, 'coed');

        _genderBreakfast = {'BOYS': 0, 'GIRLS': 0};

      }

      _saveAlert = null;

      _reloadTick++;

    });

  }



  @override

  Widget build(BuildContext context) {

    final state = context.watch<AppState>();

    final allowed = state.allowedClasses;



    return AppCard(

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.stretch,

        children: [

          const CardTitleRow(emoji: '📝', title: 'દૈનિક હાજરી નોંધણી'),

          _buildModeTabs(),

          if (!_studentSelectionMode) ...[

            const SizedBox(height: 8),

            _buildDropdownToggle(),

          ],

          const SizedBox(height: 14),

          ClassLockNote(

            text: state.isAdmin

                ? '🔓 Admin — બધા વર્ગ'

                : '🔐 તમારા વર્ગ: ${allowed.map((c) => c.key).join(' • ')}',

          ),

          if (state.isAdmin) const AdminPanel(),

          if (allowed.isEmpty)

            const MessageState(text: 'તમારા ખાતા સાથે કોઈ વર્ગ જોડાયેલ નથી. Admin નો સંપર્ક કરો.')

          else ...[

            _buildFormRow(allowed),

            if (_loading) const Padding(padding: EdgeInsets.only(top: 16), child: LoadingState()),

            if (!_loading && _lockMessage != null) AlertBox(kind: AlertKind.error, text: _lockMessage!),

            if (!_loading && _formVisible) _buildEntryForm(),

          ],

        ],

      ),

    );

  }



  Widget _buildModeTabs() {
    if (!_directEntryEnabled) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.slateLight,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.checklist_rtl_rounded, size: 18, color: AppColors.navy),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '👥 વિદ્યાર્થીવાર હાજરી (Students Selection) — Direct Entry બંધ (Deactive) છે',
                style: guFont(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.navy),
              ),
            ),
          ],
        ),
      );
    }

    return Container(

      padding: const EdgeInsets.all(4),

      decoration: BoxDecoration(

        color: AppColors.slateLight,

        borderRadius: BorderRadius.circular(11),

        border: Border.all(color: AppColors.border),

      ),

      child: Row(

        children: [

          Expanded(child: _modeTab(

            label: '🔢 Direct Entry',

            selected: !_studentSelectionMode,

            onTap: () {

              setState(() => _studentSelectionMode = false);

              context.read<AppState>().setPreferredEntryMode('direct');

            },

          )),

          Expanded(child: _modeTab(

            label: '👥 Students Selection',

            selected: _studentSelectionMode,

            onTap: () {

              setState(() => _studentSelectionMode = true);

              context.read<AppState>().setPreferredEntryMode('student');

            },

          )),

        ],

      ),

    );

  }



  Widget _modeTab({required String label, required bool selected, required VoidCallback onTap}) {

    return InkWell(

      onTap: onTap,

      borderRadius: BorderRadius.circular(9),

      child: AnimatedContainer(

        duration: const Duration(milliseconds: 140),

        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),

        alignment: Alignment.center,

        decoration: BoxDecoration(

          color: selected ? AppColors.navy : Colors.transparent,

          borderRadius: BorderRadius.circular(9),

        ),

        child: Text(label, textAlign: TextAlign.center, style: guFont(

          fontSize: 12,

          fontWeight: FontWeight.w800,

          color: selected ? Colors.white : AppColors.navy,

        )),

      ),

    );

  }



  Widget _buildDropdownToggle() {

    return Container(

      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),

      margin: const EdgeInsets.only(bottom: 4),

      decoration: BoxDecoration(color: AppColors.slateLight, borderRadius: BorderRadius.circular(AppRadius.sm)),

      child: Row(

        children: [

          Expanded(

            child: Text('🔽 નંબર પસંદગી (ડ્રોપડાઉન)',

                style: guFont(fontSize: 13, fontWeight: FontWeight.w700)),

          ),

          Switch(

            value: _quickPickMode,

            activeColor: Colors.white,

            activeTrackColor: AppColors.navyLight,

            onChanged: (v) {

              setState(() => _quickPickMode = v);

              context.read<AppState>().setQuickPickMode(v);

            },

          ),

        ],

      ),

    );

  }



  Widget _buildFormRow(List<SchoolClass> allowed) {

    return LayoutBuilder(builder: (context, constraints) {

      final narrow = constraints.maxWidth < 560;

      final classField = LabeledField(

        label: '🏫 ધોરણ પસંદ કરો',

        child: DropdownButtonFormField<String>(

          value: _selectedClass,

          isExpanded: true,

          style: guFont(fontSize: 14, fontWeight: FontWeight.w700),

          items: allowed

              .map((c) => DropdownMenuItem(value: c.key, child: Text(c.key)))

              .toList(),

          onChanged: _onClassChanged,

        ),

      );

      final dateField = LabeledField(

        label: '📅 તારીખ',

        child: Row(

          children: [

            _navBtn('◀ ગઈ', () => _changeDate(_selectedDate.subtract(const Duration(days: 1)))),

            const SizedBox(width: 6),

            _navBtn('આજ', () => _changeDate(DateTime.now()), highlight: true),

            const SizedBox(width: 6),

            Expanded(

              child: InkWell(

                onTap: _pickDate,

                child: Container(

                  padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),

                  decoration: BoxDecoration(

                    color: AppColors.slateLight,

                    border: Border.all(color: AppColors.border, width: 1.5),

                    borderRadius: BorderRadius.circular(AppRadius.sm),

                  ),

                  child: Text(_dateStr, textAlign: TextAlign.center, style: guFont(fontSize: 13, fontWeight: FontWeight.w700)),

                ),

              ),

            ),

            const SizedBox(width: 6),

            _navBtn('આવ ▶', () => _changeDate(_selectedDate.add(const Duration(days: 1)))),

          ],

        ),

      );



      if (narrow) {

        return Column(children: [classField, const SizedBox(height: 16), dateField, const SizedBox(height: 4)]);

      }

      return Padding(

        padding: const EdgeInsets.only(bottom: 4),

        child: Row(

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            Expanded(child: classField),

            const SizedBox(width: 16),

            Expanded(child: dateField),

          ],

        ),

      );

    });

  }



  Widget _navBtn(String label, VoidCallback onTap, {bool highlight = false}) {

    return InkWell(

      borderRadius: BorderRadius.circular(AppRadius.sm),

      onTap: onTap,

      child: Container(

        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),

        decoration: BoxDecoration(

          color: highlight ? AppColors.goldPale : Colors.white,

          border: Border.all(color: highlight ? AppColors.gold : AppColors.border, width: 1.5),

          borderRadius: BorderRadius.circular(AppRadius.sm),

        ),

        child: Text(label, style: guFont(fontSize: 12, fontWeight: FontWeight.w700), maxLines: 1),

      ),

    );

  }



  Widget _buildEntryForm() {

    final state = context.read<AppState>();

    final canSubmitClass = state.currentTeacher?.canAccessClass(_selectedClass ?? '') ?? false;



    if (_studentSelectionMode) {

      return StudentSelectionPanel(

        key: ValueKey('student-panel-$_selectedClass-$_dateStr-$_reloadTick'),

        className: _selectedClass!,

        date: _dateStr,

        registered: _registered,

        students: _students,

        enabled: !_isLocked,

        canSubmit: canSubmitClass,

        onReload: _loadRow,

        onSave: _saveStudentSelection,

      );

    }



    if (state.schoolType.toLowerCase() == 'coed') {

      return _buildCoedDirectEntryForm(canSubmitClass);

    }



    return Padding(

      padding: const EdgeInsets.only(top: 16),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.stretch,

        children: [

          InfoBanner(

            title: '📌 રજિસ્ટર્ડ વિદ્યાર્થીઓ (Columns C, D, E, F)',

            hint: '⚠️ હાજર ≤ રજિસ્ટર્ડ | પીએમ પોષણ ≤ હાજર | અલ્પાહાર ≤ હાજર',

            child: Wrap(

              spacing: 8,

              runSpacing: 8,

              crossAxisAlignment: WrapCrossAlignment.center,

              children: [

                for (final c in AppConfig.categories) StatChip(label: c.shortLabel, value: _registered[c]),

                StatChip(label: 'કુલ', value: _registered.total, total: true),

                IconButton(

                  tooltip: 'રજિસ્ટર્ડ સંખ્યા બદલવા માટે',

                  icon: const Icon(Icons.edit, size: 20, color: AppColors.navy),

                  onPressed: () async {

                    int sc = _registered[Category.sc], st = _registered[Category.st];

                    int obc = _registered[Category.obc], other = _registered[Category.other];

                    final ok = await showDialog<bool>(

                      context: context,

                      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {

                        return AlertDialog(

                          title: Text('✏️ રજિસ્ટર્ડ સંખ્યા બદલો', style: guFont(fontWeight: FontWeight.w800)),

                          content: Column(

                            mainAxisSize: MainAxisSize.min,

                            children: [

                              Row(children: [Expanded(child: LabeledField(label: 'SC', child: TextFormField(initialValue: '$sc', keyboardType: TextInputType.number, onChanged: (v) => sc = int.tryParse(v)??0))), const SizedBox(width: 10), Expanded(child: LabeledField(label: 'ST', child: TextFormField(initialValue: '$st', keyboardType: TextInputType.number, onChanged: (v) => st = int.tryParse(v)??0)))]),

                              const SizedBox(height: 10),

                              Row(children: [Expanded(child: LabeledField(label: 'OBC', child: TextFormField(initialValue: '$obc', keyboardType: TextInputType.number, onChanged: (v) => obc = int.tryParse(v)??0))), const SizedBox(width: 10), Expanded(child: LabeledField(label: 'અન્ય', child: TextFormField(initialValue: '$other', keyboardType: TextInputType.number, onChanged: (v) => other = int.tryParse(v)??0)))]),

                            ],

                          ),

                          actions: [

                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ કરો')),

                            AppButton(label: 'સેવ કરો', background: AppColors.greenDeep, onPressed: () => Navigator.pop(ctx, true)),

                          ],

                        );

                      }),

                    );

                    if (ok == true && mounted) {

                      setState(() => _saving = true);

                      try {

                        await context.read<AppState>().api!.saveRegistrationCounts(className: _selectedClass!, date: _dateStr, sc: sc, st: st, obc: obc, other: other);

                        await _loadRow();

                      } catch (_) { setState(() => _saving = false); }

                    }

                  },

                ),

                if (!_isLocked)

                  IconButton(

                    tooltip: 'રજિસ્ટર્ડ સંખ્યા બદલવા માટે',

                    icon: const Icon(Icons.edit, size: 20, color: AppColors.navy),

                    onPressed: () async {

                      int sc = _registered[Category.sc], st = _registered[Category.st];

                      int obc = _registered[Category.obc], other = _registered[Category.other];

                      final ok = await showDialog<bool>(

                        context: context,

                        builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {

                          return AlertDialog(

                            title: Text('✏️ રજિસ્ટર્ડ સંખ્યા બદલો', style: guFont(fontWeight: FontWeight.w800)),

                            content: Column(

                              mainAxisSize: MainAxisSize.min,

                              children: [

                                Row(children: [Expanded(child: LabeledField(label: 'SC', child: TextFormField(initialValue: '$sc', keyboardType: TextInputType.number, onChanged: (v) => sc = int.tryParse(v)??0))), const SizedBox(width: 10), Expanded(child: LabeledField(label: 'ST', child: TextFormField(initialValue: '$st', keyboardType: TextInputType.number, onChanged: (v) => st = int.tryParse(v)??0)))]),

                                const SizedBox(height: 10),

                                Row(children: [Expanded(child: LabeledField(label: 'OBC', child: TextFormField(initialValue: '$obc', keyboardType: TextInputType.number, onChanged: (v) => obc = int.tryParse(v)??0))), const SizedBox(width: 10), Expanded(child: LabeledField(label: 'અન્ય', child: TextFormField(initialValue: '$other', keyboardType: TextInputType.number, onChanged: (v) => other = int.tryParse(v)??0)))]),

                              ],

                            ),

                            actions: [

                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ કરો')),

                              AppButton(label: 'સેવ કરો', background: AppColors.greenDeep, onPressed: () => Navigator.pop(ctx, true)),

                            ],

                          );

                        }),

                      );

                      if (ok == true && mounted) {

                        setState(() => _saving = true);

                        try {

                          await context.read<AppState>().api!.saveRegistrationCounts(className: _selectedClass!, date: _dateStr, sc: sc, st: st, obc: obc, other: other);

                          await _loadRow();

                        } catch (_) { setState(() => _saving = false); }

                      }

                    },

                  ),

              ],

            ),

          ),

          const SectionTitleBar(text: '✅ હાજર વિદ્યાર્થીઓ'),

          _categoryGrid('present', _presentEdit, (c, v) {

            setState(() {

              _presentEdit.set(c, v);

              // Breakfast can never exceed total present; reset to 0 when

              // present drops below it, matching updateBreakfastDropdown().

              if (_breakfastEdit > _presentEdit.total) _breakfastEdit = 0;

            });

          }, maxOf: (c) => _registered[c]),

          TotalRow(label: 'કુલ હાજર:', value: _presentEdit.total),

          const SizedBox(height: 20),

          SectionTitleBar(text: '🍽️ પીએમ પોષણ (≤ હાજર)', borderColor: AppColors.gold),

          _categoryGrid('mdm', _mdmEdit, (c, v) {

            setState(() => _mdmEdit.set(c, v));

          }, maxOf: (c) => _presentEdit[c]),

          TotalRow(label: 'પીએમ પોષણ કુલ:', value: _mdmEdit.total),

          const SizedBox(height: 20),

          const SectionTitleBar(text: '🥐 અલ્પાહાર (≤ કુલ હાજર)', borderColor: AppColors.teal),
          _breakfastTypeSelector(),
          const SizedBox(height: 10),
          if (_breakfastEntryType == 'same_as_present')
            _buildCategoryBreakfastInputs(coed: false)
          else
            _buildTotalBreakfastInput(),

          const SizedBox(height: 20),

          if (_saveAlert != null)

            AlertBox(kind: _saveAlertIsError ? AlertKind.error : AlertKind.success, text: _saveAlert!),

          const SizedBox(height: 20),

          if (_isLocked)

            AlertBox(

              kind: AlertKind.lock,

              text: '🔒 12:01 PM પછી અથવા જૂની તારીખની હાજરીમાં ફેરફાર કરી શકાશે નહીં. '

                  'જો ફેરફાર કરવાની જરૂરત હોય તો કૃપા કરી આચાર્યશ્રીનો સંપર્ક કરો.',

            )

          else if (!canSubmitClass)

            AlertBox(kind: AlertKind.error, text: '🚫 તમને $_selectedClass માટે સબમિટ કરવાની પરવાનગી નથી.')

          else

            Wrap(

              spacing: 12,

              runSpacing: 12,

              children: [

                AppButton(

                  label: _saving

                      ? 'સેવ થાય છે…'

                      : (_isSubmitted ? '📝 ડેટા અપડેટ કરો' : '💾 સેવ કરો'),

                  loading: _saving,

                  onPressed: _saving ? null : _submit,

                ),

                AppResetButton(label: '↺ રીસેટ', onPressed: _saving ? null : _resetForm),

              ],

            ),

        ],

      ),

    );

  }



  Widget _buildCoedDirectEntryForm(bool canSubmitClass) {

    return Padding(

      padding: const EdgeInsets.only(top: 16),

      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        InfoBanner(

          title: '📌 નોંધાયેલ વિદ્યાર્થીઓ — દરેક કેટેગરીમાં Boys + Girls = Total',

          hint: 'જૂના રેકોર્ડનો gender split મળતો ન હોય તો તેને અંદાજથી વહેંચવામાં આવતો નથી.',

          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

            _buildCoedMetricInputs('registered'),

            const SizedBox(height: 8),

            Align(alignment: Alignment.centerLeft, child: AppButton(

              label: _saving ? 'સેવ થાય છે…' : '💾 નોંધણી સેવ કરો',

              background: AppColors.greenDeep,

              loading: _saving,

              onPressed: _saving || _isLocked ? null : _saveCoedRegistrationCounts,

            )),

          ]),

        ),

        const SizedBox(height: 18),

        const SectionTitleBar(text: '✅ હાજર વિદ્યાર્થીઓ — Boys + Girls = Total'),

        _buildCoedMetricInputs('present'),

        TotalRow(label: 'કુલ હાજર:', value: _presentEdit.total),

        const SizedBox(height: 18),

        SectionTitleBar(text: '🍽️ પીએમ પોષણ (≤ હાજર) — Boys + Girls = Total', borderColor: AppColors.gold),

        _buildCoedMetricInputs('mdm'),

        TotalRow(label: 'પીએમ પોષણ કુલ:', value: _mdmEdit.total),

        const SizedBox(height: 18),

        SectionTitleBar(text: '🥐 અલ્પાહાર (≤ હાજર) — Boys + Girls = Total', borderColor: AppColors.teal),
        _breakfastTypeSelector(),
        const SizedBox(height: 10),
        if (_breakfastEntryType == 'gender')
          _buildCoedBreakfastInputs()
        else if (_breakfastEntryType == 'same_as_present')
          _buildCategoryBreakfastInputs(coed: true)
        else
          _buildTotalBreakfastInput(coed: true),
        TotalRow(label: 'અલ્પાહાર કુલ:', value: _breakfastEdit),

        if (_genderNeedsEntry)

          const Padding(

            padding: EdgeInsets.only(top: 8),

            child: Text('નોંધ: આ તારીખના જૂના/અપૂર્ણ આંકડામાં Boys-Girls વિભાજન ઉપલબ્ધ નથી. સાચા બંને આંકડા દાખલ કરો; જૂના કુલમાંથી અનુમાન નહીં થાય.', style: TextStyle(fontSize: 12, color: Colors.deepOrange)),

          ),

        if (_saveAlert != null) AlertBox(kind: _saveAlertIsError ? AlertKind.error : AlertKind.success, text: _saveAlert!),

        const SizedBox(height: 20),

        if (_isLocked)

          AlertBox(kind: AlertKind.lock, text: '🔒 12:01 PM પછી અથવા જૂની તારીખની હાજરીમાં ફેરફાર કરી શકાશે નહીં. જો ફેરફાર જરૂરી હોય તો આચાર્યશ્રીનો સંપર્ક કરો.')

        else if (!canSubmitClass)

          AlertBox(kind: AlertKind.error, text: '🚫 તમને $_selectedClass માટે સબમિટ કરવાની પરવાનગી નથી.')

        else

          Wrap(spacing: 12, runSpacing: 12, children: [

            AppButton(label: _saving ? 'સેવ થાય છે…' : (_isSubmitted ? '📝 ડેટા અપડેટ કરો' : '💾 સેવ કરો'), loading: _saving, onPressed: _saving ? null : _submit),

            AppResetButton(label: '↺ રીસેટ', onPressed: _saving ? null : _resetForm),

          ]),

      ]),

    );

  }



  Widget _buildCoedMetricInputs(String metric) {

    String titleFor(String gender) => gender == 'BOYS' ? '👦 Boys' : '👧 Girls';

    int valueFor(String gender, Category category) => _genderValues[gender]![category.apiKey]![metric]!;

    int maxFor(String gender, Category category) {

      if (metric == 'registered') return 999999;

      if (metric == 'present') return _genderValues[gender]![category.apiKey]!['registered']!;

      return _genderValues[gender]![category.apiKey]!['present']!;

    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

      for (final category in AppConfig.categories)

        Card(

          margin: const EdgeInsets.only(bottom: 8),

          child: Padding(

            padding: const EdgeInsets.all(10),

            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              Text(category.shortLabel, style: guFont(fontWeight: FontWeight.w900, color: AppColors.navy)),

              const SizedBox(height: 8),

              LayoutBuilder(builder: (context, constraints) {

                final fieldWidth = constraints.maxWidth < 360 ? (constraints.maxWidth - 10) / 2 : 112.0;

                return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [

                  for (final gender in ['BOYS', 'GIRLS']) SizedBox(

                    width: fieldWidth,

                    child: QuickNumberField(

                      key: ValueKey('coed-$_selectedClass-$_dateStr-$_reloadTick-$gender-${category.apiKey}-$metric'),

                      label: titleFor(gender),

                      initialValue: valueFor(gender, category),

                      max: maxFor(gender, category),

                      quickPickMode: _quickPickMode,

                      enabled: !_isLocked,

                      onChanged: (v) => _setGenderValue(gender, category, metric, v),

                    ),

                  ),

                  Container(

                    constraints: BoxConstraints(minWidth: fieldWidth, minHeight: 46),

                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),

                    decoration: BoxDecoration(color: AppColors.greenBg, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(AppRadius.sm)),

                    child: Column(mainAxisSize: MainAxisSize.min, children: [

                      Text('TOTAL', style: guFont(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.teal)),

                      Text('${valueFor('BOYS', category) + valueFor('GIRLS', category)}', style: guFont(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.teal)),

                    ]),

                  ),

                ]);

              }),

            ]),

          ),

        ),

    ]);

  }



  Widget _buildCoedBreakfastInputs() {

    final boysPresent = AppConfig.categories.fold<int>(0, (n, c) => n + _genderValues['BOYS']![c.apiKey]!['present']!);

    final girlsPresent = AppConfig.categories.fold<int>(0, (n, c) => n + _genderValues['GIRLS']![c.apiKey]!['present']!);

    Widget field(String gender, int max) => SizedBox(

      width: 150,

      child: QuickNumberField(

        key: ValueKey('coed-breakfast-$_selectedClass-$_dateStr-$_reloadTick-$gender'),

        label: gender == 'BOYS' ? '👦 Boys' : '👧 Girls',

        initialValue: _genderBreakfast[gender] ?? 0,

        max: max,

        quickPickMode: _quickPickMode,

        enabled: !_isLocked,

        onChanged: (v) => _setGenderBreakfast(gender, v),

      ),

    );

    return Card(

      margin: const EdgeInsets.only(bottom: 8),

      child: Padding(

        padding: const EdgeInsets.all(10),

        child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [

          field('BOYS', boysPresent),

          field('GIRLS', girlsPresent),

          Container(

            constraints: const BoxConstraints(minWidth: 120, minHeight: 46),

            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),

            decoration: BoxDecoration(color: AppColors.greenBg, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(AppRadius.sm)),

            child: Column(mainAxisSize: MainAxisSize.min, children: [

              Text('TOTAL', style: guFont(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.teal)),

              Text('$_breakfastEdit', style: guFont(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.teal)),

            ]),

          ),

        ]),

      ),

    );

  }



  Future<void> _saveCoedRegistrationCounts() async {

    final issues = <String>[];

    for (final c in AppConfig.categories) {

      final key = c.apiKey;

      final boys = _genderValues['BOYS']![key]!;

      final girls = _genderValues['GIRLS']![key]!;

      if (boys['present']! > boys['registered']! || girls['present']! > girls['registered']!) issues.add('${c.shortLabel}: હાજર નોંધણી કરતાં વધારે છે.');

      if (boys['mdm']! > boys['present']! || girls['mdm']! > girls['present']!) issues.add('${c.shortLabel}: PM Poshan હાજર કરતાં વધારે છે.');

    }

    if (issues.isNotEmpty) {

      setState(() { _saveAlertIsError = true; _saveAlert = issues.join('\n'); });

      return;

    }

    setState(() { _saving = true; _saveAlert = null; });

    try {

      final res = await SupabaseAttendanceService().saveAttendance(
        className: _selectedClass!,
        date: _dateStr,
        registered: _registered,
        present: _presentEdit,
        mdm: _mdmEdit,
        breakfastTotal: _breakfastEdit,
        genderBreakdown: _genderBreakdownPayload(),
      );

      if (!mounted) return;

      if (res['result'] == 'success') {

        setState(() { _saving = false; _saveAlertIsError = false; _saveAlert = '✅ નોંધણીના Boys / Girls / Total આંકડા સાચવાયા.'; _genderNeedsEntry = false; _isSubmitted = res['attendanceSaved'] == true || _isSubmitted; });

        await _loadRow();

      } else {

        setState(() { _saving = false; _saveAlertIsError = true; _saveAlert = '❌ ${res['message'] ?? 'નોંધણી સેવ કરવામાં ભૂલ.'}'; });

      }

    } catch (e) {

      if (!mounted) return;

      setState(() { _saving = false; _saveAlertIsError = true; _saveAlert = '❌ $e'; });

    }

  }



  Widget _buildGenderEntry() {

    final schoolType = context.read<AppState>().schoolType;

    final genders = schoolType == 'boys' ? const ['BOYS'] : schoolType == 'girls' ? const ['GIRLS'] : const ['BOYS', 'GIRLS'];

    return Column(

      crossAxisAlignment: CrossAxisAlignment.stretch,

      children: [

        for (final category in AppConfig.categories)

          Card(

            margin: const EdgeInsets.only(bottom: 10),

            child: Padding(

              padding: const EdgeInsets.all(10),

              child: Column(

                crossAxisAlignment: CrossAxisAlignment.start,

                children: [

                  Text(category.shortLabel, style: guFont(fontWeight: FontWeight.w900, color: AppColors.navy)),

                  const SizedBox(height: 8),

                  for (final gender in genders)

                    Padding(

                      padding: const EdgeInsets.only(bottom: 8),

                      child: Column(

                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [

                          Text(gender == 'BOYS' ? '👦 Boys' : '👧 Girls', style: guFont(fontWeight: FontWeight.w800)),

                          const SizedBox(height: 4),

                          Wrap(

                            spacing: 8,

                            runSpacing: 8,

                            children: [

                              for (final metric in ['registered','present','mdm'])

                                SizedBox(

                                  width: 118,

                                  child: QuickNumberField(

                                    key: ValueKey('gender-$_selectedClass-$_dateStr-$_reloadTick-$gender-${category.apiKey}-$metric'),

                                    label: metric == 'registered' ? 'Registered' : metric == 'present' ? 'Present' : metric == 'mdm' ? 'PM Poshan' : 'Breakfast',

                                    initialValue: _genderValues[gender]![category.apiKey]![metric]!,

                                    max: metric == 'registered' ? _registered[category] : metric == 'present' ? _genderValues[gender]![category.apiKey]!['registered']! : metric == 'mdm' ? _genderValues[gender]![category.apiKey]!['present']! : _genderValues[gender]![category.apiKey]!['present']!,

                                    quickPickMode: _quickPickMode,

                                    enabled: !_isLocked,

                                    onChanged: (v) => _setGenderValue(gender, category, metric, v),

                                  ),

                                ),

                            ],

                          ),

                        ],

                      ),

                    ),

                ],

              ),

            ),

          ),

        const Text('દરેક કેટેગરીમાં Boys + Girls = Total હોવું જરૂરી છે. Breakfast શાળા-કુલ માટે અલગ Boys / Girls / Total છે.', style: TextStyle(fontSize: 12, color: AppColors.slate)),

        if (schoolType.toLowerCase() == 'coed') ...[const SizedBox(height: 8), _buildCoedBreakfastInputs()],

      ],

    );

  }



  Widget _categoryGrid(

    String gridId,

    CategoryCounts values,

    void Function(Category, int) onChange, {

    required int Function(Category) maxOf,

  }) {

    Widget buildField(Category c) => QuickNumberField(

          key: ValueKey('$gridId-${c.apiKey}-$_selectedClass-$_dateStr-$_reloadTick-$_isLocked'),

          label: c.shortLabel,

          initialValue: values[c],

          max: maxOf(c),

          quickPickMode: _quickPickMode,

          enabled: !_isLocked,

          onChanged: (v) => onChange(c, v),

        );



    return LayoutBuilder(builder: (context, constraints) {

      const cats = AppConfig.categories;

      if (constraints.maxWidth < 420) {

        return Column(

          mainAxisSize: MainAxisSize.min,

          children: [

            Row(

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                Expanded(child: buildField(cats[0])),

                const SizedBox(width: 12),

                Expanded(child: buildField(cats[1])),

              ],

            ),

            const SizedBox(height: 12),

            Row(

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                Expanded(child: buildField(cats[2])),

                const SizedBox(width: 12),

                Expanded(child: buildField(cats[3])),

              ],

            ),

          ],

        );

      }

      return Row(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          for (int i = 0; i < cats.length; i++) ...[

            if (i > 0) const SizedBox(width: 12),

            Expanded(child: buildField(cats[i])),

          ],

        ],

      );

    });

  }

}

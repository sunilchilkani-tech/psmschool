// FLN 130-question paper / workbook generator (teacher and admin).
//
// - School name comes only from the school registration (not editable here).
// - Students come from the database (teachers: their own standard; admin:
//   every class).
// - Output is PDF only. Papers can be printed with or without student names;
//   the school name is always printed.
// - Proper A4 page setup with page-wise spacing (gap between questions and
//   between a question and its options) so teachers get a clean print.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fln/fln_data.dart';
import '../fln/fln_engine.dart';
import '../fln/fln_job.dart';
import '../fln/fln_layout.dart';
import '../fln/fln_render.dart';
import '../services/attendance_roster_service.dart';
import '../services/class_label.dart';
import '../services/firebase_backend_client.dart';
import '../services/psm_file_export_helper.dart';
import '../services/school_name_language_service.dart';
import '../services/supabase_hajari_patrak_service.dart';
import '../theme/responsive.dart';

/// Where the FLN screen reads the school, classes and students from.
class FlnWorkbookDataSource {
  const FlnWorkbookDataSource();

  Future<List<Map<String, dynamic>>> classes() => SupabaseHajariPatrakService().getClasses();
  Future<Map<String, dynamic>> schoolMeta() => SupabaseHajariPatrakService().getSchoolMetadata();
  Future<String> schoolRef() => SupabaseHajariPatrakService().currentSchoolRef();

  /// null = every class (admin); otherwise the teacher's class ids.
  Future<Set<String>?> allowedClassIds() async {
    try {
      final allowed = await Supabase.instance.client.rpc('psm_attendance_class_ids');
      if (allowed is List) return allowed.map((e) => '$e').toSet();
    } catch (_) {}
    return null;
  }

  Future<List<Map<String, dynamic>>> students(String classId) =>
      AttendanceRosterService().loadActiveRoster(classId);
}

class FlnWorkbookScreen extends StatefulWidget {
  const FlnWorkbookScreen({super.key, required this.profile, this.dataSource = const FlnWorkbookDataSource()});

  final Map<String, dynamic> profile;
  final FlnWorkbookDataSource dataSource;

  @override
  State<FlnWorkbookScreen> createState() => _FlnWorkbookScreenState();
}

class _FlnWorkbookScreenState extends State<FlnWorkbookScreen> {
  static const String _prefsKey = 'fln130_workbook_settings_v1';
  static Future<void>? _fontsLoading;

  FlnWorkbookDataSource get _data => widget.dataSource;

  bool _loading = true;
  String? _error;
  String _schoolRef = '';
  Map<String, dynamic> _schoolMeta = <String, dynamic>{};
  String _language = SchoolNameLanguageService.gujarati;

  List<Map<String, dynamic>> _classes = <Map<String, dynamic>>[];
  String? _classId;
  bool _studentsLoading = false;
  List<Map<String, dynamic>> _students = <Map<String, dynamic>>[];
  final Set<String> _studentIds = <String>{};

  // Paper options
  bool _printNames = true;
  bool _printClass = true;
  int _paperCount = 30;
  /// null = every student gets a new paper; 1..4 = papers in sets.
  int? _setCount;
  bool _previewAnswers = false;
  List<FlnItem>? _examples;
  String _examplesKey = '';
  int _seed = DateTime.now().millisecondsSinceEpoch % 90000 + 10000;
  FlnEngineConfig _engine = const FlnEngineConfig();
  final Set<int> _selected = <int>{for (var q = 1; q <= 130; q++) q};
  bool _shuffleSection = true;
  bool _shuffleAll = false;
  bool _shuffleOptions = true;
  FlnLayoutSettings _layout = FlnLayoutSettings();

  // Preview
  int _previewPaper = 1;
  double _zoom = 1.0;
  FlnJob? _job;
  String _jobKey = '';
  List<FlnPageLayout> _previewPages = <FlnPageLayout>[];
  String _previewKey = '';
  String _questionSearch = '';

  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _rangeCtrl = TextEditingController();
  Timer? _saveTimer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _titleCtrl.dispose();
    _rangeCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  static Future<void> _ensureFonts() => _fontsLoading ??= () async {
        final loader = FontLoader(FlnText.family)
          ..addFont(rootBundle.load('assets/fonts/NotoSansGujarati-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/NotoSansGujarati-Bold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/NotoSansGujarati-ExtraBold.ttf'));
        await loader.load();
        FlnText.instance.clear();
      }();

  String _text(dynamic v) {
    final t = (v ?? '').toString().trim();
    return t.toLowerCase() == 'null' ? '' : t;
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _loadPrefs();
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        _ensureFonts(),
        _data.classes(),
        _data.schoolMeta(),
        _data.schoolRef(),
      ]);
      var classes = (results[1] as List<Map<String, dynamic>>);
      final meta = results[2] as Map<String, dynamic>;
      final schoolRef = _text(results[3]);
      // Teachers: only the classes they may take attendance for (their own
      // standard, all sections). Admin: whole school.
      final allowedIds = await _data.allowedClassIds();
      if (allowedIds != null) {
        classes = classes.where((c) => allowedIds.contains(_text(c['id']))).toList();
      }
      final language = await SchoolNameLanguageService.loadLanguage(schoolRef: schoolRef);
      if (!mounted) return;
      final savedClass = _classId;
      setState(() {
        _classes = classes;
        _schoolMeta = meta;
        _schoolRef = schoolRef;
        _language = language;
        _classId = classes.any((c) => _text(c['id']) == savedClass)
            ? savedClass
            : (classes.isEmpty ? null : _text(classes.first['id']));
        _loading = false;
      });
      if (_classId != null) await _loadStudents();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'માહિતી લોડ થઈ શકી નથી: $e';
      });
    }
  }

  Future<void> _loadStudents() async {
    final id = _classId;
    if (id == null) return;
    setState(() => _studentsLoading = true);
    try {
      final rows = List<Map<String, dynamic>>.of(await _data.students(id));
      rows.sort((a, b) {
        final ra = int.tryParse(_text(a['roll_number']));
        final rb = int.tryParse(_text(b['roll_number']));
        if (ra != null && rb != null) return ra.compareTo(rb);
        return _text(a['roll_number']).compareTo(_text(b['roll_number']));
      });
      if (!mounted || id != _classId) return;
      setState(() {
        _students = rows;
        _studentIds
          ..clear()
          ..addAll(rows.map((r) => _text(r['id'])));
        if (rows.isNotEmpty && !_printNames) _paperCount = rows.length;
        _studentsLoading = false;
        _previewPaper = 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _students = <Map<String, dynamic>>[];
        _studentsLoading = false;
      });
      _snack('વિદ્યાર્થીઓ લોડ થઈ શક્યા નથી: $e');
    }
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) {
        _titleCtrl.text = _layout.examTitle;
        return;
      }
      final j = jsonDecode(raw);
      if (j is! Map) return;
      final m = Map<String, dynamic>.from(j);
      if (m['layout'] is Map) _layout = FlnLayoutSettings.fromJson(Map<String, dynamic>.from(m['layout'] as Map));
      if (m['engine'] is Map) _engine = FlnEngineConfig.fromJson(Map<String, dynamic>.from(m['engine'] as Map));
      final sel = m['selected'];
      if (sel is List && sel.isNotEmpty) {
        _selected
          ..clear()
          ..addAll(sel.map((e) => int.tryParse('$e') ?? 0).where((q) => q >= 1 && q <= 130));
      }
      _shuffleSection = m['shuffleSection'] != false;
      _shuffleAll = m['shuffleAll'] == true;
      _shuffleOptions = m['shuffleOptions'] != false;
      final sc = int.tryParse('${m['setCount'] ?? ''}');
      _setCount = (sc != null && sc >= 1 && sc <= 4) ? sc : (m['differentPerPaper'] == false ? 1 : null);
      _printNames = m['printNames'] != false;
      _printClass = m['printClass'] != false;
      final pc = int.tryParse('${m['paperCount'] ?? ''}');
      if (pc != null) _paperCount = pc.clamp(1, 500);
      final seed = int.tryParse('${m['seed'] ?? ''}');
      if (seed != null && seed > 0) _seed = seed;
      final cid = _text(m['classId']);
      if (cid.isNotEmpty) _classId = cid;
    } catch (_) {}
    _titleCtrl.text = _layout.examTitle;
  }

  void _savePrefsSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _prefsKey,
          jsonEncode(<String, dynamic>{
            'layout': _layout.toJson(),
            'engine': _engine.toJson(),
            'selected': _selected.toList()..sort(),
            'shuffleSection': _shuffleSection,
            'shuffleAll': _shuffleAll,
            'shuffleOptions': _shuffleOptions,
            'setCount': _setCount,
            'printNames': _printNames,
            'printClass': _printClass,
            'paperCount': _paperCount,
            'seed': _seed,
            'classId': _classId,
          }),
        );
      } catch (_) {}
    });
  }

  /// Applies a change, refreshes the preview and remembers the settings.
  void _update(VoidCallback change) {
    setState(change);
    _savePrefsSoon();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------------------------------------------------------------------
  // Derived data
  // ---------------------------------------------------------------------------

  String get _schoolName => SchoolNameLanguageService.resolveSchoolName(
        language: _language,
        profile: widget.profile,
        schoolConfig: _schoolMeta,
      );

  Map<String, dynamic>? get _class {
    for (final c in _classes) {
      if (_text(c['id']) == _classId) return c;
    }
    return null;
  }

  String _classLabel(Map<String, dynamic>? c) {
    if (c == null) return '';
    for (final k in const <String>['label', 'class_key', 'sheet_name']) {
      final t = _text(c[k]);
      if (t.isNotEmpty) return t;
    }
    final std = _text(c['standard']);
    final sec = _text(c['section']);
    return sec.isEmpty ? std : '$std-$sec';
  }

  List<Map<String, dynamic>> get _chosenStudents =>
      _students.where((s) => _studentIds.contains(_text(s['id']))).toList();

  List<FlnHeaderInfo> get _headers {
    final school = _schoolName;
    final cls = _printClass ? _classLabel(_class) : '';
    if (_printNames) {
      return <FlnHeaderInfo>[
        for (final s in _chosenStudents)
          FlnHeaderInfo(
            schoolName: school,
            studentName: _text(s['name']),
            rollNo: _text(s['roll_number']),
            classLabel: cls,
          ),
      ];
    }
    return List<FlnHeaderInfo>.generate(_paperCount, (_) => FlnHeaderInfo(schoolName: school, classLabel: cls));
  }

  FlnJob? _currentJob() {
    final headers = _headers;
    if (headers.isEmpty || _selected.isEmpty) return null;
    final key = jsonEncode(<Object>[
      _seed,
      _engine.toJson(),
      (_selected.toList()..sort()),
      _setCount ?? 0,
      _shuffleSection,
      _shuffleAll,
      _shuffleOptions,
      <String>[for (final h in headers) '${h.schoolName}|${h.studentName}|${h.rollNo}|${h.classLabel}'],
    ]);
    if (_job == null || key != _jobKey) {
      _job = FlnJob(
        seed: _seed,
        engine: _engine,
        selected: Set<int>.of(_selected),
        setCount: _setCount,
        shuffleWithinSection: _shuffleSection,
        shuffleAll: _shuffleAll,
        shuffleOptions: _shuffleOptions,
        headers: headers,
        layout: _layout,
      );
      _jobKey = key;
      _previewKey = '';
    }
    return _job;
  }

  List<FlnPageLayout> _pagesForPreview() {
    final job = _currentJob();
    if (job == null) return const <FlnPageLayout>[];
    final paper = _previewPaper.clamp(1, job.paperCount);
    final key = '$_jobKey|$paper|$_previewAnswers|${jsonEncode(_layout.toJson())}';
    if (key != _previewKey) {
      try {
        _previewPages = _previewAnswers
            ? job.answerPages(paper, generic: job.inSets)
            : job.questionPages(paper);
      } catch (e) {
        _previewPages = <FlnPageLayout>[];
        _error = 'Preview error: $e';
      }
      _previewKey = key;
    }
    return _previewPages;
  }

  // ---------------------------------------------------------------------------
  // PDF
  // ---------------------------------------------------------------------------

  Future<void> _downloadPdf() async {
    if (_busy) return;
    if (_selected.isEmpty) {
      _snack('ઓછામાં ઓછો એક પ્રશ્ન પસંદ કરો.');
      return;
    }
    final job = _currentJob();
    if (job == null) {
      _snack(_printNames ? 'ઓછામાં ઓછો એક વિદ્યાર્થી પસંદ કરો.' : 'પેપરની સંખ્યા લખો.');
      return;
    }
    final status = ValueNotifier<String>('પાનાં ગોઠવાય છે…');
    final progress = ValueNotifier<double?>(null);
    setState(() => _busy = true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('PDF બને છે'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ValueListenableBuilder<String>(valueListenable: status, builder: (_, v, __) => Text(v)),
            const SizedBox(height: 12),
            ValueListenableBuilder<double?>(
              valueListenable: progress,
              builder: (_, v, __) => LinearProgressIndicator(value: v),
            ),
          ],
        ),
      ),
    );
    try {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final cls = ClassLabel.bare(_classLabel(_class)).replaceAll(RegExp(r'[^\w\-]+'), '_');
      final base = 'FLN130_${cls.isEmpty ? 'class' : cls}${_layout.examDate.isEmpty ? '' : '_${_layout.examDate.replaceAll('/', '-')}'}';
      final files = <(String, Uint8List, int)>[];
      for (final answers in const <bool>[false, true]) {
        final what = answers ? 'જવાબવાળી PDF' : 'પ્રશ્નપત્ર PDF';
        final pages = answers
            ? await job.answerPagesAll(onProgress: (p) {
                status.value = '$what: પાનાં ગોઠવાય છે… ${(p * 100).round()}%';
                progress.value = p;
              })
            : await job.questionPagesAll(onProgress: (p) {
                status.value = '$what: પાનાં ગોઠવાય છે… ${(p * 100).round()}%';
                progress.value = p;
              });
        final bytes = await FlnPdfBuilder.build(
          pages,
          title: '${_layout.examTitle}${answers ? ' — જવાબ સાથે' : ''}',
          onProgress: (stage, p) {
            status.value = stage == 'text'
                ? '$what: ગુજરાતી લખાણ… ${(p * 100).round()}%'
                : stage == 'pages'
                    ? '$what: પાનાં બને છે… ${(p * 100).round()}% (કુલ ${pages.length})'
                    : '$what: સેવ થાય છે…';
            progress.value = stage == 'save' ? null : p;
          },
        );
        files.add((answers ? '${base}_Answers.pdf' : '${base}_Questions.pdf', bytes, pages.length));
      }
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      for (final f in files) {
        await PsmFileExportHelper.saveOrShare(bytes: f.$2, filename: f.$1, title: f.$1, mimeType: 'application/pdf');
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
      _snack('બે PDF તૈયાર: પ્રશ્નપત્ર (${files[0].$3} પાનાં) અને જવાબ સાથે (${files[1].$3} પાનાં)');
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      _snack('PDF બની શકી નથી: $e');
    } finally {
      status.dispose();
      progress.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FLN 130 પ્રશ્નપત્ર / સ્વાધ્યાયપોથી'),
        actions: <Widget>[
          IconButton(
            tooltip: 'નવો સેટ (નવી સંખ્યાઓ)',
            onPressed: _loading ? null : () => _update(() => _seed = DateTime.now().millisecondsSinceEpoch % 90000 + 10000),
            icon: const Icon(Icons.casino_outlined),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: FilledButton.icon(
              onPressed: _loading || _busy ? null : _downloadPdf,
              icon: const Icon(Icons.picture_as_pdf_rounded),
              label: const Text('PDF ડાઉનલોડ (પ્રશ્ન + જવાબ)'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _classes.isEmpty
              ? _errorView()
              : LayoutBuilder(builder: (context, c) {
                  if (c.maxWidth >= 1000) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        SizedBox(width: 400, child: _settingsTabs()),
                        const VerticalDivider(width: 1),
                        Expanded(child: _previewPane()),
                      ],
                    );
                  }
                  return DefaultTabController(
                    length: 4,
                    child: Column(
                      children: <Widget>[
                        const TabBar(isScrollable: true, tabs: <Widget>[
                          Tab(text: 'વિદ્યાર્થી'),
                          Tab(text: 'પ્રશ્નો'),
                          Tab(text: 'પાનું સેટઅપ'),
                          Tab(text: 'પૂર્વાવલોકન'),
                        ]),
                        Expanded(
                          child: TabBarView(children: <Widget>[
                            _studentsTab(),
                            _questionsTab(),
                            _pageTab(),
                            _previewPane(),
                          ]),
                        ),
                      ],
                    ),
                  );
                }),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text(_error ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _init, child: const Text('ફરી પ્રયાસ કરો')),
          ]),
        ),
      );

  Widget _settingsTabs() => DefaultTabController(
        length: 3,
        child: Column(children: <Widget>[
          const TabBar(tabs: <Widget>[
            Tab(text: 'વિદ્યાર્થી'),
            Tab(text: 'પ્રશ્નો'),
            Tab(text: 'પાનું સેટઅપ'),
          ]),
          Expanded(child: TabBarView(children: <Widget>[_studentsTab(), _questionsTab(), _pageTab()])),
        ]),
      );

  Widget _section(String title, List<Widget> children, {IconData? icon}) => Card(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Row(children: <Widget>[
              if (icon != null) ...<Widget>[Icon(icon, size: 18), const SizedBox(width: 6)],
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );

  // ----------------------------- Students tab --------------------------------

  Widget _studentsTab() {
    final cls = _class;
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: <Widget>[
      _section('શાળા (નોંધણી મુજબ)', icon: Icons.lock_outline, <Widget>[
        Text(_schoolName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          'શાળાનું નામ શાળા નોંધણીમાંથી આવે છે અને દરેક પેપર પર છપાય છે. અહીં બદલી શકાતું નથી.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const <ButtonSegment<String>>[
            ButtonSegment<String>(value: 'gu', label: Text('ગુજરાતી નામ')),
            ButtonSegment<String>(value: 'en', label: Text('English name')),
          ],
          selected: <String>{_language},
          onSelectionChanged: (v) async {
            final lang = v.first;
            setState(() => _language = lang);
            await SchoolNameLanguageService.saveLanguage(schoolRef: _schoolRef, language: lang);
          },
        ),
      ]),
      _section('વર્ગ અને વિદ્યાર્થીઓ', icon: Icons.groups_rounded, <Widget>[
        if (_classes.isEmpty)
          const Text('તમારા માટે કોઈ વર્ગ ઉપલબ્ધ નથી.')
        else
          DropdownButtonFormField<String>(
            value: _classId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'ધોરણ / વર્ગ', border: OutlineInputBorder(), isDense: true),
            items: <DropdownMenuItem<String>>[
              for (final c in _classes)
                DropdownMenuItem<String>(value: _text(c['id']), child: Text(_classLabel(c))),
            ],
            onChanged: (v) {
              if (v == null || v == _classId) return;
              _update(() => _classId = v);
              _loadStudents();
            },
          ),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('વિદ્યાર્થીનું નામ છાપો'),
          subtitle: Text(_printNames
              ? 'દરેક વિદ્યાર્થીનું અલગ પેપર, નામ અને રોલ નંબર સાથે.'
              : 'નામ અને રોલ નંબર માટે ખાલી લીટી (શાળાનું નામ છપાશે).'),
          value: _printNames,
          onChanged: (v) => _update(() {
            _printNames = v;
            if (!v && _students.isNotEmpty) _paperCount = _students.length;
            _previewPaper = 1;
          }),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('ધોરણ / વર્ગ છાપો'),
          subtitle: Text(cls == null ? '' : _classLabel(cls)),
          value: _printClass,
          onChanged: (v) => _update(() => _printClass = v),
        ),
        if (_studentsLoading)
          const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
        else if (_printNames) ...<Widget>[
          TitleWithActions(
            title: Text('${_studentIds.length} / ${_students.length} વિદ્યાર્થી પસંદ',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            actions: [
              TextButton(
              onPressed: () => _update(() => _studentIds.addAll(_students.map((s) => _text(s['id'])))),
              child: const Text('બધા'),
            ),
              TextButton(onPressed: () => _update(_studentIds.clear), child: const Text('કોઈ નહીં')),
            ],
          ),
          if (_students.isEmpty)
            const Text('આ વર્ગમાં કોઈ સક્રિય વિદ્યાર્થી નથી.')
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 340),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _students.length,
                itemBuilder: (_, i) {
                  final s = _students[i];
                  final id = _text(s['id']);
                  return CheckboxListTile(
                    dense: true,
                    value: _studentIds.contains(id),
                    title: Text(_text(s['name'])),
                    secondary: Text(_text(s['roll_number'])),
                    onChanged: (v) => _update(() => v == true ? _studentIds.add(id) : _studentIds.remove(id)),
                  );
                },
              ),
            ),
        ] else
          _stepper(
            'પેપરની સંખ્યા',
            _paperCount.toDouble(),
            1,
            500,
            1,
            (v) => _update(() => _paperCount = v.round()),
            format: (v) => '${v.round()}',
            trailing: _students.isEmpty
                ? null
                : TextButton(
                    onPressed: () => _update(() => _paperCount = _students.length),
                    child: Text('= વર્ગ (${_students.length})'),
                  ),
          ),
      ]),
      _section('પરીક્ષા', icon: Icons.edit_note_rounded, <Widget>[
        TextField(
          controller: _titleCtrl,
          decoration: const InputDecoration(labelText: 'શીર્ષક', border: OutlineInputBorder(), isDense: true),
          onChanged: (v) => _update(() => _layout.examTitle = v.trim().isEmpty ? 'FLN ગણિત મૂલ્યાંકન સ્વાધ્યાયપોથી' : v.trim()),
        ),
        const SizedBox(height: 10),
        Row(children: <Widget>[
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(_layout.examDate.isEmpty ? 'તારીખ (ખાલી લીટી)' : _layout.examDate),
              onPressed: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: now,
                  firstDate: DateTime(now.year - 2),
                  lastDate: DateTime(now.year + 2),
                );
                if (d != null) {
                  _update(() => _layout.examDate =
                      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}');
                }
              },
            ),
          ),
          if (_layout.examDate.isNotEmpty)
            IconButton(
              tooltip: 'તારીખ કાઢો',
              onPressed: () => _update(() => _layout.examDate = ''),
              icon: const Icon(Icons.clear),
            ),
        ]),
      ]),
      _section('પેપરનો પ્રકાર', icon: Icons.shuffle_rounded, <Widget>[
        SegmentedButton<bool>(
          segments: const <ButtonSegment<bool>>[
            ButtonSegment<bool>(value: false, icon: Icon(Icons.person_rounded), label: Text('દરેકને નવું પેપર')),
            ButtonSegment<bool>(value: true, icon: Icon(Icons.layers_rounded), label: Text('સેટ મુજબ')),
          ],
          selected: <bool>{_setCount != null},
          onSelectionChanged: (v) => _update(() => _setCount = v.first ? (_setCount ?? 1) : null),
        ),
        const SizedBox(height: 6),
        if (_setCount == null)
          Text(
            'દરેક વિદ્યાર્થીને અલગ સંખ્યાઓવાળું પેપર મળશે (પાસે બેઠેલા નકલ ન કરી શકે). પેપર પર નંબર કે સેટ છપાશે નહીં.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else ...<Widget>[
          _dropdown<int>('સેટની સંખ્યા', _setCount!, const <(int, String)>[
            (1, '1 સેટ — બધા વિદ્યાર્થીઓને એક જ પેપર (સેટ A)'),
            (2, '2 સેટ — A, B વારાફરતી'),
            (3, '3 સેટ — A, B, C વારાફરતી'),
            (4, '4 સેટ — A, B, C, D વારાફરતી'),
          ], (v) => _update(() => _setCount = v)),
          Text(
            'એક જ સેટના બધા વિદ્યાર્થીઓનું પેપર સરખું રહેશે અને પેપર પર "સેટ A/B…" છપાશે. જવાબવાળી PDF માં દરેક સેટની એક નકલ આવશે.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 6),
        Row(children: <Widget>[
          Expanded(
            child: Text('સેટ કોડ: $_seed',
                style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          ),
          TextButton.icon(
            onPressed: _askSetCode,
            icon: const Icon(Icons.history, size: 18),
            label: const Text('કોડથી ફરી બનાવો'),
          ),
        ]),
        Text(
          'સેટ કોડ નોંધી રાખો: એ જ કોડ અને એ જ પસંદગીથી એ જ પેપર અને ઉત્તરવહી ફરી બને છે.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ]),
    ]);
  }

  Future<void> _askSetCode() async {
    final ctrl = TextEditingController(text: '$_seed');
    final code = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('સેટ કોડ'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ કરો')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
            child: const Text('લાગુ કરો'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (code != null && code > 0) _update(() => _seed = code);
  }

  // ----------------------------- Questions tab -------------------------------

  Widget _questionsTab() {
    final q = _questionSearch.trim().toLowerCase();
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: <Widget>[
      _section('પ્રશ્નો પસંદ કરો (${_selected.length} / 130)', icon: Icons.checklist_rounded, <Widget>[
        Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
          for (final p in const <(String, String)>[
            ('all', 'બધા 130'),
            ('balanced15', '15 પ્રશ્ન (દરેક વિભાગમાંથી 1)'),
            ('balanced30', '30 પ્રશ્ન (2-2)'),
            ('balanced50', '50 પ્રશ્ન'),
            ('num_only', 'સંખ્યા (Q1–59)'),
            ('ops_only', 'ચાર ક્રિયા (Q60–119)'),
            ('wp_only', 'કોયડા (Q120–130)'),
          ])
            ActionChip(
              label: Text(p.$2),
              onPressed: () => _update(() {
                _selected
                  ..clear()
                  ..addAll(flnPreset(p.$1, DateTime.now().microsecondsSinceEpoch));
              }),
            ),
          ActionChip(
            avatar: const Icon(Icons.clear, size: 16),
            label: const Text('બધું કાઢો'),
            onPressed: () => _update(_selected.clear),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: <Widget>[
          Expanded(
            child: TextField(
              controller: _rangeCtrl,
              decoration: const InputDecoration(
                labelText: 'પ્રશ્ન નંબર / શ્રેણી',
                hintText: 'દા.ત. 1-8, 17, 60-65, 120-130',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: () {
              final set = flnParseRange(_rangeCtrl.text);
              if (set.isEmpty) {
                _snack('માન્ય પ્રશ્ન નંબર લખો (1 થી 130).');
                return;
              }
              _update(() => _selected
                ..clear()
                ..addAll(set));
            },
            child: const Text('લાગુ'),
          ),
        ]),
        const SizedBox(height: 10),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'શોધો (Q નંબર, વિભાગ, લખાણ)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _questionSearch = v),
        ),
      ]),
      for (final m in kFlnSections) _sectionPicker(m, q),
      _section('ક્રમ બદલવો (નકલ અટકાવવા)', icon: Icons.swap_vert_rounded, <Widget>[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('વિભાગની અંદર પ્રશ્નોનો ક્રમ બદલો'),
          value: _shuffleSection,
          onChanged: _shuffleAll ? null : (v) => _update(() => _shuffleSection = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('બધા પ્રશ્નોનો ક્રમ બદલો'),
          subtitle: const Text('વિભાગ શીર્ષક વગર, દરેક પ્રશ્નમાં સૂચના સાથે.'),
          value: _shuffleAll,
          onChanged: (v) => _update(() => _shuffleAll = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('વિકલ્પો (A, B, C, D) નો ક્રમ બદલો'),
          value: _shuffleOptions,
          onChanged: (v) => _update(() => _shuffleOptions = v),
        ),
      ]),
      _section('પ્રશ્ન બનાવવાના નિયમો', icon: Icons.rule_rounded, <Widget>[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('વદ્દી / દશકાના સ્તર મુજબ કડક નિયમ (Q60–Q104)'),
          value: _engine.strictCarry,
          onChanged: (v) => _update(() => _engine = FlnEngineConfig(
                strictCarry: v,
                finalProfile: _engine.finalProfile,
                q130Additive: _engine.q130Additive,
              )),
        ),
        DropdownButtonFormField<bool>(
          value: _engine.finalProfile,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'અંકોની પ્રોફાઇલ (Q17–Q59)', border: OutlineInputBorder(), isDense: true),
          items: const <DropdownMenuItem<bool>>[
            DropdownMenuItem<bool>(value: true, child: Text('QUESTION final.xlsx (1 થી 4 અંક)')),
            DropdownMenuItem<bool>(value: false, child: Text('3000_FLN (2 થી 5 અંક)')),
          ],
          onChanged: (v) => _update(() => _engine = FlnEngineConfig(
                strictCarry: _engine.strictCarry,
                finalProfile: v ?? true,
                q130Additive: _engine.q130Additive,
              )),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<bool>(
          value: _engine.q130Additive,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Q130 નું સૂત્ર', border: OutlineInputBorder(), isDense: true),
          items: const <DropdownMenuItem<bool>>[
            DropdownMenuItem<bool>(value: true, child: Text('((n1−n2)−(n1−n2)/n3) × (1+n4) + n5')),
            DropdownMenuItem<bool>(value: false, child: Text('((n1−n2)−(n1−n2)/n3) × n4 + n5')),
          ],
          onChanged: (v) => _update(() => _engine = FlnEngineConfig(
                strictCarry: _engine.strictCarry,
                finalProfile: _engine.finalProfile,
                q130Additive: v ?? true,
              )),
        ),
      ]),
    ]);
  }

  /// One sample of every question (from the current set code) so the
  /// teacher sees what each question looks like before choosing it.
  FlnItem? _example(int q) {
    final key = '$_seed|${jsonEncode(_engine.toJson())}';
    if (_examples == null || _examplesKey != key) {
      try {
        _examples = flnExpandPaper(FlnGenerator.generate(_seed * 1009 + 1, _engine), _engine, 1);
      } catch (_) {
        _examples = const <FlnItem>[];
      }
      _examplesKey = key;
    }
    for (final it in _examples!) {
      if (it.qNo == q) return it;
    }
    return null;
  }

  Widget _exampleText(int q) {
    final it = _example(q);
    if (it == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(children: <InlineSpan>[
        TextSpan(text: 'ઉદા.: ', style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary)),
        TextSpan(text: it.prompt),
        TextSpan(
          text: '   » ${it.answer}',
          style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF047857)),
        ),
      ]),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _sectionPicker(FlnSectionMeta m, String q) {
    final specs = <FlnQuestionSpec>[
      for (var n = m.qStart; n <= m.qEnd; n++)
        if (q.isEmpty ||
            'q$n'.contains(q) ||
            kFlnSpecs[n - 1].code.toLowerCase().contains(q) ||
            kFlnSpecs[n - 1].inst.toLowerCase().contains(q) ||
            m.titleGuj.toLowerCase().contains(q))
          kFlnSpecs[n - 1],
    ];
    if (specs.isEmpty) return const SizedBox.shrink();
    final selectedHere = <int>[for (var n = m.qStart; n <= m.qEnd; n++) if (_selected.contains(n)) n].length;
    void setSection(int pick) => _update(() {
          for (var n = m.qStart; n <= m.qEnd; n++) {
            _selected.remove(n);
          }
          if (pick < 0) {
            for (var n = m.qStart; n <= m.qEnd; n++) {
              _selected.add(n);
            }
          } else if (pick > 0) {
            final pool = <int>[for (var n = m.qStart; n <= m.qEnd; n++) n]..shuffle();
            _selected.addAll(pool.take(pick));
          }
        });
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ExpansionTile(
        initiallyExpanded: q.isNotEmpty,
        title: Text(m.titleGuj, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('$selectedHere / ${m.count} પસંદ · Q${m.qStart}–Q${m.qEnd}'),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(spacing: 6, children: <Widget>[
              ActionChip(label: const Text('બધા'), onPressed: () => setSection(-1)),
              ActionChip(label: const Text('કોઈ 1'), onPressed: () => setSection(1)),
              ActionChip(label: const Text('કોઈ 2'), onPressed: () => setSection(2)),
              ActionChip(label: const Text('કોઈ નહીં'), onPressed: () => setSection(0)),
            ]),
          ),
          for (final sp in specs)
            CheckboxListTile(
              dense: true,
              isThreeLine: true,
              value: _selected.contains(sp.q),
              title: Text(
                'Q${sp.q} · ${sp.inst.contains('{n1}') ? sp.rule : sp.inst.replaceFirst(RegExp(r'^.*?[:.]\s*'), '')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: _exampleText(sp.q),
              onChanged: (v) => _update(() => v == true ? _selected.add(sp.q) : _selected.remove(sp.q)),
            ),
        ],
      ),
    );
  }

  // ------------------------------ Page tab -----------------------------------

  Widget _stepper(
    String label,
    double value,
    double min,
    double max,
    double step,
    ValueChanged<double> onChanged, {
    String Function(double)? format,
    Widget? trailing,
  }) {
    final shown = format?.call(value) ?? value.toStringAsFixed(1);
    return Row(children: <Widget>[
      Expanded(child: Text(label)),
      IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: value - step < min - 1e-9 ? null : () => onChanged((value - step).clamp(min, max)),
        icon: const Icon(Icons.remove_circle_outline),
      ),
      SizedBox(width: 56, child: Text(shown, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
      IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: value + step > max + 1e-9 ? null : () => onChanged((value + step).clamp(min, max)),
        icon: const Icon(Icons.add_circle_outline),
      ),
      if (trailing != null) trailing,
    ]);
  }

  Widget _dropdown<T>(String label, T value, List<(T, String)> items, ValueChanged<T> onChanged) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: DropdownButtonFormField<T>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
          items: <DropdownMenuItem<T>>[for (final i in items) DropdownMenuItem<T>(value: i.$1, child: Text(i.$2))],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      );

  Widget _pageTab() {
    final l = _layout;
    final previewPages = _pagesForPreview().where((p) => !p.isKey).length;
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: <Widget>[
      _section('કાગળ અને હાંસિયો (A4)', icon: Icons.crop_portrait_rounded, <Widget>[
        SegmentedButton<bool>(
          segments: const <ButtonSegment<bool>>[
            ButtonSegment<bool>(value: false, icon: Icon(Icons.crop_portrait), label: Text('ઊભું (Portrait)')),
            ButtonSegment<bool>(value: true, icon: Icon(Icons.crop_landscape), label: Text('આડું (Landscape)')),
          ],
          selected: <bool>{l.landscape},
          onSelectionChanged: (v) => _update(() => l.landscape = v.first),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 6, children: <Widget>[
          ActionChip(
            label: const Text('સામાન્ય 8 mm'),
            onPressed: () => _update(() => l
              ..marginTopMm = 8
              ..marginBottomMm = 8
              ..marginLeftMm = 8
              ..marginRightMm = 8),
          ),
          ActionChip(
            label: const Text('સાંકડો 5 mm'),
            onPressed: () => _update(() => l
              ..marginTopMm = 5
              ..marginBottomMm = 5
              ..marginLeftMm = 5
              ..marginRightMm = 5),
          ),
          ActionChip(
            label: const Text('ફાઇલ માટે ડાબે 15 mm'),
            onPressed: () => _update(() => l
              ..marginTopMm = 8
              ..marginBottomMm = 8
              ..marginLeftMm = 15
              ..marginRightMm = 7),
          ),
        ]),
        _stepper('ઉપર (mm)', l.marginTopMm, 3, 30, 1, (v) => _update(() => l.marginTopMm = v), format: (v) => v.toStringAsFixed(0)),
        _stepper('નીચે (mm)', l.marginBottomMm, 3, 30, 1, (v) => _update(() => l.marginBottomMm = v), format: (v) => v.toStringAsFixed(0)),
        _stepper('ડાબે (mm)', l.marginLeftMm, 3, 30, 1, (v) => _update(() => l.marginLeftMm = v), format: (v) => v.toStringAsFixed(0)),
        _stepper('જમણે (mm)', l.marginRightMm, 3, 30, 1, (v) => _update(() => l.marginRightMm = v), format: (v) => v.toStringAsFixed(0)),
      ]),
      _section('ગોઠવણી', icon: Icons.view_column_rounded, <Widget>[
        SegmentedButton<int>(
          segments: const <ButtonSegment<int>>[
            ButtonSegment<int>(value: 2, label: Text('2 કૉલમ')),
            ButtonSegment<int>(value: 1, label: Text('1 કૉલમ')),
          ],
          selected: <int>{l.columns},
          onSelectionChanged: (v) => _update(() => l.columns = v.first),
        ),
        const SizedBox(height: 6),
        _stepper('અક્ષરનું કદ (pt)', l.fontSize, 8, 14, 0.5, (v) => _update(() => l.fontSize = v)),
        const SizedBox(height: 6),
        _dropdown<String>('વિકલ્પો', l.optionsMode, const <(String, String)>[
          ('with', 'વિકલ્પો (A, B, C, D) સાથે'),
          ('without', 'વિકલ્પો વિના — જવાબ લખવાનું ખાનું'),
          ('both', 'વિકલ્પો + જવાબનું ખાનું'),
        ], (v) => _update(() => l.optionsMode = v)),
        _dropdown<String>('જવાબવાળી PDF (બીજી ફાઇલ)', l.answerFormat, const <(String, String)>[
          ('marked', 'એ જ પેપર, સાચા જવાબ અને કોયડાની રીત સાથે'),
          ('key', 'ઉત્તરવહી (જવાબનું કોષ્ટક)'),
        ], (v) => _update(() => l.answerFormat = v)),
        if (l.answerFormat == 'key')
          _dropdown<String>('ઉત્તરવહીનો પ્રકાર', l.keyStyle, const <(String, String)>[
            ('section', 'વિભાગ મુજબ (પ્રશ્ન સાથે)'),
            ('table', 'કોષ્ટક (પ્રશ્ન + જવાબ)'),
            ('grid', 'ટૂંકી ગ્રીડ'),
          ], (v) => _update(() => l.keyStyle = v)),
        _dropdown<String>('રંગ', l.theme, const <(String, String)>[
          ('royal', 'રોયલ (ઘેરો વાદળી)'),
          ('emerald', 'એમરલ્ડ (લીલો)'),
          ('bw', 'પ્રિન્ટ-સેવર (કાળું-સફેદ)'),
        ], (v) => _update(() => l.theme = v)),
        _dropdown<String>('મુખ્ય વિભાગ નવા પાને', l.groupBreaks, const <(String, String)>[
          ('off', 'ના — ખાલી જગ્યામાં આગળના પ્રશ્નો આપોઆપ'),
          ('auto', 'વિભાગ આખો ન સમાય તો નવા પાને'),
          ('on', 'હંમેશાં નવા પાને'),
        ], (v) => _update(() => l.groupBreaks = v)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('મૂળ પ્રશ્ન નંબર [Q#] બતાવો'),
          value: l.showQTag,
          onChanged: (v) => _update(() => l.showQTag = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('મેળવેલ ગુણનું ખાનું'),
          value: l.showMarksBox,
          onChanged: (v) => _update(() => l.showMarksBox = v),
        ),
      ]),
      _section('જગ્યા (બધાં પાનાં માટે)', icon: Icons.format_line_spacing_rounded, <Widget>[
        _stepper('બે પ્રશ્નો વચ્ચે (mm)', l.cardGapMm, 0, 40, 0.5, (v) => _update(() => l.cardGapMm = v)),
        _stepper('પ્રશ્ન અને વિકલ્પ વચ્ચે (mm)', l.optionGapMm, 0, 20, 0.5, (v) => _update(() => l.optionGapMm = v)),
        if (l.showWriteBox)
          _stepper('જવાબના ખાનાની ઊંચાઈ (mm)', l.answerBoxMm, 4, 40, 1, (v) => _update(() => l.answerBoxMm = v),
              format: (v) => v.toStringAsFixed(0)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('પાનું ભરાય તે રીતે જગ્યા વહેંચો'),
          subtitle: const Text('દાખલા ગણવા માટે વધારાની જગ્યા (છેલ્લા પાના સિવાય).'),
          value: l.spreadToFill,
          onChanged: (v) => _update(() => l.spreadToFill = v),
        ),
      ]),
      _section('પાના મુજબ જગ્યા (બધા પેપરમાં એ જ પાનાને લાગુ)', icon: Icons.auto_stories_rounded, <Widget>[
        Text(
          'પૂર્વાવલોકનમાં દરેક પાનાની ઉપર પણ આ જગ્યા બદલી શકાય છે.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        for (var p = 1; p <= previewPages; p++) _pageGapRow(p),
        if (l.pageGaps.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _update(l.pageGaps.clear),
              icon: const Icon(Icons.restart_alt),
              label: const Text('બધાં પાનાં સામાન્ય કરો'),
            ),
          ),
      ]),
    ]);
  }

  void _setPageGap(int page, {double? card, double? option}) {
    final g = _layout.gapFor(page);
    _update(() => _layout.pageGaps[page] = FlnPageGap(
          (card ?? g.cardGapMm).clamp(0.0, 40.0),
          (option ?? g.optionGapMm).clamp(0.0, 20.0),
        ));
  }

  Widget _pageGapRow(int page) {
    final g = _layout.gapFor(page);
    final custom = _layout.pageGaps.containsKey(page);
    Widget mini(String label, double v, VoidCallback minus, VoidCallback plus) => Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(label, style: const TextStyle(fontSize: 12)),
          IconButton(visualDensity: VisualDensity.compact, iconSize: 18, onPressed: minus, icon: const Icon(Icons.remove)),
          Text('${v.toStringAsFixed(1)} mm', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          IconButton(visualDensity: VisualDensity.compact, iconSize: 18, onPressed: plus, icon: const Icon(Icons.add)),
        ]);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: custom ? const Color(0xFFFFF7E6) : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: custom ? const Color(0xFFF59E0B) : Colors.transparent),
      ),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: <Widget>[
        Text('પાનું $page', style: const TextStyle(fontWeight: FontWeight.w800)),
        mini('પ્રશ્નો વચ્ચે', g.cardGapMm, () => _setPageGap(page, card: g.cardGapMm - 0.5),
            () => _setPageGap(page, card: g.cardGapMm + 0.5)),
        mini('પ્રશ્ન-વિકલ્પ', g.optionGapMm, () => _setPageGap(page, option: g.optionGapMm - 0.5),
            () => _setPageGap(page, option: g.optionGapMm + 0.5)),
        if (custom)
          IconButton(
            tooltip: 'આ પાનું સામાન્ય કરો',
            visualDensity: VisualDensity.compact,
            onPressed: () => _update(() => _layout.pageGaps.remove(page)),
            icon: const Icon(Icons.restart_alt, size: 18),
          ),
      ]),
    );
  }

  // ------------------------------- Preview -----------------------------------

  Widget _previewPane() {
    final job = _currentJob();
    if (_selected.isEmpty) {
      return const Center(child: Text('પ્રશ્નો ટેબમાં ઓછામાં ઓછો એક પ્રશ્ન પસંદ કરો.'));
    }
    if (job == null) {
      return Center(
        child: Text(_printNames ? 'વિદ્યાર્થીઓ ટેબમાં ઓછામાં ઓછો એક વિદ્યાર્થી પસંદ કરો.' : 'પેપરની સંખ્યા લખો.'),
      );
    }
    if (_previewPaper > job.paperCount) _previewPaper = 1;
    final pages = _pagesForPreview();
    final headers = job.headers;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Material(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 4, children: <Widget>[
            SizedBox(
              width: 280,
              child: DropdownButtonFormField<int>(
                value: _previewPaper,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'પેપર', isDense: true, border: OutlineInputBorder()),
                items: <DropdownMenuItem<int>>[
                  for (var i = 1; i <= job.paperCount && i <= 500; i++)
                    DropdownMenuItem<int>(
                      value: i,
                      child: Text(
                        <String>[
                          if (headers[i - 1].rollNo.isNotEmpty) headers[i - 1].rollNo,
                          if (headers[i - 1].studentName.isNotEmpty) headers[i - 1].studentName,
                          if (headers[i - 1].studentName.isEmpty) 'પેપર $i',
                          if (headers[i - 1].setLabel.isNotEmpty) '(સેટ ${headers[i - 1].setLabel})',
                        ].join(' '),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _previewPaper = v ?? 1),
              ),
            ),
            SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: false, icon: Icon(Icons.description_outlined), label: Text('પ્રશ્નપત્ર')),
                ButtonSegment<bool>(value: true, icon: Icon(Icons.fact_check_outlined), label: Text('જવાબ સાથે')),
              ],
              selected: <bool>{_previewAnswers},
              onSelectionChanged: (v) => setState(() => _previewAnswers = v.first),
            ),
            Text('${pages.length} પાનાં · ${job.paperCount} વિદ્યાર્થી${job.inSets ? ' · ${job.variantCount} સેટ' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              IconButton(
                tooltip: 'નાનું',
                onPressed: _zoom <= 0.5 ? null : () => setState(() => _zoom = (_zoom - 0.1).clamp(0.5, 2.0)),
                icon: const Icon(Icons.zoom_out),
              ),
              Text('${(_zoom * 100).round()}%'),
              IconButton(
                tooltip: 'મોટું',
                onPressed: _zoom >= 2.0 ? null : () => setState(() => _zoom = (_zoom + 0.1).clamp(0.5, 2.0)),
                icon: const Icon(Icons.zoom_in),
              ),
            ]),
          ]),
        ),
      ),
      Expanded(
        child: Container(
          color: const Color(0xFFE2E8F0),
          child: LayoutBuilder(builder: (context, c) {
            final baseW = (c.maxWidth - 32).clamp(280.0, 900.0);
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount: pages.length,
              itemBuilder: (_, i) {
                final page = pages[i];
                final w = baseW * _zoom;
                final h = w * page.height / page.width;
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(children: <Widget>[
                      if (!page.isKey)
                        SizedBox(width: w, child: _pageGapRow(page.pageInPaper))
                      else
                        SizedBox(
                          width: w,
                          child: Text('ઉત્તરવહી — પાનું ${page.pageInPaper} / ${page.pagesInPaper}',
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      const SizedBox(height: 6),
                      Container(
                        decoration: const BoxDecoration(boxShadow: <BoxShadow>[
                          BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4)),
                        ]),
                        child: RepaintBoundary(
                          child: CustomPaint(size: Size(w, h), painter: FlnPagePainter(page)),
                        ),
                      ),
                    ]),
                  ),
                );
              },
            );
          }),
        ),
      ),
    ]);
  }
}

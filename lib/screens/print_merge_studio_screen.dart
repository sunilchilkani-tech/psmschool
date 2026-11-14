// Print Merge Studio — design certificates, ID slips, profiles or any A4
// document and merge it with an Excel / CSV list (teachers and admins).
//
// No restrictions: school name, student names and every other value come
// from the uploaded data or are typed freely on the design.
//
// Each command lives in exactly one place:
//   top bar      – views, templates, design file, record count
//   property bar – undo/redo, align, arrange, duplicate, delete, lock, view
//   left toolbox – add text, shapes, image, photo frame
//   left docker  – merge columns
//   inspector    – content, font, colours, size/position, clip, page, layers

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fln/fln_layout.dart';
import '../print_merge/pm_io.dart';
import '../print_merge/pm_models.dart';
import '../print_merge/pm_render.dart';
import '../services/psm_file_export_helper.dart';
import '../theme/responsive.dart';

class PrintMergeStudioScreen extends StatefulWidget {
  const PrintMergeStudioScreen({super.key});

  @override
  State<PrintMergeStudioScreen> createState() => _PrintMergeStudioScreenState();
}

class _PrintMergeStudioScreenState extends State<PrintMergeStudioScreen> {
  static const String _autosaveKey = 'pm_studio_design_v1';
  static const Color _bg = Color(0xFF1E2229);
  static const Color _panel = Color(0xFF272C35);
  static const Color _panelDark = Color(0xFF1F242D);
  static const Color _line = Color(0xFF3D4554);
  static const Color _accent = Color(0xFF60A5FA);
  static final RegExp _photoCol = RegExp(r'photo|image|ફોટો|ફોટા', caseSensitive: false);

  // Views: 'data' | 'design' | 'output'
  String _view = 'design';

  // Data
  List<String> _headers = <String>[];
  List<Map<String, String>> _rows = <Map<String, String>>[];
  final Map<String, Uint8List> _photos = <String, Uint8List>{};
  final Map<String, Uint8List> _images = <String, Uint8List>{};
  final Map<int, MemoryImage> _providers = <int, MemoryImage>{};
  String _tableSearch = '';
  int _colPage = 0;
  String _colSearch = '';
  bool _colLabel = true;

  // Design
  List<PmPage> _pages = <PmPage>[];
  int _pageIdx = 0;
  int _recIdx = 0;
  String? _selId;
  List<String> _selIds = <String>[];
  String? _editingId;
  TextEditingController? _editCtrl;
  String? _clipSourceId;
  bool _lockRatio = true;
  bool _noPhoto = false;
  bool _wide = false;
  // Narrow screens: the columns / properties panels slide over the artboard.
  bool _showDocker = false;
  bool _showInspector = false;
  bool _grid = false;
  bool _guides = true;
  bool _snap = false;
  double _zoom = 0.72;
  String _paintTarget = 'fill';
  final ValueNotifier<Offset> _cursorMm = ValueNotifier<Offset>(Offset.zero);
  Offset? _marqueeStart;
  Offset? _marqueeCur;
  final List<String> _undo = <String>[];
  final List<String> _redo = <String>[];
  final FocusNode _canvasFocus = FocusNode(debugLabel: 'pm-canvas');
  final ScrollController _vScroll = ScrollController();
  final ScrollController _hScroll = ScrollController();

  /// Imported pictures (ids in [_images]) shown in the PowerClip gallery.
  final List<String> _library = <String>[];
  final Map<String, String> _libraryNames = <String, String>{};

  /// PowerClip "edit contents": dragging a clipped shape moves the photo
  /// inside it and the mouse wheel zooms it.
  bool _clipDrag = false;

  static final Set<String> _loadedFonts = <String>{'NotoSansGujaratiLocal', 'LohitGujaratiLocal'};
  static final Map<String, Future<void>> _fontLoads = <String, Future<void>>{};

  // Output
  int _perSheet = 1;
  double _gapMm = 0;
  bool _crop = true;
  bool _padOdd = false;
  int _fromRec = 1;
  int _toRec = 1;
  bool _busy = false;

  Timer? _autosaveTimer;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _editCtrl?.dispose();
    _canvasFocus.dispose();
    _vScroll.dispose();
    _hScroll.dispose();
    _cursorMm.dispose();
    super.dispose();
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  String _uid() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36) + math.Random().nextInt(1 << 20).toRadixString(36);

  PmPage? get _page => (_pageIdx >= 0 && _pageIdx < _pages.length) ? _pages[_pageIdx] : null;

  Map<String, String> get _record =>
      (_recIdx >= 0 && _recIdx < _rows.length) ? _rows[_recIdx] : const <String, String>{};

  PmObject? get _primary {
    final p = _page;
    if (p == null || _selId == null) return null;
    for (final o in p.objects) {
      if (o.id == _selId) return o;
    }
    return null;
  }

  List<PmObject> get _selected {
    final p = _page;
    if (p == null) return const <PmObject>[];
    final ids = <String>{..._selIds, if (_selId != null) _selId!};
    return p.objects.where((o) => ids.contains(o.id)).toList();
  }

  List<PmObject> get _selectedUnlocked => _selected.where((o) => !o.locked).toList();

  bool _isSelected(String id) => _selId == id || _selIds.contains(id);

  void _select(String? id) {
    _selId = id;
    _selIds = id == null ? <String>[] : <String>[id];
  }

  void _notify(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? const Color(0xFFB91C1C) : const Color(0xFF047857),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 2600),
      ));
  }

  double _snapV(double v) {
    if (!_snap) return v;
    const step = PmA4.w / PmA4.mmW * 2;
    return (v / step).round() * step;
  }

  ImageProvider? _provider(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    return _providers.putIfAbsent(identityHashCode(bytes), () => MemoryImage(bytes));
  }

  /// Loads a studio font the first time it is used.
  Future<void> _ensureFont(String family) {
    if (_loadedFonts.contains(family)) return Future<void>.value();
    (String, String, List<String>)? spec;
    for (final f in kPmFonts) {
      if (f.$1 == family) spec = f;
    }
    if (spec == null || spec.$3.isEmpty) return Future<void>.value();
    final files = spec.$3;
    return _fontLoads.putIfAbsent(family, () async {
      try {
        final loader = FontLoader(family);
        for (final f in files) {
          loader.addFont(rootBundle.load('assets/fonts/pm/$f'));
        }
        await loader.load();
        _loadedFonts.add(family);
        FlnText.instance.clear();
        if (mounted) setState(() {});
      } catch (_) {
        _fontLoads.remove(family);
      }
    });
  }

  Future<void> _ensureDesignFonts() => Future.wait(<String>{
        for (final p in _pages)
          for (final o in p.objects) o.font,
      }.map(_ensureFont));

  void _addToLibrary(String id, String name) {
    if (!_library.contains(id)) _library.add(id);
    _libraryNames[id] = name;
  }

  static String _stem(String name) {
    final i = name.lastIndexOf('.');
    return i > 0 ? name.substring(0, i) : name;
  }

  Uint8List? _photoFor(Map<String, String> rec, String column) {
    var v = (rec[column] ?? '').trim();
    if (v.isEmpty) return null;
    v = v.replaceAll('\\', '/').split('/').last.toLowerCase();
    return _photos[v] ?? _photos[_stem(v)];
  }

  // ===========================================================================
  // History (undo / redo) and autosave
  // ===========================================================================

  String _snapshot() => jsonEncode(<String, dynamic>{
        'page': _pageIdx,
        'pages': _pages.map((p) => p.toJson()).toList(),
      });

  void _restoreSnapshot(String snap) {
    final j = jsonDecode(snap) as Map<String, dynamic>;
    _pages = <PmPage>[for (final p in j['pages'] as List) PmPage.fromJson(Map<String, dynamic>.from(p as Map))];
    _pageIdx = ((j['page'] as num?)?.toInt() ?? 0).clamp(0, math.max(0, _pages.length - 1));
    _select(null);
    _stopEditing(commit: false);
  }

  void _saveHistory() {
    final s = _snapshot();
    if (_undo.isNotEmpty && _undo.last == s) return;
    _undo.add(s);
    if (_undo.length > 40) _undo.removeAt(0);
    _redo.clear();
    _autosaveSoon();
  }

  void _doUndo() {
    if (_undo.isEmpty) return _notify('પાછું લેવા માટે કંઈ નથી');
    _redo.add(_snapshot());
    setState(() => _restoreSnapshot(_undo.removeLast()));
    _autosaveSoon();
  }

  void _doRedo() {
    if (_redo.isEmpty) return _notify('ફરી કરવા માટે કંઈ નથી');
    _undo.add(_snapshot());
    setState(() => _restoreSnapshot(_redo.removeLast()));
    _autosaveSoon();
  }

  void _autosaveSoon() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(seconds: 2), () async {
      try {
        final json = jsonEncode(<String, dynamic>{'pages': _pages.map((p) => p.toJson()).toList()});
        if (json.length > 900000) return;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_autosaveKey, json);
      } catch (_) {}
    });
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_autosaveKey);
      if (raw != null) {
        final j = jsonDecode(raw);
        final pages = <PmPage>[
          for (final p in (j['pages'] as List? ?? const <dynamic>[]))
            if (p is Map) PmPage.fromJson(Map<String, dynamic>.from(p)),
        ];
        if (pages.isNotEmpty && mounted) {
          setState(() {
            _pages = pages;
            _pageIdx = 0;
          });
          _ensureDesignFonts();
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(_loadSammanSample);
  }

  // ===========================================================================
  // Samples and auto layout
  // ===========================================================================

  void _loadSampleData({required bool withDesign}) {
    _headers = <String>['ક્રમ', 'Photo', 'નામ (Full Name)', 'ગામ (City)', 'મોબાઇલ (Mobile)', 'હોદ્દો (Role)'];
    const raw = <List<String>>[
      <String>[
        '1',
        'patel.jpg',
        'રાજેશભાઈ કરશનભાઈ પટેલ',
        'અમદાવાદ (નવરંગપુરા)',
        '9825011223',
        'પ્રમુખશ્રી - સમાજ કલ્યાણ ટ્રસ્ટ'
      ],
      <String>['2', 'sharma.jpg', 'કિરણબેન મહેશભાઈ શર્મા', 'સુરત (અડાજણ)', '9879122334', 'ઉપપ્રમુખશ્રી - મહિલા સમિતિ'],
      <String>['3', 'shah.jpg', 'મિતુલભાઈ જયંતિલાલ શાહ', 'વડોદરા (અલકાપુરી)', '9909233445', 'મંત્રીશ્રી - યુવા વિભાગ'],
      <String>[
        '4',
        'desai.jpg',
        'નિલેશભાઈ રમણલાલ દેસાઈ',
        'રાજકોટ (કાલાવડ રોડ)',
        '9824344556',
        'ખજાનચીશ્રી - કારોબારી સમિતિ'
      ],
      <String>[
        '5',
        'joshi.jpg',
        'પંકજભાઈ હરિપ્રસાદ જોશી',
        'ગાંધીનગર (સેક્ટર-૧૧)',
        '9426455667',
        'સભ્યશ્રી - શિક્ષણ સમિતિ'
      ],
    ];
    _rows = <Map<String, String>>[
      for (final r in raw) <String, String>{for (var i = 0; i < _headers.length; i++) _headers[i]: r[i]},
    ];
    _recIdx = 0;
    _fromRec = 1;
    _toRec = _rows.length;
    if (withDesign) _loadSammanDesign();
  }

  void _loadSammanSample() => _loadSampleData(withDesign: true);

  void _loadSammanDesign() {
    _pages = <PmPage>[
      PmPage(id: _uid(), name: 'સન્માન પત્ર', theme: 'cert', objects: <PmObject>[
        PmObject(
            id: _uid(),
            type: 'static',
            customText: '॥ શ્રી ગણેશાય નમઃ ॥',
            x: 220,
            y: 62,
            w: 354,
            h: 36,
            size: 22,
            bold: true,
            align: 'center',
            color: '#991B1B',
            locked: true),
        PmObject(
            id: _uid(),
            type: 'static',
            customText: 'ગુજરાત પરિવાર સ્નેહમિલન તથા સન્માન સમારોહ',
            x: 75,
            y: 112,
            w: 644,
            h: 48,
            size: 26,
            bold: true,
            align: 'center',
            color: '#1E3A8A',
            locked: true),
        PmObject(
            id: _uid(),
            type: 'shape',
            shapeKind: 'banner',
            customText: 'સન્માન પત્ર',
            x: 222,
            y: 166,
            w: 350,
            h: 40,
            size: 17,
            bold: true,
            color: '#92400E',
            fill: '#FEF3C7',
            noFill: false,
            borderW: 1.5,
            borderC: '#D97706',
            locked: true),
        PmObject(
            id: _uid(),
            type: 'photo',
            key: 'Photo',
            x: 545,
            y: 245,
            w: 155,
            h: 190,
            borderW: 3,
            borderC: '#B45309',
            radius: 10,
            fit: 'cover'),
        PmObject(
            id: _uid(),
            type: 'text',
            key: 'ક્રમ',
            prefix: 'નોંધણી ક્રમાંક: ',
            gujDigits: true,
            x: 80,
            y: 245,
            w: 300,
            h: 36,
            size: 18,
            bold: true,
            color: '#334155'),
        PmObject(
            id: _uid(),
            type: 'text',
            key: 'નામ (Full Name)',
            prefix: 'શ્રી ',
            x: 80,
            y: 300,
            w: 440,
            h: 44,
            size: 22,
            bold: true,
            color: '#991B1B'),
        PmObject(
            id: _uid(),
            type: 'text',
            key: 'હોદ્દો (Role)',
            prefix: 'હોદ્દો: ',
            x: 80,
            y: 358,
            w: 440,
            h: 38,
            size: 18,
            bold: true,
            color: '#1E40AF'),
        PmObject(
            id: _uid(),
            type: 'text',
            key: 'ગામ (City)',
            prefix: 'મુ. ગામ / શહેર: ',
            x: 80,
            y: 410,
            w: 440,
            h: 36,
            size: 18,
            color: '#1E293B'),
        PmObject(
            id: _uid(),
            type: 'text',
            key: 'મોબાઇલ (Mobile)',
            prefix: 'મોબાઇલ નંબર: ',
            gujDigits: true,
            x: 80,
            y: 460,
            w: 440,
            h: 36,
            size: 18,
            bold: true,
            color: '#047857'),
        PmObject(
            id: _uid(),
            type: 'shape',
            shapeKind: 'line',
            x: 80,
            y: 900,
            w: 220,
            h: 8,
            borderW: 1.5,
            borderC: '#1E293B'),
        PmObject(
            id: _uid(),
            type: 'static',
            customText: 'આયોજકની સહી',
            x: 80,
            y: 912,
            w: 220,
            h: 30,
            size: 15,
            align: 'center',
            color: '#1E293B'),
        PmObject(
            id: _uid(),
            type: 'shape',
            shapeKind: 'line',
            x: 494,
            y: 900,
            w: 220,
            h: 8,
            borderW: 1.5,
            borderC: '#1E293B'),
        PmObject(
            id: _uid(),
            type: 'static',
            customText: 'પ્રમુખશ્રીની સહી',
            x: 494,
            y: 912,
            w: 220,
            h: 30,
            size: 15,
            align: 'center',
            color: '#1E293B'),
      ]),
    ];
    _pageIdx = 0;
    _select(null);
    _view = 'design';
  }

  void _loadProfileSampleData() {
    final base = <String>[
      'Roll_No (રોલ નં)',
      'Student_Name (વિદ્યાર્થીનું નામ)',
      'GR_No (જી.આર. નં)',
      'Standard_Div (ધોરણ-વર્ગ)',
      'Birth_Date (જન્મ તારીખ)',
      'Blood_Group (બ્લડ ગ્રુપ)',
      'Father_Name (પિતાનું નામ)',
      'Mother_Name (માતાનું નામ)',
      'Mobile_No (મોબાઇલ નંબર)',
      'City_Village (ગામ / શહેર)',
      'Taluka (તાલુકો)',
      'District (જિલ્લો)',
      'House_Team (હાઉસ ટીમ)',
      'Attendance_Days (હાજર દિવસ)',
      'Overall_Grade (કુલ ગ્રેડ)',
      'Percentage (ટકાવારી %)',
    ];
    const subjects = <String>[
      'Gujarati',
      'Maths',
      'Science',
      'Social',
      'English',
      'Hindi',
      'Sanskrit',
      'Computer',
      'Drawing',
      'Yoga'
    ];
    const metrics = <String>[
      'FA1_20',
      'FA2_20',
      'SA1_80',
      'Term1_100',
      'FA3_20',
      'FA4_20',
      'SA2_80',
      'Term2_100',
      'Project_20',
      'Final_Total'
    ];
    final headers = <String>[...base];
    for (var s = 0; s < subjects.length; s++) {
      for (final m in metrics) {
        headers.add('S${s + 1}_${subjects[s]}_$m');
      }
    }
    for (var k = 1; k <= 30; k++) {
      headers.add('Skill_$k (કૌશલ્ય $k)');
    }
    const students = <List<String>>[
      <String>[
        '101',
        'આરવકુમાર રાજેશભાઈ પટેલ',
        'GR-01',
        '10-A',
        '14/05/2011',
        'B+',
        'રાજેશભાઈ પટેલ',
        'ભાવનાબેન પટેલ',
        '9825011223',
        'બોપલ',
        'દસ્ક્રોઈ',
        'અમદાવાદ',
        'સરદાર',
        '218',
        'A1',
        '94.6%'
      ],
      <String>[
        '102',
        'દિયાબેન કિરણભાઈ શાહ',
        'GR-02',
        '10-A',
        '22/08/2011',
        'O+',
        'કિરણભાઈ શાહ',
        'પૂજાબેન શાહ',
        '9879122334',
        'અડાજણ',
        'ચોર્યાસી',
        'સુરત',
        'ટાગોર',
        '221',
        'A1',
        '93.2%'
      ],
      <String>[
        '103',
        'હર્ષિલ મહેશભાઈ દેસાઈ',
        'GR-03',
        '10-A',
        '03/11/2011',
        'A+',
        'મહેશભાઈ દેસાઈ',
        'કવિતાબેન દેસાઈ',
        '9909233445',
        'અલકાપુરી',
        'વડોદરા',
        'વડોદરા',
        'ગાંધી',
        '210',
        'A2',
        '89.4%'
      ],
    ];
    const ratings = <String>['ઉત્તમ', 'ઘણું સારું', 'સારું'];
    _rows = <Map<String, String>>[];
    for (var i = 0; i < students.length; i++) {
      final vals = <String>[...students[i]];
      for (var s = 0; s < subjects.length; s++) {
        final f1 = 18 - (i + s) % 3, f2 = 19 - (i + s) % 2, sa1 = 72 - (i * 2 + s) % 9;
        final f3 = 18 - s % 3, f4 = 19 - i % 2, sa2 = 74 - (i + s * 2) % 8;
        vals.addAll(<String>[
          '$f1',
          '$f2',
          '$sa1',
          '${f1 + sa1}',
          '$f3',
          '$f4',
          '$sa2',
          '${f3 + sa2}',
          '19',
          '${((f1 + sa1 + f3 + sa2) / 2).round()}'
        ]);
      }
      for (var k = 1; k <= 30; k++) {
        vals.add(ratings[(i + k) % ratings.length]);
      }
      _rows.add(<String, String>{for (var c = 0; c < headers.length; c++) headers[c]: c < vals.length ? vals[c] : ''});
    }
    _headers = headers;
    _recIdx = 0;
    _fromRec = 1;
    _toRec = _rows.length;
  }

  /// Builds a multi-page layout with one field per data column.
  void _autoLayout({
    required String title,
    required String subtitle,
    required int pages,
    required int cols,
    required bool photo,
    required String theme,
    required bool lockFixed,
  }) {
    if (_headers.isEmpty) return _notify('પહેલાં માહિતી (Excel) ઉમેરો', error: true);
    _saveHistory();
    final photoCols = _headers.where((h) => _photoCol.hasMatch(h)).toList();
    final rollCol = _headers.first;
    final nameCol = _headers.firstWhere((h) => RegExp(r'name|નામ', caseSensitive: false).hasMatch(h),
        orElse: () => _headers.length > 1 ? _headers[1] : _headers.first);
    final dataCols = _headers.where((h) => !photoCols.contains(h) && h != rollCol && h != nameCol).toList();
    final numPages = pages.clamp(1, PmA4.maxPages);
    final perPage = math.max(1, (dataCols.length / numPages).ceil());
    final built = <PmPage>[];
    for (var p = 0; p < numPages; p++) {
      final objs = <PmObject>[
        PmObject(
            id: _uid(),
            type: 'static',
            customText: title,
            x: 48,
            y: 44,
            w: 698,
            h: 36,
            size: 22,
            bold: true,
            align: 'center',
            color: '#1E3A8A',
            locked: lockFixed),
        PmObject(
            id: _uid(),
            type: 'static',
            customText: numPages > 1 ? '$subtitle — પાનું ${p + 1} / $numPages' : subtitle,
            x: 48,
            y: 84,
            w: 698,
            h: 28,
            size: 13.5,
            bold: true,
            align: 'center',
            color: '#475569',
            locked: lockFixed),
        PmObject(
            id: _uid(),
            type: 'shape',
            shapeKind: 'roundrect',
            x: 44,
            y: 136,
            w: 706,
            h: 38,
            fill: '#DBEAFE',
            noFill: false,
            borderW: 1.5,
            borderC: '#3B82F6',
            radius: 14,
            locked: lockFixed),
        PmObject(
            id: _uid(),
            type: 'text',
            key: rollCol,
            prefix: '$rollCol: ',
            x: 56,
            y: 143,
            w: 200,
            h: 26,
            size: 13.5,
            bold: true,
            color: '#0F172A'),
        PmObject(
            id: _uid(),
            type: 'text',
            key: nameCol,
            prefix: '$nameCol: ',
            x: 262,
            y: 143,
            w: 480,
            h: 26,
            size: 14.5,
            bold: true,
            color: '#991B1B'),
      ];
      final withPhoto = p == 0 && photo && photoCols.isNotEmpty;
      if (withPhoto) {
        objs.add(PmObject(
            id: _uid(),
            type: 'photo',
            key: photoCols.first,
            x: 618,
            y: 186,
            w: 128,
            h: 155,
            borderW: 2,
            borderC: '#1E3A8A',
            radius: 6));
      }
      final slice = dataCols.skip(p * perPage).take(perPage).toList();
      final c = cols.clamp(1, 3);
      final rowsNeeded = math.max(1, (slice.length / c).ceil());
      final rowH = (860 / rowsNeeded).clamp(20.0, 34.0);
      final fs = rowH <= 23 ? 11.0 : (rowH <= 27 ? 12.5 : 14.0);
      for (var i = 0; i < slice.length; i++) {
        final r = i ~/ c, col = i % c;
        final y = 186 + r * rowH;
        final right = (withPhoto && y < 350) ? 560.0 : 706.0;
        final cw = ((right - (c - 1) * 10) / c).floorToDouble();
        objs.add(PmObject(
          id: _uid(),
          type: 'text',
          key: slice[i],
          prefix: '${slice[i]}: ',
          x: 44 + col * (cw + 10),
          y: y,
          w: cw,
          h: rowH - 2,
          size: fs,
          color: '#1E293B',
          borderW: 1,
          borderC: '#CBD5E1',
          fill: r.isEven ? '#FFFFFF' : '#F8FAFC',
          noFill: false,
          radius: 4,
        ));
      }
      built.add(PmPage(id: _uid(), name: 'પાનું ${p + 1}', theme: theme, objects: objs));
    }
    setState(() {
      _pages = built;
      _pageIdx = 0;
      _select(null);
      _view = 'design';
    });
    _notify('$numPages પાનાંની ડિઝાઇન ${dataCols.length + 2} કૉલમ સાથે બની.');
  }

  Future<void> _showAutoLayoutDialog() async {
    final titleCtrl = TextEditingController(text: 'વિદ્યાર્થી પ્રોફાઇલ');
    final subCtrl =
        TextEditingController(text: 'શૈક્ષણિક વર્ષ ${DateTime.now().year}–${(DateTime.now().year + 1) % 100}');
    var pages = math.min(PmA4.maxPages, math.max(1, (_headers.length / 60).ceil()));
    var cols = 3;
    var photo = _headers.any((h) => _photoCol.hasMatch(h));
    var theme = 'blue';
    var lock = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('આપોઆપ ગોઠવણી (કૉલમ પરથી)'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                Text('${_headers.length} કૉલમ માટે દરેક ખાનું આપોઆપ ગોઠવાશે.'),
                const SizedBox(height: 10),
                TextField(
                    controller: titleCtrl, decoration: const InputDecoration(labelText: 'શીર્ષક (શાળા / સંસ્થા)')),
                TextField(controller: subCtrl, decoration: const InputDecoration(labelText: 'પેટા-શીર્ષક')),
                const SizedBox(height: 10),
                Row(children: <Widget>[
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      isExpanded: true,
                      value: pages,
                      decoration: const InputDecoration(labelText: 'પાનાં'),
                      items: <DropdownMenuItem<int>>[
                        for (var p = 1; p <= PmA4.maxPages; p++) DropdownMenuItem<int>(value: p, child: Text('$p')),
                      ],
                      onChanged: (v) => setD(() => pages = v ?? pages),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      isExpanded: true,
                      value: cols,
                      decoration: const InputDecoration(labelText: 'એક લીટીમાં ખાનાં'),
                      items: const <DropdownMenuItem<int>>[
                        DropdownMenuItem<int>(value: 1, child: Text('1')),
                        DropdownMenuItem<int>(value: 2, child: Text('2')),
                        DropdownMenuItem<int>(value: 3, child: Text('3')),
                      ],
                      onChanged: (v) => setD(() => cols = v ?? cols),
                    ),
                  ),
                ]),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: theme,
                  decoration: const InputDecoration(labelText: 'પાનાની ફ્રેમ'),
                  items: <DropdownMenuItem<String>>[
                    for (final t in kPmThemes) DropdownMenuItem<String>(value: t.$1, child: Text(t.$2)),
                  ],
                  onChanged: (v) => setD(() => theme = v ?? theme),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('પહેલા પાને ફોટો'),
                  subtitle: Text(_headers.any((h) => _photoCol.hasMatch(h)) ? '' : 'માહિતીમાં Photo કૉલમ નથી'),
                  value: photo,
                  onChanged: (v) => setD(() => photo = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('શીર્ષક અને પટ્ટી લૉક કરો'),
                  value: lock,
                  onChanged: (v) => setD(() => lock = v),
                ),
              ]),
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('રદ કરો')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ડિઝાઇન બનાવો')),
          ],
        ),
      ),
    );
    final title = titleCtrl.text.trim(), sub = subCtrl.text.trim();
    titleCtrl.dispose();
    subCtrl.dispose();
    if (ok == true) {
      _autoLayout(title: title, subtitle: sub, pages: pages, cols: cols, photo: photo, theme: theme, lockFixed: lock);
    }
  }

  // ===========================================================================
  // Data import / export
  // ===========================================================================

  Future<void> _uploadData() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['xlsx', 'csv', 'tsv', 'txt', 'xls'],
      withData: true,
    );
    final f = res?.files.single;
    if (f == null || f.bytes == null) return;
    try {
      final t = PmIo.parseFile(f.bytes!, f.name);
      _applyTable(t, source: f.name);
    } catch (e) {
      _notify(e is FormatException ? e.message : 'ફાઇલ વાંચી શકાઈ નહીં: $e', error: true);
    }
  }

  void _applyTable(PmTable t, {required String source}) {
    setState(() {
      _headers = t.headers;
      _rows = t.rows;
      _recIdx = 0;
      _fromRec = 1;
      _toRec = math.max(1, _rows.length);
      _colPage = 0;
    });
    final missing = <String>{};
    for (final p in _pages) {
      for (final o in p.objects) {
        if ((o.type == 'text' || o.type == 'photo') && o.key.isNotEmpty && !_headers.contains(o.key))
          missing.add(o.key);
      }
    }
    _notify('${_rows.length} રેકોર્ડ × ${_headers.length} કૉલમ લોડ થયા ($source)'
        '${missing.isEmpty ? '' : ' — ડિઝાઇનમાં ${missing.length} કૉલમ મળ્યા નહીં'}');
  }

  Future<void> _pasteData() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excel માંથી કૉપી કરેલી માહિતી ચોંટાડો'),
        content: SizedBox(
          width: 620,
          child: TextField(
            controller: ctrl,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: 'પહેલી લીટીમાં કૉલમનાં નામ. Excel માંથી કૉપી (Ctrl+C) કરી અહીં ચોંટાડો (Ctrl+V).',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('રદ કરો')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('માહિતી લો')),
        ],
      ),
    );
    final text = ctrl.text;
    ctrl.dispose();
    if (ok != true || text.trim().isEmpty) return;
    try {
      _applyTable(PmIo.parseDelimited(text), source: 'paste');
    } catch (e) {
      _notify(e is FormatException ? e.message : 'માહિતી વાંચી શકાઈ નહીં: $e', error: true);
    }
  }

  Future<void> _downloadExcel() async {
    if (_headers.isEmpty) return _notify('કોઈ કૉલમ નથી', error: true);
    try {
      final bytes = PmIo.toExcel(_headers, _rows);
      await PsmFileExportHelper.saveOrShare(
        bytes: bytes,
        filename: 'print_merge_data.xlsx',
        title: 'Print merge data',
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } catch (e) {
      _notify('Excel બની શકી નહીં: $e', error: true);
    }
  }

  Future<void> _uploadPhotos() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true, withData: true);
    if (res == null) return;
    var n = 0;
    for (final f in res.files) {
      if (f.bytes == null) continue;
      final name = f.name.toLowerCase();
      _photos[name] = f.bytes!;
      _photos[_stem(name)] = f.bytes!;
      n++;
    }
    setState(() => _noPhoto = false);
    final photoCols = _headers.where((h) => _photoCol.hasMatch(h)).toList();
    var matched = 0;
    if (photoCols.isNotEmpty) {
      for (final r in _rows) {
        if (_photoFor(r, photoCols.first) != null) matched++;
      }
    }
    _notify('$n ફોટા ઉમેર્યા'
        '${photoCols.isEmpty ? ' — માહિતીમાં Photo કૉલમ ઉમેરો (ફાઇલ નામ લખો)' : ' — $matched / ${_rows.length} રેકોર્ડ સાથે મેળ'}');
  }

  Future<Uint8List?> _pickImageBytes() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    return res?.files.single.bytes;
  }

  Future<void> _saveDesign() async {
    try {
      final bytes = PmIo.designToJson(_pages, _images);
      await PsmFileExportHelper.saveOrShare(
        bytes: bytes,
        filename: 'print_merge_design.json',
        title: 'Print merge design',
        mimeType: 'application/json',
      );
    } catch (e) {
      _notify('ડિઝાઇન સેવ થઈ નહીં: $e', error: true);
    }
  }

  Future<void> _openDesign() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: const <String>['json'], withData: true);
    final bytes = res?.files.single.bytes;
    if (bytes == null) return;
    try {
      final (pages, images) = PmIo.designFromJson(bytes);
      _saveHistory();
      setState(() {
        _pages = pages;
        _images.addAll(images);
        _pageIdx = 0;
        _select(null);
        _view = 'design';
      });
      _autosaveSoon();
      _ensureDesignFonts();
      for (final e in images.entries) {
        if (e.key.startsWith('img_')) _addToLibrary(e.key, 'ડિઝાઇનમાંથી');
      }
      _notify('${pages.length} પાનાંની ડિઝાઇન ખુલી');
    } catch (e) {
      _notify(e is FormatException ? e.message : 'ડિઝાઇન ખુલી નહીં: $e', error: true);
    }
  }

  // ===========================================================================
  // Object commands
  // ===========================================================================

  void _addObject(PmObject o, {bool edit = false}) {
    final p = _page;
    if (p == null) return;
    _saveHistory();
    setState(() {
      p.objects.add(o);
      _select(o.id);
      _view = 'design';
    });
    if (edit) _startEditing(o);
    _canvasFocus.requestFocus();
  }

  void _addMergeField(String col) {
    final p = _page;
    if (p == null) return;
    final isPhoto = _photoCol.hasMatch(col);
    _addObject(PmObject(
      id: _uid(),
      type: isPhoto ? 'photo' : 'text',
      key: col,
      prefix: (_colLabel && !isPhoto) ? '$col: ' : '',
      x: 55,
      y: math.min(1040, 85.0 + (p.objects.length % 22) * 38.0),
      w: isPhoto ? 130 : 320,
      h: isPhoto ? 160 : 30,
      size: 16,
      borderW: isPhoto ? 2 : 0,
      borderC: '#1E293B',
      radius: isPhoto ? 8 : 0,
    ));
  }

  void _addShape(String kind) {
    final d = PmShapes.defaults(kind);
    final line = kind == 'line';
    _addObject(PmObject(
      id: _uid(),
      type: 'shape',
      shapeKind: kind,
      x: (line ? 150.0 : 240.0) + ((_page?.objects.length ?? 0) % 8) * 18,
      y: 220.0 + ((_page?.objects.length ?? 0) % 8) * 18,
      w: d['w']!,
      h: d['h']!,
      radius: d['r']!,
      size: 16,
      fill: kind == 'star' ? '#FEF08A' : '#E0E7FF',
      noFill: line,
      borderW: line ? 2 : 2,
      borderC: '#1E40AF',
    ));
  }

  void _addText(Offset at) {
    _addObject(
      PmObject(
        id: _uid(),
        type: 'static',
        customText: 'નવું લખાણ',
        x: at.dx.clamp(10.0, PmA4.w - 290),
        y: at.dy.clamp(10.0, PmA4.h - 50),
        w: 280,
        h: 36,
        size: 18,
        bold: true,
      ),
      edit: true,
    );
  }

  Future<void> _addImage() async {
    final bytes = await _pickImageBytes();
    if (bytes == null) return;
    final id = 'img_${_uid()}';
    _images[id] = bytes;
    _addToLibrary(id, 'ચિત્ર');
    _addObject(PmObject(id: _uid(), type: 'image', imageId: id, x: 60, y: 60, w: 140, h: 140, fit: 'contain'));
  }

  void _addPhotoFrame() {
    final col =
        _headers.firstWhere((h) => _photoCol.hasMatch(h), orElse: () => _headers.isEmpty ? 'Photo' : _headers.first);
    _addObject(PmObject(
        id: _uid(),
        type: 'photo',
        key: col,
        x: 560,
        y: 200,
        w: 140,
        h: 170,
        borderW: 2,
        borderC: '#1E293B',
        radius: 6));
  }

  void _align(String mode) {
    final targets = _selectedUnlocked;
    if (targets.isEmpty) return _notify('પહેલાં ઑબ્જેક્ટ પસંદ કરો (લૉક ન હોય તેવો)', error: true);
    _saveHistory();
    final anchor = (_primary != null && !_primary!.locked) ? _primary! : targets.last;
    final relative = targets.length > 1 && mode != 'page';
    setState(() {
      for (final o in targets) {
        if (relative) {
          if (o.id == anchor.id) continue;
          switch (mode) {
            case 'L':
              o.x = anchor.x;
            case 'R':
              o.x = anchor.x + anchor.w - o.w;
            case 'C':
              o.x = anchor.x + (anchor.w - o.w) / 2;
            case 'T':
              o.y = anchor.y;
            case 'B':
              o.y = anchor.y + anchor.h - o.h;
            case 'M':
              o.y = anchor.y + (anchor.h - o.h) / 2;
          }
        } else {
          const m = 28.0;
          switch (mode) {
            case 'L':
              o.x = m;
            case 'R':
              o.x = PmA4.w - m - o.w;
            case 'C':
              o.x = (PmA4.w - o.w) / 2;
            case 'T':
              o.y = m;
            case 'B':
              o.y = PmA4.h - m - o.h;
            case 'M':
              o.y = (PmA4.h - o.h) / 2;
            case 'page':
              o.x = (PmA4.w - o.w) / 2;
              o.y = (PmA4.h - o.h) / 2;
          }
        }
      }
    });
  }

  void _arrange(String mode) {
    final p = _page;
    final sel = _selected;
    if (p == null || sel.isEmpty) return;
    _saveHistory();
    setState(() {
      final ids = sel.map((o) => o.id).toSet();
      final moving = p.objects.where((o) => ids.contains(o.id)).toList();
      if (mode == 'front' || mode == 'back') {
        p.objects.removeWhere((o) => ids.contains(o.id));
        mode == 'front' ? p.objects.addAll(moving) : p.objects.insertAll(0, moving);
      } else {
        final up = mode == 'forward';
        final order = up ? moving.reversed.toList() : moving;
        for (final o in order) {
          final i = p.objects.indexOf(o);
          final j = up ? i + 1 : i - 1;
          if (j < 0 || j >= p.objects.length || ids.contains(p.objects[j].id)) continue;
          p.objects[i] = p.objects[j];
          p.objects[j] = o;
        }
      }
    });
  }

  void _selectAll() {
    final p = _page;
    if (p == null) return;
    setState(() {
      _selIds = p.objects.where((o) => !o.locked).map((o) => o.id).toList();
      _selId = _selIds.isEmpty ? null : _selIds.last;
    });
  }

  void _delete() {
    final p = _page;
    final targets = _selectedUnlocked;
    if (p == null || targets.isEmpty) {
      if (_selected.isNotEmpty) _notify('પસંદ કરેલ ઑબ્જેક્ટ લૉક છે (Ctrl+L થી ખોલો)', error: true);
      return;
    }
    _saveHistory();
    final ids = targets.map((o) => o.id).toSet();
    setState(() {
      p.objects.removeWhere((o) => ids.contains(o.id));
      _select(null);
      _stopEditing(commit: false);
    });
  }

  void _duplicate() {
    final p = _page;
    final targets = _selected;
    if (p == null || targets.isEmpty) return;
    _saveHistory();
    final ids = <String>[];
    setState(() {
      for (final o in targets) {
        final c = o.copy(newId: _uid(), dx: 14, dy: 14);
        p.objects.add(c);
        ids.add(c.id);
      }
      _selIds = ids;
      _selId = ids.last;
    });
  }

  void _toggleLock() {
    final targets = _selected;
    if (targets.isEmpty) return;
    _saveHistory();
    final next = !(_primary?.locked ?? false);
    setState(() {
      for (final o in targets) {
        o.locked = next;
      }
    });
  }

  void _clipInto(PmObject src, PmObject shape) {
    final p = _page;
    if (p == null || shape.type != 'shape' || shape.shapeKind == 'line') return;
    _saveHistory();
    setState(() {
      if (src.type == 'image') {
        shape.clipMode = 'image';
        shape.clipImageId = src.imageId;
      } else {
        shape.clipMode = 'photo';
        shape.clipKey = src.key;
      }
      shape
        ..clipScale = 100
        ..clipX = 0
        ..clipY = 0;
      p.objects.removeWhere((o) => o.id == src.id);
      _clipSourceId = null;
      _select(shape.id);
    });
    _notify('ફોટો આકારની અંદર મૂક્યો');
  }

  /// Applies a property change to the selection (with one undo step).
  /// Locked objects keep their position and size ([geometry] changes skip
  /// them) but their text, font and colours can still be changed.
  void _change(void Function(PmObject o) fn, {bool history = true, bool geometry = false}) {
    final targets = geometry ? _selectedUnlocked : _selected;
    if (targets.isEmpty) return;
    if (history) _saveHistory();
    setState(() {
      for (final o in targets) {
        fn(o);
      }
    });
    _autosaveSoon();
  }

  // ----------------------------- inline editing ------------------------------

  void _startEditing(PmObject o) {
    if (o.locked) return _notify('લૉક કરેલ ઑબ્જેક્ટ બદલવા પહેલાં લૉક ખોલો', error: true);
    if (!(o.isTextual || o.type == 'shape') || (o.type == 'shape' && o.shapeKind == 'line')) return;
    _stopEditing(commit: true);
    final text = (o.type == 'text') ? (_record[o.key] ?? '') : o.customText;
    _saveHistory();
    setState(() {
      _editingId = o.id;
      _editCtrl = TextEditingController(text: text)
        ..selection = TextSelection(baseOffset: 0, extentOffset: text.length);
      _select(o.id);
    });
  }

  void _stopEditing({required bool commit}) {
    if (_editingId == null) return;
    final id = _editingId;
    final ctrl = _editCtrl;
    _editingId = null;
    _editCtrl = null;
    if (commit && ctrl != null) {
      final p = _page;
      PmObject? o;
      for (final x in p?.objects ?? const <PmObject>[]) {
        if (x.id == id) o = x;
      }
      if (o != null) {
        if (o.type == 'text') {
          if (_recIdx >= 0 && _recIdx < _rows.length) _rows[_recIdx][o.key] = ctrl.text;
        } else {
          o.customText = ctrl.text;
        }
      }
      _autosaveSoon();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl?.dispose());
  }

  // ===========================================================================
  // Keyboard (only while the artboard has focus, never while typing)
  // ===========================================================================

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_editingId != null) {
      if (e.logicalKey == LogicalKeyboardKey.escape) {
        setState(() => _stopEditing(commit: true));
        _canvasFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final hk = HardwareKeyboard.instance;
    final ctrl = hk.isControlPressed || hk.isMetaPressed;
    final k = e.logicalKey;
    if (ctrl && k == LogicalKeyboardKey.keyA) {
      _selectAll();
    } else if (ctrl && k == LogicalKeyboardKey.keyZ) {
      hk.isShiftPressed ? _doRedo() : _doUndo();
    } else if (ctrl && k == LogicalKeyboardKey.keyY) {
      _doRedo();
    } else if (ctrl && k == LogicalKeyboardKey.keyD) {
      _duplicate();
    } else if (ctrl && k == LogicalKeyboardKey.keyL) {
      _toggleLock();
    } else if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      _delete();
    } else if (k == LogicalKeyboardKey.escape) {
      setState(() {
        _select(null);
        _clipSourceId = null;
      });
    } else if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.arrowDown) {
      final targets = _selectedUnlocked;
      if (targets.isEmpty) return KeyEventResult.ignored;
      final step = hk.isShiftPressed ? 10.0 : 1.0;
      setState(() {
        for (final o in targets) {
          if (k == LogicalKeyboardKey.arrowLeft) o.x = math.max(0, o.x - step);
          if (k == LogicalKeyboardKey.arrowRight) o.x = math.min(PmA4.w - o.w, o.x + step);
          if (k == LogicalKeyboardKey.arrowUp) o.y = math.max(0, o.y - step);
          if (k == LogicalKeyboardKey.arrowDown) o.y = math.min(PmA4.h - o.h, o.y + step);
        }
      });
      _autosaveSoon();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ===========================================================================
  // Build
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final dark = ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: _bg,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF3B82F6),
        secondary: Color(0xFF10B981),
        surface: _panel,
      ),
      inputDecorationTheme: const InputDecorationTheme(isDense: true, border: OutlineInputBorder()),
    );
    return Theme(
      data: Responsive.adapt(dark, MediaQuery.sizeOf(context)),
      child: Scaffold(
        body: SafeArea(
          child: Column(children: <Widget>[
            _topBar(),
            if (_view == 'design') _propertyBar(),
            Expanded(
              child: switch (_view) {
                'data' => _dataView(),
                'output' => _outputView(),
                _ => _designView(),
              },
            ),
            _statusBar(),
          ]),
        ),
      ),
    );
  }

  // ------------------------------ top bar ------------------------------------

  Widget _topBar() {
    Widget tab(String key, String label, IconData icon) {
      final active = _view == key;
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: TextButton.icon(
          style: TextButton.styleFrom(
            backgroundColor: active ? const Color(0x333B82F6) : Colors.transparent,
            foregroundColor: active ? _accent : const Color(0xFFCBD5E1),
          ),
          onPressed: () => setState(() {
            _stopEditing(commit: true);
            _view = key;
          }),
          icon: Icon(icon, size: 18),
          label: Text(label),
        ),
      );
    }

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(color: Color(0xFF171A20), border: Border(bottom: BorderSide(color: _line))),
      child: Row(children: <Widget>[
        IconButton(
          tooltip: 'પાછા',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        const Icon(Icons.auto_awesome_mosaic_rounded, color: _accent),
        const SizedBox(width: 8),
        if (MediaQuery.sizeOf(context).width >= 700) ...[
          const Text('Print Merge Studio', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 16),
        ],
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: <Widget>[
              tab('data', '1 માહિતી', Icons.table_chart_rounded),
              tab('design', '2 ડિઝાઇન', Icons.design_services_rounded),
              tab('output', '3 PDF', Icons.picture_as_pdf_rounded),
              const SizedBox(width: 12),
              PopupMenuButton<String>(
                tooltip: 'ડિઝાઇન નમૂના',
                onSelected: (v) {
                  switch (v) {
                    case 'blank':
                      _saveHistory();
                      setState(() {
                        _pages = <PmPage>[PmPage(id: _uid(), name: 'પાનું 1')];
                        _pageIdx = 0;
                        _select(null);
                        _view = 'design';
                      });
                    case 'auto':
                      _showAutoLayoutDialog();
                    case 'samman':
                      _saveHistory();
                      setState(_loadSammanSample);
                    case 'profile':
                      setState(_loadProfileSampleData);
                      _autoLayout(
                          title: 'વિદ્યાર્થી પ્રોફાઇલ',
                          subtitle: 'નમૂનો',
                          pages: 4,
                          cols: 3,
                          photo: false,
                          theme: 'blue',
                          lockFixed: true);
                  }
                },
                itemBuilder: (_) => const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(value: 'blank', child: Text('ખાલી નવી ડિઝાઇન')),
                  PopupMenuItem<String>(value: 'auto', child: Text('આપોઆપ ગોઠવણી (માહિતીના કૉલમ પરથી)…')),
                  PopupMenuDivider(),
                  PopupMenuItem<String>(value: 'samman', child: Text('નમૂનો: સન્માન પત્ર (માહિતી સાથે)')),
                  PopupMenuItem<String>(
                      value: 'profile', child: Text('નમૂનો: વિદ્યાર્થી પ્રોફાઇલ 130+ કૉલમ (માહિતી સાથે)')),
                ],
                child: const _BarChip(icon: Icons.dashboard_customize_rounded, label: 'નમૂના'),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                tooltip: 'ડિઝાઇન ફાઇલ',
                onSelected: (v) => v == 'open' ? _openDesign() : _saveDesign(),
                itemBuilder: (_) => const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(value: 'open', child: Text('ડિઝાઇન ફાઇલ ખોલો (.json)')),
                  PopupMenuItem<String>(value: 'save', child: Text('ડિઝાઇન ફાઇલ સેવ કરો (.json)')),
                ],
                child: const _BarChip(icon: Icons.folder_open_rounded, label: 'ફાઇલ'),
              ),
            ]),
          ),
        ),
        if (MediaQuery.sizeOf(context).width >= 700)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0x2E3B82F6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x593B82F6)),
            ),
            child: Text('${_rows.length} રેકોર્ડ · ${_headers.length} કૉલમ · ${_photos.length ~/ 2} ફોટા',
                style: const TextStyle(fontSize: 12, color: Color(0xFF93C5FD), fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }

  // ---------------------------- property bar ---------------------------------

  Widget _propertyBar() {
    final o = _primary;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(color: _panel, border: Border(bottom: BorderSide(color: _line))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: <Widget>[
          _barBtn(Icons.undo_rounded, 'પાછું (Ctrl+Z)', _undo.isEmpty ? null : _doUndo),
          _barBtn(Icons.redo_rounded, 'ફરી (Ctrl+Y)', _redo.isEmpty ? null : _doRedo),
          _divider(),
          PopupMenuButton<String>(
            tooltip: 'ગોઠવો (એકથી વધુ પસંદ હોય તો પહેલા પસંદ કરેલા મુજબ)',
            onSelected: _align,
            itemBuilder: (_) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'L', child: Text('ડાબે')),
              PopupMenuItem<String>(value: 'C', child: Text('આડું મધ્ય')),
              PopupMenuItem<String>(value: 'R', child: Text('જમણે')),
              PopupMenuDivider(),
              PopupMenuItem<String>(value: 'T', child: Text('ઉપર')),
              PopupMenuItem<String>(value: 'M', child: Text('ઊભું મધ્ય')),
              PopupMenuItem<String>(value: 'B', child: Text('નીચે')),
              PopupMenuDivider(),
              PopupMenuItem<String>(value: 'page', child: Text('પાનાની બરાબર વચ્ચે')),
            ],
            child: const _BarChip(icon: Icons.align_horizontal_center_rounded, label: 'ગોઠવો'),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            tooltip: 'ક્રમ',
            onSelected: (v) => v == 'all' ? _selectAll() : _arrange(v),
            itemBuilder: (_) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'front', child: Text('સૌથી આગળ')),
              PopupMenuItem<String>(value: 'forward', child: Text('એક આગળ')),
              PopupMenuItem<String>(value: 'backward', child: Text('એક પાછળ')),
              PopupMenuItem<String>(value: 'back', child: Text('સૌથી પાછળ')),
              PopupMenuDivider(),
              PopupMenuItem<String>(value: 'all', child: Text('બધું પસંદ કરો (Ctrl+A)')),
            ],
            child: const _BarChip(icon: Icons.layers_rounded, label: 'ક્રમ'),
          ),
          _divider(),
          _barBtn(Icons.copy_all_rounded, 'નકલ (Ctrl+D)', _selected.isEmpty ? null : _duplicate),
          _barBtn(Icons.delete_outline_rounded, 'કાઢો (Delete)', _selected.isEmpty ? null : _delete),
          _barBtn(o?.locked == true ? Icons.lock_rounded : Icons.lock_open_rounded,
              o?.locked == true ? 'લૉક ખોલો (Ctrl+L)' : 'લૉક (Ctrl+L)', _selected.isEmpty ? null : _toggleLock,
              active: o?.locked == true),
          _barBtn(
              Icons.photo_filter_rounded,
              'ફોટો આકારમાં મૂકો: ફોટો પસંદ કરો, પછી આકાર પર ક્લિક',
              (o != null && (o.type == 'photo' || o.type == 'image'))
                  ? () {
                      setState(() => _clipSourceId = _clipSourceId == o.id ? null : o.id);
                      if (_clipSourceId != null) _notify('હવે જે આકારમાં મૂકવો છે તેના પર ક્લિક કરો');
                    }
                  : null,
              active: _clipSourceId != null),
          _divider(),
          _barToggle(Icons.grid_on_rounded, 'ગ્રીડ', _grid, () => setState(() => _grid = !_grid)),
          _barToggle(Icons.center_focus_weak_rounded, 'મધ્ય રેખા', _guides, () => setState(() => _guides = !_guides)),
          _barToggle(
              Icons.grid_goldenratio_rounded, 'ગ્રીડ પર ચોંટાડો (2 mm)', _snap, () => setState(() => _snap = !_snap)),
          _barToggle(Icons.aspect_ratio_rounded, 'ખૂણેથી ખેંચતાં પ્રમાણ જાળવો', _lockRatio,
              () => setState(() => _lockRatio = !_lockRatio)),
          _divider(),
          _barBtn(Icons.zoom_out_rounded, 'નાનું',
              _zoom <= 0.3 ? null : () => setState(() => _zoom = (_zoom - 0.1).clamp(0.3, 2.0))),
          SizedBox(
              width: 44,
              child:
                  Text('${(_zoom * 100).round()}%', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
          _barBtn(Icons.zoom_in_rounded, 'મોટું',
              _zoom >= 2.0 ? null : () => setState(() => _zoom = (_zoom + 0.1).clamp(0.3, 2.0))),
          _barToggle(Icons.fullscreen_rounded, 'મોટું આર્ટબોર્ડ (બાજુની પેનલ છુપાવો)', _wide,
              () => setState(() => _wide = !_wide)),
        ]),
      ),
    );
  }

  Widget _barBtn(IconData icon, String tip, VoidCallback? onTap, {bool active = false}) => IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        isSelected: active,
        color: active ? _accent : null,
        onPressed: onTap,
        icon: Icon(icon, size: 20),
      );

  Widget _barToggle(IconData icon, String tip, bool value, VoidCallback onTap) =>
      _barBtn(icon, tip, onTap, active: value);

  Widget _divider() => Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 6), color: _line);

  // ------------------------------ data view ----------------------------------

  Widget _dataView() {
    const perPage = 25;
    final colPages = math.max(1, (_headers.length / perPage).ceil());
    final page = _colPage.clamp(0, colPages - 1);
    final visible = _headers.skip(page * perPage).take(perPage).toList();
    final q = _tableSearch.trim().toLowerCase();
    final filtered = <int>[
      for (var i = 0; i < _rows.length; i++)
        if (q.isEmpty || _rows[i].values.any((v) => v.toLowerCase().contains(q))) i,
    ];
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Container(
        width: 290,
        decoration: const BoxDecoration(color: _panel, border: Border(right: BorderSide(color: _line))),
        child: ListView(padding: const EdgeInsets.all(10), children: <Widget>[
          _box('માહિતી (Excel / CSV)', <Widget>[
            FilledButton.icon(
                onPressed: _uploadData,
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Excel / CSV અપલોડ')),
            const SizedBox(height: 6),
            OutlinedButton.icon(
                onPressed: _pasteData,
                icon: const Icon(Icons.content_paste_rounded),
                label: const Text('Excel માંથી ચોંટાડો')),
            const SizedBox(height: 6),
            OutlinedButton.icon(
                onPressed: _downloadExcel,
                icon: const Icon(Icons.download_rounded),
                label: const Text('માહિતી Excel માં ડાઉનલોડ')),
            const SizedBox(height: 8),
            const Text(
              'પહેલી લીટીમાં કૉલમનાં નામ (દા.ત. નામ, રોલ નં, ગામ, Photo). દરેક લીટી = એક પ્રમાણપત્ર / પાનું.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
            ),
          ]),
          _box('ફેરફાર', <Widget>[
            Row(children: <Widget>[
              Expanded(child: OutlinedButton(onPressed: _addRow, child: const Text('+ લીટી'))),
              const SizedBox(width: 6),
              Expanded(child: OutlinedButton(onPressed: _addColumn, child: const Text('+ કૉલમ'))),
            ]),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: _rows.isEmpty && _headers.isEmpty ? null : _clearData,
              icon: const Icon(Icons.delete_sweep_rounded, color: Color(0xFFFCA5A5)),
              label: const Text('બધી માહિતી કાઢો', style: TextStyle(color: Color(0xFFFCA5A5))),
            ),
            const Text('કૉલમનું નામ બદલવા મથાળા પર, કિંમત બદલવા કોષ પર ક્લિક કરો.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8))),
          ]),
          _box('ફોટા', <Widget>[
            FilledButton.tonalIcon(
                onPressed: _uploadPhotos,
                icon: const Icon(Icons.photo_library_rounded),
                label: const Text('ફોટા ઉમેરો (ઘણા એકસાથે)')),
            const SizedBox(height: 6),
            Text('${_photos.length ~/ 2} ફોટા ઉમેરેલા', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'ફોટાની ફાઇલનું નામ (દા.ત. 101.jpg કે 101) માહિતીના Photo કૉલમમાં લખો — તે રેકોર્ડ સાથે આપોઆપ જોડાશે.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
            ),
            if (_photos.isNotEmpty)
              TextButton(onPressed: () => setState(_photos.clear), child: const Text('બધા ફોટા કાઢો')),
          ]),
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Row(children: <Widget>[
              Text('${_rows.length} રેકોર્ડ × ${_headers.length} કૉલમ',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF93C5FD))),
              const SizedBox(width: 12),
              if (colPages > 1) ...<Widget>[
                IconButton(
                    onPressed: page == 0 ? null : () => setState(() => _colPage = page - 1),
                    icon: const Icon(Icons.chevron_left)),
                Text('કૉલમ ${page * perPage + 1}–${math.min(_headers.length, (page + 1) * perPage)}'),
                IconButton(
                    onPressed: page >= colPages - 1 ? null : () => setState(() => _colPage = page + 1),
                    icon: const Icon(Icons.chevron_right)),
              ],
              const Spacer(),
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'શોધો…'),
                  onChanged: (v) => setState(() => _tableSearch = v),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                    color: const Color(0xFF181C23),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _line)),
                child: _headers.isEmpty
                    ? const Center(child: Text('Excel / CSV અપલોડ કરો અથવા + કૉલમ થી શરૂ કરો.'))
                    : SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowHeight: 38,
                            dataRowMinHeight: 32,
                            dataRowMaxHeight: 40,
                            columns: <DataColumn>[
                              const DataColumn(label: Text('#')),
                              for (final h in visible)
                                DataColumn(
                                  label: InkWell(
                                    onTap: () => _renameColumn(h),
                                    child: Text(h,
                                        style: const TextStyle(color: Color(0xFF93C5FD), fontWeight: FontWeight.bold)),
                                  ),
                                ),
                            ],
                            rows: <DataRow>[
                              for (final i in filtered.take(500))
                                DataRow(cells: <DataCell>[
                                  DataCell(Text('${i + 1}'), onTap: () => _rowMenu(i)),
                                  for (final h in visible)
                                    DataCell(
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 240),
                                        child: Text(_rows[i][h] ?? '', overflow: TextOverflow.ellipsis),
                                      ),
                                      onTap: () => _editCell(i, h),
                                    ),
                                ]),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
            if (filtered.length > 500)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child:
                    Text('પહેલા 500 રેકોર્ડ દેખાય છે (PDF માં બધા આવશે). શોધ વાપરો.', style: TextStyle(fontSize: 12)),
              ),
          ]),
        ),
      ),
    ]);
  }

  void _addRow() {
    setState(() {
      if (_headers.isEmpty) _headers = <String>['ક્રમ', 'નામ'];
      _rows.add(
          <String, String>{for (var i = 0; i < _headers.length; i++) _headers[i]: i == 0 ? '${_rows.length + 1}' : ''});
      _toRec = _rows.length;
    });
  }

  Future<void> _addColumn() async {
    final name = await _askText('નવા કૉલમનું નામ', 'Column_${_headers.length + 1}');
    if (name == null || name.trim().isEmpty) return;
    final n = name.trim();
    if (_headers.contains(n)) return _notify('આ નામનો કૉલમ છે', error: true);
    setState(() {
      _headers.add(n);
      for (final r in _rows) {
        r[n] = '';
      }
    });
  }

  Future<void> _renameColumn(String old) async {
    final name = await _askText('કૉલમનું નામ બદલો', old, extra: 'કૉલમ કાઢો');
    if (name == null) return;
    if (name == '\u0000delete') {
      setState(() {
        _headers.remove(old);
        for (final r in _rows) {
          r.remove(old);
        }
      });
      return;
    }
    final n = name.trim();
    if (n.isEmpty || n == old) return;
    if (_headers.contains(n)) return _notify('આ નામનો કૉલમ છે', error: true);
    setState(() {
      _headers[_headers.indexOf(old)] = n;
      for (final r in _rows) {
        r[n] = r.remove(old) ?? '';
      }
      for (final p in _pages) {
        for (final o in p.objects) {
          if (o.key == old) o.key = n;
          if (o.clipKey == old) o.clipKey = n;
        }
      }
    });
  }

  Future<void> _rowMenu(int i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('રેકોર્ડ ${i + 1}'),
        content: const Text('આ રેકોર્ડ કાઢી નાખવો છે?'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ના')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('કાઢો')),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _rows.removeAt(i);
        _recIdx = _recIdx.clamp(0, math.max(0, _rows.length - 1));
        _toRec = math.max(1, _rows.length);
      });
    }
  }

  void _clearData() {
    setState(() {
      _headers = <String>[];
      _rows = <Map<String, String>>[];
      _recIdx = 0;
    });
  }

  Future<void> _editCell(int row, String col) async {
    final v = await _askText('રેકોર્ડ ${row + 1} — $col', _rows[row][col] ?? '', multiline: true);
    if (v != null) setState(() => _rows[row][col] = v);
  }

  Future<String?> _askText(String title, String initial, {bool multiline = false, String? extra}) async {
    final ctrl = TextEditingController(text: initial);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 420,
          child: TextField(controller: ctrl, autofocus: true, maxLines: multiline ? 4 : 1, minLines: 1),
        ),
        actions: <Widget>[
          if (extra != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, '\u0000delete'),
              child: Text(extra, style: const TextStyle(color: Color(0xFFFCA5A5))),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ કરો')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('સેવ')),
        ],
      ),
    );
    ctrl.dispose();
    return res;
  }

  // ----------------------------- design view ---------------------------------

  Widget _designView() => LayoutBuilder(builder: (context, c) {
        if (c.maxWidth >= 1100) {
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            _toolbox(),
            if (!_wide) _columnsDocker(),
            Expanded(child: _stage()),
            if (!_wide) _inspector(),
          ]);
        }
        // Phones / tablets: artboard gets the whole width; the columns and
        // properties panels open over it from the two buttons (top-right).
        Widget toggle(IconData icon, String tip, bool on, VoidCallback tap) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: on ? _accent : const Color(0xE62F3541),
                shape: const CircleBorder(),
                elevation: 4,
                child: IconButton(
                  tooltip: tip,
                  color: Colors.white,
                  onPressed: tap,
                  icon: Icon(icon, size: 20),
                ),
              ),
            );
        final panelW = math.min(320.0, c.maxWidth - 54);
        return Stack(children: <Widget>[
          Positioned.fill(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              _toolbox(),
              Expanded(child: _stage()),
            ]),
          ),
          if (_showDocker)
            Positioned(
              left: 54,
              top: 0,
              bottom: 0,
              child: Material(elevation: 10, color: _panel, child: SizedBox(width: math.min(240.0, c.maxWidth - 54), child: _columnsDocker())),
            ),
          if (_showInspector)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Material(
                elevation: 10,
                color: _panel,
                child: SizedBox(width: panelW, child: _inspector()),
              ),
            ),
          Positioned(
            right: (_showInspector ? panelW : 0) + 8,
            top: 54,
            child: Column(children: <Widget>[
              toggle(Icons.view_column_rounded, 'મર્જ કૉલમ', _showDocker, () => setState(() => _showDocker = !_showDocker)),
              toggle(Icons.tune_rounded, 'ગુણધર્મ / PowerClip / પાનું / સ્તર', _showInspector,
                  () => setState(() => _showInspector = !_showInspector)),
            ]),
          ),
        ]);
      });

  Widget _toolbox() {
    Widget tool(Widget icon, String tip, VoidCallback onTap, {bool active = false}) => Tooltip(
          message: tip,
          waitDuration: const Duration(milliseconds: 250),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 42,
              height: 36,
              margin: const EdgeInsets.only(bottom: 3),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? const Color(0x383B82F6) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: active ? const Color(0xFF3B82F6) : Colors.transparent),
              ),
              child: IconTheme(data: IconThemeData(color: active ? _accent : Colors.white, size: 21), child: icon),
            ),
          ),
        );
    return Container(
      width: 54,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(color: Color(0xFF1B1F26), border: Border(right: BorderSide(color: _line))),
      child: Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(
          child: Column(children: <Widget>[
            tool(
              const Icon(Icons.near_me_outlined),
              'પસંદ કરો (Esc)',
              () => setState(() {
                _clipSourceId = null;
                _clipDrag = false;
                _stopEditing(commit: true);
              }),
              active: _clipSourceId == null && _editingId == null && !_clipDrag,
            ),
            tool(const Icon(Icons.text_fields_rounded), 'લખાણ ઉમેરો (આર્ટબોર્ડ પર ડબલ-ક્લિક પણ ચાલે)',
                () => _addText(const Offset(200, 140))),
            tool(const Icon(Icons.add_photo_alternate_outlined), 'ચિત્ર / લોગો / સહી ઉમેરો', _addImage),
            tool(const Icon(Icons.portrait_rounded), 'વિદ્યાર્થીનો ફોટો (માહિતીના Photo કૉલમ મુજબ)', _addPhotoFrame),
            const Divider(color: _line, indent: 8, endIndent: 8),
            const Text('આકાર', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
            const SizedBox(height: 4),
            for (final e in kPmShapeNames.entries)
              tool(
                CustomPaint(size: const Size(24, 22), painter: _ShapeIconPainter(e.key)),
                '${e.value} — ક્લિક કરી ઉમેરો, ખૂણેથી ખેંચી મોટું કરો, ડબલ-ક્લિક કરી અંદર લખો',
                () => _addShape(e.key),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _columnsDocker() {
    final q = _colSearch.trim().toLowerCase();
    final cols = _headers.where((h) => q.isEmpty || h.toLowerCase().contains(q)).toList();
    return Container(
      width: 240,
      decoration: const BoxDecoration(color: _panel, border: Border(right: BorderSide(color: _line))),
      padding: const EdgeInsets.all(8),
      child: Material(
        type: MaterialType.transparency,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text('મર્જ કૉલમ (${_headers.length})',
              style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF93C5FD))),
          const SizedBox(height: 6),
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 18), hintText: 'કૉલમ શોધો'),
            style: const TextStyle(fontSize: 12),
            onChanged: (v) => setState(() => _colSearch = v),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _colLabel,
            title: const Text('"કૉલમ: " આગળ લખો', style: TextStyle(fontSize: 12)),
            onChanged: (v) => setState(() => _colLabel = v ?? true),
          ),
          Expanded(
            child: _headers.isEmpty
                ? const Center(child: Text('માહિતી ટેબમાં Excel ઉમેરો', style: TextStyle(fontSize: 12)))
                : ListView.builder(
                    itemCount: cols.length,
                    itemBuilder: (_, i) {
                      final c = cols[i];
                      final photo = _photoCol.hasMatch(c);
                      return ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        leading: Icon(photo ? Icons.portrait_rounded : Icons.short_text_rounded, size: 18),
                        title: Text(c, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                        subtitle: Text(_record[c] ?? '',
                            style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.add_circle_outline, size: 18),
                        onTap: () => _addMergeField(c),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _stage() {
    final p = _page;
    return Container(
      color: _bg,
      padding: const EdgeInsets.all(6),
      child: Column(children: <Widget>[
        SizedBox(
          height: 38,
          child: LayoutBuilder(builder: (context, bc) {
            final tight = bc.maxWidth < 520;
            final canAdd = _pages.length < PmA4.maxPages;
            return Row(children: <Widget>[
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _pages.length,
                  itemBuilder: (_, i) {
                    final active = i == _pageIdx;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text('${i + 1}. ${_pages[i].name}', style: const TextStyle(fontSize: 12)),
                        selected: active,
                        onSelected: (_) => setState(() {
                          _stopEditing(commit: true);
                          _pageIdx = i;
                          _select(null);
                        }),
                      ),
                    );
                  },
                ),
              ),
              if (tight)
                IconButton.filledTonal(
                  tooltip: 'પાનું ઉમેરો (${_pages.length}/${PmA4.maxPages})',
                  visualDensity: VisualDensity.compact,
                  onPressed: canAdd ? () => _pageCommand('add') : null,
                  icon: const Icon(Icons.add, size: 18),
                )
              else
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: canAdd ? () => _pageCommand('add') : null,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('પાનું (${_pages.length}/${PmA4.maxPages})', style: const TextStyle(fontSize: 12)),
                ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                tooltip: 'પાનાં',
                onSelected: _pageCommand,
                itemBuilder: (_) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                      value: 'dup', enabled: _pages.length < PmA4.maxPages, child: const Text('આ પાનાની નકલ')),
                  PopupMenuItem<String>(value: 'left', enabled: _pageIdx > 0, child: const Text('ડાબે ખસેડો')),
                  PopupMenuItem<String>(
                      value: 'right', enabled: _pageIdx < _pages.length - 1, child: const Text('જમણે ખસેડો')),
                  PopupMenuItem<String>(value: 'del', enabled: _pages.length > 1, child: const Text('આ પાનું કાઢો')),
                ],
                child: tight
                    ? const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.more_horiz_rounded, color: Colors.white))
                    : const _BarChip(icon: Icons.more_horiz_rounded, label: 'આ પાનું'),
              ),
            ]);
          }),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
                color: const Color(0xFF3B4252),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _line)),
            child: p == null
                ? const Center(child: Text('કોઈ પાનું નથી'))
                : Focus(
                    focusNode: _canvasFocus,
                    autofocus: true,
                    onKeyEvent: _onKey,
                    // Dragging always moves / resizes objects (also on touch
                    // screens); the page scrolls with the wheel or scrollbars.
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(dragDevices: <PointerDeviceKind>{}),
                      child: Scrollbar(
                        controller: _vScroll,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _vScroll,
                          padding: const EdgeInsets.all(16),
                          child: Scrollbar(
                            controller: _hScroll,
                            thumbVisibility: true,
                            notificationPredicate: (n) => n.depth == 0,
                            child: SingleChildScrollView(
                              controller: _hScroll,
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: PmA4.w * _zoom,
                                height: PmA4.h * _zoom,
                                child: FittedBox(fit: BoxFit.fill, child: _artboard(p)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ]),
    );
  }

  void _pageCommand(String v) {
    _saveHistory();
    setState(() {
      _stopEditing(commit: true);
      switch (v) {
        case 'add':
          _pages.insert(_pageIdx + 1, PmPage(id: _uid(), name: 'પાનું ${_pages.length + 1}'));
          _pageIdx++;
        case 'dup':
          final src = _pages[_pageIdx];
          _pages.insert(
            _pageIdx + 1,
            PmPage(
              id: _uid(),
              name: '${src.name} (નકલ)',
              theme: src.theme,
              bgImageId: src.bgImageId,
              objects: <PmObject>[for (final o in src.objects) o.copy(newId: _uid())..locked = o.locked],
            ),
          );
          _pageIdx++;
        case 'left':
          final pg = _pages.removeAt(_pageIdx);
          _pages.insert(--_pageIdx, pg);
        case 'right':
          final pg = _pages.removeAt(_pageIdx);
          _pages.insert(++_pageIdx, pg);
        case 'del':
          _pages.removeAt(_pageIdx);
          _pageIdx = _pageIdx.clamp(0, _pages.length - 1);
      }
      _select(null);
    });
  }

  Widget _artboard(PmPage p, {bool interactive = true, Map<String, String>? record}) {
    final rec = record ?? _record;
    final bg = _provider(_images[p.bgImageId]);
    final children = <Widget>[
      Positioned.fill(child: CustomPaint(painter: PmBackgroundPainter(theme: p.theme))),
      if (bg != null) Positioned.fill(child: Image(image: bg, fit: BoxFit.fill, gaplessPlayback: true)),
      if (interactive && (_grid || _guides))
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
                painter: PmBackgroundPainter(theme: p.theme, showGrid: _grid, showGuides: _guides, background: false)),
          ),
        ),
      for (final o in p.objects)
        if (!(o.type == 'photo' && _noPhoto)) interactive ? _interactiveObject(o, rec) : _staticObject(o, rec),
      if (interactive && _marqueeStart != null && _marqueeCur != null)
        Positioned.fromRect(
          rect: Rect.fromPoints(_marqueeStart!, _marqueeCur!),
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                  color: const Color(0x243B82F6), border: Border.all(color: const Color(0xFF2563EB), width: 1.5)),
            ),
          ),
        ),
    ];
    final board =
        SizedBox(width: PmA4.w, height: PmA4.h, child: Stack(clipBehavior: Clip.hardEdge, children: children));
    if (!interactive) return board;
    return MouseRegion(
      cursor: SystemMouseCursors.precise,
      onHover: (ev) => _cursorMm.value = Offset(
        (ev.localPosition.dx / PmA4.w * PmA4.mmW).clamp(0.0, PmA4.mmW),
        (ev.localPosition.dy / PmA4.h * PmA4.mmH).clamp(0.0, PmA4.mmH),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _canvasFocus.requestFocus();
          setState(() {
            _stopEditing(commit: true);
            _clipSourceId = null;
            _select(null);
          });
        },
        onDoubleTapDown: (d) => _addText(d.localPosition),
        onDoubleTap: () {},
        onPanStart: (d) => setState(() {
          _marqueeStart = d.localPosition;
          _marqueeCur = d.localPosition;
        }),
        onPanUpdate: (d) => setState(() => _marqueeCur = d.localPosition),
        onPanEnd: (_) {
          final s = _marqueeStart, c = _marqueeCur;
          if (s != null && c != null) {
            final r = Rect.fromPoints(s, c);
            if (r.width > 6 || r.height > 6) {
              final hits = p.objects.where((o) => !o.locked && r.overlaps(Rect.fromLTWH(o.x, o.y, o.w, o.h))).toList();
              if (hits.isNotEmpty) {
                _selIds = hits.map((o) => o.id).toList();
                _selId = _selIds.last;
              }
            }
          }
          setState(() {
            _marqueeStart = null;
            _marqueeCur = null;
          });
        },
        child: board,
      ),
    );
  }

  Widget _staticObject(PmObject o, Map<String, String> rec) => Positioned(
        left: o.x,
        top: o.y,
        width: o.w,
        height: o.h,
        child: Transform.rotate(
          angle: o.rotate * math.pi / 180,
          child: Opacity(opacity: (o.opacity / 100).clamp(0.05, 1.0), child: _visual(o, rec, preview: true)),
        ),
      );

  MouseCursor _bodyCursor(PmObject o, bool editing) {
    if (editing) return SystemMouseCursors.text;
    if (_clipSourceId != null && o.type == 'shape' && o.id != _clipSourceId) return SystemMouseCursors.copy;
    if (o.locked) return SystemMouseCursors.basic;
    if (_clipDrag && o.clipMode != 'none' && _isSelected(o.id)) return SystemMouseCursors.grab;
    return SystemMouseCursors.move;
  }

  Widget _interactiveObject(PmObject o, Map<String, String> rec) {
    final selected = _isSelected(o.id);
    final secondary = selected && _selIds.length > 1 && _selId != o.id;
    final editing = _editingId == o.id;
    final showHandles = selected && !o.locked && !editing;
    // Handles keep the same size on screen at every zoom and sit on the
    // corners, half outside the object, so they are easy to grab.
    final hs = (13 / _zoom).clamp(9.0, 34.0);
    final m = showHandles ? hs : 0.0;
    final clipEdit = _clipDrag && selected && o.clipMode != 'none';
    Widget body = GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onTap: () {
        _canvasFocus.requestFocus();
        if (_clipSourceId != null && o.type == 'shape' && o.id != _clipSourceId) {
          PmObject? src;
          for (final x in _page?.objects ?? const <PmObject>[]) {
            if (x.id == _clipSourceId) src = x;
          }
          if (src != null) return _clipInto(src, o);
        }
        setState(() {
          if (_editingId != o.id) _stopEditing(commit: true);
          if (HardwareKeyboard.instance.isShiftPressed) {
            final cur = <String>{..._selIds, if (_selId != null) _selId!};
            cur.contains(o.id) ? cur.remove(o.id) : cur.add(o.id);
            _selIds = cur.toList();
            _selId = _selIds.isEmpty ? null : (cur.contains(o.id) ? o.id : _selIds.last);
          } else {
            _select(o.id);
          }
        });
      },
      onDoubleTap: () => _startEditing(o),
      onPanStart: (_) {
        if (o.locked || editing) return;
        if (!_isSelected(o.id)) setState(() => _select(o.id));
        _saveHistory();
      },
      onPanUpdate: (d) {
        if (o.locked || editing) return;
        setState(() {
          if (clipEdit) {
            o.clipX += d.delta.dx;
            o.clipY += d.delta.dy;
            return;
          }
          for (final t in _selectedUnlocked) {
            t.x = _snapV((t.x + d.delta.dx).clamp(-t.w + 10, PmA4.w - 10));
            t.y = _snapV((t.y + d.delta.dy).clamp(-t.h + 10, PmA4.h - 10));
          }
        });
      },
      onPanEnd: (_) => _autosaveSoon(),
      child: Opacity(
        opacity: (o.opacity / 100).clamp(0.05, 1.0),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: selected
                ? Border.all(
                    color: editing
                        ? const Color(0xFF10B981)
                        : (clipEdit
                            ? const Color(0xFFDB2777)
                            : (secondary ? const Color(0xFF0EA5E9) : const Color(0xFFF59E0B))),
                    width: 2,
                  )
                : (o.type != 'shape' ? Border.all(color: const Color(0x442563EB), width: 0.8) : null),
          ),
          child: editing ? _inlineEditor(o) : _visual(o, rec),
        ),
      ),
    );
    if (clipEdit) {
      body = Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) {
            GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
              final dy = (ev as PointerScrollEvent).scrollDelta.dy;
              setState(() => o.clipScale = (o.clipScale - dy * 0.15).clamp(20.0, 300.0));
              _autosaveSoon();
            });
          }
        },
        child: body,
      );
    }
    return Positioned(
      left: o.x - m,
      top: o.y - m,
      width: o.w + m * 2,
      height: o.h + m * 2,
      child: Transform.rotate(
        angle: o.rotate * math.pi / 180,
        child: Stack(clipBehavior: Clip.none, children: <Widget>[
          Positioned(
            left: m,
            top: m,
            width: o.w,
            height: o.h,
            child: MouseRegion(cursor: _bodyCursor(o, editing), child: body),
          ),
          if (o.locked)
            Positioned(
              top: m + 2,
              right: m + 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(color: const Color(0xE6EF4444), borderRadius: BorderRadius.circular(3)),
                child: const Icon(Icons.lock, size: 10, color: Colors.white),
              ),
            ),
          if (showHandles)
            for (final d in const <String>['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w']) _handle(o, d, hs, m),
        ]),
      ),
    );
  }

  Widget _handle(PmObject o, String dir, double hs, double m) {
    final corner = dir.length == 2;
    final cx = m + (dir.contains('w') ? 0 : (dir.contains('e') ? o.w : o.w / 2));
    final cy = m + (dir.contains('n') ? 0 : (dir.contains('s') ? o.h : o.h / 2));
    final cursor = switch (dir) {
      'nw' || 'se' => SystemMouseCursors.resizeUpLeftDownRight,
      'ne' || 'sw' => SystemMouseCursors.resizeUpRightDownLeft,
      'n' || 's' => SystemMouseCursors.resizeUpDown,
      _ => SystemMouseCursors.resizeLeftRight,
    };
    final dot = hs * (corner ? 0.72 : 0.6);
    return Positioned(
      left: cx - hs / 2,
      top: cy - hs / 2,
      width: hs,
      height: hs,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: (_) => _saveHistory(),
          onPanEnd: (_) => _autosaveSoon(),
          onPanUpdate: (d) {
            final dx = d.delta.dx, dy = d.delta.dy;
            final ow = math.max(12.0, o.w), oh = math.max(4.0, o.h);
            final right = o.x + ow, bottom = o.y + oh;
            setState(() {
              if (corner && _lockRatio) {
                final aspect = ow / oh;
                final sW = (dir.contains('e') ? ow + dx : ow - dx) / ow;
                final sH = (dir.contains('s') ? oh + dy : oh - dy) / oh;
                final sc = (sW - 1).abs() >= (sH - 1).abs() ? sW : sH;
                var nw = math.max(16.0, ow * sc);
                var nh = nw / aspect;
                if (nh < 6) {
                  nh = 6;
                  nw = nh * aspect;
                }
                o.w = nw;
                o.h = nh;
                if (dir.contains('w')) o.x = right - nw;
                if (dir.contains('n')) o.y = bottom - nh;
              } else {
                if (dir.contains('e')) o.w = math.max(14.0, ow + dx);
                if (dir.contains('s')) o.h = math.max(4.0, oh + dy);
                if (dir.contains('w')) {
                  final nw = math.max(14.0, ow - dx);
                  o.x = right - nw;
                  o.w = nw;
                }
                if (dir.contains('n')) {
                  final nh = math.max(4.0, oh - dy);
                  o.y = bottom - nh;
                  o.h = nh;
                }
              }
            });
          },
          child: Center(
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: corner ? const Color(0xFFF59E0B) : Colors.white,
                border: Border.all(color: const Color(0xFF111111), width: math.max(1.0, hs / 10)),
                borderRadius: BorderRadius.circular(corner ? 2 : dot / 2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _textStyle(PmObject o, {Paint? foreground}) => TextStyle(
        fontFamily: o.font,
        fontSize: o.size,
        height: o.lineH,
        fontWeight: o.bold ? FontWeight.w700 : FontWeight.w400,
        fontStyle: o.italic ? FontStyle.italic : FontStyle.normal,
        decoration: o.underline ? TextDecoration.underline : TextDecoration.none,
        color: foreground == null ? pmColor(o.color) : null,
        foreground: foreground,
        shadows: o.shadow && foreground == null
            ? <Shadow>[Shadow(color: pmColor(o.shadowC), offset: Offset(math.max(1.0, o.size * 0.07), math.max(1.0, o.size * 0.07)))]
            : null,
      );

  /// Text with the object's letter outline and shadow (same look as the PDF).
  Widget _styledText(PmObject o, String text, TextAlign align) {
    final main = Text(text, textAlign: align, style: _textStyle(o), strutStyle: _strut(o));
    if (o.outlineW <= 0) return main;
    return Stack(children: <Widget>[
      Text(
        text,
        textAlign: align,
        strutStyle: _strut(o),
        style: _textStyle(
          o,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = o.outlineW * 2
            ..strokeJoin = StrokeJoin.round
            ..color = pmColor(o.outlineC),
        ),
      ),
      main,
    ]);
  }

  StrutStyle _strut(PmObject o) =>
      StrutStyle(fontFamily: o.font, fontSize: o.size, height: o.lineH, forceStrutHeight: true);

  Widget _inlineEditor(PmObject o) => Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: TextField(
          controller: _editCtrl,
          autofocus: true,
          maxLines: null,
          style: _textStyle(o).copyWith(decoration: TextDecoration.none),
          strutStyle: _strut(o),
          textAlign: o.type == 'shape' ? TextAlign.center : pmAlign(o.align),
          cursorColor: const Color(0xFF2563EB),
          decoration: const InputDecoration(
              border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero, filled: false),
        ),
      );

  Widget _visual(PmObject o, Map<String, String> rec, {bool preview = false}) {
    if (o.type == 'shape') {
      final sw = o.hasBorder ? o.borderW : 0.0;
      final clip = o.clipMode != 'none' && o.shapeKind != 'line';
      final caption = o.shapeKind == 'line' ? '' : pmObjectText(o, rec);
      final clipBytes = !clip ? null : (o.clipMode == 'image' ? _images[o.clipImageId] : _photoFor(rec, o.clipKey));
      return Stack(fit: StackFit.expand, children: <Widget>[
        CustomPaint(painter: PmShapePainter(o, fillOnly: clip)),
        if (clip)
          ClipPath(
            clipper: PmShapeClipper(o.shapeKind, sw / 2, o.radius),
            child: Transform.translate(
              offset: Offset(o.clipX, o.clipY),
              child: Transform.scale(
                scale: (o.clipScale / 100).clamp(0.2, 3.0),
                child: _photoBox(clipBytes, rec, preview: preview, fit: 'cover'),
              ),
            ),
          ),
        if (clip) CustomPaint(painter: PmShapePainter(o, strokeOnly: true)),
        if (caption.isNotEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _styledText(o, caption, TextAlign.center),
            ),
          ),
      ]);
    }
    final rr = math.min(o.radius, math.min(o.w, o.h) / 2);
    final deco = BoxDecoration(
      color: o.noFill ? null : pmColor(o.fill, Colors.white),
      borderRadius: BorderRadius.circular(rr),
      border: o.hasBorder ? Border.all(color: pmColor(o.borderC), width: o.borderW) : null,
    );
    if (o.type == 'photo' || o.type == 'image') {
      final bytes = o.type == 'image' ? _images[o.imageId] : _photoFor(rec, o.key);
      return Container(
        decoration: deco,
        foregroundDecoration: o.hasBorder
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(rr),
                border: Border.all(color: pmColor(o.borderC), width: o.borderW))
            : null,
        clipBehavior: Clip.antiAlias,
        child: _photoBox(bytes, rec, preview: preview, fit: o.fit, isImage: o.type == 'image'),
      );
    }
    final text = pmObjectText(o, rec);
    final missing = o.type == 'text' && text.isEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: deco,
      child: missing
          ? Text(
              preview ? '' : '«${o.key}»',
              textAlign: pmAlign(o.align),
              style: _textStyle(o).copyWith(color: const Color(0xFF94A3B8), fontStyle: FontStyle.italic, shadows: const <Shadow>[]),
              strutStyle: _strut(o),
            )
          : _styledText(o, text, pmAlign(o.align)),
    );
  }

  Widget _photoBox(Uint8List? bytes, Map<String, String> rec,
      {required bool preview, required String fit, bool isImage = false}) {
    final img = _provider(bytes);
    if (img != null) {
      return Image(
        image: img,
        fit: fit == 'contain' ? BoxFit.contain : (fit == 'fill' ? BoxFit.fill : BoxFit.cover),
        gaplessPlayback: true,
        width: double.infinity,
        height: double.infinity,
      );
    }
    if (preview) return const SizedBox.expand();
    return Container(
      color: const Color(0xFFE2E8F0),
      alignment: Alignment.center,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
        Icon(isImage ? Icons.image_outlined : Icons.person, color: const Color(0xFF64748B), size: 36),
        Text(isImage ? 'ચિત્ર' : 'ફોટો', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
      ]),
    );
  }

  // ------------------------------- inspector ---------------------------------

  Widget _box(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(9),
        decoration:
            BoxDecoration(color: _panelDark, borderRadius: BorderRadius.circular(8), border: Border.all(color: _line)),
        child: Material(
          type: MaterialType.transparency,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF93C5FD))),
            const SizedBox(height: 6),
            ...children,
          ]),
        ),
      );

  Widget _num(String label, double value, double min, double max, double step, ValueChanged<double> onChanged,
          {int decimals = 0}) =>
      Row(children: <Widget>[
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: value <= min ? null : () => onChanged((value - step).clamp(min, max)),
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
            width: 46,
            child: Text(value.toStringAsFixed(decimals),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: value >= max ? null : () => onChanged((value + step).clamp(min, max)),
          icon: const Icon(Icons.add),
        ),
      ]);

  Widget _inspector() {
    final o = _primary;
    final p = _page;
    Widget tabList(List<Widget> children) => ListView(padding: const EdgeInsets.all(8), children: children);
    return Container(
      width: 320,
      decoration: const BoxDecoration(color: _panel, border: Border(left: BorderSide(color: _line))),
      child: DefaultTabController(
        length: 4,
        child: Column(children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            color: _panelDark,
            child: Row(children: <Widget>[
              IconButton(
                tooltip: 'પહેલો રેકોર્ડ',
                visualDensity: VisualDensity.compact,
                onPressed: _rows.isEmpty ? null : () => setState(() => _recIdx = 0),
                icon: const Icon(Icons.first_page),
              ),
              IconButton(
                tooltip: 'પાછલો રેકોર્ડ',
                visualDensity: VisualDensity.compact,
                onPressed: _recIdx <= 0 ? null : () => setState(() => _recIdx--),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  'રેકોર્ડ ${_rows.isEmpty ? 0 : _recIdx + 1} / ${_rows.length}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF93C5FD)),
                ),
              ),
              IconButton(
                tooltip: 'આગળનો રેકોર્ડ',
                visualDensity: VisualDensity.compact,
                onPressed: _recIdx >= _rows.length - 1 ? null : () => setState(() => _recIdx++),
                icon: const Icon(Icons.chevron_right),
              ),
              IconButton(
                tooltip: 'છેલ્લો રેકોર્ડ',
                visualDensity: VisualDensity.compact,
                onPressed: _rows.isEmpty ? null : () => setState(() => _recIdx = _rows.length - 1),
                icon: const Icon(Icons.last_page),
              ),
            ]),
          ),
          const Material(
            color: _panelDark,
            child: TabBar(
              labelPadding: EdgeInsets.zero,
              labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              tabs: <Widget>[
                Tab(icon: Icon(Icons.tune_rounded, size: 18), text: 'ગુણધર્મ', height: 48),
                Tab(icon: Icon(Icons.photo_filter_rounded, size: 18), text: 'PowerClip', height: 48),
                Tab(icon: Icon(Icons.wallpaper_rounded, size: 18), text: 'પાનું', height: 48),
                Tab(icon: Icon(Icons.layers_rounded, size: 18), text: 'સ્તર', height: 48),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(children: <Widget>[
              tabList(o == null
                  ? <Widget>[
                      _box('ઑબ્જેક્ટ', const <Widget>[
                        Text(
                          'ઑબ્જેક્ટ પર ક્લિક કરો. Shift+ક્લિક કે ખાલી જગ્યામાં ખેંચીને ઘણા પસંદ કરો.\n'
                          'ડબલ-ક્લિક: ખાલી જગ્યામાં નવું લખાણ, લખાણ કે આકાર પર લખાણ બદલો.\n'
                          'ખૂણાના ચોરસ ખેંચી મોટું / નાનું કરો.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), height: 1.5),
                        ),
                      ]),
                    ]
                  : <Widget>[
                      _contentBox(o),
                      if (o.isTextual || (o.type == 'shape' && o.shapeKind != 'line')) _fontBox(o),
                      _colourBox(o),
                      _geometryBox(o),
                    ]),
              tabList(<Widget>[_powerClipTab(o)]),
              tabList(<Widget>[if (p != null) _pageBox(p)]),
              tabList(<Widget>[if (p != null) _layersBox(p)]),
            ]),
          ),
        ]),
      ),
    );
  }

  // ------------------------------- PowerClip ---------------------------------

  Future<void> _importLibrary() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true, withData: true);
    if (res == null) return;
    var n = 0;
    for (final f in res.files) {
      if (f.bytes == null) continue;
      final id = 'img_${_uid()}';
      _images[id] = f.bytes!;
      _addToLibrary(id, f.name);
      n++;
    }
    setState(() {});
    if (n > 0) _notify('$n ફોટા ઉમેર્યા — આકાર પસંદ કરી ફોટા પર ક્લિક કરો');
  }

  /// Gallery click: inside the selected shape (PowerClip), into the selected
  /// picture frame, or as a new picture.
  void _useLibraryImage(String id) {
    final o = _primary;
    if (o != null && o.type == 'shape' && o.shapeKind != 'line') {
      _change((x) {
        x.clipMode = 'image';
        x.clipImageId = id;
        x
          ..clipScale = 100
          ..clipX = 0
          ..clipY = 0;
      });
      _notify('ફોટો આકારની અંદર મૂક્યો (PowerClip)');
    } else if (o != null && (o.type == 'image' || o.type == 'photo')) {
      _change((x) {
        x.type = 'image';
        x.imageId = id;
      });
    } else {
      _addObject(PmObject(id: _uid(), type: 'image', imageId: id, x: 300, y: 300, w: 180, h: 180, fit: 'contain'));
    }
  }

  void _extractClip(PmObject o) {
    final p = _page;
    if (p == null || o.clipMode == 'none') return;
    _saveHistory();
    setState(() {
      final copy = o.clipMode == 'image'
          ? PmObject(id: _uid(), type: 'image', imageId: o.clipImageId, x: o.x + 20, y: o.y + 20, w: o.w, h: o.h, fit: 'cover')
          : PmObject(id: _uid(), type: 'photo', key: o.clipKey, x: o.x + 20, y: o.y + 20, w: o.w, h: o.h, fit: 'cover');
      o.clipMode = 'none';
      p.objects.add(copy);
      _select(copy.id);
      _clipDrag = false;
    });
  }

  Widget _powerClipTab(PmObject? o) {
    final isShape = o != null && o.type == 'shape' && o.shapeKind != 'line';
    final photoCols = _headers.where((h) => _photoCol.hasMatch(h)).toList();
    final target = !isShape
        ? (o != null && (o.type == 'image' || o.type == 'photo') ? 'ચિત્રની જગ્યાએ મૂકાશે' : 'નવા ચિત્ર તરીકે ઉમેરાશે')
        : 'પસંદ કરેલા ${kPmShapeNames[o.shapeKind] ?? 'આકાર'}ની અંદર મૂકાશે';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      _box('PowerClip — આકારની અંદર ફોટો', <Widget>[
        const Text(
          '1. ડાબી બાજુથી આકાર ઉમેરો અને પસંદ કરો.\n2. ફોટા ઇમ્પોર્ટ કરો.\n3. નીચે ફોટા પર ક્લિક કરો — ફોટો આકારની અંદર ગોઠવાશે.',
          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), height: 1.5),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _importLibrary,
          icon: const Icon(Icons.add_photo_alternate_rounded),
          label: const Text('ફોટા ઇમ્પોર્ટ કરો'),
        ),
        const SizedBox(height: 8),
        Text('ફોટા પર ક્લિક: $target', style: const TextStyle(fontSize: 11.5, color: Color(0xFFFBBF24))),
        const SizedBox(height: 6),
        if (_library.isEmpty)
          const Text('હજી કોઈ ફોટો ઇમ્પોર્ટ કર્યો નથી.', style: TextStyle(fontSize: 12))
        else
          Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
            for (final id in _library)
              if (_images[id] != null)
                Tooltip(
                  message: _libraryNames[id] ?? '',
                  child: InkWell(
                    onTap: () => _useLibraryImage(id),
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: (isShape && o.clipMode == 'image' && o.clipImageId == id)
                              ? const Color(0xFFF59E0B)
                              : _line,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image(image: _provider(_images[id])!, fit: BoxFit.cover, gaplessPlayback: true),
                    ),
                  ),
                ),
          ]),
      ]),
      if (isShape)
        _box('વિદ્યાર્થીનો ફોટો (દરેક રેકોર્ડ મુજબ)', <Widget>[
          const Text('માહિતીના Photo કૉલમ અને "ફોટા ઉમેરો" (માહિતી ટેબ) મુજબ દરેક પ્રમાણપત્રમાં જુદો ફોટો.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8))),
          const SizedBox(height: 6),
          FilledButton.tonalIcon(
            onPressed: _headers.isEmpty
                ? null
                : () => _change((x) {
                      x.clipMode = 'photo';
                      x.clipKey = photoCols.isNotEmpty ? photoCols.first : _headers.first;
                      x
                        ..clipScale = 100
                        ..clipX = 0
                        ..clipY = 0;
                    }),
            icon: const Icon(Icons.portrait_rounded),
            label: const Text('આકારમાં વિદ્યાર્થીનો ફોટો'),
          ),
          if (o.clipMode == 'photo')
            DropdownButtonFormField<String>(
              value: _headers.contains(o.clipKey) ? o.clipKey : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'ફોટાનો કૉલમ'),
              items: <DropdownMenuItem<String>>[for (final h in _headers) DropdownMenuItem<String>(value: h, child: Text(h))],
              onChanged: (v) {
                if (v != null) _change((x) => x.clipKey = v);
              },
            ),
        ]),
      if (isShape && o.clipMode != 'none')
        _box('અંદરનો ફોટો ગોઠવો', <Widget>[
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('ફોટો ખેંચીને ગોઠવો', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            subtitle: const Text('આકાર પર ખેંચો = ફોટો ખસે, માઉસ વ્હીલ = મોટું / નાનું', style: TextStyle(fontSize: 11)),
            value: _clipDrag,
            onChanged: (v) => setState(() => _clipDrag = v),
          ),
          _num('મોટું / નાનું (%)', o.clipScale, 20, 300, 5, (v) => _change((x) => x.clipScale = v)),
          _num('આડું ખસેડો', o.clipX, -400, 400, 5, (v) => _change((x) => x.clipX = v)),
          _num('ઊભું ખસેડો', o.clipY, -400, 400, 5, (v) => _change((x) => x.clipY = v)),
          Wrap(spacing: 4, children: <Widget>[
            TextButton.icon(
              onPressed: () => _change((x) => x
                ..clipScale = 100
                ..clipX = 0
                ..clipY = 0),
              icon: const Icon(Icons.center_focus_strong_rounded, size: 18),
              label: const Text('મધ્યમાં'),
            ),
            TextButton.icon(
              onPressed: () => _extractClip(o),
              icon: const Icon(Icons.open_in_full_rounded, size: 18),
              label: const Text('બહાર કાઢો'),
            ),
            TextButton.icon(
              onPressed: () => _change((x) => x.clipMode = 'none'),
              icon: const Icon(Icons.delete_outline, color: Color(0xFFFCA5A5), size: 18),
              label: const Text('કાઢી નાખો', style: TextStyle(color: Color(0xFFFCA5A5))),
            ),
          ]),
        ]),
    ]);
  }

  Widget _contentBox(PmObject o) {
    final typeName = switch (o.type) {
      'text' => 'મર્જ લખાણ',
      'static' => 'લખાણ',
      'photo' => 'ફોટો ફ્રેમ',
      'image' => 'ચિત્ર',
      _ => kPmShapeNames[o.shapeKind] ?? 'આકાર',
    };
    final children = <Widget>[];
    if (o.type == 'text' || o.type == 'photo') {
      children.add(DropdownButtonFormField<String>(
        value: _headers.contains(o.key) ? o.key : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'કૉલમ'),
        items: <DropdownMenuItem<String>>[
          for (final h in _headers) DropdownMenuItem<String>(value: h, child: Text(h, overflow: TextOverflow.ellipsis)),
        ],
        hint: Text(o.key.isEmpty ? 'કૉલમ પસંદ કરો' : '${o.key} (માહિતીમાં નથી)'),
        onChanged: (v) {
          if (v != null) _change((x) => x.key = v);
        },
      ));
    }
    if (o.type == 'text') {
      children.add(const SizedBox(height: 8));
      children.add(
          _textField('આગળનું લખાણ', o.prefix, (v) => _change((x) => x.prefix = v, history: false), key: 'pre${o.id}'));
      children.add(const SizedBox(height: 8));
      children.add(
          _textField('પાછળનું લખાણ', o.suffix, (v) => _change((x) => x.suffix = v, history: false), key: 'suf${o.id}'));
    }
    if (o.type == 'static' || (o.type == 'shape' && o.shapeKind != 'line')) {
      children.add(_textField(o.type == 'shape' ? 'આકારમાં લખાણ' : 'લખાણ', o.customText,
          (v) => _change((x) => x.customText = v, history: false),
          key: 'txt${o.id}', multiline: true));
    }
    if (o.type == 'photo' || o.type == 'image') {
      children.add(const SizedBox(height: 8));
      children.add(SegmentedButton<String>(
        segments: const <ButtonSegment<String>>[
          ButtonSegment<String>(value: 'cover', label: Text('ભરો')),
          ButtonSegment<String>(value: 'contain', label: Text('આખું')),
          ButtonSegment<String>(value: 'fill', label: Text('ખેંચો')),
        ],
        selected: <String>{o.fit},
        onSelectionChanged: (v) => _change((x) => x.fit = v.first),
      ));
    }
    if (o.type == 'image') {
      children.add(TextButton.icon(
        onPressed: () async {
          final b = await _pickImageBytes();
          if (b == null) return;
          final id = 'img_${_uid()}';
          _images[id] = b;
          _change((x) => x.imageId = id);
        },
        icon: const Icon(Icons.image_search_rounded),
        label: const Text('ચિત્ર બદલો'),
      ));
    }
    return _box('$typeName${_selected.length > 1 ? ' (${_selected.length} પસંદ)' : ''}', children);
  }

  String? _typingKey;

  /// Inspector text field; the first keystroke in a field records one undo step.
  Widget _textField(String label, String value, ValueChanged<String> onChanged,
          {required String key, bool multiline = false}) =>
      TextFormField(
        key: ValueKey<String>(key),
        initialValue: value,
        minLines: 1,
        maxLines: multiline ? 4 : 1,
        decoration: InputDecoration(labelText: label),
        onChanged: (v) {
          if (_typingKey != key) {
            _saveHistory();
            _typingKey = key;
          }
          onChanged(v);
        },
      );

  Widget _fontBox(PmObject o) => _box('અક્ષર', <Widget>[
        DropdownButtonFormField<String>(
          value: kPmFonts.any((f) => f.$1 == o.font) ? o.font : kPmFonts.first.$1,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'ફોન્ટ'),
          items: <DropdownMenuItem<String>>[
            for (final f in kPmFonts)
              DropdownMenuItem<String>(value: f.$1, child: Text(f.$2, style: TextStyle(fontFamily: f.$1))),
          ],
          onChanged: (v) async {
            if (v == null) return;
            await _ensureFont(v);
            _change((x) => x.font = v);
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          value: null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'તૈયાર શૈલી'),
          hint: const Text('શૈલી પસંદ કરો…'),
          items: <DropdownMenuItem<int>>[
            for (var i = 0; i < kPmTextStyles.length; i++)
              DropdownMenuItem<int>(value: i, child: Text(kPmTextStyles[i].$1)),
          ],
          onChanged: (i) {
            if (i == null) return;
            final st = kPmTextStyles[i];
            _change((x) {
              x
                ..size = st.$2
                ..bold = st.$3
                ..color = st.$4
                ..outlineW = st.$6;
              if (x.type != 'shape') x.align = st.$5;
              if (st.$6 > 0) x.outlineC = '#7C2D12';
            });
          },
        ),
        _num('કદ', o.size, 6, 120, 1, (v) => _change((x) => x.size = v)),
        _num('લીટી અંતર', o.lineH, 0.8, 3, 0.05, (v) => _change((x) => x.lineH = v), decimals: 2),
        Row(children: <Widget>[
          _toggleBtn('B', o.bold, () => _change((x) => x.bold = !o.bold), bold: true),
          _toggleBtn('I', o.italic, () => _change((x) => x.italic = !o.italic), italic: true),
          _toggleBtn('U', o.underline, () => _change((x) => x.underline = !o.underline), underline: true),
        ]),
        if (o.type != 'shape') ...<Widget>[
          const SizedBox(height: 6),
          SegmentedButton<String>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(value: 'left', icon: Icon(Icons.format_align_left, size: 16)),
              ButtonSegment<String>(value: 'center', icon: Icon(Icons.format_align_center, size: 16)),
              ButtonSegment<String>(value: 'right', icon: Icon(Icons.format_align_right, size: 16)),
            ],
            selected: <String>{o.align == 'justify' ? 'left' : o.align},
            onSelectionChanged: (v) => _change((x) => x.align = v.first),
          ),
        ],
        const Divider(height: 18),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('અક્ષરની કિનારી (Outline)', style: TextStyle(fontSize: 12)),
          value: o.outlineW > 0,
          onChanged: (v) => _change((x) => x.outlineW = v ? 1.2 : 0),
        ),
        if (o.outlineW > 0) ...<Widget>[
          _num('કિનારીની જાડાઈ', o.outlineW, 0.4, 6, 0.2, (v) => _change((x) => x.outlineW = v), decimals: 1),
          Wrap(spacing: 4, runSpacing: 4, children: <Widget>[
            for (final hex in const <String>['#FFFFFF', '#000000', '#7C2D12', '#1E3A8A', '#B45309', '#047857', '#BE185D'])
              _swatch(hex, o.outlineC.toUpperCase() == hex, () => _change((x) => x.outlineC = hex)),
          ]),
        ],
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('પડછાયો (Shadow)', style: TextStyle(fontSize: 12)),
          value: o.shadow,
          onChanged: (v) => _change((x) => x.shadow = v),
        ),
        if (o.shadow)
          Wrap(spacing: 4, runSpacing: 4, children: <Widget>[
            for (final hex in const <String>['#94A3B8', '#475569', '#000000', '#FDE68A', '#FCA5A5'])
              _swatch(hex, o.shadowC.toUpperCase() == hex, () => _change((x) => x.shadowC = hex)),
          ]),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('ગુજરાતી અંક (૧૨૩)', style: TextStyle(fontSize: 12)),
          value: o.gujDigits,
          onChanged: (v) => _change((x) => x.gujDigits = v),
        ),
      ]);

  Widget _toggleBtn(String label, bool on, VoidCallback onTap,
          {bool bold = false, bool italic = false, bool underline = false}) =>
      Padding(
        padding: const EdgeInsets.only(right: 4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? const Color(0xFF3B82F6) : const Color(0xFF2F3541),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: on ? _accent : const Color(0xFF4C566A)),
            ),
            child: Text(label,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
                  fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                  decoration: underline ? TextDecoration.underline : TextDecoration.none,
                )),
          ),
        ),
      );

  Widget _colourBox(PmObject o) {
    final targets = <(String, String)>[
      if (o.isTextual || (o.type == 'shape' && o.shapeKind != 'line')) ('text', 'અક્ષર'),
      if (!(o.type == 'shape' && o.shapeKind == 'line')) ('fill', 'અંદરનો રંગ'),
      ('outline', 'કિનારી'),
    ];
    final target = targets.any((t) => t.$1 == _paintTarget) ? _paintTarget : targets.first.$1;
    String current() => switch (target) {
          'text' => o.color,
          'fill' => o.noFill ? 'none' : o.fill,
          _ => o.hasBorder ? o.borderC : 'none',
        };
    void apply(String hex) => _change((x) {
          switch (target) {
            case 'text':
              if (hex != 'none') x.color = hex;
            case 'fill':
              if (hex == 'none') {
                x.noFill = true;
              } else {
                x.noFill = false;
                x.fill = hex;
              }
            default:
              if (hex == 'none') {
                x.borderW = 0;
              } else {
                x.borderC = hex;
                if (x.borderW <= 0) x.borderW = x.type == 'shape' ? 2 : 1;
              }
          }
        });
    final cur = current().toUpperCase();
    return _box('રંગ', <Widget>[
      SegmentedButton<String>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: <ButtonSegment<String>>[
          for (final t in targets)
            ButtonSegment<String>(value: t.$1, label: Text(t.$2, style: const TextStyle(fontSize: 11))),
        ],
        selected: <String>{target},
        onSelectionChanged: (v) => setState(() => _paintTarget = v.first),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 4, runSpacing: 4, children: <Widget>[
        if (target != 'text') _swatch(null, cur == 'NONE', () => apply('none')),
        for (final hex in kPmPalette) _swatch(hex, cur == hex.toUpperCase(), () => apply(hex)),
      ]),
      if (target == 'outline' && o.hasBorder)
        _num('કિનારીની જાડાઈ', o.borderW, 0.5, 20, 0.5, (v) => _change((x) => x.borderW = v), decimals: 1),
      if (o.type != 'shape' || o.shapeKind == 'roundrect' || o.shapeKind == 'rect' || o.shapeKind == 'square')
        _num('ગોળ ખૂણા', o.radius, 0, 200, 2, (v) => _change((x) => x.radius = v)),
      Row(children: <Widget>[
        const Text('પારદર્શકતા', style: TextStyle(fontSize: 12)),
        Expanded(
          child: Slider(
            value: o.opacity.clamp(5.0, 100.0),
            min: 5,
            max: 100,
            onChangeStart: (_) => _saveHistory(),
            onChanged: (v) => _change((x) => x.opacity = v.roundToDouble(), history: false),
          ),
        ),
        SizedBox(width: 36, child: Text('${o.opacity.round()}%', style: const TextStyle(fontSize: 12))),
      ]),
    ]);
  }

  Widget _swatch(String? hex, bool selected, VoidCallback onTap) => Tooltip(
        message: hex ?? 'રંગ નહીં',
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: hex == null ? Colors.white : pmColor(hex),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: selected ? const Color(0xFFF59E0B) : Colors.white38, width: selected ? 2.5 : 1),
            ),
            child: hex == null ? const Icon(Icons.block, size: 16, color: Colors.red) : null,
          ),
        ),
      );

  Widget _geometryBox(PmObject o) {
    const mm = PmA4.mmW / PmA4.w;
    return _box('સ્થાન અને માપ (mm)', <Widget>[
      _num('X (ડાબેથી)', o.x * mm, -50, 210, 1, (v) => _change((x) => x.x = v / mm, geometry: true)),
      _num('Y (ઉપરથી)', o.y * mm, -50, 297, 1, (v) => _change((x) => x.y = v / mm, geometry: true)),
      _num('પહોળાઈ', o.w * mm, 2, 210, 1, (v) => _change((x) => x.w = v / mm, geometry: true)),
      _num('ઊંચાઈ', o.h * mm, 1, 297, 1, (v) => _change((x) => x.h = v / mm, geometry: true)),
      _num('ફેરવો (°)', o.rotate, -180, 180, 5, (v) => _change((x) => x.rotate = v, geometry: true)),
    ]);
  }

  Widget _pageBox(PmPage p) => _box('પાનું ${_pageIdx + 1}', <Widget>[
        _textField('પાનાનું નામ', p.name, (v) {
          setState(() => p.name = v.trim().isEmpty ? 'પાનું ${_pageIdx + 1}' : v.trim());
          _autosaveSoon();
        }, key: 'pg${p.id}'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: p.theme,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'ફ્રેમ'),
          items: <DropdownMenuItem<String>>[
            for (final t in kPmThemes) DropdownMenuItem<String>(value: t.$1, child: Text(t.$2))
          ],
          onChanged: (v) {
            if (v == null) return;
            _saveHistory();
            setState(() => p.theme = v);
          },
        ),
        const SizedBox(height: 6),
        Row(children: <Widget>[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                final b = await _pickImageBytes();
                if (b == null) return;
                final id = 'bg_${_uid()}';
                _images[id] = b;
                _saveHistory();
                setState(() => p.bgImageId = id);
              },
              icon: const Icon(Icons.wallpaper_rounded, size: 18),
              label: Text(p.bgImageId.isEmpty ? 'પૃષ્ઠભૂમિ ચિત્ર' : 'પૃષ્ઠભૂમિ બદલો',
                  style: const TextStyle(fontSize: 12)),
            ),
          ),
          if (p.bgImageId.isNotEmpty)
            IconButton(
              tooltip: 'પૃષ્ઠભૂમિ કાઢો',
              onPressed: () {
                _saveHistory();
                setState(() => p.bgImageId = '');
              },
              icon: const Icon(Icons.close),
            ),
        ]),
        if (p.bgImageId.isNotEmpty && _pages.length > 1)
          TextButton.icon(
            onPressed: () {
              _saveHistory();
              setState(() {
                for (final pg in _pages) {
                  pg.bgImageId = p.bgImageId;
                }
              });
              _notify('પૃષ્ઠભૂમિ બધાં ${_pages.length} પાનાં પર લાગુ કરી');
            },
            icon: const Icon(Icons.copy_all_rounded, size: 18),
            label: const Text('આ પૃષ્ઠભૂમિ બધાં પાનાં પર'),
          ),
        const Text(
            'આખા A4 પાના પર પૃષ્ઠભૂમિ ચિત્ર (દા.ત. છાપેલા પ્રમાણપત્ર કે પ્રશ્નપત્રનું સ્કેન). તેના પર ખાનાં ગોઠવો — દરેક રેકોર્ડ માટે નવું પાનું બનશે.',
            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
      ]);

  Widget _layersBox(PmPage p) => _box('ઑબ્જેક્ટ (${p.objects.length})', <Widget>[
        SizedBox(
          height: math.min(260, 30.0 * p.objects.length + 4),
          child: ListView.builder(
            itemCount: p.objects.length,
            itemBuilder: (_, i) {
              final o = p.objects[p.objects.length - 1 - i];
              final label = switch (o.type) {
                'text' => '«${o.key}»',
                'static' => o.customText.isEmpty ? 'લખાણ' : o.customText,
                'photo' => 'ફોટો «${o.key}»',
                'image' => 'ચિત્ર',
                _ => '${kPmShapeNames[o.shapeKind] ?? o.shapeKind}${o.customText.isEmpty ? '' : ': ${o.customText}'}',
              };
              return InkWell(
                onTap: () => setState(() {
                  _stopEditing(commit: true);
                  _select(o.id);
                }),
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  color: _isSelected(o.id) ? const Color(0x383B82F6) : Colors.transparent,
                  child: Row(children: <Widget>[
                    Expanded(child: Text(label, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                    if (o.locked) const Icon(Icons.lock, size: 13, color: Color(0xFFFCA5A5)),
                  ]),
                ),
              );
            },
          ),
        ),
      ]);

  // ------------------------------ output view --------------------------------

  Widget _outputView() {
    final total = _rows.length;
    final int from = _fromRec.clamp(1, math.max(1, total)).toInt();
    final int to = _toRec.clamp(from, math.max(1, total)).toInt();
    final count = total == 0 ? 0 : to - from + 1;
    final itemsPerRecord = _pages.length + (_padOdd && _pages.length.isOdd ? 1 : 0);
    final sheets = (count * itemsPerRecord / _perSheet).ceil();
    final grid = PmPdfExporter.grid(_perSheet, _gapMm);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            const Text('PDF તૈયાર કરો', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: <Widget>[
              _metric('$count', 'રેકોર્ડ'),
              _metric('${_pages.length}', 'પાનાં / રેકોર્ડ'),
              _metric('$sheets', 'કુલ A4 શીટ'),
              _metric('${_photos.length ~/ 2}', 'ફોટા'),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.start, children: <Widget>[
              SizedBox(
                width: 420,
                child: _box('રેકોર્ડ અને વિકલ્પો', <Widget>[
                  _num('શરૂઆત (રેકોર્ડ નં.)', from.toDouble(), 1, math.max(1, total).toDouble(), 1,
                      (v) => setState(() => _fromRec = v.round())),
                  _num('છેલ્લે (રેકોર્ડ નં.)', to.toDouble(), from.toDouble(), math.max(1, total).toDouble(), 1,
                      (v) => setState(() => _toRec = v.round())),
                  Row(children: <Widget>[
                    TextButton(
                        onPressed: () => setState(() {
                              _fromRec = 1;
                              _toRec = math.max(1, total);
                            }),
                        child: const Text('બધા')),
                    TextButton(
                        onPressed: total == 0
                            ? null
                            : () => setState(() {
                                  _fromRec = _recIdx + 1;
                                  _toRec = _recIdx + 1;
                                }),
                        child: const Text('ફક્ત હાલનો રેકોર્ડ')),
                  ]),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('બંને બાજુ છાપવા (એકી પાનાં પછી ખાલી પાનું)'),
                    value: _padOdd,
                    onChanged: (v) => setState(() => _padOdd = v),
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('ફોટા વગર છાપો'),
                    value: _noPhoto,
                    onChanged: (v) => setState(() => _noPhoto = v),
                  ),
                ]),
              ),
              SizedBox(
                width: 420,
                child: _box('એક A4 શીટ પર કેટલા', <Widget>[
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    value: _perSheet,
                    decoration: const InputDecoration(labelText: 'ગોઠવણી'),
                    items: const <DropdownMenuItem<int>>[
                      DropdownMenuItem<int>(value: 1, child: Text('1 — આખું A4')),
                      DropdownMenuItem<int>(value: 2, child: Text('2 — અડધું A4 (A5)')),
                      DropdownMenuItem<int>(value: 4, child: Text('4 — ચોથા ભાગનું (A6 કાર્ડ)')),
                      DropdownMenuItem<int>(value: 8, child: Text('8 — ઓળખ / બેઠક કાર્ડ')),
                      DropdownMenuItem<int>(value: 12, child: Text('12 — નાની સ્લિપ')),
                    ],
                    onChanged: (v) => setState(() => _perSheet = v ?? 1),
                  ),
                  if (_perSheet > 1) ...<Widget>[
                    const SizedBox(height: 6),
                    Text('${grid.$1 ? 'આડી' : 'ઊભી'} A4 શીટ: ${grid.$2} × ${grid.$3}',
                        style: const TextStyle(fontSize: 12)),
                    _num('બે વચ્ચે જગ્યા (mm)', _gapMm, 0, 20, 1, (v) => setState(() => _gapMm = v)),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('કાપવાની નિશાની (crop marks)'),
                      value: _crop,
                      onChanged: (v) => setState(() => _crop = v),
                    ),
                  ],
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            _box('પ્રથમ શીટનું પૂર્વાવલોકન', <Widget>[
              Center(child: _sheetPreview(from, grid)),
            ]),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
                onPressed: _busy || count == 0 || _pages.isEmpty ? null : () => _generatePdf(from, to),
                icon: const Icon(Icons.picture_as_pdf_rounded),
                label: Text(count == 0 ? 'પહેલાં માહિતી ઉમેરો' : 'PDF બનાવો ($count રેકોર્ડ, $sheets શીટ)'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _sheetPreview(int from, (bool, int, int) grid) {
    final landscape = grid.$1;
    final cols = grid.$2, rows = grid.$3;
    final sw = landscape ? 420.0 : 297.0;
    final sh = landscape ? 297.0 : 420.0;
    final items = <(PmPage?, Map<String, String>)>[];
    for (var r = from - 1; r < _rows.length && items.length < _perSheet; r++) {
      for (final p in _pages) {
        if (items.length < _perSheet) items.add((p, _rows[r]));
      }
      if (_padOdd && _pages.length.isOdd && items.length < _perSheet) items.add((null, _rows[r]));
    }
    final cellW = (sw - 12) / cols, cellH = (sh - 12) / rows;
    return Container(
      width: sw,
      height: sh,
      color: Colors.white,
      padding: const EdgeInsets.all(6),
      child: Wrap(children: <Widget>[
        for (var i = 0; i < cols * rows; i++)
          SizedBox(
            width: cellW,
            height: cellH,
            child: Padding(
              padding: EdgeInsets.all(_perSheet > 1 ? 2 : 0),
              child: i < items.length && items[i].$1 != null
                  ? FittedBox(child: _artboard(items[i].$1!, interactive: false, record: items[i].$2))
                  : Container(color: const Color(0xFFF1F5F9)),
            ),
          ),
      ]),
    );
  }

  Widget _metric(String v, String label) => Container(
        width: 200,
        padding: const EdgeInsets.all(12),
        decoration:
            BoxDecoration(color: _panelDark, borderRadius: BorderRadius.circular(8), border: Border.all(color: _line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _accent)),
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
        ]),
      );

  Future<void> _generatePdf(int from, int to) async {
    setState(() => _busy = true);
    final status = ValueNotifier<String>('તૈયાર થાય છે…');
    final progress = ValueNotifier<double?>(null);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('PDF બને છે'),
        content:
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          ValueListenableBuilder<String>(valueListenable: status, builder: (_, v, __) => Text(v)),
          const SizedBox(height: 12),
          ValueListenableBuilder<double?>(
              valueListenable: progress, builder: (_, v, __) => LinearProgressIndicator(value: v)),
        ]),
      ),
    );
    try {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await _ensureDesignFonts();
      final bytes = await PmPdfExporter.build(
        pages: _pages,
        records: _rows.sublist(from - 1, to),
        images: _images,
        photoFor: _photoFor,
        perSheet: _perSheet,
        gapMm: _gapMm,
        cropMarks: _crop,
        padOddPages: _padOdd,
        noPhoto: _noPhoto,
        onProgress: (stage, p) {
          status.value = switch (stage) {
            'layout' => 'લખાણ ગોઠવાય છે… ${(p * 100).round()}%',
            'text' => 'ગુજરાતી અક્ષર તૈયાર થાય છે… ${(p * 100).round()}%',
            'pages' => 'પાનાં બને છે… ${(p * 100).round()}%',
            _ => 'PDF સેવ થાય છે…',
          };
          progress.value = stage == 'save' ? null : p;
        },
      );
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await PsmFileExportHelper.saveOrShare(
        bytes: bytes,
        filename: 'print_merge_${from}_$to.pdf',
        title: 'Print merge PDF',
        mimeType: 'application/pdf',
      );
      _notify('PDF તૈયાર (${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB)');
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      _notify('PDF બની શકી નહીં: $e', error: true);
    } finally {
      status.dispose();
      progress.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------ status bar ---------------------------------

  Widget _statusBar() => Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(color: Color(0xFF14171D), border: Border(top: BorderSide(color: _line))),
        child: Row(children: <Widget>[
          ValueListenableBuilder<Offset>(
            valueListenable: _cursorMm,
            builder: (_, v, __) => Text('X ${v.dx.toStringAsFixed(1)}  Y ${v.dy.toStringAsFixed(1)} mm',
                style: const TextStyle(fontSize: 11, color: _accent, fontWeight: FontWeight.w600)),
          ),
          _divider(),
          Expanded(
            child: Text(
              'ડબલ-ક્લિક: લખાણ  ·  Shift+ક્લિક: ઘણા પસંદ  ·  Ctrl+A / Z / Y / D / L  ·  તીર: ખસેડો (Shift = 10)  ·  Delete: કાઢો  ·  ${_selected.isEmpty ? '' : '${_selected.length} પસંદ'}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      );
}

class _BarChip extends StatelessWidget {
  const _BarChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF2F3541),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF4C566A)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Icon(icon, size: 16, color: const Color(0xFFCBD5E1)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFFF1F5F9), fontWeight: FontWeight.w600)),
          const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFFCBD5E1)),
        ]),
      );
}

/// Toolbox icon drawn with the same geometry as the shape itself, so it
/// always shows (no font glyphs needed).
class _ShapeIconPainter extends CustomPainter {
  const _ShapeIconPainter(this.kind);
  final String kind;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white;
    if (kind == 'line') {
      canvas.drawLine(Offset(2, size.height - 3), Offset(size.width - 2, 3), paint);
      return;
    }
    var box = Size(size.width, size.height);
    var dx = 0.0;
    if (kind == 'square' || kind == 'ellipse' || kind == 'diamond' || kind == 'polygon' || kind == 'star') {
      box = Size(size.height, size.height);
      dx = (size.width - size.height) / 2;
    } else if (kind == 'banner' || kind == 'arrow' || kind == 'oval') {
      box = Size(size.width, size.height * 0.7);
    }
    canvas.save();
    canvas.translate(dx, (size.height - box.height) / 2);
    final path = PmShapes.path(kind, box, 1.5, kind == 'roundrect' ? 6 : 0);
    canvas.drawPath(path, Paint()..color = const Color(0x553B82F6));
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ShapeIconPainter old) => old.kind != kind;
}

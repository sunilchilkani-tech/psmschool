// ============================================================================
// ID Card Studio Pro — High-Speed Modular Flutter / Dart Implementation
// ============================================================================
// Split into clean `part` files under `lib/screens/id_card_studio_parts/`
// for fast compilation, cached rendering, zero-lag pointer dragging,
// Principal Signature overlay, Photo Folder upload, and uniform photo frames.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:excel_community/excel_community.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' as html;

import '../services/class_label.dart';
import '../services/psm_file_export_helper.dart';
import '../theme/responsive.dart';

part 'id_card_studio_parts/id_card_models.dart';
part 'id_card_studio_parts/id_card_painters.dart';
part 'id_card_studio_parts/id_card_data_and_actions.dart';
part 'id_card_studio_parts/id_card_sidebar_tabs.dart';
part 'id_card_studio_parts/id_card_stage_and_canvas.dart';

void main() {
  runApp(const IdCardStudioDemoApp());
}

/// Standalone MaterialApp wrapper if you want to run this file directly.
class IdCardStudioDemoApp extends StatefulWidget {
  const IdCardStudioDemoApp({super.key});

  @override
  State<IdCardStudioDemoApp> createState() => _IdCardStudioDemoAppState();
}

class _IdCardStudioDemoAppState extends State<IdCardStudioDemoApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ID Card Studio Pro',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0D7480),
        brightness: Brightness.light,
        fontFamily: 'NotoSansGujaratiLocal',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF22B8CF),
        brightness: Brightness.dark,
        fontFamily: 'NotoSansGujaratiLocal',
      ),
      home: IdCardStudioScreen(onToggleTheme: _toggleTheme),
    );
  }
}

class SupabaseIdCardStudioScreen extends StatefulWidget {
  const SupabaseIdCardStudioScreen({super.key});

  @override
  State<SupabaseIdCardStudioScreen> createState() =>
      _SupabaseIdCardStudioScreenState();
}

class _SupabaseIdCardStudioScreenState
    extends State<SupabaseIdCardStudioScreen> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  Future<void> _handleExportPng(Uint8List pngBytes, String fileName) async {
    await PsmFileExportHelper.saveOrShare(
      bytes: pngBytes,
      filename: fileName,
      title: fileName,
      mimeType: 'image/png',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _themeMode == ThemeMode.dark
          ? ThemeData(
              useMaterial3: true,
              colorSchemeSeed: const Color(0xFF22B8CF),
              brightness: Brightness.dark,
              fontFamily: 'NotoSansGujaratiLocal',
            )
          : ThemeData(
              useMaterial3: true,
              colorSchemeSeed: const Color(0xFF0D7480),
              brightness: Brightness.light,
              fontFamily: 'NotoSansGujaratiLocal',
            ),
      // Re-apply the phone adjustments on top of this screen's own theme.
      child: ResponsiveTheme(
        child: IdCardStudioScreen(
          onToggleTheme: _toggleTheme,
          onExportSheetPng: _handleExportPng,
        ),
      ),
    );
  }
}

class IdCardStudioScreen extends StatelessWidget {
  final VoidCallback? onToggleTheme;
  final void Function(Uint8List pngBytes, String fileName)? onExportSheetPng;

  const IdCardStudioScreen({
    super.key,
    this.onToggleTheme,
    this.onExportSheetPng,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IdCardStudioView(
          onToggleTheme: onToggleTheme,
          onExportSheetPng: onExportSheetPng,
        ),
      ),
    );
  }
}

class IdCardStudioView extends StatefulWidget {
  final VoidCallback? onToggleTheme;
  final void Function(Uint8List pngBytes, String fileName)? onExportSheetPng;
  final List<String>? initialHeaders;
  final List<List<String>>? initialRows;

  const IdCardStudioView({
    super.key,
    this.onToggleTheme,
    this.onExportSheetPng,
    this.initialHeaders,
    this.initialRows,
  });

  @override
  State<IdCardStudioView> createState() => _IdCardStudioViewState();
}

class _IdCardStudioViewState extends State<IdCardStudioView>
    with SingleTickerProviderStateMixin {
  static const double kSafePad = 12.0; // 1.2mm safe margin
  static const double kMmToPx = 96.0 / 25.4;
  static const double kHandleHitPad = 12.0; // Expanded hit area for corner drag

  static const String _prefKeyLastTab = 'psm_id_studio_last_tab_v3';
  static const String _prefKeyZoom = 'psm_id_studio_zoom_v3';
  static const String _prefKeyShowGrid = 'psm_id_studio_show_grid_v3';
  static const String _prefKeyShowRulers = 'psm_id_studio_show_rulers_v3';
  static const String _prefKeyShowGuides = 'psm_id_studio_show_guides_v3';
  static const String _prefKeySnapEnabled = 'psm_id_studio_snap_enabled_v3';
  static const String _prefKeyRecentFonts = 'psm_id_studio_recent_fonts_v3';
  static const String _prefKeyWorkspaceState = 'psm_id_studio_workspace_state_v4';
  static const String _prefKeyWorkspaceImages = 'psm_id_studio_workspace_images_v4';
  static const String _prefKeyWorkspacePhotos = 'psm_id_studio_workspace_photos_v4';
  static const String _prefKeyLastPdfB64 = 'psm_id_studio_last_pdf_b64_v4';
  static const String _prefKeyLastPdfName = 'psm_id_studio_last_pdf_name_v4';
  static const String _prefKeyDefaultPrefixMode =
      'psm_id_studio_default_prefix_mode_v1';

  late TabController _sideTabController;
  final FocusNode _canvasFocusNode = FocusNode(debugLabel: 'IdCanvasFocus');
  final FocusNode _studentListFocusNode =
      FocusNode(debugLabel: 'IdStudentListFocus');
  final FocusNode _globalShortcutFocusNode =
      FocusNode(debugLabel: 'IdGlobalShortcutFocus');
  final GlobalKey _sheetBoundaryKey = GlobalKey();
  final GlobalKey _singleCardBoundaryKey = GlobalKey();
  final ScrollController _studentListScrollCtrl = ScrollController();

  // Pointer drag lock so background never scrolls while moving/resizing objects
  bool _isCanvasPointerDown = false;
  DateTime? _lastTapTime;
  SelectedItemKey? _lastTapKey;
  // Pointer id of the last press that landed on a card object, so the canvas
  // background does not clear the selection for that same click.
  int? _lastObjectPointer;
  int? _bgPointerDown;
  Offset? _bgPointerDownPos;

  // Card Physical Dimensions in Editor Units (10 units = 1 mm)
  double _cw = 840.0; // 84.0 mm
  double _ch = 540.0; // 54.0 mm
  bool _scaleItemsOnResize = true;

  // Template state — starts BLANK by default
  BuiltInTemplateTheme _tplTheme = BuiltInTemplateTheme.none;
  String _tplHeaderTitle = '';
  Color _tplAccentColor = const Color(0xFF0F766E);
  Uint8List? _uploadedTemplateBytes;
  MemoryImage? _cachedTemplateImage;
  String _uploadedTemplateName = '';

  // Photo, Seal & Principal Signature visibility state — all deletable & corner-resizable
  bool _showPhoto = true;
  bool _photoLockAspect = false;

  bool _showSeal = false;
  Uint8List? _uploadedSealRawBytes;
  Uint8List? _uploadedSealBytes;
  MemoryImage? _cachedSealImage;
  String _uploadedSealName = '';
  double _sealAspect = 1.0;
  bool _sealLockAspect = false;
  int _sealTolerance = 38;

  bool _showSignature = false;
  Uint8List? _uploadedSignatureRawBytes;
  Uint8List? _uploadedSignatureBytes;
  MemoryImage? _cachedSignatureImage;
  String _uploadedSignatureName = '';
  double _signatureAspect = 2.4;
  bool _signatureLockAspect = false;
  int _signatureTolerance = 38;

  // Student Database state
  List<Map<String, dynamic>> _dbClasses = [];
  List<Map<String, dynamic>> _dbStudentsAll = [];
  String _selectedClassId = '__ALL__';
  String _schoolTitle = '';
  String _schoolAddr = '';
  Map<String, String> _customHeaderLabels = {};

  /// Prefix automatically applied to newly inserted fields.
  /// 'none' (default) = no label, 'label' = Gujarati/registered label,
  /// 'header' = the raw column header name. Admin can still type any custom
  /// prefix per field from the Fields tab.
  String _defaultPrefixMode = 'none';

  /// True when the active rows came from an uploaded Excel/CSV file instead of
  /// the school student database. Class-filter rebuilds from the database are
  /// suppressed so the uploaded data is never silently overwritten.
  bool _excelDataSourceActive = false;
  String _excelSourceFileName = '';
  final Set<String> _selectedDbHeaderKeys = {
    'student_name',
    'class_label',
    'roll_no',
    'gr_no',
    'birth_date',
    'mobile',
  };

  // Active Tabular Data state
  List<String> _headers = [
    'Sr No',
    'Photo File',
    'Student Name',
    'Class',
    'Roll No',
    'GR No',
    'Birth Date',
    'Mobile',
    'Father Name',
    'Mother Name',
    'Caste',
    'Category',
    'Gender',
    'Address',
    'UID Number',
    'PEN',
    'APAAR ID',
    'Enroll Date',
    'School Name',
  ];
  List<List<String>> _rows = [
    List<String>.filled(19, ''),
  ];
  int _photoCol = 1;
  final Map<String, Uint8List> _uploadedPhotos = {};
  final Map<String, MemoryImage> _photoImageCache = {};
  int _curRowIdx = 0;
  String _searchQuery = '';
  String _studentPanelSearchQuery = '';
  Timer? _searchDebounceTimer;
  Timer? _numericDebounceTimer;
  Timer? _workspaceSaveDebounceTimer;
  bool _isRestoringWorkspace = false;
  bool _isCapturingCleanSingleCard = false;
  Uint8List? _lastSavedPdfBytes;
  String _lastSavedPdfName = 'school_id_cards.pdf';

  // Professional Student Selection state
  final Set<int> _selectedStudentIndices = <int>{0};
  int? _lastClickedStudentIdx = 0;
  bool _selectedOnlyPreviewMode = false;
  PrintRecordScope _printScope = PrintRecordScope.all;
  List<int> _cachedFilteredRowIndices = <int>[0];
  bool _filteredIndicesDirty = true;

  // Layouts (4 alternating sets)
  List<CardLayoutSet> _layouts = [];
  int _curLayoutIdx = 0;
  CardFieldItem? _defaultStyleTemplate;
  CardClipboardPayload? _clipboardPayload;
  int _nextGroupId = 1;

  // Selection & Multi-Select (CorelDRAW style)
  SelectedItemKey? _selKey;
  List<SelectedItemKey> _multiSel = [];
  bool _preventOverlap = false;
  bool _showSafeZone = true;
  bool _showGrid = true; // Enabled by default in Editor, NEVER in print/export
  bool _showRulers = true;
  bool _snapEnabled = true;
  double _zoom = 0.85;
  bool _snapX = false;
  bool _snapY = false;

  // Font search & Recent fonts state
  String _fontSearchQuery = '';
  List<String> _recentFonts = <String>[
    'NotoSansGujaratiLocal',
    'LohitGujaratiLocal',
    'Roboto',
    'Poppins',
  ];

  // Batch style checkboxes
  bool _applyAllSets = true;
  bool _incFont = true;
  bool _incSize = true;
  bool _incAlign = true;
  bool _incColor = true;
  bool _incStyle = true;
  bool _incAutoFit = true;

  // Sheet & Imposition settings
  String _paperSize = '12x18';
  double _gapMm = 1.0;
  int _exportDpi = 200;
  CutGuideStyle _guideStyle = CutGuideStyle.solid;
  bool _alternateSets = false;
  bool _drawCutGuides = true;
  int _sheetPageIdx = 0;
  int _rangeFrom = 1;
  int _rangeTo = 1;

  // Export progress & cancel state
  bool _isExporting = false;
  int _exportProcessedCount = 0;
  int _exportTotalCount = 0;
  bool _cancelExportRequested = false;

  // Undo / Redo history
  final List<String> _history = [];
  int _historyIdx = -1;
  bool _isRestoringHistory = false;

  String _statusMessage =
      'Ready. Tap any Header chip or "Insert Selected Headers" to add fields, or drag any corner handle to resize Photo, Seal, Principal Sign, or Fields.';

  // Reused TextEditingControllers
  final TextEditingController _tplTitleCtrl = TextEditingController(text: '');
  final TextEditingController _liveCellCtrl = TextEditingController();
  final TextEditingController _directTextCtrl = TextEditingController();
  final TextEditingController _prefixCtrl = TextEditingController();
  final TextEditingController _cardWmmCtrl = TextEditingController(text: '84');
  final TextEditingController _cardHmmCtrl = TextEditingController(text: '54');
  final TextEditingController _photoWmmCtrl =
      TextEditingController(text: '20.5');
  final TextEditingController _photoHmmCtrl =
      TextEditingController(text: '25.5');
  final TextEditingController _sealWmmCtrl = TextEditingController(text: '9.5');
  final TextEditingController _sealHmmCtrl = TextEditingController(text: '9.5');
  final TextEditingController _signWmmCtrl =
      TextEditingController(text: '18.0');
  final TextEditingController _signHmmCtrl = TextEditingController(text: '7.5');
  final TextEditingController _fieldWmmCtrl =
      TextEditingController(text: '45.0');
  final TextEditingController _fieldHmmCtrl =
      TextEditingController(text: '3.0');
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _studentSearchCtrl = TextEditingController();
  final TextEditingController _fontSearchCtrl = TextEditingController();
  final TextEditingController _fontSizeCtrl = TextEditingController(text: '9.5');
  final TextEditingController _minFontSizeCtrl =
      TextEditingController(text: '4.5');
  final TextEditingController _lineHeightCtrl =
      TextEditingController(text: '1.15');
  final TextEditingController _letterSpacingCtrl =
      TextEditingController(text: '0.0');
  final TextEditingController _rangeFromCtrl = TextEditingController(text: '1');
  final TextEditingController _rangeToCtrl = TextEditingController(text: '1');

  CardLayoutSet get _curLayout => _layouts[_curLayoutIdx];

  void _syncActiveLayoutToAllSets() {
    if (_layouts.isEmpty || _alternateSets) return;
    final idx = _curLayoutIdx.clamp(0, _layouts.length - 1).toInt();
    final src = _layouts[idx];
    for (int i = 0; i < _layouts.length; i++) {
      if (i != idx) {
        _layouts[i] = src.copy();
      }
    }
  }

  void _rebuild(VoidCallback fn) {
    if (!mounted) return;
    setState(() {
      fn();
      _syncActiveLayoutToAllSets();
    });
    if (!_isRestoringWorkspace && !_isRestoringHistory) {
      _scheduleWorkspaceAutoSave();
    }
  }

  bool _handleRawHardwareKey(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;
    if (_isEditableTextFocused()) return false;
    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final key = event.logicalKey;
    if (isCtrl && key == LogicalKeyboardKey.keyZ) {
      _restoreHistory(isShift ? 1 : -1);
      return true;
    }
    if (isCtrl && key == LogicalKeyboardKey.keyY) {
      _restoreHistory(1);
      return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleRawHardwareKey);
    _sideTabController = TabController(length: 6, vsync: this);
    _sideTabController.addListener(_onSideTabChanged);
    _initBlankWorkspace();
    _loadSavedStudioPreferences().then((_) {
      if (mounted) _loadSchoolRecordsFromDatabase();
    });
  }

  void _onSideTabChanged() {
    if (!mounted) return;
    setState(() {});
    _saveLastOpenTab(_sideTabController.index);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleRawHardwareKey);
    _searchDebounceTimer?.cancel();
    _numericDebounceTimer?.cancel();
    _workspaceSaveDebounceTimer?.cancel();
    _sideTabController.removeListener(_onSideTabChanged);
    _sideTabController.dispose();
    _canvasFocusNode.dispose();
    _studentListFocusNode.dispose();
    _globalShortcutFocusNode.dispose();
    _studentListScrollCtrl.dispose();
    _tplTitleCtrl.dispose();
    _liveCellCtrl.dispose();
    _directTextCtrl.dispose();
    _prefixCtrl.dispose();
    _cardWmmCtrl.dispose();
    _cardHmmCtrl.dispose();
    _photoWmmCtrl.dispose();
    _photoHmmCtrl.dispose();
    _sealWmmCtrl.dispose();
    _sealHmmCtrl.dispose();
    _signWmmCtrl.dispose();
    _signHmmCtrl.dispose();
    _fieldWmmCtrl.dispose();
    _fieldHmmCtrl.dispose();
    _searchCtrl.dispose();
    _studentSearchCtrl.dispose();
    _fontSearchCtrl.dispose();
    _fontSizeCtrl.dispose();
    _minFontSizeCtrl.dispose();
    _lineHeightCtrl.dispose();
    _letterSpacingCtrl.dispose();
    _rangeFromCtrl.dispose();
    _rangeToCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 980;
    return Focus(
      focusNode: _globalShortcutFocusNode,
      onKeyEvent: _handleGlobalKeyEvent,
      child: Column(
        children: [
          // Wide screens keep header + toolbar fixed; on phones / tablets
          // they scroll with the page so the card gets the screen height.
          if (isWide) ...[
            _buildTopHeaderBar(context),
            _buildCompactProToolbar(context),
          ],
          if (_isExporting) _buildExportProgressBanner(context),
          Expanded(
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 415, child: _buildSidebar(context)),
                      const VerticalDivider(width: 1),
                      Expanded(child: _buildMainStage(context)),
                    ],
                  )
                : ListView(
                    physics: _isCanvasPointerDown
                        ? const NeverScrollableScrollPhysics()
                        : const ClampingScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      _buildTopHeaderBar(context),
                      _buildCompactProToolbar(context),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: _buildSidebar(context, shrinkWrap: true),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: _buildMainStage(context, shrinkWrap: true),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

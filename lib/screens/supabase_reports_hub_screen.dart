import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import '../services/datewise_report_columns.dart';
import '../services/school_class_order.dart';
import '../services/supabase_attendance_report_service.dart';
import '../services/supabase_report_export_service.dart';
import '../services/school_name_language_service.dart';
import '../widgets/school_name_language_selector.dart';
import 'datewise_columns_settings_dialog.dart';

import '../services/psm_file_export_helper.dart';
import '../services/school_type.dart';
import '../services/psm_daily_report_print_stub.dart'
    if (dart.library.html) '../services/psm_daily_report_print_web.dart'
    as daily_print;

/// One school-wide reporting hub for Admin and Teacher logins.
/// All report data is read from school-scoped, aggregate Supabase RPCs; this
/// screen never broadens the class-scoped policies used to edit attendance.
class SupabaseReportsHubScreen extends StatefulWidget {
  const SupabaseReportsHubScreen({
    super.key,
    required this.profile,
    this.readOnly = false,
  });

  final Map<String, dynamic> profile;
  final bool readOnly;

  @override
  State<SupabaseReportsHubScreen> createState() =>
      _SupabaseReportsHubScreenState();
}

enum _ReportMode { daily, classwise, groupwise, combine, tarij, mdm }

class _SupabaseReportsHubScreenState extends State<SupabaseReportsHubScreen> {
  final SupabaseAttendanceReportService _reports =
      SupabaseAttendanceReportService();
  final SupabaseReportExportService _exports = SupabaseReportExportService();
  final SupabaseClient _client = Supabase.instance.client;
  String _schoolNameLanguage = SchoolNameLanguageService.gujarati;
  String _schoolRef = '';
  Map<String, dynamic> _schoolContext = <String, dynamic>{};
  Map<String, dynamic> _schoolConfig = <String, dynamic>{};

  late DateTime _fromDate;
  late DateTime _toDate;
  late DateTime _month;
  _ReportMode _mode = _ReportMode.daily;
  String _group = SchoolClassOrder.all;
  bool _loading = false;
  bool _exporting = false;
  bool _uploadingAttendance = false;
  Timer? _uploadWindowTimer;
  String? _error;
  List<Map<String, dynamic>> _attendanceRows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _classRows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _tarijCounts = <Map<String, dynamic>>[];
  List<List<String>> _preview = <List<String>>[];
  List<String> _selectedColumnKeys = DateWiseReportColumn.allKeys.toList();
  List<String> _selectedTarijColumnKeys = TarijReportColumn.allKeys.toList();

  String get _hubSchoolType => SchoolType.resolve(<dynamic>[
        _schoolContext['school_type'],
        widget.profile['school_type'],
        widget.profile['schoolType'],
      ]);
  String _schoolAddress = '';
  String _dailySerial = '';

  bool get _isAdmin =>
      '${widget.profile['role'] ?? ''}'.trim().toLowerCase() == 'admin';
  String get _schoolName => SchoolNameLanguageService.resolveSchoolName(
    language: _schoolNameLanguage,
    profile: widget.profile,
    schoolContext: _schoolContext,
    schoolConfig: _schoolConfig,
    fallbackEnglish:
        '${widget.profile['school_name'] ?? widget.profile['schoolName'] ?? 'School'}'
            .trim(),
  );

  DateTime _indiaNow() {
    final india = DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
    return DateTime(india.year, india.month, india.day);
  }

  String _iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _label(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';

  String get _monthStart => _iso(DateTime(_month.year, _month.month, 1));
  String get _monthEnd => _iso(DateTime(_month.year, _month.month + 1, 0));
  String get _rangeLabel => '${_label(_fromDate)} થી ${_label(_toDate)}';
  String get _monthLabel =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  bool get _isPrevAttendanceUploadActive {
    if (!_isAdmin || widget.readOnly) return false;
    final enabled = _schoolContext['prev_attendance_upload_enabled'] == true ||
        _schoolConfig['prev_attendance_upload_enabled'] == true;
    if (!enabled) return false;
    final expRaw =
        '${_schoolContext['prev_attendance_upload_expires_at'] ?? _schoolConfig['prev_attendance_upload_expires_at'] ?? ''}'
            .trim();
    final expDt = DateTime.tryParse(expRaw)?.toUtc();
    if (expDt == null) return false;
    return DateTime.now().toUtc().isBefore(expDt);
  }

  String get _prevAttendanceUploadRemainingText {
    final expRaw =
        '${_schoolContext['prev_attendance_upload_expires_at'] ?? _schoolConfig['prev_attendance_upload_expires_at'] ?? ''}'
            .trim();
    final expDt = DateTime.tryParse(expRaw)?.toUtc();
    if (expDt == null) return '';
    final diff = expDt.difference(DateTime.now().toUtc());
    if (diff.isNegative) return 'સમય પૂર્ણ (Expired)';
    final hrs = diff.inHours;
    final mins = diff.inMinutes.remainder(60);
    return '${hrs} કલાક ${mins} મિનિટ બાકી';
  }

  @override
  void initState() {
    super.initState();
    final today = _indiaNow();
    _toDate = today;
    _fromDate = DateTime(today.year, today.month, 1);
    _month = DateTime(today.year, today.month, 1);
    _uploadWindowTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadSchoolNamePreference();
      await _generateReport();
    });
  }

  @override
  void dispose() {
    _uploadWindowTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSchoolNamePreference() async {
    final schoolRef = await SchoolNameLanguageService.currentSchoolRef(_client);
    final language = await SchoolNameLanguageService.loadLanguage(
      schoolRef: schoolRef,
    );
    final schoolContext =
        await SchoolNameLanguageService.loadCurrentSchoolContext(_client);
    var schoolConfig = <String, dynamic>{};
    if (schoolRef.isNotEmpty) {
      try {
        final row = await _client
            .from('school_settings')
            .select('config')
            .eq('school_ref', schoolRef)
            .maybeSingle();
        final config = row?['config'];
        if (config is Map) {
          schoolConfig = config.map(
            (key, value) => MapEntry(key.toString(), value),
          );
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _schoolRef = schoolRef;
      _schoolNameLanguage = language;
      _schoolContext = schoolContext;
      _schoolConfig = schoolConfig;
    });
  }

  void _setSchoolNameLanguage(String language) {
    if (!mounted) return;
    setState(() => _schoolNameLanguage = language);
  }

  List<Map<String, dynamic>> _uniqueClasses(List<Map<String, dynamic>> rows) {
    final byId = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final id = '${row['class_id'] ?? row['id'] ?? ''}'.trim();
      if (id.isNotEmpty) byId.putIfAbsent(id, () => row);
    }
    return SchoolClassOrder.sorted(byId.values.toList());
  }

  Future<void> _pickDate({required bool from}) async {
    final current = from ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2018),
      lastDate: _indiaNow(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _fromDate = DateTime(picked.year, picked.month, picked.day);
        if (_fromDate.isAfter(_toDate)) _toDate = _fromDate;
      } else {
        _toDate = DateTime(picked.year, picked.month, picked.day);
        if (_toDate.isBefore(_fromDate)) _fromDate = _toDate;
      }
    });
    await _generateReport();
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2018),
      lastDate: _indiaNow(),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked == null || !mounted) return;
    setState(() => _month = DateTime(picked.year, picked.month, 1));
    await _generateReport();
  }

  Future<void> _openColumnSettings() async {
    if (!_isAdmin || widget.readOnly) return;
    await showDateWiseColumnSettingsDialog(context);
    if (mounted) await _generateReport();
  }

  Future<void> _openTarijColumnSettings() async {
    if (!_isAdmin || widget.readOnly) return;
    await showTarijColumnSettingsDialog(context);
    if (mounted) await _generateReport();
  }

  Future<void> _generateReport() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _loadSchoolNamePreference();
      final isMonthly = _mode == _ReportMode.tarij || _mode == _ReportMode.mdm;
      final from = isMonthly
          ? _monthStart
          : _iso(_mode == _ReportMode.daily ? _toDate : _fromDate);
      final to = isMonthly ? _monthEnd : _iso(_toDate);
      final rows = await _reports.getSchoolwideAttendanceRows(
        fromDate: from,
        toDate: to,
      );
      var uniqueClasses = _uniqueClasses(rows);
      var reportAttendanceRows = rows;
      var tarijRows = <Map<String, dynamic>>[];
      if (isMonthly) {
        tarijRows = await _reports.getSchoolwideTarijStudentCounts(
          monthStart: _monthStart,
          monthEnd: _monthEnd,
        );
        if (uniqueClasses.isEmpty && tarijRows.isNotEmpty) {
          uniqueClasses = _uniqueClasses(tarijRows);
        }
      }
      _selectedColumnKeys = await _reports.getDateWiseSelectedColumnKeys();
      _selectedTarijColumnKeys = await _reports.getTarijSelectedColumnKeys();
      List<List<String>> preview;
      var dailySerial = '';
      if (_mode == _ReportMode.daily) {
        final result = await _reports.getDailyReportRowsByDate(_iso(_toDate));
        dailySerial = '${result['serial'] ?? ''}';
        final raw = result['values'];
        preview = raw is List
            ? raw
                  .map(
                    (row) => row is List
                        ? row.map((cell) => '$cell').toList()
                        : <String>[],
                  )
                  .toList()
            : <List<String>>[];
        final rawClasses = result['classRows'];
        uniqueClasses = rawClasses is List
            ? SchoolClassOrder.sorted(
                rawClasses
                    .whereType<Map>()
                    .map((row) => Map<String, dynamic>.from(row))
                    .toList(),
              )
            : uniqueClasses;
        reportAttendanceRows = uniqueClasses;
        _schoolAddress = '${result['school_address'] ?? ''}';
      } else if (_mode == _ReportMode.groupwise) {
        preview = _exports.buildGroupwisePreview(
          rows: rows,
          group: _group,
          visibleColumnKeys: _selectedColumnKeys,
        );
      } else if (_mode == _ReportMode.classwise) {
        preview = _exports.buildSummaryPreview(
          rows: rows,
          visibleColumnKeys: _selectedColumnKeys,
        );
      } else if (_mode == _ReportMode.combine) {
        preview = _exports.buildCombinePreview(
          rows: rows,
          visibleColumnKeys: _selectedColumnKeys,
        );
      } else if (_mode == _ReportMode.tarij) {
        preview = _exports.buildTarijPreview(
          classRows: uniqueClasses,
          attendanceRows: rows,
          studentCounts: tarijRows,
          visibleColumnKeys: _selectedColumnKeys,
          visibleTarijColumnKeys: _selectedTarijColumnKeys,
          schoolType: _hubSchoolType,
        );
      } else {
        preview = _exports.buildMdmPreview(
          schoolName: _schoolName,
          classRows: uniqueClasses,
          attendanceRows: rows,
          studentCounts: tarijRows,
          visibleColumnKeys: _selectedColumnKeys,
        );
      }
      if (!mounted) return;
      setState(() {
        _attendanceRows = reportAttendanceRows;
        _classRows = uniqueClasses;
        _tarijCounts = tarijRows;
        _preview = preview;
        _dailySerial = dailySerial;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  String _fileSlug(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');

  Future<void> _shareXlsx(
    List<int> bytes,
    String filename,
    String title,
  ) async {
    await PsmFileExportHelper.saveOrShare(
      bytes: Uint8List.fromList(bytes),
      filename: filename,
      title: title,
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  Future<void> _sharePdf(List<int> bytes, String filename, String title) async {
    await PsmFileExportHelper.saveOrShare(
      bytes: Uint8List.fromList(bytes),
      filename: filename,
      title: title,
      mimeType: 'application/pdf',
    );
  }

  Future<void> _exportExcel() async {
    if (_loading || _exporting) return;
    setState(() => _exporting = true);
    try {
      final columns = await _reports.getDateWiseSelectedColumnKeys();
      final classes = _classRows;
      final rows = _attendanceRows;
      final Uint8List bytes;
      final String filename;
      switch (_mode) {
        case _ReportMode.daily:
          bytes = await _exports.exportDatewiseXlsx(
            schoolName: _schoolName,
            schoolAddress: _schoolAddress,
            date: _iso(_toDate),
            attendanceSerial: _dailySerial,
            classRows: classes,
            visibleColumnKeys: columns,
          );
          filename = 'DATEWISE_${_iso(_toDate)}.xlsx';
          break;
        case _ReportMode.classwise:
          bytes = await _exports.exportClasswiseAllDataXlsx(
            schoolName: _schoolName,
            fromDate: _iso(_fromDate),
            toDate: _iso(_toDate),
            classRows: classes,
            attendanceRows: rows,
            visibleColumnKeys: columns,
          );
          filename = 'CLASSWISE_ALL_${_iso(_fromDate)}_${_iso(_toDate)}.xlsx';
          break;
        case _ReportMode.groupwise:
          bytes = await _exports.exportGroupwiseXlsx(
            schoolName: _schoolName,
            fromDate: _iso(_fromDate),
            toDate: _iso(_toDate),
            group: _group,
            rows: rows,
            visibleColumnKeys: columns,
          );
          filename =
              'GROUPWISE_${_fileSlug(_group)}_${_iso(_fromDate)}_${_iso(_toDate)}.xlsx';
          break;
        case _ReportMode.combine:
          bytes = await _exports.exportCombineReportXlsx(
            schoolName: _schoolName,
            fromDate: _iso(_fromDate),
            toDate: _iso(_toDate),
            rows: rows,
            visibleColumnKeys: columns,
          );
          filename = 'COMBINE_REPORT_${_iso(_fromDate)}_${_iso(_toDate)}.xlsx';
          break;
        case _ReportMode.tarij:
          final tarijColumns = await _reports.getTarijSelectedColumnKeys();
          bytes = await _exports.exportTarijXlsx(
            schoolName: _schoolName,
            monthLabel: _monthLabel,
            classRows: classes,
            attendanceRows: rows,
            studentCounts: _tarijCounts,
            visibleColumnKeys: columns,
            visibleTarijColumnKeys: tarijColumns,
            schoolType: _hubSchoolType,
          );
          filename = 'TARIJ_$_monthLabel.xlsx';
          break;
        case _ReportMode.mdm:
          bytes = await _exports.exportMdmEkandarXlsx(
            schoolName: _schoolName,
            monthLabel: _monthLabel,
            classRows: classes,
            attendanceRows: rows,
            studentCounts: _tarijCounts,
            visibleColumnKeys: columns,
          );
          filename = 'MDM_EKANDAR_$_monthLabel.xlsx';
          break;
      }
      await _shareXlsx(bytes, filename, filename.replaceAll('.xlsx', ''));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Excel export failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportPdf() async {
    if (_loading || _exporting) return;
    final Object? printWindow = _mode == _ReportMode.daily && kIsWeb
        ? daily_print.openDailyReportPrintWindow()
        : null;
    setState(() => _exporting = true);
    try {
      if (_mode == _ReportMode.daily && kIsWeb) {
        final result = await _reports.getDailyReportRowsByDate(_iso(_toDate));
        final rawClasses = result['classRows'];
        final classes = rawClasses is List
            ? SchoolClassOrder.sorted(
                rawClasses
                    .whereType<Map>()
                    .map((row) => Map<String, dynamic>.from(row))
                    .toList(),
              )
            : _classRows;
        final selected = await _reports.getDateWiseSelectedColumnKeys();
        final html = _exports.buildDailyDatewisePrintHtml(
          schoolName: _schoolName,
          schoolAddress: '${result['school_address'] ?? _schoolAddress}',
          date: _iso(_toDate),
          attendanceSerial: '${result['serial'] ?? ''}',
          classRows: classes,
          visibleColumnKeys: selected,
        );
        await daily_print.printDailyReportHtml(printWindow, html);
        return;
      }

      List<List<String>> values;
      String title;
      String period;
      bool wide = false;
      switch (_mode) {
        case _ReportMode.daily:
          values = _preview.map((row) => List<String>.from(row)).toList();
          if (values.isNotEmpty) values[0].add('વર્ગ શિક્ષકની સહી');
          for (var i = 1; i < values.length; i++) {
            values[i].add('');
          }
          title = 'DATEWISE — દૈનિક હાજરી અહેવાલ';
          period = 'તારીખ: ${_label(_toDate)}';
          wide = true;
          break;
        case _ReportMode.groupwise:
          final keys = await _reports.getDateWiseSelectedColumnKeys();
          values = _exports.buildGroupwisePreview(
            rows: _attendanceRows,
            group: _group,
            visibleColumnKeys: keys,
          );
          title = 'GROUP WISE — ${SchoolClassOrder.labelFor(_group)}';
          period = 'સમયગાળો: $_rangeLabel';
          wide = true;
          break;
        case _ReportMode.tarij:
          values = _preview;
          title = 'TARIJ — માસિક પત્રક (Page 1 & Page 2)';
          period = 'માસ: $_monthLabel';
          wide = true;
          break;
        case _ReportMode.mdm:
          values = _preview;
          title = 'MDM EKANDAR — સરેરાશ હાજરી અને મધ્યાહન ભોજન';
          period = 'માસ: $_monthLabel';
          wide = true;
          break;
        case _ReportMode.classwise:
        case _ReportMode.combine:
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('આ અહેવાલ Excel માટે છે; PDF ઉપલબ્ધ નથી.'),
              ),
            );
          }
          return;
      }
      final headers = values.isNotEmpty ? values.first : <String>[];
      final rows = values.length > 1
          ? values.skip(1).toList()
          : <List<String>>[];
      final bytes = await _exports.buildSummaryPdfAsync(
        title: title,
        schoolName: _schoolName,
        periodLabel: period,
        headers: headers,
        rows: rows,
        a3Landscape: wide && _mode != _ReportMode.daily,
      );
      final suffix = _mode == _ReportMode.daily
          ? _iso(_toDate)
          : _mode == _ReportMode.groupwise
          ? '${_iso(_fromDate)}_${_iso(_toDate)}'
          : _monthLabel;
      await _sharePdf(bytes, '${_mode.name.toUpperCase()}_$suffix.pdf', title);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('PDF export failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _downloadClasswiseTemplateForUpload() async {
    if (_loading || _exporting || _uploadingAttendance) return;
    if (_mode != _ReportMode.classwise) {
      setState(() => _mode = _ReportMode.classwise);
      await _generateReport();
    }
    await _exportExcel();
  }

  Future<void> _uploadPreviousAttendanceExcel() async {
    if (_loading || _exporting || _uploadingAttendance) return;
    await _loadSchoolNamePreference();
    if (!_isPrevAttendanceUploadActive) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'અગાઉની હાજરી અપલોડ કરવાની ૨૪ કલાકની સમયમર્યાદા પૂર્ણ થઈ ગઈ છે અથવા બંધ છે.',
          ),
        ),
      );
      setState(() {});
      return;
    }

    if (!mounted) return;
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.deepOrange, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'અગાઉની દૈનિક હાજરી અપલોડ — મહત્વપૂર્ણ ચેતવણી',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5),
              ),
            ),
          ],
        ),
        content: const SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1️⃣ પહેલા "Class-wise all classes — Excel only" રિપોર્ટ ડાઉનલોડ કરો અને તે જ ફાઈલમાં તારીખ મુજબ હાજરીના આંકડા ભરો.',
                  style: TextStyle(fontWeight: FontWeight.w600, height: 1.4),
                ),
                SizedBox(height: 8),
                Text(
                  '2️⃣ ⚠️ કડક સૂચના: ફાઈલમાં આવેલ Sheet ના નામ (વર્ગના નામ) અથવા Column Headers (Row 1 થી Row 5 ના હેડર) માં કોઈપણ ફેરફાર કરશો નહીં!',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.red,
                    height: 1.4,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '3️⃣ જો કોઈપણ Sheet નું નામ અથવા Column Header બદલાયેલું હશે, તો આખી શાળાનો ડેટા રિજેક્ટ (Reject) કરવામાં આવશે (એક પણ વર્ગનો ડેટા સેવ થશે નહીં).',
                  style: TextStyle(fontWeight: FontWeight.w700, height: 1.4),
                ),
                SizedBox(height: 8),
                Text(
                  '4️⃣ આપે પસંદ કરેલા કૉલમ (બધા 60 કૉલમ, કેટેગરી કુલ વગરના કૉલમ, કે ફક્ત અલ્પાહાર કુલ) હેડર મેચિંગથી આપોઆપ ઓળખાઈ જશે.',
                  style: TextStyle(height: 1.4),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('રદ કરો (Cancel)'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.upload_file),
            label: const Text('સમજાયું, Excel ફાઈલ પસંદ કરો'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['xlsx'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty || !mounted) return;
    final fileBytes = picked.files.first.bytes;
    if (fileBytes == null || fileBytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('પસંદ કરેલ ફાઈલ વાંચી શકાઈ નથી.')),
      );
      return;
    }

    setState(() {
      _uploadingAttendance = true;
      _error = null;
    });
    try {
      final activeClassRows = await _client
          .from('school_classes')
          .select('id,school_ref,class_key,label,sheet_name,standard,section,report_group,sort_order,is_active')
          .eq('school_ref', _schoolRef)
          .eq('is_active', true)
          .order('sort_order');
      final classes = SchoolClassOrder.sorted(
        activeClassRows.map((r) => Map<String, dynamic>.from(r)).toList(),
      );
      if (classes.isEmpty) {
        throw const FormatException('શાળામાં કોઈ સક્રિય વર્ગો મળ્યા નથી.');
      }
      final schoolType =
          '${_schoolContext['school_type'] ?? widget.profile['school_type'] ?? widget.profile['schoolType'] ?? 'mixed'}';
      final teacherId = '${widget.profile['teacher_id'] ?? ''}'.trim();
      final dayPayloads = _exports.parseAndValidateClasswiseAttendanceXlsx(
        bytes: fileBytes,
        schoolRef: _schoolRef,
        classRows: classes,
        schoolType: schoolType,
        todayIso: _iso(_indiaNow()),
        updatedByTeacherId: teacherId,
      );

      await _client
          .from('attendance_days')
          .upsert(dayPayloads, onConflict: 'school_ref,class_id,attendance_date');

      if (!mounted) return;
      await _generateReport();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text('અગાઉની હાજરી સફળતાપૂર્વક અપલોડ થઈ ગઈ!'),
              ),
            ],
          ),
          content: Text(
            'આખી શાળાના વર્ગોની કુલ ${dayPayloads.length} દૈનિક હાજરી એન્ટ્રીઓ હેડર મેચિંગ સાથે સફળતાપૂર્વક સેવ થઈ ગઈ છે.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } on FormatException catch (fe) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text('અપલોડ રિજેક્ટ (Upload Rejected)'),
              ),
            ],
          ),
          content: Text(fe.message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _uploadingAttendance = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthly = _mode == _ReportMode.tarij || _mode == _ReportMode.mdm;
    final daily = _mode == _ReportMode.daily;
    final excelOnly =
        _mode == _ReportMode.classwise || _mode == _ReportMode.combine;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('REPORTS / અહેવાલ', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text(
          'School-wide read-only reports. Attendance editing remains limited to assigned classes.',
        ),
        if (_isPrevAttendanceUploadActive) ...<Widget>[
          const SizedBox(height: 12),
          Card(
            color: Colors.teal.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.teal.shade600, width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.upload_file_rounded, color: Colors.teal.shade900),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'અગાઉની દૈનિક હાજરી અપલોડ (Previous Attendance Excel Upload • $_prevAttendanceUploadRemainingText)',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Colors.teal.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '1. પહેલા \"Class-wise all classes — Excel only\" રિપોર્ટ ડાઉનલોડ કરો.\n'
                    '2. Sheet ના નામ કે Column Headers બદલ્યા વગર તારીખ મુજબ સંખ્યા ભરીને અહીં અપલોડ કરો (૨૪ કલાક પછી આ વિભાગ આપોઆપ બંધ થઈ જશે).',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _loading || _exporting || _uploadingAttendance
                            ? null
                            : _downloadClasswiseTemplateForUpload,
                        icon: const Icon(Icons.download_outlined),
                        label: const Text(
                          '1. Download Class-wise All Classes Excel Template',
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.teal.shade800,
                        ),
                        onPressed: _loading || _exporting || _uploadingAttendance
                            ? null
                            : _uploadPreviousAttendanceExcel,
                        icon: _uploadingAttendance
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.cloud_upload_outlined),
                        label: Text(
                          _uploadingAttendance
                              ? 'Uploading Attendance…'
                              : '2. Upload Previous Attendance Excel (.xlsx)',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SchoolNameLanguageSelector(
          schoolRef: _schoolRef.isEmpty ? null : _schoolRef,
          onChanged: _setSchoolNameLanguage,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<_ReportMode>(
          isExpanded: true,
          initialValue: _mode,
          decoration: const InputDecoration(
            labelText: 'Report type / અહેવાલનો પ્રકાર',
            border: OutlineInputBorder(),
          ),
          items: const <DropdownMenuItem<_ReportMode>>[
            DropdownMenuItem(
              value: _ReportMode.daily,
              child: Text('Daily DATEWISE — whole school PDF + Excel'),
            ),
            DropdownMenuItem(
              value: _ReportMode.classwise,
              child: Text('Class-wise all classes — Excel only'),
            ),
            DropdownMenuItem(
              value: _ReportMode.groupwise,
              child: Text('Group Wise — date range PDF + Excel'),
            ),
            DropdownMenuItem(
              value: _ReportMode.combine,
              child: Text('COMBINE REPORT — whole-school Excel only'),
            ),
            DropdownMenuItem(
              value: _ReportMode.tarij,
              child: Text('TARIJ — monthly (Page 1 Class-wise & Page 2 Standard-wise)'),
            ),
            DropdownMenuItem(
              value: _ReportMode.mdm,
              child: Text('MDM EKANDAR — monthly group & school averages'),
            ),
          ],
          onChanged: _loading
              ? null
              : (value) async {
                  if (value == null) return;
                  setState(() => _mode = value);
                  await _generateReport();
                },
        ),
        const SizedBox(height: 10),
        if (monthly)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _pickMonth,
              icon: const Icon(Icons.calendar_month),
              label: Text(_monthLabel),
            ),
          )
        else if (daily)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _loading ? null : () => _pickDate(from: false),
              icon: const Icon(Icons.calendar_month),
              label: Text(_label(_toDate)),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: _loading ? null : () => _pickDate(from: true),
                icon: const Icon(Icons.calendar_month),
                label: Text('થી: ${_label(_fromDate)}'),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : () => _pickDate(from: false),
                icon: const Icon(Icons.event),
                label: Text('સુધી: ${_label(_toDate)}'),
              ),
            ],
          ),
        if (_mode == _ReportMode.groupwise) ...<Widget>[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _group,
            decoration: const InputDecoration(
              labelText: 'Report group / વર્ગ જૂથ',
              border: OutlineInputBorder(),
            ),
            items: SchoolClassOrder.reportGroups
                .map(
                  (group) => DropdownMenuItem<String>(
                    value: group.$1,
                    child: Text(group.$2),
                  ),
                )
                .toList(),
            onChanged: _loading
                ? null
                : (value) async {
                    if (value == null) return;
                    setState(() => _group = value);
                    await _generateReport();
                  },
          ),
        ],
        if (_isAdmin && !widget.readOnly) ...<Widget>[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: _loading ? null : _openColumnSettings,
                icon: const Icon(Icons.view_column),
                label: Text(
                  'Report columns / પસંદ કરેલા કૉલમ (${_selectedColumnKeys.length}/60)',
                ),
              ),
              OutlinedButton.icon(
                style: _mode == _ReportMode.tarij
                    ? OutlinedButton.styleFrom(
                        backgroundColor: Colors.indigo.shade50,
                        side: BorderSide(color: Colors.indigo.shade600, width: 1.5),
                      )
                    : null,
                onPressed: _loading ? null : _openTarijColumnSettings,
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(
                  'TARIJ columns / તારીજ કૉલમ પસંદગી (${TarijColumnSpec.resolve(_selectedTarijColumnKeys, _hubSchoolType).length}/${TarijColumnSpec.allFor(_hubSchoolType).length})',
                ),
              ),
            ],
          ),
        ] else ...<Widget>[
          const SizedBox(height: 8),
          Text(
            'School-wide column selection (Boys/Girls/Total & Categories) is controlled by the Admin.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.icon(
              onPressed: _loading ? null : _generateReport,
              icon: const Icon(Icons.refresh),
              label: const Text('Generate report'),
            ),
            FilledButton.icon(
              onPressed: _loading || _exporting || _preview.isEmpty
                  ? null
                  : _exportExcel,
              icon: const Icon(Icons.file_download_outlined),
              label: Text(_exporting ? 'Exporting…' : 'Export Excel'),
            ),
            if (!excelOnly)
              OutlinedButton.icon(
                onPressed: _loading || _exporting || _preview.isEmpty
                    ? null
                    : _exportPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Export PDF'),
              ),
            if (_isPrevAttendanceUploadActive)
              FilledButton.tonalIcon(
                onPressed: _loading || _exporting || _uploadingAttendance
                    ? null
                    : _uploadPreviousAttendanceExcel,
                icon: const Icon(Icons.upload_file),
                label: Text(
                  _uploadingAttendance
                      ? 'Uploading…'
                      : 'Upload Previous Attendance (.xlsx)',
                ),
              ),
          ],
        ),
        if (_loading || _exporting) ...<Widget>[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          _preview.isEmpty
              ? 'Generate a report to preview the current school data.'
              : 'Preview • ${_classRows.length} active classes • ${monthly
                    ? _monthLabel
                    : daily
                    ? _label(_toDate)
                    : _rangeLabel}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (_preview.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: <DataColumn>[
                for (final heading in _preview.first)
                  DataColumn(
                    label: Text(
                      heading,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
              rows: _preview
                  .skip(1)
                  .map(
                    (row) => DataRow(
                      cells: <DataCell>[
                        for (
                          var index = 0;
                          index < _preview.first.length;
                          index++
                        )
                          DataCell(Text(index < row.length ? row[index] : '')),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          _mode == _ReportMode.tarij
              ? 'TARIJ: Includes Page 1 (Class-wise & Group subtotals) and Page 2 (Standard-wise summary with separate attendance %). Columns follow Admin column selection (કુમાર / કન્યા / કુલ).'
              : _mode == _ReportMode.mdm
              ? 'MDM EKANDAR: Includes Average Present and Average PM POSHAN tables for Balvatika, Std 1–5, Std 6–8, and Whole School (=SUM of groups) with કુમાર / કન્યા / કુલ.'
              : 'All classes in this school are included in reporting. Only saved attendance is counted; no record is fabricated for an unsaved date.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

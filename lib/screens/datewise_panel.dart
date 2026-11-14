import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';

import '../data/app_config.dart';
import '../data/datewise_report_options.dart';
import '../services/api_service.dart';
import '../services/app_state.dart';
import '../services/supabase_attendance_report_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/data_tables.dart';
import '../widgets/dialogs.dart';

/// Decodes `pdfBase64` from a backend response and hands it to the
/// browser to save/print, exactly matching what the "🖨️" buttons do
/// in the original (the PDF bytes themselves come straight from
/// Google's own Sheets-to-PDF export - nothing is built client-side).
Future<void> _deliverPdf(Map<String, dynamic> res, {required String fallbackName}) async {
  if (res['result'] != 'success') {
    throw ApiException(res['message']?.toString() ?? 'PDF બનાવવામાં ભૂલ થઈ.');
  }
  final b64 = res['pdfBase64'] as String?;
  if (b64 == null || b64.isEmpty) {
    throw ApiException('PDF ડેટા મળ્યો નથી.');
  }
  final Uint8List bytes = base64Decode(b64);
  final filename = (res['fileName'] as String?)?.trim().isNotEmpty == true ? res['fileName'] as String : fallbackName;
  await Printing.sharePdf(bytes: bytes, filename: filename);
}

class DateWisePanel extends StatefulWidget {
  const DateWisePanel({super.key});

  @override
  State<DateWisePanel> createState() => _DateWisePanelState();
}

class _DateWisePanelState extends State<DateWisePanel> {
  final _serialCtrl = TextEditingController();
  bool _loading = false;
  String? _statusError;
  Map<String, dynamic>? _report; // result:'success' payload (serial,date,values)
  List<String>? _multipleSerials;

  @override
  void dispose() {
    _serialCtrl.dispose();
    super.dispose();
  }

  ApiService? get _api => context.read<AppState>().api;

  Future<void> _showBySerial() async {
    final serial = _serialCtrl.text.trim();
    if (serial.isEmpty) {
      setState(() => _statusError = 'Serial Number દાખલ કરો.');
      return;
    }
    await _runLookup(() => _api!.getDateWiseReport(serial));
  }

  Future<void> _showToday() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await _runLookup(
      () => SupabaseAttendanceReportService().getDateWiseReportByDate(today),
    );
  }

  Future<void> _runLookup(Future<Map<String, dynamic>> Function() call) async {
    setState(() {
      _loading = true;
      _statusError = null;
      _report = null;
      _multipleSerials = null;
    });
    try {
      final res = await call();
      if (!mounted) return;
      if (res['result'] == 'success') {
        setState(() {
          _loading = false;
          _report = res;
          _serialCtrl.text = (res['serial'] ?? _serialCtrl.text).toString();
        });
      } else if (res['result'] == 'multiple') {
        setState(() {
          _loading = false;
          _multipleSerials = (res['serials'] as List? ?? []).map((e) => e.toString()).toList();
        });
      } else {
        setState(() {
          _loading = false;
          _statusError = res['message']?.toString() ?? 'રિપોર્ટ મળ્યો નથી.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusError = '$e';
      });
    }
  }

  Future<void> _savePdf() async {
    if (_report == null) return;

    final date = (_report!['date'] ?? '').toString().trim();
    if (date.isEmpty) {
      showSnack(context, '❌ રિપોર્ટની તારીખ મળી નથી.', error: true);
      return;
    }

    Map<String, dynamic> asMap(dynamic value) {
      if (value is Map) {
        return value.map((key, value) => MapEntry('$key', value));
      }
      return <String, dynamic>{};
    }

    int asInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('${value ?? ''}') ?? 0;
    }

    const categories = <String>['SC', 'ST', 'OBC', 'OTHER'];
    const classColumnWidth = 65.0;
    final classBreakdowns = ((_report!['classBreakdowns'] as List?) ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    int categoryValue(
      Map<String, dynamic> breakdown,
      String gender,
      String category,
      String metric,
    ) {
      final genderData = asMap(breakdown[gender]);
      final categoryData = asMap(genderData[category]);
      return asInt(categoryData[metric]);
    }

    int overallValue(
      Map<String, dynamic> breakdown,
      String gender,
      String metric,
    ) {
      final genderData = asMap(breakdown[gender]);
      final overallData = asMap(genderData['_OVERALL']);
      final savedOverall = asInt(overallData[metric]);
      if (savedOverall != 0) return savedOverall;
      return categories.fold<int>(
        0,
        (sum, category) => sum + categoryValue(breakdown, gender, category, metric),
      );
    }

    int valueForOption(Map<String, dynamic> breakdown, DateWiseReportColumn option) {
      final metric = option.metricKey;
      final gender = option.genderKey;
      if (option.categoryKey == 'TOTAL') {
        if (gender == 'boys') return overallValue(breakdown, 'BOYS', metric);
        if (gender == 'girls') return overallValue(breakdown, 'GIRLS', metric);
        return overallValue(breakdown, 'BOYS', metric) +
            overallValue(breakdown, 'GIRLS', metric);
      }
      if (gender == 'boys') return categoryValue(breakdown, 'BOYS', option.categoryKey, metric);
      if (gender == 'girls') return categoryValue(breakdown, 'GIRLS', option.categoryKey, metric);
      return categoryValue(breakdown, 'BOYS', option.categoryKey, metric) +
          categoryValue(breakdown, 'GIRLS', option.categoryKey, metric);
    }

    showBusyDialog(context, 'Admin દ્વારા પસંદ કરેલા columns સાથે PDF તૈયાર થાય છે…');
    try {
      final savedKeys = await SupabaseAttendanceReportService().getDateWiseSelectedColumnKeys();
      final selectedKeySet = savedKeys.isEmpty
          ? DateWiseReportColumns.allKeys
          : savedKeys.toSet().intersection(DateWiseReportColumns.allKeys);
      final selectedColumns = DateWiseReportColumns.all
          .where((option) => selectedKeySet.contains(option.key))
          .toList();
      if (selectedColumns.isEmpty) {
        throw StateError('Admin Panel માં DATE WISE માટે ઓછામાં ઓછો એક column પસંદ કરો.');
      }

      final document = pw.Document();
      for (final metric in DateWiseReportColumns.metrics) {
        final metricKey = metric['key']!;
        final title = metric['pdfTitle']!;
        final metricColumns = selectedColumns
            .where((option) => option.metricKey == metricKey)
            .toList();
        // Hide whole report section/page when the administrator unchecked all of its columns.
        if (metricColumns.isEmpty) continue;

        final totals = List<int>.filled(metricColumns.length, 0);
        final dataRows = <List<String>>[];
        for (final classRow in classBreakdowns) {
          final breakdown = asMap(classRow['genderBreakdown']);
          final values = metricColumns.map((option) => valueForOption(breakdown, option)).toList();
          for (var index = 0; index < values.length; index++) {
            totals[index] += values[index];
          }
          dataRows.add(<String>[
            (classRow['class'] ?? classRow['className'] ?? '').toString(),
            ...values.map((value) => value.toString()),
          ]);
        }
        if (dataRows.isEmpty) {
          dataRows.add(<String>[
            'No attendance record',
            ...List<String>.filled(metricColumns.length, '-'),
          ]);
        }
        dataRows.add(<String>['TOTAL SCHOOL', ...totals.map((value) => value.toString())]);

        pw.Widget buildHeaderCell(String label, {bool dark = true}) => pw.Container(
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 5),
              decoration: pw.BoxDecoration(
                color: dark ? pdf.PdfColors.indigo900 : pdf.PdfColors.blueGrey100,
              ),
              child: pw.Text(
                label,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 5.8,
                  fontWeight: pw.FontWeight.bold,
                  color: dark ? pdf.PdfColors.white : pdf.PdfColors.black,
                ),
              ),
            );

        final bodyRows = <pw.TableRow>[
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: pdf.PdfColors.indigo900),
            children: <pw.Widget>[
              buildHeaderCell('Class'),
              for (final option in metricColumns)
                buildHeaderCell(option.genderKey == 'boys'
                    ? 'B'
                    : option.genderKey == 'girls'
                        ? 'G'
                        : 'T'),
            ],
          ),
          for (var rowIndex = 0; rowIndex < dataRows.length; rowIndex++)
            pw.TableRow(
              decoration: pw.BoxDecoration(
                color: rowIndex == dataRows.length - 1
                    ? pdf.PdfColors.amber100
                    : rowIndex.isEven
                        ? pdf.PdfColors.grey100
                        : pdf.PdfColors.white,
              ),
              children: <pw.Widget>[
                for (var columnIndex = 0; columnIndex < dataRows[rowIndex].length; columnIndex++)
                  pw.Container(
                    alignment: columnIndex == 0 ? pw.Alignment.centerLeft : pw.Alignment.center,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                    child: pw.Text(
                      dataRows[rowIndex][columnIndex],
                      maxLines: 2,
                      style: pw.TextStyle(
                        fontSize: 5.5,
                        fontWeight: rowIndex == dataRows.length - 1
                            ? pw.FontWeight.bold
                            : pw.FontWeight.normal,
                        color: pdf.PdfColors.black,
                      ),
                    ),
                  ),
              ],
            ),
        ];

        final groupKeys = <String>[];
        for (final option in metricColumns) {
          if (!groupKeys.contains(option.categoryKey)) groupKeys.add(option.categoryKey);
        }
        final categoryLabels = <String, String>{
          for (final category in DateWiseReportColumns.categories)
            category['key']!: category['label']!,
        };
        final columnsByCategory = <String, int>{
          for (final key in groupKeys)
            key: metricColumns.where((option) => option.categoryKey == key).length,
        };

        document.addPage(
          pw.MultiPage(
            pageFormat: pdf.PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.fromLTRB(16, 16, 16, 18),
            header: (context) => pw.Container(
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Column(
                children: <pw.Widget>[
                  pw.Text(
                    'DATE WISE ATTENDANCE REPORT',
                    style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    '$title — CATEGORY & GENDER-WISE',
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ),
            footer: (context) => pw.Container(
              alignment: pw.Alignment.centerRight,
              padding: const pw.EdgeInsets.only(top: 5),
              child: pw.Text(
                'Date: $date    Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 7),
              ),
            ),
            build: (context) => <pw.Widget>[
              pw.SizedBox(height: 4),
              pw.Row(
                children: <pw.Widget>[
                  pw.SizedBox(
                    width: classColumnWidth,
                    child: buildHeaderCell('CLASS', dark: false),
                  ),
                  for (final categoryKey in groupKeys)
                    pw.Expanded(
                      flex: columnsByCategory[categoryKey]!,
                      child: buildHeaderCell(categoryLabels[categoryKey] ?? categoryKey, dark: false),
                    ),
                ],
              ),
              pw.Table(
                border: pw.TableBorder.all(color: pdf.PdfColors.blueGrey300, width: 0.45),
                columnWidths: <int, pw.TableColumnWidth>{
                  0: const pw.FixedColumnWidth(classColumnWidth),
                  for (var i = 1; i <= metricColumns.length; i++) i: const pw.FlexColumnWidth(1),
                },
                children: bodyRows,
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                'Only the columns enabled by the school administrator are included. Total = Boys + Girls.',
                style: const pw.TextStyle(fontSize: 6.5),
              ),
            ],
          ),
        );
      }

      final bytes = await document.save();
      if (!mounted) return;
      hideBusyDialog(context);
      await Printing.sharePdf(bytes: bytes, filename: 'DATE WISE - $date.pdf');
    } catch (e) {
      if (!mounted) return;
      hideBusyDialog(context);
      showSnack(context, '❌ PDF બનાવવામાં ભૂલ: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // હાલમાં કયા યુઝર/શિક્ષકનું લોગિન છે તે ચેક કરો 
    final teacherName = context.watch<AppState>().currentTeacher?.name ?? '';
    final isPmPoshan = teacherName.trim().toUpperCase() == 'PM POSHAN';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const CardTitleRow(emoji: '📄', title: 'DATE WISE PDF'),
              const InfoBanner(
                title: '📌 તારીખ દ્વારા DATE WISE રિપોર્ટ',
                hint: 'તારીખ પસંદ કરો. રિપોર્ટ સીધો તે તારીખના વર્ગોની નોંધણી, હાજરી, PM Poshan અને નાસ્તાના આંકડાથી બનશે; Serial Number જરૂરી નથી.',
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  SizedBox(
                    width: 200,
                    child: LabeledField(
                      label: '📅 તારીખ પસંદ કરો',
                      child: InkWell(
                        onTap: _loading ? null : () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            final dateStr = DateFormat('yyyy-MM-dd').format(picked);
                            _runLookup(
                              () => SupabaseAttendanceReportService()
                                  .getDateWiseReportByDate(dateStr),
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: AppColors.border, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'કેલેન્ડર ખોલવા ક્લિક કરો',
                            style: guFont(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.navy),
                          ),
                        ),
                      ),
                    ),
                  ),
                  AppButton(
                    label: '📅 આજનો રિપોર્ટ',
                    background: const Color(0xFFDCFCE7),
                    foreground: const Color(0xFF166534),
                    onPressed: _loading ? null : _showToday,
                  ),
                ],
              ),
              if (_statusError != null) AlertBox(kind: AlertKind.error, text: '❌ $_statusError'),
              if (_multipleSerials != null) ...[
                const SizedBox(height: 14),
                Text('એક કરતાં વધુ Serial Number મળ્યા — એક પસંદ કરો:',
                    style: guFont(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in _multipleSerials!)
                      ActionChip(
                        label: Text(s, style: guFont(fontWeight: FontWeight.w700)),
                        onPressed: () {
                          _serialCtrl.text = s;
                          _runLookup(() => _api!.getDateWiseReport(s));
                        },
                      ),
                  ],
                ),
              ],
              if (_report != null) ...[
                const SizedBox(height: 20),
                Text(((_report!['serial'] ?? '').toString().trim().isEmpty)
                    ? 'તારીખ ${_report!['date']}'
                    : 'Serial ${_report!['serial']} · તારીખ ${_report!['date']}',
                    style: guFont(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.navyMid)),
                const SizedBox(height: 10),
                RawGridTable(rows: _rawValues(_report!['values'])),
                const SizedBox(height: 16),
                AppButton(label: '🖨️ SAVE AS PDF', onPressed: _savePdf),
              ],
            ],
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const CardTitleRow(emoji: '📊', title: 'માસિક રિપોર્ટ PDF', iconBg: AppColors.iconGreen),
              const InfoBanner(
                title: '📌 મહિનો પસંદ કરો અને PDF બનાવો',
                hint: 'દરેક રિપોર્ટ માટે મહિનો પસંદ કરો — Sheet માં cell (N1 / B2) માં જે નામ સિલેક્ટ થાય છે એ જ નામ અહીં પસંદ કરવું જરૂરી છે.',
              ),
              _MonthlyPdfSection(
                emoji: '🧒',
                label: 'બાલવાટિકા EKANDAR',
                onGenerate: (m) => _api!.getBalvatikaEkandarPDF(m),
              ),
              _divider(),
              _MonthlyPdfSection(
                emoji: '📘',
                label: 'STD 1 TO 5 EKANDAR',
                onGenerate: (m) => _api!.getStd1to5EkandarPDF(m),
              ),
              _divider(),
              _MonthlyPdfSection(
                emoji: '📗',
                label: 'STD 6 TO 8 EKANDAR',
                onGenerate: (m) => _api!.getStd6to8EkandarPDF(m),
              ),
              // જો યુઝર PM POSHAN નહિ હોય તો જ નીચેના 5 ઓપ્શન દેખાશે
              if (!isPmPoshan) ...[
                _divider(),
                _MonthlyPdfSection(
                  emoji: '📕',
                  label: 'TARIJ',
                  onGenerate: (m) => _api!.getTarijPDF(m),
                ),
                _divider(),
                _MonthlyClassWisePdfSection(
                  emoji: '📄',
                  label: 'HAJARI FRONT PAGE',
                  onGenerate: (m, c) => _api!.getHajariFrontPagePDF(m, c),
                ),
                _divider(),
                const _HajariPatrakPdfSection(),
                _divider(),
                const _TarijClassWiseSection(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _divider() => Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.only(bottom: 18),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0)))),
      );

  List<List<String>> _rawValues(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map<List<String>>((row) => (row is List) ? row.map((e) => e?.toString() ?? '').toList() : <String>[])
        .toList();
  }
}

/// One "pick a month → 🖨️ PDF બનાવો" row, reused for the 4 monthly
/// area exports (Balvatika / STD1-5 / STD6-8 / Tarij).
class _MonthlyPdfSection extends StatefulWidget {
  final String emoji;
  final String label;
  final Future<Map<String, dynamic>> Function(String month) onGenerate;
  const _MonthlyPdfSection({required this.emoji, required this.label, required this.onGenerate});

  @override
  State<_MonthlyPdfSection> createState() => _MonthlyPdfSectionState();
}

class _MonthlyPdfSectionState extends State<_MonthlyPdfSection> {
  String? _month;
  bool _loading = false;
  String? _status;
  bool _statusError = false;

  Future<void> _generate() async {
    if (_month == null) {
      setState(() {
        _status = 'મહિનો પસંદ કરો.';
        _statusError = true;
      });
      return;
    }
    setState(() {
      _loading = true;
      _status = null;
    });
    try {
      final res = await widget.onGenerate(_month!);
      await _deliverPdf(res, fallbackName: '${widget.label} - $_month.pdf');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusError = false;
        _status = '✅ PDF તૈયાર થયું.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusError = true;
        _status = '❌ $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // હાલમાં કયા યુઝર/શિક્ષકનું લોગિન છે તે ચેક કરો 
    final teacherName = context.watch<AppState>().currentTeacher?.name ?? '';
    final isPmPoshan = teacherName.trim().toUpperCase() == 'PM POSHAN';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${widget.emoji} ${widget.label}', style: guFont(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.slate, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(width: 200, child: _MonthDropdown(value: _month, onChanged: (v) => setState(() => _month = v))),
            AppButton(label: '🖨️ PDF બનાવો', loading: _loading, onPressed: _loading ? null : _generate),
          ],
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_status!, style: guFont(fontSize: 12.5, fontWeight: FontWeight.w700, color: _statusError ? AppColors.rose : AppColors.greenDeep)),
          ),
      ],
    );
  }
}

class _MonthDropdown extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _MonthDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      hint: Text('-- Select Month --', style: guFont(fontSize: 13, color: AppColors.slate)),
      items: AppConfig.monthNames.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
      onChanged: onChanged,
    );
  }
}

/// "🎯 TARIJ — ધોરણ મુજબ રિપોર્ટ" - shown on screen, not a PDF.
class _TarijClassWiseSection extends StatefulWidget {
  const _TarijClassWiseSection();

  @override
  State<_TarijClassWiseSection> createState() => _TarijClassWiseSectionState();
}

class _TarijClassWiseSectionState extends State<_TarijClassWiseSection> {
  List<String>? _classNames;
  String? _month;
  String? _className;
  bool _loading = false;
  String? _status;
  bool _statusError = false;
  Map<String, dynamic>? _result;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_classNames == null) {
      _classNames = [];
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadClassNames());
    }
  }

  Future<void> _loadClassNames() async {
    final api = context.read<AppState>().api;
    if (api == null) return;
    try {
      final names = await api.getTarijClassNames();
      if (mounted) setState(() => _classNames = names);
    } catch (_) {
      // fall back to the static class list if the endpoint fails
      if (mounted) setState(() => _classNames = context.read<AppState>().allSchoolClasses.map((c) => c.key).toList());
    }
  }

  Future<void> _show() async {
    final api = context.read<AppState>().api;
    if (api == null || _className == null || _month == null) {
      setState(() {
        _statusError = true;
        _status = 'પહેલા મહિનો, પછી ધોરણ પસંદ કરો.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _status = null;
      _result = null;
    });
    try {
      final res = await api.getTarijClassData(_className!, _month!);
      if (!mounted) return;
      if (res['result'] == 'success') {
        setState(() {
          _loading = false;
          _result = res;
        });
      } else {
        setState(() {
          _loading = false;
          _statusError = true;
          _status = res['message']?.toString() ?? 'ડેટા મળ્યો નથી.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusError = true;
        _status = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // હાલમાં કયા યુઝર/શિક્ષકનું લોગિન છે તે ચેક કરો 
    final teacherName = context.watch<AppState>().currentTeacher?.name ?? '';
    final isPmPoshan = teacherName.trim().toUpperCase() == 'PM POSHAN';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('🎯 TARIJ — ધોરણ મુજબ રિપોર્ટ', style: guFont(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.slate, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text('પહેલા મહિનો, પછી ધોરણ પસંદ કરો.', style: guFont(fontSize: 11, color: AppColors.slate)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(width: 170, child: _MonthDropdown(value: _month, onChanged: (v) => setState(() => _month = v))),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                value: (_classNames ?? const []).contains(_className) ? _className : null,
                isExpanded: true,
                hint: Text('-- ધોરણ પસંદ કરો --', style: guFont(fontSize: 13, color: AppColors.slate)),
                items: (_classNames ?? const []).map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _className = v),
              ),
            ),
            AppButton(label: '🔍 રિપોર્ટ બતાવો', loading: _loading, onPressed: _loading ? null : _show),
          ],
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_status!, style: guFont(fontSize: 12.5, fontWeight: FontWeight.w700, color: _statusError ? AppColors.rose : AppColors.greenDeep)),
          ),
        if (_result != null) ...[
          const SizedBox(height: 12),
          RawGridTable(
            rows: [
              ..._as2d(_result!['headers']),
              _as1d(_result!['row']),
            ],
            headerRows: _as2d(_result!['headers']).length,
          ),
        ],
      ],
    );
  }

  List<List<String>> _as2d(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map<List<String>>((row) => (row is List) ? row.map((e) => e?.toString() ?? '').toList() : <String>[]).toList();
  }

  List<String> _as1d(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e?.toString() ?? '').toList();
  }
}

class _MonthlyClassWisePdfSection extends StatefulWidget {
  final String emoji;
  final String label;
  final Future<Map<String, dynamic>> Function(String month, String className) onGenerate;

  const _MonthlyClassWisePdfSection({required this.emoji, required this.label, required this.onGenerate});

  @override
  State<_MonthlyClassWisePdfSection> createState() => _MonthlyClassWisePdfSectionState();
}

class _MonthlyClassWisePdfSectionState extends State<_MonthlyClassWisePdfSection> {
  List<String>? _classNames;
  String? _month;
  String? _className;
  bool _loading = false;
  String? _status;
  bool _statusError = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_classNames == null) {
      _classNames = [];
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadClassNames());
    }
  }

  Future<void> _loadClassNames() async {
    final api = context.read<AppState>().api;
    if (api == null) return;
    try {
      final names = await api.getTarijClassNames();
      if (mounted) setState(() => _classNames = names);
    } catch (_) {
      if (mounted) setState(() => _classNames = context.read<AppState>().allSchoolClasses.map((c) => c.key).toList());
    }
  }

  Future<void> _generate() async {
    if (_month == null || _className == null) {
      setState(() { _statusError = true; _status = 'પહેલા મહિનો અને ધોરણ પસંદ કરો.'; });
      return;
    }
    setState(() { _loading = true; _status = null; });
    try {
      final res = await widget.onGenerate(_month!, _className!);
      await _deliverPdf(res, fallbackName: '${widget.label} - $_className - $_month.pdf');
      if (!mounted) return;
      setState(() { _loading = false; _statusError = false; _status = '✅ PDF તૈયાર થયું.'; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _statusError = true; _status = '❌ $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    // હાલમાં કયા યુઝર/શિક્ષકનું લોગિન છે તે ચેક કરો 
    final teacherName = context.watch<AppState>().currentTeacher?.name ?? '';
    final isPmPoshan = teacherName.trim().toUpperCase() == 'PM POSHAN';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${widget.emoji} ${widget.label}', style: guFont(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.slate, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(width: 170, child: _MonthDropdown(value: _month, onChanged: (v) => setState(() => _month = v))),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                value: (_classNames ?? const []).contains(_className) ? _className : null,
                isExpanded: true,
                hint: Text('-- ધોરણ --', style: guFont(fontSize: 13, color: AppColors.slate)),
                items: (_classNames ?? const []).map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _className = v),
              ),
            ),
            AppButton(label: '🖨️ PDF બનાવો', loading: _loading, onPressed: _loading ? null : _generate),
          ],
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_status!, style: guFont(fontSize: 12.5, fontWeight: FontWeight.w700, color: _statusError ? AppColors.rose : AppColors.greenDeep)),
          ),
      ],
    );
  }
}
class _HajariPatrakPdfSection extends StatefulWidget {
  const _HajariPatrakPdfSection();

  @override
  State<_HajariPatrakPdfSection> createState() => _HajariPatrakPdfSectionState();
}

class _HajariPatrakPdfSectionState extends State<_HajariPatrakPdfSection> {
  List<String>? _classNames;
  String? _month;
  String? _className;
  bool _loading = false;
  String? _status;
  bool _statusError = false;

  final _rowHeightCtrl = TextEditingController();
  final _fontSizeCtrl = TextEditingController();

  @override
  void dispose() {
    _rowHeightCtrl.dispose();
    _fontSizeCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_classNames == null) {
      _classNames = [];
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadClassNames());
    }
  }

  Future<void> _loadClassNames() async {
    final api = context.read<AppState>().api;
    if (api == null) return;
    try {
      final names = await api.getTarijClassNames();
      if (mounted) setState(() => _classNames = names);
    } catch (_) {
      if (mounted) setState(() => _classNames = context.read<AppState>().allSchoolClasses.map((c) => c.key).toList());
    }
  }

  Future<void> _fetchSettings(String className) async {
    final api = context.read<AppState>().api;
    if (api == null) return;
    try {
      final res = await api.getSavedPdfSettings(className);
      if (res['result'] == 'success' && mounted) {
        setState(() {
          _rowHeightCtrl.text = res['rowHeight']?.toString() ?? '';
          _fontSizeCtrl.text = res['fontSize']?.toString() ?? '';
        });
      }
    } catch (_) {}
  }

  Future<void> _generate() async {
    if (_month == null || _className == null) {
      setState(() { _statusError = true; _status = 'પહેલા મહિનો અને ધોરણ પસંદ કરો.'; });
      return;
    }
    setState(() { _loading = true; _status = null; });
    try {
      final res = await context.read<AppState>().api!.getHajariPatrakPDF(
        _month!, 
        _className!, 
        rowHeight: _rowHeightCtrl.text.trim(), 
        fontSize: _fontSizeCtrl.text.trim(),
      );
      await _deliverPdf(res, fallbackName: 'HAJARI PATRAK - $_className - $_month.pdf');
      if (!mounted) return;
      setState(() { _loading = false; _statusError = false; _status = '✅ PDF તૈયાર થયું.'; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _statusError = true; _status = '❌ $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    // હાલમાં કયા યુઝર/શિક્ષકનું લોગિન છે તે ચેક કરો 
    final teacherName = context.watch<AppState>().currentTeacher?.name ?? '';
    final isPmPoshan = teacherName.trim().toUpperCase() == 'PM POSHAN';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('🗓️ HAJARI PATRAK', style: guFont(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.slate, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(width: 170, child: _MonthDropdown(value: _month, onChanged: (v) => setState(() => _month = v))),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                value: (_classNames ?? const []).contains(_className) ? _className : null,
                isExpanded: true,
                hint: Text('-- ધોરણ --', style: guFont(fontSize: 13, color: AppColors.slate)),
                items: (_classNames ?? const []).map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) {
                  setState(() => _className = v);
                  if (v != null) _fetchSettings(v); // ધોરણ પસંદ કરતા જ છેલ્લી સાઈઝ લઈ આવશે
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 170,
              child: TextFormField(
                controller: _rowHeightCtrl,
                keyboardType: TextInputType.number,
                style: guFont(fontSize: 14, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  labelText: 'Row Height (દા.ત. 25)',
                  labelStyle: guFont(fontSize: 12, color: AppColors.slate),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ),
            SizedBox(
              width: 170,
              child: TextFormField(
                controller: _fontSizeCtrl,
                keyboardType: TextInputType.number,
                style: guFont(fontSize: 14, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  labelText: 'Font Size (દા.ત. 10)',
                  labelStyle: guFont(fontSize: 12, color: AppColors.slate),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ),
            AppButton(label: '🖨️ PDF બનાવો', loading: _loading, onPressed: _loading ? null : _generate),
          ],
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_status!, style: guFont(fontSize: 12.5, fontWeight: FontWeight.w700, color: _statusError ? AppColors.rose : AppColors.greenDeep)),
          ),
      ],
    );
  }
}
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';
import 'package:universal_html/html.dart' as html;

import '../services/attendance_lifecycle.dart';
import '../services/school_class_order.dart';
import '../services/school_name_language_service.dart';

/// Textbook Issue Register (`પાઠ્યપુસ્તક વિતરણ કર્યાની પહોંચ`) for both Admin and Teachers.
/// Matches the user's exact A4 Portrait `TEXTBOOK` template:
/// - Snapshot date of students (active on that date)
/// - Serial numbers (1..N), Student names, 12 book columns, Student/Parent signature, Remarks
/// - Extra blank rows input
/// - Direct browser print PDF preserving exact A4 portrait page setup & repeating headers.
class SupabaseTextbookIssueRegisterScreen extends StatefulWidget {
  const SupabaseTextbookIssueRegisterScreen({
    super.key,
    required this.profile,
  });

  final Map<String, dynamic> profile;

  @override
  State<SupabaseTextbookIssueRegisterScreen> createState() =>
      _SupabaseTextbookIssueRegisterScreenState();
}

class _SupabaseTextbookIssueRegisterScreenState
    extends State<SupabaseTextbookIssueRegisterScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _blankRowsCtrl = TextEditingController(text: '5');
  final DateFormat _dmy = DateFormat('dd/MM/yyyy');

  bool _loading = true;
  bool _loadingStudents = false;
  String? _error;
  String _schoolRef = '';
  String _schoolName = 'શાળા';
  List<Map<String, dynamic>> _classes = <Map<String, dynamic>>[];
  String? _selectedClassId;
  late DateTime _snapshotDate;
  String _termLabel = 'પ્રથમ સત્ર પાઠ્ય પુસ્તક વિતરણ કર્યાની પહોંચ';
  List<Map<String, dynamic>> _students = <Map<String, dynamic>>[];

  static const List<String> _termOptions = <String>[
    'પ્રથમ સત્ર પાઠ્ય પુસ્તક વિતરણ કર્યાની પહોંચ',
    'દ્વિતીય સત્ર પાઠ્ય પુસ્તક વિતરણ કર્યાની પહોંચ',
    'પાઠ્ય પુસ્તક વિતરણ કર્યાની પહોંચ',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    _snapshotDate = DateTime(now.year, now.month, now.day);
    _loadInitial();
  }

  @override
  void dispose() {
    _blankRowsCtrl.dispose();
    super.dispose();
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _text(dynamic v) => (v ?? '').toString().trim();

  String get _academicYear {
    final startYr = _snapshotDate.month >= 6
        ? _snapshotDate.year
        : _snapshotDate.year - 1;
    return '$startYr-${(startYr + 1).toString().substring(2)}';
  }

  String get _selectedClassLabel {
    for (final c in _classes) {
      if (_text(c['id']) == _selectedClassId) {
        final lbl = _text(c['label']);
        return lbl.isNotEmpty ? lbl : _text(c['class_key']);
      }
    }
    return '';
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ref = _text(await _client.rpc('current_school_ref'));
      if (ref.isEmpty) throw StateError('સક્રિય શાળા login મળ્યું નથી.');
      final lang = await SchoolNameLanguageService.loadLanguage(schoolRef: ref);
      final sCtx =
          await SchoolNameLanguageService.loadCurrentSchoolContext(_client);
      final schoolName = SchoolNameLanguageService.resolveSchoolName(
        language: lang,
        profile: widget.profile,
        schoolContext: sCtx,
        fallbackEnglish: _text(
          widget.profile['school_name_en'] ??
              widget.profile['school_name'] ??
              'શાળા',
        ),
      );
      final rawClasses = await _client
          .from('school_classes')
          .select('id,class_key,label,standard,section,sort_order,is_active')
          .eq('school_ref', ref)
          .eq('is_active', true);
      final classes = SchoolClassOrder.sorted(
        rawClasses.map((e) => Map<String, dynamic>.from(e)),
      );
      if (!mounted) return;
      setState(() {
        _schoolRef = ref;
        _schoolName = schoolName;
        _classes = classes;
        _selectedClassId =
            classes.isEmpty ? null : _text(classes.first['id']);
        _loading = false;
      });
      if (_selectedClassId != null) {
        await _loadSnapshotStudents();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _loadSnapshotStudents() async {
    final cid = _selectedClassId;
    if (cid == null || cid.isEmpty || _schoolRef.isEmpty) return;
    setState(() {
      _loadingStudents = true;
      _error = null;
    });
    try {
      final snapIso = _iso(_snapshotDate);
      final rows = await _client
          .from('students')
          .select(
            'id,class_id,roll_number,previous_roll_number,name,gr,is_active,leaving_date,exit_date,enroll_school,enrollment_date,admission_date,enroll_class,custom_fields',
          )
          .eq('school_ref', _schoolRef)
          .eq('class_id', cid);

      final filtered = rows
          .map((e) => Map<String, dynamic>.from(e))
          .where((row) {
            final leaving = _text(row['leaving_date']).isNotEmpty
                ? _text(row['leaving_date'])
                : _text(row['exit_date']);
            if (leaving.length >= 10 &&
                leaving.substring(0, 10).compareTo(snapIso) < 0) {
              return false;
            }
            if (row['is_active'] == false && leaving.isEmpty) {
              return false;
            }
            final enrolled = AttendanceLifecycle.parseEnrollmentDate(row);
            if (enrolled != null &&
                AttendanceLifecycle.day(_snapshotDate)
                    .isBefore(AttendanceLifecycle.day(enrolled))) {
              return false;
            }
            return true;
          })
          .toList();

      filtered.sort((a, b) {
        final ar = int.tryParse(_text(a['roll_number'])) ??
            int.tryParse(_text(a['previous_roll_number'])) ??
            999999;
        final br = int.tryParse(_text(b['roll_number'])) ??
            int.tryParse(_text(b['previous_roll_number'])) ??
            999999;
        if (ar != br) return ar.compareTo(br);
        return _text(a['name']).compareTo(_text(b['name']));
      });

      if (!mounted) return;
      setState(() {
        _students = filtered;
        _loadingStudents = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _loadingStudents = false;
      });
    }
  }

  String _esc(String s) => const HtmlEscape().convert(s);

  void _printBrowserPdf() {
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Direct Browser Print Web બ્રાઉઝરમાં ઉપલબ્ધ છે.'),
        ),
      );
      return;
    }
    final extraBlank =
        (int.tryParse(_blankRowsCtrl.text.trim()) ?? 0).clamp(0, 150);
    final totalRows = _students.length + extraBlank;
    if (totalRows == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('પ્રિન્ટ કરવા માટે કોઈ વિદ્યાર્થી કે ખાલી હરોળ નથી.'),
        ),
      );
      return;
    }

    const int rowsPerPage = 14;
    final int pageCount = (totalRows + rowsPerPage - 1) ~/ rowsPerPage;
    final pagesHtml = StringBuffer();

    for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
      final start = pageIndex * rowsPerPage;
      final end = (start + rowsPerPage) > totalRows
          ? totalRows
          : (start + rowsPerPage);
      final isLastPage = pageIndex == pageCount - 1;
      final bodyRows = StringBuffer();
      for (var i = start; i < end; i++) {
        final isStudent = i < _students.length;
        final name = isStudent ? _esc(_text(_students[i]['name'])) : '';
        bodyRows.write('<tr>');
        bodyRows.write('<td class="sr">${i + 1}</td>');
        bodyRows.write('<td class="name">$name</td>');
        for (var b = 0; b < 12; b++) {
          bodyRows.write('<td class="bk"></td>');
        }
        bodyRows.write('<td class="sign"></td>');
        bodyRows.write('<td class="rem"></td>');
        bodyRows.write('</tr>\n');
      }

      pagesHtml.write('''
<div class="print-page${isLastPage ? ' last-page' : ''}">
<table>
  <colgroup>
    <col style="width: 4.60%;">
    <col style="width: 17.41%;">
    ${List.filled(12, '<col style="width: 4.03%;">').join('')}
    <col style="width: 23.02%;">
    <col style="width: 6.61%;">
  </colgroup>
  <thead>
    <tr class="r1"><th colspan="16" class="h-school">${_esc(_schoolName)}</th></tr>
    <tr class="r2"><th colspan="16" class="h-title">${_esc(_termLabel)}</th></tr>
    <tr class="r3"><th colspan="16" class="h-meta">ધોરણ :– ${_esc(_selectedClassLabel)} &nbsp;&nbsp;&nbsp;&nbsp;,&nbsp;&nbsp;&nbsp;&nbsp; વર્ષ :– ${_esc(_academicYear)}</th></tr>
    <tr class="r4">
      <th rowspan="2">ક્રમ</th>
      <th rowspan="2">વિદ્યાર્થીનું નામ</th>
      <th colspan="12">આપેલ પુસ્તકનું નામ</th>
      <th rowspan="2">વિદ્યાર્થી /<br>વાલીની સહી</th>
      <th rowspan="2">રિમાર્ક્સ</th>
    </tr>
    <tr class="r5">
      ${List.filled(12, '<th class="sub-bk"></th>').join('')}
    </tr>
  </thead>
  <tbody>
    $bodyRows
  </tbody>
</table>
</div>
''');
    }

    final docHtml = '''<!DOCTYPE html>
<html lang="gu">
<head>
<meta charset="utf-8">
<title>Textbook Issue Register - ${_esc(_selectedClassLabel)}</title>
<style>
  @page { size: A4 portrait; margin: 0.16in 0.08in 0.24in 0.28in; }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    padding: 0;
    font-family: "Noto Sans Gujarati", "Shruti", Arial, sans-serif;
    color: #000;
  }
  .print-page {
    page-break-after: always;
    break-after: page;
  }
  .print-page.last-page {
    page-break-after: auto;
    break-after: auto;
  }
  table {
    width: 100%;
    border-collapse: collapse;
    table-layout: fixed;
  }
  thead { display: table-header-group; }
  tr { page-break-inside: avoid; }
  .h-school {
    height: 25.5pt;
    font-size: 15.5pt;
    font-weight: 800;
    text-align: center;
    padding: 2px 4px;
    border: none;
    background: transparent;
  }
  .h-title {
    height: 25.5pt;
    font-size: 13pt;
    font-weight: 800;
    text-align: center;
    padding: 2px 4px;
    border: none;
    background: transparent;
  }
  .h-meta {
    height: 25.5pt;
    font-size: 12pt;
    font-weight: 700;
    text-align: center;
    padding: 2px 4px;
    border: none;
    background: transparent;
  }
  th, td {
    border: 1px solid #000;
    padding: 2px 3px;
    vertical-align: middle;
  }
  th {
    font-size: 10pt;
    font-weight: 800;
    text-align: center;
    background: #f8fafc;
  }
  tr.r4 th {
    height: 21pt;
  }
  th.sub-bk {
    height: 70.5pt;
    background: #fff;
  }
  tbody td {
    height: 43.5pt;
    font-size: 10.5pt;
  }
  td.sr { text-align: center; font-weight: 700; }
  td.name { text-align: left; font-weight: 700; padding-left: 5px; word-wrap: break-word; }
  td.bk, td.sign, td.rem { text-align: center; }
</style>
</head>
<body>
$pagesHtml
<script>window.onload = function() { window.print(); };</script>
</body>
</html>''';

    final blob = html.Blob(<dynamic>[docHtml], 'text/html;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.window.open(url, '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final extraBlank =
        (int.tryParse(_blankRowsCtrl.text.trim()) ?? 0).clamp(0, 150);
    return Scaffold(
      appBar: AppBar(
        title: const Text('પાઠ્યપુસ્તક વિતરણ રજીસ્ટર / Textbook Issue Register'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadInitial,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          value: _selectedClassId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'ધોરણ પસંદ કરો (Select Class)',
                            border: OutlineInputBorder(),
                          ),
                          items: _classes
                              .map(
                                (c) => DropdownMenuItem<String>(
                                  value: _text(c['id']),
                                  child: Text(
                                    _text(c['label']).isNotEmpty
                                        ? _text(c['label'])
                                        : _text(c['class_key']),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _selectedClassId = v);
                            _loadSnapshotStudents();
                          },
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: _termLabel,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'શીર્ષક / સત્ર (Register Title)',
                            border: OutlineInputBorder(),
                          ),
                          items: _termOptions
                              .map(
                                (t) => DropdownMenuItem<String>(
                                  value: t,
                                  child: Text(t),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _termLabel = v);
                          },
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                final p = await showDatePicker(
                                  context: context,
                                  initialDate: _snapshotDate,
                                  firstDate: DateTime(2018),
                                  lastDate: DateTime(2100),
                                  helpText: 'વિદ્યાર્થી યાદીની તારીખ (Snapshot Date)',
                                );
                                if (p != null && mounted) {
                                  setState(() => _snapshotDate = p);
                                  _loadSnapshotStudents();
                                }
                              },
                              icon: const Icon(Icons.calendar_month),
                              label: Text(
                                'વિદ્યાર્થી Snapshot તારીખ: ${_dmy.format(_snapshotDate)}',
                              ),
                            ),
                            SizedBox(
                              width: 220,
                              child: TextField(
                                controller: _blankRowsCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  labelText: 'વધારાની ખાલી હરોળ (Extra Blank Rows)',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _loadingStudents ? null : _printBrowserPdf,
                          icon: const Icon(Icons.print_rounded),
                          label: Text(
                            '🖨️ ડાયરેક્ટ બ્રાઉઝર પ્રિન્ટ / PDF (${_students.length} વિદ્યાર્થી + $extraBlank ખાલી હરોળ)',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 10),
                if (_loadingStudents)
                  const LinearProgressIndicator()
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'યાદી પ્રિવ્યુ — $_selectedClassLabel (${_students.length} વિદ્યાર્થીઓ • તારીખ: ${_dmy.format(_snapshotDate)})',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          if (_students.isEmpty)
                            const Text('આ તારીખે આ વર્ગમાં કોઈ વિદ્યાર્થી મળ્યો નથી.')
                          else
                            for (var i = 0; i < _students.length; i++)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  '${i + 1}. ${_text(_students[i]['name'])}',
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

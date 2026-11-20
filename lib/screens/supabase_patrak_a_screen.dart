import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';
import 'package:universal_html/html.dart' as html;

import '../services/attendance_lifecycle.dart';
import '../services/school_class_order.dart';
import '../services/school_name_language_service.dart';

/// Standalone Patrak-A (`અનૌપચારિક સતત મૂલ્યાંકનનું પત્રક-A`) view embedded
/// inside the Result section as its own dedicated tab (completely independent
/// of Result marks entry and Result printing).
/// Supports:
/// - Both Admin and Teachers
/// - Student Snapshot Date (independent of Result roster)
/// - Subject selection
/// - Three Boxes (`PATRAK-A three boxes`) or Single Box (`PATRAK-A one box`)
/// - Extra blank rows
/// - Last row: `વિષય શિક્ષકની સહી –` (matching template row 250)
/// - Direct Browser Print PDF in exact Legal Landscape page setup with repeating header rows.
class SupabasePatrakAView extends StatefulWidget {
  const SupabasePatrakAView({
    super.key,
    this.initialClassKey,
    this.initialSemester = 1,
  });

  final String? initialClassKey;
  final int initialSemester;

  @override
  State<SupabasePatrakAView> createState() => _SupabasePatrakAViewState();
}

class _SupabasePatrakAViewState extends State<SupabasePatrakAView> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _blankRowsCtrl = TextEditingController(text: '5');
  final TextEditingController _customSubjectCtrl = TextEditingController();
  final DateFormat _dmy = DateFormat('dd/MM/yyyy');

  static const List<String> _defaultSubjects = <String>[
    'ગુજરાતી',
    'ગણિત',
    'અંગ્રેજી',
    'પર્યાવરણ / આસપાસ',
    'વિજ્ઞાન',
    'સામાજિક વિજ્ઞાન',
    'હિન્દી',
    'સંસ્કૃત',
    'કલા / ચિત્રકામ',
    'શા. શિ.',
    'કમ્પ્યુટર',
    'અન્ય (જાતે લખો)',
  ];

  bool _loading = true;
  bool _loadingStudents = false;
  String? _error;
  String _schoolRef = '';
  String _schoolName = 'શાળા';
  List<Map<String, dynamic>> _classes = <Map<String, dynamic>>[];
  String? _selectedClassId;
  late DateTime _snapshotDate;
  late int _semester;
  bool _threeBoxes = true;
  List<String> _subjects = List<String>.from(_defaultSubjects);
  String _selectedSubject = _defaultSubjects.first;
  List<Map<String, dynamic>> _students = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    _snapshotDate = DateTime(now.year, now.month, now.day);
    _semester = widget.initialSemester == 2 ? 2 : 1;
    _loadInitial();
  }

  @override
  void dispose() {
    _blankRowsCtrl.dispose();
    _customSubjectCtrl.dispose();
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

  String get _effectiveSubject {
    if (_selectedSubject == 'અન્ય (જાતે લખો)') {
      return _customSubjectCtrl.text.trim();
    }
    return _selectedSubject;
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
        schoolContext: sCtx,
        fallbackEnglish: _text(
          sCtx['school_name_en'] ?? sCtx['school_name'] ?? 'શાળા',
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

      String? initialId;
      final wantKey = (widget.initialClassKey ?? '').trim().toLowerCase();
      if (wantKey.isNotEmpty) {
        for (final c in classes) {
          if (_text(c['id']).toLowerCase() == wantKey ||
              _text(c['class_key']).toLowerCase() == wantKey ||
              _text(c['label']).toLowerCase() == wantKey) {
            initialId = _text(c['id']);
            break;
          }
        }
      }
      initialId ??= classes.isEmpty ? null : _text(classes.first['id']);

      if (!mounted) return;
      setState(() {
        _schoolRef = ref;
        _schoolName = schoolName;
        _classes = classes;
        _selectedClassId = initialId;
        _loading = false;
      });
      if (_selectedClassId != null) {
        await Future.wait([
          _loadSubjectsForClass(),
          _loadSnapshotStudents(),
        ]);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _loadSubjectsForClass() async {
    final cid = _selectedClassId;
    if (cid == null || cid.isEmpty || _schoolRef.isEmpty) return;
    try {
      final rows = await _client
          .from('class_subjects')
          .select('subject_name')
          .eq('school_ref', _schoolRef)
          .eq('class_id', cid);
      final found = <String>{};
      for (final r in rows) {
        final name = _text(r['subject_name']);
        if (name.isNotEmpty && name != 'વ્યક્તિત્વ વિકાસ') {
          found.add(name);
        }
      }
      final merged = <String>[
        ...found,
        for (final d in _defaultSubjects)
          if (!found.contains(d)) d,
      ];
      if (!mounted) return;
      setState(() {
        _subjects = merged;
        if (!_subjects.contains(_selectedSubject)) {
          _selectedSubject = _subjects.first;
        }
      });
    } catch (_) {}
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

  void _printPatrakABrowserPdf() {
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Direct Browser Print Web બ્રાઉઝરમાં ઉપલબ્ધ છે.'),
        ),
      );
      return;
    }
    final subj = _effectiveSubject;
    if (subj.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('કૃપા કરીને વિષય પસંદ કરો અથવા લખો.')),
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

    final semText = _semester == 1 ? 'પ્રથમ સત્ર' : 'દ્વિતીય સત્ર';
    final loHeaders = StringBuffer();
    for (var n = 1; n <= 20; n++) {
      loHeaders.write('<th colspan="3" class="lo-num">$n</th>');
    }

    const int rowsPerPage = 16;
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
        if (_threeBoxes) {
          for (var b = 0; b < 60; b++) {
            bodyRows.write('<td class="lo3"></td>');
          }
        } else {
          for (var b = 0; b < 20; b++) {
            bodyRows.write('<td colspan="3" class="lo1"></td>');
          }
        }
        bodyRows.write('<td class="tot"></td>');
        bodyRows.write('<td class="tot"></td>');
        bodyRows.write('<td class="tot"></td>');
        bodyRows.write('<td class="marks"></td>');
        bodyRows.write('</tr>\n');
      }

      if (isLastPage) {
        // Last row: Subject Teacher's Sign (from template row 250)
        bodyRows.write(
          '<tr class="sign-row">'
          '<td colspan="66" class="sign-cell">વિષય શિક્ષકની સહી – ______________________________________</td>'
          '</tr>\n',
        );
      }

      pagesHtml.write('''
<div class="print-page${isLastPage ? ' last-page' : ''}">
<table>
  <colgroup>
    <col style="width: 3.17%;">
    <col style="width: 10.10%;">
    ${List.filled(60, '<col style="width: 1.283%;">').join('')}
    <col style="width: 2.22%;">
    <col style="width: 2.05%;">
    <col style="width: 1.63%;">
    <col style="width: 3.85%;">
  </colgroup>
  <thead>
    <tr class="r1"><th colspan="66" class="noborder h-school">${_esc(_schoolName)}</th></tr>
    <tr class="r2"><th colspan="66" class="noborder h-sub">પરિશિષ્ટ - અ</th></tr>
    <tr class="r3"><th colspan="66" class="noborder h-title">અનૌપચારિક સતત મૂલ્યાંકનનું પત્રક-A &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; (વર્ષ : ${_esc(_academicYear)})</th></tr>
    <tr class="r4">
      <th colspan="2" class="noborder h-meta">ધોરણ :– ${_esc(_selectedClassLabel)}</th>
      <th colspan="27" class="noborder h-meta">વિષય :– ${_esc(subj)}</th>
      <th colspan="14" class="noborder h-meta">સત્ર :– ${_esc(semText)}</th>
      <th colspan="23" class="noborder h-meta">સત્રની અધ્યયન નિષ્પત્તિઓ :–</th>
    </tr>
    <tr class="r5">
      <th rowspan="2">ક્રમ</th>
      <th rowspan="2">વિદ્યાર્થીનું નામ</th>
      <th colspan="60">અભ્યાસક્રમ પ્રમાણે સત્રની પ્રતિનિધિરૂપ અધ્યયન નિષ્પત્તિઓનો ક્રમ</th>
      <th colspan="3">સત્રાંતે વિદ્યાર્થીઓએ મેળવેલ નિશાનીઓની કુલ સંખ્યા</th>
      <th rowspan="2">40 માથી<br>મેળવેલ ગુણ</th>
    </tr>
    <tr class="r6">
      $loHeaders
      <th>x</th>
      <th>?</th>
      <th>√</th>
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
<title>Patrak-A - ${_esc(_selectedClassLabel)} - ${_esc(subj)}</title>
<style>
  @page { size: legal landscape; margin: 0.2in; }
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
  .noborder { border: none !important; background: transparent !important; }
  .h-school { height: 23.25pt; font-size: 14.5pt; font-weight: 800; text-align: center; padding: 1px; }
  .h-sub { height: 18pt; font-size: 11.5pt; font-weight: 800; text-align: center; padding: 1px; }
  .h-title { height: 18.75pt; font-size: 12pt; font-weight: 800; text-align: center; padding: 1px; }
  .h-meta { height: 20.25pt; font-size: 10.5pt; font-weight: 700; text-align: left; padding: 1px 4px; }
  th, td {
    border: 1px solid #000;
    padding: 1px 2px;
    vertical-align: middle;
  }
  th {
    font-size: 8.6pt;
    font-weight: 800;
    text-align: center;
    background: #f8fafc;
  }
  tr.r5 th { height: 57.75pt; }
  tr.r6 th, th.lo-num { height: 16.5pt; font-size: 8.5pt; }
  tbody td {
    height: 24.95pt;
    font-size: 9.5pt;
  }
  td.sr { text-align: center; font-weight: 700; }
  td.name { text-align: left; font-weight: 700; padding-left: 4px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  tr.sign-row td.sign-cell {
    border: none !important;
    height: 24pt;
    padding-top: 8pt;
    font-size: 11pt;
    font-weight: 800;
    text-align: left;
    padding-left: 8%;
  }
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
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final extraBlank =
        (int.tryParse(_blankRowsCtrl.text.trim()) ?? 0).clamp(0, 150);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '📋 અનૌપચારિક સતત મૂલ્યાંકનનું પત્રક - A (Patrak A — Direct Browser Print PDF)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                ),
                const SizedBox(height: 4),
                const Text(
                  'આ પત્રક-A રિઝલ્ટ પ્રિન્ટિંગથી અલગ છે. અહીંથી કોઈપણ તારીખની વિદ્યાર્થી યાદી (Snapshot), વિષય અને ૩ ખાના અથવા ૧ ખાના મુજબ સીધું Legal Landscape PDF પ્રિન્ટ કરી શકાશે (છેલ્લી હરોળમાં વિષય શિક્ષકની સહી સાથે).',
                  style: TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: 210,
                      child: DropdownButtonFormField<String>(
                        value: _selectedClassId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'ધોરણ (Class)',
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
                          _loadSubjectsForClass();
                          _loadSnapshotStudents();
                        },
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        value: _selectedSubject,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'વિષય (Subject)',
                          border: OutlineInputBorder(),
                        ),
                        items: _subjects
                            .map(
                              (s) => DropdownMenuItem<String>(
                                value: s,
                                child: Text(s, overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedSubject = v);
                        },
                      ),
                    ),
                    if (_selectedSubject == 'અન્ય (જાતે લખો)')
                      SizedBox(
                        width: 220,
                        child: TextField(
                          controller: _customSubjectCtrl,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'વિષયનું નામ લખો',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
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
                      icon: const Icon(Icons.calendar_month, size: 18),
                      label: Text('Snapshot તારીખ: ${_dmy.format(_snapshotDate)}'),
                    ),
                    SizedBox(
                      width: 190,
                      child: TextField(
                        controller: _blankRowsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'વધારાની ખાલી હરોળ',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ChoiceChip(
                      selected: _semester == 1,
                      label: const Text('પ્રથમ સત્ર'),
                      onSelected: (_) => setState(() => _semester = 1),
                    ),
                    ChoiceChip(
                      selected: _semester == 2,
                      label: const Text('દ્વિતીય સત્ર'),
                      onSelected: (_) => setState(() => _semester = 2),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      selected: _threeBoxes,
                      label: const Text('૩ ખાના (Three Boxes)'),
                      onSelected: (_) => setState(() => _threeBoxes = true),
                    ),
                    ChoiceChip(
                      selected: !_threeBoxes,
                      label: const Text('૧ ખાનું (Single Box)'),
                      onSelected: (_) => setState(() => _threeBoxes = false),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _loadingStudents ? null : _printPatrakABrowserPdf,
                  icon: const Icon(Icons.print_rounded),
                  label: Text(
                    '🖨️ પત્રક - A પ્રિન્ટ / PDF (${_threeBoxes ? "૩ ખાના" : "૧ ખાનું"} • ${_students.length} વિદ્યાર્થી + $extraBlank ખાલી હરોળ)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
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
                    'વિદ્યાર્થી યાદી પ્રિવ્યુ — $_selectedClassLabel (${_students.length} વિદ્યાર્થીઓ • તારીખ: ${_dmy.format(_snapshotDate)})',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  if (_students.isEmpty)
                    const Text('આ તારીખે આ વર્ગમાં કોઈ વિદ્યાર્થી મળ્યો નથી.')
                  else
                    for (var i = 0; i < _students.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('${i + 1}. ${_text(_students[i]['name'])}'),
                      ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

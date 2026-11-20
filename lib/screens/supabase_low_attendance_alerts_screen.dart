import 'dart:typed_data';

import 'package:excel_community/excel_community.dart' as ec;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/psm_file_export_helper.dart';
import '../services/school_class_order.dart';

/// Low-Attendance Alert List (`સતત ગેરહાજર / ઓછી હાજરી યાદી`):
/// 1. Highlights students absent for 3+ consecutive working days OR below 75% monthly attendance
///    (computed strictly from student-wise attendance; Direct Entry days are ignored).
/// 2. 1-tap Gujarati WhatsApp notice to parents.
/// 3. Admin Excel Export: enter minimum absent days (e.g. 5 -> 5 or more absent days)
///    for a selected Month or Custom Date Range and download `.xlsx`.
class SupabaseLowAttendanceAlertsScreen extends StatefulWidget {
  const SupabaseLowAttendanceAlertsScreen({
    super.key,
    required this.profile,
    this.initialFilterMode = 'all',
  });

  final Map<String, dynamic> profile;
  final String initialFilterMode;

  @override
  State<SupabaseLowAttendanceAlertsScreen> createState() =>
      _SupabaseLowAttendanceAlertsScreenState();
}

class _SupabaseLowAttendanceAlertsScreenState
    extends State<SupabaseLowAttendanceAlertsScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _minAbsentDaysCtrl = TextEditingController(text: '5');
  final DateFormat _dmy = DateFormat('dd-MM-yyyy');

  bool _loading = true;
  bool _exporting = false;
  String? _error;
  String _schoolRef = '';
  String _monthPrefix = '';
  String _filterMode = 'all'; // 'all' | 'consecutive' | 'low_pct'
  List<Map<String, dynamic>> _alerts = <Map<String, dynamic>>[];

  // Admin Excel export period controls
  String _exportScope = 'month'; // 'month' | 'range'
  late DateTime _exportMonth;
  late DateTime _rangeStart;
  late DateTime _rangeEnd;

  bool get _isAdmin {
    final r = '${widget.profile['role'] ?? 'teacher'}'.trim().toLowerCase();
    return r == 'admin' || r == 'developer';
  }

  @override
  void initState() {
    super.initState();
    _filterMode = widget.initialFilterMode;
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    _exportMonth = DateTime(now.year, now.month, 1);
    _rangeStart = DateTime(now.year, now.month, 1);
    _rangeEnd = DateTime(now.year, now.month, now.day);
    _load();
  }

  @override
  void dispose() {
    _minAbsentDaysCtrl.dispose();
    super.dispose();
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _text(dynamic v) => (v ?? '').toString().trim();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ref = _text(await _client.rpc('current_school_ref'));
      if (ref.isEmpty) throw StateError('સક્રિય શાળા login મળ્યું નથી.');
      final res = await _client.rpc(
        'psm_compute_absence_streaks_and_alerts',
        params: const <String, dynamic>{},
      );
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      final rawAlerts = (map['alerts'] as List? ?? const <dynamic>[])
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry('$k', v)))
          .toList();
      if (!mounted) return;
      setState(() {
        _schoolRef = ref;
        _alerts = rawAlerts;
        _monthPrefix = _text(map['month_prefix']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  String _normalizePhone(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
    if (d.length == 10) d = '91$d';
    if (d.length < 11 || d.length > 15) return '';
    return d;
  }

  Future<void> _sendParentWhatsApp(Map<String, dynamic> item) async {
    final schoolName = _text(
      widget.profile['school_name_gu'] ??
          widget.profile['school_name_en'] ??
          widget.profile['school_name'] ??
          'શાળા',
    );
    final stName = _text(item['student_name']);
    final clsLabel = _text(item['class_label']);
    final streak = (item['consecutive_absent'] as int?) ?? 0;
    final pct = item['month_percentage'] ?? 0;
    final monthAbs = item['month_absent_days'] ?? 0;
    final msg = StringBuffer()
      ..writeln('નમસ્તે વાલીશ્રી,')
      ..writeln('🏫 $schoolName')
      ..writeln('')
      ..writeln('આપના બાળક *$stName* (ધોરણ: $clsLabel) અંગે મહત્વપૂર્ણ જાણ:')
      ..writeln(
        streak >= 3
            ? '• વિદ્યાર્થી સતત *$streak દિવસ* થી શાળાએ ગેરહાજર છે.'
            : '• ચાલુ મહિનામાં હાજરી *$pct%* છે (ગેરહાજર દિવસો: $monthAbs).',
      )
      ..writeln('')
      ..writeln(
        'કૃપા કરીને વિદ્યાર્થીની ગેરહાજરીનું કારણ જણાવશો અને નિયમિત શાળાએ મોકલવા વિનંતી છે.',
      );

    final phone = _normalizePhone(_text(item['mobile']));
    final encoded = Uri.encodeComponent(msg.toString().trim());
    final uri = phone.isNotEmpty
        ? Uri.parse('https://wa.me/$phone?text=$encoded')
        : Uri.parse('https://wa.me/?text=$encoded');

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: msg.toString().trim()));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('WhatsApp સંદેશ ક્લિપબોર્ડ પર કોપી થઈ ગયો છે.'),
          ),
        );
      }
    }
  }

  Future<void> _exportAbsentExcel() async {
    final minDays = int.tryParse(_minAbsentDaysCtrl.text.trim()) ?? 0;
    if (minDays < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('કૃપા કરીને ઓછામાં ઓછા ગેરહાજર દિવસોની સંખ્યા (1 કે વધુ) દાખલ કરો.'),
        ),
      );
      return;
    }

    late String startIso;
    late String endIso;
    if (_exportScope == 'month') {
      final first = DateTime(_exportMonth.year, _exportMonth.month, 1);
      final last = DateTime(_exportMonth.year, _exportMonth.month + 1, 0);
      startIso = _iso(first);
      endIso = _iso(last);
    } else {
      startIso = _iso(_rangeStart);
      endIso = _iso(_rangeEnd);
      if (endIso.compareTo(startIso) < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('અંતિમ તારીખ શરૂઆતની તારીખથી પહેલાં ન હોઈ શકે.')),
        );
        return;
      }
    }

    setState(() => _exporting = true);
    try {
      final rawClasses = await _client
          .from('school_classes')
          .select('id,class_key,label,sort_order,is_active')
          .eq('school_ref', _schoolRef)
          .eq('is_active', true);
      final classes = SchoolClassOrder.sorted(
        rawClasses.map((e) => Map<String, dynamic>.from(e)),
      );
      final classLabelById = <String, String>{
        for (final c in classes)
          _text(c['id']): _text(c['label']).isNotEmpty
              ? _text(c['label'])
              : _text(c['class_key']),
      };
      final classOrderById = <String, int>{
        for (var i = 0; i < classes.length; i++) _text(classes[i]['id']): i,
      };

      final rawStudents = await _client
          .from('students')
          .select('id,class_id,roll_number,gr,name,mobile,is_active,leaving_date,exit_date')
          .eq('school_ref', _schoolRef)
          .eq('is_active', true);
      final students = rawStudents
          .map((e) => Map<String, dynamic>.from(e))
          .where(
            (s) =>
                s['is_active'] == true &&
                _text(s['leaving_date']).isEmpty &&
                _text(s['exit_date']).isEmpty,
          )
          .toList();

      final rawDays = await _client
          .from('attendance_days')
          .select('id,class_id,attendance_date,attendance_mode,student_details_saved,present_saved,student_marks')
          .eq('school_ref', _schoolRef)
          .gte('attendance_date', startIso)
          .lte('attendance_date', endIso);

      // Strictly student-wise attendance only (skip Direct Entry!)
      final studentDays = rawDays
          .map((e) => Map<String, dynamic>.from(e))
          .where(
            (d) =>
                _text(d['attendance_mode']).toLowerCase() != 'direct' &&
                d['student_details_saved'] != false &&
                d['present_saved'] != false,
          )
          .toList();

      final legacyDayIds = <String>[];
      for (final d in studentDays) {
        if (d['student_marks'] is! Map) {
          final did = _text(d['id']);
          if (did.isNotEmpty) legacyDayIds.add(did);
        }
      }
      final legacyMarksByDay = <String, Map<String, bool>>{};
      if (legacyDayIds.isNotEmpty) {
        for (var i = 0; i < legacyDayIds.length; i += 200) {
          final chunk = legacyDayIds.skip(i).take(200).toList();
          final marks = await _client
              .from('student_attendance')
              .select('attendance_day_id,student_id,present')
              .eq('school_ref', _schoolRef)
              .inFilter('attendance_day_id', chunk);
          for (final m in marks) {
            final did = _text(m['attendance_day_id']);
            final sid = _text(m['student_id']);
            legacyMarksByDay.putIfAbsent(did, () => <String, bool>{})[sid] =
                m['present'] == true;
          }
        }
      }

      final daysByClass = <String, List<Map<String, dynamic>>>{};
      for (final d in studentDays) {
        final cid = _text(d['class_id']);
        daysByClass.putIfAbsent(cid, () => <Map<String, dynamic>>[]).add(d);
      }

      final matchingRows = <Map<String, dynamic>>[];
      for (final st in students) {
        final sid = _text(st['id']);
        final cid = _text(st['class_id']);
        final clsDays = daysByClass[cid];
        if (clsDays == null || clsDays.isEmpty) continue;

        var working = 0;
        var present = 0;
        var absent = 0;
        final absentDates = <String>[];
        for (final d in clsDays) {
          final did = _text(d['id']);
          bool? isPres;
          if (d['student_marks'] is Map) {
            final m = (d['student_marks'] as Map)[sid];
            if (m is Map) isPres = m['present'] == true;
          } else if (legacyMarksByDay[did]?.containsKey(sid) == true) {
            isPres = legacyMarksByDay[did]![sid];
          }
          if (isPres == null) continue;
          working++;
          if (isPres) {
            present++;
          } else {
            absent++;
            absentDates.add(_text(d['attendance_date']));
          }
        }

        if (absent >= minDays) {
          absentDates.sort();
          final pct = working > 0 ? (present * 100.0 / working) : 0.0;
          matchingRows.add(<String, dynamic>{
            'class_order': classOrderById[cid] ?? 9999,
            'class_label': classLabelById[cid] ?? 'Class',
            'roll_number': _text(st['roll_number']),
            'gr': _text(st['gr']),
            'name': _text(st['name']),
            'mobile': _text(st['mobile']),
            'working_days': working,
            'present_days': present,
            'absent_days': absent,
            'percentage': pct.toStringAsFixed(1),
            'absent_dates': absentDates.join(', '),
          });
        }
      }

      matchingRows.sort((a, b) {
        final co = (a['class_order'] as int).compareTo(b['class_order'] as int);
        if (co != 0) return co;
        final ab = (b['absent_days'] as int).compareTo(a['absent_days'] as int);
        if (ab != 0) return ab;
        return _text(a['name']).compareTo(_text(b['name']));
      });

      if (matchingRows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$startIso થી $endIso દરમિયાન $minDays કે તેથી વધુ દિવસ ગેરહાજર કોઈ વિદ્યાર્થી મળ્યો નથી.',
              ),
            ),
          );
        }
        return;
      }

      final wb = ec.Excel.createExcel();
      final sheet = wb['Sheet1'];
      final headers = <String>[
        'ક્રમ (Sr)',
        'ધોરણ (Class)',
        'રોલ નં. (Roll)',
        'GR નં.',
        'વિદ્યાર્થીનું નામ (Student Name)',
        'વાલી મોબાઈલ (Mobile)',
        'કુલ કાર્યદિવસ (Working)',
        'હાજર દિવસ (Present)',
        'ગેરહાજર દિવસ (Absent)',
        'હાજરી %',
        'ગેરહાજર તારીખો (Absent Dates)',
      ];
      for (var c = 0; c < headers.length; c++) {
        sheet
            .cell(ec.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
            .value = ec.TextCellValue(headers[c]);
      }
      for (var i = 0; i < matchingRows.length; i++) {
        final r = matchingRows[i];
        final vals = <String>[
          '${i + 1}',
          _text(r['class_label']),
          _text(r['roll_number']),
          _text(r['gr']),
          _text(r['name']),
          _text(r['mobile']),
          '${r['working_days']}',
          '${r['present_days']}',
          '${r['absent_days']}',
          '${r['percentage']}%',
          _text(r['absent_dates']),
        ];
        for (var c = 0; c < vals.length; c++) {
          sheet
              .cell(
                ec.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: i + 1),
              )
              .value = ec.TextCellValue(vals[c]);
        }
      }

      final bytes = wb.encode();
      if (bytes != null) {
        await PsmFileExportHelper.saveOrShare(
          bytes: Uint8List.fromList(bytes),
          filename: 'Absent_Students_${minDays}PlusDays_${startIso}_to_$endIso.xlsx',
          title: 'Absent Students ($minDays+ Days)',
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${matchingRows.length} વિદ્યાર્થીઓની ગેરહાજર યાદી ($minDays+ દિવસ) Excel માં ડાઉનલોડ થઈ.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel ભૂલ: ${'$e'.replaceFirst('Exception: ', '')}')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _alerts.where((item) {
      final streak = (item['consecutive_absent'] as int?) ?? 0;
      final pct = (item['month_percentage'] as num?)?.toDouble() ?? 100.0;
      if (_filterMode == 'consecutive') return streak >= 3;
      if (_filterMode == 'below_65') return pct < 65.0;
      if (_filterMode == 'low_pct') return pct < 75.0;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('સતત ગેરહાજર / ઓછી હાજરી યાદી'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
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
                  color: const Color(0xFFFFFBEB),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      '📌 ઓટોમેટિક સૂચના નિયમો (માત્ર Student-wise હાજરી માટે; Direct Entry માટે કોઈ એલર્ટ નહીં):\n'
                      '• સતત 4 દિવસ ગેરહાજર → શિક્ષકને પોપઅપ (અન્ય વિદ્યાર્થી દ્વારા ફોન/કારણ પૂછવું)\n'
                      '• સતત 7 દિવસ ગેરહાજર → શિક્ષકને પોપઅપ (વાલીનો રૂબરૂ સંપર્ક)\n'
                      '• સતત 10 દિવસ ગેરહાજર → Admin ને પોપઅપ (વર્ગ શિક્ષકને કારણ પૂછવું)\n'
                      '• સતત 15 દિવસ ગેરહાજર → શિક્ષક અને Admin બંનેને પોપઅપ (વાલી મુલાકાત)\n'
                      '• સતત 21 દિવસ ગેરહાજર → શિક્ષક અને Admin બંનેને પોપઅપ (CRC કો-ઓર્ડિનેટરને જાણ કરી આચાર્યશ્રી સાથે વાલી મુલાકાત)\n'
                      '• સતત 30 દિવસ ગેરહાજર → શિક્ષક અને Admin બંનેને પોપઅપ (SMC ને જાણ કરવી)\n'
                      '• 30 દિવસથી વધુ → કોઈ રીમાઈન્ડર નહીં (દરેક સૂચના માત્ર એક જ વાર).',
                      style: TextStyle(fontSize: 12.5, height: 1.45),
                    ),
                  ),
                ),
                if (_isAdmin) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '📥 Admin Excel ડાઉનલોડ — N કે તેથી વધુ દિવસ ગેરહાજર વિદ્યાર્થીઓ',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ChoiceChip(
                                selected: _exportScope == 'month',
                                label: const Text('માસિક (Monthly)'),
                                onSelected: (_) =>
                                    setState(() => _exportScope = 'month'),
                              ),
                              ChoiceChip(
                                selected: _exportScope == 'range',
                                label: const Text('તારીખ રેન્જ (Date Range)'),
                                onSelected: (_) =>
                                    setState(() => _exportScope = 'range'),
                              ),
                              SizedBox(
                                width: 220,
                                child: TextField(
                                  controller: _minAbsentDaysCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: 'ઓછામાં ઓછા ગેરહાજર દિવસ (દા.ત. 5)',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (_exportScope == 'month')
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: _exportMonth,
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime(2100),
                                    );
                                    if (picked != null && mounted) {
                                      setState(
                                        () => _exportMonth = DateTime(
                                          picked.year,
                                          picked.month,
                                          1,
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.calendar_month),
                                  label: Text(
                                    'મહિનો: ${DateFormat('MMMM yyyy').format(_exportMonth)}',
                                  ),
                                ),
                                FilledButton.icon(
                                  onPressed:
                                      _exporting ? null : _exportAbsentExcel,
                                  icon: const Icon(Icons.download_rounded),
                                  label: Text(
                                    _exporting
                                        ? 'Excel બનાવે છે…'
                                        : 'ગેરહાજર યાદી Excel ડાઉનલોડ',
                                  ),
                                ),
                              ],
                            )
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final p = await showDatePicker(
                                      context: context,
                                      initialDate: _rangeStart,
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime(2100),
                                    );
                                    if (p != null && mounted) {
                                      setState(() => _rangeStart = p);
                                    }
                                  },
                                  icon: const Icon(Icons.date_range),
                                  label: Text('થી: ${_dmy.format(_rangeStart)}'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final p = await showDatePicker(
                                      context: context,
                                      initialDate: _rangeEnd,
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime(2100),
                                    );
                                    if (p != null && mounted) {
                                      setState(() => _rangeEnd = p);
                                    }
                                  },
                                  icon: const Icon(Icons.date_range),
                                  label: Text('સુધી: ${_dmy.format(_rangeEnd)}'),
                                ),
                                FilledButton.icon(
                                  onPressed:
                                      _exporting ? null : _exportAbsentExcel,
                                  icon: const Icon(Icons.download_rounded),
                                  label: Text(
                                    _exporting
                                        ? 'Excel બનાવે છે…'
                                        : 'ગેરહાજર યાદી Excel ડાઉનલોડ',
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      selected: _filterMode == 'all',
                      label: Text('બધા (${_alerts.length})'),
                      onSelected: (_) => setState(() => _filterMode = 'all'),
                    ),
                    ChoiceChip(
                      selected: _filterMode == 'consecutive',
                      label: Text(
                        '૩+ સતત ગેરહાજર (${_alerts.where((e) => ((e['consecutive_absent'] as int?) ?? 0) >= 3).length})',
                      ),
                      onSelected: (_) =>
                          setState(() => _filterMode = 'consecutive'),
                    ),
                    ChoiceChip(
                      selected: _filterMode == 'below_65',
                      label: Text(
                        '૬૫% થી ઓછી હાજરી (${_alerts.where((e) => ((e['month_percentage'] as num?)?.toDouble() ?? 100) < 65).length})',
                      ),
                      onSelected: (_) =>
                          setState(() => _filterMode = 'below_65'),
                    ),
                    ChoiceChip(
                      selected: _filterMode == 'low_pct',
                      label: Text(
                        '૭૫% થી ઓછી હાજરી (${_alerts.where((e) => ((e['month_percentage'] as num?)?.toDouble() ?? 100) < 75).length})',
                      ),
                      onSelected: (_) =>
                          setState(() => _filterMode = 'low_pct'),
                    ),
                  ],
                ),
                if (_monthPrefix.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'માસિક ટકાવારી મહિનો: $_monthPrefix',
                      style: Theme.of(context).textTheme.bodySmall,
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
                if (visible.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          'હાલમાં કોઈ સતત ગેરહાજર (3+ દિવસ) કે 75% થી ઓછી હાજરી ધરાવતો વિદ્યાર્થી નથી.',
                        ),
                      ),
                    ),
                  )
                else
                  for (final item in visible)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              ((item['consecutive_absent'] as int?) ?? 0) >= 7
                                  ? Colors.red.shade100
                                  : Colors.orange.shade100,
                          child: Text(
                            '${item['consecutive_absent'] ?? 0}d',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color:
                                  ((item['consecutive_absent'] as int?) ?? 0) >=
                                          7
                                      ? Colors.red.shade900
                                      : Colors.orange.shade900,
                            ),
                          ),
                        ),
                        title: Text(
                          '${_text(item['student_name'])}  •  ${_text(item['class_label'])}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          'રોલ નં: ${_text(item['roll_number']).isEmpty ? '—' : _text(item['roll_number'])}'
                          ' • સતત ગેરહાજર: ${item['consecutive_absent']} દિવસ'
                          ' • માસિક હાજરી: ${item['month_percentage']}% (${item['month_present_days']}/${item['month_working_days']})',
                        ),
                        trailing: FilledButton.tonalIcon(
                          onPressed: () => _sendParentWhatsApp(item),
                          icon: const Icon(Icons.chat_rounded, size: 16),
                          label: const Text('વાલી WhatsApp'),
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import '../services/supabase_leave_pdf_service.dart';
import '../services/school_name_language_service.dart';
import '../widgets/school_name_language_selector.dart';

/// School-scoped leave PDF/report picker. Supabase RLS remains the authority:
/// Admin sees this school's rows; a teacher can only see their own rows.
class SupabaseLeaveReportPdfScreen extends StatefulWidget {
  const SupabaseLeaveReportPdfScreen({super.key});

  @override
  State<SupabaseLeaveReportPdfScreen> createState() =>
      _SupabaseLeaveReportPdfScreenState();
}

class _SupabaseLeaveReportPdfScreenState
    extends State<SupabaseLeaveReportPdfScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  bool _loading = true;
  bool _printing = false;
  String? _error;
  String _schoolName = 'શાળા';
  String _schoolRef = '';
  Map<String, dynamic> _schoolContext = <String, dynamic>{};
  Map<String, dynamic> _schoolConfig = <String, dynamic>{};
  String _statusFilter = 'all';
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _teacherRoster = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _classRoster = <Map<String, dynamic>>[];
  final Set<String> _selected = <String>{};

  String _s(dynamic value, [String fallback = '']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty || text.toLowerCase() == 'null' ? fallback : text;
  }

  String _statusLabel(String status) => switch (status.toLowerCase()) {
        'approved' => 'મંજૂર',
        'rejected' => 'નામંજૂર',
        'cancelled' => 'રદ',
        _ => 'મંજૂરી બાકી',
      };

  List<Map<String, dynamic>> _rowsFromRpc(dynamic value) {
    dynamic current = value;
    if (current is String) {
      try {
        current = jsonDecode(current);
      } catch (_) {
        return <Map<String, dynamic>>[];
      }
    }
    if (current is Map) {
      final map = current.map((key, value) => MapEntry(key.toString(), value));
      if (map.containsKey('id') &&
          (map.containsKey('teacher_name') ||
              map.containsKey('teacherName') ||
              map.containsKey('name'))) {
        return <Map<String, dynamic>>[Map<String, dynamic>.from(map)];
      }
      for (final key in const [
        'teachers',
        'classes',
        'data',
        'result',
        'payload',
        'rows',
        'records',
        'psm_leave_teacher_roster_v2'
      ]) {
        final candidate = map[key];
        if (candidate is List || candidate is String) {
          final parsed = _rowsFromRpc(candidate);
          if (parsed.isNotEmpty || candidate is List && candidate.isEmpty)
            return parsed;
        }
      }
      for (final candidate in map.values) {
        if (candidate is List || candidate is String) {
          final parsed = _rowsFromRpc(candidate);
          if (parsed.isNotEmpty) return parsed;
        }
      }
    }
    if (current is! List) return <Map<String, dynamic>>[];
    return current
        .whereType<Map>()
        .map((row) => row
            .map((key, value) =>
                MapEntry<String, dynamic>(key.toString(), value))
            .cast<String, dynamic>())
        .toList();
  }

  Map<String, dynamic> _mapValue(dynamic value) => value is Map
      ? value
          .map((key, value) => MapEntry<String, dynamic>(key.toString(), value))
          .cast<String, dynamic>()
      : <String, dynamic>{};

  String _assignedClass(String teacherId) {
    if (teacherId.isEmpty) return '';
    final labels = _classRoster
        .where((row) =>
            _s(row['class_teacher_id']) == teacherId &&
            _s(row['is_active'], 'true').toLowerCase() != 'false')
        .map((row) => _s(row['label'], _s(row['class_key'], 'ધોરણ')))
        .where((value) => value.isNotEmpty)
        .toList();
    if (labels.isNotEmpty) return labels.join(' / ');

    dynamic allowed;
    for (final teacher in _teacherRoster) {
      if (_s(teacher['id']) == teacherId) {
        allowed = teacher['allowed_classes'];
        break;
      }
    }
    if (allowed is List) {
      for (final item in allowed) {
        final value = _s(item);
        if (value.isEmpty) continue;
        Map<String, dynamic>? matched;
        for (final row in _classRoster) {
          if (_s(row['is_active'], 'true').toLowerCase() == 'false') continue;
          final tokens = <String>{
            _s(row['label']).toLowerCase(),
            _s(row['class_key']).toLowerCase(),
            _s(row['sheet_name']).toLowerCase(),
          };
          if (tokens.contains(value.toLowerCase())) {
            matched = row;
            break;
          }
        }
        final label = matched == null
            ? value
            : _s(matched['label'], _s(matched['class_key'], value));
        if (!labels.contains(label)) labels.add(label);
      }
    }
    return labels.join(' / ');
  }

  String _teacherNameForId(String teacherId) {
    for (final teacher in _teacherRoster) {
      if (_s(teacher['id']) == teacherId)
        return _s(teacher['teacher_name'] ?? teacher['teacherName']);
    }
    return '';
  }

  List<Map<String, dynamic>> _resolveClassSnapshots(
      List<Map<String, dynamic>> rows) {
    return rows.map((row) {
      final updated = Map<String, dynamic>.from(row);
      final data = _mapValue(row['leave_data']);
      final teacherId = _s(row['teacher_id']);
      final currentTeacherName = _teacherNameForId(teacherId);
      if (currentTeacherName.isNotEmpty)
        data['teacher_name'] = currentTeacherName;
      final teacherClass = _assignedClass(teacherId);
      if (teacherClass.isNotEmpty || _classRoster.isNotEmpty)
        data['teacher_class'] = teacherClass.isNotEmpty ? teacherClass : '—';
      final chargeId = _s(data['charge_teacher_id']);
      if (chargeId.isNotEmpty) {
        final chargeName = _teacherNameForId(chargeId);
        if (chargeName.isNotEmpty) data['charge_teacher_name'] = chargeName;
        final chargeClass = _assignedClass(chargeId);
        if (chargeClass.isNotEmpty || _classRoster.isNotEmpty)
          data['charge_teacher_class'] =
              chargeClass.isNotEmpty ? chargeClass : '—';
      }
      updated['leave_data'] = data;
      return updated;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      final school = _s(await _client.rpc('current_school_ref'));
      if (school.isEmpty)
        throw StateError('સક્રિય શાળા મળતી નથી. ફરી login કરો.');
      final result = await _client
          .from('teacher_leaves')
          .select(
              'id,school_ref,teacher_id,start_date,end_date,leave_type,reason,status,decision_note,leave_data,record_source,recorded_by,created_at,updated_at')
          .eq('school_ref', school)
          .order('created_at', ascending: false);

      Map<String, dynamic> schoolContext = <String, dynamic>{};
      Map<String, dynamic> schoolConfig = <String, dynamic>{};
      try {
        final contextValue = await _client.rpc('psm_library_school_context');
        if (contextValue is Map)
          schoolContext = Map<String, dynamic>.from(contextValue);
      } catch (_) {}
      try {
        final settings = await _client
            .from('school_settings')
            .select('config')
            .eq('school_ref', school)
            .maybeSingle();
        final cfgValue = settings?['config'];
        if (cfgValue is Map) schoolConfig = Map<String, dynamic>.from(cfgValue);
      } catch (_) {}
      final schoolNameLanguage =
          await SchoolNameLanguageService.loadLanguage(schoolRef: school);
      final schoolName = SchoolNameLanguageService.resolveSchoolName(
        language: schoolNameLanguage,
        profile: const <String, dynamic>{},
        schoolContext: schoolContext,
        schoolConfig: schoolConfig,
        fallbackEnglish: _s(schoolContext['school_name_en'] ??
            schoolContext['school_name'] ??
            schoolContext['schoolName']),
      );

      List<Map<String, dynamic>> teachers = <Map<String, dynamic>>[];
      List<Map<String, dynamic>> classes = <Map<String, dynamic>>[];
      try {
        teachers =
            _rowsFromRpc(await _client.rpc('psm_leave_teacher_roster_v2'));
      } catch (_) {}
      if (teachers.isEmpty) {
        try {
          teachers =
              _rowsFromRpc(await _client.rpc('current_school_teacher_roster'));
        } catch (_) {}
      }
      try {
        classes =
            _rowsFromRpc(await _client.rpc('current_school_class_roster'));
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _schoolRef = school;
        _schoolContext = schoolContext;
        _schoolConfig = schoolConfig;
        _schoolName = schoolName;
        _teacherRoster = teachers;
        _classRoster = classes;
        _rows = result.map((item) => Map<String, dynamic>.from(item)).toList();
        _selected.removeWhere((id) => !_rows.any((row) => _s(row['id']) == id));
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'
            .replaceFirst('Exception: ', '')
            .replaceFirst('Bad state: ', '');
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _visibleRows => _rows.where((row) {
        if (_statusFilter == 'all') return true;
        return _s(row['status'], 'pending').toLowerCase() == _statusFilter;
      }).toList();

  List<Map<String, dynamic>> get _selectedRows =>
      _visibleRows.where((row) => _selected.contains(_s(row['id']))).toList();

  void _setSchoolNameLanguage(String language) {
    setState(() {
      _schoolName = SchoolNameLanguageService.resolveSchoolName(
        language: language,
        schoolContext: _schoolContext,
        schoolConfig: _schoolConfig,
        fallbackEnglish: _s(_schoolContext['school_name_en'] ??
            _schoolContext['school_name'] ??
            _schoolContext['schoolName']),
      );
    });
  }

  Future<void> _print({required int perPage}) async {
    final rows = _selectedRows;
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('PDF માટે ઓછામાં ઓછી એક અરજી પસંદ કરો.')));
      return;
    }
    setState(() => _printing = true);
    try {
      // Freeze the first utilized-leave calculation per application in Supabase.
      // Reprints receive the same snapshot even if later leave requests are added.
      final reportRows = <Map<String, dynamic>>[];
      for (final sourceRow in _resolveClassSnapshots(rows)) {
        final leaveId = _s(sourceRow['id']);
        if (leaveId.isEmpty)
          throw StateError('રજા અરજીનો ID મળ્યો નથી. Refresh કરો.');
        final rawSnapshotResponse = await _client.rpc(
          'psm_get_or_create_teacher_leave_report_snapshot',
          params: <String, dynamic>{'p_leave_id': leaveId},
        );
        final snapshotResponse = _mapValue(rawSnapshotResponse);
        final snapshot = _mapValue(snapshotResponse['snapshot']);
        if (snapshotResponse['result'] != 'success' || snapshot.isEmpty) {
          throw StateError(_s(snapshotResponse['message'],
              'ભોગવેલી રજાનો snapshot સેવ કરી શકાયો નથી.'));
        }
        reportRows.add(<String, dynamic>{
          ...sourceRow,
          'utilized_leave_snapshot': snapshot,
          'utilized_snapshot_created_at':
              _s(snapshotResponse['snapshot_created_at']),
        });
      }

      await SupabaseLeavePdfService.printRequests(
        records: reportRows,
        history: _resolveClassSnapshots(_rows),
        schoolName: _schoolName,
        perPage: perPage,
        fileName: perPage == 2
            ? 'Leave_Report_Two_Per_Page.pdf'
            : 'Leave_Report_Half_Page.pdf',
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('PDF: $error')));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return Scaffold(appBar: AppBar(title: const Text('રજા રિપોર્ટ')), body: const Center(child: CircularProgressIndicator()));
    final visible = _visibleRows;
    return Scaffold(
      appBar: AppBar(
        title: const Text('રજા રિપોર્ટ PDF'),
        actions: [
          IconButton(
              onPressed: _load,
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh))
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('$_schoolName | રજા અરજીઓ',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          SchoolNameLanguageSelector(
            schoolRef: _schoolRef.isEmpty ? null : _schoolRef,
            label: 'School name on leave reports / રજા રિપોર્ટમાં શાળાનું નામ',
            onChanged: _setSchoolNameLanguage,
          ),
          const SizedBox(height: 12),
          const Text(
              'A4 portrait. Each report uses half a page; choose one report per sheet or two reports on the same sheet.'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            value: _statusFilter,
            decoration: const InputDecoration(
                labelText: 'સ્થિતિ પ્રમાણે પસંદ કરો',
                border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('બધી અરજીઓ')),
              DropdownMenuItem(value: 'pending', child: Text('મંજૂરી બાકી')),
              DropdownMenuItem(value: 'approved', child: Text('મંજૂર')),
              DropdownMenuItem(value: 'rejected', child: Text('નામંજૂર')),
              DropdownMenuItem(value: 'cancelled', child: Text('રદ કરેલી')),
            ],
            onChanged: (value) =>
                setState(() => _statusFilter = value ?? 'all'),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(
                onPressed: visible.isEmpty
                    ? null
                    : () => setState(() =>
                        _selected.addAll(visible.map((r) => _s(r['id'])))),
                child: const Text('દેખાતી બધી પસંદ કરો')),
            OutlinedButton(
                onPressed:
                    _selected.isEmpty ? null : () => setState(_selected.clear),
                child: const Text('પસંદગી દૂર કરો')),
          ]),
          const SizedBox(height: 8),
          if (visible.isEmpty)
            const Card(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('આ સ્થિતિમાં કોઈ અરજી નથી.'))),
          for (final row in visible)
            Card(
              child: CheckboxListTile(
                value: _selected.contains(_s(row['id'])),
                onChanged: (value) => setState(() {
                  final id = _s(row['id']);
                  if (value == true) {
                    _selected.add(id);
                  } else {
                    _selected.remove(id);
                  }
                }),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                    '${_s(row['leave_type'], 'રજા')} • ${_statusLabel(_s(row['status'], 'pending'))}'),
                subtitle: Text(
                  '${_s(row['start_date'])} થી ${_s(row['end_date'])} • ${SupabaseLeavePdfService.totalDays(row)} દિવસ\n'
                  '${_s((row['leave_data'] is Map) ? (row['leave_data'] as Map)['teacher_name'] : null, 'શિક્ષક')} • ${_s(row['reason'])}',
                ),
                isThreeLine: true,
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _printing || _selectedRows.isEmpty
                ? null
                : () => _print(perPage: 1),
            icon: _printing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_outlined),
            label: Text(
                'પસંદ કરેલી PDF — એક રિપોર્ટ અડધા પેજમાં (${_selectedRows.length})'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _printing || _selectedRows.isEmpty
                ? null
                : () => _print(perPage: 2),
            icon: const Icon(Icons.view_agenda_outlined),
            label: const Text('બે રિપોર્ટ એક A4 પેજમાં'),
          ),
        ],
      ),
    );
  }
}

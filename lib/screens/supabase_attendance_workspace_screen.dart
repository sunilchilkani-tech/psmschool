import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';
import 'package:flutter/material.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import '../models/models.dart';
import '../services/supabase_attendance_report_service.dart';
import '../services/school_class_order.dart';
import 'datewise_columns_settings_dialog.dart';
import 'supabase_attendance_entry_screen.dart';
import 'supabase_parent_attendance_message_screen.dart';
import 'supabase_library_screen.dart';
import 'supabase_reports_hub_screen.dart';

import '../services/psm_file_export_helper.dart';
import '../widgets/global_student_search_card.dart';
/// Supabase-native attendance workspace. It presents attendance, report,
/// student attendance ranking, and the future Library area without relying on
/// the legacy Apps Script AppState login.
class SupabaseAttendanceWorkspaceScreen extends StatefulWidget {
  const SupabaseAttendanceWorkspaceScreen({
    super.key,
    required this.profile,
    this.readOnly = false,
    this.initialIndex = 0,
  });

  final Map<String, dynamic> profile;
  final bool readOnly;
  final int initialIndex;

  @override
  State<SupabaseAttendanceWorkspaceScreen> createState() =>
      _SupabaseAttendanceWorkspaceScreenState();
}

class _SupabaseAttendanceWorkspaceScreenState
    extends State<SupabaseAttendanceWorkspaceScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      initialIndex: widget.initialIndex.clamp(0, 5).toInt(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.readOnly ? 'Attendance Reports / અહેવાલ' : 'Attendance / હાજરી'),
          actions: [
            IconButton(
              tooltip: 'Global Student Search / વિદ્યાર્થી ગ્લોબલ સર્ચ',
              onPressed: () => showGlobalStudentSearchDialog(
                context,
                readOnly: widget.readOnly,
              ),
              icon: const Icon(Icons.person_search_rounded),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(icon: Icon(Icons.fact_check_outlined), text: '1. હાજરી નોંધણી (Attendance)'),
              Tab(icon: Icon(Icons.history), text: '2. વર્ગ ઇતિહાસ (History)'),
              Tab(icon: Icon(Icons.summarize_outlined), text: '3. અહેવાલ અને હાજરીપત્રક (Reports)'),
              Tab(icon: Icon(Icons.emoji_events_outlined), text: '4. સૌથી વધુ હાજર (Most Present)'),
              Tab(icon: Icon(Icons.local_library_outlined), text: '5. પુસ્તકાલય (Library)'),
              Tab(icon: Icon(Icons.mark_email_read_outlined), text: '6. વાલી સંદેશ (Parent Msg)'),
            ],
          ),
        ),
        body: TabBarView(
            physics: const NeverScrollableScrollPhysics(),
          children: <Widget>[
            SupabaseAttendanceEntryScreen(
              profile: widget.profile,
              readOnly: widget.readOnly,
              showAppBar: false,
            ),
            const _SupabaseHistoryTab(),
            SupabaseReportsHubScreen(profile: widget.profile, readOnly: widget.readOnly),
            const _SupabaseMostPresentTab(),
            SupabaseLibraryScreen(profile: widget.profile, readOnly: widget.readOnly, embedded: true),
            SupabaseParentAttendanceMessageScreen(profile: widget.profile, readOnly: widget.readOnly),
          ],
        ),
      ),
    );
  }
}

class _SupabaseMostPresentTab extends StatefulWidget {
  const _SupabaseMostPresentTab();

  @override
  State<_SupabaseMostPresentTab> createState() => _SupabaseMostPresentTabState();
}

class _SupabaseMostPresentTabState
    extends _SupabaseReportBaseState<_SupabaseMostPresentTab> {
  static const List<String> _periods = <String>['Week', 'Month', 'Quarter', 'Half Year', 'Year', 'Custom Range'];
  String _selectedPeriod = 'Week';
  DateTime? _customFromDate;
  DateTime? _customToDate;
  bool _loadingRanking = false;
  String? _rankingError;
  String _rangeLabel = '';
  List<Map<String, dynamic>> _ranking = <Map<String, dynamic>>[];
  bool _hasStudentLevelDays = true;

  @override
  void initState() {
    super.initState();
    loadClasses().then((_) {
      if (mounted && classes.isNotEmpty) _loadRanking();
    });
  }

  DateTime _indiaNow() => DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

  String _dateString(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  (DateTime, DateTime) _dateRange(String period) {
    final now = _indiaNow();
    final today = DateTime(now.year, now.month, now.day);
    late DateTime start;
    if (period == 'Custom Range') {
      start = _customFromDate ?? today.subtract(Duration(days: today.weekday - DateTime.monday));
      final end = _customToDate ?? today;
      return (start, end.isAfter(today) ? today : end);
    } else if (period == 'Month') {
      start = DateTime(today.year, today.month, 1);
    } else if (period == 'Quarter') {
      final firstQuarterMonth = ((today.month - 1) ~/ 3) * 3 + 1;
      start = DateTime(today.year, firstQuarterMonth, 1);
    } else if (period == 'Half Year') {
      start = DateTime(today.year, today.month <= 6 ? 1 : 7, 1);
    } else if (period == 'Year') {
      start = DateTime(today.year, 1, 1);
    } else {
      start = today.subtract(Duration(days: today.weekday - DateTime.monday));
    }
    return (start, today);
  }

  String _displayDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';

  String get _customFromLabel => _displayDate(_dateRange('Custom Range').$1);
  String get _customToLabel => _displayDate(_dateRange('Custom Range').$2);

  Future<void> _pickCustomFromDate() async {
    final now = _indiaNow();
    final today = DateTime(now.year, now.month, now.day);
    final currentRange = _dateRange('Custom Range');
    final picked = await showDatePicker(
      context: context,
      initialDate: _customFromDate ?? currentRange.$1,
      firstDate: DateTime(2018),
      lastDate: _customToDate ?? today,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedPeriod = 'Custom Range';
      _customFromDate = DateTime(picked.year, picked.month, picked.day);
      _customToDate ??= today;
      if (_customToDate!.isBefore(_customFromDate!)) _customToDate = _customFromDate;
    });
    await _loadRanking();
  }

  Future<void> _pickCustomToDate() async {
    final now = _indiaNow();
    final today = DateTime(now.year, now.month, now.day);
    final currentRange = _dateRange('Custom Range');
    final picked = await showDatePicker(
      context: context,
      initialDate: _customToDate ?? today,
      firstDate: _customFromDate ?? currentRange.$1,
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedPeriod = 'Custom Range';
      _customToDate = DateTime(picked.year, picked.month, picked.day);
      _customFromDate ??= currentRange.$1;
      if (_customFromDate!.isAfter(_customToDate!)) _customFromDate = _customToDate;
    });
    await _loadRanking();
  }

  Future<void> _loadRanking() async {
    setState(() { _loadingRanking = true; _rankingError = null; });
    try {
      if (client.auth.currentUser == null) throw StateError('Please sign in again.');
      final schoolRefValue = await client.rpc('current_school_ref');
      final schoolRef = '${schoolRefValue ?? ''}'.trim();
      if (schoolRef.isEmpty) throw StateError('This login is not linked to an active school.');
      final range = _dateRange(_selectedPeriod);
      final startDate = _dateString(range.$1);
      final endDate = _dateString(range.$2);
      _rangeLabel = '$startDate to $endDate';

      final dayRows = <Map<String, dynamic>>[];
      const pageSize = 500;
      for (var offset = 0; ; offset += pageSize) {
        final page = await client
            .from('attendance_days')
            .select('id,class_id,attendance_date,attendance_mode,student_details_saved')
            .eq('school_ref', schoolRef)
            .gte('attendance_date', startDate)
            .lte('attendance_date', endDate)
            .order('attendance_date')
            .order('id')
            .range(offset, offset + pageSize - 1);
        final rows = page.map((row) => Map<String, dynamic>.from(row)).toList();
        dayRows.addAll(rows);
        if (rows.length < pageSize) break;
      }

      // Direct Entry days have no reliable student-level mapping. Do not assign
      // those class totals to individual students in the ranking.
      final studentDays = dayRows.where((row) =>
          '${row['attendance_mode'] ?? 'student'}' != 'direct' && row['student_details_saved'] != false).toList();
      final dayIds = studentDays.map((row) => '${row['id']}').toList();
      final presentCountByStudent = <String, int>{};
      if (dayIds.isNotEmpty) {
        const idChunkSize = 200;
        for (var offset = 0; offset < dayIds.length; offset += idChunkSize) {
          final chunk = dayIds.skip(offset).take(idChunkSize).toList();
          final marks = await client
              .from('student_attendance')
              .select('student_id,attendance_day_id')
              .eq('school_ref', schoolRef)
              .eq('present', true)
              .inFilter('attendance_day_id', chunk);
          for (final mark in marks) {
            final id = '${mark['student_id']}';
            presentCountByStudent[id] = (presentCountByStudent[id] ?? 0) + 1;
          }
        }
      }

      final students = <Map<String, dynamic>>[];
      for (var offset = 0; ; offset += pageSize) {
        final page = await client
            .from('students')
            .select('id,roll_number,name,class_id')
            .eq('school_ref', schoolRef)
            .eq('is_active', true)
            .order('id')
            .range(offset, offset + pageSize - 1);
        final rows = page.map((row) => Map<String, dynamic>.from(row)).toList();
        students.addAll(rows);
        if (rows.length < pageSize) break;
      }
      final classNames = <String, String>{
        for (final row in classes) '${row['id']}': classLabel(row),
      };
      final ranking = <Map<String, dynamic>>[];
      for (final student in students) {
        final count = presentCountByStudent['${student['id']}'] ?? 0;
        if (count <= 0) continue;
        ranking.add(<String, dynamic>{
          ...student,
          'days_present': count,
          'class_label': classNames['${student['class_id']}'] ?? 'Class',
        });
      }
      int rollNumber(Map<String, dynamic> row) => int.tryParse('${row['roll_number'] ?? ''}') ?? 1 << 30;
      ranking.sort((a, b) {
        final score = (b['days_present'] as int).compareTo(a['days_present'] as int);
        if (score != 0) return score;
        final roll = rollNumber(a).compareTo(rollNumber(b));
        if (roll != 0) return roll;
        return '${a['name'] ?? ''}'.compareTo('${b['name'] ?? ''}');
      });
      if (!mounted) return;
      setState(() {
        _ranking = ranking.take(100).toList();
        _hasStudentLevelDays = studentDays.isNotEmpty;
        _loadingRanking = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { _rankingError = '$error'.replaceFirst('Exception: ', ''); _loadingRanking = false; });
    }
  }

  @override
  Widget build(BuildContext context) => buildBaseState(child: ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('Most Present Students / સૌથી વધુ હાજર વિદ્યાર્થીઓ', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 6),
      const Text('Ranks students using individual Student Selection attendance only. Direct Entry contains class totals, so it cannot be attributed to individual students.'),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: DropdownButtonFormField<String>(
          initialValue: _selectedPeriod,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Period', border: OutlineInputBorder()),
          items: _periods.map((period) => DropdownMenuItem<String>(value: period, child: Text(period))).toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _selectedPeriod = value;
              if (value == 'Custom Range') {
                final range = _dateRange('Week');
                _customFromDate ??= range.$1;
                _customToDate ??= range.$2;
              }
            });
            _loadRanking();
          },
        )),
        const SizedBox(width: 8),
        IconButton.filledTonal(onPressed: _loadingRanking ? null : _loadRanking, icon: const Icon(Icons.refresh), tooltip: 'Refresh ranking'),
      ]),
      if (_selectedPeriod == 'Custom Range') ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _loadingRanking ? null : _pickCustomFromDate,
              icon: const Icon(Icons.calendar_month),
              label: Text('From: $_customFromLabel'),
            ),
            OutlinedButton.icon(
              onPressed: _loadingRanking ? null : _pickCustomToDate,
              icon: const Icon(Icons.event),
              label: Text('To: $_customToLabel'),
            ),
          ],
        ),
      ],
      const SizedBox(height: 8),
      Text('Period: $_rangeLabel', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      if (_loadingRanking) const LinearProgressIndicator()
      else if (_rankingError != null) Text(_rankingError!, style: TextStyle(color: Theme.of(context).colorScheme.error))
      else if (_ranking.isEmpty) Text(_hasStudentLevelDays
          ? 'No student has a saved Present mark in this period.'
          : 'No student-level attendance was saved in this period. Direct Entry class totals are not used for student rankings.' )
      else ...[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const <DataColumn>[
              DataColumn(label: Text('#')),
              DataColumn(label: Text('Student')),
              DataColumn(label: Text('Roll No.')),
              DataColumn(label: Text('Class')),
              DataColumn(label: Text('Days Present')),
            ],
            rows: <DataRow>[
              for (var index = 0; index < _ranking.length; index++)
                DataRow(cells: <DataCell>[
                  DataCell(Text('${index + 1}')),
                  DataCell(Text('${_ranking[index]['name'] ?? ''}')),
                  DataCell(Text('${_ranking[index]['roll_number'] ?? ''}')),
                  DataCell(Text('${_ranking[index]['class_label'] ?? ''}')),
                  DataCell(Text('${_ranking[index]['days_present']}')),
                ]),
            ],
          ),
        ),
        if (_ranking.length == 100)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Showing the top 100 students.', style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    ],
  ));
}

abstract class _SupabaseReportBaseState<T extends StatefulWidget> extends State<T> {
  final SupabaseClient client = Supabase.instance.client;
  final SupabaseAttendanceReportService reports = SupabaseAttendanceReportService();
  List<Map<String, dynamic>> classes = <Map<String, dynamic>>[];
  bool loadingClasses = true;
  String? classLoadError;

  Future<void> loadClasses() async {
    setState(() { loadingClasses = true; classLoadError = null; });
    try {
      if (client.auth.currentUser == null) throw StateError('Please sign in again.');
      final schoolRef = await client.rpc('current_school_ref');
      if (schoolRef == null || '$schoolRef'.trim().isEmpty) {
        throw StateError('This login is not linked to an active school.');
      }
      final rows = await client
          .from('school_classes')
          .select('id,school_ref,class_key,label,sheet_name,standard,section,report_group,sort_order,is_active')
          .eq('school_ref', '$schoolRef')
          .eq('is_active', true)
          .order('sort_order')
          .order('label');
      if (!mounted) return;
      setState(() {
        classes = SchoolClassOrder.sorted(
          rows.map((row) => Map<String, dynamic>.from(row)),
        );
        loadingClasses = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { classLoadError = '$error'.replaceFirst('Exception: ', ''); loadingClasses = false; });
    }
  }

  String classLabel(Map<String, dynamic> row) => '${row['label'] ?? row['class_key'] ?? ''}';
  String classKey(Map<String, dynamic> row) => '${row['class_key'] ?? row['label'] ?? ''}';
  List<Map<String, dynamic>> classesForGroup(String group) =>
      SchoolClassOrder.sorted(classes.where((row) => SchoolClassOrder.matches(row, group)));

  Widget buildBaseState({required Widget child}) {
    if (loadingClasses) return const Center(child: CircularProgressIndicator());
    if (classLoadError != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 40),
          const SizedBox(height: 10),
          Text(classLoadError!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: loadClasses, icon: const Icon(Icons.refresh), label: const Text('Try again')),
        ]),
      ));
    }
    if (classes.isEmpty) return const Center(child: Padding(
      padding: EdgeInsets.all(20),
      child: Text('No active or assigned classes are available for this account.', textAlign: TextAlign.center),
    ));
    return child;
  }
}

class _SupabaseHistoryTab extends StatefulWidget {
  const _SupabaseHistoryTab();
  @override
  State<_SupabaseHistoryTab> createState() => _SupabaseHistoryTabState();
}

class _SupabaseHistoryTabState extends _SupabaseReportBaseState<_SupabaseHistoryTab> {
  String? selectedClass;
  bool loadingHistory = false;
  String? error;
  Map<String, AttendanceRecord> history = <String, AttendanceRecord>{};

  @override
  void initState() {
    super.initState();
    loadClasses().then((_) {
      if (mounted && classes.isNotEmpty) {
        selectedClass = classKey(classes.first);
        _loadHistory();
      }
    });
  }

  Future<void> _loadHistory() async {
    final key = selectedClass;
    if (key == null) return;
    setState(() { loadingHistory = true; error = null; });
    try {
      final value = await reports.getAttendanceHistory(key);
      if (!mounted) return;
      setState(() { history = value; loadingHistory = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { error = '$e'; loadingHistory = false; });
    }
  }

  @override
  Widget build(BuildContext context) => buildBaseState(child: ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('ઇતિહાસ — વર્ગ મુજબ', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: selectedClass,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Class', border: OutlineInputBorder()),
        items: classes.map((row) => DropdownMenuItem<String>(value: classKey(row), child: Text('${classLabel(row)} • ${SchoolClassOrder.labelFor(SchoolClassOrder.groupOf(row))}'))).toList(),
        onChanged: (value) { setState(() => selectedClass = value); _loadHistory(); },
      ),
      const SizedBox(height: 12),
      if (loadingHistory) const LinearProgressIndicator()
      else if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
      else if (history.isEmpty) const Text('આ વર્ગ માટે હજુ કોઈ હાજરી નોંધાઈ નથી.')
      else SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(columns: const <DataColumn>[
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Registered')),
          DataColumn(label: Text('Present')),
          DataColumn(label: Text('PM POSHAN')),
          DataColumn(label: Text('Breakfast')),
        ], rows: (history.keys.toList()..sort()).map((dateKey) {
          final record = history[dateKey]!;
          return DataRow(cells: <DataCell>[
            DataCell(Text(dateKey)),
            DataCell(Text('${record.registered?.total ?? 0}')),
            DataCell(Text('${record.present.total}')),
            DataCell(Text('${record.mdm.total}')),
            DataCell(Text('${record.breakfastTotal}')),
          ]);
        }).toList()),
      ),
    ],
  ));
}


class _SupabaseDailySummaryTab extends StatefulWidget {
  const _SupabaseDailySummaryTab();
  @override
  State<_SupabaseDailySummaryTab> createState() => _SupabaseDailySummaryTabState();
}

class _SupabaseDailySummaryTabState extends _SupabaseReportBaseState<_SupabaseDailySummaryTab> {
  DateTime date = DateTime.now();
  String selectedGroup = SchoolClassOrder.all;
  bool loadingReport = false;
  String? error;
  List<Map<String, dynamic>> resultRows = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    loadClasses().then((_) { if (mounted && classes.isNotEmpty) _loadReport(); });
  }

  String get _date => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2018), lastDate: DateTime(2100));
    if (picked == null || !mounted) return;
    setState(() => date = picked);
    await _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() { loadingReport = true; error = null; });
    try {
      final selectedClasses = classesForGroup(selectedGroup);
      final results = await Future.wait(selectedClasses.map((row) async {
        final key = classKey(row);
        final data = await reports.getRowData(key, _date);
        final record = data.attendance;
        return <String, dynamic>{
          'class': classLabel(row),
          'registered': data.registered.total,
          'present': record?.present.total ?? 0,
          'mdm': record?.mdm.total ?? 0,
          'breakfast': record?.breakfastTotal ?? 0,
        };
      }));
      final totalRow = <String, dynamic>{
        'class': 'કુલ (${SchoolClassOrder.labelFor(selectedGroup)})',
        'registered': results.fold<int>(0, (sum, row) => sum + (row['registered'] as int)),
        'present': results.fold<int>(0, (sum, row) => sum + (row['present'] as int)),
        'mdm': results.fold<int>(0, (sum, row) => sum + (row['mdm'] as int)),
        'breakfast': results.fold<int>(0, (sum, row) => sum + (row['breakfast'] as int)),
        '_total': true,
      };
      if (!mounted) return;
      setState(() { resultRows = <Map<String, dynamic>>[...results, if (results.isNotEmpty) totalRow]; loadingReport = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { error = '$e'; loadingReport = false; });
    }
  }

  @override
  Widget build(BuildContext context) => buildBaseState(child: ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('દૈનિક રિપોર્ટ • ${SchoolClassOrder.labelFor(selectedGroup)}', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_month), label: Text(_date)),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: selectedGroup,
        decoration: const InputDecoration(labelText: 'Report group / વર્ગ જૂથ', border: OutlineInputBorder()),
        items: SchoolClassOrder.reportGroups.map((group) => DropdownMenuItem<String>(
          value: group.$1,
          child: Text(group.$2),
        )).toList(),
        onChanged: (value) {
          if (value == null) return;
          setState(() => selectedGroup = value);
          _loadReport();
        },
      ),
      const SizedBox(height: 12),
      if (loadingReport) const LinearProgressIndicator()
      else if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
      else if (resultRows.isEmpty) Text('આ જૂથ માટે કોઈ વર્ગ બનાવેલ નથી. Admin → Classes માં વર્ગ જૂથ પસંદ કરો.')
      else SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(columns: const <DataColumn>[
          DataColumn(label: Text('Class')),
          DataColumn(label: Text('Registered')),
          DataColumn(label: Text('Present')),
          DataColumn(label: Text('PM POSHAN')),
          DataColumn(label: Text('Breakfast')),
        ], rows: resultRows.map((row) => DataRow(
          color: row['_total'] == true ? WidgetStatePropertyAll(Theme.of(context).colorScheme.secondaryContainer) : null,
          cells: <DataCell>[
            DataCell(Text('${row['class']}', style: TextStyle(fontWeight: row['_total'] == true ? FontWeight.bold : FontWeight.normal))),
            DataCell(Text('${row['registered']}')),
            DataCell(Text('${row['present']}')),
            DataCell(Text('${row['mdm']}')),
            DataCell(Text('${row['breakfast']}')),
          ],
        )).toList()),
      ),
      const SizedBox(height: 8),
      Text('Date: $_date • Totals are read from Supabase; opening this report never creates an attendance record.', style: Theme.of(context).textTheme.bodySmall),
    ],
  ));
}

class _SupabaseDateWiseTab extends StatefulWidget {
  const _SupabaseDateWiseTab({required this.profile, required this.readOnly});
  final Map<String, dynamic> profile;
  final bool readOnly;
  @override
  State<_SupabaseDateWiseTab> createState() => _SupabaseDateWiseTabState();
}

class _SupabaseDateWiseTabState extends _SupabaseReportBaseState<_SupabaseDateWiseTab> {
  DateTime date = DateTime.now();
  String selectedGroup = SchoolClassOrder.all;
  bool get _isAdmin => '${widget.profile['role'] ?? ''}'.trim().toLowerCase() == 'admin';
  bool loadingReport = false;
  String? error;
  List<List<String>> values = <List<String>>[];

  @override
  void initState() {
    super.initState();
    loadClasses().then((_) { if (mounted && classes.isNotEmpty) _loadReport(); });
  }

  String get _date => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2018), lastDate: DateTime(2100));
    if (picked == null || !mounted) return;
    setState(() => date = picked);
    await _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() { loadingReport = true; error = null; });
    try {
      final result = await reports.getDateWiseReportByDate(_date, classGroup: selectedGroup);
      final raw = result['values'];
      final rows = raw is List
          ? raw.map((row) => row is List ? row.map((cell) => '$cell').toList() : <String>[]).toList()
          : <List<String>>[];
      if (!mounted) return;
      setState(() { values = rows; loadingReport = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { error = '$e'; loadingReport = false; });
    }
  }

  Future<void> _openColumnSettings() async {
    if (!_isAdmin || widget.readOnly) return;
    await showDateWiseColumnSettingsDialog(context);
    if (mounted) await _loadReport();
  }

  Future<void> _exportXlsx() async {
    final workbook = Excel.createExcel();
    workbook.rename('Sheet1', 'DATEWISE');
    final sheet = workbook['DATEWISE'];
    for (final row in values) {
      sheet.appendRow(row.map((value) => TextCellValue(value)).toList());
    }
    final bytes = workbook.encode();
    if (bytes == null || bytes.isEmpty) throw StateError('Could not create the DATE WISE workbook.');
    await PsmFileExportHelper.saveOrShare(
      bytes: Uint8List.fromList(bytes),
      filename: 'DATE_WISE_$_date.xlsx',
      title: 'DATE WISE $_date',
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  @override
  Widget build(BuildContext context) => buildBaseState(child: ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('DATE WISE — Supabase', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_month), label: Text(_date)),
        if (_isAdmin && !widget.readOnly)
          OutlinedButton.icon(onPressed: _openColumnSettings, icon: const Icon(Icons.view_column), label: const Text('DATE WISE Columns')),
        FilledButton.icon(onPressed: loadingReport || values.isEmpty ? null : _exportXlsx, icon: const Icon(Icons.download), label: const Text('Export XLSX')),
      ]),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: selectedGroup,
        decoration: const InputDecoration(labelText: 'Report group / વર્ગ જૂથ', border: OutlineInputBorder()),
        items: SchoolClassOrder.reportGroups.map((group) => DropdownMenuItem<String>(
          value: group.$1,
          child: Text(group.$2),
        )).toList(),
        onChanged: (value) {
          if (value == null) return;
          setState(() => selectedGroup = value);
          _loadReport();
        },
      ),
      const SizedBox(height: 12),
      if (loadingReport) const LinearProgressIndicator()
      else if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
      else if (values.isEmpty) const Text('No rows returned for this date.')
      else SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: <DataColumn>[
            for (final value in values.first) DataColumn(label: Text(value, style: const TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: values.skip(1).map((row) => DataRow(cells: <DataCell>[
            for (var i = 0; i < values.first.length; i++) DataCell(Text(i < row.length ? row[i] : '')),
          ])).toList(),
        ),
      ),
      const SizedBox(height: 8),
      Text('જૂથ: ${SchoolClassOrder.labelFor(selectedGroup)} • This tab reads saved Supabase attendance. DATE WISE columns are saved school-wide by the Admin.', style: Theme.of(context).textTheme.bodySmall),
    ],
  ));
}

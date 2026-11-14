import 'dart:typed_data';

import 'package:excel_community/excel_community.dart' as ec;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import '../services/psm_file_export_helper.dart';
import 'supabase_admin_center_screen.dart';
import '../services/supabase_school_access_service.dart';

/// Admin-only workflow for setting up school classes and teacher accounts.
/// The Edge Function re-checks role, school, validity and block status for every call.
class AdminWorkflowPanel extends StatefulWidget {
  const AdminWorkflowPanel({super.key, SupabaseSchoolAccessService? service})
    : _service = service;

  final SupabaseSchoolAccessService? _service;

  @override
  State<AdminWorkflowPanel> createState() => _AdminWorkflowPanelState();
}

class _AdminWorkflowPanelState extends State<AdminWorkflowPanel> {
  late final SupabaseSchoolAccessService _service;
  Map<String, dynamic>? _contextData;
  List<Map<String, dynamic>> _classes = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _teachers = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _subjects = <Map<String, dynamic>>[];
  Map<String, Map<String, List<String>>> _teacherClassSubjects =
      <String, Map<String, List<String>>>{};
  bool _busy = true;
  String? _error;

  Map<String, dynamic> get _school => _map(_contextData?['school']);
  bool get _canEdit => _contextData?['can_edit'] == true;
  bool get _isBlocked => _school['is_blocked'] == true;

  @override
  void initState() {
    super.initState();
    _service = widget._service ?? SupabaseSchoolAccessService();
    _load();
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
    return <String, dynamic>{};
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final contextData = await _service.adminGetContext();
      final classes = await _service.adminListClasses();
      final teachers = await _service.adminListTeachers();
      final client = Supabase.instance.client;
      final schoolRefRaw = await client.rpc('current_school_ref');
      final schoolRef = '${schoolRefRaw ?? ''}'.trim();
      if (schoolRef.isEmpty)
        throw StateError('School reference is missing. Sign in again.');
      try {
        await client.rpc('ensure_school_planning_core_subjects');
      } catch (_) {}
      final subjectRows = await client
          .from('school_subject_master')
          .select('id,subject_name,sort_order,is_active,updated_at')
          .eq('school_ref', schoolRef)
          .order('sort_order')
          .order('subject_name');
      final assignmentRows = await client
          .from('teacher_subject_assignments')
          .select('teacher_id,class_id,subject_name,max_periods')
          .eq('school_ref', schoolRef);
      final teacherClassSubjects = <String, Map<String, List<String>>>{};
      for (final raw in assignmentRows) {
        final tid = '${raw['teacher_id'] ?? ''}'.trim();
        final cid = '${raw['class_id'] ?? ''}'.trim();
        final sName = '${raw['subject_name'] ?? ''}'.trim();
        final maxP = int.tryParse('${raw['max_periods'] ?? ''}');
        if (tid.isEmpty || cid.isEmpty || sName.isEmpty) continue;
        final byClass = teacherClassSubjects.putIfAbsent(
          tid,
          () => <String, List<String>>{},
        );
        final list = byClass.putIfAbsent(cid, () => <String>[]);
        final displaySub = (maxP != null && maxP > 0) ? '$sName ($maxP તાસ)' : sName;
        if (!list.contains(displaySub)) list.add(displaySub);
      }
      final subjects =
          subjectRows
              .map<Map<String, dynamic>>(
                (row) => Map<String, dynamic>.from(row),
              )
              .toList()
            ..sort((a, b) {
              final aOrder =
                  int.tryParse('${a['sort_order'] ?? ''}') ?? 2147483647;
              final bOrder =
                  int.tryParse('${b['sort_order'] ?? ''}') ?? 2147483647;
              final orderCompare = aOrder.compareTo(bOrder);
              if (orderCompare != 0) return orderCompare;
              return '${a['subject_name'] ?? ''}'.toLowerCase().compareTo(
                '${b['subject_name'] ?? ''}'.toLowerCase(),
              );
            });
      if (!mounted) return;
      setState(() {
        _contextData = contextData;
        _classes = classes;
        _teachers = teachers;
        _subjects = subjects;
        _teacherClassSubjects = teacherClassSubjects;
      });
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _do(Future<void> Function() action, String success) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _load();
      if (mounted) _snack(success);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
        _snack(_error!, error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _promptSubjectName({String initialValue = ''}) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          initialValue.isEmpty
              ? 'Add school subject / વિષય ઉમેરો'
              : 'Edit school subject / વિષય બદલો',
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(
            labelText: 'Subject name / વિષયનું નામ',
            hintText: 'ગુજરાતી, ગણિત, વિજ્ઞાન…',
          ),
          onSubmitted: (_) =>
              Navigator.pop(dialogContext, controller.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    final cleaned = (result ?? '').trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  Future<void> _addSubject() async {
    if (!_canEdit || _busy) return;
    final name = await _promptSubjectName();
    if (name == null) return;
    await _do(
      () async {
        final client = Supabase.instance.client;
        final schoolRef = await client.rpc('current_school_ref');
        final currentMax = _subjects.fold<int>(-1, (v, row) {
          final order = row['sort_order'];
          final n = order is num ? order.toInt() : int.tryParse('$order') ?? -1;
          return n > v ? n : v;
        });
        await client.from('school_subject_master').insert(<String, dynamic>{
          'school_ref': '$schoolRef',
          'subject_name': name,
          'sort_order': currentMax + 1,
          'is_active': true,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      },
      'Subject added to the school master. Teachers can now select it in their class assignments.',
    );
  }

  Future<void> _editSubject(Map<String, dynamic> subject) async {
    if (!_canEdit || _busy) return;
    final name = await _promptSubjectName(
      initialValue: '${subject['subject_name'] ?? ''}',
    );
    if (name == null || name == '${subject['subject_name'] ?? ''}'.trim())
      return;
    await _do(
      () async {
        await Supabase.instance.client.rpc(
          'psm_rename_school_result_subject',
          params: <String, dynamic>{
            'p_subject_id': '${subject['id']}',
            'p_new_subject_name': name,
          },
        );
      },
      'Subject renamed for new assignments across classes. Historical marks remain attached to their original subject name.',
    );
  }

  Future<void> _setSubjectActive(
    Map<String, dynamic> subject,
    bool active,
  ) async {
    if (!_canEdit || _busy) return;
    await _do(
      () async {
        await Supabase.instance.client
            .from('school_subject_master')
            .update(<String, dynamic>{
              'is_active': active,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', '${subject['id']}');
      },
      active
          ? 'Subject reactivated.'
          : 'Subject deactivated. Existing mark history has not been deleted.',
    );
  }

  Widget _subjectsView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final heading = const Text(
              'School-wide Result Subjects / શાળાના વિષયો',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            );
            final addButton = FilledButton.icon(
              onPressed: !_canEdit || _busy ? null : _addSubject,
              icon: const Icon(Icons.add),
              label: const Text('Add subject'),
            );
            if (constraints.maxWidth < 480) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  heading,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: addButton),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: heading),
                addButton,
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        const Text(
          'Add every subject taught in the school here. When assigning a teacher, choose one or more of these subjects separately for each class. Deactivating a subject hides it from new assignments but does not delete previous marks.',
        ),
        const SizedBox(height: 12),
        if (_subjects.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No subjects found. Apply the subject-master migration, then refresh.',
              ),
            ),
          ),
        for (final subject in _subjects)
          Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text('${_subjects.indexOf(subject) + 1}'),
              ),
              title: Text(
                '${subject['subject_name'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                subject['is_active'] == true
                    ? 'Active / સક્રિય'
                    : 'Inactive / બંધ',
              ),
              trailing: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Rename subject',
                    onPressed: !_canEdit || _busy
                        ? null
                        : () => _editSubject(subject),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  Switch(
                    value: subject['is_active'] == true,
                    onChanged: !_canEdit || _busy
                        ? null
                        : (value) => _setSubjectActive(subject, value),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _putCell(ec.Sheet sheet, int row, int col, String value) {
    sheet
        .cell(ec.CellIndex.indexByColumnRow(rowIndex: row, columnIndex: col))
        .value = ec.TextCellValue(
      value,
    );
  }

  Future<void> _shareWorkbook(ec.Excel workbook, String filename) async {
    final bytes = workbook.encode(); // encode(): no extra auto-download on web
    if (bytes == null || bytes.isEmpty)
      throw StateError('Excel file could not be created.');
    await PsmFileExportHelper.saveOrShare(
      bytes: Uint8List.fromList(bytes),
      filename: filename,
      title: filename,
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  Future<void> _downloadClassTemplate() async {
    try {
      final book = ec.Excel.createExcel();
      final sheet = book['Sheet1'];
      const headers = <String>[
        'ધોરણ',
        'વર્ગ',
        'ધોરણ સાથે વર્ગ',
        'Report Group (optional)',
        'ધોરણમાં વર્ગ હોય તો વર્ગ પસંદ કરવા નહિતર એમને એમ માત્ર ધોરણ પણ ચાલશે. ',
      ];
      for (var c = 0; c < headers.length; c++) {
        _putCell(sheet, 0, c, headers[c]);
      }
      // Include the 3 sample rows matching PSM_Class_Bulk_Import_Template.xlsx
      const sampleRows = <List<String>>[
        <String>['બાલવાટિકા', '', 'બાલવાટિકા', 'બાલવાટિકા', ''],
        <String>['1', 'A', 'ધોરણ - 1 - અ', '1 થી 5', ''],
        <String>['2', '', 'ધોરણ - 2', '1 થી 5', ''],
      ];
      for (var r = 0; r < sampleRows.length; r++) {
        for (var c = 0; c < sampleRows[r].length; c++) {
          if (sampleRows[r][c].isNotEmpty) {
            _putCell(sheet, r + 1, c, sampleRows[r][c]);
          }
        }
      }
      sheet.addDataValidation(
        'B2:B1048576',
        ec.DataValidation.list(const <String>[
          'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
          'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
        ])
            .withPrompt('વર્ગ પસંદ કરો', 'ધોરણમાં વર્ગ હોય તો A થી Z પસંદ કરો, નહિતર ખાલી રાખો.')
            .withError('ખોટો વર્ગ', 'કૃપા કરીને A થી Z માંથી વર્ગ પસંદ કરો અથવા ખાલી રાખો.'),
      );
      sheet.addDataValidation(
        'D2:D1048576',
        ec.DataValidation.list(const <String>['બાલવાટિકા', '1 થી 5', '6 થી 8'])
            .withPrompt('Report Group પસંદ કરો', 'બાલવાટિકા, 1 થી 5, અથવા 6 થી 8 પસંદ કરો.')
            .withError('ખોટું જૂથ', 'ફક્ત બાલવાટિકા, 1 થી 5, અથવા 6 થી 8 પસંદ કરો.'),
      );

      final instructions = book['Instructions'];
      const guide = <List<String>>[
        <String>['PSM બલ્ક વર્ગ (Class) બનાવવાની સૂચનાઓ'],
        <String>[
          'Sheet1 માં માહિતી ભરો. પ્રથમ હેડર હરોળ (Row 1) માં કોઈ ફેરફાર કરશો નહીં અને સેલ મર્જ (Merge) કરશો નહીં.',
        ],
        <String>[
          'ધોરણ (ફરજિયાત)',
          'ઉદાહરણ: બાલવાટિકા, 1, 2, 3, 4, 5, 6, 7, 8',
        ],
        <String>[
          'વર્ગ (Optional)',
          'જો ધોરણમાં વિભાગ/વર્ગ હોય તો ડ્રોપડાઉનમાંથી A થી Z પસંદ કરો. જો ધોરણમાં વર્ગ ન હોય તો ખાલી રાખો.',
        ],
        <String>[
          'ધોરણ સાથે વર્ગ',
          'શાળામાં દેખાતું પૂરું નામ (દા.ત. બાલવાટિકા, ધોરણ - 1 - અ, ધોરણ - 2). ખાલી રાખશો તો ધોરણ અને વર્ગ પરથી આપોઆપ બની જશે.',
        ],
        <String>[
          'Report Group (optional)',
          'ડ્રોપડાઉનમાંથી બાલવાટિકા, 1 થી 5, અથવા 6 થી 8 પસંદ કરો (ખાલી રાખશો તો ધોરણ મુજબ આપોઆપ સેટ થશે).',
        ],
        <String>[
          'સુરક્ષા અને નોંધ',
          'દરેક વર્ગ માટે અલગ હરોળ રાખો. Class Key અને ક્રમ (Sort Order) સિસ્ટમ દ્વારા આપોઆપ બની જશે.',
        ],
      ];
      for (var r = 0; r < guide.length; r++) {
        for (var c = 0; c < guide[r].length; c++) {
          _putCell(instructions, r, c, guide[r][c]);
        }
      }
      await _shareWorkbook(book, 'PSM_Class_Bulk_Import_Template.xlsx');
    } catch (error) {
      _snack('Class template error: $error', error: true);
    }
  }

  Future<void> _downloadTeacherTemplate() async {
    try {
      final activeClasses = _classes
          .where((row) => row['is_active'] == true)
          .where((row) => '${row['class_key'] ?? ''}'.trim().isNotEmpty)
          .toList();
      final activeSubjects = _subjects
          .where((row) => row['is_active'] != false)
          .map((row) => '${row['subject_name'] ?? ''}'.trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList();
      for (final extra in const <String>['FLN', 'શા. શિ.']) {
        if (!activeSubjects.any((s) => s.toLowerCase() == extra.toLowerCase())) {
          activeSubjects.add(extra);
        }
      }
      if (activeClasses.isEmpty) {
        throw StateError(
          'શિક્ષકનો ટેમ્પલેટ ડાઉનલોડ કરતાં પહેલાં ઓછામાં ઓછો એક સક્રિય વર્ગ બનાવો.',
        );
      }
      if (activeSubjects.isEmpty) {
        throw StateError(
          'શિક્ષકનો ટેમ્પલેટ ડાઉનલોડ કરતાં પહેલાં Admin Setup → Subjects માં સક્રિય વિષયો ઉમેરો.',
        );
      }

      final book = ec.Excel.createExcel();
      // Keep one normalized input sheet: one row = one teacher/class assignment.
      // The app groups rows by mobile number to create one teacher account.
      book.rename('Sheet1', 'શિક્ષકવાર માહિતી');
      final sheet = book['શિક્ષકવાર માહિતી'];
      final headers = <String>[
        'શિક્ષકનું નામ (Teacher Name)',
        'મોબાઇલ નંબર — 10 અંક, +91 વગર (Mobile)',
        'પ્રારંભિક પાસવર્ડ — 4 થી 15 અક્ષર (Password)',
        'વર્ગ પસંદ કરો — ડ્રોપડાઉન (Class Name)',
        'આ વર્ગના વર્ગશિક્ષક? — હા/ના (Is Class Teacher)',
        for (int sIdx = 1; sIdx <= 17; sIdx++) 'વિષય $sIdx (Subject $sIdx)',
      ];
      for (var c = 0; c < headers.length; c++) {
        _putCell(sheet, 0, c, headers[c]);
      }

      // Separate lookup worksheet with clean Class Names in Column A and all 17 Active Subjects in Column B
      final dropdowns = book['પસંદગી_યાદી'];
      _putCell(dropdowns, 0, 0, 'સક્રિય વર્ગો (Class Name)');
      _putCell(dropdowns, 0, 1, 'શાળાના સક્રિય વિષયો (Active Subjects)');
      for (var i = 0; i < activeClasses.length; i++) {
        final classKey = '${activeClasses[i]['class_key']}'.trim();
        final classLabel = '${activeClasses[i]['label'] ?? classKey}'.trim();
        _putCell(dropdowns, i + 1, 0, classLabel.isNotEmpty ? classLabel : classKey);
      }
      for (var i = 0; i < activeSubjects.length; i++) {
        _putCell(dropdowns, i + 1, 1, activeSubjects[i]);
      }

      // Template supports up to 1,000 teacher/class assignment rows.
      sheet.addDataValidation(
        'D2:D1001',
        ec.DataValidation.listFromRange(
              'A2:A${activeClasses.length + 1}',
              sheetName: 'પસંદગી_યાદી',
            )
            .withPrompt('વર્ગ પસંદ કરો', 'ડ્રોપડાઉનમાંથી સક્રિય વર્ગનું નામ પસંદ કરો.')
            .withError(
              'ખોટો વર્ગ',
              'કૃપા કરીને યાદીમાંથી સક્રિય વર્ગ પસંદ કરો.',
            ),
      );
      sheet.addDataValidation(
        'E2:E1001',
        ec.DataValidation.list(const <String>['હા', 'ના'])
            .withPrompt(
              'વર્ગશિક્ષક',
              'આ શિક્ષક આ વર્ગના વર્ગશિક્ષક હોય તો હા પસંદ કરો; ખાલી રાખશો અથવા ના પસંદ કરશો તો ના ગણાશે.',
            )
            .withError('ખોટી પસંદગી', 'ફક્ત હા અથવા ના પસંદ કરો (અથવા ખાલી રાખો).'),
      );
      sheet.addDataValidation(
        'F2:V1001',
        ec.DataValidation.listFromRange(
              'B2:B${activeSubjects.length + 1}',
              sheetName: 'પસંદગી_યાદી',
            )
            .withPrompt(
              'વિષય પસંદ કરો',
              'દરેક કૉલમ (વિષય 1 થી 17) માં એક વિષય પસંદ કરો. બાકી કૉલમ ખાલી રાખો.',
            )
            .withError(
              'ખોટો વિષય',
              'કૃપા કરીને યાદીમાંથી સક્રિય વિષય પસંદ કરો.',
            ),
      );

      final instructions = book['કેવી રીતે ભરવું'];
      const guide = <List<String>>[
        <String>['શિક્ષકવાર માહિતી — બલ્ક શિક્ષક બનાવવાની સૂચનાઓ'],
        <String>[
          'મુખ્ય માહિતી “શિક્ષકવાર માહિતી” શીટમાં ભરો. હેડર પંક્તિના નામ ન બદલો અને કૉલમ કાઢશો નહીં.',
        ],
        <String>[
          'શિક્ષકનું નામ (Teacher Name)',
          'ફરજિયાત. એક જ શિક્ષકની બધી પંક્તિઓમાં નામ સરખું જ લખો.',
        ],
        <String>[
          'મોબાઇલ નંબર (Mobile)',
          'ભારતીય 10 અંકનો મોબાઇલ નંબર +91 વગર લખો. એક જ શિક્ષક માટે દરેક પંક્તિમાં એ જ નંબર લખવો.',
        ],
        <String>[
          'પ્રારંભિક પાસવર્ડ (Password)',
          '4 થી 15 અક્ષર. એક શિક્ષકની પહેલી પંક્તિમાં પાસવર્ડ લખો; પછીની પંક્તિઓમાં ખાલી રાખી શકો.',
        ],
        <String>[
          'વર્ગ પસંદ કરો (Class Name)',
          'ડ્રોપડાઉનમાંથી સક્રિય વર્ગનું નામ (દા.ત. બાલવાટિકા, ધોરણ - 1, ધોરણ - 3 - અ) પસંદ કરો.',
        ],
        <String>[
          'આ વર્ગના વર્ગશિક્ષક? (Is Class Teacher)',
          'વર્ગની તરત બાજુના કૉલમ E માં જો આ શિક્ષક તે વર્ગના વર્ગશિક્ષક હોય તો “હા” પસંદ કરો. જો કંઈ પસંદ ન કરો (ખાલી રાખો) અથવા “ના” પસંદ કરો તો “ના” ગણાશે.',
        ],
        <String>[
          'વિષય 1 થી 17 (Subjects 1 to 17)',
          'કૉલમ F થી V માં આ વર્ગ માટે શિક્ષક ભણાવતા વિષયો ડ્રોપડાઉનમાંથી પસંદ કરો. બાકીના વિષય કૉલમ ખાલી રાખો.',
        ],
        <String>[
          'એકથી વધુ વર્ગો',
          'દરેક શિક્ષક-વર્ગ ફાળવણી માટે એક પંક્તિ રાખો. એ જ શિક્ષક માટે નામ અને મોબાઇલ નંબર સરખા રાખો.',
        ],
        <String>[
          'એક શિક્ષક = એક એકાઉન્ટ',
          'એપ મોબાઇલ નંબરના આધારે પંક્તિઓ ભેગી કરીને એક જ શિક્ષકનું એકાઉન્ટ બનાવશે અને દરેક વર્ગની વિષય ફાળવણી સાચવશે.',
        ],
        <String>[
          'પસંદગી યાદી (Dropdowns)',
          'આ શીટમાં હાલમાં સક્રિય વર્ગોના નામ અને Admin Setup → Subjects માંથી તમામ 17 સક્રિય વિષયો છે.',
        ],
      ];
      for (var r = 0; r < guide.length; r++) {
        for (var c = 0; c < guide[r].length; c++) {
          _putCell(instructions, r, c, guide[r][c]);
        }
      }
      await _shareWorkbook(
        book,
        'PSM_Teacher_Subject_Bulk_Import_Template.xlsx',
      );
    } catch (error) {
      _snack('શિક્ષકનો ટેમ્પલેટ બનાવવામાં ભૂલ: $error', error: true);
    }
  }

  Future<void> _exportCreatedTeachersExcel() async {
    try {
      if (_teachers.isEmpty) {
        _snack('નિકાસ કરવા માટે કોઈ શિક્ષક એકાઉન્ટ નથી.', error: true);
        return;
      }
      final book = ec.Excel.createExcel();
      book.rename('Sheet1', 'શિક્ષકવાર માહિતી');
      final sheet = book['શિક્ષકવાર માહિતી'];
      final headers = <String>[
        'શિક્ષકનું નામ (Teacher Name)',
        'મોબાઇલ નંબર — 10 અંક, +91 વગર (Mobile)',
        'પ્રારંભિક પાસવર્ડ — 4 થી 15 અક્ષર (Password)',
        'વર્ગ પસંદ કરો — ડ્રોપડાઉન (Class Name)',
        'આ વર્ગના વર્ગશિક્ષક? — હા/ના (Is Class Teacher)',
        for (int sIdx = 1; sIdx <= 17; sIdx++) 'વિષય $sIdx (Subject $sIdx)',
      ];
      for (var c = 0; c < headers.length; c++) {
        _putCell(sheet, 0, c, headers[c]);
      }

      int rowIdx = 1;
      for (final teacher in _teachers) {
        final tid = '${teacher['id'] ?? ''}'.trim();
        final tName = '${teacher['teacher_name'] ?? ''}'.trim();
        var rawMob = '${teacher['mobile'] ?? teacher['registered_mobile'] ?? ''}'
            .replaceAll(RegExp(r'\D'), '');
        if (rawMob.length > 10) {
          rawMob = rawMob.substring(rawMob.length - 10);
        }
        final byClass = _teacherClassSubjects[tid] ?? const <String, List<String>>{};
        final allowedRaw = teacher['allowed_classes'];
        final allowedSet = allowedRaw is List
            ? allowedRaw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toSet()
            : <String>{};

        final matchedClasses = <Map<String, dynamic>>[];
        for (final cls in _classes) {
          final cid = '${cls['id'] ?? ''}'.trim();
          final cKey = '${cls['class_key'] ?? ''}'.trim();
          final cLabel = '${cls['label'] ?? cKey}'.trim();
          final isCt = '${cls['class_teacher_id'] ?? ''}'.trim() == tid;
          final hasSubs = (byClass[cid] ?? const <String>[]).isNotEmpty;
          if (isCt ||
              hasSubs ||
              allowedSet.contains(cid) ||
              allowedSet.contains(cKey) ||
              allowedSet.contains(cLabel)) {
            matchedClasses.add(cls);
          }
        }

        if (matchedClasses.isEmpty) {
          _putCell(sheet, rowIdx, 0, tName);
          _putCell(sheet, rowIdx, 1, rawMob);
          _putCell(sheet, rowIdx, 2, '');
          _putCell(sheet, rowIdx, 3, '');
          _putCell(sheet, rowIdx, 4, 'ના');
          rowIdx++;
        } else {
          for (final cls in matchedClasses) {
            final cid = '${cls['id'] ?? ''}'.trim();
            final cKey = '${cls['class_key'] ?? ''}'.trim();
            final cLabel = '${cls['label'] ?? cKey}'.trim();
            final isCt = '${cls['class_teacher_id'] ?? ''}'.trim() == tid;
            final subs = byClass[cid] ?? const <String>[];
            _putCell(sheet, rowIdx, 0, tName);
            _putCell(sheet, rowIdx, 1, rawMob);
            _putCell(sheet, rowIdx, 2, '');
            _putCell(sheet, rowIdx, 3, cLabel.isNotEmpty ? cLabel : cKey);
            _putCell(sheet, rowIdx, 4, isCt ? 'હા' : 'ના');
            for (var s = 0; s < subs.length && s < 17; s++) {
              _putCell(sheet, rowIdx, 5 + s, subs[s]);
            }
            rowIdx++;
          }
        }
      }

      await _shareWorkbook(
        book,
        'PSM_Created_Teachers_Export.xlsx',
      );
    } catch (error) {
      _snack('શિક્ષકોની માહિતી Excel માં નિકાસ કરવામાં ભૂલ: $error', error: true);
    }
  }

  Future<List<List<String>>> _pickRows() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return <List<String>>[];
    final bytes = result.files.single.bytes;
    if (bytes == null || bytes.isEmpty)
      throw StateError(
        'Could not read the selected Excel file. Choose an .xlsx file.',
      );
    final workbook = ec.Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty)
      throw StateError('The Excel workbook has no worksheet.');
    return workbook.tables.values.first.rows
        .map((row) => row.map((cell) => _cellString(cell?.value)).toList())
        .toList();
  }

  String _extractTextSpan(dynamic span) {
    if (span == null) return '';
    if (span is String) return span;
    final buffer = StringBuffer();
    try {
      final t = (span as dynamic).text;
      if (t is String) buffer.write(t);
    } catch (_) {}
    try {
      final children = (span as dynamic).children;
      if (children is Iterable) {
        for (final child in children) {
          buffer.write(_extractTextSpan(child));
        }
      }
    } catch (_) {}
    final result = buffer.toString();
    return result.isNotEmpty ? result : span.toString();
  }

  String _cellString(dynamic value) {
    if (value == null) return '';
    if (value is ec.TextCellValue) return _extractTextSpan(value.value).trim();
    if (value is ec.IntCellValue) return '${value.value}';
    if (value is ec.DoubleCellValue) {
      final numVal = value.value;
      return numVal == numVal.roundToDouble()
          ? numVal.toInt().toString()
          : '$numVal';
    }
    if (value is ec.BoolCellValue) return value.value ? 'TRUE' : 'FALSE';
    if (value is ec.DateCellValue) {
      return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    }
    if (value is ec.DateTimeCellValue) return value.toString();
    return value.toString().trim();
  }

  int _columnIndex(List<String> headers, List<String> candidates) {
    for (final candidate in candidates) {
      final index = headers.indexWhere(
        (header) => header.trim().toLowerCase() == candidate.toLowerCase(),
      );
      if (index >= 0) return index;
    }
    for (final candidate in candidates) {
      final index = headers.indexWhere(
        (header) =>
            header.trim().toLowerCase().contains(candidate.toLowerCase()),
      );
      if (index >= 0) return index;
    }
    return -1;
  }

  static String _gujaratiSectionLabel(String section) {
    const map = <String, String>{
      'A': 'અ',
      'B': 'બ',
      'C': 'ક',
      'D': 'ડ',
      'E': 'ઇ',
      'F': 'ફ',
    };
    final clean = section.trim().toUpperCase();
    return map[clean] ?? clean;
  }

  static String _englishStandardToken(String rawStandard) {
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    var s = rawStandard.trim();
    for (var i = 0; i < guj.length; i++) {
      s = s.replaceAll(guj[i], '$i');
    }
    final lower = s.toLowerCase();
    if (lower.contains('balvatika') || lower.contains('બાલવાટિકા') || lower.contains('બાલ')) {
      return 'BALVATIKA';
    }
    final m = RegExp(r'[1-8]').firstMatch(s);
    return m != null ? m.group(0)! : s;
  }

  String _defaultClassLabel(String standard, String section) {
    final cleanSec = section.trim().toUpperCase();
    final gujSec = cleanSec.isEmpty ? '' : _gujaratiSectionLabel(cleanSec);
    final suffix = gujSec.isEmpty ? '' : ' - $gujSec';
    final stdToken = _englishStandardToken(standard);
    if (stdToken == 'BALVATIKA') {
      return 'બાલવાટિકા$suffix';
    }
    return 'ધોરણ - $stdToken$suffix';
  }

  String _defaultReportGroup(String standard) {
    final stdToken = _englishStandardToken(standard);
    if (stdToken == 'BALVATIKA') return 'balvatika';
    final number = int.tryParse(stdToken);
    if (number != null && number >= 1 && number <= 5) return 'std1to5';
    if (number != null && number >= 6 && number <= 8) return 'std6to8';
    return 'other';
  }

  String _normalizeReportGroup(String rawGroup, String standard) {
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    var g = rawGroup.trim().toLowerCase();
    for (var i = 0; i < guj.length; i++) {
      g = g.replaceAll(guj[i], '$i');
    }
    if (g.isEmpty) return _defaultReportGroup(standard);
    if (g.contains('balvatika') || g.contains('બાલવાટિકા') || g.contains('બાલ')) {
      return 'balvatika';
    }
    if (g.contains('1') && g.contains('5')) return 'std1to5';
    if (g.contains('6') && g.contains('8')) return 'std6to8';
    if (g == 'std1to5' || g == 'std6to8' || g == 'balvatika' || g == 'other') {
      return g;
    }
    return _defaultReportGroup(standard);
  }

  String _defaultClassKey(String standard, String section) {
    final stdToken = _englishStandardToken(standard).toLowerCase();
    final secToken = section.trim().toLowerCase();
    final raw = secToken.isEmpty ? stdToken : '${stdToken}_$secToken';
    final normalized = raw
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return normalized.isEmpty
        ? 'class_${DateTime.now().millisecondsSinceEpoch}'
        : normalized;
  }

  Future<void> _bulkImportClasses() async {
    if (!_canEdit || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    var created = 0;
    final errors = <String>[];
    try {
      final rows = await _pickRows();
      if (rows.isEmpty) return;
      if (rows.length < 2)
        throw StateError(
          'Excel needs a header row and at least one class row.',
        );
      final headers = rows.first
          .map((value) => value.trim().toLowerCase())
          .toList();
      int idx(List<String> aliases) => _columnIndex(headers, aliases);
      final standardIndex = idx(<String>['ધોરણ', 'standard']);
      final sectionIndex = idx(<String>['વર્ગ', 'section', 'વિભાગ']);
      final labelIndex = idx(<String>[
        'ધોરણ સાથે વર્ગ',
        'class name',
        'label',
        'display name',
        'વર્ગનું નામ',
      ]);
      final keyIndex = idx(<String>['class key', 'class_key', 'unique key']);
      final groupIndex = idx(<String>[
        'report group (optional)',
        'report group',
        'report_group',
        'જૂથ',
      ]);
      final sortIndex = idx(<String>['sort order', 'sort_order', 'order']);
      final sheetIndex = idx(<String>['sheet name', 'sheet_name']);
      if (standardIndex < 0)
        throw StateError('Template must include the ધોરણ (Standard) column.');
      for (var i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.every((value) => value.trim().isEmpty)) continue;
        String value(int index) =>
            index < 0 || index >= row.length ? '' : row[index].trim();
        final rawStandard = value(standardIndex);
        if (rawStandard.isEmpty) {
          errors.add('Row ${i + 1}: ધોરણ (Standard) ખાલી છે.');
          continue;
        }
        final standard = _englishStandardToken(rawStandard);
        final sectionRaw = value(sectionIndex).toUpperCase();
        final section = (sectionRaw == 'NONE' || sectionRaw == '-') ? '' : sectionRaw;
        final label = value(labelIndex).isNotEmpty
            ? value(labelIndex)
            : _defaultClassLabel(rawStandard, section);
        final key = value(keyIndex).isNotEmpty
            ? value(keyIndex)
            : _defaultClassKey(standard, section);
        final group = _normalizeReportGroup(value(groupIndex), standard);
        try {
          await _service.adminCreateClass(
            classKey: key,
            label: label,
            standard: standard,
            section: section,
            sheetName: value(sheetIndex),
            reportGroup: group,
            sortOrder:
                int.tryParse(value(sortIndex)) ??
                (_classes.length + created + 1),
          );
          created++;
        } catch (error) {
          errors.add(
            'Row ${i + 1}: ${error.toString().replaceFirst('Exception: ', '')}',
          );
        }
      }
      await _load();
      _snack(
        'Bulk class import: $created created, ${errors.length} failed.' +
            (errors.isEmpty ? '' : '\n${errors.take(8).join('\n')}'),
        error: errors.isNotEmpty,
      );
    } catch (error) {
      if (mounted) _snack('Class import failed: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _truthy(String value) => const <String>{
    'true',
    'yes',
    '1',
    'y',
    'હા',
  }.contains(value.trim().toLowerCase());

  Future<void> _bulkImportTeachers() async {
    if (!_canEdit || _busy) return;
    final activeClasses = _classes
        .where((row) => row['is_active'] == true)
        .toList();
    if (activeClasses.isEmpty) {
      _snack('Create classes first.', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    var created = 0;
    final errors = <String>[];
    try {
      final rows = await _pickRows();
      if (rows.isEmpty) return;
      if (rows.length < 2)
        throw StateError(
          'Excel needs a header row and at least one teacher-class assignment row.',
        );
      final headers = rows.first
          .map((value) => value.trim().toLowerCase())
          .toList();
      int idx(List<String> aliases) => _columnIndex(headers, aliases);
      final nameIndex = idx(<String>[
        'teacher name',
        'teacher_name',
        'name',
        'શિક્ષકનું નામ',
      ]);
      final mobileIndex = idx(<String>[
        'mobile',
        'mobile number',
        'registered mobile',
        'મોબાઇલ',
      ]);
      final passwordIndex = idx(<String>[
        'password',
        'password (4-15 characters)',
        'password (8+ characters)',
        'પાસવર્ડ',
      ]);
      final classIndex = idx(<String>[
        'વર્ગ પસંદ કરો',
        'class key or name',
        'class name',
        'class key',
        'class',
        'વર્ગ',
      ]);
      // Old templates use one semicolon-separated Subjects column. The updated
      // template has multiple Subject 1..N / વિષય 1..N dropdown columns; support all formats.
      final subjectsIndex = idx(<String>[
        'subjects',
        'subject names',
        'taught subjects',
        'વિષયો',
        'ભણાવતા વિષયો',
      ]);
      final subjectColumnIndices = <int>[];
      for (var column = 0; column < headers.length; column++) {
        final h = headers[column].trim();
        if (RegExp(r'(?:subject|વિષય)\s*\d*').hasMatch(h) &&
            column != subjectsIndex) {
          subjectColumnIndices.add(column);
        }
      }
      final classTeacherIndex = idx(<String>[
        'is class teacher',
        'class teacher',
        'વર્ગશિક્ષક',
        'વર્ગ શિક્ષક',
      ]);
      if (nameIndex < 0 ||
          mobileIndex < 0 ||
          classIndex < 0 ||
          (subjectsIndex < 0 && subjectColumnIndices.isEmpty)) {
        throw StateError(
          'Required columns: Teacher Name, Mobile, Class Key or Name, and Subjects or Subject 1..N.',
        );
      }

      String normClassToken(String raw) {
        const guj = '૦૧૨૩૪૫૬૭૮૯';
        var s = raw.trim().toLowerCase();
        for (var i = 0; i < guj.length; i++) {
          s = s.replaceAll(guj[i], '$i');
        }
        return s
            .replaceAll(RegExp(r'[—–\-_\s]+'), ' ')
            .trim();
      }

      final classLookup = <String, Map<String, dynamic>>{};
      for (final item in activeClasses) {
        final classKey = '${item['class_key'] ?? ''}'.trim();
        final classLabel = '${item['label'] ?? classKey}'.trim();
        final standard = '${item['standard'] ?? ''}'.trim();
        final section = '${item['section'] ?? ''}'.trim();
        for (final variant in <String>[
          classKey,
          classLabel,
          '$classKey — $classLabel',
          '$classKey - $classLabel',
          if (standard.isNotEmpty && section.isEmpty) standard,
          if (standard.isNotEmpty && section.isEmpty) 'ધોરણ $standard',
          if (standard.isNotEmpty && section.isEmpty) 'ધોરણ - $standard',
          if (standard.isNotEmpty && section.isNotEmpty) '$standard-$section',
          if (standard.isNotEmpty && section.isNotEmpty) '$standard - $section',
          if (standard.isNotEmpty && section.isNotEmpty) 'ધોરણ $standard - $section',
          if (standard.isNotEmpty && section.isNotEmpty) 'ધોરણ - $standard - $section',
        ]) {
          classLookup[variant.toLowerCase()] = item;
          classLookup[normClassToken(variant)] = item;
        }
      }

      final subjectLookup = <String, String>{
        for (final item in _subjects.where(
          (subject) => subject['is_active'] != false,
        ))
          '${item['subject_name'] ?? ''}'.trim().toLowerCase():
              '${item['subject_name'] ?? ''}'.trim(),
        'fln': 'FLN',
        'શા. શિ.': 'શા. શિ.',
        'શા.શિ.': 'શા. શિ.',
        'શા. શિ': 'શા. શિ.',
        'શા.શિ': 'શા. શિ.',
      };

      // Map existing teachers by 10-digit mobile and by lowercase name
      final existingByMobile = <String, Map<String, dynamic>>{};
      final existingByName = <String, Map<String, dynamic>>{};
      for (final t in _teachers) {
        final tName = '${t['teacher_name'] ?? ''}'.trim();
        final rawMob = '${t['mobile'] ?? t['registered_mobile'] ?? ''}'
            .replaceAll(RegExp(r'\D'), '');
        final mob10 = rawMob.length >= 10
            ? rawMob.substring(rawMob.length - 10)
            : rawMob;
        if (mob10.isNotEmpty) existingByMobile[mob10] = t;
        if (tName.isNotEmpty) existingByName[tName.toLowerCase()] = t;
      }

      // Group one or more class-assignment rows into a single teacher account.
      // Supports continuation rows where Teacher Name or Mobile is left blank under the same teacher.
      final groups = <String, Map<String, dynamic>>{};
      String lastTeacherName = '';
      String lastMobile10 = '';
      String lastPassword = '';

      for (var i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.every((value) => value.trim().isEmpty)) continue;
        String value(int index) =>
            index < 0 || index >= row.length ? '' : row[index].trim();
        var name = value(nameIndex);
        final mobileRaw = value(mobileIndex);
        var digits = mobileRaw.replaceAll(RegExp(r'\D'), '');
        if (digits.length == 12 && digits.startsWith('91')) {
          digits = digits.substring(2);
        } else if (digits.length == 11 && digits.startsWith('0')) {
          digits = digits.substring(1);
        } else if (digits.length > 10) {
          digits = digits.substring(digits.length - 10);
        }
        var keyMobile = digits;
        var password = passwordIndex >= 0 ? value(passwordIndex) : '';

        // Handle continuation rows (merged or blank teacher/mobile cells in Excel)
        if (name.isEmpty && lastTeacherName.isNotEmpty) {
          name = lastTeacherName;
        }
        if (keyMobile.isEmpty && name.isNotEmpty) {
          if (name.toLowerCase() == lastTeacherName.toLowerCase() &&
              lastMobile10.isNotEmpty) {
            keyMobile = lastMobile10;
          } else {
            final existing = existingByName[name.toLowerCase()];
            if (existing != null) {
              final em = '${existing['mobile'] ?? ''}'.replaceAll(RegExp(r'\D'), '');
              if (em.length >= 10) {
                keyMobile = em.substring(em.length - 10);
              }
            }
          }
        }
        if (password.isEmpty &&
            name.toLowerCase() == lastTeacherName.toLowerCase() &&
            lastPassword.isNotEmpty) {
          password = lastPassword;
        }

        final classRaw = value(classIndex).trim();
        Map<String, dynamic>? klass =
            classLookup[classRaw.toLowerCase()] ??
            classLookup[normClassToken(classRaw)];
        if (klass == null && classRaw.contains('—')) {
          final firstPart = classRaw.split('—').first.trim();
          klass = classLookup[firstPart.toLowerCase()] ??
              classLookup[normClassToken(firstPart)];
        }
        if (klass == null && classRaw.contains('-')) {
          final firstPart = classRaw.split('-').first.trim();
          klass = classLookup[firstPart.toLowerCase()] ??
              classLookup[normClassToken(firstPart)];
        }

        final subjectTokens = <String>[];
        if (subjectsIndex >= 0) {
          subjectTokens.addAll(value(subjectsIndex).split(RegExp(r'[;,|]')));
        }
        for (final subjectColumn in subjectColumnIndices) {
          final selected = value(subjectColumn);
          if (selected.isNotEmpty) {
            subjectTokens.addAll(selected.split(RegExp(r'[;,|]')));
          }
        }

        if (name.length < 2 || !RegExp(r'^[6-9]\d{9}$').hasMatch(keyMobile)) {
          errors.add(
            'Row ${i + 1}: valid Teacher Name and 10-digit Indian mobile are required.',
          );
          continue;
        }
        if (klass == null) {
          errors.add(
            'Row ${i + 1}: class "$classRaw" was not found or is inactive.',
          );
          continue;
        }

        lastTeacherName = name;
        lastMobile10 = keyMobile;
        if (password.isNotEmpty) lastPassword = password;

        final resolvedSubjects = <String>[];
        for (final rawSub in subjectTokens) {
          var cleanSub = rawSub.trim();
          if (cleanSub.isEmpty) continue;
          if (cleanSub.toLowerCase() == 'fln') cleanSub = 'FLN';
          if (cleanSub == 'શા.શિ.' ||
              cleanSub == 'શા. શિ' ||
              cleanSub == 'શા.શિ') {
            cleanSub = 'શા. શિ.';
          }
          final canonical = subjectLookup.putIfAbsent(
            cleanSub.toLowerCase(),
            () => cleanSub,
          );
          if (!resolvedSubjects.contains(canonical)) {
            resolvedSubjects.add(canonical);
          }
        }

        final group = groups.putIfAbsent(
          keyMobile,
          () => <String, dynamic>{
            'teacherName': name,
            'mobile': keyMobile,
            'password': '',
            'assignments': <String, Map<String, dynamic>>{},
            'firstRow': i + 1,
            'invalid': false,
          },
        );
        if (password.isNotEmpty) {
          if (password.length < 4 || password.length > 15) {
            errors.add(
              'Row ${i + 1}: password must contain 4 to 15 characters.',
            );
            group['invalid'] = true;
          } else {
            group['password'] = password;
          }
        }
        final assignments =
            group['assignments'] as Map<String, Map<String, dynamic>>;
        final classId = '${klass['id']}';
        final classKey = '${klass['class_key']}';
        final existingAssignment = assignments[classId];
        if (existingAssignment == null) {
          assignments[classId] = <String, dynamic>{
            'classId': classId,
            'classKey': classKey,
            'subjectNames': resolvedSubjects.toSet().toList(),
            'isClassTeacher': _truthy(value(classTeacherIndex)),
          };
        } else {
          final merged = <String>{
            ...List<String>.from(existingAssignment['subjectNames'] as List),
            ...resolvedSubjects,
          };
          existingAssignment['subjectNames'] = merged.toList();
          existingAssignment['isClassTeacher'] =
              existingAssignment['isClassTeacher'] == true ||
              _truthy(value(classTeacherIndex));
        }
      }

      for (final entry in groups.entries) {
        final group = entry.value;
        final assignments =
            (group['assignments'] as Map<String, Map<String, dynamic>>).values
                .toList();
        if (group['invalid'] == true) continue;
        final tName = '${group['teacherName']}'.trim();
        final tMob = '${group['mobile']}'.trim();
        final password = '${group['password']}';
        final existingTeacher =
            existingByMobile[tMob] ?? existingByName[tName.toLowerCase()];

        if (existingTeacher == null &&
            (password.length < 4 || password.length > 15)) {
          errors.add(
            'Rows for $tName: provide a password of 4 to 15 characters in the first row.',
          );
          continue;
        }
        if (assignments.isEmpty) {
          errors.add(
            'Rows for $tName: no valid class/subject assignment was found.',
          );
          continue;
        }
        try {
          if (existingTeacher != null) {
            final tid = '${existingTeacher['id']}'.trim();
            // Merge existing class assignments for classes not touched in this import
            final existingByCid = _teacherClassSubjects[tid] ?? const <String, List<String>>{};
            final importedCids = assignments.map((a) => '${a['classId']}').toSet();
            final mergedAssignments = List<Map<String, dynamic>>.from(assignments);
            for (final cidEntry in existingByCid.entries) {
              final cid = cidEntry.key;
              if (importedCids.contains(cid)) continue;
              final cls = activeClasses.where((c) => '${c['id']}' == cid).firstOrNull;
              if (cls == null) continue;
              mergedAssignments.add(<String, dynamic>{
                'classId': cid,
                'classKey': '${cls['class_key']}',
                'subjectNames': cidEntry.value,
                'isClassTeacher': '${cls['class_teacher_id'] ?? ''}' == tid,
              });
            }
            final mergedAllowedKeys = <String>{
              if (existingTeacher['allowed_classes'] is List)
                ...(existingTeacher['allowed_classes'] as List).map((e) => '$e'.trim()),
              ...mergedAssignments.map((a) => '${a['classKey']}'.trim()),
            }..removeWhere((s) => s.isEmpty);

            await _service.adminUpdateTeacher(
              teacherId: tid,
              teacherName: tName,
              mobile: tMob,
              newPassword: password.length >= 4 && password.length <= 15
                  ? password
                  : null,
              allowedClasses: mergedAllowedKeys.toList(),
              classSubjectAssignments: mergedAssignments,
            );
          } else {
            await _service.adminCreateTeacher(
              teacherName: tName,
              mobile: tMob,
              password: password,
              allowedClasses: assignments
                  .map((assignment) => '${assignment['classKey']}')
                  .toList(),
              classSubjectAssignments: assignments,
            );
          }
          created++;
        } catch (error) {
          errors.add(
            'Rows for $tName: ${error.toString().replaceFirst('Exception: ', '')}',
          );
        }
      }
      await _load();
      _snack(
        'Bulk teacher import: $created accounts created, ${errors.length} issues.' +
            (errors.isEmpty ? '' : '\n${errors.take(8).join('\n')}'),
        error: errors.isNotEmpty,
      );
    } catch (error) {
      if (mounted) _snack('Teacher import failed: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addClass() async {
    if (!_canEdit) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _ClassEditorDialog(),
    );
    if (result == null) return;
    await _do(
      () => _service.adminCreateClass(
        classKey: '${result['classKey']}',
        label: '${result['label']}',
        standard: '${result['standard'] ?? ''}',
        section: '${result['section'] ?? ''}',
        sheetName: '${result['sheetName'] ?? ''}',
        reportGroup: '${result['reportGroup'] ?? ''}',
        sortOrder: (result['sortOrder'] as int?) ?? 0,
      ),
      'Class created.',
    );
  }

  Future<void> _setClassActive(Map<String, dynamic> item, bool value) async {
    if (!_canEdit) return;
    await _do(
      () => _service.adminSetClassActive(
        classId: '${item['id']}',
        isActive: value,
      ),
      value ? 'Class activated.' : 'Class deactivated.',
    );
  }

  Future<void> _addTeacher() async {
    if (!_canEdit) return;
    final activeClasses = _classes
        .where((c) => c['is_active'] == true)
        .toList();
    if (activeClasses.isEmpty) {
      _snack(
        'Create at least one active class before creating a teacher.',
        error: true,
      );
      return;
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _TeacherEditorDialog(classes: activeClasses),
    );
    if (result == null) return;
    await _do(
      () => _service.adminCreateTeacher(
        teacherName: '${result['teacherName']}',
        mobile: '${result['mobile']}',
        password: '${result['password']}',
        allowedClasses: (result['allowedClasses'] as List)
            .map((e) => e.toString())
            .toList(),
        classSubjectAssignments: (result['classSubjectAssignments'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      ),
      'Teacher account created.',
    );
  }

  Future<void> _editTeacher(Map<String, dynamic> teacher) async {
    if (!_canEdit) return;
    final activeClasses = _classes
        .where((c) => c['is_active'] == true)
        .toList();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          _TeacherEditorDialog(classes: activeClasses, teacher: teacher),
    );
    if (result == null) return;
    await _do(
      () => _service.adminUpdateTeacher(
        teacherId: '${teacher['id']}',
        teacherName: result['teacherName']?.toString(),
        mobile: result['mobile']?.toString(),
        allowedClasses: (result['allowedClasses'] as List)
            .map((e) => e.toString())
            .toList(),
        newPassword: result['password']?.toString(),
        classSubjectAssignments: (result['classSubjectAssignments'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      ),
      'Teacher account updated.',
    );
  }

  Future<void> _setTeacherActive(
    Map<String, dynamic> teacher,
    bool value,
  ) async {
    if (!_canEdit) return;
    await _do(
      () => _service.adminUpdateTeacher(
        teacherId: '${teacher['id']}',
        isActive: value,
      ),
      value ? 'Teacher account activated.' : 'Teacher account deactivated.',
    );
  }

  String _classesLabel(dynamic raw) {
    final keys = raw is List
        ? raw.map((e) => e.toString()).toList()
        : <String>[];
    if (keys.isEmpty) return 'No classes assigned';
    final names = <String>[];
    for (final key in keys) {
      final match = _classes
          .where(
            (c) =>
                '${c['id']}' == key ||
                '${c['class_key']}' == key ||
                '${c['label']}' == key,
          )
          .firstOrNull;
      names.add(match == null ? key : '${match['label']}');
    }
    return names.join(', ');
  }

  String _teacherCardSummary(Map<String, dynamic> teacher) {
    final tid = '${teacher['id'] ?? ''}'.trim();
    final roleLine =
        '${teacher['role'] ?? 'teacher'} • ${teacher['is_active'] == true ? 'Active' : 'Inactive'}';
    final ctClasses = _classes
        .where((c) => '${c['class_teacher_id'] ?? ''}'.trim() == tid)
        .map((c) => '${c['label'] ?? c['class_key']}')
        .toList();
    final byClass = _teacherClassSubjects[tid] ?? const <String, List<String>>{};
    final subjectParts = <String>[];
    for (final c in _classes) {
      final cid = '${c['id'] ?? ''}'.trim();
      final subs = byClass[cid];
      if (subs != null && subs.isNotEmpty) {
        final cLabel = '${c['label'] ?? c['class_key']}';
        subjectParts.add('$cLabel: ${subs.join(', ')}');
      }
    }
    final lines = <String>[
      roleLine,
      'વર્ગો: ${_classesLabel(teacher['allowed_classes'])}',
      if (ctClasses.isNotEmpty) 'વર્ગશિક્ષક: ${ctClasses.join(', ')}',
      if (subjectParts.isNotEmpty) 'ભણાવતા વિષયો: ${subjectParts.join(' | ')}',
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final schoolName = '${_school['school_name'] ?? 'School Admin'}';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Admin Setup • $schoolName',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _busy && _contextData == null
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _problemView(_error!)
            // admin.get_context is served by the Edge Function, whose
            // requireAdmin() check is authoritative. Do not duplicate the
            // role check against a client-side response shape.
            : DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    const Material(
                      child: TabBar(
                        isScrollable: true,
                        tabs: [
                          Tab(
                            icon: Icon(Icons.class_outlined),
                            text: 'Classes',
                          ),
                          Tab(
                            icon: Icon(Icons.people_outline),
                            text: 'Teachers',
                          ),
                          Tab(
                            icon: Icon(Icons.menu_book_outlined),
                            text: 'Subjects',
                          ),
                        ],
                      ),
                    ),
                    if (_isBlocked) _blockedBanner(),
                    if (_busy) const LinearProgressIndicator(),
                    Expanded(
                      child: TabBarView(
            physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _classesView(),
                          _teachersView(),
                          _subjectsView(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _blockedBanner() => Container(
    width: double.infinity,
    color: Theme.of(context).colorScheme.errorContainer,
    padding: const EdgeInsets.all(12),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'આ શાળા BLOCKED છે. Reports જોઈ/ડાઉનલોડ કરી શકાય છે, પરંતુ classes, teachers, attendance અથવા અન્ય data edit/upload/save કરી શકાશે નહીં.',
          ),
        ),
      ],
    ),
  );

  Widget _problemView(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, size: 44),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );

  Widget _classesView() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _heading(
        'School Classes',
        'Only classes created here will be available in student imports and attendance reports.',
      ),
      const SizedBox(height: 12),
      if (_canEdit)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _addClass,
              icon: const Icon(Icons.add),
              label: const Text('Create Class'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _downloadClassTemplate,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download Excel Template'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _bulkImportClasses,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Import Classes (.xlsx)'),
            ),
            FilledButton.tonalIcon(
              onPressed: _busy
                  ? null
                  : () async {
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const SupabaseClassPromotionScreen(),
                        ),
                      );
                      if (mounted) _load();
                    },
              icon: const Icon(Icons.trending_up),
              label: const Text('Class Promote / વર્ગ બઢતી'),
            ),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              const SupabaseAttendanceFreezeManageScreen(),
                        ),
                      );
                    },
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Attendance Unfreeze / હાજરી અનફ્રીઝ'),
            ),
          ],
        ),
      const SizedBox(height: 8),
      if (_classes.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(22),
            child: Center(child: Text('No classes created yet.')),
          ),
        ),
      for (var i = 0; i < _classes.length; i++)
        Builder(
          builder: (context) {
            final item = _classes[i];
            return Card(
              child: ListTile(
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(
                  '${item['label'] ?? item['class_key']}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Key: ${item['class_key']}${'${item['standard'] ?? ''}'.isNotEmpty ? ' • Standard ${item['standard']}' : ''}${'${item['section'] ?? ''}'.isNotEmpty ? ' • Section ${item['section']}' : ''}\n${item['is_active'] == true ? 'Active' : 'Inactive'}',
                ),
                isThreeLine: true,
                trailing: _canEdit
                    ? Switch(
                        value: item['is_active'] == true,
                        onChanged: _busy
                            ? null
                            : (value) => _setClassActive(item, value),
                      )
                    : Icon(
                        item['is_active'] == true
                            ? Icons.check_circle_outline
                            : Icons.pause_circle_outline,
                      ),
              ),
            );
          },
        ),
    ],
  );

  Widget _teachersView() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _heading(
        'Teacher Accounts',
        'Teachers sign in with this school DISE number, their name selection, and their password.',
      ),
      const SizedBox(height: 12),
      if (_canEdit)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _addTeacher,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Create Teacher Account'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _downloadTeacherTemplate,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download Excel Template'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _bulkImportTeachers,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Import Teachers (.xlsx)'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _exportCreatedTeachersExcel,
              icon: const Icon(Icons.table_view_outlined),
              label: const Text('Export Teachers Excel (શિક્ષકોની યાદી .xlsx)'),
            ),
          ],
        ),
      const SizedBox(height: 8),
      if (_teachers.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(22),
            child: Center(child: Text('No teacher accounts created yet.')),
          ),
        ),
      for (final teacher in _teachers)
        Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Icon(
                '${teacher['role']}'.toLowerCase() == 'admin'
                    ? Icons.admin_panel_settings
                    : Icons.person_outline,
              ),
            ),
            title: Text(
              '${teacher['teacher_name'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _teacherCardSummary(teacher),
            ),
            isThreeLine: true,
            trailing:
                _canEdit && '${teacher['role']}'.toLowerCase() == 'teacher'
                ? PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') _editTeacher(teacher);
                      if (value == 'active')
                        _setTeacherActive(
                          teacher,
                          teacher['is_active'] != true,
                        );
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit name / classes / password'),
                      ),
                      PopupMenuItem(
                        value: 'active',
                        child: Text(
                          teacher['is_active'] == true
                              ? 'Deactivate account'
                              : 'Activate account',
                        ),
                      ),
                    ],
                  )
                : Icon(
                    teacher['is_active'] == true
                        ? Icons.check_circle_outline
                        : Icons.pause_circle_outline,
                  ),
          ),
        ),
    ],
  );

  Widget _heading(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );
}

class _ClassEditorDialog extends StatefulWidget {
  const _ClassEditorDialog();
  @override
  State<_ClassEditorDialog> createState() => _ClassEditorDialogState();
}

class _ClassEditorDialogState extends State<_ClassEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  String _selectedStandard = '1';
  String _selectedSection = '';
  String _selectedReportGroup = '1 થી 5';
  final _label = TextEditingController(text: 'ધોરણ - 1');

  static const List<String> _standardOptions = <String>[
    'બાલવાટિકા',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
  ];

  static const List<String> _sectionOptions = <String>[
    '',
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  static const List<String> _reportGroupOptions = <String>[
    'બાલવાટિકા',
    '1 થી 5',
    '6 થી 8',
  ];

  static String _gujSection(String sec) {
    const map = <String, String>{
      'A': 'અ',
      'B': 'બ',
      'C': 'ક',
      'D': 'ડ',
      'E': 'ઇ',
      'F': 'ફ',
    };
    return map[sec] ?? sec;
  }

  void _syncDerivedFields() {
    final secSuffix = _selectedSection.isEmpty
        ? ''
        : ' - ${_gujSection(_selectedSection)}';
    if (_selectedStandard == 'બાલવાટિકા') {
      _label.text = 'બાલવાટિકા$secSuffix';
      _selectedReportGroup = 'બાલવાટિકા';
    } else {
      _label.text = 'ધોરણ - $_selectedStandard$secSuffix';
      final n = int.tryParse(_selectedStandard) ?? 1;
      _selectedReportGroup = n <= 5 ? '1 થી 5' : '6 થી 8';
    }
  }

  int _autoSortOrder() {
    final secOffset = _selectedSection.isEmpty
        ? 0
        : (_selectedSection.codeUnitAt(0) - 64).clamp(1, 26);
    if (_selectedStandard == 'બાલવાટિકા') {
      return 1 + secOffset;
    }
    final n = int.tryParse(_selectedStandard) ?? 1;
    return (n * 10) + secOffset;
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
    title: const Text('નવો વર્ગ બનાવો (Create Class)'),
    content: SizedBox(
      width: MediaQuery.sizeOf(context).width * 0.86,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: _selectedStandard,
                decoration: const InputDecoration(
                  labelText: 'ધોરણ *',
                  border: OutlineInputBorder(),
                ),
                items: _standardOptions
                    .map(
                      (std) => DropdownMenuItem<String>(
                        value: std,
                        child: Text(std),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _selectedStandard = v;
                    _syncDerivedFields();
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: _selectedSection,
                decoration: const InputDecoration(
                  labelText: 'વર્ગ (ધોરણમાં વર્ગ હોય તો પસંદ કરો, નહિતર ખાલી રાખો)',
                  border: OutlineInputBorder(),
                ),
                items: _sectionOptions
                    .map(
                      (sec) => DropdownMenuItem<String>(
                        value: sec,
                        child: Text(
                          sec.isEmpty
                              ? '— કોઈ વર્ગ નહીં (માત્ર ધોરણ) —'
                              : '$sec (${_gujSection(sec)})',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedSection = v ?? '';
                    _syncDerivedFields();
                  });
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'ધોરણ સાથે વર્ગ *',
                  hintText: 'દા.ત. બાલવાટિકા, ધોરણ - 1 - અ, ધોરણ - 2',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'ધોરણ સાથે વર્ગ લખો' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: _selectedReportGroup,
                decoration: const InputDecoration(
                  labelText: 'Report Group (optional)',
                  border: OutlineInputBorder(),
                ),
                items: _reportGroupOptions
                    .map(
                      (grp) => DropdownMenuItem<String>(
                        value: grp,
                        child: Text(grp),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _selectedReportGroup = v);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('રદ કરો (Cancel)'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          final stdCode = _selectedStandard == 'બાલવાટિકા'
              ? 'BALVATIKA'
              : _selectedStandard;
          final keyBase = _selectedStandard == 'બાલવાટિકા'
              ? 'balvatika'
              : _selectedStandard;
          final autoKey = _selectedSection.isEmpty
              ? keyBase
              : '${keyBase}_${_selectedSection.toLowerCase()}';
          final reportGroupCode = _selectedReportGroup == 'બાલવાટિકા'
              ? 'balvatika'
              : _selectedReportGroup == '6 થી 8'
                  ? 'std6to8'
                  : 'std1to5';
          Navigator.pop(context, <String, dynamic>{
            'classKey': autoKey,
            'label': _label.text.trim(),
            'standard': stdCode,
            'section': _selectedSection,
            'sheetName': _label.text.trim(),
            'reportGroup': reportGroupCode,
            'sortOrder': _autoSortOrder(),
          });
        },
        child: const Text('વર્ગ બનાવો (Create)'),
      ),
    ],
  );
}

class _TeacherEditorDialog extends StatefulWidget {
  const _TeacherEditorDialog({required this.classes, this.teacher});
  final List<Map<String, dynamic>> classes;
  final Map<String, dynamic>? teacher;
  @override
  State<_TeacherEditorDialog> createState() => _TeacherEditorDialogState();
}

class _TeacherEditorDialogState extends State<_TeacherEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _mobile;
  final _password = TextEditingController();
  late Set<String> _selectedClasses;
  final Map<String, List<String>> _subjectOptions = <String, List<String>>{};
  final Map<String, Set<String>> _selectedSubjects = <String, Set<String>>{};
  final Map<String, Map<String, TextEditingController>>
      _subjectMaxPeriodControllers =
      <String, Map<String, TextEditingController>>{};
  final Map<String, TextEditingController> _newSubjects =
      <String, TextEditingController>{};

  TextEditingController _maxPeriodCtrlFor(String classId, String subject,
      {String initialText = ''}) {
    final bySub = _subjectMaxPeriodControllers.putIfAbsent(
      classId,
      () => <String, TextEditingController>{},
    );
    return bySub.putIfAbsent(
      subject,
      () => TextEditingController(text: initialText),
    );
  }
  final Map<String, String?> _classTeacherIds = <String, String?>{};
  final Set<String> _classTeacherClasses = <String>{};
  bool _subjectLoading = true;
  String? _loadError;

  String _classId(Map<String, dynamic> item) => '${item['id'] ?? ''}';
  String _classKey(Map<String, dynamic> item) => '${item['class_key'] ?? ''}';
  String _classLabel(Map<String, dynamic> item) =>
      '${item['label'] ?? item['class_key'] ?? 'Class'}';
  String get _teacherId => '${widget.teacher?['id'] ?? ''}';

  static String _clean10DigitMobile(dynamic raw) {
    final digits = '${raw ?? ''}'.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      return digits.substring(2);
    }
    if (digits.length == 11 && digits.startsWith('0')) {
      return digits.substring(1);
    }
    if (digits.length > 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: '${widget.teacher?['teacher_name'] ?? ''}',
    );
    _mobile = TextEditingController(
      text: _clean10DigitMobile(
        widget.teacher?['mobile'] ?? widget.teacher?['registered_mobile'],
      ),
    );
    final raw = widget.teacher?['allowed_classes'];
    _selectedClasses = raw is List
        ? raw.map((e) => e.toString()).toSet()
        : <String>{};
    for (final item in widget.classes) {
      final id = _classId(item);
      if (id.isNotEmpty) _newSubjects[id] = TextEditingController();
    }
    _loadAssignmentData();
  }

  Future<void> _loadAssignmentData() async {
    try {
      final ids = widget.classes
          .map(_classId)
          .where((id) => id.isNotEmpty)
          .toList();
      if (ids.isNotEmpty) {
        final client = Supabase.instance.client;
        final schoolRefRaw = await client.rpc('current_school_ref');
        final schoolRef = '${schoolRefRaw ?? ''}'.trim();
        if (schoolRef.isEmpty)
          throw StateError('School reference is unavailable.');
        final masterRows = await client
            .from('school_subject_master')
            .select('subject_name,sort_order')
            .eq('school_ref', schoolRef)
            .eq('is_active', true)
            .order('sort_order');
        final orderedMasterRows =
            masterRows
                .map<Map<String, dynamic>>(
                  (row) => Map<String, dynamic>.from(row),
                )
                .toList()
              ..sort((a, b) {
                final aOrder =
                    int.tryParse('${a['sort_order'] ?? ''}') ?? 2147483647;
                final bOrder =
                    int.tryParse('${b['sort_order'] ?? ''}') ?? 2147483647;
                final orderCompare = aOrder.compareTo(bOrder);
                if (orderCompare != 0) return orderCompare;
                return '${a['subject_name'] ?? ''}'.toLowerCase().compareTo(
                  '${b['subject_name'] ?? ''}'.toLowerCase(),
                );
              });
        final masterNames = orderedMasterRows
            .map((row) => '${row['subject_name'] ?? ''}'.trim())
            .where(
              (name) =>
                  name.isNotEmpty &&
                  name != 'વ્યક્તિત્વ વિકાસ',
            )
            .toList();
        for (final id in ids) {
          _subjectOptions[id] = List<String>.from(masterNames);
        }

        final classRows = await client
            .from('school_classes')
            .select('id,class_teacher_id,standard')
            .inFilter('id', ids);
        for (final raw in classRows) {
          final row = Map<String, dynamic>.from(raw);
          final id = '${row['id']}';
          final assignedTeacher = row['class_teacher_id']?.toString();
          _classTeacherIds[id] = assignedTeacher;
          if (_teacherId.isNotEmpty && assignedTeacher == _teacherId) {
            _classTeacherClasses.add(id);
            final item = widget.classes
                .where((c) => _classId(c) == id)
                .firstOrNull;
            if (item != null) _selectedClasses.add(_classKey(item));
          }
        }

        if (_teacherId.isNotEmpty) {
          final assignmentRows = await client
              .from('teacher_subject_assignments')
              .select('class_id,subject_name,max_periods')
              .eq('teacher_id', _teacherId)
              .eq('school_ref', schoolRef);
          for (final raw in assignmentRows) {
            final row = Map<String, dynamic>.from(raw);
            final id = '${row['class_id']}';
            final name = '${row['subject_name'] ?? ''}'.trim();
            final maxP = int.tryParse('${row['max_periods'] ?? ''}');
            if (id.isEmpty || name.isEmpty) continue;
            final item = widget.classes
                .where((c) => _classId(c) == id)
                .firstOrNull;
            if (item != null) {
              _selectedClasses.add(_classKey(item));
            }
            final options = _subjectOptions.putIfAbsent(id, () => <String>[]);
            var canonical = options
                .where((value) => value.toLowerCase() == name.toLowerCase())
                .firstOrNull;
            if (canonical == null) {
              canonical = name;
              options.add(canonical);
            }
            (_selectedSubjects[id] ??= <String>{}).add(canonical);
            final ctrl = _maxPeriodCtrlFor(id, canonical);
            if (maxP != null && maxP > 0) {
              ctrl.text = '$maxP';
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _subjectLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _subjectLoading = false;
        _loadError =
            'Could not load school-wide subjects. Confirm migration 20261028030000 is applied. Details: $error';
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _password.dispose();
    for (final controller in _newSubjects.values) {
      controller.dispose();
    }
    for (final subMap in _subjectMaxPeriodControllers.values) {
      for (final controller in subMap.values) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  List<String> _subjectsFor(String classId) {
    final options = _subjectOptions[classId] ?? const <String>[];
    final selected = _selectedSubjects[classId] ?? const <String>{};
    return options.where((name) => selected.contains(name)).toList();
  }

  List<Map<String, dynamic>> _buildAssignmentPayload() {
    final result = <Map<String, dynamic>>[];
    for (final item in widget.classes) {
      final id = _classId(item);
      final key = _classKey(item);
      if (id.isEmpty || key.isEmpty || !_selectedClasses.contains(key))
        continue;
      final selectedSubs = _subjectsFor(id);
      final maxPeriodsMap = <String, int>{};
      for (final sub in selectedSubs) {
        final rawText =
            (_subjectMaxPeriodControllers[id]?[sub]?.text ?? '').trim();
        final parsed = int.tryParse(rawText);
        if (parsed != null && parsed > 0) {
          maxPeriodsMap[sub] = parsed.clamp(1, 48);
        }
      }
      result.add(<String, dynamic>{
        'classId': id,
        'classKey': key,
        'subjectNames': selectedSubs,
        'subjectMaxPeriods': maxPeriodsMap,
        'isClassTeacher': _classTeacherClasses.contains(id),
      });
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.teacher != null;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      title: Text(
        isEdit
            ? 'Edit Teacher & Subject Assignments'
            : 'Create Teacher & Subject Assignments',
      ),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width * 0.92,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Teacher name / શિક્ષકનું નામ',
                  ),
                  validator: (value) => (value ?? '').trim().length < 2
                      ? 'Enter teacher name.'
                      : null,
                  textCapitalization: TextCapitalization.words,
                ),
                TextFormField(
                  controller: _mobile,
                  keyboardType: TextInputType.phone,
                  maxLength: 13,
                  decoration: const InputDecoration(
                    labelText: 'Registered mobile / નોંધાયેલ મોબાઇલ',
                    hintText: '10-digit Indian mobile number',
                    counterText: '',
                  ),
                  validator: (value) {
                    final digits = _clean10DigitMobile(value);
                    return RegExp(r'^[6-9]\d{9}$').hasMatch(digits)
                        ? null
                        : 'Enter a valid 10-digit Indian mobile number.';
                  },
                ),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: isEdit
                        ? 'New password (leave blank to keep current)'
                        : 'Password',
                    helperText: '4 to 15 characters.',
                  ),
                  validator: (value) =>
                      (!isEdit || (value ?? '').isNotEmpty) &&
                          ((value ?? '').length < 4 ||
                              (value ?? '').length > 15)
                      ? 'Enter 4 to 15 characters.'
                      : null,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Class, taught subjects and class-teacher responsibility',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Choose one or many subjects for each class from the school-wide Admin Setup → Subjects catalogue. The same teacher can have different subjects in different classes.',
                ),
                if (_subjectLoading) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (_loadError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _loadError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                for (final item in widget.classes)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            value: _selectedClasses.contains(_classKey(item)),
                            title: Text(
                              _classLabel(item),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(_classKey(item)),
                            onChanged: _subjectLoading
                                ? null
                                : (checked) => setState(() {
                                    final key = _classKey(item);
                                    if (checked == true) {
                                      _selectedClasses.add(key);
                                    } else {
                                      _selectedClasses.remove(key);
                                    }
                                  }),
                          ),
                          if (_selectedClasses.contains(_classKey(item))) ...[
                            const Divider(height: 12),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              value: _classTeacherClasses.contains(
                                _classId(item),
                              ),
                              title: const Text(
                                'આ વર્ગનો વર્ગશિક્ષક (વ્યક્તિગત વિકાસ / વર્તન મૂલ્યાંકન)',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle:
                                  (_classTeacherIds[_classId(item)] != null &&
                                      _classTeacherIds[_classId(item)] !=
                                          _teacherId)
                                  ? const Text(
                                      'હાલમાં બીજા શિક્ષક વર્ગશિક્ષક છે. પસંદ કરવાથી તેમની જગ્યાએ આ શિક્ષક નિમાશે.',
                                    )
                                  : const Text(
                                      'આ જવાબદારી મળવાથી આ વર્ગમાં વ્યક્તિગત વિકાસ મૂલ્યાંકન સેવ કરી શકાશે.',
                                    ),
                              onChanged: _subjectLoading
                                  ? null
                                  : (checked) => setState(() {
                                      final id = _classId(item);
                                      if (checked == true) {
                                        _classTeacherClasses.add(id);
                                      } else {
                                        _classTeacherClasses.remove(id);
                                      }
                                    }),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'આ વર્ગમાં શીખવાતા વિષયો',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            if ((_subjectOptions[_classId(item)] ??
                                    const <String>[])
                                .isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 5),
                                child: Text(
                                  'No active school subjects. Open Admin Setup → Subjects and add the subjects first.',
                                ),
                              ),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                for (final subject
                                    in _subjectOptions[_classId(item)] ??
                                        const <String>[])
                                  FilterChip(
                                    label: Text(subject),
                                    selected:
                                        (_selectedSubjects[_classId(item)] ??
                                                const <String>{})
                                            .contains(subject),
                                    onSelected: _subjectLoading
                                        ? null
                                        : (selected) => setState(() {
                                            final id = _classId(item);
                                            final set = _selectedSubjects
                                                .putIfAbsent(
                                                  id,
                                                  () => <String>{},
                                                );
                                            if (selected) {
                                              set.add(subject);
                                              _maxPeriodCtrlFor(id, subject);
                                            } else {
                                              set.remove(subject);
                                            }
                                          }),
                                  ),
                              ],
                            ),
                            if (_subjectsFor(_classId(item)).isNotEmpty) ...[
                              const SizedBox(height: 10),
                              const Text(
                                '⏱️ પસંદ કરેલ વિષયના મહત્તમ તાસ / અઠવાડિયું (Maximum Weekly Periods for Auto Timetable):',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 10,
                                runSpacing: 8,
                                children: [
                                  for (final selSub
                                      in _subjectsFor(_classId(item)))
                                    SizedBox(
                                      width: 195,
                                      child: TextFormField(
                                        controller: _maxPeriodCtrlFor(
                                          _classId(item),
                                          selSub,
                                        ),
                                        keyboardType: TextInputType.number,
                                        decoration: InputDecoration(
                                          labelText: '$selSub — મહત્તમ તાસ',
                                          hintText: 'દા.ત. 6',
                                          isDense: true,
                                          border: const OutlineInputBorder(),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text(
                                'વિષય પસંદ કરતા નીચે મહત્તમ તાસનું ખાનું ખુલશે. ઓટો-સમયપત્રક (Auto Timetable) બનાવતી વખતે આ વર્ગ અને વિષયમાં દાખલ કરેલ મહત્તમ તાસથી વધુ તાસ ફાળવાશે નહીં.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _subjectLoading || _loadError != null
              ? null
              : () {
                  if (!_formKey.currentState!.validate()) return;
                  if (_selectedClasses.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Select at least one class.'),
                      ),
                    );
                    return;
                  }
                  final classAssignments = _buildAssignmentPayload();
                  for (final assignment in classAssignments) {
                    final names = assignment['subjectNames'] as List<String>;
                    if (names.any(
                      (name) => name.trim().isEmpty || name.trim().length > 100,
                    )) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Subject names must contain 1–100 characters.',
                          ),
                        ),
                      );
                      return;
                    }
                  }
                  Navigator.pop(context, <String, dynamic>{
                    'teacherName': _name.text.trim(),
                    'mobile': _clean10DigitMobile(_mobile.text),
                    'password': _password.text,
                    'allowedClasses': _selectedClasses.toList()..sort(),
                    'classSubjectAssignments': classAssignments,
                  });
                },
          child: Text(isEdit ? 'Save assignments' : 'Create account'),
        ),
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

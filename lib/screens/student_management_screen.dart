import 'package:flutter/material.dart';
import 'archived_students_screen.dart';
import 'student_bulk_import_screen.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

/// Supabase student roster management with the full school Excel-template field
/// set. Template-only/custom columns are preserved in students.custom_fields.
class StudentManagementScreen extends StatefulWidget {
  const StudentManagementScreen({
    super.key,
    required this.classId,
    required this.classLabel,
    required this.schoolType,
    this.isAdmin = false,
    this.readOnly = false,
  });

  final String classId;
  final String classLabel;
  final String schoolType;
  final bool isAdmin;
  final bool readOnly;

  @override
  State<StudentManagementScreen> createState() =>
      _StudentManagementScreenState();
}

const List<Map<String, String>> _studentFields = <Map<String, String>>[
  {'key': 'roll_number', 'label': 'Roll Number'},
  {'key': 'gr', 'label': 'GR નંબર'},
  {'key': 'dd', 'label': 'DD'},
  {'key': 'mm', 'label': 'MM'},
  {'key': 'yyyy', 'label': 'YYYY'},
  {'key': 'name', 'label': 'વિદ્યાર્થીનું નામ'},
  {'key': 'father_name', 'label': 'પિતાનું નામ / Father Name'},
  {'key': 'religion', 'label': 'ધર્મ / Religion (Gujarati)'},
  {'key': 'caste', 'label': 'પેટા જ્ઞાતિ'},
  {'key': 'category', 'label': 'કેટેગરી'},
  {'key': 'gender', 'label': 'લિંગ / Gender'},
  {'key': 'enroll_school', 'label': 'શાળા પ્રવેશ'},
  {'key': 'enroll_class', 'label': 'વર્ગ પ્રવેશ'},
  {'key': 'mobile', 'label': 'મોબાઈલ નંબર'},
  {'key': 'mother_name', 'label': 'માતાનું નામ'},
  {'key': 'address', 'label': 'સરનામું / Address'},
  {'key': 'birth_place', 'label': 'જન્મ સ્થળ'},
  {'key': 'native_place', 'label': 'વતન / Native Place'},
  {'key': 'dob_words', 'label': 'જન્મ તારીખ શબ્દોમાં'},
  {'key': 'last_school', 'label': 'પૂર્વ શાળાનું નામ'},
  {'key': 'enroll_sch_class', 'label': 'શાળામાં દાખલ ધોરણ'},
  {'key': 'enroll_sch_class_words', 'label': 'દાખલ ધોરણ શબ્દોમાં'},
  {'key': 'present_days', 'label': 'હાજર દિવસો / Present Days'},
  {'key': 'name_en', 'label': 'NAME IN ENGLISH'},
  {'key': 'religion_en', 'label': 'RELIGION IN ENGLISH'},
  {'key': 'caste_en', 'label': 'CASTE IN ENGLISH'},
  {'key': 'category_en', 'label': 'CATEGORY IN ENG'},
  {'key': 'mother_en', 'label': 'MOTHER IN ENGLISH'},
  {'key': 'birth_place_en', 'label': 'BIRTH PLACE IN ENG'},
  {'key': 'native_place_en', 'label': 'NATIVE PLACE IN ENG'},
  {'key': 'dob_en', 'label': 'DOB IN ENGLISH'},
  {'key': 'last_school_en', 'label': 'LAST SCHOOL IN ENG'},
  {'key': 'enroll_sch_class_en', 'label': 'ENROLL CLASS IN ENG'},
  {'key': 'enroll_sch_class_words_en', 'label': 'ENROLL CLASS WORDS IN ENG'},
  {'key': 'apaar_id', 'label': 'APAAR ID'},
  {'key': 'has_aadhaar', 'label': 'આધાર કાર્ડ છે? (Has Student Aadhaar • YES/NO)'},
  {'key': 'ration_card_kyc', 'label': 'રેશન કાર્ડ KYC (Ration Card KYC • YES/NO)'},
  {'key': 'scholarship_done', 'label': 'શિષ્યવૃત્તિ થઈ ગઈ છે? (Scholarship Done • YES/NO)'},
  {'key': 'scholarship_reason', 'label': 'શિષ્યવૃત્તિ બાકી હોવાનું કારણ (Reason if NO)'},
  {'key': 'scholarship_other', 'label': 'શિષ્યવૃત્તિ અન્ય વિગતો'},
  {'key': 'uid', 'label': 'UID નંબર'},
  {'key': 'pen', 'label': 'PEN નંબર'},
  {'key': 'is_divyang', 'label': 'દિવ્યાંગ વિદ્યાર્થી? (હા / ના)'},
];

// Bank details remain Admin-only. Aadhaar and ration-card fields are no longer collected.
const List<Map<String, String>> _privateFields = <Map<String, String>>[
  {'key': 'bank_name', 'label': 'બેંકનું નામ'},
  {'key': 'bank_branch', 'label': 'બેંક બ્રાન્ચ'},
  {'key': 'name_as_passbook', 'label': 'પાસબુક મુજબ નામ'},
  {'key': 'account_number', 'label': 'એકાઉન્ટ નંબર'},
  {'key': 'ifsc_code', 'label': 'IFSC કોડ'},
];

class _StudentManagementScreenState extends State<StudentManagementScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  List<Map<String, dynamic>> _students = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _allAccessibleActiveStudents = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _classes = <Map<String, dynamic>>[];
  Set<String> _classTeacherClassIds = <String>{};
  Map<String, String> _classLabels = <String, String>{};
  late String _activeClassId;
  late String _activeClassLabel;
  int _archivedInClassCount = 0;
  int _archivedInSchoolCount = 0;
  List<String> _customHeaders = <String>[];
  String? _schoolRef;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _search = '';

  bool _canManageClass(String classId) {
    if (widget.readOnly) return false;
    if (widget.isAdmin) return true;
    final cid = classId.trim();
    if (cid.isEmpty || cid == '__ALL__') {
      return _classTeacherClassIds.isNotEmpty;
    }
    return _classTeacherClassIds.contains(cid);
  }

  bool get _canEditExisting => _canManageClass(_activeClassId);
  bool get _canAdd => _canManageClass(_activeClassId);

  @override
  void initState() {
    super.initState();
    _activeClassId = widget.classId.trim().isEmpty ? '__ALL__' : widget.classId.trim();
    _activeClassLabel = widget.classLabel.trim().isEmpty ? 'સમગ્ર શાળા (All Classes)' : widget.classLabel.trim();
    _load();
  }

  String _text(dynamic value) => (value ?? '').toString().trim();

  String _cleanError(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('PostgrestException(message: ', 'Database error: ');

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_client.auth.currentUser == null)
        throw StateError('Please sign in again.');
      final ref = _text(await _client.rpc('current_school_ref'));
      if (ref.isEmpty)
        throw StateError('No active school is linked to this login.');

      final classRows = await _client
          .from('school_classes')
          .select('id,label,class_key,sort_order,is_active')
          .eq('school_ref', ref)
          .eq('is_active', true)
          .order('sort_order');
      var sortedClasses = classRows.map((r) => Map<String, dynamic>.from(r)).toList();
      Set<String> ctIdSet = <String>{};
      if (widget.isAdmin) {
        ctIdSet = sortedClasses.map((c) => _text(c['id'])).toSet();
      } else {
        try {
          final ctIds = await _client.rpc('psm_class_teacher_class_ids');
          if (ctIds is List) {
            ctIdSet = ctIds.map((e) => _text(e)).where((s) => s.isNotEmpty).toSet();
          }
          final allowedIds = await _client.rpc('psm_attendance_class_ids');
          if (allowedIds is List) {
            final set = allowedIds.map((e) => _text(e)).toSet();
            sortedClasses = sortedClasses.where((c) => set.contains(_text(c['id']))).toList();
          }
        } catch (_) {}
      }
      final allowedClassIdSet = sortedClasses.map((c) => _text(c['id'])).toSet();
      final labels = <String, String>{
        for (final c in sortedClasses)
          '${c['id']}': '${c['label'] ?? c['class_key'] ?? ''}',
      };

      if (_activeClassId != '__ALL__' && _activeClassId.isNotEmpty) {
        try {
          await _client.rpc('psm_renumber_class_rolls', params: <String, dynamic>{
            'p_class_id': _activeClassId,
          });
        } catch (_) {}
      }
      final allSchoolStudents = await _client
          .from('students')
          .select('*')
          .eq('school_ref', ref);
      var archClass = 0;
      var archSchool = 0;
      final rawStudents = <Map<String, dynamic>>[];
      final allAccessibleActive = <Map<String, dynamic>>[];
      for (final raw in allSchoolStudents) {
        final s = Map<String, dynamic>.from(raw);
        final cid = _text(s['class_id']);
        if (!widget.isAdmin && !allowedClassIdSet.contains(cid)) {
          continue;
        }
        final isAct = s['is_active'] == true &&
            _text(s['leaving_date']).isEmpty &&
            _text(s['exit_date']).isEmpty;
        if (!isAct) {
          archSchool++;
          if (_activeClassId == '__ALL__' || cid == _activeClassId) {
            archClass++;
          }
        } else {
          allAccessibleActive.add(s);
          if (_activeClassId == '__ALL__' || cid == _activeClassId) {
            rawStudents.add(s);
          }
        }
      }

      var headers = <String>[];
      try {
        final headerRow = await _client
            .from('school_custom_headers')
            .select('headers')
            .eq('school_ref', ref)
            .maybeSingle();
        final rawHeaders = headerRow?['headers'];
        if (rawHeaders is List)
          headers = rawHeaders.map((value) => _text(value)).toList();
      } catch (_) {
        // Custom headers are optional; the standard Excel-template fields remain available.
      }
      if (headers.isEmpty || headers.every((value) => value.isEmpty)) {
        headers = List<String>.generate(11, (index) => 'Custom ${index + 1}');
      }

      if (!mounted) return;
      final loadedStudents =
          rawStudents.map((row) => Map<String, dynamic>.from(row)).toList();
      loadedStudents.sort((a, b) {
        final aRoll = int.tryParse(_text(a['roll_number']));
        final bRoll = int.tryParse(_text(b['roll_number']));
        if (aRoll != null && bRoll != null) return aRoll.compareTo(bRoll);
        if (aRoll != null) return -1;
        if (bRoll != null) return 1;
        return _text(a['name']).compareTo(_text(b['name']));
      });
      if (!mounted) return;
      setState(() {
        _schoolRef = ref;
        _classes = sortedClasses;
        _classTeacherClassIds = ctIdSet;
        _classLabels = labels;
        _archivedInClassCount = archClass;
        _archivedInSchoolCount = archSchool;
        _students = loadedStudents;
        _allAccessibleActiveStudents = allAccessibleActive;
        _customHeaders = headers;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _cleanError(error);
        _loading = false;
      });
    }
  }

  Future<void> _openEditor({Map<String, dynamic>? student}) async {
    if ((student == null && !_canAdd) ||
        (student != null && !_canEditExisting) ||
        _saving) return;
    final schoolRef = _schoolRef;
    if (schoolRef == null) return;

    Map<String, dynamic> privateDetails = <String, dynamic>{};
    if (widget.isAdmin && student != null) {
      try {
        final raw = await _client
            .from('student_private_details')
            .select(
                'student_id,school_ref,bank_name,bank_branch,name_as_passbook,account_number,ifsc_code')
            .eq('school_ref', schoolRef)
            .eq('student_id', '${student['id']}')
            .maybeSingle();
        if (raw != null) privateDetails = Map<String, dynamic>.from(raw);
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Private bank details could not be loaded. Check the Admin-only Supabase policy. ${_cleanError(error)}'),
        ));
        return; // Never open an edit form with blank private values over an existing private record.
      }
    }

    final result = await showDialog<_StudentFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StudentEditorDialog(
        classLabel: _activeClassLabel,
        schoolType: widget.schoolType,
        student: student,
        privateDetails: privateDetails,
        customHeaders: _customHeaders,
        showPrivateFields: widget.isAdmin,
      ),
    );
    if (result == null || !mounted) return;
    if (student == null) {
      final proceed =
          await _checkArchivedStudentBeforeAdd(result.studentValues, schoolRef);
      if (!proceed || !mounted) return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payload = <String, dynamic>{
        ...result.studentValues,
        'school_ref': schoolRef,
        'class_id': _activeClassId == '__ALL__' ? (_classes.isNotEmpty ? '${_classes.first['id']}' : '') : _activeClassId,
        'custom_fields': result.customValues,
        'is_active': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      final dynamic savedRow;
      final previousRoll = student == null ? '' : _text(student['roll_number']);
      final requestedRoll = _text(result.studentValues['roll_number']);
      final rollChanged = student != null && previousRoll != requestedRoll;
      if (student == null) {
        savedRow = await _client
            .from('students')
            .insert(payload)
            .select('id')
            .single();
      } else {
        // A single database RPC updates the student's fields and shifts the
        // intervening active rolls in one transaction. This avoids transient
        // duplicate-roll errors from the class's unique index.
        await _client.rpc(
          'psm_update_student_profile_with_roll_shift',
          params: <String, dynamic>{
            'p_student_id': '${student['id']}',
            'p_student_values': result.studentValues,
            'p_custom_fields': result.customValues,
          },
        );
        if (widget.isAdmin) {
          await _client
              .from('students')
              .update({
                'is_divyang': result.studentValues['is_divyang'] == true,
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              })
              .eq('id', '${student['id']}')
              .eq('school_ref', schoolRef)
              .eq('class_id', '${student['class_id'] ?? _activeClassId}');
        }
        savedRow = <String, dynamic>{'id': student['id']};
      }

      if (widget.isAdmin) {
        final privatePayload = <String, dynamic>{
          ...result.privateValues,
          'student_id': '${savedRow['id']}',
          'school_ref': schoolRef,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
        await _client.from('student_private_details').upsert(
              privatePayload,
              onConflict: 'student_id',
            );
      }
      await _load();
      if (!mounted) return;
      final successMessage = student == null
          ? 'Student added successfully.'
          : (rollChanged
              ? 'Student updated. Roll numbers between the old and new positions were shifted automatically.'
              : 'Student updated successfully.');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _canonicalEntryDate(dynamic value) {
    final raw = _text(value);
    final dmy =
        RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$').firstMatch(raw);
    if (dmy != null) {
      final d = (int.tryParse(dmy.group(1)!) ?? 0).toString().padLeft(2, '0');
      final m = (int.tryParse(dmy.group(2)!) ?? 0).toString().padLeft(2, '0');
      final y = dmy.group(3)!;
      return '$y-$m-$d';
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
    }
    return raw.toLowerCase();
  }

  String _studentDobKey(Map<String, dynamic> row) {
    final day = _text(row['dd']);
    final month = _text(row['mm']);
    final year = _text(row['yyyy']);
    if (day.isEmpty && month.isEmpty && year.isEmpty) return '';
    return '${day.padLeft(2, '0')}/${month.padLeft(2, '0')}/$year';
  }

  Future<bool> _checkArchivedStudentBeforeAdd(
      Map<String, dynamic> values, String schoolRef) async {
    final archivedRaw = await _client
        .from('students')
        .select(
            'id,roll_number,gr,name,dd,mm,yyyy,enroll_school,leaving_date,class_id')
        .eq('school_ref', schoolRef)
        .eq('is_active', false);
    final archived =
        archivedRaw.map((row) => Map<String, dynamic>.from(row)).toList();
    final enteredGr = _text(values['gr']).toLowerCase();
    final enteredEntry = _canonicalEntryDate(values['enroll_school']);
    final enteredName = _text(values['name']).toLowerCase();
    final enteredDob = _studentDobKey(values);
    bool sameDate(String a, String b) => a.isNotEmpty && b.isNotEmpty && a == b;
    bool sameGrAndEntry(Map<String, dynamic> row) =>
        enteredGr.isNotEmpty &&
        _text(row['gr']).toLowerCase() == enteredGr &&
        sameDate(enteredEntry, _canonicalEntryDate(row['enroll_school']));
    bool likelyMatch(Map<String, dynamic> row) =>
        (enteredName.isNotEmpty &&
            _text(row['name']).toLowerCase() == enteredName) ||
        (enteredDob.isNotEmpty && enteredDob == _studentDobKey(row));

    final exact = archived.where(sameGrAndEntry).toList();
    if (exact.isNotEmpty) {
      final old = exact.first;
      final restore = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Archived enrollment already exists'),
          content: Text(
              '${_text(old['name'])} has the same GR number and school-entry date in Archived Students. Restore this original enrollment rather than creating a duplicate?'),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Restore existing')),
          ],
        ),
      );
      if (restore != true || !mounted) return false;
      setState(() {
        _saving = true;
        _error = null;
      });
      try {
        await _client
            .from('students')
            .update(<String, dynamic>{
              'is_active': true,
              'leaving_date': null,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', _text(old['id']))
            .eq('school_ref', schoolRef);
        await _load();
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Archived enrollment restored; no duplicate was created.')));
      } catch (error) {
        if (mounted) setState(() => _error = _cleanError(error));
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return false;
    }

    final similar = archived.where(likelyMatch).toList();
    if (similar.isEmpty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Similar archived student found'),
            content: Text(
                '${_text(similar.first['name'])} looks similar to this new entry. Check the GR number and school-entry date. If this is a genuine reenrollment with a new GR/date, continue to create a new enrollment.'),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Continue as new enrollment')),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _changeSectionDialog(Map<String, dynamic> student) async {
    if (!widget.isAdmin || _saving || _classes.length < 2) return;
    final curCid = _text(student['class_id']);
    final candidates = _classes.where((c) => _text(c['id']) != curCid).toList();
    if (candidates.isEmpty) return;
    String targetCid = _text(candidates.first['id']);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('વિદ્યાર્થીનો વિભાગ બદલો (Change Section A ↔ B ↔ C)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_text(student['name'])} (GR: ${_text(student['gr'])})\n'
                'માત્ર વર્ગ વિભાગ જ બદલાશે — હાજર દિવસો, જન્મ તારીખ કે શાળા પ્રવેશમાં કોઈ ફેરફાર થશે નહીં.',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: targetCid,
                decoration: const InputDecoration(
                  labelText: 'નવો વિભાગ / વર્ગ પસંદ કરો (Target Section)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: candidates
                    .map(
                      (c) => DropdownMenuItem<String>(
                        value: _text(c['id']),
                        child: Text(_text(c['label']).isNotEmpty ? _text(c['label']) : _text(c['class_key'])),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => targetCid = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('વિભાગ બદલો'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _client.rpc(
        'psm_change_student_section_only',
        params: <String, dynamic>{
          'p_student_ids': <String>[_text(student['id'])],
          'p_to_class_id': targetCid,
        },
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_text(student['name'])} નો વિભાગ બદલીને "${_classLabels[targetCid] ?? targetCid}" કરવામાં આવ્યો છે.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _archiveStudent(Map<String, dynamic> student) async {
    if (!_canEditExisting || _saving || _schoolRef == null) return;
    var selectedDate = DateTime.now();
    var selectedReason = 'lc';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final dateIso =
              '${selectedDate.year.toString().padLeft(4, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
          final dateDmy =
              '${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}';
          return AlertDialog(
            title: const Text('Deactive Student? / વિદ્યાર્થીને નિષ્ક્રિય (Deactive) કરો'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'શું તમે "${_text(student['name'])}" ને નિષ્ક્રિય (Deactive) કરવા માંગો છો? માત્ર આ ૧ જ વિદ્યાર્થી નિષ્ક્રિય (Deactive) થશે.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate,
                      firstDate: DateTime(1900, 1, 1),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text('શાળા છોડ્યાની / કમી તારીખ: $dateDmy ($dateIso)'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: selectedReason,
                  decoration: const InputDecoration(
                    labelText: 'હાજરીપત્રકના મુખપૃષ્ઠ મુજબ કમી કરવાનું કારણ',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'lc',
                      child: Text('ચાલુ માસમાં લિ. સર્ટી. લઈ ગયેલ'),
                    ),
                    DropdownMenuItem(
                      value: 'continuous_absence',
                      child: Text('સતત ગેરહાજરીથી નામ કમી કરેલ'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedReason = v);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel / રદ કરો'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Deactive / નિષ્ક્રિય કરો'),
              ),
            ],
          );
        },
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final leavingDate = '${selectedDate.year.toString().padLeft(4, '0')}-'
          '${selectedDate.month.toString().padLeft(2, '0')}-'
          '${selectedDate.day.toString().padLeft(2, '0')}';
      await _client.rpc(
        'psm_archive_student_and_shift_rolls',
        params: <String, dynamic>{
          'p_student_id': '${student['id']}',
          'p_exit_date': leavingDate,
          'p_exit_reason': selectedReason,
        },
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _normSearch(String input) {
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    final sb = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      final idx = guj.indexOf(ch);
      sb.write(idx >= 0 ? idx : ch);
    }
    return sb.toString();
  }

  @override
  Widget build(BuildContext context) {
    final term = _normSearch(_search.trim());
    final tokens = term
        .split(RegExp(r'\s+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    // Admin searching by keyword automatically searches across all classes without requiring class selection.
    final sourcePool = (widget.isAdmin && tokens.isNotEmpty)
        ? _allAccessibleActiveStudents
        : _students;
    final visible = sourcePool.where((row) {
      if (tokens.isEmpty) return true;
      final haystack = _normSearch(<String>[
        _text(row['name']),
        _text(row['name_en']),
        _text(row['roll_number']),
        _text(row['gr']),
        _text(row['father_name']),
        _text(row['mother_name']),
        _text(row['mother_en']),
        _text(row['mobile']),
        _text(row['uid']),
        _text(row['pen']),
        _classLabels[_text(row['class_id'])] ?? '',
      ].join(' '));
      return tokens.every((tok) => haystack.contains(tok));
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Students — $_activeClassLabel (${visible.length})',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_canEditExisting)
            IconButton(
              tooltip: 'Bulk Upload / GR Smart Update (સમગ્ર શાળા અથવા વર્ગ)',
              onPressed: _saving
                  ? null
                  : () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => StudentBulkImportScreen(
                            classId: _activeClassId == '__ALL__' ? '' : _activeClassId,
                            classLabel: _activeClassLabel,
                            schoolType: widget.schoolType,
                            readOnly: widget.readOnly,
                          ),
                        ),
                      );
                      if (mounted) await _load();
                    },
              icon: const Icon(Icons.upload_file_outlined),
            ),
          if (_schoolRef != null)
            IconButton(
              tooltip: 'Active / Deactive Students ($_archivedInSchoolCount)',
            onPressed: _schoolRef == null
                ? null
                : () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => ArchivedStudentsScreen(
                        schoolRef: _schoolRef!,
                        classId: _activeClassId == '__ALL__' ? '' : _activeClassId,
                        classLabel: _activeClassLabel,
                        readOnly: widget.readOnly,
                      ),
                    ));
                    if (mounted) await _load();
                  },
            icon: Badge(
              isLabelVisible: _archivedInSchoolCount > 0,
              label: Text('$_archivedInSchoolCount'),
              child: const Icon(Icons.archive_outlined),
            ),
          ),

          IconButton(
              tooltip: 'Refresh',
              onPressed: _load,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: _canAdd
          ? FloatingActionButton.extended(
              onPressed: _saving ? null : () => _openEditor(),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add student'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              if (!_canEditExisting)
                const MaterialBanner(
                  content: Text(
                      'This school is blocked. Student records are view-only.'),
                  leading: Icon(Icons.lock_outline),
                  actions: [SizedBox.shrink()],
                ),
              if (_archivedInClassCount > 0 && _schoolRef != null)
                Container(
                  width: double.infinity,
                  color: Colors.amber.shade100,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Text(
                        'આ વર્ગમાં $_archivedInClassCount વિદ્યાર્થીઓ નિષ્ક્રિય (Deactive) સ્થિતિમાં છે (શાળામાં કુલ: $_archivedInSchoolCount).',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.orange.shade800,
                        ),
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ArchivedStudentsScreen(
                                schoolRef: _schoolRef!,
                                classId: _activeClassId == '__ALL__' ? '' : _activeClassId,
                                classLabel: _activeClassLabel,
                                readOnly: widget.readOnly,
                              ),
                            ),
                          );
                          if (mounted) await _load();
                        },
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('Active / Deactive યાદી ખોલો (વર્ગ પસંદ કરી સક્રિય કરો)'),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Row(
                  children: [
                    if (_classes.isNotEmpty) ...[
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _activeClassId == '__ALL__' ||
                                  _classes.any((c) => '${c['id']}' == _activeClassId)
                              ? _activeClassId
                              : '__ALL__',
                          decoration: const InputDecoration(
                            labelText: 'વર્ગ પસંદ કરો (Class)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: <DropdownMenuItem<String>>[
                            const DropdownMenuItem<String>(
                              value: '__ALL__',
                              child: Text('સમગ્ર શાળા (All Classes)'),
                            ),
                            ..._classes.map(
                              (c) => DropdownMenuItem<String>(
                                value: '${c['id']}',
                                child: Text('${c['label'] ?? c['class_key']}'),
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _activeClassId = v;
                              _activeClassLabel = v == '__ALL__'
                                  ? 'સમગ્ર શાળા (All Classes)'
                                  : (_classLabels[v] ?? v);
                            });
                            _load();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      flex: 3,
                      child: TextField(
                        decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: widget.isAdmin
                                ? 'Admin Whole-School Search: Name, GR, Mobile, Father Name, Mother Name'
                                : 'Search Allotted Class: Name, GR, Mobile, Father Name, Mother Name',
                            border: const OutlineInputBorder(),
                            isDense: true),
                        onChanged: (value) => setState(() => _search = value),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.all(10),
                    child: MaterialBanner(
                      content: Text(_error!),
                      leading: const Icon(Icons.error_outline),
                      actions: [
                        TextButton(onPressed: _load, child: const Text('Retry'))
                      ],
                    )),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Text(widget.isAdmin
                            ? 'No active students in this class. Use Add student to create the first record.'
                            : 'No active students in this class. Please ask the School Admin to add students.'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final row = visible[index];
                          final gender = _text(row['gender']).isEmpty
                              ? 'UNSPECIFIED'
                              : _text(row['gender']);
                          final category = _text(row['category']).isEmpty
                              ? 'OTHER'
                              : _text(row['category']);
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                  child: Text(_text(row['roll_number']).isEmpty
                                      ? '${index + 1}'
                                      : _text(row['roll_number']))),
                              title: Text(_text(row['name']),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              subtitle: Text(
                                  '${_classLabels[_text(row['class_id'])] ?? ''} • GR: ${_text(row['gr']).isEmpty ? '-' : _text(row['gr'])} • Mobile: ${_text(row['mobile']).isEmpty ? '-' : _text(row['mobile'])} • પિતા: ${_text(row['father_name']).isEmpty ? '-' : _text(row['father_name'])} • માતા: ${_text(row['mother_name']).isEmpty ? '-' : _text(row['mother_name'])} • $category • $gender'),
                              trailing: _canManageClass(_text(row['class_id']))
                                  ? PopupMenuButton<String>(
                                      enabled: _canManageClass(_text(row['class_id'])),
                                      onSelected: (value) {
                                        if (value == 'edit')
                                          _openEditor(student: row);
                                        if (value == 'change_section')
                                          _changeSectionDialog(row);
                                        if (value == 'archive') _archiveStudent(row);
                                      },
                                      itemBuilder: (_) => <PopupMenuEntry<String>>[
                                        const PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Edit student')),
                                        if (widget.isAdmin && _classes.length > 1)
                                          const PopupMenuItem(
                                            value: 'change_section',
                                            child: Text('Change Section (વિભાગ બદલો A↔B↔C)'),
                                          ),
                                        const PopupMenuItem(
                                            value: 'archive',
                                            child: Text('Deactive student (નિષ્ક્રિય કરો)')),
                                      ],
                                    )
                                  : null,
                              onTap: _canManageClass(_text(row['class_id']))
                                  ? () => _openEditor(student: row)
                                  : null,
                            ),
                          );
                        },
                      ),
              ),
            ]),
    );
  }
}

class _StudentFormResult {
  const _StudentFormResult(
      {required this.studentValues,
      required this.privateValues,
      required this.customValues});
  final Map<String, dynamic> studentValues;
  final Map<String, dynamic> privateValues;
  final Map<String, dynamic> customValues;
}

class _StudentEditorDialog extends StatefulWidget {
  const _StudentEditorDialog({
    required this.classLabel,
    required this.schoolType,
    required this.student,
    required this.privateDetails,
    required this.customHeaders,
    required this.showPrivateFields,
  });

  final String classLabel;
  final String schoolType;
  final Map<String, dynamic>? student;
  final Map<String, dynamic> privateDetails;
  final List<String> customHeaders;
  final bool showPrivateFields;

  @override
  State<_StudentEditorDialog> createState() => _StudentEditorDialogState();
}

class _StudentEditorDialogState extends State<_StudentEditorDialog> {
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  late String _category;
  late String _gender;
  bool _saving = false;
  String? _validationError;

  bool get _editing => widget.student != null;
  bool get _isCoed =>
      const {'mixed', 'coed'}.contains(widget.schoolType.trim().toLowerCase());

  String _normalizeCategory(String raw) {
    final value = raw.trim().toUpperCase();
    if (value == 'SC' || value.contains('SCHEDULED CASTE')) return 'SC';
    if (value == 'ST' || value.contains('SCHEDULED TRIBE')) return 'ST';
    if (value == 'OBC' ||
        value.contains('બક્ષી') ||
        value.contains('BAKSHIPANCH')) return 'OBC';
    return 'OTHER';
  }

  String _normalizeGender(String raw) {
    final value = raw.trim().toUpperCase();
    if (const {'BOYS', 'BOY', 'MALE', 'M', 'KUMAR', 'કુમાર'}.contains(value))
      return 'BOYS';
    if (const {'GIRLS', 'GIRL', 'FEMALE', 'F', 'KANYA', 'કન્યા'}
        .contains(value)) return 'GIRLS';
    return 'UNSPECIFIED';
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.student ?? <String, dynamic>{};
    for (final field in _studentFields) {
      final key = field['key']!;
      final raw = existing[key];
      final initial = (key == 'is_divyang' ||
              key == 'has_aadhaar' ||
              key == 'ration_card_kyc' ||
              key == 'scholarship_done')
          ? ((raw == true ||
                  const {'TRUE', 'YES', 'Y', '1', 'T', 'હા'}
                      .contains('$raw'.trim().toUpperCase()))
              ? 'YES'
              : 'NO')
          : '${raw ?? ''}';
      _controllers[key] = TextEditingController(text: initial);
    }
    for (final field in _privateFields) {
      final key = field['key']!;
      _controllers['private:$key'] =
          TextEditingController(text: '${widget.privateDetails[key] ?? ''}');
    }
    final custom = existing['custom_fields'];
    final customValues = custom is Map ? custom : <String, dynamic>{};
    for (var index = 0; index < _customHeadersForForm.length; index++) {
      final header = _customHeadersForForm[index];
      final slot = 'template_custom_${index + 1}';
      final legacyDefault = 'Custom ${index + 1}';
      final savedValue = customValues[slot] ??
          customValues[header] ??
          customValues[legacyDefault] ??
          '';
      _controllers['custom:$header'] =
          TextEditingController(text: '$savedValue');
    }
    _category = _normalizeCategory('${existing['category'] ?? 'OTHER'}');
    final normalizedSchoolType = widget.schoolType.trim().toLowerCase();
    final fallbackGender = normalizedSchoolType == 'boys'
        ? 'BOYS'
        : (normalizedSchoolType == 'girls' ? 'GIRLS' : 'UNSPECIFIED');
    // For single-gender schools, the school's type is authoritative. For a
    // mixed school, keep a blank gender unassigned until the user chooses it.
    _gender = _isCoed
        ? _normalizeGender('${existing['gender'] ?? fallbackGender}')
        : fallbackGender;
    _controllers['category']!.text = _category;
    _controllers['gender']!.text = _gender;
  }

  bool _isRestrictedCustomHeader(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.contains('aadhaar') ||
        normalized.contains('aadhar') ||
        normalized.contains('ration') ||
        normalized.contains('આધાર') ||
        normalized.contains('રેશન');
  }

  List<String> get _customHeadersForForm {
    const standardLabels = <String>{
      'roll number',
      'gr નંબર',
      'dd',
      'mm',
      'yyyy',
      'વિદ્યાર્થીનું નામ',
      'પિતાનું નામ / father name',
      'ધર્મ / religion (gujarati)',
      'ધર્મ',
      'religion in english',
      'પેટા જ્ઞાતિ',
      'કેટેગરી',
      'લિંગ / gender',
      'શાળા પ્રવેશ',
      'વર્ગ પ્રવેશ',
      'મોબાઈલ નંબર',
      'માતાનું નામ',
      'સરનામું / address',
      'જન્મ સ્થળ',
      'વતન / native place',
      'જન્મ તારીખ શબ્દોમાં',
      'પૂર્વ શાળાનું નામ',
      'શાળામાં દાખલ ધોરણ',
      'દાખલ ધોરણ શબ્દોમાં',
      'હાજર દિવસો / present days',
      'name in english',
      'caste in english',
      'category in eng',
      'mother in english',
      'birth place in eng',
      'native place in eng',
      'dob in english',
      'last school in eng',
      'enroll class in eng',
      'enroll class words in eng',
      'apaar id',
      'શિષ્યવૃત્તિ?',
      'શિષ્યવૃત્તિ કારણ',
      'શિષ્યવૃત્તિ અન્ય વિગતો',
      'uid નંબર',
      'pen નંબર',
      'દિવ્યાંગ વિદ્યાર્થી? (હા / ના)',
      'બેંકનું નામ',
      'બેંક બ્રાન્ચ',
      'પાસબુક મુજબ નામ',
      'એકાઉન્ટ નંબર',
      'ifsc કોડ',
    };
    final configured =
        widget.customHeaders.map((header) => header.trim()).toList();
    final out = <String>[];
    // The template has 11 custom positions. A configured school header renames
    // that position; it must not create a second, duplicate field next to Custom N.
    for (var index = 0; index < 11; index++) {
      final configuredLabel =
          index < configured.length ? configured[index] : '';
      final candidate = configuredLabel.isNotEmpty &&
              !standardLabels.contains(configuredLabel.toLowerCase()) &&
              !_isRestrictedCustomHeader(configuredLabel)
          ? configuredLabel
          : 'Custom ${index + 1}';
      out.add(out.contains(candidate) ? 'Custom ${index + 1}' : candidate);
    }
    // Keep any extra configured labels visible as well, without losing the
    // stable first 11 positions from the workbook template.
    for (var index = 11; index < configured.length; index++) {
      final candidate = configured[index];
      if (candidate.isNotEmpty &&
          !standardLabels.contains(candidate.toLowerCase()) &&
          !_isRestrictedCustomHeader(candidate) &&
          !out.contains(candidate)) {
        out.add(candidate);
      }
    }
    return out;
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field(String key, String label,
      {bool multiline = false, bool secret = false}) {
    final controller = _controllers[key] ??= TextEditingController();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: secret,
        minLines: multiline ? 2 : 1,
        maxLines: multiline ? 3 : 1,
        decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            alignLabelWithHint: multiline),
      ),
    );
  }

  Widget _rollNumberCompatibilityField() {
    final controller = _controllers['roll_number']!;
    final isCoedSchool = const {'mixed', 'coed'}
        .contains(widget.schoolType.trim().toLowerCase());
    final label = isCoedSchool
        ? 'Roll Number (CY) — automatically copied from Roll Number'
        : 'Roll Number (CA) — automatically copied from Roll Number';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: Text(value.text.trim().isEmpty
              ? 'Will match the Roll Number above'
              : value.text.trim()),
        ),
      ),
    );
  }

  List<Widget> _fieldsFor(List<String> keys) {
    final output = <Widget>[];
    for (final key in keys) {
      if (key == 'is_divyang' && !widget.showPrivateFields) continue;
      final field = _studentFields.firstWhere((item) => item['key'] == key);
      final label = field['label']!;
      if (key == 'is_divyang' ||
          key == 'has_aadhaar' ||
          key == 'ration_card_kyc' ||
          key == 'scholarship_done') {
        final raw = _controllers[key]!.text.trim().toUpperCase();
        final current =
            const {'YES', 'TRUE', 'Y', '1', 'T', 'હા'}.contains(raw) ? 'YES' : 'NO';
        output.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            value: current,
            decoration: InputDecoration(
                labelText: label, border: const OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'YES', child: Text('YES (હા)')),
              DropdownMenuItem(value: 'NO', child: Text('NO (ના)')),
            ],
            onChanged: (value) => setState(() {
              final nextVal = value ?? 'NO';
              _controllers[key]!.text = nextVal;
              if (key == 'scholarship_done' && nextVal == 'YES') {
                _controllers['scholarship_reason']?.clear();
              }
            }),
          ),
        ));
      } else if (key == 'scholarship_reason') {
        final schRaw = (_controllers['scholarship_done']?.text ?? 'NO').trim().toUpperCase();
        final isSchYes = const {'YES', 'TRUE', 'Y', '1', 'T', 'હા'}.contains(schRaw);
        output.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: _controllers[key],
            enabled: !isSchYes,
            readOnly: isSchYes,
            minLines: 1,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: isSchYes
                  ? 'શિષ્યવૃત્તિ કારણ (Scholarship YES હોવાથી બંધ છે)'
                  : label,
              border: const OutlineInputBorder(),
              filled: isSchYes,
            ),
          ),
        ));
      } else if (key == 'category') {
        const categories = <String>['SC', 'ST', 'OBC', 'OTHER'];
        output.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            value: categories.contains(_category.toUpperCase())
                ? _category.toUpperCase()
                : 'OTHER',
            decoration: InputDecoration(
                labelText: label, border: const OutlineInputBorder()),
            items: categories
                .map((value) =>
                    DropdownMenuItem(value: value, child: Text(value)))
                .toList(),
            onChanged: (value) => setState(() {
              _category = value ?? 'OTHER';
              _controllers['category']!.text = _category;
            }),
          ),
        ));
      } else if (key == 'gender') {
        const genders = <String>['BOYS', 'GIRLS', 'UNSPECIFIED'];
        final normalized = _gender.toUpperCase();
        output.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            value: genders.contains(normalized) ? normalized : 'UNSPECIFIED',
            decoration: InputDecoration(
                labelText: label, border: const OutlineInputBorder()),
            items: genders
                .map((value) => DropdownMenuItem(
                    value: value,
                    child: Text(switch (value) {
                      'BOYS' => 'કુમાર (BOYS)',
                      'GIRLS' => 'કન્યા (GIRLS)',
                      _ => 'લિંગ પસંદ કરો (Not set)'
                    })))
                .toList(),
            onChanged: (value) => setState(() {
              _gender = value ?? 'UNSPECIFIED';
              _controllers['gender']!.text = _gender;
            }),
          ),
        ));
      } else {
        output.add(_field(key, label,
            multiline: const {
              'address',
              'scholarship_reason',
              'scholarship_other'
            }.contains(key)));
      }
    }
    return output;
  }

  Future<void> _save() async {
    final name = (_controllers['name']?.text ?? '').trim();
    if (name.isEmpty) {
      setState(() => _validationError = 'વિદ્યાર્થીનું નામ જરૂરી છે.');
      return;
    }
    final roll = (_controllers['roll_number']?.text ?? '').trim();
    if (roll.isEmpty) {
      setState(() => _validationError = 'Roll Number ખાલી રાખી શકાતો નથી.');
      return;
    }
    if (_isCoed && !const {'BOYS', 'GIRLS'}.contains(_gender)) {
      setState(
          () => _validationError = 'મિશ્ર શાળા માટે લિંગ પસંદ કરવું જરૂરી છે.');
      return;
    }
    setState(() {
      _saving = true;
      _validationError = null;
    });
    try {
      final studentValues = <String, dynamic>{};
      for (final field in _studentFields) {
        final key = field['key']!;
        if (key == 'present_days') {
          final raw = (_controllers[key]?.text ?? '').trim();
          final value = int.tryParse(raw);
          if (raw.isNotEmpty && value == null)
            throw Exception('હાજર દિવસો માટે પૂર્ણાંક સંખ્યા દાખલ કરો.');
          studentValues[key] = value ?? 0;
        } else if (key == 'is_divyang') {
          studentValues[key] = const {'YES', 'TRUE', '1', 'T'}
              .contains((_controllers[key]?.text ?? '').trim().toUpperCase());
        } else {
          studentValues[key] = (_controllers[key]?.text ?? '').trim();
        }
      }
      final privateValues = <String, dynamic>{};
      if (widget.showPrivateFields) {
        for (final field in _privateFields) {
          final key = field['key']!;
          privateValues[key] =
              (_controllers['private:$key']?.text ?? '').trim();
        }
      }
      final current = widget.student?['custom_fields'];
      final customValues = current is Map
          ? current.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};
      const restrictedKeys = <String>{
        'aadhaar',
        'name_as_aadhaar',
        'dob_as_aadhaar',
        'nameAsAadhaar',
        'dobAsAadhaar',
        'ration_card_type',
        'ration_card_no',
        'ration_card_member_no',
        'rationCardType',
        'rationCardNo',
        'rationCardMemberNo',
      };
      customValues.removeWhere((key, value) {
        final normalizedKey = key
            .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '')
            .toLowerCase()
            .replaceAll('_', '');
        final hasRestrictedToken = normalizedKey.contains('aadhaar') ||
            normalizedKey.contains('aadhar') ||
            normalizedKey.contains('ration') ||
            key.contains('આધાર') ||
            key.contains('રેશન');
        return hasRestrictedToken ||
            restrictedKeys.any((restricted) =>
                restricted.toLowerCase().replaceAll('_', '') == normalizedKey);
      });
      for (var index = 0; index < _customHeadersForForm.length; index++) {
        final header = _customHeadersForForm[index];
        final value = (_controllers['custom:$header']?.text ?? '').trim();
        // Stable slot keys preserve values when Admin changes the visible
        // school-specific label later; aliases preserve legacy exports.
        customValues['template_custom_${index + 1}'] = value;
        customValues[header] = value;
        if (index < 11) customValues['Custom ${index + 1}'] = value;
      }
      studentValues['category'] =
          _category.trim().isEmpty ? 'OTHER' : _category.trim().toUpperCase();
      studentValues['gender'] =
          _gender.trim().isEmpty ? 'UNSPECIFIED' : _gender.trim().toUpperCase();
      if (mounted)
        Navigator.of(context).pop(_StudentFormResult(
            studentValues: studentValues,
            privateValues: privateValues,
            customValues: customValues));
    } catch (error) {
      setState(() {
        _saving = false;
        _validationError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final basicKeys = <String>[
      'roll_number',
      'gr',
      'dd',
      'mm',
      'yyyy',
      'name',
      'father_name',
      'religion',
      'caste',
      'category',
      if (_isCoed) 'gender',
      'mother_name',
      'mobile',
      'address',
      if (widget.showPrivateFields) 'is_divyang',
    ];
    const enrollmentKeys = <String>[
      'enroll_school',
      'enroll_class',
      'enroll_sch_class',
      'enroll_sch_class_words',
      'present_days',
      'birth_place',
      'native_place',
      'dob_words',
      'last_school'
    ];
    const englishKeys = <String>[
      'name_en',
      'religion_en',
      'caste_en',
      'category_en',
      'mother_en',
      'birth_place_en',
      'native_place_en',
      'dob_en',
      'last_school_en',
      'enroll_sch_class_en',
      'enroll_sch_class_words_en'
    ];
    const scholarshipKeys = <String>[
      'apaar_id',
      'has_aadhaar',
      'ration_card_kyc',
      'uid',
      'pen',
      'scholarship_done',
      'scholarship_reason',
      'scholarship_other'
    ];
    return Dialog(
      child: SizedBox(
        width: 900,
        height: 660,
        child: DefaultTabController(
          length: widget.showPrivateFields ? 5 : 4,
          child: Column(children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
                child: Row(children: [
                  Expanded(
                      child: Text(
                          _editing
                              ? 'Edit student — ${widget.classLabel}'
                              : 'Add student — ${widget.classLabel}',
                          style: Theme.of(context).textTheme.titleLarge)),
                  IconButton(
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close)),
                ])),
            TabBar(isScrollable: true, tabs: <Widget>[
              const Tab(text: 'Basic details'),
              const Tab(text: 'School / enrollment'),
              const Tab(text: 'English fields'),
              const Tab(text: 'Scholarship / template'),
              if (widget.showPrivateFields) const Tab(text: 'Private details'),
            ]),
            Expanded(
                child: TabBarView(
            physics: const NeverScrollableScrollPhysics(),children: [
              ListView(padding: const EdgeInsets.all(18), children: <Widget>[
                ..._fieldsFor(basicKeys),
                _rollNumberCompatibilityField(),
              ]),
              ListView(
                  padding: const EdgeInsets.all(18),
                  children: _fieldsFor(enrollmentKeys)),
              ListView(
                  padding: const EdgeInsets.all(18),
                  children: _fieldsFor(englishKeys)),
              ListView(padding: const EdgeInsets.all(18), children: [
                ..._fieldsFor(scholarshipKeys),
                const Divider(height: 26),
                Text('Custom columns from the school template',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                for (final header in _customHeadersForForm)
                  _field('custom:$header', header),
              ]),
              if (widget.showPrivateFields)
                ListView(padding: const EdgeInsets.all(18), children: [
                  const Text(
                      'બેંકની વિગતો માત્ર School Admin જોઈ અને સુધારી શકે છે.'),
                  const SizedBox(height: 12),
                  for (final field in _privateFields)
                    _field('private:${field['key']}', field['label']!,
                        secret: field['key'] == 'account_number'),
                ]),
            ])),
            if (_validationError != null)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(_validationError!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)))),
            Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save),
                      label: Text(_saving ? 'Saving…' : 'Save student')),
                ])),
          ]),
        ),
      ),
    );
  }
}

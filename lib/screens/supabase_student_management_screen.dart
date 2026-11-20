import 'package:pmshri_attendance/services/firebase_backend_client.dart';
import 'package:flutter/material.dart';

import 'package:share_plus/share_plus.dart';
import '../services/school_class_order.dart';
import '../services/school_export_service.dart';
import '../services/supabase_student_service.dart';
import 'archived_students_screen.dart';
import 'student_bulk_import_screen.dart';
import '../services/school_type.dart';

/// Supabase roster manager with add/edit/soft-archive support.
/// Includes Religion (Gujarati & English) and excludes Aadhaar (3) and Ration Card (3) headers.
class SupabaseStudentManagementScreen extends StatefulWidget {
  const SupabaseStudentManagementScreen({
    super.key,
    required this.classId,
    required this.classLabel,
    required this.schoolType,
    this.readOnly = false,
  });

  final String classId;
  final String classLabel;
  final String schoolType;
  final bool readOnly;

  @override
  State<SupabaseStudentManagementScreen> createState() =>
      _SupabaseStudentManagementScreenState();
}

class _SupabaseStudentManagementScreenState
    extends State<SupabaseStudentManagementScreen> {
  final SupabaseStudentService _service = SupabaseStudentService();
  final TextEditingController _search = TextEditingController();
  List<Map<String, dynamic>> _students = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _allSchoolStudents = <Map<String, dynamic>>[];
  bool _includePromotedAndArchived = false;
  List<Map<String, dynamic>> _classes = <Map<String, dynamic>>[];
  Set<String> _classTeacherClassIds = <String>{};
  Map<String, String> _classLabels = <String, String>{};

  bool _canManageClass(String classId) {
    if (widget.readOnly) return false;
    if (_isAdmin) return true;
    final cid = classId.trim();
    if (cid.isEmpty || cid == '__ALL__') {
      return _classTeacherClassIds.isNotEmpty;
    }
    return _classTeacherClassIds.contains(cid);
  }
  late String _selectedClassId;
  late String _selectedClassLabel;
  String? _schoolRef;
  String _resolvedSchoolType = '';
  int _archivedCount = 0;
  bool _isAdmin = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedClassId =
        widget.classId.trim().isEmpty ? '__ALL__' : widget.classId.trim();
    _selectedClassLabel = widget.classLabel.trim().isEmpty
        ? 'સમગ્ર શાળા (All Classes)'
        : widget.classLabel.trim();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ref = await _service.currentSchoolRef();
      final client = Supabase.instance.client;
      final classRows = await client
          .from('school_classes')
          .select('id,label,class_key,sort_order,is_active')
          .eq('school_ref', ref)
          .eq('is_active', true)
          .order('sort_order');
      var sortedClasses = SchoolClassOrder.sorted(
        classRows.map((r) => Map<String, dynamic>.from(r)),
      );
      final isAdminUser = await _service.isCurrentUserAdmin();
      Set<String> classTeacherIdSet = <String>{};
      if (isAdminUser) {
        classTeacherIdSet = sortedClasses.map((c) => '${c['id'] ?? ''}'.trim()).toSet();
      } else {
        try {
          final ctIds = await client.rpc('psm_class_teacher_class_ids');
          if (ctIds is List) {
            classTeacherIdSet = ctIds.map((e) => '${e ?? ''}'.trim()).where((s) => s.isNotEmpty).toSet();
          }
          final allowedIds = await client.rpc('psm_attendance_class_ids');
          if (allowedIds is List) {
            final set = allowedIds.map((e) => '${e ?? ''}'.trim()).toSet();
            sortedClasses = sortedClasses
                .where((c) => set.contains('${c['id'] ?? ''}'.trim()))
                .toList();
          }
        } catch (_) {}
      }
      final allowedClassIdSet =
          sortedClasses.map((c) => '${c['id'] ?? ''}'.trim()).toSet();
      final labels = <String, String>{
        for (final c in sortedClasses)
          '${c['id']}': '${c['label'] ?? c['class_key'] ?? ''}',
      };
      if (!widget.readOnly &&
          _selectedClassId != '__ALL__' &&
          _selectedClassId.isNotEmpty) {
        try {
          await client.rpc(
            'psm_renumber_class_rolls',
            params: <String, dynamic>{'p_class_id': _selectedClassId},
          );
        } catch (_) {}
      }
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        _service.listStudents(classId: _selectedClassId),
        Future<bool>.value(isAdminUser),
        client
            .from('students')
            .select('*')
            .eq('school_ref', ref),
        client
            .from('schools')
            .select('school_type')
            .eq('id', ref)
            .maybeSingle(),
      ]);
      final schoolRow = results[3];
      final regType = schoolRow is Map
          ? '${schoolRow['school_type'] ?? ''}'.trim()
          : '';
      final allRaw = results[2] as List;
      final fullList = <Map<String, dynamic>>[];
      var archCount = 0;
      for (final r in allRaw) {
        if (r is! Map) continue;
        final m = Map<String, dynamic>.from(r);
        final cid = '${m['class_id'] ?? ''}'.trim();
        if (!isAdminUser && !allowedClassIdSet.contains(cid)) {
          continue;
        }
        fullList.add(m);
        if (_selectedClassId != '__ALL__' &&
            _selectedClassId.isNotEmpty &&
            cid != _selectedClassId) {
          continue;
        }
        final isAct = m['is_active'] == true &&
            '${m['leaving_date'] ?? ''}'.trim().isEmpty &&
            '${m['exit_date'] ?? ''}'.trim().isEmpty;
        if (!isAct) archCount++;
      }
      if (!mounted) return;
      setState(() {
        _schoolRef = ref;
        if (regType.isNotEmpty) _resolvedSchoolType = regType;
        _classes = sortedClasses;
        _classTeacherClassIds = classTeacherIdSet;
        _classLabels = labels;
        _students = results[0] as List<Map<String, dynamic>>;
        _allSchoolStudents = fullList;
        _isAdmin = results[1] as bool;
        _archivedCount = archCount;
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

  List<Map<String, dynamic>> get _filteredStudents {
    final query = _search.text.trim().toLowerCase();
    final source = (_isAdmin && (_includePromotedAndArchived || query.isNotEmpty))
        ? _allSchoolStudents.where((s) {
            if (_selectedClassId == '__ALL__' || _selectedClassId.isEmpty) {
              return true;
            }
            return '${s['class_id'] ?? ''}'.trim() == _selectedClassId ||
                '${s['previous_class_id'] ?? ''}'.trim() == _selectedClassId;
          }).toList()
        : _students;
    if (query.isEmpty) return source;
    final tokens = query
        .split(RegExp(r'\s+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    return source.where((student) {
      final combined = <String>[
        '${student['gr'] ?? ''}',
        '${student['roll_number'] ?? ''}',
        '${student['previous_roll_number'] ?? ''}',
        '${student['name'] ?? ''}',
        '${student['name_en'] ?? ''}',
        '${student['father_name'] ?? ''}',
        '${student['mother_name'] ?? ''}',
        '${student['mother_en'] ?? ''}',
        '${student['mobile'] ?? ''}',
        '${student['religion'] ?? ''}',
        '${student['religion_en'] ?? ''}',
        '${student['caste'] ?? ''}',
        '${student['uid'] ?? ''}',
        '${student['pen'] ?? ''}',
        '${student['apaar_id'] ?? ''}',
        '${student['promoted_from_class_label'] ?? ''}',
        '${student['promoted_to_class_label'] ?? ''}',
      ].join(' ').toLowerCase();
      return tokens.every((tok) => combined.contains(tok));
    }).toList();
  }

  void _showStudentWholeDataDialog(Map<String, dynamic> s) {
    final isGrad8 = '${s['promoted_to_standard'] ?? ''}' == '9' ||
        s['graduated_from_std_8'] == true;
    final isAct = s['is_active'] == true &&
        '${s['leaving_date'] ?? ''}'.trim().isEmpty &&
        '${s['exit_date'] ?? ''}'.trim().isEmpty;
    final statusLabel = isGrad8
        ? 'ધોરણ 8 પૂર્ણ -> ધોરણ 9 માં બઢતી (Promoted to Class 9)'
        : (isAct ? 'સક્રિય (Active)' : 'નિષ્ક્રિય / કમી (Deactive)');
    final clsLabel = _classLabels['${s['class_id']}'] ??
        '${s['class_label'] ?? s['promoted_from_class_label'] ?? '-'}';
    final pairs = <MapEntry<String, String>>[
      MapEntry('સ્થિતિ (Status)', statusLabel),
      MapEntry('વર્ગ (Current / Last Class)', clsLabel),
      if ('${s['promoted_from_class_label'] ?? ''}'.trim().isNotEmpty)
        MapEntry('અગાઉનો વર્ગ (Promoted From)', '${s['promoted_from_class_label']} (Roll: ${s['previous_roll_number'] ?? '-'})'),
      if ('${s['promoted_to_class_label'] ?? ''}'.trim().isNotEmpty)
        MapEntry('બઢતી વર્ગ (Promoted To)', '${s['promoted_to_class_label']} (${s['promoted_at'] ?? ''})'),
      MapEntry('રોલ નંબર (Roll Number)', '${s['roll_number'] ?? '-'}'),
      MapEntry('GR નંબર (GR Number)', '${s['gr'] ?? '-'}'),
      MapEntry('વિદ્યાર્થીનું નામ (Surname / Name / Father Name)', '${s['name'] ?? '-'}'),
      MapEntry('Name in English', '${s['name_en'] ?? '-'}'),
      MapEntry('પિતાનું નામ (Father Name)', '${s['father_name'] ?? '-'}'),
      MapEntry('માતાનું નામ (Mother Name)', '${s['mother_name'] ?? '-'} (${s['mother_en'] ?? ''})'),
      MapEntry('જન્મ તારીખ (DOB)', '${s['dd'] ?? ''}/${s['mm'] ?? ''}/${s['yyyy'] ?? ''} (${s['dob_words'] ?? ''})'),
      MapEntry('જાતિ (Gender)', _gender(s['gender'])),
      MapEntry('કેટેગરી (Category)', _category(s['category'])),
      MapEntry('જ્ઞાતિ (Caste)', '${s['caste'] ?? '-'} (${s['caste_en'] ?? ''})'),
      MapEntry('ધર્મ (Religion)', '${s['religion'] ?? '-'} (${s['religion_en'] ?? ''})'),
      MapEntry('શાળા પ્રવેશ તારીખ (School Enroll Date)', '${s['enroll_school'] ?? '-'}'),
      MapEntry('વર્ગ પ્રવેશ તારીખ (Class Enroll Date)', '${s['enroll_class'] ?? '-'}'),
      MapEntry('મોબાઇલ નંબર (Mobile)', '${s['mobile'] ?? '-'}'),
      MapEntry('સરનામું / વતન (Address / Native)', '${s['address'] ?? ''} ${s['native_place'] ?? ''}'),
      MapEntry('જન્મ સ્થળ (Birth Place)', '${s['birth_place'] ?? '-'}'),
      MapEntry('છેલ્લી શાળા (Last School)', '${s['last_school'] ?? '-'}'),
      MapEntry('UID / Aadhaar', '${s['uid'] ?? '-'} (Aadhaar: ${s['has_aadhaar'] ?? '-'})'),
      MapEntry('PEN Number', '${s['pen'] ?? '-'}'),
      MapEntry('APAAR ID', '${s['apaar_id'] ?? '-'}'),
      MapEntry('Ration Card KYC', '${s['ration_card_kyc'] ?? '-'}'),
      MapEntry('Scholarship', '${s['scholarship_done'] ?? '-'} (${s['scholarship_reason'] ?? ''})'),
      if (_isAdmin) ...[
        MapEntry('Bank Name & Branch', '${s['bank_name'] ?? '-'} / ${s['bank_branch'] ?? '-'}'),
        MapEntry('Account No & IFSC', '${s['account_number'] ?? '-'} / ${s['ifsc_code'] ?? '-'}'),
        MapEntry('Name as per Passbook', '${s['name_as_passbook'] ?? '-'}'),
      ],
      MapEntry('હાજર દિવસો (Present Days)', '${s['present_days'] ?? '-'}'),
      if ('${s['leaving_date'] ?? ''}'.trim().isNotEmpty)
        MapEntry('શાળા છોડ્યા તારીખ (Leaving Date)', '${s['leaving_date']}'),
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('વિદ્યાર્થીની સંપૂર્ણ વિગત (Whole Data) — ${s['name'] ?? ''}'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in pairs)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 220,
                          child: Text(
                            e.key,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Expanded(child: SelectableText(e.value)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('બંધ કરો (Close)'),
          ),
        ],
      ),
    );
  }

  String _category(dynamic value) {
    final text = '${value ?? ''}'.toUpperCase();
    if (text == 'SC') return 'SC';
    if (text == 'ST') return 'ST';
    if (text == 'OBC') return 'OBC';
    return 'OTHER';
  }

  String get _effectiveSchoolType {
    final raw = (_resolvedSchoolType.isNotEmpty
            ? _resolvedSchoolType
            : widget.schoolType)
        .trim();
    return SchoolType.canonical(raw);
  }

  String _gender(dynamic value) {
    if (_effectiveSchoolType == 'boys') return 'BOYS';
    if (_effectiveSchoolType == 'girls') return 'GIRLS';
    final text = '${value ?? ''}'.toUpperCase();
    if (const <String>{'BOYS', 'BOY', 'MALE', 'M', 'KUMAR', 'કુમાર'}
        .contains(text)) {
      return 'BOYS';
    }
    if (const <String>{'GIRLS', 'GIRL', 'FEMALE', 'F', 'KANYA', 'કન્યા'}
        .contains(text)) {
      return 'GIRLS';
    }
    return 'UNSPECIFIED';
  }

  bool get _mixed => _service.isMixedSchool(_effectiveSchoolType);

  Future<void> _openEditor([Map<String, dynamic>? existing]) async {
    if (widget.readOnly || _saving) return;
    final row = existing == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(existing);
    final targetClassId = existing != null
        ? '${existing['class_id'] ?? _selectedClassId}'
        : (_selectedClassId == '__ALL__'
            ? (_classes.firstWhere(
                  (c) => _canManageClass('${c['id']}'),
                  orElse: () => _classes.isNotEmpty ? _classes.first : <String, dynamic>{},
                )['id']?.toString() ?? '')
            : _selectedClassId);
    if (!_canManageClass(targetClassId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'માત્ર જે-તે વર્ગના વર્ગ શિક્ષક (Class Teacher) અથવા School Admin જ આ વર્ગમાં નવો વિદ્યાર્થી ઉમેરી કે સુધારી શકે છે. વિષય શિક્ષક (Subject Teacher) વિદ્યાર્થી ઉમેરી શકતા નથી.',
          ),
        ),
      );
      return;
    }
    final controllers = <String, TextEditingController>{};
    const textKeys = <String>[
      'roll_number',
      'gr',
      'dd',
      'mm',
      'yyyy',
      'name',
      'religion',
      'religion_en',
      'caste',
      'enroll_school',
      'enroll_class',
      'mobile',
      'father_name',
      'mother_name',
      'address',
      'birth_place',
      'dob_words',
      'last_school',
      'enroll_sch_class',
      'enroll_sch_class_words',
      'name_en',
      'caste_en',
      'category_en',
      'mother_en',
      'birth_place_en',
      'dob_en',
      'last_school_en',
      'enroll_sch_class_en',
      'enroll_sch_class_words_en',
      'apaar_id',
      'present_days',
      'scholarship_reason',
      'uid',
      'pen',
      'bank_name',
      'bank_branch',
      'name_as_passbook',
      'account_number',
      'ifsc_code',
      'native_place',
      'native_place_en',
    ];
    for (final key in textKeys) {
      controllers[key] = TextEditingController(text: '${row[key] ?? ''}');
    }
    var category = _category(row['category']);
    String? gender = _gender(row['gender']);
    if (!_mixed &&
        (_effectiveSchoolType.toLowerCase() == 'boys' ||
            _effectiveSchoolType.toLowerCase() == 'girls')) {
      gender = _gender(row['gender']);
    }
    String normYesNo(dynamic v) {
      final s = '${v ?? ''}'.trim().toUpperCase();
      if (const <String>{'YES', 'Y', 'TRUE', '1', 'હા'}.contains(s) ||
          s.startsWith('YES') ||
          s.startsWith('હા')) {
        return 'YES';
      }
      return 'NO';
    }
    var hasAadhaar = normYesNo(row['has_aadhaar']);
    var rationCardKyc = normYesNo(row['ration_card_kyc']);
    var scholarshipDone = normYesNo(row['scholarship_done']);
    if (scholarshipDone == 'YES') {
      controllers['scholarship_reason']?.clear();
    }
    var formError = '';

    Widget field(String key, String label, {bool numeric = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: controllers[key],
            keyboardType: numeric ? TextInputType.number : TextInputType.text,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        );

    Widget grid(List<Widget> children) => LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final itemWidth = width < 520 ? width : (width - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 0,
              children: children
                  .map((child) => SizedBox(width: itemWidth, child: child))
                  .toList(),
            );
          },
        );

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            insetPadding: const EdgeInsets.all(16),
            title: Text(
              existing == null
                  ? 'નવો વિદ્યાર્થી ઉમેરો'
                  : 'વિદ્યાર્થીની વિગત સુધારો',
            ),
            content: SizedBox(
              width: 760,
              height: MediaQuery.of(dialogContext).size.height * 0.72,
              child: ListView(
                children: [
                  Text(
                    'વર્ગ: ${_classLabels[targetClassId] ?? _selectedClassLabel}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  ExpansionTile(
                    initiallyExpanded: true,
                    title: const Text('Basic Details / મૂળભૂત વિગતો'),
                    children: [
                      grid(<Widget>[
                        field(
                          'roll_number',
                          'Roll Number (optional; blank = next roll)',
                          numeric: true,
                        ),
                        field('gr', 'GR નંબર'),
                        field('dd', 'DD'),
                        field('mm', 'MM'),
                        field('yyyy', 'YYYY'),
                        field('name', 'વિદ્યાર્થીનું નામ *'),
                        field('religion', 'ધર્મ (Religion in Gujarati)'),
                        field('caste', 'પેટા જ્ઞાતિ'),
                      ]),
                      DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration: const InputDecoration(
                          labelText: 'કેટેગરી',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem(
                              value: 'SC', child: Text('અ. જા. / SC')),
                          DropdownMenuItem(
                              value: 'ST', child: Text('અ. જ. જા. / ST')),
                          DropdownMenuItem(
                              value: 'OBC', child: Text('બક્ષીપંચ / OBC')),
                          DropdownMenuItem(
                              value: 'OTHER', child: Text('અન્ય / OTHER')),
                        ],
                        onChanged: (value) =>
                            setDialogState(() => category = value ?? 'OTHER'),
                      ),
                      if (_mixed) ...[
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue:
                              (gender == 'BOYS' || gender == 'GIRLS')
                                  ? gender
                                  : null,
                          decoration: const InputDecoration(
                            labelText: 'જાતિ / Gender',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem(
                                value: 'BOYS', child: Text('કુમાર / BOYS')),
                            DropdownMenuItem(
                                value: 'GIRLS', child: Text('કન્યા / GIRLS')),
                          ],
                          onChanged: (value) =>
                              setDialogState(() => gender = value),
                        ),
                      ],
                      const SizedBox(height: 10),
                      grid(<Widget>[
                        field('enroll_school', 'શાળામાં દાખલ તારીખ'),
                        field('enroll_class', 'વર્ગમાં દાખલ તારીખ'),
                        field('mobile', 'મોબાઈલ નંબર', numeric: true),
                        field('father_name', 'પિતાનું નામ'),
                        field('mother_name', 'માતાનું નામ'),
                        field('birth_place', 'જન્મ સ્થળ'),
                        field('dob_words', 'જન્મ તારીખ શબ્દોમાં'),
                        field('last_school', 'પૂર્વ શાળાનું નામ'),
                        field('enroll_sch_class', 'શાળામાં દાખલ ધોરણ'),
                        field(
                          'enroll_sch_class_words',
                          'શાળામાં દાખલ ધોરણ શબ્દોમાં',
                        ),
                        field('address', 'સરનામું (optional)'),
                      ]),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text('English Details / અંગ્રેજી વિગતો'),
                    children: [
                      grid(<Widget>[
                        field('name_en', 'NAME IN ENGLISH'),
                        field('religion_en', 'RELIGION IN ENGLISH'),
                        field('caste_en', 'CASTE IN ENGLISH'),
                        field('category_en', 'CATEGORY IN ENG'),
                        field('mother_en', "MOTHER'S NAME IN ENGLISH"),
                        field('birth_place_en', 'BIRTH PLACE IN ENGLISH'),
                        field('dob_en', 'DOB IN ENGLISH WORDS'),
                        field('last_school_en', 'LAST SCHOOL IN ENGLISH'),
                        field('enroll_sch_class_en', 'ENROLL CLASS IN ENGLISH'),
                        field(
                          'enroll_sch_class_words_en',
                          'ENROLL CLASS IN ENGLISH WORDS',
                        ),
                      ]),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text('IDs / Scholarship / અન્ય વિગતો'),
                    children: [
                      grid(<Widget>[
                        field('apaar_id', 'APAAR ID'),
                        field('present_days', 'હાજર દિવસો (initial data)'),
                        field('uid', 'UID નંબર'),
                        field('pen', 'PEN નંબર'),
                        field('native_place', 'વતન'),
                        field('native_place_en', 'વતન (English)'),
                      ]),
                      const SizedBox(height: 6),
                      grid(<Widget>[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: DropdownButtonFormField<String>(
                            initialValue: hasAadhaar,
                            decoration: const InputDecoration(
                              labelText: 'આધાર કાર્ડ છે? (Has Student Aadhaar)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const <DropdownMenuItem<String>>[
                              DropdownMenuItem(value: 'YES', child: Text('YES (હા)')),
                              DropdownMenuItem(value: 'NO', child: Text('NO (ના)')),
                            ],
                            onChanged: (value) => setDialogState(() {
                              hasAadhaar = value ?? 'NO';
                            }),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: DropdownButtonFormField<String>(
                            initialValue: rationCardKyc,
                            decoration: const InputDecoration(
                              labelText: 'રેશન કાર્ડ KYC (Ration Card KYC)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const <DropdownMenuItem<String>>[
                              DropdownMenuItem(value: 'YES', child: Text('YES (હા)')),
                              DropdownMenuItem(value: 'NO', child: Text('NO (ના)')),
                            ],
                            onChanged: (value) => setDialogState(() {
                              rationCardKyc = value ?? 'NO';
                            }),
                          ),
                        ),
                      ]),
                      DropdownButtonFormField<String>(
                        initialValue: scholarshipDone,
                        decoration: const InputDecoration(
                          labelText: 'શિષ્યવૃત્તિ થઈ ગઈ છે? (Scholarship Done)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem(value: 'YES', child: Text('YES (હા — શિષ્યવૃત્તિ થયેલ)')),
                          DropdownMenuItem(value: 'NO', child: Text('NO (ના — શિષ્યવૃત્તિ બાકી)')),
                        ],
                        onChanged: (value) => setDialogState(() {
                          scholarshipDone = value ?? 'NO';
                          if (scholarshipDone == 'YES') {
                            controllers['scholarship_reason']!.clear();
                          }
                        }),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
                          controller: controllers['scholarship_reason'],
                          enabled: scholarshipDone == 'NO',
                          readOnly: scholarshipDone == 'YES',
                          decoration: InputDecoration(
                            labelText: scholarshipDone == 'YES'
                                ? 'શિષ્યવૃત્તિ કારણ (Scholarship YES હોવાથી બંધ છે)'
                                : 'શિષ્યવૃત્તિ બાકી હોવાનું કારણ (Reason why Scholarship is NO) *',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            filled: scholarshipDone == 'YES',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_isAdmin)
                    ExpansionTile(
                      title: const Text('Bank Details / બેંક વિગતો (Admin only)'),
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Bank details are restricted to the School Admin. Aadhaar and Ration Card fields are no longer collected.',
                          ),
                        ),
                        grid(<Widget>[
                          field('bank_name', 'બેંકનું નામ'),
                          field('bank_branch', 'બેંક બ્રાન્ચ'),
                          field('name_as_passbook', 'પાસબુક મુજબ નામ'),
                          field('account_number', 'એકાઉન્ટ નંબર', numeric: true),
                          field('ifsc_code', 'IFSC કોડ'),
                        ]),
                      ],
                    ),
                  if (formError.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        formError,
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () {
                  if ((controllers['name']?.text ?? '').trim().isEmpty) {
                    setDialogState(
                        () => formError = 'Student name is required.');
                    return;
                  }
                  if (_mixed &&
                      !const <String>{'BOYS', 'GIRLS'}.contains(gender)) {
                    setDialogState(() =>
                        formError = 'Select BOYS or GIRLS for a mixed school.');
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Student'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true && mounted) {
      setState(() {
        _saving = true;
        _error = null;
      });
      try {
        final values = <String, dynamic>{
          for (final entry in controllers.entries)
            entry.key: entry.value.text.trim(),
          'category': category,
          'gender': gender ?? 'UNSPECIFIED',
          'has_aadhaar': hasAadhaar,
          'ration_card_kyc': rationCardKyc,
          'scholarship_done': scholarshipDone,
          'scholarship_reason': scholarshipDone == 'YES'
              ? ''
              : (controllers['scholarship_reason']?.text ?? '').trim(),
        };
        await _service.saveStudent(
          classId: targetClassId,
          schoolType: _effectiveSchoolType,
          values: values,
          studentId: existing == null ? null : '${existing['id']}',
        );
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                existing == null
                    ? 'Student added successfully.'
                    : 'Student updated successfully.',
              ),
            ),
          );
        }
      } catch (error) {
        if (mounted) {
          setState(() {
            _error = '$error'.replaceFirst('Exception: ', '');
            _saving = false;
          });
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  Future<void> _exportWholeSchoolExcel() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final bundle = await SchoolExportService().exportForCurrentUser(
        includePrivateDetails: _isAdmin,
      );
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile.fromData(
              bundle.bytes,
              mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              name: bundle.fileName,
            ),
          ],
          text: bundle.fileName,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ડાઉનલોડ પૂર્ણ: ${bundle.fileName}')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reRollSelectedClass() async {
    if (widget.readOnly || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      if (_selectedClassId == '__ALL__' || _selectedClassId.isEmpty) {
        for (final c in _classes) {
          final cid = '${c['id'] ?? ''}'.trim();
          if (cid.isNotEmpty) {
            await client.rpc(
              'psm_renumber_class_rolls',
              params: <String, dynamic>{'p_class_id': cid},
            );
          }
        }
      } else {
        await client.rpc(
          'psm_renumber_class_rolls',
          params: <String, dynamic>{'p_class_id': _selectedClassId},
        );
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('રોલ નંબર 1 થી સળંગ ગોઠવાઈ ગયા છે (Re-Roll 1..N Complete).'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _archiveStudent(Map<String, dynamic> student) async {
    if (widget.readOnly || _saving) return;
    final targetId = '${student['id'] ?? ''}'.trim();
    if (targetId.isEmpty) return;
    final stClassId = '${student['class_id'] ?? _selectedClassId}'.trim();
    if (!_canManageClass(stClassId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'માત્ર જે-તે વર્ગના વર્ગ શિક્ષક (Class Teacher) અથવા School Admin જ વિદ્યાર્થીને નિષ્ક્રિય (Deactive) કરી શકે છે. વિષય શિક્ષક (Subject Teacher) Deactive કરી શકતા નથી.',
          ),
        ),
      );
      return;
    }
    var selectedDate = DateTime.now();
    var selectedReason = 'lc';
    final accepted = await showDialog<bool>(
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
                  'શું તમે "${student['name'] ?? 'આ વિદ્યાર્થી'}" ને નિષ્ક્રિય (Deactive) કરવા માંગો છો? માત્ર આ ૧ જ વિદ્યાર્થી Deactive થશે અને રેકોર્ડ સુરક્ષિત રહેશે.',
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000, 1, 1),
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
    if (accepted != true || !mounted) return;
    final leavingIso =
        '${selectedDate.year.toString().padLeft(4, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.archiveStudent(
        classId: '${student['class_id'] ?? _selectedClassId}',
        studentId: '${student['id']}',
        leavingDate: leavingIso,
        exitReason: selectedReason,
      );
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filteredStudents;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Students — $_selectedClassLabel (${visible.length})',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_canManageClass(_selectedClassId))
            IconButton(
              tooltip: 'Bulk Upload / Whole-School Upload',
              onPressed: _saving
                  ? null
                  : () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => StudentBulkImportScreen(
                            classId: _selectedClassId == '__ALL__'
                                ? ''
                                : _selectedClassId,
                            classLabel: _selectedClassLabel,
                            schoolType: _effectiveSchoolType,
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
              tooltip: 'Active / Deactive Students ($_archivedCount)',
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ArchivedStudentsScreen(
                      schoolRef: _schoolRef!,
                      classId:
                          _selectedClassId == '__ALL__' ? '' : _selectedClassId,
                      classLabel: _selectedClassLabel,
                      readOnly: widget.readOnly,
                    ),
                  ),
                );
                if (mounted) await _load();
              },
              icon: Badge(
                isLabelVisible: _archivedCount > 0,
                label: Text('$_archivedCount'),
                child: const Icon(Icons.archive_outlined),
              ),
            ),
          IconButton(
            tooltip: 'Download Whole School Data (Excel)',
            onPressed: _saving ? null : _exportWholeSchoolExcel,
            icon: const Icon(Icons.sim_card_download_outlined),
          ),
          if (_canManageClass(_selectedClassId) && visible.isNotEmpty)
            IconButton(
              tooltip: 'Re-Roll Numbers (1..N)',
              onPressed: _saving ? null : _reRollSelectedClass,
              icon: const Icon(Icons.format_list_numbered),
            ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          if (_canManageClass(_selectedClassId))
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _saving ? null : () => _openEditor(),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Add Student'),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_archivedCount > 0 && _schoolRef != null)
                  Container(
                    width: double.infinity,
                    color: Colors.amber.shade100,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Text(
                          'આ વર્ગ/શાળામાં $_archivedCount વિદ્યાર્થીઓ નિષ્ક્રિય (Deactive) સ્થિતિમાં છે.',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ArchivedStudentsScreen(
                                  schoolRef: _schoolRef!,
                                  classId: _selectedClassId == '__ALL__'
                                      ? ''
                                      : _selectedClassId,
                                  classLabel: _selectedClassLabel,
                                  readOnly: widget.readOnly,
                                ),
                              ),
                            );
                            if (mounted) await _load();
                          },
                          icon: const Icon(Icons.restore),
                          label: const Text('Active / Deactive જુઓ (વર્ગ પસંદ કરી સક્રિય કરો)'),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                  child: Row(
                    children: [
                      if (_classes.isNotEmpty) ...[
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedClassId == '__ALL__' ||
                                    _classes.any(
                                      (c) => '${c['id']}' == _selectedClassId,
                                    )
                                ? _selectedClassId
                                : '__ALL__',
                            decoration: const InputDecoration(
                              labelText: 'વર્ગ (Class)',
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
                                _selectedClassId = v;
                                _selectedClassLabel = v == '__ALL__'
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
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: _isAdmin
                                ? 'Admin Search: GR, Roll, કે નામનો કોઈપણ ભાગ (અટક / નામ / પિતાનું નામ) — Promoted સહિત'
                                : 'Search by GR, Roll, Surname, Name, Father Name, or Mobile',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: _search.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _search.clear();
                                      setState(() {});
                                    },
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isAdmin)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FilterChip(
                        selected: _includePromotedAndArchived,
                        onSelected: (v) =>
                            setState(() => _includePromotedAndArchived = v),
                        avatar: const Icon(Icons.manage_search, size: 18),
                        label: const Text(
                          'Admin: બઢતી પામેલ (ધોરણ 8 -> 9 કમી સહિત) અને નિષ્ક્રિય વિદ્યાર્થીઓ પણ બતાવો (Show Whole School History)',
                        ),
                      ),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    child: Text(
                      _error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                Expanded(
                  child: visible.isEmpty
                      ? const Center(
                          child: Text('No active students in this selection.'),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final student = visible[index];
                            final classTag = _selectedClassId == '__ALL__'
                                ? ' [${_classLabels['${student['class_id']}'] ?? ''}]'
                                : '';
                            final religionTag =
                                '${student['religion'] ?? ''}'.trim().isNotEmpty
                                    ? ' • ધર્મ: ${student['religion']}'
                                    : '';
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text(
                                    '${student['roll_number'] ?? index + 1}',
                                  ),
                                ),
                                title: Text(
                                  '${student['name'] ?? ''}$classTag',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                                subtitle: Text(
                                  'GR: ${student['gr'] ?? '-'} • Category: ${_category(student['category'])} • Gender: ${_gender(student['gender'])}$religionTag • Mobile: ${student['mobile'] ?? '-'}',
                                ),
                                trailing: Wrap(
                                  spacing: 4,
                                  children: [
                                    if (_isAdmin)
                                      IconButton(
                                        tooltip: 'સંપૂર્ણ ડેટા જુઓ (Whole Student Data)',
                                        onPressed: () =>
                                            _showStudentWholeDataDialog(student),
                                        icon: const Icon(Icons.visibility_outlined),
                                      ),
                                    if (_canManageClass('${student['class_id'] ?? ''}')) ...[
                                      IconButton(
                                        tooltip: 'Edit',
                                        onPressed: () => _openEditor(student),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: 'Deactive / નિષ્ક્રિય કરો (માત્ર વર્ગ શિક્ષક / Admin)',
                                        onPressed: () =>
                                            _archiveStudent(student),
                                        icon: const Icon(
                                            Icons.person_off_outlined),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

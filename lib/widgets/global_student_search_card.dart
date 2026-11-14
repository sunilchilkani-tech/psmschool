import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import '../screens/archived_students_screen.dart';
import '../services/school_class_order.dart';
import '../services/school_type.dart';

/// Opens a full-screen/modal Global Student Search dialog from any screen.
Future<void> showGlobalStudentSearchDialog(
  BuildContext context, {
  bool readOnly = false,
  VoidCallback? onDataChanged,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 820),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[Color(0xFF0F2942), Color(0xFF1E3A5F)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_search_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Global Student Search / વિદ્યાર્થી ગ્લોબલ સર્ચ અને સુધારા',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: GlobalStudentSearchCard(
                  readOnly: readOnly,
                  initiallyExpanded: true,
                  showAllWhenEmptyQuery: true,
                  onDataChanged: onDataChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Global Student Search Card for all Home Screens:
/// - Admin: searches across the WHOLE SCHOOL (all classes automatically without
///   requiring class selection) by Student Name, GR Number, Mobile Number,
///   Father's Name, Mother's Name (plus Roll No, English Name, UID, PEN).
/// - Teacher: searches across their ALLOTTED classes automatically.
/// - Supports direct full editing of any student after search, single student
///   deactivation/reactivation, and "Make Deactivated All" (bulk deactivate).
class GlobalStudentSearchCard extends StatefulWidget {
  const GlobalStudentSearchCard({
    super.key,
    this.readOnly = false,
    this.initiallyExpanded = false,
    this.showAllWhenEmptyQuery = false,
    this.onDataChanged,
  });

  final bool readOnly;
  final bool initiallyExpanded;
  final bool showAllWhenEmptyQuery;
  final VoidCallback? onDataChanged;

  @override
  State<GlobalStudentSearchCard> createState() =>
      _GlobalStudentSearchCardState();
}

const List<Map<String, String>> _kGlobalStudentFields = <Map<String, String>>[
  {'key': 'roll_number', 'label': 'Roll Number (રોલ નંબર)'},
  {'key': 'gr', 'label': 'GR નંબર (GR Number)'},
  {'key': 'dd', 'label': 'DD (જન્મ તારીખ)'},
  {'key': 'mm', 'label': 'MM (જન્મ માસ)'},
  {'key': 'yyyy', 'label': 'YYYY (જન્મ વર્ષ)'},
  {'key': 'name', 'label': 'વિદ્યાર્થીનું નામ (Student Name)'},
  {'key': 'father_name', 'label': 'પિતાનું નામ (Father\'s Name)'},
  {'key': 'mother_name', 'label': 'માતાનું નામ (Mother\'s Name)'},
  {'key': 'mobile', 'label': 'મોબાઈલ નંબર (Mobile Number)'},
  {'key': 'religion', 'label': 'ધર્મ / Religion (Gujarati)'},
  {'key': 'caste', 'label': 'પેટા જ્ઞાતિ (Caste)'},
  {'key': 'category', 'label': 'કેટેગરી (Category)'},
  {'key': 'gender', 'label': 'લિંગ / Gender'},
  {'key': 'enroll_school', 'label': 'શાળા પ્રવેશ તારીખ'},
  {'key': 'enroll_class', 'label': 'વર્ગ પ્રવેશ તારીખ'},
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
  {'key': 'has_aadhaar', 'label': 'આધાર કાર્ડ છે? (YES/NO)'},
  {'key': 'ration_card_kyc', 'label': 'રેશન કાર્ડ KYC (YES/NO)'},
  {'key': 'scholarship_done', 'label': 'શિષ્યવૃત્તિ થઈ ગઈ છે? (YES/NO)'},
  {'key': 'scholarship_reason', 'label': 'શિષ્યવૃત્તિ બાકી હોવાનું કારણ'},
  {'key': 'scholarship_other', 'label': 'શિષ્યવૃત્તિ અન્ય વિગતો'},
  {'key': 'uid', 'label': 'UID નંબર'},
  {'key': 'pen', 'label': 'PEN નંબર'},
  {'key': 'is_divyang', 'label': 'દિવ્યાંગ વિદ્યાર્થી? (હા / ના)'},
];

const List<Map<String, String>> _kGlobalPrivateFields = <Map<String, String>>[
  {'key': 'bank_name', 'label': 'બેંકનું નામ (Bank Name)'},
  {'key': 'bank_branch', 'label': 'બેંક બ્રાન્ચ (Bank Branch)'},
  {'key': 'name_as_passbook', 'label': 'પાસબુક મુજબ નામ'},
  {'key': 'account_number', 'label': 'એકાઉન્ટ નંબર (Account No)'},
  {'key': 'ifsc_code', 'label': 'IFSC કોડ'},
];

class _GlobalStudentSearchCardState extends State<GlobalStudentSearchCard> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  String? _schoolRef;
  String _schoolType = 'coed';
  bool _isAdmin = false;

  List<Map<String, dynamic>> _accessibleClasses = <Map<String, dynamic>>[];
  Map<String, String> _classLabels = <String, String>{};
  List<Map<String, dynamic>> _allScopedStudents = <Map<String, dynamic>>[];
  List<String> _customHeaders = <String>[];

  String _selectedClassFilter = '__ALL__';
  bool _includeDeactive = false;
  bool _showListWhenEmpty = false;
  final Set<String> _selectedStudentIds = <String>{};

  @override
  void initState() {
    super.initState();
    _showListWhenEmpty =
        widget.showAllWhenEmptyQuery || widget.initiallyExpanded;
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _text(dynamic value) => (value ?? '').toString().trim();

  String _cleanError(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('PostgrestException(message: ', 'Database error: ');

  static String _normalizeDigitsAndLower(String input) {
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    final sb = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      final idx = guj.indexOf(ch);
      if (idx >= 0) {
        sb.write(idx);
      } else {
        sb.write(ch);
      }
    }
    return sb.toString();
  }

  bool _isStudentActive(Map<String, dynamic> s) {
    return s['is_active'] == true &&
        _text(s['leaving_date']).isEmpty &&
        _text(s['exit_date']).isEmpty;
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_client.auth.currentUser == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Please sign in to search students.';
        });
        return;
      }
      final ref = _text(await _client.rpc('current_school_ref'));
      if (ref.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'No active school linked to this account.';
        });
        return;
      }

      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        _client.rpc('is_school_admin'),
        _client.rpc('psm_attendance_class_ids'),
        _client
            .from('school_classes')
            .select(
              'id,school_ref,class_key,label,sheet_name,standard,section,report_group,sort_order,is_active',
            )
            .eq('school_ref', ref)
            .eq('is_active', true)
            .order('sort_order'),
        _client.from('students').select('*').eq('school_ref', ref),
        _client
            .from('schools')
            .select('school_type')
            .eq('id', ref)
            .maybeSingle(),
      ]);

      final isAdmin = results[0] == true;
      final rawAllowedIds = results[1];
      final rawClasses = results[2] as List;
      final rawStudents = results[3] as List;
      final schoolRow = results[4];

      final allClasses = SchoolClassOrder.sorted(
        rawClasses.map((r) => Map<String, dynamic>.from(r as Map)),
      );
      final labels = <String, String>{
        for (final c in allClasses)
          _text(c['id']): _text(c['label']).isNotEmpty
              ? _text(c['label'])
              : _text(c['class_key']),
      };

      List<Map<String, dynamic>> accessibleClasses;
      Set<String> allowedClassIdSet;
      if (isAdmin || rawAllowedIds == null) {
        accessibleClasses = allClasses;
        allowedClassIdSet = allClasses.map((c) => _text(c['id'])).toSet();
      } else if (rawAllowedIds is List) {
        final set = rawAllowedIds.map((e) => _text(e)).toSet();
        accessibleClasses =
            allClasses.where((c) => set.contains(_text(c['id']))).toList();
        allowedClassIdSet = set;
      } else {
        accessibleClasses = allClasses;
        allowedClassIdSet = allClasses.map((c) => _text(c['id'])).toSet();
      }

      final scopedStudents = <Map<String, dynamic>>[];
      for (final r in rawStudents) {
        if (r is! Map) continue;
        final m = Map<String, dynamic>.from(r);
        final cid = _text(m['class_id']);
        if (!isAdmin && !allowedClassIdSet.contains(cid)) {
          continue;
        }
        scopedStudents.add(m);
      }

      scopedStudents.sort((a, b) {
        final ca = labels[_text(a['class_id'])] ?? '';
        final cb = labels[_text(b['class_id'])] ?? '';
        final cCmp = ca.compareTo(cb);
        if (cCmp != 0) return cCmp;
        final ra = int.tryParse(_text(a['roll_number'])) ?? 999999;
        final rb = int.tryParse(_text(b['roll_number'])) ?? 999999;
        if (ra != rb) return ra.compareTo(rb);
        return _text(a['name']).compareTo(_text(b['name']));
      });

      var headers = <String>[];
      try {
        final headerRow = await _client
            .from('school_custom_headers')
            .select('headers')
            .eq('school_ref', ref)
            .maybeSingle();
        final rawHeaders = headerRow?['headers'];
        if (rawHeaders is List) {
          headers = rawHeaders.map((v) => _text(v)).toList();
        }
      } catch (_) {}
      if (headers.isEmpty || headers.every((v) => v.isEmpty)) {
        headers = List<String>.generate(11, (i) => 'Custom ${i + 1}');
      }

      final regType = schoolRow is Map ? _text(schoolRow['school_type']) : '';

      if (!mounted) return;
      setState(() {
        _schoolRef = ref;
        _isAdmin = isAdmin;
        _schoolType = SchoolType.coedCompat(regType);
        _accessibleClasses = accessibleClasses;
        _classLabels = labels;
        _allScopedStudents = scopedStudents;
        _customHeaders = headers;
        if (_selectedClassFilter != '__ALL__' &&
            !accessibleClasses
                .any((c) => _text(c['id']) == _selectedClassFilter)) {
          _selectedClassFilter = '__ALL__';
        }
        _selectedStudentIds.removeWhere(
          (id) => !scopedStudents.any((s) => _text(s['id']) == id),
        );
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

  List<Map<String, dynamic>> get _filteredStudents {
    final query = _normalizeDigitsAndLower(_searchCtrl.text.trim());
    final tokens = query
        .split(RegExp(r'\s+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    return _allScopedStudents.where((s) {
      final isAct = _isStudentActive(s);
      if (!_includeDeactive && !isAct) return false;
      if (_selectedClassFilter != '__ALL__' &&
          _text(s['class_id']) != _selectedClassFilter) {
        return false;
      }
      if (tokens.isEmpty) return true;

      final classLbl = _classLabels[_text(s['class_id'])] ?? '';
      final searchable = _normalizeDigitsAndLower(<String>[
        _text(s['name']),
        _text(s['name_en']),
        _text(s['gr']),
        _text(s['mobile']),
        _text(s['father_name']),
        _text(s['mother_name']),
        _text(s['mother_en']),
        _text(s['roll_number']),
        _text(s['previous_roll_number']),
        _text(s['uid']),
        _text(s['pen']),
        _text(s['apaar_id']),
        _text(s['caste']),
        _text(s['category']),
        classLbl,
      ].join(' '));

      return tokens.every((tok) => searchable.contains(tok));
    }).toList();
  }

  int get _activeCountInScope =>
      _allScopedStudents.where(_isStudentActive).length;

  int get _deactiveCountInScope =>
      _allScopedStudents.where((s) => !_isStudentActive(s)).length;

  Future<void> _openStudentEditor(Map<String, dynamic> student) async {
    if (widget.readOnly || _saving || _schoolRef == null) return;
    final schoolRef = _schoolRef!;

    Map<String, dynamic> privateDetails = <String, dynamic>{};
    if (_isAdmin) {
      try {
        final raw = await _client
            .from('student_private_details')
            .select(
              'student_id,school_ref,bank_name,bank_branch,name_as_passbook,account_number,ifsc_code',
            )
            .eq('school_ref', schoolRef)
            .eq('student_id', _text(student['id']))
            .maybeSingle();
        if (raw != null) {
          privateDetails = Map<String, dynamic>.from(raw);
        }
      } catch (_) {}
    }

    if (!mounted) return;
    final currentClassId = _text(student['class_id']);
    final currentClassLabel =
        _classLabels[currentClassId] ?? 'સમગ્ર શાળા (All Classes)';

    final result = await showDialog<_GlobalStudentFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _GlobalStudentEditorDialog(
        classId: currentClassId,
        classLabel: currentClassLabel,
        availableClasses: _accessibleClasses,
        schoolType: _schoolType,
        student: student,
        privateDetails: privateDetails,
        customHeaders: _customHeaders,
        isAdmin: _isAdmin,
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final studentId = _text(student['id']);
      final targetClassId = result.selectedClassId.trim().isNotEmpty
          ? result.selectedClassId.trim()
          : currentClassId;

      if (_isAdmin &&
          targetClassId.isNotEmpty &&
          targetClassId != currentClassId) {
        await _client.rpc(
          'psm_move_student_to_class_section',
          params: <String, dynamic>{
            'p_student_id': studentId,
            'p_to_class_id': targetClassId,
          },
        );
      }

      await _client.rpc(
        'psm_update_student_profile_with_roll_shift',
        params: <String, dynamic>{
          'p_student_id': studentId,
          'p_student_values': result.studentValues,
          'p_custom_fields': result.customValues,
        },
      );

      if (_isAdmin) {
        await _client
            .from('students')
            .update(<String, dynamic>{
              'is_divyang': result.studentValues['is_divyang'] == true,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', studentId)
            .eq('school_ref', schoolRef);

        final privatePayload = <String, dynamic>{
          ...result.privateValues,
          'student_id': studentId,
          'school_ref': schoolRef,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
        await _client.from('student_private_details').upsert(
              privatePayload,
              onConflict: 'student_id',
            );
      }

      FirestoreQueryBuilder.invalidateCache('students');
      await _loadData();
      widget.onDataChanged?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'વિદ્યાર્થી "${_text(result.studentValues['name'])}" ની માહિતી સફળતાપૂર્વક સુધારાઈ ગઈ છે.',
          ),
          backgroundColor: const Color(0xFF087F5B),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showStudentWholeDataDialog(Map<String, dynamic> s) {
    final isAct = _isStudentActive(s);
    final classLbl = _classLabels[_text(s['class_id'])] ?? '-';
    final rows = <MapEntry<String, String>>[
      MapEntry('સ્થિતિ (Status)', isAct ? 'Active (સક્રિય)' : 'Deactive (નિષ્ક્રિય)'),
      MapEntry('વર્ગ (Class)', classLbl),
      MapEntry('Roll Number', _text(s['roll_number'])),
      MapEntry('GR નંબર', _text(s['gr'])),
      MapEntry('વિદ્યાર્થીનું નામ', _text(s['name'])),
      MapEntry('NAME IN ENGLISH', _text(s['name_en'])),
      MapEntry('પિતાનું નામ (Father\'s Name)', _text(s['father_name'])),
      MapEntry('માતાનું નામ (Mother\'s Name)', _text(s['mother_name'])),
      MapEntry('MOTHER IN ENGLISH', _text(s['mother_en'])),
      MapEntry('મોબાઈલ નંબર (Mobile)', _text(s['mobile'])),
      MapEntry(
        'જન્મ તારીખ (DD/MM/YYYY)',
        '${_text(s['dd'])}/${_text(s['mm'])}/${_text(s['yyyy'])}',
      ),
      MapEntry('લિંગ (Gender)', _text(s['gender'])),
      MapEntry('ધર્મ (Religion)', _text(s['religion'])),
      MapEntry('જ્ઞાતિ (Caste)', _text(s['caste'])),
      MapEntry('કેટેગરી (Category)', _text(s['category'])),
      MapEntry('સરનામું (Address)', _text(s['address'])),
      MapEntry('જન્મ સ્થળ', _text(s['birth_place'])),
      MapEntry('વતન', _text(s['native_place'])),
      MapEntry('પૂર્વ શાળા', _text(s['last_school'])),
      MapEntry('શાળા પ્રવેશ તારીખ', _text(s['enroll_school'])),
      MapEntry('વર્ગ પ્રવેશ તારીખ', _text(s['enroll_class'])),
      MapEntry('UID નંબર', _text(s['uid'])),
      MapEntry('PEN નંબર', _text(s['pen'])),
      MapEntry('APAAR ID', _text(s['apaar_id'])),
      MapEntry('હાજર દિવસો', _text(s['present_days'])),
    ];

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_text(s['name'])} — સંપૂર્ણ માહિતી'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rows
                  .where((e) =>
                      e.value.trim().isNotEmpty && e.value.trim() != '//')
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 190,
                            child: Text(
                              '${e.key}:',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF334155),
                              ),
                            ),
                          ),
                          Expanded(
                            child: SelectableText(
                              e.value,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        actions: [
          if (!widget.readOnly)
            FilledButton.tonalIcon(
              onPressed: () {
                Navigator.of(ctx).pop();
                _openStudentEditor(s);
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit / સુધારો'),
            ),
          TextButton.icon(
            onPressed: () {
              final text = rows
                  .where((e) =>
                      e.value.trim().isNotEmpty && e.value.trim() != '//')
                  .map((e) => '${e.key}: ${e.value}')
                  .join('\n');
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('વિદ્યાર્થીની માહિતી કોપી થઈ ગઈ.')),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _deactivateSingleStudent(Map<String, dynamic> student) async {
    if (widget.readOnly || _saving) return;
    final targetId = _text(student['id']);
    if (targetId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Deactivate Student? / વિદ્યાર્થીને નિષ્ક્રિય (Deactive) કરો',
        ),
        content: Text(
          'શું તમે "${_text(student['name'])}" (GR: ${_text(student['gr']).isEmpty ? '-' : _text(student['gr'])}) ને નિષ્ક્રિય (Deactive) કરવા માંગો છો?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel / રદ કરો'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Deactivate / નિષ્ક્રિય કરો'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _client.rpc(
        'psm_archive_student_and_shift_rolls',
        params: <String, dynamic>{
          'p_student_id': targetId,
          'p_exit_reason': 'deactive',
        },
      );
      _selectedStudentIds.remove(targetId);
      FirestoreQueryBuilder.invalidateCache('students');
      await _loadData();
      widget.onDataChanged?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '"${_text(student['name'])}" ને નિષ્ક્રિય (Deactive) કરવામાં આવ્યા છે.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reactivateSingleStudent(Map<String, dynamic> student) async {
    if (widget.readOnly || _saving || _schoolRef == null) return;
    final targetId = _text(student['id']);
    if (targetId.isEmpty) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _client.rpc(
        'psm_restore_disappeared_or_archived_students',
        params: <String, dynamic>{
          'p_school_ref': _schoolRef!,
          'p_student_ids': <String>[targetId],
          if (_text(student['class_id']).isNotEmpty)
            'p_target_class_id': _text(student['class_id']),
        },
      );
      FirestoreQueryBuilder.invalidateCache('students');
      await _loadData();
      widget.onDataChanged?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '"${_text(student['name'])}" ને પાછા સક્રિય (Active) કરવામાં આવ્યા છે.',
          ),
          backgroundColor: const Color(0xFF087F5B),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Bulk Deactivate ("Make Deactivated All"):
  /// Deactivates either the checked students, all currently searched/filtered
  /// active students, or all active students in the current scope.
  Future<void> _makeDeactivatedAll() async {
    if (widget.readOnly || _saving) return;

    final filteredActive =
        _filteredStudents.where(_isStudentActive).toList();
    final selectedActive = filteredActive
        .where((s) => _selectedStudentIds.contains(_text(s['id'])))
        .toList();
    final allScopeActive =
        _allScopedStudents.where(_isStudentActive).toList();

    final targets = selectedActive.isNotEmpty
        ? selectedActive
        : (filteredActive.isNotEmpty ? filteredActive : allScopeActive);

    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('નિષ્ક્રિય કરવા માટે કોઈ સક્રિય (Active) વિદ્યાર્થી મળ્યા નથી.'),
        ),
      );
      return;
    }

    final scopeDesc = selectedActive.isNotEmpty
        ? 'પસંદ કરેલા ${selectedActive.length} વિદ્યાર્થીઓ (Selected Students)'
        : (_searchCtrl.text.trim().isNotEmpty ||
                _selectedClassFilter != '__ALL__'
            ? 'સર્ચ/ફિલ્ટર થયેલા ${targets.length} વિદ્યાર્થીઓ (Filtered Active Students)'
            : (_isAdmin
                ? 'સમગ્ર શાળાના બધા ${targets.length} સક્રિય વિદ્યાર્થીઓ (Whole School Active Students)'
                : 'તમારા ફાળવેલ વર્ગના બધા ${targets.length} સક્રિય વિદ્યાર્થીઓ (Allotted Class Active Students)'));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.person_off_rounded, color: Colors.red.shade700),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Make Deactivated All / બધા વિદ્યાર્થીઓને નિષ્ક્રિય (Deactive) કરો',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Text(
          'શું તમે ખરેખર $scopeDesc ને એકસાથે નિષ્ક્રિય (Deactive) કરવા માંગો છો?\n\n'
          '• કુલ ${targets.length} વિદ્યાર્થીઓ Deactive યાદીમાં જશે.\n'
          '• તેમનો ડેટા સુરક્ષિત રહેશે અને ગમે ત્યારે પાછા Active કરી શકાશે.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel / રદ કરો'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.person_off_outlined),
            label: Text(
              'Yes, Make Deactivated All (${targets.length})',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      for (final student in targets) {
        final sid = _text(student['id']);
        if (sid.isEmpty) continue;
        await _client.rpc(
          'psm_archive_student_and_shift_rolls',
          params: <String, dynamic>{
            'p_student_id': sid,
            'p_exit_reason': 'deactive',
          },
        );
      }
      _selectedStudentIds.clear();
      FirestoreQueryBuilder.invalidateCache('students');
      await _loadData();
      widget.onDataChanged?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'કુલ ${targets.length} વિદ્યાર્થીઓને સફળતાપૂર્વક નિષ્ક્રિય (Deactive) કરવામાં આવ્યા છે.',
          ),
          backgroundColor: Colors.orange.shade900,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final queryNotEmpty = _searchCtrl.text.trim().isNotEmpty;
    final visible = _filteredStudents;
    final showResultsSection =
        queryNotEmpty || _showListWhenEmpty || _selectedClassFilter != '__ALL__';
    final activeVisible = visible.where(_isStudentActive).toList();

    final allottedClassNames = _accessibleClasses
        .map((c) => _classLabels[_text(c['id'])] ?? _text(c['label']))
        .where((s) => s.isNotEmpty)
        .join(', ');

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFBFDBFE), width: 1.4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDBEAFE),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.person_search_rounded,
                        color: Color(0xFF1D4ED8),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isAdmin
                                ? 'Global Student Search — સમગ્ર શાળા (All Classes • Whole School)'
                                : 'Global Student Search — ફાળવેલ વર્ગ (Allotted Class)',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F2942),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isAdmin
                                ? 'Admin: વર્ગ પસંદ કર્યા વિના સમગ્ર શાળામાંથી નામ, GR નંબર, મોબાઈલ, પિતાનું નામ કે માતાના નામથી શોધો, સુધારો કરો અથવા બધાને Deactive કરો'
                                : 'Teacher (${allottedClassNames.isEmpty ? "No Class" : allottedClassNames}): તમારા ફાળવેલ વર્ગમાંથી નામ, GR, મોબાઈલ, પિતા કે માતાના નામથી શોધો અને સુધારો કરો',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Text(
                        'Active: $_activeCountInScope  •  Deactive: $_deactiveCountInScope',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF065F46),
                        ),
                      ),
                    ),
                    if (!widget.readOnly && _activeCountInScope > 0)
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFEE2E2),
                          foregroundColor: const Color(0xFFB91C1C),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _saving ? null : _makeDeactivatedAll,
                        icon: const Icon(Icons.person_off_outlined, size: 17),
                        label: Text(
                          _selectedStudentIds.isNotEmpty
                              ? 'Make Deactivated Selected (${_selectedStudentIds.length})'
                              : (queryNotEmpty ||
                                      _selectedClassFilter != '__ALL__'
                                  ? 'Make Deactivated All (${activeVisible.length})'
                                  : 'Make Deactivated All ($_activeCountInScope)'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (_schoolRef != null)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ArchivedStudentsScreen(
                                schoolRef: _schoolRef!,
                                classId: _selectedClassFilter == '__ALL__'
                                    ? ''
                                    : _selectedClassFilter,
                                classLabel: _selectedClassFilter == '__ALL__'
                                    ? 'સમગ્ર શાળા (All Classes)'
                                    : (_classLabels[_selectedClassFilter] ??
                                        'Class'),
                                readOnly: widget.readOnly,
                              ),
                            ),
                          );
                          if (mounted) await _loadData();
                          widget.onDataChanged?.call();
                        },
                        icon: const Icon(Icons.archive_outlined, size: 17),
                        label: Text('Deactive યાદી ($_deactiveCountInScope)'),
                      ),
                    IconButton(
                      tooltip: 'Refresh Student Data',
                      visualDensity: VisualDensity.compact,
                      onPressed: _loading ? null : _loadData,
                      icon: const Icon(Icons.refresh, size: 20),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Color(0xFF1D4ED8),
                      ),
                      hintText: _isAdmin
                          ? 'નામ (Name), GR નંબર, મોબાઈલ નંબર, પિતાનું નામ (Father Name), કે માતાનું નામ (Mother Name) લખો...'
                          : 'નામ, GR નંબર, મોબાઈલ નંબર, પિતાનું નામ, કે માતાનું નામ લખો...',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (queryNotEmpty)
                            IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {});
                              },
                            ),
                          TextButton.icon(
                            onPressed: () => setState(
                              () => _showListWhenEmpty = !_showListWhenEmpty,
                            ),
                            icon: Icon(
                              _showListWhenEmpty
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 18,
                            ),
                            label: Text(
                              _showListWhenEmpty ? 'Hide List' : 'Show All',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_accessibleClasses.length > 1) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _selectedClassFilter,
                      decoration: InputDecoration(
                        labelText: _isAdmin
                            ? 'Scope (Default: સમગ્ર શાળા)'
                            : 'ફાળવેલ વર્ગ (Allotted Class)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      items: <DropdownMenuItem<String>>[
                        DropdownMenuItem<String>(
                          value: '__ALL__',
                          child: Text(
                            _isAdmin
                                ? 'સમગ્ર શાળા (All Classes)'
                                : 'બધા ફાળવેલ વર્ગો (All Allotted)',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        ..._accessibleClasses.map(
                          (c) => DropdownMenuItem<String>(
                            value: _text(c['id']),
                            child: Text(
                              _classLabels[_text(c['id'])] ?? _text(c['label']),
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _selectedClassFilter = v);
                      },
                    ),
                  ),
                ],
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            if (_loading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ] else if (showResultsSection) ...[
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: activeVisible.isNotEmpty &&
                            activeVisible.every(
                              (s) =>
                                  _selectedStudentIds.contains(_text(s['id'])),
                            ),
                        onChanged: activeVisible.isEmpty
                            ? null
                            : (checked) {
                                setState(() {
                                  if (checked == true) {
                                    for (final s in activeVisible) {
                                      _selectedStudentIds.add(_text(s['id']));
                                    }
                                  } else {
                                    for (final s in activeVisible) {
                                      _selectedStudentIds
                                          .remove(_text(s['id']));
                                    }
                                  }
                                });
                              },
                      ),
                      Text(
                        'મળેલા વિદ્યાર્થીઓ: ${visible.length} (Select All Active: ${activeVisible.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(
                        selected: _includeDeactive,
                        onSelected: (v) =>
                            setState(() => _includeDeactive = v),
                        label: const Text(
                          'નિષ્ક્રિય (Deactive) વિદ્યાર્થીઓ પણ બતાવો',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (visible.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Text(
                    'આ સર્ચ મુજબ કોઈ વિદ્યાર્થી મળ્યા નથી. (નામ, GR નંબર, મોબાઈલ નંબર, પિતાનું નામ કે માતાનું નામ તપાસો)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 430),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final s = visible[index];
                      final sid = _text(s['id']);
                      final isAct = _isStudentActive(s);
                      final classLbl =
                          _classLabels[_text(s['class_id'])] ?? 'વર્ગ';
                      final gr = _text(s['gr']).isEmpty ? '-' : _text(s['gr']);
                      final roll = _text(s['roll_number']).isEmpty
                          ? '-'
                          : _text(s['roll_number']);
                      final mobile = _text(s['mobile']).isEmpty
                          ? '-'
                          : _text(s['mobile']);
                      final father = _text(s['father_name']).isEmpty
                          ? '-'
                          : _text(s['father_name']);
                      final mother = _text(s['mother_name']).isEmpty
                          ? (_text(s['mother_en']).isEmpty
                              ? '-'
                              : _text(s['mother_en']))
                          : _text(s['mother_name']);

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isAct
                              ? Colors.white
                              : const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isAct
                                ? const Color(0xFFE2E8F0)
                                : const Color(0xFFFDE68A),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (isAct && !widget.readOnly)
                              Checkbox(
                                value: _selectedStudentIds.contains(sid),
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selectedStudentIds.add(sid);
                                    } else {
                                      _selectedStudentIds.remove(sid);
                                    }
                                  });
                                },
                              ),
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: isAct
                                  ? const Color(0xFFDBEAFE)
                                  : Colors.orange.shade100,
                              child: Text(
                                roll,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: isAct
                                      ? const Color(0xFF1E40AF)
                                      : Colors.orange.shade900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: InkWell(
                                onTap: () => widget.readOnly
                                    ? _showStudentWholeDataDialog(s)
                                    : _openStudentEditor(s),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          _text(s['name']),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14.5,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                        if (_text(s['name_en']).isNotEmpty)
                                          Text(
                                            '(${_text(s['name_en'])})',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF475569),
                                            ),
                                          ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE0E7FF),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            classLbl,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF3730A3),
                                            ),
                                          ),
                                        ),
                                        if (!isAct)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              'DEACTIVE',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.red.shade900,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'GR: $gr  •  Mobile: $mobile  •  પિતા: $father  •  માતા: $mother',
                                      style: const TextStyle(
                                        fontSize: 12.2,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF334155),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  tooltip: 'સંપૂર્ણ માહિતી જુઓ (View Details)',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () =>
                                      _showStudentWholeDataDialog(s),
                                  icon: const Icon(
                                    Icons.visibility_outlined,
                                    color: Color(0xFF0369A1),
                                    size: 20,
                                  ),
                                ),
                                if (!widget.readOnly)
                                  FilledButton.tonalIcon(
                                    style: FilledButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                    ),
                                    onPressed: _saving
                                        ? null
                                        : () => _openStudentEditor(s),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      'Edit / સુધારો',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                if (!widget.readOnly && isAct)
                                  IconButton(
                                    tooltip: 'Deactivate / નિષ્ક્રિય કરો',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _saving
                                        ? null
                                        : () => _deactivateSingleStudent(s),
                                    icon: Icon(
                                      Icons.person_off_outlined,
                                      color: Colors.red.shade700,
                                      size: 20,
                                    ),
                                  ),
                                if (!widget.readOnly && !isAct)
                                  FilledButton.tonalIcon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFFD1FAE5),
                                      foregroundColor: const Color(0xFF065F46),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: _saving
                                        ? null
                                        : () => _reactivateSingleStudent(s),
                                    icon: const Icon(Icons.restore, size: 16),
                                    label: const Text(
                                      'Activate',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GlobalStudentFormResult {
  const _GlobalStudentFormResult({
    required this.selectedClassId,
    required this.studentValues,
    required this.privateValues,
    required this.customValues,
  });

  final String selectedClassId;
  final Map<String, dynamic> studentValues;
  final Map<String, dynamic> privateValues;
  final Map<String, dynamic> customValues;
}

class _GlobalStudentEditorDialog extends StatefulWidget {
  const _GlobalStudentEditorDialog({
    required this.classId,
    required this.classLabel,
    required this.availableClasses,
    required this.schoolType,
    required this.student,
    required this.privateDetails,
    required this.customHeaders,
    required this.isAdmin,
  });

  final String classId;
  final String classLabel;
  final List<Map<String, dynamic>> availableClasses;
  final String schoolType;
  final Map<String, dynamic> student;
  final Map<String, dynamic> privateDetails;
  final List<String> customHeaders;
  final bool isAdmin;

  @override
  State<_GlobalStudentEditorDialog> createState() =>
      _GlobalStudentEditorDialogState();
}

class _GlobalStudentEditorDialogState
    extends State<_GlobalStudentEditorDialog> {
  final Map<String, TextEditingController> _studentControllers =
      <String, TextEditingController>{};
  final Map<String, TextEditingController> _privateControllers =
      <String, TextEditingController>{};
  final List<TextEditingController> _customControllers =
      <TextEditingController>[];

  late String _selectedClassId;
  String _category = 'OBC';
  String _gender = 'BOYS';
  bool _hasAadhaar = false;
  bool _rationCardKyc = false;
  bool _scholarshipDone = false;
  String _scholarshipReason = '';
  bool _isDivyang = false;
  String? _validationError;

  static const List<String> _scholarshipPendingReasons = <String>[
    'આધાર કાર્ડ નથી (No Aadhaar Card)',
    'રેશન કાર્ડ KYC બાકી (Ration Card KYC Pending)',
    'બેંક ખાતું નથી / બંધ છે (No / Inactive Bank Account)',
    'બેંક ખાતામાં આધાર સીડિંગ (NPCI/DBT) બાકી',
    'જન્મનો દાખલો / જાતિનો દાખલો બાકી',
    'નામ કે સ્પેલિંગમાં ભૂલ (Name Mismatch in Documents)',
    'અન્ય કારણ (Other Reason)',
  ];

  bool _parseYesNo(dynamic raw, {bool defaultValue = false}) {
    final s = (raw ?? '').toString().trim().toUpperCase();
    if (s.isEmpty) return defaultValue;
    return const <String>{
      'YES',
      'Y',
      'TRUE',
      '1',
      'હા',
      'DONE',
      'OK',
    }.contains(s);
  }

  @override
  void initState() {
    super.initState();
    _selectedClassId = widget.classId;
    for (final field in _kGlobalStudentFields) {
      final key = field['key']!;
      _studentControllers[key] = TextEditingController(
        text: '${widget.student[key] ?? ''}',
      );
    }
    for (final field in _kGlobalPrivateFields) {
      final key = field['key']!;
      _privateControllers[key] = TextEditingController(
        text: '${widget.privateDetails[key] ?? ''}',
      );
    }
    final customMap = widget.student['custom_fields'] is Map
        ? Map<String, dynamic>.from(widget.student['custom_fields'] as Map)
        : <String, dynamic>{};
    for (var i = 0; i < 11; i++) {
      final header =
          i < widget.customHeaders.length &&
                  widget.customHeaders[i].trim().isNotEmpty
              ? widget.customHeaders[i].trim()
              : 'Custom ${i + 1}';
      final value = customMap[header] ?? customMap['custom_${i + 1}'] ?? '';
      _customControllers.add(TextEditingController(text: '$value'));
    }

    _category = _normalizeCategory(
      _studentControllers['category']!.text,
      _studentControllers['category_en']!.text,
    );
    _gender = _normalizeGender(_studentControllers['gender']!.text);
    _hasAadhaar = _parseYesNo(
      widget.student['has_aadhaar'],
      defaultValue: false,
    );
    _rationCardKyc = _parseYesNo(
      widget.student['ration_card_kyc'],
      defaultValue: false,
    );
    _scholarshipDone = _parseYesNo(
      widget.student['scholarship_done'],
      defaultValue: false,
    );
    final savedReason = '${widget.student['scholarship_reason'] ?? ''}'.trim();
    _scholarshipReason = _scholarshipPendingReasons.contains(savedReason)
        ? savedReason
        : (savedReason.isNotEmpty ? 'અન્ય કારણ (Other Reason)' : '');
    if (savedReason.isNotEmpty &&
        !_scholarshipPendingReasons.contains(savedReason) &&
        _studentControllers['scholarship_other']!.text.trim().isEmpty) {
      _studentControllers['scholarship_other']!.text = savedReason;
    }
    final rawDivyang = widget.student['is_divyang'];
    _isDivyang = rawDivyang == true ||
        '${rawDivyang ?? ''}'.trim().toLowerCase() == 'true' ||
        '${rawDivyang ?? ''}'.trim() == 'હા';
  }

  @override
  void dispose() {
    for (final c in _studentControllers.values) {
      c.dispose();
    }
    for (final c in _privateControllers.values) {
      c.dispose();
    }
    for (final c in _customControllers) {
      c.dispose();
    }
    super.dispose();
  }

  String _normalizeCategory(String guValue, String enValue) {
    final combined = '$guValue $enValue'.toUpperCase();
    if (combined.contains('SC') || combined.contains('અ.જા')) return 'SC';
    if (combined.contains('ST') || combined.contains('અ.જ.જા')) return 'ST';
    if (combined.contains('OBC') ||
        combined.contains('SEBC') ||
        combined.contains('બક્ષી')) {
      return 'OBC';
    }
    if (combined.contains('GEN') ||
        combined.contains('OTHER') ||
        combined.contains('સામાન્ય')) {
      return 'OTHER';
    }
    return 'OBC';
  }

  String _normalizeGender(String value) {
    if (widget.schoolType == 'boys') return 'BOYS';
    if (widget.schoolType == 'girls') return 'GIRLS';
    final upper = value.trim().toUpperCase();
    if (upper.contains('GIRL') ||
        upper.contains('FEMALE') ||
        upper == 'F' ||
        value.contains('કન્યા') ||
        value.contains('છોકરી')) {
      return 'GIRLS';
    }
    return 'BOYS';
  }

  void _submit() {
    final name = _studentControllers['name']!.text.trim();
    final nameEn = _studentControllers['name_en']!.text.trim();
    if (name.isEmpty && nameEn.isEmpty) {
      setState(() => _validationError = 'વિદ્યાર્થીનું નામ લખવું ફરજિયાત છે.');
      return;
    }
    _studentControllers['category']!.text = _category;
    if (_studentControllers['category_en']!.text.trim().isEmpty) {
      _studentControllers['category_en']!.text = _category;
    }
    _studentControllers['gender']!.text = _gender;
    _studentControllers['has_aadhaar']!.text = _hasAadhaar ? 'YES' : 'NO';
    _studentControllers['ration_card_kyc']!.text =
        _rationCardKyc ? 'YES' : 'NO';
    _studentControllers['scholarship_done']!.text =
        _scholarshipDone ? 'YES' : 'NO';
    _studentControllers['scholarship_reason']!.text =
        _scholarshipDone ? '' : _scholarshipReason;
    if (_scholarshipDone) {
      _studentControllers['scholarship_other']!.text = '';
    }

    final studentValues = <String, dynamic>{
      for (final entry in _studentControllers.entries)
        entry.key: entry.value.text.trim(),
    };
    studentValues['is_divyang'] = _isDivyang;

    final privateValues = <String, dynamic>{
      for (final entry in _privateControllers.entries)
        entry.key: entry.value.text.trim(),
    };
    final customValues = <String, dynamic>{};
    for (var i = 0; i < _customControllers.length; i++) {
      final header =
          i < widget.customHeaders.length &&
                  widget.customHeaders[i].trim().isNotEmpty
              ? widget.customHeaders[i].trim()
              : 'Custom ${i + 1}';
      final val = _customControllers[i].text.trim();
      if (val.isNotEmpty) {
        customValues[header] = val;
      }
    }

    Navigator.of(context).pop(
      _GlobalStudentFormResult(
        selectedClassId: _selectedClassId,
        studentValues: studentValues,
        privateValues: privateValues,
        customValues: customValues,
      ),
    );
  }

  Widget _buildFieldGrid(List<String> keys) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: keys.map((key) {
        final field = _kGlobalStudentFields.firstWhere(
          (f) => f['key'] == key,
          orElse: () => <String, String>{'key': key, 'label': key},
        );
        return SizedBox(
          width: 260,
          child: TextField(
            controller: _studentControllers[key],
            decoration: InputDecoration(
              labelText: field['label'],
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabCount = widget.isAdmin ? 4 : 3;
    return DefaultTabController(
      length: tabCount,
      child: AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Edit Student / વિદ્યાર્થી માહિતી સુધારો — ${widget.student['name'] ?? ''}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            if (_validationError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _validationError!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
          ],
        ),
        content: SizedBox(
          width: 860,
          height: 540,
          child: Column(
            children: [
              TabBar(
                isScrollable: true,
                labelColor: Theme.of(context).colorScheme.primary,
                tabs: [
                  const Tab(text: '1. મુખ્ય વિગત (Basic & Gujarati)'),
                  const Tab(text: '2. English & IDs / Scholarship'),
                  const Tab(text: '3. વધારાના કોલમ (Custom)'),
                  if (widget.isAdmin)
                    const Tab(text: '4. બેંક વિગત (Admin Bank)'),
                ],
              ),
              const Divider(height: 1),
              Expanded(
                child: TabBarView(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              if (widget.availableClasses.isNotEmpty)
                                SizedBox(
                                  width: 260,
                                  child: DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    value: widget.availableClasses.any(
                                      (c) => '${c['id']}' == _selectedClassId,
                                    )
                                        ? _selectedClassId
                                        : '${widget.availableClasses.first['id']}',
                                    decoration: const InputDecoration(
                                      labelText: 'વર્ગ / ધોરણ (Class)',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    items: widget.availableClasses
                                        .map(
                                          (c) => DropdownMenuItem<String>(
                                            value: '${c['id']}',
                                            child: Text(
                                              '${c['label'] ?? c['class_key']}',
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: widget.isAdmin
                                        ? (v) {
                                            if (v != null) {
                                              setState(
                                                () => _selectedClassId = v,
                                              );
                                            }
                                          }
                                        : null,
                                  ),
                                ),
                              SizedBox(
                                width: 200,
                                child: DropdownButtonFormField<String>(
                                  value: _category,
                                  decoration: const InputDecoration(
                                    labelText: 'કેટેગરી (Category)',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'SC',
                                      child: Text('SC (અ.જા.)'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'ST',
                                      child: Text('ST (અ.જ.જા.)'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'OBC',
                                      child: Text('OBC (બક્ષીપંચ)'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'OTHER',
                                      child: Text('OTHER / GENERAL'),
                                    ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _category = v ?? 'OBC'),
                                ),
                              ),
                              SizedBox(
                                width: 200,
                                child: DropdownButtonFormField<String>(
                                  value: _gender,
                                  decoration: const InputDecoration(
                                    labelText: 'લિંગ (Gender)',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'BOYS',
                                      child: Text('BOYS (કુમાર)'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'GIRLS',
                                      child: Text('GIRLS (કન્યા)'),
                                    ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _gender = v ?? 'BOYS'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildFieldGrid(const <String>[
                            'roll_number',
                            'gr',
                            'name',
                            'father_name',
                            'mother_name',
                            'mobile',
                            'dd',
                            'mm',
                            'yyyy',
                            'religion',
                            'caste',
                            'address',
                            'birth_place',
                            'native_place',
                            'dob_words',
                            'last_school',
                            'enroll_school',
                            'enroll_class',
                            'enroll_sch_class',
                            'enroll_sch_class_words',
                            'present_days',
                          ]),
                        ],
                      ),
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldGrid(const <String>[
                            'name_en',
                            'mother_en',
                            'religion_en',
                            'caste_en',
                            'category_en',
                            'birth_place_en',
                            'native_place_en',
                            'dob_en',
                            'last_school_en',
                            'enroll_sch_class_en',
                            'enroll_sch_class_words_en',
                            'uid',
                            'pen',
                            'apaar_id',
                          ]),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 14,
                            runSpacing: 8,
                            children: [
                              FilterChip(
                                selected: _hasAadhaar,
                                onSelected: (v) =>
                                    setState(() => _hasAadhaar = v),
                                label: const Text('આધાર કાર્ડ છે (Has Aadhaar)'),
                              ),
                              FilterChip(
                                selected: _rationCardKyc,
                                onSelected: (v) =>
                                    setState(() => _rationCardKyc = v),
                                label: const Text(
                                  'રેશન કાર્ડ KYC પૂર્ણ (Ration KYC)',
                                ),
                              ),
                              FilterChip(
                                selected: _scholarshipDone,
                                onSelected: (v) =>
                                    setState(() => _scholarshipDone = v),
                                label: const Text(
                                  'શિષ્યવૃત્તિ થઈ ગઈ છે (Scholarship Done)',
                                ),
                              ),
                              FilterChip(
                                selected: _isDivyang,
                                onSelected: (v) =>
                                    setState(() => _isDivyang = v),
                                label: const Text(
                                  'દિવ્યાંગ વિદ્યાર્થી (Divyang)',
                                ),
                              ),
                            ],
                          ),
                          if (!_scholarshipDone) ...[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: _scholarshipReason.isEmpty
                                  ? null
                                  : _scholarshipReason,
                              decoration: const InputDecoration(
                                labelText: 'શિષ્યવૃત્તિ બાકી હોવાનું કારણ',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: _scholarshipPendingReasons
                                  .map(
                                    (r) => DropdownMenuItem<String>(
                                      value: r,
                                      child: Text(r),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _scholarshipReason = v ?? ''),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller:
                                  _studentControllers['scholarship_other'],
                              decoration: const InputDecoration(
                                labelText: 'શિષ્યવૃત્તિ અન્ય વિગત',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.only(top: 14),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: List<Widget>.generate(
                          _customControllers.length,
                          (i) {
                            final header = i < widget.customHeaders.length &&
                                    widget.customHeaders[i].trim().isNotEmpty
                                ? widget.customHeaders[i].trim()
                                : 'Custom ${i + 1}';
                            return SizedBox(
                              width: 260,
                              child: TextField(
                                controller: _customControllers[i],
                                decoration: InputDecoration(
                                  labelText: header,
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    if (widget.isAdmin)
                      SingleChildScrollView(
                        padding: const EdgeInsets.only(top: 14),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: _kGlobalPrivateFields.map((field) {
                            final key = field['key']!;
                            return SizedBox(
                              width: 260,
                              child: TextField(
                                controller: _privateControllers[key],
                                decoration: InputDecoration(
                                  labelText: field['label'],
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel / રદ કરો'),
          ),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save Changes / સુધારા સાચવો'),
          ),
        ],
      ),
    );
  }
}

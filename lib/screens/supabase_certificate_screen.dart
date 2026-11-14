import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, TextInputFormatter;
import 'package:intl/intl.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import '../models/models.dart';
import '../services/certificate_service.dart';
import '../services/supabase_hajari_patrak_service.dart';
import '../services/school_name_language_service.dart';
import '../services/supabase_student_service.dart';

/// Supabase-backed Bonafide / LC generator. Student details are read directly
/// from the active school's class roster; private bank fields are returned by
/// SupabaseStudentService only for the School Admin under the existing RLS rules.
class SupabaseCertificateScreen extends StatefulWidget {
  const SupabaseCertificateScreen({
    super.key,
    required this.profile,
    required this.isLc,
  });

  final Map<String, dynamic> profile;
  final bool isLc;

  @override
  State<SupabaseCertificateScreen> createState() =>
      _SupabaseCertificateScreenState();
}

class _SupabaseCertificateScreenState extends State<SupabaseCertificateScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  late final SupabaseStudentService _studentsService =
      SupabaseStudentService(client: _client);
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _certificateNumberController =
      TextEditingController(text: '1');
  final TextEditingController _reasonGuController = TextEditingController();
  final TextEditingController _reasonEnController = TextEditingController();
  final TextEditingController _progressGuController = TextEditingController();
  final TextEditingController _progressEnController = TextEditingController();
  final TextEditingController _conductGuController = TextEditingController();
  final TextEditingController _conductEnController = TextEditingController();
  final TextEditingController _remarksGuController = TextEditingController();
  final TextEditingController _remarksEnController = TextEditingController();

  List<Map<String, dynamic>> _classes = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _studentRows = <Map<String, dynamic>>[];
  Set<String> _selectedStudentIds = <String>{};
  String? _selectedClassId;
  String _selectedClassLabel = '';
  bool _loading = true;
  bool _loadingStudents = false;
  bool _generating = false;
  bool _isAdmin = false;
  bool _printCategory = true;
  String? _error;
  Map<String, dynamic> _schoolMeta = <String, dynamic>{};
  DateTime _lcDate = DateTime.now();
  bool _preferStudentLeavingDate = true;
  String _selectedReasonPreset = '__CUSTOM__';

  static const Map<String, String> _lcReasonPresets = <String, String>{
    '__CUSTOM__': '-- કારણ પસંદ કરો અથવા નીચે લખો (Select / Custom) --',
    'અન્યત્ર અભ્યાસાર્થે જતાં': 'GOING ELSEWHERE FOR STUDY',
    'સહપરિવાર સ્થળાંતર થતાં': 'MIGRATING WITH FAMILY',
    'અન્યત્ર રહેવા જવાથી': 'SHIFTING TO ANOTHER PLACE',
    'વતનમાં જતાં': 'GOING TO NATIVE PLACE',
    'બહાર ગામ જતાં': 'RELOCATING TO ANOTHER VILLAGE/TOWN',
    'વાલીની ઇચ્છાથી': 'BY PARENTS WISH',
    'આ શાળામાં ધોરણ 9 ન હોવાથી': 'STD. 9 IS NOT AVAILABLE IN THIS SCHOOL',
  };

  String _text(dynamic value) {
    final result = (value ?? '').toString().trim();
    return result.toLowerCase() == 'null' ? '' : result;
  }

  String _firstText(Iterable<dynamic> values) {
    for (final value in values) {
      final result = _text(value);
      if (result.isNotEmpty) return result;
    }
    return '';
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _certificateNumberController.dispose();
    _reasonGuController.dispose();
    _reasonEnController.dispose();
    _progressGuController.dispose();
    _progressEnController.dispose();
    _conductGuController.dispose();
    _conductEnController.dispose();
    _remarksGuController.dispose();
    _remarksEnController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_client.auth.currentUser == null) {
        throw StateError('કૃપા કરીને ફરીથી લૉગિન કરો.');
      }
      final schoolRef = _text(await _client.rpc('current_school_ref'));
      if (schoolRef.isEmpty) {
        throw StateError('આ લૉગિન માટે શાળાની માહિતી મળી નથી.');
      }

      var isAdmin = '${widget.profile['role'] ?? ''}'.toLowerCase() == 'admin';
      try {
        isAdmin = await _client.rpc('is_school_admin') == true;
      } catch (_) {
        // Keep the verified role from the authenticated home profile as fallback.
      }

      final classResult = await _client
          .from('school_classes')
          .select('id,label,class_key,sort_order,is_active')
          .eq('school_ref', schoolRef)
          .eq('is_active', true)
          .order('sort_order');
      final classes = classResult
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      Map<String, dynamic> config = <String, dynamic>{};
      try {
        final settingRow = await _client
            .from('school_settings')
            .select('config')
            .eq('school_ref', schoolRef)
            .maybeSingle();
        config = _map(settingRow?['config']);
      } catch (_) {
        // School profile RPC and login profile are still usable if config read is restricted.
      }
      final contextData =
          await SchoolNameLanguageService.loadCurrentSchoolContext(_client);
      final schoolMeta = _buildSchoolMeta(
        profile: widget.profile,
        contextData: contextData,
        config: config,
      );

      if (!mounted) return;
      setState(() {
        _isAdmin = isAdmin;
        _classes = classes;
        _schoolMeta = schoolMeta;
        _loading = false;
      });

      if (classes.isNotEmpty) {
        final first = classes.first;
        await _selectClass(
          _text(first['id']),
          _text(first['label']).isNotEmpty
              ? _text(first['label'])
              : _text(first['class_key']),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _cleanError(error);
        _loading = false;
      });
    }
  }

  String _cleanError(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('StateError: ', '')
      .replaceFirst('PostgrestException(message: ', 'Database error: ');

  Map<String, dynamic> _buildSchoolMeta({
    required Map<String, dynamic> profile,
    required Map<String, dynamic> contextData,
    required Map<String, dynamic> config,
  }) {
    final guName = _firstText(<dynamic>[
      contextData['school_name_gu'],
      contextData['schoolNameGu'],
      contextData['school_name_gj'],
      contextData['gujarati_school_name'],
      contextData['name_gu'],
      config['school_name_gu'],
      config['schoolNameGu'],
      config['schoolNameGujarati'],
      profile['school_name_gu'],
      profile['schoolNameGu'],
      config['schoolName'],
    ]);
    final enName = _firstText(<dynamic>[
      contextData['school_name_en'],
      contextData['schoolNameEn'],
      contextData['school_name'],
      contextData['schoolName'],
      contextData['name'],
      config['school_name_en'],
      config['schoolNameEn'],
      profile['school_name_en'],
      profile['schoolNameEn'],
      profile['school_name'],
      config['schoolName'],
    ]);
    final village = _firstText(<dynamic>[
      config['village'], config['villageName'], config['village_name'],
      contextData['village'], contextData['village_name'], profile['village'],
    ]);
    final taluka = _firstText(<dynamic>[
      config['taluka'], config['talukaName'], config['taluka_name'],
      contextData['taluka'], contextData['taluka_name'], profile['taluka'],
    ]);
    final district = _firstText(<dynamic>[
      config['district'], config['districtName'], config['district_name'],
      contextData['district'], contextData['district_name'], profile['district'],
    ]);
    final guAddress = _firstText(<dynamic>[
      contextData['school_address_gu'],
      contextData['schoolAddressGu'],
      contextData['address_gu'],
      contextData['addressGujarati'],
      config['school_address_gu'],
      config['schoolAddressGu'],
      config['address_gu'],
      config['addressGujarati'],
      config['school_address'],
      config['schoolAddress'],
      profile['school_address_gu'],
      profile['schoolAddressGu'],
    ]);
    final enAddress = _firstText(<dynamic>[
      contextData['school_address_en'],
      contextData['schoolAddressEn'],
      contextData['address_en'],
      contextData['addressEnglish'],
      config['school_address_en'],
      config['schoolAddressEn'],
      config['address_en'],
      config['addressEnglish'],
      profile['school_address_en'],
      profile['schoolAddressEn'],
      config['school_address'],
    ]);
    final diseCode = _firstText(<dynamic>[
      contextData['school_id'], contextData['schoolDiseCode'],
      contextData['dise_number'], contextData['diseNumber'],
      config['schoolDiseCode'], config['school_id'], config['diseCode'],
      profile['school_id'], profile['schoolDiseCode'],
      profile['dise_number'], profile['udise_code'],
    ]);
    final medium = _firstText(<dynamic>[
      config['medium'], config['schoolMedium'], contextData['medium'],
      profile['medium'],
    ]);
    final generatedGuAddress = <String>[village, taluka, district]
        .where((value) => value.isNotEmpty)
        .join(', ');
    final generatedEnAddress = <String>[village, taluka, district]
        .where((value) => value.isNotEmpty)
        .join(', ');

    final result = <String, dynamic>{
      ...profile,
      ...contextData,
      ...config,
      'school_name_gu': guName,
      'school_name_en': enName,
      'school_address_gu': guAddress.isNotEmpty ? guAddress : generatedGuAddress,
      'school_address_en': enAddress.isNotEmpty ? enAddress : generatedEnAddress,
      'school_id': diseCode,
      'medium': medium,
      'village': village,
      'taluka': taluka,
      'district': district,
      'centerName': _firstText(<dynamic>[
        config['centerName'], config['payCenter'], contextData['centerName'],
      ]),
      'crcName': _firstText(<dynamic>[config['crcName'], contextData['crcName']]),
      'academicYear': _firstText(<dynamic>[config['academicYear'], contextData['academicYear']]),
    };
    return result;
  }

  Future<void> _selectClass(String classId, String label) async {
    if (classId.isEmpty) return;
    setState(() {
      _selectedClassId = classId;
      _selectedClassLabel = label;
      _loadingStudents = true;
      _error = null;
      _studentRows = <Map<String, dynamic>>[];
      _selectedStudentIds = <String>{};
    });
    try {
      final loaded = await _studentsService.listStudents(classId: classId);
      loaded.sort((a, b) {
        final ar = int.tryParse(_text(a['roll_number']));
        final br = int.tryParse(_text(b['roll_number']));
        if (ar != null && br != null && ar != br) return ar.compareTo(br);
        return _text(a['roll_number']).compareTo(_text(b['roll_number']));
      });
      if (widget.isLc && loaded.isNotEmpty) {
        try {
          final academicYearStart =
              _lcDate.month >= 6 ? _lcDate.year : _lcDate.year - 1;
          final fromDate = DateTime(academicYearStart, 6, 1);
          final data = await SupabaseHajariPatrakService(client: _client)
              .getPresentDaysForDateRange(
            classId: classId,
            fromDate: fromDate,
            throughDate: _lcDate,
            students: loaded,
          );
          final rawDays = data['days_by_student_id'];
          if (rawDays is Map) {
            for (final st in loaded) {
              final sid = _text(st['id']);
              final v = rawDays[sid];
              final parsed = v is num ? v.toInt() : int.tryParse('$v');
              if (parsed != null && parsed > 0) {
                st['present_days'] = '$parsed';
                final cf = _map(st['custom_fields']);
                cf['present_days'] = '$parsed';
                st['custom_fields'] = cf;
              }
            }
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _studentRows = loaded;
        _selectedStudentIds = loaded.map((row) => _text(row['id'])).where((id) => id.isNotEmpty).toSet();
        _loadingStudents = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _cleanError(error);
        _loadingStudents = false;
      });
    }
  }

  Map<String, String> _customFields(Map<String, dynamic> row) {
    final result = <String, String>{};
    final raw = row['custom_fields'];
    if (raw is Map) {
      raw.forEach((key, value) {
        final text = _text(value);
        if (text.isNotEmpty) result[key.toString()] = text;
      });
    }
    const extraKeys = <String>[
      'apaar_id', 'present_days', 'native_place', 'native_place_en',
      'religion', 'progress_gu', 'progress_en', 'conduct_gu', 'conduct_en',
      'remarks_gu', 'remarks_en', 'progress', 'conduct', 'remarks',
      'remark_gu', 'remark_en', 'date_of_leaving', 'dateOfLeaving',
      'leaving_date', 'leavingDate', 'leave_date', 'lc_date', 'lcDate',
      'leave_reason_gu', 'leaving_reason_gu', 'reason_for_leaving',
      'reason_of_leaving', 'leave_reason_en', 'leaving_reason_en',
      'reason_for_leaving_en', 'reason_of_leaving_en',
      'વર્તણૂક', 'વર્તણુક', 'પ્રગતિ', 'વિશેષ નોંધ', 'શાળા છોડ્યાની તારીખ',
      'શાળા છોડવાનું કારણ', 'c1', 'c2',
    ];
    for (final key in extraKeys) {
      final value = _text(row[key]);
      if (value.isNotEmpty) result[key] = value;
    }
    return result;
  }

  StudentRecord _toStudentRecord(Map<String, dynamic> row) {
    final rawCategory = _text(row['category']).toUpperCase();
    final category = switch (rawCategory) {
      'SC' => Category.sc,
      'ST' => Category.st,
      'OBC' => Category.obc,
      _ => Category.other,
    };
    String field(String key) => _text(row[key]);
    return StudentRecord(
      id: field('id'),
      rollNumber: field('roll_number'),
      gr: field('gr'),
      dd: field('dd'),
      mm: field('mm'),
      yyyy: field('yyyy'),
      name: field('name'),
      caste: field('caste'),
      category: category,
      gender: field('gender'),
      enrollSchool: field('enroll_school'),
      enrollClass: field('enroll_class'),
      mobile: field('mobile'),
      motherName: field('mother_name'),
      birthPlace: field('birth_place'),
      dobWords: field('dob_words'),
      lastSchool: field('last_school'),
      enrollSchClass: field('enroll_sch_class'),
      enrollSchClassWords: field('enroll_sch_class_words'),
      nameEn: field('name_en'),
      casteEn: field('caste_en'),
      catEn: field('category_en'),
      motherEn: field('mother_en'),
      birthPlaceEn: field('birth_place_en'),
      dobEn: field('dob_en'),
      lastSchoolEn: field('last_school_en'),
      enrollSchClassEn: field('enroll_sch_class_en'),
      enrollSchClassWordsEn: field('enroll_sch_class_words_en'),
      uid: field('uid'),
      pen: field('pen'),
      bankName: _isAdmin ? field('bank_name') : '',
      bankBranch: _isAdmin ? field('bank_branch') : '',
      nameAsPassbook: _isAdmin ? field('name_as_passbook') : '',
      accountNumber: _isAdmin ? field('account_number') : '',
      ifscCode: _isAdmin ? field('ifsc_code') : '',
      isDivyang: field('is_divyang'),
      customFields: _customFields(row),
    );
  }

  List<Map<String, dynamic>> get _filteredRows {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _studentRows;
    return _studentRows.where((row) {
      return <String>[
        _text(row['name']),
        _text(row['name_en']),
        _text(row['roll_number']),
        _text(row['gr']),
      ].any((value) => value.toLowerCase().contains(query));
    }).toList();
  }

  void _toggleStudent(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedStudentIds.add(id);
      } else {
        _selectedStudentIds.remove(id);
      }
    });
  }

  void _selectAllFiltered(bool selected) {
    setState(() {
      for (final row in _filteredRows) {
        final id = _text(row['id']);
        if (id.isEmpty) continue;
        if (selected) {
          _selectedStudentIds.add(id);
        } else {
          _selectedStudentIds.remove(id);
        }
      }
    });
  }

  Future<void> _pickLcDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _lcDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'LC પર દર્શાવવાની તારીખ પસંદ કરો',
    );
    if (picked != null && mounted) setState(() => _lcDate = picked);
  }

  Future<({bool leaveBlank, Map<String, int?> daysById})?>
      _askAndPreparePresentDaysForLc(
    List<Map<String, dynamic>> students,
  ) async {
    final shouldAutoFill = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('હાજર દિવસો (Present Days)'),
        content: const Text(
          'તમારે LC માં વિદ્યાર્થીઓના હાજર દિવસો ઓટોમેટિક (Student-wise હાજરી અથવા દાખલ કરેલ વિગત પરથી) લખવા છે?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: const Text('રદ કરો'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ના, ખાલી રાખો'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('હા, આગળ વધો'),
          ),
        ],
      ),
    );
    if (shouldAutoFill == null) return null;
    if (!shouldAutoFill) {
      return (leaveBlank: true, daysById: <String, int?>{});
    }

    final defaults = <String, int?>{};
    var complete = false;
    var incompleteMonths = <String>[];
    try {
      final academicYearStart =
          _lcDate.month >= 6 ? _lcDate.year : _lcDate.year - 1;
      final fromDate = DateTime(academicYearStart, 6, 1);
      final data = await SupabaseHajariPatrakService(client: _client)
          .getPresentDaysForDateRange(
        classId: _selectedClassId ?? '',
        fromDate: fromDate,
        throughDate: _lcDate,
        students: students,
      );
      complete = data['is_complete'] == true;
      if (data['incomplete_months'] is List) {
        incompleteMonths = (data['incomplete_months'] as List)
            .map((e) => '$e')
            .toSet()
            .toList()
          ..sort();
      }
      final rawDays = data['days_by_student_id'];
      if (rawDays is Map) {
        for (final entry in rawDays.entries) {
          final v = entry.value;
          final parsed = v is num ? v.toInt() : int.tryParse('$v');
          if (parsed != null && parsed > 0) {
            defaults['${entry.key}'] = parsed;
          }
        }
      }
    } catch (_) {
      for (final student in students) {
        final id = _text(student['id']);
        final custom = _map(student['custom_fields']);
        final raw = _firstText(<dynamic>[
          student['present_days'],
          custom['present_days'],
          custom['presentDays'],
          custom['હાજર દિવસો'],
        ]);
        final parsed = int.tryParse(raw);
        if (id.isNotEmpty && parsed != null && parsed > 0) {
          defaults[id] = parsed;
        }
      }
    }

    final warning = complete
        ? 'જૂનથી LC તારીખ સુધીના Student-wise records / દાખલ કરેલ વિગત પરથી હાજર દિવસો ગણાયા છે. જરૂર હોય તો Days સુધારીને આગળ વધો.'
        : 'જો Student-wise હાજરી કે દાખલ કરેલ હાજર દિવસો ઉપલબ્ધ હશે તો નીચે દેખાશે${incompleteMonths.isEmpty ? "" : " (${incompleteMonths.join(", ")})"}. જ્યાં ખાલી રાખશો ત્યાં LC માં ખાલી જ રહેશે.';

    final controllers = <TextEditingController>[
      for (final student in students)
        TextEditingController(
          text: defaults[_text(student['id'])] != null &&
                  defaults[_text(student['id'])]! > 0
              ? '${defaults[_text(student["id"])]}'
              : '',
        ),
    ];

    Map<String, int?>? edited;
    try {
      if (!mounted) return null;
      edited = await showDialog<Map<String, int?>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final viewport = MediaQuery.sizeOf(context);
            return AlertDialog(
              title: const Text('LC માટે હાજર દિવસો ચકાસો / દાખલ કરો'),
              content: SizedBox(
                width: viewport.width < 760 ? viewport.width * 0.78 : 700,
                height: viewport.height * 0.62,
                child: Column(
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        warning,
                        style: TextStyle(
                          color: complete
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: const <Widget>[
                          SizedBox(
                            width: 76,
                            child: Text(
                              'રોલ નંબર',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'વિદ્યાર્થીનું નામ',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          SizedBox(
                            width: 112,
                            child: Text(
                              'Days',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.separated(
                        itemCount: students.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final student = students[index];
                          final roll = _text(student['roll_number']).isEmpty
                              ? '${index + 1}'
                              : _text(student['roll_number']);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: <Widget>[
                                SizedBox(width: 76, child: Text(roll)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _text(student['name']),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 102,
                                  child: TextField(
                                    controller: controllers[index],
                                    keyboardType: TextInputType.number,
                                    inputFormatters: <TextInputFormatter>[
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    textAlign: TextAlign.center,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                      hintText: 'ખાલી',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: const Text('રદ કરો'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    final candidate = <String, int?>{};
                    for (var i = 0; i < students.length; i++) {
                      final id = _text(students[i]['id']);
                      if (id.isEmpty) continue;
                      final raw = controllers[i].text.trim();
                      final parsed = int.tryParse(raw);
                      candidate[id] =
                          (parsed != null && parsed > 0) ? parsed : null;
                    }
                    Navigator.of(dialogContext).pop(candidate);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('સાચવો અને આગળ વધો'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      for (final c in controllers) {
        c.dispose();
      }
    }
    if (edited == null) return null;
    return (leaveBlank: false, daysById: edited);
  }

  Future<void> _generate() async {
    final selectedRows = _studentRows
        .where((row) => _selectedStudentIds.contains(_text(row['id'])))
        .toList();
    if (selectedRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ઓછામાં ઓછો એક વિદ્યાર્થી પસંદ કરો.')),
      );
      return;
    }
    ({bool leaveBlank, Map<String, int?> daysById})? lcPresentDaysOutcome;
    if (widget.isLc) {
      lcPresentDaysOutcome = await _askAndPreparePresentDaysForLc(selectedRows);
      if (lcPresentDaysOutcome == null || !mounted) return;
    }
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final selectedStudents = selectedRows.map(_toStudentRecord).toList();
      if (widget.isLc) {
        final startNo = int.tryParse(_certificateNumberController.text.trim());
        await CertificateService.generateBulkLC(
          students: selectedStudents,
          className: _selectedClassLabel,
          printCategory: _printCategory,
          leaveReasonGu: _reasonGuController.text.trim(),
          leaveReasonEn: _reasonEnController.text.trim(),
          lcDate: DateFormat('dd/MM/yyyy').format(_lcDate),
          preferStudentLeavingDate: _preferStudentLeavingDate,
          schoolMeta: _schoolMeta,
          certificateStartNumber: startNo,
          certificateNo: _certificateNumberController.text.trim(),
          progressGu: _progressGuController.text.trim(),
          progressEn: _progressEnController.text.trim(),
          conductGu: _conductGuController.text.trim(),
          conductEn: _conductEnController.text.trim(),
          remarksGu: _remarksGuController.text.trim(),
          remarksEn: _remarksEnController.text.trim(),
          presentDaysByStudentId: lcPresentDaysOutcome?.daysById,
          leavePresentDaysBlank: lcPresentDaysOutcome?.leaveBlank ?? false,
        );
      } else {
        await CertificateService.generateBulkBonafide(
          students: selectedStudents,
          className: _selectedClassLabel,
          printCategory: _printCategory,
          schoolMeta: _schoolMeta,
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Widget _buildStudentPicker() {
    if (_loadingStudents) return const Center(child: CircularProgressIndicator());
    if (_studentRows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: Text('આ વર્ગમાં સક્રિય વિદ્યાર્થી મળ્યા નથી.')),
      );
    }
    return Column(
      children: <Widget>[
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'વિદ્યાર્થી શોધો / Search students',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Clear search',
              onPressed: () {
                _searchController.clear();
                setState(() {});
              },
              icon: const Icon(Icons.clear),
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Text('પસંદ: ${_selectedStudentIds.length}/${_studentRows.length}'),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _selectAllFiltered(true),
              icon: const Icon(Icons.done_all),
              label: const Text('બધા પસંદ'),
            ),
            TextButton(
              onPressed: () => _selectAllFiltered(false),
              child: const Text('પસંદગી દૂર'),
            ),
          ],
        ),
        Container(
          constraints: const BoxConstraints(maxHeight: 360),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _filteredRows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final row = _filteredRows[index];
              final id = _text(row['id']);
              final selected = _selectedStudentIds.contains(id);
              final roll = _text(row['roll_number']);
              final name = _text(row['name']);
              final gr = _text(row['gr']);
              return CheckboxListTile(
                dense: true,
                value: selected,
                onChanged: (value) => _toggleStudent(id, value == true),
                title: Text(
                  '${roll.isEmpty ? '—' : roll}. $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'GR: ${gr.isEmpty ? '—' : gr}  •  ${_text(row['name_en'])}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                controlAffinity: ListTileControlAffinity.leading,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label,
      {String? hint, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isLc
        ? 'Leaving Certificate (LC) / શાળા છોડ્યાનું પ્રમાણપત્ર'
        : 'Bonafide Certificate / બોનાફાઈડ';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: <Widget>[
          IconButton(
            tooltip: 'Reload database data',
            onPressed: _loading || _generating ? null : _loadInitialData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Icon(Icons.storage_outlined),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'ડેટાબેઝમાંથી આપમેળે ભરાશે',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'શાળા, DISE કોડ, માધ્યમ, સરનામું અને વિદ્યાર્થીની વિગતો ડેટાબેઝમાંથી લેવામાં આવે છે. ${_isAdmin ? 'Admin માટે જ મંજૂર બેંક વિગતો પણ લોડ થાય છે.' : 'ખાનગી બેંક વિગતો આ ખાતામાંથી વાંચવામાં આવતી નથી.'}',
                        ),
                        if (_schoolMeta['school_name_gu'] != null &&
                            _text(_schoolMeta['school_name_gu']).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _text(_schoolMeta['school_name_gu']),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_error != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!),
                    ),
                  ),
                if (_classes.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('આ ખાતા માટે કોઈ સક્રિય/ફાળવેલો વર્ગ મળ્યો નથી.'),
                    ),
                  )
                else ...<Widget>[
                  DropdownButtonFormField<String>(
                    value: _selectedClassId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'વર્ગ પસંદ કરો / Select class',
                      border: OutlineInputBorder(),
                    ),
                    items: _classes.map((row) {
                      final id = _text(row['id']);
                      final label = _firstText(<dynamic>[row['label'], row['class_key']]);
                      return DropdownMenuItem<String>(
                        value: id,
                        child: Text(label, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: _loadingStudents || _generating
                        ? null
                        : (value) {
                            if (value == null) return;
                            final row = _classes.firstWhere(
                              (item) => _text(item['id']) == value,
                            );
                            final label = _firstText(<dynamic>[row['label'], row['class_key']]);
                            _selectClass(value, label);
                          },
                  ),
                  const SizedBox(height: 14),
                  Text('વિદ્યાર્થી પસંદગી', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _buildStudentPicker(),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _printCategory,
                    onChanged: (value) => setState(() => _printCategory = value == true),
                    title: const Text('જાતિ / કેટેગરી ઉમેરો'),
                    subtitle: const Text('ચેક કરવાથી પ્રમાણપત્રમાં category label પણ ઉમેરાશે.'),
                  ),
                  if (widget.isLc) ...<Widget>[
                    const Divider(height: 28),
                    Text('LC વિગતો', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'LC તારીખ / Date',
                              border: OutlineInputBorder(),
                            ),
                            child: InkWell(
                              onTap: _pickLcDate,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  children: <Widget>[
                                    Expanded(child: Text(DateFormat('dd/MM/yyyy').format(_lcDate))),
                                    const Icon(Icons.calendar_month_outlined),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _field(
                            _certificateNumberController,
                            'પ્રમાણપત્ર ક્રમાંક (શરૂઆત)',
                            hint: '1',
                          ),
                        ),
                      ],
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _preferStudentLeavingDate,
                      onChanged: (value) => setState(
                        () => _preferStudentLeavingDate = value == true,
                      ),
                      title: const Text('વિદ્યાર્થીના ડેટાબેઝમાં LC તારીખ હોય તો તે વાપરો'),
                      subtitle: const Text('ડેટાબેઝમાં તારીખ ન હોય તો ઉપર પસંદ કરેલી તારીખ વપરાશે.'),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DropdownButtonFormField<String>(
                        value: _lcReasonPresets.containsKey(_selectedReasonPreset)
                            ? _selectedReasonPreset
                            : '__CUSTOM__',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'શાળા છોડવાનું કારણ પસંદ કરો (Sample Reasons)',
                          border: OutlineInputBorder(),
                        ),
                        items: _lcReasonPresets.entries.map((entry) {
                          final label = entry.key == '__CUSTOM__'
                              ? entry.value
                              : '${entry.key} (${entry.value})';
                          return DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(label, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: _generating
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() {
                                  _selectedReasonPreset = value;
                                  if (value != '__CUSTOM__') {
                                    _reasonGuController.text = value;
                                    _reasonEnController.text =
                                        _lcReasonPresets[value] ?? '';
                                  }
                                });
                              },
                      ),
                    ),
                    _field(_reasonGuController, 'શાળા છોડવાનું કારણ (ગુજરાતી)',
                        hint: 'ખાલી રાખો તો DBમાંથી લેવાનો પ્રયત્ન કરશે'),
                    _field(_reasonEnController, 'Reason for leaving (English)',
                        hint: 'Leave blank to use a database value if available'),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _generating
                            ? null
                            : () {
                                setState(() {
                                  _selectedReasonPreset =
                                      'આ શાળામાં ધોરણ 9 ન હોવાથી';
                                  _reasonGuController.text =
                                      'આ શાળામાં ધોરણ 9 ન હોવાથી';
                                  _reasonEnController.text =
                                      'STD. 9 IS NOT AVAILABLE IN THIS SCHOOL';
                                });
                              },
                        icon: const Icon(Icons.school_outlined),
                        label: const Text(
                            'ધોરણ 9 નથી — ધોરણ 8 પાસ મુજબ લખો'),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text(
                        'આ ખાસ કારણ પસંદ કરવાથી LC માં “ધોરણ ૮ (આઠમું) પાસ” અને LC તારીખ મુજબની અભ્યાસ વિગત આવશે. અન્ય કારણ માટે કારણનું લખાણ સામાન્ય રીતે દાખલ કરો.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    Row(
                      children: <Widget>[
                        Expanded(child: _field(_progressGuController, 'પ્રગતિ')),
                        const SizedBox(width: 10),
                        Expanded(child: _field(_progressEnController, 'Progress')),
                      ],
                    ),
                    Row(
                      children: <Widget>[
                        Expanded(child: _field(_conductGuController, 'વર્તણૂક')),
                        const SizedBox(width: 10),
                        Expanded(child: _field(_conductEnController, 'Conduct')),
                      ],
                    ),
                    Row(
                      children: <Widget>[
                        Expanded(child: _field(_remarksGuController, 'વિશેષ નોંધ', maxLines: 2)),
                        const SizedBox(width: 10),
                        Expanded(child: _field(_remarksEnController, 'Remarks', maxLines: 2)),
                      ],
                    ),
                    const Text(
                      'નોંધ: વિદ્યાર્થીના LC date/reason, remarks_gu/remarks_en અને legacy C1/C2 custom fields ઉપલબ્ધ હોય તો રેકોર્ડમાંથી લેવામાં આવે છે. અહીં દાખલ કરેલું લખાણ આ PDF માટે જ વપરાય છે; વિદ્યાર્થીના રેકોર્ડમાં કોઈ ફેરફાર થતો નથી.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _generating || _loadingStudents ? null : _generate,
                    icon: _generating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(_generating
                        ? 'પ્રમાણપત્ર તૈયાર થઈ રહ્યું છે…'
                        : widget.isLc
                            ? 'પસંદ કરેલા વિદ્યાર્થીઓના LC બનાવો'
                            : 'પસંદ કરેલા વિદ્યાર્થીઓના Bonafide બનાવો'),
                  ),
                ],
              ],
            ),
    );
  }
}

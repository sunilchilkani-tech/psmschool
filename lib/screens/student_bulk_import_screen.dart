import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';
import 'package:share_plus/share_plus.dart';

import '../services/school_class_order.dart';
import '../services/supabase_student_service.dart';
import 'archived_students_screen.dart';
import '../services/school_type.dart';

/// Full school roster template/import screen. Supports Whole-School upload
/// (auto-routed by `ધોરણ` column or worksheet tab name) as well as single-class
/// upload, smart GR partial-column merge, and automatic reactivation of
/// archived/disappeared students.
class StudentBulkImportScreen extends StatefulWidget {
  const StudentBulkImportScreen({
    super.key,
    required this.classId,
    required this.classLabel,
    required this.schoolType,
    this.classKey = '',
    this.standard = '',
    this.section = '',
    this.readOnly = false,
  });

  final String classId;
  final String classLabel;
  final String schoolType;
  final String classKey;
  final String standard;
  final String section;
  final bool readOnly;

  @override
  State<StudentBulkImportScreen> createState() =>
      _StudentBulkImportScreenState();
}

class _StudentBulkImportScreenState extends State<StudentBulkImportScreen> {
  final SupabaseStudentService _service = SupabaseStudentService();
  final SupabaseClient _client = Supabase.instance.client;
  bool _working = false;
  bool _isAdmin = false;
  String? _schoolRef;
  late String _selectedClassId;
  late String _selectedClassLabel;
  List<Map<String, dynamic>> _classes = <Map<String, dynamic>>[];
  String _resolvedSchoolType = '';
  int _archivedSchoolCount = 0;
  String _status =
      'નમૂનો ડાઉનલોડ કરો, વિદ્યાર્થીની વિગતો ભરો અને પછી XLSX ફાઇલ અપલોડ કરો.';
  List<String> _errors = <String>[];
  List<String> _warnings = <String>[];

  @override
  void initState() {
    super.initState();
    _selectedClassId =
        widget.classId.trim().isEmpty ? '__ALL__' : widget.classId.trim();
    _selectedClassLabel = widget.classLabel.trim().isEmpty
        ? 'સમગ્ર શાળા (All Classes / Whole School)'
        : widget.classLabel.trim();
    _initContext();
  }

  Future<void> _initContext() async {
    try {
      final admin = await _service.isCurrentUserAdmin();
      final ref = await _service.currentSchoolRef();
      final classRows = await _client
          .from('school_classes')
          .select('id,label,class_key,standard,section,sheet_name,sort_order,is_active')
          .eq('school_ref', ref)
          .eq('is_active', true)
          .order('sort_order');
      final sortedClasses = SchoolClassOrder.sorted(
        classRows.map((r) => Map<String, dynamic>.from(r)),
      );
      final schoolRow = await _client
          .from('schools')
          .select('school_type')
          .eq('id', ref)
          .maybeSingle();
      final regType = '${schoolRow?['school_type'] ?? ''}'.trim();
      final allStudents = await _client
          .from('students')
          .select('id,is_active,leaving_date,exit_date')
          .eq('school_ref', ref);
      var archivedCount = 0;
      for (final raw in allStudents) {
        final isAct = raw['is_active'] == true &&
            '${raw['leaving_date'] ?? ''}'.trim().isEmpty &&
            '${raw['exit_date'] ?? ''}'.trim().isEmpty;
        if (!isAct) archivedCount++;
      }
      if (!mounted) return;
      setState(() {
        _isAdmin = admin;
        _schoolRef = ref;
        if (regType.isNotEmpty) _resolvedSchoolType = regType;
        _classes = sortedClasses;
        _archivedSchoolCount = archivedCount;
        if (_selectedClassId != '__ALL__') {
          final match = sortedClasses.where(
            (c) => '${c['id']}' == _selectedClassId,
          );
          if (match.isNotEmpty) {
            _selectedClassLabel =
                '${match.first['label'] ?? match.first['class_key'] ?? _selectedClassLabel}';
          }
        }
      });
    } catch (_) {
      // Import still works for ordinary fields; RLS will remain authoritative.
    }
  }

  String get _effectiveSchoolType {
    final raw = (_resolvedSchoolType.isNotEmpty
            ? _resolvedSchoolType
            : widget.schoolType)
        .trim();
    return SchoolType.canonical(raw);
  }

  bool get _mixed => _service.isMixedSchool(_effectiveSchoolType);

  String get _schoolTypeLabel {
    if (_mixed) return 'મિશ્ર શાળા (Co-ed)';
    if (_effectiveSchoolType == 'boys') return 'કુમાર શાળા (Boys)';
    if (_effectiveSchoolType == 'girls') return 'કન્યા શાળા (Girls)';
    return _effectiveSchoolType;
  }

  static const List<String> _singleGenderHeaders = <String>[
    'ક્રમ',
    'ધોરણ',
    'Roll Number',
    'GR નંબર',
    'DD',
    'MM',
    'YYYY',
    'વિદ્યાર્થીનું નામ',
    'ધર્મ',
    'પેટા જ્ઞાતિ',
    'કેટેગરી',
    'શાળામાં દાખલ તારીખ',
    'વર્ગમાં દાખલ તારીખ',
    'મોબાઈલ નંબર',
    'પિતાનું નામ',
    'માતાનું નામ',
    'જન્મ સ્થળ',
    'જન્મ તારીખ શબ્દોમાં',
    'પૂર્વ શાળાનું નામ',
    'શાળામાં દાખલ ધોરણ',
    'શાળામાં દાખલ ધોરણ શબ્દોમાં',
    'હાજર દિવસો',
    'NAME IN ENGLISH',
    'RELIGION IN ENGLISH',
    'CASTE IN ENGLISH',
    'CATEGORY IN ENG',
    "MOTHER'S NAME IN ENGLISH",
    'BIRTH PLACE IN ENGLISH',
    'DOB IN ENGLISH WORDS',
    'LAST SCHOOL IN ENGLISH',
    'ENROLL CLASS IN ENGLISH',
    'ENROLL CLASS IN ENGLISH WORDS',
    'APAAR ID',
    'આધાર કાર્ડ છે? (YES/NO)',
    'રેશન કાર્ડ KYC (YES/NO)',
    'શિષ્યવૃત્તિ?',
    'શિષ્યવૃત્તિ કારણ',
    'UID નંબર',
    'PEN નંબર',
    'દિવ્યાંગ? (YES/NO)',
    'બેંકનું નામ',
    'બેંક બ્રાન્ચ',
    'પાસબુક મુજબ નામ',
    'એકાઉન્ટ નંબર',
    'IFSC કોડ',
    'વતન',
    'વતન (English)',
  ];

  static const List<String> _coedHeaders = <String>[
    'ક્રમ',
    'ધોરણ',
    'Roll Number',
    'GR નંબર',
    'DD',
    'MM',
    'YYYY',
    'વિદ્યાર્થીનું નામ',
    'જાતિ',
    'ધર્મ',
    'પેટા જ્ઞાતિ',
    'કેટેગરી',
    'શાળામાં દાખલ તારીખ',
    'વર્ગમાં દાખલ તારીખ',
    'મોબાઈલ નંબર',
    'પિતાનું નામ',
    'માતાનું નામ',
    'જન્મ સ્થળ',
    'જન્મ તારીખ શબ્દોમાં',
    'પૂર્વ શાળાનું નામ',
    'શાળામાં દાખલ ધોરણ',
    'શાળામાં દાખલ ધોરણ શબ્દોમાં',
    'હાજર દિવસો',
    'NAME IN ENGLISH',
    'RELIGION IN ENGLISH',
    'CASTE IN ENGLISH',
    'CATEGORY IN ENG',
    "MOTHER'S NAME IN ENGLISH",
    'BIRTH PLACE IN ENGLISH',
    'DOB IN ENGLISH WORDS',
    'LAST SCHOOL IN ENGLISH',
    'ENROLL CLASS IN ENGLISH',
    'ENROLL CLASS IN ENGLISH WORDS',
    'APAAR ID',
    'આધાર કાર્ડ છે? (YES/NO)',
    'રેશન કાર્ડ KYC (YES/NO)',
    'શિષ્યવૃત્તિ?',
    'શિષ્યવૃત્તિ કારણ',
    'UID નંબર',
    'PEN નંબર',
    'દિવ્યાંગ? (YES/NO)',
    'બેંકનું નામ',
    'બેંક બ્રાન્ચ',
    'પાસબુક મુજબ નામ',
    'એકાઉન્ટ નંબર',
    'IFSC કોડ',
    'વતન',
    'વતન (English)',
  ];

  List<String> get _headers => _mixed ? _coedHeaders : _singleGenderHeaders;

  String _headerKey(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r"[\s\-\._/()?:']"), '');

  String? _canonicalHeader(String raw) {
    final key = _headerKey(raw);
    const aliases = <String, String>{
      'ક્રમ': 'serial',
      'serialnumber': 'serial',
      'serialno': 'serial',
      'ધોરણ': 'class_label',
      'વર્ગ': 'class_label',
      'class': 'class_label',
      'classlabel': 'class_label',
      'standard': 'class_label',
      'rollnumber': 'roll_number',
      'rollno': 'roll_number',
      'roll': 'roll_number',
      'grનંબર': 'gr',
      'grno': 'gr',
      'grnumber': 'gr',
      'gr': 'gr',
      'dd': 'dd',
      'mm': 'mm',
      'yyyy': 'yyyy',
      'year': 'yyyy',
      'વિદ્યાર્થીનુંનામ': 'name',
      'studentname': 'name',
      'name': 'name',
      'જાતિ': 'gender',
      'gender': 'gender',
      'sex': 'gender',
      'ધર્મ': 'religion',
      'religion': 'religion',
      'ધર્મગુજરાતી': 'religion',
      'religiongujarati': 'religion',
      'religioninenglish': 'religion_en',
      'religionenglish': 'religion_en',
      'religionen': 'religion_en',
      'religion_en': 'religion_en',
      'ધર્મenglish': 'religion_en',
      'ધર્મઅંગ્રેજી': 'religion_en',
      'પેટાજ્ઞાતિ': 'caste',
      'caste': 'caste',
      'subcaste': 'caste',
      'કેટેગરી': 'category',
      'category': 'category',
      'શાળામાંદાખલતારીખ': 'enroll_school',
      'enrollschool': 'enroll_school',
      'schooladmissiondate': 'enroll_school',
      'વર્ગમાંદાખલતારીખ': 'enroll_class',
      'enrollclassdate': 'enroll_class',
      'classadmissiondate': 'enroll_class',
      'મોબાઈલનંબર': 'mobile',
      'મોબાઇલનંબર': 'mobile',
      'mobile': 'mobile',
      'mobilenumber': 'mobile',
      'phone': 'mobile',
      'પિતાનુંનામ': 'father_name',
      'fathername': 'father_name',
      'માતાનુંનામ': 'mother_name',
      'mothername': 'mother_name',
      'જન્મસ્થળ': 'birth_place',
      'birthplace': 'birth_place',
      'જન્મતારીખશબ્દોમાં': 'dob_words',
      'dobwords': 'dob_words',
      'dobinwords': 'dob_words',
      'પૂર્વશાળાનુંનામ': 'last_school',
      'lastschool': 'last_school',
      'શાળામાંદાખલધોરણ': 'enroll_sch_class',
      'enrollclass': 'enroll_sch_class',
      'શાળામાંદાખલધોરણશબ્દોમાં': 'enroll_sch_class_words',
      'enrollclasswords': 'enroll_sch_class_words',
      'હાજરદિવસો': 'present_days',
      'presentdays': 'present_days',
      'nameinenglish': 'name_en',
      'name_en': 'name_en',
      'casteinenglish': 'caste_en',
      'caste_en': 'caste_en',
      'categoryineng': 'category_en',
      'categoryenglish': 'category_en',
      'mothersnameinenglish': 'mother_en',
      'mothernameinenglish': 'mother_en',
      'birthplaceinenglish': 'birth_place_en',
      'dobinenglishwords': 'dob_en',
      'lastschoolinenglish': 'last_school_en',
      'enrollclassinenglish': 'enroll_sch_class_en',
      'enrollclassinenglishwords': 'enroll_sch_class_words_en',
      'apaarid': 'apaar_id',
      'અપારઆઈડી': 'apaar_id',
      'આધારકાર્ડછે': 'has_aadhaar',
      'આધારકાર્ડછેyesno': 'has_aadhaar',
      'hasstudentaadhaar': 'has_aadhaar',
      'hasaadhaar': 'has_aadhaar',
      'has_aadhaar': 'has_aadhaar',
      'studentaadhaar': 'has_aadhaar',
      'રેશનકાર્ડkyc': 'ration_card_kyc',
      'રેશનકાર્ડkycyesno': 'ration_card_kyc',
      'rationcardkyc': 'ration_card_kyc',
      'ration_card_kyc': 'ration_card_kyc',
      'rationkyc': 'ration_card_kyc',
      'શિષ્યવૃત્તિ': 'scholarship_done',
      'scholarship': 'scholarship_done',
      'scholarshipdone': 'scholarship_done',
      'શિષ્યવૃત્તિકારણ': 'scholarship_reason',
      'scholarshipreason': 'scholarship_reason',
      'uidનંબર': 'uid',
      'uid': 'uid',
      'penનંબર': 'pen',
      'pen': 'pen',
      'દિવ્યાંગ': 'is_divyang',
      'દિવ્યાંગyesno': 'is_divyang',
      'divyang': 'is_divyang',
      'isdivyang': 'is_divyang',
      'બેંકનુંનામ': 'bank_name',
      'bankname': 'bank_name',
      'બેંકબ્રાન્ચ': 'bank_branch',
      'bankbranch': 'bank_branch',
      'પાસબુકમુજબનામ': 'name_as_passbook',
      'nameaspassbook': 'name_as_passbook',
      'એકાઉન્ટનંબર': 'account_number',
      'accountnumber': 'account_number',
      'ifscકોડ': 'ifsc_code',
      'ifsccode': 'ifsc_code',
      'વતન': 'native_place',
      'nativeplace': 'native_place',
      'વતનenglish': 'native_place_en',
      'nativeplaceenglish': 'native_place_en',
      'સરનામું': 'address',
      'address': 'address',
      'જન્મતારીખ': 'dob_combined',
      'dob': 'dob_combined',
      'dateofbirth': 'dob_combined',
      'birthdate': 'dob_combined',
    };
    return aliases[key];
  }

  String _excelSpanText(dynamic span) {
    final buffer = StringBuffer();
    final value = span.text;
    if (value is String) buffer.write(value);
    final children = span.children;
    if (children is Iterable) {
      for (final child in children) {
        buffer.write(_excelSpanText(child));
      }
    }
    return buffer.toString();
  }

  String _cellText(Data? cell) {
    final value = cell?.value;
    if (value == null) return '';
    if (value is TextCellValue) return _excelSpanText(value.value);
    if (value is IntCellValue) return '${value.value}';
    if (value is DoubleCellValue) {
      final n = value.value;
      return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
    }
    if (value is BoolCellValue) return '${value.value}';
    return '$value';
  }

  Future<void> _downloadTemplate() async {
    final workbook = Excel.createExcel();
    workbook.rename('Sheet1', 'Students');
    final sheet = workbook['Students'];
    sheet.appendRow(_headers.map((header) => TextCellValue(header)).toList());

    final classListNames = _classes
        .map((c) => '${c['label'] ?? c['class_key'] ?? ''}'.trim())
        .where((s) => s.isNotEmpty)
        .join(', ');

    final instructions = workbook['Instructions'];
    for (final row in <List<String>>[
      <String>['પ્રોફેશનલ સ્કૂલ મેનેજમેન્ટ - વિદ્યાર્થી આયાત (સમગ્ર શાળા / વર્ગ મુજબ)'],
      <String>['પસંદ કરેલો વર્ગ / સ્કોપ', _selectedClassLabel],
      <String>[
        'શાળાના ઉપલબ્ધ વર્ગો',
        classListNames.isEmpty ? 'બાલવાટિકા, ધોરણ - 1 થી 8' : classListNames,
      ],
      <String>['શાળાનો પ્રકાર', _schoolTypeLabel],
      <String>[
        'સમગ્ર શાળા અપલોડ નિયમ',
        'તમે આખી શાળાના બધા ધોરણના વિદ્યાર્થીઓ એક જ શીટમાં ("ધોરણ" કૉલમમાં બાલવાટિકા, ધોરણ - 1, વગેરે લખીને) અથવા અલગ-અલગ શીટમાં અપલોડ કરી શકો છો. જો "ધોરણ" કૉલમ ખાલી હોય, તો ઉપર પસંદ કરેલા વર્ગમાં વિદ્યાર્થી ઉમેરાશે.'
      ],
      <String>[
        'ધર્મ હેડર',
        '"ધર્મ" (ગુજરાતીમાં) અને "RELIGION IN ENGLISH" (અંગ્રેજીમાં) કૉલમ ઉમેરવામાં આવ્યા છે. આધાર અને રેશન કાર્ડના કૉલમ દૂર કરવામાં આવ્યા છે.'
      ],
      <String>['જરૂરી વિગતો', 'નવા વિદ્યાર્થી માટે વિદ્યાર્થીનું નામ ફરજિયાત છે. જૂના વિદ્યાર્થીના અપડેટ માટે GR નંબર પૂરતો છે.'],
      <String>[
        'રોલ નંબર',
        'ખાલી રાખશો તો આગળનો ઉપલબ્ધ રોલ નંબર આપવામાં આવશે અને વર્ગના રોલ નંબર 1..N ક્રમમાં ગોઠવાશે.'
      ],
      <String>[
        'કેટેગરીના વિકલ્પો',
        'SC / ST / OBC / OTHER; ગુજરાતી કેટેગરીના નામ (અ.જા., અ.જ.જા., બક્ષીપંચ, અન્ય) પણ માન્ય છે.'
      ],
      <String>[
        'જાતિ / Gender',
        _mixed
            ? 'કુમાર / BOYS અથવા કન્યા / GIRLS (મિશ્ર શાળામાં જરૂરી).'
            : 'શાળાના પ્રકાર પરથી જાતિ આપમેળે નક્કી થશે.'
      ],
    ]) {
      instructions.appendRow(row.map((value) => TextCellValue(value)).toList());
    }

    final bytes = workbook.encode();
    if (bytes == null || bytes.isEmpty) {
      throw StateError('XLSX નમૂનો બનાવી શકાયો નથી.');
    }
    await SharePlus.instance.share(ShareParams(
      title: 'વિદ્યાર્થી આયાત નમૂનો - $_selectedClassLabel',
      files: <XFile>[
        XFile.fromData(
          Uint8List.fromList(bytes),
          name:
              'PSM_Student_Template_${_mixed ? 'COED' : 'SINGLE_GENDER'}.xlsx',
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ],
    ));
  }

  Future<void> _downloadPartialGrTemplate() async {
    final workbook = Excel.createExcel();
    workbook.rename('Sheet1', 'GR_Partial_Update');
    final sheet = workbook['GR_Partial_Update'];
    sheet.appendRow(<CellValue>[
      TextCellValue('GR નંબર'),
      TextCellValue('ધર્મ'),
      TextCellValue('RELIGION IN ENGLISH'),
      TextCellValue('મોબાઈલ નંબર'),
      TextCellValue('APAAR ID'),
      TextCellValue('UID નંબર'),
      TextCellValue('PEN નંબર'),
    ]);
    final bytes = workbook.encode();
    if (bytes == null || bytes.isEmpty) {
      throw StateError('XLSX નમૂનો બનાવી શકાયો નથી.');
    }
    await SharePlus.instance.share(ShareParams(
      title: 'GR મુજબ આંશિક અપડેટ નમૂનો',
      files: <XFile>[
        XFile.fromData(
          Uint8List.fromList(bytes),
          name: 'PSM_GR_Partial_Column_Update_Template.xlsx',
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ],
    ));
  }

  Future<void> _restoreAllDisappearedStudents() async {
    if (_working || widget.readOnly) return;
    setState(() {
      _working = true;
      _errors = <String>[];
      _warnings = <String>[];
      _status = 'આર્કાઇવ / ગાયબ થયેલા વિદ્યાર્થીઓ પાછા સક્રિય થઈ રહ્યા છે...';
    });
    try {
      final res = await _client.rpc(
        'psm_restore_disappeared_or_archived_students',
        params: <String, dynamic>{
          'p_class_id': _selectedClassId == '__ALL__' ? '' : _selectedClassId,
        },
      );
      final restored = (res is Map ? res['restored_count'] : 0) ?? 0;
      await _initContext();
      if (!mounted) return;
      setState(() {
        _working = false;
        _status =
            'સફળતાપૂર્વક $restored વિદ્યાર્થીઓને પાછા સક્રિય (Active) કરવામાં આવ્યા છે અને રોલ નંબર 1..N ક્રમમાં ગોઠવાઈ ગયા છે!';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _status = 'વિદ્યાર્થીઓ પાછા લાવવામાં ભૂલ: $e';
      });
    }
  }

  Future<void> _pickAndImport() async {
    if (widget.readOnly) return;
    setState(() {
      _working = true;
      _errors = <String>[];
      _warnings = <String>[];
      _status = 'કૃપા કરીને XLSX ફાઇલ પસંદ કરો...';
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['xlsx'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) {
        if (mounted) {
          setState(() {
            _working = false;
            _status = 'આયાત રદ કરવામાં આવી.';
          });
        }
        return;
      }
      final bytes = picked.files.single.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError(
          'પસંદ કરેલી XLSX ફાઇલ વાંચી શકાઈ નથી. ફાઇલ ફરી પસંદ કરો.',
        );
      }
      final workbook = Excel.decodeBytes(bytes);
      if (workbook.tables.isEmpty) {
        throw StateError('નમૂનામાં કોઈ worksheet નથી.');
      }

      final dataRows = <Map<String, dynamic>>[];

      for (final entry in workbook.tables.entries) {
        final sheetName = entry.key.trim();
        if (sheetName.toLowerCase() == 'instructions' ||
            sheetName.toLowerCase() == 'સૂચનાઓ') {
          continue;
        }
        final sheet = entry.value;
        if (sheet.rows.length < 2) continue;

        final headers = sheet.rows.first.map(_cellText).toList();
        final indexByField = <String, int>{};
        final customColByHeader = <String, int>{};
        for (var i = 0; i < headers.length; i++) {
          final hRaw = headers[i].trim();
          if (hRaw.isEmpty) continue;
          final canonical = _canonicalHeader(hRaw);
          if (canonical != null) {
            indexByField[canonical] = i;
          } else {
            // Skip restricted Aadhaar / Ration Card headers automatically
            final lower = hRaw.toLowerCase();
            if (lower.contains('aadhaar') ||
                lower.contains('aadhar') ||
                lower.contains('ration') ||
                hRaw.contains('આધાર') ||
                hRaw.contains('રેશન')) {
              continue;
            }
            customColByHeader[hRaw] = i;
          }
        }

        if (!indexByField.containsKey('gr') &&
            !indexByField.containsKey('name') &&
            !indexByField.containsKey('roll_number')) {
          continue;
        }

        String at(List<Data?> row, String key) {
          final index = indexByField[key];
          return index == null || index >= row.length
              ? ''
              : _cellText(row[index]).trim();
        }

        for (var r = 1; r < sheet.rows.length; r++) {
          final row = sheet.rows[r];
          if (row.every((cell) => _cellText(cell).trim().isEmpty)) continue;
          final gr = at(row, 'gr');
          final name = at(row, 'name');
          final roll = at(row, 'roll_number');
          if (gr.isEmpty && name.isEmpty && roll.isEmpty) continue;

          final uploadedClass = at(row, 'class_label');
          final item = <String, dynamic>{
            '_excel_row': r + 1,
            '_sheet_name': sheetName,
            if (uploadedClass.isNotEmpty) 'class_label': uploadedClass,
          };

          for (final field in SupabaseStudentService.allTemplateFields) {
            if (field == 'serial' || field == 'class_label') continue;
            if (indexByField.containsKey(field)) {
              final val = at(row, field);
              if (val.isNotEmpty) {
                item[field] = val;
              }
            }
          }
          if (indexByField.containsKey('address')) {
            final addr = at(row, 'address');
            if (addr.isNotEmpty) item['address'] = addr;
          }
          if (indexByField.containsKey('dob_combined')) {
            final dobRaw = at(row, 'dob_combined');
            if (dobRaw.isNotEmpty) {
              final parts = dobRaw.split(RegExp(r'[/.-]'));
              if (parts.length == 3) {
                if (parts[0].length == 4) {
                  item['yyyy'] ??= parts[0].trim();
                  item['mm'] ??= parts[1].trim().padLeft(2, '0');
                  item['dd'] ??= parts[2].trim().padLeft(2, '0');
                } else {
                  item['dd'] ??= parts[0].trim().padLeft(2, '0');
                  item['mm'] ??= parts[1].trim().padLeft(2, '0');
                  item['yyyy'] ??= parts[2].trim();
                }
              }
            }
          }
          if (customColByHeader.isNotEmpty) {
            final customMap = <String, String>{};
            for (final ce in customColByHeader.entries) {
              if (ce.value < row.length) {
                final cv = _cellText(row[ce.value]).trim();
                if (cv.isNotEmpty) customMap[ce.key] = cv;
              }
            }
            if (customMap.isNotEmpty) {
              item['custom_fields'] = customMap;
            }
          }

          dataRows.add(item);
        }
      }

      if (dataRows.isEmpty) {
        throw StateError(
          'Excel ફાઇલમાં GR નંબર અથવા વિદ્યાર્થીનું નામ ધરાવતી કોઈ પંક્તિ મળી નથી.',
        );
      }
      if (mounted) {
        setState(
          () => _status =
              '${dataRows.length} વિદ્યાર્થી રેકોર્ડ ($_selectedClassLabel / GR મુજબ સ્માર્ટ મર્જ) આયાત થાય છે...',
        );
      }
      final preValidationErrors = List<String>.from(_errors);
      final result = await _service.importRows(
        classId: _selectedClassId == '__ALL__' ? '' : _selectedClassId,
        schoolType: _effectiveSchoolType,
        rows: dataRows,
      );
      await _initContext();
      if (!mounted) return;
      final errors = <String>[
        ...preValidationErrors,
        ...((result['errors'] as List? ?? const <dynamic>[]).map((e) => '$e')),
      ];
      final warnings = (result['warnings'] as List? ?? const <dynamic>[])
          .map((e) => '$e')
          .toList();
      final imported = (result['imported'] as int? ?? 0);
      final updated = (result['updated'] as int? ?? 0);
      final restored = (result['restored'] as int? ?? 0);
      final addedNew = (imported - updated).clamp(0, imported);
      final failed = errors.length;
      setState(() {
        _working = false;
        _status =
            'આયાત સફળ: કુલ $imported (નવા ઉમેરાયેલા: $addedNew, GR મુજબ અપડેટ થયેલા: $updated${restored > 0 ? ', આર્કાઇવમાંથી પાછા સક્રિય થયેલા: $restored' : ''}); ભૂલો: $failed. અગાઉના કૉલમનો ડેટા સુરક્ષિત રાખવામાં આવ્યો છે.';
        _errors = errors;
        _warnings = warnings;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _status = 'આયાત નિષ્ફળ ગઈ: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          toolbarHeight: 68,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'વિદ્યાર્થીઓનું બલ્ક અપલોડ (સમગ્ર શાળા / વર્ગ)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
              Text(
                _selectedClassLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          actions: [
            if (_schoolRef != null)
              TextButton.icon(
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
                  if (mounted) await _initContext();
                },
                icon: const Icon(Icons.restore_from_trash_outlined),
                label: Text(
                  _archivedSchoolCount > 0
                      ? 'આર્કાઇવ વિદ્યાર્થીઓ ($_archivedSchoolCount)'
                      : 'આર્કાઇવ વિદ્યાર્થીઓ',
                ),
              ),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (_archivedSchoolCount > 0)
            Card(
              color: Colors.amber.shade50,
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Colors.orange.shade900),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'આ શાળાના $_archivedSchoolCount વિદ્યાર્થીઓ આર્કાઇવ / ગાયબ (Archived / Promoted) સ્થિતિમાં છે!',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Colors.orange.shade900,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'જો બાલવાટિકા કે અન્ય વર્ગના વિદ્યાર્થીઓ ગાયબ થઈ ગયા હોય, તો નીચેના બટનથી ૧-ક્લિકમાં બધાને પાછા સક્રિય (Restore) કરી શકો છો અથવા ફરીથી Excel અપલોડ કરશો તો પણ આપમેળે સક્રિય થઈ જશે.',
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange.shade800,
                          ),
                          onPressed:
                              _working || widget.readOnly ? null : _restoreAllDisappearedStudents,
                          icon: const Icon(Icons.settings_backup_restore),
                          label: Text(
                            'બધા $_archivedSchoolCount ગાયબ/આર્કાઇવ વિદ્યાર્થીઓ પાછા લાવો (Restore All)',
                          ),
                        ),
                        if (_schoolRef != null)
                          OutlinedButton.icon(
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ArchivedStudentsScreen(
                                    schoolRef: _schoolRef!,
                                    classId: '',
                                    classLabel:
                                        'સમગ્ર શાળા (All Classes / Whole School)',
                                    readOnly: widget.readOnly,
                                  ),
                                ),
                              );
                              if (mounted) await _initContext();
                            },
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text(
                              'આર્કાઇવ વિદ્યાર્થીઓની યાદી જુઓ / વર્ગ બદલો',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'અપલોડનો પ્રકાર / વર્ગ પસંદ કરો (Whole School or Single Class)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedClassId == '__ALL__' ||
                            _classes.any((c) => '${c['id']}' == _selectedClassId)
                        ? _selectedClassId
                        : '__ALL__',
                    decoration: const InputDecoration(
                      labelText: 'અપલોડ સ્કોપ / વર્ગ (Target Class or Whole School)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: <DropdownMenuItem<String>>[
                      const DropdownMenuItem<String>(
                        value: '__ALL__',
                        child: Text(
                          'સમગ્ર શાળા (All Classes / Whole School — ધોરણ કૉલમ મુજબ)',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      ..._classes.map(
                        (c) => DropdownMenuItem<String>(
                          value: '${c['id']}',
                          child: Text(
                            '${c['label'] ?? c['class_key']} (આ વર્ગમાં સીધું અપલોડ)',
                          ),
                        ),
                      ),
                    ],
                    onChanged: _working
                        ? null
                        : (val) {
                            if (val == null) return;
                            setState(() {
                              _selectedClassId = val;
                              if (val == '__ALL__') {
                                _selectedClassLabel =
                                    'સમગ્ર શાળા (All Classes / Whole School)';
                              } else {
                                final found = _classes.firstWhere(
                                  (c) => '${c['id']}' == val,
                                  orElse: () => <String, dynamic>{},
                                );
                                _selectedClassLabel =
                                    '${found['label'] ?? found['class_key'] ?? val}';
                              }
                            });
                          },
                  ),
                  const SizedBox(height: 10),
                  Text('શાળાનો પ્રકાર: $_schoolTypeLabel', softWrap: true),
                  const SizedBox(height: 4),
                  Text(
                    _mixed
                        ? 'મિશ્ર શાળાના નમૂનામાં 46 કૉલમ છે (ધર્મ અને RELIGION IN ENGLISH સહિત). જાતિ / Gender માં કુમાર અથવા કન્યા પસંદ કરો.'
                        : 'એકલ-જાતિ શાળાના નમૂનામાં 45 કૉલમ છે (ધર્મ અને RELIGION IN ENGLISH સહિત). જાતિ શાળાના પ્રકાર મુજબ આપમેળે નક્કી થશે.',
                    softWrap: true,
                  ),
                ],
              ),
            ),
          ),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('૧. સંપૂર્ણ નમૂનો ડાઉનલોડ કરો',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                            softWrap: true),
                        const SizedBox(height: 8),
                        const Text(
                            'નમૂનામાં ધર્મ (ગુજરાતી) અને RELIGION IN ENGLISH ઉમેરવામાં આવ્યા છે, અને આધાર કાર્ડ (3) તથા રેશન કાર્ડ (3) ના કૉલમ દૂર કરવામાં આવ્યા છે.',
                            softWrap: true),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _working
                                  ? null
                                  : () async {
                                      try {
                                        await _downloadTemplate();
                                      } catch (error) {
                                        if (mounted) {
                                          setState(() => _status =
                                              'નમૂનો બનાવવામાં ભૂલ: $error');
                                        }
                                      }
                                    },
                              icon: const Icon(Icons.download),
                              label: const Text(
                                  'સંપૂર્ણ XLSX નમૂનો (Full Template)'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _working
                                  ? null
                                  : () async {
                                      try {
                                        await _downloadPartialGrTemplate();
                                      } catch (error) {
                                        if (mounted) {
                                          setState(() => _status =
                                              'નમૂનો બનાવવામાં ભૂલ: $error');
                                        }
                                      }
                                    },
                              icon: const Icon(Icons.bolt_outlined),
                              label: const Text(
                                  'GR મુજબ આંશિક અપડેટ નમૂનો (GR + Any Column)'),
                            ),
                          ],
                        ),
                      ]))),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('૨. ભરેલો નમૂનો અપલોડ કરો',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                            softWrap: true),
                        const SizedBox(height: 8),
                        const Text(
                            '• સમગ્ર શાળાનો ડેટા (બધા ધોરણો એકસાથે અથવા અલગ શીટમાં) અપલોડ કરી શકાશે.\n'
                            '• જો તમારી Excel ફાઇલમાં "ધોરણ" કૉલમ ન હોય (જેમ કે માત્ર બાલવાટિકાની ફાઇલ), તો ઉપર ડ્રોપડાઉનમાંથી તે વર્ગ (દા.ત. બાલવાટિકા) પસંદ કરીને અપલોડ કરો.\n'
                            '• જો કોઈ વિદ્યાર્થી અગાઉ આર્કાઇવ કે ગાયબ થઈ ગયો હશે, તો ફરી અપલોડ કરવાથી તે આપમેળે સક્રિય (Active) થઈ જશે!',
                            softWrap: true),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _working || widget.readOnly
                              ? null
                              : _pickAndImport,
                          icon: _working
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.upload_file),
                          label: Text(widget.readOnly
                              ? 'અહીં અપલોડ બંધ છે (ફક્ત વાંચવા માટે)'
                              : _working
                                  ? 'કામ ચાલુ છે...'
                                  : 'XLSX પસંદ કરો અને આયાત કરો ($_selectedClassLabel)'),
                        ),
                      ]))),
          const SizedBox(height: 8),
          SelectableText(
            _status,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (_warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('ચેતવણીઓ (${_warnings.length})',
                style: Theme.of(context).textTheme.titleMedium),
            for (final warning in _warnings)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('• $warning',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.tertiary))),
          ],
          if (_errors.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('સુધારાની જરૂર હોય તેવી પંક્તિઓ (${_errors.length})',
                style: Theme.of(context).textTheme.titleMedium),
            for (final error in _errors)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('• $error',
                      style: const TextStyle(color: Colors.red))),
          ],
        ]),
      );
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:excel_community/excel_community.dart' as ec;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html;
import '../services/template_print/template_print_service.dart';

import '../services/datewise_report_columns.dart';
import '../services/psm_file_export_helper.dart';
import '../services/school_class_order.dart';
import '../services/supabase_report_export_service.dart';
import '../services/supabase_school_access_service.dart';

/// Platform Developer tab. Developer authority is checked by the Edge Function
/// against the server-only PSM_DEVELOPER_KEY; no privileged Supabase key is in Flutter.
class DeveloperPanel extends StatefulWidget {
  const DeveloperPanel({
    super.key,
    SupabaseSchoolAccessService? service,
    this.showAppBar = true,
    this.initialSessionKey = '',
    this.initialSchools,
  }) : _service = service;

  final SupabaseSchoolAccessService? _service;
  final bool showAppBar;
  final String initialSessionKey;
  final List<Map<String, dynamic>>? initialSchools;

  @override
  State<DeveloperPanel> createState() => _DeveloperPanelState();
}

class _DeveloperPanelState extends State<DeveloperPanel>
    with WidgetsBindingObserver {
  late final SupabaseSchoolAccessService _service;
  final _developerKeyController = TextEditingController();
  final _schoolNameController = TextEditingController();
  final _schoolNameGuController = TextEditingController();
  final _schoolAddressEnController = TextEditingController();
  final _schoolAddressGuController = TextEditingController();
  final _schoolSearchController = TextEditingController();
  final _developerMessageController = TextEditingController();
  final _diseController = TextEditingController();
  final _adminNameController = TextEditingController();
  final _adminMobileController = TextEditingController();
  final _adminPasswordController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  String _schoolType = 'mixed';
  DateTime _validityDate = DateTime.now().add(const Duration(days: 365));
  List<Map<String, dynamic>> _schools = <Map<String, dynamic>>[];
  bool _unlocked = false;
  bool _busy = false;
  String? _error;
  DateTime _messageDate = DateTime.now();
  String _recipientScope = 'admin_only';
  List<Map<String, dynamic>> _developerMessages = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _sharedFiles = <Map<String, dynamic>>[];
  final _sharedFileTitleController = TextEditingController();
  final _sharedFileDescController = TextEditingController();
  Map<String, dynamic> _usage = <String, dynamic>{};
  List<Map<String, dynamic>> _bulkPreview = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _bulkResults = <Map<String, dynamic>>[];
  /// New-school requests sent from the login screen, waiting for approval.
  List<Map<String, dynamic>> _regRequests = <Map<String, dynamic>>[];
  bool _regLoading = false;

  static const _schoolTypes = <String, String>{
    'boys': 'કુમાર શાળા',
    'girls': 'કન્યા શાળા',
    'mixed': 'મિશ્ર શાળા',
  };

  void _autoLockAndCloseOnHide() {
    _developerKeyController.clear();
    if (!mounted) return;
    setState(() {
      _unlocked = false;
      _schools = <Map<String, dynamic>>[];
    });
    if (widget.showAppBar && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _autoLockAndCloseOnHide();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service = widget._service ?? SupabaseSchoolAccessService();
    if (kIsWeb) {
      html.document.onVisibilityChange.listen((_) {
        if (html.document.hidden == true) {
          _autoLockAndCloseOnHide();
        }
      });
    }
    if (widget.initialSessionKey.trim().isNotEmpty) {
      _developerKeyController.text = widget.initialSessionKey.trim();
      if (widget.initialSchools != null) {
        _schools = List<Map<String, dynamic>>.from(widget.initialSchools!);
        _unlocked = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _loadDeveloperMessages(silent: true);
          _loadDeveloperSharedFiles(silent: true);
          _loadUsage(silent: true);
          _loadRegistrationRequests(silent: true);
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _unlock();
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _developerKeyController.clear();
    _developerKeyController.dispose();
    _schoolNameController.dispose();
    _schoolNameGuController.dispose();
    _schoolAddressEnController.dispose();
    _schoolAddressGuController.dispose();
    _schoolSearchController.dispose();
    _developerMessageController.dispose();
    _sharedFileTitleController.dispose();
    _sharedFileDescController.dispose();
    _diseController.dispose();
    _adminNameController.dispose();
    _adminMobileController.dispose();
    _adminPasswordController.dispose();
    super.dispose();
  }

  String _dateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  bool _isValidIndianMobile(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return RegExp(r'^(?:[6-9]\d{9}|91[6-9]\d{9})$').hasMatch(digits);
  }

  String _dateDisplay(dynamic value) {
    final raw = (value ?? '').toString();
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw.isEmpty ? 'Not set' : raw;
    return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  void _message(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _unlock() async {
    final key = _developerKeyController.text.trim();
    if (key.isEmpty) {
      _message('Developer key દાખલ કરો.', isError: true);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final schools = await _service.developerListSchools(key);
      if (!mounted) return;
      setState(() {
        _schools = schools;
        _unlocked = true;
      });
      _message('Developer access verified.');
      await Future.wait(<Future<void>>[
        _loadDeveloperMessages(silent: true),
        _loadDeveloperSharedFiles(silent: true),
        _loadUsage(silent: true),
        _loadRegistrationRequests(silent: true),
      ]);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _unlocked = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reloadSchools() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final schools = await _service.developerListSchools(
        _developerKeyController.text.trim(),
      );
      if (mounted) setState(() => _schools = schools);
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createSchool() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.developerCreateSchool(
        developerKey: _developerKeyController.text.trim(),
        schoolName: _schoolNameController.text,
        schoolNameGu: _schoolNameGuController.text,
        schoolAddressEn: _schoolAddressEnController.text,
        schoolAddressGu: _schoolAddressGuController.text,
        diseNumber: _diseController.text,
        adminName: _adminNameController.text,
        adminMobile: _adminMobileController.text,
        adminPassword: _adminPasswordController.text,
        schoolType: _schoolType,
        validityDate: _dateIso(_validityDate),
      );
      _schoolNameController.clear();
      _schoolNameGuController.clear();
      _schoolAddressEnController.clear();
      _schoolAddressGuController.clear();
      _diseController.clear();
      _adminNameController.clear();
      _adminMobileController.clear();
      _adminPasswordController.clear();
      await _reloadSchools();
      if (mounted) _message('School and Admin account created successfully.');
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
        _message(_error!, isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editSchool(Map<String, dynamic> school) async {
    final name = TextEditingController(
      text: '${school['school_name_en'] ?? school['school_name'] ?? ''}',
    );
    final nameGu = TextEditingController(
      text: '${school['school_name_gu'] ?? ''}',
    );
    final addressEn = TextEditingController(
      text: '${school['school_address_en'] ?? ''}',
    );
    final addressGu = TextEditingController(
      text: '${school['school_address_gu'] ?? ''}',
    );
    final adminName = TextEditingController(
      text: '${school['admin_name'] ?? ''}',
    );
    final mobile = TextEditingController(
      text: '${school['admin_mobile'] ?? ''}'.replaceFirst('+91', ''),
    );
    final password = TextEditingController();
    var type = '${school['school_type'] ?? 'mixed'}';
    var validity =
        DateTime.tryParse('${school['validity_date'] ?? ''}') ?? _validityDate;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Edit school and Admin'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'School name (English)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameGu,
                    decoration: const InputDecoration(
                      labelText: 'School name (Gujarati)',
                      border: OutlineInputBorder(),
                      hintText: 'ગુજરાતીમાં શાળાનું નામ',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: addressEn,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'School address (English)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: addressGu,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'School address (Gujarati)',
                      border: OutlineInputBorder(),
                      hintText: 'ગુજરાતીમાં શાળાનું સરનામું',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: adminName,
                    decoration: const InputDecoration(
                      labelText: 'Admin name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: mobile,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Registered Admin mobile',
                      helperText: '10-digit Indian mobile number',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: password,
                    obscureText: true,
                    maxLength: 15,
                    decoration: const InputDecoration(
                      labelText: 'Set new Admin password (optional)',
                      helperText:
                          'Leave blank to keep current (4 to 15 characters).',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: type,
                    decoration: const InputDecoration(
                      labelText: 'School type',
                      border: OutlineInputBorder(),
                    ),
                    items: _schoolTypes.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => type = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Validity date',
                      border: OutlineInputBorder(),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: Text(_dateDisplay(_dateIso(validity)))),
                        TextButton.icon(
                          icon: const Icon(Icons.calendar_month),
                          label: const Text('Select'),
                          onPressed: () async {
                            final pick = await showDatePicker(
                              context: dialogContext,
                              initialDate: validity,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (pick != null)
                              setDialogState(() => validity = pick);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().length < 2 ||
                    nameGu.text.trim().length < 2 ||
                    addressEn.text.trim().length < 3 ||
                    addressGu.text.trim().length < 3 ||
                    adminName.text.trim().length < 2)
                  return;
                if (mobile.text.trim().isNotEmpty &&
                    !_isValidIndianMobile(mobile.text))
                  return;
                if (password.text.isNotEmpty &&
                    (password.text.length < 4 || password.text.length > 15))
                  return;
                Navigator.pop(dialogContext, <String, dynamic>{
                  'schoolName': name.text.trim(),
                  'schoolNameGu': nameGu.text.trim(),
                  'schoolAddressEn': addressEn.text.trim(),
                  'schoolAddressGu': addressGu.text.trim(),
                  'adminName': adminName.text.trim(),
                  'adminMobile': mobile.text.trim(),
                  'adminPassword': password.text,
                  'schoolType': type,
                  'validityDate': _dateIso(validity),
                });
              },
              child: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    nameGu.dispose();
    addressEn.dispose();
    addressGu.dispose();
    adminName.dispose();
    mobile.dispose();
    password.dispose();
    if (result == null) return;
    await _runSchoolAction(
      () => _service.developerUpdateSchool(
        developerKey: _developerKeyController.text.trim(),
        schoolRef: '${school['id']}',
        schoolName: result['schoolName'] as String,
        schoolNameGu: result['schoolNameGu'] as String,
        schoolAddressEn: result['schoolAddressEn'] as String,
        schoolAddressGu: result['schoolAddressGu'] as String,
        adminName: result['adminName'] as String,
        adminMobile: result['adminMobile'] as String,
        adminPassword: result['adminPassword'] as String,
        schoolType: result['schoolType'] as String,
        validityDate: result['validityDate'] as String,
      ),
    );
  }

  Future<void> _deleteSchool(Map<String, dynamic> school) async {
    final confirm = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Permanently delete school?'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This permanently deletes ${school['school_name']} and ALL its data from the server: teachers and logins, classes, students, attendance, results, leave, library, Rojmel, files, settings and its registration request. Export a directory/backup first. This cannot be undone.',
              ),
              const SizedBox(height: 12),
              Text(
                'Type the exact DISE number ${school['school_id']} to confirm.',
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirm,
                decoration: const InputDecoration(
                  labelText: 'Confirm DISE number',
                  border: OutlineInputBorder(),
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
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(
              dialogContext,
              confirm.text.trim() == '${school['school_id']}',
            ),
            child: const Text('Permanently delete'),
          ),
        ],
      ),
    );
    final typed = confirm.text.trim();
    confirm.dispose();
    if (approved != true) {
      if (typed.isNotEmpty)
        _message(
          'Delete was cancelled: DISE number did not match.',
          isError: true,
        );
      return;
    }
    await _runSchoolAction(() async {
      // Backups are best effort: a failed download must not block the delete.
      try {
        await _downloadLibraryBooksBackupBeforeDelete(
          schoolRef: '${school['id']}',
          schoolId: typed,
          schoolName:
              '${school['school_name_gu'] ?? school['school_name_en'] ?? school['school_name'] ?? 'School'}',
        );
        await _downloadAttendanceBackupBeforeDelete(
          schoolRef: '${school['id']}',
          schoolId: typed,
          schoolName:
              '${school['school_name_gu'] ?? school['school_name_en'] ?? school['school_name'] ?? 'School'}',
        );
      } catch (_) {}
      await _service.developerDeleteSchool(
        developerKey: _developerKeyController.text.trim(),
        schoolRef: '${school['id']}',
        confirmSchoolId: typed,
      );
    });
  }

  Future<void> _downloadLibraryBooksBackupBeforeDelete({
    required String schoolRef,
    required String schoolId,
    required String schoolName,
  }) async {
    final backup = await _service.developerGetLibraryBooksBackupData(
      developerKey: _developerKeyController.text.trim(),
      schoolRef: schoolRef,
    );
    final rawBooks = backup['books'];
    final books = rawBooks is List
        ? rawBooks
            .whereType<Map>()
            .map((r) => r.map((k, v) => MapEntry('$k', v)))
            .toList()
        : <Map<String, dynamic>>[];
    final rawTransactions = backup['transactions'];
    final transactions = rawTransactions is List
        ? rawTransactions
            .whereType<Map>()
            .map((r) => r.map((k, v) => MapEntry('$k', v)))
            .toList()
        : <Map<String, dynamic>>[];
    final rawStudents = backup['students'];
    final students = rawStudents is List
        ? rawStudents
            .whereType<Map>()
            .map((r) => r.map((k, v) => MapEntry('$k', v)))
            .toList()
        : <Map<String, dynamic>>[];

    final todayIso = DateTime.now().toIso8601String().substring(0, 10);

    // 1. Download Library Book List Excel
    final wbBooks = ec.Excel.createExcel();
    final defBooks = wbBooks.getDefaultSheet() ?? 'Sheet1';
    const sheetBooksName = 'Library Books';
    if (defBooks != sheetBooksName) {
      wbBooks.rename(defBooks, sheetBooksName);
    }
    final sheetBooks = wbBooks[sheetBooksName];
    const bookHeaders = <String>[
      'Book Number / પુસ્તક નંબર',
      'Book Name / પુસ્તકનું નામ',
      'Author / લેખક',
      'Publication / પ્રકાશક',
      'Price ₹ / કિંમત',
      'ISBN',
      'Status / સ્થિતિ',
    ];
    for (var c = 0; c < bookHeaders.length; c++) {
      _setCell(sheetBooks, 0, c, bookHeaders[c]);
    }
    for (var r = 0; r < books.length; r++) {
      final b = books[r];
      final values = <String>[
        '${b['book_number'] ?? r + 1}',
        '${b['title'] ?? b['book_name'] ?? ''}',
        '${b['author'] ?? ''}',
        '${b['publisher'] ?? b['publication'] ?? ''}',
        '${b['price'] ?? ''}',
        '${b['isbn'] ?? ''}',
        b['is_active'] == false ? 'Removed / રદ' : 'Active / સક્રિય',
      ];
      for (var c = 0; c < values.length; c++) {
        _setCell(sheetBooks, r + 1, c, values[c]);
      }
    }
    final bookBytes = wbBooks.encode();
    if (bookBytes != null && bookBytes.isNotEmpty) {
      await PsmFileExportHelper.saveOrShare(
        bytes: Uint8List.fromList(bookBytes),
        filename: '1_LIBRARY_BOOK_LIST_${schoolId}_$todayIso.xlsx',
        title: '1. Library Book List ($schoolName)',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }

    // 2. Download Library Issue/Return Register Excel
    final wbReg = ec.Excel.createExcel();
    final defReg = wbReg.getDefaultSheet() ?? 'Sheet1';
    const sheetRegName = 'Library Register';
    if (defReg != sheetRegName) {
      wbReg.rename(defReg, sheetRegName);
    }
    final sheetReg = wbReg[sheetRegName];
    const regHeaders = <String>[
      'Book Number / પુસ્તક નંબર',
      'Book Name / પુસ્તકનું નામ',
      'Borrower Type',
      'Borrower Name / વાંચનારનું નામ',
      'Class / ધોરણ',
      'Roll / GR',
      'Issue Date / આપ્યા તારીખ',
      'Return Date / પરત તારીખ',
      'Status / સ્થિતિ',
    ];
    for (var c = 0; c < regHeaders.length; c++) {
      _setCell(sheetReg, 0, c, regHeaders[c]);
    }
    for (var r = 0; r < transactions.length; r++) {
      final tx = transactions[r];
      final values = <String>[
        '${tx['book_number'] ?? ''}',
        '${tx['book_title'] ?? tx['title'] ?? ''}',
        '${tx['borrower_type'] ?? 'student'}',
        '${tx['borrower_name'] ?? tx['student_name'] ?? tx['teacher_name'] ?? ''}',
        '${tx['class_label'] ?? ''}',
        '${tx['roll_number'] ?? tx['gr'] ?? ''}',
        '${tx['issue_date'] ?? tx['issued_at'] ?? ''}',
        '${tx['return_date'] ?? tx['returned_at'] ?? ''}',
        '${tx['status'] ?? (tx['returned_at'] != null ? 'Returned' : 'Issued')}',
      ];
      for (var c = 0; c < values.length; c++) {
        _setCell(sheetReg, r + 1, c, values[c]);
      }
    }
    final regBytes = wbReg.encode();
    if (regBytes != null && regBytes.isNotEmpty) {
      await PsmFileExportHelper.saveOrShare(
        bytes: Uint8List.fromList(regBytes),
        filename: '2_LIBRARY_REGISTER_${schoolId}_$todayIso.xlsx',
        title: '2. Library Issue Register ($schoolName)',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }

    // 3. Download School Students Whole Data Excel
    if (students.isNotEmpty) {
      final wbStu = ec.Excel.createExcel();
      final defStu = wbStu.getDefaultSheet() ?? 'Sheet1';
      const sheetStuName = 'Students Whole Data';
      if (defStu != sheetStuName) {
        wbStu.rename(defStu, sheetStuName);
      }
      final sheetStu = wbStu[sheetStuName];
      const stuHeaders = <String>[
        'Status',
        'Class / ધોરણ',
        'Roll No',
        'GR No',
        'Student Name / વિદ્યાર્થીનું નામ',
        'Father Name / પિતાનું નામ',
        'Mother Name / માતાનું નામ',
        'Gender',
        'Category',
        'Caste / જ્ઞાતિ',
        'Religion / ધર્મ',
        'DOB (DD/MM/YYYY)',
        'Enroll School Date',
        'Enroll Class Date',
        'Mobile',
        'UID / Aadhaar',
        'PEN',
        'APAAR ID',
        'Promoted From',
        'Promoted To',
      ];
      for (var c = 0; c < stuHeaders.length; c++) {
        _setCell(sheetStu, 0, c, stuHeaders[c]);
      }
      for (var r = 0; r < students.length; r++) {
        final s = students[r];
        final isGrad8 = '${s['promoted_to_standard'] ?? ''}' == '9' ||
            s['graduated_from_std_8'] == true;
        final status = isGrad8
            ? 'Promoted Std 8->9'
            : (s['is_active'] == false ? 'Deactive' : 'Active');
        final vals = <String>[
          status,
          '${s['class_label'] ?? s['promoted_from_class_label'] ?? s['class_id'] ?? ''}',
          '${s['roll_number'] ?? ''}',
          '${s['gr'] ?? ''}',
          '${s['name'] ?? ''}',
          '${s['father_name'] ?? ''}',
          '${s['mother_name'] ?? ''}',
          '${s['gender'] ?? ''}',
          '${s['category'] ?? ''}',
          '${s['caste'] ?? ''}',
          '${s['religion'] ?? ''}',
          '${s['dd'] ?? ''}/${s['mm'] ?? ''}/${s['yyyy'] ?? ''}',
          '${s['enroll_school'] ?? ''}',
          '${s['enroll_class'] ?? ''}',
          '${s['mobile'] ?? ''}',
          '${s['uid'] ?? ''}',
          '${s['pen'] ?? ''}',
          '${s['apaar_id'] ?? ''}',
          '${s['promoted_from_class_label'] ?? ''}',
          '${s['promoted_to_class_label'] ?? ''}',
        ];
        for (var c = 0; c < vals.length; c++) {
          _setCell(sheetStu, r + 1, c, vals[c]);
        }
      }
      final stuBytes = wbStu.encode();
      if (stuBytes != null && stuBytes.isNotEmpty) {
        await PsmFileExportHelper.saveOrShare(
          bytes: Uint8List.fromList(stuBytes),
          filename: '3_STUDENTS_WHOLE_DATA_${schoolId}_$todayIso.xlsx',
          title: '3. Students Whole Data ($schoolName)',
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }
  }

  Future<void> _deleteAllLibraryBooks(Map<String, dynamic> school) async {
    final dise = TextEditingController();
    final phrase = TextEditingController();
    final schoolId = '${school['school_id'] ?? ''}'.trim();
    final schoolName =
        '${school['school_name_gu'] ?? school['school_name_en'] ?? school['school_name'] ?? ''}'
            .trim();
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text(
            'Delete all library books? / તમામ પુસ્તકો દૂર કરો?',
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected school: $schoolName\nDISE/UDISE: $schoolId',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '• Before deleting, an Excel backup (LIBRARY_BOOKS_BACKUP_<DISE>.xlsx) will be automatically downloaded so the Admin can re-upload the exact same books if needed.\n'
                    '• This permanently deletes every active and removed book, all book-number history, and all issue/return transactions for this school only.',
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: dise,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Type the exact DISE number: $schoolId',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phrase,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Type DELETE ALL BOOKS',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel / રદ કરો'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed:
                  dise.text.trim() == schoolId &&
                      phrase.text.trim() == 'DELETE ALL BOOKS'
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('Download Backup & Delete Library Data'),
            ),
          ],
        ),
      ),
    );
    final typedDise = dise.text.trim();
    dise.dispose();
    phrase.dispose();
    if (approved != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _downloadLibraryBooksBackupBeforeDelete(
        schoolRef: '${school['id']}',
        schoolId: schoolId,
        schoolName: schoolName,
      );
      await _downloadAttendanceBackupBeforeDelete(
        schoolRef: '${school['id']}',
        schoolId: schoolId,
        schoolName: schoolName,
      );
      final result = await _service.developerDeleteAllLibraryBooks(
        developerKey: _developerKeyController.text.trim(),
        schoolRef: '${school['id']}',
        confirmSchoolId: typedDise,
      );
      if (!mounted) return;
      await _reloadSchools();
      _message(
        'Backup downloaded & library cleared for ${result['school_name'] ?? schoolName}: ${result['books_deleted'] ?? 0} books, ${result['transactions_deleted'] ?? 0} issue/return records and ${result['number_history_deleted'] ?? 0} number-history rows deleted.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      _message(_error!, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadAttendanceBackupBeforeDelete({
    required String schoolRef,
    required String schoolId,
    required String schoolName,
    String? fromDateFilter,
    String? toDateFilter,
  }) async {
    final backup = await _service.developerGetAttendanceBackupData(
      developerKey: _developerKeyController.text.trim(),
      schoolRef: schoolRef,
      fromDate: fromDateFilter,
      toDate: toDateFilter,
    );
    final schoolType = DateWiseReportColumn.normalizeSchoolType(
      backup['school_type'],
    );
    final rawClasses = backup['classes'];
    final rawAtt = backup['attendance_rows'];
    final classRows = rawClasses is List
        ? SchoolClassOrder.sorted(
            rawClasses
                .whereType<Map>()
                .map((r) => r.map((k, v) => MapEntry('$k', v)))
                .toList(),
          )
        : <Map<String, dynamic>>[];
    final attendanceRows = rawAtt is List
        ? rawAtt
            .whereType<Map>()
            .map((r) => r.map((k, v) => MapEntry('$k', v)))
            .toList()
        : <Map<String, dynamic>>[];

    final dates = attendanceRows
        .map((r) => '${r['attendance_date'] ?? ''}'.trim())
        .where((d) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d))
        .toList()
      ..sort();
    final todayIso = DateTime.now().toIso8601String().substring(0, 10);
    final fromDate = (fromDateFilter != null && fromDateFilter.isNotEmpty)
        ? fromDateFilter
        : (dates.isNotEmpty ? dates.first : todayIso);
    final toDate = (toDateFilter != null && toDateFilter.isNotEmpty)
        ? toDateFilter
        : (dates.isNotEmpty ? dates.last : todayIso);

    final exportService = SupabaseReportExportService();
    final bytes = await exportService.exportClasswiseAllDataXlsx(
      schoolName: schoolName.isEmpty ? 'School' : schoolName,
      fromDate: fromDate,
      toDate: toDate,
      classRows: classRows,
      attendanceRows: attendanceRows,
      visibleColumnKeys: DateWiseReportColumn.keysForSchoolType(schoolType),
    );
    final filename = 'CLASSWISE_ALL_${schoolId}_${fromDate}_$toDate.xlsx';
    await PsmFileExportHelper.saveOrShare(
      bytes: bytes,
      filename: filename,
      title: 'Attendance Backup ($schoolName)',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  Future<void> _deleteAllAttendanceRecords(Map<String, dynamic> school) async {
    final dise = TextEditingController();
    final phrase = TextEditingController();
    final schoolId = '${school['school_id'] ?? ''}'.trim();
    final schoolName =
        '${school['school_name_gu'] ?? school['school_name_en'] ?? school['school_name'] ?? ''}'
            .trim();
    var deleteMode = 'whole'; // whole or date_range
    var rangeFrom = DateTime(DateTime.now().year, DateTime.now().month, 1);
    var rangeTo = DateTime.now();

    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text(
            'Delete attendance records (Whole or Date Range) / હાજરી રેકોર્ડ દૂર કરો',
          ),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected school: $schoolName\nDISE/UDISE: $schoolId',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '• Before deleting, a Class-wise All Classes Excel backup (CLASSWISE_ALL_<DISE>.xlsx) for the selected scope/date range will be automatically downloaded.\n'
                    '• Choose whether to delete Whole Attendance Data or a specific Date Range (From Date – To Date).',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Whole Attendance Data (સંપૂર્ણ હાજરી)'),
                        selected: deleteMode == 'whole',
                        onSelected: (_) =>
                            setDialogState(() => deleteMode = 'whole'),
                      ),
                      ChoiceChip(
                        label: const Text('Date Range (From – To Date / તારીખ ગાળો)'),
                        selected: deleteMode == 'date_range',
                        onSelected: (_) =>
                            setDialogState(() => deleteMode = 'date_range'),
                      ),
                    ],
                  ),
                  if (deleteMode == 'date_range') ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: dialogContext,
                              initialDate: rangeFrom,
                              firstDate: DateTime(2018, 1, 1),
                              lastDate: DateTime(2035, 12, 31),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                rangeFrom = DateTime(
                                  picked.year,
                                  picked.month,
                                  picked.day,
                                );
                                if (rangeFrom.isAfter(rangeTo)) {
                                  rangeTo = rangeFrom;
                                }
                              });
                            }
                          },
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text('From: ${_dateDisplay(_dateIso(rangeFrom))}'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: dialogContext,
                              initialDate: rangeTo,
                              firstDate: DateTime(2018, 1, 1),
                              lastDate: DateTime(2035, 12, 31),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                rangeTo = DateTime(
                                  picked.year,
                                  picked.month,
                                  picked.day,
                                );
                                if (rangeTo.isBefore(rangeFrom)) {
                                  rangeFrom = rangeTo;
                                }
                              });
                            }
                          },
                          icon: const Icon(Icons.event_outlined),
                          label: Text('To: ${_dateDisplay(_dateIso(rangeTo))}'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: dise,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Type the exact DISE number: $schoolId',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phrase,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Type DELETE ATTENDANCE',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel / રદ કરો'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed:
                  dise.text.trim() == schoolId &&
                      phrase.text.trim() == 'DELETE ATTENDANCE'
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: Text(
                deleteMode == 'date_range'
                    ? 'Download Range Excel & Delete Range'
                    : 'Download Backup & Delete All Attendance',
              ),
            ),
          ],
        ),
      ),
    );
    final typedDise = dise.text.trim();
    dise.dispose();
    phrase.dispose();
    if (approved != true) return;
    final fromIso = deleteMode == 'date_range' ? _dateIso(rangeFrom) : null;
    final toIso = deleteMode == 'date_range' ? _dateIso(rangeTo) : null;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _downloadAttendanceBackupBeforeDelete(
        schoolRef: '${school['id']}',
        schoolId: schoolId,
        schoolName: schoolName,
        fromDateFilter: fromIso,
        toDateFilter: toIso,
      );
      final result = await _service.developerDeleteAllAttendanceRecords(
        developerKey: _developerKeyController.text.trim(),
        schoolRef: '${school['id']}',
        confirmSchoolId: typedDise,
        fromDate: fromIso,
        toDate: toIso,
      );
      if (!mounted) return;
      await _reloadSchools();
      _message(
        'Backup downloaded & attendance cleared for ${result['school_name'] ?? schoolName}: ${result['attendance_days_deleted'] ?? 0} daily class records and ${result['student_marks_deleted'] ?? 0} student attendance marks deleted.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      _message(_error!, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setCell(ec.Sheet sheet, int row, int col, String value) {
    sheet
        .cell(ec.CellIndex.indexByColumnRow(rowIndex: row, columnIndex: col))
        .value = ec.TextCellValue(
      value,
    );
  }

  Future<void> _exportDirectory() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final records = await _service.developerExportDirectory(
        _developerKeyController.text.trim(),
      );
      final workbook = ec.Excel.createExcel();
      final sheet = workbook['School Directory'];
      final headers = <String>[
        'School DISE',
        'School Name (English)',
        'School Name (Gujarati)',
        'Address (English)',
        'Address (Gujarati)',
        'School Type',
        'Validity',
        'School Active',
        'Blocked',
        'Account Name',
        'Role',
        'Registered Mobile',
        'Account Active',
        'Assigned Classes',
        'Account Created',
      ];
      for (var c = 0; c < headers.length; c++)
        _setCell(sheet, 0, c, headers[c]);
      for (var r = 0; r < records.length; r++) {
        final row = records[r];
        final values = <String>[
          '${row['school_id'] ?? ''}',
          '${row['school_name_en'] ?? row['school_name'] ?? ''}',
          '${row['school_name_gu'] ?? ''}',
          '${row['school_address_en'] ?? ''}',
          '${row['school_address_gu'] ?? ''}',
          '${row['school_type'] ?? ''}',
          '${row['validity_date'] ?? ''}',
          '${row['school_active'] ?? ''}',
          '${row['school_blocked'] ?? ''}',
          '${row['account_name'] ?? ''}',
          '${row['account_role'] ?? ''}',
          '${row['registered_mobile'] ?? ''}',
          '${row['account_active'] ?? ''}',
          '${row['assigned_classes'] ?? ''}',
          '${row['account_created_at'] ?? ''}',
        ];
        for (var c = 0; c < values.length; c++)
          _setCell(sheet, r + 1, c, values[c]);
      }
      final bytes = workbook.encode();
      if (bytes == null || bytes.isEmpty)
        throw StateError('Excel export could not be created.');
      final filename =
          'PSM_School_Admin_Teacher_Directory_${DateTime.now().toIso8601String().substring(0, 10)}.xlsx';
      await SharePlus.instance.share(
        ShareParams(
          title: filename,
          files: <XFile>[
            XFile.fromData(
              Uint8List.fromList(bytes),
              name: filename,
              mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ),
          ],
        ),
      );
      if (mounted)
        _message(
          'Directory exported: ${records.length} account records. Passwords are not included for security.',
        );
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectMessageDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _messageDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Message display date',
    );
    if (selected != null && mounted) setState(() => _messageDate = selected);
  }

  Future<void> _loadDeveloperMessages({bool silent = false}) async {
    try {
      final messages = await _service.developerListMessages(
        _developerKeyController.text.trim(),
      );
      if (mounted) setState(() => _developerMessages = messages);
    } catch (error) {
      if (!silent && mounted)
        _message('Could not load Developer messages: $error', isError: true);
    }
  }

  Future<void> _publishDeveloperMessage() async {
    final text = _developerMessageController.text.trim();
    if (text.isEmpty) {
      _message('Enter the message first.', isError: true);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.developerCreateMessage(
        developerKey: _developerKeyController.text.trim(),
        message: text,
        recipientScope: _recipientScope,
        displayDate: _dateIso(_messageDate),
      );
      _developerMessageController.clear();
      await _loadDeveloperMessages(silent: true);
      if (mounted) {
        _message(
          'Developer message scheduled for ${_dateDisplay(_dateIso(_messageDate))}.',
        );
        await _showDeveloperMessagesOneByOnePopup(
          onlyForDateIso: _dateIso(_messageDate),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
        _message(_error!, isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showDeveloperMessagesOneByOnePopup({
    String? onlyForDateIso,
  }) async {
    final todayIso = _dateIso(DateTime.now());
    final targetDate = onlyForDateIso ?? todayIso;
    final activeList = _developerMessages
        .where(
          (m) =>
              m['is_active'] == true &&
              '${m['display_date'] ?? ''}'.trim() == targetDate,
        )
        .toList();
    activeList.sort(
      (a, b) => '${a['created_at'] ?? ''}'.compareTo(
        '${b['created_at'] ?? ''}',
      ),
    );
    if (activeList.isEmpty || !mounted) return;
    for (var i = 0; i < activeList.length; i++) {
      if (!mounted) break;
      final item = activeList[i];
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.campaign_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Developer Pop-up (${i + 1}/${activeList.length}) • ${_dateDisplay(item['display_date'])}',
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              child: SelectableText(
                '${item['message'] ?? ''}',
                style: const TextStyle(fontSize: 15, height: 1.4),
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                i + 1 < activeList.length ? 'Next (${i + 2}/${activeList.length})' : 'OK',
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _exportDeveloperMessagesExcel() async {
    try {
      final book = ec.Excel.createExcel();
      final sheet = book['Sheet1'];
      _putCell(sheet, 0, 0, 'Date');
      _putCell(sheet, 0, 1, 'Message');
      _putCell(sheet, 0, 2, 'RecipientScope');
      for (var i = 0; i < _developerMessages.length; i++) {
        final item = _developerMessages[i];
        _putCell(sheet, i + 1, 0, '${item['display_date'] ?? ''}');
        _putCell(sheet, i + 1, 1, '${item['message'] ?? ''}');
        _putCell(sheet, i + 1, 2, '${item['recipient_scope'] ?? _recipientScope}');
      }
      final bytes = book.encode();
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Could not create the Excel workbook.');
      }
      await _downloadOrShareWorkbook(bytes, 'Developer_Messages.xlsx');
      if (mounted) {
        _message('Exported ${_developerMessages.length} Developer messages to Excel.');
      }
    } catch (error) {
      if (mounted) _message('Excel export failed: $error', isError: true);
    }
  }

  Future<void> _importDeveloperMessagesExcel() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pick = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['xlsx'],
        withData: true,
      );
      if (pick == null || pick.files.isEmpty) return;
      final bytes = pick.files.single.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Could not read the selected Excel file.');
      }
      final book = ec.Excel.decodeBytes(bytes);
      if (book.tables.isEmpty) {
        throw StateError('The Excel workbook has no worksheet.');
      }
      final sheet = book.tables.values.first;
      final rows = sheet.rows
          .map((row) => row.map((cell) => _cellText(cell?.value)).toList())
          .toList();
      if (rows.length < 2) {
        throw StateError(
          'The Excel workbook needs a header row (Date, Message) and at least one message row.',
        );
      }
      final headers = rows.first.map((v) => v.trim().toLowerCase()).toList();
      final dateIdx = headers.indexWhere(
        (v) => v.contains('date') || v.contains('તારીખ'),
      );
      final msgIdx = headers.indexWhere(
        (v) => v.contains('message') || v.contains('msg') || v.contains('સંદેશ'),
      );
      final scopeIdx = headers.indexWhere(
        (v) => v.contains('scope') || v.contains('recipient'),
      );
      final dCol = dateIdx < 0 ? 0 : dateIdx;
      final mCol = msgIdx < 0 ? 1 : msgIdx;

      final payloadMessages = <Map<String, dynamic>>[];
      for (final row in rows.skip(1)) {
        if (row.length <= dCol || row.length <= mCol) continue;
        final rawDate = row[dCol].trim();
        final validDate = _validBulkDate(rawDate);
        final msgText = row[mCol].trim();
        if (validDate.isEmpty || msgText.isEmpty) continue;
        var rowScope = _recipientScope;
        if (scopeIdx >= 0 && scopeIdx < row.length) {
          final rawScope = row[scopeIdx].trim().toLowerCase();
          if (rawScope.contains('teacher') || rawScope.contains('all')) {
            rowScope = 'admins_and_teachers';
          } else if (rawScope.contains('admin')) {
            rowScope = 'admin_only';
          }
        }
        payloadMessages.add(<String, dynamic>{
          'displayDate': validDate,
          'message': msgText,
          'recipientScope': rowScope,
        });
      }
      if (payloadMessages.isEmpty) {
        throw StateError(
          'No valid (Date, Message) rows found in the Excel file.',
        );
      }
      await _service.developerBulkCreateMessages(
        developerKey: _developerKeyController.text.trim(),
        messages: payloadMessages,
        recipientScope: _recipientScope,
      );
      await _loadDeveloperMessages(silent: true);
      if (mounted) {
        _message('Imported ${payloadMessages.length} Developer pop-up messages from Excel.');
        await _showDeveloperMessagesOneByOnePopup();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
        _message(_error!, isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setDeveloperMessageActive(
    Map<String, dynamic> message,
    bool active,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.developerSetMessageActive(
        developerKey: _developerKeyController.text.trim(),
        messageId: '${message['id']}',
        isActive: active,
      );
      await _loadDeveloperMessages(silent: true);
      if (mounted)
        _message(active ? 'Message activated.' : 'Message cancelled.');
    } catch (error) {
      if (mounted) _message('Message change failed: $error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadDeveloperSharedFiles({bool silent = false}) async {
    try {
      final files = await _service.developerListSharedFiles(
        _developerKeyController.text.trim(),
      );
      if (mounted) setState(() => _sharedFiles = files);
    } catch (error) {
      if (!silent && mounted) {
        _message('Could not load shared files: $error', isError: true);
      }
    }
  }

  Future<void> _uploadDeveloperSharedFile() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pick = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (pick == null || pick.files.isEmpty) return;
      final file = pick.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Could not read the selected file.');
      }
      final fileName = file.name.trim().isEmpty ? 'shared_file' : file.name.trim();
      final title = _sharedFileTitleController.text.trim().isEmpty
          ? fileName
          : _sharedFileTitleController.text.trim();
      final desc = _sharedFileDescController.text.trim();
      final ext = (file.extension ?? '').toLowerCase();
      final mime = switch (ext) {
        'pdf' => 'application/pdf',
        'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'xls' => 'application/vnd.ms-excel',
        'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'zip' => 'application/zip',
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'txt' => 'text/plain',
        _ => 'application/octet-stream',
      };
      await _service.developerUploadSharedFile(
        developerKey: _developerKeyController.text.trim(),
        fileName: fileName,
        title: title,
        description: desc,
        mimeType: mime,
        base64Data: base64Encode(bytes),
        sizeBytes: bytes.length,
      );
      _sharedFileTitleController.clear();
      _sharedFileDescController.clear();
      await _loadDeveloperSharedFiles(silent: true);
      if (mounted) {
        _message(
          'File "$fileName" uploaded & shared with School Admins. It will stay available until you delete it.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
        _message(_error!, isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteDeveloperSharedFile(Map<String, dynamic> file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete shared file?'),
        content: Text(
          'Delete "${file['title'] ?? file['file_name']}"? This will permanently remove the file from Cloud Storage and hide it from all Admin screens.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.developerDeleteSharedFile(
        developerKey: _developerKeyController.text.trim(),
        fileId: '${file['id']}',
      );
      await _loadDeveloperSharedFiles(silent: true);
      if (mounted) {
        _message('Shared file deleted from Cloud Storage and removed from Admin screens.');
      }
    } catch (error) {
      if (mounted) _message('Delete failed: $error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // NEW SCHOOL REGISTRATION REQUESTS (sent from the login screen)
  // ---------------------------------------------------------------------------

  Future<void> _loadRegistrationRequests({bool silent = false}) async {
    if (mounted) setState(() => _regLoading = true);
    try {
      final rows = await _service.developerListRegistrationRequests(_developerKeyController.text.trim());
      if (mounted) setState(() => _regRequests = rows);
    } catch (e) {
      if (!silent && mounted) _message(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _regLoading = false);
    }
  }

  String _typeName(Object? t) => _schoolTypes['${t ?? 'mixed'}'] ?? 'મિશ્ર શાળા';

  Future<void> _editRegistrationRequest(Map<String, dynamic> r) async {
    final fields = <String, TextEditingController>{
      'dise_number': TextEditingController(text: '${r['dise_number'] ?? ''}'),
      'school_name_en': TextEditingController(text: '${r['school_name_en'] ?? ''}'),
      'school_name_gu': TextEditingController(text: '${r['school_name_gu'] ?? ''}'),
      'school_address_en': TextEditingController(text: '${r['school_address_en'] ?? ''}'),
      'school_address_gu': TextEditingController(text: '${r['school_address_gu'] ?? ''}'),
      'admin_name': TextEditingController(text: '${r['admin_name'] ?? ''}'),
      'admin_mobile': TextEditingController(text: '${r['admin_mobile'] ?? ''}'.replaceFirst('+91', '')),
      'admin_password': TextEditingController(text: '${r['admin_password'] ?? ''}'),
    };
    const labels = <String, String>{
      'dise_number': 'DISE / UDISE number (cannot change)',
      'school_name_en': 'School name (English)',
      'school_name_gu': 'શાળાનું નામ (ગુજરાતી)',
      'school_address_en': 'School address (English)',
      'school_address_gu': 'શાળાનું સરનામું (ગુજરાતી)',
      'admin_name': 'Admin name',
      'admin_mobile': 'Admin mobile',
      'admin_password': 'Admin password (4–15)',
    };
    var type = '${r['school_type'] ?? 'mixed'}';
    if (!_schoolTypes.containsKey(type)) type = 'mixed';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Edit registration request'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in fields.entries) ...[
                    TextField(
                      controller: e.value,
                      // The request is stored under its DISE number.
                      enabled: e.key != 'dise_number',
                      decoration: InputDecoration(labelText: labels[e.key], border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                  ],
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'School type', border: OutlineInputBorder()),
                    items: [for (final t in _schoolTypes.entries) DropdownMenuItem(value: t.key, child: Text(t.value))],
                    onChanged: (v) => setD(() => type = v ?? 'mixed'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save changes')),
          ],
        ),
      ),
    );
    if (ok == true) {
      setState(() => _busy = true);
      try {
        await _service.developerUpdateRegistrationRequest(
          developerKey: _developerKeyController.text.trim(),
          requestId: '${r['id']}',
          fields: <String, dynamic>{
            for (final e in fields.entries)
              if (e.key != 'dise_number') e.key: e.value.text.trim(),
            'school_type': type,
          },
        );
        await _loadRegistrationRequests();
        if (mounted) _message('Request updated. Check and approve.');
      } catch (e) {
        if (mounted) _message(e.toString().replaceFirst('Exception: ', ''), isError: true);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    for (final c in fields.values) {
      c.dispose();
    }
  }

  Future<void> _approveRegistrationRequest(Map<String, dynamic> r) async {
    var validity = DateTime.now().add(const Duration(days: 365));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Approve and create school?'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r['school_name_en'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text('DISE ${r['dise_number'] ?? ''} • ${_typeName(r['school_type'])}'),
                Text('Admin: ${r['admin_name'] ?? ''} • ${r['admin_mobile'] ?? ''}'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: validity,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (picked != null) setD(() => validity = picked);
                  },
                  icon: const Icon(Icons.event_available_outlined),
                  label: Text('Valid through: ${_dateIso(validity)}'),
                ),
                const SizedBox(height: 8),
                const Text('The school and its Admin account are created exactly as in "Create school + Admin".'),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Approve & create'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _service.developerApproveRegistrationRequest(
        developerKey: _developerKeyController.text.trim(),
        requestId: '${r['id']}',
        validityDate: _dateIso(validity),
      );
      await Future.wait(<Future<void>>[_loadRegistrationRequests(), _reloadSchools()]);
      if (mounted) _message('School ${r['dise_number']} approved and created.');
    } catch (e) {
      if (mounted) _message(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rejectRegistrationRequest(Map<String, dynamic> r) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reject request — DISE ${r['dise_number'] ?? ''}?'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: reason,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Reason (optional)', border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _service.developerRejectRegistrationRequest(
        developerKey: _developerKeyController.text.trim(),
        requestId: '${r['id']}',
        reason: text,
      );
      await _loadRegistrationRequests();
      if (mounted) _message('Request rejected.');
    } catch (e) {
      if (mounted) _message(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _registrationRequestsCard() {
    final pending = _regRequests;
    return Card(
      color: pending.isEmpty ? null : const Color(0xFFFFFBEB),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.app_registration_rounded),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'નવી શાળા નોંધણી વિનંતી — Approval pending (${pending.length})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _regLoading || _busy ? null : () => _loadRegistrationRequests(),
                  icon: _regLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            const Text(
              'Requests sent from "Register New School" on the login screen. Check or edit the details, then approve to create the school.',
            ),
            const SizedBox(height: 10),
            if (pending.isEmpty)
              const Text('No pending requests.', style: TextStyle(fontStyle: FontStyle.italic))
            else
              for (final r in pending)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFCD34D)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${r['school_name_en'] ?? ''}${'${r['school_name_gu'] ?? ''}'.isNotEmpty ? ' / ${r['school_name_gu']}' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text('DISE: ${r['dise_number'] ?? ''}  •  ${_typeName(r['school_type'])}'),
                      Text('Admin: ${r['admin_name'] ?? ''}  •  ${r['admin_mobile'] ?? ''}'),
                      if ('${r['school_address_en'] ?? r['school_address_gu'] ?? ''}'.trim().isNotEmpty)
                        Text('Address: ${'${r['school_address_en'] ?? ''}'.trim().isNotEmpty ? r['school_address_en'] : r['school_address_gu']}'),
                      if ('${r['note'] ?? ''}'.trim().isNotEmpty) Text('Note: ${r['note']}'),
                      Text(
                        'Sent: ${'${r['created_at'] ?? ''}'.replaceFirst('T', ' ').split('.').first} UTC',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _editRegistrationRequest(r),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Check / Edit'),
                          ),
                          FilledButton.icon(
                            onPressed: _busy ? null : () => _approveRegistrationRequest(r),
                            icon: const Icon(Icons.verified_outlined),
                            label: const Text('Approve'),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                            onPressed: _busy ? null : () => _rejectRegistrationRequest(r),
                            icon: const Icon(Icons.block_outlined),
                            label: const Text('Reject'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _developerSharedFilesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_upload_outlined),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Developer File Share (ડેવલપર ફાઈલ શેર — Admin Download)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh shared files',
                  onPressed: _busy ? null : () => _loadDeveloperSharedFiles(),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Share any file with all School Admins. The file stays available until you delete it. In the Admin screen, the download tab is shown automatically only when at least one file is shared, and hidden when empty. Deleting a file also deletes it from Cloud Storage.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sharedFileTitleController,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'File title / label (optional)',
                hintText: 'e.g. Updated Format / Circular / Template',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _sharedFileDescController,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Note / description for Admin (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _uploadDeveloperSharedFile,
                icon: const Icon(Icons.upload_file),
                label: const Text('Select & Upload File for Admins'),
              ),
            ),
            const Divider(height: 24),
            Text(
              'Active Shared Files (${_sharedFiles.length})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            if (_sharedFiles.isEmpty)
              const Text(
                'No files currently shared. The Developer File tab is automatically hidden on Admin screens.',
              ),
            for (final f in _sharedFiles)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  child: Icon(Icons.insert_drive_file_outlined),
                ),
                title: Text(
                  '${f['title'] ?? f['file_name'] ?? 'File'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${f['file_name'] ?? ''} • ${_prettyBytes(f['size_bytes'])} • ${_dateDisplay(f['created_at'])}${'${f['description'] ?? ''}'.trim().isNotEmpty ? '\n${f['description']}' : ''}',
                ),
                isThreeLine: '${f['description'] ?? ''}'.trim().isNotEmpty,
                trailing: IconButton(
                  tooltip: 'Delete file from Cloud Storage',
                  onPressed: _busy ? null : () => _deleteDeveloperSharedFile(f),
                  icon: const Icon(Icons.delete_forever_outlined, color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadUsage({bool silent = false}) async {
    try {
      final usage = await _service.developerGetUsage(
        _developerKeyController.text.trim(),
      );
      if (mounted) setState(() => _usage = usage);
    } catch (error) {
      if (!silent && mounted)
        _message('Could not load Firebase usage: $error', isError: true);
    }
  }

  String _excelTextSpanToPlainText(ec.TextSpan span) {
    final buffer = StringBuffer(span.text ?? '');
    for (final child in span.children ?? const <ec.TextSpan>[]) {
      buffer.write(_excelTextSpanToPlainText(child));
    }
    return buffer.toString();
  }

  String _cellText(ec.CellValue? value) {
    if (value == null) return '';
    if (value is ec.TextCellValue)
      return _excelTextSpanToPlainText(value.value);
    if (value is ec.IntCellValue) return '${value.value}';
    if (value is ec.DoubleCellValue) return '${value.value}';
    if (value is ec.BoolCellValue) return value.value ? 'TRUE' : 'FALSE';
    if (value is ec.DateCellValue)
      return _dateIso(DateTime(value.year, value.month, value.day));
    if (value is ec.DateTimeCellValue)
      return _dateIso(DateTime(value.year, value.month, value.day));
    if (value is ec.FormulaCellValue) return value.formula;
    return value.toString();
  }

  void _putCell(ec.Sheet sheet, int row, int col, String value) {
    sheet
        .cell(ec.CellIndex.indexByColumnRow(rowIndex: row, columnIndex: col))
        .value = ec.TextCellValue(
      value,
    );
  }

  Future<void> _downloadOrShareWorkbook(
    List<int> bytes,
    String filename,
  ) async {
    final data = Uint8List.fromList(bytes);
    const mime =
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    if (kIsWeb) {
      final blob = html.Blob(<Object>[data], mime);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..download = filename
        ..style.display = 'none';
      html.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
      Future<void>.delayed(
        const Duration(seconds: 1),
        () => html.Url.revokeObjectUrl(url),
      );
    } else {
      await SharePlus.instance.share(
        ShareParams(
          title: filename,
          files: <XFile>[XFile.fromData(data, name: filename, mimeType: mime)],
        ),
      );
    }
  }

  Future<void> _downloadSchoolTemplate() async {
    try {
      final book = ec.Excel.createExcel();
      final sheet = book['School Registration'];
      final headers = <String>[
        'school_name_en',
        'school_name_gu',
        'school_address_en',
        'school_address_gu',
        'dise_number',
        'admin_name',
        'admin_mobile',
        'admin_password',
        'school_type',
        'validity_date',
        'active',
      ];
      for (var col = 0; col < headers.length; col++) {
        _putCell(sheet, 0, col, headers[col]);
      }
      final bytes = book.encode();
      if (bytes == null || bytes.isEmpty)
        throw StateError('Could not generate the Excel template.');
      await _downloadOrShareWorkbook(
        bytes,
        'PSM_Bulk_School_Registration_Template.xlsx',
      );
      if (mounted)
        _message(
          'Blank school registration template is ready. Keep the DISE column as text to preserve leading zeros.',
        );
    } catch (error) {
      if (mounted) _message('Template download failed: $error', isError: true);
    }
  }

  String _normalizeHeader(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  String _normalSchoolType(String value) {
    final t = value.trim().toLowerCase();
    if (const ['boys', 'boy', 'boys_only', 'કુમાર શાળા', 'કુમાર'].contains(t))
      return 'boys';
    if (const [
      'girls',
      'girl',
      'girls_only',
      'કન્યા શાળા',
      'કન્યા',
    ].contains(t))
      return 'girls';
    if (const [
      'mixed',
      'coed',
      'co_ed',
      'co_education',
      'મિશ્ર શાળા',
      'મિશ્ર',
    ].contains(t))
      return 'mixed';
    return t;
  }

  String _validBulkDate(String input) {
    final raw = input.trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
      final iso = DateTime.tryParse(raw);
      if (iso != null && _dateIso(iso) == raw) return raw;
    }
    final parts = raw.split(RegExp(r'[/.-]')).map((x) => x.trim()).toList();
    if (parts.length == 3) {
      int? day, month, year;
      if (parts[0].length == 4) {
        year = int.tryParse(parts[0]);
        month = int.tryParse(parts[1]);
        day = int.tryParse(parts[2]);
      } else {
        day = int.tryParse(parts[0]);
        month = int.tryParse(parts[1]);
        year = int.tryParse(parts[2]);
      }
      if (day != null &&
          month != null &&
          year != null &&
          year >= 2000 &&
          year <= 2100) {
        final d = DateTime(year, month, day);
        if (d.year == year && d.month == month && d.day == day)
          return _dateIso(d);
      }
    }
    return '';
  }

  Future<void> _pickAndPreviewBulkSchools() async {
    setState(() {
      _busy = true;
      _error = null;
      _bulkPreview = <Map<String, dynamic>>[];
      _bulkResults = <Map<String, dynamic>>[];
    });
    try {
      final pick = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['xlsx'],
        withData: true,
      );
      if (pick == null || pick.files.isEmpty) return;
      final bytes = pick.files.single.bytes;
      if (bytes == null || bytes.isEmpty)
        throw StateError('Could not read the selected Excel workbook.');
      final book = ec.Excel.decodeBytes(bytes);
      if (book.tables.isEmpty)
        throw StateError('The workbook has no worksheet.');
      final sheet =
          book.tables['School Registration'] ?? book.tables.values.first;
      final rows = sheet.rows
          .map((row) => row.map((cell) => _cellText(cell?.value)).toList())
          .toList();
      if (rows.length < 2)
        throw StateError(
          'Add at least one school record under the header row.',
        );
      final headers = rows.first.map(_normalizeHeader).toList();
      int findCol(List<String> aliases) {
        for (final alias in aliases) {
          final ix = headers.indexOf(_normalizeHeader(alias));
          if (ix >= 0) return ix;
        }
        return -1;
      }

      String valueAt(List<String> row, List<String> aliases) {
        final ix = findCol(aliases);
        return ix < 0 || ix >= row.length ? '' : row[ix].trim();
      }

      final prepared = <Map<String, dynamic>>[];
      final usedDise = <String>{};
      final registeredDise = _schools
          .map((s) => '${s['school_id'] ?? ''}'.trim())
          .where((s) => s.isNotEmpty)
          .toSet();
      for (var i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.every((v) => v.trim().isEmpty)) continue;
        final nameEn = valueAt(row, const [
          'school_name_en',
          'school name english',
          'english school name',
        ]);
        final nameGu = valueAt(row, const [
          'school_name_gu',
          'school name gujarati',
          'gujarati school name',
        ]);
        final addressEn = valueAt(row, const [
          'school_address_en',
          'school address english',
          'english address',
        ]);
        final addressGu = valueAt(row, const [
          'school_address_gu',
          'school address gujarati',
          'gujarati address',
        ]);
        final dise = valueAt(row, const [
          'dise_number',
          'dise',
          'udise_number',
          'school_id',
          'school dise',
        ]);
        final adminName = valueAt(row, const ['admin_name', 'admin name']);
        final mobile = valueAt(row, const [
          'admin_mobile',
          'admin mobile',
          'mobile',
        ]);
        final password = valueAt(row, const [
          'admin_password',
          'admin password',
          'password',
        ]);
        final schoolType = _normalSchoolType(
          valueAt(row, const ['school_type', 'school type']),
        );
        final validity = _validBulkDate(
          valueAt(row, const ['validity_date', 'validity date', 'expiry date']),
        );
        final activeRaw = valueAt(row, const [
          'active',
          'is_active',
          'school active',
        ]).toLowerCase();
        final isActive =
            activeRaw.isEmpty ||
            const ['true', 'yes', '1', 'active'].contains(activeRaw);
        final issues = <String>[];
        if (nameEn.length < 2) issues.add('English school name required');
        if (nameGu.length < 2) issues.add('Gujarati school name required');
        if (addressEn.length < 3) issues.add('English school address required');
        if (addressGu.length < 3)
          issues.add('Gujarati school address required');
        if (!RegExp(r'^\d{4,20}$').hasMatch(dise))
          issues.add('DISE must be 4–20 digits');
        if (registeredDise.contains(dise))
          issues.add('DISE already registered');
        if (dise.isNotEmpty && !usedDise.add(dise))
          issues.add('Duplicate DISE within this file');
        if (adminName.length < 2) issues.add('Admin name required');
        if (!_isValidIndianMobile(mobile)) issues.add('Invalid Admin mobile');
        if (password.length < 4 || password.length > 15)
          issues.add('Password must be 4 to 15 characters');
        if (!const ['boys', 'girls', 'mixed'].contains(schoolType))
          issues.add('School type must be boys/girls/mixed');
        if (validity.isEmpty)
          issues.add('Validity date invalid (use YYYY-MM-DD or DD/MM/YYYY)');
        prepared.add(<String, dynamic>{
          'rowNumber': i + 1,
          'diseNumber': dise,
          'error': issues.join('; '),
          'fields': <String, dynamic>{
            'rowNumber': i + 1,
            'schoolNameEn': nameEn,
            'schoolNameGu': nameGu,
            'schoolAddressEn': addressEn,
            'schoolAddressGu': addressGu,
            'diseNumber': dise,
            'adminName': adminName,
            'adminMobile': mobile,
            'adminPassword': password,
            'schoolType': schoolType,
            'validityDate': validity,
            'isActive': isActive,
          },
        });
      }
      if (prepared.isEmpty)
        throw StateError('No non-empty school rows were found.');
      if (mounted) setState(() => _bulkPreview = prepared);
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createValidBulkSchools() async {
    final valid = _bulkPreview
        .where((row) => '${row['error'] ?? ''}'.isEmpty)
        .toList();
    if (valid.isEmpty) {
      _message('There are no valid rows to create.', isError: true);
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create bulk school accounts?'),
        content: Text(
          'This will create ${valid.length} school and Admin account(s). ${_bulkPreview.length - valid.length} invalid row(s) will be skipped. Account passwords are sent to Supabase only and are never included in this summary.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Create valid rows'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    setState(() {
      _busy = true;
      _error = null;
      _bulkResults = <Map<String, dynamic>>[];
    });
    final results = <Map<String, dynamic>>[];
    try {
      final rows = valid
          .map((item) => Map<String, dynamic>.from(item['fields'] as Map))
          .toList();
      for (var offset = 0; offset < rows.length; offset += 20) {
        final batch = rows.skip(offset).take(20).toList();
        final response = await _service.developerBulkCreateSchools(
          developerKey: _developerKeyController.text.trim(),
          rows: batch,
        );
        final rawResults = response['results'];
        if (rawResults is List) {
          for (final item in rawResults.whereType<Map>()) {
            results.add(item.map((k, v) => MapEntry(k.toString(), v)));
          }
        }
        // Preserve each committed batch in the UI so a later network failure
        // cannot hide accounts that were already created successfully.
        if (mounted)
          setState(
            () => _bulkResults = List<Map<String, dynamic>>.from(results),
          );
      }
      if (mounted) {
        await _reloadSchools();
        final created = results.where((r) => r['success'] == true).length;
        final failed = results.length - created;
        _message(
          'Bulk creation finished: $created created, $failed failed. Invalid preview rows were skipped.',
        );
      }
    } catch (error) {
      if (mounted)
        setState(() {
          _bulkResults = List<Map<String, dynamic>>.from(results);
          _error = error.toString().replaceFirst('Exception: ', '');
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _prettyBytes(dynamic input) {
    final bytes = input is num
        ? input.toDouble()
        : double.tryParse('$input') ?? 0;
    if (bytes >= 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    if (bytes >= 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${bytes.round()} B';
  }

  double _usageRatio(dynamic used, dynamic limit) {
    final u = used is num ? used.toDouble() : double.tryParse('$used') ?? 0;
    final l = limit is num ? limit.toDouble() : double.tryParse('$limit') ?? 0;
    if (l <= 0) return 0;
    return (u / l).clamp(0.0, 1.0).toDouble();
  }

  Widget _developerMessagesCard() {
    final recipientItems = const <DropdownMenuItem<String>>[
      DropdownMenuItem(
        value: 'admin_only',
        child: Text('Admin Only — all schools'),
      ),
      DropdownMenuItem(
        value: 'admins_and_teachers',
        child: Text('Admin + All Teachers — all schools'),
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.campaign_outlined),
                SizedBox(width: 8),
                Flexible(child: Text(
                  'Developer Message / Popup',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                )),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'The popup appears only on the selected India date. Each recipient sees each message until they press OK once.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _developerMessageController,
              minLines: 3,
              maxLines: 6,
              maxLength: 5000,
              decoration: const InputDecoration(
                labelText: 'Message',
                hintText: 'Enter a platform message…',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: _recipientScope,
              items: recipientItems,
              decoration: const InputDecoration(
                labelText: 'Recipients',
                border: OutlineInputBorder(),
              ),
              onChanged: _busy
                  ? null
                  : (v) {
                      if (v != null) setState(() => _recipientScope = v);
                    },
            ),
            const SizedBox(height: 10),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Display date (India)',
                border: OutlineInputBorder(),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(_dateDisplay(_dateIso(_messageDate)))),
                  TextButton.icon(
                    onPressed: _busy ? null : _selectMessageDate,
                    icon: const Icon(Icons.calendar_month),
                    label: const Text('Select date'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _publishDeveloperMessage,
                icon: const Icon(Icons.send_outlined),
                label: const Text('Schedule / Publish Message'),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _importDeveloperMessagesExcel,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import Excel (Date & Message)'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _exportDeveloperMessagesExcel,
                  icon: const Icon(Icons.download),
                  label: const Text('Export Excel'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _showDeveloperMessagesOneByOnePopup(),
                  icon: const Icon(Icons.slideshow_outlined),
                  label: const Text("Show Today's Pop-ups One-by-One"),
                ),
              ],
            ),
            const Divider(height: 26),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Recent messages',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh messages',
                  onPressed: _busy ? null : () => _loadDeveloperMessages(),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_developerMessages.isEmpty)
              const Text('No Developer messages yet.'),
            for (final item in _developerMessages.take(10))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  item['is_active'] == true
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                ),
                title: Text(
                  '${item['message'] ?? ''}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${item['recipient_scope'] == 'admin_only' ? 'Admin Only' : 'Admin + All Teachers'} • ${_dateDisplay(item['display_date'])} • ${item['is_active'] == true ? 'Active' : 'Cancelled'}',
                ),
                trailing: IconButton(
                  tooltip: item['is_active'] == true
                      ? 'Cancel message'
                      : 'Activate message',
                  onPressed: _busy
                      ? null
                      : () => _setDeveloperMessageActive(
                          item,
                          item['is_active'] != true,
                        ),
                  icon: Icon(
                    item['is_active'] == true
                        ? Icons.cancel_outlined
                        : Icons.play_circle_outline,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _bulkRowSubtitle(Map<String, dynamic> row) {
    final rawFields = row['fields'];
    final fields = rawFields is Map
        ? rawFields.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    final name = '${fields['schoolNameEn'] ?? ''}';
    final error = '${row['error'] ?? ''}';
    return error.isEmpty ? name : '$name\n$error';
  }

  Widget _bulkSchoolsCard() {
    final validCount = _bulkPreview
        .where((r) => '${r['error'] ?? ''}'.isEmpty)
        .length;
    final invalidCount = _bulkPreview.length - validCount;
    final successful = _bulkResults.where((r) => r['success'] == true).length;
    final failed = _bulkResults.length - successful;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.upload_file_outlined),
                SizedBox(width: 8),
                Flexible(child: Text(
                  'Bulk School Account Creation',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                )),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Download the blank template whenever needed. Upload and validate the workbook before creating accounts. DISE/UDISE must be kept as text to preserve leading zeros.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _downloadSchoolTemplate,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Download Excel Template'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _pickAndPreviewBulkSchools,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Upload & Validate Excel'),
                ),
              ],
            ),
            if (_bulkPreview.isNotEmpty) ...[
              const Divider(height: 26),
              Text(
                'Validation: ${_bulkPreview.length} row(s) • $validCount valid • $invalidCount invalid',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              for (final row in _bulkPreview.take(50))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    '${row['error'] ?? ''}'.isEmpty
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    color: '${row['error'] ?? ''}'.isEmpty
                        ? Colors.green
                        : Colors.red,
                  ),
                  title: Text(
                    'Excel row ${row['rowNumber']} • DISE ${row['diseNumber']}',
                  ),
                  subtitle: Text(_bulkRowSubtitle(row)),
                ),
              if (_bulkPreview.length > 50)
                Text('Showing first 50 of ${_bulkPreview.length} rows.'),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy || validCount == 0
                      ? null
                      : _createValidBulkSchools,
                  icon: const Icon(Icons.playlist_add_check_circle_outlined),
                  label: Text('Create $validCount valid row(s)'),
                ),
              ),
            ],
            if (_bulkResults.isNotEmpty) ...[
              const Divider(height: 26),
              Text(
                'Creation result: $successful successful • $failed failed',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final row
                  in _bulkResults.where((r) => r['success'] != true).take(30))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.error_outline, color: Colors.red),
                  title: Text(
                    'Excel row ${row['rowNumber']} • DISE ${row['diseNumber']}',
                  ),
                  subtitle: Text('${row['error'] ?? 'Failed'}'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _usageCard() {
    final dbBytes = _usage['database_bytes'] ?? 0;
    final storageBytes = _usage['storage_bytes'] ?? 0;
    final dbLimit = _usage['database_free_plan_reference_bytes'] ?? 524288000;
    final storageLimit =
        _usage['storage_free_plan_reference_bytes'] ?? 1073741824;
    final buckets = (_usage['bucket_usage'] is List)
        ? (_usage['bucket_usage'] as List)
        : const <dynamic>[];
    Widget meter(String title, dynamic used, dynamic limit) {
      final ratio = _usageRatio(used, limit);
      final percent = (ratio * 100).round();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text('${_prettyBytes(used)} / ${_prettyBytes(limit)}'),
              ],
            ),
            const SizedBox(height: 5),
            LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              color: percent >= 90
                  ? Colors.red
                  : percent >= 80
                  ? Colors.orange
                  : null,
            ),
            const SizedBox(height: 3),
            Text(
              '$percent% of the displayed reference limit',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.storage_outlined),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Firebase Usage & Storage (Cloud Firestore & Storage)',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh usage',
                  onPressed: _busy ? null : () => _loadUsage(),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_usage.isEmpty)
              const Text('Usage has not been loaded yet. Tap Refresh.'),
            if (_usage.isNotEmpty) ...[
              meter('Cloud Firestore document usage (estimated)', dbBytes, dbLimit),
              meter(
                'Firebase Cloud Storage / school assets',
                storageBytes,
                storageLimit,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(Icons.school_outlined),
                    label: Text('Schools: ${_usage['school_count'] ?? '—'}'),
                  ),
                  Chip(
                    avatar: const Icon(Icons.people_outline),
                    label: Text('Teachers: ${_usage['teacher_count'] ?? '—'}'),
                  ),
                  Chip(
                    avatar: const Icon(Icons.face_outlined),
                    label: Text(
                      'Students: ${_usage['student_count_available'] == true ? (_usage['student_count'] ?? '0') : 'table unavailable'}',
                    ),
                  ),
                ],
              ),
              if (buckets.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  'Storage bucket estimates',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final bucket in buckets.whereType<Map>().take(20))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(
                      '${bucket['bucket_name'] ?? bucket['bucket_id']}',
                    ),
                    subtitle: Text('${bucket['object_count'] ?? 0} object(s)'),
                    trailing: Text(_prettyBytes(bucket['bytes'])),
                  ),
              ],
              const SizedBox(height: 4),
              Text(
                'Measured: ${_usage['measured_at'] ?? 'unknown'}. Free-plan limits are references only; verify the current quota and billed usage in the Firebase Console.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _setActive(Map<String, dynamic> school, bool value) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(value ? 'Activate school?' : 'Deactivate school?'),
        content: Text(
          value
              ? 'This school will be allowed to sign in again, subject to its validity date.'
              : 'This school will no longer be able to sign in or access its data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _runSchoolAction(
      () => _service.developerSetActive(
        developerKey: _developerKeyController.text.trim(),
        schoolRef: '${school['id']}',
        isActive: value,
      ),
    );
  }

  Future<void> _setBlocked(Map<String, dynamic> school, bool value) async {
    final reasonController = TextEditingController(
      text: '${school['block_reason'] ?? ''}',
    );
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(value ? 'Block school?' : 'Unblock school?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value
                  ? 'While blocked, Admin can download reports only. Admin and teachers cannot upload, edit, or save changes.'
                  : 'Unblocking restores permitted editing, uploads, and attendance operations.',
            ),
            if (value) ...[
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(value ? 'Block' : 'Unblock'),
          ),
        ],
      ),
    );
    if (accepted != true) {
      reasonController.dispose();
      return;
    }
    await _runSchoolAction(
      () => _service.developerSetBlocked(
        developerKey: _developerKeyController.text.trim(),
        schoolRef: '${school['id']}',
        isBlocked: value,
        blockReason: reasonController.text.trim(),
      ),
    );
    reasonController.dispose();
  }

  Future<void> _changeValidity(Map<String, dynamic> school) async {
    final existing =
        DateTime.tryParse('${school['validity_date'] ?? ''}') ?? _validityDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: existing,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Select school validity date',
    );
    if (selected == null) return;
    await _runSchoolAction(
      () => _service.developerUpdateValidity(
        developerKey: _developerKeyController.text.trim(),
        schoolRef: '${school['id']}',
        validityDate: _dateIso(selected),
      ),
    );
  }

  Future<void> _runSchoolAction(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _reloadSchools();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
        _message(_error!, isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectValidityDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _validityDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'School validity date',
    );
    if (selected != null && mounted) setState(() => _validityDate = selected);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final diseQuery = _schoolSearchController.text.trim().toLowerCase();
    final visibleSchools = _schools
        .where(
          (school) =>
              '${school['school_id'] ?? ''}'.toLowerCase().contains(diseQuery),
        )
        .toList();
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Developer • School Management'),
              actions: [
                if (_unlocked)
                  IconButton(
                    tooltip: 'Refresh schools',
                    onPressed: _busy ? null : _reloadSchools,
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            )
          : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.admin_panel_settings_outlined),
                        SizedBox(width: 8),
                        Text(
                          'Developer access',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter the server-configured Developer key. It is kept only in this screen state and is not stored in the app.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _developerKeyController,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      autofillHints: const <String>[],
                      enabled: !_busy && !_unlocked,
                      decoration: const InputDecoration(
                        labelText: 'Developer key (Never saved — enter each time)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.key_outlined),
                      ),
                      onSubmitted: (_) => _unlock(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: _unlocked
                          ? OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                      _unlocked = false;
                                      _developerKeyController.clear();
                                    }),
                              icon: const Icon(Icons.lock_outline),
                              label: const Text('Lock Developer tab'),
                            )
                          : FilledButton.icon(
                              onPressed: _busy ? null : _unlock,
                              icon: const Icon(Icons.lock_open_outlined),
                              label: Text(
                                _busy ? 'Please wait…' : 'Unlock Developer tab',
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              _ErrorCard(message: _error!),
            ],
            if (_busy) const LinearProgressIndicator(),
            if (_unlocked) ...[
              const SizedBox(height: 16),
              _registrationRequestsCard(),
              const SizedBox(height: 12),
              const _PrintServiceCard(),
              const SizedBox(height: 12),
              _developerSharedFilesCard(),
              const SizedBox(height: 12),
              _developerMessagesCard(),
              const SizedBox(height: 12),
              _bulkSchoolsCard(),
              const SizedBox(height: 12),
              _usageCard(),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.add_business_outlined),
                            SizedBox(width: 8),
                            Text(
                              'Create school + Admin',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'The DISE/UDISE number is the school login ID for both Admin and teachers.',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _schoolNameController,
                          decoration: const InputDecoration(
                            labelText: 'School name (English)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.school_outlined),
                          ),
                          validator: (v) => (v ?? '').trim().length < 2
                              ? 'Enter the school name in English.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _schoolNameGuController,
                          decoration: const InputDecoration(
                            labelText: 'School name (Gujarati)',
                            hintText: 'ગુજરાતીમાં શાળાનું નામ',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.translate_outlined),
                          ),
                          validator: (v) => (v ?? '').trim().length < 2
                              ? 'Enter the school name in Gujarati.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _schoolAddressEnController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'School address (English)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.location_on_outlined),
                          ),
                          validator: (v) => (v ?? '').trim().length < 3
                              ? 'Enter the school address in English.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _schoolAddressGuController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'School address (Gujarati)',
                            hintText: 'ગુજરાતીમાં શાળાનું સરનામું',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.location_on_outlined),
                          ),
                          validator: (v) => (v ?? '').trim().length < 3
                              ? 'Enter the school address in Gujarati.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _diseController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'School DISE / UDISE number',
                            helperText:
                                'Numeric ID; leading zeros are preserved.',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.numbers_outlined),
                          ),
                          validator: (v) =>
                              !RegExp(r'^\d{4,20}$').hasMatch((v ?? '').trim())
                              ? 'Enter 4–20 digits.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _adminNameController,
                          decoration: const InputDecoration(
                            labelText: 'Admin name',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (v) => (v ?? '').trim().length < 2
                              ? 'Enter Admin name.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _adminMobileController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Admin registered mobile number',
                            helperText:
                                'Required for SMS OTP password recovery.',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.phone_android_outlined),
                          ),
                          validator: (v) => !_isValidIndianMobile(v ?? '')
                              ? 'Enter a valid Indian mobile number.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _adminPasswordController,
                          obscureText: true,
                          maxLength: 15,
                          decoration: const InputDecoration(
                            labelText: 'Admin password',
                            helperText: '4 to 15 characters. Share securely with the Admin.',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.password_outlined),
                          ),
                          validator: (v) =>
                              ((v ?? '').length < 4 || (v ?? '').length > 15)
                              ? 'Password must contain 4 to 15 characters.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _schoolType,
                          decoration: const InputDecoration(
                            labelText: 'School type',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.groups_outlined),
                          ),
                          items: _schoolTypes.entries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value),
                                ),
                              )
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (value) {
                                  if (value != null)
                                    setState(() => _schoolType = value);
                                },
                        ),
                        const SizedBox(height: 12),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Validity date',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.event_available_outlined),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _dateDisplay(_dateIso(_validityDate)),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _busy ? null : _selectValidityDate,
                                icon: const Icon(Icons.calendar_month),
                                label: const Text('Select'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _createSchool,
                            icon: const Icon(Icons.add_circle_outline),
                            label: Text(
                              _busy
                                  ? 'Creating…'
                                  : 'Create School and Admin account',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Registered schools',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _exportDirectory,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Export directory'),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text('${visibleSchools.length}/${_schools.length}'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _schoolSearchController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Search registered school by DISE/UDISE code',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: _schoolSearchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _schoolSearchController.clear();
                            setState(() {});
                          },
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              if (_schools.isEmpty && !_busy)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('No schools have been created yet.'),
                    ),
                  ),
                ),
              if (_schools.isNotEmpty && visibleSchools.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No registered school matches that DISE/UDISE code.',
                      ),
                    ),
                  ),
                ),
              for (final school in visibleSchools) _schoolCard(school),
            ],
          ],
        ),
      ),
    );
  }

  bool _isPrevAttendanceUploadActiveForSchool(Map<String, dynamic> school) {
    if (school['prev_attendance_upload_enabled'] != true) return false;
    final expStr = '${school['prev_attendance_upload_expires_at'] ?? ''}'.trim();
    final expDt = DateTime.tryParse(expStr)?.toUtc();
    if (expDt == null) return false;
    return DateTime.now().toUtc().isBefore(expDt);
  }

  String _prevAttendanceUploadRemainingLabel(Map<String, dynamic> school) {
    final expStr = '${school['prev_attendance_upload_expires_at'] ?? ''}'.trim();
    final expDt = DateTime.tryParse(expStr)?.toUtc();
    if (expDt == null) return '24h';
    final diff = expDt.difference(DateTime.now().toUtc());
    if (diff.isNegative) return 'Expired';
    final hrs = diff.inHours;
    final mins = diff.inMinutes.remainder(60);
    return '${hrs}h ${mins}m left';
  }

  Future<void> _togglePrevAttendanceUpload(
    Map<String, dynamic> school,
    bool enable,
  ) async {
    final schoolName =
        '${school['school_name_gu'] ?? school['school_name_en'] ?? school['school_name'] ?? ''}'
            .trim();
    final schoolId = '${school['school_id'] ?? ''}'.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          enable
              ? 'Activate Previous Attendance Upload (24 Hours)?'
              : 'Deactivate Previous Attendance Upload?',
        ),
        content: Text(
          enable
              ? 'School: $schoolName (DISE: $schoolId)\n\n'
                'This will activate the "Upload Previous Daily Attendance (Class-wise Excel)" tab inside the REPORTS section for this school Admin ONLY.\n\n'
                '• It remains active for 24 hours only and automatically deactivates after 24 hours.\n'
                '• You can also manually deactivate it anytime.'
              : 'School: $schoolName (DISE: $schoolId)\n\n'
                'This will immediately hide and deactivate the Previous Daily Attendance Upload button for this school.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(enable ? 'Activate for 24 Hours' : 'Deactivate Now'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runSchoolAction(
      () => _service.developerSetPrevAttendanceUpload(
        developerKey: _developerKeyController.text.trim(),
        schoolRef: '${school['id']}',
        enabled: enable,
      ),
    );
    if (mounted) {
      _message(
        enable
            ? 'Previous Attendance Upload activated for 24 hours for $schoolName.'
            : 'Previous Attendance Upload deactivated for $schoolName.',
      );
    }
  }

  Widget _schoolCard(Map<String, dynamic> school) {
    final active = school['is_active'] == true;
    final blocked = school['is_blocked'] == true;
    final expired = school['expired'] == true;
    final prevUploadActive = _isPrevAttendanceUploadActiveForSchool(school);
    final prevUploadRem = _prevAttendanceUploadRemainingLabel(school);
    final typeKey = '${school['school_type'] ?? 'mixed'}';
    final statusText = !active
        ? 'DEACTIVATED'
        : expired
        ? 'EXPIRED'
        : blocked
        ? 'BLOCKED • READ ONLY'
        : 'ACTIVE';
    final statusColor = !active || expired
        ? Colors.red
        : blocked
        ? Colors.deepOrange
        : Colors.green;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            ListTile(
              leading: CircleAvatar(
                child: Icon(active ? Icons.school : Icons.school_outlined),
              ),
              title: Text(
                '${school['school_name_en'] ?? school['school_name'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ('${school['school_name_gu'] ?? ''}'.trim().isNotEmpty)
                      Text('ગુજરાતી નામ: ${school['school_name_gu']}'),
                    if ('${school['school_address_en'] ?? ''}'
                        .trim()
                        .isNotEmpty)
                      Text('Address: ${school['school_address_en']}'),
                    if ('${school['school_address_gu'] ?? ''}'
                        .trim()
                        .isNotEmpty)
                      Text('સરનામું: ${school['school_address_gu']}'),
                    Text(
                      'DISE: ${school['school_id'] ?? ''}  •  ${_schoolTypes[typeKey] ?? typeKey}',
                    ),
                    Text('Admin: ${school['admin_name'] ?? 'Not found'}'),
                    Text(
                      'Registered mobile: ${school['admin_mobile'] ?? 'Not registered'}',
                    ),
                    Text('Validity: ${_dateDisplay(school['validity_date'])}'),
                    const SizedBox(height: 5),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (blocked &&
                        '${school['block_reason'] ?? ''}'.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Reason: ${school['block_reason']}',
                          style: const TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ),
                  ],
                ),
              ),
              isThreeLine: true,
              trailing: PopupMenuButton<String>(
                enabled: !_busy,
                onSelected: (value) {
                  if (value == 'active') _setActive(school, !active);
                  if (value == 'blocked') _setBlocked(school, !blocked);
                  if (value == 'validity') _changeValidity(school);
                  if (value == 'edit') _editSchool(school);
                  if (value == 'delete') _deleteSchool(school);
                  if (value == 'delete_library') _deleteAllLibraryBooks(school);
                  if (value == 'prev_attendance_upload') {
                    _togglePrevAttendanceUpload(school, !prevUploadActive);
                  }
                  if (value == 'delete_attendance') {
                    _deleteAllAttendanceRecords(school);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'active',
                    child: Text(
                      active ? 'Deactivate school' : 'Activate school',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'blocked',
                    child: Text(
                      blocked ? 'Unblock school' : 'Block school (read-only)',
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'validity',
                    child: Text('Change validity date'),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Edit school / Admin / mobile / password'),
                  ),
                  const PopupMenuItem(
                    value: 'delete_library',
                    child: Text(
                      'Developer: delete all library books for this school',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'prev_attendance_upload',
                    child: Text(
                      prevUploadActive
                          ? 'Developer: Deactivate Previous Attendance Upload ($prevUploadRem)'
                          : 'Developer: Activate Previous Attendance Upload (24 Hours)',
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete_attendance',
                    child: Text(
                      'Developer: delete all attendance records for this school (Auto-Backup)',
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Permanently delete school'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _setActive(school, !active),
                          icon: Icon(
                            active
                                ? Icons.pause_circle_outline
                                : Icons.play_circle_outline,
                          ),
                          label: Text(active ? 'Deactivate' : 'Activate'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _busy
                              ? null
                              : () => _setBlocked(school, !blocked),
                          icon: Icon(
                            blocked ? Icons.lock_open_outlined : Icons.lock_outline,
                          ),
                          label: Text(blocked ? 'Unblock' : 'Block'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: prevUploadActive
                          ? Colors.teal.shade50
                          : null,
                      foregroundColor: prevUploadActive
                          ? Colors.teal.shade900
                          : null,
                      side: BorderSide(
                        color: prevUploadActive
                            ? Colors.teal.shade600
                            : Colors.grey.shade400,
                      ),
                    ),
                    onPressed: _busy
                        ? null
                        : () => _togglePrevAttendanceUpload(
                              school,
                              !prevUploadActive,
                            ),
                    icon: Icon(
                      prevUploadActive
                          ? Icons.timer_outlined
                          : Icons.upload_file_outlined,
                      size: 18,
                    ),
                    label: Text(
                      prevUploadActive
                          ? 'Previous Attendance Upload: ACTIVE ($prevUploadRem) • Tap to Deactivate'
                          : 'Previous Attendance Upload: DEACTIVE (Default) • Tap to Activate for 24h',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade800,
                      side: BorderSide(color: Colors.red.shade300),
                    ),
                    onPressed: _busy
                        ? null
                        : () => _deleteAllAttendanceRecords(school),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text(
                      'Delete Attendance Records Only (Auto-Downloads Re-Uploadable Excel First)',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.2),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}


/// Developer setting: Google Apps Script web app URLs used to make
/// Hajari Patrak / Result / Vyaktitva Vikas PDFs (no paid server).
class _PrintServiceCard extends StatefulWidget {
  const _PrintServiceCard();

  @override
  State<_PrintServiceCard> createState() => _PrintServiceCardState();
}

class _PrintServiceCardState extends State<_PrintServiceCard> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    TemplatePrintService.appsScriptUrls(refresh: true).then((urls) {
      if (!mounted) return;
      setState(() {
        _controller.text = urls.join(',\n');
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save({bool test = false}) async {
    final urls = TemplatePrintService.parseUrls(_controller.text);
    setState(() {
      _saving = true;
      _status = null;
    });
    try {
      if (test) {
        final results = <String>[];
        for (var i = 0; i < urls.length; i++) {
          final ok = await TemplatePrintService.testUrl(urls[i]);
          results.add('${i + 1}: ${ok ? 'OK' : 'not working'}');
        }
        _status = urls.isEmpty ? 'No valid URL.' : results.join('   ');
      } else {
        await TemplatePrintService.saveAppsScriptUrls(urls);
        _controller.text = urls.join(',\n');
        _status = '${urls.length} URL saved.';
      }
    } catch (e) {
      _status = 'Error: $e';
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(children: [
              Icon(Icons.picture_as_pdf_rounded),
              SizedBox(width: 8),
              Expanded(
                child: Text('PDF service — Google Apps Script URLs',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ]),
            const SizedBox(height: 6),
            const Text(
              'Hajari Patrak, Result અને વ્યક્તિત્વ વિકાસ: website પર Browser Print હંમેશાં ચાલે છે. '
              'PDF (અને mobile app માં print) માટે Apps Script Web app URL નાખો. '
              'એકથી વધુ URL comma થી અલગ કરો — app કામ વહેંચશે, એટલે 30 એકસાથે limit નહીં આવે.',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              enabled: !_loading && !_saving,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'https://script.google.com/macros/s/.../exec, https://script.google.com/...',
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: _loading || _saving ? null : () => _save(),
                icon: const Icon(Icons.save_rounded),
                label: const Text('Save URLs'),
              ),
              OutlinedButton.icon(
                onPressed: _loading || _saving ? null : () => _save(test: true),
                icon: const Icon(Icons.network_check_rounded),
                label: const Text('Test'),
              ),
            ]),
            if (_saving) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
            if (_status != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_status!)),
          ],
        ),
      ),
    );
  }
}

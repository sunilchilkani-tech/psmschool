import 'dart:typed_data';

import 'package:excel_community/excel_community.dart' as ec;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import '../services/psm_file_export_helper.dart';
import '../services/supabase_library_service.dart';
import '../services/school_name_language_service.dart';
import 'package:pmshri_attendance/services/class_label.dart';

/// School-scoped digital library. Registered school data is read from Supabase;
/// only book metadata is uploaded here, and only a School Admin can upload/archive.
class SupabaseLibraryScreen extends StatefulWidget {
  const SupabaseLibraryScreen({
    super.key,
    required this.profile,
    this.readOnly = false,
    this.embedded = false,
  });

  final Map<String, dynamic> profile;
  final bool readOnly;
  final bool embedded;

  @override
  State<SupabaseLibraryScreen> createState() => _SupabaseLibraryScreenState();
}

class _SupabaseLibraryScreenState extends State<SupabaseLibraryScreen> with TickerProviderStateMixin {
  final SupabaseLibraryService _service = SupabaseLibraryService();
  late final TabController _circulationController;
  final TextEditingController _bookSearch = TextEditingController();
  final TextEditingController _transactionSearch = TextEditingController();
  final TextEditingController _rollController = TextEditingController();
  final TextEditingController _bookNumberController = TextEditingController();
  final TextEditingController _issueRemarksController = TextEditingController();
  final TextEditingController _returnRemarksController = TextEditingController();
  final TextEditingController _dueDaysController = TextEditingController(text: '14');
  final TextEditingController _maxBooksController = TextEditingController(text: '1');
  final TextEditingController _fineController = TextEditingController(text: '0');

  bool _loading = true;
  bool _actionBusy = false;
  bool _importBusy = false;
  bool _manualBookSaveBusy = false;
  bool _settingsBusy = false;
  bool _reportBusy = false;
  bool _isAdmin = false;
  String? _error;
  Map<String, dynamic> _school = <String, dynamic>{};
  String _schoolNameLanguage = SchoolNameLanguageService.gujarati;
  Map<String, dynamic> _settings = <String, dynamic>{
    'due_days': 14,
    'max_books_per_borrower': 1,
    'fine_per_day': 0,
  };
  List<Map<String, dynamic>> _classes = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _teachers = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _books = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _students = <Map<String, dynamic>>[];
  Map<String, int> _studentCountByClassId = <String, int>{};
  int _wholeSchoolStudentCount = 0;
  List<Map<String, dynamic>> _transactions = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _bookNumberHistory = <Map<String, dynamic>>[];
  String _studentIssuePermission = 'class_teacher_only';
  List<String> _allowedStudentIssueTeacherIds = <String>[];
  String _currentTeacherId = '';

  String _selectedClassId = '';
  String _borrowerType = 'student';
  String _selectedStudentId = '';
  String _selectedTeacherId = '';
  String _selectedBookId = '';
  String _selectedReturnTransactionId = '';
  DateTime _issueDate = DateTime.now();
  DateTime _returnDate = DateTime.now();
  DateTime? _reportFrom;
  DateTime? _reportTo;
  String _transactionStatusFilter = 'all';

  bool get _validityExpired {
    final validity = _parseDate(_school['validity_date']);
    return validity != null && validity.isBefore(_today());
  }
  bool get _schoolInactive => _school['is_active'] == false;
  bool get _readOnly => widget.readOnly || _school['is_blocked'] == true || _schoolInactive || _validityExpired;
  String get _readOnlyReason {
    if (_schoolInactive) return 'શાળાનું એકાઉન્ટ નિષ્ક્રિય છે: પુસ્તકમાં ફેરફાર બંધ છે. રિપોર્ટ ડાઉનલોડ કરી શકાય છે.';
    if (_validityExpired) return 'શાળાની માન્યતા પૂરી થઈ છે: પુસ્તકમાં ફેરફાર બંધ છે. રિપોર્ટ ડાઉનલોડ કરી શકાય છે.';
    if (_school['is_blocked'] == true) return 'શાળાનું એકાઉન્ટ બ્લોક છે: પુસ્તકની નોંધણી અને ફેરફાર બંધ છે. રિપોર્ટ ડાઉનલોડ કરી શકાય છે.';
    return 'આ લૉગિન વાંચન મોડમાં છે: નવી નોંધ, ફેરફાર અને અપલોડ બંધ છે. રિપોર્ટ ડાઉનલોડ કરી શકાય છે.';
  }
  String get _schoolName => SchoolNameLanguageService.resolveSchoolName(
        language: _schoolNameLanguage,
        profile: widget.profile,
        schoolContext: _school,
        fallbackEnglish: _clean(_school['school_name_en'] ?? _school['school_name'] ?? widget.profile['school_name_en'] ?? widget.profile['school_name'], fallback: 'School Library'),
      );
  int get _dueDays => _int(_settings['due_days'], 14);
  int get _maxBooks => _int(_settings['max_books_per_borrower'], 1);
  double get _finePerDay => _double(_settings['fine_per_day'], 0);
  bool _canManageStudentClass(String classId) {
    if (_isAdmin) return true;
    if (_currentTeacherId.isEmpty) return false;
    switch (_studentIssuePermission) {
      case 'any_teacher':
        return true;
      case 'selected_teachers_only':
        return _allowedStudentIssueTeacherIds.contains(_currentTeacherId);
      default:
        return _classes.any((row) => _clean(row['id']) == classId && _clean(row['class_teacher_id']) == _currentTeacherId);
    }
  }

  List<Map<String, dynamic>> get _issueableClasses {
    if (_isAdmin || _studentIssuePermission == 'any_teacher') return _classes;
    if (_studentIssuePermission == 'selected_teachers_only') {
      return _allowedStudentIssueTeacherIds.contains(_currentTeacherId) ? _classes : <Map<String, dynamic>>[];
    }
    if (_currentTeacherId.isEmpty) return <Map<String, dynamic>>[];
    return _classes.where((row) => _clean(row['class_teacher_id']) == _currentTeacherId).toList();
  }

  @override
  void initState() {
    super.initState();
    _isAdmin = '${widget.profile['role'] ?? ''}'.trim().toLowerCase() == 'admin';
    _circulationController = TabController(length: 2, vsync: this);
    _issueDate = _today();
    _returnDate = _today();
    _refresh();
  }

  @override
  void dispose() {
    _circulationController.dispose();
    _bookSearch.dispose();
    _transactionSearch.dispose();
    _rollController.dispose();
    _bookNumberController.dispose();
    _issueRemarksController.dispose();
    _returnRemarksController.dispose();
    _dueDaysController.dispose();
    _maxBooksController.dispose();
    _fineController.dispose();
    super.dispose();
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  String _clean(dynamic value, {String fallback = ''}) {
    final result = (value ?? '').toString().trim();
    return result.isEmpty || result.toLowerCase() == 'null' ? fallback : result;
  }

  int _int(dynamic value, [int fallback = 0]) =>
      value is int ? value : int.tryParse('$value') ?? fallback;

  double _double(dynamic value, [double fallback = 0]) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

  String _iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _dateText(dynamic value) {
    final raw = _clean(value);
    if (raw.length < 10) return raw;
    final parsed = DateTime.tryParse(raw.substring(0, 10));
    if (parsed == null) return raw;
    return '${parsed.day.toString().padLeft(2, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.year}';
  }

  String _todayIso() => _iso(_today());

  String _money(dynamic value) => '₹${_double(value).toStringAsFixed(2)}';

  DateTime? _parseDate(dynamic value) {
    final raw = _clean(value);
    if (raw.length < 10) return null;
    return DateTime.tryParse(raw.substring(0, 10));
  }

  int _daysBetween(DateTime start, DateTime end) {
    final a = DateTime.utc(start.year, start.month, start.day);
    final b = DateTime.utc(end.year, end.month, end.day);
    return b.difference(a).inDays;
  }

  Map<String, dynamic>? _findById(List<Map<String, dynamic>> rows, String id) {
    if (id.isEmpty) return null;
    for (final row in rows) {
      if (_clean(row['id']) == id) return row;
    }
    return null;
  }

  Map<String, dynamic>? get _selectedStudent => _findById(_students, _selectedStudentId);
  Map<String, dynamic>? get _selectedTeacher => _findById(_teachers, _selectedTeacherId);
  Map<String, dynamic>? get _selectedBook => _findById(_books, _selectedBookId);

  String _classLabel(String id) =>
      _clean(_findById(_classes, id)?['label'], fallback: 'વર્ગ');

  String _teacherName(String id) {
    final row = _findById(_teachers, id);
    return _clean(row?['teacher_name'], fallback: 'શિક્ષક');
  }

  String _borrowerName(Map<String, dynamic> tx) =>
      _clean(tx['borrower_name_snapshot'], fallback: 'નામ ઉપલબ્ધ નથી');

  String _bookTitle(Map<String, dynamic> tx) =>
      '${_clean(tx['book_number_snapshot'])} — ${_clean(tx['book_name_snapshot'])}';

  bool _isIssued(Map<String, dynamic> tx) =>
      _clean(tx['status']).toLowerCase() == 'issued';

  bool _isOverdue(Map<String, dynamic> tx, [DateTime? asOf]) {
    if (!_isIssued(tx)) return false;
    final due = _parseDate(tx['due_date']);
    if (due == null) return false;
    return _daysBetween(due, asOf ?? _today()) > 0;
  }

  int _overdueDays(Map<String, dynamic> tx, [DateTime? asOf]) {
    final due = _parseDate(tx['due_date']);
    if (due == null) return 0;
    final end = _parseDate(tx['return_date']) ?? asOf ?? _today();
    return _daysBetween(due, end).clamp(0, 1000000).toInt();
  }

  double _calculatedFine(Map<String, dynamic> tx, [DateTime? asOf]) =>
      _overdueDays(tx, asOf) * _double(tx['fine_per_day_at_issue']);

  List<Map<String, dynamic>> get _activeLoans =>
      _transactions.where(_isIssued).toList();

  String _normRoll(dynamic raw) {
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    var s = _clean(raw).toLowerCase();
    for (var i = 0; i < guj.length; i++) {
      s = s.replaceAll(guj[i], '$i');
    }
    final asInt = int.tryParse(s);
    if (asInt != null) return '$asInt';
    return s;
  }

  String _liveRollForLoan(Map<String, dynamic> tx) {
    final sid = _clean(tx['student_id']);
    if (sid.isNotEmpty) {
      final st = _findById(_students, sid);
      final r = _clean(st?['roll_number']);
      if (r.isNotEmpty) return r;
    }
    return _clean(tx['roll_number_snapshot'], fallback: '—');
  }

  String _liveStudentNameForLoan(Map<String, dynamic> tx) {
    final sid = _clean(tx['student_id']);
    if (sid.isNotEmpty) {
      final st = _findById(_students, sid);
      final n = _clean(st?['name']);
      if (n.isNotEmpty) return n;
    }
    return _borrowerName(tx);
  }

  List<Map<String, dynamic>> get _selectedClassActiveLoans {
    if (_selectedClassId.isEmpty) return <Map<String, dynamic>>[];
    final label = _classLabel(_selectedClassId);
    final list = _activeLoans.where((tx) {
      if (_clean(tx['borrower_type']) != 'student') return false;
      final txClassId = _clean(tx['class_id']);
      if (txClassId.isNotEmpty) return txClassId == _selectedClassId;
      return label.isNotEmpty && _clean(tx['class_label_snapshot']) == label;
    }).toList();
    list.sort((a, b) {
      final rA = int.tryParse(_normRoll(_liveRollForLoan(a))) ?? 999999;
      final rB = int.tryParse(_normRoll(_liveRollForLoan(b))) ?? 999999;
      if (rA != rB) return rA.compareTo(rB);
      return _clean(a['book_number_snapshot']).compareTo(_clean(b['book_number_snapshot']));
    });
    return list;
  }

  List<Map<String, dynamic>> get _selectedBorrowerLoans {
    if (_borrowerType == 'student') {
      final typedRoll = _normRoll(_rollController.text);
      return _activeLoans.where((tx) {
        if (_clean(tx['borrower_type']) != 'student') return false;
        if (_selectedStudentId.isNotEmpty && _clean(tx['student_id']) == _selectedStudentId) {
          return true;
        }
        // Fallback if roll number is typed and matches an active loan in the selected class
        if (_selectedClassId.isNotEmpty && typedRoll.isNotEmpty) {
          final sameClass = _clean(tx['class_id']) == _selectedClassId ||
              (_classLabel(_selectedClassId).isNotEmpty &&
                  _clean(tx['class_label_snapshot']) == _classLabel(_selectedClassId));
          if (sameClass && _normRoll(_liveRollForLoan(tx)) == typedRoll) {
            return true;
          }
        }
        return false;
      }).toList();
    }
    return _activeLoans.where((tx) {
      return _selectedTeacherId.isNotEmpty &&
          _clean(tx['borrower_type']) == 'teacher' &&
          _clean(tx['teacher_borrower_id']) == _selectedTeacherId;
    }).toList();
  }

  List<Map<String, dynamic>> get _reportTransactions => _transactions.where((tx) {
        final issueDate = _parseDate(tx['issue_date']);
        if (issueDate == null) return false;
        if (_reportFrom != null && issueDate.isBefore(_reportFrom!)) return false;
        if (_reportTo != null && issueDate.isAfter(_reportTo!)) return false;
        return true;
      }).toList();

  List<Map<String, dynamic>> get _filteredTransactions {
    final query = _transactionSearch.text.trim().toLowerCase();
    return _reportTransactions.where((tx) {
      final status = _clean(tx['status']).toLowerCase();
      if (_transactionStatusFilter == 'issued' && status != 'issued') return false;
      if (_transactionStatusFilter == 'returned' && status != 'returned') return false;
      if (_transactionStatusFilter == 'overdue' && !_isOverdue(tx)) return false;
      if (query.isNotEmpty) {
        final text = <String>[
          _clean(tx['book_number_snapshot']),
          _clean(tx['book_name_snapshot']),
          _clean(tx['borrower_name_snapshot']),
          _clean(tx['roll_number_snapshot']),
          _clean(tx['class_label_snapshot']),
          _clean(tx['recorded_by_teacher_name']),
        ].join(' ').toLowerCase();
        if (!text.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  void _message(String message, {bool error = false, bool warning = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontFamily: 'NotoSansGujaratiLocal')),
      backgroundColor: error
          ? Theme.of(context).colorScheme.error
          : warning
              ? Colors.orange.shade800
              : Colors.green.shade800,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _refresh({bool quiet = false}) async {
    if (!mounted) return;
    if (!quiet) setState(() { _loading = true; _error = null; });
    try {
      final serverAdmin = await _service.isSchoolAdmin();
      final currentTeacherId = await _service.currentTeacherId();
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        _service.loadSchoolContext(),
        _service.loadClasses(),
        _service.loadTeachers(),
        _service.loadSettings(),
      ]);
      final school = Map<String, dynamic>.from(results[0] as Map);
      final schoolRef = await SchoolNameLanguageService.currentSchoolRef(Supabase.instance.client);
      final schoolNameLanguage = await SchoolNameLanguageService.loadLanguage(schoolRef: schoolRef);
      final classes = (results[1] as List<Map<String, dynamic>>);
      final teachers = (results[2] as List<Map<String, dynamic>>)
          .where((teacher) => _clean(teacher['role']).toLowerCase() == 'teacher')
          .toList();
      final settings = Map<String, dynamic>.from(results[3] as Map);
      final records = await Future.wait<dynamic>(<Future<dynamic>>[
        _service.loadBooks(includeArchived: true),
        _service.loadTransactions(),
        _service.loadBookNumberHistory(),
      ]);
      final books = records[0] as List<Map<String, dynamic>>;
      final transactions = records[1] as List<Map<String, dynamic>>;
      final numberHistory = records[2] as List<Map<String, dynamic>>;
      final classStudentCounts = <String, int>{};
      var totalSchoolStudents = 0;
      try {
        final rawAllStudents = await Supabase.instance.client
            .from('students')
            .select('id,class_id,is_active,leaving_date')
            .eq('school_ref', schoolRef)
            .eq('is_active', true);
        final todayStr = _todayIso();
        for (final s in rawAllStudents) {
          final lv = _clean(s['leaving_date']);
          if (lv.length >= 10 && lv.substring(0, 10).compareTo(todayStr) <= 0) {
            continue;
          }
          final cid = _clean(s['class_id']);
          if (cid.isNotEmpty) {
            classStudentCounts[cid] = (classStudentCounts[cid] ?? 0) + 1;
            totalSchoolStudents++;
          }
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _studentCountByClassId = classStudentCounts;
        _wholeSchoolStudentCount = totalSchoolStudents;
        _isAdmin = serverAdmin;
        _currentTeacherId = currentTeacherId;
        _school = school;
        _schoolNameLanguage = schoolNameLanguage;
        _classes = classes;
        _teachers = teachers;
        _settings = settings;
        _books = books;
        _transactions = transactions;
        _bookNumberHistory = numberHistory;
        _loading = false;
        _error = null;
      });
      _syncSettingsControllers();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  String _friendlyError(Object error) {
    var text = '$error'.replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '');
    if (text.contains('Could not find the function') || text.contains('schema cache')) {
      return 'પુસ્તકાલયનું ડેટાબેઝ માઇગ્રેશન હજી લાગુ થયું નથી. પહેલા આપેલી Supabase migration ચલાવો અને પછી Refresh કરો.\n\n$text';
    }
    return text;
  }

  void _syncSettingsControllers() {
    _dueDaysController.text = '$_dueDays';
    _maxBooksController.text = '$_maxBooks';
    _fineController.text = _finePerDay.toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '');
    _studentIssuePermission = _clean(_settings['student_issue_permission'], fallback: 'class_teacher_only');
    final ids = _settings['allowed_student_issue_teacher_ids'];
    _allowedStudentIssueTeacherIds = ids is List ? ids.map((value) => _clean(value)).where((value) => value.isNotEmpty).toSet().toList() : <String>[];
  }

  Future<void> _loadStudentsForClass(String classId) async {
    setState(() {
      _selectedClassId = classId;
      _students = <Map<String, dynamic>>[];
      _selectedStudentId = '';
      _rollController.clear();
    });
    if (classId.isEmpty) return;
    try {
      final students = await _service.loadStudents(classId);
      if (!mounted || _selectedClassId != classId) return;
      setState(() => _students = students);
    } catch (error) {
      _message('વિદ્યાર્થીઓની યાદી લોડ થઈ નથી: ${_friendlyError(error)}', error: true);
    }
  }

  void _findStudent({bool notifyMissing = true}) {
    final roll = _normRoll(_rollController.text);
    if (_selectedClassId.isEmpty || roll.isEmpty) {
      setState(() {
        _selectedStudentId = '';
        _selectedReturnTransactionId = '';
      });
      if (notifyMissing) _message('પહેલા વર્ગ પસંદ કરો અને વિદ્યાર્થીનો રોલ નંબર દાખલ કરો.', warning: true);
      return;
    }
    Map<String, dynamic>? found;
    for (final student in _students) {
      if (_normRoll(student['roll_number']) == roll) {
        found = student;
        break;
      }
    }
    final foundId = _clean(found?['id']);
    setState(() {
      _selectedStudentId = foundId;
      final loans = _selectedBorrowerLoans;
      _selectedReturnTransactionId = loans.isNotEmpty ? _clean(loans.first['id']) : '';
    });
    if (found == null && _selectedBorrowerLoans.isEmpty && notifyMissing) {
      _message('આ વર્ગમાં આ રોલ નંબરનો સક્રિય વિદ્યાર્થી મળ્યો નથી.', error: true);
    }
  }

  void _findBook({bool notifyMissing = true}) {
    final number = _bookNumberController.text.trim().toLowerCase();
    Map<String, dynamic>? found;
    for (final book in _books) {
      if (_clean(book['is_active']).toLowerCase() == 'false') continue;
      if (_clean(book['book_number']).toLowerCase() == number) {
        found = book;
        break;
      }
    }
    setState(() => _selectedBookId = _clean(found?['id']));
    if (found == null && number.isNotEmpty && notifyMissing) {
      _message('આ પુસ્તક નંબર પુસ્તકાલયમાં મળ્યો નથી. નંબર ફરી ચકાસો.', error: true);
    }
  }

  Future<DateTime?> _pickDate(DateTime current, {DateTime? notBefore}) async {
    final today = _today();
    var initial = current;
    if (initial.isAfter(today)) initial = today;
    if (notBefore != null && initial.isBefore(notBefore)) initial = notBefore;
    final first = DateTime(2000, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: notBefore != null && notBefore.isAfter(first) ? notBefore : first,
      lastDate: today,
      helpText: 'તારીખ પસંદ કરો / Select date',
      cancelText: 'રદ કરો',
      confirmText: 'પસંદ કરો',
    );
    return picked == null ? null : DateTime(picked.year, picked.month, picked.day);
  }

  Future<void> _issueBook() async {
    final student = _selectedStudent;
    final teacher = _selectedTeacher;
    final book = _selectedBook;
    final borrower = _borrowerType == 'student' ? student : teacher;
    if (_readOnly) {
      _message('આ શાળા હાલમાં માત્ર રિપોર્ટ જોવા માટે ખુલ્લી છે.', warning: true);
      return;
    }
    if (borrower == null) {
      _message(_borrowerType == 'student'
          ? 'વર્ગ અને સાચો રોલ નંબર પસંદ કરો.'
          : 'યાદીમાંથી શિક્ષકનું નામ પસંદ કરો.', warning: true);
      return;
    }
    if (book == null) {
      _message('પુસ્તક નંબર દાખલ કરીને પુસ્તક શોધો.', warning: true);
      return;
    }
    final activeForBorrower = _transactions.where((tx) {
      if (!_isIssued(tx) || _clean(tx['borrower_type']) != _borrowerType) return false;
      return _borrowerType == 'student'
          ? _clean(tx['student_id']) == _selectedStudentId
          : _clean(tx['teacher_borrower_id']) == _selectedTeacherId;
    }).length;
    if (activeForBorrower >= _maxBooks) {
      _message('આ વાચક પાસે પહેલેથી જ મહત્તમ $_maxBooks સક્રિય પુસ્તક(ો) છે.', warning: true);
      return;
    }
    final alreadyIssued = _transactions.any((tx) =>
        _isIssued(tx) && _clean(tx['book_id']) == _clean(book['id']));
    if (alreadyIssued) {
      _message('આ પુસ્તક હાલમાં બીજા વાચક પાસે જારી થયેલું છે.', error: true);
      return;
    }

    final borrowerDisplay = _borrowerType == 'student'
        ? '${_clean(student?['name'])}  (ધોરણ ${ClassLabel.bare(_classLabel(_selectedClassId))}, રોલ ${_clean(student?['roll_number'])})'
        : _clean(teacher?['teacher_name']);
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('પુસ્તક આપવાની પુષ્ટિ / Confirm Issue'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('વાચક / Borrower: $borrowerDisplay'),
          const SizedBox(height: 8),
          Text('પુસ્તક નંબર: ${_clean(book['book_number'])}'),
          Text('પુસ્તકનું નામ: ${_clean(book['book_name'])}'),
          Text('આપવાની તારીખ: ${_dateText(_iso(_issueDate))}'),
          Text('પરત કરવાની છેલ્લી તારીખ: ${_dateText(_iso(_issueDate.add(Duration(days: _dueDays))))}'),
          const SizedBox(height: 8),
          const Text('શું આ પુસ્તક નોંધણીમાં ઉમેરવું છે?'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('રદ કરો')),
          FilledButton.icon(onPressed: () => Navigator.pop(dialogContext, true), icon: const Icon(Icons.check), label: const Text('હા, પુસ્તક આપો')),
        ],
      ),
    );
    if (approved != true || !mounted) return;

    setState(() => _actionBusy = true);
    try {
      await _service.issueBook(
        bookId: _clean(book['id']),
        borrowerType: _borrowerType,
        issueDate: _issueDate,
        remarks: _issueRemarksController.text.trim(),
        classId: _borrowerType == 'student' ? _selectedClassId : null,
        studentId: _borrowerType == 'student' ? _selectedStudentId : null,
        teacherBorrowerId: _borrowerType == 'teacher' ? _selectedTeacherId : null,
      );
      _message('પુસ્તક સફળતાપૂર્વક જારી થયું. / Book issued successfully.');
      _issueRemarksController.clear();
      _bookNumberController.clear();
      setState(() {
        _selectedBookId = '';
        _issueDate = _today();
      });
      await _refresh(quiet: true);
    } catch (error) {
      _message(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _returnBook() async {
    final loan = _findById(_transactions, _selectedReturnTransactionId);
    if (_readOnly) {
      _message('આ શાળા હાલમાં માત્ર રિપોર્ટ જોવા માટે ખુલ્લી છે.', warning: true);
      return;
    }
    if (loan == null || !_isIssued(loan)) {
      _message('પરત કરવા માટે સક્રિય પુસ્તક પસંદ કરો.', warning: true);
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('પુસ્તક પરત લેવાની પુષ્ટિ'),
        content: Text(
          'વાચક: ${_borrowerName(loan)}\n'
          'પુસ્તક: ${_bookTitle(loan)}\n'
          'જારી તારીખ: ${_dateText(loan['issue_date'])}\n'
          'પરત તારીખ: ${_dateText(_iso(_returnDate))}\n\n'
          'શું આ પુસ્તક પરત મળ્યું છે?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('રદ કરો')),
          FilledButton.icon(onPressed: () => Navigator.pop(dialogContext, true), icon: const Icon(Icons.assignment_turned_in_outlined), label: const Text('હા, પરત મળ્યું')),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => _actionBusy = true);
    try {
      await _service.returnBook(
        transactionId: _selectedReturnTransactionId,
        returnDate: _returnDate,
        remarks: _returnRemarksController.text.trim(),
      );
      _message('પુસ્તક પરત નોંધાયું. / Book return saved.');
      _returnRemarksController.clear();
      setState(() {
        _selectedReturnTransactionId = '';
        _returnDate = _today();
      });
      await _refresh(quiet: true);
    } catch (error) {
      _message(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _quickReturnLoan(Map<String, dynamic> loan) async {
    if (_readOnly) {
      _message('આ શાળા હાલમાં માત્ર રિપોર્ટ જોવા માટે ખુલ્લી છે.', warning: true);
      return;
    }
    if (!_isIssued(loan)) {
      _message('આ પુસ્તક પહેલેથી પરત થઈ ચૂક્યું છે.', warning: true);
      return;
    }
    final loanClassId = _clean(loan['class_id'], fallback: _selectedClassId);
    if (!_isAdmin && _clean(loan['borrower_type']) == 'student' && !_canManageStudentClass(loanClassId)) {
      _message('તમારા લૉગિનને આ વર્ગના પુસ્તક પરત લેવાની પરવાનગી નથી.', warning: true);
      return;
    }

    var pickedReturnDate = _today();
    final issueDt = _parseDate(loan['issue_date']);
    if (issueDt != null && pickedReturnDate.isBefore(issueDt)) {
      pickedReturnDate = issueDt;
    }
    final remarksCtrl = TextEditingController();
    final rollDisp = _liveRollForLoan(loan);
    final studentDisp = _liveStudentNameForLoan(loan);
    final bookNoDisp = _clean(loan['book_number_snapshot']);
    final bookNameDisp = _clean(loan['book_name_snapshot']);

    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('📗 પુસ્તક પરત લેવાની પુષ્ટિ / Return Book'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'વિદ્યાર્થી: $studentDisp (રોલ નંબર: $rollDisp)',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'પુસ્તક નંબર: $bookNoDisp  •  પુસ્તકનું નામ: $bookNameDisp',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text('આપ્યા તારીખ: ${_dateText(loan['issue_date'])}  •  મુદત: ${_dateText(loan['due_date'])}'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await _pickDate(pickedReturnDate, notBefore: issueDt);
                    if (d != null) {
                      setDialogState(() => pickedReturnDate = d);
                    }
                  },
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text('પરત તારીખ: ${_dateText(_iso(pickedReturnDate))} (તારીખ બદલો)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: remarksCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'પરત અંગે નોંધ (વૈકલ્પિક)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('રદ કરો'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.assignment_turned_in_outlined),
              label: const Text('હા, પુસ્તક પરત લો'),
            ),
          ],
        ),
      ),
    );
    final remarks = remarksCtrl.text.trim();
    remarksCtrl.dispose();
    if (approved != true || !mounted) return;

    setState(() => _actionBusy = true);
    try {
      await _service.returnBook(
        transactionId: _clean(loan['id']),
        returnDate: pickedReturnDate,
        remarks: remarks,
      );
      _message('પુસ્તક નં. $bookNoDisp ($studentDisp) સફળતાપૂર્વક પરત નોંધાયું.');
      if (_selectedReturnTransactionId == _clean(loan['id'])) {
        _selectedReturnTransactionId = '';
      }
      await _refresh(quiet: true);
    } catch (error) {
      _message(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _downloadBookTemplate() async {
    final workbook = ec.Excel.createExcel();
    workbook.rename('Sheet1', 'Books');
    final books = workbook['Books'];
    books.appendRow(<ec.CellValue>[
      ec.TextCellValue('Book Number / પુસ્તક નંબર'),
      ec.TextCellValue('Book Name / પુસ્તકનું નામ'),
      ec.TextCellValue('Author / લેખક'),
      ec.TextCellValue('Publication / પ્રકાશક'),
      ec.TextCellValue('Price / કિંમત'),
      ec.TextCellValue('ISBN'),
    ]);
    final instructions = workbook['Instructions'];
    for (final row in <List<String>>[
      <String>['Digital Library – Book Import / પુસ્તક આયાત'],
      <String>['Required columns', 'Book Number and Book Name are required.'],
      <String>['Duplicate handling', 'Duplicate or previously used book numbers are skipped. Admin can change an active book number individually; the old number remains reserved and is recorded in Book Number History.'],
      <String>['Do not upload student data', 'Students, class names and teachers already come from the registered school records.'],
      <String>['Safe upload', 'Keep the first-row column labels. Leave optional author, publication, price and ISBN blank when unknown.'],
      <String>['Gujarati', 'પુસ્તક નંબર અને પુસ્તકનું નામ ફરજિયાત છે. પહેલેથી નોંધાયેલ પુસ્તક નંબર ફરીથી ઉમેરાશે નહીં.'],
    ]) {
      instructions.appendRow(row.map<ec.CellValue>((value) => ec.TextCellValue(value)).toList());
    }
    final bytes = workbook.encode();
    if (bytes == null || bytes.isEmpty) throw StateError('Excel template બનાવી શકાયો નથી.');
    await PsmFileExportHelper.saveOrShare(
      bytes: Uint8List.fromList(bytes),
      filename: 'PSM_Digital_Library_Book_Template.xlsx',
      title: 'Digital Library Book Template',
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  String _cellText(ec.Data? cell) {
    final value = cell?.value;
    if (value == null) return '';
    if (value is ec.TextCellValue) {
      return _textSpan(value.value).trim();
    }
    if (value is ec.IntCellValue) return '${value.value}';
    if (value is ec.DoubleCellValue) {
      final number = value.value;
      return number == number.roundToDouble() ? number.toInt().toString() : number.toString();
    }
    if (value is ec.BoolCellValue) return '${value.value}';
    return '$value'.trim();
  }

  String _textSpan(dynamic span) {
    if (span is String) return span;
    final buffer = StringBuffer();
    final text = span?.text;
    if (text is String) buffer.write(text);
    final children = span?.children;
    if (children is Iterable) {
      for (final child in children) {
        buffer.write(_textSpan(child));
      }
    }
    return buffer.toString();
  }

  String _normalizeHeader(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_./()\-]+'), '')
      .replaceAll(':', '');

  Future<void> _addBookManually() async {
    if (!_isAdmin || _readOnly) {
      _message('નવું પુસ્તક ઉમેરવાની પરવાનગી માત્ર School Admin ને છે.',
          warning: true);
      return;
    }
    if (_manualBookSaveBusy || _importBusy) return;

    final numberController = TextEditingController();
    final nameController = TextEditingController();
    final authorController = TextEditingController();
    final publicationController = TextEditingController();
    final priceController = TextEditingController(text: '0');
    final isbnController = TextEditingController();

    try {
      String? validationError;
      final values = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('નવું પુસ્તક ઉમેરો / Add New Book'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: numberController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'પુસ્તક નંબર / Book Number *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'પુસ્તકનું નામ / Book Name *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: authorController,
                      decoration: const InputDecoration(
                        labelText: 'લેખક / Author',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: publicationController,
                      decoration: const InputDecoration(
                        labelText: 'પ્રકાશક / Publication',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: priceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'કિંમત ₹ / Price',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: isbnController,
                      decoration: const InputDecoration(
                        labelText: 'ISBN Number',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (validationError != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          validationError!,
                          style: TextStyle(
                              color: Theme.of(dialogContext)
                                  .colorScheme
                                  .error),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('રદ કરો / Cancel'),
              ),
              FilledButton.icon(
                onPressed: () {
                  final number = numberController.text.trim();
                  final name = nameController.text.trim();
                  final rawPrice = priceController.text.trim();
                  final price =
                      rawPrice.isEmpty ? 0.0 : double.tryParse(rawPrice);
                  if (number.isEmpty || name.isEmpty) {
                    setDialogState(() => validationError =
                        'પુસ્તક નંબર અને પુસ્તકનું નામ ફરજિયાત છે.');
                    return;
                  }
                  if (price == null || !price.isFinite || price < 0) {
                    setDialogState(() =>
                        validationError = 'કિંમત 0 અથવા તેનાથી વધુ સંખ્યા હોવી જોઈએ.');
                    return;
                  }
                  Navigator.pop(dialogContext, <String, String>{
                    'book_number': number,
                    'book_name': name,
                    'author': authorController.text.trim(),
                    'publication': publicationController.text.trim(),
                    'price': price.toString(),
                    'isbn': isbnController.text.trim(),
                  });
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('પુસ્તક સાચવો / Save Book'),
              ),
            ],
          ),
        ),
      );

      if (values == null) return;
      if (!mounted) return;
      setState(() => _manualBookSaveBusy = true);

      // Use the same tenant-scoped, admin-checked RPC as Excel import so
      // duplicate and previously-used book numbers are handled consistently.
      final result = await _service.bulkAddBooks(<Map<String, dynamic>>[
        <String, dynamic>{...values},
      ]);
      final added = _int(result['added']);
      final skipped = _int(result['skipped']);
      final invalid = _int(result['invalid']);
      final duplicateNumbers = result['duplicate_numbers'] is List
          ? (result['duplicate_numbers'] as List)
              .map((value) => value.toString())
              .where((value) => value.trim().isNotEmpty)
              .join(', ')
          : '';

      await _refresh(quiet: true);
      if (!mounted) return;
      if (added > 0) {
        _message('પુસ્તક સફળતાપૂર્વક ઉમેરાયું. / Book added successfully.');
      } else if (skipped > invalid) {
        _message(
          duplicateNumbers.isEmpty
              ? 'આ પુસ્તક નંબર પહેલેથી નોંધાયેલ છે અથવા અગાઉ વપરાયો છે.'
              : 'પુસ્તક નંબર $duplicateNumbers પહેલેથી નોંધાયેલ/વપરાયેલ છે.',
          warning: true,
        );
      } else {
        _message('પુસ્તક ઉમેરાયું નથી. વિગતો ચકાસો.', error: true);
      }
    } catch (error) {
      _message('પુસ્તક ઉમેરવામાં ભૂલ: ${_friendlyError(error)}', error: true);
    } finally {
      numberController.dispose();
      nameController.dispose();
      authorController.dispose();
      publicationController.dispose();
      priceController.dispose();
      isbnController.dispose();
      if (mounted) setState(() => _manualBookSaveBusy = false);
    }
  }

  Future<void> _importBooks() async {
    if (!_isAdmin || _readOnly) {
      _message('પુસ્તક અપલોડ કરવાની પરવાનગી માત્ર શાળા એડમિનને છે.', warning: true);
      return;
    }
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final bytes = picked.files.first.bytes;
    if (bytes == null || bytes.isEmpty) {
      _message('Excel ફાઇલ વાંચી શકાઈ નથી. ફરીથી પસંદ કરો.', error: true);
      return;
    }
    setState(() => _importBusy = true);
    try {
      final workbook = ec.Excel.decodeBytes(bytes);
      ec.Sheet? sheet;
      for (final entry in workbook.tables.entries) {
        final key = entry.key.toLowerCase();
        if (key == 'books' || key.contains('book')) {
          sheet = entry.value;
          break;
        }
      }
      if (sheet == null && workbook.tables.isNotEmpty) sheet = workbook.tables.values.first;
      if (sheet == null || sheet.rows.length < 2) {
        throw StateError('Excel માં header row અને ઓછામાં ઓછી એક પુસ્તકની row હોવી જોઈએ.');
      }
      final headers = sheet.rows.first.map(_cellText).map(_normalizeHeader).toList();
      int col(List<String> aliases) => headers.indexWhere(
        (header) => aliases.any((alias) => header == alias || header.contains(alias)),
      );
      final numberCol = col(const ['booknumber', 'serial', 'serialnumber', 'bookno', 'bookserial', 'પુસ્તકનંબર', 'પુસ્તકક્રમ', 'ક્રમનંબર', 'નંબર']);
      final nameCol = col(const ['bookname', 'title', 'nameofbook', 'પુસ્તકનુનામ', 'પુસ્તકનુંનામ', 'પુસ્તકનામ']);
      final authorCol = col(const ['author', 'authorname', 'લેખક']);
      final publicationCol = col(const ['publication', 'publisher', 'publicationname', 'પ્રકાશક']);
      final priceCol = col(const ['price', 'cost', 'કિંમત', 'મૂલ્ય']);
      final isbnCol = col(const ['isbn', 'isbnnumber']);
      if (numberCol < 0 || nameCol < 0) {
        throw StateError('ફરજિયાત columns નથી મળ્યા. Template માં Book Number અને Book Name રાખો.');
      }
      String cellAt(List<ec.Data?> row, int index) =>
          index < 0 || index >= row.length ? '' : _cellText(row[index]);
      final rows = <Map<String, dynamic>>[];
      for (var i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.every((cell) => _cellText(cell).isEmpty)) continue;
        rows.add(<String, dynamic>{
          'book_number': cellAt(row, numberCol),
          'book_name': cellAt(row, nameCol),
          'author': cellAt(row, authorCol),
          'publication': cellAt(row, publicationCol),
          'price': cellAt(row, priceCol),
          'isbn': cellAt(row, isbnCol),
        });
      }
      if (rows.isEmpty) throw StateError('Excel માં અપલોડ કરવા યોગ્ય પુસ્તકની row નથી.');
      final result = await _service.bulkAddBooks(rows);
      final added = _int(result['added']);
      final skipped = _int(result['skipped']);
      final invalid = _int(result['invalid']);
      final duplicateNumbers = (result['duplicate_numbers'] is List)
          ? (result['duplicate_numbers'] as List).map((e) => '$e').take(8).join(', ')
          : '';
      await _refresh(quiet: true);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('પુસ્તક અપલોડ પૂર્ણ / Book Upload Complete'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _resultLine('નવા ઉમેરાયેલા પુસ્તકો / Added', added, Colors.green),
            _resultLine('પહેલેથી નોંધાયેલા નંબર હોવાથી છોડ્યા / Duplicate numbers skipped', skipped - invalid, Colors.orange),
            _resultLine('અપૂર્ણ/ખોટી row / Invalid rows', invalid, Colors.red),
            const SizedBox(height: 8),
            Text('કુલ તપાસેલી rows: ${rows.length}'),
            if (duplicateNumbers.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('છોડેલા પુસ્તક નંબર: $duplicateNumbers', style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            const Text('જૂના પુસ્તક નંબર અથવા અગાઉની નોંધ બદલાઈ નથી.'),
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('બરાબર / OK'))],
        ),
      );
    } catch (error) {
      _message('પુસ્તક અપલોડ નિષ્ફળ: ${_friendlyError(error)}', error: true);
    } finally {
      if (mounted) setState(() => _importBusy = false);
    }
  }

  Widget _resultLine(String label, int value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text('$value', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        ]),
      );

  Future<void> _archiveBook(Map<String, dynamic> book) async {
    if (!_isAdmin || _readOnly) return;
    final currentLoan = _transactions.any((tx) =>
        _isIssued(tx) && _clean(tx['book_id']) == _clean(book['id']));
    if (currentLoan) {
      _message('પુસ્તક હાલમાં જારી છે. પહેલા પરત મેળવો, પછી દૂર કરો.', warning: true);
      return;
    }
    final details = TextEditingController();
    var reasonCode = 'lost';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('પુસ્તક દૂર કરવાની નોંધ / Remove Book'),
        content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('પુસ્તક નંબર: ${_clean(book['book_number'])}\nપુસ્તકનું નામ: ${_clean(book['book_name'])}'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: reasonCode,
              decoration: const InputDecoration(labelText: 'દૂર કરવાનું કારણ / Reason', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'lost', child: Text('ખોવાઈ ગયું / Lost')),
                DropdownMenuItem(value: 'torn', child: Text('ફાટી ગયું / Torn')),
                DropdownMenuItem(value: 'damaged', child: Text('ક્ષતિગ્રસ્ત / Damaged')),
                DropdownMenuItem(value: 'worn_out', child: Text('જૂનું અથવા ઉપયોગ લાયક નથી / Worn out')),
                DropdownMenuItem(value: 'other', child: Text('અન્ય કારણ / Other')),
              ],
              onChanged: (value) { if (value != null) setDialogState(() => reasonCode = value); },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: details,
              onChanged: (_) => setDialogState(() {}),
              maxLines: 3,
              decoration: InputDecoration(
                labelText: reasonCode == 'other' ? 'કારણની વિગત (ફરજિયાત) / Details (required)' : 'વધારાની નોંધ / Additional note',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text('આ પુસ્તક સક્રિય યાદીમાંથી દૂર થશે. જૂના રિપોર્ટમાં નંબર, કારણ, તારીખ અને નોંધ કરનારનું નામ રહેશે. નંબર ફરીથી વાપરી શકાશે નહીં.'),
          ],
        ))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('રદ કરો')),
          FilledButton.tonal(
            onPressed: reasonCode == 'other' && details.text.trim().isEmpty
                ? null
                : () => Navigator.pop(dialogContext, <String, String>{'reason': reasonCode, 'details': details.text.trim()}),
            child: const Text('કારણ સાચવો અને દૂર કરો'),
          ),
        ],
      )),
    );
    final reasonDetails = details.text.trim();
    details.dispose();
    if (result == null || !mounted) return;
    setState(() => _actionBusy = true);
    try {
      await _service.archiveBook(
        bookId: _clean(book['id']),
        reasonCode: result['reason'] ?? 'other',
        reasonDetails: result['details'] ?? reasonDetails,
      );
      _message('પુસ્તક દૂર થયું. કારણ અને નોંધ રિપોર્ટમાં સાચવ્યાં છે.');
      await _refresh(quiet: true);
    } catch (error) {
      _message(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _changeBookNumber(Map<String, dynamic> book) async {
    if (!_isAdmin || _readOnly || _clean(book['is_active']).toLowerCase() == 'false') return;
    final alreadyIssued = _transactions.any((tx) =>
        _isIssued(tx) && _clean(tx['book_id']) == _clean(book['id']));
    if (alreadyIssued) {
      _message('જારી પુસ્તકનો નંબર બદલવા પહેલાં પુસ્તક પરત મેળવો.', warning: true);
      return;
    }
    final controller = TextEditingController(text: _clean(book['book_number']));
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('પુસ્તક નંબર બદલો / Change Number'),
        content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('પુસ્તક: ${_clean(book['book_name'])}'),
          Text('હાલનો નંબર: ${_clean(book['book_number'])}'),
          const SizedBox(height: 12),
          TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'નવો પુસ્તક નંબર', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          const Text('જૂનો નંબરનો ઇતિહાસ રિપોર્ટમાં રહેશે અને ફરીથી વાપરી શકાશે નહીં.'),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('રદ કરો')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim().isNotEmpty), child: const Text('નંબર બદલો')),
        ],
      ),
    );
    final newNumber = controller.text.trim();
    controller.dispose();
    if (approved != true || !mounted) return;
    setState(() => _actionBusy = true);
    try {
      final response = await _service.changeBookNumber(bookId: _clean(book['id']), newBookNumber: newNumber);
      _message('${_clean(response['old_book_number'])} → ${_clean(response['new_book_number'])}: પુસ્તક નંબર સાચવાયો.');
      await _refresh(quiet: true);
    } catch (error) {
      _message(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _saveSettings() async {
    if (!_isAdmin || _readOnly) return;
    final dueDays = int.tryParse(_dueDaysController.text.trim());
    final maxBooks = int.tryParse(_maxBooksController.text.trim());
    final fine = double.tryParse(_fineController.text.trim());
    if (_studentIssuePermission == 'selected_teachers_only' && _allowedStudentIssueTeacherIds.isEmpty) {
      _message('કૃપા કરીને ઓછામાં ઓછા એક શિક્ષકને પુસ્તક આપ-લે માટે પસંદ કરો.', warning: true);
      return;
    }
    if (dueDays == null || dueDays < 1 || dueDays > 365 ||
        maxBooks == null || maxBooks < 1 || maxBooks > 10 ||
        fine == null || fine < 0 || fine > 100000) {
      _message('સમયમર્યાદા 1–365 દિવસ, મહત્તમ પુસ્તકો 1–10 અને દૈનિક દંડ 0 કે વધુ હોવો જોઈએ.', warning: true);
      return;
    }
    setState(() => _settingsBusy = true);
    try {
      final saved = await _service.saveSettings(
        dueDays: dueDays,
        maxBooksPerBorrower: maxBooks,
        finePerDay: fine,
        studentIssuePermission: _studentIssuePermission,
        allowedStudentIssueTeacherIds: _allowedStudentIssueTeacherIds,
      );
      if (!mounted) return;
      setState(() => _settings = saved);
      _syncSettingsControllers();
      _message('પુસ્તકાલયની સેટિંગ્સ સાચવાઈ ગઈ.');
    } catch (error) {
      _message(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _settingsBusy = false);
    }
  }

  Future<void> _pickReportDate({required bool from}) async {
    final current = from ? _reportFrom : _reportTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? _today(),
      firstDate: DateTime(2000),
      lastDate: _today(),
      helpText: from ? 'શરૂઆતની તારીખ' : 'અંતિમ તારીખ',
    );
    if (picked == null || !mounted) return;
    final value = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      if (from) {
        _reportFrom = value;
        if (_reportTo != null && _reportTo!.isBefore(value)) _reportTo = value;
      } else {
        _reportTo = value;
        if (_reportFrom != null && _reportFrom!.isAfter(value)) _reportFrom = value;
      }
    });
  }

  void _clearReportDates() => setState(() {
        _reportFrom = null;
        _reportTo = null;
      });

  Future<void> _exportAllReports() async {
    if (_loading || _reportBusy) return;
    setState(() => _reportBusy = true);
    try {
      final rows = _reportTransactions;
      final workbook = ec.Excel.createExcel();
      workbook.rename('Sheet1', 'School Summary');

      String newSheetName(String requested) {
        var base = requested.replaceAll(RegExp(r'[\\/\?\*\[\]:]'), ' ').trim();
        if (base.isEmpty) base = 'Report';
        if (base.length > 31) base = base.substring(0, 31);
        var candidate = base;
        var suffixNumber = 2;
        bool exists(String name) => workbook.tables.keys.any(
          (key) => key.toLowerCase() == name.toLowerCase(),
        );
        while (exists(candidate)) {
          final suffix = ' ($suffixNumber)';
          final prefixLength = 31 - suffix.length;
          candidate = '${base.substring(0, base.length > prefixLength ? prefixLength : base.length)}$suffix';
          suffixNumber++;
        }
        return candidate;
      }

      void addSheet(String name, List<List<String>> data) {
        String? existing;
        for (final key in workbook.tables.keys) {
          if (key.toLowerCase() == name.toLowerCase()) {
            existing = key;
            break;
          }
        }
        final sheet = workbook[existing ?? newSheetName(name)];
        for (final row in data) {
          sheet.appendRow(row.map<ec.CellValue>((value) => ec.TextCellValue(value)).toList());
        }
      }

      // Report roster uses only active, registered students in the classes this login can access.
      // Individual loan snapshots are also retained below for students who have since left the roster.
      final reportClasses = _issueableClasses;
      final rosterLoadSucceeded = List<bool>.filled(reportClasses.length, false);
      final rosterResults = await Future.wait<List<Map<String, dynamic>>>(
        reportClasses.asMap().entries.map((entry) async {
          try {
            final result = await _service.loadStudents(_clean(entry.value['id']));
            rosterLoadSucceeded[entry.key] = true;
            return result;
          } catch (_) {
            return <Map<String, dynamic>>[];
          }
        }),
      );
      final rosterComplete = rosterLoadSucceeded.every((loaded) => loaded);
      final registeredStudents = <Map<String, dynamic>>[];
      final registeredCountsByClass = <String, int>{};
      for (var i = 0; i < reportClasses.length; i++) {
        final classRow = reportClasses[i];
        final classId = _clean(classRow['id']);
        final classLabel = _clean(classRow['label']);
        registeredCountsByClass[classLabel] = rosterResults[i].length;
        for (final student in rosterResults[i]) {
          registeredStudents.add(<String, dynamic>{
            ...student,
            'library_class_id': classId,
            'library_class_label': classLabel,
          });
        }
      }

      final issued = rows.where(_isIssued).toList();
      final returned = rows.where((tx) => !_isIssued(tx)).toList();
      final overdue = issued.where(_isOverdue).toList();
      final registeredBooks = _books.where((book) => _clean(book['is_active']).toLowerCase() != 'false').length;
      final retiredBooks = _books.where((book) => _clean(book['is_active']).toLowerCase() == 'false').toList();
      final fines = rows.fold<double>(0, (sum, tx) => sum + _calculatedFine(tx));
      addSheet('School Summary', <List<String>>[
        <String>['DIGITAL LIBRARY REGISTER / ડિજિટલ પુસ્તકાલય રજિસ્ટર'],
        <String>['શાળા / School', _schoolName],
        <String>['DISE/UDISE', _clean(_school['school_id'], fallback: _clean(widget.profile['school_id']))],
        <String>['Report period', _reportFrom == null && _reportTo == null ? 'All dates / તમામ તારીખો' : '${_reportFrom == null ? 'Beginning' : _iso(_reportFrom!)} to ${_reportTo == null ? 'Today' : _iso(_reportTo!)}'],
        <String>['Generated on', _todayIso()],
        <String>['Active books in catalog', '$registeredBooks'],
        <String>['Removed/lost/damaged books with reason record', '${retiredBooks.length}'],
        <String>['Active classes available to this login', '${reportClasses.length}'],
        <String>['Active teachers in school roster', '${_teachers.length}'],
        <String>['Registered active students in available classes', '${registeredStudents.length}'],
        <String>['Transactions in selected period', '${rows.length}'],
        <String>['Currently issued (in this report period)', '${issued.length}'],
        <String>['Returned (in this report period)', '${returned.length}'],
        <String>['Overdue currently issued', '${overdue.length}'],
        <String>['Calculated accumulated late fine (₹)', fines.toStringAsFixed(2)],
        <String>['Loan period (days)', 'Default at issue: $_dueDays; each loan keeps its original due period.'],
        <String>['Fine rule', 'Fine = overdue calendar days × fine per day recorded on issue.'],
        <String>['Student directory note', rosterComplete ? 'Registered students are included for classes visible to this login.' : 'Some student roster rows could not be loaded; saved transaction history remains included.'],
      ]);

      final transactionHeaders = <String>[
        'ક્રમ / Txn ID', 'પુસ્તક નંબર / Book Number', 'પુસ્તકનું નામ / Book Name',
        'વાચકનો પ્રકાર / Borrower Type', 'વાચકનું નામ / Borrower Name',
        'ધોરણ / Class', 'રોલ નંબર / Roll Number', 'જારી તારીખ / Issue Date',
        'પરત કરવાની તારીખ / Due Date', 'પરત તારીખ / Return Date', 'સ્થિતિ / Status',
        'દિવસ / Days Kept', 'વિલંબ દિવસ / Overdue Days', 'દંડ ₹ / Fine ₹',
        'નોંધનાર શિક્ષક / Recorded By', 'જારી નોંધ / Issue Remarks', 'પરત નોંધ / Return Remarks',
      ];
      int daysKept(Map<String, dynamic> tx) {
        final issue = _parseDate(tx['issue_date']);
        if (issue == null) return 0;
        final end = _parseDate(tx['return_date']) ?? _today();
        return _daysBetween(issue, end).clamp(0, 1000000).toInt();
      }
      final liveStudentById = <String, Map<String, dynamic>>{
        for (final st in registeredStudents)
          if (_clean(st['id']).isNotEmpty) _clean(st['id']): st,
      };
      List<String> transactionRow(Map<String, dynamic> tx) {
        final sid = _clean(tx['student_id']);
        final liveSt = (_isIssued(tx) && sid.isNotEmpty) ? liveStudentById[sid] : null;
        final liveClass = liveSt != null
            ? _clean(liveSt['library_class_label'], fallback: _clean(tx['class_label_snapshot']))
            : _clean(tx['class_label_snapshot']);
        final liveRoll = liveSt != null
            ? _clean(liveSt['roll_number'], fallback: _clean(tx['roll_number_snapshot']))
            : _clean(tx['roll_number_snapshot']);
        return <String>[
          _clean(tx['id']), _clean(tx['book_number_snapshot']), _clean(tx['book_name_snapshot']),
          _clean(tx['borrower_type']) == 'teacher' ? 'શિક્ષક / Teacher' : 'વિદ્યાર્થી / Student',
          _borrowerName(tx), liveClass, liveRoll,
          _clean(tx['issue_date']), _clean(tx['due_date']), _clean(tx['return_date']),
          _isIssued(tx) ? 'જારી / Issued' : 'પરત / Returned', '${daysKept(tx)}',
          '${_overdueDays(tx)}', _calculatedFine(tx).toStringAsFixed(2),
          _clean(tx['recorded_by_teacher_name']), _clean(tx['issue_remarks']), _clean(tx['return_remarks']),
        ];
      }
      addSheet('Transactions', <List<String>>[transactionHeaders, ...rows.map(transactionRow)]);
      addSheet('Currently Issued', <List<String>>[transactionHeaders, ...issued.map(transactionRow)]);
      addSheet('Returned History', <List<String>>[transactionHeaders, ...returned.map(transactionRow)]);
      addSheet('Overdue', <List<String>>[transactionHeaders, ...overdue.map(transactionRow)]);

      addSheet('Books', <List<String>>[
        <String>['Book Number / પુસ્તક નંબર', 'Book Name / પુસ્તકનું નામ', 'Author / લેખક', 'Publication / પ્રકાશક', 'Price ₹ / કિંમત', 'ISBN', 'Catalog Status / સ્થિતિ', 'Removal Reason / દૂર કરવાનું કારણ', 'Reason Details / કારણની વિગત', 'Removed At / દૂર કરવાની તારીખ', 'Removed By / નોંધ કરનાર'],
        ..._books.map((book) => <String>[
          _clean(book['book_number']), _clean(book['book_name']), _clean(book['author']),
          _clean(book['publication']), _double(book['price']).toStringAsFixed(2),
          _clean(book['isbn']), _clean(book['is_active']).toLowerCase() == 'false' ? 'Archived / દૂર કરેલ' : 'Active / સક્રિય',
          _reasonLabel(_clean(book['retired_reason_code'])), _clean(book['retired_reason_details']),
          _clean(book['retired_at']), _clean(book['retired_by_teacher_name']),
        ]),
      ]);
      addSheet('Removed Books', <List<String>>[
        <String>['Book Number', 'Book Name', 'Reason', 'Reason Details', 'Removed At', 'Recorded By'],
        ...retiredBooks.map((book) => <String>[
          _clean(book['book_number']), _clean(book['book_name']),
          _reasonLabel(_clean(book['retired_reason_code'])), _clean(book['retired_reason_details']),
          _clean(book['retired_at']), _clean(book['retired_by_teacher_name']),
        ]),
      ]);
      addSheet('Book Number History', <List<String>>[
        <String>['Book ID', 'Book Number', 'Previous Number', 'Change Type', 'Changed By', 'Changed At'],
        ..._bookNumberHistory.map((row) => <String>[
          _clean(row['book_id']), _clean(row['book_number']), _clean(row['previous_book_number']),
          _clean(row['change_type']) == 'renumbered' ? 'નંબર બદલાયો / Renumbered' : 'નોંધાયેલ / Registered',
          _clean(row['changed_by_teacher_name']), _clean(row['changed_at']),
        ]),
      ]);

      // Merge registered students and retained historical borrower snapshots for Student Summary.
      final studentProfiles = <String, Map<String, dynamic>>{};
      String studentKey(Map<String, dynamic> row) {
        final id = _clean(row['id'] ?? row['student_id']);
        if (id.isNotEmpty) return 'id:$id';
        return 'snapshot:${_clean(row['class_label'] ?? row['class_label_snapshot'])}|${_clean(row['roll_number'] ?? row['roll_number_snapshot'])}|${_clean(row['name'] ?? row['borrower_name_snapshot'])}';
      }
      for (final student in registeredStudents) {
        final id = _clean(student['id'] ?? student['student_id']);
        final classLabel = _clean(student['library_class_label'] ?? student['class_label']);
        final roll = _clean(student['roll_number'] ?? student['roll_number_snapshot']);
        final name = _clean(student['name'] ?? student['borrower_name_snapshot']);
        final hasTransaction = rows.any((tx) => _clean(tx['borrower_type']) == 'student' && (
          id.isNotEmpty ? _clean(tx['student_id']) == id :
          _clean(tx['class_label_snapshot']) == classLabel &&
          _clean(tx['roll_number_snapshot']) == roll && _borrowerName(tx) == name
        ));
        if (hasTransaction) studentProfiles[studentKey(student)] = student;
      }
      for (final tx in rows.where((tx) => _clean(tx['borrower_type']) == 'student')) {
        final id = _clean(tx['student_id']);
        final profileKey = id.isNotEmpty
            ? 'id:$id'
            : 'snapshot:${_clean(tx['class_label_snapshot'])}|${_clean(tx['roll_number_snapshot'])}|${_borrowerName(tx)}';
        studentProfiles.putIfAbsent(profileKey, () => <String, dynamic>{
          'id': id,
          'name': _borrowerName(tx),
          'roll_number': _clean(tx['roll_number_snapshot']),
          'gr': '',
          'library_class_label': _clean(tx['class_label_snapshot']),
        });
      }
      final studentProfilesSorted = studentProfiles.values.toList()
        ..sort((a, b) {
          final classCompare = _clean(a['library_class_label'] ?? a['class_label']).compareTo(_clean(b['library_class_label'] ?? b['class_label']));
          if (classCompare != 0) return classCompare;
          final ar = _clean(a['roll_number']);
          final br = _clean(b['roll_number']);
          final ai = int.tryParse(ar);
          final bi = int.tryParse(br);
          if (ai != null && bi != null) return ai.compareTo(bi);
          return ar.compareTo(br);
        });
      List<Map<String, dynamic>> loansForStudent(Map<String, dynamic> student) {
        final id = _clean(student['id'] ?? student['student_id']);
        final classLabel = _clean(student['library_class_label'] ?? student['class_label']);
        final roll = _clean(student['roll_number'] ?? student['roll_number_snapshot']);
        final name = _clean(student['name'] ?? student['borrower_name_snapshot']);
        return rows.where((tx) => _clean(tx['borrower_type']) == 'student' && (
          id.isNotEmpty ? _clean(tx['student_id']) == id :
          _clean(tx['class_label_snapshot']) == classLabel &&
          _clean(tx['roll_number_snapshot']) == roll && _borrowerName(tx) == name
        )).toList();
      }
      List<String> studentSummaryRow(Map<String, dynamic> student) {
        final items = loansForStudent(student);
        final active = items.where(_isIssued).toList();
        final returnedItems = items.where((tx) => !_isIssued(tx)).toList();
        final totalDays = items.fold<int>(0, (sum, tx) => sum + daysKept(tx));
        final details = items.map((tx) => '${_clean(tx['book_name_snapshot'])} [${_clean(tx['book_number_snapshot'])}] (${_clean(tx['issue_date'])} to ${_clean(tx['return_date'], fallback: 'વાંચનમાં')}: ${daysKept(tx)} દિવસ)').join('; ');
        return <String>[
          _clean(student['roll_number'] ?? student['roll_number_snapshot']),
          _clean(student['library_class_label'] ?? student['class_label'] ?? student['className']),
          _clean(student['name'] ?? student['borrower_name_snapshot']),
          _clean(student['gr']), '${items.length}', '${returnedItems.length}',
          active.map((tx) => '${_clean(tx['book_name_snapshot'])} (${_clean(tx['book_number_snapshot'])})').join(', '),
          active.map((tx) => _clean(tx['issue_date'])).join(', '), '$totalDays',
          items.fold<double>(0, (sum, tx) => sum + _calculatedFine(tx)).toStringAsFixed(2), details,
        ];
      }
      final studentSummaryHeaders = <String>[
        'રોલ નંબર / Roll', 'ધોરણ / Class', 'વિદ્યાર્થીનું નામ / Student', 'GR',
        'કુલ પુસ્તકો / Total Issues', 'પરત / Returned', 'હાલના પુસ્તકો / Currently Holding',
        'જારી તારીખ / Issue Dates', 'કુલ વાંચન દિવસ / Total Reading Days', 'કુલ દંડ ₹ / Fine', 'પુસ્તક ઇતિહાસ / History',
      ];
      final studentSummaryRows = <List<String>>[
        studentSummaryHeaders,
        ...studentProfilesSorted.map(studentSummaryRow),
      ];
      addSheet('Student Summary', studentSummaryRows);

      final classLabels = <String>{
        for (final tx in rows.where((tx) => _clean(tx['borrower_type']) == 'student')) _clean(tx['class_label_snapshot']),
      }..removeWhere((label) => label.isEmpty);
      final sortedClassLabels = classLabels.toList()..sort();
      final classSummaryRows = <List<String>>[
        <String>['ધોરણ / Class', 'Registered Members', 'Total Issues', 'Currently Issued', 'Returned', 'Overdue', 'Total Reading Days', 'Calculated Fine ₹'],
      ];
      for (final classLabel in sortedClassLabels) {
        final classTx = rows.where((tx) => _clean(tx['borrower_type']) == 'student' && _clean(tx['class_label_snapshot']) == classLabel).toList();
        classSummaryRows.add(<String>[
          classLabel, '${registeredCountsByClass[classLabel] ?? 0}', '${classTx.length}',
          '${classTx.where(_isIssued).length}', '${classTx.where((tx) => !_isIssued(tx)).length}',
          '${classTx.where(_isOverdue).length}', '${classTx.fold<int>(0, (sum, tx) => sum + daysKept(tx))}',
          classTx.fold<double>(0, (sum, tx) => sum + _calculatedFine(tx)).toStringAsFixed(2),
        ]);
        addSheet('Class - $classLabel', <List<String>>[transactionHeaders, ...classTx.map(transactionRow)]);
        final classStudents = studentProfilesSorted.where((student) =>
          _clean(student['library_class_label'] ?? student['class_label'] ?? student['className']) == classLabel
        ).toList();
        addSheet('Students - $classLabel', <List<String>>[
          studentSummaryHeaders,
          ...classStudents.map(studentSummaryRow),
        ]);
      }
      addSheet('Class-wise', classSummaryRows);

      final teacherGroups = <String, List<Map<String, dynamic>>>{};
      for (final tx in rows) {
        final name = _clean(tx['recorded_by_teacher_name'], fallback: 'શિક્ષક નામ ઉપલબ્ધ નથી');
        teacherGroups.putIfAbsent(name, () => <Map<String, dynamic>>[]).add(tx);
      }
      final teacherRows = <List<String>>[
        <String>['નોંધનાર શિક્ષક / Recorded By', 'Total Transactions', 'Currently Issued', 'Returned', 'Overdue', 'Total Reading Days', 'Calculated Fine ₹'],
      ];
      for (final entry in teacherGroups.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
        final items = entry.value;
        teacherRows.add(<String>[
          entry.key, '${items.length}', '${items.where(_isIssued).length}',
          '${items.where((tx) => !_isIssued(tx)).length}', '${items.where(_isOverdue).length}',
          '${items.fold<int>(0, (sum, tx) => sum + daysKept(tx))}',
          items.fold<double>(0, (sum, tx) => sum + _calculatedFine(tx)).toStringAsFixed(2),
        ]);
      }
      addSheet('Teacher-wise', teacherRows);

      final teacherProfiles = <String, Map<String, dynamic>>{};
      for (final teacher in _teachers) {
        teacherProfiles[_clean(teacher['id'])] = teacher;
      }
      for (final tx in rows.where((tx) => _clean(tx['borrower_type']) == 'teacher')) {
        final id = _clean(tx['teacher_borrower_id']);
        if (id.isEmpty) continue;
        teacherProfiles.putIfAbsent(id, () => <String, dynamic>{'id': id, 'teacher_name': _borrowerName(tx)});
      }
      final sortedTeachers = teacherProfiles.values.toList()
        ..sort((a, b) => _clean(a['teacher_name']).compareTo(_clean(b['teacher_name'])));
      final teacherSummaryRows = <List<String>>[
        <String>['શિક્ષકનું નામ / Teacher', 'કુલ પુસ્તકો / Total Received', 'પરત / Returned', 'હાલનાં પુસ્તકો / Currently Holding', 'જારી તારીખો / Issue Dates', 'કુલ વાંચન દિવસ / Total Reading Days', 'કુલ દંડ ₹ / Fine', 'પુસ્તક ઇતિહાસ / History'],
      ];
      for (final teacher in sortedTeachers) {
        final teacherId = _clean(teacher['id']);
        final items = rows.where((tx) => _clean(tx['borrower_type']) == 'teacher' && (
          teacherId.isNotEmpty ? _clean(tx['teacher_borrower_id']) == teacherId : _borrowerName(tx) == _clean(teacher['teacher_name'])
        )).toList();
        final active = items.where(_isIssued).toList();
        final details = items.map((tx) => '${_clean(tx['book_name_snapshot'])} [${_clean(tx['book_number_snapshot'])}] (${_clean(tx['issue_date'])} to ${_clean(tx['return_date'], fallback: 'વાંચનમાં')}: ${daysKept(tx)} દિવસ)').join('; ');
        teacherSummaryRows.add(<String>[
          _clean(teacher['teacher_name']), '${items.length}', '${items.where((tx) => !_isIssued(tx)).length}',
          active.map((tx) => '${_clean(tx['book_name_snapshot'])} (${_clean(tx['book_number_snapshot'])})').join(', '),
          active.map((tx) => _clean(tx['issue_date'])).join(', '),
          '${items.fold<int>(0, (sum, tx) => sum + daysKept(tx))}',
          items.fold<double>(0, (sum, tx) => sum + _calculatedFine(tx)).toStringAsFixed(2), details,
        ]);
      }
      addSheet('Teacher Borrowers', teacherSummaryRows);

      final bytes = workbook.encode();
      if (bytes == null || bytes.isEmpty) throw StateError('Excel report બનાવી શકાયો નથી.');
      await PsmFileExportHelper.saveOrShare(
        bytes: Uint8List.fromList(bytes),
        filename: 'PSM_Digital_Library_All_Reports_${_todayIso()}.xlsx',
        title: 'Digital Library — All Reports',
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      _message(rosterComplete
          ? 'બધા રિપોર્ટ્સ એક Excel ફાઇલમાં ડાઉનલોડ થયા.'
          : 'રિપોર્ટ ડાઉનલોડ થયા; કેટલીક સક્રિય વિદ્યાર્થી યાદી લોડ ન થઈ હોવાથી જૂના આપ-લે રેકોર્ડ્સ જાળવ્યા છે.',
        warning: !rosterComplete,
      );
    } catch (error) {
      if (mounted) _message('રિપોર્ટ તૈયાર થઈ શક્યો નથી: ${_friendlyError(error)}', error: true);
    } finally {
      if (mounted) setState(() => _reportBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final themed = Theme(
      data: baseTheme.copyWith(
        textTheme: baseTheme.textTheme.apply(fontFamily: 'NotoSansGujaratiLocal'),
        primaryTextTheme: baseTheme.primaryTextTheme.apply(fontFamily: 'NotoSansGujaratiLocal'),
      ),
      child: _loading && _school.isEmpty
          ? Scaffold(
              appBar: widget.embedded
                  ? null
                  : AppBar(title: const Text('ડિજિટલ પુસ્તકાલય / Digital Library')),
              body: const Center(child: CircularProgressIndicator()),
            )
          : _error != null && _school.isEmpty
              ? Scaffold(
                  appBar: widget.embedded
                      ? null
                      : AppBar(title: const Text('ડિજિટલ પુસ્તકાલય / Digital Library')),
                  body: _errorView(),
                )
              : _libraryScaffold(),
    );
    return themed;
  }

  Widget _errorView() => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_outlined, size: 52),
              const SizedBox(height: 12),
              Text('પુસ્તકાલય લોડ થઈ શક્યું નથી', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              SelectableText(_error ?? 'અજ્ઞાત ભૂલ'),
              const SizedBox(height: 14),
              FilledButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('ફરી પ્રયાસ કરો / Retry')),
            ]),
          ),
        ),
      );

  Widget _libraryScaffold() {
    final tabs = <Tab>[
      const Tab(icon: Icon(Icons.dashboard_outlined), text: 'ઝાંખી'),
      const Tab(icon: Icon(Icons.menu_book_outlined), text: 'પુસ્તકો'),
      const Tab(icon: Icon(Icons.swap_horiz), text: 'આપ-લે'),
      const Tab(icon: Icon(Icons.receipt_long_outlined), text: 'નોંધપોથી'),
      const Tab(icon: Icon(Icons.summarize_outlined), text: 'રિપોર્ટ્સ'),
      if (_isAdmin) const Tab(icon: Icon(Icons.settings_outlined), text: 'સેટિંગ્સ'),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Builder(builder: (tabContext) {
        final pages = <Widget>[
          _dashboardTab(),
          _booksTab(),
          _circulationTab(),
          _transactionsTab(onOpenCirculation: () => DefaultTabController.of(tabContext).animateTo(2)),
          _reportsTab(),
          if (_isAdmin) _settingsTab(),
        ];
        return Scaffold(
        appBar: widget.embedded
            ? null
            : AppBar(
                title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(_schoolName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const Text('ડિજિટલ પુસ્તકાલય / Digital Library', style: TextStyle(fontSize: 12)),
                ]),
                actions: [
                  IconButton(tooltip: 'Refresh / તાજું કરો', onPressed: _loading ? null : () => _refresh(), icon: const Icon(Icons.refresh)),
                  if (_isAdmin && !_readOnly)
                    IconButton(tooltip: 'Book Excel Template', onPressed: _downloadBookTemplate, icon: const Icon(Icons.download_for_offline_outlined)),
                  if (_isAdmin && !_readOnly)
                    IconButton(tooltip: 'Bulk Upload Books / પુસ્તકો અપલોડ', onPressed: _importBusy ? null : _importBooks, icon: const Icon(Icons.upload_file)),
                  IconButton(tooltip: 'Download All Reports', onPressed: _reportBusy || _loading ? null : _exportAllReports, icon: const Icon(Icons.file_download_outlined)),
                ],
                bottom: TabBar(isScrollable: true, tabs: tabs),
              ),
        body: widget.embedded
            ? Column(children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Row(children: [
                    const Icon(Icons.local_library_outlined),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_schoolName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                      const Text('ડિજિટલ પુસ્તકાલય / Digital Library'),
                    ])),
                    IconButton(tooltip: 'Refresh', onPressed: _loading ? null : () => _refresh(), icon: const Icon(Icons.refresh)),
                    IconButton(tooltip: 'Download All Reports', onPressed: _reportBusy || _loading ? null : _exportAllReports, icon: const Icon(Icons.file_download_outlined)),
                  ]),
                ),
                Material(color: Theme.of(context).colorScheme.surface, child: TabBar(isScrollable: true, tabs: tabs)),
                if (_readOnly) _readOnlyBanner(),
                if (_loading) const LinearProgressIndicator(),
                Expanded(child: TabBarView(
            physics: const NeverScrollableScrollPhysics(),children: pages)),
              ])
            : Column(children: [
                if (_readOnly) _readOnlyBanner(),
                if (_loading) const LinearProgressIndicator(),
                Expanded(child: TabBarView(
            physics: const NeverScrollableScrollPhysics(),children: pages)),
              ]),
      );
      }),
    );
  }

  Widget _readOnlyBanner() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        color: Colors.orange.shade100,
        child: Text(
          _readOnlyReason,
          style: const TextStyle(color: Colors.brown, fontWeight: FontWeight.w600),
        ),
      );

  int _booksDistributedInClass(String classId, {bool activeOnly = false}) {
    if (classId.isEmpty) return 0;
    final label = _classLabel(classId);
    return _transactions.where((tx) {
      if (_clean(tx['borrower_type']) == 'teacher') return false;
      if (activeOnly && !_isIssued(tx)) return false;
      final txClassId = _clean(tx['class_id']);
      final txClassLabel = _clean(tx['class_label_snapshot']);
      if (txClassId.isNotEmpty) return txClassId == classId;
      return label.isNotEmpty && txClassLabel == label;
    }).length;
  }

  int _booksDistributedWholeSchool({bool activeOnly = false}) {
    return _transactions.where((tx) {
      if (activeOnly && !_isIssued(tx)) return false;
      return true;
    }).length;
  }

  Widget _classAndSchoolStatsCard() {
    final hasClass = _selectedClassId.isNotEmpty;
    final classLabel = hasClass ? _classLabel(_selectedClassId) : 'વર્ગ પસંદ કરો';
    final classStudents = hasClass
        ? (_students.isNotEmpty
            ? _students.length
            : (_studentCountByClassId[_selectedClassId] ?? 0))
        : 0;
    final classActiveBooks =
        hasClass ? _booksDistributedInClass(_selectedClassId, activeOnly: true) : 0;
    final classTotalBooks =
        hasClass ? _booksDistributedInClass(_selectedClassId, activeOnly: false) : 0;

    final schoolStudents = _wholeSchoolStudentCount;
    final schoolActiveBooks = _booksDistributedWholeSchool(activeOnly: true);
    final schoolTotalBooks = _booksDistributedWholeSchool(activeOnly: false);

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.55),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasClass
                            ? '📚 પસંદ કરેલ વર્ગ: $classLabel'
                            : '📚 પસંદ કરેલ વર્ગ (વર્ગ પસંદ કરો)',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.indigo.shade900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasClass
                            ? 'કુલ વિદ્યાર્થીઓ: $classStudents  •  વિતરિત પુસ્તકો (હાલ આપેલ): $classActiveBooks (કુલ આપેલ: $classTotalBooks)'
                            : 'વર્ગ પસંદ કરશો એટલે તે વર્ગના કુલ વિદ્યાર્થીઓ અને વિતરિત પુસ્તકોની સંખ્યા અહીં દેખાશે.',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🏫 સમગ્ર શાળા (Whole School Summary)',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.teal.shade900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'શાળાના કુલ વિદ્યાર્થીઓ: $schoolStudents  •  શાળામાં વિતરિત પુસ્તકો (હાલ આપેલ): $schoolActiveBooks (કુલ આપેલ: $schoolTotalBooks)',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            CircleAvatar(backgroundColor: color.withOpacity(.12), foregroundColor: color, child: Icon(icon)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 2),
              Text(title, style: Theme.of(context).textTheme.bodySmall),
            ])),
          ]),
        ),
      );

  Widget _dashboardTab() {
    final activeBooks = _books.where((book) => _clean(book['is_active']).toLowerCase() != 'false').length;
    final issued = _activeLoans;
    final overdue = issued.where(_isOverdue).length;
    final returned = _transactions.where((tx) => !_isIssued(tx)).length;
    final available = (activeBooks - issued.length).clamp(0, 100000000);
    return RefreshIndicator(
      onRefresh: () => _refresh(quiet: true),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF073B2A), Color(0xFF0F7B55)])),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.local_library_outlined, color: Colors.white, size: 42),
              const SizedBox(height: 10),
              Text(_schoolName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: Colors.white)),
              const SizedBox(height: 4),
              const Text('પુસ્તકો, વિદ્યાર્થી અને શિક્ષકની આપ-લેનું રજિસ્ટર', style: TextStyle(color: Colors.white)),
              const SizedBox(height: 10),
              Text('DISE/UDISE: ${_clean(_school['school_id'], fallback: _clean(widget.profile['school_id'], fallback: '—'))}', style: const TextStyle(color: Colors.white70)),
              if (_readOnly) const Padding(padding: EdgeInsets.only(top: 10), child: Text('વાંચન અને રિપોર્ટ ડાઉનલોડ માટેનો મોડ', style: TextStyle(color: Colors.yellowAccent))),
            ]),
          ),
        ),
        const SizedBox(height: 4),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth > 850 ? 4 : constraints.maxWidth > 520 ? 2 : 1;
          return GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: columns == 1 ? 4.2 : 2.2,
            children: [
              _statCard('પુસ્તકાલયમાં સક્રિય પુસ્તકો', '$activeBooks', Icons.menu_book_outlined, Colors.green),
              _statCard('ઉપલબ્ધ પુસ્તકો (અંદાજ)', '$available', Icons.library_add_check_outlined, Colors.teal),
              _statCard('હાલમાં જારી', '${issued.length}', Icons.outbox_outlined, Colors.orange),
              _statCard('મુદત પૂરી / Overdue', '$overdue', Icons.warning_amber_outlined, Colors.red),
              _statCard('પરત થયેલ નોંધ', '$returned', Icons.assignment_turned_in_outlined, Colors.blue),
              _statCard('નોંધાયેલા વર્ગો', '${_classes.length}', Icons.class_outlined, Colors.indigo),
              _statCard('શાળાના કુલ વિદ્યાર્થીઓ', '$_wholeSchoolStudentCount', Icons.groups_outlined, Colors.deepPurple),
              _statCard('કુલ વિતરિત પુસ્તકો', '${_booksDistributedWholeSchool(activeOnly: false)}', Icons.auto_stories_outlined, Colors.brown),
            ],
          );
        }),
        const SizedBox(height: 8),
        _classAndSchoolStatsCard(),
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ઝડપી માર્ગદર્શન / Quick Guide', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('વિદ્યાર્થી માટે: વર્ગ પસંદ કરો → રોલ નંબર દાખલ કરો → નામ ચકાસો → પુસ્તક નંબર દાખલ કરો → તારીખ પસંદ કરો → પુષ્ટિ કર્યા પછી જારી કરો.'),
          const SizedBox(height: 6),
          const Text('શિક્ષક માટે: યાદીમાંથી શિક્ષકનું નામ પસંદ કરો. અલગ Teacher ID દાખલ કરવાની જરૂર નથી.'),
          const SizedBox(height: 6),
          const Text('Admin સક્રિય પુસ્તકનો નંબર બદલી શકે છે. જૂનો નંબર અને તેની નોંધ Book Number History રિપોર્ટમાં રહેશે; અગાઉ વપરાયેલ નંબર ફરીથી વાપરી શકાતો નથી. દૂર કરેલા પુસ્તકોનું કારણ પણ રિપોર્ટમાં રહેશે.'),
          if (_isAdmin) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: _readOnly || _importBusy ? null : _importBooks, icon: const Icon(Icons.upload_file), label: const Text('પુસ્તકોનું Excel અપલોડ')),
              OutlinedButton.icon(onPressed: _downloadBookTemplate, icon: const Icon(Icons.download), label: const Text('ખાલી Excel Template')),
              FilledButton.icon(onPressed: _reportBusy ? null : _exportAllReports, icon: _reportBusy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.file_download), label: const Text('બધા રિપોર્ટ એકસાથે')),
            ]),
          ],
        ]))),
        if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    );
  }

  Widget _booksTab() {
    final query = _bookSearch.text.trim().toLowerCase();
    final visibleBooks = _books.where((book) {
      final text = <String>[_clean(book['book_number']), _clean(book['book_name']), _clean(book['author']), _clean(book['publication']), _clean(book['isbn']), _reasonLabel(_clean(book['retired_reason_code'])), _clean(book['retired_reason_details'])].join(' ').toLowerCase();
      return text.contains(query);
    }).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Text(
            'પુસ્તક યાદી / Book Catalogue',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (_isAdmin && !_readOnly) ...[
            FilledButton.icon(
              onPressed: (_manualBookSaveBusy || _importBusy)
                  ? null
                  : _addBookManually,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('નવું પુસ્તક ઉમેરો / Add Book'),
            ),
            PopupMenuButton<String>(
              tooltip: 'Book Import Options',
              onSelected: (value) =>
                  value == 'template' ? _downloadBookTemplate() : _importBooks(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'template',
                    child: ListTile(
                        leading: Icon(Icons.download),
                        title: Text('ખાલી Template ડાઉનલોડ'))),
                PopupMenuItem(
                    value: 'upload',
                    child: ListTile(
                        leading: Icon(Icons.upload_file),
                        title: Text('Bulk Book Upload'))),
              ],
            ),
          ],
        ],
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _bookSearch,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          labelText: 'પુસ્તક નંબર, નામ, લેખક અથવા ISBN શોધો',
          suffixIcon: IconButton(onPressed: () => setState(() => _bookSearch.clear()), icon: const Icon(Icons.clear)),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      if (_importBusy || _manualBookSaveBusy) const LinearProgressIndicator(),
      Text('${visibleBooks.length} પુસ્તકો દર્શાવેલ', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      if (visibleBooks.isEmpty)
        _emptyCard(
          'પુસ્તકો મળ્યાં નથી',
          _isAdmin
              ? 'નવું પુસ્તક ઉમેરો અથવા Excel દ્વારા પુસ્તકો અપલોડ કરો.'
              : 'શાળા એડમિન પુસ્તક યાદી અપડેટ કરે પછી અહીં દેખાશે.',
        ),
      ...visibleBooks.map(_bookCard),
      if (_isAdmin && !_readOnly) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: _importBusy ? null : _importBooks, icon: const Icon(Icons.cloud_upload_outlined), label: const Text('Bulk Book Upload / એકસાથે પુસ્તકો ઉમેરો')),
        const Text('પહેલેથી નોંધાયેલ પુસ્તક નંબર ફરીથી ઉમેરાશે નહીં. સ્ટુડન્ટ અથવા ટીચર Excel અપલોડ અહીં નથી; તેઓ શાળાના રજિસ્ટરથી જ આવે છે.', style: TextStyle(fontSize: 12)),
      ],
    ]);
  }

  String _reasonLabel(String code) => switch (code) {
        'lost' => 'ખોવાઈ ગયું / Lost',
        'torn' => 'ફાટી ગયું / Torn',
        'damaged' => 'ક્ષતિગ્રસ્ત / Damaged',
        'worn_out' => 'જૂનું / Worn out',
        'other' => 'અન્ય / Other',
        '' => 'કારણ નોંધાયેલ નથી / Not recorded',
        _ => code,
      };

  Widget _bookCard(Map<String, dynamic> book) {
    final active = _clean(book['is_active']).toLowerCase() != 'false';
    final loans = _transactions.where((tx) => _isIssued(tx) && _clean(tx['book_id']) == _clean(book['id']));
    final loan = loans.isEmpty ? null : loans.first;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(backgroundColor: active ? Colors.green.shade50 : Colors.grey.shade200, foregroundColor: active ? Colors.green.shade800 : Colors.grey, child: const Icon(Icons.menu_book_outlined)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_clean(book['book_number'])}  •  ${_clean(book['book_name'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
            if (_clean(book['author']).isNotEmpty) Text('લેખક: ${_clean(book['author'])}'),
            if (_clean(book['publication']).isNotEmpty) Text('પ્રકાશક: ${_clean(book['publication'])}'),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (_clean(book['isbn']).isNotEmpty) Chip(label: Text('ISBN ${_clean(book['isbn'])}'), visualDensity: VisualDensity.compact),
              Chip(label: Text(_money(book['price'])), visualDensity: VisualDensity.compact),
              Chip(label: Text(!active ? 'દૂર કરેલું' : loan != null ? 'જારી છે' : 'ઉપલબ્ધ'), visualDensity: VisualDensity.compact, backgroundColor: !active ? Colors.grey.shade200 : loan != null ? Colors.orange.shade100 : Colors.green.shade100),
            ]),
            if (loan != null) Text('વાચક: ${_borrowerName(loan)} • જારી: ${_dateText(loan['issue_date'])}', style: Theme.of(context).textTheme.bodySmall),
            if (!active) ...[
              Text('કારણ: ${_reasonLabel(_clean(book['retired_reason_code']))}', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.deepOrange)),
              if (_clean(book['retired_reason_details']).isNotEmpty) Text('વિગત: ${_clean(book['retired_reason_details'])}'),
              if (_clean(book['retired_at']).isNotEmpty) Text('દૂર કરવાની તારીખ: ${_dateText(book['retired_at'])}'),
              if (_clean(book['retired_by_teacher_name']).isNotEmpty) Text('નોંધ કરનાર: ${_clean(book['retired_by_teacher_name'])}'),
            ],
          ])),
          if (_isAdmin && !_readOnly && active)
            Column(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'પુસ્તક નંબર બદલો',
                onPressed: _actionBusy || loan != null ? null : () => _changeBookNumber(book),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'કારણ સાથે પુસ્તક દૂર કરો',
                onPressed: _actionBusy || loan != null ? null : () => _archiveBook(book),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
              ),
            ]),
        ]),
      ),
    );
  }

  Widget _circulationTab() {
    final selectedBook = _selectedBook;
    final selectedStudent = _selectedStudent;
    final selectedTeacher = _selectedTeacher;
    final selectedBorrower = _borrowerType == 'student' ? selectedStudent : selectedTeacher;
    final activeLoans = _selectedBorrowerLoans;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('પુસ્તક આપવું / પરત લેવું', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      const Text('નોંધ: વિદ્યાર્થીનું નામ નોંધાયેલા વર્ગ અને રોલ નંબરથી મળશે. શિક્ષક માટે યાદીમાંથી નામ પસંદ કરો.'),
      if (_readOnly) Padding(padding: const EdgeInsets.only(top: 8), child: _readOnlyBanner()),
      const SizedBox(height: 10),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'student', icon: Icon(Icons.school_outlined), label: Text('વિદ્યાર્થી')),
          ButtonSegment(value: 'teacher', icon: Icon(Icons.person_outline), label: Text('શિક્ષક')),
        ],
        selected: <String>{_borrowerType},
        onSelectionChanged: _readOnly ? null : (values) {
          setState(() {
            _borrowerType = values.first;
            _selectedClassId = '';
            _selectedStudentId = '';
            _selectedTeacherId = '';
            _selectedReturnTransactionId = '';
            _rollController.clear();
            _selectedBookId = '';
            _bookNumberController.clear();
            _students = <Map<String, dynamic>>[];
          });
        },
      ),
      const SizedBox(height: 14),
      if (_borrowerType == 'student') ...[
        DropdownButtonFormField<String>(
          isExpanded: true,
          value: _issueableClasses.any((row) => _clean(row['id']) == _selectedClassId) ? _selectedClassId : null,
          decoration: const InputDecoration(labelText: 'વર્ગ પસંદ કરો / Select Class', prefixIcon: Icon(Icons.class_outlined)),
          items: _issueableClasses.map((row) => DropdownMenuItem(value: _clean(row['id']), child: Text(_clean(row['label'])))).toList(),
          onChanged: _readOnly ? null : (value) { if (value != null) _loadStudentsForClass(value); },
        ),
        const SizedBox(height: 10),
        _classAndSchoolStatsCard(),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(
            controller: _rollController,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(labelText: 'વિદ્યાર્થીનો રોલ નંબર', hintText: 'ઉદા. 12 / Roll Number', prefixIcon: Icon(Icons.numbers)),
            onChanged: (_) {
              final roll = _normRoll(_rollController.text);
              final matches = _students.where((s) => _normRoll(s['roll_number']) == roll);
              final found = matches.isEmpty ? null : matches.first;
              setState(() {
                _selectedStudentId = found == null ? '' : _clean(found['id']);
                final loans = _selectedBorrowerLoans;
                _selectedReturnTransactionId = loans.isNotEmpty ? _clean(loans.first['id']) : '';
              });
            },
            onSubmitted: (_) => _findStudent(),
          )),
          const SizedBox(width: 8),
          FilledButton.tonal(onPressed: _readOnly ? null : _findStudent, child: const Text('નામ શોધો')),
        ]),
        const SizedBox(height: 8),
        if (selectedStudent != null)
          _personBox(
            name: _clean(selectedStudent['name']),
            subtitle: 'ધોરણ: ${ClassLabel.bare(_classLabel(_selectedClassId))}  •  રોલ નંબર: ${_clean(selectedStudent['roll_number'])}${_clean(selectedStudent['gr']).isEmpty ? '' : '  •  GR: ${_clean(selectedStudent['gr'])}'}',
            icon: Icons.school_outlined,
          )
        else
          _emptyCard('વિદ્યાર્થીની વિગતો', 'વર્ગ પસંદ કરો અને શાળાના રજિસ્ટરમાં નોંધાયેલ રોલ નંબર દાખલ કરો.'),
        if (activeLoans.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildSelectedStudentIssuedBooksBanner(activeLoans),
        ],
        if (_selectedClassId.isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildClassIssuedBooksCard(),
        ],
      ] else ...[
        DropdownButtonFormField<String>(
          value: _selectedTeacherId.isEmpty ? null : _selectedTeacherId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'શિક્ષકનું નામ પસંદ કરો / Select Teacher', prefixIcon: Icon(Icons.person_outline)),
          items: _teachers.map((row) => DropdownMenuItem(value: _clean(row['id']), child: Text(_clean(row['teacher_name'])))).toList(),
          onChanged: _readOnly ? null : (value) => setState(() { _selectedTeacherId = value ?? ''; _selectedReturnTransactionId = ''; }),
        ),
        const SizedBox(height: 8),
        if (selectedTeacher != null)
          _personBox(name: _clean(selectedTeacher['teacher_name']), subtitle: 'શાળાના નોંધાયેલા શિક્ષક', icon: Icons.person_outline)
        else
          _emptyCard('શિક્ષક પસંદ કરો', 'અલગ Teacher ID જરૂરી નથી. નામની યાદીમાંથી પસંદ કરો.'),
      ],
      const SizedBox(height: 16),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TabBar(
          controller: _circulationController,
          onTap: (index) => setState(() {}),
          tabs: const [Tab(text: '📕 પુસ્તક આપો'), Tab(text: '📗 પુસ્તક પરત લો')],
        ),
        SizedBox(
          height: _borrowerType == 'student' ? 455 : 405,
          child: TabBarView(
            physics: const NeverScrollableScrollPhysics(),
            controller: _circulationController,
            children: [
              _issueForm(selectedBorrower, selectedBook),
              _returnForm(activeLoans),
            ],
          ),
        ),
      ]),
    ]);
  }

  Widget _personBox({required String name, required String subtitle, required IconData icon}) => Card(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(.45),
        child: ListTile(leading: Icon(icon, size: 32), title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(subtitle)),
      );

  Widget _buildSelectedStudentIssuedBooksBanner(List<Map<String, dynamic>> loans) {
    final canReturn = !_readOnly && (_isAdmin || _canManageStudentClass(_selectedClassId));
    return Card(
      color: Colors.amber.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.amber.shade700, width: 1.4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.menu_book_rounded, color: Colors.amber.shade900),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'આ વિદ્યાર્થી પાસે હાલમાં ${loans.length} પુસ્તક જારી છે (અહીંથી સીધું પરત લઈ શકાશે):',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final tx in loans)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'રોલ નં.: ${_liveRollForLoan(tx)}  •  ${_liveStudentNameForLoan(tx)}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'પુસ્તક નં.: ${_clean(tx['book_number_snapshot'])}  —  ${_clean(tx['book_name_snapshot'])}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.indigo.shade900,
                          ),
                        ),
                        Text(
                          'આપ્યા તા.: ${_dateText(tx['issue_date'])}  •  છેલ્લી તા.: ${_dateText(tx['due_date'])}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: (_actionBusy || !canReturn) ? null : () => _quickReturnLoan(tx),
                      icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
                      label: const Text('📗 પુસ્તક પરત લો (Return)'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildClassIssuedBooksCard() {
    final classLoans = _selectedClassActiveLoans;
    final className = _classLabel(_selectedClassId);
    final canReturn = !_readOnly && (_isAdmin || _canManageStudentClass(_selectedClassId));

    return Card(
      color: Colors.blueGrey.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.indigo.shade200, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.library_books_outlined, color: Colors.indigo.shade900),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '📖 $className માં હાલ પુસ્તક આપેલ વિદ્યાર્થીઓ (${classLoans.length})',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (classLoans.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('આ વર્ગમાં હાલ કોઈ વિદ્યાર્થી પાસે પુસ્તક જારી નથી.'),
              )
            else
              for (final tx in classLoans)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.indigo.shade100),
                  ),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      InkWell(
                        onTap: () {
                          final roll = _liveRollForLoan(tx);
                          setState(() {
                            _selectedStudentId = _clean(tx['student_id']);
                            if (roll != '—') _rollController.text = roll;
                            _selectedReturnTransactionId = _clean(tx['id']);
                          });
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'રોલ નં.: ${_liveRollForLoan(tx)}  •  ${_liveStudentNameForLoan(tx)}',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              'પુસ્તક નં.: ${_clean(tx['book_number_snapshot'])}  —  ${_clean(tx['book_name_snapshot'])}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Colors.indigo.shade800,
                              ),
                            ),
                            Text(
                              'આપ્યા તા.: ${_dateText(tx['issue_date'])}  •  મુદત: ${_dateText(tx['due_date'])}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green.shade50,
                          foregroundColor: Colors.green.shade900,
                        ),
                        onPressed: (_actionBusy || !canReturn) ? null : () => _quickReturnLoan(tx),
                        icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
                        label: const Text('📗 પરત લો (Return)'),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _issueForm(Map<String, dynamic>? borrower, Map<String, dynamic>? book) => ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          Row(children: [
            Expanded(child: TextField(
              controller: _bookNumberController,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(labelText: 'પુસ્તક નંબર / Book Number', prefixIcon: Icon(Icons.qr_code_2), hintText: 'પુસ્તક પરનો નંબર દાખલ કરો'),
              onChanged: (_) => _findBook(notifyMissing: false),
              onSubmitted: (_) => _findBook(),
              readOnly: _readOnly,
            )),
            const SizedBox(width: 8),
            FilledButton.tonal(onPressed: _readOnly ? null : () => _findBook(), child: const Text('શોધો')),
          ]),
          const SizedBox(height: 8),
          if (book != null)
            _personBox(name: _clean(book['book_name']), subtitle: 'નંબર: ${_clean(book['book_number'])}${_clean(book['author']).isEmpty ? '' : '  •  લેખક: ${_clean(book['author'])}'}', icon: Icons.menu_book_outlined)
          else
            _emptyCard('પુસ્તકની વિગતો', 'પુસ્તક નંબર નાખતાં પુસ્તકનું નામ અહીં દેખાશે.'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _readOnly ? null : () async { final picked = await _pickDate(_issueDate); if (picked != null && mounted) setState(() => _issueDate = picked); },
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text('જારી તારીખ: ${_dateText(_iso(_issueDate))}  (તારીખ બદલો)'),
          ),
          const SizedBox(height: 8),
          Text('છેલ્લી પરત તારીખ: ${_dateText(_iso(_issueDate.add(Duration(days: _dueDays))))}  •  મુદત: $_dueDays દિવસ', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          TextField(controller: _issueRemarksController, maxLines: 2, readOnly: _readOnly, decoration: const InputDecoration(labelText: 'નોંધ (વૈકલ્પિક)', prefixIcon: Icon(Icons.notes))),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _actionBusy || _readOnly || borrower == null || book == null || (_borrowerType == 'student' && !_canManageStudentClass(_selectedClassId)) ? null : _issueBook,
            icon: _actionBusy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.outbox_outlined),
            label: const Text('ચકાસો અને પુસ્તક જારી કરો'),
          ),
          if (_borrowerType == 'student' && !_canManageStudentClass(_selectedClassId)) const Padding(padding: EdgeInsets.only(top: 6), child: Text('તમારા લૉગિનને આ વિદ્યાર્થીને પુસ્તક આપવા પરવાનગી નથી. હાલમાં જારી પુસ્તકો જોઈ શકો છો; પરત/જારી માટે Admin દ્વારા પસંદ કરાયેલા શિક્ષકનો સંપર્ક કરો.')),
          if (_readOnly) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Read-only: હાલ કોઈ નવી પુસ્તક નોંધ કરી શકાશે નહીં.')),
        ],
      );

  Widget _returnForm(List<Map<String, dynamic>> activeLoans) => ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          if (_selectedBorrower == null)
            _emptyCard('વાચક પસંદ કરો', 'વિદ્યાર્થી અથવા શિક્ષક પસંદ કર્યા પછી તેમના સક્રિય પુસ્તકો અહીં દેખાશે.')
          else if (activeLoans.isEmpty)
            _emptyCard('સક્રિય જારી પુસ્તક નથી', 'આ વાચકના નામે હાલમાં કોઈ પુસ્તક જારી નથી.')
          else
            DropdownButtonFormField<String>(
              value: activeLoans.any((tx) => _clean(tx['id']) == _selectedReturnTransactionId) ? _selectedReturnTransactionId : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'પરત મળતું પુસ્તક પસંદ કરો', prefixIcon: Icon(Icons.menu_book_outlined)),
              items: activeLoans.map((tx) => DropdownMenuItem(value: _clean(tx['id']), child: Text('${_bookTitle(tx)} • છેલ્લી તારીખ ${_dateText(tx['due_date'])}', maxLines: 2, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: _readOnly ? null : (value) => setState(() => _selectedReturnTransactionId = value ?? ''),
            ),
          if (_selectedReturnTransactionId.isNotEmpty && _findById(_transactions, _selectedReturnTransactionId) != null) ...[
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final tx = _findById(_transactions, _selectedReturnTransactionId)!;
              return _personBox(name: _borrowerName(tx), subtitle: '${_bookTitle(tx)}  •  જારી: ${_dateText(tx['issue_date'])}  •  મુદત: ${_dateText(tx['due_date'])}', icon: Icons.person_outline);
            }),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _readOnly ? null : () async {
              final tx = _findById(_transactions, _selectedReturnTransactionId);
              final issue = _parseDate(tx?['issue_date']);
              final picked = await _pickDate(_returnDate, notBefore: issue);
              if (picked != null && mounted) setState(() => _returnDate = picked);
            },
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text('પરત તારીખ: ${_dateText(_iso(_returnDate))}  (તારીખ બદલો)'),
          ),
          const SizedBox(height: 8),
          TextField(controller: _returnRemarksController, maxLines: 2, readOnly: _readOnly, decoration: const InputDecoration(labelText: 'પરત અંગે નોંધ (વૈકલ્પિક)', prefixIcon: Icon(Icons.notes))),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _actionBusy || _readOnly || _selectedReturnTransactionId.isEmpty || _returnNotAllowedBySetting ? null : _returnBook,
            icon: _actionBusy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.assignment_turned_in_outlined),
            label: const Text('ચકાસો અને પરત નોંધો'),
          ),
        ],
      );

  bool get _returnNotAllowedBySetting {
    final loan = _findById(_transactions, _selectedReturnTransactionId);
    if (loan == null || _isAdmin || _clean(loan['borrower_type']) != 'student') return false;
    return !_canManageStudentClass(_clean(loan['class_id']));
  }

  // Returns the selected borrower based on current circulation mode.
  Map<String, dynamic>? get _selectedBorrower => _borrowerType == 'student' ? _selectedStudent : _selectedTeacher;

  Widget _transactionsTab({required VoidCallback onOpenCirculation}) {
    final rows = _filteredTransactions;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('પુસ્તક આપ-લેની નોંધપોથી', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      const Text('તમામ સક્રિય શિક્ષકો હાલમાં વિદ્યાર્થીઓ પાસે રહેલા પુસ્તકો જોઈ શકે છે. પુસ્તક આપવાની અને પરત લેવાની પરવાનગી Admin ની Library Settings પ્રમાણે લાગુ પડે છે.'),
      const SizedBox(height: 10),
      TextField(controller: _transactionSearch, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: 'પુસ્તક નંબર, પુસ્તક/વાચકનું નામ, રોલ અથવા વર્ગ શોધો', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(onPressed: () => setState(() => _transactionSearch.clear()), icon: const Icon(Icons.clear)))),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        isExpanded: true,
        value: _transactionStatusFilter,
        decoration: const InputDecoration(labelText: 'સ્થિતિ પ્રમાણે ફિલ્ટર'),
        items: const [
          DropdownMenuItem(value: 'all', child: Text('બધી નોંધો')),
          DropdownMenuItem(value: 'issued', child: Text('હાલમાં જારી')),
          DropdownMenuItem(value: 'returned', child: Text('પરત થયેલ')),
          DropdownMenuItem(value: 'overdue', child: Text('મુદત પૂરી થયેલ')),
        ],
        onChanged: (value) => setState(() => _transactionStatusFilter = value ?? 'all'),
      ),
      const SizedBox(height: 8),
      Text('${rows.length} નોંધો', style: Theme.of(context).textTheme.bodySmall),
      if (rows.isEmpty) _emptyCard('નોંધ નથી', 'પસંદ કરેલા ફિલ્ટર માટે કોઈ નોંધ મળી નથી.'),
      ...rows.take(500).map((tx) => Card(child: ListTile(
            leading: CircleAvatar(child: Icon(_isIssued(tx) ? Icons.outbox_outlined : Icons.assignment_turned_in_outlined)),
            title: Text(_bookTitle(tx), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              '${_borrowerName(tx)}${_clean(tx['class_label_snapshot']).isEmpty ? '' : ' • ${_clean(tx['class_label_snapshot'])}'}'
              '${_clean(tx['roll_number_snapshot']).isEmpty ? '' : ' • રોલ ${_clean(tx['roll_number_snapshot'])}'}\n'
              'જારી: ${_dateText(tx['issue_date'])} • છેલ્લી તારીખ: ${_dateText(tx['due_date'])}'
              '${_clean(tx['return_date']).isEmpty ? '' : ' • પરત: ${_dateText(tx['return_date'])}'}\n'
              'સ્થિતિ: ${_isIssued(tx) ? (_isOverdue(tx) ? 'મુદત પૂરી' : 'જારી છે') : 'પરત'} • વિલંબ દિવસ: ${_overdueDays(tx)} • દંડ: ${_money(_calculatedFine(tx))}',
            ),
            isThreeLine: true,
            trailing: _isIssued(tx) ? IconButton(tooltip: 'પરત નોંધો', onPressed: _readOnly ? null : () async {
              final borrowerType = _clean(tx['borrower_type']) == 'teacher' ? 'teacher' : 'student';
              final classId = _clean(tx['class_id']);
              if (borrowerType == 'student' && classId.isNotEmpty) {
                await _loadStudentsForClass(classId);
              }
              if (!mounted) return;
              final sid = _clean(tx['student_id']);
              final matchedStudent = sid.isEmpty
                  ? null
                  : _students.cast<Map<String, dynamic>?>().firstWhere(
                        (s) => _clean(s?['id']) == sid,
                        orElse: () => null,
                      );
              setState(() {
                _borrowerType = borrowerType;
                _selectedClassId = classId;
                _selectedStudentId = sid;
                _selectedTeacherId = _clean(tx['teacher_borrower_id']);
                _rollController.text = matchedStudent != null
                    ? _clean(matchedStudent['roll_number'], fallback: _clean(tx['roll_number_snapshot']))
                    : _clean(tx['roll_number_snapshot']);
                _selectedReturnTransactionId = _clean(tx['id']);
                _returnDate = _today();
              });
              onOpenCirculation();
              _circulationController.animateTo(1);
            }, icon: const Icon(Icons.assignment_turned_in_outlined)) : null,
          ))),
      if (rows.length > 500) const Text('આ સ્ક્રીન પર પ્રથમ 500 નોંધો બતાવેલ છે. સંપૂર્ણ યાદી માટે “બધા રિપોર્ટ્સ” Excel ડાઉનલોડ કરો.'),
    ]);
  }

  Widget _reportsTab() {
    final rows = _reportTransactions;
    final issued = rows.where(_isIssued).length;
    final returned = rows.where((tx) => !_isIssued(tx)).length;
    final overdue = rows.where(_isOverdue).length;
    final fine = rows.fold<double>(0, (sum, tx) => sum + _calculatedFine(tx));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('રિપોર્ટ્સ અને હિસાબ / Reports & Calculations', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      const Text('એક જ Excel ફાઇલમાં શાળા-વાર, વર્ગ-વાર, શિક્ષક-વાર, હાલનાં પુસ્તકો, પરતનો ઇતિહાસ અને બાકી/મુદત પૂરી થયેલા પુસ્તકો મળશે.'),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('સમયગાળો / Period', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: () => _pickReportDate(from: true), icon: const Icon(Icons.calendar_month), label: Text('From: ${_reportFrom == null ? 'શરૂઆતથી' : _dateText(_iso(_reportFrom!))}')),
          OutlinedButton.icon(onPressed: () => _pickReportDate(from: false), icon: const Icon(Icons.event), label: Text('To: ${_reportTo == null ? 'આજ સુધી' : _dateText(_iso(_reportTo!))}')),
          TextButton.icon(onPressed: _clearReportDates, icon: const Icon(Icons.clear), label: const Text('બધી તારીખો')),
        ]),
      ]))),
      LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth > 760 ? 4 : constraints.maxWidth > 460 ? 2 : 1;
        return GridView.count(
          crossAxisCount: columns,
          childAspectRatio: columns == 1 ? 4 : 1.9,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _statCard('કુલ નોંધો', '${rows.length}', Icons.receipt_long, Colors.blue),
            _statCard('હાલમાં જારી', '$issued', Icons.outbox, Colors.orange),
            _statCard('પરત થયેલ', '$returned', Icons.assignment_turned_in, Colors.green),
            _statCard('મુદત પૂરી', '$overdue', Icons.warning_amber, Colors.red),
          ],
        );
      }),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('દંડની ગણતરી: ${_money(fine)}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('દરેક ઇશ્યૂ વખતે સેટ થયેલા દિવસો અને દૈનિક દંડ પ્રમાણે ગણતરી થાય છે. સેટિંગ્સ બદલવાથી જૂના લોનની મૂળ મુદત બદલાતી નથી.'),
      ]))),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: _loading || _reportBusy ? null : _exportAllReports,
        icon: const Icon(Icons.file_download_outlined),
        label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('બધા રિપોર્ટ્સ એક જ Excel ફાઇલમાં ડાઉનલોડ કરો', textAlign: TextAlign.center)),
      ),
      const SizedBox(height: 8),
      const Text('Excel sheets: School Summary, Books, Removed Books (reason and recorder), Book Number History, Transactions, Currently Issued, Returned History, Overdue, Class-wise, Teacher-wise અને Teacher Borrowers.', style: TextStyle(fontSize: 12)),
    ]);
  }

  Widget _settingsTab() => ListView(padding: const EdgeInsets.all(16), children: [
        Text('પુસ્તકાલય સેટિંગ્સ', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('આ સેટિંગ્સ નવી ઇશ્યૂ નોંધો પર લાગુ થશે. પહેલેથી જારી થયેલ પુસ્તકની due date અને દંડની દર નોંધમાં જ જળવાશે.'),
        const SizedBox(height: 14),
        TextField(controller: _dueDaysController, keyboardType: TextInputType.number, enabled: !_readOnly, decoration: const InputDecoration(labelText: 'પુસ્તક રાખવાની મુદત (દિવસ)', helperText: '1 થી 365 દિવસ', prefixIcon: Icon(Icons.calendar_month))),
        const SizedBox(height: 12),
        TextField(controller: _maxBooksController, keyboardType: TextInputType.number, enabled: !_readOnly, decoration: const InputDecoration(labelText: 'દરેક વાચકને એકસાથે મહત્તમ પુસ્તકો', helperText: '1 થી 10 પુસ્તકો', prefixIcon: Icon(Icons.menu_book))),
        const SizedBox(height: 12),
        TextField(controller: _fineController, keyboardType: const TextInputType.numberWithOptions(decimal: true), enabled: !_readOnly, decoration: const InputDecoration(labelText: 'મોડું થાય તો દૈનિક દંડ (₹)', helperText: 'દંડ ન હોય તો 0 લખો', prefixIcon: Icon(Icons.currency_rupee))),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          isExpanded: true,
          value: _studentIssuePermission,
          decoration: const InputDecoration(labelText: 'વિદ્યાર્થીને પુસ્તક આપવાની પરવાનગી', prefixIcon: Icon(Icons.admin_panel_settings_outlined), border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'class_teacher_only', child: Text('માત્ર નિયુક્ત વર્ગ શિક્ષક')),
            DropdownMenuItem(value: 'any_teacher', child: Text('શાળાના કોઈપણ શિક્ષક — કોઈપણ વર્ગ')),
            DropdownMenuItem(value: 'selected_teachers_only', child: Text('માત્ર Admin દ્વારા પસંદ કરેલા શિક્ષકો')),
          ],
          onChanged: _readOnly || _settingsBusy ? null : (value) { if (value != null) setState(() => _studentIssuePermission = value); },
        ),
        const SizedBox(height: 6),
        Text(
          _studentIssuePermission == 'any_teacher'
              ? 'આ વિકલ્પમાં શાળાના સક્રિય શિક્ષકો કોઈપણ વર્ગના નોંધાયેલા વિદ્યાર્થીને પુસ્તક આપી અને પરત લઈ શકે છે.'
              : _studentIssuePermission == 'selected_teachers_only'
                  ? 'નીચે પસંદ કરેલા શિક્ષકો જ વિદ્યાર્થીઓને પુસ્તક આપી અને પરત લઈ શકશે. અન્ય શિક્ષકો હાલમાં જારી પુસ્તકો જોઈ શકશે જેથી વિદ્યાર્થીઓને યાદ અપાવી શકે.'
                  : 'આ વિકલ્પમાં માત્ર school_classes માં નિયુક્ત Class Teacher પોતાના વર્ગના વિદ્યાર્થીને પુસ્તક આપી અને પરત લઈ શકે છે. જો Class Teacher નિયુક્ત નથી, તો Admin પુસ્તક આપી શકે છે.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_studentIssuePermission == 'selected_teachers_only') ...[
          const SizedBox(height: 8),
          Text('પુસ્તક આપ-લે કરી શકતા શિક્ષકો પસંદ કરો', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          ..._teachers.where((teacher) => _clean(teacher['id']).isNotEmpty).map((teacher) {
            final id = _clean(teacher['id']);
            final name = _clean(teacher['teacher_name'], fallback: 'શિક્ષક');
            return CheckboxListTile(
              value: _allowedStudentIssueTeacherIds.contains(id),
              title: Text(name),
              subtitle: const Text('શાળાના નોંધાયેલા શિક્ષક'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: _readOnly || _settingsBusy ? null : (checked) => setState(() {
                if (checked == true) { if (!_allowedStudentIssueTeacherIds.contains(id)) _allowedStudentIssueTeacherIds.add(id); }
                else { _allowedStudentIssueTeacherIds.remove(id); }
              }),
            );
          }),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.tertiaryContainer.withOpacity(.45), borderRadius: BorderRadius.circular(12)),
          child: const Text('બધાં પુસ્તકો એક જ વખત દૂર કરવાં હોય તો Developer નો સંપર્ક કરો. શાળા Admin અહીંથી બધા પુસ્તકો એકસાથે delete કરી શકતા નથી. એક-એક પુસ્તક દૂર કરતાં કારણ નોંધવું ફરજિયાત છે.'),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _readOnly || _settingsBusy ? null : _saveSettings, icon: _settingsBusy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined), label: const Text('સેટિંગ્સ સાચવો')),
      ]);

  Widget _emptyCard(String title, String subtitle) => Card(
        child: Padding(padding: const EdgeInsets.all(22), child: Column(children: [
          const Icon(Icons.inbox_outlined, size: 36),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle, textAlign: TextAlign.center),
        ])),
      );
}

import 'package:pmshri_attendance/services/firebase_backend_client.dart';

/// Supabase-only data layer for the school library.
///
/// Tenant boundaries, teacher class access, duplicate-book checks, immutable book
/// numbers, issue/return transitions and write blocking are enforced by SQL/RPCs.
/// This client deliberately never receives or uses a service-role key.
class SupabaseLibraryService {
  SupabaseLibraryService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const int _pageSize = 1000;

  String _text(dynamic value, [String fallback = '']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty || text.toLowerCase() == 'null' ? fallback : text;
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _rows(dynamic value) {
    dynamic current = value;
    if (current is Map) {
      for (final key in const ['data', 'result', 'payload', 'rows']) {
        if (current[key] is List) {
          current = current[key];
          break;
        }
      }
    }
    if (current is! List) return <Map<String, dynamic>>[];
    return current
        .whereType<Map>()
        .map((row) => row.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
  }

  Future<String> currentSchoolRef() async {
    if (_client.auth.currentUser == null) {
      throw StateError('કૃપા કરીને ફરીથી લૉગિન કરો. Please sign in again.');
    }
    final value = _text(await _client.rpc('current_school_ref'));
    if (value.isEmpty) {
      throw StateError('આ લૉગિન સક્રિય શાળા સાથે જોડાયેલું નથી.');
    }
    return value;
  }

  Future<String> currentTeacherId() async => _text(await _client.rpc('current_teacher_id'));

  Future<bool> isSchoolAdmin() async {
    final value = await _client.rpc('is_school_admin');
    if (value is bool) return value;
    return const <String>{'true', 't', '1'}.contains(_text(value).toLowerCase());
  }

  Future<Map<String, dynamic>> loadSchoolContext() async =>
      _map(await _client.rpc('psm_library_school_context'));

  Future<List<Map<String, dynamic>>> loadClasses() async => _rows(
        await _client.rpc('current_school_class_roster'),
      ).where((row) => row['is_active'] == true || _text(row['is_active']).toLowerCase() == 'true').toList();

  Future<List<Map<String, dynamic>>> loadStudents(String classId) async =>
      _rows(await _client.rpc('psm_library_student_roster', params: <String, dynamic>{
        'p_class_id': classId,
      }));

  Future<List<Map<String, dynamic>>> loadTeachers() async =>
      _rows(await _client.rpc('current_school_teacher_roster'));

  Future<Map<String, dynamic>> loadSettings() async {
    final schoolRef = await currentSchoolRef();
    final row = await _client
        .from('library_settings')
        .select('school_ref,due_days,max_books_per_borrower,fine_per_day,student_issue_permission,allowed_student_issue_teacher_ids,updated_at')
        .eq('school_ref', schoolRef)
        .maybeSingle();
    return row == null
        ? <String, dynamic>{
            'due_days': 14,
            'max_books_per_borrower': 1,
            'fine_per_day': 0,
            'student_issue_permission': 'class_teacher_only',
            'allowed_student_issue_teacher_ids': <String>[],
          }
        : Map<String, dynamic>.from(row);
  }

  Future<List<Map<String, dynamic>>> loadBooks({required bool includeArchived}) async {
    final schoolRef = await currentSchoolRef();
    final result = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      var query = _client
          .from('library_books')
          .select('id,school_ref,book_number,book_name,author,publication,isbn,price,is_active,retired_reason_code,retired_reason_details,retired_at,retired_by_teacher_id,retired_by_teacher_name,created_at,updated_at')
          .eq('school_ref', schoolRef);
      if (!includeArchived) query = query.eq('is_active', true);
      final page = await query
          .order('book_number')
          .range(offset, offset + _pageSize - 1);
      final rows = page.map((row) => Map<String, dynamic>.from(row)).toList();
      result.addAll(rows);
      if (rows.length < _pageSize) break;
      offset += _pageSize;
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> loadBookNumberHistory() async {
    final schoolRef = await currentSchoolRef();
    final result = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await _client
          .from('library_book_number_history')
          .select('id,school_ref,book_id,book_number,previous_book_number,change_type,changed_by_teacher_name,changed_at')
          .eq('school_ref', schoolRef)
          .order('changed_at', ascending: false)
          .range(offset, offset + _pageSize - 1);
      final rows = page.map((row) => Map<String, dynamic>.from(row)).toList();
      result.addAll(rows);
      if (rows.length < _pageSize) break;
      offset += _pageSize;
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> loadTransactions() async {
    final schoolRef = await currentSchoolRef();
    final result = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await _client
          .from('library_transactions')
          .select('id,school_ref,book_id,book_number_snapshot,book_name_snapshot,author_snapshot,borrower_type,student_id,teacher_borrower_id,class_id,class_label_snapshot,borrower_name_snapshot,roll_number_snapshot,issue_date,due_date,due_days_at_issue,fine_per_day_at_issue,return_date,status,issue_remarks,return_remarks,recorded_by_teacher_id,recorded_by_teacher_name,created_at,updated_at')
          .eq('school_ref', schoolRef)
          .order('issue_date', ascending: false)
          .order('created_at', ascending: false)
          .range(offset, offset + _pageSize - 1);
      final rows = page.map((row) => Map<String, dynamic>.from(row)).toList();
      result.addAll(rows);
      if (rows.length < _pageSize) break;
      offset += _pageSize;
    }
    return result;
  }

  Future<Map<String, dynamic>> bulkAddBooks(List<Map<String, dynamic>> rows) async {
    final result = await _client.rpc('psm_library_bulk_add_books', params: <String, dynamic>{
      'p_rows': rows,
    });
    return _map(result);
  }

  Future<Map<String, dynamic>> archiveBook({
    required String bookId,
    required String reasonCode,
    required String reasonDetails,
  }) async => _map(
        await _client.rpc('psm_library_archive_book', params: <String, dynamic>{
          'p_book_id': bookId,
          'p_reason_code': reasonCode,
          'p_reason_details': reasonDetails,
        }),
      );

  Future<Map<String, dynamic>> changeBookNumber({
    required String bookId,
    required String newBookNumber,
  }) async => _map(
        await _client.rpc('psm_library_change_book_number', params: <String, dynamic>{
          'p_book_id': bookId,
          'p_new_book_number': newBookNumber.trim(),
        }),
      );

  Future<Map<String, dynamic>> issueBook({
    required String bookId,
    required String borrowerType,
    required DateTime issueDate,
    required String remarks,
    String? classId,
    String? studentId,
    String? teacherBorrowerId,
  }) async => _map(
        await _client.rpc('psm_library_issue_book', params: <String, dynamic>{
          'p_book_id': bookId,
          'p_borrower_type': borrowerType,
          'p_class_id': classId,
          'p_student_id': studentId,
          'p_teacher_borrower_id': teacherBorrowerId,
          'p_issue_date': _isoDate(issueDate),
          'p_remarks': remarks,
        }),
      );

  Future<Map<String, dynamic>> returnBook({
    required String transactionId,
    required DateTime returnDate,
    required String remarks,
  }) async => _map(
        await _client.rpc('psm_library_return_book', params: <String, dynamic>{
          'p_transaction_id': transactionId,
          'p_return_date': _isoDate(returnDate),
          'p_return_remarks': remarks,
        }),
      );

  Future<Map<String, dynamic>> saveSettings({
    required int dueDays,
    required int maxBooksPerBorrower,
    required double finePerDay,
    required String studentIssuePermission,
    required List<String> allowedStudentIssueTeacherIds,
  }) async => _map(
        await _client.rpc('psm_library_save_settings', params: <String, dynamic>{
          'p_due_days': dueDays,
          'p_max_books_per_borrower': maxBooksPerBorrower,
          'p_fine_per_day': finePerDay,
          'p_student_issue_permission': studentIssuePermission,
          'p_allowed_teacher_ids': allowedStudentIssueTeacherIds,
        }),
      );

  String _isoDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

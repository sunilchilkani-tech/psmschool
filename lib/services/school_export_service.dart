import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';
import 'package:pmshri_attendance/services/attendance_lifecycle.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';
import 'xlsx_sanitizer.dart';

class SchoolExportBundle {
  const SchoolExportBundle({required this.bytes, required this.fileName});
  final Uint8List bytes;
  final String fileName;
}

/// Creates a clean, human-readable multi-sheet Excel workbook for Whole School Data Download.
/// - Replaces all internal IDs (`id`, `school_ref`, `class_id`, `class_teacher_id`, `teacher_id`,
///   `student_id`, `book_id`, `subject_id`) with actual School, Teacher, Class, Subject, and
///   Student/Book names and `DD/MM/YYYY` dates.
/// - Excludes internal/unneeded raw tables (`TeacherAssignments`, `LibrarySettings`, `RojmelState`,
///   `CustomHeaders`, `AdminMessages`, `Holidays`, `SubjectMarks`, `ResultProfiles`, `Subjects`,
///   `StudentAttendance`, `AttendanceDays`, etc.).
class SchoolExportService {
  SchoolExportService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  String _str(dynamic value) {
    final s = (value ?? '').toString().trim();
    return s.toLowerCase() == 'null' ? '' : s;
  }

  String _formatDate(dynamic value) {
    final raw = _str(value);
    if (raw.isEmpty) return '';
    final dt = AttendanceLifecycle.parseDate(raw) ?? DateTime.tryParse(raw);
    if (dt != null) {
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    }
    if (raw.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(raw)) {
      final parts = raw.substring(0, 10).split('-');
      if (parts.length == 3) return '${parts[2]}/${parts[1]}/${parts[0]}';
    }
    return raw;
  }

  Future<SchoolExportBundle> exportForCurrentUser({
    bool includePrivateDetails = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Please sign in again before exporting.');
    }
    final teacherRow = await _client
        .from('school_teachers')
        .select('id,school_ref,teacher_name,role,allowed_classes,is_active')
        .eq('auth_user_id', user.id)
        .maybeSingle();
    if (teacherRow == null || teacherRow['is_active'] != true) {
      throw StateError('The signed-in teacher is not active.');
    }
    final teacher = Map<String, dynamic>.from(teacherRow);
    final schoolRef = _str(teacher['school_ref']);
    final role = _str(teacher['role']).toLowerCase();
    final isAdmin = const {'admin', 'developer'}.contains(role);

    final schoolRowRaw = await _client
        .from('schools')
        .select()
        .eq('id', schoolRef)
        .maybeSingle();
    final schoolRow = schoolRowRaw == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(schoolRowRaw);
    final schoolName = _str(schoolRow['school_name_gu']).isNotEmpty
        ? _str(schoolRow['school_name_gu'])
        : (_str(schoolRow['school_name']).isNotEmpty
            ? _str(schoolRow['school_name'])
            : _str(schoolRow['school_name_en']));

    final classRows = await _client
        .from('school_classes')
        .select()
        .eq('school_ref', schoolRef)
        .order('sort_order');
    final allClasses = classRows
        .map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r))
        .toList();

    final allTeachersRaw =
        await _readSchoolTableOptional('school_teachers', schoolRef);
    final teacherNameById = <String, String>{};
    for (final t in allTeachersRaw) {
      final tid = _str(t['id']);
      final tName = _str(t['teacher_name']);
      if (tid.isNotEmpty && tName.isNotEmpty) {
        teacherNameById[tid] = tName;
      }
    }

    final classLabelById = <String, String>{};
    for (final c in allClasses) {
      final cid = _str(c['id']);
      final cLabel = _str(c['label']).isNotEmpty
          ? _str(c['label'])
          : (_str(c['class_key']).isNotEmpty
              ? _str(c['class_key'])
              : _str(c['sheet_name']));
      if (cid.isNotEmpty) {
        classLabelById[cid] = cLabel;
      }
      final ck = _str(c['class_key']);
      if (ck.isNotEmpty && !classLabelById.containsKey(ck)) {
        classLabelById[ck] = cLabel;
      }
    }

    final allowed = (teacher['allowed_classes'] as List? ?? const [])
        .map((v) => '$v')
        .toSet();
    final classes = isAdmin
        ? allClasses
        : allClasses
            .where((c) =>
                allowed.contains('${c['id']}') ||
                allowed.contains('${c['class_key']}') ||
                allowed.contains('${c['label']}') ||
                allowed.contains('${c['sheet_name']}'))
            .toList();
    if (!isAdmin && classes.isEmpty) {
      throw StateError('No assigned classes are available for export.');
    }
    final classIds = classes.map((c) => '${c['id']}').toList();

    final workbook = Excel.createExcel();
    workbook.rename('Sheet1', 'School');

    // 1. School Sheet (Clean human-readable fields, no UUIDs)
    final now = DateTime.now();
    final exportDateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    _append(workbook['School'], <Map<String, dynamic>>[
      <String, dynamic>{
        'School Code / DISE': _str(schoolRow['school_id']),
        'School Name (Gujarati) / શાળાનું નામ': _str(schoolRow['school_name_gu']),
        'School Name (English)': _str(schoolRow['school_name_en']).isNotEmpty
            ? _str(schoolRow['school_name_en'])
            : _str(schoolRow['school_name']),
        'Address (Gujarati) / સરનામું': _str(schoolRow['school_address_gu']).isNotEmpty
            ? _str(schoolRow['school_address_gu'])
            : _str(schoolRow['school_address']),
        'Address (English)': _str(schoolRow['school_address_en']),
        'School Type / શાળાનો પ્રકાર': _str(schoolRow['school_type']),
        'Academic Year / શૈક્ષણિક વર્ષ': _str(schoolRow['academic_year']),
        'Principal Name / આચાર્યનું નામ': _str(schoolRow['principal_name']),
        'Mobile / મોબાઈલ': _str(schoolRow['mobile']),
        'Email / ઈમેલ': _str(schoolRow['email']),
        'Status / સ્થિતિ': schoolRow['is_active'] == false ? 'INACTIVE' : 'ACTIVE',
        'Validity Date / માન્યતા તારીખ': _formatDate(schoolRow['validity_date']),
        'Exported By / ડાઉનલોડ કરનાર': _str(teacher['teacher_name']),
        'Role / હોદ્દો': role.toUpperCase(),
        'Export Date / તારીખ': exportDateStr,
      },
    ]);

    // 2. Classes Sheet (Teacher Name, Class Name, Standard, Section, Group, Date — no IDs!)
    final formattedClasses = <Map<String, dynamic>>[];
    for (var i = 0; i < classes.length; i++) {
      final c = classes[i];
      final ctId = _str(c['class_teacher_id']);
      final ctName = teacherNameById[ctId] ??
          (_str(c['class_teacher_name']).isNotEmpty
              ? _str(c['class_teacher_name'])
              : '');
      formattedClasses.add(<String, dynamic>{
        'Sr No / ક્રમ': '${i + 1}',
        'School Name / શાળાનું નામ': schoolName,
        'Class Name / વર્ગનું નામ': _str(c['label']).isNotEmpty
            ? _str(c['label'])
            : _str(c['class_key']),
        'Standard / ધોરણ': _str(c['standard']),
        'Section / વિભાગ': _str(c['section']),
        'Report Group / જૂથ': _str(c['report_group']),
        'Class Teacher Name / વર્ગ શિક્ષકનું નામ': ctName,
        'Status / સ્થિતિ': c['is_active'] == false ? 'INACTIVE' : 'ACTIVE',
        'Date / તારીખ': _formatDate(c['updated_at'] ?? c['created_at']),
      });
    }
    _append(workbook['Classes'], formattedClasses);

    // 3. Students Sheet (Human-readable Class Name, Roll, GR, Student Details, Bank Details, Dates & Exit Reason — no raw IDs!)
    final rawStudents = isAdmin
        ? await _readSchoolTableOptional('students', schoolRef)
        : await _readClassTable('students', schoolRef, classIds);
    final privateByStudentId = <String, Map<String, dynamic>>{};
    if (isAdmin && includePrivateDetails) {
      final privRows =
          await _readSchoolTableOptional('student_private_details', schoolRef);
      for (final p in privRows) {
        final sid = _str(p['student_id']);
        if (sid.isNotEmpty) {
          privateByStudentId[sid] = p;
        }
      }
    }

    final studentNameById = <String, String>{};
    final studentRollById = <String, String>{};
    final studentClassById = <String, String>{};
    for (final s in rawStudents) {
      final sid = _str(s['id']);
      if (sid.isNotEmpty) {
        studentNameById[sid] = _str(s['name']);
        studentRollById[sid] = _str(s['roll_number']).isNotEmpty
            ? _str(s['roll_number'])
            : _str(s['previous_roll_number']);
        final cid = _str(s['class_id']);
        studentClassById[sid] = classLabelById[cid] ?? '';
      }
    }

    final sortedStudents = List<Map<String, dynamic>>.from(rawStudents)
      ..sort((a, b) {
        final ca = (classLabelById[_str(a['class_id'])] ?? '')
            .compareTo(classLabelById[_str(b['class_id'])] ?? '');
        if (ca != 0) return ca;
        final ra = int.tryParse(_str(a['roll_number']).isNotEmpty
                ? _str(a['roll_number'])
                : _str(a['previous_roll_number'])) ??
            999999;
        final rb = int.tryParse(_str(b['roll_number']).isNotEmpty
                ? _str(b['roll_number'])
                : _str(b['previous_roll_number'])) ??
            999999;
        if (ra != rb) return ra.compareTo(rb);
        return _str(a['name']).compareTo(_str(b['name']));
      });

    final formattedStudents = <Map<String, dynamic>>[];
    for (var i = 0; i < sortedStudents.length; i++) {
      final s = sortedStudents[i];
      final sid = _str(s['id']);
      final cf = s['custom_fields'] is Map
          ? Map<String, dynamic>.from(s['custom_fields'] as Map)
          : <String, dynamic>{};
      final priv = privateByStudentId[sid] ?? const <String, dynamic>{};
      String pick(String key) {
        final top = _str(s[key]);
        if (top.isNotEmpty) return top;
        final nested = _str(cf[key]);
        if (nested.isNotEmpty) return nested;
        return _str(priv[key]);
      }

      final cid = _str(s['class_id']);
      final leavingRaw = pick('leaving_date').isNotEmpty
          ? pick('leaving_date')
          : pick('exit_date');
      final isAct = s['is_active'] == true && leavingRaw.isEmpty;
      final rawReason = AttendanceLifecycle.parseExitReason(s);
      final reasonDisplay = isAct
          ? ''
          : AttendanceLifecycle.hajariFrontPageReasonLabel(
              rawReason.isEmpty ? 'lc' : rawReason,
            );
      final dd = pick('dd').padLeft(pick('dd').isEmpty ? 0 : 2, '0');
      final mm = pick('mm').padLeft(pick('mm').isEmpty ? 0 : 2, '0');
      final yyyy = pick('yyyy');
      final dobFormatted =
          (dd.isNotEmpty && mm.isNotEmpty && yyyy.isNotEmpty)
              ? '$dd/$mm/$yyyy'
              : _formatDate(pick('dob'));

      formattedStudents.add(<String, dynamic>{
        'Sr No / ક્રમ': '${i + 1}',
        'School Name / શાળાનું નામ': schoolName,
        'Class / ધોરણ': classLabelById[cid] ?? pick('class_label'),
        'Roll No / રોલ નં.': pick('roll_number'),
        'Previous Roll / જૂનો રોલ': pick('previous_roll_number'),
        'GR No / જી.આર. નં.': pick('gr'),
        'Student Name / વિદ્યાર્થીનું નામ': pick('name'),
        'Name in English': pick('name_en'),
        'Father Name / પિતાનું નામ': pick('father_name'),
        'Mother Name / માતાનું નામ': pick('mother_name'),
        'Mother Name (English)': pick('mother_en'),
        'Birth Date / જન્મ તારીખ': dobFormatted,
        'DOB DD': pick('dd'),
        'DOB MM': pick('mm'),
        'DOB YYYY': pick('yyyy'),
        'DOB Words / જન્મ તારીખ શબ્દોમાં': pick('dob_words'),
        'Gender / જાતિ': pick('gender'),
        'Category / કેટેગરી': pick('category'),
        'Caste / પેટા જ્ઞાતિ': pick('caste'),
        'Religion / ધર્મ': pick('religion'),
        'Mobile / મોબાઈલ': pick('mobile'),
        'UID / DISE': pick('uid'),
        'PEN': pick('pen'),
        'APAAR ID': pick('apaar_id'),
        'Aadhaar / આધાર કાર્ડ': pick('has_aadhaar'),
        'Ration Card KYC': pick('ration_card_kyc'),
        'Divyang / દિવ્યાંગ': (s['is_divyang'] == true ||
                pick('is_divyang').toUpperCase() == 'YES')
            ? 'YES'
            : 'NO',
        'Scholarship Done / શિષ્યવૃત્તિ': pick('scholarship_done'),
        'Scholarship Reason / શિષ્યવૃત્તિ કારણ': pick('scholarship_reason'),
        'School Admission Date / શાળા પ્રવેશ તારીખ':
            _formatDate(pick('enroll_school')),
        'Class Admission Date / વર્ગ પ્રવેશ તારીખ':
            _formatDate(pick('enroll_class')),
        'Enrolled Standard / દાખલ ધોરણ': pick('enroll_sch_class'),
        'Last School / પૂર્વ શાળા': pick('last_school'),
        'Address / સરનામું': pick('address'),
        'Birth Place / જન્મ સ્થળ': pick('birth_place'),
        'Native Place / વતન': pick('native_place'),
        'Present Days / હાજર દિવસો': pick('present_days'),
        if (isAdmin && includePrivateDetails) ...<String, dynamic>{
          'Bank Name / બેંકનું નામ': pick('bank_name'),
          'Bank Branch / બ્રાન્ચ': pick('bank_branch'),
          'Name as per Passbook / પાસબુક મુજબ નામ': pick('name_as_passbook'),
          'Account Number / એકાઉન્ટ નંબર': pick('account_number'),
          'IFSC Code': pick('ifsc_code'),
        },
        'Status / સ્થિતિ': isAct ? 'ACTIVE (સક્રિય)' : 'DEACTIVE (નિષ્ક્રિય)',
        'Leaving Date / કમી તારીખ': _formatDate(leavingRaw),
        'Exit Reason / કમી કારણ (હાજરીપત્રક મુજબ)': reasonDisplay,
        'Promotion Status / બઢતી સ્થિતિ': pick('last_promotion_status'),
      });
    }
    _append(workbook['Students'], formattedStudents);

    if (isAdmin) {
      // 4. Teachers Sheet (with Class Names & Assigned Subject Names instead of IDs)
      final rawAssignments = await _readSchoolTableOptional(
        'teacher_subject_assignments',
        schoolRef,
      );
      final subjectsByTeacher = <String, List<String>>{};
      for (final a in rawAssignments) {
        final tid = _str(a['teacher_id']);
        final cid = _str(a['class_id']);
        final cName = classLabelById[cid] ?? cid;
        final subj = _str(a['subject_name']);
        if (tid.isEmpty || subj.isEmpty) continue;
        final entry = cName.isNotEmpty ? '$cName: $subj' : subj;
        final list = subjectsByTeacher.putIfAbsent(tid, () => <String>[]);
        if (!list.contains(entry)) list.add(entry);
      }

      final classTeacherClassesByTid = <String, List<String>>{};
      for (final c in allClasses) {
        final ctId = _str(c['class_teacher_id']);
        final cName = classLabelById[_str(c['id'])] ?? _str(c['label']);
        if (ctId.isNotEmpty && cName.isNotEmpty) {
          classTeacherClassesByTid
              .putIfAbsent(ctId, () => <String>[])
              .add(cName);
        }
      }

      final formattedTeachers = <Map<String, dynamic>>[];
      for (var i = 0; i < allTeachersRaw.length; i++) {
        final t = allTeachersRaw[i];
        final tid = _str(t['id']);
        final rawAllowed = t['allowed_classes'] is List
            ? (t['allowed_classes'] as List).map((e) => _str(e)).toList()
            : <String>[];
        final resolvedAllowed = <String>[];
        for (final token in rawAllowed) {
          if (token.isEmpty) continue;
          final resolved = classLabelById[token] ?? token;
          if (!resolvedAllowed.contains(resolved)) {
            resolvedAllowed.add(resolved);
          }
        }
        formattedTeachers.add(<String, dynamic>{
          'Sr No / ક્રમ': '${i + 1}',
          'School Name / શાળાનું નામ': schoolName,
          'Teacher Name / શિક્ષકનું નામ': _str(t['teacher_name']),
          'Role / હોદ્દો': _str(t['role']).toUpperCase(),
          'Mobile / મોબાઈલ': _str(t['mobile']),
          'Email / ઈમેલ': _str(t['email']),
          'Class Teacher Of / વર્ગ શિક્ષક':
              (classTeacherClassesByTid[tid] ?? const <String>[]).join(', '),
          'Allowed Classes / ફાળવેલ વર્ગો': resolvedAllowed.join(', '),
          'Assigned Subjects / વિષયો':
              (subjectsByTeacher[tid] ?? const <String>[]).join(' | '),
          'Status / સ્થિતિ': t['is_active'] == false ? 'INACTIVE' : 'ACTIVE',
          'Date / તારીખ': _formatDate(t['updated_at'] ?? t['created_at']),
        });
      }
      _append(workbook['Teachers'], formattedTeachers);

      // 5. TeacherLeaves Sheet (Teacher Name, Leave Type, Dates, Days, Reason — no IDs)
      final rawLeaves =
          await _readSchoolTableOptional('teacher_leaves', schoolRef);
      final formattedLeaves = <Map<String, dynamic>>[];
      for (var i = 0; i < rawLeaves.length; i++) {
        final l = rawLeaves[i];
        final tid = _str(l['teacher_id']);
        final ld = l['leave_data'] is Map
            ? Map<String, dynamic>.from(l['leave_data'] as Map)
            : <String, dynamic>{};
        final tName = teacherNameById[tid] ??
            (_str(l['teacher_name']).isNotEmpty
                ? _str(l['teacher_name'])
                : _str(ld['teacher_name']));
        formattedLeaves.add(<String, dynamic>{
          'Sr No / ક્રમ': '${i + 1}',
          'School Name / શાળાનું નામ': schoolName,
          'Teacher Name / શિક્ષકનું નામ': tName,
          'Leave Type / રજાનો પ્રકાર': _str(l['leave_type']),
          'From Date / શરૂ તારીખ': _formatDate(l['start_date']),
          'To Date / અંત તારીખ': _formatDate(l['end_date']),
          'Total Days / કુલ દિવસો':
              _str(ld['total_days']).isNotEmpty ? _str(ld['total_days']) : _str(l['total_days']),
          'Reason / રજાનું કારણ': _str(l['reason']).isNotEmpty
              ? _str(l['reason'])
              : _str(ld['reason']),
          'Status / સ્થિતિ': _str(l['status']).toUpperCase(),
          'Application Date / અરજી તારીખ':
              _formatDate(l['created_at'] ?? l['updated_at']),
        });
      }
      _append(workbook['TeacherLeaves'], formattedLeaves);

      // 6. LibraryBooks Sheet (Book No, Title, Author, Subject, Date — no IDs)
      final rawBooks =
          await _readSchoolTableOptional('library_books', schoolRef);
      final bookTitleById = <String, String>{};
      final bookNumberById = <String, String>{};
      final formattedBooks = <Map<String, dynamic>>[];
      for (var i = 0; i < rawBooks.length; i++) {
        final b = rawBooks[i];
        final bid = _str(b['id']);
        final bNum = _str(b['book_number']);
        final bTitle = _str(b['title']).isNotEmpty
            ? _str(b['title'])
            : _str(b['book_name']);
        if (bid.isNotEmpty) {
          bookTitleById[bid] = bTitle;
          bookNumberById[bid] = bNum;
        }
        formattedBooks.add(<String, dynamic>{
          'Sr No / ક્રમ': '${i + 1}',
          'Book Number / પુસ્તક ક્રમાંક': bNum,
          'Book Title / પુસ્તકનું નામ': bTitle,
          'Author / લેખક': _str(b['author']),
          'Subject / વિષય': _str(b['category']).isNotEmpty
              ? _str(b['category'])
              : _str(b['subject']),
          'Language / ભાષા': _str(b['language']),
          'Publisher / પ્રકાશક': _str(b['publisher']),
          'Price / કિંમત': _str(b['price']),
          'Status / સ્થિતિ': b['is_active'] == false
              ? 'REMOVED'
              : (_str(b['status']).isEmpty
                  ? 'AVAILABLE'
                  : _str(b['status']).toUpperCase()),
          'Date / તારીખ': _formatDate(b['updated_at'] ?? b['created_at']),
        });
      }
      _append(workbook['LibraryBooks'], formattedBooks);

      // 7. LibraryTransactions Sheet (Book Name, Class Name, Student/Teacher Name, Dates — no IDs)
      final rawTx =
          await _readSchoolTableOptional('library_transactions', schoolRef);
      final formattedTx = <Map<String, dynamic>>[];
      for (var i = 0; i < rawTx.length; i++) {
        final tx = rawTx[i];
        final bid = _str(tx['book_id']);
        final sid = _str(tx['student_id']);
        final tid = _str(tx['teacher_id']);
        final cid = _str(tx['class_id']);
        final cName = classLabelById[cid] ??
            (_str(tx['class_label']).isNotEmpty
                ? _str(tx['class_label'])
                : (studentClassById[sid] ?? ''));
        final borrowerName = _str(tx['borrower_name']).isNotEmpty
            ? _str(tx['borrower_name'])
            : (_str(tx['student_name']).isNotEmpty
                ? _str(tx['student_name'])
                : (studentNameById[sid] ?? teacherNameById[tid] ?? ''));
        final rollNo = _str(tx['roll_number_snapshot']).isNotEmpty
            ? _str(tx['roll_number_snapshot'])
            : (studentRollById[sid] ?? '');
        formattedTx.add(<String, dynamic>{
          'Sr No / ક્રમ': '${i + 1}',
          'Book Number / પુસ્તક ક્રમાંક': _str(tx['book_number']).isNotEmpty
              ? _str(tx['book_number'])
              : (bookNumberById[bid] ?? ''),
          'Book Title / પુસ્તકનું નામ': _str(tx['book_title']).isNotEmpty
              ? _str(tx['book_title'])
              : (bookTitleById[bid] ?? ''),
          'Borrower Type / પ્રકાર': _str(tx['borrower_type']).isEmpty
              ? (sid.isNotEmpty ? 'STUDENT' : 'TEACHER')
              : _str(tx['borrower_type']).toUpperCase(),
          'Class / ધોરણ': cName,
          'Roll No / રોલ નં.': rollNo,
          'Student or Teacher Name / નામ': borrowerName,
          'Issue Date / આપ્યા તારીખ': _formatDate(tx['issue_date']),
          'Due Date / મુદત તારીખ': _formatDate(tx['due_date']),
          'Return Date / પરત તારીખ': _formatDate(tx['return_date']),
          'Status / સ્થિતિ': _str(tx['status']).toUpperCase(),
        });
      }
      _append(workbook['LibraryTransactions'], formattedTx);
    }

    final bytes = workbook.encode();
    if (bytes == null) throw StateError('Excel workbook encoding failed.');
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    return SchoolExportBundle(
      bytes: XlsxSanitizer.clean(Uint8List.fromList(bytes)),
      fileName: 'PSM_${isAdmin ? 'School' : 'AssignedClasses'}_$stamp.xlsx',
    );
  }

  Future<List<Map<String, dynamic>>> _readClassTable(
    String table,
    String schoolRef,
    List<String> classIds,
  ) async {
    if (classIds.isEmpty) return [];
    try {
      final rows = await _client
          .from(table)
          .select()
          .eq('school_ref', schoolRef)
          .inFilter('class_id', classIds);
      return rows
          .map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r))
          .toList();
    } catch (error) {
      throw StateError(
        'Could not export $table. Check this teacher\'s class permissions. $error',
      );
    }
  }

  Future<List<Map<String, dynamic>>> _readSchoolTableOptional(
    String table,
    String schoolRef,
  ) async {
    try {
      final rows =
          await _client.from(table).select().eq('school_ref', schoolRef);
      return rows
          .map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  void _append(Sheet sheet, List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      sheet.appendRow([TextCellValue('No rows available')]);
      return;
    }
    final columns = <String>[];
    for (final row in rows) {
      for (final key in row.keys) {
        if (!columns.contains(key)) columns.add(key);
      }
    }
    sheet.appendRow(columns.map((k) => TextCellValue(k)).toList());
    for (final row in rows) {
      sheet.appendRow(
        columns.map((key) {
          final value = row[key];
          if (value == null) return TextCellValue('');
          return TextCellValue('$value');
        }).toList(),
      );
    }
  }
}

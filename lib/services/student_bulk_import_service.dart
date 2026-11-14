import 'student_management_service.dart';
import 'school_type.dart';

class StudentBulkImportService {
  StudentBulkImportService({StudentManagementService? students})
      : _students = students ?? StudentManagementService();

  final StudentManagementService _students;

  static const _commonHeaders = <String>[
    'Roll Number', 'Student Name', 'GR', 'Category', 'Father Name',
    'Mother Name', 'Mobile', 'Address',
  ];

  /// Single-gender templates omit Gender. Co-ed templates require it.
  List<String> templateHeaders(String schoolType) =>
      SchoolType.isMixed(schoolType)
          ? [..._commonHeaders, 'Gender']
          : List<String>.from(_commonHeaders);

  String normalizeCategory(Object? input) {
    final value = (input ?? 'OTHER').toString().trim().toUpperCase();
    return const {'SC', 'ST', 'OBC', 'OTHER'}.contains(value) ? value : 'OTHER';
  }

  String? normalizeGender(Object? input, String schoolType) {
    switch (SchoolType.canonical(schoolType)) {
      case 'boys': return 'BOYS';
      case 'girls': return 'GIRLS';
      default:
        final value = (input ?? '').toString().trim().toUpperCase();
        if (const {'BOY', 'MALE', 'M', 'BOYS'}.contains(value)) return 'BOYS';
        if (const {'GIRL', 'FEMALE', 'F', 'GIRLS'}.contains(value)) return 'GIRLS';
        return null;
    }
  }

  /// Insert rows without clearing existing records. Numeric roll rows are imported ascending,
  /// so requested positions remain stable while the DB's atomic insert shifts existing rolls.
  Future<BulkImportResult> importRows({
    required String classId,
    required String schoolType,
    required List<Map<String, dynamic>> rows,
  }) async {
    final errors = <String>[];
    var imported = 0;
    final sorted = List<Map<String, dynamic>>.from(rows);
    String value(Map<String, dynamic> row, String key, [String? alias]) =>
        (row[key] ?? (alias == null ? null : row[alias]) ?? '').toString().trim();
    sorted.sort((a, b) {
      final ar = int.tryParse(value(a, 'roll_number', 'Roll Number')) ?? 2147483647;
      final br = int.tryParse(value(b, 'roll_number', 'Roll Number')) ?? 2147483647;
      return ar.compareTo(br);
    });

    for (var index = 0; index < sorted.length; index++) {
      final row = sorted[index];
      final rowLabel = 'Row ${index + 2}';
      final name = value(row, 'name', 'Student Name');
      if (name.isEmpty) {
        errors.add('$rowLabel: Student Name is required.');
        continue;
      }
      final gender = normalizeGender(row['gender'] ?? row['Gender'], schoolType);
      if (SchoolType.isMixed(schoolType) && gender == null) {
        errors.add('$rowLabel ($name): Gender must be BOYS or GIRLS for a co-ed school.');
        continue;
      }
      final rawRoll = value(row, 'roll_number', 'Roll Number');
      final roll = rawRoll.isEmpty ? null : int.tryParse(rawRoll);
      if (rawRoll.isNotEmpty && (roll == null || roll < 1)) {
        errors.add('$rowLabel ($name): Roll Number must be a positive integer.');
        continue;
      }
      try {
        await _students.addStudent(
          classId: classId,
          rollNumber: roll,
          student: {
            'name': name,
            'gr': value(row, 'gr', 'GR'),
            'category': normalizeCategory(row['category'] ?? row['Category']),
            'gender': gender,
            'father_name': value(row, 'father_name', 'Father Name'),
            'mother_name': value(row, 'mother_name', 'Mother Name'),
            'mobile': value(row, 'mobile', 'Mobile'),
            'address': value(row, 'address', 'Address'),
          },
        );
        imported++;
      } catch (error) {
        errors.add('$rowLabel ($name): $error');
      }
    }
    return BulkImportResult(imported: imported, failed: errors.length, errors: errors);
  }
}

class BulkImportResult {
  const BulkImportResult({required this.imported, required this.failed, required this.errors});
  final int imported;
  final int failed;
  final List<String> errors;
}

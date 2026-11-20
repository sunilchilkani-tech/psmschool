import 'attendance_lifecycle.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'school_type.dart';
import 'xlsx_row_colors.dart';
import 'xlsx_sanitizer.dart';
import 'package:pmshri_attendance/services/class_label.dart';

/// Day-wise attendance already recorded in the app. When passed to
/// [HajariPatrakXlsxTemplateExporter.build] the register is filled (P / A per
/// student per day) and the template's bottom rows 2001–2008 receive the daily
/// totals: category-wise present, total present, absent, PM POSHAN and
/// breakfast. The same Excel template (and therefore the same Gujarati font
/// rendering via the cloud LibreOffice converter) is used for both modes.
class HajariRecordedData {
  const HajariRecordedData({
    required this.studentDailyMarks,
    required this.recordedDays,
    this.holidayIsoDates = const <String>{},
    this.attendanceDays = const <Map<String, dynamic>>[],
  });

  /// studentId -> day -> {present, mdm, breakfast}
  final Map<String, Map<int, Map<String, bool>>> studentDailyMarks;

  /// Days for which student-wise attendance was saved.
  final Set<int> recordedDays;

  /// yyyy-mm-dd holiday dates (Sundays are handled automatically).
  final Set<String> holidayIsoDates;

  /// Class-level attendance_days rows (used for direct count entry days).
  final List<Map<String, dynamic>> attendanceDays;
}

/// Writes the supplied Excel workbook as the month-end handwriting sheet.
/// Cell values and print metadata are updated while preserving page geometry,
/// merged cells, row heights and margins. Student row styles are data-driven:
/// category controls font color, co-ed gender controls a subtle row fill, and
/// category transitions receive a double bottom rule.
class HajariPatrakXlsxTemplateExporter {
  static const String _assetPath =
      'assets/hajari_patrak/hajari_patrak_template.xlsx';
  static const List<String> _months = <String>[
    'જાન્યુઆરી',
    'ફેબ્રુઆરી',
    'માર્ચ',
    'એપ્રિલ',
    'મે',
    'જૂન',
    'જુલાઈ',
    'ઓગસ્ટ',
    'સપ્ટેમ્બર',
    'ઓક્ટોબર',
    'નવેમ્બર',
    'ડિસેમ્બર',
  ];
  static const List<String> _weekdays = <String>[
    'સોમવાર',
    'મંગળવાર',
    'બુધવાર',
    'ગુરુવાર',
    'શુક્રવાર',
    'શનિવાર',
    'રવિવાર',
  ];
  static const List<String> _categories = <String>['SC', 'ST', 'OBC', 'OTHER'];

  // Recorded register: meal colour code of each P / A mark.
  static const String _markBoth = 'FFDC2626';
  static const String _markMdm = 'FF1D4ED8';
  static const String _markBreakfast = 'FFDB2777';
  static const String _markPresent = 'FF000000';
  static const String _markAbsent = 'FF4B5563';
  static const String _recordedLegend =
      'રંગ કોડ: P(કાળો)=હાજર | P(વાદળી)=મ.ભો. | P(ગુલાબી)=નાસ્તો | P(લાલ)=બંને | A=ગેરહાજર';

  Future<Uint8List> build({
    required String schoolName,
    required String schoolAddress,
    required String schoolType,
    required String academicYear,
    required String classLabel,
    required String teacherName,
    required int year,
    required int month,
    required List<Map<String, dynamic>> students,
    int blankRows = 4,
    Map<String, int?> presentDaysByStudentId = const <String, int?>{},
    HajariRecordedData? recorded,
    Set<String> holidayIsoDates = const <String>{},
  }) async {
    if (month < 1 || month > 12) throw ArgumentError.value(month, 'month');
    if (students.isEmpty)
      throw StateError('આ મહિના માટે કોઈ વિદ્યાર્થી મળ્યો નથી.');
    if (blankRows < 0) throw ArgumentError.value(blankRows, 'blankRows');
    // Student rows start at 4 and the master template's month-end summary is
    // fixed at rows 2001-2008. Rows 4-2000 are the only usable roster/blank area.
    if (students.length + blankRows > 1997) {
      final maximum = (1997 - students.length).clamp(0, 1997);
      throw StateError(
        'આ વર્ગમાં ${students.length} વિદ્યાર્થી છે. Summary rows 2001–2008 સ્થિર હોવાથી વધુમાં વધુ $maximum ખાલી લાઇન પસંદ કરી શકાય.',
      );
    }

    final data = await rootBundle.load(_assetPath);
    final templateBytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final archive = ZipDecoder().decodeBytes(templateBytes, verify: true);
    String readText(String name) {
      ArchiveFile? file;
      for (final item in archive.files) {
        if (item.name == name) {
          file = item;
          break;
        }
      }
      if (file == null) throw StateError('Excel template is missing $name.');
      final content = file.readBytes();
      if (content == null)
        throw StateError('Excel template file $name is not readable.');
      return utf8.decode(content, allowMalformed: false);
    }

    void writeText(String name, String text) {
      var index = -1;
      ArchiveFile? original;
      for (var i = 0; i < archive.files.length; i++) {
        final item = archive.files[i];
        if (item.name == name) {
          index = i;
          original = item;
          break;
        }
      }
      if (index < 0 || original == null) {
        throw StateError('Excel template is missing $name.');
      }

      // archive 4.x exposes file contents as read-only. Replace the ZIP entry
      // at the same index instead of trying to assign ArchiveFile.content.
      final replacement = ArchiveFile.bytes(name, utf8.encode(text));
      replacement.compression = original.compression;
      replacement.comment = original.comment;
      archive.modifyAtIndex(index, replacement);
    }

    final type = _canonicalType(schoolType);
    final coed = type == 'coed';
    final first = DateTime(year, month, 1);
    final last = DateTime(year, month + 1, 0);
    final filteredStudents = students.where((student) {
      final entry = AttendanceLifecycle.parseEnrollmentDate(student);
      final left = AttendanceLifecycle.parseLeavingDate(student);
      if (entry != null) {
        // Recorded register: include students who joined during this month so
        // both the front-page admissions row and daily marks are complete.
        if (recorded != null &&
            entry.year == year &&
            entry.month == month &&
            (left == null || !left.isBefore(first))) {
          return true;
        }
        return AttendanceLifecycle.includeInMonthlyRegister(
          registerMonth: first,
          enrolledOn: entry,
          leftOn: left,
        );
      }
      if (left != null && first.isAfter(DateTime(left.year, left.month, 1))) {
        return false;
      }
      return true;
    }).map((s) => Map<String, dynamic>.from(s)).toList();
    final sortedStudents = filteredStudents
      ..sort((a, b) {
        final left = int.tryParse(_roll(a));
        final right = int.tryParse(_roll(b));
        if (left != null && right != null) return left.compareTo(right);
        if (left != null) return -1;
        if (right != null) return 1;
        return _roll(a).compareTo(_roll(b));
      });
    final movements = _movements(sortedStudents, first, last, type);
    final regCounts = movements['opening']!;

    // Covers: the opening registered-strength row is populated; remaining census rows stay blank for month-end handwriting.
    final coverSheet = type == 'boys'
        ? 'xl/worksheets/sheet1.xml'
        : type == 'girls'
            ? 'xl/worksheets/sheet2.xml'
            : 'xl/worksheets/sheet3.xml';
    var coverXml = readText(coverSheet);
    final coverValues = <String, dynamic>{
      'A1': 'શૈક્ષણિક વર્ષ ${_gujaratiDigits(academicYear)}',
      'A2': 'વિદ્યાર્થીઓનું હાજરીપત્રક',
      // The single-gender template merges A5:C5 for the fixed 'માસ' label,
      // D5:G5 for the month, and H5:J5 for the year. Write only to merge anchors.
      'D5': _months[month - 1],
      'H5': '-${_gujaratiDigits('$year')}',
      'A8': schoolName,
      'A9': schoolAddress,
      'A10': 'ધોરણ - ${_classValue(classLabel)}',
      'E10': 'વર્ગ શિક્ષક :- $teacherName',
    };
    if (coed) {
      // The mixed-gender template merges A5:D5 for 'માસ', E5:K5 for
      // the month, and L5:P5 for the year. Write only to those merge anchors.
      coverValues.remove('D5');
      coverValues.remove('H5');
      coverValues['E5'] = _months[month - 1];
      coverValues['L5'] = '-${_gujaratiDigits('$year')}';
      coverValues['B25'] = 'વર્ગ શિક્ષક';
      coverValues['I25'] = 'મુખ્ય શિક્ષક';
      coverValues['B26'] = schoolName;
      coverValues['I26'] = schoolName;
      coverValues['A15'] = 'ગયા માસને આખરે બાકી';
      coverValues['A16'] = 'ચાલુ માસમાં નવા આવેલ';
      coverValues['A17'] = 'ચાલુ માસમાં લિ. સર્ટી. લઈ ગયેલ';
      coverValues['A18'] = 'સતત ગેરહાજરીથી નામ કમી કરેલ';
      coverValues['A19'] = 'ચાલુ માસને આખરે બાકી';
      for (var i = 0; i < 5; i++) {
        final row = 15 + i;
        // Blank register: only the opening row is printed (the rest are
        // handwritten at month end). Recorded register: all five rows.
        if (i > 0 && recorded == null) {
          // Handwritten month-end fields: clear every numeric cell, including
          // template dashes/zeros, but preserve the existing row labels/styles.
          final blankValues = <String, dynamic>{
            for (final col in const <String>[
              'C',
              'D',
              'E',
              'F',
              'G',
              'H',
              'I',
              'J',
              'K',
              'L',
              'M',
              'N',
              'O',
              'P',
            ])
              '$col$row': '',
          };
          _setMany(
            (v) => coverXml = v,
            coverXml,
            blankValues,
            styleFallbackRow: 15,
          );
          continue;
        }
        final stats = movements[_movementKey(i)]!;
        final gender = _asMap(stats['gender']);
        final byCategory = _asMap(stats['genderCategory']);
        final boys = _n(gender, 'BOYS');
        final girls = _n(gender, 'GIRLS');
        final total = _n(stats, 'total');
        final values = <String, dynamic>{
          'C$row': boys,
          'D$row': girls,
          'E$row': total,
          'F$row': _n(byCategory, 'BOYS_SC'),
          'G$row': _n(byCategory, 'GIRLS_SC'),
          'H$row': _n(byCategory, 'BOYS_ST'),
          'I$row': _n(byCategory, 'GIRLS_ST'),
          'J$row': _n(byCategory, 'BOYS_OBC'),
          'K$row': _n(byCategory, 'GIRLS_OBC'),
          'L$row': _n(byCategory, 'BOYS_OTHER'),
          'M$row': _n(byCategory, 'GIRLS_OTHER'),
          'N$row': boys,
          'O$row': girls,
          'P$row': total,
        };
        _setMany((v) => coverXml = v, coverXml, values, styleFallbackRow: 15);
      }
    } else {
      coverValues['B24'] = 'વર્ગ શિક્ષક';
      coverValues['G24'] = 'મુખ્ય શિક્ષક';
      coverValues['B25'] = schoolName;
      coverValues['G25'] = schoolName;
      for (var i = 0; i < 5; i++) {
        final row = 14 + i;
        if (i > 0 && recorded == null) {
          // Admissions, exits and closing strength are teacher-entered at month-end.
          final blankValues = <String, dynamic>{
            for (final col in const <String>[
              'C',
              'D',
              'E',
              'F',
              'G',
              'H',
              'I',
              'J',
            ])
              '$col$row': '',
          };
          _setMany(
            (v) => coverXml = v,
            coverXml,
            blankValues,
            styleFallbackRow: 14,
          );
          continue;
        }
        final stats = movements[_movementKey(i)]!;
        final gender = _asMap(stats['gender']);
        final counts = _asMap(stats['category']);
        final total = _n(stats, 'total');
        final boysSchool = type == 'boys';
        final values = <String, dynamic>{
          'C$row': boysSchool ? _n(gender, 'BOYS') : '---',
          'D$row': boysSchool ? '---' : _n(gender, 'GIRLS'),
          'E$row': total,
          'F$row': _n(counts, 'SC'),
          'G$row': _n(counts, 'ST'),
          'H$row': _n(counts, 'OBC'),
          'I$row': _n(counts, 'OTHER'),
          'J$row': total,
        };
        _setMany((v) => coverXml = v, coverXml, values, styleFallbackRow: 14);
      }
    }
    _setMany(
      (v) => coverXml = v,
      coverXml,
      coverValues,
      styleFallbackRow: coed ? 15 : 14,
    );
    writeText(coverSheet, coverXml);

    // Register sheet: preserve the actual Excel page geometry and use the 40 designed writing rows.
    final registerName =
        coed ? 'xl/worksheets/sheet5.xml' : 'xl/worksheets/sheet4.xml';
    var registerXml = readText(registerName);
    final classText = 'ધોરણ - ${_classValue(classLabel)}';
    final registerHeader = coed
        ? <String, dynamic>{
            'B1': classText,
            'J1': _months[month - 1],
            'L1': '- $year માસનું',
          }
        : <String, dynamic>{
            'B1': classText,
            'I1': _months[month - 1],
            'K1': '- $year માસનું',
          };
    _setMany(
      (v) => registerXml = v,
      registerXml,
      registerHeader,
      styleFallbackRow: 1,
    );

    final firstDayCol = coed ? 12 : 11; // L for co-ed, K for single gender.
    final firstDayCount = coed ? 7 : 8;
    final laterDayCol = 22; // V in both template sheets.
    final laterFirstDay = firstDayCount + 1;
    for (var i = 0; i < firstDayCount; i++) {
      final day = i + 1;
      final col = firstDayCol + i;
      final refLetter = _columnLetters(col);
      final valid = day <= last.day;
      final date = DateTime(year, month, day);
      registerXml = _setCell(
        registerXml,
        '${refLetter}2',
        valid ? _weekdays[date.weekday - 1] : null,
        styleFallbackRef: '${refLetter}2',
      );
      registerXml = _setCell(
        registerXml,
        '${refLetter}3',
        valid ? day : null,
        styleFallbackRef: '${refLetter}3',
      );
    }
    final laterCount = 31 - firstDayCount;
    for (var i = 0; i < laterCount; i++) {
      final day = laterFirstDay + i;
      final col = laterDayCol + i;
      final refLetter = _columnLetters(col);
      final valid = day <= last.day;
      final date = valid ? DateTime(year, month, day) : null;
      registerXml = _setCell(
        registerXml,
        '${refLetter}2',
        date == null ? null : _weekdays[date.weekday - 1],
        styleFallbackRef: '${refLetter}2',
      );
      registerXml = _setCell(
        registerXml,
        '${refLetter}3',
        valid ? day : null,
        styleFallbackRef: '${refLetter}3',
      );
    }

    // Clear sample values in the body, preserve every cell style/row height,
    // and reveal exactly student-count + selected blank rows. The fixed summary
    // stays at rows 2001-2008. Bulk row rewriting avoids thousands of ZIP/XML edits.
    String dayRef(int day) => _columnLetters(
          day <= firstDayCount
              ? firstDayCol + day - 1
              : laterDayCol + (day - firstDayCount - 1),
        );
    final recordedFill = recorded == null
        ? null
        : _buildRecordedFill(
            recorded: recorded,
            students: sortedStudents,
            year: year,
            month: month,
            daysInMonth: last.day,
            coed: coed,
            dayRef: dayRef,
            presentDaysByStudentId: presentDaysByStudentId,
          );
    // Recorded register keeps at least one blank row for the colour legend.
    final effectiveBlankRows =
        recordedFill != null && blankRows < 1 ? 1 : blankRows;
    registerXml = _rewriteRegisterBodyRows(
      registerXml,
      coed: coed,
      schoolType: type,
      students: sortedStudents,
      blankRows: effectiveBlankRows,
      presentDaysByStudentId: presentDaysByStudentId,
      extraStudentValues: recordedFill?.studentValues,
    );
    // Grey only the real Sundays and the admin's holidays of this month (the
    // template's sample shading belonged to another month's weekday).
    {
      String iso(int d) =>
          '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      final holidays = <String>{...holidayIsoDates, ...?recorded?.holidayIsoDates};
      final closed = <String>{};
      final open = <String>{};
      for (var d = 1; d <= 31; d++) {
        final letter = dayRef(d);
        if (d > last.day) {
          open.add(letter);
          continue;
        }
        final date = DateTime(year, month, d);
        if (date.weekday == DateTime.sunday || holidays.contains(iso(d))) {
          closed.add(letter);
        } else {
          open.add(letter);
        }
      }
      final shaded = _shadeDayColumns(readText('xl/styles.xml'), registerXml,
          closed: closed, open: open, firstRow: 2, lastRow: 2008);
      registerXml = shaded.$1;
      writeText('xl/styles.xml', shaded.$2);
    }
    final rowStyling = _applyRegisterRowStyles(
      readText('xl/styles.xml'),
      registerXml,
      coed: coed,
      schoolType: type,
      students: sortedStudents,
    );
    registerXml = rowStyling.$1;
    var stylesXml = rowStyling.$2;
    if (recordedFill != null) {
      // The template rotates the body cells of the day and month-end columns
      // by 90° (meant for handwriting). Filled values must read normally, so
      // the data cells get 0° rotation; the header rows keep their style.
      final upright = <String>{
        for (var d = 1; d <= last.day; d++) dayRef(d),
        ...(coed
            ? const <String>['AT', 'AU', 'AV', 'AW']
            : const <String>['AS', 'AT', 'AU', 'AV']),
      };
      final unrotated = _uprightCells(
        stylesXml,
        registerXml,
        columns: upright,
        firstRow: 4,
        lastRow: 3 + sortedStudents.length + effectiveBlankRows,
        wrapColumns: <String>{coed ? 'AW' : 'AV'},
      );
      registerXml = unrotated.$1;
      stylesXml = unrotated.$2;

      // Bold, colour-coded P / A in the day cells (Arial so the Latin
      // letters never show as missing glyphs). Identity and summary columns
      // keep the student's category colour.
      final cellColors = <String, String>{};
      for (var i = 0; i < recordedFill.studentDayColors.length; i++) {
        final rowNumber = 4 + i;
        recordedFill.studentDayColors[i].forEach((col, color) {
          cellColors['$col$rowNumber'] = color;
        });
      }
      final colored = _colorMarkCells(stylesXml, registerXml, cellColors);
      registerXml = colored.$1;
      stylesXml = colored.$2;

      // Colour legend in the last blank row (merged across the identity
      // columns, shrunk to fit).
      final legendRow = 3 + sortedStudents.length + effectiveBlankRows;
      final legendEnd = coed ? 'K' : 'J';
      registerXml = _rewriteSpecificRows(registerXml, <int, Map<String, dynamic>>{
        legendRow: <String, dynamic>{'F$legendRow': _recordedLegend},
      });
      registerXml = _addMergeIfFree(registerXml, 'F$legendRow:$legendEnd$legendRow');
      final legendStyled = _shrinkToFitCells(stylesXml, registerXml, <String>{'F$legendRow'});
      registerXml = legendStyled.$1;
      stylesXml = legendStyled.$2;
    }
    // The right-page title (U1, merged to the last day column) has only top
    // and bottom lines in the template; its left edge came from column T,
    // which is blank binding space and is cleared for the PDF. Give the
    // title cell its own border on all four sides (blank and recorded
    // registers, single-gender and mixed sheets).
    {
      final boxed = _boxCellBorders(stylesXml, registerXml, 'U1');
      registerXml = boxed.$1;
      stylesXml = boxed.$2;
    }
    writeText('xl/styles.xml', stylesXml);

    // Start-of-month registered category counts are the only numeric register-footer summary values.
    final categoryCounts = _asMap(regCounts['category']);
    final countRows = <String, String>{
      'SC': '2001',
      'ST': '2002',
      'OBC': '2003',
      'OTHER': '2004',
      'TOTAL': '2005',
    };
    for (final cat in _categories) {
      final row = countRows[cat]!;
      // Template summary cells: single-gender values in H2001:H2005;
      // mixed-gender values in I2001:I2005. The teacher-entered present side stays blank.
      final valueColumn = coed ? 'I' : 'H';
      registerXml = _setCell(
        registerXml,
        '$valueColumn$row',
        _n(categoryCounts, cat),
        styleFallbackRef: '$valueColumn$row',
      );
    }
    // Registered total (row 2005) so the Excel download is complete too.
    {
      final valueColumn = coed ? 'I' : 'H';
      registerXml = _setCell(
        registerXml,
        '${valueColumn}2005',
        _categories.fold<int>(0, (t, c) => t + _n(categoryCounts, c)),
        styleFallbackRef: '${valueColumn}2005',
      );
    }

    // Ensure Over, then Down page order so student batch 1 (e.g. Roll 1-30)
    // prints both its Left and Right horizontal pages before student batch 2 starts.
    registerXml = registerXml.replaceFirstMapped(
      RegExp(r'<pageSetup\b[^>]*/>'),
      (m) {
        final tag = m.group(0)!;
        if (RegExp(r'\bpageOrder="[^"]*"').hasMatch(tag)) {
          return tag.replaceFirst(
            RegExp(r'\bpageOrder="[^"]*"'),
            'pageOrder="overThenDown"',
          );
        }
        return tag.replaceFirst('/>', ' pageOrder="overThenDown"/>');
      },
    );

    // Blank (handwriting) mode leaves present, absent, PM POSHAN, breakfast
    // and average lines empty. Recorded mode fills the daily totals.
    if (recordedFill != null) {
      registerXml =
          _rewriteSpecificRows(registerXml, recordedFill.summaryValuesByRow);
    }
    writeText(registerName, registerXml);

    // Recorded register: cover page working days, total present days,
    // average attendance and attendance percentage.
    if (recordedFill != null) {
      final st = recordedFill.stats;
      final average = st.workingDays == 0 ? 0.0 : st.sumPresent / st.workingDays;
      final possible = st.sumPresent + st.sumAbsent;
      final percent = possible == 0 ? 0.0 : st.sumPresent * 100.0 / possible;
      final cells = coed
          ? <String, dynamic>{
              'E22': st.sumPresent,
              'E23': st.workingDays,
              'L21': '${percent.toStringAsFixed(2)} %',
              'L22': average.toStringAsFixed(2),
            }
          : <String, dynamic>{
              'E21': st.sumPresent,
              'E22': st.workingDays,
              'I20': '${percent.toStringAsFixed(2)} %',
              'I21': average.toStringAsFixed(2),
            };
      var cover = readText(coverSheet);
      cells.forEach((ref, value) {
        cover = _setCell(cover, ref, value, styleFallbackRef: ref);
      });
      writeText(coverSheet, cover);
    }

    // Long school names: the cover's A8 (merged across the page) shrinks to
    // fit instead of overflowing, for boys, girls and mixed covers alike.
    {
      final shrunk = _shrinkToFitCells(
        readText('xl/styles.xml'),
        readText(coverSheet),
        const <String>{'A8', 'A9'},
      );
      writeText(coverSheet, shrunk.$1);
      writeText('xl/styles.xml', shrunk.$2);
    }

    // Remove only the broken global print area and set explicit local print areas for each register.
    var workbookXml = readText('xl/workbook.xml');
    workbookXml = _configureWorkbook(workbookXml, type);
    writeText('xl/workbook.xml', workbookXml);

    final encoded = ZipEncoder().encode(archive);
    if (encoded.isEmpty) throw StateError('Could not create the Excel file.');
    return XlsxSanitizer.clean(Uint8List.fromList(encoded));
  }

  String _rewriteRegisterBodyRows(
    String xml, {
    required bool coed,
    required String schoolType,
    required List<Map<String, dynamic>> students,
    required int blankRows,
    required Map<String, int?> presentDaysByStudentId,
    List<Map<String, dynamic>>? extraStudentValues,
  }) {
    final finalVisibleRow = 3 + students.length + blankRows;
    const firstBodyRow = 4;
    const lastBodyRow = 2000;
    final sheetDataPattern = RegExp(
      r'<sheetData\b[^>]*>.*?</sheetData>',
      dotAll: true,
    );
    final sheetDataMatch = sheetDataPattern.firstMatch(xml);
    if (sheetDataMatch == null) {
      throw StateError('Excel template worksheet has no sheetData section.');
    }
    final sheetData = sheetDataMatch.group(0)!;
    final rowPattern = RegExp(r'<row\b[^>]*?(?:/>|>.*?</row>)', dotAll: true);
    final rewritten = sheetData.replaceAllMapped(rowPattern, (rowMatch) {
      final rowXml = rowMatch.group(0)!;
      final rowNumberMatch = RegExp(r'\br="(\d+)"').firstMatch(rowXml);
      if (rowNumberMatch == null) return rowXml;
      final rowNumber = int.tryParse(rowNumberMatch.group(1)!) ?? 0;
      if (rowNumber < firstBodyRow || rowNumber > lastBodyRow) return rowXml;

      final openEnd = rowXml.indexOf('>');
      if (openEnd < 0 || rowXml.endsWith('/>')) {
        throw StateError(
          'Excel template body row $rowNumber is not expandable.',
        );
      }
      var opening = rowXml.substring(0, openEnd + 1);
      opening = opening.replaceAll(RegExp(r'\s+hidden="[^"]*"'), '');
      if (rowNumber > finalVisibleRow) {
        opening = '${opening.substring(0, opening.length - 1)} hidden="1">';
      }

      Map<String, dynamic> values = <String, dynamic>{};
      final studentIndex = rowNumber - firstBodyRow;
      if (studentIndex >= 0 && studentIndex < students.length) {
        final student = students[studentIndex];
        final roll =
            _roll(student).isEmpty ? '${studentIndex + 1}' : _roll(student);
        final dob = _dobParts(student);
        values = <String, dynamic>{
          'A$rowNumber': roll,
          'B$rowNumber': _text(student['gr']),
          'C$rowNumber': dob[0],
          'D$rowNumber': dob[1],
          'E$rowNumber': dob[2],
          'F$rowNumber': _text(student['name']),
          'U$rowNumber': roll,
        };
        final studentId = _text(student['id']);
        final presentDays =
            studentId.isEmpty ? null : presentDaysByStudentId[studentId];
        // In the supplied template, prior-month present days are AT for single-
        // gender schools and AU for co-ed schools. Unknown counts stay blank.
        values[coed ? 'AU$rowNumber' : 'AT$rowNumber'] = presentDays;
        if (coed) {
          values['G$rowNumber'] = _genderLabel(student, schoolType);
          values['H$rowNumber'] = _text(student['caste']);
          values['I$rowNumber'] = _categoryLabel(student['category']);
          values['J$rowNumber'] = _dateDmy(student['enroll_school']);
          values['K$rowNumber'] = _dateDmy(student['enroll_class']);
        } else {
          values['G$rowNumber'] = _text(student['caste']);
          values['H$rowNumber'] = _categoryLabel(student['category']);
          values['I$rowNumber'] = _dateDmy(student['enroll_school']);
          values['J$rowNumber'] = _dateDmy(student['enroll_class']);
        }
        if (extraStudentValues != null &&
            studentIndex < extraStudentValues.length) {
          // Column letters only; bind them to this row number.
          for (final e in extraStudentValues[studentIndex].entries) {
            values['${e.key}$rowNumber'] = e.value;
          }
        }
      }

      final innerStart = openEnd + 1;
      final closeStart = rowXml.lastIndexOf('</row>');
      if (closeStart < innerStart)
        throw StateError('Excel template body row $rowNumber is malformed.');
      final inner = rowXml.substring(innerStart, closeStart);
      final cellPattern = RegExp(r'<c\b[^>]*?(?:/>|>.*?</c>)', dotAll: true);
      final foundRefs = <String>{};
      final newInner = inner.replaceAllMapped(cellPattern, (cellMatch) {
        final originalCell = cellMatch.group(0)!;
        final refMatch = RegExp(r'\br="([A-Z]+\d+)"').firstMatch(originalCell);
        if (refMatch == null) return originalCell;
        final ref = refMatch.group(1)!;
        foundRefs.add(ref);
        return _renderCell(
          originalCell,
          ref,
          values.containsKey(ref) ? values[ref] : null,
        );
      });
      for (final requiredRef in values.keys) {
        if (!foundRefs.contains(requiredRef)) {
          throw StateError(
            'Excel template is missing cell $requiredRef needed for the selected student.',
          );
        }
      }
      return '$opening$newInner</row>';
    });
    return xml.replaceRange(
      sheetDataMatch.start,
      sheetDataMatch.end,
      rewritten,
    );
  }

  /// Computes per-student P/A marks and the daily summary rows for the
  /// recorded register. Student values are keyed by column letter only.
  ({
    List<Map<String, dynamic>> studentValues,
    List<Map<String, String>> studentDayColors,
    Map<int, Map<String, dynamic>> summaryValuesByRow,
    ({int workingDays, int sumPresent, int sumAbsent}) stats,
  }) _buildRecordedFill({
    required HajariRecordedData recorded,
    required List<Map<String, dynamic>> students,
    required int year,
    required int month,
    required int daysInMonth,
    required bool coed,
    required String Function(int day) dayRef,
    required Map<String, int?> presentDaysByStudentId,
  }) {
    String iso(int d) =>
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
    bool isClosed(int d) {
      final date = DateTime(year, month, d);
      return date.weekday == DateTime.sunday ||
          recorded.holidayIsoDates.contains(iso(d));
    }

    // Class-level rows for days entered as direct counts (no student marks).
    final directByDay = <int, Map<String, dynamic>>{};
    for (final row in recorded.attendanceDays) {
      final dt = AttendanceLifecycle.parseDate(row['attendance_date']);
      if (dt == null || dt.year != year || dt.month != month) continue;
      directByDay[dt.day] = row;
    }

    int countOf(dynamic map, [String? key]) {
      if (map is! Map) return int.tryParse('${map ?? ''}') ?? 0;
      if (key != null) return int.tryParse('${map[key] ?? 0}') ?? 0;
      var t = 0;
      for (final v in map.values) {
        t += int.tryParse('$v') ?? 0;
      }
      return t;
    }

    final presentCol = coed ? 'AT' : 'AS';
    final priorCol = coed ? 'AU' : 'AT';
    final totalCol = coed ? 'AV' : 'AU';
    final remarkCol = coed ? 'AW' : 'AV';

    final perDayPresentByCat = <int, Map<String, int>>{};
    final perDayAbsent = <int, int>{};
    final perDayMdm = <int, int>{};
    final perDayBf = <int, int>{};
    final studentValues = <Map<String, dynamic>>[];
    final studentDayColors = <Map<String, String>>[];

    for (final student in students) {
      final values = <String, dynamic>{};
      final colors = <String, String>{};
      final sid = _text(student['id']);
      final marks = recorded.studentDailyMarks[sid];
      final cat = _category(student['category']);
      final enrolledOn = AttendanceLifecycle.parseEnrollmentDate(student);
      final leftOn = AttendanceLifecycle.parseLeavingDate(student);
      var monthPresent = 0;
      var monthMdm = 0;
      var monthBf = 0;
      for (var d = 1; d <= daysInMonth; d++) {
        if (isClosed(d) || !recorded.recordedDays.contains(d)) continue;
        final active = AttendanceLifecycle.isActiveOnDate(
          targetDate: DateTime(year, month, d),
          enrolledOn: enrolledOn,
          leftOn: leftOn,
        );
        final mark = marks?[d];
        if (mark == null && !active) continue;
        final present = mark?['present'] == true;
        values[dayRef(d)] = present ? 'P' : 'A';
        // Meal colour code of the mark (bold): red = PM POSHAN + breakfast,
        // blue = PM POSHAN, pink = breakfast, black = present only,
        // dark grey = absent.
        final tookMdm = present && mark?['mdm'] == true;
        final tookBf = present && mark?['breakfast'] == true;
        colors[dayRef(d)] = !present
            ? _markAbsent
            : (tookMdm && tookBf)
                ? _markBoth
                : tookMdm
                    ? _markMdm
                    : tookBf
                        ? _markBreakfast
                        : _markPresent;
        if (present) {
          monthPresent++;
          final byCat = perDayPresentByCat.putIfAbsent(d, () => <String, int>{});
          byCat[cat] = (byCat[cat] ?? 0) + 1;
          if (mark?['mdm'] == true) {
            monthMdm++;
            perDayMdm[d] = (perDayMdm[d] ?? 0) + 1;
          }
          if (mark?['breakfast'] == true) {
            monthBf++;
            perDayBf[d] = (perDayBf[d] ?? 0) + 1;
          }
        } else {
          perDayAbsent[d] = (perDayAbsent[d] ?? 0) + 1;
        }
      }
      final prior = sid.isEmpty ? null : presentDaysByStudentId[sid];
      if (recorded.recordedDays.isNotEmpty) {
        values[presentCol] = monthPresent;
        values[totalCol] = monthPresent + (prior ?? 0);
        values[remarkCol] = 'ભો.$monthMdm / ના.$monthBf';
      }
      if (prior != null) values[priorCol] = prior;
      studentValues.add(values);
      studentDayColors.add(colors);
    }

    // Days entered as direct counts only (no student-wise marks).
    for (final entry in directByDay.entries) {
      final d = entry.key;
      if (d > daysInMonth || isClosed(d) || recorded.recordedDays.contains(d)) {
        continue;
      }
      final row = entry.value;
      final byCat = <String, int>{
        for (final c in _categories) c: countOf(row['present_counts'], c),
      };
      final presentTotal = byCat.values.fold<int>(0, (a, b) => a + b);
      final registered = countOf(row['registered_counts']);
      if (presentTotal == 0 && registered == 0) continue;
      perDayPresentByCat[d] = byCat;
      perDayAbsent[d] = (registered - presentTotal).clamp(0, 99999).toInt();
      perDayMdm[d] = countOf(row['mdm_counts']);
      perDayBf[d] = countOf(row['breakfast_total']);
    }

    final summary = <int, Map<String, dynamic>>{
      for (var r = 2001; r <= 2008; r++) r: <String, dynamic>{},
    };
    var sumPresent = 0;
    var sumMdm = 0;
    var sumBf = 0;
    var sumAbsent = 0;
    var workingDays = 0;
    var mdmDays = 0;
    var bfDays = 0;
    for (var d = 1; d <= daysInMonth; d++) {
      final byCat = perDayPresentByCat[d];
      final hasDay = byCat != null || perDayAbsent.containsKey(d);
      if (!hasDay || isClosed(d)) continue;
      workingDays++;
      final ref = dayRef(d);
      var total = 0;
      for (var i = 0; i < _categories.length; i++) {
        final v = byCat?[_categories[i]] ?? 0;
        total += v;
        summary[2001 + i]!['$ref${2001 + i}'] = v;
      }
      final absent = perDayAbsent[d] ?? 0;
      final mdm = perDayMdm[d] ?? 0;
      final bf = perDayBf[d] ?? 0;
      summary[2005]!['${ref}2005'] = total;
      summary[2006]!['${ref}2006'] = absent;
      summary[2007]!['${ref}2007'] = mdm;
      summary[2008]!['${ref}2008'] = bf;
      sumPresent += total;
      sumAbsent += absent;
      sumMdm += mdm;
      sumBf += bf;
      if (mdm > 0) mdmDays++;
      if (bf > 0) bfDays++;
    }

    String avgOf(int total, int days) => days == 0
        ? '0'
        : (total / days).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
    String avg(int total) => avgOf(total, workingDays);
    // PM POSHAN / breakfast may not run every working day (Tithi Bhojan,
    // half days), so their averages use the days they were actually served.
    final mdmDivisor = mdmDays > 0 ? mdmDays : workingDays;
    final bfDivisor = bfDays > 0 ? bfDays : workingDays;
    final avgCol = coed ? 'AT' : 'AS';
    summary[2001]!['${avgCol}2001'] =
        'હાજરી સરાસરી = $sumPresent ÷ $workingDays = ${avg(sumPresent)}\n'
        'કુલ ગેરહાજર = $sumAbsent';
    summary[2005]!['${avgCol}2005'] =
        'મધ્યાહ્ન ભોજન સરાસરી = $sumMdm ÷ $mdmDivisor = ${avgOf(sumMdm, mdmDivisor)}\n'
        'અલ્પાહાર સરાસરી = $sumBf ÷ $bfDivisor = ${avgOf(sumBf, bfDivisor)}';
    return (
      studentValues: studentValues,
      studentDayColors: studentDayColors,
      summaryValuesByRow: summary,
      stats: (workingDays: workingDays, sumPresent: sumPresent, sumAbsent: sumAbsent),
    );
  }

  /// Bold, coloured Arial font for the given cells (ref → ARGB colour).
  (String, String) _colorMarkCells(
    String stylesXml,
    String sheetXml,
    Map<String, String> cellColors,
  ) {
    if (cellColors.isEmpty) return (sheetXml, stylesXml);
    final fontsM = RegExp(r'<fonts\b[^>]*>.*?</fonts>', dotAll: true).firstMatch(stylesXml);
    final xfsM = RegExp(r'<cellXfs\b[^>]*>.*?</cellXfs>', dotAll: true).firstMatch(stylesXml);
    if (fontsM == null || xfsM == null) return (sheetXml, stylesXml);
    final fonts = RegExp(r'<font\b[^>]*?(?:/>|>.*?</font>)', dotAll: true)
        .allMatches(fontsM.group(0)!)
        .map((m) => m.group(0)!)
        .toList();
    final xfs = RegExp(r'<xf\b[^>]*?(?:/>|>.*?</xf>)', dotAll: true)
        .allMatches(xfsM.group(0)!)
        .map((m) => m.group(0)!)
        .toList();
    final fontCache = <String, int>{};
    final xfCache = <String, int>{};
    int markFont(int baseId, String color) {
      final key = '$baseId|$color';
      final hit = fontCache[key];
      if (hit != null) return hit;
      final base = fonts[baseId.clamp(0, fonts.length - 1)];
      final size = RegExp(r'<sz\b[^>]*/>').firstMatch(base)?.group(0) ?? '<sz val="10"/>';
      fonts.add('<font><b/>$size<color rgb="$color"/><name val="Arial"/><family val="2"/></font>');
      return fontCache[key] = fonts.length - 1;
    }

    int markXf(int baseXf, String color) {
      final key = '$baseXf|$color';
      final hit = xfCache[key];
      if (hit != null) return hit;
      var xf = xfs[baseXf.clamp(0, xfs.length - 1)];
      final fontId = int.tryParse(RegExp(r'\bfontId="(\d+)"').firstMatch(xf)?.group(1) ?? '') ?? 0;
      final nf = markFont(fontId, color);
      xf = RegExp(r'\bfontId="\d+"').hasMatch(xf)
          ? xf.replaceFirst(RegExp(r'\bfontId="\d+"'), 'fontId="$nf"')
          : xf.replaceFirst('<xf ', '<xf fontId="$nf" ');
      if (!xf.contains('applyFont=')) xf = xf.replaceFirst('<xf ', '<xf applyFont="1" ');
      xfs.add(xf);
      return xfCache[key] = xfs.length - 1;
    }

    final cellPattern = RegExp(r'<c\b[^>]*?(?:/>|>.*?</c>)', dotAll: true);
    final sheet = sheetXml.replaceAllMapped(cellPattern, (m) {
      final cell = m.group(0)!;
      final ref = RegExp(r'\br="([A-Z]+\d+)"').firstMatch(cell)?.group(1);
      final color = ref == null ? null : cellColors[ref];
      if (color == null) return cell;
      final sM = RegExp(r'\bs="(\d+)"').firstMatch(cell);
      final id = markXf(int.tryParse(sM?.group(1) ?? '') ?? 0, color);
      return sM == null
          ? cell.replaceFirst('<c ', '<c s="$id" ')
          : cell.replaceFirst(sM.group(0)!, 's="$id"');
    });
    String rebuild(String original, String tag, List<String> items) {
      var open = original.substring(0, original.indexOf('>') + 1);
      open = RegExp(r'\bcount="\d+"').hasMatch(open)
          ? open.replaceFirst(RegExp(r'\bcount="\d+"'), 'count="${items.length}"')
          : open.replaceFirst('>', ' count="${items.length}">');
      return '$open${items.join()}</$tag>';
    }

    var styles = stylesXml;
    // xfs come after fonts in styles.xml: replace the later block first.
    styles = styles.replaceRange(xfsM.start, xfsM.end, rebuild(xfsM.group(0)!, 'cellXfs', xfs));
    styles = styles.replaceRange(fontsM.start, fontsM.end, rebuild(fontsM.group(0)!, 'fonts', fonts));
    return (sheet, styles);
  }

  /// Adds a merged range unless it overlaps an existing merge.
  String _addMergeIfFree(String sheetXml, String range) {
    final parts = range.split(':');
    int col(String ref) => _columnNumber(_columnOfRef(ref));
    int row(String ref) => int.parse(RegExp(r'\d+').firstMatch(ref)!.group(0)!);
    final c1 = col(parts[0]), c2 = col(parts[1]), r1 = row(parts[0]), r2 = row(parts[1]);
    for (final m in RegExp(r'<mergeCell ref="([A-Z]+\d+):([A-Z]+\d+)"').allMatches(sheetXml)) {
      final a = m.group(1)!, b = m.group(2)!;
      final overlap = !(col(b) < c1 || col(a) > c2 || row(b) < r1 || row(a) > r2);
      if (overlap) return sheetXml;
    }
    final mc = RegExp(r'<mergeCells\b([^>]*)>').firstMatch(sheetXml);
    if (mc == null) return sheetXml;
    var out = sheetXml.replaceRange(mc.end, mc.end, '<mergeCell ref="$range"/>');
    final count = RegExp(r'<mergeCell ref=').allMatches(out).length;
    out = out.replaceFirstMapped(RegExp(r'<mergeCells\b[^>]*>'), (m) {
      final tag = m.group(0)!;
      return RegExp(r'\bcount="\d+"').hasMatch(tag)
          ? tag.replaceFirst(RegExp(r'\bcount="\d+"'), 'count="$count"')
          : tag.replaceFirst('>', ' count="$count">');
    });
    return out;
  }

  /// Gives [refs] a copy of their style with shrinkToFit (no wrapping), so
  /// the text is scaled down to the cell width when printed.
  /// Gives [ref] a copy of its style with a thin border on all four sides.
  (String, String) _boxCellBorders(String stylesXml, String sheetXml, String ref) {
    final xfsMatch =
        RegExp(r'<cellXfs\b[^>]*>.*?</cellXfs>', dotAll: true).firstMatch(stylesXml);
    final bordersMatch =
        RegExp(r'<borders\b[^>]*>.*?</borders>', dotAll: true).firstMatch(stylesXml);
    final cell = RegExp('<c r="$ref"[^>]*?(?:/>|>)').firstMatch(sheetXml);
    if (xfsMatch == null || bordersMatch == null || cell == null) {
      return (sheetXml, stylesXml);
    }
    final xfs = RegExp(r'<xf\b[^>]*?(?:/>|>.*?</xf>)', dotAll: true)
        .allMatches(xfsMatch.group(0)!)
        .map((m) => m.group(0)!)
        .toList();
    final borders = RegExp(r'<border\b[^>]*?(?:/>|>.*?</border>)', dotAll: true)
        .allMatches(bordersMatch.group(0)!)
        .map((m) => m.group(0)!)
        .toList();
    final sMatch = RegExp(r'\bs="(\d+)"').firstMatch(cell.group(0)!);
    final id = int.tryParse(sMatch?.group(1) ?? '') ?? 0;
    if (id < 0 || id >= xfs.length) return (sheetXml, stylesXml);
    const side = '<color rgb="FF000000"/>';
    borders.add(
      '<border><left style="thin">$side</left><right style="thin">$side</right>'
      '<top style="thin">$side</top><bottom style="thin">$side</bottom><diagonal/></border>',
    );
    final borderId = borders.length - 1;
    var xf = xfs[id];
    xf = RegExp(r'\bborderId="\d+"').hasMatch(xf)
        ? xf.replaceFirst(RegExp(r'\bborderId="\d+"'), 'borderId="$borderId"')
        : xf.replaceFirst('<xf ', '<xf borderId="$borderId" ');
    xf = RegExp(r'\bapplyBorder="[^"]*"').hasMatch(xf)
        ? xf.replaceFirst(RegExp(r'\bapplyBorder="[^"]*"'), 'applyBorder="1"')
        : xf.replaceFirst('<xf ', '<xf applyBorder="1" ');
    xfs.add(xf);
    final nid = xfs.length - 1;
    final open = cell.group(0)!;
    final newOpen = sMatch == null
        ? open.replaceFirst('<c ', '<c s="$nid" ')
        : open.replaceFirst(sMatch.group(0)!, 's="$nid"');
    final sheet = sheetXml.replaceRange(cell.start, cell.end, newOpen);
    String rebuilt(String original, String tag, List<String> items) {
      final head = original
          .substring(0, original.indexOf('>') + 1)
          .replaceFirst(RegExp(r'\bcount="\d+"'), 'count="${items.length}"');
      return '$head${items.join()}</$tag>';
    }
    // Borders come before cellXfs in styles.xml: replace the later one first.
    var styles = stylesXml.replaceRange(
        xfsMatch.start, xfsMatch.end, rebuilt(xfsMatch.group(0)!, 'cellXfs', xfs));
    styles = styles.replaceRange(bordersMatch.start, bordersMatch.end,
        rebuilt(bordersMatch.group(0)!, 'borders', borders));
    return (sheet, styles);
  }

  /// Gives the day columns in [closed] a grey fill and removes the template's
  /// grey from the [open] ones, rows [firstRow]..[lastRow].
  (String, String) _shadeDayColumns(
    String stylesXml,
    String sheetXml, {
    required Set<String> closed,
    required Set<String> open,
    required int firstRow,
    required int lastRow,
  }) {
    final xfsMatch =
        RegExp(r'<cellXfs\b[^>]*>.*?</cellXfs>', dotAll: true).firstMatch(stylesXml);
    final fillsMatch =
        RegExp(r'<fills\b[^>]*>.*?</fills>', dotAll: true).firstMatch(stylesXml);
    if (xfsMatch == null || fillsMatch == null) return (sheetXml, stylesXml);
    final xfs = RegExp(r'<xf\b[^>]*?(?:/>|>.*?</xf>)', dotAll: true)
        .allMatches(xfsMatch.group(0)!)
        .map((m) => m.group(0)!)
        .toList();
    final fills = RegExp(r'<fill\b[^>]*?(?:/>|>.*?</fill>)', dotAll: true)
        .allMatches(fillsMatch.group(0)!)
        .map((m) => m.group(0)!)
        .toList();
    bool isGrey(int id) {
      if (id < 0 || id >= fills.length) return false;
      final f = fills[id].toUpperCase();
      return f.contains('SOLID') && (f.contains('D9D9D9') || f.contains('BFBFBF') || f.contains('D8D8D8'));
    }
    fills.add('<fill><patternFill patternType="solid"><fgColor rgb="FFD9D9D9"/><bgColor indexed="64"/></patternFill></fill>');
    final greyId = fills.length - 1;
    final cache = <String, int>{};
    int variant(int id, bool shade) {
      if (id < 0 || id >= xfs.length) id = 0;
      final key = '$id|$shade';
      final hit = cache[key];
      if (hit != null) return hit;
      var xf = xfs[id];
      final fillId = int.tryParse(RegExp(r'\bfillId="(\d+)"').firstMatch(xf)?.group(1) ?? '0') ?? 0;
      final target = shade ? greyId : (isGrey(fillId) ? 0 : fillId);
      if (target == fillId) return cache[key] = id;
      xf = RegExp(r'\bfillId="\d+"').hasMatch(xf)
          ? xf.replaceFirst(RegExp(r'\bfillId="\d+"'), 'fillId="$target"')
          : xf.replaceFirst('<xf ', '<xf fillId="$target" ');
      xf = RegExp(r'\bapplyFill="[^"]*"').hasMatch(xf)
          ? xf.replaceFirst(RegExp(r'\bapplyFill="[^"]*"'), 'applyFill="1"')
          : xf.replaceFirst('<xf ', '<xf applyFill="1" ');
      xfs.add(xf);
      return cache[key] = xfs.length - 1;
    }

    final sheet = sheetXml.replaceAllMapped(
      RegExp(r'<c r="([A-Z]{1,3})(\d+)"([^>]*?)(/?)>'),
      (m) {
        final letter = m.group(1)!;
        final row = int.parse(m.group(2)!);
        if (row < firstRow || row > lastRow) return m.group(0)!;
        final shade = closed.contains(letter);
        if (!shade && !open.contains(letter)) return m.group(0)!;
        final rest = m.group(3)!;
        final sMatch = RegExp(r'\bs="(\d+)"').firstMatch(rest);
        final id = int.tryParse(sMatch?.group(1) ?? '0') ?? 0;
        final nid = variant(id, shade);
        if (nid == id) return m.group(0)!;
        final newRest = sMatch == null ? '$rest s="$nid"' : rest.replaceFirst(sMatch.group(0)!, 's="$nid"');
        return '<c r="$letter${m.group(2)}"$newRest${m.group(4)}>';
      },
    );
    String rebuilt(String original, String tag, List<String> items) {
      final head = original
          .substring(0, original.indexOf('>') + 1)
          .replaceFirst(RegExp(r'\bcount="\d+"'), 'count="${items.length}"');
      return '$head${items.join()}</$tag>';
    }
    // fills come before cellXfs in styles.xml: replace the later one first.
    var styles = stylesXml.replaceRange(
        xfsMatch.start, xfsMatch.end, rebuilt(xfsMatch.group(0)!, 'cellXfs', xfs));
    styles = styles.replaceRange(
        fillsMatch.start, fillsMatch.end, rebuilt(fillsMatch.group(0)!, 'fills', fills));
    return (sheet, styles);
  }

  (String, String) _shrinkToFitCells(
    String stylesXml,
    String sheetXml,
    Set<String> refs,
  ) {
    final xfsMatch =
        RegExp(r'<cellXfs\b[^>]*>.*?</cellXfs>', dotAll: true).firstMatch(stylesXml);
    if (xfsMatch == null) return (sheetXml, stylesXml);
    final xfs = RegExp(r'<xf\b[^>]*?(?:/>|>.*?</xf>)', dotAll: true)
        .allMatches(xfsMatch.group(0)!)
        .map((m) => m.group(0)!)
        .toList();
    var sheet = sheetXml;
    for (final ref in refs) {
      final cell = RegExp('<c r="$ref"[^>]*?(?:/>|>)').firstMatch(sheet);
      if (cell == null) continue;
      final sMatch = RegExp(r'\bs="(\d+)"').firstMatch(cell.group(0)!);
      final id = int.tryParse(sMatch?.group(1) ?? '') ?? 0;
      if (id < 0 || id >= xfs.length) continue;
      var xf = xfs[id];
      String align(String a) {
        a = a
            .replaceAll(RegExp(r'\s*wrapText="[^"]*"'), '')
            .replaceAll(RegExp(r'\s*shrinkToFit="[^"]*"'), '');
        if (!a.contains('horizontal=')) a += ' horizontal="center"';
        if (!a.contains('vertical=')) a += ' vertical="center"';
        return '$a shrinkToFit="1"';
      }
      if (xf.contains('<alignment')) {
        xf = xf.replaceFirstMapped(RegExp(r'<alignment\b([^>]*?)/>'),
            (m) => '<alignment${align(m.group(1)!)}/>');
      } else if (xf.endsWith('/>')) {
        xf = '${xf.substring(0, xf.length - 2)}><alignment${align('')}/></xf>';
      } else {
        xf = xf.replaceFirst('</xf>', '<alignment${align('')}/></xf>');
      }
      if (!xf.contains('applyAlignment=')) {
        xf = xf.replaceFirst('<xf ', '<xf applyAlignment="1" ');
      }
      xfs.add(xf);
      final nid = xfs.length - 1;
      final open = cell.group(0)!;
      final newOpen = sMatch == null
          ? open.replaceFirst('<c ', '<c s="$nid" ')
          : open.replaceFirst(sMatch.group(0)!, 's="$nid"');
      sheet = sheet.replaceRange(cell.start, cell.end, newOpen);
    }
    final xfsXml = xfsMatch.group(0)!;
    final head = xfsXml
        .substring(0, xfsXml.indexOf('>') + 1)
        .replaceFirst(RegExp(r'\bcount="\d+"'), 'count="${xfs.length}"');
    return (
      sheet,
      stylesXml.replaceRange(xfsMatch.start, xfsMatch.end, '$head${xfs.join()}</cellXfs>'),
    );
  }

  /// Gives the cells of [columns] in rows [firstRow]..[lastRow] a copy of their
  /// style with textRotation 0 (wrapped text for [wrapColumns]).
  (String, String) _uprightCells(
    String stylesXml,
    String sheetXml, {
    required Set<String> columns,
    required int firstRow,
    required int lastRow,
    Set<String> wrapColumns = const <String>{},
  }) {
    final xfsMatch =
        RegExp(r'<cellXfs\b[^>]*>.*?</cellXfs>', dotAll: true).firstMatch(stylesXml);
    if (xfsMatch == null) return (sheetXml, stylesXml);
    final xfs = RegExp(r'<xf\b[^>]*?(?:/>|>.*?</xf>)', dotAll: true)
        .allMatches(xfsMatch.group(0)!)
        .map((m) => m.group(0)!)
        .toList();
    final cache = <String, int>{};
    int uprightOf(int id, bool wrap) {
      final key = '$id|$wrap';
      final hit = cache[key];
      if (hit != null) return hit;
      if (id < 0 || id >= xfs.length) return id;
      var xf = xfs[id];
      String align(String attrs) {
        var a = attrs
            .replaceAll(RegExp(r'\s*textRotation="[^"]*"'), '')
            .replaceAll(RegExp(r'\s*wrapText="[^"]*"'), '');
        if (!a.contains('horizontal=')) a += ' horizontal="center"';
        if (!a.contains('vertical=')) a += ' vertical="center"';
        if (wrap) a += ' wrapText="1"';
        return a;
      }
      if (xf.contains('<alignment')) {
        xf = xf.replaceFirstMapped(
          RegExp(r'<alignment\b([^>]*?)/>'),
          (m) => '<alignment${align(m.group(1)!)}/>',
        );
      } else if (xf.endsWith('/>')) {
        xf = '${xf.substring(0, xf.length - 2)}><alignment${align('')}/></xf>';
      } else {
        xf = xf.replaceFirst('</xf>', '<alignment${align('')}/></xf>');
      }
      if (!xf.contains('applyAlignment=')) {
        xf = xf.replaceFirst('<xf ', '<xf applyAlignment="1" ');
      }
      xfs.add(xf);
      return cache[key] = xfs.length - 1;
    }

    final rowPattern = RegExp(r'<row\b[^>]*?(?:/>|>.*?</row>)', dotAll: true);
    final cellPattern = RegExp(r'<c\b[^>]*?(?:/>|>.*?</c>)', dotAll: true);
    final newSheet = sheetXml.replaceAllMapped(rowPattern, (rm) {
      final rowXml = rm.group(0)!;
      final n = int.tryParse(
              RegExp(r'\br="(\d+)"').firstMatch(rowXml)?.group(1) ?? '') ??
          0;
      if (n < firstRow || n > lastRow) return rowXml;
      return rowXml.replaceAllMapped(cellPattern, (cm) {
        final cell = cm.group(0)!;
        final ref = RegExp(r'\br="([A-Z]+)\d+"').firstMatch(cell)?.group(1);
        if (ref == null || !columns.contains(ref)) return cell;
        final sMatch = RegExp(r'\bs="(\d+)"').firstMatch(cell);
        final id = int.tryParse(sMatch?.group(1) ?? '') ?? 0;
        final nid = uprightOf(id, wrapColumns.contains(ref));
        return sMatch == null
            ? cell.replaceFirst('<c ', '<c s="$nid" ')
            : cell.replaceFirst(sMatch.group(0)!, 's="$nid"');
      });
    });
    final xfsXml = xfsMatch.group(0)!;
    final open = xfsXml.substring(0, xfsXml.indexOf('>') + 1).replaceFirst(
          RegExp(r'\bcount="\d+"'),
          'count="${xfs.length}"',
        );
    final newStyles = stylesXml.replaceRange(
      xfsMatch.start,
      xfsMatch.end,
      '$open${xfs.join()}</cellXfs>',
    );
    return (newSheet, newStyles);
  }

  /// Single-pass value writer for a handful of rows in a very large sheet.
  String _rewriteSpecificRows(
    String xml,
    Map<int, Map<String, dynamic>> valuesByRow,
  ) {
    if (valuesByRow.isEmpty) return xml;
    final pending = <String, dynamic>{};
    for (final m in valuesByRow.values) {
      pending.addAll(m);
    }
    final rowPattern = RegExp(r'<row\b[^>]*?(?:/>|>.*?</row>)', dotAll: true);
    final cellPattern = RegExp(r'<c\b[^>]*?(?:/>|>.*?</c>)', dotAll: true);
    var out = xml.replaceAllMapped(rowPattern, (rowMatch) {
      final rowXml = rowMatch.group(0)!;
      final numMatch = RegExp(r'\br="(\d+)"').firstMatch(rowXml);
      final rowNumber = int.tryParse(numMatch?.group(1) ?? '') ?? 0;
      final values = valuesByRow[rowNumber];
      if (values == null || values.isEmpty || rowXml.endsWith('/>')) {
        return rowXml;
      }
      return rowXml.replaceAllMapped(cellPattern, (cellMatch) {
        final cellXml = cellMatch.group(0)!;
        final ref = RegExp(r'\br="([A-Z]+\d+)"').firstMatch(cellXml)?.group(1);
        if (ref == null || !values.containsKey(ref)) return cellXml;
        pending.remove(ref);
        return _renderCell(cellXml, ref, values[ref]);
      });
    });
    // Any cell missing from a sparse template is inserted the slow way.
    for (final e in pending.entries) {
      out = _setCell(out, e.key, e.value, styleFallbackRef: e.key);
    }
    return out;
  }

  (String, String) _applyRegisterRowStyles(
    String stylesXml,
    String worksheetXml, {
    required bool coed,
    required String schoolType,
    required List<Map<String, dynamic>> students,
  }) {
    final fontsMatch = RegExp(
      r'<fonts\b[^>]*>.*?</fonts>',
      dotAll: true,
    ).firstMatch(stylesXml);
    final fillsMatch = RegExp(
      r'<fills\b[^>]*>.*?</fills>',
      dotAll: true,
    ).firstMatch(stylesXml);
    final bordersMatch = RegExp(
      r'<borders\b[^>]*>.*?</borders>',
      dotAll: true,
    ).firstMatch(stylesXml);
    final xfsMatch = RegExp(
      r'<cellXfs\b[^>]*>.*?</cellXfs>',
      dotAll: true,
    ).firstMatch(stylesXml);
    if (fontsMatch == null ||
        fillsMatch == null ||
        bordersMatch == null ||
        xfsMatch == null) {
      throw StateError(
        'The Hajari Patrak Excel template has incomplete style tables.',
      );
    }

    List<String> children(String collection, String childTag) => RegExp(
          '<$childTag\\b[^>]*?(?:/>|>.*?</$childTag>)',
          dotAll: true,
        ).allMatches(collection).map((match) => match.group(0)!).toList();

    String updateCollection(String original, String tag, List<String> items) {
      final openEnd = original.indexOf('>');
      final closeStart = original.lastIndexOf('</$tag>');
      if (openEnd < 0 || closeStart < openEnd) {
        throw StateError(
          'Invalid $tag style collection in Hajari Patrak template.',
        );
      }
      var opening = original.substring(0, openEnd + 1);
      if (RegExp(r'\bcount="\d+"').hasMatch(opening)) {
        opening = opening.replaceFirst(
          RegExp(r'\bcount="\d+"'),
          'count="${items.length}"',
        );
      } else {
        opening = opening.replaceFirst('>', ' count="${items.length}">');
      }
      return '$opening${items.join()}${original.substring(closeStart)}';
    }

    var fonts = children(fontsMatch.group(0)!, 'font');
    var fills = children(fillsMatch.group(0)!, 'fill');
    var borders = children(bordersMatch.group(0)!, 'border');
    var xfs = children(xfsMatch.group(0)!, 'xf');
    if (fonts.isEmpty || xfs.isEmpty || borders.isEmpty || fills.isEmpty) {
      throw StateError('The Hajari Patrak template style tables are empty.');
    }

    final fontCache = <String, int>{};
    final fillCache = <String, int>{};
    final borderCache = <String, int>{};
    final xfCache = <String, int>{};

    int fontVariant(int baseId, String color) {
      final key = '$baseId|$color';
      final cached = fontCache[key];
      if (cached != null) return cached;
      if (baseId < 0 || baseId >= fonts.length) {
        throw StateError(
          'Invalid font style $baseId in Hajari Patrak template.',
        );
      }
      var font = fonts[baseId];
      final colorTag = '<color rgb="$color"/>';
      final colorPattern = RegExp(r'<color\b[^>]*/>');
      if (colorPattern.hasMatch(font)) {
        font = font.replaceFirst(colorPattern, colorTag);
      } else {
        final sizeTag = RegExp(r'<sz\b[^>]*/>').firstMatch(font);
        if (sizeTag != null) {
          font = font.replaceRange(sizeTag.end, sizeTag.end, colorTag);
        } else {
          font = font.replaceFirst('</font>', '$colorTag</font>');
        }
      }
      final id = fonts.length;
      fonts.add(font);
      fontCache[key] = id;
      return id;
    }

    int fillVariant(String gender) {
      final cached = fillCache[gender];
      if (cached != null) return cached;
      final color = XlsxRowColors.genderFill[gender] ?? 'FFF2F2F2';
      final id = fills.length;
      fills.add(
        '<fill><patternFill patternType="solid"><fgColor rgb="$color"/><bgColor rgb="$color"/></patternFill></fill>',
      );
      fillCache[gender] = id;
      return id;
    }

    int borderVariant(int baseId, bool doubleBottom) {
      if (baseId < 0 || baseId >= borders.length) {
        throw StateError(
          'Invalid border style $baseId in Hajari Patrak template.',
        );
      }
      final original = borders[baseId];
      final bottomMatch = RegExp(
        r'<bottom\b([^>]*?)>(.*?)</bottom>|<bottom\b([^>]*?)/>',
        dotAll: true,
      ).firstMatch(original);
      final currentStyle = bottomMatch == null
          ? ''
          : (RegExp(r'\bstyle="([^"]+)"')
                  .firstMatch(
                    bottomMatch.group(1) ?? bottomMatch.group(3) ?? '',
                  )
                  ?.group(1) ??
              '');
      final desiredStyle = doubleBottom ? 'double' : 'thin';
      if (currentStyle == desiredStyle ||
          (!doubleBottom && currentStyle != 'double')) return baseId;
      final key = '$baseId|$desiredStyle';
      final cached = borderCache[key];
      if (cached != null) return cached;

      var updated = original;
      final match = bottomMatch;
      if (match == null) {
        updated = updated.replaceFirst(
          '</border>',
          '<bottom style="$desiredStyle"><color rgb="FF000000"/></bottom></border>',
        );
      } else {
        final attrs = (match.group(1) ?? match.group(3) ?? '').replaceAll(
              RegExp(r'\s+style="[^"]*"'),
              '',
            ) +
            ' style="$desiredStyle"';
        var body = match.group(2) ?? '<color rgb="FF000000"/>';
        if (body.trim().isEmpty) body = '<color rgb="FF000000"/>';
        final replacement = '<bottom$attrs>$body</bottom>';
        updated = updated.replaceRange(match.start, match.end, replacement);
      }
      final id = borders.length;
      borders.add(updated);
      borderCache[key] = id;
      return id;
    }

    String setXfAttribute(String xf, String name, int value) {
      final pattern = RegExp('\\b$name="[^\"]*"');
      if (pattern.hasMatch(xf))
        return xf.replaceFirst(pattern, '$name="$value"');
      final close = xf.indexOf('>');
      if (close < 0)
        throw StateError(
          'Invalid cell style record in Hajari Patrak template.',
        );
      final open = xf.substring(0, close + 1);
      final replacement = open.endsWith('/>')
          ? open.replaceFirst('/>', ' $name="$value"/>')
          : open.replaceFirst('>', ' $name="$value">');
      return replacement + xf.substring(close + 1);
    }

    int styleVariant(int baseStyleId, String category, String gender,
        bool categoryEnd, bool useGenderFill,
        {bool forceHorizontal = false}) {
      final key =
          '$baseStyleId|$category|$gender|$categoryEnd|$useGenderFill|$forceHorizontal';
      final cached = xfCache[key];
      if (cached != null) return cached;
      if (baseStyleId < 0 || baseStyleId >= xfs.length) {
        throw StateError(
          'Invalid cell style $baseStyleId in Hajari Patrak template.',
        );
      }
      var xf = xfs[baseStyleId];
      if (forceHorizontal) {
        final alignmentMatch = RegExp(r'<alignment\b[^>]*/>').firstMatch(xf);
        if (alignmentMatch != null) {
          final alignment = alignmentMatch.group(0)!;
          final horizontalAlignment = alignment.replaceAll(
            RegExp(r'\s+textRotation="[^"]*"'),
            '',
          );
          xf = xf.replaceRange(
            alignmentMatch.start,
            alignmentMatch.end,
            horizontalAlignment,
          );
        }
      }
      int attr(String name) =>
          int.tryParse(
            RegExp('\\b$name="(\\d+)"').firstMatch(xf)?.group(1) ?? '',
          ) ??
          0;
      final fontId = attr('fontId');
      final fillId = attr('fillId');
      final borderId = attr('borderId');
      final color =
          XlsxRowColors.categoryFont[category] ?? XlsxRowColors.categoryFont['OTHER']!;
      xf = setXfAttribute(xf, 'fontId', fontVariant(fontId, color));
      // Preserve template fills used for Sundays/holidays; gender shading is
      // applied only to cells whose template fill is otherwise transparent.
      final effectiveFill = useGenderFill && (fillId == 0 || fillId == 1)
          ? fillVariant(gender)
          : fillId;
      xf = setXfAttribute(xf, 'fillId', effectiveFill);
      xf = setXfAttribute(xf, 'borderId', borderVariant(borderId, categoryEnd));
      xf = setXfAttribute(xf, 'applyFont', 1);
      if (useGenderFill && effectiveFill != fillId)
        xf = setXfAttribute(xf, 'applyFill', 1);
      if (categoryEnd || borderVariant(borderId, false) != borderId)
        xf = setXfAttribute(xf, 'applyBorder', 1);
      final id = xfs.length;
      xfs.add(xf);
      xfCache[key] = id;
      return id;
    }

    final sheetDataPattern = RegExp(
      r'<sheetData\b[^>]*>.*?</sheetData>',
      dotAll: true,
    );
    final sheetMatch = sheetDataPattern.firstMatch(worksheetXml);
    if (sheetMatch == null)
      throw StateError('Hajari Patrak register has no sheetData.');
    final sheetData = sheetMatch.group(0)!;
    final rowPattern = RegExp(r'<row\b[^>]*?(?:/>|>.*?</row>)', dotAll: true);
    // Create a clean borderless, fill-free style for binding-space columns S (19) and T (20)
    final emptyBorderId = borders.length;
    borders.add('<border><left/><right/><top/><bottom/><diagonal/></border>');
    final blankGapStyleId = xfs.length;
    var gapXf = xfs.first;
    gapXf = setXfAttribute(gapXf, 'fillId', 0);
    gapXf = setXfAttribute(gapXf, 'borderId', emptyBorderId);
    gapXf = setXfAttribute(gapXf, 'applyFill', 1);
    gapXf = setXfAttribute(gapXf, 'applyBorder', 1);
    xfs.add(gapXf);
    final maxTableCol = coed ? 49 : 48;

    final styledSheetData = sheetData.replaceAllMapped(rowPattern, (rowMatch) {
      final rowXml = rowMatch.group(0)!;
      final rowNumber = int.tryParse(
            RegExp(r'\br="(\d+)"').firstMatch(rowXml)?.group(1) ?? '',
          ) ??
          0;
      final studentIndex = rowNumber - 4;
      final isStudentRow = studentIndex >= 0 && studentIndex < students.length;
      final student = isStudentRow ? students[studentIndex] : null;
      final category = isStudentRow ? _category(student!['category']) : '';
      final gender = isStudentRow ? _gender(student!, schoolType) : '';
      final isCategoryEnd = isStudentRow &&
          (studentIndex == students.length - 1 ||
              _category(students[studentIndex + 1]['category']) != category);
      return rowXml.replaceAllMapped(
        RegExp(r'<c\b[^>]*?(?:/>|>.*?</c>)', dotAll: true),
        (cellMatch) {
          final cell = cellMatch.group(0)!;
          final cellRef =
              RegExp(r'\br="([A-Z]+\d+)"').firstMatch(cell)?.group(1) ?? '';
          final colNum = cellRef.isEmpty ? 0 : _columnNumber(_columnOfRef(cellRef));
          // Never draw borders or double lines in the binding space (Cols 19..20, S..T) or outside the table!
          if (colNum == 19 || colNum == 20 || colNum > maxTableCol) {
            final styleAttr = RegExp(r'\bs="\d+"');
            if (styleAttr.hasMatch(cell)) {
              return cell.replaceFirst(styleAttr, 's="$blankGapStyleId"');
            }
            return cell;
          }
          if (!isStudentRow) return cell;
          final styleId = int.tryParse(
                RegExp(r'\bs="(\d+)"').firstMatch(cell)?.group(1) ?? '',
              ) ??
              0;
          final forceHorizontal = !coed && cellRef == 'AT$rowNumber';
          final updatedStyle = styleVariant(
            styleId,
            category,
            gender,
            isCategoryEnd,
            coed,
            forceHorizontal: forceHorizontal,
          );
          final styleAttr = RegExp(r'\bs="\d+"');
          if (styleAttr.hasMatch(cell))
            return cell.replaceFirst(styleAttr, 's="$updatedStyle"');
          final openEnd = cell.indexOf('>');
          if (openEnd < 0) return cell;
          final opening = cell.substring(0, openEnd + 1);
          final updatedOpening = opening.endsWith('/>')
              ? opening.replaceFirst('/>', ' s="$updatedStyle"/>')
              : opening.replaceFirst('>', ' s="$updatedStyle">');
          return updatedOpening + cell.substring(openEnd + 1);
        },
      );
    });

    worksheetXml = worksheetXml.replaceRange(
      sheetMatch.start,
      sheetMatch.end,
      styledSheetData,
    );
    stylesXml = stylesXml.replaceRange(
      xfsMatch.start,
      xfsMatch.end,
      updateCollection(xfsMatch.group(0)!, 'cellXfs', xfs),
    );
    // Re-find each collection after updating the preceding one, since string lengths changed.
    final fm = RegExp(
      r'<fonts\b[^>]*>.*?</fonts>',
      dotAll: true,
    ).firstMatch(stylesXml)!;
    stylesXml = stylesXml.replaceRange(
      fm.start,
      fm.end,
      updateCollection(fm.group(0)!, 'fonts', fonts),
    );
    final fillm = RegExp(
      r'<fills\b[^>]*>.*?</fills>',
      dotAll: true,
    ).firstMatch(stylesXml)!;
    stylesXml = stylesXml.replaceRange(
      fillm.start,
      fillm.end,
      updateCollection(fillm.group(0)!, 'fills', fills),
    );
    final bm = RegExp(
      r'<borders\b[^>]*>.*?</borders>',
      dotAll: true,
    ).firstMatch(stylesXml)!;
    stylesXml = stylesXml.replaceRange(
      bm.start,
      bm.end,
      updateCollection(bm.group(0)!, 'borders', borders),
    );
    return (worksheetXml, stylesXml);
  }

  static String _configureWorkbook(String xml, String type) {
    xml = xml.replaceAll(
      RegExp(
        r'<definedName\b(?=[^>]*\bname="_xlnm\.Print_Area")[^>]*>\s*#REF!\s*</definedName>',
        dotAll: true,
      ),
      '',
    );
    const printAreas =
        r'''<definedName name="_xlnm.Print_Area" localSheetId="3">'HAJARI PATRAK for sungle gender'!$A$1:$AV$2008</definedName><definedName name="_xlnm.Print_Area" localSheetId="4">'HAJARI PATRAK for  BOTH GENDER'!$A$1:$AW$2008</definedName><definedName name="_xlnm.Print_Titles" localSheetId="3">'HAJARI PATRAK for sungle gender'!$1:$3</definedName><definedName name="_xlnm.Print_Titles" localSheetId="4">'HAJARI PATRAK for  BOTH GENDER'!$1:$3</definedName>''';
    if (xml.contains('</definedNames>')) {
      // Prevent duplicate local print areas if this exporter is applied to a template that already has them.
      xml = xml.replaceAll(
        RegExp(
          r'<definedName\b(?=[^>]*\bname="_xlnm\.(?:Print_Area|Print_Titles)")(?=[^>]*\blocalSheetId="[34]")[^>]*>.*?</definedName>',
          dotAll: true,
        ),
        '',
      );
      xml = xml.replaceFirst('</definedNames>', '$printAreas</definedNames>');
    }
    final visible = type == 'boys'
        ? <String, bool>{
            'FRONT PAGE only boys': true,
            'FRONT PAGE only girls': false,
            'FRONT PAGE both': false,
            'HAJARI PATRAK for sungle gender': true,
            'HAJARI PATRAK for  BOTH GENDER': false,
          }
        : type == 'girls'
            ? <String, bool>{
                'FRONT PAGE only boys': false,
                'FRONT PAGE only girls': true,
                'FRONT PAGE both': false,
                'HAJARI PATRAK for sungle gender': true,
                'HAJARI PATRAK for  BOTH GENDER': false,
              }
            : <String, bool>{
                'FRONT PAGE only boys': false,
                'FRONT PAGE only girls': false,
                'FRONT PAGE both': true,
                'HAJARI PATRAK for sungle gender': false,
                'HAJARI PATRAK for  BOTH GENDER': true,
              };
    xml = xml.replaceAllMapped(
      RegExp(r'<sheet\b[^>]*\bname="([^"]+)"[^>]*/>'),
      (match) {
        final name = match.group(1)!;
        final original = match.group(0)!;
        final isVisible = visible[name] ?? true;
        final clean = original.replaceAll(RegExp(r'\s+state="[^"]*"'), '');
        if (isVisible) return clean;
        return clean.replaceFirst('/>', ' state="hidden"/>');
      },
    );
    final activeTab = type == 'boys'
        ? '0'
        : type == 'girls'
            ? '1'
            : '2';
    xml = xml.replaceAllMapped(RegExp(r'<workbookView\b[^>]*/>'), (match) {
      final old = match.group(0)!;
      final clean = old.replaceAll(RegExp(r'\s+activeTab="[^"]*"'), '');
      return clean.replaceFirst('/>', ' activeTab="$activeTab"/>');
    });
    return xml;
  }

  static void _setMany(
    void Function(String) assign,
    String xml,
    Map<String, dynamic> values, {
    required int styleFallbackRow,
  }) {
    var output = xml;
    for (final entry in values.entries) {
      // If a sparse co-ed template omits the cover month row, E5 is written
      // before A5 and supplies a more appropriate centered month-band style.
      final fallbackRef = entry.key == 'A5'
          ? 'E5'
          : '${_columnOfRef(entry.key)}$styleFallbackRow';
      output = _setCell(
        output,
        entry.key,
        entry.value,
        styleFallbackRef: fallbackRef,
      );
    }
    assign(output);
  }

  static String _setCell(
    String xml,
    String ref,
    dynamic value, {
    String? styleFallbackRef,
  }) {
    final refEscaped = RegExp.escape(ref);
    final pattern = RegExp(
      '<c\\b(?=[^>]*\\br="$refEscaped")[^>]*?(?:/>|>.*?</c>)',
      dotAll: true,
    );
    final existing = pattern.firstMatch(xml);
    String cell;
    if (existing != null) {
      cell = _renderCell(existing.group(0)!, ref, value);
      return xml.replaceRange(existing.start, existing.end, cell);
    }
    final rowNumber = RegExp(r'\d+').firstMatch(ref)!.group(0)!;
    final rowPattern = RegExp(
      '<row\\b(?=[^>]*\\br="$rowNumber")[^>]*?(?:/>|>.*?</row>)',
      dotAll: true,
    );
    final row = rowPattern.firstMatch(xml);
    final style =
        styleFallbackRef == null ? '' : _styleAttribute(xml, styleFallbackRef);
    final empty = '<c r="$ref"$style></c>';
    cell = _renderCell(empty, ref, value);
    if (row != null) {
      final rowXml = row.group(0)!;
      // Some Excel editors serialize an empty styled row as <row .../>.
      // Expand it instead of failing because the row has no closing tag.
      if (RegExp(r'/\s*>$').hasMatch(rowXml)) {
        final slash = rowXml.lastIndexOf('/>');
        final newRow = '${rowXml.substring(0, slash)}>$cell</row>';
        return xml.replaceRange(row.start, row.end, newRow);
      }
      final openEnd = rowXml.indexOf('>');
      final inner = rowXml.substring(openEnd + 1, rowXml.lastIndexOf('</row>'));
      final targetCol = _columnNumber(_columnOfRef(ref));
      final cells = RegExp(
        r'<c\b[^>]*?(?:/>|>.*?</c>)',
        dotAll: true,
      ).allMatches(inner);
      Match? before;
      for (final candidate in cells) {
        final cellRefMatch =
            RegExp(r'\br="([A-Z]+\d+)"').firstMatch(candidate.group(0)!);
        if (cellRefMatch == null) continue;
        final candidateRef = cellRefMatch.group(1)!;
        if (_columnNumber(_columnOfRef(candidateRef)) > targetCol) {
          before = candidate;
          break;
        }
      }
      final newInner = before == null
          ? '$inner$cell'
          : '${inner.substring(0, before.start)}$cell${inner.substring(before.start)}';
      final newRow = '${rowXml.substring(0, openEnd + 1)}$newInner</row>';
      return xml.replaceRange(row.start, row.end, newRow);
    }

    // Certain school-provided copies have sparse sheetData and omit an empty
    // row entirely. Insert the new row in ascending row order instead of
    // crashing (e.g. when writing the month label/heading into A5).
    final sheetDataPattern = RegExp(
      r'<sheetData\b[^>]*>.*?</sheetData>',
      dotAll: true,
    );
    final sheetDataMatch = sheetDataPattern.firstMatch(xml);
    if (sheetDataMatch == null) {
      throw StateError(
        'Excel template worksheet has no sheetData while writing $ref.',
      );
    }
    final sheetDataXml = sheetDataMatch.group(0)!;
    final rowMatches = RegExp(
      r'<row\b[^>]*?(?:/>|>.*?</row>)',
      dotAll: true,
    ).allMatches(sheetDataXml);
    final targetRow = int.parse(rowNumber);
    Match? beforeRow;
    Match? nearestRow;
    var nearestDistance = 1 << 30;
    for (final candidate in rowMatches) {
      final candidateXml = candidate.group(0)!;
      final numberMatch = RegExp(r'\br="(\d+)"').firstMatch(candidateXml);
      if (numberMatch == null) continue;
      final number = int.parse(numberMatch.group(1)!);
      if (number > targetRow && beforeRow == null) beforeRow = candidate;
      final distance = (number - targetRow).abs();
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestRow = candidate;
      }
    }

    var rowAttributes = ' r="$rowNumber"';
    if (nearestRow != null) {
      final nearestXml = nearestRow.group(0)!;
      final openEnd = nearestXml.indexOf('>');
      var attributes = nearestXml
          .substring(4, openEnd)
          .replaceAll(RegExp(r'\s+r="\d+"'), '')
          .replaceFirst(RegExp(r'/\s*$'), '');
      // Do not accidentally carry hidden/border-break flags from the adjacent row.
      attributes = attributes
          .replaceAll(RegExp(r'\s+hidden="[^"]*"'), '')
          .replaceAll(RegExp(r'\s+thickTop="[^"]*"'), '')
          .replaceAll(RegExp(r'\s+thickBot="[^"]*"'), '')
          .replaceAll(RegExp(r'\s+collapsed="[^"]*"'), '')
          .replaceAll(RegExp(r'\s+outlineLevel="[^"]*"'), '');
      // The cover's month band is 28.5 points high in the supplied workbook.
      if (targetRow == 5) {
        if (RegExp(r'\bht="[^"]*"').hasMatch(attributes)) {
          attributes = attributes.replaceAll(
            RegExp(r'\bht="[^"]*"'),
            'ht="28.5"',
          );
        } else {
          attributes += ' ht="28.5"';
        }
        if (!RegExp(r'\bcustomHeight="[^"]*"').hasMatch(attributes)) {
          attributes += ' customHeight="1"';
        }
      }
      rowAttributes = ' r="$rowNumber"$attributes';
    }
    final newRow = '<row$rowAttributes>$cell</row>';
    final insertAt = beforeRow == null
        ? sheetDataXml.lastIndexOf('</sheetData>')
        : beforeRow.start;
    if (insertAt < 0) {
      throw StateError(
        'Excel template sheetData is malformed while writing $ref.',
      );
    }
    final patchedSheetData = sheetDataXml.substring(0, insertAt) +
        newRow +
        sheetDataXml.substring(insertAt);
    return xml.replaceRange(
      sheetDataMatch.start,
      sheetDataMatch.end,
      patchedSheetData,
    );
  }

  static String _renderCell(String cellXml, String ref, dynamic value) {
    final openingMatch = RegExp(r'^<c\b[^>]*').firstMatch(cellXml);
    if (openingMatch == null)
      throw StateError('Invalid Excel cell XML for $ref.');
    var opening = openingMatch.group(0)!;
    opening = opening
        .replaceAll(RegExp(r'\s+t="[^"]*"'), '')
        .replaceAll(RegExp(r'/\s*$'), '');
    if (value == null || (value is String && value.isEmpty))
      return '$opening></c>';
    if (value is num) return '$opening><v>$value</v></c>';
    if (value is bool) return '$opening t="b"><v>${value ? 1 : 0}</v></c>';
    final text = _escapeXml('$value');
    return '$opening t="inlineStr"><is><t xml:space="preserve">$text</t></is></c>';
  }

  static String _styleAttribute(String xml, String ref) {
    final pat = RegExp(
      '<c\\b(?=[^>]*\\br="${RegExp.escape(ref)}")[^>]*?(?:/>|>.*?</c>)',
      dotAll: true,
    );
    final match = pat.firstMatch(xml);
    if (match == null) return '';
    final style = RegExp(r'\bs="([^"]+)"').firstMatch(match.group(0)!);
    return style == null ? '' : ' s="${style.group(1)}"';
  }

  Map<String, Map<String, dynamic>> _movements(
    List<Map<String, dynamic>> students,
    DateTime first,
    DateTime last,
    String type,
  ) {
    final opening = <Map<String, dynamic>>[];
    final admissions = <Map<String, dynamic>>[];
    final departures = <Map<String, dynamic>>[];
    final continuous = <Map<String, dynamic>>[];
    final lcExits = <Map<String, dynamic>>[];
    final closing = <Map<String, dynamic>>[];
    for (final student in students) {
      final rawEntry = _effectiveEntry(student);
      // In June (start of the academic year), students admitted on or before June 1st
      // belong to the opening register strength.
      final entry = (first.month == 6 &&
              rawEntry.year == first.year &&
              rawEntry.month == 6 &&
              rawEntry.day == 1)
          ? DateTime(first.year, 5, 31)
          : rawEntry;
      final leaving = AttendanceLifecycle.parseLeavingDate(student);
      if (entry.isBefore(first) &&
          (leaving == null || !leaving.isBefore(first))) {
        opening.add(student);
      }
      if (!entry.isBefore(first) && !entry.isAfter(last)) {
        admissions.add(student);
      }
      if (!entry.isAfter(last) &&
          leaving != null &&
          !leaving.isBefore(first) &&
          !leaving.isAfter(last)) {
        final reason = _leavingReason(student);
        departures.add(student);
        if (_continuousAbsence(reason)) {
          continuous.add(student);
        } else {
          lcExits.add(student);
        }
      }
      if (!entry.isAfter(last) && (leaving == null || leaving.isAfter(last))) {
        closing.add(student);
      }
    }
    const hasUnclassifiedDeparture = false;
    Map<String, dynamic> summarize(
      List<Map<String, dynamic>> source, {
      bool reasonUnknown = false,
    }) {
      final gender = <String, int>{'BOYS': 0, 'GIRLS': 0, 'UNSPECIFIED': 0};
      final category = <String, int>{
        for (final c in _categories) c: 0,
        'TOTAL': source.length,
      };
      final genderCategory = <String, int>{};
      for (final student in source) {
        final g = _gender(student, type);
        final c = _category(student['category']);
        gender[g] = (gender[g] ?? 0) + 1;
        category[c] = (category[c] ?? 0) + 1;
        genderCategory['${g}_$c'] = (genderCategory['${g}_$c'] ?? 0) + 1;
      }
      return <String, dynamic>{
        'total': source.length,
        'gender': gender,
        'category': category,
        'genderCategory': genderCategory,
        'unknownReason': reasonUnknown,
      };
    }

    return <String, Map<String, dynamic>>{
      'opening': summarize(opening),
      'admissions': summarize(admissions),
      'exits': summarize(lcExits, reasonUnknown: hasUnclassifiedDeparture),
      'absenceRemovals': summarize(
        continuous,
        reasonUnknown: hasUnclassifiedDeparture,
      ),
      'closing': summarize(closing),
    };
  }

  String _movementKey(int index) => const <String>[
        'opening',
        'admissions',
        'exits',
        'absenceRemovals',
        'closing',
      ][index];
  Map<String, dynamic> _asMap(dynamic value) => value is Map
      ? value.map((k, v) => MapEntry('$k', v))
      : <String, dynamic>{};
  int _n(dynamic map, String key) {
    final value = _asMap(map)[key];
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  String _text(dynamic value) => (value ?? '').toString().trim();
  String _canonicalType(String value) => SchoolType.coedCompat(value);

  String _classValue(String value) => ClassLabel.bare(value);
  String _roll(Map<String, dynamic> student) => _text(student['roll_number']);
  DateTime? _parseDate(dynamic value) {
    if (value is DateTime) return DateTime(value.year, value.month, value.day);
    final raw = _text(value);
    final dmy =
        RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$').firstMatch(raw);
    if (dmy != null) {
      final d = int.tryParse(dmy.group(1)!) ?? 0;
      final m = int.tryParse(dmy.group(2)!) ?? 0;
      final y = int.tryParse(dmy.group(3)!) ?? 0;
      if (d > 0 && m > 0 && m <= 12 && y >= 1900) {
        final v = DateTime(y, m, d);
        if (v.year == y && v.month == m && v.day == d) return v;
      }
    }
    final v = DateTime.tryParse(raw);
    return v == null ? null : DateTime(v.year, v.month, v.day);
  }

  DateTime _effectiveEntry(Map<String, dynamic> student) =>
      AttendanceLifecycle.parseEnrollmentDate(student) ??
      DateTime(1900, 1, 1);
  String _dateDmy(dynamic value) {
    final v = _parseDate(value);
    if (v == null) return _text(value);
    return '${v.day.toString().padLeft(2, '0')}/${v.month.toString().padLeft(2, '0')}/${v.year}';
  }

  List<String> _dobParts(Map<String, dynamic> student) {
    final dd = _text(student['dd']);
    final mm = _text(student['mm']);
    final yyyy = _text(student['yyyy']);
    if (dd.isNotEmpty || mm.isNotEmpty || yyyy.isNotEmpty)
      return <String>[dd.padLeft(2, '0'), mm.padLeft(2, '0'), yyyy];
    final date = _parseDate(student['dob']);
    return date == null
        ? <String>['', '', '']
        : <String>[
            date.day.toString().padLeft(2, '0'),
            date.month.toString().padLeft(2, '0'),
            '${date.year}',
          ];
  }

  String _category(dynamic value) {
    final raw = _text(value).toUpperCase().replaceAll(RegExp(r'\s+'), '');
    if (raw == 'ST' || raw.contains('અ.જ.જા') || raw == 'S.T') return 'ST';
    if (raw == 'SC' || raw == 'S.C' || raw.contains('અ.જા')) return 'SC';
    if (raw == 'OBC' || raw.contains('બ.પં') || raw.contains('બક્ષીપંચ'))
      return 'OBC';
    return 'OTHER';
  }

  String _categoryLabel(dynamic value) => const <String, String>{
        'SC': 'અ. જા.',
        'ST': 'અ.જ.જા.',
        'OBC': 'બક્ષીપંચ',
        'OTHER': 'અન્ય',
      }[_category(value)]!;
  String _gender(Map<String, dynamic> student, String type) {
    if (type == 'boys') return 'BOYS';
    if (type == 'girls') return 'GIRLS';
    final raw = _text(student['gender']).toUpperCase();
    if (const <String>{
      'BOYS',
      'BOY',
      'MALE',
      'M',
      'KUMAR',
      'કુમાર',
    }.contains(raw)) return 'BOYS';
    if (const <String>{
      'GIRLS',
      'GIRL',
      'FEMALE',
      'F',
      'KANYA',
      'કન્યા',
    }.contains(raw)) return 'GIRLS';
    return 'UNSPECIFIED';
  }

  String _genderLabel(Map<String, dynamic> student, String type) =>
      switch (_gender(student, type)) {
        'BOYS' => 'કુમાર',
        'GIRLS' => 'કન્યા',
        _ => '',
      };
  String _leavingReason(Map<String, dynamic> student) =>
      AttendanceLifecycle.parseExitReason(student);

  bool _continuousAbsence(String reason) =>
      AttendanceLifecycle.isContinuousAbsenceReason(reason);

  bool _isLeavingCertificate(String reason) {
    final text = reason.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    return text.contains('leavingcertificate') ||
        text == 'lc' ||
        text.contains('લિવિંગસર્ટિફિકેટ') ||
        text.contains('લીવિંગસર્ટિફિકેટ') ||
        text.contains('લિ.સર્ટી') ||
        text.contains('લ.સર્ટી');
  }

  String _gujaratiDigits(String value) => value
      .replaceAll('0', '૦')
      .replaceAll('1', '૧')
      .replaceAll('2', '૨')
      .replaceAll('3', '૩')
      .replaceAll('4', '૪')
      .replaceAll('5', '૫')
      .replaceAll('6', '૬')
      .replaceAll('7', '૭')
      .replaceAll('8', '૮')
      .replaceAll('9', '૯');
  static String _escapeXml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
  static String _columnOfRef(String ref) =>
      RegExp(r'^[A-Z]+').firstMatch(ref)!.group(0)!;
  String _columnLetters(int n) {
    var value = n;
    var output = '';
    while (value > 0) {
      final rem = (value - 1) % 26;
      output = String.fromCharCode(65 + rem) + output;
      value = (value - 1) ~/ 26;
    }
    return output;
  }

  static int _columnNumber(String value) {
    var out = 0;
    for (final code in value.codeUnits) {
      out = out * 26 + code - 64;
    }
    return out;
  }
}

import 'dart:convert';
import 'dart:ui' as ui;
import 'package:excel_community/excel_community.dart' as ec;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'datewise_report_columns.dart';
import 'school_class_order.dart';
import 'school_type.dart';
import 'xlsx_sanitizer.dart';

class _TarijComputedRow {
  final String label;
  final bool isTotal;
  final Map<String, int> opening;
  final Map<String, int> admissions;
  final Map<String, int> exits;
  final Map<String, int> lcExits;
  final Map<String, int> absenceExits;
  final Map<String, int> closing;
  final int workingDays;
  final int mdmDays;
  final int tithiDays;
  final bool individualsComplete;
  final int perfectAttendanceCount;
  final Map<String, int> perfect100;
  final Map<String, int> age5to6;
  final Map<String, int> age6to14;
  final Map<String, int> ageAbove14;
  final Map<String, int> aadhaar;
  final Map<String, int> minority;
  final int libraryBooks;
  final Map<String, int> registeredDays;
  final Map<String, int> presentDays;
  final Map<String, int> mdmStudentDays;
  final Map<String, double> avgPresent;
  final Map<String, double> avgMdm;

  const _TarijComputedRow({
    required this.label,
    required this.isTotal,
    required this.opening,
    required this.admissions,
    required this.exits,
    this.lcExits = const <String, int>{},
    this.absenceExits = const <String, int>{},
    required this.closing,
    required this.workingDays,
    required this.mdmDays,
    required this.tithiDays,
    required this.individualsComplete,
    required this.perfectAttendanceCount,
    required this.perfect100,
    required this.age5to6,
    required this.age6to14,
    required this.ageAbove14,
    required this.aadhaar,
    required this.minority,
    required this.libraryBooks,
    required this.registeredDays,
    required this.presentDays,
    required this.mdmStudentDays,
    required this.avgPresent,
    required this.avgMdm,
  });

  double attendancePct(String key) {
    final reg = registeredDays[key] ?? 0;
    final pres = presentDays[key] ?? 0;
    if (reg <= 0) return 0.0;
    return (pres * 100.0) / reg;
  }
}

/// Template-based report exporters for the Supabase Reports workspace.
/// Workbook templates are copied into app assets so borders, merged headers,
/// column widths, row heights and print settings survive report generation.
class SupabaseReportExportService {
  static const String _datewiseTemplate = 'assets/report_templates/datewise_template.xlsx';
  static const String _monthlyTemplate = 'assets/report_templates/tarij_combined_template.xlsx';

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) return value.map((key, value) => MapEntry('$key', value));
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry('$key', value));
        }
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value') ?? 0;
  }

  String _text(dynamic value) => (value ?? '').toString().trim();

  String _dateLabel(String iso) {
    final parts = iso.split('-');
    return parts.length == 3 ? '${parts[2]}-${parts[1]}-${parts[0]}' : iso;
  }

  String _weekday(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '';
    const days = <String>['સોમવાર', 'મંગળવાર', 'બુધવાર', 'ગુરુવાર', 'શુક્રવાર', 'શનિવાર', 'રવિવાર'];
    return days[parsed.weekday - 1];
  }

  String _classLabel(Map<String, dynamic> row) =>
      _text(row['class_label'] ?? row['label'] ?? row['class_key'] ?? row['sheet_name']);

  bool _hasDay(Map<String, dynamic> row) => _text(row['attendance_date']).isNotEmpty;

  Map<String, dynamic> _genderBreakdown(Map<String, dynamic> row) => _map(row['gender_breakdown']);

  int _valueFor(Map<String, dynamic> row, DateWiseReportColumn column) {
    final rowSchoolType = DateWiseReportColumn.normalizeSchoolType(
      row['school_type'] ?? row['schoolType'],
    );
    if (column.metric == 'breakfast' && column.category == 'CATEGORY_TOTAL') {
      if (column.gender == 'TOTAL') {
        return _int(row['breakfast_total']);
      }
      if (rowSchoolType == 'boys' && column.gender == 'BOYS') {
        return _int(row['breakfast_total']);
      }
      if (rowSchoolType == 'girls' && column.gender == 'GIRLS') {
        return _int(row['breakfast_total']);
      }
    }
    final rawBreakdown = _genderBreakdown(row);
    final schoolType = rowSchoolType;
    const categories = <String>['SC', 'ST', 'OBC', 'OTHER'];

    Map<String, dynamic> breakdown = rawBreakdown;
    if (rawBreakdown.isNotEmpty && (schoolType == 'boys' || schoolType == 'girls')) {
      final adjusted = Map<String, dynamic>.from(rawBreakdown);
      final unspecifiedPayload = _map(adjusted['UNSPECIFIED']);
      if (unspecifiedPayload.isNotEmpty) {
        final targetGender = schoolType == 'girls' ? 'GIRLS' : 'BOYS';
        final targetPayload = _map(adjusted[targetGender]);
        for (final key in <String>['SC', 'ST', 'OBC', 'OTHER', '_OVERALL']) {
          final targetCounts = _map(targetPayload[key]);
          final unspecifiedCounts = _map(unspecifiedPayload[key]);
          for (final metric in <String>['registered', 'present', 'mdm', 'breakfast']) {
            targetCounts[metric] = _int(targetCounts[metric]) + _int(unspecifiedCounts[metric]);
          }
          targetPayload[key] = targetCounts;
        }
        adjusted[targetGender] = targetPayload;
      }
      breakdown = adjusted;
    }

    int byGender(String gender, String category) {
      final group = _map(breakdown[gender]);
      if (category == 'CATEGORY_TOTAL') {
        final overall = _map(group['_OVERALL']);
        final fromCats = categories.fold<int>(0, (sum, key) => sum + byGender(gender, key));
        if (fromCats > 0) return fromCats;
        if (overall.containsKey(column.metric)) return _int(overall[column.metric]);
        return 0;
      }
      return _int(_map(group[category])[column.metric]);
    }

    final unspecCatTotal = (schoolType == 'boys' || schoolType == 'girls')
        ? 0
        : byGender('UNSPECIFIED', 'CATEGORY_TOTAL');
    final breakdownMetricTotal =
        byGender('BOYS', 'CATEGORY_TOTAL') +
        byGender('GIRLS', 'CATEGORY_TOTAL') +
        unspecCatTotal;
    final breakdownRegTotal = categories.fold<int>(
      0,
      (sum, cat) =>
          sum +
          _int(_map(_map(breakdown['BOYS'])[cat])['registered']) +
          _int(_map(_map(breakdown['GIRLS'])[cat])['registered']) +
          ((schoolType == 'boys' || schoolType == 'girls')
              ? 0
              : _int(_map(_map(breakdown['UNSPECIFIED'])[cat])['registered'])),
    );

    if (breakdown.isNotEmpty && (breakdownMetricTotal > 0 || breakdownRegTotal > 0)) {
      if (column.gender == 'TOTAL') {
        final unspecVal = (schoolType == 'boys' || schoolType == 'girls')
            ? 0
            : byGender('UNSPECIFIED', column.category);
        return byGender('BOYS', column.category) +
            byGender('GIRLS', column.category) +
            unspecVal;
      }
      return byGender(column.gender, column.category);
    }

    final source = switch (column.metric) {
      'registered' => _map(row['registered_counts']),
      'present' => _map(row['present_counts']),
      'mdm' => _map(row['mdm_counts']),
      _ => <String, dynamic>{},
    };
    int totalForCategory() {
      if (column.metric == 'breakfast') {
        return column.category == 'CATEGORY_TOTAL' ? _int(row['breakfast_total']) : 0;
      }
      if (column.category == 'CATEGORY_TOTAL') {
        return categories.fold<int>(0, (sum, key) => sum + _int(source[key]));
      }
      return _int(source[column.category]);
    }

    final total = totalForCategory();
    if (column.gender == 'TOTAL') return total;
    if (schoolType == 'girls') {
      return column.gender == 'GIRLS' ? total : 0;
    }
    if (schoolType == 'boys') {
      return column.gender == 'BOYS' ? total : 0;
    }
    return 0;
  }

  int _dailyDatewiseValue(
    Map<String, dynamic> row,
    DateWiseReportColumn column,
  ) =>
      _valueFor(row, column);

  void _setText(ec.Sheet sheet, int rowIndex, int columnIndex, String value) {
    sheet.cell(ec.CellIndex.indexByColumnRow(rowIndex: rowIndex, columnIndex: columnIndex)).value = ec.TextCellValue(value);
  }

  void _setInt(ec.Sheet sheet, int rowIndex, int columnIndex, int value) {
    sheet.cell(ec.CellIndex.indexByColumnRow(rowIndex: rowIndex, columnIndex: columnIndex)).value = ec.IntCellValue(value);
  }

  void _clearCell(ec.Sheet sheet, int rowIndex, int columnIndex) {
    sheet.cell(ec.CellIndex.indexByColumnRow(rowIndex: rowIndex, columnIndex: columnIndex)).value = null;
  }

  Future<ec.Excel> _loadTemplate(String path) async {
    final data = await rootBundle.load(path);
    return ec.Excel.decodeBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }

  Uint8List _save(ec.Excel excel) {
    final bytes = excel.encode(); // encode(): no extra auto-download on web
    if (bytes == null || bytes.isEmpty) throw StateError('Could not create the Excel report file.');
    // Remove print-area names / formula chain left over from deleted
    // template sheets, which make Microsoft Excel report the file as damaged.
    return XlsxSanitizer.clean(Uint8List.fromList(bytes));
  }

  void _keepOnly(ec.Excel excel, Set<String> keep) {
    for (final name in excel.sheets.keys.toList()) {
      if (!keep.contains(name)) excel.delete(name);
    }
  }

  void _copyRowStyle(ec.Sheet sheet, int sourceRow, int targetRow, int columnCount) {
    if (sourceRow == targetRow) return;
    for (var columnIndex = 0; columnIndex < columnCount; columnIndex++) {
      final sourceCell = sheet.cell(ec.CellIndex.indexByColumnRow(
        rowIndex: sourceRow,
        columnIndex: columnIndex,
      ));
      final targetCell = sheet.cell(ec.CellIndex.indexByColumnRow(
        rowIndex: targetRow,
        columnIndex: columnIndex,
      ));
      final sourceStyle = sourceCell.cellStyle;
      if (sourceStyle != null) targetCell.cellStyle = sourceStyle;
    }
  }

  void _rewriteRemainingColumnHeaders(ec.Sheet sheet, int firstColumn, Set<String> selectedKeys) {
    final remainingColumns = DateWiseReportColumn.all
        .where((c) => selectedKeys.contains(c.key))
        .toList();
    String prevMetric = '';
    String prevCat = '';
    for (var cIdx = 0; cIdx < remainingColumns.length; cIdx++) {
      final col = remainingColumns[cIdx];
      final excelCol = firstColumn + cIdx;
      if (col.metric != prevMetric) {
        final mTitle = switch (col.metric) {
          'registered' => 'રજીસ્ટરર્ડ વિદ્યાર્થીઓની સંખ્યા',
          'present' => 'હાજર વિદ્યાર્થીઓની સંખ્યા',
          'mdm' => 'પીએમ પોષણ યોજનામાં ભાગ લીધેલ વિદ્યાર્થીઓની સંખ્યા',
          'breakfast' => 'સીએમ અલ્પાહાર યોજનામાં ભાગ  લીધેલ વિદ્યાર્થીઓની સંખ્યા',
          _ => col.metric,
        };
        _setText(sheet, 2, excelCol, mTitle);
        prevMetric = col.metric;
        prevCat = '';
      }
      if (col.category != prevCat) {
        final cTitle = switch (col.category) {
          'SC' => 'અ. જા. ',
          'ST' => 'અ. જ. જા.',
          'OBC' => 'બક્ષીપંચ',
          'OTHER' => 'અન્ય',
          'CATEGORY_TOTAL' => 'કુલ',
          _ => col.category,
        };
        _setText(sheet, 3, excelCol, cTitle);
        prevCat = col.category;
      }
      final gTitle = switch (col.gender) {
        'BOYS' => 'કુમાર ',
        'GIRLS' => 'કન્યા ',
        'TOTAL' => 'કુલ ',
        _ => col.gender,
      };
      _setText(sheet, 4, excelCol, gTitle);
    }
  }

  void _removeUnselectedDataColumns(ec.Sheet sheet, int firstColumn, Set<String> selectedKeys) {
    for (var index = DateWiseReportColumn.all.length - 1; index >= 0; index--) {
      if (!selectedKeys.contains(DateWiseReportColumn.all[index].key)) {
        sheet.removeColumn(firstColumn + index);
      }
    }
    _rewriteRemainingColumnHeaders(sheet, firstColumn, selectedKeys);
  }

  String _resolveSchoolTypeFromRowSets(List<Iterable<Map<String, dynamic>>> rowSets) {
    for (final set in rowSets) {
      for (final row in set) {
        final raw = _text(row['school_type'] ?? row['schoolType']);
        if (raw.isNotEmpty) {
          return DateWiseReportColumn.normalizeSchoolType(raw);
        }
      }
    }
    return 'mixed';
  }

  Set<String> _normaliseSelection(
    Iterable<String> keys, {
    List<Iterable<Map<String, dynamic>>> rowSets = const <Iterable<Map<String, dynamic>>>[],
  }) {
    final schoolType = _resolveSchoolTypeFromRowSets(rowSets);
    return DateWiseReportColumn.filterColumnKeysForSchoolType(keys, schoolType).toSet();
  }

  /// Returns the list of (Category, Gender) pairs enabled by Admin's column selection
  /// and automatically constrained by the school's registered school_type (Only Boys / Only Girls / Boys+Girls+Total).
  List<(String, String)> _enabledCategoryGenderPairs(
    Iterable<String> visibleColumnKeys, {
    List<Iterable<Map<String, dynamic>>> rowSets = const <Iterable<Map<String, dynamic>>>[],
  }) {
    final schoolType = _resolveSchoolTypeFromRowSets(rowSets);
    final selected = _normaliseSelection(visibleColumnKeys, rowSets: rowSets);
    const categories = <String>['SC', 'ST', 'OBC', 'OTHER', 'TOTAL'];
    final genders = schoolType == 'boys'
        ? const <String>['BOYS']
        : schoolType == 'girls'
            ? const <String>['GIRLS']
            : const <String>['BOYS', 'GIRLS', 'TOTAL'];
    final pairs = <(String, String)>[];
    for (final cat in categories) {
      final catKey = cat == 'TOTAL' ? 'category_total' : cat.toLowerCase();
      for (final gen in genders) {
        final genKey = gen.toLowerCase();
        final anyMatch = selected.contains('registered_${catKey}_$genKey') ||
            selected.contains('present_${catKey}_$genKey') ||
            selected.contains('mdm_${catKey}_$genKey');
        if (anyMatch) {
          pairs.add((cat, gen));
        }
      }
    }
    if (pairs.isEmpty) {
      for (final cat in categories) {
        for (final gen in genders) {
          pairs.add((cat, gen));
        }
      }
    }
    return pairs;
  }

  List<String> _enabledGenders(
    Iterable<String> visibleColumnKeys, {
    List<Iterable<Map<String, dynamic>>> rowSets = const <Iterable<Map<String, dynamic>>>[],
  }) {
    final schoolType = _resolveSchoolTypeFromRowSets(rowSets);
    if (schoolType == 'boys') return const <String>['BOYS'];
    if (schoolType == 'girls') return const <String>['GIRLS'];
    final pairs = _enabledCategoryGenderPairs(visibleColumnKeys, rowSets: rowSets);
    final set = pairs.map((p) => p.$2).toSet();
    final ordered = <String>[
      if (set.contains('BOYS')) 'BOYS',
      if (set.contains('GIRLS')) 'GIRLS',
      if (set.contains('TOTAL')) 'TOTAL',
    ];
    return ordered.isEmpty ? const <String>['BOYS', 'GIRLS', 'TOTAL'] : ordered;
  }

  Future<Uint8List> exportDatewiseXlsx({
    required String schoolName,
    String schoolAddress = '',
    required String date,
    required String attendanceSerial,
    required List<Map<String, dynamic>> classRows,
    required Iterable<String> visibleColumnKeys,
  }) async {
    final workbook = await _loadTemplate(_datewiseTemplate);
    final sheet = workbook['DATEWISE'];
    final selected = _normaliseSelection(visibleColumnKeys, rowSets: [classRows]);
    final selectedColumns = DateWiseReportColumn.all
        .where((column) => selected.contains(column.key))
        .toList();
    _keepOnly(workbook, <String>{'DATEWISE'});

    final address = schoolAddress.trim();
    _setText(sheet, 0, 0, address.isEmpty ? schoolName : '$schoolName\n$address');
    _setText(
      sheet,
      1,
      0,
      'પીએમ પોષણ અને સીએમ અલ્પાહાર યોજના — દૈનિક હાજરી અહેવાલ  |  તારીખ: ${_dateLabelGujarati(date)}  |  વાર: ${_weekday(date)}',
    );
    sheet.setRowHeight(0, address.isEmpty ? 30.75 : 42.0);
    sheet.setRowHeight(1, selectedColumns.length > 32 ? 38.0 : 34.0);

    final ordered = SchoolClassOrder.sorted(classRows);
    final balvatika = ordered
        .where((row) => SchoolClassOrder.groupOf(row) == SchoolClassOrder.balvatika)
        .toList();
    final std1to5 = ordered
        .where((row) => SchoolClassOrder.groupOf(row) == SchoolClassOrder.standards1to5)
        .toList();
    final std6to8 = ordered
        .where((row) => SchoolClassOrder.groupOf(row) == SchoolClassOrder.standards6to8)
        .toList();
    final other = ordered.where((row) {
      final group = SchoolClassOrder.groupOf(row);
      return group != SchoolClassOrder.balvatika &&
          group != SchoolClassOrder.standards1to5 &&
          group != SchoolClassOrder.standards6to8;
    }).toList();

    final visibleSubtotalRows =
        (balvatika.length > 1 ? 1 : 0) +
        (std1to5.isNotEmpty ? 1 : 0) +
        ((balvatika.isNotEmpty || std1to5.isNotEmpty) ? 1 : 0) +
        (std6to8.isNotEmpty ? 1 : 0) +
        ((std1to5.isNotEmpty || std6to8.isNotEmpty) ? 1 : 0) +
        (ordered.isNotEmpty ? 1 : 0);
    final reportBodyRowCount = ordered.length + visibleSubtotalRows;
    final targetBodyRowHeight = (390.0 / (reportBodyRowCount < 1 ? 1 : reportBodyRowCount))
        .clamp(10.5, 27.0)
        .toDouble();

    final earlyClasses = <Map<String, dynamic>>[...balvatika, ...std1to5];
    const earlySlotCount = 12;
    const upperSlotCount = 6;
    final earlyFixed = earlyClasses.take(earlySlotCount).toList();
    final earlyExtras = earlyClasses.skip(earlySlotCount).toList();
    final upperFixed = std6to8.take(upperSlotCount).toList();
    final upperExtras = std6to8.skip(upperSlotCount).toList();

    for (var i = 0; i < upperExtras.length; i++) {
      sheet.insertRow(26 + i);
    }
    for (var i = 0; i < earlyExtras.length; i++) {
      sheet.insertRow(17 + i);
    }
    for (var i = 0; i < other.length; i++) {
      sheet.insertRow(28 + earlyExtras.length + upperExtras.length + i);
    }

    void clearDataCells(int rowIndex) {
      _clearCell(sheet, rowIndex, 3);
      for (var columnIndex = 4; columnIndex < 64; columnIndex++) {
        _clearCell(sheet, rowIndex, columnIndex);
      }
      _clearCell(sheet, rowIndex, 64);
    }

    void writeClassValues(int rowIndex, Map<String, dynamic> classRow) {
      _setText(sheet, rowIndex, 3, _classLabel(classRow));
      final hasSavedAttendance = _hasDay(classRow);
      for (final column in selectedColumns) {
        final columnIndex = 4 + DateWiseReportColumn.all.indexOf(column);
        if (column.metric != 'registered' && !hasSavedAttendance) {
          _clearCell(sheet, rowIndex, columnIndex);
        } else {
          _setInt(sheet, rowIndex, columnIndex, _dailyDatewiseValue(classRow, column));
        }
      }
    }

    void styleExtraRow(int targetRow, int sourceRow) {
      for (var columnIndex = 0; columnIndex < 65; columnIndex++) {
        final source = sheet.cell(ec.CellIndex.indexByColumnRow(
          rowIndex: sourceRow,
          columnIndex: columnIndex,
        ));
        final target = sheet.cell(ec.CellIndex.indexByColumnRow(
          rowIndex: targetRow,
          columnIndex: columnIndex,
        ));
        final sourceStyle = source.cellStyle;
        if (sourceStyle != null) target.cellStyle = sourceStyle;
        if (columnIndex >= 3) _clearCell(sheet, targetRow, columnIndex);
      }
    }

    void writeExtraRow(int rowIndex, Map<String, dynamic> classRow, int sourceRow) {
      styleExtraRow(rowIndex, sourceRow);
      writeClassValues(rowIndex, classRow);
      _setRowHeightForClass(sheet, rowIndex, _classLabel(classRow), baseHeight: targetBodyRowHeight);
    }

    if (attendanceSerial.trim().isEmpty) {
      _clearCell(sheet, 5, 0);
    } else {
      _setText(sheet, 5, 0, attendanceSerial.trim());
    }

    for (var i = 0; i < earlySlotCount; i++) {
      final rowIndex = 5 + i;
      clearDataCells(rowIndex);
      if (i < earlyFixed.length) {
        sheet.setRowHidden(rowIndex, false);
        writeClassValues(rowIndex, earlyFixed[i]);
        _setRowHeightForClass(sheet, rowIndex, _classLabel(earlyFixed[i]), baseHeight: targetBodyRowHeight);
      } else {
        sheet.setRowHidden(rowIndex, true);
      }
    }

    for (var i = 0; i < earlyExtras.length; i++) {
      final rowIndex = 17 + i;
      writeExtraRow(rowIndex, earlyExtras[i], 5);
      sheet.setRowHidden(rowIndex, false);
    }

    final upperBase = 20 + earlyExtras.length;
    for (var i = 0; i < upperSlotCount; i++) {
      final rowIndex = upperBase + i;
      clearDataCells(rowIndex);
      if (i < upperFixed.length) {
        sheet.setRowHidden(rowIndex, false);
        writeClassValues(rowIndex, upperFixed[i]);
        _setRowHeightForClass(sheet, rowIndex, _classLabel(upperFixed[i]), baseHeight: targetBodyRowHeight);
      } else {
        sheet.setRowHidden(rowIndex, true);
      }
    }
    for (var i = 0; i < upperExtras.length; i++) {
      final rowIndex = 26 + earlyExtras.length + i;
      writeExtraRow(rowIndex, upperExtras[i], upperBase);
      sheet.setRowHidden(rowIndex, false);
    }

    final otherBase = 28 + earlyExtras.length + upperExtras.length;
    for (var i = 0; i < other.length; i++) {
      final rowIndex = otherBase + i;
      writeExtraRow(rowIndex, other[i], 5);
      sheet.setRowHidden(rowIndex, false);
    }

    final balvatikaTotalRow = 17 + earlyExtras.length;
    final std1to5TotalRow = 18 + earlyExtras.length;
    final bvTo5TotalRow = 19 + earlyExtras.length;
    final std6to8TotalRow = 26 + earlyExtras.length + upperExtras.length;
    final std1to8TotalRow = 27 + earlyExtras.length + upperExtras.length;
    final wholeSchoolTotalRow = 28 + earlyExtras.length + upperExtras.length + other.length;

    final totals = <(int, String, List<Map<String, dynamic>>)>[
      (balvatikaTotalRow, 'કુલ બાલવાટિકા', balvatika),
      (std1to5TotalRow, 'કુલ ધોરણ 1 થી 5', std1to5),
      (bvTo5TotalRow, 'કુલ બાલવાટિકા થી ધોરણ 5', <Map<String, dynamic>>[...balvatika, ...std1to5]),
      (std6to8TotalRow, 'કુલ ધોરણ 6 થી 8', std6to8),
      (std1to8TotalRow, 'કુલ ધોરણ 1 થી 8', <Map<String, dynamic>>[...std1to5, ...std6to8]),
      (wholeSchoolTotalRow, 'કુલ શાળા', ordered),
    ];

    for (final entry in totals) {
      final rowIndex = entry.$1;
      final label = entry.$2;
      final includedClasses = entry.$3;
      for (var columnIndex = 4; columnIndex < 64; columnIndex++) {
        _clearCell(sheet, rowIndex, columnIndex);
      }
      _setText(sheet, rowIndex, 3, label);
      final showBalvatikaTotal = label != 'કુલ બાલવાટિકા' || balvatika.length > 1;
      sheet.setRowHidden(rowIndex, !showBalvatikaTotal || includedClasses.isEmpty);
      if (!showBalvatikaTotal || includedClasses.isEmpty) continue;

      for (final column in selectedColumns) {
        final eligibleClasses = column.metric == 'registered'
            ? includedClasses
            : includedClasses.where(_hasDay).toList();
        if (eligibleClasses.isEmpty) continue;
        var total = 0;
        for (final classRow in eligibleClasses) {
          total += _dailyDatewiseValue(classRow, column);
        }
        _setInt(sheet, rowIndex, 4 + DateWiseReportColumn.all.indexOf(column), total);
      }
      sheet.setRowHeight(rowIndex, targetBodyRowHeight);
    }

    final columnWidth = selectedColumns.length > 42
        ? 6.2
        : selectedColumns.length > 28
            ? 7.0
            : selectedColumns.length > 16
                ? 8.2
                : selectedColumns.length > 8
                    ? 9.5
                    : 11.0;
    sheet.setColumnWidth(0, 4.5);
    sheet.setColumnWidth(1, 10.0);
    sheet.setColumnWidth(2, 11.0);
    final classColumnWidth = selectedColumns.length > 42
        ? 14.0
        : selectedColumns.length > 28
            ? 18.0
            : selectedColumns.length > 16
                ? 23.0
                : selectedColumns.length > 8
                    ? 30.0
                    : 38.0;
    sheet.setColumnWidth(3, classColumnWidth);
    for (var columnIndex = 4; columnIndex < 64; columnIndex++) {
      sheet.setColumnWidth(columnIndex, columnWidth);
    }
    sheet.setColumnWidth(64, 15.0);

    final headerFontSize = selectedColumns.length > 42
        ? 5
        : selectedColumns.length > 28
            ? 6
            : selectedColumns.length > 16
                ? 7
                : 8;
    final bodyFontSize = selectedColumns.length > 42 || reportBodyRowCount > 32
        ? 7
        : selectedColumns.length > 28 || reportBodyRowCount > 25
            ? 8
            : selectedColumns.length > 16
                ? 9
                : 10;
    final lastReportRow = wholeSchoolTotalRow;
    for (var rowIndex = 0; rowIndex <= lastReportRow; rowIndex++) {
      final isHeader = rowIndex >= 2 && rowIndex <= 4;
      final fontSize = rowIndex == 0 ? 12 : rowIndex == 1 ? 10 : isHeader ? headerFontSize : bodyFontSize;
      for (var columnIndex = 0; columnIndex < 65; columnIndex++) {
        final cell = sheet.cell(ec.CellIndex.indexByColumnRow(
          rowIndex: rowIndex,
          columnIndex: columnIndex,
        ));
        final style = cell.cellStyle;
        if (style != null) {
          cell.cellStyle = style.copyWith(
            textWrappingVal: ec.TextWrapping.WrapText,
            verticalAlignVal: ec.VerticalAlign.Center,
            fontSizeVal: fontSize,
          );
        }
      }
    }
    sheet.setRowHeight(2, 35.0);
    sheet.setRowHeight(3, selectedColumns.length > 24 ? 34.0 : 30.0);
    sheet.setRowHeight(4, selectedColumns.length > 24 ? 30.0 : 27.0);
    for (var rowIndex = lastReportRow + 1;
        rowIndex < 939 + earlyExtras.length + upperExtras.length + other.length;
        rowIndex++) {
      sheet.setRowHidden(rowIndex, true);
    }

    for (var index = DateWiseReportColumn.all.length - 1; index >= 0; index--) {
      final columnIndex = 4 + index;
      final key = DateWiseReportColumn.all[index].key;
      if (selected.contains(key)) {
        sheet.setColumnHidden(columnIndex, false);
      } else {
        sheet.removeColumn(columnIndex);
      }
    }
    _rewriteRemainingColumnHeaders(sheet, 4, selected);
    sheet.removeColumn(2);
    sheet.removeColumn(1);

    return _save(workbook);
  }

  void _setRowHeightForClass(
    ec.Sheet sheet,
    int rowIndex,
    String label, {
    double baseHeight = 23.0,
  }) {
    final height = label.length > 20 ? baseHeight + 2.0 : baseHeight;
    sheet.setRowHeight(rowIndex, height.clamp(10.5, 29.0).toDouble());
  }

  String _dateLabelGujarati(String iso) {
    const digits = <String>['૦', '૧', '૨', '૩', '૪', '૫', '૬', '૭', '૮', '૯'];
    return _dateLabel(iso).split('').map((char) {
      final index = int.tryParse(char);
      return index == null ? char : digits[index];
    }).join();
  }

  Future<Uint8List> exportClasswiseAllDataXlsx({
    required String schoolName,
    String schoolAddress = '',
    required String fromDate,
    required String toDate,
    required List<Map<String, dynamic>> classRows,
    required List<Map<String, dynamic>> attendanceRows,
    required Iterable<String> visibleColumnKeys,
  }) async {
    final workbook = await _loadTemplate(_datewiseTemplate);
    const templateName = 'class wise for all class data';
    final selected = _normaliseSelection(visibleColumnKeys, rowSets: [classRows, attendanceRows]);
    final classNames = <String>[];
    final used = <String>{};

    for (final classRow in SchoolClassOrder.sorted(classRows)) {
      final label = _classLabel(classRow);
      var name = label.replaceAll(RegExp(r'[\\/:?*\[\]]'), ' ').trim();
      if (name.isEmpty) name = 'Class';
      if (name.length > 31) name = name.substring(0, 31);
      final root = name;
      var suffix = 2;
      while (used.contains(name.toLowerCase()) || name.toLowerCase() == templateName.toLowerCase()) {
        final ending = ' ($suffix)';
        name = '${root.substring(0, root.length > 31 - ending.length ? 31 - ending.length : root.length)}$ending';
        suffix++;
      }
      used.add(name.toLowerCase());
      workbook.copy(templateName, name);
      final sheet = workbook[name];
      classNames.add(name);
      final headerName = schoolAddress.trim().isEmpty
          ? schoolName
          : '$schoolName, ${schoolAddress.trim()}';
      _setText(sheet, 0, 0, headerName);
      _setText(sheet, 1, 0, 'પીએમ પોષણ અને સીએમ અલ્પાહાર યોજના — $label');
      for (var rowIndex = 5; rowIndex < 421; rowIndex++) {
        _clearCell(sheet, rowIndex, 0);
        _clearCell(sheet, rowIndex, 1);
        for (var colIndex = 2; colIndex < 62; colIndex++) {
          _clearCell(sheet, rowIndex, colIndex);
        }
      }
      final classId = _text(classRow['class_id'] ?? classRow['id']);
      final data = attendanceRows.where((row) => _text(row['class_id']) == classId && _hasDay(row)).toList()
        ..sort((a, b) => _text(a['attendance_date']).compareTo(_text(b['attendance_date'])));
      for (var index = 0; index < data.length; index++) {
        final rowIndex = 5 + index;
        if (rowIndex > 420) _copyRowStyle(sheet, 5, rowIndex, 62);
        final record = data[index];
        _setInt(sheet, rowIndex, 0, index + 1);
        _setText(sheet, rowIndex, 1, _dateLabel(_text(record['attendance_date'])));
        for (final column in DateWiseReportColumn.all) {
          final colIndex = 2 + DateWiseReportColumn.all.indexOf(column);
          _setInt(sheet, rowIndex, colIndex, _valueFor(record, column));
        }
      }

      final totalRow = 5 + data.length;
      _copyRowStyle(sheet, 5, totalRow, 62);
      _setText(sheet, totalRow, 1, 'કુલ');
      for (final column in DateWiseReportColumn.all) {
        final columnIndex = 2 + DateWiseReportColumn.all.indexOf(column);
        final total = data.fold<int>(0, (sum, record) => sum + _valueFor(record, column));
        _setInt(sheet, totalRow, columnIndex, total);
      }

      _removeUnselectedDataColumns(sheet, 2, selected);
      final remainingColumns = DateWiseReportColumn.all
          .where((c) => selected.contains(c.key))
          .toList();
      String prevMetric = '';
      String prevCat = '';
      for (var cIdx = 0; cIdx < remainingColumns.length; cIdx++) {
        final col = remainingColumns[cIdx];
        final excelCol = 2 + cIdx;
        if (col.metric != prevMetric) {
          final mTitle = switch (col.metric) {
            'registered' => 'રજીસ્ટરર્ડ વિદ્યાર્થીઓની સંખ્યા',
            'present' => 'હાજર વિદ્યાર્થીઓની સંખ્યા',
            'mdm' => 'પીએમ પોષણ યોજનામાં ભાગ લીધેલ વિદ્યાર્થીઓની સંખ્યા',
            'breakfast' => 'સીએમ અલ્પાહાર યોજનામાં ભાગ  લીધેલ વિદ્યાર્થીઓની સંખ્યા',
            _ => col.metric,
          };
          _setText(sheet, 2, excelCol, mTitle);
          prevMetric = col.metric;
          prevCat = '';
        }
        if (col.category != prevCat) {
          final cTitle = switch (col.category) {
            'SC' => 'અ. જા. ',
            'ST' => 'અ. જ. જા.',
            'OBC' => 'બક્ષીપંચ',
            'OTHER' => 'અન્ય',
            'CATEGORY_TOTAL' => 'કુલ',
            _ => col.category,
          };
          _setText(sheet, 3, excelCol, cTitle);
          prevCat = col.category;
        }
        final gTitle = switch (col.gender) {
          'BOYS' => 'કુમાર ',
          'GIRLS' => 'કન્યા ',
          'TOTAL' => 'કુલ ',
          _ => col.gender,
        };
        _setText(sheet, 4, excelCol, gTitle);
      }
      sheet.setColumnHidden(0, false);
      sheet.setColumnHidden(1, false);
    }

    if (classNames.isEmpty) throw StateError('No active school classes were returned.');
    for (final name in workbook.sheets.keys.toList()) {
      if (!classNames.contains(name)) workbook.delete(name);
    }
    return _save(workbook);
  }

  static String _matchUploadMetricHeader(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    if (t.contains('રજીસ્ટર')) return 'registered';
    if (t.contains('હાજર')) return 'present';
    if (t.contains('પીએમ પોષણ') || t.contains('પોષણ')) return 'mdm';
    if (t.contains('અલ્પાહાર')) return 'breakfast';
    return 'INVALID';
  }

  static String _matchUploadCategoryHeader(String raw) {
    final t = raw.replaceAll(' ', '').trim();
    if (t.isEmpty) return '';
    if (t == 'અ.જ.જા.' || t == 'અ.જ.જા' || t.toUpperCase() == 'ST') return 'ST';
    if (t == 'અ.જા.' || t == 'અ.જા' || t.toUpperCase() == 'SC') return 'SC';
    if (t == 'બક્ષીપંચ' || t.toUpperCase() == 'OBC') return 'OBC';
    if (t == 'અન્ય' || t.toUpperCase() == 'OTHER') return 'OTHER';
    if (t == 'કુલ' || t.toUpperCase() == 'TOTAL') return 'CATEGORY_TOTAL';
    return 'INVALID';
  }

  static String _matchUploadGenderHeader(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    if (t == 'કુમાર' || t.toUpperCase() == 'BOYS') return 'BOYS';
    if (t == 'કન્યા' || t.toUpperCase() == 'GIRLS') return 'GIRLS';
    if (t == 'કુલ' || t.toUpperCase() == 'TOTAL') return 'TOTAL';
    return 'INVALID';
  }

  static String? _parseUploadDateCellToIso(String raw) {
    var clean = raw.trim();
    if (clean.isEmpty) return null;
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    for (int i = 0; i < 10; i++) {
      clean = clean.replaceAll(guj[i], '$i');
    }
    if (clean.contains('T')) {
      clean = clean.split('T').first.trim();
    } else if (clean.contains(' ')) {
      clean = clean.split(' ').first.trim();
    }
    final isoMatch = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$').firstMatch(clean);
    if (isoMatch != null) {
      final y = int.tryParse(isoMatch.group(1)!) ?? 0;
      final m = int.tryParse(isoMatch.group(2)!) ?? 0;
      final d = int.tryParse(isoMatch.group(3)!) ?? 0;
      if (y >= 2000 && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        return '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      }
    }
    final dmyMatch = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$').firstMatch(clean);
    if (dmyMatch != null) {
      final d = int.tryParse(dmyMatch.group(1)!) ?? 0;
      final m = int.tryParse(dmyMatch.group(2)!) ?? 0;
      final y = int.tryParse(dmyMatch.group(3)!) ?? 0;
      if (y >= 2000 && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        return '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      }
    }
    return null;
  }

  String _cellStr(ec.Sheet sheet, int r, int c) {
    final val = sheet
        .cell(ec.CellIndex.indexByColumnRow(rowIndex: r, columnIndex: c))
        .value;
    if (val == null) return '';
    return '$val'.trim();
  }

  int? _cellIntOrNull(ec.Sheet sheet, int r, int c) {
    final raw = _cellStr(sheet, r, c);
    if (raw.isEmpty) return null;
    var clean = raw;
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    for (int i = 0; i < 10; i++) {
      clean = clean.replaceAll(guj[i], '$i');
    }
    final asNum = num.tryParse(clean);
    if (asNum != null) return asNum.round();
    return null;
  }

  /// Strictly validates all sheet names and headers (Rows 3-5) of a
  /// `CLASSWISE_ALL_*.xlsx` workbook and parses all daily attendance records.
  /// If ANY sheet name or column header is changed, throws a [FormatException]
  /// rejecting the entire workbook.
  List<Map<String, dynamic>> parseAndValidateClasswiseAttendanceXlsx({
    required Uint8List bytes,
    required String schoolRef,
    required List<Map<String, dynamic>> classRows,
    required String schoolType,
    required String todayIso,
    String updatedByTeacherId = '',
  }) {
    final ec.Excel workbook;
    try {
      workbook = ec.Excel.decodeBytes(bytes);
    } catch (e) {
      throw const FormatException(
        '❌ ફાઈલ ખૂલી શકી નથી. કૃપા કરીને માન્ય Class-wise (.xlsx) ફાઈલ પસંદ કરો.',
      );
    }

    if (workbook.sheets.isEmpty) {
      throw const FormatException('❌ અપલોડ કરેલ Excel ફાઈલ ખાલી છે.');
    }

    const templateName = 'class wise for all class data';
    final expectedSheetToClass = <String, Map<String, dynamic>>{};
    final used = <String>{};
    for (final classRow in SchoolClassOrder.sorted(classRows)) {
      final label = _classLabel(classRow);
      var name = label.replaceAll(RegExp(r'[\\/:?*\[\]]'), ' ').trim();
      if (name.isEmpty) name = 'Class';
      if (name.length > 31) name = name.substring(0, 31);
      final root = name;
      var suffix = 2;
      while (used.contains(name.toLowerCase()) ||
          name.toLowerCase() == templateName.toLowerCase()) {
        final ending = ' ($suffix)';
        name =
            '${root.substring(0, root.length > 31 - ending.length ? 31 - ending.length : root.length)}$ending';
        suffix++;
      }
      used.add(name.toLowerCase());
      expectedSheetToClass[name] = classRow;
    }

    for (final sheetName in workbook.sheets.keys) {
      if (!expectedSheetToClass.containsKey(sheetName)) {
        throw FormatException(
          '❌ અપલોડ રિજેક્ટ (Rejected): Sheet નું નામ "$sheetName" બદલાયેલું છે અથવા શાળાના વર્ગો સાથે મેચ થતું નથી.\n'
          'માન્ય Sheet નામો: ${expectedSheetToClass.keys.join(", ")}.\n'
          'કૃપા કરીને Sheet ના નામમાં કોઈ ફેરફાર કર્યા વગર ફરી અપલોડ કરો.',
        );
      }
    }

    for (final expectedName in expectedSheetToClass.keys) {
      if (!workbook.sheets.containsKey(expectedName)) {
        throw FormatException(
          '❌ અપલોડ રિજેક્ટ (Rejected): વર્ગ "$expectedName" ની Sheet ફાઈલમાંથી કાઢી નાખવામાં આવી છે અથવા તેનું નામ બદલવામાં આવ્યું છે. આખી શાળાની મૂળ Template ફાઈલ જ અપલોડ કરો.',
        );
      }
    }

    final isGirlsSchool = SchoolType.isGirls(schoolType);
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final parsedDayPayloads = <Map<String, dynamic>>[];

    for (final entry in expectedSheetToClass.entries) {
      final sheetName = entry.key;
      final classRow = entry.value;
      final classId = _text(classRow['class_id'] ?? classRow['id']);
      final sheet = workbook.sheets[sheetName]!;

      final hdrKram = _cellStr(sheet, 2, 0);
      final hdrDate = _cellStr(sheet, 2, 1);
      if (hdrKram != 'ક્રમ' || hdrDate != 'તારીખ') {
        throw FormatException(
          '❌ અપલોડ રિજેક્ટ (Rejected): Sheet "$sheetName" માં Row 3 ના પ્રથમ બે Column Headers ("ક્રમ", "તારીખ") બદલાયેલા છે (મળેલ: "$hdrKram", "$hdrDate"). Column Headers માં કોઈ ફેરફાર કરશો નહીં.',
        );
      }

      int maxCol = sheet.maxColumns;
      if (maxCol < 3) {
        throw FormatException(
          '❌ અપલોડ રિજેક્ટ (Rejected): Sheet "$sheetName" માં હાજરીના ડેટા કૉલમ મળ્યા નથી.',
        );
      }

      // Map each column index >= 2 to (metric, category, gender)
      final colSpec = <int, (String, String, String)>{};
      String curMetric = '';
      String curCategory = '';

      for (int c = 2; c < maxCol; c++) {
        final r3 = _cellStr(sheet, 2, c);
        final r4 = _cellStr(sheet, 3, c);
        final r5 = _cellStr(sheet, 4, c);
        if (r3.isEmpty && r4.isEmpty && r5.isEmpty) {
          continue;
        }
        if (r3.isNotEmpty) {
          final m = _matchUploadMetricHeader(r3);
          if (m == 'INVALID' || m.isEmpty) {
            throw FormatException(
              '❌ અપલોડ રિજેક્ટ (Rejected): Sheet "$sheetName" માં કૉલમ ${c + 1} (Row 3) નું હેડર "$r3" બદલાયેલું છે!',
            );
          }
          curMetric = m;
          curCategory = '';
        }
        if (r4.isNotEmpty) {
          final cat = _matchUploadCategoryHeader(r4);
          if (cat == 'INVALID' || cat.isEmpty) {
            throw FormatException(
              '❌ અપલોડ રિજેક્ટ (Rejected): Sheet "$sheetName" માં કૉલમ ${c + 1} (Row 4) નું કેટેગરી હેડર "$r4" બદલાયેલું છે!',
            );
          }
          curCategory = cat;
        }
        final gen = _matchUploadGenderHeader(r5);
        if (gen == 'INVALID' || gen.isEmpty) {
          throw FormatException(
            '❌ અપલોડ રિજેક્ટ (Rejected): Sheet "$sheetName" માં કૉલમ ${c + 1} (Row 5) નું હેડર "$r5" બદલાયેલું છે (માન્ય: કુમાર / કન્યા / કુલ)!',
          );
        }
        if (curMetric == 'breakfast' && curCategory.isEmpty) {
          curCategory = 'CATEGORY_TOTAL';
        }
        if (curMetric.isEmpty || curCategory.isEmpty) {
          throw FormatException(
            '❌ અપલોડ રિજેક્ટ (Rejected): Sheet "$sheetName" માં કૉલમ ${c + 1} નું મુખ્ય કે કેટેગરી હેડર ખૂટે છે અથવા બદલાયેલું છે!',
          );
        }
        colSpec[c] = (curMetric, curCategory, gen);
      }

      if (colSpec.isEmpty) {
        throw FormatException(
          '❌ અપલોડ રિજેક્ટ (Rejected): Sheet "$sheetName" માં કોઈ માન્ય ડેટા હેડર મળ્યા નથી.',
        );
      }

      final seenDatesInSheet = <String>{};
      final maxRows = sheet.maxRows;
      for (int r = 5; r < maxRows; r++) {
        final rawDateStr = _cellStr(sheet, r, 1);
        if (rawDateStr.isEmpty ||
            rawDateStr == 'કુલ' ||
            rawDateStr.contains('કુલ') ||
            rawDateStr.contains('એકંદર')) {
          continue;
        }
        final dateIso = _parseUploadDateCellToIso(rawDateStr);
        if (dateIso == null) {
          throw FormatException(
            '❌ અપલોડ રિજેક્ટ (Rejected): Sheet "$sheetName" ની હરોળ ${r + 1} માં તારીખ "$rawDateStr" અમાન્ય છે. તારીખ DD-MM-YYYY (દા.ત. 02-11-2026) ફોર્મેટમાં લખો.',
          );
        }
        if (dateIso.compareTo(todayIso) > 0) {
          throw FormatException(
            '❌ અપલોડ રિજેક્ટ (Rejected): Sheet "$sheetName" ની હરોળ ${r + 1} માં ભવિષ્યની તારીખ ($rawDateStr) આપેલ છે. ભવિષ્યની તારીખની હાજરી અપલોડ કરી શકાતી નથી.',
          );
        }
        if (!seenDatesInSheet.add(dateIso)) {
          throw FormatException(
            '❌ અપલોડ રિજેક્ટ (Rejected): Sheet "$sheetName" માં તારીખ "$rawDateStr" બે વાર લખાયેલ છે.',
          );
        }

        // Read all mapped cells for this row
        // Structure: values[metric][category][gender]
        final values = <String, Map<String, Map<String, int>>>{
          for (final m in const <String>['registered', 'present', 'mdm', 'breakfast'])
            m: <String, Map<String, int>>{
              for (final cat in const <String>[
                'SC',
                'ST',
                'OBC',
                'OTHER',
                'CATEGORY_TOTAL',
              ])
                cat: <String, int>{},
            },
        };
        bool anyNonZeroOrPresentCell = false;
        for (final cEntry in colSpec.entries) {
          final cellVal = _cellIntOrNull(sheet, r, cEntry.key);
          if (cellVal != null) {
            if (cellVal < 0) {
              throw FormatException(
                '❌ અપલોડ રિજેક્ટ (Rejected): Sheet "$sheetName" (તારીખ $rawDateStr) માં ઋણ (Negative) સંખ્યા માન્ય નથી.',
              );
            }
            if (cellVal > 0) anyNonZeroOrPresentCell = true;
            final (m, cat, gen) = cEntry.value;
            values[m]![cat]![gen] = cellVal;
          }
        }
        if (!anyNonZeroOrPresentCell) {
          continue;
        }

        // Resolve Boys & Girls per category & metric
        const cats = <String>['SC', 'ST', 'OBC', 'OTHER'];
        const metrics = <String>['registered', 'present', 'mdm', 'breakfast'];

        final breakdown = <String, Map<String, dynamic>>{
          for (final g in const <String>['BOYS', 'GIRLS', 'UNSPECIFIED'])
            g: <String, dynamic>{
              for (final c in cats)
                c: <String, int>{
                  'registered': 0,
                  'present': 0,
                  'mdm': 0,
                  'breakfast': 0,
                },
              '_OVERALL': <String, int>{
                'registered': 0,
                'present': 0,
                'mdm': 0,
                'breakfast': 0,
              },
            },
        };

        final registeredCounts = <String, int>{
          'SC': 0,
          'ST': 0,
          'OBC': 0,
          'OTHER': 0,
        };
        final presentCounts = <String, int>{
          'SC': 0,
          'ST': 0,
          'OBC': 0,
          'OTHER': 0,
        };
        final mdmCounts = <String, int>{
          'SC': 0,
          'ST': 0,
          'OBC': 0,
          'OTHER': 0,
        };

        for (final m in metrics) {
          int sumBoys = 0;
          int sumGirls = 0;
          for (final cat in cats) {
            final gMap = values[m]![cat]!;
            int b = 0;
            int g = 0;
            if (gMap.containsKey('BOYS') || gMap.containsKey('GIRLS')) {
              b = gMap['BOYS'] ?? 0;
              g = gMap['GIRLS'] ?? 0;
            } else if (gMap.containsKey('TOTAL')) {
              if (isGirlsSchool) {
                g = gMap['TOTAL'] ?? 0;
              } else {
                b = gMap['TOTAL'] ?? 0;
              }
            }
            (breakdown['BOYS']![cat] as Map<String, int>)[m] = b;
            (breakdown['GIRLS']![cat] as Map<String, int>)[m] = g;
            sumBoys += b;
            sumGirls += g;
            final totCat = b + g;
            if (m == 'registered') registeredCounts[cat] = totCat;
            if (m == 'present') presentCounts[cat] = totCat;
            if (m == 'mdm') mdmCounts[cat] = totCat;
          }

          // Check if CATEGORY_TOTAL was provided when individual categories were 0
          final catTotMap = values[m]!['CATEGORY_TOTAL']!;
          int totBoysFromOverall = catTotMap['BOYS'] ?? 0;
          int totGirlsFromOverall = catTotMap['GIRLS'] ?? 0;
          if (!catTotMap.containsKey('BOYS') &&
              !catTotMap.containsKey('GIRLS') &&
              catTotMap.containsKey('TOTAL')) {
            if (isGirlsSchool) {
              totGirlsFromOverall = catTotMap['TOTAL'] ?? 0;
            } else {
              totBoysFromOverall = catTotMap['TOTAL'] ?? 0;
            }
          }
          final finalBoysOverall =
              (sumBoys > 0 || sumGirls > 0) ? sumBoys : totBoysFromOverall;
          final finalGirlsOverall =
              (sumBoys > 0 || sumGirls > 0) ? sumGirls : totGirlsFromOverall;
          (breakdown['BOYS']!['_OVERALL'] as Map<String, int>)[m] =
              finalBoysOverall;
          (breakdown['GIRLS']!['_OVERALL'] as Map<String, int>)[m] =
              finalGirlsOverall;
        }

        final regTotal = ((breakdown['BOYS']!['_OVERALL']
                    as Map<String, int>)['registered'] ??
                0) +
            ((breakdown['GIRLS']!['_OVERALL'] as Map<String, int>)['registered'] ??
                0);
        final presTotal = ((breakdown['BOYS']!['_OVERALL']
                    as Map<String, int>)['present'] ??
                0) +
            ((breakdown['GIRLS']!['_OVERALL'] as Map<String, int>)['present'] ??
                0);
        final mdmTotal = ((breakdown['BOYS']!['_OVERALL']
                    as Map<String, int>)['mdm'] ??
                0) +
            ((breakdown['GIRLS']!['_OVERALL'] as Map<String, int>)['mdm'] ?? 0);
        final bfTotal = ((breakdown['BOYS']!['_OVERALL']
                    as Map<String, int>)['breakfast'] ??
                0) +
            ((breakdown['GIRLS']!['_OVERALL'] as Map<String, int>)['breakfast'] ??
                0);

        if (regTotal > 0 && presTotal > regTotal) {
          throw FormatException(
            '❌ અપલોડ રિજેક્ટ (Rejected): Sheet "$sheetName" (તારીખ $rawDateStr) માં હાજર સંખ્યા ($presTotal) રજીસ્ટર સંખ્યા ($regTotal) કરતાં વધારે છે.',
          );
        }
        if (mdmTotal > presTotal) {
          throw FormatException(
            '❌ અપલોડ રિજેક્ટ (Rejected): Sheet "$sheetName" (તારીખ $rawDateStr) માં PM POSHAN સંખ્યા ($mdmTotal) હાજર સંખ્યા ($presTotal) કરતાં વધારે છે.',
          );
        }
        if (bfTotal > presTotal) {
          throw FormatException(
            '❌ અપલોડ રિજેક્ટ (Rejected): Sheet "$sheetName" (તારીખ $rawDateStr) માં અલ્પાહાર (Breakfast) સંખ્યા ($bfTotal) હાજર સંખ્યા ($presTotal) કરતાં વધારે છે.',
          );
        }

        final dayPayload = <String, dynamic>{
          'school_ref': schoolRef,
          'class_id': classId,
          'attendance_date': dateIso,
          'registered_counts': registeredCounts,
          'present_counts': presentCounts,
          'mdm_counts': mdmCounts,
          'breakfast_total': bfTotal,
          'gender_breakdown': breakdown,
          'attendance_mode': 'direct',
          'student_details_saved': false,
          'present_saved': true,
          'mdm_saved': true,
          'breakfast_saved': true,
          'present_frozen': true,
          'mdm_frozen': true,
          'breakfast_frozen': true,
          'is_frozen': true,
          'unfrozen_by_admin': false,
          'uploaded_from_excel': true,
          'updated_at': nowIso,
          if (updatedByTeacherId.isNotEmpty)
            'updated_by_teacher': updatedByTeacherId,
        };
        parsedDayPayloads.add(dayPayload);
      }
    }

    if (parsedDayPayloads.isEmpty) {
      throw const FormatException(
        '❌ અપલોડ કરેલ ફાઈલમાં કોઈપણ તારીખની હાજરીની એન્ટ્રી મળી નથી.',
      );
    }

    return parsedDayPayloads;
  }

  Future<Uint8List> exportGroupwiseXlsx({
    required String schoolName,
    String schoolAddress = '',
    required String fromDate,
    required String toDate,
    required String group,
    required List<Map<String, dynamic>> rows,
    required Iterable<String> visibleColumnKeys,
  }) async {
    final workbook = await _loadTemplate(_datewiseTemplate);
    final sheet = workbook['group wise'];
    _keepOnly(workbook, <String>{'group wise'});
    final selected = _normaliseSelection(visibleColumnKeys, rowSets: [rows]);
    final filtered = rows.where((row) => SchoolClassOrder.matches(row, group) && _hasDay(row)).toList();
    final headerName = schoolAddress.trim().isEmpty
        ? schoolName
        : '$schoolName, ${schoolAddress.trim()}';
    _setText(sheet, 0, 0, headerName);
    _setText(sheet, 1, 0, 'પીએમ પોષણ અને સીએમ અલ્પાહાર યોજના — ${SchoolClassOrder.labelFor(group)}');
    _setText(sheet, 2, 0, 'સમયગાળો: ${_dateLabel(fromDate)} થી ${_dateLabel(toDate)}');
    final byDate = _aggregateByDate(filtered);
    for (var rowIndex = 5; rowIndex < 421; rowIndex++) {
      _clearCell(sheet, rowIndex, 0);
      _clearCell(sheet, rowIndex, 1);
      for (var colIndex = 2; colIndex < 62; colIndex++) _clearCell(sheet, rowIndex, colIndex);
    }
    final dates = byDate.keys.toList()..sort();
    for (var i = 0; i < dates.length; i++) {
      final rowIndex = 5 + i;
      if (rowIndex > 420) _copyRowStyle(sheet, 5, rowIndex, 62);
      final date = dates[i];
      final aggregate = byDate[date]!;
      _setInt(sheet, rowIndex, 0, i + 1);
      _setText(sheet, rowIndex, 1, _dateLabel(date));
      for (final column in DateWiseReportColumn.all) {
        _setInt(sheet, rowIndex, 2 + DateWiseReportColumn.all.indexOf(column), _valueFor(aggregate, column));
      }
    }

    final totalRow = 5 + dates.length;
    _copyRowStyle(sheet, 5, totalRow, 62);
    _setText(sheet, totalRow, 1, 'કુલ');
    for (final column in DateWiseReportColumn.all) {
      final columnIndex = 2 + DateWiseReportColumn.all.indexOf(column);
      final total = dates.fold<int>(0, (sum, date) => sum + _valueFor(byDate[date]!, column));
      _setInt(sheet, totalRow, columnIndex, total);
    }

    _removeUnselectedDataColumns(sheet, 2, selected);
    return _save(workbook);
  }

  Future<Uint8List> exportCombineReportXlsx({
    required String schoolName,
    String schoolAddress = '',
    required String fromDate,
    required String toDate,
    required List<Map<String, dynamic>> rows,
    required Iterable<String> visibleColumnKeys,
  }) async {
    final workbook = await _loadTemplate(_monthlyTemplate);
    final sheet = workbook['COMBINE REPORT'];
    _keepOnly(workbook, <String>{'COMBINE REPORT'});
    final selected = _normaliseSelection(visibleColumnKeys, rowSets: [rows]);
    final headerName = schoolAddress.trim().isEmpty
        ? schoolName
        : '$schoolName, ${schoolAddress.trim()}';
    _setText(sheet, 0, 0, headerName);
    _setText(sheet, 1, 0, 'એકંદર પત્રક');
    _setText(sheet, 2, 0, 'સમયગાળો: ${_dateLabel(fromDate)} થી ${_dateLabel(toDate)}');
    for (var rowIndex = 5; rowIndex < 420; rowIndex++) {
      _clearCell(sheet, rowIndex, 0);
      _clearCell(sheet, rowIndex, 1);
      _clearCell(sheet, rowIndex, 2);
      for (var colIndex = 3; colIndex < 63; colIndex++) _clearCell(sheet, rowIndex, colIndex);
    }
    final byDate = _aggregateByDate(rows.where(_hasDay).toList());
    final dates = byDate.keys.toList()..sort();
    final writtenDates = dates.take(415).toList();
    for (var i = 0; i < writtenDates.length; i++) {
      final date = writtenDates[i];
      final aggregate = byDate[date]!;
      final rowIndex = 5 + i;
      _setInt(sheet, rowIndex, 0, i + 1);
      _setText(sheet, rowIndex, 1, _weekday(date));
      _setText(sheet, rowIndex, 2, _dateLabel(date));
      for (final column in DateWiseReportColumn.all) {
        _setInt(sheet, rowIndex, 3 + DateWiseReportColumn.all.indexOf(column), _valueFor(aggregate, column));
      }
    }

    final totalRow = 5 + writtenDates.length;
    _copyRowStyle(sheet, 5, totalRow, 63);
    _setText(sheet, totalRow, 2, 'કુલ');
    for (final column in DateWiseReportColumn.all) {
      final columnIndex = 3 + DateWiseReportColumn.all.indexOf(column);
      final total = writtenDates.fold<int>(0, (sum, date) => sum + _valueFor(byDate[date]!, column));
      _setInt(sheet, totalRow, columnIndex, total);
    }

    _removeUnselectedDataColumns(sheet, 3, selected);
    return _save(workbook);
  }

  List<List<String>> buildGroupwisePreview({
    required List<Map<String, dynamic>> rows,
    required String group,
    required Iterable<String> visibleColumnKeys,
  }) {
    final selected = _normaliseSelection(visibleColumnKeys, rowSets: [rows]);
    final columns = DateWiseReportColumn.all.where((column) => selected.contains(column.key)).toList();
    final filtered = rows.where((row) => _hasDay(row) && SchoolClassOrder.matches(row, group)).toList();
    final byDate = _aggregateByDate(filtered);
    final dates = byDate.keys.toList()..sort();
    final output = <List<String>>[
      <String>['તારીખ', ...columns.map((column) => column.label)],
      for (final date in dates)
        <String>[_dateLabel(date), for (final column in columns) '${_valueFor(byDate[date]!, column)}'],
    ];
    output.add(<String>[
      'કુલ',
      for (final column in columns)
        '${dates.fold<int>(0, (sum, date) => sum + _valueFor(byDate[date]!, column))}',
    ]);
    return output;
  }

  List<List<String>> buildCombinePreview({
    required List<Map<String, dynamic>> rows,
    required Iterable<String> visibleColumnKeys,
  }) {
    final selected = _normaliseSelection(visibleColumnKeys, rowSets: [rows]);
    final columns = DateWiseReportColumn.all.where((column) => selected.contains(column.key)).toList();
    final byDate = _aggregateByDate(rows.where(_hasDay).toList());
    final dates = byDate.keys.toList()..sort();
    final writtenDates = dates.take(415).toList();
    final output = <List<String>>[
      <String>['ક્રમ', 'વાર', 'તારીખ', ...columns.map((column) => column.label)],
      for (var index = 0; index < writtenDates.length; index++)
        <String>[
          '${index + 1}',
          _weekday(writtenDates[index]),
          _dateLabel(writtenDates[index]),
          for (final column in columns) '${_valueFor(byDate[writtenDates[index]]!, column)}',
        ],
    ];
    output.add(<String>[
      '',
      '',
      'કુલ',
      for (final column in columns)
        '${writtenDates.fold<int>(0, (sum, date) => sum + _valueFor(byDate[date]!, column))}',
    ]);
    return output;
  }

  List<List<String>> buildSummaryPreview({
    required List<Map<String, dynamic>> rows,
    Iterable<String> visibleColumnKeys = const <String>[],
  }) {
    final selected = _normaliseSelection(visibleColumnKeys, rowSets: [rows]);
    final columns = DateWiseReportColumn.all.where((column) => selected.contains(column.key)).toList();
    final byDate = _aggregateByDate(rows.where(_hasDay).toList());
    final dates = byDate.keys.toList()..sort();
    final output = <List<String>>[
      <String>[
        'તારીખ',
        'વર્ગોની સંખ્યા',
        ...columns.map((col) => col.label),
      ],
      for (final date in dates)
        <String>[
          _dateLabel(date),
          '${(byDate[date]!['_rows'] as List<Map<String, dynamic>>).length}',
          for (final column in columns) '${_valueFor(byDate[date]!, column)}',
        ],
    ];
    if (dates.isNotEmpty) {
      output.add(<String>[
        'કુલ',
        '',
        for (final column in columns)
          '${dates.fold<int>(0, (sum, date) => sum + _valueFor(byDate[date]!, column))}',
      ]);
    }
    return output;
  }

  Map<String, Map<String, dynamic>> _aggregateByDate(List<Map<String, dynamic>> rows) {
    final out = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final date = _text(row['attendance_date']);
      if (date.isEmpty) continue;
      final aggregate = out.putIfAbsent(date, () => <String, dynamic>{
        'attendance_date': date,
        'school_type': row['school_type'],
        'registered_counts': <String, int>{'SC': 0, 'ST': 0, 'OBC': 0, 'OTHER': 0},
        'present_counts': <String, int>{'SC': 0, 'ST': 0, 'OBC': 0, 'OTHER': 0},
        'mdm_counts': <String, int>{'SC': 0, 'ST': 0, 'OBC': 0, 'OTHER': 0},
        'breakfast_total': 0,
        'gender_breakdown': <String, dynamic>{},
        '_rows': <Map<String, dynamic>>[],
      });
      (aggregate['_rows'] as List<Map<String, dynamic>>).add(row);
      for (final metric in <String>['registered_counts', 'present_counts', 'mdm_counts']) {
        final into = _map(aggregate[metric]);
        final source = _map(row[metric]);
        for (final key in <String>['SC', 'ST', 'OBC', 'OTHER']) {
          into[key] = _int(into[key]) + _int(source[key]);
        }
        aggregate[metric] = into;
      }
      aggregate['breakfast_total'] = _int(aggregate['breakfast_total']) + _int(row['breakfast_total']);
      final targetBreakdown = _map(aggregate['gender_breakdown']);
      final sourceBreakdown = _genderBreakdown(row);
      for (final gender in <String>['BOYS', 'GIRLS', 'UNSPECIFIED']) {
        final targetGender = _map(targetBreakdown[gender]);
        final sourceGender = _map(sourceBreakdown[gender]);
        for (final category in <String>['SC', 'ST', 'OBC', 'OTHER', '_OVERALL']) {
          final targetCategory = _map(targetGender[category]);
          final sourceCategory = _map(sourceGender[category]);
          for (final metric in <String>['registered', 'present', 'mdm', 'breakfast']) {
            targetCategory[metric] = _int(targetCategory[metric]) + _int(sourceCategory[metric]);
          }
          targetGender[category] = targetCategory;
        }
        targetBreakdown[gender] = targetGender;
      }
      aggregate['gender_breakdown'] = targetBreakdown;
    }
    return out;
  }

  // ===========================================================================
  // TARIJ REPORT (Page 1: Class-wise & Group Subtotals, Page 2: Standard-wise)
  // ===========================================================================

  String? _standardBucketOf(Map<String, dynamic> row) {
    final group = SchoolClassOrder.groupOf(row);
    if (group == SchoolClassOrder.balvatika) return 'બાલવાટિકા';
    for (final key in const <String>[
      'standard',
      'class_standard',
      'standard_name',
      'class_label',
      'label',
      'class_key',
      'sheet_name',
      'class_name',
    ]) {
      final raw = _text(row[key]);
      if (raw.isEmpty) continue;
      const gujDigits = <String, String>{
        '૦': '0',
        '૧': '1',
        '૨': '2',
        '૩': '3',
        '૪': '4',
        '૫': '5',
        '૬': '6',
        '૭': '7',
        '૮': '8',
        '૯': '9',
      };
      var norm = raw;
      gujDigits.forEach((g, a) => norm = norm.replaceAll(g, a));
      final m = RegExp(r'(?:^|\D)([1-8])(?:st|nd|rd|th)?(?:\D|$)', caseSensitive: false).firstMatch(norm);
      if (m != null) {
        return 'ધોરણ ${m.group(1)}';
      }
    }
    return null;
  }

  Map<String, Map<String, dynamic>> _indexTarijCountsByClass(List<Map<String, dynamic>> studentCounts) {
    final countByClass = <String, Map<String, dynamic>>{};
    for (final row in studentCounts) {
      final classId = _text(row['class_id']);
      final category = _text(row['category']).toUpperCase();
      final rawGender = _text(row['gender']).toUpperCase();
      final schoolType = SchoolType.canonical(row['school_type']);
      final gender = (rawGender == 'BOYS' || rawGender == 'GIRLS')
          ? rawGender
          : (schoolType == 'girls' ? 'GIRLS' : 'BOYS');
      final target = countByClass.putIfAbsent(classId, () => <String, dynamic>{});
      final cat = target.putIfAbsent(
        category,
        () => <String, dynamic>{
          'BOYS': <String, int>{},
          'GIRLS': <String, int>{},
        },
      ) as Map<String, dynamic>;
      final values = cat[gender] as Map<String, int>;
      for (final metric in <String>[
        'opening_count',
        'admission_count',
        'lc_exit_count',
        'continuous_absence_exit_count',
        'other_exit_count',
        'closing_count',
        'perfect_attendance_gender_count',
        'age_5_6_count',
        'age_6_14_count',
        'age_above_14_count',
        'aadhaar_count',
        'minority_count',
      ]) {
        values[metric] = _int(values[metric]) + _int(row[metric]);
      }
    }
    return countByClass;
  }

  _TarijComputedRow _computeTarijClassRow({
    required Map<String, dynamic> classRow,
    required Map<String, dynamic> perCategory,
    required List<Map<String, dynamic>> days,
    required Map<String, dynamic>? classStats,
  }) {
    const categories = <String>['SC', 'ST', 'OBC', 'OTHER', 'TOTAL'];
    const genders = <String>['BOYS', 'GIRLS', 'TOTAL'];
    final opening = <String, int>{};
    final admissions = <String, int>{};
    final exits = <String, int>{};
    final lcExits = <String, int>{};
    final absenceExits = <String, int>{};
    final closing = <String, int>{};
    final perfect100 = <String, int>{};
    final age5to6 = <String, int>{};
    final age6to14 = <String, int>{};
    final ageAbove14 = <String, int>{};
    final aadhaar = <String, int>{};
    final minority = <String, int>{};

    for (final cat in categories) {
      for (final gen in genders) {
        final key = '${cat}_$gen';
        final op = _tarijCount(perCategory, cat, gen, 'opening_count');
        final cl = _tarijCount(perCategory, cat, gen, 'closing_count');
        var adm = _tarijCount(perCategory, cat, gen, 'admission_count');
        var lcEx = _tarijCount(perCategory, cat, gen, 'lc_exit_count') +
            _tarijCount(perCategory, cat, gen, 'other_exit_count');
        final absEx = _tarijCount(perCategory, cat, gen, 'continuous_absence_exit_count');
        var ex = lcEx + absEx;
        if (adm == 0 && ex == 0 && cl != op) {
          if (cl > op) {
            adm = cl - op;
          } else {
            ex = op - cl;
            lcEx = ex;
          }
        }
        opening[key] = op;
        admissions[key] = adm;
        exits[key] = ex;
        lcExits[key] = lcEx;
        absenceExits[key] = absEx;
        closing[key] = cl;
        perfect100[key] = _tarijCount(perCategory, cat, gen, 'perfect_attendance_gender_count');
        age5to6[key] = _tarijCount(perCategory, cat, gen, 'age_5_6_count');
        age6to14[key] = _tarijCount(perCategory, cat, gen, 'age_6_14_count');
        ageAbove14[key] = _tarijCount(perCategory, cat, gen, 'age_above_14_count');
        aadhaar[key] = _tarijCount(perCategory, cat, gen, 'aadhaar_count');
        minority[key] = _tarijCount(perCategory, cat, gen, 'minority_count');
      }
    }

    final fallbackPerfect = _int(classStats?['perfect_attendance_count']);
    if ((perfect100['TOTAL_TOTAL'] ?? 0) == 0 && fallbackPerfect > 0) {
      final st = SchoolType.canonical(classStats?['school_type'] ?? classRow['school_type']);
      final targetGen = st == 'girls' ? 'GIRLS' : 'BOYS';
      perfect100['TOTAL_$targetGen'] = fallbackPerfect;
      perfect100['TOTAL_TOTAL'] = fallbackPerfect;
    }

    final registeredDays = <String, int>{};
    final presentDays = <String, int>{};
    final mdmStudentDays = <String, int>{};
    for (final cat in categories) {
      for (final gen in genders) {
        final key = '${cat}_$gen';
        registeredDays[key] = 0;
        presentDays[key] = 0;
        mdmStudentDays[key] = 0;
      }
    }

    // Deduplicate days by attendance_date so each recorded date is counted once.
    final uniqueDaysByDate = <String, Map<String, dynamic>>{};
    for (final dayRow in days) {
      final dt = _text(dayRow['attendance_date']);
      if (dt.isNotEmpty) {
        uniqueDaysByDate[dt] = dayRow;
      }
    }
    final uniqueDays = uniqueDaysByDate.isNotEmpty
        ? uniqueDaysByDate.values.toList()
        : days;

    var workingDays = 0;
    var mdmDays = 0;
    for (final dayRow in uniqueDays) {
      final colTotalPres = DateWiseReportColumn.all.firstWhere(
        (c) => c.metric == 'present' && c.category == 'CATEGORY_TOTAL' && c.gender == 'TOTAL',
      );
      final colTotalMdm = DateWiseReportColumn.all.firstWhere(
        (c) => c.metric == 'mdm' && c.category == 'CATEGORY_TOTAL' && c.gender == 'TOTAL',
      );
      final dayPresTotal = _valueFor(dayRow, colTotalPres);
      final dayMdmTotal = _valueFor(dayRow, colTotalMdm);
      final isWorkingDay = dayPresTotal > 0 ||
          dayRow['present_saved'] == true ||
          dayRow['student_details_saved'] == true;
      final isMdmDay = dayMdmTotal > 0 ||
          (dayRow['mdm_saved'] == true && dayMdmTotal > 0);
      if (isWorkingDay) workingDays++;
      if (isMdmDay) mdmDays++;

      for (final cat in categories) {
        final colCat = cat == 'TOTAL' ? 'CATEGORY_TOTAL' : cat;
        for (final gen in genders) {
          final key = '${cat}_$gen';
          final regCol = DateWiseReportColumn.all.firstWhere(
            (c) => c.metric == 'registered' && c.category == colCat && c.gender == gen,
          );
          final presCol = DateWiseReportColumn.all.firstWhere(
            (c) => c.metric == 'present' && c.category == colCat && c.gender == gen,
          );
          final mdmCol = DateWiseReportColumn.all.firstWhere(
            (c) => c.metric == 'mdm' && c.category == colCat && c.gender == gen,
          );
          if (isWorkingDay) {
            registeredDays[key] = (registeredDays[key] ?? 0) + _valueFor(dayRow, regCol);
            presentDays[key] = (presentDays[key] ?? 0) + _valueFor(dayRow, presCol);
          }
          if (isMdmDay) {
            mdmStudentDays[key] = (mdmStudentDays[key] ?? 0) + _valueFor(dayRow, mdmCol);
          }
        }
      }
    }

    if (workingDays == 0) {
      if (uniqueDays.isNotEmpty) {
        workingDays = uniqueDays.length;
      } else if (classStats != null) {
        workingDays = _int(classStats['working_days']);
      }
    }
    if (mdmDays == 0 && uniqueDays.isEmpty && classStats != null) {
      mdmDays = _int(classStats['mdm_days']);
    }

    final avgPresent = <String, double>{};
    final avgMdm = <String, double>{};
    for (final cat in categories) {
      for (final gen in genders) {
        final key = '${cat}_$gen';
        avgPresent[key] = workingDays > 0 ? (presentDays[key] ?? 0) / workingDays : 0.0;
        avgMdm[key] = mdmDays > 0 ? (mdmStudentDays[key] ?? 0) / mdmDays : 0.0;
      }
    }

    final completeIndividual = classStats?['individual_records_complete'] == true &&
        uniqueDays.isNotEmpty &&
        uniqueDays.every(
          (row) =>
              _text(row['attendance_mode']).toLowerCase() != 'direct' &&
              row['student_details_saved'] == true,
        );

    final tithiDays = workingDays >= mdmDays ? workingDays - mdmDays : 0;
    final libraryBooks = _int(classStats?['class_library_books_count']);

    return _TarijComputedRow(
      label: _classLabel(classRow),
      isTotal: false,
      opening: opening,
      admissions: admissions,
      exits: exits,
      lcExits: lcExits,
      absenceExits: absenceExits,
      closing: closing,
      workingDays: workingDays,
      mdmDays: mdmDays,
      tithiDays: tithiDays,
      individualsComplete: completeIndividual,
      perfectAttendanceCount: perfect100['TOTAL_TOTAL'] ?? fallbackPerfect,
      perfect100: perfect100,
      age5to6: age5to6,
      age6to14: age6to14,
      ageAbove14: ageAbove14,
      aadhaar: aadhaar,
      minority: minority,
      libraryBooks: libraryBooks,
      registeredDays: registeredDays,
      presentDays: presentDays,
      mdmStudentDays: mdmStudentDays,
      avgPresent: avgPresent,
      avgMdm: avgMdm,
    );
  }

  /// Combines multiple class rows into a Subtotal or Standard row using the exact
  /// Excel formulas from PM POSHAN 2026-27 (2).xlsx:
  /// - Movement counts, workingDays, mdmDays, registeredDays, presentDays, mdmStudentDays = SUM of class rows
  /// - avgPresent = SUM of class avgPresent (=SUMIF(P_range, "<>#DIV/0!"))
  /// - avgMdm = SUM of class avgMdm (=SUMIF(T_range, "<>#DIV/0!"))
  /// - attendancePct = 100 * SUM(presentDays) / SUM(registeredDays) (=IFERROR((SUM(O_range)/SUM(N_range))*100, 0))
  _TarijComputedRow _combineTarijRows(String label, List<_TarijComputedRow> rows, {bool useMaxDays = false}) {
    const categories = <String>['SC', 'ST', 'OBC', 'OTHER', 'TOTAL'];
    const genders = <String>['BOYS', 'GIRLS', 'TOTAL'];
    final opening = <String, int>{};
    final admissions = <String, int>{};
    final exits = <String, int>{};
    final lcExits = <String, int>{};
    final absenceExits = <String, int>{};
    final closing = <String, int>{};
    final perfect100 = <String, int>{};
    final age5to6 = <String, int>{};
    final age6to14 = <String, int>{};
    final ageAbove14 = <String, int>{};
    final aadhaar = <String, int>{};
    final minority = <String, int>{};
    final registeredDays = <String, int>{};
    final presentDays = <String, int>{};
    final mdmStudentDays = <String, int>{};
    final avgPresent = <String, double>{};
    final avgMdm = <String, double>{};

    for (final cat in categories) {
      for (final gen in genders) {
        final key = '${cat}_$gen';
        opening[key] = rows.fold<int>(0, (s, r) => s + (r.opening[key] ?? 0));
        admissions[key] = rows.fold<int>(0, (s, r) => s + (r.admissions[key] ?? 0));
        exits[key] = rows.fold<int>(0, (s, r) => s + (r.exits[key] ?? 0));
        lcExits[key] = rows.fold<int>(0, (s, r) => s + (r.lcExits[key] ?? 0));
        absenceExits[key] = rows.fold<int>(0, (s, r) => s + (r.absenceExits[key] ?? 0));
        closing[key] = rows.fold<int>(0, (s, r) => s + (r.closing[key] ?? 0));
        perfect100[key] = rows.fold<int>(0, (s, r) => s + (r.perfect100[key] ?? 0));
        age5to6[key] = rows.fold<int>(0, (s, r) => s + (r.age5to6[key] ?? 0));
        age6to14[key] = rows.fold<int>(0, (s, r) => s + (r.age6to14[key] ?? 0));
        ageAbove14[key] = rows.fold<int>(0, (s, r) => s + (r.ageAbove14[key] ?? 0));
        aadhaar[key] = rows.fold<int>(0, (s, r) => s + (r.aadhaar[key] ?? 0));
        minority[key] = rows.fold<int>(0, (s, r) => s + (r.minority[key] ?? 0));
        registeredDays[key] = rows.fold<int>(0, (s, r) => s + (r.registeredDays[key] ?? 0));
        presentDays[key] = rows.fold<int>(0, (s, r) => s + (r.presentDays[key] ?? 0));
        mdmStudentDays[key] = rows.fold<int>(0, (s, r) => s + (r.mdmStudentDays[key] ?? 0));
        avgPresent[key] = rows.fold<double>(0.0, (s, r) => s + (r.avgPresent[key] ?? 0.0));
        avgMdm[key] = rows.fold<double>(0.0, (s, r) => s + (r.avgMdm[key] ?? 0.0));
      }
    }

    final workingDays = useMaxDays
        ? rows.fold<int>(0, (m, r) => r.workingDays > m ? r.workingDays : m)
        : rows.fold<int>(0, (s, r) => s + r.workingDays);
    final mdmDays = useMaxDays
        ? rows.fold<int>(0, (m, r) => r.mdmDays > m ? r.mdmDays : m)
        : rows.fold<int>(0, (s, r) => s + r.mdmDays);
    final tithiDays = workingDays >= mdmDays ? workingDays - mdmDays : 0;
    final individualsComplete = rows.isNotEmpty && rows.every((r) => r.individualsComplete);
    final perfectCount = rows.fold<int>(0, (s, r) => s + r.perfectAttendanceCount);
    final libraryBooks = rows.fold<int>(0, (s, r) => s + r.libraryBooks);

    return _TarijComputedRow(
      label: label,
      isTotal: true,
      opening: opening,
      admissions: admissions,
      exits: exits,
      lcExits: lcExits,
      absenceExits: absenceExits,
      closing: closing,
      workingDays: workingDays,
      mdmDays: mdmDays,
      tithiDays: tithiDays,
      individualsComplete: individualsComplete,
      perfectAttendanceCount: perfectCount,
      perfect100: perfect100,
      age5to6: age5to6,
      age6to14: age6to14,
      ageAbove14: ageAbove14,
      aadhaar: aadhaar,
      minority: minority,
      libraryBooks: libraryBooks,
      registeredDays: registeredDays,
      presentDays: presentDays,
      mdmStudentDays: mdmStudentDays,
      avgPresent: avgPresent,
      avgMdm: avgMdm,
    );
  }

  ({
    List<_TarijComputedRow> page1Rows,
    List<_TarijComputedRow> page2Rows,
  }) _computeAllTarijPages({
    required List<Map<String, dynamic>> classRows,
    required List<Map<String, dynamic>> attendanceRows,
    required List<Map<String, dynamic>> studentCounts,
  }) {
    final countByClass = _indexTarijCountsByClass(studentCounts);
    final classes = <String, Map<String, dynamic>>{};
    for (final row in classRows) {
      final id = _text(row['class_id'] ?? row['id']);
      if (id.isNotEmpty) classes[id] = row;
    }
    for (final row in studentCounts) {
      final id = _text(row['class_id']);
      if (id.isNotEmpty && !classes.containsKey(id)) {
        classes[id] = row;
      }
    }
    final dailyByClass = <String, List<Map<String, dynamic>>>{};
    for (final row in attendanceRows.where(_hasDay)) {
      dailyByClass.putIfAbsent(_text(row['class_id']), () => <Map<String, dynamic>>[]).add(row);
    }

    final sortedClasses = SchoolClassOrder.sorted(classes.values.toList());
    final computedByClassId = <String, _TarijComputedRow>{};
    for (final classRow in sortedClasses) {
      final classId = _text(classRow['class_id'] ?? classRow['id']);
      final perCategory = countByClass[classId] ?? <String, dynamic>{};
      final days = (dailyByClass[classId] ?? <Map<String, dynamic>>[])
        ..sort((a, b) => _text(a['attendance_date']).compareTo(_text(b['attendance_date'])));
      Map<String, dynamic>? classStats;
      for (final statRow in studentCounts) {
        if (_text(statRow['class_id']) == classId) {
          classStats = statRow;
          break;
        }
      }
      computedByClassId[classId] = _computeTarijClassRow(
        classRow: classRow,
        perCategory: perCategory,
        days: days,
        classStats: classStats,
      );
    }

    final balvatikaRows = <_TarijComputedRow>[];
    final std1to5Rows = <_TarijComputedRow>[];
    final std6to8Rows = <_TarijComputedRow>[];
    final otherRows = <_TarijComputedRow>[];
    final byStandard = <String, List<_TarijComputedRow>>{
      'બાલવાટિકા': <_TarijComputedRow>[],
      for (var std = 1; std <= 8; std++) 'ધોરણ $std': <_TarijComputedRow>[],
    };

    for (final classRow in sortedClasses) {
      final classId = _text(classRow['class_id'] ?? classRow['id']);
      final computed = computedByClassId[classId]!;
      final group = SchoolClassOrder.groupOf(classRow);
      if (group == SchoolClassOrder.balvatika) {
        balvatikaRows.add(computed);
      } else if (group == SchoolClassOrder.standards1to5) {
        std1to5Rows.add(computed);
      } else if (group == SchoolClassOrder.standards6to8) {
        std6to8Rows.add(computed);
      } else {
        otherRows.add(computed);
      }
      final stdBucket = _standardBucketOf(classRow);
      if (stdBucket != null && byStandard.containsKey(stdBucket)) {
        byStandard[stdBucket]!.add(computed);
      }
    }

    final page1Rows = <_TarijComputedRow>[
      ...balvatikaRows,
      if (balvatikaRows.length > 1) _combineTarijRows('કુલ બાલવાટિકા', balvatikaRows),
      ...std1to5Rows,
      if (std1to5Rows.isNotEmpty) _combineTarijRows('ધોરણ એક થી ધોરણ પાંચ', std1to5Rows),
      if (balvatikaRows.isNotEmpty || std1to5Rows.isNotEmpty)
        _combineTarijRows('બાલવાટિકા થી ધોરણ 5', <_TarijComputedRow>[...balvatikaRows, ...std1to5Rows]),
      ...std6to8Rows,
      ...otherRows,
      if (std6to8Rows.isNotEmpty) _combineTarijRows('ધોરણ છ થી ધોરણ આઠ', std6to8Rows),
      if (std1to5Rows.isNotEmpty || std6to8Rows.isNotEmpty)
        _combineTarijRows('ધોરણ એક થી ધોરણ આઠ', <_TarijComputedRow>[...std1to5Rows, ...std6to8Rows]),
      if (sortedClasses.isNotEmpty)
        _combineTarijRows(
          'બાલવાટિકા થી ધોરણ 8',
          <_TarijComputedRow>[...balvatikaRows, ...std1to5Rows, ...std6to8Rows, ...otherRows],
        ),
    ];

    final page2Rows = <_TarijComputedRow>[];
    for (final stdKey in <String>[
      'બાલવાટિકા',
      'ધોરણ 1',
      'ધોરણ 2',
      'ધોરણ 3',
      'ધોરણ 4',
      'ધોરણ 5',
      'ધોરણ 6',
      'ધોરણ 7',
      'ધોરણ 8',
    ]) {
      final list = byStandard[stdKey] ?? const <_TarijComputedRow>[];
      page2Rows.add(_combineTarijRows(stdKey, list, useMaxDays: true));
    }
    if (std1to5Rows.isNotEmpty) {
      page2Rows.add(_combineTarijRows('ધોરણ એક થી ધોરણ પાંચ', std1to5Rows));
    }
    if (balvatikaRows.isNotEmpty || std1to5Rows.isNotEmpty) {
      page2Rows.add(_combineTarijRows('બાલવાટિકા થી ધોરણ 5', <_TarijComputedRow>[...balvatikaRows, ...std1to5Rows]));
    }
    if (std6to8Rows.isNotEmpty) {
      page2Rows.add(_combineTarijRows('ધોરણ છ થી ધોરણ આઠ', std6to8Rows));
    }
    if (std1to5Rows.isNotEmpty || std6to8Rows.isNotEmpty) {
      page2Rows.add(_combineTarijRows('ધોરણ એક થી ધોરણ આઠ', <_TarijComputedRow>[...std1to5Rows, ...std6to8Rows]));
    }
    if (sortedClasses.isNotEmpty) {
      page2Rows.add(_combineTarijRows(
        'બાલવાટિકા થી ધોરણ 8',
        <_TarijComputedRow>[...balvatikaRows, ...std1to5Rows, ...std6to8Rows, ...otherRows],
      ));
    }

    return (page1Rows: page1Rows, page2Rows: page2Rows);
  }

  /// Preserves the exact column order configured by the School Admin.
  List<String> _normaliseOrderedTarijSelection(Iterable<String> visibleTarijColumnKeys) {
    final ordered = <String>[];
    final seen = <String>{};
    for (final raw in visibleTarijColumnKeys) {
      final key = raw.trim();
      if (TarijReportColumn.allKeys.contains(key) && seen.add(key)) {
        ordered.add(key);
      }
    }
    return ordered.isEmpty
        ? TarijReportColumn.all.map((c) => c.key).toList()
        : ordered;
  }

  /// Ordered TARIJ columns for this report (admin's numbered selection).
  List<TarijColumnSpec> _tarijSpecs(
    Iterable<String> visibleTarijColumnKeys,
    String schoolType,
    List<Iterable<Map<String, dynamic>>> rowSets,
  ) {
    final type = schoolType.trim().isNotEmpty
        ? SchoolType.canonical(schoolType)
        : _resolveSchoolTypeFromRowSets(rowSets);
    return TarijColumnSpec.resolve(visibleTarijColumnKeys, type);
  }

  /// One TARIJ cell. Counts are returned as int, averages / percentages as
  /// formatted text, the signature column as an empty string.
  Object _tarijCell(_TarijComputedRow r, TarijColumnSpec c) {
    final hasDays = r.workingDays > 0;
    final hasMdm = r.mdmDays > 0;
    final g = c.gender ?? 'TOTAL';
    final gk = 'TOTAL_$g';
    final ck = '${c.category ?? 'TOTAL'}_$g';
    switch (c.section) {
      case 'opening':
        return r.opening[gk] ?? 0;
      case 'admissions':
        return r.admissions[gk] ?? 0;
      case 'exits':
        return r.exits[gk] ?? 0;
      case 'lc_exits':
        return r.lcExits[gk] ?? 0;
      case 'absence_exits':
        return r.absenceExits[gk] ?? 0;
      case 'closing':
        return r.closing[ck] ?? 0;
      case 'working_days':
        return r.workingDays;
      case 'present_total':
        return hasDays ? (r.presentDays[gk] ?? 0) : 0;
      case 'avg_present':
        return hasDays ? (r.avgPresent[ck] ?? 0.0).toStringAsFixed(2) : '0.00';
      case 'attendance_pct':
        return (r.registeredDays[gk] ?? 0) > 0
            ? '${r.attendancePct(gk).toStringAsFixed(2)}%'
            : '0.00%';
      case 'mdm_days':
        return r.mdmDays;
      case 'tithi_days':
        return r.tithiDays;
      case 'mdm_total':
        return hasMdm ? (r.mdmStudentDays[gk] ?? 0) : 0;
      case 'avg_mdm':
        return hasMdm ? (r.avgMdm[ck] ?? 0.0).toStringAsFixed(2) : '0.00';
      case 'perfect_100':
        return r.individualsComplete ? (r.perfect100[gk] ?? 0) : 0;
      case 'age_5_6':
        return r.age5to6[gk] ?? 0;
      case 'age_6_14':
        return r.age6to14[gk] ?? 0;
      case 'age_above_14':
        return r.ageAbove14[gk] ?? 0;
      case 'aadhaar':
        return r.aadhaar[gk] ?? 0;
      case 'minority':
        return r.minority[gk] ?? 0;
      case 'library_books':
        return r.libraryBooks;
      case 'teacher_sign':
      default:
        return '';
    }
  }

  List<List<String>> buildTarijPreview({
    required List<Map<String, dynamic>> classRows,
    required List<Map<String, dynamic>> attendanceRows,
    required List<Map<String, dynamic>> studentCounts,
    Iterable<String> visibleColumnKeys = const <String>[],
    Iterable<String> visibleTarijColumnKeys = const <String>[],
    String schoolType = '',
  }) {
    final specs = _tarijSpecs(
      visibleTarijColumnKeys,
      schoolType,
      [classRows, attendanceRows, studentCounts],
    );
    final pages = _computeAllTarijPages(
      classRows: classRows,
      attendanceRows: attendanceRows,
      studentCounts: studentCounts,
    );
    final headers = <String>[
      'ધોરણ / જૂથ',
      for (var i = 0; i < specs.length; i++) '${i + 1}. ${specs[i].title}',
    ];
    List<String> formatRow(_TarijComputedRow r) => <String>[
          r.label,
          for (final c in specs) '${_tarijCell(r, c)}',
        ];
    return <List<String>>[
      headers,
      for (final r in pages.page1Rows) formatRow(r),
      <String>[
        '=== TARIJ PAGE 2 (ધોરણવાર સારાંશ / Standard-wise Summary) ===',
        for (var i = 1; i < headers.length; i++) '',
      ],
      for (final r in pages.page2Rows) formatRow(r),
    ];
  }

  Future<Uint8List> exportTarijXlsx({
    required String schoolName,
    String schoolAddress = '',
    required String monthLabel,
    required List<Map<String, dynamic>> classRows,
    required List<Map<String, dynamic>> attendanceRows,
    required List<Map<String, dynamic>> studentCounts,
    Iterable<String> visibleColumnKeys = const <String>[],
    Iterable<String> visibleTarijColumnKeys = const <String>[],
    String schoolType = '',
  }) async {
    final workbook = ec.Excel.createExcel();
    workbook.rename('Sheet1', 'TARIJ - Page 1');
    final sheet1 = workbook['TARIJ - Page 1'];
    final sheet2 = workbook['TARIJ - Page 2'];

    final specs = _tarijSpecs(
      visibleTarijColumnKeys,
      schoolType,
      [classRows, attendanceRows, studentCounts],
    );
    final pages = _computeAllTarijPages(
      classRows: classRows,
      attendanceRows: attendanceRows,
      studentCounts: studentCounts,
    );
    final headers = <String>[
      'ધોરણ',
      for (var i = 0; i < specs.length; i++) '${i + 1}. ${specs[i].title}',
    ];

    void writeTarijSheet(ec.Sheet sheet, String pageSubtitle, List<_TarijComputedRow> rows) {
      final headerName = schoolAddress.trim().isEmpty
          ? schoolName
          : '$schoolName, ${schoolAddress.trim()}';
      _setText(sheet, 0, 0, headerName);
      _setText(sheet, 1, 0, 'માસિક પત્રક (TARIJ) — $monthLabel ($pageSubtitle)');
      _setText(
        sheet,
        2,
        0,
        'હાજરી ટકાવારી = (કુલ હાજર વિદ્યાર્થી-દિવસ ÷ કુલ નોંધાયેલ વિદ્યાર્થી-દિવસ) × 100  |  સરેરાશ હાજરી = વર્ગવાર સરેરાશનો સરવાળો',
      );
      for (var col = 0; col < headers.length; col++) {
        _setText(sheet, 4, col, headers[col]);
      }
      var outRow = 5;
      for (final r in rows) {
        _setText(sheet, outRow, 0, r.label);
        for (var i = 0; i < specs.length; i++) {
          final v = _tarijCell(r, specs[i]);
          if (v is int) {
            _setInt(sheet, outRow, i + 1, v);
          } else {
            _setText(sheet, outRow, i + 1, '$v');
          }
        }
        outRow++;
      }
      _setText(sheet, outRow + 1, 0, 'આચાર્યની સહી : ___________________________');
    }

    writeTarijSheet(sheet1, 'Page 1 — વર્ગવાર અને જૂથવાર પત્રક', pages.page1Rows);
    writeTarijSheet(sheet2, 'Page 2 — ધોરણવાર સારાંશ પત્રક', pages.page2Rows);

    return _save(workbook);
  }

  int _tarijCount(Map<String, dynamic> byClass, String category, String gender, String metric) {
    const allCategories = <String>['SC', 'ST', 'OBC', 'OTHER'];
    final targetCategories = category == 'TOTAL' ? allCategories : <String>[category];
    final targetGenders = gender == 'TOTAL' ? <String>['BOYS', 'GIRLS'] : <String>[gender];
    var total = 0;
    for (final categoryKey in targetCategories) {
      final categoryData = _map(byClass[categoryKey]);
      for (final genderKey in targetGenders) {
        final genderData = _map(categoryData[genderKey]);
        if (metric == 'exit') {
          total += _int(genderData['lc_exit_count']) +
              _int(genderData['continuous_absence_exit_count']) +
              _int(genderData['other_exit_count']);
        } else {
          total += _int(genderData[metric]);
        }
      }
    }
    return total;
  }

  // ===========================================================================
  // MDM EKANDAR REPORT (Average Present & Average PM POSHAN by Group & School)
  // ===========================================================================

  List<List<String>> buildMdmPreview({
    required String schoolName,
    required List<Map<String, dynamic>> classRows,
    required List<Map<String, dynamic>> attendanceRows,
    required List<Map<String, dynamic>> studentCounts,
    Iterable<String> visibleColumnKeys = const <String>[],
  }) {
    final enabledPairs = _enabledCategoryGenderPairs(visibleColumnKeys, rowSets: [classRows, attendanceRows, studentCounts]);
    final enabledGenders = _enabledGenders(visibleColumnKeys, rowSets: [classRows, attendanceRows, studentCounts]);
    const groups = <(String, String)>[
      (SchoolClassOrder.balvatika, 'બાલવાટિકા'),
      (SchoolClassOrder.standards1to5, 'ધો.1 થી 5'),
      (SchoolClassOrder.standards6to8, 'ધો.6 થી 8'),
    ];

    String gLabel(String g) => _dailyGenderLabel(g);
    String cLabel(String c) => _dailyCategoryLabel(c == 'TOTAL' ? 'CATEGORY_TOTAL' : c);

    final countByClass = _indexTarijCountsByClass(studentCounts);
    int groupClosing(String group, String gender) {
      var sum = 0;
      for (final row in studentCounts) {
        if (!SchoolClassOrder.matches(row, group)) continue;
        final rawGen = _text(row['gender']).toUpperCase();
        final schoolType = SchoolType.canonical(row['school_type']);
        final gen = (rawGen == 'BOYS' || rawGen == 'GIRLS')
            ? rawGen
            : (schoolType == 'girls' ? 'GIRLS' : 'BOYS');
        if (gender == 'TOTAL' || gen == gender) {
          sum += _int(row['closing_count']);
        }
      }
      return sum;
    }

    // Group daily average = AVERAGE(FILTER(group_daily_sum, group_daily_total > 0))
    // matching exact formula in PM POSHAN 2026-27 (2).xlsx MDM EKANDAR!
    double groupAverageMetric(String group, String metric, String category, String gender) {
      final rows = attendanceRows
          .where((row) => _hasDay(row) && SchoolClassOrder.matches(row, group))
          .toList();
      if (rows.isEmpty) return 0.0;
      final colCat = category == 'TOTAL' ? 'CATEGORY_TOTAL' : category;
      final targetCol = DateWiseReportColumn.all.firstWhere(
        (item) => item.metric == metric && item.category == colCat && item.gender == gender,
        orElse: () => DateWiseReportColumn.all.first,
      );
      final totalCol = DateWiseReportColumn.all.firstWhere(
        (item) => item.metric == metric && item.category == 'CATEGORY_TOTAL' && item.gender == 'TOTAL',
        orElse: () => DateWiseReportColumn.all.first,
      );
      final byDateVal = <String, int>{};
      final byDateTotal = <String, int>{};
      for (final row in rows) {
        final date = _text(row['attendance_date']);
        if (date.isEmpty) continue;
        byDateVal[date] = (byDateVal[date] ?? 0) + _valueFor(row, targetCol);
        byDateTotal[date] = (byDateTotal[date] ?? 0) + _valueFor(row, totalCol);
      }
      final activeDates = byDateTotal.entries.where((e) => e.value > 0).map((e) => e.key).toList();
      if (activeDates.isEmpty) return 0.0;
      final totalSum = activeDates.fold<int>(0, (sum, d) => sum + (byDateVal[d] ?? 0));
      return totalSum / activeDates.length;
    }

    // Ensure countByClass is referenced so analyzer stays happy
    if (countByClass.isEmpty && studentCounts.isNotEmpty) {}

    final headers = <String>[
      'પત્રક / વર્ગ જૂથ',
      for (final g in enabledGenders) 'રજી. સંખ્યા (${gLabel(g)})',
      for (final p in enabledPairs) '${cLabel(p.$1)} • ${gLabel(p.$2)}',
    ];

    List<List<String>> buildTableSection(String sectionTitle, String metric) {
      final groupReg = <String, Map<String, int>>{};
      final groupAvg = <String, Map<String, double>>{};
      for (final g in groups) {
        groupReg[g.$1] = <String, int>{
          for (final gen in enabledGenders) gen: groupClosing(g.$1, gen),
        };
        groupAvg[g.$1] = <String, double>{
          for (final p in enabledPairs)
            '${p.$1}_${p.$2}': groupAverageMetric(g.$1, metric, p.$1, p.$2),
        };
      }

      // School row = exact SUM of the 3 group rows (=SUM(B7:B9), =SUM(C7:C9))
      final schoolRow = <String>[
        '$sectionTitle — કુલ શાળા ($schoolName)',
        for (final gen in enabledGenders)
          '${groups.fold<int>(0, (s, g) => s + (groupReg[g.$1]?[gen] ?? 0))}',
        for (final p in enabledPairs)
          groups
              .fold<double>(0.0, (s, g) => s + (groupAvg[g.$1]?['${p.$1}_${p.$2}'] ?? 0.0))
              .toStringAsFixed(2),
      ];

      return <List<String>>[
        schoolRow,
        for (final g in groups)
          <String>[
            '$sectionTitle — ${g.$2}',
            for (final gen in enabledGenders) '${groupReg[g.$1]?[gen] ?? 0}',
            for (final p in enabledPairs)
              (groupAvg[g.$1]?['${p.$1}_${p.$2}'] ?? 0.0).toStringAsFixed(2),
          ],
      ];
    }

    return <List<String>>[
      headers,
      ...buildTableSection('૧. વિદ્યાર્થીઓની હાજરી સરેરાશ', 'present'),
      ...buildTableSection('૨. સરેરાશ મધ્યાહન ભોજન લીધેલ વિદ્યાર્થી', 'mdm'),
    ];
  }

  Future<Uint8List> exportMdmEkandarXlsx({
    required String schoolName,
    String schoolAddress = '',
    required String monthLabel,
    required List<Map<String, dynamic>> classRows,
    required List<Map<String, dynamic>> attendanceRows,
    required List<Map<String, dynamic>> studentCounts,
    Iterable<String> visibleColumnKeys = const <String>[],
  }) async {
    final workbook = await _loadTemplate(_monthlyTemplate);
    final sheet = workbook['MDM EKANDAR'];
    _keepOnly(workbook, <String>{'MDM EKANDAR'});
    final headerName = schoolAddress.trim().isEmpty
        ? schoolName
        : '$schoolName, ${schoolAddress.trim()}';
    _setText(sheet, 0, 0, headerName);
    _setText(sheet, 1, 0, monthLabel);
    _setText(sheet, 2, 0, 'શાળાનું નામ');
    _setText(sheet, 2, 1, monthLabel);
    _setText(sheet, 12, 0, 'શાળાનું નામ');
    _setText(sheet, 12, 1, monthLabel);

    // Clear stray timestamp cells at column 102 in the template so print area stays clean
    for (var r = 0; r < 22; r++) {
      _clearCell(sheet, r, 102);
    }

    const categories = <String>['SC', 'ST', 'OBC', 'OTHER', 'CATEGORY_TOTAL'];
    const genders = <String>['BOYS', 'GIRLS', 'TOTAL'];
    const groups = <(String, String)>[
      (SchoolClassOrder.balvatika, 'બાલવાટિકા'),
      (SchoolClassOrder.standards1to5, 'ધો.1 થી 5'),
      (SchoolClassOrder.standards6to8, 'ધો.6 થી 8'),
    ];

    double averageMetric(String group, String metric, String category, String gender) {
      final rows = attendanceRows
          .where((row) => _hasDay(row) && SchoolClassOrder.matches(row, group))
          .toList();
      if (rows.isEmpty) return 0.0;
      final keyMetric = metric == 'mdm' ? 'mdm' : 'present';
      final col = DateWiseReportColumn.all.firstWhere(
        (item) => item.metric == keyMetric && item.category == category && item.gender == gender,
        orElse: () => DateWiseReportColumn.all.first,
      );
      final totalCol = DateWiseReportColumn.all.firstWhere(
        (item) => item.metric == keyMetric && item.category == 'CATEGORY_TOTAL' && item.gender == 'TOTAL',
        orElse: () => DateWiseReportColumn.all.first,
      );
      final byDateVal = <String, int>{};
      final byDateTotal = <String, int>{};
      for (final row in rows) {
        final date = _text(row['attendance_date']);
        if (date.isEmpty) continue;
        byDateVal[date] = (byDateVal[date] ?? 0) + _valueFor(row, col);
        byDateTotal[date] = (byDateTotal[date] ?? 0) + _valueFor(row, totalCol);
      }
      final activeDates = byDateTotal.entries.where((e) => e.value > 0).map((e) => e.key).toList();
      if (activeDates.isEmpty) return 0.0;
      return activeDates.fold<int>(0, (sum, d) => sum + (byDateVal[d] ?? 0)) / activeDates.length;
    }

    void populateMdmTable(int startRowIdx, String metric) {
      final groupClosings = <int>[0, 0, 0];
      final groupValues = List<List<double>>.generate(3, (_) => List<double>.filled(15, 0.0));

      for (var gIdx = 0; gIdx < groups.length; gIdx++) {
        final groupKey = groups[gIdx].$1;
        final rowIdx = startRowIdx + 1 + gIdx;
        _setText(sheet, rowIdx, 0, groups[gIdx].$2);
        final closingCount = studentCounts
            .where((row) => SchoolClassOrder.matches(row, groupKey))
            .fold<int>(0, (sum, row) => sum + _int(row['closing_count']));
        groupClosings[gIdx] = closingCount;
        _setInt(sheet, rowIdx, 1, closingCount);

        var colOffset = 0;
        for (final category in categories) {
          for (final gender in genders) {
            final val = averageMetric(groupKey, metric, category, gender);
            groupValues[gIdx][colOffset] = val;
            _setText(sheet, rowIdx, 2 + colOffset, val.toStringAsFixed(2));
            colOffset++;
          }
        }
      }

      // School total row (startRowIdx) = exact SUM of the 3 group rows (=SUM(B7:B9), =SUM(C7:C9))
      _setText(sheet, startRowIdx, 0, schoolName);
      final totalClosing = groupClosings.fold<int>(0, (a, b) => a + b);
      _setInt(sheet, startRowIdx, 1, totalClosing);
      for (var colOffset = 0; colOffset < 15; colOffset++) {
        final sumVal = groupValues[0][colOffset] + groupValues[1][colOffset] + groupValues[2][colOffset];
        _setText(sheet, startRowIdx, 2 + colOffset, sumVal.toStringAsFixed(2));
      }
    }

    // First table: average Present (rows 5..8, 1-based 6..9)
    populateMdmTable(5, 'present');
    // Second table: average PM POSHAN (rows 15..18, 1-based 16..19)
    populateMdmTable(15, 'mdm');

    // Apply Admin's column selection to the 15 category x gender columns (Cols 2..16)
    final enabledPairs = _enabledCategoryGenderPairs(visibleColumnKeys, rowSets: [classRows, attendanceRows, studentCounts])
        .map((p) => '${p.$1 == 'TOTAL' ? 'CATEGORY_TOTAL' : p.$1}_${p.$2}')
        .toSet();
    var colOffset = 0;
    for (final category in categories) {
      final catTitle = _dailyCategoryLabel(category);
      bool wroteCatHeaderOnVisibleCol = false;
      for (final gender in genders) {
        final isEnabled = enabledPairs.contains('${category}_$gender');
        final colIdx = 2 + colOffset;
        sheet.setColumnHidden(colIdx, !isEnabled);
        if (isEnabled) {
          if (!wroteCatHeaderOnVisibleCol) {
            _setText(sheet, 3, colIdx, catTitle);
            _setText(sheet, 13, colIdx, catTitle);
            wroteCatHeaderOnVisibleCol = true;
          }
          _setText(sheet, 4, colIdx, _dailyGenderLabel(gender));
          _setText(sheet, 14, colIdx, _dailyGenderLabel(gender));
        }
        colOffset++;
      }
    }
    _setText(sheet, 21, 0, 'આચાર્યની સહી : ___________________________');

    return _save(workbook);
  }

  String _htmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  String _dailyGenderLabel(String gender) => switch (gender) {
        'BOYS' => 'કુમાર',
        'GIRLS' => 'કન્યા',
        _ => 'કુલ',
      };

  String _dailyCategoryLabel(String category) => switch (category) {
        'SC' => 'અ. જા.',
        'ST' => 'અ. જ. જા.',
        'OBC' => 'બક્ષીપંચ',
        'OTHER' => 'અન્ય',
        _ => 'કુલ',
      };

  String _dailyMetricLabel(String metric) => switch (metric) {
        'registered' => 'રજીસ્ટરર્ડ વિદ્યાર્થીઓની સંખ્યા',
        'present' => 'હાજર વિદ્યાર્થીઓની સંખ્યા',
        'mdm' => 'પીએમ પોષણ યોજનામાં ભાગ લીધેલ વિદ્યાર્થીઓની સંખ્યા',
        _ => 'સીએમ અલ્પાહાર લીધેલ વિદ્યાર્થીઓની સંખ્યા',
      };

  String _dailyGujaratiDigits(String value) {
    const digits = <String>['૦', '૧', '૨', '૩', '૪', '૫', '૬', '૭', '૮', '૯'];
    return value.split('').map((char) {
      final index = int.tryParse(char);
      return index == null ? char : digits[index];
    }).join();
  }

  String buildDailyDatewisePrintHtml({
    required String schoolName,
    required String schoolAddress,
    required String date,
    required String attendanceSerial,
    required List<Map<String, dynamic>> classRows,
    required Iterable<String> visibleColumnKeys,
  }) {
    final selected = _normaliseSelection(visibleColumnKeys, rowSets: [classRows]);
    final columns = DateWiseReportColumn.all
        .where((column) => selected.contains(column.key))
        .toList();
    final ordered = SchoolClassOrder.sorted(classRows);
    final balvatika = ordered
        .where((row) => SchoolClassOrder.groupOf(row) == SchoolClassOrder.balvatika)
        .toList();
    final std1to5 = ordered
        .where((row) => SchoolClassOrder.groupOf(row) == SchoolClassOrder.standards1to5)
        .toList();
    final std6to8 = ordered
        .where((row) => SchoolClassOrder.groupOf(row) == SchoolClassOrder.standards6to8)
        .toList();
    final other = ordered.where((row) {
      final group = SchoolClassOrder.groupOf(row);
      return group != SchoolClassOrder.balvatika &&
          group != SchoolClassOrder.standards1to5 &&
          group != SchoolClassOrder.standards6to8;
    }).toList();

    final bodyRows = <Map<String, dynamic>>[];
    void addClassRows(List<Map<String, dynamic>> source) {
      for (final row in source) {
        bodyRows.add(<String, dynamic>{
          'label': _classLabel(row),
          'kind': 'class',
          'row': row,
        });
      }
    }

    void addTotal(String label, List<Map<String, dynamic>> included) {
      if (included.isEmpty) return;
      bodyRows.add(<String, dynamic>{
        'label': label,
        'kind': 'total',
        'classes': included,
      });
    }

    addClassRows(balvatika);
    if (balvatika.length > 1) addTotal('કુલ બાલવાટિકા', balvatika);
    addClassRows(std1to5);
    addTotal('કુલ ધોરણ 1 થી 5', std1to5);
    addTotal('કુલ બાલવાટિકા થી ધોરણ 5', <Map<String, dynamic>>[...balvatika, ...std1to5]);
    addClassRows(std6to8);
    addTotal('કુલ ધોરણ 6 થી 8', std6to8);
    addTotal('કુલ ધોરણ 1 થી 8', <Map<String, dynamic>>[...std1to5, ...std6to8]);
    addClassRows(other);
    addTotal('કુલ શાળા', ordered);
    if (bodyRows.isEmpty) {
      bodyRows.add(<String, dynamic>{'label': 'કોઈ સક્રિય વર્ગ ઉપલબ્ધ નથી', 'kind': 'empty'});
    }
    final headerReserveMm = columns.length > 42
        ? 47.0
        : columns.length > 24
            ? 39.0
            : columns.length > 12
                ? 32.0
                : 27.0;
    final bodyAvailableMm = 178.0 - headerReserveMm;
    final targetPrintRowHeightMm =
        (bodyAvailableMm / bodyRows.length).clamp(3.8, 18.0).toDouble();

    String cellValue(Map<String, dynamic> displayRow, DateWiseReportColumn column) {
      if (displayRow['kind'] == 'class') {
        final row = displayRow['row'] as Map<String, dynamic>;
        if (column.metric != 'registered' && !_hasDay(row)) return '';
        return '${_dailyDatewiseValue(row, column)}';
      }
      if (displayRow['kind'] == 'total') {
        final included = (displayRow['classes'] as List).cast<Map<String, dynamic>>();
        final eligible = column.metric == 'registered' ? included : included.where(_hasDay).toList();
        if (eligible.isEmpty) return '';
        final total = eligible.fold<int>(0, (sum, row) => sum + _dailyDatewiseValue(row, column));
        return '$total';
      }
      return '';
    }

    List<Map<String, dynamic>> contiguousGroups(String Function(DateWiseReportColumn) keyOf) {
      final groups = <Map<String, dynamic>>[];
      for (final column in columns) {
        final key = keyOf(column);
        if (groups.isEmpty || groups.last['key'] != key) {
          groups.add(<String, dynamic>{'key': key, 'columns': <DateWiseReportColumn>[column]});
        } else {
          (groups.last['columns'] as List<DateWiseReportColumn>).add(column);
        }
      }
      return groups;
    }

    final metricGroups = contiguousGroups((column) => column.metric);
    final categoryGroups = contiguousGroups((column) => '${column.metric}|${column.category}');
    String groupMetric(Map<String, dynamic> group) =>
        _dailyMetricLabel('${group['key']}');
    String groupCategory(Map<String, dynamic> group) {
      final key = '${group['key']}'.split('|');
      return _dailyCategoryLabel(key.length > 1 ? key[1] : '');
    }

    String dateLabel = _dateLabel(date);
    final parsed = DateTime.tryParse(date);
    const weekDays = <String>['સોમવાર', 'મંગળવાર', 'બુધવાર', 'ગુરુવાર', 'શુક્રવાર', 'શનિવાર', 'રવિવાર'];
    final weekday = parsed == null ? '' : weekDays[parsed.weekday - 1];
    dateLabel = _dailyGujaratiDigits(dateLabel);
    final dateAndDay = weekday.isEmpty ? dateLabel : '$dateLabel • $weekday';
    final fontSize = columns.length > 48
        ? '5pt'
        : columns.length > 36
            ? '5.5pt'
            : columns.length > 24
                ? '6.2pt'
                : columns.length > 14
                    ? '7pt'
                    : columns.length > 8
                        ? '8pt'
                        : '9pt';
    final dataWidthPercent = 80.0 / (columns.isEmpty ? 1 : columns.length);
    final columnGroupHtml = StringBuffer()
      ..write('<colgroup><col style="width:3.5%"><col style="width:8.5%">');
    for (var i = 0; i < columns.length; i++) {
      columnGroupHtml.write('<col style="width:${dataWidthPercent.toStringAsFixed(3)}%">');
    }
    columnGroupHtml.write('<col style="width:8%"></colgroup>');
    final addressHtml = schoolAddress.trim().isEmpty
        ? ''
        : '<div class="address">${_htmlEscape(schoolAddress.trim())}</div>';
    final headerHtml = StringBuffer()
      ..write('<tr><th rowspan="3" class="serial">ક્રમ</th>')
      ..write('<th rowspan="3" class="class">ધોરણ</th>');
    for (final group in metricGroups) {
      headerHtml.write('<th colspan="${(group['columns'] as List).length}">${_htmlEscape(groupMetric(group))}</th>');
    }
    headerHtml.write('<th rowspan="3" class="signature">વર્ગ શિક્ષકની સહી</th></tr><tr>');
    for (final group in categoryGroups) {
      headerHtml.write('<th colspan="${(group['columns'] as List).length}">${_htmlEscape(groupCategory(group))}</th>');
    }
    headerHtml.write('</tr><tr>');
    for (final column in columns) {
      headerHtml.write('<th class="gender">${_htmlEscape(_dailyGenderLabel(column.gender))}</th>');
    }
    headerHtml.write('</tr>');

    final serialNumber = int.tryParse(attendanceSerial.trim());
    final serialValueClass = serialNumber != null && serialNumber > 99
        ? 'vertical serialValue'
        : 'serialValue';
    final tableBody = StringBuffer();
    for (var rowIndex = 0; rowIndex < bodyRows.length; rowIndex++) {
      final displayRow = bodyRows[rowIndex];
      final isTotal = displayRow['kind'] == 'total';
      final isEmpty = displayRow['kind'] == 'empty';
      tableBody.write('<tr class="${isTotal ? 'total' : isEmpty ? 'empty' : 'detail'}">');
      if (rowIndex == 0) {
        final serialText = attendanceSerial.trim().isEmpty
            ? ''
            : _dailyGujaratiDigits(attendanceSerial.trim());
        tableBody.write('<td rowspan="${bodyRows.length}" class="$serialValueClass">${_htmlEscape(serialText)}</td>');
      }
      tableBody.write('<td class="className">${_htmlEscape('${displayRow['label'] ?? ''}')}</td>');
      for (final column in columns) {
        tableBody.write('<td class="number">${_htmlEscape(cellValue(displayRow, column))}</td>');
      }
      tableBody.write('<td class="sign"></td>');
      tableBody.write('</tr>');
    }

    return '''<!doctype html>
<html lang="gu">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_htmlEscape('DATEWISE_$date')}</title>
<style>
@page { size: A4 landscape; margin: 3mm; }
* { box-sizing: border-box; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
html, body { margin: 0; padding: 0; color: #111; font-family: "Noto Sans Gujarati", "Nirmala UI", "Shruti", sans-serif; }
body { width: 100%; }
.heading { text-align: center; margin: 0 0 2mm 0; line-height: 1.15; }
.school { font-weight: 700; font-size: 12pt; margin: 0 0 1mm; }
.address { font-size: 8pt; margin: 0 0 1mm; }
.title { font-size: 9pt; font-weight: 700; margin: 0 0 1mm; }
.period { font-size: 7pt; margin: 0 0 2mm; }
table { width: 100%; border-collapse: collapse; table-layout: fixed; font-size: $fontSize; }
thead { display: table-header-group; }
tfoot { display: table-footer-group; }
th, td { border: 0.3pt solid #555; padding: 0.5mm 0.35mm; text-align: center; vertical-align: middle; overflow-wrap: anywhere; word-break: normal; white-space: normal; line-height: 1.15; }
th { background: #e3e3e3; font-weight: 700; }
th.gender { font-weight: 600; }
th.serial, td.serialValue { width: 3.5%; }
th.class { width: 8.5%; }
th.signature, td.sign { width: 8%; }
td.serialValue { font-weight: 700; text-align: center; vertical-align: middle; }
td.serialValue.vertical { writing-mode: vertical-rl; transform: rotate(180deg); }
td.className { text-align: left; padding-left: 2px; font-size: ${columns.length > 36 ? '5.5pt' : '7pt'}; }
td.number { font-size: $fontSize; }
td.sign { color: #333; font-size: 5pt; }
tr.detail, tr.total, tr.empty { height: ${targetPrintRowHeightMm.toStringAsFixed(2)}mm; }
tr.total { font-weight: 700; background: #ececec; }
tr.total td { border-top-width: 0.7pt; }
tr.empty td { text-align: center; padding: 4mm; }
@media screen { body { padding: 5mm; } }
</style>
</head>
<body>
<div class="heading">
  <div class="school">${_htmlEscape(schoolName)}</div>
  $addressHtml
  <div class="title">પીએમ પોષણ અને સીએમ અલ્પાહાર યોજના — દૈનિક હાજરી અહેવાલ</div>
  <div class="period">તારીખ: ${_htmlEscape(dateAndDay)}</div>
</div>
<table>
$columnGroupHtml
<thead>$headerHtml</thead>
<tbody>$tableBody</tbody>
</table>
</body>
</html>''';
  }

  static bool _reportRasterFontLoaded = false;
  static const String _reportRasterFontFamily = 'PSMReportGujaratiRaster';
  static const double _reportRasterDpr = 2.6;

  static Future<void> _ensureReportRasterFontLoaded() async {
    if (_reportRasterFontLoaded) return;
    final loader = FontLoader(_reportRasterFontFamily);
    loader.addFont(rootBundle.load('assets/fonts/NotoSansGujarati-Regular.ttf'));
    loader.addFont(rootBundle.load('assets/fonts/NotoSansGujarati-Bold.ttf'));
    await loader.load();
    _reportRasterFontLoaded = true;
  }

  Future<pw.Widget> _rasterReportText(
    String rawText, {
    required double maxWidthPt,
    required double fontSizePt,
    bool bold = false,
    TextAlign align = TextAlign.center,
    int maxLines = 2,
    required Map<String, ({pw.MemoryImage image, double wPt, double hPt})> cache,
  }) async {
    final cleaned = rawText
        .replaceAll(RegExp(r'_{2,}'), '')
        .trim();
    if (cleaned.isEmpty) {
      return pw.SizedBox(height: fontSizePt + 2);
    }
    final safeMaxW = maxWidthPt.clamp(14.0, 1100.0).toDouble();
    final key =
        '$cleaned|${fontSizePt.toStringAsFixed(2)}|$bold|${align.name}|${safeMaxW.toStringAsFixed(1)}|$maxLines';
    final existing = cache[key];
    if (existing != null) {
      return pw.Align(
        alignment: switch (align) {
          TextAlign.left => pw.Alignment.centerLeft,
          TextAlign.right => pw.Alignment.centerRight,
          _ => pw.Alignment.center,
        },
        child: pw.Image(
          existing.image,
          width: existing.wPt,
          height: existing.hPt,
          fit: pw.BoxFit.contain,
        ),
      );
    }

    await _ensureReportRasterFontLoaded();
    final painter = TextPainter(
      text: TextSpan(
        text: cleaned,
        style: TextStyle(
          fontFamily: _reportRasterFontFamily,
          fontFamilyFallback: const <String>[
            'NotoSansGujaratiLocal',
            'Noto Sans Gujarati',
            'Nirmala UI',
            'Shruti',
            'Roboto',
            'Segoe UI',
            'Arial',
            'sans-serif',
          ],
          fontSize: fontSizePt * _reportRasterDpr,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: Colors.black,
          height: 1.18,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: maxLines == 1 ? '…' : null,
    )..layout(minWidth: 0, maxWidth: safeMaxW * _reportRasterDpr);

    final imgW = (painter.width.ceil() + 4).clamp(1, 8000).toInt();
    final imgH = (painter.height.ceil() + 4).clamp(1, 2000).toInt();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble()),
    );
    painter.paint(canvas, const ui.Offset(2, 2));
    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(imgW, imgH);
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    uiImage.dispose();
    picture.dispose();
    if (byteData == null) {
      return pw.SizedBox(height: fontSizePt + 2);
    }
    final memImg = pw.MemoryImage(byteData.buffer.asUint8List());
    final wPt = imgW / _reportRasterDpr;
    final hPt = imgH / _reportRasterDpr;
    cache[key] = (image: memImg, wPt: wPt, hPt: hPt);

    return pw.Align(
      alignment: switch (align) {
        TextAlign.left => pw.Alignment.centerLeft,
        TextAlign.right => pw.Alignment.centerRight,
        _ => pw.Alignment.center,
      },
      child: pw.Image(
        memImg,
        width: wPt,
        height: hPt,
        fit: pw.BoxFit.contain,
      ),
    );
  }

  Future<Uint8List> buildSummaryPdfAsync({
    required String title,
    required String schoolName,
    String schoolAddress = '',
    required String periodLabel,
    required List<String> headers,
    required List<List<String>> rows,
    bool a3Landscape = false,
  }) async {
    await _ensureReportRasterFontLoaded();
    final doc = pw.Document();
    final pageFormat =
        a3Landscape ? PdfPageFormat.a3.landscape : PdfPageFormat.a4.landscape;
    const marginPt = 14.0;
    final availWidth = pageFormat.width - (marginPt * 2);
    final colCount = headers.isEmpty ? 1 : headers.length;

    // Dynamic column flex & font sizing:
    // Fewer selected columns -> bigger column width & bigger font size;
    // More selected columns -> smaller column width & smaller font size,
    // stretching across 100% of the full landscape page width with auto-wrapping text.
    final firstColFlex = colCount <= 8
        ? 2.1
        : colCount <= 14
            ? 2.4
            : colCount <= 22
                ? 2.6
                : 2.8;

    double colFlexFor(int c) {
      if (c == 0) return firstColFlex;
      final h = c < headers.length ? headers[c] : '';
      if (h.contains('સહી') || h.contains('પુસ્તક')) return 1.35;
      if (h.contains('•') || h.contains(' - ')) return 1.12;
      return 1.0;
    }

    var totalFlex = 0.0;
    for (var c = 0; c < colCount; c++) {
      totalFlex += colFlexFor(c);
    }
    if (totalFlex <= 0) totalFlex = 1.0;

    double colWidthPt(int colIdx) =>
        availWidth * (colFlexFor(colIdx) / totalFlex);

    final colWidths = <int, pw.TableColumnWidth>{
      for (var c = 0; c < colCount; c++)
        c: pw.FlexColumnWidth(colFlexFor(c)),
    };

    final double headerFontPt = colCount <= 8
        ? 9.6
        : colCount <= 12
            ? 8.6
            : colCount <= 18
                ? 7.5
                : colCount <= 26
                    ? 6.5
                    : colCount <= 36
                        ? 5.6
                        : 4.9;
    final double cellFontPt = colCount <= 8
        ? 9.2
        : colCount <= 12
            ? 8.2
            : colCount <= 18
                ? 7.2
                : colCount <= 26
                    ? 6.2
                    : colCount <= 36
                        ? 5.3
                        : 4.7;
    final double hPad = colCount <= 12 ? 3.5 : (colCount <= 24 ? 2.2 : 1.4);
    final double vPad = colCount <= 12 ? 3.6 : (colCount <= 24 ? 2.4 : 1.7);

    final cache = <String, ({pw.MemoryImage image, double wPt, double hPt})>{};

    final upperTitle = title.toUpperCase();
    final isPrincipalSignReport =
        upperTitle.contains('MDM') || upperTitle.contains('TARIJ');
    final signLabelText =
        isPrincipalSignReport ? 'આચાર્યની સહી :' : 'વર્ગ શિક્ષકની સહી :';

    Future<List<pw.TableRow>> buildTableRows(List<List<String>> sectionRows) async {
      // Build fresh header cell widgets per table so package:pdf never reuses
      // pw.Widget instances across multiple tables (which caused header overlap).
      final freshHeaderCells = <pw.Widget>[];
      for (var c = 0; c < colCount; c++) {
        final hText = c < headers.length ? headers[c] : '';
        final w = await _rasterReportText(
          hText,
          maxWidthPt: (colWidthPt(c) - (hPad * 2) - 1.0).clamp(12.0, 600.0),
          fontSizePt: headerFontPt,
          bold: true,
          align: TextAlign.center,
          maxLines: 3,
          cache: cache,
        );
        freshHeaderCells.add(
          pw.Container(
            padding: pw.EdgeInsets.symmetric(horizontal: hPad, vertical: vPad + 0.6),
            alignment: pw.Alignment.center,
            child: w,
          ),
        );
      }

      final out = <pw.TableRow>[
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: freshHeaderCells,
        ),
      ];

      for (final r in sectionRows) {
        final firstCell = r.isNotEmpty ? r[0].trim() : '';
        final isSummaryRow = firstCell.startsWith('કુલ') ||
            firstCell.contains('થી ધોરણ') ||
            firstCell.contains('કુલ શાળા');
        final rowCells = <pw.Widget>[];
        for (var c = 0; c < colCount; c++) {
          final cellText = c < r.length ? r[c] : '';
          final w = await _rasterReportText(
            cellText,
            maxWidthPt: (colWidthPt(c) - (hPad * 2) - 1.0).clamp(12.0, 600.0),
            fontSizePt: c == 0 ? (cellFontPt + 0.3) : cellFontPt,
            bold: isSummaryRow || c == 0,
            align: c == 0 ? TextAlign.left : TextAlign.center,
            maxLines: 2,
            cache: cache,
          );
          rowCells.add(
            pw.Container(
              padding: pw.EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
              alignment: c == 0 ? pw.Alignment.centerLeft : pw.Alignment.center,
              child: w,
            ),
          );
        }
        out.add(
          pw.TableRow(
            decoration: isSummaryRow
                ? const pw.BoxDecoration(color: PdfColors.grey200)
                : null,
            children: rowCells,
          ),
        );
      }
      return out;
    }

    Future<void> addReportSectionPage({
      required String sectionTitle,
      required List<List<String>> sectionRows,
    }) async {
      final fullSchoolHeader = schoolAddress.trim().isEmpty
          ? (schoolName.trim().isEmpty ? 'School' : schoolName.trim())
          : '${schoolName.trim().isEmpty ? 'School' : schoolName.trim()}, ${schoolAddress.trim()}';
      final schoolTitleWidget = await _rasterReportText(
        fullSchoolHeader,
        maxWidthPt: availWidth,
        fontSizePt: 13.0,
        bold: true,
        align: TextAlign.center,
        maxLines: 2,
        cache: cache,
      );
      final reportTitleWidget = await _rasterReportText(
        sectionTitle,
        maxWidthPt: availWidth,
        fontSizePt: 10.5,
        bold: true,
        align: TextAlign.center,
        maxLines: 2,
        cache: cache,
      );
      final periodWidget = await _rasterReportText(
        periodLabel,
        maxWidthPt: availWidth,
        fontSizePt: 8.5,
        bold: true,
        align: TextAlign.left,
        maxLines: 1,
        cache: cache,
      );
      final signLabelWidget = await _rasterReportText(
        signLabelText,
        maxWidthPt: 150,
        fontSizePt: 9.0,
        bold: true,
        align: TextAlign.left,
        maxLines: 1,
        cache: cache,
      );
      final builtRows = await buildTableRows(sectionRows);

      doc.addPage(
        pw.MultiPage(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(marginPt),
          build: (context) => <pw.Widget>[
            pw.Center(child: schoolTitleWidget),
            pw.SizedBox(height: 3),
            pw.Center(child: reportTitleWidget),
            pw.SizedBox(height: 3),
            periodWidget,
            pw.SizedBox(height: 6),
            pw.Table(
              columnWidths: colWidths,
              border: pw.TableBorder.all(color: PdfColors.grey800, width: 0.45),
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              children: builtRows,
            ),
            pw.SizedBox(height: 12),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: <pw.Widget>[
                signLabelWidget,
                pw.SizedBox(width: 6),
                pw.Container(
                  width: 150,
                  height: 10,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: PdfColors.black, width: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Split Tarij Page 1 and Page 2 onto separate full landscape pages
    final page2SepIdx = rows.indexWhere(
      (r) => r.isNotEmpty && r[0].trim().startsWith('=== TARIJ PAGE 2'),
    );

    if (page2SepIdx >= 0) {
      final page1Data = rows.sublist(0, page2SepIdx);
      final page2Data = rows.sublist(page2SepIdx + 1);
      await addReportSectionPage(
        sectionTitle: 'TARIJ — માસિક પત્રક (Page 1: વર્ગવાર અને જૂથવાર પત્રક)',
        sectionRows: page1Data,
      );
      await addReportSectionPage(
        sectionTitle: 'TARIJ — માસિક પત્રક (Page 2: ધોરણવાર સારાંશ પત્રક)',
        sectionRows: page2Data,
      );
    } else {
      await addReportSectionPage(
        sectionTitle: title,
        sectionRows: rows,
      );
    }

    return Uint8List.fromList(await doc.save());
  }
}

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'school_type.dart';
import 'xlsx_row_colors.dart';
import 'xlsx_sanitizer.dart';
import 'package:pmshri_attendance/services/class_label.dart';

/// Populates the school-provided 2026-27 Result workbook without rebuilding
/// its formatting. Existing cell styles, logos, merged cells, widths, hidden
/// columns, page setup and print decorations are preserved.
class ResultXlsxTemplateExporter {
  static const String assetPath =
      'assets/result_templates/RESULT_2026_27_TEMPLATE.xlsx';
  static const int _firstStudentRow = 7;
  static const int _maxTemplateStudentRows = 994; // rows 7 through 1000

  Future<Uint8List> build({
    required int semester,
    required String schoolType,
    required String classLabel,
    required List<String> subjects,
    required Map<String, dynamic> frontPageValues,
    required List<Map<String, dynamic>> studentRows,
    Uint8List? schoolLogoBytes,
    bool removeUnusedSubjectGroups = true,
    bool includeTailColumns = true,
    bool showParinamColumn = true,
    int? vvMaxOverride,
    int? grandMaxOverride,
    Set<String> sem2OnlySubjects = const <String>{},
  }) async {
    if (semester != 1 && semester != 2) {
      throw ArgumentError.value(semester, 'semester');
    }
    if (studentRows.isEmpty) {
      throw StateError('આ વર્ગમાં પરિણામ માટે કોઈ વિદ્યાર્થી નથી.');
    }
    if (studentRows.length > _maxTemplateStudentRows) {
      throw StateError(
          'ટેમ્પલેટમાં વધુમાં વધુ $_maxTemplateStudentRows વિદ્યાર્થીની હરોળ ઉપલબ્ધ છે.');
    }
    if (subjects.isEmpty) {
      throw StateError('પરિણામ માટે કોઈ વિષય પસંદ થયેલો નથી.');
    }
    // If a class has more than 7 subjects, extra subject column groups are
    // cloned automatically from the 7th template subject group below.

    final normalizedType = _normalizeSchoolType(schoolType);
    final coed = normalizedType == 'coed';
    final frontSheetIndex = semester == 1 ? 0 : 5;
    final resultSheetIndex = semester == 1 ? (coed ? 2 : 1) : (coed ? 4 : 6);
    final frontSheetName =
        semester == 1 ? 'FIRST SEM FRONT PAGE' : 'SECOND SEM FRONT PAGE';
    final resultSheetName = semester == 1
        ? (coed
            ? 'FIRST SEM RESULT for both gende'
            : 'FIRST SEM RESULT for single gen')
        : (coed
            ? 'SECOND SEM RESULT for both gend'
            : 'SECOND SEM RESULT for single ge');

    final baseColumns = coed ? 9 : 8;
    final groupWidth = semester == 1 ? 5 : 8;
    final firstSubjectColumn = baseColumns + 1;
    final resultSheetPath = 'xl/worksheets/sheet${resultSheetIndex + 1}.xml';
    final frontSheetPath = 'xl/worksheets/sheet${frontSheetIndex + 1}.xml';

    final loaded = await rootBundle.load(assetPath);
    final templateBytes = loaded.buffer.asUint8List(
      loaded.offsetInBytes,
      loaded.lengthInBytes,
    );
    final archive = ZipDecoder().decodeBytes(templateBytes, verify: true);

    String readText(String name) {
      for (final file in archive.files) {
        if (file.name == name) {
          final bytes = file.readBytes();
          if (bytes == null) break;
          return utf8.decode(bytes, allowMalformed: false);
        }
      }
      throw StateError('Result template file is missing: $name');
    }

    void writeText(String name, String text) {
      var index = -1;
      ArchiveFile? original;
      for (var i = 0; i < archive.files.length; i++) {
        if (archive.files[i].name == name) {
          index = i;
          original = archive.files[i];
          break;
        }
      }
      if (index < 0 || original == null) {
        throw StateError('Result template file is missing: $name');
      }
      final replacement = ArchiveFile.bytes(name, utf8.encode(text));
      replacement.compression = original.compression;
      replacement.comment = original.comment;
      archive.modifyAtIndex(index, replacement);
    }

    void writeBytesIfExists(String name, Uint8List bytes) {
      for (var i = 0; i < archive.files.length; i++) {
        final original = archive.files[i];
        if (original.name != name) continue;
        final replacement = ArchiveFile.bytes(name, bytes);
        replacement.compression = original.compression;
        replacement.comment = original.comment;
        archive.modifyAtIndex(i, replacement);
        return;
      }
    }

    if (includeTailColumns) {
      if (schoolLogoBytes != null && schoolLogoBytes.isNotEmpty) {
        writeBytesIfExists('xl/media/image1.png', schoolLogoBytes);
        writeBytesIfExists('xl/media/image2.png', schoolLogoBytes);
      }
      // Center the B4 logo across B4:U4 in drawing1.xml and drawing2.xml
      for (final drawingPath in const <String>[
        'xl/drawings/drawing1.xml',
        'xl/drawings/drawing2.xml',
      ]) {
        try {
          final drawingXml = readText(drawingPath);
          writeText(
            drawingPath,
            _centerFrontPageLogoInDrawing(drawingXml, schoolLogoBytes),
          );
        } catch (_) {}
      }
      var frontXml = readText(frontSheetPath);
      // Keep the exact Front Page setup from the template, only nudging the
      // page slightly upward (top="0.25", verticalCentered="0") and setting cell values.
      frontXml = frontXml
          .replaceAll('verticalCentered="1"', 'verticalCentered="0"')
          .replaceAll('top="0.75"', 'top="0.20"');
      final normalizedFrontPageValues =
          Map<String, dynamic>.from(frontPageValues);
      final rawB8 = (normalizedFrontPageValues['B8'] ?? '').toString().trim();
      if (rawB8.isNotEmpty) {
        final cleanedStd = ClassLabel.bare(rawB8);
        normalizedFrontPageValues['B8'] = 'ધોરણ:- $cleanedStd';
      }
      frontXml = _setCellValues(frontXml, normalizedFrontPageValues);
      writeText(frontSheetPath, frontXml);
    }

    var resultXml = readText(resultSheetPath);
    resultXml = _trimRowsAfter(resultXml, 1000);
    final lastStudentRow = _firstStudentRow + studentRows.length - 1;
    resultXml = _ensureTrailingStyledRows(
      resultXml,
      lastRow: lastStudentRow,
      prototypeRow: 9,
    );

    final templateSubjectSlots = subjects.length > 7 ? subjects.length : 7;
    if (templateSubjectSlots > 7) {
      resultXml = _insertExtraSubjectGroups(
        resultXml,
        baseColumns: baseColumns,
        groupWidth: groupWidth,
        extraGroups: templateSubjectSlots - 7,
      );
    }
    final tailStart = baseColumns + templateSubjectSlots * groupWidth + 1;
    final hasFirstSemParinam =
        semester == 1 && includeTailColumns && showParinamColumn;
    if (hasFirstSemParinam) {
      resultXml = _enableFirstSemParinamColumn(
        resultXml,
        tailStart: tailStart,
      );
    }
    final tailWidth = (semester == 1 && !hasFirstSemParinam) ? 7 : 8;
    final totalColumns =
        baseColumns + templateSubjectSlots * groupWidth + tailWidth;
    final activeSubjectCount = subjects.length.clamp(1, templateSubjectSlots);

    // Determine which columns should be hidden so only inserted subjects (and
    // tail columns when includeTailColumns == true) are printed!
    final hiddenColumns = <int>{};
    if (removeUnusedSubjectGroups) {
      for (var group = activeSubjectCount;
          group < templateSubjectSlots;
          group++) {
        final startCol = firstSubjectColumn + group * groupWidth;
        for (var offset = 0; offset < groupWidth; offset++) {
          hiddenColumns.add(startCol + offset);
        }
      }
    }
    if (!includeTailColumns) {
      for (var offset = 0; offset < tailWidth; offset++) {
        hiddenColumns.add(tailStart + offset);
      }
    } else if (semester == 2 && !showParinamColumn) {
      hiddenColumns.add(tailStart + 5);
    }

    final resultValues = <String, dynamic>{};
    final directSemester1MergeRanges = <String>[];
    for (var i = 0; i < templateSubjectSlots; i++) {
      final column = _columnName(firstSubjectColumn + i * groupWidth);
      resultValues['${column}2'] = i < subjects.length ? subjects[i] : '';
      // Second semester: subject total header (offset 6) shows its real
      // maximum; second-semester-only subjects have no first-semester marks.
      if (semester == 2 && i < subjects.length && groupWidth == 8) {
        final first = firstSubjectColumn + i * groupWidth;
        final only2 = sem2OnlySubjects.contains(subjects[i]);
        resultValues['${_columnName(first + 6)}3'] =
            'કુલ ગુણ ${only2 ? 100 : 200} માંથી મેળવેલ ગુણ';
        if (only2) {
          for (var k = 0; k < 3; k++) {
            resultValues['${_columnName(first + k)}5'] = '-';
          }
        }
      }
    }

    if (hasFirstSemParinam) {
      resultValues['${_columnName(tailStart + 5)}1'] = 'પરિણામ';
      resultValues['${_columnName(tailStart + 6)}1'] =
          'વિદ્યાર્થીનો U.I.D. નંબર';
      resultValues['${_columnName(tailStart + 7)}1'] =
          'વિદ્યાર્થીનો PEN નંબર';
    }

    // Dynamic maximum headers in Row 5 for Vyaktitva Vikas and Grand Total
    if (includeTailColumns) {
      if (vvMaxOverride != null && vvMaxOverride > 0) {
        resultValues['${_columnName(tailStart)}5'] = '$vvMaxOverride\nગુણ';
      }
      if (grandMaxOverride != null && grandMaxOverride > 0) {
        resultValues['${_columnName(tailStart + 2)}5'] =
            '$grandMaxOverride\nગુણ';
      }
    }

    // Renumber Row 6 column index numbers sequentially across visible columns
    final dobStartCol = coed ? 6 : 5;
    var nextColIndexNumber = 1;
    for (var col = 1; col <= totalColumns; col++) {
      if (hiddenColumns.contains(col)) {
        resultValues['${_columnName(col)}6'] = '';
        continue;
      }
      if (col == dobStartCol + 1 || col == dobStartCol + 2) {
        continue; // Inside merged DOB header cell
      }
      resultValues['${_columnName(col)}6'] = nextColIndexNumber++;
    }

    for (var i = 0; i < studentRows.length; i++) {
      final rowNumber = _firstStudentRow + i;
      final row = studentRows[i];
      final base = _asList(row['base']);
      final groups = _asList(row['groups']);
      final tail = _asList(row['tail']);

      for (var col = 1; col <= baseColumns; col++) {
        resultValues['${_columnName(col)}$rowNumber'] =
            col <= base.length ? base[col - 1] : '';
      }
      for (var group = 0; group < templateSubjectSlots; group++) {
        final values =
            group < groups.length ? _asList(groups[group]) : const <dynamic>[];
        final directSem1 =
            values.length > groupWidth && values[groupWidth] == true;
        if (directSem1 && group < activeSubjectCount) {
          final firstCol = firstSubjectColumn + group * groupWidth;
          directSemester1MergeRanges.add(
            '${_columnName(firstCol)}$rowNumber:${_columnName(firstCol + 2)}$rowNumber',
          );
        }
        for (var offset = 0; offset < groupWidth; offset++) {
          resultValues[
                  '${_columnName(firstSubjectColumn + group * groupWidth + offset)}$rowNumber'] =
              (group < activeSubjectCount && offset < values.length)
                  ? values[offset]
                  : '';
        }
      }
      for (var offset = 0; offset < tailWidth; offset++) {
        resultValues['${_columnName(tailStart + offset)}$rowNumber'] =
            (includeTailColumns && offset < tail.length) ? tail[offset] : '';
      }
    }
    resultXml = _setCellValues(resultXml, resultValues);
    resultXml = _appendMergeCells(resultXml, directSemester1MergeRanges);

    resultXml = _setStudentRowsVisibility(
      resultXml,
      first: _firstStudentRow,
      last: 1000,
      visibleLast: lastStudentRow,
    );
    resultXml = _trimRowsAfter(resultXml, lastStudentRow);

    final lastVisibleColumnNumber = includeTailColumns
        ? totalColumns
        : (firstSubjectColumn + activeSubjectCount * groupWidth - 1);

    resultXml = _applyColumnVisibility(
      resultXml,
      maxCol: totalColumns,
      hiddenColumns: hiddenColumns,
    );

    if (!includeTailColumns) {
      resultXml = _stripCellsAndMergesAfterColumn(
        resultXml,
        lastVisibleColumnNumber,
      );
    }

    final lastColumn = _columnName(lastVisibleColumnNumber);
    resultXml = _setDimension(
      resultXml,
      'A1:${lastColumn}$lastStudentRow',
    );
    resultXml = _setRowSpans(resultXml, lastVisibleColumnNumber);

    // Category font colour on every student row; in a mixed school boys and
    // girls also get different row backgrounds (same category colour).
    // The last student of each category (and overall) gets a double bottom
    // line, the same category separator as the Hajari Patrak register.
    String categoryOf(int i) {
      final base = _asList(studentRows[i]['base']);
      return XlsxRowColors.categoryKey(base.length > 2 ? base[2] : '');
    }
    final colorRows = <int, ({String category, String gender, bool categoryEnd})>{};
    for (var i = 0; i < studentRows.length; i++) {
      final base = _asList(studentRows[i]['base']);
      final category = categoryOf(i);
      colorRows[_firstStudentRow + i] = (
        category: category,
        gender: coed && base.length > 3 ? XlsxRowColors.genderKey(base[3]) : '',
        categoryEnd: i == studentRows.length - 1 || categoryOf(i + 1) != category,
      );
    }
    final colored = XlsxRowColors.apply(
      stylesXml: readText('xl/styles.xml'),
      sheetXml: resultXml,
      rows: colorRows,
      genderBackground: coed,
    );
    resultXml = colored.$1;
    writeText('xl/styles.xml', colored.$2);
    writeText(resultSheetPath, resultXml);

    var workbookXml = readText('xl/workbook.xml');
    final visibleSheets = includeTailColumns
        ? <String>{frontSheetName, resultSheetName}
        : <String>{resultSheetName};
    workbookXml = _setSheetVisibility(
      workbookXml,
      visibleNames: visibleSheets,
      activeTab: includeTailColumns ? frontSheetIndex : resultSheetIndex,
    );
    workbookXml = _setPrintTitles(
      workbookXml,
      sheetName: resultSheetName,
      localSheetId: resultSheetIndex,
      colsRange: r'$A:$B',
      rowsRange: r'$1:$6',
    );
    writeText('xl/workbook.xml', workbookXml);

    final encoded = ZipEncoder().encode(archive);
    if (encoded.isEmpty) {
      throw StateError('Result Excel workbook could not be encoded.');
    }
    return XlsxSanitizer.clean(Uint8List.fromList(encoded));
  }

  /// Adds an 8th tail column (`પરિણામ` at `tailStart + 5`, `UID` at `tailStart + 6`,
  /// `PEN` at `tailStart + 7`) to the First Semester Result sheet when the teacher
  /// chooses to insert the `પરિણામ` column in First Semester.
  /// Automatically clones the 7th subject group `extraGroups` times and shifts
  /// all tail columns (`Vyaktitva Vikas .. PEN`) right when `subjects.length > 7`.
  /// Centers the B4-anchored 200-point logo horizontally across the merged B4:U4
  /// banner on the Front Page while preserving its aspect ratio.
  static String _centerFrontPageLogoInDrawing(
    String drawingXml,
    Uint8List? logoBytes,
  ) {
    // Default 270x200 px (cx=2571750, cy=1905000 EMU)
    var widthPx = 270.0;
    const heightPx = 200.0;
    const cyEmu = 1905000;
    if (logoBytes != null &&
        logoBytes.length >= 24 &&
        logoBytes[0] == 0x89 &&
        logoBytes[1] == 0x50 &&
        logoBytes[2] == 0x4E &&
        logoBytes[3] == 0x47) {
      final w = (logoBytes[16] << 24) |
          (logoBytes[17] << 16) |
          (logoBytes[18] << 8) |
          logoBytes[19];
      final h = (logoBytes[20] << 24) |
          (logoBytes[21] << 16) |
          (logoBytes[22] << 8) |
          logoBytes[23];
      if (w > 0 && h > 0) {
        final aspect = (w / h).clamp(0.55, 2.2);
        widthPx = (heightPx * aspect).clamp(110.0, 440.0);
      }
    }
    final cxEmu = (widthPx * 9525).round();
    // Pixel widths of Front Page columns A..U (cols 1..21):
    // A=13, B=89, C..E=31 each, F..U=33 each -> B..U total = 710 px
    const colWidthsPx = <int>[
      13,
      89,
      31,
      31,
      31,
      33,
      33,
      33,
      33,
      33,
      33,
      33,
      33,
      33,
      33,
      33,
      33,
      33,
      33,
      33,
      33,
    ];
    const bToUWidthPx = 710.0;
    final targetLeftPx =
        colWidthsPx[0] + ((bToUWidthPx - widthPx) / 2.0).clamp(0.0, 600.0);
    var cursorPx = 0.0;
    var anchorColZeroBased = 6;
    var colOffEmu = 47625;
    for (var i = 0; i < colWidthsPx.length; i++) {
      final cw = colWidthsPx[i].toDouble();
      if (targetLeftPx < cursorPx + cw) {
        anchorColZeroBased = i;
        colOffEmu = ((targetLeftPx - cursorPx).clamp(0.0, cw - 1) * 9525).round();
        break;
      }
      cursorPx += cw;
    }

    var updated = drawingXml.replaceFirst(
      RegExp(r'<col>\d+</col>\s*<colOff>\d+</colOff>'),
      '<col>$anchorColZeroBased</col><colOff>$colOffEmu</colOff>',
    );
    updated = updated.replaceFirst(
      RegExp(r'<ext\s+cx="\d+"\s+cy="\d+"\s*/>'),
      '<ext cx="$cxEmu" cy="$cyEmu"/>',
    );
    return updated;
  }

  static String _insertExtraSubjectGroups(
    String xml, {
    required int baseColumns,
    required int groupWidth,
    required int extraGroups,
  }) {
    if (extraGroups <= 0) return xml;
    final firstSubCol = baseColumns + 1;
    final lastGrpStart = firstSubCol + 6 * groupWidth;
    final lastGrpEnd = lastGrpStart + groupWidth - 1;
    final oldTailStart = baseColumns + 7 * groupWidth + 1;
    final shiftCols = extraGroups * groupWidth;

    final cellPattern = RegExp(
      r'<c\b(?=[^>]*\br="([A-Z]{1,3})(\d+)")[^<>]*(?:/>|>[\s\S]*?</c>)',
    );
    final rowPattern = RegExp(
      r'<row\b(?=[^>]*\br="(\d+)")[^>]*(?:/>|>[\s\S]*?</row>)',
    );

    // 1. Shift tail cells right and insert cloned subject-group cells in every row
    var updated = xml.replaceAllMapped(rowPattern, (rowMatch) {
      final rowXml = rowMatch.group(0)!;
      if (rowXml.endsWith('/>')) return rowXml;
      final openEnd = rowXml.indexOf('>');
      final openTag = rowXml.substring(0, openEnd + 1);
      final inner = rowXml.substring(openEnd + 1, rowXml.lastIndexOf('</row>'));

      final beforeCells = <String>[];
      final grp6Cells = <({int colNum, String rowNum, String xml})>[];
      final tailCells = <({int colNum, String rowNum, String xml})>[];

      for (final cm in cellPattern.allMatches(inner)) {
        final cTag = cm.group(0)!;
        final colLetters = cm.group(1)!;
        final rNum = cm.group(2)!;
        final cNum = _columnNumber(colLetters);
        if (cNum < oldTailStart) {
          beforeCells.add(cTag);
          if (cNum >= lastGrpStart && cNum <= lastGrpEnd) {
            grp6Cells.add((colNum: cNum, rowNum: rNum, xml: cTag));
          }
        } else {
          tailCells.add((colNum: cNum, rowNum: rNum, xml: cTag));
        }
      }

      final clonedCells = <String>[];
      for (var g = 0; g < extraGroups; g++) {
        final delta = (g + 1) * groupWidth;
        for (final cell in grp6Cells) {
          final newCol = _columnName(cell.colNum + delta);
          clonedCells.add(
            cell.xml.replaceFirst(
              RegExp(r'\br="[A-Z]{1,3}\d+"'),
              'r="$newCol${cell.rowNum}"',
            ),
          );
        }
      }

      final shiftedTailCells = <String>[];
      for (final cell in tailCells) {
        final newCol = _columnName(cell.colNum + shiftCols);
        shiftedTailCells.add(
          cell.xml.replaceFirst(
            RegExp(r'\br="[A-Z]{1,3}\d+"'),
            'r="$newCol${cell.rowNum}"',
          ),
        );
      }

      final nonCellContent = inner.replaceAll(cellPattern, '');
      return '$openTag${beforeCells.join()}${clonedCells.join()}${shiftedTailCells.join()}$nonCellContent</row>';
    });

    // 2. Shift tail merge ranges and clone Group 6 merge ranges
    final mergeBlockPattern =
        RegExp(r'<mergeCells\b[^>]*>([\s\S]*?)</mergeCells>');
    final mergeMatch = mergeBlockPattern.firstMatch(updated);
    if (mergeMatch != null) {
      final mergeTagPattern = RegExp(
        r'<mergeCell\b[^>]*\bref="([A-Z]{1,3})(\d+):([A-Z]{1,3})(\d+)"[^>]*/>',
      );
      final newMerges = <String>[];
      final grp6Merges = <({int c1, String r1, int c2, String r2})>[];
      for (final mm in mergeTagPattern.allMatches(mergeMatch.group(1)!)) {
        final c1 = _columnNumber(mm.group(1)!);
        final r1 = mm.group(2)!;
        final c2 = _columnNumber(mm.group(3)!);
        final r2 = mm.group(4)!;
        if (c1 >= oldTailStart) {
          newMerges.add(
            '<mergeCell ref="${_columnName(c1 + shiftCols)}$r1:${_columnName(c2 + shiftCols)}$r2"/>',
          );
        } else {
          newMerges.add(mm.group(0)!);
          if (c1 >= lastGrpStart && c2 <= lastGrpEnd) {
            grp6Merges.add((c1: c1, r1: r1, c2: c2, r2: r2));
          }
        }
      }
      for (var g = 0; g < extraGroups; g++) {
        final delta = (g + 1) * groupWidth;
        for (final gm in grp6Merges) {
          newMerges.add(
            '<mergeCell ref="${_columnName(gm.c1 + delta)}${gm.r1}:${_columnName(gm.c2 + delta)}${gm.r2}"/>',
          );
        }
      }
      final replacement =
          '<mergeCells count="${newMerges.length}">${newMerges.join()}</mergeCells>';
      updated = updated.replaceRange(
        mergeMatch.start,
        mergeMatch.end,
        replacement,
      );
    }

    // 3. Extend subject <col> range and shift tail <col> ranges
    final colsPattern = RegExp(r'<cols\b[^>]*>([\s\S]*?)</cols>');
    final colsMatch = colsPattern.firstMatch(updated);
    if (colsMatch != null) {
      final colTagPattern = RegExp(r'<col\b[^>]*/>');
      final buffer = StringBuffer('<cols>');
      for (final m in colTagPattern.allMatches(colsMatch.group(1)!)) {
        final tag = m.group(0)!;
        final minVal = int.tryParse(
              RegExp(r'\bmin="(\d+)"').firstMatch(tag)?.group(1) ?? '',
            ) ??
            0;
        final maxVal = int.tryParse(
              RegExp(r'\bmax="(\d+)"').firstMatch(tag)?.group(1) ?? '',
            ) ??
            0;
        if (minVal <= 0 || maxVal <= 0) {
          buffer.write(tag);
          continue;
        }
        if (maxVal < oldTailStart) {
          if (maxVal == oldTailStart - 1) {
            buffer.write(_setAttribute(tag, 'max', '${maxVal + shiftCols}'));
          } else {
            buffer.write(tag);
          }
        } else if (minVal >= oldTailStart) {
          final shiftedMin = minVal + shiftCols;
          final shiftedMax =
              (maxVal + shiftCols) > 16384 ? 16384 : (maxVal + shiftCols);
          if (shiftedMin <= 16384) {
            var shifted = _setAttribute(tag, 'min', '$shiftedMin');
            shifted = _setAttribute(shifted, 'max', '$shiftedMax');
            buffer.write(shifted);
          }
        } else {
          // Range straddles oldTailStart
          var left = _setAttribute(tag, 'max', '${oldTailStart - 1 + shiftCols}');
          buffer.write(left);
          final shiftedMin = oldTailStart + shiftCols;
          final shiftedMax =
              (maxVal + shiftCols) > 16384 ? 16384 : (maxVal + shiftCols);
          if (shiftedMin <= 16384) {
            var right = _setAttribute(tag, 'min', '$shiftedMin');
            right = _setAttribute(right, 'max', '$shiftedMax');
            buffer.write(right);
          }
        }
      }
      buffer.write('</cols>');
      updated = updated.replaceRange(
        colsMatch.start,
        colsMatch.end,
        buffer.toString(),
      );
    }

    return updated;
  }

  static String _enableFirstSemParinamColumn(
    String xml, {
    required int tailStart,
  }) {
    final oldLastCol = tailStart + 6;
    final newLastCol = tailStart + 7;
    final oldLastColName = _columnName(oldLastCol);
    final newLastColName = _columnName(newLastCol);
    final parinamCol = tailStart + 5;
    final uidCol = tailStart + 6;

    // 1. Clone the oldLastCol cell in every row as newLastCol so styles/borders match
    final rowPattern = RegExp(
      r'<row\b(?=[^>]*\br="(\d+)")[^>]*(?:/>|>[\s\S]*?</row>)',
    );
    var updated = xml.replaceAllMapped(rowPattern, (rowMatch) {
      final rowXml = rowMatch.group(0)!;
      final rowNum = rowMatch.group(1)!;
      final cellPattern = RegExp(
        '<c\\b(?=[^>]*\\br="$oldLastColName$rowNum")[^<>]*(?:/>|>[\\s\\S]*?</c>)',
      );
      final cellMatch = cellPattern.firstMatch(rowXml);
      if (cellMatch == null) return rowXml;
      final clonedCell = cellMatch.group(0)!.replaceFirst(
            'r="$oldLastColName$rowNum"',
            'r="$newLastColName$rowNum"',
          );
      final insertPos = rowXml.lastIndexOf('</row>');
      if (insertPos < 0) return rowXml;
      return '${rowXml.substring(0, insertPos)}$clonedCell</row>';
    });

    // 2. Add the header merge for the new PEN column (e.g. AY1:AY5 or AZ1:AZ5)
    updated = _appendMergeCells(
      updated,
      <String>['${newLastColName}1:${newLastColName}5'],
    );

    // 3. Split the UID/PEN <col> range so parinamCol has width 10.140625 and
    //    uidCol..newLastCol have width 20.5703125
    final colsPattern = RegExp(r'<cols\b[^>]*>([\s\S]*?)</cols>');
    final colsMatch = colsPattern.firstMatch(updated);
    if (colsMatch != null) {
      final inner = colsMatch.group(1)!;
      final colTagPattern = RegExp(r'<col\b[^>]*/>');
      final buffer = StringBuffer('<cols>');
      for (final m in colTagPattern.allMatches(inner)) {
        final tag = m.group(0)!;
        final minVal = int.tryParse(
              RegExp(r'\bmin="(\d+)"').firstMatch(tag)?.group(1) ?? '',
            ) ??
            0;
        final maxVal = int.tryParse(
              RegExp(r'\bmax="(\d+)"').firstMatch(tag)?.group(1) ?? '',
            ) ??
            0;
        if (minVal == parinamCol && maxVal == oldLastCol) {
          var parinamTag = _setAttribute(tag, 'min', '$parinamCol');
          parinamTag = _setAttribute(parinamTag, 'max', '$parinamCol');
          parinamTag = _setAttribute(parinamTag, 'width', '10.140625');
          var uidPenTag = _setAttribute(tag, 'min', '$uidCol');
          uidPenTag = _setAttribute(uidPenTag, 'max', '$newLastCol');
          uidPenTag = _setAttribute(uidPenTag, 'width', '20.5703125');
          buffer.write(parinamTag);
          buffer.write(uidPenTag);
        } else {
          buffer.write(tag);
        }
      }
      buffer.write('</cols>');
      updated = updated.replaceRange(
        colsMatch.start,
        colsMatch.end,
        buffer.toString(),
      );
    }

    return updated;
  }

  /// Builds the official 40-statement Vyaktitva Vikas workbook sheet.
  /// Both Semester 1 and Semester 2 now have statements in C..AP (cols 3..42),
  /// Total in AQ (col 43), and in Semester 2 First Sem Total in AR (col 44)
  /// and Both-Semester Average in AS (col 45). All 40 headers C5..AP5 are
  /// rotated 90 degrees vertically.
  Future<Uint8List> buildVyaktitvaVikas({
    required int semester,
    required String classLabel,
    required String schoolName,
    required String academicYear,
    required List<String> sentenceTitles,
    required List<Map<String, dynamic>> studentRows,
  }) async {
    if (semester != 1 && semester != 2) {
      throw ArgumentError.value(semester, 'semester');
    }
    if (studentRows.isEmpty) {
      throw StateError('આ વર્ગમાં વ્યક્તિત્વ વિકાસ માટે કોઈ વિદ્યાર્થી નથી.');
    }
    if (studentRows.length > 995) {
      throw StateError(
          'વ્યક્તિત્વ વિકાસ પત્રકમાં વધુમાં વધુ 995 વિદ્યાર્થીની હરોળ ઉપલબ્ધ છે.');
    }
    if (sentenceTitles.length != 40) {
      throw StateError('વ્યક્તિત્વ વિકાસ માટે ચોક્કસ 40 વિધાનો જરૂરી છે.');
    }

    final sheetIndex = semester == 1 ? 3 : 7;
    final sheetName = semester == 1
        ? 'FIRST SEM VYAKTITV VIKAS'
        : '6 A SECOND SEM VYAKTITV VIKAS';
    final sheetPath = 'xl/worksheets/sheet${sheetIndex + 1}.xml';
    const firstStudentRow = 6;
    const firstSentenceColumn = 3; // Column C
    const totalColumn = 43; // Column AQ
    final lastColumnNumber = semester == 1 ? 43 : 45; // AQ or AS
    final lastColumn = _columnName(lastColumnNumber);
    final lastStudentRow = firstStudentRow + studentRows.length - 1;

    final loaded = await rootBundle.load(assetPath);
    final templateBytes = loaded.buffer.asUint8List(
      loaded.offsetInBytes,
      loaded.lengthInBytes,
    );
    final archive = ZipDecoder().decodeBytes(templateBytes, verify: true);

    String readText(String name) {
      for (final file in archive.files) {
        if (file.name == name) {
          final bytes = file.readBytes();
          if (bytes == null) break;
          return utf8.decode(bytes, allowMalformed: false);
        }
      }
      throw StateError('Result template file is missing: $name');
    }

    void writeText(String name, String text) {
      var index = -1;
      ArchiveFile? original;
      for (var i = 0; i < archive.files.length; i++) {
        if (archive.files[i].name == name) {
          index = i;
          original = archive.files[i];
          break;
        }
      }
      if (index < 0 || original == null) {
        throw StateError('Result template file is missing: $name');
      }
      final replacement = ArchiveFile.bytes(name, utf8.encode(text));
      replacement.compression = original.compression;
      replacement.comment = original.comment;
      archive.modifyAtIndex(index, replacement);
    }

    var sheetXml = readText(sheetPath);
    sheetXml = _ensureTrailingStyledRows(
      sheetXml,
      lastRow: lastStudentRow,
      prototypeRow: 9,
    );

    final values = <String, dynamic>{
      'A2': 'ધોરણ:- ${ClassLabel.bare(classLabel)}',
      'C2': semester == 1 ? 'પ્રથમ સત્ર' : 'દ્વિતિય સત્ર',
      'H2': schoolName,
      'AE2': 'વર્ષ - $academicYear',
    };
    for (var i = 0; i < 40; i++) {
      values['${_columnName(firstSentenceColumn + i)}5'] = sentenceTitles[i];
    }

    for (var i = 0; i < studentRows.length; i++) {
      final rowNumber = firstStudentRow + i;
      final row = studentRows[i];
      final sentenceValues = _asList(row['sentences']);
      if (sentenceValues.length != 40) {
        throw StateError(
            'વિદ્યાર્થી ${row['name'] ?? ''} માટે 40 વિધાનના ગુણ ઉપલબ્ધ નથી.');
      }
      values['A$rowNumber'] = row['roll'] ?? '';
      values['B$rowNumber'] = row['name'] ?? '';
      for (var sentence = 0; sentence < 40; sentence++) {
        values['${_columnName(firstSentenceColumn + sentence)}$rowNumber'] =
            sentenceValues[sentence];
      }
      values['${_columnName(totalColumn)}$rowNumber'] = row['total'] ?? 0;
      if (semester == 2) {
        values['AR$rowNumber'] = row['firstSemesterTotal'] ?? 0;
        values['AS$rowNumber'] = row['average'] ?? 0;
      }
    }

    sheetXml = _setCellValues(sheetXml, values);
    sheetXml = _enforceVvHeader90DegreeStyle(sheetXml);
    {
      // Marks and their headings sit in the middle of their cells (columns C
      // onwards); roll number and student name keep the template alignment.
      final centred = _centerCells(readText('xl/styles.xml'), sheetXml,
          (col, row) => col >= 3 && row >= 4);
      sheetXml = centred.$1;
      writeText('xl/styles.xml', centred.$2);
    }
    sheetXml = _setStudentRowsVisibility(
      sheetXml,
      first: firstStudentRow,
      last: 1000,
      visibleLast: lastStudentRow,
    );
    sheetXml = _trimRowsAfter(sheetXml, lastStudentRow);
    sheetXml = _ensureOverThenDownAndCleanColBreaks(
      sheetXml,
      clearColBreaks: true,
      forceLegalLandscape: true,
    );
    sheetXml = _setDimension(sheetXml, 'A1:${lastColumn}$lastStudentRow');
    sheetXml = _setRowSpans(sheetXml, lastColumnNumber);
    writeText(sheetPath, sheetXml);

    var workbookXml = readText('xl/workbook.xml');
    workbookXml = _setSheetVisibility(
      workbookXml,
      visibleNames: <String>{sheetName},
      activeTab: sheetIndex,
    );
    workbookXml = _setPrintArea(
      workbookXml,
      sheetName: sheetName,
      localSheetId: sheetIndex,
      range: '\$A\$1:\$$lastColumn\$$lastStudentRow',
    );
    workbookXml = _setPrintTitles(
      workbookXml,
      sheetName: sheetName,
      localSheetId: sheetIndex,
      colsRange: r'$A:$B',
      rowsRange: r'$1:$5',
    );
    writeText('xl/workbook.xml', workbookXml);

    final encoded = ZipEncoder().encode(archive);
    if (encoded.isEmpty) {
      throw StateError('Vyaktitva Vikas workbook could not be encoded.');
    }
    return XlsxSanitizer.clean(Uint8List.fromList(encoded));
  }

  /// Copies the style of every cell for which [test] is true with
  /// horizontal and vertical centre alignment (rotation and wrap kept).
  static (String, String) _centerCells(
      String stylesXml, String sheetXml, bool Function(int col, int row) test) {
    final xfsMatch =
        RegExp(r'<cellXfs\b[^>]*>[\s\S]*?</cellXfs>').firstMatch(stylesXml);
    if (xfsMatch == null) return (sheetXml, stylesXml);
    final xfs = RegExp(r'<xf\b[^>]*?(?:/>|>[\s\S]*?</xf>)')
        .allMatches(xfsMatch.group(0)!)
        .map((m) => m.group(0)!)
        .toList();
    final cache = <int, int>{};
    int centred(int id) {
      if (id < 0 || id >= xfs.length) id = 0;
      return cache.putIfAbsent(id, () {
        var xf = xfs[id];
        String align(String a) {
          a = a
              .replaceAll(RegExp(r'\s*horizontal="[^"]*"'), '')
              .replaceAll(RegExp(r'\s*vertical="[^"]*"'), '');
          return '$a horizontal="center" vertical="center"';
        }
        if (xf.contains('<alignment')) {
          xf = xf.replaceFirstMapped(RegExp(r'<alignment\b([^>]*?)/>'),
              (m) => '<alignment${align(m.group(1)!)}/>');
        } else if (xf.endsWith('/>')) {
          xf = '${xf.substring(0, xf.length - 2)}><alignment${align('')}/></xf>';
        } else {
          xf = xf.replaceFirst('</xf>', '<alignment${align('')}/></xf>');
        }
        xf = RegExp(r'\bapplyAlignment="[^"]*"').hasMatch(xf)
            ? xf.replaceFirst(RegExp(r'\bapplyAlignment="[^"]*"'), 'applyAlignment="1"')
            : xf.replaceFirst('<xf ', '<xf applyAlignment="1" ');
        xfs.add(xf);
        return xfs.length - 1;
      });
    }

    final sheet = sheetXml.replaceAllMapped(
      RegExp(r'<c r="([A-Z]{1,3})(\d+)"([^>]*?)(/?)>'),
      (m) {
        final col = _columnNumber(m.group(1)!);
        final row = int.parse(m.group(2)!);
        if (!test(col, row)) return m.group(0)!;
        final rest = m.group(3)!;
        final sMatch = RegExp(r'\bs="(\d+)"').firstMatch(rest);
        final nid = centred(int.tryParse(sMatch?.group(1) ?? '0') ?? 0);
        final newRest = sMatch == null ? '$rest s="$nid"' : rest.replaceFirst(sMatch.group(0)!, 's="$nid"');
        return '<c r="${m.group(1)}${m.group(2)}"$newRest${m.group(4)}>';
      },
    );
    final xfsXml = xfsMatch.group(0)!;
    final head = xfsXml
        .substring(0, xfsXml.indexOf('>') + 1)
        .replaceFirst(RegExp(r'\bcount="\d+"'), 'count="${xfs.length}"');
    return (
      sheet,
      stylesXml.replaceRange(xfsMatch.start, xfsMatch.end, '$head${xfs.join()}</cellXfs>'),
    );
  }

  /// Ensures all 40 sentence header cells C5..AP5 use the vertical 90° style
  /// from D5 (`s="38"`) so C5 and AP5 are never 0° or mismatched.
  static String _enforceVvHeader90DegreeStyle(String xml) {
    final row5Pattern = RegExp(
      r'<row\b(?=[^>]*\br="5")[^>]*>([\s\S]*?)</row>',
    );
    final match = row5Pattern.firstMatch(xml);
    if (match == null) return xml;
    final rowXml = match.group(0)!;
    final d5Style = RegExp(r'<c\b[^>]*\br="D5"[^>]*\bs="(\d+)"')
            .firstMatch(rowXml)
            ?.group(1) ??
        '38';
    final updatedRow = rowXml.replaceAllMapped(
      RegExp(r'<c\b(?=[^>]*\br="([A-Z]{1,2})5")[^>]*>'),
      (cellMatch) {
        final colLetters = cellMatch.group(1)!;
        final colNum = _columnNumber(colLetters);
        if (colNum < 3 || colNum > 42) return cellMatch.group(0)!;
        return _setAttribute(cellMatch.group(0)!, 's', d5Style);
      },
    );
    return xml.replaceRange(match.start, match.end, updatedRow);
  }

  static String _applyColumnVisibility(
    String xml, {
    required int maxCol,
    required Set<int> hiddenColumns,
  }) {
    if (hiddenColumns.isEmpty) return xml;
    final colsPattern = RegExp(r'<cols\b[^>]*>([\s\S]*?)</cols>');
    final match = colsPattern.firstMatch(xml);
    if (match == null) return xml;
    final inner = match.group(1)!;
    final colTagPattern = RegExp(r'<col\b[^>]*/>');
    final buffer = StringBuffer('<cols>');
    for (final colMatch in colTagPattern.allMatches(inner)) {
      final tag = colMatch.group(0)!;
      final minVal = int.tryParse(
            RegExp(r'\bmin="(\d+)"').firstMatch(tag)?.group(1) ?? '',
          ) ??
          0;
      final maxVal = int.tryParse(
            RegExp(r'\bmax="(\d+)"').firstMatch(tag)?.group(1) ?? '',
          ) ??
          0;
      if (minVal <= 0 || maxVal <= 0 || minVal > maxCol) {
        buffer.write(tag);
        continue;
      }
      final intersectsHidden = hiddenColumns.any(
        (c) => c >= minVal && c <= maxVal,
      );
      if (!intersectsHidden) {
        buffer.write(tag);
        continue;
      }
      for (var c = minVal; c <= maxVal; c++) {
        var single = _setAttribute(tag, 'min', '$c');
        single = _setAttribute(single, 'max', '$c');
        if (hiddenColumns.contains(c)) {
          single = _setAttribute(single, 'hidden', '1');
        } else {
          single = single.replaceAll(RegExp(r'\s+hidden="[^"]*"'), '');
        }
        buffer.write(single);
      }
    }
    buffer.write('</cols>');
    return xml.replaceRange(match.start, match.end, buffer.toString());
  }

  static String _stripCellsAndMergesAfterColumn(String xml, int maxAllowedCol) {
    final cellPattern = RegExp(
      r'<c\b(?=[^>]*\br="([A-Z]{1,3})\d+")[^<>]*(?:/>|>[\s\S]*?</c>)',
    );
    var updated = xml.replaceAllMapped(cellPattern, (m) {
      final colLetters = m.group(1)!;
      return _columnNumber(colLetters) <= maxAllowedCol ? m.group(0)! : '';
    });
    final mergeBlockPattern = RegExp(r'<mergeCells\b[^>]*>([\s\S]*?)</mergeCells>');
    final mergeMatch = mergeBlockPattern.firstMatch(updated);
    if (mergeMatch != null) {
      final mergeTags = RegExp(r'<mergeCell\b[^>]*\bref="([A-Z]{1,3})\d+:([A-Z]{1,3})\d+"[^>]*/>')
          .allMatches(mergeMatch.group(1)!)
          .where((m) =>
              _columnNumber(m.group(1)!) <= maxAllowedCol &&
              _columnNumber(m.group(2)!) <= maxAllowedCol)
          .map((m) => m.group(0)!)
          .toList();
      final replacement = mergeTags.isEmpty
          ? ''
          : '<mergeCells count="${mergeTags.length}">${mergeTags.join()}</mergeCells>';
      updated = updated.replaceRange(
        mergeMatch.start,
        mergeMatch.end,
        replacement,
      );
    }
    return updated;
  }

  static String _ensureOverThenDownAndCleanColBreaks(
    String xml, {
    required bool clearColBreaks,
    bool forceLegalLandscape = false,
  }) {
    final pageSetupPattern = RegExp(r'<pageSetup\b[^>]*/>');
    if (pageSetupPattern.hasMatch(xml)) {
      xml = xml.replaceFirstMapped(pageSetupPattern, (m) {
        var tag = _setAttribute(m.group(0)!, 'pageOrder', 'overThenDown');
        if (forceLegalLandscape) {
          tag = _setAttribute(tag, 'paperSize', '5'); // 5 = Legal
          tag = _setAttribute(tag, 'orientation', 'landscape');
        }
        return tag;
      });
    } else if (forceLegalLandscape && xml.contains('</worksheet>')) {
      xml = xml.replaceFirst(
        '</worksheet>',
        '<pageSetup paperSize="5" orientation="landscape" pageOrder="overThenDown"/></worksheet>',
      );
    }
    if (clearColBreaks) {
      xml = xml.replaceAll(
        RegExp(r'<colBreaks\b[^>]*>[\s\S]*?</colBreaks>'),
        '',
      );
    }
    return xml;
  }

  static String _normalizeSchoolType(String raw) => SchoolType.coedCompat(raw);

  static List<dynamic> _asList(dynamic value) =>
      value is List ? List<dynamic>.from(value) : const <dynamic>[];

  static String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _setCellValues(String xml, Map<String, dynamic> values) {
    if (values.isEmpty) return xml;
    final remaining = values.keys.toSet();
    final cellPattern = RegExp(
      r'<c\b(?=[^>]*\br="([A-Z]{1,3}\d+)")[^<>]*(?:/>|>[\s\S]*?</c>)',
    );
    var updated = xml.replaceAllMapped(cellPattern, (match) {
      final old = match.group(0)!;
      final ref = RegExp(r'\br="([A-Z]{1,3}\d+)"').firstMatch(old)?.group(1);
      if (ref == null || !values.containsKey(ref)) return old;
      remaining.remove(ref);
      return _buildCellTag(old, values[ref]);
    });
    if (remaining.isEmpty) return updated;

    final prototypeRowPattern = RegExp(
      r'<row\b(?=[^>]*\br="9")[^>]*>([\s\S]*?)</row>',
    );
    final prototype = prototypeRowPattern.firstMatch(updated);
    if (prototype == null) {
      throw StateError(
          'The Result template is missing its styled prototype row 9.');
    }
    final stylesByColumn = <String, String>{};
    void collectColumnStyles(String cellXml) {
      for (final match in cellPattern.allMatches(cellXml)) {
        final cell = match.group(0)!;
        final ref = RegExp(r'\br="([A-Z]{1,3})\d+"').firstMatch(cell);
        if (ref == null) continue;
        final column = ref.group(1)!;
        final style = RegExp(r'\bs="(\d+)"').firstMatch(cell)?.group(1);
        if (style != null && style.isNotEmpty) {
          stylesByColumn.putIfAbsent(column, () => ' s="$style"');
        }
      }
    }

    collectColumnStyles(prototype.group(1)!);
    collectColumnStyles(updated);

    final byRow = <int, List<String>>{};
    for (final address in remaining) {
      final match = RegExp(r'^([A-Z]{1,3})(\d+)$').firstMatch(address);
      if (match == null) continue;
      final column = match.group(1)!;
      final rowNumber = int.parse(match.group(2)!);
      final style = stylesByColumn[column] ?? '';
      final emptyCell = '<c r="$address"$style/>';
      byRow.putIfAbsent(rowNumber, () => <String>[]).add(
            _buildCellTag(emptyCell, values[address]),
          );
    }

    final sortedRows = byRow.keys.toList()..sort();
    for (final rowNumber in sortedRows) {
      final rowPattern = RegExp(
        '<row\\b(?=[^>]*\\br="$rowNumber")[^>]*(?:/>|>[\\s\\S]*?</row>)',
      );
      final rowMatch = rowPattern.firstMatch(updated);
      if (rowMatch == null) {
        throw StateError(
            'The Result template is missing student row $rowNumber.');
      }
      final oldRow = rowMatch.group(0)!;
      final openEnd = oldRow.indexOf('>');
      var openTag = oldRow.substring(0, openEnd + 1);
      if (openTag.endsWith('/>')) {
        openTag = '${openTag.substring(0, openTag.length - 2)}>';
      }
      final inner = oldRow.endsWith('/>')
          ? ''
          : oldRow.substring(openEnd + 1, oldRow.lastIndexOf('</row>'));
      final existingCells =
          cellPattern.allMatches(inner).map((m) => m.group(0)!).toList();
      final allCells = <String>[...existingCells, ...byRow[rowNumber]!];
      allCells.sort((a, b) {
        final ar = RegExp(r'\br="([A-Z]{1,3})\d+"').firstMatch(a)!.group(1)!;
        final br = RegExp(r'\br="([A-Z]{1,3})\d+"').firstMatch(b)!.group(1)!;
        return _columnNumber(ar).compareTo(_columnNumber(br));
      });
      final nonCellContent = inner.replaceAll(cellPattern, '');
      final newRow = '$openTag${allCells.join()}$nonCellContent</row>';
      updated = updated.replaceRange(rowMatch.start, rowMatch.end, newRow);
    }
    return updated;
  }

  static String _buildCellTag(String old, dynamic value) {
    final endOfOpenTag = old.indexOf('>');
    if (endOfOpenTag < 0) {
      throw StateError('Invalid cell XML in the Result template.');
    }
    var attributes = old.substring(2, endOfOpenTag).trim();
    attributes = attributes.replaceAll(RegExp(r'\s*/$'), '');
    attributes = attributes.replaceAll(RegExp(r'\s+t="[^"]*"'), '');
    final attrText = attributes.isEmpty ? '' : ' $attributes';

    if (value == null || (value is String && value.isEmpty)) {
      return '<c$attrText/>';
    }
    if (value is num && value.isFinite) {
      return '<c$attrText><v>$value</v></c>';
    }
    if (value is bool) {
      return '<c$attrText t="b"><v>${value ? 1 : 0}</v></c>';
    }
    return '<c$attrText t="inlineStr"><is><t xml:space="preserve">${_xmlEscape('$value')}</t></is></c>';
  }

  static String _trimRowsAfter(String xml, int lastAllowedRow) {
    final firstRemovedRow = lastAllowedRow + 1;
    final rowStartPattern = RegExp(
      '<row\\b(?=[^>]*\\br="$firstRemovedRow")[^>]*>',
    );
    final start = rowStartPattern.firstMatch(xml)?.start;
    if (start == null) return xml;
    final end = xml.indexOf('</sheetData>', start);
    if (end < 0) throw StateError('Invalid Result template sheetData XML.');
    return xml.replaceRange(start, end, '');
  }

  static String _ensureTrailingStyledRows(
    String xml, {
    required int lastRow,
    required int prototypeRow,
  }) {
    final sheetDataPattern = RegExp(
      r'(<sheetData\b[^>]*>)([\s\S]*?)(</sheetData>)',
    );
    final sheetData = sheetDataPattern.firstMatch(xml);
    if (sheetData == null) {
      throw StateError('Invalid Result template sheetData XML.');
    }
    final inner = sheetData.group(2)!;
    final rowPattern = RegExp(
      r'<row\b(?=[^>]*\br="(\d+)")[^>]*(?:/>|>[\s\S]*?</row>)',
    );
    final rowsByNumber = <int, String>{};
    for (final match in rowPattern.allMatches(inner)) {
      final rowTag = match.group(0)!;
      final rowNumber = int.tryParse(
        RegExp(r'\br="(\d+)"').firstMatch(rowTag)?.group(1) ?? '',
      );
      if (rowNumber != null) rowsByNumber[rowNumber] = rowTag;
    }
    if (rowsByNumber.isEmpty) {
      throw StateError('The Result template contains no styled student rows.');
    }
    final highestExisting = rowsByNumber.keys.reduce((a, b) => a > b ? a : b);

    final prototype = rowsByNumber[prototypeRow];
    if (prototype == null) {
      throw StateError(
          'The Result template is missing its styled prototype row $prototypeRow.');
    }
    String clone(int rowNumber) => prototype
        .replaceFirst(RegExp(r'\br="\d+"'), 'r="$rowNumber"')
        .replaceAllMapped(RegExp(r'\br="([A-Z]{1,3})\d+"'),
            (match) => 'r="${match.group(1)}$rowNumber"')
        .replaceAll(RegExp(r'\s+hidden="[^"]*"'), '');
    String? styleOfB(String rowTag) => RegExp(r'<c\b[^>]*\br="B\d+"[^>]*\bs="(\d+)"').firstMatch(rowTag)?.group(1);
    // The template only styles the first rows of the student area. Rows
    // that exist further down but still carry the plain sheet style (other
    // height and other column-B style) are replaced by the prototype row so
    // large classes keep borders, alignment and fonts.
    final protoB = styleOfB(prototype);
    // Last row of the styled block (rows like the prototype), plus the
    // closing row after it that may carry the table's bottom border.
    var styledEnd = prototypeRow;
    for (var r = prototypeRow + 1; r <= highestExisting; r++) {
      final row = rowsByNumber[r];
      if (row == null || styleOfB(row) != protoB) break;
      styledEnd = r;
    }
    // Keep the closing row only when it is a real table row (same height).
    String? heightOf(String rowTag) =>
        RegExp(r'\bht="([^"]*)"').firstMatch(rowTag.substring(0, rowTag.indexOf('>') + 1))?.group(1);
    final closing = rowsByNumber[styledEnd + 1];
    final firstToFix = closing != null && heightOf(closing) == heightOf(prototype)
        ? styledEnd + 2
        : styledEnd + 1;
    var fixedInner = inner;
    for (var rowNumber = firstToFix;
        rowNumber <= lastRow && rowNumber <= highestExisting;
        rowNumber++) {
      final existing = rowsByNumber[rowNumber];
      if (existing == null) continue;
      if (styleOfB(existing) != protoB) {
        fixedInner = fixedInner.replaceFirst(existing, clone(rowNumber));
      }
    }
    if (lastRow <= highestExisting) {
      if (identical(fixedInner, inner)) return xml;
      return xml.replaceRange(sheetData.start, sheetData.end,
          '${sheetData.group(1)}$fixedInner${sheetData.group(3)}');
    }
    final output = StringBuffer(fixedInner);
    for (var rowNumber = highestExisting + 1;
        rowNumber <= lastRow;
        rowNumber++) {
      var clonedRow = prototype.replaceFirst(
        RegExp(r'\br="\d+"'),
        'r="$rowNumber"',
      );
      clonedRow = clonedRow.replaceAllMapped(
        RegExp(r'\br="([A-Z]{1,3})\d+"'),
        (match) => 'r="${match.group(1)}$rowNumber"',
      );
      clonedRow = clonedRow.replaceAll(RegExp(r'\s+hidden="[^"]*"'), '');
      output.write(clonedRow);
    }
    final replacement =
        '${sheetData.group(1)}${output.toString()}${sheetData.group(3)}';
    return xml.replaceRange(sheetData.start, sheetData.end, replacement);
  }

  static String _setStudentRowsVisibility(
    String xml, {
    required int first,
    required int last,
    required int visibleLast,
  }) {
    final pattern = RegExp(r'<row\b[^>]*\br="(\d+)"[^>]*>');
    return xml.replaceAllMapped(pattern, (match) {
      final number = int.tryParse(match.group(1) ?? '');
      if (number == null || number < first || number > last) {
        return match.group(0)!;
      }
      var tag = match.group(0)!;
      if (number <= visibleLast) {
        tag = tag.replaceAll(RegExp(r'\s+hidden="[^"]*"'), '');
      } else {
        tag = _setAttribute(tag, 'hidden', '1');
      }
      return tag;
    });
  }

  static String _setAttribute(String tag, String name, String value) {
    final pattern = RegExp('\\s+$name="[^"]*"');
    final replacement = ' $name="$value"';
    if (pattern.hasMatch(tag)) return tag.replaceFirst(pattern, replacement);
    final end = tag.endsWith('/>') ? tag.length - 2 : tag.length - 1;
    return '${tag.substring(0, end)}$replacement${tag.substring(end)}';
  }

  static String _setDimension(String xml, String ref) {
    final pattern = RegExp(r'<dimension\b[^>]*/>');
    if (!pattern.hasMatch(xml)) return xml;
    return xml.replaceFirstMapped(pattern, (match) {
      var tag = match.group(0)!;
      tag = _setAttribute(tag, 'ref', ref);
      return tag;
    });
  }

  static String _setRowSpans(String xml, int maxColumn) {
    return xml.replaceAllMapped(RegExp(r'<row\b[^>]*>'), (match) {
      return _setAttribute(match.group(0)!, 'spans', '1:$maxColumn');
    });
  }

  static String _setSheetVisibility(
    String xml, {
    required Set<String> visibleNames,
    required int activeTab,
  }) {
    final sheetPattern = RegExp(r'<sheet\b[^>]*/>');
    xml = xml.replaceAllMapped(sheetPattern, (match) {
      final tag = match.group(0)!;
      final nameMatch = RegExp(r'\bname="([^"]+)"').firstMatch(tag);
      final name = nameMatch?.group(1) ?? '';
      final visible = visibleNames.contains(name);
      var result = tag.replaceAll(RegExp(r'\s+state="[^"]*"'), '');
      if (!visible) result = _setAttribute(result, 'state', 'hidden');
      return result;
    });
    final viewPattern = RegExp(r'<workbookView\b[^>]*/>');
    if (viewPattern.hasMatch(xml)) {
      xml = xml.replaceFirstMapped(viewPattern,
          (match) => _setAttribute(match.group(0)!, 'activeTab', '$activeTab'));
    }
    return xml;
  }

  static String _appendMergeCells(String xml, Iterable<String> ranges) {
    final uniqueRanges = ranges.toSet();
    if (uniqueRanges.isEmpty) return xml;

    final mergePattern = RegExp(r'<mergeCells\b[^>]*>[\s\S]*?</mergeCells>');
    final match = mergePattern.firstMatch(xml);
    if (match == null) {
      throw StateError('The Result template has no mergeCells section.');
    }

    final existingBlock = match.group(0)!;
    final openingEnd = existingBlock.indexOf('>');
    if (openingEnd < 0) {
      throw StateError('The Result template mergeCells section is invalid.');
    }
    var openingTag = existingBlock.substring(0, openingEnd + 1);
    final body = existingBlock.substring(
      openingEnd + 1,
      existingBlock.lastIndexOf('</mergeCells>'),
    );
    final existingRanges = RegExp(r'<mergeCell\b[^>]*\bref="([^"]+)"[^>]*/>')
        .allMatches(body)
        .map((m) => m.group(1)!)
        .toSet();
    final additions = uniqueRanges
        .where((range) => !existingRanges.contains(range))
        .toList(growable: false);
    if (additions.isEmpty) return xml;

    final newCount = existingRanges.length + additions.length;
    openingTag = _setAttribute(openingTag, 'count', '$newCount');
    final addedXml =
        additions.map((range) => '<mergeCell ref="$range"/>').join();
    final replacement = '$openingTag$body$addedXml</mergeCells>';
    return xml.replaceRange(match.start, match.end, replacement);
  }

  static String _setPrintArea(
    String xml, {
    required String sheetName,
    required int localSheetId,
    required String range,
  }) {
    final namePattern = RegExp(
      '<definedName\\b(?=[^>]*\\bname="_xlnm\\.Print_Area")(?=[^>]*\\blocalSheetId="$localSheetId")[^>]*>[\\s\\S]*?</definedName>',
    );
    final content = "'${sheetName.replaceAll("'", "''")}'!$range";
    if (namePattern.hasMatch(xml)) {
      return xml.replaceFirstMapped(namePattern, (match) {
        final openEnd = match.group(0)!.indexOf('>');
        final open = match.group(0)!.substring(0, openEnd + 1);
        return '$open${_xmlEscape(content)}</definedName>';
      });
    }
    final close = '</definedNames>';
    final tag =
        '<definedName name="_xlnm.Print_Area" localSheetId="$localSheetId">${_xmlEscape(content)}</definedName>';
    if (xml.contains(close)) return xml.replaceFirst(close, '$tag$close');
    return xml.replaceFirst(
        '</workbook>', '<definedNames>$tag</definedNames></workbook>');
  }

  static String _setPrintTitles(
    String xml, {
    required String sheetName,
    required int localSheetId,
    required String colsRange,
    required String rowsRange,
  }) {
    final namePattern = RegExp(
      '<definedName\\b(?=[^>]*\\bname="_xlnm\\.Print_Titles")(?=[^>]*\\blocalSheetId="$localSheetId")[^>]*>[\\s\\S]*?</definedName>',
    );
    final safeSheet = "'${sheetName.replaceAll("'", "''")}'";
    final content = '$safeSheet!$colsRange,$safeSheet!$rowsRange';
    if (namePattern.hasMatch(xml)) {
      return xml.replaceFirstMapped(namePattern, (match) {
        final openEnd = match.group(0)!.indexOf('>');
        final open = match.group(0)!.substring(0, openEnd + 1);
        return '$open${_xmlEscape(content)}</definedName>';
      });
    }
    final close = '</definedNames>';
    final tag =
        '<definedName name="_xlnm.Print_Titles" localSheetId="$localSheetId">${_xmlEscape(content)}</definedName>';
    if (xml.contains(close)) return xml.replaceFirst(close, '$tag$close');
    return xml.replaceFirst(
        '</workbook>', '<definedNames>$tag</definedNames></workbook>');
  }

  static int _columnNumber(String letters) {
    var value = 0;
    for (final code in letters.codeUnits) {
      value = value * 26 + code - 64;
    }
    return value;
  }

  static String _columnName(int number) {
    var value = number;
    final output = StringBuffer();
    while (value > 0) {
      final remainder = (value - 1) % 26;
      output.writeCharCode(65 + remainder);
      value = (value - 1) ~/ 26;
    }
    return output.toString().split('').reversed.join();
  }
}

// Print Merge Studio: Excel / CSV data import-export and design files.

import 'dart:convert';
import 'dart:typed_data';

import 'package:excel_community/excel_community.dart' as xls;

import '../services/xlsx_sanitizer.dart';
import 'pm_models.dart';

class PmTable {
  PmTable(this.headers, this.rows);
  final List<String> headers;
  final List<Map<String, String>> rows;
}

class PmIo {
  PmIo._();

  static String _cellText(xls.Data? cell) {
    final v = cell?.value;
    if (v == null) return '';
    String dmy(int d, int m, int y) => '${d.toString().padLeft(2, '0')}/${m.toString().padLeft(2, '0')}/$y';
    if (v is xls.DateCellValue) return dmy(v.day, v.month, v.year);
    if (v is xls.DateTimeCellValue) return dmy(v.day, v.month, v.year);
    if (v is xls.IntCellValue) return '${v.value}';
    if (v is xls.DoubleCellValue) {
      final d = v.value;
      return d == d.roundToDouble() ? '${d.toInt()}' : '$d';
    }
    return v.toString().trim();
  }

  /// Turns a grid (first non-empty row = headers) into a table. Empty rows are
  /// skipped and duplicate / blank header names are made unique.
  static PmTable fromGrid(List<List<String>> grid) {
    final nonEmpty = grid.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
    if (nonEmpty.isEmpty) throw const FormatException('ફાઇલમાં કોઈ માહિતી નથી.');
    final rawHeaders = nonEmpty.first;
    var width = rawHeaders.length;
    while (width > 0 && rawHeaders[width - 1].trim().isEmpty) {
      width--;
    }
    if (width == 0) throw const FormatException('પહેલી લીટીમાં કૉલમનાં નામ હોવાં જોઈએ.');
    final headers = <String>[];
    final seen = <String, int>{};
    for (var i = 0; i < width; i++) {
      var h = rawHeaders[i].trim().replaceAll(RegExp(r'\s+'), ' ');
      if (h.isEmpty) h = 'Column_${i + 1}';
      final n = (seen[h] ?? 0) + 1;
      seen[h] = n;
      headers.add(n == 1 ? h : '${h}_$n');
    }
    final rows = <Map<String, String>>[];
    for (final r in nonEmpty.skip(1)) {
      rows.add(<String, String>{
        for (var i = 0; i < headers.length; i++) headers[i]: i < r.length ? r[i].trim() : '',
      });
    }
    return PmTable(headers, rows);
  }

  /// Reads .xlsx, .csv, .tsv or .txt.
  static PmTable parseFile(Uint8List bytes, String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.xls')) {
      throw const FormatException('જૂની .xls ફાઇલ ચાલતી નથી. Excel માં "Save As → .xlsx" કરીને ફરી upload કરો.');
    }
    if (lower.endsWith('.xlsx') || (bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B)) {
      final x = xls.Excel.decodeBytes(bytes);
      xls.Sheet? best;
      var bestCells = -1;
      for (final s in x.tables.values) {
        final cells = s.rows.fold<int>(0, (n, r) => n + r.where((c) => _cellText(c).isNotEmpty).length);
        if (cells > bestCells) {
          best = s;
          bestCells = cells;
        }
      }
      if (best == null || bestCells <= 0) throw const FormatException('Excel ફાઇલમાં કોઈ માહિતી નથી.');
      return fromGrid(<List<String>>[for (final r in best.rows) r.map(_cellText).toList()]);
    }
    return parseDelimited(utf8.decode(bytes, allowMalformed: true));
  }

  /// CSV / TSV / semicolon text, with quoted fields ("a, b" and "" escapes).
  static PmTable parseDelimited(String text) {
    var t = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (t.startsWith('﻿')) t = t.substring(1);
    final firstLine = t.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    String sep = ',';
    var best = 0;
    for (final c in const <String>['\t', ',', ';']) {
      final n = c.allMatches(firstLine).length;
      if (n > best) {
        best = n;
        sep = c;
      }
    }
    final grid = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < t.length; i++) {
      final ch = t[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < t.length && t[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == '"' && cell.isEmpty) {
        inQuotes = true;
      } else if (ch == sep) {
        row.add(cell.toString());
        cell.clear();
      } else if (ch == '\n') {
        row.add(cell.toString());
        cell.clear();
        grid.add(row);
        row = <String>[];
      } else {
        cell.write(ch);
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString());
      grid.add(row);
    }
    return fromGrid(grid);
  }

  /// The data (or an empty template with only headers) as an .xlsx file.
  static Uint8List toExcel(List<String> headers, List<Map<String, String>> rows) {
    final x = xls.Excel.createExcel();
    final defaultName = x.getDefaultSheet() ?? 'Sheet1';
    x.rename(defaultName, 'Data');
    final sheet = x['Data'];
    sheet.appendRow(<xls.CellValue?>[for (final h in headers) xls.TextCellValue(h)]);
    for (final r in rows) {
      sheet.appendRow(<xls.CellValue?>[for (final h in headers) xls.TextCellValue(r[h] ?? '')]);
    }
    final bytes = x.encode();
    if (bytes == null || bytes.isEmpty) throw StateError('Excel ફાઇલ બની શકી નથી.');
    return XlsxSanitizer.clean(Uint8List.fromList(bytes));
  }

  // ---------------------------------------------------------------------------
  // Design file (.json): pages, objects and embedded images
  // ---------------------------------------------------------------------------

  static Uint8List designToJson(List<PmPage> pages, Map<String, Uint8List> images) {
    final used = <String>{};
    for (final p in pages) {
      if (p.bgImageId.isNotEmpty) used.add(p.bgImageId);
      for (final o in p.objects) {
        if (o.imageId.isNotEmpty) used.add(o.imageId);
        if (o.clipImageId.isNotEmpty) used.add(o.clipImageId);
      }
    }
    return Uint8List.fromList(utf8.encode(jsonEncode(<String, dynamic>{
      'app': 'psm-print-merge',
      'version': 1,
      'pages': pages.map((p) => p.toJson()).toList(),
      'images': <String, String>{
        for (final id in used)
          if (images[id] != null) id: base64Encode(images[id]!),
      },
    })));
  }

  static (List<PmPage>, Map<String, Uint8List>) designFromJson(Uint8List bytes) {
    final j = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    if (j is! Map || j['pages'] is! List) throw const FormatException('આ ડિઝાઇન ફાઇલ નથી.');
    final pages = <PmPage>[
      for (final p in j['pages'] as List)
        if (p is Map) PmPage.fromJson(Map<String, dynamic>.from(p)),
    ].take(PmA4.maxPages).toList();
    if (pages.isEmpty) throw const FormatException('ડિઝાઇન ફાઇલમાં કોઈ પાનું નથી.');
    final images = <String, Uint8List>{};
    final raw = j['images'];
    if (raw is Map) {
      raw.forEach((k, v) {
        try {
          images['$k'] = base64Decode('$v');
        } catch (_) {}
      });
    }
    return (pages, images);
  }
}

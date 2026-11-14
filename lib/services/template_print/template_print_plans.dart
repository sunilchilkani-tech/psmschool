import 'dart:math' as math;
import 'dart:typed_data';

import 'print_page.dart';
import 'xlsx_model.dart';

/// Builds the printed pages for the Hajari Patrak and Result templates.
/// The rules are the same ones the old Cloud Run converter used, so the
/// browser print looks like the PDF teachers already know.
class TemplatePrintPlans {
  TemplatePrintPlans._();

  // ------------------------------------------------------------- helpers
  static String canonicalSchoolType(String value) {
    final v = value.trim().toLowerCase();
    if (const ['mixed', 'coed', 'co-ed', 'both', 'મિશ્ર'].any(v.contains)) return 'coed';
    if (v.contains('boy') || v.contains('kumar') || v.contains('કુમાર')) return 'boys';
    if (v.contains('girl') || v.contains('kanya') || v.contains('કન્યા')) return 'girls';
    return 'coed';
  }

  static List<int> _visibleCols(XSheet s, int from, int to) =>
      [for (var c = from; c <= to; c++) if (!s.hiddenCols.contains(c)) c];

  static List<int> _visibleRows(XSheet s, int from, int to) =>
      [for (var r = from; r <= to; r++) if (!s.hiddenRows.contains(r)) r];

  /// Picture size that fits inside [maxW] x [maxH] keeping its shape.
  static (double, double) _fit(Uint8List bytes, double maxW, double maxH) {
    final (w, h) = imageSize(bytes) ?? (maxW, maxH);
    final k = math.min(1.0, math.min(maxW / w, maxH / h));
    return (w * k, h * k);
  }

  /// Width and height of a PNG / JPEG / GIF / WebP picture.
  static (double, double)? imageSize(Uint8List b) {
    try {
      if (b.length > 24 && b[0] == 0x89 && b[1] == 0x50) {
        final d = ByteData.sublistView(b);
        return (d.getUint32(16).toDouble(), d.getUint32(20).toDouble());
      }
      if (b.length > 10 && b[0] == 0x47 && b[1] == 0x49) {
        return ((b[6] | b[7] << 8).toDouble(), (b[8] | b[9] << 8).toDouble());
      }
      if (b.length > 30 && b[0] == 0x52 && b[8] == 0x57) {
        // WebP: VP8X / VP8 / VP8L
        final chunk = String.fromCharCodes(b.sublist(12, 16));
        if (chunk == 'VP8X') return ((1 + (b[24] | b[25] << 8 | b[26] << 16)).toDouble(), (1 + (b[27] | b[28] << 8 | b[29] << 16)).toDouble());
        if (chunk == 'VP8 ') return ((b[26] | b[27] << 8) & 0x3fff).toDouble() > 0 ? (((b[26] | b[27] << 8) & 0x3fff).toDouble(), ((b[28] | b[29] << 8) & 0x3fff).toDouble()) : null;
        if (chunk == 'VP8L') {
          final bits = b[21] | b[22] << 8 | b[23] << 16 | b[24] << 24;
          return ((1 + (bits & 0x3fff)).toDouble(), (1 + ((bits >> 14) & 0x3fff)).toDouble());
        }
      }
      if (b.length > 4 && b[0] == 0xFF && b[1] == 0xD8) {
        var i = 2;
        while (i + 9 < b.length) {
          if (b[i] != 0xFF) {
            i++;
            continue;
          }
          final marker = b[i + 1];
          final len = b[i + 2] << 8 | b[i + 3];
          if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
            return ((b[i + 7] << 8 | b[i + 8]).toDouble(), (b[i + 5] << 8 | b[i + 6]).toDouble());
          }
          i += 2 + len;
        }
      }
    } catch (_) {}
    return null;
  }

  static Uint8List? _logo(XWorkbook wb, Uint8List? given) {
    if (given != null && given.length > 300) return given;
    final media = wb.mediaImages;
    return media.isEmpty ? null : media.first;
  }

  static String _mime(Uint8List b) {
    if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
    if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49) return 'image/gif';
    if (b.length > 12 && b[0] == 0x52 && b[8] == 0x57) return 'image/webp';
    return 'image/png';
  }

  /// Groups rows that belong to one vertical merge so they stay on one page.
  static List<List<int>> _rowUnits(XSheet s, List<int> rows) {
    final end = <int, int>{};
    for (final m in s.merges) {
      if (m.r2 > m.r1) end[m.r1] = math.max(end[m.r1] ?? m.r1, m.r2);
    }
    final units = <List<int>>[];
    var i = 0;
    while (i < rows.length) {
      var last = end[rows[i]] ?? rows[i];
      final unit = <int>[];
      while (i < rows.length && rows[i] <= last) {
        unit.add(rows[i]);
        last = math.max(last, end[rows[i]] ?? rows[i]);
        i++;
      }
      units.add(unit);
    }
    return units;
  }

  // -------------------------------------------------------------- Hajari
  static PrintJob hajari({
    required Uint8List workbookBytes,
    required String schoolType,
    required int year,
    required int month,
    int rowHeightPx = 22,
    int fontPt = 7,
    Uint8List? logoBytes,
    String title = 'Hajari Patrak',
  }) {
    final wb = XWorkbook.parse(workbookBytes);
    final kind = canonicalSchoolType(schoolType);
    final coed = kind == 'coed';
    final coverName = const {'boys': 'FRONT PAGE only boys', 'girls': 'FRONT PAGE only girls', 'coed': 'FRONT PAGE both'}[kind]!;
    final registerName = coed ? 'HAJARI PATRAK for  BOTH GENDER' : 'HAJARI PATRAK for sungle gender';
    final cover = wb.sheet(coverName);
    final reg = wb.sheet(registerName);
    if (cover == null || reg == null) {
      throw StateError('Hajari Patrak workbook does not contain the $coverName / $registerName sheets.');
    }
    final edits = SheetEdits();
    final pages = <PrintPage>[];

    // Cover page.
    final cr2 = cover.areaR2 ?? (coed ? 27 : 26), cc2 = cover.areaC2 ?? (coed ? 16 : 10);
    final coverPage = PrintPage(
      sheet: cover,
      cols: _visibleCols(cover, 1, cc2),
      rows: _visibleRows(cover, 1, cr2),
      paper: cover.paper,
      // The template's zero top/bottom margins cut the frame off on most
      // printers: keep a safe margin and centre the page.
      marginLeftIn: math.max(cover.marginLeft, 0.3),
      marginRightIn: math.max(cover.marginRight, 0.3),
      marginTopIn: math.max(cover.marginTop, 0.35),
      marginBottomIn: math.max(cover.marginBottom, 0.35),
      hCenter: true,
    )..vCenter = true;
    final logo = _logo(wb, logoBytes);
    if (logo != null && cover.images.isEmpty) {
      final (w, h) = _fit(logo, 320, 195);
      final (m1, m2) = coed ? (5, 11) : (4, 7);
      var x0 = 0.0, mw = 0.0;
      for (var c = 1; c < m1; c++) {
        if (!cover.hiddenCols.contains(c)) x0 += cover.colPx(c);
      }
      for (var c = m1; c <= m2; c++) {
        mw += cover.colPx(c);
      }
      var y0 = 0.0;
      for (var r = 1; r < 7; r++) {
        if (!cover.hiddenRows.contains(r)) y0 += cover.rowPt(r) * 4 / 3;
      }
      final rh = cover.rowPt(7) * 4 / 3;
      coverPage.images.add(PlacedImage(logo, _mime(logo), x0 + (mw - w) / 2, y0 + math.max(0, (rh - h) / 2), w, h));
    }
    coverPage.scale = coverPage.fitScale();
    pages.add(coverPage);

    // Register total (sum of category totals).
    final src = coed ? 9 : 8;
    var total = 0;
    var any = false;
    for (var r = 2001; r <= 2004; r++) {
      final cell = reg.cell(r, src);
      final n = cell?.number ?? int.tryParse(cell?.text.trim() ?? '');
      if (n != null) {
        total += n.toInt();
        any = true;
      }
    }
    if (any) edits.setValue(reg, 2005, src, '$total', number: total);

    // Dates that do not exist this month, weekday names, Sunday shading.
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstCol = coed ? 12 : 11;
    final firstCount = coed ? 7 : 8;
    final dayCol = <int, int>{};
    for (var i = 0; i < firstCount; i++) {
      dayCol[i + 1] = firstCol + i;
    }
    for (var i = 0; i < 31 - firstCount; i++) {
      dayCol[firstCount + 1 + i] = 22 + i;
    }
    const weekdays = ['સોમવાર', 'મંગળવાર', 'બુધવાર', 'ગુરુવાર', 'શુક્રવાર', 'શનિવાર', 'રવિવાર'];
    final hiddenDayCols = <int>[];
    dayCol.forEach((day, col) {
      if (day > daysInMonth) {
        reg.hiddenCols.add(col);
        hiddenDayCols.add(col);
        edits.setValue(reg, 2, col, '');
        edits.setValue(reg, 3, col, '');
        return;
      }
      reg.hiddenCols.remove(col);
      final d = DateTime(year, month, day);
      edits.setValue(reg, 2, col, weekdays[d.weekday - 1]);
      // Sunday / holiday shading comes from the exported workbook.
    });
    edits.hiddenCols[reg.name] = hiddenDayCols;

    // Row height / font slider for the student area.
    final rowScale = rowHeightPx / 22.0;
    final minForFont = fontPt * 1.65;
    for (var r = 4; r <= 2000; r++) {
      if (reg.hiddenRows.contains(r)) continue;
      final base = reg.rowHeights[r] ?? 15.0;
      reg.rowHeights[r] = math.max(6.0, math.min(45.0, math.max(base * rowScale, minForFont)));
    }

    final maxTableCol = coed ? 49 : 48;
    final lastRow = reg.areaR2 ?? 2008;
    final leftCols = _visibleCols(reg, 1, 19);
    final rightCols = _visibleCols(reg, 20, maxTableCol);
    final headerRows = _visibleRows(reg, 1, 3);
    final bodyRows = _visibleRows(reg, 4, lastRow);

    PrintPage mk(List<int> cols, List<int> rows) {
      final p = PrintPage(
        sheet: reg,
        cols: cols,
        rows: rows,
        paper: reg.paper,
        marginLeftIn: reg.marginLeft,
        marginRightIn: reg.marginRight,
        marginTopIn: reg.marginTop,
        marginBottomIn: reg.marginBottom,
        hCenter: true,
      )
        ..blankCols.addAll(const [19, 20])
        ..fontFromRow = 4
        ..fontToRow = 2000
        ..fontPt = fontPt.toDouble()
        ..compensateFont = false;
      return p;
    }

    final probeL = mk(leftCols, headerRows), probeR = mk(rightCols, headerRows);
    final scale = math.min(1.0, math.min(probeL.availWidthPx / probeL.contentWidthPx, probeR.availWidthPx / probeR.contentWidthPx));
    final headerPx = probeL.contentHeightPx;
    final capacity = probeL.availHeightPx / scale - headerPx;
    final units = _rowUnits(reg, bodyRows);
    final batches = <List<int>>[];
    var cur = <int>[];
    var used = 0.0;
    for (final u in units) {
      final h = u.fold<double>(0, (s, r) => s + reg.rowPt(r) * 4 / 3);
      if (cur.isNotEmpty && used + h > capacity + 0.5) {
        batches.add(cur);
        cur = <int>[];
        used = 0;
      }
      cur.addAll(u);
      used += h;
    }
    if (cur.isNotEmpty) batches.add(cur);
    for (final batch in batches) {
      for (final cols in [leftCols, rightCols]) {
        pages.add(mk(cols, [...headerRows, ...batch])..scale = scale);
      }
    }
    return PrintJob(title: title, pages: pages, edits: edits, workbookBytes: workbookBytes);
  }

  // -------------------------------------------------------------- Result
  static XSheet _pick(XWorkbook wb, bool Function(String upper) test) {
    for (final n in wb.sheetNames) {
      if (wb.isVisible(n) && test(n.toUpperCase())) return wb.sheet(n)!;
    }
    for (final n in wb.sheetNames) {
      if (test(n.toUpperCase())) return wb.sheet(n)!;
    }
    throw StateError('Result workbook does not contain the requested sheet.');
  }

  static int _lastStudentRow(XSheet s, int first) {
    var last = first - 1;
    for (var r = first; r <= s.maxRow; r++) {
      if (s.text(r, 1).trim().isNotEmpty || s.text(r, 2).trim().isNotEmpty) last = r;
    }
    return last;
  }

  /// [view] is 'front', 'result' or 'vv'.
  static PrintJob result({
    required Uint8List workbookBytes,
    required String view,
    int rowHeightPx = 22,
    int fontPt = 7,
    Uint8List? logoBytes,
    String title = 'Result',
  }) {
    final wb = XWorkbook.parse(workbookBytes);
    final edits = SheetEdits();
    final pages = <PrintPage>[];
    if (view == 'front') {
      final s = _pick(wb, (u) => u.contains('FRONT PAGE'));
      final firstSem = s.name.toUpperCase().contains('FIRST SEM');
      s.colWidths[1] = 1.14;
      s.colWidths[2] = 12.0;
      for (var c = 3; c <= 5; c++) {
        s.colWidths[c] = 3.71;
      }
      for (var c = 6; c <= 21; c++) {
        s.colWidths[c] = 4.0;
      }
      s.colWidths[22] = 1.14;
      s.colWidths[23] = 2.5;
      s.rowHeights[4] = 200;
      final p = PrintPage(
        sheet: s,
        cols: _visibleCols(s, 1, firstSem ? 22 : 23),
        rows: _visibleRows(s, 1, 24),
        paper: firstSem ? '9' : '5',
        marginLeftIn: math.max(0.3, math.min(s.marginLeft, 0.5)),
        marginRightIn: math.max(0.3, math.min(s.marginRight, 0.5)),
        marginTopIn: 0.3,
        marginBottomIn: 0.3,
        hCenter: true,
      )
        ..drawSheetImages = false
        ..vCenter = true;
      final logo = _logo(wb, logoBytes);
      if (logo != null) {
        final (w, h) = _fit(logo, 250, 185);
        var x0 = 0.0, span = 0.0;
        if (!s.hiddenCols.contains(1)) x0 = s.colPx(1);
        for (var c = 2; c <= 21; c++) {
          span += s.colPx(c);
        }
        var y0 = 0.0;
        for (var r = 1; r < 4; r++) {
          if (!s.hiddenRows.contains(r)) y0 += s.rowPt(r) * 4 / 3;
        }
        p.images.add(PlacedImage(logo, _mime(logo), x0 + (span - w) / 2, y0 + (200 * 4 / 3 - h) / 2, w, h));
      }
      p.scale = p.fitScale();
      pages.add(p);
    } else if (view == 'result') {
      pages.addAll(_resultPages(_pick(wb, (u) => u.contains('RESULT FOR')), rowHeightPx, fontPt));
    } else {
      pages.addAll(_vvPages(_pick(wb, (u) => u.contains('VYAKTITV VIKAS')), rowHeightPx, fontPt));
    }
    return PrintJob(title: title, pages: pages, edits: edits, workbookBytes: workbookBytes);
  }

  static List<PrintPage> _resultPages(XSheet s, int rowHeightPx, int fontPt) {
    final lastRow = _lastStudentRow(s, 7);
    if (lastRow < 7) throw StateError('The Result sheet contains no student rows.');
    for (var r = 1; r <= 6; r++) {
      s.hiddenRows.remove(r);
    }
    final upper = s.name.toUpperCase();
    final coed = upper.contains('BOTH');
    final firstSem = upper.contains('FIRST SEM');
    final baseCols = coed ? 9 : 8;
    final groupW = firstSem ? 5 : 8;
    final firstSub = baseCols + 1;
    var groups = 7;
    for (var g = 7; g < 30; g++) {
      final col = firstSub + g * groupW;
      final h1 = s.text(1, col).trim();
      if (h1.contains('પત્રક-B') || h1.contains('વ્યક્તિત્વ')) {
        groups = g;
        break;
      }
      if (h1.isEmpty && col > s.maxCol) {
        groups = g;
        break;
      }
    }
    final tailStart = baseCols + groups * groupW + 1;
    final hasEighth = s.text(1, tailStart + 7).trim().isNotEmpty;
    final tailW = (!firstSem || hasEighth) ? 8 : 7;
    final totalCols = baseCols + groups * groupW + tailW;
    final hiddenTail = {for (var c = tailStart; c <= totalCols; c++) if (s.hiddenCols.contains(c)) c};
    final active = <(int, int)>[];
    for (var g = 0; g < groups; g++) {
      final start = firstSub + g * groupW;
      if (s.text(2, start).trim().isNotEmpty) active.add((start, start + groupW - 1));
    }
    final hasTail = s.text(1, tailStart).trim().isNotEmpty && !s.hiddenCols.contains(tailStart);
    final summary = (tailStart, totalCols - 2);
    final uidPen = (totalCols - 1, totalCols);
    final specs = <(String, List<(int, int)>)>[];
    if (active.isNotEmpty) {
      specs.add(('first', [active.first]));
      final rest = active.sublist(1);
      final chunks = [for (var i = 0; i < rest.length; i += 2) rest.sublist(i, math.min(i + 2, rest.length))];
      if (hasTail) {
        if (active.length.isEven && chunks.isNotEmpty) {
          for (final ch in chunks.sublist(0, chunks.length - 1)) {
            specs.add(('subjects', ch));
          }
          specs.add(('last', [...chunks.last, summary]));
        } else {
          for (final ch in chunks) {
            specs.add(('subjects', ch));
          }
          specs.add(('summary', [summary]));
        }
        specs.add(('uid', [uidPen]));
      } else {
        for (final ch in chunks) {
          specs.add(('subjects', ch));
        }
      }
    } else {
      specs.add(hasTail ? ('first', [summary]) : ('first', <(int, int)>[]));
      if (hasTail) specs.add(('uid', [uidPen]));
    }

    final baseWidths = {for (var c = 1; c <= totalCols; c++) c: s.colWidthChars(c)};
    final targetWidth = firstSem ? 96.0 : 99.0;
    final paper = firstSem ? '9' : '5';
    final headerRows = [for (var r = 1; r <= 6; r++) r];
    final rowScale = rowHeightPx / 22.0;
    final minForFont = fontPt * 1.70;
    final minRowPt = math.max(14.0, math.min(46.0, math.max(20.0 * rowScale, minForFont)));

    // Column layout of each horizontal page.
    final layouts = <(List<int>, Map<int, double>)>[];
    for (final (kind, ranges) in specs) {
      final keep = <int>{...(kind == 'first' ? [for (var c = 1; c <= baseCols; c++) c] : [1, 2])};
      for (final (a, b) in ranges) {
        for (var c = a; c <= b; c++) {
          if (!hiddenTail.contains(c)) keep.add(c);
        }
      }
      final sorted = keep.toList()..sort();
      final flex = sorted.where((c) => c != 1 && c != 2).toList();
      const c1 = 4.0;
      final c2 = kind == 'first' ? 22.0 : 25.5;
      final rem = math.max(30.0, targetWidth - c1 - c2);
      final flexSum = flex.fold<double>(0, (t, c) => t + baseWidths[c]!);
      final k = rem / (flexSum == 0 ? 1 : flexSum);
      final widths = <int, double>{
        for (final c in sorted) c: c == 1 ? c1 : (c == 2 ? c2 : double.parse(math.max(3.4, baseWidths[c]! * k).toStringAsFixed(2))),
      };
      layouts.add((sorted, widths));
    }

    PrintPage mk(List<int> cols, Map<int, double> widths, List<int> rows) {
      final p = PrintPage(sheet: s, cols: cols, rows: rows, paper: paper)
        ..fontFromRow = 7
        ..fontToRow = lastRow
        ..fontPt = fontPt.toDouble()
        ..compensateFont = false;
      widths.forEach((c, w) => p.colPxOverride[c] = colWidthCharsToPx(w));
      return p;
    }

    final students = [for (var r = 7; r <= lastRow; r++) r];
    final pages = <PrintPage>[];
    final probes = [for (final (cols, widths) in layouts) mk(cols, widths, headerRows)];
    final batches = _studentBatches(probes, students, rowHeightPx, fontPt);
    for (var b = 0; b < batches.length; b++) {
      final batch = batches[b];
      final full = b < batches.length - 1 || batches.length == 1 || batch.length >= batches.first.length * 0.65;
      for (var l = 0; l < layouts.length; l++) {
        final (cols, widths) = layouts[l];
        pages.add(_fillPage(mk(cols, widths, [...headerRows, ...batch]), batch, rowHeightPx, fontPt, full: full));
      }
    }
    return pages;
  }

  // ------------------------------------------------- shared row sizing
  /// Smallest printed row height for the teacher's row-height / font
  /// settings (the default 22 px gives 16 pt rows).
  static double _minPrintedRowPt(int rowHeightPx, int fontPt) =>
      math.max(11.0, math.max(16.0 * rowHeightPx / 22.0, fontPt * 1.6));

  /// Scale that makes the page's columns fill the paper width.
  static double _widthScale(PrintPage p) => math.min(1.15, p.availWidthPx / p.contentWidthPx);

  /// Splits the students over pages: bigger rows → more pages. Every page
  /// repeats the header rows.
  static List<List<int>> _studentBatches(List<PrintPage> headerProbes, List<int> students, int rowHeightPx, int fontPt) {
    final minPt = _minPrintedRowPt(rowHeightPx, fontPt);
    var perPage = 1 << 30;
    var availPt = double.infinity;
    for (final probe in headerProbes) {
      final sc = _widthScale(probe);
      final a = probe.availHeightPx * 0.75 - probe.contentHeightPx * 0.75 * sc;
      availPt = math.min(availPt, a);
      perPage = math.min(perPage, math.max(3, (a / minPt).floor()));
    }
    // Avoid a page with only 1–3 students when rows may shrink a little.
    if (students.length > perPage && students.length - perPage <= 3 && availPt / students.length >= minPt * 0.85) {
      perPage = students.length;
    }
    return [for (var i = 0; i < students.length; i += perPage) students.sublist(i, math.min(i + perPage, students.length))];
  }

  /// Sizes the student rows of [p] so the table fills the page height
  /// (rows never smaller than the teacher's setting, never above 42 pt).
  static PrintPage _fillPage(PrintPage p, List<int> batch, int rowHeightPx, int fontPt, {bool full = true}) {
    final sc = _widthScale(p);
    final minPt = _minPrintedRowPt(rowHeightPx, fontPt);
    final headerPx = p.rows.where((r) => !batch.contains(r)).fold<double>(0, (t, r) => t + p.rowH(r));
    final availPt = p.availHeightPx * 0.75 - headerPx * 0.75 * sc;
    final fillPt = availPt / math.max(1, batch.length);
    final rowPt = full ? math.min(fillPt, math.min(42.0, math.max(minPt, fillPt))) : math.min(fillPt, minPt * 1.15);
    for (final r in batch) {
      p.rowPxOverride[r] = rowPt / sc * 4 / 3;
    }
    p
      ..scale = sc
      ..compensateFont = true;
    return p;
  }

  static List<PrintPage> _vvPages(XSheet s, int rowHeightPx, int fontPt) {
    final lastRow = _lastStudentRow(s, 6);
    if (lastRow < 6) throw StateError('The Vyaktitva Vikas sheet contains no student rows.');
    final firstSem = s.name.toUpperCase().contains('FIRST SEM');
    final lastCol = firstSem ? 43 : 45;
    s.colWidths[43] = math.max(s.colWidths[43] ?? 0, 7.5);
    if (!firstSem) {
      s.colWidths[44] = math.max(s.colWidths[44] ?? 0, 7.5);
      s.colWidths[45] = math.max(s.colWidths[45] ?? 0, 7.5);
    }
    // Statement headings are printed vertically.
    final rotated = <int, int>{};
    for (var c = 3; c <= 42; c++) {
      final cell = s.cell(5, c);
      if (cell == null) continue;
      final st = s.styles(cell.style);
      if (st.rotation == 90) continue;
      cell.style = rotated.putIfAbsent(cell.style, () {
        final copy = XStyle()
          ..font = st.font
          ..fill = st.fill
          ..left = st.left
          ..right = st.right
          ..top = st.top
          ..bottom = st.bottom
          ..horizontal = st.horizontal
          ..vertical = st.vertical
          ..wrap = st.wrap
          ..rotation = 90
          ..numFmt = st.numFmt;
        s.styleTable.add(copy);
        return s.styleTable.length - 1;
      });
    }
    for (var r = 1; r <= 5; r++) {
      s.hiddenRows.remove(r);
    }
    final cols = _visibleCols(s, 1, lastCol);
    final headerRows = [for (var r = 1; r <= 5; r++) r];
    // Both semesters: Legal paper, landscape.
    PrintPage mk(List<int> rows) => PrintPage(
          sheet: s,
          cols: cols,
          rows: rows,
          paper: '5',
          landscape: true,
          marginLeftIn: 0.25,
          marginRightIn: 0.25,
          marginTopIn: 0.25,
          marginBottomIn: 0.25,
        )
          ..fontFromRow = 6
          ..fontToRow = lastRow
          ..fontPt = fontPt.toDouble();
    final students = [for (var r = 6; r <= lastRow; r++) r];
    final batches = _studentBatches([mk(headerRows)], students, rowHeightPx, fontPt);
    final pages = <PrintPage>[];
    for (var b = 0; b < batches.length; b++) {
      final batch = batches[b];
      final full = b < batches.length - 1 || batches.length == 1 || batch.length >= batches.first.length * 0.65;
      pages.add(_fillPage(mk([...headerRows, ...batch]), batch, rowHeightPx, fontPt, full: full));
    }
    return pages;
  }
}

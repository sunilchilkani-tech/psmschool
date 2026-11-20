import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:universal_html/html.dart' as uhtml;

import 'google_sheets_pdf_service.dart';
import 'psm_file_export_helper.dart';
import 'rojmel_html_printer.dart';
import 'school_type.dart';

class _XlsxFontStyle {
  const _XlsxFontStyle({
    this.bold = false,
    this.italic = false,
    this.sizePt = 10.0,
    this.colorHex,
    this.name = 'Noto Sans Gujarati',
  });

  final bool bold;
  final bool italic;
  final double sizePt;
  final String? colorHex;
  final String name;
}

class _XlsxBorderSide {
  const _XlsxBorderSide({
    this.style = 'none',
    this.colorHex = '#000000',
  });

  final String style;
  final String colorHex;

  bool get isNone => style.isEmpty || style == 'none';
}

class _XlsxBorderStyle {
  const _XlsxBorderStyle({
    this.left = const _XlsxBorderSide(),
    this.right = const _XlsxBorderSide(),
    this.top = const _XlsxBorderSide(),
    this.bottom = const _XlsxBorderSide(),
  });

  final _XlsxBorderSide left;
  final _XlsxBorderSide right;
  final _XlsxBorderSide top;
  final _XlsxBorderSide bottom;
}

class _XlsxCellXf {
  const _XlsxCellXf({
    this.fontId = 0,
    this.fillId = 0,
    this.borderId = 0,
    this.numFmtId = 0,
    this.horizontal = '',
    this.vertical = 'center',
    this.textRotation = 0,
    this.wrapText = false,
  });

  final int fontId;
  final int fillId;
  final int borderId;
  final int numFmtId;
  final String horizontal;
  final String vertical;
  final int textRotation;
  final bool wrapText;
}

class _XlsxCellData {
  _XlsxCellData({
    required this.row,
    required this.col,
    required this.styleIndex,
    required this.text,
    this.isNumeric = false,
  });

  final int row;
  final int col;
  int styleIndex;
  String text;
  bool isNumeric;
  bool forceGreyBackground = false;
  bool forceDoubleBottom = false;
}

class _XlsxMergeRange {
  const _XlsxMergeRange({
    required this.r1,
    required this.c1,
    required this.r2,
    required this.c2,
  });

  final int r1;
  final int c1;
  final int r2;
  final int c2;
}

class _XlsxSheetData {
  _XlsxSheetData({
    required this.name,
    required this.path,
    required this.hidden,
    required this.colWidths,
    required this.hiddenCols,
    required this.rowHeightsPt,
    required this.hiddenRows,
    required this.cells,
    required this.merges,
  });

  final String name;
  final String path;
  final bool hidden;
  final Map<int, double> colWidths;
  final Set<int> hiddenCols;
  final Map<int, double> rowHeightsPt;
  final Set<int> hiddenRows;
  final Map<int, Map<int, _XlsxCellData>> cells;
  final List<_XlsxMergeRange> merges;

  _XlsxCellData? cellAt(int r, int c) => cells[r]?[c];

  void setCellText(int r, int c, String value, {bool isNumeric = false}) {
    final rowMap = cells.putIfAbsent(r, () => <int, _XlsxCellData>{});
    final existing = rowMap[c];
    if (existing != null) {
      existing.text = value;
      existing.isNumeric = isNumeric;
    } else {
      rowMap[c] = _XlsxCellData(
        row: r,
        col: c,
        styleIndex: 0,
        text: value,
        isNumeric: isNumeric,
      );
    }
  }
}

class _XlsxWorkbookModel {
  _XlsxWorkbookModel({
    required this.fonts,
    required this.fills,
    required this.borders,
    required this.xfs,
    required this.sheetsByPath,
  });

  final List<_XlsxFontStyle> fonts;
  final List<String?> fills;
  final List<_XlsxBorderStyle> borders;
  final List<_XlsxCellXf> xfs;
  final Map<String, _XlsxSheetData> sheetsByPath;
}

class _ResultPageSpec {
  const _ResultPageSpec({
    required this.kind,
    required this.cols,
  });

  final String kind;
  final List<int> cols;
}

class _XlsxTabSliceSpec {
  const _XlsxTabSliceSpec({
    required this.title,
    required this.sheet,
    required this.rows,
    required this.cols,
    this.rowHeightOverridesPt = const <int, double>{},
    this.blankPadRowsCount = 0,
    this.blankPadRowHeightPt = 16.0,
    this.isResultSheetSlice = false,
  });

  final String title;
  final _XlsxSheetData sheet;
  final List<int> rows;
  final List<int> cols;
  final Map<int, double> rowHeightOverridesPt;
  final int blankPadRowsCount;
  final double blankPadRowHeightPt;
  final bool isResultSheetSlice;
}

/// Pure-Dart Excel (.xlsx) Template -> PDF / Browser Print Engine.
///
/// - If the Developer has configured a Google Sheets Web App URL in the
///   Developer Panel, converts the exact multi-tab `.xlsx` via Google Sheets.
/// - If no URL is configured yet (or if 50+ teachers print at the same time
///   and the Google Sheets endpoint is busy), automatically and silently
///   renders the exact template PDF output via the local Browser Print Engine
///   at ₹0 cost with unlimited concurrency.
class XlsxBrowserPrintService {
  const XlsxBrowserPrintService();

  Future<void> printHajariWorkbook({
    required Uint8List workbookBytes,
    required String schoolType,
    required int year,
    required int month,
    required Set<String> holidayIsoDates,
    required int rowHeightPx,
    required int fontSizePt,
    required bool colorMode,
    Uint8List? schoolLogoBytes,
    required String documentTitle,
    Object? preOpenedWindow,
    bool forceBrowserPrint = false,
  }) async {
    if (!forceBrowserPrint) {
      try {
        final urls =
            await const GoogleSheetsPdfService().getConfiguredScriptUrls();
        if (urls.isNotEmpty) {
          final preparedBytes = buildHajariGoogleSheetsWorkbook(
            workbookBytes: workbookBytes,
            schoolType: schoolType,
            year: year,
            month: month,
            holidayIsoDates: holidayIsoDates,
            rowHeightPx: rowHeightPx,
            fontSizePt: fontSizePt,
          );
          final isCoed = SchoolType.canonical(schoolType) == SchoolType.mixed;
          final pdfBytes =
              await const GoogleSheetsPdfService().convertWorkbookToPdf(
            preparedWorkbookBytes: preparedBytes,
            filename: documentTitle,
            paperSize: 'a4',
            portrait: false,
            schoolLogoBytes: schoolLogoBytes,
            logoRow: 7,
            logoCol: isCoed ? 5 : 4,
            logoWidthPx: 135,
            logoHeightPx: 125,
          );
          await PsmFileExportHelper.saveOrShare(
            bytes: pdfBytes,
            filename: documentTitle.endsWith('.pdf')
                ? documentTitle
                : '$documentTitle.pdf',
            title: 'Hajari Patrak / હાજરીપત્રક',
            mimeType: 'application/pdf',
          );
          return;
        }
      } catch (_) {
        // Automatic silent fallback to local Browser Print when 50+ teachers print simultaneously
      }
    }

    final htmlDoc = renderHajariWorkbookToHtml(
      workbookBytes: workbookBytes,
      schoolType: schoolType,
      year: year,
      month: month,
      holidayIsoDates: holidayIsoDates,
      rowHeightPx: rowHeightPx,
      fontSizePt: fontSizePt,
      colorMode: colorMode,
      schoolLogoBytes: schoolLogoBytes,
      documentTitle: documentTitle,
    );
    await _presentPrintHtml(
      htmlDocument: htmlDoc,
      documentTitle: documentTitle,
      pageFormat: PdfPageFormat.a4.landscape,
      preOpenedWindow: preOpenedWindow,
    );
  }

  Future<void> printResultWorkbook({
    required Uint8List workbookBytes,
    required String view,
    required int rowHeightPx,
    required int fontSizePt,
    Uint8List? schoolLogoBytes,
    Set<int> doubleBorderStudentIndices = const <int>{},
    required String documentTitle,
    Object? preOpenedWindow,
    bool forceBrowserPrint = false,
  }) async {
    final normalizedView = view.trim().toLowerCase();
    if (normalizedView == 'vv') {
      await printVyaktitvaVikasWorkbooks(
        workbookBytesList: <Uint8List>[workbookBytes],
        rowHeightPx: rowHeightPx,
        fontSizePt: fontSizePt,
        doubleBorderStudentIndices: doubleBorderStudentIndices,
        documentTitle: documentTitle,
        preOpenedWindow: preOpenedWindow,
        forceBrowserPrint: forceBrowserPrint,
      );
      return;
    }

    if (!forceBrowserPrint) {
      try {
        final urls =
            await const GoogleSheetsPdfService().getConfiguredScriptUrls();
        if (urls.isNotEmpty) {
          final (preparedBytes, isSem2) = buildResultGoogleSheetsWorkbook(
            workbookBytes: workbookBytes,
            view: normalizedView,
            rowHeightPx: rowHeightPx,
            fontSizePt: fontSizePt,
            doubleBorderStudentIndices: doubleBorderStudentIndices,
          );
          final pdfBytes =
              await const GoogleSheetsPdfService().convertWorkbookToPdf(
            preparedWorkbookBytes: preparedBytes,
            filename: documentTitle,
            paperSize: isSem2 ? 'legal' : 'a4',
            portrait: true,
            schoolLogoBytes: normalizedView == 'front' ? schoolLogoBytes : null,
            logoRow: 4,
            logoCol: 2,
            logoWidthPx: 115,
            logoHeightPx: 115,
          );
          await PsmFileExportHelper.saveOrShare(
            bytes: pdfBytes,
            filename: documentTitle.endsWith('.pdf')
                ? documentTitle
                : '$documentTitle.pdf',
            title: documentTitle,
            mimeType: 'application/pdf',
          );
          return;
        }
      } catch (_) {
        // Automatic silent fallback to local Browser Print when 50+ teachers print simultaneously
      }
    }

    final htmlDoc = renderResultWorkbookToHtml(
      workbookBytes: workbookBytes,
      view: normalizedView,
      rowHeightPx: rowHeightPx,
      fontSizePt: fontSizePt,
      schoolLogoBytes: schoolLogoBytes,
      doubleBorderStudentIndices: doubleBorderStudentIndices,
      documentTitle: documentTitle,
    );
    final pageFormat = normalizedView == 'vv'
        ? PdfPageFormat.legal.landscape
        : PdfPageFormat.a4;
    await _presentPrintHtml(
      htmlDocument: htmlDoc,
      documentTitle: documentTitle,
      pageFormat: pageFormat,
      preOpenedWindow: preOpenedWindow,
    );
  }

  Future<void> printVyaktitvaVikasWorkbooks({
    required List<Uint8List> workbookBytesList,
    required int rowHeightPx,
    required int fontSizePt,
    Set<int> doubleBorderStudentIndices = const <int>{},
    required String documentTitle,
    Object? preOpenedWindow,
    bool forceBrowserPrint = false,
  }) async {
    if (!forceBrowserPrint) {
      try {
        final urls =
            await const GoogleSheetsPdfService().getConfiguredScriptUrls();
        if (urls.isNotEmpty) {
          final preparedBytes = buildVyaktitvaVikasGoogleSheetsWorkbook(
            workbookBytesList: workbookBytesList,
            rowHeightPx: rowHeightPx,
            fontSizePt: fontSizePt,
            doubleBorderStudentIndices: doubleBorderStudentIndices,
          );
          final pdfBytes =
              await const GoogleSheetsPdfService().convertWorkbookToPdf(
            preparedWorkbookBytes: preparedBytes,
            filename: documentTitle,
            paperSize: 'legal',
            portrait: false,
          );
          await PsmFileExportHelper.saveOrShare(
            bytes: pdfBytes,
            filename: documentTitle.endsWith('.pdf')
                ? documentTitle
                : '$documentTitle.pdf',
            title: documentTitle,
            mimeType: 'application/pdf',
          );
          return;
        }
      } catch (_) {
        // Automatic silent fallback to local Browser Print when 50+ teachers print simultaneously
      }
    }

    final htmlDoc = renderVyaktitvaVikasWorkbooksToHtml(
      workbookBytesList: workbookBytesList,
      rowHeightPx: rowHeightPx,
      fontSizePt: fontSizePt,
      doubleBorderStudentIndices: doubleBorderStudentIndices,
      documentTitle: documentTitle,
    );
    await _presentPrintHtml(
      htmlDocument: htmlDoc,
      documentTitle: documentTitle,
      pageFormat: PdfPageFormat.legal.landscape,
      preOpenedWindow: preOpenedWindow,
    );
  }

  Future<void> _presentPrintHtml({
    required String htmlDocument,
    required String documentTitle,
    required PdfPageFormat pageFormat,
    Object? preOpenedWindow,
  }) async {
    if (kIsWeb) {
      final win = preOpenedWindow ?? openRojmelPrintWindow();
      if (win != null) {
        try {
          writeRojmelPrintDocument(win, htmlDocument);
          return;
        } catch (_) {
          closeRojmelPrintWindow(win);
        }
      }
      _printViaHiddenIframeWeb(htmlDocument);
      return;
    }
    await Printing.layoutPdf(
      name: documentTitle.endsWith('.pdf') ? documentTitle : '$documentTitle.pdf',
      format: pageFormat,
      onLayout: (format) async => Printing.convertHtml(
        format: format,
        html: htmlDocument,
      ),
    );
  }

  void _printViaHiddenIframeWeb(String htmlDocument) {
    final existing = uhtml.document.getElementById('psm-xlsx-print-iframe');
    existing?.remove();

    final blob = uhtml.Blob(<Object>[htmlDocument], 'text/html;charset=utf-8');
    final objectUrl = uhtml.Url.createObjectUrlFromBlob(blob);

    final iframe = uhtml.IFrameElement()
      ..id = 'psm-xlsx-print-iframe'
      ..style.position = 'fixed'
      ..style.right = '0'
      ..style.bottom = '0'
      ..style.width = '1px'
      ..style.height = '1px'
      ..style.border = '0'
      ..style.opacity = '0'
      ..src = objectUrl;

    uhtml.document.body?.append(iframe);

    Timer(const Duration(minutes: 3), () {
      uhtml.Url.revokeObjectUrl(objectUrl);
    });
  }

  // ===========================================================================
  // 1. HAJARI PATRAK HTML RENDERER (Matches cloud_run/hajari-pdf-converter/main.py)
  // ===========================================================================
  String renderHajariWorkbookToHtml({
    required Uint8List workbookBytes,
    required String schoolType,
    required int year,
    required int month,
    required Set<String> holidayIsoDates,
    required int rowHeightPx,
    required int fontSizePt,
    required bool colorMode,
    Uint8List? schoolLogoBytes,
    required String documentTitle,
  }) {
    final wb = _parseWorkbook(workbookBytes);
    final normalizedType = SchoolType.canonical(schoolType);
    final isCoed = normalizedType == SchoolType.mixed;

    final coverPath = normalizedType == SchoolType.boys
        ? 'xl/worksheets/sheet1.xml'
        : (normalizedType == SchoolType.girls
            ? 'xl/worksheets/sheet2.xml'
            : 'xl/worksheets/sheet3.xml');
    final registerPath =
        isCoed ? 'xl/worksheets/sheet5.xml' : 'xl/worksheets/sheet4.xml';

    final coverSheet = wb.sheetsByPath[coverPath] ?? wb.sheetsByPath.values.first;
    final registerSheet =
        wb.sheetsByPath[registerPath] ?? wb.sheetsByPath.values.last;

    _populateHajariRegisteredTotal(registerSheet, isCoed: isCoed);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    _prepareHajariDatesAndHolidays(
      registerSheet,
      year: year,
      month: month,
      daysInMonth: daysInMonth,
      holidayIsoDates: holidayIsoDates,
      isCoed: isCoed,
    );

    final pagesHtml = StringBuffer();

    final coverMaxCol = isCoed ? 16 : 10;
    final coverCols = <int>[for (var c = 1; c <= coverMaxCol; c++) c];
    final coverRows = <int>[
      for (var r = 1; r <= 27; r++)
        if (!coverSheet.hiddenRows.contains(r)) r,
    ];
    final logoDataUri = (schoolLogoBytes != null && schoolLogoBytes.isNotEmpty)
        ? 'data:image/png;base64,${base64Encode(schoolLogoBytes)}'
        : null;

    pagesHtml.writeln('<section class="print-page cover-page">');
    pagesHtml.writeln('<div class="whole-page-border">');
    pagesHtml.writeln('<div class="whole-page-inner">');
    pagesHtml.writeln(_renderSheetSliceTable(
      wb: wb,
      sheet: coverSheet,
      rows: coverRows,
      cols: coverCols,
      colorMode: colorMode,
      tableClass: 'xlsx-table cover-table',
      logoDataUri: logoDataUri,
      logoTargetRow: 7,
      logoTargetColStart: isCoed ? 5 : 4,
    ));
    pagesHtml.writeln('</div></div></section>');

    final visibleStudentRows = <int>[
      for (var r = 4; r <= 2000; r++)
        if (registerSheet.cells.containsKey(r) &&
            !registerSheet.hiddenRows.contains(r))
          r,
    ];
    final summaryRows = <int>[
      for (var r = 2001; r <= 2008; r++)
        if (registerSheet.cells.containsKey(r) &&
            !registerSheet.hiddenRows.contains(r))
          r,
    ];

    final double clampedRowPx = rowHeightPx.clamp(12, 48).toDouble();
    final double clampedFontPt = fontSizePt.clamp(4, 16).toDouble();
    final rowScale = clampedRowPx / 22.0;
    final desiredStudentPt = math.max(
      9.0,
      math.min(36.0, math.max(15.0 * rowScale, clampedFontPt * 1.45)),
    );
    final summaryRowPt = math.max(
      13.5,
      math.min(22.0, math.max(15.0 * rowScale, (clampedFontPt + 1) * 1.35)),
    );

    const usableHeightPt = 535.0;
    const headerHeightPt = 92.0;
    final availableRegularPt = usableHeightPt - headerHeightPt;
    final summaryTotalPt = summaryRows.length * summaryRowPt;
    final availableLastPt = math.max(120.0, availableRegularPt - summaryTotalPt);

    final rowsPerPage =
        math.max(8, (availableRegularPt / desiredStudentPt).floor());
    final rowsOnLastPage =
        math.max(4, (availableLastPt / desiredStudentPt).floor());

    final studentChunks = <List<int>>[];
    var idx = 0;
    while (idx < visibleStudentRows.length) {
      final remaining = visibleStudentRows.length - idx;
      if (remaining <= rowsOnLastPage) {
        studentChunks.add(visibleStudentRows.sublist(idx));
        break;
      }
      if (remaining <= rowsPerPage) {
        final takeCount = math.max(1, remaining - rowsOnLastPage);
        studentChunks.add(visibleStudentRows.sublist(idx, idx + takeCount));
        idx += takeCount;
      } else {
        studentChunks.add(visibleStudentRows.sublist(idx, idx + rowsPerPage));
        idx += rowsPerPage;
      }
    }
    if (studentChunks.isEmpty) {
      studentChunks.add(const <int>[]);
    }

    final totalCols = isCoed ? 49 : 48;
    final leftCols = <int>[
      for (var c = 1; c <= 18; c++)
        if (!registerSheet.hiddenCols.contains(c)) c,
    ];
    final rightCols = <int>[
      for (var c = 21; c <= totalCols; c++)
        if (!registerSheet.hiddenCols.contains(c)) c,
    ];

    for (var cIdx = 0; cIdx < studentChunks.length; cIdx++) {
      final chunk = studentChunks[cIdx];
      final isLastChunk = cIdx == studentChunks.length - 1;
      final pageRows = <int>[
        1,
        2,
        3,
        ...chunk,
        if (isLastChunk) ...summaryRows,
      ];

      final availForStudents =
          isLastChunk ? availableLastPt : availableRegularPt;
      final stretchedStudentPt = chunk.isEmpty
          ? desiredStudentPt
          : (availForStudents / chunk.length)
              .clamp(desiredStudentPt * 0.9, 34.0)
              .toDouble();

      final rowHeightOverridesPt = <int, double>{
        1: 20.0,
        2: 44.0,
        3: 26.0,
        for (final r in chunk) r: stretchedStudentPt,
        for (final r in summaryRows) r: summaryRowPt,
      };

      pagesHtml.writeln('<section class="print-page register-left-page">');
      pagesHtml.writeln(_renderSheetSliceTable(
        wb: wb,
        sheet: registerSheet,
        rows: pageRows,
        cols: leftCols,
        colorMode: colorMode,
        tableClass: 'xlsx-table register-table',
        rowHeightOverridesPt: rowHeightOverridesPt,
        studentRowSet: chunk.toSet(),
        summaryRowSet: summaryRows.toSet(),
        studentFontSizePt: clampedFontPt.toDouble(),
      ));
      pagesHtml.writeln('</section>');

      pagesHtml.writeln('<section class="print-page register-right-page">');
      pagesHtml.writeln(_renderSheetSliceTable(
        wb: wb,
        sheet: registerSheet,
        rows: pageRows,
        cols: rightCols,
        colorMode: colorMode,
        tableClass: 'xlsx-table register-table',
        rowHeightOverridesPt: rowHeightOverridesPt,
        studentRowSet: chunk.toSet(),
        summaryRowSet: summaryRows.toSet(),
        studentFontSizePt: clampedFontPt.toDouble(),
      ));
      pagesHtml.writeln('</section>');
    }

    return _wrapHtmlDocument(
      title: documentTitle,
      pageSizeCss: 'A4 landscape',
      pageMarginCss: '5mm',
      pageWidthMm: 287.0,
      pageHeightMm: 200.0,
      bodyHtml: pagesHtml.toString(),
    );
  }

  void _populateHajariRegisteredTotal(
    _XlsxSheetData sheet, {
    required bool isCoed,
  }) {
    final regCol = isCoed ? 9 : 8;
    var total = 0;
    var hasAny = false;
    for (var r = 2001; r <= 2004; r++) {
      final raw = sheet.cellAt(r, regCol)?.text.trim() ?? '';
      final parsed = int.tryParse(raw);
      if (parsed != null) {
        total += parsed;
        hasAny = true;
      }
    }
    if (hasAny) {
      final existing = sheet.cellAt(2005, regCol)?.text.trim() ?? '';
      if (existing.isEmpty || existing == '0') {
        sheet.setCellText(2005, regCol, '$total', isNumeric: true);
      }
    }
  }

  void _prepareHajariDatesAndHolidays(
    _XlsxSheetData sheet, {
    required int year,
    required int month,
    required int daysInMonth,
    required Set<String> holidayIsoDates,
    required bool isCoed,
  }) {
    const gujaratiWeekdays = <int, String>{
      DateTime.monday: 'સોમ',
      DateTime.tuesday: 'મંગળ',
      DateTime.wednesday: 'બુધ',
      DateTime.thursday: 'ગુરુ',
      DateTime.friday: 'શુક્ર',
      DateTime.saturday: 'શનિ',
      DateTime.sunday: 'રવિ',
    };
    final firstDayCol = isCoed ? 13 : 12;
    for (var day = 1; day <= 31; day++) {
      final col = firstDayCol + day - 1;
      if (day > daysInMonth) {
        sheet.hiddenCols.add(col);
        continue;
      }
      final dt = DateTime(year, month, day);
      final iso =
          '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      final weekdayName = gujaratiWeekdays[dt.weekday] ?? '';
      sheet.setCellText(2, col, weekdayName);
      sheet.setCellText(3, col, '$day', isNumeric: true);

      final isSunday = dt.weekday == DateTime.sunday;
      final isHoliday = holidayIsoDates.contains(iso);
      if (isSunday || isHoliday) {
        for (final entry in sheet.cells.entries) {
          final r = entry.key;
          if (r >= 2 && (r <= 2000 || (r >= 2001 && r <= 2008))) {
            final cell = entry.value[col];
            if (cell != null && isSunday) {
              cell.forceGreyBackground = true;
            }
          }
        }
      }
    }
  }

  // ===========================================================================
  // 2. RESULT FRONT PAGE & RESULT SHEET HTML RENDERER
  // ===========================================================================
  String renderResultWorkbookToHtml({
    required Uint8List workbookBytes,
    required String view,
    required int rowHeightPx,
    required int fontSizePt,
    Uint8List? schoolLogoBytes,
    Set<int> doubleBorderStudentIndices = const <int>{},
    required String documentTitle,
  }) {
    final normalizedView = view.trim().toLowerCase();
    if (normalizedView == 'vv') {
      return renderVyaktitvaVikasWorkbooksToHtml(
        workbookBytesList: <Uint8List>[workbookBytes],
        rowHeightPx: rowHeightPx,
        fontSizePt: fontSizePt,
        doubleBorderStudentIndices: doubleBorderStudentIndices,
        documentTitle: documentTitle,
      );
    }

    final wb = _parseWorkbook(workbookBytes);

    if (normalizedView == 'front') {
      final frontSheet = _findVisibleSheet(
        wb,
        preferredPaths: const <String>[
          'xl/worksheets/sheet1.xml',
          'xl/worksheets/sheet6.xml',
        ],
      );
      final isSem2 = frontSheet.path.endsWith('sheet6.xml');
      final cols = <int>[for (var c = 2; c <= 21; c++) c];
      final rows = <int>[
        for (var r = 1; r <= 23; r++)
          if (!frontSheet.hiddenRows.contains(r)) r,
      ];
      final logoDataUri = (schoolLogoBytes != null && schoolLogoBytes.isNotEmpty)
          ? 'data:image/png;base64,${base64Encode(schoolLogoBytes)}'
          : null;

      final pagesHtml = StringBuffer();
      pagesHtml.writeln('<section class="print-page result-front-page">');
      pagesHtml.writeln('<div class="whole-page-border">');
      pagesHtml.writeln('<div class="whole-page-inner">');
      pagesHtml.writeln(_renderSheetSliceTable(
        wb: wb,
        sheet: frontSheet,
        rows: rows,
        cols: cols,
        colorMode: true,
        tableClass: 'xlsx-table result-front-table',
        logoDataUri: logoDataUri,
        logoTargetRow: 4,
        logoTargetColStart: 2,
      ));
      pagesHtml.writeln('</div></div></section>');

      return _wrapHtmlDocument(
        title: documentTitle,
        pageSizeCss: isSem2 ? 'legal portrait' : 'A4 portrait',
        pageMarginCss: '6mm',
        pageWidthMm: 203.0,
        pageHeightMm: isSem2 ? 343.0 : 285.0,
        bodyHtml: pagesHtml.toString(),
      );
    }

    final resultSheet = _findVisibleSheet(
      wb,
      preferredPaths: const <String>[
        'xl/worksheets/sheet2.xml',
        'xl/worksheets/sheet3.xml',
        'xl/worksheets/sheet5.xml',
        'xl/worksheets/sheet7.xml',
      ],
    );
    final isCoed = resultSheet.path.endsWith('sheet3.xml') ||
        resultSheet.path.endsWith('sheet5.xml');
    final isSem2 = resultSheet.path.endsWith('sheet5.xml') ||
        resultSheet.path.endsWith('sheet7.xml');

    final pageSpecs = _buildResultPageSpecs(
      resultSheet,
      isCoed: isCoed,
      isSem2: isSem2,
    );

    final studentRows = <int>[
      for (final r in resultSheet.cells.keys.toList()..sort())
        if (r >= 7 &&
            !resultSheet.hiddenRows.contains(r) &&
            _rowHasStudentIdentity(resultSheet, r))
          r,
    ];

    final catCol = 3;
    for (var i = 0; i < studentRows.length; i++) {
      final r = studentRows[i];
      final curCat = _normalizeCategory(resultSheet.cellAt(r, catCol)?.text ?? '');
      final nextCat = (i + 1 < studentRows.length)
          ? _normalizeCategory(
              resultSheet.cellAt(studentRows[i + 1], catCol)?.text ?? '')
          : '';
      final isCategoryEnd = (i == studentRows.length - 1) ||
          (curCat.isNotEmpty && nextCat.isNotEmpty && curCat != nextCat) ||
          doubleBorderStudentIndices.contains(i);
      if (isCategoryEnd) {
        final rowCells = resultSheet.cells[r];
        if (rowCells != null) {
          for (final cell in rowCells.values) {
            cell.forceDoubleBottom = true;
          }
        }
      }
    }

    final double clampedRowPx = rowHeightPx.clamp(12, 36).toDouble();
    final double clampedFontPt = fontSizePt.clamp(4, 12).toDouble();
    final rowScale = clampedRowPx / 22.0;

    final usablePagePt = isSem2 ? 968.0 : 802.0;
    final headerHeightsPt = <int, double>{
      1: isSem2 ? 22.0 : 20.0,
      2: isSem2 ? 19.0 : 17.0,
      3: isSem2 ? 15.0 : 14.0,
      4: isSem2 ? 52.0 : 46.0,
      5: isSem2 ? 18.0 : 16.0,
      6: isSem2 ? 18.0 : 16.0,
    };
    final totalHeaderPt =
        headerHeightsPt.values.fold<double>(0.0, (a, b) => a + b);
    final availableStudentPt = math.max(180.0, usablePagePt - totalHeaderPt - 10.0);

    final baseRowPt = isSem2 ? 17.5 : 16.0;
    final desiredRowPt = math.max(
      11.5,
      math.min(36.0, math.max(baseRowPt * rowScale, clampedFontPt * 1.55)),
    );
    final studentsPerPage =
        (availableStudentPt / desiredRowPt).floor().clamp(8, 55).toInt();

    final studentBatches = <List<int>>[];
    for (var i = 0; i < studentRows.length; i += studentsPerPage) {
      studentBatches.add(
        studentRows.sublist(
          i,
          math.min(studentRows.length, i + studentsPerPage),
        ),
      );
    }
    if (studentBatches.isEmpty) {
      studentBatches.add(const <int>[]);
    }

    final pagesHtml = StringBuffer();
    for (var bIdx = 0; bIdx < studentBatches.length; bIdx++) {
      final batch = studentBatches[bIdx];
      final effectiveRowPt = batch.isEmpty
          ? desiredRowPt
          : (availableStudentPt / batch.length)
              .clamp(desiredRowPt, 34.0)
              .toDouble();
      final padBlankCount = batch.isEmpty
          ? 0
          : math.max(
              0,
              ((availableStudentPt - (batch.length * effectiveRowPt)) /
                      effectiveRowPt)
                  .floor(),
            );

      final rowHeightOverridesPt = <int, double>{
        ...headerHeightsPt,
        for (final r in batch) r: effectiveRowPt,
      };

      for (final spec in pageSpecs) {
        final sliceRows = <int>[1, 2, 3, 4, 5, 6, ...batch];
        pagesHtml.writeln('<section class="print-page result-sheet-page">');
        pagesHtml.writeln(_renderSheetSliceTable(
          wb: wb,
          sheet: resultSheet,
          rows: sliceRows,
          cols: spec.cols,
          colorMode: true,
          tableClass: 'xlsx-table result-table',
          rowHeightOverridesPt: rowHeightOverridesPt,
          studentRowSet: batch.toSet(),
          studentFontSizePt: clampedFontPt.toDouble(),
          headerFontSizePt: math.max(6.5, clampedFontPt - 0.5),
          blankPadRowsCount: padBlankCount,
          blankPadRowHeightPt: effectiveRowPt,
          isResultSheetSlice: true,
        ));
        pagesHtml.writeln('</section>');
      }
    }

    return _wrapHtmlDocument(
      title: documentTitle,
      pageSizeCss: isSem2 ? 'legal portrait' : 'A4 portrait',
      pageMarginCss: '5mm',
      pageWidthMm: 205.0,
      pageHeightMm: isSem2 ? 345.0 : 287.0,
      bodyHtml: pagesHtml.toString(),
    );
  }

  List<_ResultPageSpec> _buildResultPageSpecs(
    _XlsxSheetData sheet, {
    required bool isCoed,
    required bool isSem2,
  }) {
    final baseCols = isCoed ? 9 : 8;
    final groupW = isSem2 ? 8 : 5;
    final firstSubCol = baseCols + 1;

    var maxCol = 0;
    for (final rowMap in sheet.cells.values) {
      for (final c in rowMap.keys) {
        if (c > maxCol) maxCol = c;
      }
    }

    final activeSubjectRanges = <(int, int)>[];
    var col = firstSubCol;
    var tailStart = maxCol + 1;

    while (col + groupW - 1 <= maxCol) {
      final header2 = _mergedOrCellText(sheet, 2, col).trim();
      final header3 = _mergedOrCellText(sheet, 3, col).trim();
      if (header2.contains('વ્યક્તિત્વ') ||
          header3.contains('વ્યક્તિત્વ') ||
          header2.contains('કુલ ગુણ') ||
          header2.toUpperCase().contains('UID')) {
        tailStart = col;
        break;
      }
      if (!sheet.hiddenCols.contains(col) && header2.isNotEmpty) {
        final visibleInGroup = <int>[
          for (var c = col; c < col + groupW; c++)
            if (!sheet.hiddenCols.contains(c)) c,
        ];
        if (visibleInGroup.isNotEmpty) {
          activeSubjectRanges.add((visibleInGroup.first, visibleInGroup.last));
        }
      }
      col += groupW;
    }

    if (tailStart > maxCol) {
      tailStart = firstSubCol + activeSubjectRanges.length * groupW;
    }

    final visibleTailCols = <int>[
      for (var c = tailStart; c <= maxCol; c++)
        if (!sheet.hiddenCols.contains(c)) c,
    ];

    final uidPenCols = <int>[];
    final summaryCols = <int>[];
    for (final c in visibleTailCols) {
      final h2 = _mergedOrCellText(sheet, 2, c).toUpperCase();
      final h4 = _mergedOrCellText(sheet, 4, c).toUpperCase();
      if (h2.contains('UID') ||
          h2.contains('PEN') ||
          h2.contains('ડાયસ') ||
          h4.contains('UID') ||
          h4.contains('PEN')) {
        uidPenCols.add(c);
      } else {
        summaryCols.add(c);
      }
    }

    final specs = <_ResultPageSpec>[];
    final baseColList = <int>[
      for (var c = 1; c <= baseCols; c++)
        if (!sheet.hiddenCols.contains(c)) c,
    ];
    const idCols = <int>[1, 2];

    if (activeSubjectRanges.isEmpty) {
      specs.add(_ResultPageSpec(
        kind: 'first',
        cols: <int>[...baseColList, ...summaryCols, ...uidPenCols],
      ));
      return specs;
    }

    final firstSub = activeSubjectRanges.first;
    specs.add(_ResultPageSpec(
      kind: 'first',
      cols: <int>[
        ...baseColList,
        for (var c = firstSub.$1; c <= firstSub.$2; c++)
          if (!sheet.hiddenCols.contains(c)) c,
      ],
    ));

    final remainingSubjects = activeSubjectRanges.sublist(1);
    final totalSubjects = activeSubjectRanges.length;

    if (totalSubjects % 2 == 0) {
      var idx = 0;
      while (idx + 1 < remainingSubjects.length) {
        final g1 = remainingSubjects[idx];
        final g2 = remainingSubjects[idx + 1];
        specs.add(_ResultPageSpec(
          kind: 'subjects',
          cols: <int>[
            ...idCols,
            for (var c = g1.$1; c <= g1.$2; c++)
              if (!sheet.hiddenCols.contains(c)) c,
            for (var c = g2.$1; c <= g2.$2; c++)
              if (!sheet.hiddenCols.contains(c)) c,
          ],
        ));
        idx += 2;
      }
      final lastSub = remainingSubjects.last;
      specs.add(_ResultPageSpec(
        kind: 'last_sub_and_summary',
        cols: <int>[
          ...idCols,
          for (var c = lastSub.$1; c <= lastSub.$2; c++)
            if (!sheet.hiddenCols.contains(c)) c,
          ...summaryCols,
        ],
      ));
    } else {
      for (var idx = 0; idx < remainingSubjects.length; idx += 2) {
        final g1 = remainingSubjects[idx];
        final g2 = remainingSubjects[idx + 1];
        specs.add(_ResultPageSpec(
          kind: 'subjects',
          cols: <int>[
            ...idCols,
            for (var c = g1.$1; c <= g1.$2; c++)
              if (!sheet.hiddenCols.contains(c)) c,
            for (var c = g2.$1; c <= g2.$2; c++)
              if (!sheet.hiddenCols.contains(c)) c,
          ],
        ));
      }
      if (summaryCols.isNotEmpty) {
        specs.add(_ResultPageSpec(
          kind: 'summary',
          cols: <int>[...idCols, ...summaryCols],
        ));
      }
    }

    if (uidPenCols.isNotEmpty) {
      specs.add(_ResultPageSpec(
        kind: 'uid_pen',
        cols: <int>[...idCols, ...uidPenCols],
      ));
    }

    return specs;
  }

  // ===========================================================================
  // 3. VYAKTITVA VIKAS LEGAL LANDSCAPE HTML RENDERER
  // ===========================================================================
  String renderVyaktitvaVikasWorkbooksToHtml({
    required List<Uint8List> workbookBytesList,
    required int rowHeightPx,
    required int fontSizePt,
    Set<int> doubleBorderStudentIndices = const <int>{},
    required String documentTitle,
  }) {
    final pagesHtml = StringBuffer();
    final double clampedRowPx = rowHeightPx.clamp(12, 38).toDouble();
    final double clampedFontPt = fontSizePt.clamp(4, 12).toDouble();
    final rowScale = clampedRowPx / 22.0;

    const usableHeightPt = 576.0;
    final headerHeightsPt = <int, double>{
      1: 20.0,
      2: 18.0,
      3: 15.0,
      4: 24.0,
      5: 112.0,
    };
    final totalHeaderPt =
        headerHeightsPt.values.fold<double>(0.0, (a, b) => a + b);
    final availableStudentPt = math.max(180.0, usableHeightPt - totalHeaderPt);

    final desiredRowPt = math.max(
      12.5,
      math.min(34.0, math.max(15.5 * rowScale, clampedFontPt * 1.55)),
    );
    final studentsPerPage =
        (availableStudentPt / desiredRowPt).floor().clamp(8, 36).toInt();

    for (final bytes in workbookBytesList) {
      final wb = _parseWorkbook(bytes);
      final vvSheet = _findVisibleSheet(
        wb,
        preferredPaths: const <String>[
          'xl/worksheets/sheet4.xml',
          'xl/worksheets/sheet8.xml',
        ],
      );
      final isSem2 = vvSheet.path.endsWith('sheet8.xml');
      final maxCol = isSem2 ? 45 : 43;
      final cols = <int>[
        for (var c = 1; c <= maxCol; c++)
          if (!vvSheet.hiddenCols.contains(c)) c,
      ];

      final studentRows = <int>[
        for (final r in vvSheet.cells.keys.toList()..sort())
          if (r >= 6 &&
              !vvSheet.hiddenRows.contains(r) &&
              _rowHasStudentIdentity(vvSheet, r))
            r,
      ];

      for (var i = 0; i < studentRows.length; i++) {
        if (i == studentRows.length - 1 ||
            doubleBorderStudentIndices.contains(i)) {
          final rowMap = vvSheet.cells[studentRows[i]];
          if (rowMap != null) {
            for (final cell in rowMap.values) {
              cell.forceDoubleBottom = true;
            }
          }
        }
      }

      final batches = <List<int>>[];
      for (var i = 0; i < studentRows.length; i += studentsPerPage) {
        batches.add(
          studentRows.sublist(
            i,
            math.min(studentRows.length, i + studentsPerPage),
          ),
        );
      }
      if (batches.isEmpty) {
        batches.add(const <int>[]);
      }

      for (final batch in batches) {
        final effectiveRowPt = batch.isEmpty
            ? desiredRowPt
            : (availableStudentPt / batch.length)
                .clamp(desiredRowPt, 32.0)
                .toDouble();
        final padBlankCount = batch.isEmpty
            ? 0
            : math.max(
                0,
                ((availableStudentPt - (batch.length * effectiveRowPt)) /
                        effectiveRowPt)
                    .floor(),
              );

        final rowHeightOverridesPt = <int, double>{
          ...headerHeightsPt,
          for (final r in batch) r: effectiveRowPt,
        };

        pagesHtml.writeln('<section class="print-page vv-page">');
        pagesHtml.writeln(_renderSheetSliceTable(
          wb: wb,
          sheet: vvSheet,
          rows: <int>[1, 2, 3, 4, 5, ...batch],
          cols: cols,
          colorMode: true,
          tableClass: 'xlsx-table vv-table',
          rowHeightOverridesPt: rowHeightOverridesPt,
          studentRowSet: batch.toSet(),
          studentFontSizePt: clampedFontPt.toDouble(),
          headerFontSizePt: math.max(6.2, clampedFontPt - 0.5),
          blankPadRowsCount: padBlankCount,
          blankPadRowHeightPt: effectiveRowPt,
        ));
        pagesHtml.writeln('</section>');
      }
    }

    return _wrapHtmlDocument(
      title: documentTitle,
      pageSizeCss: 'legal landscape',
      pageMarginCss: '4mm',
      pageWidthMm: 347.0,
      pageHeightMm: 207.0,
      bodyHtml: pagesHtml.toString(),
    );
  }

  // ===========================================================================
  // 4. CORE TABLE SLICE HTML GENERATOR
  // ===========================================================================
  String _renderSheetSliceTable({
    required _XlsxWorkbookModel wb,
    required _XlsxSheetData sheet,
    required List<int> rows,
    required List<int> cols,
    required bool colorMode,
    required String tableClass,
    Map<int, double> rowHeightOverridesPt = const <int, double>{},
    Set<int> studentRowSet = const <int>{},
    Set<int> summaryRowSet = const <int>{},
    double? studentFontSizePt,
    double? headerFontSizePt,
    String? logoDataUri,
    int? logoTargetRow,
    int? logoTargetColStart,
    int blankPadRowsCount = 0,
    double blankPadRowHeightPt = 16.0,
    bool isResultSheetSlice = false,
  }) {
    if (rows.isEmpty || cols.isEmpty) return '';

    final rowIndexMap = <int, int>{
      for (var i = 0; i < rows.length; i++) rows[i]: i,
    };
    final colIndexMap = <int, int>{
      for (var i = 0; i < cols.length; i++) cols[i]: i,
    };

    final rawColWeights = <double>[
      for (final c in cols)
        math.max(2.2, sheet.colWidths[c] ?? 8.43),
    ];
    final totalWeight =
        rawColWeights.fold<double>(0.0, (sum, w) => sum + w);

    final skipCells = <(int, int)>{};
    final spanByTopLeft = <(int, int), (int, int, int, int)>{};

    for (final m in sheet.merges) {
      final intersectingRows = <int>[
        for (final r in rows)
          if (r >= m.r1 && r <= m.r2) r,
      ];
      final intersectingCols = <int>[
        for (final c in cols)
          if (c >= m.c1 && c <= m.c2) c,
      ];
      if (intersectingRows.isEmpty || intersectingCols.isEmpty) continue;
      if (intersectingRows.length == 1 && intersectingCols.length == 1) {
        final r = intersectingRows.first;
        final c = intersectingCols.first;
        if (r != m.r1 || c != m.c1) {
          spanByTopLeft[(r, c)] = (1, 1, m.r1, m.c1);
        }
        continue;
      }
      final topR = intersectingRows.first;
      final leftC = intersectingCols.first;
      spanByTopLeft[(topR, leftC)] = (
        intersectingRows.length,
        intersectingCols.length,
        m.r1,
        m.c1,
      );
      for (final r in intersectingRows) {
        for (final c in intersectingCols) {
          if (r != topR || c != leftC) {
            skipCells.add((r, c));
          }
        }
      }
    }

    if (isResultSheetSlice && rows.contains(1) && cols.length > 1) {
      final firstC = cols.first;
      spanByTopLeft[(1, firstC)] = (1, cols.length, 1, 1);
      for (final c in cols.skip(1)) {
        skipCells.add((1, c));
      }
    }

    final sb = StringBuffer();
    sb.writeln('<table class="$tableClass">');
    sb.writeln('<colgroup>');
    for (final w in rawColWeights) {
      final pct = totalWeight > 0 ? (w * 100.0 / totalWeight) : (100.0 / cols.length);
      sb.writeln('<col style="width:${pct.toStringAsFixed(3)}%;">');
    }
    sb.writeln('</colgroup>');
    sb.writeln('<tbody>');

    for (final r in rows) {
      final rowPt = rowHeightOverridesPt[r] ?? sheet.rowHeightsPt[r] ?? 18.0;
      sb.writeln('<tr style="height:${rowPt.toStringAsFixed(2)}pt;">');

      for (final c in cols) {
        if (skipCells.contains((r, c))) continue;

        final spanInfo = spanByTopLeft[(r, c)];
        final rowSpan = spanInfo?.$1 ?? 1;
        final colSpan = spanInfo?.$2 ?? 1;
        final sourceR = spanInfo?.$3 ?? r;
        final sourceC = spanInfo?.$4 ?? c;

        final cell = sheet.cellAt(r, c) ?? sheet.cellAt(sourceR, sourceC);
        final styleCell = sheet.cellAt(r, c) ?? cell;
        final xfIndex = styleCell?.styleIndex ?? 0;
        final xf = (xfIndex >= 0 && xfIndex < wb.xfs.length)
            ? wb.xfs[xfIndex]
            : const _XlsxCellXf();
        final font = (xf.fontId >= 0 && xf.fontId < wb.fonts.length)
            ? wb.fonts[xf.fontId]
            : const _XlsxFontStyle();
        final fillHex = (xf.fillId >= 0 && xf.fillId < wb.fills.length)
            ? wb.fills[xf.fillId]
            : null;
        final border = (xf.borderId >= 0 && xf.borderId < wb.borders.length)
            ? wb.borders[xf.borderId]
            : const _XlsxBorderStyle();

        final endR = rows[math.min(rows.length - 1, (rowIndexMap[r] ?? 0) + rowSpan - 1)];
        final endC = cols[math.min(cols.length - 1, (colIndexMap[c] ?? 0) + colSpan - 1)];
        final endCell = sheet.cellAt(endR, endC);
        final endXf = (endCell != null &&
                endCell.styleIndex >= 0 &&
                endCell.styleIndex < wb.xfs.length)
            ? wb.xfs[endCell.styleIndex]
            : xf;
        final endBorder =
            (endXf.borderId >= 0 && endXf.borderId < wb.borders.length)
                ? wb.borders[endXf.borderId]
                : border;

        var text = cell?.text ?? '';
        if (isResultSheetSlice && r == 1 && c == cols.first && text.trim().isEmpty) {
          text = _mergedOrCellText(sheet, 1, 1);
        }

        final isStudentRow = studentRowSet.contains(r);
        final isSummaryRow = summaryRowSet.contains(r);

        double fontSize = font.sizePt;
        if (isStudentRow && studentFontSizePt != null) {
          fontSize = studentFontSizePt;
        } else if (isSummaryRow && studentFontSizePt != null) {
          fontSize = math.max(7.0, studentFontSizePt - 0.5);
        } else if (!isStudentRow &&
            !isSummaryRow &&
            headerFontSizePt != null &&
            r >= 3) {
          fontSize = math.min(font.sizePt, headerFontSizePt);
        }

        final css = StringBuffer();
        css.write('font-size:${fontSize.toStringAsFixed(1)}pt;');
        if (font.bold || isSummaryRow) {
          css.write('font-weight:700;');
        }
        if (font.italic) {
          css.write('font-style:italic;');
        }

        if (cell?.forceGreyBackground == true) {
          css.write('background-color:#D9D9D9;');
        } else if (colorMode && fillHex != null) {
          css.write('background-color:$fillHex;');
        }
        if (colorMode && font.colorHex != null) {
          css.write('color:${font.colorHex};');
        } else {
          css.write('color:#000000;');
        }

        css.write(_borderSideCss('border-top', border.top));
        css.write(_borderSideCss('border-left', border.left));
        css.write(_borderSideCss(
          'border-right',
          !endBorder.right.isNone ? endBorder.right : border.right,
        ));
        if (cell?.forceDoubleBottom == true ||
            endCell?.forceDoubleBottom == true) {
          css.write('border-bottom:2.4pt double #000000;');
        } else {
          css.write(_borderSideCss(
            'border-bottom',
            !endBorder.bottom.isNone ? endBorder.bottom : border.bottom,
          ));
        }

        final hAlign = _resolveHorizontalAlign(xf.horizontal, cell, c, isStudentRow);
        css.write('text-align:$hAlign;');
        final vAlign = xf.vertical == 'top'
            ? 'top'
            : (xf.vertical == 'bottom' ? 'bottom' : 'middle');
        css.write('vertical-align:$vAlign;');

        if (!xf.wrapText && isStudentRow) {
          css.write('white-space:nowrap;overflow:hidden;');
        }

        final spanAttrs = StringBuffer();
        if (rowSpan > 1) spanAttrs.write(' rowspan="$rowSpan"');
        if (colSpan > 1) spanAttrs.write(' colspan="$colSpan"');

        final isLogoTarget = logoDataUri != null &&
            logoTargetRow == r &&
            logoTargetColStart != null &&
            c <= logoTargetColStart &&
            (c + colSpan - 1) >= logoTargetColStart;

        if (isLogoTarget) {
          final logoHeightPt = math.max(48.0, rowPt * rowSpan - 8.0);
          sb.write('<td$spanAttrs style="$css">');
          if (text.trim().isNotEmpty) {
            sb.write(
              '<div class="logo-with-title">'
              '<img src="$logoDataUri" style="max-height:${logoHeightPt.toStringAsFixed(0)}pt;max-width:110pt;object-fit:contain;" alt="Logo">'
              '<div class="logo-title-text">${_escapeHtml(text)}</div>'
              '</div>',
            );
          } else {
            sb.write(
              '<div class="logo-box">'
              '<img src="$logoDataUri" style="max-height:${logoHeightPt.toStringAsFixed(0)}pt;max-width:160pt;object-fit:contain;" alt="Logo">'
              '</div>',
            );
          }
          sb.writeln('</td>');
        } else if (xf.textRotation == 90 || xf.textRotation == 255) {
          var spanHeightPt = 0.0;
          final startIdx = rowIndexMap[r] ?? 0;
          for (var k = 0; k < rowSpan && (startIdx + k) < rows.length; k++) {
            final rr = rows[startIdx + k];
            spanHeightPt +=
                rowHeightOverridesPt[rr] ?? sheet.rowHeightsPt[rr] ?? 18.0;
          }
          final maxVertPt = math.max(18.0, spanHeightPt - 4.0);
          sb.write('<td$spanAttrs style="$css">');
          sb.write(
            '<div class="rot90-wrap" style="max-height:${maxVertPt.toStringAsFixed(1)}pt;">'
            '<span class="rot90-text">${_escapeHtml(text)}</span>'
            '</div>',
          );
          sb.writeln('</td>');
        } else {
          final formattedHtml = _escapeHtml(text).replaceAll('\n', '<br>');
          sb.writeln('<td$spanAttrs style="$css">$formattedHtml</td>');
        }
      }
      sb.writeln('</tr>');
    }

    for (var b = 0; b < blankPadRowsCount; b++) {
      sb.writeln(
          '<tr style="height:${blankPadRowHeightPt.toStringAsFixed(2)}pt;">');
      for (var i = 0; i < cols.length; i++) {
        sb.writeln(
          '<td style="border:0.5pt solid #000000;">&nbsp;</td>',
        );
      }
      sb.writeln('</tr>');
    }

    sb.writeln('</tbody></table>');
    return sb.toString();
  }

  String _resolveHorizontalAlign(
    String xfHorizontal,
    _XlsxCellData? cell,
    int col,
    bool isStudentRow,
  ) {
    final h = xfHorizontal.toLowerCase();
    if (h == 'left') return 'left';
    if (h == 'right') return 'right';
    if (h == 'center' || h == 'centercontinuous') return 'center';
    if (isStudentRow && col == 2) return 'left';
    return 'center';
  }

  String _borderSideCss(String prop, _XlsxBorderSide side) {
    if (side.isNone) return '';
    final color = side.colorHex;
    switch (side.style) {
      case 'double':
        return '$prop:2.2pt double $color;';
      case 'thick':
        return '$prop:1.5pt solid $color;';
      case 'medium':
        return '$prop:1.0pt solid $color;';
      case 'dashed':
      case 'mediumDashed':
        return '$prop:0.7pt dashed $color;';
      case 'dotted':
      case 'hair':
        return '$prop:0.5pt dotted $color;';
      default:
        return '$prop:0.55pt solid $color;';
    }
  }

  String _wrapHtmlDocument({
    required String title,
    required String pageSizeCss,
    required String pageMarginCss,
    required double pageWidthMm,
    required double pageHeightMm,
    required String bodyHtml,
  }) {
    final escapedTitle = _escapeHtml(title);
    return '''<!DOCTYPE html>
<html lang="gu">
<head>
  <meta charset="utf-8">
  <title>$escapedTitle</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Noto+Sans+Gujarati:wght@400;600;700;800&display=swap" rel="stylesheet">
  <style>
    @page {
      size: $pageSizeCss;
      margin: $pageMarginCss;
    }
    * {
      box-sizing: border-box;
      -webkit-print-color-adjust: exact !important;
      print-color-adjust: exact !important;
    }
    html, body {
      margin: 0;
      padding: 0;
      background: #e2e8f0;
      font-family: 'Noto Sans GujaratiLocal', 'Noto Sans Gujarati', 'Shruti', 'Nirmala UI', sans-serif;
      color: #000000;
    }
    .print-toolbar {
      position: sticky;
      top: 0;
      z-index: 9999;
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 10px 18px;
      background: #0f172a;
      color: #ffffff;
      box-shadow: 0 2px 8px rgba(0,0,0,0.25);
    }
    .print-toolbar-title {
      font-size: 14px;
      font-weight: 700;
    }
    .print-toolbar-actions {
      display: flex;
      gap: 10px;
    }
    .print-btn {
      background: #16a34a;
      color: #ffffff;
      border: none;
      border-radius: 8px;
      padding: 8px 16px;
      font-size: 13px;
      font-weight: 800;
      cursor: pointer;
      font-family: inherit;
    }
    .close-btn {
      background: #475569;
      color: #ffffff;
      border: none;
      border-radius: 8px;
      padding: 8px 14px;
      font-size: 13px;
      font-weight: 700;
      cursor: pointer;
      font-family: inherit;
    }
    .pages-container {
      display: flex;
      flex-direction: column;
      align-items: center;
      padding: 14px 0 32px;
      gap: 16px;
    }
    .print-page {
      width: ${pageWidthMm.toStringAsFixed(1)}mm;
      height: ${pageHeightMm.toStringAsFixed(1)}mm;
      background: #ffffff;
      box-shadow: 0 4px 14px rgba(0,0,0,0.18);
      padding: 2mm;
      display: flex;
      flex-direction: column;
      justify-content: stretch;
      overflow: hidden;
      page-break-after: always;
      break-after: page;
    }
    .print-page:last-child {
      page-break-after: auto;
      break-after: auto;
    }
    .register-left-page {
      padding-right: 13mm;
    }
    .register-right-page {
      padding-left: 13mm;
    }
    .whole-page-border {
      width: 100%;
      height: 100%;
      border: 2.2pt solid #000000;
      padding: 2.5pt;
      display: flex;
      flex-direction: column;
    }
    .whole-page-inner {
      width: 100%;
      height: 100%;
      border: 0.75pt solid #000000;
      padding: 3mm;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
    }
    .xlsx-table {
      width: 100%;
      height: 100%;
      border-collapse: collapse;
      table-layout: fixed;
    }
    .xlsx-table td {
      padding: 1px 2px;
      line-height: 1.12;
      overflow: hidden;
    }
    .rot90-wrap {
      display: flex;
      align-items: center;
      justify-content: center;
      width: 100%;
      height: 100%;
      overflow: hidden;
    }
    .rot90-text {
      writing-mode: vertical-rl;
      transform: rotate(180deg);
      white-space: nowrap;
      line-height: 1.05;
      text-align: center;
      display: inline-block;
    }
    .logo-box {
      display: flex;
      align-items: center;
      justify-content: center;
      width: 100%;
      height: 100%;
    }
    .logo-with-title {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 12px;
      width: 100%;
      height: 100%;
    }
    .logo-title-text {
      flex: 1;
      text-align: center;
    }
    @media print {
      html, body {
        background: #ffffff;
      }
      .print-toolbar {
        display: none !important;
      }
      .pages-container {
        padding: 0;
        gap: 0;
        display: block;
      }
      .print-page {
        width: 100%;
        height: ${pageHeightMm.toStringAsFixed(1)}mm;
        box-shadow: none;
        margin: 0;
      }
    }
  </style>
</head>
<body>
  <div class="print-toolbar">
    <div class="print-toolbar-title">🖨️ $escapedTitle — Print / Save as PDF</div>
    <div class="print-toolbar-actions">
      <button class="print-btn" onclick="window.print()">🖨️ પ્રિન્ટ / Save as PDF</button>
      <button class="close-btn" onclick="window.close()">✕ બંધ કરો</button>
    </div>
  </div>
  <div class="pages-container">
    $bodyHtml
  </div>
  <script>
    window.addEventListener('load', function () {
      if (document.fonts && document.fonts.ready) {
        document.fonts.ready.then(function () {
          setTimeout(function () { window.focus(); window.print(); }, 250);
        });
      } else {
        setTimeout(function () { window.focus(); window.print(); }, 450);
      }
    });
  </script>
</body>
</html>''';
  }

  // ===========================================================================
  // 4B. MULTI-TAB GOOGLE SHEETS WORKBOOK (.XLSX) SLICER
  // ===========================================================================
  Uint8List buildHajariGoogleSheetsWorkbook({
    required Uint8List workbookBytes,
    required String schoolType,
    required int year,
    required int month,
    required Set<String> holidayIsoDates,
    required int rowHeightPx,
    required int fontSizePt,
  }) {
    final wb = _parseWorkbook(workbookBytes);
    final normalizedType = SchoolType.canonical(schoolType);
    final isCoed = normalizedType == SchoolType.mixed;

    final coverPath = normalizedType == SchoolType.boys
        ? 'xl/worksheets/sheet1.xml'
        : (normalizedType == SchoolType.girls
            ? 'xl/worksheets/sheet2.xml'
            : 'xl/worksheets/sheet3.xml');
    final registerPath =
        isCoed ? 'xl/worksheets/sheet5.xml' : 'xl/worksheets/sheet4.xml';

    final coverSheet = wb.sheetsByPath[coverPath] ?? wb.sheetsByPath.values.first;
    final registerSheet =
        wb.sheetsByPath[registerPath] ?? wb.sheetsByPath.values.last;

    _populateHajariRegisteredTotal(registerSheet, isCoed: isCoed);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    _prepareHajariDatesAndHolidays(
      registerSheet,
      year: year,
      month: month,
      daysInMonth: daysInMonth,
      holidayIsoDates: holidayIsoDates,
      isCoed: isCoed,
    );

    final slices = <_XlsxTabSliceSpec>[];
    final coverMaxCol = isCoed ? 16 : 10;
    slices.add(_XlsxTabSliceSpec(
      title: 'COVER',
      sheet: coverSheet,
      rows: <int>[
        for (var r = 1; r <= 27; r++)
          if (!coverSheet.hiddenRows.contains(r)) r,
      ],
      cols: <int>[for (var c = 1; c <= coverMaxCol; c++) c],
    ));

    final visibleStudentRows = <int>[
      for (var r = 4; r <= 2000; r++)
        if (registerSheet.cells.containsKey(r) &&
            !registerSheet.hiddenRows.contains(r))
          r,
    ];
    final summaryRows = <int>[
      for (var r = 2001; r <= 2008; r++)
        if (registerSheet.cells.containsKey(r) &&
            !registerSheet.hiddenRows.contains(r))
          r,
    ];

    final double clampedRowPx = rowHeightPx.clamp(12, 48).toDouble();
    final double clampedFontPt = fontSizePt.clamp(4, 16).toDouble();
    final rowScale = clampedRowPx / 22.0;
    final desiredStudentPt = math.max(
      9.0,
      math.min(36.0, math.max(15.0 * rowScale, clampedFontPt * 1.45)),
    );
    final summaryRowPt = math.max(
      13.5,
      math.min(22.0, math.max(15.0 * rowScale, (clampedFontPt + 1) * 1.35)),
    );

    const usableHeightPt = 535.0;
    const headerHeightPt = 92.0;
    final availableRegularPt = usableHeightPt - headerHeightPt;
    final summaryTotalPt = summaryRows.length * summaryRowPt;
    final availableLastPt = math.max(120.0, availableRegularPt - summaryTotalPt);

    final rowsPerPage =
        math.max(8, (availableRegularPt / desiredStudentPt).floor());
    final rowsOnLastPage =
        math.max(4, (availableLastPt / desiredStudentPt).floor());

    final studentChunks = <List<int>>[];
    var idx = 0;
    while (idx < visibleStudentRows.length) {
      final remaining = visibleStudentRows.length - idx;
      if (remaining <= rowsOnLastPage) {
        studentChunks.add(visibleStudentRows.sublist(idx));
        break;
      }
      if (remaining <= rowsPerPage) {
        final takeCount = math.max(1, remaining - rowsOnLastPage);
        studentChunks.add(visibleStudentRows.sublist(idx, idx + takeCount));
        idx += takeCount;
      } else {
        studentChunks.add(visibleStudentRows.sublist(idx, idx + rowsPerPage));
        idx += rowsPerPage;
      }
    }
    if (studentChunks.isEmpty) {
      studentChunks.add(const <int>[]);
    }

    final totalCols = isCoed ? 49 : 48;
    final leftCols = <int>[
      for (var c = 1; c <= 20; c++)
        if (!registerSheet.hiddenCols.contains(c)) c,
    ];
    final rightCols = <int>[
      19,
      20,
      for (var c = 21; c <= totalCols; c++)
        if (!registerSheet.hiddenCols.contains(c)) c,
    ];

    for (var cIdx = 0; cIdx < studentChunks.length; cIdx++) {
      final chunk = studentChunks[cIdx];
      final isLastChunk = cIdx == studentChunks.length - 1;
      final pageRows = <int>[
        1,
        2,
        3,
        ...chunk,
        if (isLastChunk) ...summaryRows,
      ];
      final availForStudents =
          isLastChunk ? availableLastPt : availableRegularPt;
      final stretchedStudentPt = chunk.isEmpty
          ? desiredStudentPt
          : (availForStudents / chunk.length)
              .clamp(desiredStudentPt * 0.9, 34.0)
              .toDouble();

      final rowHeightOverridesPt = <int, double>{
        1: 20.0,
        2: 44.0,
        3: 26.0,
        for (final r in chunk) r: stretchedStudentPt,
        for (final r in summaryRows) r: summaryRowPt,
      };

      slices.add(_XlsxTabSliceSpec(
        title: 'LEFT_${cIdx + 1}',
        sheet: registerSheet,
        rows: pageRows,
        cols: leftCols,
        rowHeightOverridesPt: rowHeightOverridesPt,
      ));
      slices.add(_XlsxTabSliceSpec(
        title: 'RIGHT_${cIdx + 1}',
        sheet: registerSheet,
        rows: pageRows,
        cols: rightCols,
        rowHeightOverridesPt: rowHeightOverridesPt,
      ));
    }

    return _encodeSlicedWorkbook(workbookBytes, slices);
  }

  (Uint8List, bool) buildResultGoogleSheetsWorkbook({
    required Uint8List workbookBytes,
    required String view,
    required int rowHeightPx,
    required int fontSizePt,
    Set<int> doubleBorderStudentIndices = const <int>{},
  }) {
    final normalizedView = view.trim().toLowerCase();
    if (normalizedView == 'vv') {
      return (
        buildVyaktitvaVikasGoogleSheetsWorkbook(
          workbookBytesList: <Uint8List>[workbookBytes],
          rowHeightPx: rowHeightPx,
          fontSizePt: fontSizePt,
          doubleBorderStudentIndices: doubleBorderStudentIndices,
        ),
        true,
      );
    }

    final wb = _parseWorkbook(workbookBytes);
    if (normalizedView == 'front') {
      final frontSheet = _findVisibleSheet(
        wb,
        preferredPaths: const <String>[
          'xl/worksheets/sheet1.xml',
          'xl/worksheets/sheet6.xml',
        ],
      );
      final isSem2 = frontSheet.path.endsWith('sheet6.xml');
      final cols = <int>[for (var c = 1; c <= (isSem2 ? 23 : 22); c++) c];
      final rows = <int>[
        for (var r = 1; r <= 24; r++)
          if (!frontSheet.hiddenRows.contains(r)) r,
      ];
      final slices = <_XlsxTabSliceSpec>[
        _XlsxTabSliceSpec(
          title: 'FRONT_PAGE',
          sheet: frontSheet,
          rows: rows,
          cols: cols,
          rowHeightOverridesPt: const <int, double>{4: 200.0},
        ),
      ];
      return (_encodeSlicedWorkbook(workbookBytes, slices), isSem2);
    }

    final resultSheet = _findVisibleSheet(
      wb,
      preferredPaths: const <String>[
        'xl/worksheets/sheet2.xml',
        'xl/worksheets/sheet3.xml',
        'xl/worksheets/sheet5.xml',
        'xl/worksheets/sheet7.xml',
      ],
    );
    final isCoed = resultSheet.path.endsWith('sheet3.xml') ||
        resultSheet.path.endsWith('sheet5.xml');
    final isSem2 = resultSheet.path.endsWith('sheet5.xml') ||
        resultSheet.path.endsWith('sheet7.xml');

    final pageSpecs = _buildResultPageSpecs(
      resultSheet,
      isCoed: isCoed,
      isSem2: isSem2,
    );

    final studentRows = <int>[
      for (final r in resultSheet.cells.keys.toList()..sort())
        if (r >= 7 &&
            !resultSheet.hiddenRows.contains(r) &&
            _rowHasStudentIdentity(resultSheet, r))
          r,
    ];

    final double clampedRowPx = rowHeightPx.clamp(12, 36).toDouble();
    final double clampedFontPt = fontSizePt.clamp(4, 12).toDouble();
    final rowScale = clampedRowPx / 22.0;

    final usablePagePt = isSem2 ? 968.0 : 802.0;
    final headerHeightsPt = <int, double>{
      1: isSem2 ? 22.0 : 20.0,
      2: isSem2 ? 19.0 : 17.0,
      3: isSem2 ? 15.0 : 14.0,
      4: isSem2 ? 52.0 : 46.0,
      5: isSem2 ? 18.0 : 16.0,
      6: isSem2 ? 18.0 : 16.0,
    };
    final totalHeaderPt =
        headerHeightsPt.values.fold<double>(0.0, (a, b) => a + b);
    final availableStudentPt =
        math.max(180.0, usablePagePt - totalHeaderPt - 10.0);

    final baseRowPt = isSem2 ? 17.5 : 16.0;
    final desiredRowPt = math.max(
      11.5,
      math.min(36.0, math.max(baseRowPt * rowScale, clampedFontPt * 1.55)),
    );
    final studentsPerPage =
        (availableStudentPt / desiredRowPt).floor().clamp(8, 55).toInt();

    final studentBatches = <List<int>>[];
    for (var i = 0; i < studentRows.length; i += studentsPerPage) {
      studentBatches.add(
        studentRows.sublist(
          i,
          math.min(studentRows.length, i + studentsPerPage),
        ),
      );
    }
    if (studentBatches.isEmpty) {
      studentBatches.add(const <int>[]);
    }

    final slices = <_XlsxTabSliceSpec>[];
    var pageCounter = 1;
    for (final batch in studentBatches) {
      final effectiveRowPt = batch.isEmpty
          ? desiredRowPt
          : (availableStudentPt / batch.length)
              .clamp(desiredRowPt, 34.0)
              .toDouble();
      final padBlankCount = batch.isEmpty
          ? 0
          : math.max(
              0,
              ((availableStudentPt - (batch.length * effectiveRowPt)) /
                      effectiveRowPt)
                  .floor(),
            );
      final rowHeightOverridesPt = <int, double>{
        ...headerHeightsPt,
        for (final r in batch) r: effectiveRowPt,
      };
      for (final spec in pageSpecs) {
        slices.add(_XlsxTabSliceSpec(
          title: 'RES_P$pageCounter',
          sheet: resultSheet,
          rows: <int>[1, 2, 3, 4, 5, 6, ...batch],
          cols: spec.cols,
          rowHeightOverridesPt: rowHeightOverridesPt,
          blankPadRowsCount: padBlankCount,
          blankPadRowHeightPt: effectiveRowPt,
          isResultSheetSlice: true,
        ));
        pageCounter++;
      }
    }

    return (_encodeSlicedWorkbook(workbookBytes, slices), isSem2);
  }

  Uint8List buildVyaktitvaVikasGoogleSheetsWorkbook({
    required List<Uint8List> workbookBytesList,
    required int rowHeightPx,
    required int fontSizePt,
    Set<int> doubleBorderStudentIndices = const <int>{},
  }) {
    if (workbookBytesList.isEmpty) {
      throw StateError('No Vyaktitva Vikas workbook bytes provided.');
    }
    final double clampedRowPx = rowHeightPx.clamp(12, 38).toDouble();
    final double clampedFontPt = fontSizePt.clamp(4, 12).toDouble();
    final rowScale = clampedRowPx / 22.0;

    const usableHeightPt = 576.0;
    final headerHeightsPt = <int, double>{
      1: 20.0,
      2: 18.0,
      3: 15.0,
      4: 24.0,
      5: 112.0,
    };
    final totalHeaderPt =
        headerHeightsPt.values.fold<double>(0.0, (a, b) => a + b);
    final availableStudentPt = math.max(180.0, usableHeightPt - totalHeaderPt);

    final desiredRowPt = math.max(
      12.5,
      math.min(34.0, math.max(15.5 * rowScale, clampedFontPt * 1.55)),
    );
    final studentsPerPage =
        (availableStudentPt / desiredRowPt).floor().clamp(8, 36).toInt();

    final slices = <_XlsxTabSliceSpec>[];
    var pageCounter = 1;
    for (final bytes in workbookBytesList) {
      final wb = _parseWorkbook(bytes);
      final vvSheet = _findVisibleSheet(
        wb,
        preferredPaths: const <String>[
          'xl/worksheets/sheet4.xml',
          'xl/worksheets/sheet8.xml',
        ],
      );
      final isSem2 = vvSheet.path.endsWith('sheet8.xml');
      final maxCol = isSem2 ? 45 : 43;
      final cols = <int>[
        for (var c = 1; c <= maxCol; c++)
          if (!vvSheet.hiddenCols.contains(c)) c,
      ];
      final studentRows = <int>[
        for (final r in vvSheet.cells.keys.toList()..sort())
          if (r >= 6 &&
              !vvSheet.hiddenRows.contains(r) &&
              _rowHasStudentIdentity(vvSheet, r))
            r,
      ];
      final batches = <List<int>>[];
      for (var i = 0; i < studentRows.length; i += studentsPerPage) {
        batches.add(
          studentRows.sublist(
            i,
            math.min(studentRows.length, i + studentsPerPage),
          ),
        );
      }
      if (batches.isEmpty) {
        batches.add(const <int>[]);
      }
      for (final batch in batches) {
        final effectiveRowPt = batch.isEmpty
            ? desiredRowPt
            : (availableStudentPt / batch.length)
                .clamp(desiredRowPt, 32.0)
                .toDouble();
        final padBlankCount = batch.isEmpty
            ? 0
            : math.max(
                0,
                ((availableStudentPt - (batch.length * effectiveRowPt)) /
                        effectiveRowPt)
                    .floor(),
              );
        final rowHeightOverridesPt = <int, double>{
          ...headerHeightsPt,
          for (final r in batch) r: effectiveRowPt,
        };
        slices.add(_XlsxTabSliceSpec(
          title: 'VV_P$pageCounter',
          sheet: vvSheet,
          rows: <int>[1, 2, 3, 4, 5, ...batch],
          cols: cols,
          rowHeightOverridesPt: rowHeightOverridesPt,
          blankPadRowsCount: padBlankCount,
          blankPadRowHeightPt: effectiveRowPt,
        ));
        pageCounter++;
      }
    }

    return _encodeSlicedWorkbook(workbookBytesList.first, slices);
  }

  Uint8List _encodeSlicedWorkbook(
    Uint8List baseWorkbookBytes,
    List<_XlsxTabSliceSpec> slices,
  ) {
    final baseArchive = ZipDecoder().decodeBytes(baseWorkbookBytes);
    final outArchive = Archive();

    for (final file in baseArchive.files) {
      if (!file.isFile) continue;
      final name = file.name;
      if (name.startsWith('xl/worksheets/') ||
          name.startsWith('xl/printerSettings/') ||
          name.startsWith('xl/drawings/') ||
          name == 'xl/workbook.xml' ||
          name == 'xl/_rels/workbook.xml.rels' ||
          name == '[Content_Types].xml' ||
          name == 'xl/sharedStrings.xml') {
        continue;
      }
      outArchive.addFile(ArchiveFile(
        name,
        file.size,
        file.content as List<int>,
      ));
    }

    for (var i = 0; i < slices.length; i++) {
      final sheetXml = _buildSlicedWorksheetXml(slices[i]);
      final bytes = utf8.encode(sheetXml);
      outArchive.addFile(ArchiveFile(
        'xl/worksheets/sheet${i + 1}.xml',
        bytes.length,
        bytes,
      ));
    }

    final wbXml = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln(
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">',
      )
      ..writeln('<sheets>');
    for (var i = 0; i < slices.length; i++) {
      wbXml.writeln(
        '<sheet name="${_escapeXmlAttr(slices[i].title)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>',
      );
    }
    wbXml
      ..writeln('</sheets>')
      ..writeln('</workbook>');
    final wbBytes = utf8.encode(wbXml.toString());
    outArchive.addFile(ArchiveFile('xl/workbook.xml', wbBytes.length, wbBytes));

    final relsXml = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln(
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
      );
    for (var i = 0; i < slices.length; i++) {
      relsXml.writeln(
        '<Relationship Id="rId${i + 1}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
        'Target="worksheets/sheet${i + 1}.xml"/>',
      );
    }
    relsXml.writeln(
      '<Relationship Id="rId${slices.length + 1}" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
      'Target="styles.xml"/>',
    );
    relsXml.writeln(
      '<Relationship Id="rId${slices.length + 2}" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" '
      'Target="theme/theme1.xml"/>',
    );
    relsXml.writeln('</Relationships>');
    final relsBytes = utf8.encode(relsXml.toString());
    outArchive.addFile(
      ArchiveFile('xl/_rels/workbook.xml.rels', relsBytes.length, relsBytes),
    );

    final ctXml = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln(
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">',
      )
      ..writeln(
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>',
      )
      ..writeln('<Default Extension="xml" ContentType="application/xml"/>')
      ..writeln('<Default Extension="png" ContentType="image/png"/>')
      ..writeln('<Default Extension="jpeg" ContentType="image/jpeg"/>')
      ..writeln(
        '<Override PartName="/xl/workbook.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>',
      )
      ..writeln(
        '<Override PartName="/xl/styles.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>',
      )
      ..writeln(
        '<Override PartName="/xl/theme/theme1.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>',
      );
    for (var i = 0; i < slices.length; i++) {
      ctXml.writeln(
        '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
      );
    }
    ctXml.writeln('</Types>');
    final ctBytes = utf8.encode(ctXml.toString());
    outArchive.addFile(ArchiveFile('[Content_Types].xml', ctBytes.length, ctBytes));

    final encoded = ZipEncoder().encode(outArchive);
    return Uint8List.fromList(encoded);
  }

  String _buildSlicedWorksheetXml(_XlsxTabSliceSpec spec) {
    final sheet = spec.sheet;
    final rows = spec.rows;
    final cols = spec.cols;

    final newRowByOld = <int, int>{
      for (var i = 0; i < rows.length; i++) rows[i]: i + 1,
    };
    final newColByOld = <int, int>{
      for (var i = 0; i < cols.length; i++) cols[i]: i + 1,
    };

    final mergeRefs = <String>[];
    final sourceCellFallback = <(int, int), (int, int)>{};

    for (final m in sheet.merges) {
      final intRows = <int>[
        for (final r in rows)
          if (r >= m.r1 && r <= m.r2) r,
      ];
      final intCols = <int>[
        for (final c in cols)
          if (c >= m.c1 && c <= m.c2) c,
      ];
      if (intRows.isEmpty || intCols.isEmpty) continue;
      final topOldR = intRows.first;
      final leftOldC = intCols.first;
      if (topOldR != m.r1 || leftOldC != m.c1) {
        sourceCellFallback[(topOldR, leftOldC)] = (m.r1, m.c1);
      }
      if (intRows.length > 1 || intCols.length > 1) {
        final nr1 = newRowByOld[intRows.first]!;
        final nc1 = newColByOld[intCols.first]!;
        final nr2 = newRowByOld[intRows.last]!;
        final nc2 = newColByOld[intCols.last]!;
        if (!spec.isResultSheetSlice || nr1 != 1) {
          mergeRefs.add('${_colLetters(nc1)}$nr1:${_colLetters(nc2)}$nr2');
        }
      }
    }

    if (spec.isResultSheetSlice && rows.contains(1) && cols.length > 1) {
      mergeRefs.insert(0, 'A1:${_colLetters(cols.length)}1');
      sourceCellFallback[(1, cols.first)] = (1, 1);
    }

    final sb = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln(
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">',
      )
      ..writeln('<sheetViews><sheetView workbookViewId="0" showGridLines="0"/></sheetViews>')
      ..writeln('<cols>');

    for (var i = 0; i < cols.length; i++) {
      final oldC = cols[i];
      final newC = i + 1;
      final w = math.max(2.5, sheet.colWidths[oldC] ?? 8.43);
      sb.writeln(
        '<col min="$newC" max="$newC" width="${w.toStringAsFixed(2)}" customWidth="1"/>',
      );
    }
    sb.writeln('</cols>');
    sb.writeln('<sheetData>');

    for (var rIdx = 0; rIdx < rows.length; rIdx++) {
      final oldR = rows[rIdx];
      final newR = rIdx + 1;
      final ht =
          spec.rowHeightOverridesPt[oldR] ?? sheet.rowHeightsPt[oldR] ?? 18.0;
      sb.writeln(
        '<row r="$newR" ht="${ht.toStringAsFixed(2)}" customHeight="1">',
      );
      for (var cIdx = 0; cIdx < cols.length; cIdx++) {
        final oldC = cols[cIdx];
        final newC = cIdx + 1;
        final ref = '${_colLetters(newC)}$newR';
        final direct = sheet.cellAt(oldR, oldC);
        final fbCoords = sourceCellFallback[(oldR, oldC)];
        final fbCell = fbCoords != null
            ? sheet.cellAt(fbCoords.$1, fbCoords.$2)
            : null;
        final styleIdx = direct?.styleIndex ?? fbCell?.styleIndex ?? 0;
        var text = (direct != null && direct.text.trim().isNotEmpty)
            ? direct.text
            : (fbCell?.text ?? '');
        if (spec.isResultSheetSlice &&
            newR == 1 &&
            newC == 1 &&
            text.trim().isEmpty) {
          text = _mergedOrCellText(sheet, 1, 1);
        }
        final isNum =
            (direct?.isNumeric ?? fbCell?.isNumeric ?? false) &&
            double.tryParse(text.trim()) != null;

        if (text.isEmpty) {
          sb.write('<c r="$ref" s="$styleIdx"/>');
        } else if (isNum) {
          sb.write('<c r="$ref" s="$styleIdx" t="n"><v>${text.trim()}</v></c>');
        } else {
          sb.write(
            '<c r="$ref" s="$styleIdx" t="inlineStr"><is><t>${_escapeXmlAttr(text)}</t></is></c>',
          );
        }
      }
      sb.writeln('</row>');
    }

    final sampleStudentOldR = rows.isNotEmpty ? rows.last : 1;
    for (var b = 0; b < spec.blankPadRowsCount; b++) {
      final newR = rows.length + b + 1;
      sb.writeln(
        '<row r="$newR" ht="${spec.blankPadRowHeightPt.toStringAsFixed(2)}" customHeight="1">',
      );
      for (var cIdx = 0; cIdx < cols.length; cIdx++) {
        final oldC = cols[cIdx];
        final newC = cIdx + 1;
        final ref = '${_colLetters(newC)}$newR';
        final styleIdx = sheet.cellAt(sampleStudentOldR, oldC)?.styleIndex ?? 0;
        sb.write('<c r="$ref" s="$styleIdx"/>');
      }
      sb.writeln('</row>');
    }

    sb.writeln('</sheetData>');
    if (mergeRefs.isNotEmpty) {
      sb.writeln('<mergeCells count="${mergeRefs.length}">');
      for (final mRef in mergeRefs) {
        sb.writeln('<mergeCell ref="$mRef"/>');
      }
      sb.writeln('</mergeCells>');
    }
    sb.writeln(
      '<pageMargins left="0.16" right="0.16" top="0.16" bottom="0.16" header="0.08" footer="0.08"/>',
    );
    sb.writeln('</worksheet>');
    return sb.toString();
  }

  static String _colLetters(int colNumber) {
    var n = colNumber;
    final sb = StringBuffer();
    while (n > 0) {
      final rem = (n - 1) % 26;
      sb.writeCharCode(65 + rem);
      n = (n - 1) ~/ 26;
    }
    return sb.toString().split('').reversed.join();
  }

  static String _escapeXmlAttr(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  // ===========================================================================
  // 5. OOXML (.xlsx) PARSER
  // ===========================================================================
  _XlsxWorkbookModel _parseWorkbook(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final filesByName = <String, ArchiveFile>{
      for (final file in archive.files)
        if (file.isFile) file.name: file,
    };

    String readXml(String path) {
      final f = filesByName[path];
      if (f == null) return '';
      return utf8.decode(f.content as List<int>, allowMalformed: true);
    }

    final sharedStrings = _parseSharedStrings(readXml('xl/sharedStrings.xml'));
    final styles = _parseStyles(readXml('xl/styles.xml'));
    final sheetMeta = _parseWorkbookSheets(
      readXml('xl/workbook.xml'),
      readXml('xl/_rels/workbook.xml.rels'),
    );

    final sheetsByPath = <String, _XlsxSheetData>{};
    for (final meta in sheetMeta) {
      final xml = readXml(meta.path);
      if (xml.isEmpty) continue;
      sheetsByPath[meta.path] = _parseWorksheet(
        xml: xml,
        name: meta.name,
        path: meta.path,
        hidden: meta.hidden,
        sharedStrings: sharedStrings,
        xfs: styles.$4,
      );
    }

    return _XlsxWorkbookModel(
      fonts: styles.$1,
      fills: styles.$2,
      borders: styles.$3,
      xfs: styles.$4,
      sheetsByPath: sheetsByPath,
    );
  }

  List<String> _parseSharedStrings(String xml) {
    if (xml.isEmpty) return const <String>[];
    final result = <String>[];
    final siRegex = RegExp(r'<si\b[^>]*>(.*?)</si>', dotAll: true);
    final tRegex = RegExp(r'<t(?:\s+[^>]*)?>(.*?)</t>', dotAll: true);
    for (final siMatch in siRegex.allMatches(xml)) {
      final siBody = siMatch.group(1) ?? '';
      final sb = StringBuffer();
      for (final tMatch in tRegex.allMatches(siBody)) {
        sb.write(_unescapeXml(tMatch.group(1) ?? ''));
      }
      result.add(sb.toString());
    }
    return result;
  }

  (
    List<_XlsxFontStyle>,
    List<String?>,
    List<_XlsxBorderStyle>,
    List<_XlsxCellXf>
  ) _parseStyles(String xml) {
    final fonts = <_XlsxFontStyle>[];
    final fills = <String?>[];
    final borders = <_XlsxBorderStyle>[];
    final xfs = <_XlsxCellXf>[];

    if (xml.isEmpty) {
      return (
        const <_XlsxFontStyle>[_XlsxFontStyle()],
        const <String?>[null],
        const <_XlsxBorderStyle>[_XlsxBorderStyle()],
        const <_XlsxCellXf>[_XlsxCellXf()],
      );
    }

    final fontsBlock =
        RegExp(r'<fonts\b[^>]*>(.*?)</fonts>', dotAll: true).firstMatch(xml)?.group(1) ?? '';
    for (final m in RegExp(r'<font\b[^>]*>(.*?)</font>', dotAll: true).allMatches(fontsBlock)) {
      final body = m.group(1) ?? '';
      final bold = RegExp(r'<b(?:\s*/>|\s+val="1"|\s+val="true")').hasMatch(body);
      final italic = RegExp(r'<i(?:\s*/>|\s+val="1"|\s+val="true")').hasMatch(body);
      final szStr = RegExp(r'<sz\b[^>]*\bval="([^"]+)"').firstMatch(body)?.group(1);
      final sz = double.tryParse(szStr ?? '') ?? 10.0;
      final rgb = RegExp(r'<color\b[^>]*\brgb="([^"]+)"').firstMatch(body)?.group(1);
      final name = RegExp(r'<name\b[^>]*\bval="([^"]+)"').firstMatch(body)?.group(1) ??
          'Noto Sans Gujarati';
      fonts.add(_XlsxFontStyle(
        bold: bold,
        italic: italic,
        sizePt: sz,
        colorHex: _argbToCssHex(rgb),
        name: name,
      ));
    }

    final fillsBlock =
        RegExp(r'<fills\b[^>]*>(.*?)</fills>', dotAll: true).firstMatch(xml)?.group(1) ?? '';
    for (final m in RegExp(r'<fill\b[^>]*>(.*?)</fill>', dotAll: true).allMatches(fillsBlock)) {
      final body = m.group(1) ?? '';
      final pattern =
          RegExp(r'<patternFill\b[^>]*\bpatternType="([^"]+)"').firstMatch(body)?.group(1) ??
              'none';
      if (pattern == 'none' || pattern == 'gray125') {
        fills.add(null);
      } else {
        final rgb = RegExp(r'<fgColor\b[^>]*\brgb="([^"]+)"').firstMatch(body)?.group(1);
        final hex = _argbToCssHex(rgb);
        fills.add((hex == '#FFFFFF' || hex == '#000000') ? null : hex);
      }
    }

    final bordersBlock =
        RegExp(r'<borders\b[^>]*>(.*?)</borders>', dotAll: true).firstMatch(xml)?.group(1) ?? '';
    for (final m in RegExp(r'<border\b[^>]*>(.*?)</border>', dotAll: true).allMatches(bordersBlock)) {
      final body = m.group(1) ?? '';
      borders.add(_XlsxBorderStyle(
        left: _parseBorderSide(body, 'left'),
        right: _parseBorderSide(body, 'right'),
        top: _parseBorderSide(body, 'top'),
        bottom: _parseBorderSide(body, 'bottom'),
      ));
    }

    final cellXfsBlock =
        RegExp(r'<cellXfs\b[^>]*>(.*?)</cellXfs>', dotAll: true).firstMatch(xml)?.group(1) ?? '';
    for (final m in RegExp(r'<xf\b([^>]*)(?:/>|>(.*?)</xf>)', dotAll: true).allMatches(cellXfsBlock)) {
      final attrs = m.group(1) ?? '';
      final body = m.group(2) ?? '';
      final fontId = int.tryParse(_attr(attrs, 'fontId') ?? '0') ?? 0;
      final fillId = int.tryParse(_attr(attrs, 'fillId') ?? '0') ?? 0;
      final borderId = int.tryParse(_attr(attrs, 'borderId') ?? '0') ?? 0;
      final numFmtId = int.tryParse(_attr(attrs, 'numFmtId') ?? '0') ?? 0;

      final alignTag = RegExp(r'<alignment\b([^>]*)/?>').firstMatch(body)?.group(1) ?? '';
      final horizontal = _attr(alignTag, 'horizontal') ?? '';
      final vertical = _attr(alignTag, 'vertical') ?? 'center';
      final textRotation = int.tryParse(_attr(alignTag, 'textRotation') ?? '0') ?? 0;
      final wrapText = (_attr(alignTag, 'wrapText') ?? '') == '1' ||
          (_attr(alignTag, 'wrapText') ?? '') == 'true';

      xfs.add(_XlsxCellXf(
        fontId: fontId,
        fillId: fillId,
        borderId: borderId,
        numFmtId: numFmtId,
        horizontal: horizontal,
        vertical: vertical,
        textRotation: textRotation,
        wrapText: wrapText,
      ));
    }

    return (fonts, fills, borders, xfs);
  }

  _XlsxBorderSide _parseBorderSide(String borderBody, String sideName) {
    final m = RegExp('<$sideName\\b([^>]*)(?:/>|>(.*?)</$sideName>)', dotAll: true)
        .firstMatch(borderBody);
    if (m == null) return const _XlsxBorderSide();
    final attrs = m.group(1) ?? '';
    final body = m.group(2) ?? '';
    final style = _attr(attrs, 'style') ?? 'none';
    if (style == 'none' || style.isEmpty) return const _XlsxBorderSide();
    final rgb = RegExp(r'<color\b[^>]*\brgb="([^"]+)"').firstMatch(body)?.group(1);
    return _XlsxBorderSide(
      style: style,
      colorHex: _argbToCssHex(rgb) ?? '#000000',
    );
  }

  List<({String name, String path, bool hidden})> _parseWorkbookSheets(
    String workbookXml,
    String relsXml,
  ) {
    final targetById = <String, String>{};
    for (final m in RegExp(r'<Relationship\b([^>]*)/?>').allMatches(relsXml)) {
      final attrs = m.group(1) ?? '';
      final id = _attr(attrs, 'Id') ?? '';
      var target = _attr(attrs, 'Target') ?? '';
      if (id.isEmpty || target.isEmpty) continue;
      if (target.startsWith('/')) {
        target = target.substring(1);
      } else if (!target.startsWith('xl/')) {
        target = 'xl/$target';
      }
      targetById[id] = target;
    }

    final result = <({String name, String path, bool hidden})>[];
    var idx = 1;
    for (final m in RegExp(r'<sheet\b([^>]*)/?>').allMatches(workbookXml)) {
      final attrs = m.group(1) ?? '';
      final name = _unescapeXml(_attr(attrs, 'name') ?? 'Sheet$idx');
      final rId = _attr(attrs, 'r:id') ?? '';
      final state = (_attr(attrs, 'state') ?? '').toLowerCase();
      final hidden = state == 'hidden' || state == 'veryhidden';
      final path = targetById[rId] ?? 'xl/worksheets/sheet$idx.xml';
      result.add((name: name, path: path, hidden: hidden));
      idx++;
    }
    return result;
  }

  _XlsxSheetData _parseWorksheet({
    required String xml,
    required String name,
    required String path,
    required bool hidden,
    required List<String> sharedStrings,
    required List<_XlsxCellXf> xfs,
  }) {
    final colWidths = <int, double>{};
    final hiddenCols = <int>{};
    for (final m in RegExp(r'<col\b([^>]*)/?>').allMatches(xml)) {
      final attrs = m.group(1) ?? '';
      final minC = int.tryParse(_attr(attrs, 'min') ?? '') ?? 0;
      final maxC = int.tryParse(_attr(attrs, 'max') ?? '') ?? minC;
      final width = double.tryParse(_attr(attrs, 'width') ?? '') ?? 8.43;
      final isHidden = (_attr(attrs, 'hidden') ?? '') == '1' ||
          (_attr(attrs, 'hidden') ?? '') == 'true';
      for (var c = minC; c <= maxC; c++) {
        colWidths[c] = width;
        if (isHidden || width <= 0.05) {
          hiddenCols.add(c);
        }
      }
    }

    final rowHeightsPt = <int, double>{};
    final hiddenRows = <int>{};
    final cells = <int, Map<int, _XlsxCellData>>{};

    final rowRegex = RegExp(r'<row\b([^>]*)(?:/>|>(.*?)</row>)', dotAll: true);
    final cellRegex = RegExp(r'<c\b([^>]*)(?:/>|>(.*?)</c>)', dotAll: true);
    final vRegex = RegExp(r'<v>(.*?)</v>', dotAll: true);
    final tRegex = RegExp(r'<t(?:\s+[^>]*)?>(.*?)</t>', dotAll: true);

    for (final rowMatch in rowRegex.allMatches(xml)) {
      final rAttrs = rowMatch.group(1) ?? '';
      final rBody = rowMatch.group(2) ?? '';
      final rNum = int.tryParse(_attr(rAttrs, 'r') ?? '') ?? 0;
      if (rNum <= 0) continue;

      final ht = double.tryParse(_attr(rAttrs, 'ht') ?? '');
      if (ht != null && ht > 0) {
        rowHeightsPt[rNum] = ht;
      }
      final isRowHidden = (_attr(rAttrs, 'hidden') ?? '') == '1' ||
          (_attr(rAttrs, 'hidden') ?? '') == 'true' ||
          (ht != null && ht <= 0.1);
      if (isRowHidden) {
        hiddenRows.add(rNum);
      }

      if (rBody.isEmpty) continue;
      final rowMap = cells.putIfAbsent(rNum, () => <int, _XlsxCellData>{});

      for (final cMatch in cellRegex.allMatches(rBody)) {
        final cAttrs = cMatch.group(1) ?? '';
        final cBody = cMatch.group(2) ?? '';
        final ref = _attr(cAttrs, 'r') ?? '';
        final colNum = _colIndexFromRef(ref);
        if (colNum <= 0) continue;

        final styleIdx = int.tryParse(_attr(cAttrs, 's') ?? '0') ?? 0;
        final cType = _attr(cAttrs, 't') ?? '';

        var text = '';
        var isNumeric = false;
        if (cType == 's') {
          final vRaw = vRegex.firstMatch(cBody)?.group(1)?.trim() ?? '';
          final sIdx = int.tryParse(vRaw);
          if (sIdx != null && sIdx >= 0 && sIdx < sharedStrings.length) {
            text = sharedStrings[sIdx];
          }
        } else if (cType == 'inlineStr' || cType == 'str') {
          final sb = StringBuffer();
          for (final tm in tRegex.allMatches(cBody)) {
            sb.write(_unescapeXml(tm.group(1) ?? ''));
          }
          if (sb.isEmpty) {
            text = _unescapeXml(vRegex.firstMatch(cBody)?.group(1) ?? '');
          } else {
            text = sb.toString();
          }
        } else {
          final vRaw = _unescapeXml(vRegex.firstMatch(cBody)?.group(1)?.trim() ?? '');
          if (vRaw.isNotEmpty) {
            final numVal = double.tryParse(vRaw);
            if (numVal != null) {
              isNumeric = true;
              final xf = (styleIdx >= 0 && styleIdx < xfs.length)
                  ? xfs[styleIdx]
                  : const _XlsxCellXf();
              if ((numVal - numVal.roundToDouble()).abs() < 1e-6 &&
                  xf.numFmtId != 2 &&
                  xf.numFmtId != 4) {
                text = '${numVal.round()}';
              } else {
                text = numVal.toStringAsFixed(2);
              }
            } else {
              text = vRaw;
            }
          }
        }

        rowMap[colNum] = _XlsxCellData(
          row: rNum,
          col: colNum,
          styleIndex: styleIdx,
          text: text,
          isNumeric: isNumeric,
        );
      }
    }

    final merges = <_XlsxMergeRange>[];
    for (final m in RegExp(r'<mergeCell\b[^>]*\bref="([^"]+)"').allMatches(xml)) {
      final ref = m.group(1) ?? '';
      final parts = ref.split(':');
      if (parts.length == 2) {
        final r1 = _rowIndexFromRef(parts[0]);
        final c1 = _colIndexFromRef(parts[0]);
        final r2 = _rowIndexFromRef(parts[1]);
        final c2 = _colIndexFromRef(parts[1]);
        if (r1 > 0 && c1 > 0 && r2 >= r1 && c2 >= c1) {
          merges.add(_XlsxMergeRange(r1: r1, c1: c1, r2: r2, c2: c2));
        }
      }
    }

    return _XlsxSheetData(
      name: name,
      path: path,
      hidden: hidden,
      colWidths: colWidths,
      hiddenCols: hiddenCols,
      rowHeightsPt: rowHeightsPt,
      hiddenRows: hiddenRows,
      cells: cells,
      merges: merges,
    );
  }

  _XlsxSheetData _findVisibleSheet(
    _XlsxWorkbookModel wb, {
    required List<String> preferredPaths,
  }) {
    for (final p in preferredPaths) {
      final s = wb.sheetsByPath[p];
      if (s != null && !s.hidden) return s;
    }
    for (final s in wb.sheetsByPath.values) {
      if (!s.hidden) return s;
    }
    for (final p in preferredPaths) {
      final s = wb.sheetsByPath[p];
      if (s != null) return s;
    }
    return wb.sheetsByPath.values.first;
  }

  String _mergedOrCellText(_XlsxSheetData sheet, int r, int c) {
    final direct = sheet.cellAt(r, c)?.text ?? '';
    if (direct.trim().isNotEmpty) return direct;
    for (final m in sheet.merges) {
      if (r >= m.r1 && r <= m.r2 && c >= m.c1 && c <= m.c2) {
        return sheet.cellAt(m.r1, m.c1)?.text ?? '';
      }
    }
    return '';
  }

  bool _rowHasStudentIdentity(_XlsxSheetData sheet, int r) {
    final c1 = sheet.cellAt(r, 1)?.text.trim() ?? '';
    final c2 = sheet.cellAt(r, 2)?.text.trim() ?? '';
    return c1.isNotEmpty || c2.isNotEmpty;
  }

  String _normalizeCategory(String raw) {
    final u = raw.trim().toUpperCase();
    if (u.contains('SC') || u.contains('અ.જા') || u.contains('અનુ. જાતિ')) {
      return 'SC';
    }
    if (u.contains('ST') || u.contains('અ.જ.જા') || u.contains('અનુ. જ. જાતિ')) {
      return 'SC_ST_2';
    }
    if (u.contains('OBC') || u.contains('SEBC') || u.contains('બ.પં') || u.contains('બક્ષી')) {
      return 'OBC';
    }
    if (u.isEmpty) return '';
    return 'OTHER';
  }

  static int _colIndexFromRef(String ref) {
    var col = 0;
    for (var i = 0; i < ref.length; i++) {
      final code = ref.codeUnitAt(i);
      if (code >= 65 && code <= 90) {
        col = col * 26 + (code - 64);
      } else if (code >= 97 && code <= 122) {
        col = col * 26 + (code - 96);
      } else {
        break;
      }
    }
    return col;
  }

  static int _rowIndexFromRef(String ref) {
    final m = RegExp(r'(\d+)$').firstMatch(ref);
    return int.tryParse(m?.group(1) ?? '') ?? 0;
  }

  static String? _attr(String tagAttrs, String name) {
    final m = RegExp('(?:^|\\s)$name="([^"]*)"').firstMatch(tagAttrs);
    return m?.group(1);
  }

  static String? _argbToCssHex(String? argb) {
    if (argb == null || argb.isEmpty) return null;
    final clean = argb.trim().toUpperCase();
    if (clean.length == 8) {
      return '#${clean.substring(2)}';
    }
    if (clean.length == 6) {
      return '#$clean';
    }
    return null;
  }

  static String _repairMojibake(String value) {
    if (!value.contains('àª') &&
        !value.contains('à«') &&
        !value.contains('ðŸ') &&
        !value.contains('âœ')) {
      return value;
    }
    const cp1252Overrides = <int, int>{
      0x20AC: 0x80,
      0x201A: 0x82,
      0x0192: 0x83,
      0x201E: 0x84,
      0x2026: 0x85,
      0x2020: 0x86,
      0x2021: 0x87,
      0x02C6: 0x88,
      0x2030: 0x89,
      0x0160: 0x8A,
      0x2039: 0x8B,
      0x0152: 0x8C,
      0x017D: 0x8E,
      0x2018: 0x91,
      0x2019: 0x92,
      0x201C: 0x93,
      0x201D: 0x94,
      0x2022: 0x95,
      0x2013: 0x96,
      0x2014: 0x97,
      0x02DC: 0x98,
      0x2122: 0x99,
      0x0161: 0x9A,
      0x203A: 0x9B,
      0x0153: 0x9C,
      0x017E: 0x9E,
      0x0178: 0x9F,
    };
    final bytes = <int>[];
    for (final unit in value.codeUnits) {
      if (unit <= 0xFF) {
        bytes.add(unit);
      } else if (cp1252Overrides.containsKey(unit)) {
        bytes.add(cp1252Overrides[unit]!);
      } else {
        return value;
      }
    }
    try {
      final decoded = utf8.decode(bytes, allowMalformed: false);
      if (RegExp(r'[\u0A80-\u0AFF]').hasMatch(decoded)) return decoded;
    } catch (_) {}
    return value;
  }

  static String _unescapeXml(String input) {
    final unescaped = !input.contains('&')
        ? input
        : input
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&quot;', '"')
            .replaceAll('&apos;', "'")
            .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
              final code = int.tryParse(m.group(1) ?? '', radix: 16);
              return code != null ? String.fromCharCode(code) : '';
            })
            .replaceAllMapped(RegExp(r'&#([0-9]+);'), (m) {
              final code = int.tryParse(m.group(1) ?? '');
              return code != null ? String.fromCharCode(code) : '';
            })
            .replaceAll('&amp;', '&');
    return _repairMojibake(unescaped);
  }

  static String _escapeHtml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}

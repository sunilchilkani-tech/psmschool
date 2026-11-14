import 'dart:convert';
import 'dart:typed_data';

import 'xlsx_model.dart';

/// Paper size in millimetres (portrait) for an Excel paperSize code.
(double, double) paperMm(String paper) {
  switch (paper) {
    case '5':
      return (215.9, 355.6); // Legal
    case '1':
      return (215.9, 279.4); // Letter
    case '8':
      return (297, 420); // A3
    default:
      return (210, 297); // A4
  }
}

class PlacedImage {
  PlacedImage(this.bytes, this.mime, this.x, this.y, this.w, this.h);
  final Uint8List bytes;
  final String mime;
  final double x, y, w, h; // sheet pixels, relative to the page's first cell
}

/// One printed page: which rows and columns of a sheet appear on it, how big
/// they are, and how the block is placed on the paper.
class PrintPage {
  PrintPage({
    required this.sheet,
    required this.cols,
    required this.rows,
    required this.paper,
    this.landscape = false,
    this.marginLeftIn = 0.2,
    this.marginRightIn = 0.2,
    this.marginTopIn = 0.2,
    this.marginBottomIn = 0.2,
    this.hCenter = true,
  });

  final XSheet sheet;
  final List<int> cols;
  final List<int> rows;
  final String paper;
  final bool landscape;
  double marginLeftIn, marginRightIn, marginTopIn, marginBottomIn;
  bool hCenter;
  bool vCenter = false;

  final Map<int, double> colPxOverride = <int, double>{};
  final Map<int, double> rowPxOverride = <int, double>{};

  /// Columns printed as plain blank space (binding gap).
  final Set<int> blankCols = <int>{};

  /// Body font size (printed points) for non-empty cells in these rows.
  int fontFromRow = 0;
  int fontToRow = -1;
  double? fontPt;

  /// When true, [fontPt] is the size on paper (compensates for the scale).
  bool compensateFont = true;

  /// Scale from sheet pixels to paper (1 = 100%).
  double scale = 1;

  bool drawSheetImages = true;
  final List<PlacedImage> images = <PlacedImage>[];

  double colW(int c) => colPxOverride[c] ?? sheet.colPx(c);
  double rowH(int r) => rowPxOverride[r] ?? sheet.rowPt(r) * 4 / 3;

  double get contentWidthPx => cols.fold<double>(0, (s, c) => s + colW(c));
  double get contentHeightPx => rows.fold<double>(0, (s, r) => s + rowH(r));

  (double, double) get paperSizeMm {
    final (w, h) = paperMm(paper);
    return landscape ? (h, w) : (w, h);
  }

  static const double pxPerMm = 96 / 25.4;
  static const double pxPerIn = 96;

  double get availWidthPx => paperSizeMm.$1 * pxPerMm - (marginLeftIn + marginRightIn) * pxPerIn;
  double get availHeightPx => paperSizeMm.$2 * pxPerMm - (marginTopIn + marginBottomIn) * pxPerIn;

  /// Scale that makes the block fit inside the margins.
  double fitScale({bool width = true, bool height = true, double max = 1}) {
    var s = max;
    if (width && contentWidthPx > 0) s = s < availWidthPx / contentWidthPx ? s : availWidthPx / contentWidthPx;
    if (height && contentHeightPx > 0) s = s < availHeightPx / contentHeightPx ? s : availHeightPx / contentHeightPx;
    return s;
  }

  /// Plain description of the page (used by the Google Apps Script PDF
  /// service, which rebuilds the same page in Google Sheets).
  Map<String, dynamic> toPlanJson() => <String, dynamic>{
        'sheet': sheet.name,
        'cols': cols,
        'colPx': <String, double>{for (final c in cols) '$c': double.parse(colW(c).toStringAsFixed(2))},
        'rows': rows,
        'rowPx': <String, double>{for (final r in rows) '$r': double.parse(rowH(r).toStringAsFixed(2))},
        'blankCols': blankCols.toList(),
        if (fontPt != null)
          'font': <String, dynamic>{'from': fontFromRow, 'to': fontToRow, 'pt': double.parse((compensateFont ? fontPt! / scale : fontPt!).toStringAsFixed(2))},
        'paper': paper == '5' ? 'legal' : (paper == '1' ? 'letter' : 'A4'),
        'landscape': landscape,
        'margins': <String, double>{'left': marginLeftIn, 'right': marginRightIn, 'top': marginTopIn, 'bottom': marginBottomIn},
        'hCenter': hCenter,
        'vCenter': vCenter,
        'dropSheetImages': !drawSheetImages,
        'images': images
            .map((i) => <String, dynamic>{'data': base64Encode(i.bytes), 'mime': i.mime, 'x': i.x, 'y': i.y, 'w': i.w, 'h': i.h})
            .toList(),
      };
}

/// Cell edits made while preparing pages (weekday names, totals, Sunday
/// shading…), so the Apps Script copy shows the same values.
class SheetEdits {
  final Map<String, Map<String, String>> values = <String, Map<String, String>>{};
  final Map<String, Map<String, String>> fills = <String, Map<String, String>>{};
  final Map<String, List<int>> hiddenCols = <String, List<int>>{};

  static String a1(int r, int c) {
    var n = c;
    final b = StringBuffer();
    while (n > 0) {
      final m = (n - 1) % 26;
      b.write(String.fromCharCode(65 + m));
      n = (n - 1) ~/ 26;
    }
    return '${b.toString().split('').reversed.join()}$r';
  }

  void setValue(XSheet s, int r, int c, String v, {num? number}) {
    s.setText(r, c, v, number: number);
    (values[s.name] ??= <String, String>{})[a1(r, c)] = v;
  }

  void setFill(XSheet s, int r, int c, String? color) {
    s.setFill(r, c, color);
    (fills[s.name] ??= <String, String>{})[a1(r, c)] = color ?? 'none';
  }

  /// Same colour for a column block (kept compact in the JSON plan).
  final List<Map<String, String>> rangeFills = <Map<String, String>>[];

  void fillColumn(XSheet s, int c, int r1, int r2, String? color) {
    for (var r = r1; r <= r2; r++) {
      s.setFill(r, c, color);
    }
    rangeFills.add(<String, String>{'sheet': s.name, 'range': '${a1(r1, c)}:${a1(r2, c)}', 'color': color ?? 'none'});
  }

  Map<String, dynamic> toJson() => <String, dynamic>{'values': values, 'fills': fills, 'rangeFills': rangeFills};
}

class PrintJob {
  PrintJob({required this.title, required this.pages, required this.edits, required this.workbookBytes});
  final String title;
  final List<PrintPage> pages;
  final SheetEdits edits;
  final Uint8List workbookBytes;

  Map<String, dynamic> toPlanJson() => <String, dynamic>{
        'title': title,
        'edits': edits.toJson(),
        'pages': pages.map((p) => p.toPlanJson()).toList(),
      };
}

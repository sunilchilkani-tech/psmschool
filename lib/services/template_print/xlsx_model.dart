import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// A light, read-only model of an .xlsx workbook: just what is needed to
/// print a sheet exactly like the spreadsheet (values, fonts, fills, borders,
/// alignment, merges, column widths, row heights and pictures).
class XFont {
  XFont({this.name = 'Calibri', this.size = 11, this.bold = false, this.italic = false, this.underline = false, this.color});
  String name;
  double size;
  bool bold;
  bool italic;
  bool underline;
  String? color; // #RRGGBB
}

class XBorder {
  const XBorder(this.style, this.color);
  final String style;
  final String color;

  /// Strength used when two neighbouring cells describe the same edge.
  int get weight => const <String, int>{
        'hair': 1,
        'dotted': 2,
        'dashDotDot': 3,
        'dashDot': 4,
        'dashed': 5,
        'thin': 6,
        'mediumDashDotDot': 7,
        'slantDashDot': 8,
        'mediumDashDot': 9,
        'mediumDashed': 10,
        'medium': 11,
        'double': 12,
        'thick': 13,
      }[style] ??
      0;
}

class XStyle {
  XStyle();
  XFont font = XFont();
  String? fill;
  XBorder? left, right, top, bottom;
  String horizontal = 'general';
  String vertical = 'bottom';
  bool wrap = false;
  int rotation = 0;
  int indent = 0;
  String numFmt = 'General';
}

class XCell {
  XCell(this.text, {this.number, this.style = 0});
  String text;
  num? number;
  int style;

  /// Print-time overrides (do not change the template style itself).
  String? fillOverride; // '#RRGGBB' or 'none'
  bool get isEmpty => text.isEmpty;
}

class XMerge {
  const XMerge(this.r1, this.c1, this.r2, this.c2);
  final int r1, c1, r2, c2;
  bool contains(int r, int c) => r >= r1 && r <= r2 && c >= c1 && c <= c2;
}

class XImage {
  XImage({required this.bytes, required this.mime, required this.col, required this.colOffPx, required this.row, required this.rowOffPx, required this.widthPx, required this.heightPx});
  final Uint8List bytes;
  final String mime;
  final int col, row; // 1-based
  final double colOffPx, rowOffPx, widthPx, heightPx;
}

class XSheet {
  XSheet(this.name);
  final String name;
  bool visible = true;
  double defaultColWidth = 8.43;
  double defaultRowHeight = 15;
  final Map<int, double> colWidths = <int, double>{};
  final Set<int> hiddenCols = <int>{};
  final Map<int, double> rowHeights = <int, double>{};
  final Set<int> hiddenRows = <int>{};
  final Map<int, Map<int, XCell>> rows = <int, Map<int, XCell>>{};
  final List<XMerge> merges = <XMerge>[];
  final List<XImage> images = <XImage>[];
  int maxRow = 0;
  int maxCol = 0;
  String paper = '9';
  bool landscape = false;
  double marginLeft = 0.7, marginRight = 0.7, marginTop = 0.75, marginBottom = 0.75; // inches
  bool hCenter = false;
  int? areaR1, areaC1, areaR2, areaC2;

  List<XStyle> styleTable = <XStyle>[XStyle()];
  XStyle styles(int i) => i >= 0 && i < styleTable.length ? styleTable[i] : styleTable.first;

  XCell? cell(int r, int c) => rows[r]?[c];
  String text(int r, int c) => rows[r]?[c]?.text ?? '';

  void setText(int r, int c, String value, {num? number}) {
    final row = rows.putIfAbsent(r, () => <int, XCell>{});
    final existing = row[c];
    if (existing == null) {
      row[c] = XCell(value, number: number);
    } else {
      existing
        ..text = value
        ..number = number;
    }
  }

  void setFill(int r, int c, String? color) {
    final row = rows.putIfAbsent(r, () => <int, XCell>{});
    (row[c] ??= XCell('')).fillOverride = color;
  }

  double colWidthChars(int c) => colWidths[c] ?? defaultColWidth;

  /// Excel column width (characters of the default font) to screen pixels.
  double colPx(int c) => colWidthCharsToPx(colWidthChars(c));

  double rowPt(int r) => rowHeights[r] ?? defaultRowHeight;
}

double colWidthCharsToPx(double w) => w <= 0 ? 0 : (w * 7 + 0.5).truncateToDouble() + 5;

class XWorkbook {
  XWorkbook._();
  final Map<String, XSheet> _sheets = <String, XSheet>{};
  final List<String> sheetNames = <String>[];
  final List<XStyle> styles = <XStyle>[];
  final Map<String, String> _sheetPaths = <String, String>{};
  late final Archive _archive;
  final Map<String, String> _files = <String, String>{};
  List<String> _shared = const <String>[];
  List<String> _theme = const <String>[];

  /// All pictures in the workbook (largest first) — used to find the school logo.
  List<Uint8List> get mediaImages {
    final list = _archive.files
        .where((f) => f.isFile && f.name.startsWith('xl/media/'))
        .map((f) => Uint8List.fromList(f.content as List<int>))
        .where((b) => b.length > 300)
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return list;
  }

  static XWorkbook parse(Uint8List bytes) {
    final wb = XWorkbook._();
    wb._archive = ZipDecoder().decodeBytes(bytes);
    wb._load();
    return wb;
  }

  String? _read(String name) {
    if (_files.containsKey(name)) return _files[name];
    final f = _archive.findFile(name);
    if (f == null) return null;
    final s = utf8.decode(f.content as List<int>, allowMalformed: true);
    _files[name] = s;
    return s;
  }

  Uint8List? _readBytes(String name) {
    final f = _archive.findFile(name);
    return f == null ? null : Uint8List.fromList(f.content as List<int>);
  }

  static String _resolve(String base, String target) {
    if (target.startsWith('/')) return target.substring(1);
    final parts = base.split('/')..removeLast();
    for (final p in target.split('/')) {
      if (p == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else if (p != '.') {
        parts.add(p);
      }
    }
    return parts.join('/');
  }

  Map<String, String> _rels(String part) {
    final dir = part.contains('/') ? part.substring(0, part.lastIndexOf('/')) : '';
    final file = part.substring(part.lastIndexOf('/') + 1);
    final xml = _read('$dir/_rels/$file.rels');
    final out = <String, String>{};
    if (xml == null) return out;
    for (final e in XmlDocument.parse(xml).findAllElements('Relationship')) {
      out[e.getAttribute('Id') ?? ''] = _resolve(part, e.getAttribute('Target') ?? '');
    }
    return out;
  }

  void _load() {
    final ssXml = _read('xl/sharedStrings.xml');
    if (ssXml != null) {
      _shared = XmlDocument.parse(ssXml)
          .findAllElements('si')
          .map((si) => si.findAllElements('t').where((t) => t.parentElement?.name.local != 'rPh').map((t) => t.innerText).join())
          .toList();
    }
    _loadTheme();
    _loadStyles();
    final wbXml = XmlDocument.parse(_read('xl/workbook.xml') ?? '<workbook/>');
    final rels = _rels('xl/workbook.xml');
    final areas = <int, String>{};
    for (final dn in wbXml.findAllElements('definedName')) {
      if (dn.getAttribute('name') == '_xlnm.Print_Area') {
        final id = int.tryParse(dn.getAttribute('localSheetId') ?? '');
        if (id != null) areas[id] = dn.innerText;
      }
    }
    var index = 0;
    for (final s in wbXml.findAllElements('sheet')) {
      final name = s.getAttribute('name') ?? 'Sheet${index + 1}';
      final rid = s.getAttribute('r:id') ?? s.attributes.firstWhere((a) => a.name.local == 'id', orElse: () => XmlAttribute(XmlName('id'), '')).value;
      final path = rels[rid];
      if (path != null) {
        sheetNames.add(name);
        _sheetPaths[name] = path;
        final st = s.getAttribute('state');
        final area = areas[index];
        _pendingMeta[name] = _SheetMeta(st == null || st == 'visible', area);
      }
      index++;
    }
  }

  final Map<String, _SheetMeta> _pendingMeta = <String, _SheetMeta>{};

  bool isVisible(String name) => _pendingMeta[name]?.visible ?? false;

  XSheet? sheet(String name) {
    if (_sheets.containsKey(name)) return _sheets[name];
    final path = _sheetPaths[name];
    if (path == null) return null;
    final sheet = _parseSheet(name, path);
    final meta = _pendingMeta[name];
    if (meta != null) {
      sheet.visible = meta.visible;
      final area = meta.area;
      if (area != null) {
        final ref = area.contains('!') ? area.substring(area.lastIndexOf('!') + 1) : area;
        final m = RegExp(r'\$?([A-Z]+)\$?(\d+):\$?([A-Z]+)\$?(\d+)').firstMatch(ref.split(',').first);
        if (m != null) {
          sheet
            ..areaC1 = colIndex(m.group(1)!)
            ..areaR1 = int.parse(m.group(2)!)
            ..areaC2 = colIndex(m.group(3)!)
            ..areaR2 = int.parse(m.group(4)!);
        }
      }
    }
    _sheets[name] = sheet;
    return sheet;
  }

  static int colIndex(String letters) {
    var n = 0;
    for (final ch in letters.codeUnits) {
      n = n * 26 + (ch - 64);
    }
    return n;
  }

  static (int, int) cellRef(String ref) {
    final m = RegExp(r'([A-Z]+)(\d+)').firstMatch(ref)!;
    return (int.parse(m.group(2)!), colIndex(m.group(1)!));
  }

  // ---------------------------------------------------------------- theme
  void _loadTheme() {
    final xml = _read('xl/theme/theme1.xml');
    if (xml == null) return;
    final doc = XmlDocument.parse(xml);
    final scheme = doc.findAllElements('clrScheme', namespace: '*').firstOrNull;
    if (scheme == null) return;
    final colors = <String>[];
    for (final child in scheme.childElements) {
      final sys = child.findElements('sysClr', namespace: '*').firstOrNull;
      final srgb = child.findElements('srgbClr', namespace: '*').firstOrNull;
      colors.add('#${(srgb?.getAttribute('val') ?? sys?.getAttribute('lastClr') ?? '000000').toUpperCase()}');
    }
    if (colors.length >= 4) {
      // Spreadsheet theme indexes swap light/dark: 0=lt1, 1=dk1, 2=lt2, 3=dk2.
      _theme = <String>[colors[1], colors[0], colors[3], colors[2], ...colors.skip(4)];
    }
  }

  String? _color(XmlElement? e) {
    if (e == null) return null;
    String? base;
    final rgb = e.getAttribute('rgb');
    if (rgb != null && rgb.length >= 6) {
      base = '#${rgb.substring(rgb.length - 6).toUpperCase()}';
    } else if (e.getAttribute('theme') != null) {
      final t = int.tryParse(e.getAttribute('theme')!) ?? 1;
      base = t < _theme.length ? _theme[t] : (t == 0 ? '#FFFFFF' : '#000000');
    } else if (e.getAttribute('indexed') != null) {
      final i = int.tryParse(e.getAttribute('indexed')!) ?? 64;
      base = i < _indexed.length ? _indexed[i] : null;
    } else if (e.getAttribute('auto') == '1') {
      base = '#000000';
    }
    final tint = double.tryParse(e.getAttribute('tint') ?? '');
    if (base != null && tint != null && tint != 0) base = _applyTint(base, tint);
    return base;
  }

  static String _applyTint(String hex, double tint) {
    final v = int.parse(hex.substring(1), radix: 16);
    var r = ((v >> 16) & 255) / 255, g = ((v >> 8) & 255) / 255, b = (v & 255) / 255;
    final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
    var h = 0.0, s = 0.0;
    var l = (mx + mn) / 2;
    if (mx != mn) {
      final d = mx - mn;
      s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
      if (mx == r) {
        h = (g - b) / d + (g < b ? 6 : 0);
      } else if (mx == g) {
        h = (b - r) / d + 2;
      } else {
        h = (r - g) / d + 4;
      }
      h /= 6;
    }
    l = tint < 0 ? l * (1 + tint) : l * (1 - tint) + tint;
    double hue(double p, double q, double t) {
      if (t < 0) t += 1;
      if (t > 1) t -= 1;
      if (t < 1 / 6) return p + (q - p) * 6 * t;
      if (t < 1 / 2) return q;
      if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
      return p;
    }

    if (s == 0) {
      r = g = b = l;
    } else {
      final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
      final p = 2 * l - q;
      r = hue(p, q, h + 1 / 3);
      g = hue(p, q, h);
      b = hue(p, q, h - 1 / 3);
    }
    String two(double x) => (x * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${two(r)}${two(g)}${two(b)}'.toUpperCase();
  }

  // ---------------------------------------------------------------- styles
  void _loadStyles() {
    final xml = _read('xl/styles.xml');
    if (xml == null) {
      styles.add(XStyle());
      return;
    }
    final doc = XmlDocument.parse(xml);
    final numFmts = <int, String>{
      0: 'General', 1: '0', 2: '0.00', 3: '#,##0', 4: '#,##0.00', 9: '0%', 10: '0.00%',
      14: 'dd/mm/yyyy', 15: 'd-mmm-yy', 16: 'd-mmm', 17: 'mmm-yy', 22: 'dd/mm/yyyy hh:mm', 49: '@',
    };
    for (final f in doc.findAllElements('numFmt')) {
      numFmts[int.tryParse(f.getAttribute('numFmtId') ?? '') ?? -1] = f.getAttribute('formatCode') ?? 'General';
    }
    final fonts = <XFont>[];
    for (final f in doc.findAllElements('fonts').firstOrNull?.findElements('font') ?? const <XmlElement>[]) {
      XmlElement? el(String n) => f.findElements(n).firstOrNull;
      fonts.add(XFont(
        name: el('name')?.getAttribute('val') ?? 'Calibri',
        size: double.tryParse(el('sz')?.getAttribute('val') ?? '') ?? 11,
        bold: el('b') != null && el('b')!.getAttribute('val') != '0' && el('b')!.getAttribute('val') != 'false',
        italic: el('i') != null && el('i')!.getAttribute('val') != '0' && el('i')!.getAttribute('val') != 'false',
        underline: el('u') != null && el('u')!.getAttribute('val') != 'none',
        color: _color(el('color')),
      ));
    }
    final fills = <String?>[];
    for (final f in doc.findAllElements('fills').firstOrNull?.findElements('fill') ?? const <XmlElement>[]) {
      final p = f.findElements('patternFill').firstOrNull;
      if (p == null || (p.getAttribute('patternType') ?? 'none') == 'none') {
        fills.add(null);
      } else if (p.getAttribute('patternType') == 'solid') {
        fills.add(_color(p.findElements('fgColor').firstOrNull) ?? _color(p.findElements('bgColor').firstOrNull));
      } else {
        fills.add(null);
      }
    }
    final borders = <List<XBorder?>>[];
    for (final b in doc.findAllElements('borders').firstOrNull?.findElements('border') ?? const <XmlElement>[]) {
      XBorder? side(String n) {
        final e = b.findElements(n).firstOrNull;
        final st = e?.getAttribute('style');
        if (e == null || st == null || st == 'none') return null;
        return XBorder(st, _color(e.findElements('color').firstOrNull) ?? '#000000');
      }

      borders.add(<XBorder?>[side('left'), side('right'), side('top'), side('bottom')]);
    }
    for (final xf in doc.findAllElements('cellXfs').firstOrNull?.findElements('xf') ?? const <XmlElement>[]) {
      final s = XStyle();
      final fi = int.tryParse(xf.getAttribute('fontId') ?? '0') ?? 0;
      final src = fi < fonts.length ? fonts[fi] : XFont();
      s.font = XFont(name: src.name, size: src.size, bold: src.bold, italic: src.italic, underline: src.underline, color: src.color);
      final fl = int.tryParse(xf.getAttribute('fillId') ?? '0') ?? 0;
      s.fill = fl < fills.length ? fills[fl] : null;
      final bi = int.tryParse(xf.getAttribute('borderId') ?? '0') ?? 0;
      if (bi < borders.length) {
        s
          ..left = borders[bi][0]
          ..right = borders[bi][1]
          ..top = borders[bi][2]
          ..bottom = borders[bi][3];
      }
      s.numFmt = numFmts[int.tryParse(xf.getAttribute('numFmtId') ?? '0') ?? 0] ?? 'General';
      final al = xf.findElements('alignment').firstOrNull;
      if (al != null) {
        s
          ..horizontal = al.getAttribute('horizontal') ?? 'general'
          ..vertical = al.getAttribute('vertical') ?? 'bottom'
          ..wrap = al.getAttribute('wrapText') == '1' || al.getAttribute('wrapText') == 'true'
          ..rotation = int.tryParse(al.getAttribute('textRotation') ?? '0') ?? 0
          ..indent = int.tryParse(al.getAttribute('indent') ?? '0') ?? 0;
      }
      styles.add(s);
    }
    if (styles.isEmpty) styles.add(XStyle());
  }

  // ---------------------------------------------------------------- sheet
  // Large sheets (Hajari Patrak has ~2,500 rows x 50 columns) are read with a
  // light scanner instead of a full XML tree: several times faster in the
  // browser and far less memory.
  static final RegExp _attrRe = RegExp(r'([\w:]+)="([^"]*)"');
  static Map<String, String> _attrs(String tag) {
    final out = <String, String>{};
    for (final m in _attrRe.allMatches(tag)) {
      final k = m.group(1)!;
      out[k.contains(':') ? k.substring(k.indexOf(':') + 1) : k] = m.group(2)!;
    }
    return out;
  }

  static String _unescape(String s) {
    if (!s.contains('&')) return s;
    return s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);'), (m) {
      final v = m.group(1)!;
      switch (v) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
      }
      final code = v.startsWith('#x') ? int.tryParse(v.substring(2), radix: 16) : int.tryParse(v.substring(1));
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });
  }

  static bool _isTrue(String? v) => v == '1' || v == 'true';

  XSheet _parseSheet(String name, String path) {
    final sheet = XSheet(name)..styleTable = styles;
    final xml = _read(path) ?? '';
    String? firstTag(String tag) => RegExp('<$tag\\b[^>]*>').firstMatch(xml)?.group(0);

    final fmt = firstTag('sheetFormatPr');
    if (fmt != null) {
      final a = _attrs(fmt);
      sheet.defaultRowHeight = double.tryParse(a['defaultRowHeight'] ?? '') ?? 15;
      final dcw = double.tryParse(a['defaultColWidth'] ?? '');
      final base = double.tryParse(a['baseColWidth'] ?? '');
      if (dcw != null) {
        sheet.defaultColWidth = dcw;
      } else if (base != null) {
        sheet.defaultColWidth = base + 0.71;
      }
    }
    for (final m in RegExp(r'<col\b[^>]*/?>').allMatches(xml)) {
      final a = _attrs(m.group(0)!);
      final mn = int.tryParse(a['min'] ?? '') ?? 1;
      final mx = math.min(int.tryParse(a['max'] ?? '') ?? mn, mn + 400);
      final w = double.tryParse(a['width'] ?? '');
      final hidden = _isTrue(a['hidden']);
      for (var i = mn; i <= mx; i++) {
        if (w != null) sheet.colWidths[i] = w;
        if (hidden) sheet.hiddenCols.add(i);
      }
    }

    final dataStart = xml.indexOf('<sheetData');
    final dataEnd = xml.indexOf('</sheetData>');
    if (dataStart >= 0 && dataEnd > dataStart) {
      final data = xml.substring(dataStart, dataEnd);
      final rowRe = RegExp(r'<row\b([^>]*?)(/>|>([\s\S]*?)</row>)');
      final cellRe = RegExp(r'<c\b([^>]*?)(/>|>([\s\S]*?)</c>)');
      final vRe = RegExp(r'<v>([\s\S]*?)</v>');
      final tRe = RegExp(r'<t(?:\s[^>]*)?>([\s\S]*?)</t>');
      var rowNo = 0;
      for (final rm in rowRe.allMatches(data)) {
        final ra = _attrs(rm.group(1)!);
        rowNo = int.tryParse(ra['r'] ?? '') ?? rowNo + 1;
        final ht = double.tryParse(ra['ht'] ?? '');
        if (ht != null) sheet.rowHeights[rowNo] = ht;
        if (_isTrue(ra['hidden'])) sheet.hiddenRows.add(rowNo);
        final rowStyle = ra['customFormat'] == '1' ? int.tryParse(ra['s'] ?? '') : null;
        final body = rm.group(3);
        if (rowNo > sheet.maxRow) sheet.maxRow = rowNo;
        if (body == null || body.isEmpty) continue;
        final cells = <int, XCell>{};
        var colNo = 0;
        for (final cm in cellRe.allMatches(body)) {
          final ca = _attrs(cm.group(1)!);
          final ref = ca['r'];
          colNo = ref != null ? cellRef(ref).$2 : colNo + 1;
          final style = int.tryParse(ca['s'] ?? '') ?? rowStyle ?? 0;
          final t = ca['t'];
          final inner = cm.group(3) ?? '';
          final v = inner.isEmpty ? null : vRe.firstMatch(inner)?.group(1);
          String text = '';
          num? number;
          if (t == 's') {
            final i = int.tryParse(v ?? '') ?? -1;
            text = i >= 0 && i < _shared.length ? _shared[i] : '';
          } else if (t == 'inlineStr') {
            text = _unescape(tRe.allMatches(inner).map((m) => m.group(1)!).join());
          } else if (t == 'str' || t == 'e') {
            text = _unescape(v ?? '');
          } else if (t == 'b') {
            text = v == '1' ? 'TRUE' : 'FALSE';
          } else if (v != null && v.isNotEmpty) {
            number = num.tryParse(v);
            text = number == null ? _unescape(v) : formatNumber(number, style < styles.length ? styles[style].numFmt : 'General');
          }
          cells[colNo] = XCell(text, number: number, style: style);
          if (colNo > sheet.maxCol && (text.isNotEmpty || style != 0)) sheet.maxCol = colNo;
        }
        if (cells.isNotEmpty) sheet.rows[rowNo] = cells;
      }
    }
    for (final m in RegExp(r'<mergeCell\b[^>]*ref="([A-Z]+\d+):([A-Z]+\d+)"').allMatches(xml)) {
      final a = cellRef(m.group(1)!), b = cellRef(m.group(2)!);
      sheet.merges.add(XMerge(a.$1, a.$2, b.$1, b.$2));
    }
    final ps = firstTag('pageSetup');
    if (ps != null) {
      final a = _attrs(ps);
      sheet.paper = a['paperSize'] ?? '9';
      sheet.landscape = a['orientation'] == 'landscape';
    }
    final pm = firstTag('pageMargins');
    if (pm != null) {
      final a = _attrs(pm);
      sheet
        ..marginLeft = double.tryParse(a['left'] ?? '') ?? 0.7
        ..marginRight = double.tryParse(a['right'] ?? '') ?? 0.7
        ..marginTop = double.tryParse(a['top'] ?? '') ?? 0.75
        ..marginBottom = double.tryParse(a['bottom'] ?? '') ?? 0.75;
    }
    final po = firstTag('printOptions');
    sheet.hCenter = po != null && _isTrue(_attrs(po)['horizontalCentered']);
    final drawing = firstTag('drawing');
    if (drawing != null) _loadImages(sheet, path, _attrs(drawing)['id'] ?? '');
    return sheet;
  }

  void _loadImages(XSheet sheet, String path, String rid) {
    final dPath = _rels(path)[rid];
    if (dPath == null) return;
    final dXml = _read(dPath);
    if (dXml == null) return;
    final dRels = _rels(dPath);
    const emuPerPx = 9525.0;
    for (final anchor in XmlDocument.parse(dXml).rootElement.childElements) {
      final from = anchor.findElements('from', namespace: '*').firstOrNull;
      final pic = anchor.findAllElements('pic', namespace: '*').firstOrNull;
      if (from == null || pic == null) continue;
      int n(XmlElement e, String tag) => int.tryParse(e.findElements(tag, namespace: '*').firstOrNull?.innerText ?? '') ?? 0;
      final blip = pic.findAllElements('blip', namespace: '*').firstOrNull;
      final embed = blip?.attributes.firstWhere((a) => a.name.local == 'embed', orElse: () => XmlAttribute(XmlName('embed'), '')).value;
      final media = dRels[embed];
      if (media == null) continue;
      final bytes = _readBytes(media);
      if (bytes == null) continue;
      final col = n(from, 'col') + 1, row = n(from, 'row') + 1;
      final colOff = n(from, 'colOff') / emuPerPx, rowOff = n(from, 'rowOff') / emuPerPx;
      var w = 0.0, h = 0.0;
      final ext = anchor.findElements('ext', namespace: '*').firstOrNull ?? pic.findAllElements('ext', namespace: '*').firstOrNull;
      if (ext != null) {
        w = (int.tryParse(ext.getAttribute('cx') ?? '') ?? 0) / emuPerPx;
        h = (int.tryParse(ext.getAttribute('cy') ?? '') ?? 0) / emuPerPx;
      }
      final to = anchor.findElements('to', namespace: '*').firstOrNull;
      if (to != null && (w == 0 || anchor.name.local == 'twoCellAnchor')) {
        var x = 0.0;
        for (var c = col; c < n(to, 'col') + 1; c++) {
          x += sheet.colPx(c);
        }
        w = x - colOff + n(to, 'colOff') / emuPerPx;
        var y = 0.0;
        for (var r = row; r < n(to, 'row') + 1; r++) {
          y += sheet.rowPt(r) * 4 / 3;
        }
        h = y - rowOff + n(to, 'rowOff') / emuPerPx;
      }
      final lower = media.toLowerCase();
      final mime = lower.endsWith('.jpg') || lower.endsWith('.jpeg') ? 'image/jpeg' : (lower.endsWith('.gif') ? 'image/gif' : 'image/png');
      sheet.images.add(XImage(bytes: bytes, mime: mime, col: col, colOffPx: colOff, row: row, rowOffPx: rowOff, widthPx: w, heightPx: h));
    }
  }
}

class _SheetMeta {
  const _SheetMeta(this.visible, this.area);
  final bool visible;
  final String? area;
}

/// Formats a number the way the spreadsheet would show it for the common
/// formats used by the templates.
String formatNumber(num value, String format) {
  var f = format.split(';').first.replaceAll(RegExp(r'\[[^\]]*\]'), '').replaceAll('"', '').trim();
  if (f.isEmpty || f.toLowerCase() == 'general' || f == '@') {
    if (value == value.roundToDouble() && value.abs() < 1e15) return value.toInt().toString();
    var s = value.toStringAsPrecision(10);
    if (s.contains('.') && !s.contains('e')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return s;
  }
  final lower = f.toLowerCase();
  if (RegExp(r'[dy]').hasMatch(lower) || (lower.contains('m') && !lower.contains('0'))) {
    final date = DateTime.utc(1899, 12, 30).add(Duration(milliseconds: (value * 86400000).round()));
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}';
  }
  final percent = f.contains('%');
  final v = percent ? value * 100 : value;
  final dot = f.indexOf('.');
  var decimals = 0;
  if (dot >= 0) {
    for (var i = dot + 1; i < f.length && (f[i] == '0' || f[i] == '#'); i++) {
      decimals++;
    }
  }
  var s = v.toStringAsFixed(decimals);
  if (f.contains(',')) {
    final parts = s.split('.');
    final neg = parts[0].startsWith('-');
    var intPart = neg ? parts[0].substring(1) : parts[0];
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    intPart = buf.toString();
    s = '${neg ? '-' : ''}$intPart${parts.length > 1 ? '.${parts[1]}' : ''}';
  }
  return percent ? '$s%' : s;
}

const List<String> _indexed = <String>[
  '#000000', '#FFFFFF', '#FF0000', '#00FF00', '#0000FF', '#FFFF00', '#FF00FF', '#00FFFF',
  '#000000', '#FFFFFF', '#FF0000', '#00FF00', '#0000FF', '#FFFF00', '#FF00FF', '#00FFFF',
  '#800000', '#008000', '#000080', '#808000', '#800080', '#008080', '#C0C0C0', '#808080',
  '#9999FF', '#993366', '#FFFFCC', '#CCFFFF', '#660066', '#FF8080', '#0066CC', '#CCCCFF',
  '#000080', '#FF00FF', '#FFFF00', '#00FFFF', '#800080', '#800000', '#008080', '#0000FF',
  '#00CCFF', '#CCFFFF', '#CCFFCC', '#FFFF99', '#99CCFF', '#FF99CC', '#CC99FF', '#FFCC99',
  '#3366FF', '#33CCCC', '#99CC00', '#FFCC00', '#FF9900', '#FF6600', '#666699', '#969696',
  '#003366', '#339966', '#003300', '#333300', '#993300', '#993366', '#333399', '#333333',
  '#000000', '#FFFFFF',
];

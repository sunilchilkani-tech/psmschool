import 'dart:math' as math;

/// Kind of printed page, used to place the binding space.
enum RojmelPageKind { cashbookCredit, cashbookDebit, report, blank }

/// Margins (mm) of one printed page and the edge that carries the binding.
class RojmelPageBox {
  const RojmelPageBox({
    required this.top,
    required this.right,
    required this.bottom,
    required this.left,
    required this.edge,
  });

  final double top;
  final double right;
  final double bottom;
  final double left;

  /// 'left' | 'right' | 'top' | 'bottom' | 'none'
  final String edge;

  static String _f(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);

  /// CSS `padding` value (top right bottom left).
  String get css => '${_f(top)}mm ${_f(right)}mm ${_f(bottom)}mm ${_f(left)}mm';
}

/// Print page setup shared by the Rojmel cashbook and every audit report:
/// cashbook orientation, how much binding space is left and on which edge,
/// page by page, so single- and double-sided prints both bind cleanly.
class RojmelPrintSetup {
  RojmelPrintSetup();

  /// Binding layouts: key, Gujarati label, explanation.
  static const List<(String, String, String)> modes = <(String, String, String)>[
    (
      'register',
      'રોજમેળ રજીસ્ટર (હાલની રીત)',
      'આવક પાને જમણી બાજુ, જાવક પાને ડાબી બાજુ બાઈન્ડિંગ જગ્યા — ખુલ્લા રજીસ્ટર જેવું. પત્રકોમાં ડાબે/જમણે સેટ કરેલી જગ્યા જ રહે છે.',
    ),
    (
      'left',
      'એક બાજુ પ્રિન્ટ — ડાબી બાજુ ફાઈલ',
      'દરેક પાને ડાબી બાજુ બાઈન્ડિંગ જગ્યા. લેન્ડસ્કેપ પાનું ફાઈલમાં ફેરવીને બંધાય છે એટલે તેમાં જગ્યા ઉપર આવે છે.',
    ),
    (
      'duplex_left',
      'બંને બાજુ પ્રિન્ટ — ડાબી બાજુ ફાઈલ',
      'એકી પાને (આગળ) ડાબી બાજુ, બેકી પાને (પાછળ) જમણી બાજુ જગ્યા. લેન્ડસ્કેપ પાને એકી પાને ઉપર, બેકી પાને નીચે.',
    ),
    (
      'top',
      'એક બાજુ પ્રિન્ટ — ઉપર બાઈન્ડિંગ',
      'દરેક પાને ઉપરની બાજુ બાઈન્ડિંગ જગ્યા (પોર્ટ્રેટ અને લેન્ડસ્કેપ બંને).',
    ),
    (
      'duplex_top',
      'બંને બાજુ પ્રિન્ટ — ઉપર/નીચે બાઈન્ડિંગ',
      'એકી પાને ઉપર, બેકી પાને નીચે જગ્યા — ટૂંકી બાજુએ ફેરવીને (flip on short edge) છાપો ત્યારે બધી જગ્યા એક જ કિનારે આવે છે.',
    ),
    (
      'none',
      'બાઈન્ડિંગ જગ્યા નહીં',
      'બધી બાજુ સામાન્ય હાંસિયો; કોઈ વધારાની જગ્યા નહીં.',
    ),
  ];

  static const List<String> edges = <String>['left', 'right', 'top', 'bottom', 'none'];

  static String edgeLabel(String e) => switch (e) {
        'left' => 'ડાબે',
        'right' => 'જમણે',
        'top' => 'ઉપર',
        'bottom' => 'નીચે',
        _ => 'નહીં',
      };

  /// 'portrait' | 'landscape' for the cashbook pages.
  String cashbookOrientation = 'portrait';

  /// One of [modes].
  String mode = 'register';

  /// Total margin on the binding edge (mm).
  double bindingMm = 24;

  /// In a file bound at the side, landscape pages are turned and bound by
  /// their top (front) / bottom (back) edge.
  bool rotateLandscape = true;

  /// The printer turns landscape pages the other way (swap top / bottom).
  bool flipLandscape = false;

  /// Double-sided: add blank pages so the cashbook's આવક page faces its જાવક
  /// page in the open file and every report starts on the front of a sheet.
  bool duplexAlign = false;

  /// Page-wise binding edge by PDF page number (1-based, physical order).
  Map<int, String> pageEdges = <int, String>{};

  bool get isDuplex => mode == 'duplex_left' || mode == 'duplex_top';
  bool get isLandscapeCashbook => cashbookOrientation == 'landscape';

  // ---------------------------------------------------------------------------
  // PAGE PLACEMENT
  // ---------------------------------------------------------------------------

  /// Binding edge of PDF page [page] by the mode alone (no page-wise rule).
  String autoEdge(int page, {required RojmelPageKind kind, required bool landscape}) {
    if (kind == RojmelPageKind.blank) return 'none';
    final odd = page.isOdd;
    switch (mode) {
      case 'register':
        if (kind == RojmelPageKind.cashbookCredit) return 'right';
        if (kind == RojmelPageKind.cashbookDebit) return 'left';
        return 'none';
      case 'left':
        return landscape && rotateLandscape ? _turned('left') : 'left';
      case 'duplex_left':
        final e = odd ? 'left' : 'right';
        return landscape && rotateLandscape ? _turned(e) : e;
      case 'top':
        return 'top';
      case 'duplex_top':
        return odd ? 'top' : 'bottom';
      default:
        return 'none';
    }
  }

  /// A side edge of the file as seen on a landscape page turned into it.
  String _turned(String e) {
    final t = e == 'left' ? 'top' : 'bottom';
    if (!flipLandscape) return t;
    return t == 'top' ? 'bottom' : 'top';
  }

  /// Binding edge of PDF page [page] (page-wise rule first).
  String edgeFor(int page, {required RojmelPageKind kind, required bool landscape}) {
    if (kind == RojmelPageKind.blank) return 'none';
    return pageEdges[page] ?? autoEdge(page, kind: kind, landscape: landscape);
  }

  /// Margins of PDF page [page]. [reportLeft] / [reportRight] are the
  /// report side spaces set in the report page setup.
  RojmelPageBox boxFor(
    int page, {
    required RojmelPageKind kind,
    required bool landscape,
    double reportLeft = 8,
    double reportRight = 8,
  }) {
    if (kind == RojmelPageKind.blank) {
      return const RojmelPageBox(top: 0, right: 0, bottom: 0, left: 0, edge: 'none');
    }
    final cash = kind != RojmelPageKind.report;
    var top = cash ? 3.0 : 4.0;
    var bottom = cash ? 2.8 : 3.0;
    var left = cash ? 9.0 : reportLeft;
    var right = cash ? 9.0 : reportRight;
    final edge = edgeFor(page, kind: kind, landscape: landscape);
    final b = bindingMm.clamp(0.0, 45.0);
    switch (edge) {
      case 'left':
        left = math.max(left, b);
      case 'right':
        right = math.max(right, b);
      case 'top':
        top = math.max(top, b);
      case 'bottom':
        bottom = math.max(bottom, b);
    }
    return RojmelPageBox(top: top, right: right, bottom: bottom, left: left, edge: edge);
  }

  /// Height (mm) that top / bottom binding can take from a page of this kind
  /// (worst case over all pages, used when rows are split into pages).
  double extraVerticalMm({required bool cashbook, required bool landscape}) {
    final vertical = switch (mode) {
          'top' || 'duplex_top' => true,
          'left' || 'duplex_left' => landscape && rotateLandscape,
          _ => false,
        } ||
        pageEdges.values.any((e) => e == 'top' || e == 'bottom');
    if (!vertical) return 0;
    return math.max(0.0, bindingMm.clamp(0.0, 45.0) - (cashbook ? 2.8 : 3.0));
  }

  /// True when a blank page must be printed before a section that would
  /// start on PDF page [page] (double-sided alignment).
  bool needsBlankBefore(int page, {required RojmelPageKind kind}) {
    if (!duplexAlign || !isDuplex) return false;
    if (kind == RojmelPageKind.cashbookCredit && mode == 'duplex_left') {
      // Open file: આવક page on the left (back of a sheet = even page),
      // જાવક page on the right (front of the next sheet).
      return page.isOdd;
    }
    return page.isEven; // start on the front of a sheet
  }

  /// Blank pages printed before a cashbook printed on its own.
  int get cashbookLeadBlank => needsBlankBefore(1, kind: RojmelPageKind.cashbookCredit) ? 1 : 0;

  // ---------------------------------------------------------------------------
  // PAGE-WISE RULES TEXT ("3=ઉપર, 4=નીચે, 10-12=ડાબે")
  // ---------------------------------------------------------------------------

  static String? _edgeWord(String w) {
    final t = w.trim().toLowerCase();
    if (t.isEmpty) return null;
    const map = <String, String>{
      'left': 'left', 'l': 'left', 'ડાબે': 'left', 'ડાબી': 'left', 'ડાબુ': 'left',
      'right': 'right', 'r': 'right', 'જમણે': 'right', 'જમણી': 'right', 'જમણું': 'right',
      'top': 'top', 't': 'top', 'up': 'top', 'u': 'top', 'upper': 'top', 'upward': 'top', 'ઉપર': 'top',
      'bottom': 'bottom', 'b': 'bottom', 'down': 'bottom', 'd': 'bottom', 'lower': 'bottom', 'downward': 'bottom', 'નીચે': 'bottom',
      'none': 'none', 'no': 'none', 'n': 'none', '0': 'none', 'off': 'none', 'નહીં': 'none', 'નહિ': 'none', 'ખાલી': 'none',
    };
    return map[t];
  }

  static String _ascii(String s) {
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    final b = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      final i = guj.indexOf(ch);
      b.write(i >= 0 ? '$i' : ch);
    }
    return b.toString();
  }

  /// Parses "3=top, 4=bottom, 10-12=left" (Gujarati words and digits too).
  /// Returns the rules and the parts that could not be read.
  static ({Map<int, String> rules, List<String> bad}) parsePageEdges(String text) {
    final rules = <int, String>{};
    final bad = <String>[];
    for (final raw in _ascii(text).split(RegExp(r'[,;\n]+'))) {
      final part = raw.trim();
      if (part.isEmpty) continue;
      final m = RegExp(r'^(?:page|pg|p|પાનું|પાના)?\s*(\d{1,4})(?:\s*(?:-|–|to|થી)\s*(\d{1,4}))?\s*[=:]?\s*(\S+)$',
              caseSensitive: false)
          .firstMatch(part);
      final edge = m == null ? null : _edgeWord(m.group(3)!);
      if (m == null || edge == null) {
        bad.add(part);
        continue;
      }
      final a = int.parse(m.group(1)!);
      final b = m.group(2) == null ? a : int.parse(m.group(2)!);
      if (a < 1 || b < a || b - a > 2000) {
        bad.add(part);
        continue;
      }
      for (var p = a; p <= b; p++) {
        rules[p] = edge;
      }
    }
    return (rules: rules, bad: bad);
  }

  /// "3=ઉપર, 4=નીચે, 10-12=ડાબે" for [rules] (consecutive pages joined).
  static String formatPageEdges(Map<int, String> rules, {bool gujarati = true}) {
    final pages = rules.keys.toList()..sort();
    final out = <String>[];
    var i = 0;
    while (i < pages.length) {
      final start = pages[i];
      final e = rules[start]!;
      var end = start;
      while (i + 1 < pages.length && pages[i + 1] == end + 1 && rules[pages[i + 1]] == e) {
        i++;
        end = pages[i];
      }
      final label = gujarati ? edgeLabel(e) : e;
      out.add(start == end ? '$start=$label' : '$start-$end=$label');
      i++;
    }
    return out.join(', ');
  }

  // ---------------------------------------------------------------------------
  // STORAGE
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => <String, dynamic>{
        'cashbookOrientation': cashbookOrientation,
        'mode': mode,
        'bindingMm': bindingMm,
        'rotateLandscape': rotateLandscape,
        'flipLandscape': flipLandscape,
        'duplexAlign': duplexAlign,
        'pageEdges': pageEdges.map((k, v) => MapEntry('$k', v)),
      };

  void loadJson(Object? raw) {
    reset();
    if (raw is! Map) return;
    final o = '${raw['cashbookOrientation'] ?? ''}';
    if (o == 'portrait' || o == 'landscape') cashbookOrientation = o;
    final m = '${raw['mode'] ?? ''}';
    if (modes.any((x) => x.$1 == m)) mode = m;
    final b = raw['bindingMm'];
    if (b is num && b >= 0 && b <= 45) bindingMm = b.toDouble();
    if (raw['rotateLandscape'] is bool) rotateLandscape = raw['rotateLandscape'] as bool;
    if (raw['flipLandscape'] is bool) flipLandscape = raw['flipLandscape'] as bool;
    if (raw['duplexAlign'] is bool) duplexAlign = raw['duplexAlign'] as bool;
    final pe = raw['pageEdges'];
    if (pe is Map) {
      pe.forEach((k, v) {
        final p = int.tryParse('$k');
        final e = '$v';
        if (p != null && p > 0 && edges.contains(e)) pageEdges[p] = e;
      });
    }
  }

  void reset() {
    cashbookOrientation = 'portrait';
    mode = 'register';
    bindingMm = 24;
    rotateLandscape = true;
    flipLandscape = false;
    duplexAlign = false;
    pageEdges = <int, String>{};
  }
}

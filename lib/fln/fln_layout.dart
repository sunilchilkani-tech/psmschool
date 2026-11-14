// A4 page layout for the FLN workbook. One layout feeds both the on-screen
// preview and the PDF, so what the teacher sees is exactly what prints.
//
// Units are PDF points (1/72 inch). Text is measured with Flutter's text
// engine (correct Gujarati shaping); the PDF draws the same words as cached
// images at the same positions.

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:flutter/painting.dart';

import '../services/class_label.dart';
import 'fln_data.dart';
import 'fln_engine.dart';

const double kMm = 72.0 / 25.4;
const double kA4W = 595.2756;
const double kA4H = 841.8898;

// ---------------------------------------------------------------------------
// Text measurement
// ---------------------------------------------------------------------------

class FlnStyle {
  const FlnStyle(
    this.size, {
    this.weight = 400,
    this.color = 0xFF0F172A,
    this.family = FlnText.family,
    this.italic = false,
    this.lineFactor = FlnText.lineFactor,
  });
  final double size;
  final int weight;
  final int color;
  final String family;
  final bool italic;
  final double lineFactor;

  double get lineHeight => size * lineFactor;
  FlnStyle withColor(int c) =>
      FlnStyle(size, weight: weight, color: c, family: family, italic: italic, lineFactor: lineFactor);
  FlnStyle withSize(double s) =>
      FlnStyle(s, weight: weight, color: color, family: family, italic: italic, lineFactor: lineFactor);
  String get key =>
      '${size.toStringAsFixed(2)}|$weight|$color|$family|${italic ? 1 : 0}|${lineFactor.toStringAsFixed(2)}';
}

class FlnText {
  FlnText._();
  static final FlnText instance = FlnText._();

  static const String family = 'NotoSansGujaratiLocal';
  static const double lineFactor = 1.32;

  final Map<String, double> _widths = <String, double>{};
  final Map<String, TextPainter> _painters = <String, TextPainter>{};

  void clear() {
    _widths.clear();
    for (final p in _painters.values) {
      p.dispose();
    }
    _painters.clear();
  }

  static FontWeight _weight(int w) => w >= 800
      ? FontWeight.w800
      : w >= 700
          ? FontWeight.w700
          : w >= 600
              ? FontWeight.w600
              : FontWeight.w400;

  static TextStyle textStyle(FlnStyle st) => TextStyle(
        fontFamily: st.family,
        fontSize: st.size,
        fontWeight: _weight(st.weight),
        fontStyle: st.italic ? FontStyle.italic : FontStyle.normal,
        color: Color(st.color),
        height: st.lineFactor,
      );

  static StrutStyle strut(FlnStyle st) => StrutStyle(
        fontFamily: st.family,
        fontSize: st.size,
        height: st.lineFactor,
        forceStrutHeight: true,
      );

  /// Painter for one word / character (cached, laid out).
  TextPainter painter(String text, FlnStyle st) {
    final key = '${st.key}|$text';
    final hit = _painters[key];
    if (hit != null) return hit;
    final tp = TextPainter(
      text: TextSpan(text: text, style: textStyle(st)),
      textDirection: TextDirection.ltr,
      strutStyle: strut(st),
      maxLines: 1,
    )..layout();
    if (_painters.length > 6000) clear();
    _painters[key] = tp;
    return tp;
  }

  double _raw(String text, FlnStyle st) {
    final key = 'w${st.key}|$text';
    final hit = _widths[key];
    if (hit != null) return hit;
    final w = painter(text, st).width;
    _widths[key] = w;
    return w;
  }

  /// True when the word has no Gujarati letters, so it can be drawn
  /// character by character (digits, Latin, punctuation, Gujarati digits).
  static bool isSimple(String word) {
    for (final r in word.runes) {
      if (r >= 0x0A80 && r <= 0x0AFF && !(r >= 0x0AE6 && r <= 0x0AEF)) return false;
    }
    return true;
  }

  double charWidth(String ch, FlnStyle st) => _raw(ch, st);

  double wordWidth(String word, FlnStyle st) {
    if (!isSimple(word)) return _raw(word, st);
    var w = 0.0;
    for (final r in word.runes) {
      w += _raw(String.fromCharCode(r), st);
    }
    return w;
  }

  double spaceWidth(FlnStyle st) {
    final key = 'space|${st.key}';
    final hit = _widths[key];
    if (hit != null) return hit;
    final w = math.max(_raw('x x', st) - _raw('xx', st), st.size * 0.25);
    _widths[key] = w;
    return w;
  }

  double textWidth(String text, FlnStyle st) {
    final words = splitWords(text);
    if (words.isEmpty) return 0;
    var w = 0.0;
    for (final word in words) {
      w += wordWidth(word, st);
    }
    return w + spaceWidth(st) * (words.length - 1);
  }

  static List<String> splitWords(String text) =>
      text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  /// Largest size (down to [minSize]) at which [text] fits on one line.
  FlnStyle fit(String text, FlnStyle st, double maxW, {double minSize = 6}) {
    var s = st;
    while (s.size > minSize && textWidth(text, s) > maxW) {
      s = s.withSize(math.max(minSize, s.size - 0.5));
    }
    return s;
  }

  /// Cuts [text] to one line with an ellipsis.
  String ellipsize(String text, FlnStyle st, double maxW) {
    if (textWidth(text, st) <= maxW) return text;
    final words = splitWords(text);
    var out = '';
    for (final w in words) {
      final next = out.isEmpty ? w : '$out $w';
      if (textWidth('$next …', st) > maxW) break;
      out = next;
    }
    return out.isEmpty ? '…' : '$out …';
  }
}

// ---------------------------------------------------------------------------
// Draw operations
// ---------------------------------------------------------------------------

abstract class FlnOp {
  FlnOp shifted(double dy);
}

class FlnBoxOp extends FlnOp {
  FlnBoxOp(this.rect, {this.fill, this.stroke, this.strokeWidth = 0.6, this.radius = 0});
  final Rect rect;
  final int? fill;
  final int? stroke;
  final double strokeWidth;
  final double radius;
  @override
  FlnOp shifted(double dy) => FlnBoxOp(rect.shift(Offset(0, dy)),
      fill: fill, stroke: stroke, strokeWidth: strokeWidth, radius: radius);
}

class FlnLineOp extends FlnOp {
  FlnLineOp(this.a, this.b, {this.color = 0xFF334155, this.width = 0.6, this.dotted = false});
  final Offset a;
  final Offset b;
  final int color;
  final double width;
  final bool dotted;
  @override
  FlnOp shifted(double dy) =>
      FlnLineOp(a.translate(0, dy), b.translate(0, dy), color: color, width: width, dotted: dotted);
}

/// One word. [y] is the top of its line box; [scale] shrinks over-long words.
class FlnWordOp extends FlnOp {
  FlnWordOp(this.text, this.x, this.y, this.style, {this.scale = 1});
  final String text;
  final double x;
  final double y;
  final FlnStyle style;
  final double scale;
  @override
  FlnOp shifted(double dy) => FlnWordOp(text, x, y + dy, style, scale: scale);
}

class FlnPageLayout {
  FlnPageLayout({
    required this.width,
    required this.height,
    required this.paperNo,
    required this.pageInPaper,
    required this.isKey,
  });
  final double width;
  final double height;
  final int paperNo;
  int pageInPaper;
  int pagesInPaper = 1;
  final bool isKey;
  final List<FlnOp> ops = <FlnOp>[];
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

class FlnPageGap {
  const FlnPageGap(this.cardGapMm, this.optionGapMm);
  final double cardGapMm;
  final double optionGapMm;
}

class FlnLayoutSettings {
  FlnLayoutSettings({
    this.landscape = false,
    this.marginTopMm = 8,
    this.marginBottomMm = 8,
    this.marginLeftMm = 8,
    this.marginRightMm = 8,
    this.columns = 2,
    this.fontSize = 10,
    this.optionsMode = 'with',
    this.answersMode = 'student',
    this.keyStyle = 'section',
    this.theme = 'royal',
    this.showQTag = false,
    this.groupBreaks = 'off',
    this.cardGapMm = 2.5,
    this.optionGapMm = 1.2,
    this.answerBoxMm = 7,
    this.spreadToFill = true,
    Map<int, FlnPageGap>? pageGaps,
    this.examTitle = 'FLN ગણિત મૂલ્યાંકન સ્વાધ્યાયપોથી',
    this.examDate = '',
    this.showMarksBox = true,
    this.answerFormat = 'marked',
  }) : pageGaps = pageGaps ?? <int, FlnPageGap>{};

  bool landscape;
  double marginTopMm;
  double marginBottomMm;
  double marginLeftMm;
  double marginRightMm;
  int columns;
  double fontSize;

  /// 'with' | 'without' | 'both'
  String optionsMode;

  /// 'student' | 'inline' | 'key_each' | 'key_master' | 'key_only'
  String answersMode;

  /// 'section' | 'table' | 'grid'
  String keyStyle;

  /// 'royal' | 'emerald' | 'bw'
  String theme;
  bool showQTag;

  /// 'auto' | 'on' | 'off'
  String groupBreaks;
  double cardGapMm;
  double optionGapMm;
  double answerBoxMm;
  bool spreadToFill;
  final Map<int, FlnPageGap> pageGaps;
  String examTitle;
  String examDate;
  bool showMarksBox;

  /// Second PDF: 'marked' = the same papers with answers and steps,
  /// 'key' = answer-key tables.
  String answerFormat;

  double get pageW => landscape ? kA4H : kA4W;
  double get pageH => landscape ? kA4W : kA4H;

  FlnPageGap gapFor(int page) => pageGaps[page] ?? FlnPageGap(cardGapMm, optionGapMm);

  bool get showOptions => optionsMode == 'with' || optionsMode == 'both';
  bool get showWriteBox => optionsMode == 'without' || optionsMode == 'both';
  bool get inlineAnswers => answersMode == 'inline';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'landscape': landscape,
        'mt': marginTopMm,
        'mb': marginBottomMm,
        'ml': marginLeftMm,
        'mr': marginRightMm,
        'columns': columns,
        'fontSize': fontSize,
        'optionsMode': optionsMode,
        'answersMode': answersMode,
        'keyStyle': keyStyle,
        'theme': theme,
        'showQTag': showQTag,
        'groupBreaks': groupBreaks,
        'layoutVersion': 2,
        'answerFormat': answerFormat,
        'examDate': examDate,
        'cardGapMm': cardGapMm,
        'optionGapMm': optionGapMm,
        'answerBoxMm': answerBoxMm,
        'spreadToFill': spreadToFill,
        'pageGaps': <String, dynamic>{
          for (final e in pageGaps.entries) '${e.key}': <double>[e.value.cardGapMm, e.value.optionGapMm],
        },
        'examTitle': examTitle,
        'showMarksBox': showMarksBox,
      };

  factory FlnLayoutSettings.fromJson(Map<String, dynamic> j) {
    double d(String k, double def, double lo, double hi) {
      final v = j[k];
      return v is num ? v.toDouble().clamp(lo, hi) : def;
    }

    String pick(String k, String def, Set<String> allowed) {
      final v = '${j[k] ?? ''}';
      return allowed.contains(v) ? v : def;
    }

    final gaps = <int, FlnPageGap>{};
    final rawGaps = j['pageGaps'];
    if (rawGaps is Map) {
      rawGaps.forEach((k, v) {
        final p = int.tryParse('$k');
        if (p != null && v is List && v.length == 2 && v[0] is num && v[1] is num) {
          gaps[p] = FlnPageGap(
            (v[0] as num).toDouble().clamp(0.0, 40.0),
            (v[1] as num).toDouble().clamp(0.0, 20.0),
          );
        }
      });
    }
    return FlnLayoutSettings(
      landscape: j['landscape'] == true,
      marginTopMm: d('mt', 8, 3, 30),
      marginBottomMm: d('mb', 8, 3, 30),
      marginLeftMm: d('ml', 8, 3, 30),
      marginRightMm: d('mr', 8, 3, 30),
      columns: j['columns'] == 1 ? 1 : 2,
      fontSize: d('fontSize', 10, 8, 14),
      optionsMode: pick('optionsMode', 'with', const <String>{'with', 'without', 'both'}),
      answersMode: pick('answersMode', 'student',
          const <String>{'student', 'inline', 'key_each', 'key_master', 'key_only'}),
      keyStyle: pick('keyStyle', 'section', const <String>{'section', 'table', 'grid'}),
      theme: pick('theme', 'royal', const <String>{'royal', 'emerald', 'bw'}),
      showQTag: j['showQTag'] == true,
      groupBreaks: j['layoutVersion'] == 2 ? pick('groupBreaks', 'off', const <String>{'auto', 'on', 'off'}) : 'off',
      cardGapMm: d('cardGapMm', 2.5, 0, 40),
      optionGapMm: d('optionGapMm', 1.2, 0, 20),
      answerBoxMm: d('answerBoxMm', 7, 4, 40),
      spreadToFill: j['spreadToFill'] != false,
      pageGaps: gaps,
      examTitle: '${j['examTitle'] ?? ''}'.trim().isEmpty
          ? 'FLN ગણિત મૂલ્યાંકન સ્વાધ્યાયપોથી'
          : '${j['examTitle']}',
      showMarksBox: j['showMarksBox'] != false,
      answerFormat: pick('answerFormat', 'marked', const <String>{'marked', 'key'}),
      examDate: '${j['examDate'] ?? ''}'.trim(),
    );
  }
}

/// Header facts printed on a paper.
class FlnHeaderInfo {
  const FlnHeaderInfo({
    required this.schoolName,
    this.studentName = '',
    this.rollNo = '',
    this.classLabel = '',
    this.setLabel = '',
  });
  final String schoolName;
  final String studentName;
  final String rollNo;

  /// Class as stored ("ધોરણ - 6 - અ" or "6 - અ"); printed without a
  /// second "ધોરણ".
  final String classLabel;

  /// "A", "B"… only when papers are printed in sets.
  final String setLabel;

  String get classBare => ClassLabel.bare(classLabel);

  FlnHeaderInfo withSet(String set) => FlnHeaderInfo(
        schoolName: schoolName,
        studentName: studentName,
        rollNo: rollNo,
        classLabel: classLabel,
        setLabel: set,
      );

  /// Same header without the student (answer copies of a set).
  FlnHeaderInfo get generic => FlnHeaderInfo(schoolName: schoolName, classLabel: classLabel, setLabel: setLabel);
}

class _Theme {
  const _Theme({
    required this.bandFill,
    required this.bandText,
    required this.bandBorder,
    required this.bannerFill,
    required this.bannerAccent,
    required this.bannerText,
    required this.badgeFill,
    required this.badgeText,
    required this.cardBorder,
    required this.frame,
  });
  final int? bandFill;
  final int bandText;
  final int bandBorder;
  final int bannerFill;
  final int bannerAccent;
  final int bannerText;
  final int badgeFill;
  final int badgeText;
  final int cardBorder;
  final int frame;

  static _Theme of(String name) {
    switch (name) {
      case 'emerald':
        return const _Theme(
          bandFill: 0xFF134E4A,
          bandText: 0xFFFFFFFF,
          bandBorder: 0xFF134E4A,
          bannerFill: 0xFFF0FDFA,
          bannerAccent: 0xFF115E59,
          bannerText: 0xFF042F2E,
          badgeFill: 0xFF115E59,
          badgeText: 0xFFFFFFFF,
          cardBorder: 0xFF99D5CC,
          frame: 0xFF134E4A,
        );
      case 'bw':
        return const _Theme(
          bandFill: null,
          bandText: 0xFF000000,
          bandBorder: 0xFF000000,
          bannerFill: 0xFFF1F5F9,
          bannerAccent: 0xFF000000,
          bannerText: 0xFF000000,
          badgeFill: 0xFF000000,
          badgeText: 0xFFFFFFFF,
          cardBorder: 0xFF6B7280,
          frame: 0xFF000000,
        );
      default:
        return const _Theme(
          bandFill: 0xFF1E1B4B,
          bandText: 0xFFFFFFFF,
          bandBorder: 0xFF1E1B4B,
          bannerFill: 0xFFFFFBEB,
          bannerAccent: 0xFF312E81,
          bannerText: 0xFF1E1B4B,
          badgeFill: 0xFF312E81,
          badgeText: 0xFFFFFFFF,
          cardBorder: 0xFFCBD5E1,
          frame: 0xFF1E1B4B,
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Paragraph wrapping
// ---------------------------------------------------------------------------

class _Tok {
  const _Tok(this.text, this.style);
  final String text;
  final FlnStyle style;
}

class _Para {
  _Para(this.ops, this.height, this.lines);
  final List<FlnOp> ops;
  final double height;
  final int lines;
}

/// Lays out [tokens] in the column [x0, x0+maxW]; first line may start at
/// [firstX] (for a leading badge). Ops are relative to y = 0.
_Para _wrap(List<_Tok> tokens, double x0, double maxW, {double? firstX, TextAlign align = TextAlign.left}) {
  final t = FlnText.instance;
  final lines = <List<(_Tok, double)>>[];
  final lineStarts = <double>[];
  var line = <(_Tok, double)>[];
  var lineStart = firstX ?? x0;
  var cursor = lineStart;
  final right = x0 + maxW;

  void push() {
    lines.add(line);
    lineStarts.add(lineStart);
    line = <(_Tok, double)>[];
    lineStart = x0;
    cursor = x0;
  }

  for (final tok in tokens) {
    for (final w in FlnText.splitWords(tok.text)) {
      final ww = t.wordWidth(w, tok.style);
      final sp = line.isEmpty ? 0.0 : t.spaceWidth(tok.style);
      if (line.isNotEmpty && cursor + sp + ww > right) push();
      final x = cursor + (line.isEmpty ? 0.0 : t.spaceWidth(tok.style));
      line.add((_Tok(w, tok.style), x));
      cursor = x + ww;
    }
  }
  if (line.isNotEmpty) push();

  final ops = <FlnOp>[];
  var y = 0.0;
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final lh = l.fold<double>(0, (m, e) => math.max(m, e.$1.style.lineHeight));
    final startX = lineStarts[i];
    final last = l.last;
    final lineW = last.$2 + t.wordWidth(last.$1.text, last.$1.style) - startX;
    final avail = right - startX;
    var dx = 0.0;
    if (align == TextAlign.center) dx = math.max(0, (avail - lineW) / 2);
    if (align == TextAlign.right) dx = math.max(0, avail - lineW);
    final scale = lineW > avail && l.length == 1 ? avail / lineW : 1.0;
    for (final e in l) {
      final top = y + (lh - e.$1.style.lineHeight) * 0.75;
      ops.add(FlnWordOp(e.$1.text, e.$2 + dx, top, e.$1.style, scale: scale));
    }
    y += lh;
  }
  return _Para(ops, y, lines.length);
}

/// Public paragraph layout: words of [text] wrapped in [maxW] starting at x = 0.
/// Returns word ops (y = top of line box, relative to 0) and the height.
(List<FlnWordOp>, double) flnLayoutParagraph(String text, FlnStyle style, double maxW,
    {TextAlign align = TextAlign.left}) {
  final para = _wrap(<_Tok>[_Tok(text, style)], 0, maxW, align: align);
  return (para.ops.whereType<FlnWordOp>().toList(), para.height);
}

List<FlnOp> _shift(List<FlnOp> ops, double dy) => <FlnOp>[for (final o in ops) o.shifted(dy)];

/// Single line of text at (x, y) (top of line box).
List<FlnOp> _line(String text, double x, double y, FlnStyle st, {double? maxW, TextAlign align = TextAlign.left}) {
  final t = FlnText.instance;
  var style = st;
  if (maxW != null) style = t.fit(text, st, maxW, minSize: math.min(st.size, 6.5));
  final w = t.textWidth(text, style);
  var x0 = x;
  if (maxW != null && align == TextAlign.center) x0 = x + math.max(0, (maxW - w) / 2);
  if (maxW != null && align == TextAlign.right) x0 = x + math.max(0, maxW - w);
  final ops = <FlnOp>[];
  var cx = x0;
  final yy = y + (st.lineHeight - style.lineHeight) / 2;
  for (final word in FlnText.splitWords(text)) {
    ops.add(FlnWordOp(word, cx, yy, style));
    cx += t.wordWidth(word, style) + t.spaceWidth(style);
  }
  return ops;
}

// ---------------------------------------------------------------------------
// Blocks (banner / row of cards) placed on pages
// ---------------------------------------------------------------------------

class _Block {
  _Block(this.ops, this.height, {this.isBanner = false});
  final List<FlnOp> ops; // relative to block top
  final double height;
  final bool isBanner;
}

class _PageBuilder {
  _PageBuilder(this.s, this.paperNo, this.isKey, this.pageNo);
  final FlnLayoutSettings s;
  final int paperNo;
  final bool isKey;
  final int pageNo;
  final List<(_Block, double)> blocks = <(_Block, double)>[];
  double top = 0;
  double bottom = 0;
  double y = 0;

  bool get isEmpty => blocks.isEmpty;
}

/// Paper and answer-key layout.
class FlnLayoutEngine {
  FlnLayoutEngine(this.s, {this.answers = false});
  final FlnLayoutSettings s;

  /// Teacher copy: correct options marked, answers and word-problem steps.
  final bool answers;
  final FlnText _t = FlnText.instance;

  double get _fs => s.fontSize;
  _Theme get _th => _Theme.of(s.theme);
  double get _left => s.marginLeftMm * kMm;
  double get _right => s.pageW - s.marginRightMm * kMm;
  double get _contentW => _right - _left;
  double get _top => s.marginTopMm * kMm;
  double get _bottom => s.pageH - s.marginBottomMm * kMm;

  FlnStyle get _body => FlnStyle(_fs, weight: 600, color: 0xFF0F172A);
  FlnStyle get _small => FlnStyle(_fs * 0.82, weight: 400, color: 0xFF475569);

  // ----------------------------- headers / footer ---------------------------

  double _fullHeaderHeight() {
    final bandH = _fs * 1.2 * FlnText.lineFactor + 8;
    final rowH = _fs * FlnText.lineFactor + 5;
    return bandH + rowH * 3 + 8;
  }

  List<FlnOp> _fullHeader(int paperNo, int totalQuestions, FlnHeaderInfo h) {
    final ops = <FlnOp>[];
    final th = _th;
    final bandH = _fs * 1.2 * FlnText.lineFactor + 8;
    final rowH = _fs * FlnText.lineFactor + 5;
    final totalH = _fullHeaderHeight();
    final x = _left, w = _contentW, y = _top;
    ops.add(FlnBoxOp(Rect.fromLTWH(x, y, w, totalH), stroke: th.frame, strokeWidth: 1.2, radius: 4));
    if (th.bandFill != null) {
      ops.add(FlnBoxOp(Rect.fromLTWH(x, y, w, bandH), fill: th.bandFill, radius: 4));
      ops.add(FlnBoxOp(Rect.fromLTWH(x, y + bandH - 4, w, 4), fill: th.bandFill));
    } else {
      ops.add(FlnLineOp(Offset(x, y + bandH), Offset(x + w, y + bandH), color: th.bandBorder, width: 1));
    }
    final bandText = FlnStyle(_fs * 1.2, weight: 800, color: th.bandText);
    final pill = <String>[
      if (answers) 'જવાબ સાથે',
      if (h.setLabel.isNotEmpty) 'સેટ ${h.setLabel}',
      'કુલ પ્રશ્નો ${flnGujDigits(totalQuestions)}',
    ].join(' · ');
    final pillSt = FlnStyle(_fs * 0.85, weight: 700, color: answers ? 0xFFB91C1C : (th.bandFill == null ? 0xFF000000 : 0xFF0F172A));
    final pillW = _t.textWidth(pill, pillSt) + 12;
    final pillH = pillSt.lineHeight + 2;
    final pillX = x + w - pillW - 6;
    final pillY = y + (bandH - pillH) / 2;
    ops.add(FlnBoxOp(Rect.fromLTWH(pillX, pillY, pillW, pillH),
        fill: 0xFFFFFFFF, stroke: th.bandFill == null ? 0xFF000000 : null, radius: pillH / 2));
    ops.addAll(_line(pill, pillX + 6, pillY + 1, pillSt));
    ops.addAll(_line(s.examTitle, x + 8, y + (bandH - bandText.lineHeight) / 2, bandText,
        maxW: pillX - x - 16));

    final label = FlnStyle(_fs * 0.92, weight: 700, color: 0xFF0F172A);
    final value = FlnStyle(_fs * 0.98, weight: 700, color: 0xFF1E1B4B);
    double field(String lbl, String val, double fx, double fy, double fw, {String blank = ''}) {
      final lw = _t.textWidth(lbl, label);
      ops.addAll(_line(lbl, fx, fy, label));
      final lineX = fx + lw + 5;
      final lineY = fy + label.lineHeight - 1;
      ops.add(FlnLineOp(Offset(lineX, lineY), Offset(fx + fw, lineY), color: 0xFF475569, width: 0.8, dotted: true));
      final shown = val.trim().isNotEmpty ? val.trim() : blank;
      if (shown.isNotEmpty) {
        ops.addAll(_line(shown, lineX + 3, fy, val.trim().isNotEmpty ? value : _small, maxW: fx + fw - lineX - 6));
      }
      return fx + fw;
    }

    final inner = x + 8, innerW = w - 16;
    var ry = y + bandH + 4;
    field('શાળાનું નામ :', h.schoolName, inner, ry, innerW);
    ry += rowH;
    field('વિદ્યાર્થીનું નામ :', h.studentName, inner, ry, innerW * 0.66 - 6);
    field('રોલ નં. :', h.rollNo, inner + innerW * 0.66, ry, innerW * 0.34);
    ry += rowH;
    final marksText = 'મેળવેલ ગુણ : ______ / ${flnGujDigits(totalQuestions)}';
    final marksSt = FlnStyle(_fs * 0.92, weight: 800, color: 0xFF0F172A);
    final marksW = s.showMarksBox ? _t.textWidth(marksText, marksSt) + 14 : 0.0;
    final rest = innerW - marksW - (s.showMarksBox ? 8 : 0);
    field('ધોરણ / વર્ગ :', h.classBare, inner, ry, rest * 0.48 - 6);
    field('તારીખ :', s.examDate, inner + rest * 0.48, ry, rest * 0.52, blank: '____ / ____ / ૨૦૨__');
    if (s.showMarksBox) {
      final bx = inner + innerW - marksW;
      ops.add(FlnBoxOp(Rect.fromLTWH(bx, ry - 1, marksW, marksSt.lineHeight + 3),
          fill: 0xFFF8FAFC, stroke: 0xFF1F2937, strokeWidth: 1, radius: 3));
      ops.addAll(_line(marksText, bx + 7, ry + 0.5, marksSt));
    }
    return ops;
  }

  double _contHeaderHeight() => _fs * 0.9 * FlnText.lineFactor + 6;

  List<FlnOp> _contHeader(int paperNo, int pageNo, int pages, FlnHeaderInfo h, {bool key = false}) {
    final st = FlnStyle(_fs * 0.9, weight: 700, color: 0xFF0F172A);
    final hh = _contHeaderHeight();
    final ops = <FlnOp>[
      FlnBoxOp(Rect.fromLTWH(_left, _top, _contentW, hh), fill: 0xFFF8FAFC, stroke: _th.frame, strokeWidth: 0.8, radius: 3),
    ];
    final pageText = 'પાનું ${flnGujDigits(pageNo)} / ${flnGujDigits(pages)}';
    final pw = _t.textWidth(pageText, st);
    ops.addAll(_line(pageText, _right - pw - 6, _top + 3, st));
    final meta = <String>[
      if (h.studentName.trim().isNotEmpty) h.studentName.trim(),
      if (h.rollNo.trim().isNotEmpty) 'રોલ નં. ${h.rollNo.trim()}',
      if (h.classBare.isNotEmpty) 'ધોરણ ${h.classBare}',
    ].join(' · ');
    final title = '${key ? 'ઉત્તરવહી' : s.examTitle}'
        '${h.setLabel.isEmpty ? '' : ' — સેટ ${h.setLabel}'}'
        '${answers && !key ? ' (જવાબ સાથે)' : ''}'
        '${meta.isEmpty ? '' : '  ($meta)'}';
    ops.addAll(_line(_t.ellipsize(title, st, _contentW - pw - 20), _left + 6, _top + 3, st));
    return ops;
  }

  double _footerHeight() => _fs * 0.78 * FlnText.lineFactor + 5;

  List<FlnOp> _footer(int paperNo, int pageNo, int pages, FlnHeaderInfo h) {
    final st = FlnStyle(_fs * 0.78, weight: 400, color: 0xFF475569);
    final bold = FlnStyle(_fs * 0.78, weight: 700, color: 0xFF0F172A);
    final fh = _footerHeight();
    final y = _bottom - fh;
    final ops = <FlnOp>[FlnLineOp(Offset(_left, y), Offset(_right, y), color: 0xFFCBD5E1, width: 0.6)];
    final left = <String>[
      if (h.setLabel.isNotEmpty) 'સેટ ${h.setLabel}',
      if (h.rollNo.trim().isNotEmpty) 'રોલ નં. ${h.rollNo.trim()}',
      if (h.studentName.trim().isNotEmpty) h.studentName.trim(),
    ].join(' · ');
    ops.addAll(_line(left, _left, y + 3, st, maxW: _contentW * 0.34));
    ops.addAll(_line('શિક્ષક / નિરીક્ષકની સહી : ____________', _left + _contentW * 0.34, y + 3, st,
        maxW: _contentW * 0.4, align: TextAlign.center));
    ops.addAll(_line('પાનું ${flnGujDigits(pageNo)} / ${flnGujDigits(pages)}', _left + _contentW * 0.74, y + 3, bold,
        maxW: _contentW * 0.26, align: TextAlign.right));
    return ops;
  }

  // ------------------------------- blocks -----------------------------------

  _Block _banner(FlnSectionMeta m, int count, {bool continued = false, double? width, double? x}) {
    final bx = x ?? _left;
    final bw = width ?? _contentW;
    final st = FlnStyle(_fs * 0.95, weight: 800, color: _th.bannerText);
    final h = st.lineHeight + 5;
    final countText = '${flnGujDigits(count)} પ્રશ્નો';
    final countSt = FlnStyle(_fs * 0.78, weight: 700, color: 0xFF334155);
    final cw = _t.textWidth(countText, countSt) + 10;
    final title = '${m.titleGuj}${continued ? ' (ચાલુ)' : ''}  —  ${m.shortInstruction}';
    final ops = <FlnOp>[
      FlnBoxOp(Rect.fromLTWH(bx, 0, bw, h), fill: _th.bannerFill, radius: 2.5),
      FlnBoxOp(Rect.fromLTWH(bx, 0, 3, h), fill: _th.bannerAccent),
      FlnBoxOp(Rect.fromLTWH(bx + bw - cw - 4, (h - countSt.lineHeight - 2) / 2, cw, countSt.lineHeight + 2),
          fill: 0xFFFFFFFF, stroke: 0xFFCBD5E1, strokeWidth: 0.5, radius: 2),
      ..._line(countText, bx + bw - cw + 1, (h - countSt.lineHeight) / 2, countSt),
      ..._line(title, bx + 8, 2.5, st, maxW: bw - cw - 18),
    ];
    return _Block(ops, h, isBanner: true);
  }

  /// One question card at (x, 0) with width [w]. Returns ops and height.
  (List<FlnOp>, double) _card(FlnPreparedItem p, double x, double w, int page, {bool withInstruction = false}) {
    final ops = <FlnOp>[];
    const pad = 4.0;
    final gap = s.gapFor(page);
    final optGap = gap.optionGapMm * kMm;
    final innerX = x + pad;
    final innerW = w - pad * 2;
    final badgeSt = FlnStyle(_fs * 0.82, weight: 800, color: _th.badgeText);
    final badgeText = 'પ્રશ્ન ${p.displayNo}';
    final badgeW = _t.textWidth(badgeText, badgeSt) + 8;
    final badgeH = badgeSt.lineHeight + 1;
    var y = pad;
    ops.add(FlnBoxOp(Rect.fromLTWH(innerX, y + 0.5, badgeW, badgeH), fill: _th.badgeFill, radius: 2.5));
    ops.addAll(_line(badgeText, innerX + 4, y + 1, badgeSt));

    final showBubble = s.showOptions && !answers;
    final bubbleSt = FlnStyle(_fs * 0.78, weight: 700, color: 0xFF334155);
    const bubbleText = 'જવાબ: (      )';
    final bubbleW = showBubble ? _t.textWidth(bubbleText, bubbleSt) + 8 : 0.0;
    if (showBubble) {
      final bx = innerX + innerW - bubbleW;
      ops.add(FlnBoxOp(Rect.fromLTWH(bx, y + 0.5, bubbleW, bubbleSt.lineHeight + 2),
          fill: 0xFFF8FAFC, stroke: 0xFF94A3B8, strokeWidth: 0.6, radius: 2));
      ops.addAll(_line(bubbleText, bx + 4, y + 1.5, bubbleSt));
    }

    final meta = flnSectionOf(p.item.sec);
    final promptText = withInstruction ? '${meta.shortInstruction} ${p.item.prompt}' : p.item.prompt;
    final textX = innerX + badgeW + 5;
    final textW = innerW - badgeW - 5 - (showBubble ? bubbleW + 5 : 0);
    final tokens = <_Tok>[
      _Tok(promptText, _body),
      if (s.showQTag) _Tok('[Q${p.item.qNo}]', FlnStyle(_fs * 0.72, weight: 400, color: 0xFF94A3B8)),
    ];
    final para = _wrap(tokens, textX, textW);
    ops.addAll(_shift(para.ops, y));
    y += math.max(para.height, badgeH + 1);

    if (s.showOptions) {
      y += optGap;
      ops.add(FlnLineOp(Offset(innerX, y - optGap / 2), Offset(innerX + innerW, y - optGap / 2),
          color: 0xFFE2E8F0, width: 0.4));
      final optSt = FlnStyle(_fs * 0.92, weight: 400, color: 0xFF1F2937);
      final letterSt = FlnStyle(_fs * 0.72, weight: 800, color: 0xFF0F172A);
      final d = letterSt.lineHeight;
      const cellGap = 3.0;
      const cellPad = 2.0;
      int cols = 4;
      double cellW(int c) => (innerW - cellGap * (c - 1)) / c;
      bool fitsOneLine(int c) => p.choices.every(
          (ch) => _t.textWidth(ch.text, optSt) <= cellW(c) - d - 4 - cellPad * 2);
      if (!fitsOneLine(4)) cols = fitsOneLine(2) ? 2 : (innerW > 220 ? 2 : 1);
      final cw = cellW(cols);
      var rowTop = y;
      for (var r = 0; r * cols < p.choices.length; r++) {
        final rowItems = p.choices.skip(r * cols).take(cols).toList();
        final paras = <_Para>[];
        for (var i = 0; i < rowItems.length; i++) {
          final cx = innerX + i * (cw + cellGap);
          paras.add(_wrap(<_Tok>[_Tok(rowItems[i].text, optSt)], cx + cellPad + d + 3, cw - cellPad * 2 - d - 3));
        }
        final rowH = paras.fold<double>(d, (m, pp) => math.max(m, pp.height)) + cellPad * 2;
        for (var i = 0; i < rowItems.length; i++) {
          final ch = rowItems[i];
          final cx = innerX + i * (cw + cellGap);
          final hi = answers && ch.correct;
          ops.add(FlnBoxOp(Rect.fromLTWH(cx, rowTop, cw, rowH),
              fill: hi ? 0xFFD1FAE5 : 0xFFF8FAFC, stroke: hi ? 0xFF059669 : 0xFFCBD5E1, strokeWidth: hi ? 0.9 : 0.5, radius: 2));
          final cy = rowTop + cellPad + (paras[i].lines == 1 ? (paras[i].height - d) / 2 : 0);
          ops.add(FlnBoxOp(Rect.fromLTWH(cx + cellPad, cy, d, d),
              fill: hi ? 0xFF047857 : 0xFFFFFFFF, stroke: hi ? 0xFF047857 : 0xFF475569, strokeWidth: 0.6, radius: d / 2));
          ops.addAll(_line(ch.letter, cx + cellPad, cy, hi ? letterSt.withColor(0xFFFFFFFF) : letterSt,
              maxW: d, align: TextAlign.center));
          ops.addAll(_shift(paras[i].ops, rowTop + cellPad));
        }
        rowTop += rowH + cellGap;
      }
      y = rowTop - cellGap;
    }

    if (s.showWriteBox && !answers) {
      y += s.showOptions ? 3 : optGap;
      final lblSt = FlnStyle(_fs * 0.85, weight: 700, color: 0xFF475569);
      const lbl = 'જવાબ લખો :';
      final lw = _t.textWidth(lbl, lblSt);
      final boxH = s.answerBoxMm * kMm;
      final boxW = math.min(innerW - lw - 6, math.max(120.0, innerW * 0.55));
      ops.addAll(_line(lbl, innerX, y + (math.min(boxH, lblSt.lineHeight * 1.6) - lblSt.lineHeight) / 2, lblSt));
      ops.add(FlnBoxOp(Rect.fromLTWH(innerX + lw + 6, y, boxW, boxH), stroke: 0xFF64748B, strokeWidth: 0.7, radius: 2));
      y += boxH;
    }

    if (answers) {
      y += math.max(2.0, optGap * 0.6);
      final ansSt = FlnStyle(_fs * 0.9, weight: 800, color: 0xFF047857);
      final text = 'સાચો જવાબ : ${s.showOptions ? '(${p.correctLetter}) ' : ''}${p.item.answer}';
      final para2 = _wrap(<_Tok>[_Tok(text, ansSt)], innerX, innerW);
      ops.addAll(_shift(para2.ops, y));
      y += para2.height;
      if (p.item.steps.isNotEmpty) {
        final stepSt = FlnStyle(_fs * 0.8, weight: 600, color: 0xFF334155);
        final para3 = _wrap(<_Tok>[_Tok('રીત :  ${p.item.steps.join('   »   ')}', stepSt)], innerX, innerW);
        y += 1;
        ops.addAll(_shift(para3.ops, y));
        y += para3.height;
      }
    }

    y += pad;
    return (ops, y);
  }

  _Block _cardRow(List<FlnPreparedItem> row, int page, bool withInstruction) {
    const colGap = 6.0;
    final w = (_contentW - colGap) / 2;
    if (row.length == 1) {
      // In the 2-column layout an odd last question keeps the column width
      // (word problems always use the full width).
      final full = s.columns == 1 || row.first.item.sec == 'WP';
      final cw = full ? _contentW : w;
      final c = _card(row.first, _left, cw, page, withInstruction: withInstruction);
      return _Block(<FlnOp>[
        FlnBoxOp(Rect.fromLTWH(_left, 0, cw, c.$2), stroke: _th.cardBorder, strokeWidth: 0.7, radius: 3),
        ...c.$1,
      ], c.$2);
    }
    final a = _card(row[0], _left, w, page, withInstruction: withInstruction);
    final b = _card(row[1], _left + w + colGap, w, page, withInstruction: withInstruction);
    final h = math.max(a.$2, b.$2);
    return _Block(<FlnOp>[
      FlnBoxOp(Rect.fromLTWH(_left, 0, w, h), stroke: _th.cardBorder, strokeWidth: 0.7, radius: 3),
      FlnBoxOp(Rect.fromLTWH(_left + w + colGap, 0, w, h), stroke: _th.cardBorder, strokeWidth: 0.7, radius: 3),
      ...a.$1,
      ...b.$1,
    ], h);
  }

  // ------------------------------- papers -----------------------------------

  String _groupKey(String sec) {
    switch (sec) {
      case '1A':
        return 'P1';
      case '1B':
      case '2A':
        return 'P2';
      case '2B':
      case '2C':
        return 'P3';
      case '3A':
      case '3B':
      case '3C':
        return 'P4';
      case '3D':
      case '3E':
        return 'P5';
      default:
        return sec;
    }
  }

  /// Pages of one student paper (without answer-key pages).
  List<FlnPageLayout> layoutPaper(int paperNo, List<FlnPreparedItem> items, FlnHeaderInfo h,
      {required bool shuffleAll, int extraPages = 0}) {
    final pages = <_PageBuilder>[];
    _PageBuilder newPage() {
      final pb = _PageBuilder(s, paperNo, false, pages.length + 1);
      pb.top = (pages.isEmpty ? _top + _fullHeaderHeight() : _top + _contHeaderHeight()) + 6;
      pb.bottom = _bottom - _footerHeight() - 4;
      pb.y = pb.top;
      pages.add(pb);
      return pb;
    }

    var cur = newPage();
    final twoCol = s.columns == 2;

    // Sections (or one flat list when every question number is shuffled).
    final groups = <(FlnSectionMeta?, List<FlnPreparedItem>)>[];
    if (shuffleAll) {
      groups.add((null, items));
    } else {
      for (final m in kFlnSections) {
        final secItems = items.where((it) => it.item.sec == m.sec).toList();
        if (secItems.isNotEmpty) groups.add((m, secItems));
      }
    }
    List<List<FlnPreparedItem>> rowsOf(FlnSectionMeta? meta, List<FlnPreparedItem> list) {
      final rows = <List<FlnPreparedItem>>[];
      final pairUp = twoCol && meta?.sec != 'WP';
      for (var i = 0; i < list.length;) {
        final it = list[i];
        if (pairUp && it.item.sec != 'WP' && i + 1 < list.length && list[i + 1].item.sec != 'WP') {
          rows.add(<FlnPreparedItem>[it, list[i + 1]]);
          i += 2;
        } else {
          rows.add(<FlnPreparedItem>[it]);
          i += 1;
        }
      }
      return rows;
    }

    final allRows = <List<List<FlnPreparedItem>>>[for (final g in groups) rowsOf(g.$1, g.$2)];

    /// Height of every section of the main group that starts at [gi].
    double groupHeight(int gi, int page) {
      final key = _groupKey(groups[gi].$1!.sec);
      final gap = s.gapFor(page).cardGapMm * kMm;
      var total = 0.0;
      for (var k = gi; k < groups.length && _groupKey(groups[k].$1!.sec) == key; k++) {
        total += math.max(gap, 4.0) + _banner(groups[k].$1!, groups[k].$2.length).height + 3;
        for (var r = 0; r < allRows[k].length; r++) {
          total += (r == 0 ? 0 : gap) + _cardRow(allRows[k][r], page, false).height;
        }
      }
      return total;
    }

    String? lastGroup;
    for (var gi = 0; gi < groups.length; gi++) {
      final g = groups[gi];
      final meta = g.$1;
      final rows = allRows[gi];
      if (meta != null && !shuffleAll && lastGroup != null && _groupKey(meta.sec) != lastGroup && !cur.isEmpty) {
        if (s.groupBreaks == 'on') {
          cur = newPage();
        } else if (s.groupBreaks == 'auto') {
          // Start a main group on a new page only when it does not fit in
          // the space left but fits on a fresh page (never split needlessly).
          final need = groupHeight(gi, cur.pageNo);
          final fresh = _bottom - _footerHeight() - 4 - (_top + _contHeaderHeight() + 6);
          if (cur.y + need > cur.bottom && need <= fresh) cur = newPage();
        }
      }
      if (meta != null) lastGroup = _groupKey(meta.sec);

      var placed = 0;
      while (placed < rows.length) {
        final gap = s.gapFor(cur.pageNo).cardGapMm * kMm;
        final sectionGap = cur.isEmpty ? 0.0 : math.max(gap, 4.0);
        final banner = meta == null ? null : _banner(meta, g.$2.length, continued: placed > 0);
        final bannerH = banner == null ? 0.0 : banner.height + 3;
        final rowBlocks = <_Block>[];
        var y = cur.y + sectionGap + bannerH;
        for (var r = placed; r < rows.length; r++) {
          final blk = _cardRow(rows[r], cur.pageNo, shuffleAll);
          final add = (rowBlocks.isEmpty ? 0.0 : gap) + blk.height;
          if (y + add > cur.bottom && (rowBlocks.isNotEmpty || !cur.isEmpty)) break;
          rowBlocks.add(blk);
          y += add;
        }
        if (rowBlocks.isEmpty) {
          cur = newPage();
          continue;
        }
        cur.y += sectionGap;
        if (banner != null) {
          cur.blocks.add((banner, cur.y));
          cur.y += bannerH;
        }
        for (var i = 0; i < rowBlocks.length; i++) {
          if (i > 0) cur.y += gap;
          cur.blocks.add((rowBlocks[i], cur.y));
          cur.y += rowBlocks[i].height;
        }
        placed += rowBlocks.length;
        if (placed < rows.length) cur = newPage();
      }
    }

    final total = pages.length + extraPages;
    final out = <FlnPageLayout>[];
    for (var i = 0; i < pages.length; i++) {
      final pb = pages[i];
      final page = FlnPageLayout(width: s.pageW, height: s.pageH, paperNo: paperNo, pageInPaper: i + 1, isKey: false);
      page.ops.addAll(i == 0 ? _fullHeader(paperNo, items.length, h) : _contHeader(paperNo, i + 1, total, h));
      _emitBlocks(page, pb, spread: s.spreadToFill && i < pages.length - 1);
      page.ops.addAll(_footer(paperNo, i + 1, total, h));
      page.pagesInPaper = total;
      out.add(page);
    }
    return out;
  }

  void _emitBlocks(FlnPageLayout page, _PageBuilder pb, {required bool spread}) {
    var extra = 0.0;
    if (spread && pb.blocks.length > 1) {
      var slots = 0;
      for (var i = 1; i < pb.blocks.length; i++) {
        if (!pb.blocks[i - 1].$1.isBanner) slots++;
      }
      if (slots > 0) extra = math.min((pb.bottom - pb.y) / slots, 14 * kMm);
    }
    var offset = 0.0;
    for (var i = 0; i < pb.blocks.length; i++) {
      if (i > 0 && extra > 0 && !pb.blocks[i - 1].$1.isBanner) offset += extra;
      final b = pb.blocks[i];
      page.ops.addAll(_shift(b.$1.ops, b.$2 + offset));
    }
  }

  // ------------------------------ answer key --------------------------------

  List<_Block> _keyBlocks(List<FlnPreparedItem> items) {
    final blocks = <_Block>[];
    final showLetter = s.showOptions;
    final nSt = FlnStyle(_fs * 0.82, weight: 800, color: 0xFF1E1B4B);
    final aSt = FlnStyle(_fs * 0.86, weight: 800, color: 0xFF047857);
    final qSt = FlnStyle(_fs * 0.74, weight: 400, color: 0xFF64748B);
    String ans(FlnPreparedItem p) => '${showLetter ? '(${p.correctLetter}) ' : ''}${p.item.answer}';

    if (s.keyStyle == 'table') {
      final cols = <double>[0.11, 0.13, 0.46, 0.1, 0.2];
      final xs = <double>[_left];
      for (final c in cols) {
        xs.add(xs.last + c * _contentW);
      }
      final headSt = FlnStyle(_fs * 0.8, weight: 800, color: 0xFFFFFFFF);
      final heads = <String>['પ્રશ્ન નં.', 'મૂળ ક્રમ', 'પ્રશ્ન', 'વિકલ્પ', 'સાચો જવાબ'];
      final hh = headSt.lineHeight + 4;
      blocks.add(_Block(<FlnOp>[
        FlnBoxOp(Rect.fromLTWH(_left, 0, _contentW, hh), fill: 0xFF1E293B),
        for (var i = 0; i < heads.length; i++) ..._line(heads[i], xs[i] + 3, 2, headSt, maxW: xs[i + 1] - xs[i] - 6),
      ], hh, isBanner: true));
      for (final p in items) {
        final cells = <(String, FlnStyle)>[
          ('પ્રશ્ન ${p.displayNo}', nSt),
          ('Q${p.item.qNo} (${p.item.code})', qSt),
          (p.item.questionVal, FlnStyle(_fs * 0.8, weight: 400, color: 0xFF1F2937)),
          (showLetter ? '(${p.correctLetter})' : '-', nSt),
          (p.item.answer, aSt),
        ];
        final paras = <_Para>[
          for (var i = 0; i < cells.length; i++)
            _wrap(<_Tok>[_Tok(cells[i].$1, cells[i].$2)], xs[i] + 3, xs[i + 1] - xs[i] - 6),
        ];
        final rh = paras.fold<double>(0, (m, pp) => math.max(m, pp.height)) + 4;
        blocks.add(_Block(<FlnOp>[
          FlnLineOp(Offset(_left, rh), Offset(_right, rh), color: 0xFFE2E8F0, width: 0.5),
          for (final pp in paras) ..._shift(pp.ops, 2),
        ], rh));
      }
      return blocks;
    }

    final perRow = s.keyStyle == 'grid' ? (s.landscape ? 7 : 5) : (s.landscape ? 6 : 4);
    const gap = 4.0;
    final cw = (_contentW - gap * (perRow - 1)) / perRow;
    List<_Block> grid(List<FlnPreparedItem> list) {
      final out = <_Block>[];
      for (var i = 0; i < list.length; i += perRow) {
        final row = list.skip(i).take(perRow).toList();
        final cells = <(List<FlnOp>, double)>[];
        for (var c = 0; c < row.length; c++) {
          final p = row[c];
          final x = _left + c * (cw + gap) + 3;
          final w = cw - 6;
          final head = 'પ્ર.${p.displayNo}${s.showQTag ? ' [Q${p.item.qNo}]' : ''}';
          final hw = _t.textWidth(head, nSt) + 4;
          final ops = <FlnOp>[..._line(head, x, 2, nSt)];
          final ap = _wrap(<_Tok>[_Tok(ans(p), aSt)], x + hw, w - hw);
          ops.addAll(_shift(ap.ops, 2));
          var h = 2.0 + math.max(nSt.lineHeight, ap.height);
          if (s.keyStyle == 'section') {
            ops.addAll(_line(_t.ellipsize(p.item.questionVal, qSt, w), x, h, qSt));
            h += qSt.lineHeight;
          }
          cells.add((ops, h + 2));
        }
        final rh = cells.fold<double>(0, (m, c) => math.max(m, c.$2));
        out.add(_Block(<FlnOp>[
          for (var c = 0; c < cells.length; c++)
            FlnBoxOp(Rect.fromLTWH(_left + c * (cw + gap), 0, cw, rh), fill: 0xFFF8FAFC, stroke: 0xFFCBD5E1, strokeWidth: 0.5, radius: 2),
          for (final c in cells) ...c.$1,
        ], rh));
      }
      return out;
    }

    if (s.keyStyle == 'grid') return grid(items);
    for (final m in kFlnSections) {
      final secItems = items.where((p) => p.item.sec == m.sec).toList();
      if (secItems.isEmpty) continue;
      blocks.add(_banner(m, secItems.length));
      blocks.addAll(grid(secItems));
    }
    return blocks;
  }

  /// Answer-key pages for one paper. [firstPageNo]/[pagesBefore] continue the
  /// paper's page numbering when the key follows the paper.
  List<FlnPageLayout> layoutKey(int paperNo, List<FlnPreparedItem> items, FlnHeaderInfo h, {int pagesBefore = 0}) {
    final blocks = _keyBlocks(items);
    final pages = <_PageBuilder>[];
    final titleSt = FlnStyle(_fs * 1.05, weight: 800, color: 0xFF064E3B);
    final metaSt = FlnStyle(_fs * 0.82, weight: 600, color: 0xFF334155);
    final keyHeadH = titleSt.lineHeight + metaSt.lineHeight + 10;
    _PageBuilder newPage() {
      final pb = _PageBuilder(s, paperNo, true, pages.length + 1);
      pb.top = (pages.isEmpty ? _top + keyHeadH : _top + _contHeaderHeight()) + 6;
      pb.bottom = _bottom - _footerHeight() - 4;
      pb.y = pb.top;
      pages.add(pb);
      return pb;
    }

    var cur = newPage();
    const gap = 3.0;
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final next = i + 1 < blocks.length ? blocks[i + 1].height + gap : 0.0;
      final need = (cur.isEmpty ? 0.0 : gap) + b.height + (b.isBanner ? next : 0);
      if (cur.y + need > cur.bottom && !cur.isEmpty) cur = newPage();
      if (!cur.isEmpty) cur.y += gap;
      cur.blocks.add((b, cur.y));
      cur.y += b.height;
    }

    final total = pagesBefore + pages.length;
    final out = <FlnPageLayout>[];
    for (var i = 0; i < pages.length; i++) {
      final pageNo = pagesBefore + i + 1;
      final page = FlnPageLayout(width: s.pageW, height: s.pageH, paperNo: paperNo, pageInPaper: pageNo, isKey: true);
      if (i == 0) {
        page.ops.add(FlnBoxOp(Rect.fromLTWH(_left, _top, _contentW, keyHeadH),
            fill: 0xFFECFDF5, stroke: 0xFF6EE7B7, strokeWidth: 0.8, radius: 4));
        page.ops.addAll(_line('શિક્ષક ઉત્તરવહી (Answer Key)${h.setLabel.isEmpty ? '' : ' — સેટ ${h.setLabel}'}',
            _left + 8, _top + 4, titleSt, maxW: _contentW - 16));
        final meta = <String>[
          if (h.studentName.trim().isNotEmpty) 'વિદ્યાર્થી: ${h.studentName.trim()}',
          if (h.rollNo.trim().isNotEmpty) 'રોલ નં.: ${h.rollNo.trim()}',
          if (h.classBare.isNotEmpty) 'ધોરણ/વર્ગ: ${h.classBare}',
          'કુલ પ્રશ્નો: ${flnGujDigits(items.length)}',
        ].join('   |   ');
        page.ops.addAll(_line(meta, _left + 8, _top + 6 + titleSt.lineHeight, metaSt, maxW: _contentW - 16));
      } else {
        page.ops.addAll(_contHeader(paperNo, pageNo, total, h, key: true));
      }
      _emitBlocks(page, pages[i], spread: false);
      page.ops.addAll(_footer(paperNo, pageNo, total, h));
      page.pagesInPaper = total;
      out.add(page);
    }
    return out;
  }
}

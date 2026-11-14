import 'dart:convert';
import 'dart:math' as math;

import 'print_page.dart';
import 'xlsx_model.dart';

/// Turns [PrintPage]s into one HTML document with exact page geometry. Every
/// cell is absolutely positioned (like the spreadsheet grid), borders are
/// drawn centred on grid lines, and each page is scaled onto the paper.
class TemplateHtmlRenderer {
  TemplateHtmlRenderer({this.fontRegularBase64, this.fontBoldBase64});

  final String? fontRegularBase64;
  final String? fontBoldBase64;

  String render(List<PrintPage> pages, {required String title, bool autoPrint = true}) {
    final (pw, ph) = pages.isEmpty ? (210.0, 297.0) : pages.first.paperSizeMm;
    final b = StringBuffer()
      ..write('<!DOCTYPE html><html lang="gu"><head><meta charset="utf-8">')
      ..write('<meta name="viewport" content="width=device-width, initial-scale=1">')
      ..write('<title>${_esc(title)}</title><style>');
    if (fontRegularBase64 != null) {
      b.write("@font-face{font-family:'PSMGuj';font-weight:400;src:url(data:font/ttf;base64,$fontRegularBase64) format('truetype');}");
    }
    if (fontBoldBase64 != null) {
      b.write("@font-face{font-family:'PSMGuj';font-weight:700;src:url(data:font/ttf;base64,$fontBoldBase64) format('truetype');}");
    }
    b
      ..write('@page{size:${pw}mm ${ph}mm;margin:0;}')
      ..write(_namedPages(pages))
      ..write('*{box-sizing:border-box;-webkit-print-color-adjust:exact;print-color-adjust:exact;}')
      ..write("html,body{margin:0;padding:0;background:#e9edf2;font-family:'PSMGuj','Noto Sans Gujarati',Arial,sans-serif;}")
      ..write('.pg{position:relative;overflow:hidden;background:#fff;margin:12px auto;box-shadow:0 2px 10px rgba(0,0,0,.25);}')
      ..write('.sh{position:absolute;left:0;top:0;transform-origin:0 0;}')
      ..write('.f{position:absolute;}')
      ..write('.t{position:absolute;display:flex;line-height:1.12;padding:0 2px;}')
      ..write('.t>span{display:block;}')
      ..write('.ln{position:absolute;}')
      ..write('img.im{position:absolute;}')
      ..write('@media print{html,body{background:#fff;}.pg{margin:0;box-shadow:none;break-after:page;page-break-after:always;}.pg:last-child{break-after:auto;page-break-after:auto;}}')
      ..write('</style></head><body>');
    for (final p in pages) {
      _page(b, p);
    }
    // Text that is wider (or, when wrapped, taller) than its cell is shrunk
    // to fit, then the print dialog opens.
    b.write('<script>(function(){'
        'function fit(){var els=document.querySelectorAll(".t.fit,.t.fitw");'
        'for(var i=0;i<els.length;i++){var el=els[i],sp=el.firstChild;if(!sp)continue;'
        'var fs=parseFloat(el.style.fontSize)||8;'
        'if(el.classList.contains("fit")){var w=el.clientWidth-3,sw=sp.getBoundingClientRect().width;'
        'if(sw>w&&w>0){el.style.fontSize=(fs*Math.max(0.45,w/sw)).toFixed(2)+"pt";}}'
        'else{var n=0;while(sp.scrollHeight>el.clientHeight+1&&n<10){fs*=0.9;el.style.fontSize=fs.toFixed(2)+"pt";n++;}}}}'
        'function go(){try{fit();}catch(e){}${autoPrint ? 'setTimeout(function(){window.focus();window.print();},250);' : ''}}'
        'var imgs=Array.prototype.slice.call(document.images);'
        'Promise.all([document.fonts?document.fonts.ready:Promise.resolve()].concat(imgs.map(function(i){return i.complete?Promise.resolve():new Promise(function(r){i.onload=i.onerror=r;});}))).then(go,go);})();</script>');
    b.write('</body></html>');
    return b.toString();
  }

  void _page(StringBuffer b, PrintPage p) {
    final (wMm, hMm) = p.paperSizeMm;
    final s = p.scale;
    final ml = p.marginLeftIn * 96, mt = p.marginTopIn * 96;
    final cw = p.contentWidthPx * s;
    final left = p.hCenter ? ml + (p.availWidthPx - cw) / 2 : ml;
    final top = p.vCenter ? mt + math.max(0.0, (p.availHeightPx - p.contentHeightPx * s) / 2) : mt;
    // Height a hair under the paper so rounding never spills an empty page.
    b.write('<div class="pg" style="width:${wMm}mm;height:${(hMm - 0.4).toStringAsFixed(2)}mm;page:${_pageName(wMm, hMm)}">');
    // Everything is laid out at final size (no CSS transform: print engines
    // can clip transformed blocks).
    b.write('<div class="sh" style="left:${_n(left)}px;top:${_n(top)}px;width:${_n(cw)}px;height:${_n(p.contentHeightPx * s)}px">');
    _k = s;

    final sheet = p.sheet;
    final cols = p.cols, rows = p.rows;
    final colPos = <int, int>{for (var i = 0; i < cols.length; i++) cols[i]: i};
    final rowPos = <int, int>{for (var i = 0; i < rows.length; i++) rows[i]: i};
    final xs = <double>[0];
    for (final c in cols) {
      xs.add(xs.last + p.colW(c) * s);
    }
    final ys = <double>[0];
    for (final r in rows) {
      ys.add(ys.last + p.rowH(r) * s);
    }

    // Merged blocks that touch this page, clipped to the visible rows/cols.
    final blockOf = <int, _Block>{}; // key = rowIdx * 100000 + colIdx
    final blocks = <_Block>[];
    for (final m in sheet.merges) {
      int? i1, i2, j1, j2;
      for (var i = 0; i < cols.length; i++) {
        if (cols[i] >= m.c1 && cols[i] <= m.c2) {
          i1 ??= i;
          i2 = i;
        }
      }
      if (i1 == null) continue;
      for (var j = 0; j < rows.length; j++) {
        if (rows[j] >= m.r1 && rows[j] <= m.r2) {
          j1 ??= j;
          j2 = j;
        }
      }
      if (j1 == null) continue;
      final blk = _Block(m, j1, j2!, i1, i2!);
      blocks.add(blk);
      for (var j = j1; j <= j2; j++) {
        for (var i = i1; i <= i2; i++) {
          blockOf[j * 100000 + i] = blk;
        }
      }
    }

    bool hasText(int j, int i) {
      if (i < 0 || i >= cols.length) return false;
      if (blockOf.containsKey(j * 100000 + i)) return true;
      final c = sheet.cell(rows[j], cols[i]);
      return c != null && c.text.isNotEmpty && !p.blankCols.contains(cols[i]);
    }

    // Edges: horizontal at row boundary j (0..rows) for column i; vertical at
    // column boundary i (0..cols) for row j.
    final hEdges = <int, XBorder>{};
    final vEdges = <int, XBorder>{};
    void put(Map<int, XBorder> map, int key, XBorder? e) {
      if (e == null) return;
      final cur = map[key];
      if (cur == null || e.weight > cur.weight) map[key] = e;
    }

    final fills = StringBuffer();
    final texts = StringBuffer();
    for (var j = 0; j < rows.length; j++) {
      final r = rows[j];
      final rowCells = sheet.rows[r];
      for (var i = 0; i < cols.length; i++) {
        final c = cols[i];
        if (p.blankCols.contains(c)) continue;
        final cell = rowCells?[c];
        final blk = blockOf[j * 100000 + i];
        final style = sheet.styles(cell?.style ?? 0);
        // Borders of every constituent cell (Excel stores them per cell).
        if (cell != null) {
          put(hEdges, j * 100000 + i, style.top);
          put(hEdges, (j + 1) * 100000 + i, style.bottom);
          put(vEdges, j * 100000 + i, style.left);
          put(vEdges, j * 100000 + i + 1, style.right);
        }
        if (blk != null && (blk.j1 != j || blk.i1 != i)) continue;
        // The block's content comes from the merge's top-left cell.
        final XCell? src = blk == null ? cell : sheet.cell(blk.m.r1, blk.m.c1);
        final srcStyle = sheet.styles(src?.style ?? 0);
        final x = xs[blk?.i1 ?? i], y = ys[blk?.j1 ?? j];
        final w = xs[(blk?.i2 ?? i) + 1] - x, h = ys[(blk?.j2 ?? j) + 1] - y;
        final fill = src?.fillOverride == 'none' ? null : (src?.fillOverride ?? srcStyle.fill);
        if (fill != null) {
          fills.write('<div class="f" style="left:${_n(x)}px;top:${_n(y)}px;width:${_n(w)}px;height:${_n(h)}px;background:$fill"></div>');
        }
        if (src == null || src.text.isEmpty) continue;
        _text(texts, p, src, srcStyle, r, x, y, w, h, blk == null,
            leftBusy: hasText(j, i - 1), rightBusy: hasText(j, (blk?.i2 ?? i) + 1));
      }
    }
    // No grid lines inside merged blocks.
    for (final blk in blocks) {
      for (var j = blk.j1 + 1; j <= blk.j2; j++) {
        for (var i = blk.i1; i <= blk.i2; i++) {
          hEdges.remove(j * 100000 + i);
        }
      }
      for (var j = blk.j1; j <= blk.j2; j++) {
        for (var i = blk.i1 + 1; i <= blk.i2; i++) {
          vEdges.remove(j * 100000 + i);
        }
      }
    }
    b.write(fills);
    if (p.drawSheetImages) {
      for (final im in sheet.images) {
        final ci = colPos[im.col], rj = rowPos[im.row];
        if (ci == null || rj == null) continue;
        _img(b, im.bytes, im.mime, xs[ci] + im.colOffPx * s, ys[rj] + im.rowOffPx * s, im.widthPx * s, im.heightPx * s);
      }
    }
    for (final im in p.images) {
      _img(b, im.bytes, im.mime, im.x * s, im.y * s, im.w * s, im.h * s);
    }
    _lines(b, hEdges, xs, ys, horizontal: true);
    _lines(b, vEdges, xs, ys, horizontal: false);
    b.write(texts);
    b.write('</div></div>');
  }

  static String _pageName(double w, double h) => 'p${w.round()}x${h.round()}';

  /// One named @page per paper size, so a document may mix A4 and Legal.
  static String _namedPages(List<PrintPage> pages) {
    final seen = <String>{};
    final b = StringBuffer();
    for (final p in pages) {
      final (w, h) = p.paperSizeMm;
      final name = _pageName(w, h);
      if (seen.add(name)) b.write('@page $name{size:${w}mm ${h}mm;margin:0;}');
    }
    return b.toString();
  }

  void _img(StringBuffer b, List<int> bytes, String mime, double x, double y, double w, double h) {
    b.write('<img class="im" style="left:${_n(x)}px;top:${_n(y)}px;width:${_n(w)}px;height:${_n(h)}px" src="data:$mime;base64,${base64Encode(bytes)}">');
  }

  void _lines(StringBuffer b, Map<int, XBorder> edges, List<double> xs, List<double> ys, {required bool horizontal}) {
    // Join neighbouring segments with the same style into one line.
    final keys = edges.keys.toList()..sort();
    final used = <int>{};
    var k = 0;
    while (k < keys.length) {
      final key = keys[k];
      if (used.contains(key)) {
        k++;
        continue;
      }
      final e = edges[key]!;
      final a = key ~/ 100000, bIdx = key % 100000;
      var end = horizontal ? bIdx : a;
      var next = k + 1;
      while (next < keys.length) {
        final nk = keys[next];
        final na = nk ~/ 100000, nb = nk % 100000;
        final ne = edges[nk]!;
        if (horizontal) {
          if (na != a || nb != end + 1 || ne.style != e.style || ne.color != e.color) break;
          end = nb;
        } else {
          break; // vertical keys are row-major; joined below
        }
        next++;
      }
      final (css, width) = _borderCss(e);
      if (horizontal) {
        final x1 = xs[bIdx], x2 = xs[end + 1], y = ys[a];
        b.write('<div class="ln" style="left:${_n(x1 - width / 2)}px;top:${_n(y - width / 2)}px;width:${_n(x2 - x1 + width)}px;height:0;border-top:$css"></div>');
      } else {
        // a = row index, bIdx = column boundary; extend down while the same.
        var lastRow = a;
        while (true) {
          final nk = (lastRow + 1) * 100000 + bIdx;
          final ne = edges[nk];
          if (ne == null || used.contains(nk) || ne.style != e.style || ne.color != e.color) break;
          used.add(nk);
          lastRow++;
        }
        final x = xs[bIdx], y1 = ys[a], y2 = ys[lastRow + 1];
        b.write('<div class="ln" style="left:${_n(x - width / 2)}px;top:${_n(y1 - width / 2)}px;height:${_n(y2 - y1 + width)}px;width:0;border-left:$css"></div>');
      }
      k = next;
    }
  }

  double _k = 1;

  (String, double) _borderCss(XBorder e) {
    final (css, w) = _borderCssRaw(e);
    final k = _k.clamp(0.6, 1.5);
    final scaled = w * k < 0.5 ? 0.5 : w * k;
    return (css.replaceFirst(RegExp(r'^[0-9.]+px'), '${scaled.toStringAsFixed(2)}px'), scaled);
  }

  (String, double) _borderCssRaw(XBorder e) {
    final c = e.color;
    switch (e.style) {
      case 'hair':
        return ('0.5px solid $c', 0.5);
      case 'dotted':
        return ('1px dotted $c', 1);
      case 'dashed':
      case 'dashDot':
      case 'dashDotDot':
        return ('1px dashed $c', 1);
      case 'medium':
        return ('2px solid $c', 2);
      case 'mediumDashed':
      case 'mediumDashDot':
      case 'mediumDashDotDot':
      case 'slantDashDot':
        return ('2px dashed $c', 2);
      case 'thick':
        return ('3px solid $c', 3);
      case 'double':
        return ('3px double $c', 3);
      default:
        return ('1px solid $c', 1);
    }
  }

  void _text(StringBuffer b, PrintPage p, XCell cell, XStyle st, int row, double x, double y, double w, double h, bool single,
      {required bool leftBusy, required bool rightBusy}) {
    final f = st.font;
    var size = f.size;
    if (p.fontPt != null && row >= p.fontFromRow && row <= p.fontToRow) {
      size = p.compensateFont ? p.fontPt! / p.scale : p.fontPt!;
    }
    size *= p.scale;
    var hAlign = st.horizontal;
    if (hAlign == 'general') hAlign = cell.number != null ? 'right' : 'left';
    if (hAlign == 'centerContinuous' || hAlign == 'distributed') hAlign = 'center';
    if (hAlign == 'fill' || hAlign == 'justify') hAlign = 'left';
    final justify = hAlign == 'center' ? 'center' : (hAlign == 'right' ? 'flex-end' : 'flex-start');
    final align = st.vertical == 'top' ? 'flex-start' : (st.vertical == 'center' || st.vertical == 'distributed' || st.vertical == 'justify' ? 'center' : 'flex-end');
    final rot = st.rotation;
    final vertical = rot == 90 || rot == 180 || rot == 255;
    // Text that does not wrap may run into empty neighbours (like Excel).
    var clip = st.wrap || vertical;
    if (!clip && single) {
      if (hAlign == 'left' && rightBusy) clip = true;
      if (hAlign == 'right' && leftBusy) clip = true;
      if (hAlign == 'center' && (leftBusy || rightBusy)) clip = true;
    } else if (!single && !st.wrap) {
      clip = true;
    }
    final family = _family(f.name);
    final style = StringBuffer()
      ..write('left:${_n(x)}px;top:${_n(y)}px;width:${_n(w)}px;height:${_n(h)}px;')
      ..write('justify-content:$justify;align-items:$align;')
      ..write("font-family:$family;font-size:${size.toStringAsFixed(2)}pt;")
      ..write(clip ? 'overflow:hidden;' : 'overflow:visible;');
    if (f.bold) style.write('font-weight:700;');
    if (f.italic) style.write('font-style:italic;');
    if (f.underline) style.write('text-decoration:underline;');
    if (f.color != null && f.color != '#000000') style.write('color:${f.color};');
    if (st.indent > 0 && hAlign == 'left') style.write('padding-left:${_n(2 + st.indent * 9 * p.scale)}px;');
    final span = StringBuffer();
    if (vertical) {
      final upright = rot == 255;
      span.write('writing-mode:vertical-rl;max-height:${_n(h)}px;text-align:center;');
      if (rot == 90) span.write('transform:rotate(180deg);');
      if (upright) span.write('text-orientation:upright;');
      span.write(st.wrap ? 'white-space:pre-wrap;word-break:break-word;' : 'white-space:pre;');
    } else if (rot != 0) {
      final deg = rot <= 90 ? -rot : rot - 90;
      span.write('white-space:pre;transform:rotate(${deg}deg);');
    } else {
      span.write(st.wrap ? 'white-space:pre-wrap;word-break:break-word;max-width:100%;text-align:${hAlign == 'center' ? 'center' : hAlign};' : 'white-space:pre;');
    }
    final fitClass = vertical || rot != 0 ? '' : (st.wrap ? ' fitw' : (clip ? ' fit' : ''));
    b.write('<div class="t$fitClass" style="$style"><span style="$span">${_esc(cell.text)}</span></div>');
  }

  static String _family(String name) {
    final n = name.toLowerCase();
    if (n.contains('times')) return "'Times New Roman',Tinos,'PSMGuj',serif";
    if (n.contains('arial')) return "Arial,Arimo,'PSMGuj',sans-serif";
    if (n.contains('calibri')) return "Calibri,Carlito,Arial,'PSMGuj',sans-serif";
    return "'PSMGuj','Noto Sans Gujarati',Arial,sans-serif";
  }

  static String _n(double v) => v.toStringAsFixed(2);

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

class _Block {
  _Block(this.m, this.j1, this.j2, this.i1, this.i2);
  final XMerge m;
  final int j1, j2, i1, i2;
}
